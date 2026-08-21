import Foundation
import SwiftUI
import Combine
import OSLog

@MainActor
final class SecretChallengeViewModel: ObservableObject {

    private let service: GameBackend
    private let eventId: String
    private let listenerKey: String
    /// The author's participant id, handed in by the view from `EventSession`. Held so
    /// `save()` can stamp authorship without reaching back into the session.
    private var userId: String?
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "SecretChallenge")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.scoped("challenges_secret", eventId: eventId)
    }
    
    // MARK: - Published
    
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var pointValue: Int = 50
    @Published var existingChallenge: Challenge?
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var saveSuccess = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    // MARK: - Options
    
    let pointOptions = [25, 50, 75, 100]
    
    // MARK: - Computed
    
    var hasExisting: Bool { existingChallenge != nil }
    var isEditable: Bool { !(existingChallenge?.isDelivered ?? false) }
    var isCompleted: Bool { existingChallenge?.isCompleted ?? false }
    
    var statusText: String {
        if isCompleted { return "✅ Completed!" }
        if existingChallenge?.isDelivered == true { return "📨 Delivered — waiting on them..." }
        if hasExisting { return "📝 Draft — edit anytime" }
        return "Create your secret dare"
    }
    
    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSaving
    }
    
    // MARK: - Load
    
    func loadExisting(userId: String?) {
        self.userId = userId
        guard let userId else {
            isLoading = false
            return
        }
        
        service.listenToChallenges(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let challenges):
                    // Find this friend's secret challenge
                    let mine = challenges.first {
                        $0.isSecret && $0.createdByUserId == userId
                    }

                    if let mine {
                        self.existingChallenge = mine
                        self.title = mine.title
                        self.description = mine.description
                        self.pointValue = mine.pointValue
                    }
                case .failure(let error):
                    self.errorMessage = "Couldn't load your dare."
                    self.logger.error("Secret challenge listener: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func stopListening() {
        service.removeListener(forKey: listenerKey)
    }
    
    // MARK: - Save / Create
    
    func save() async {
        guard canSave else { return }
        guard let userId else { return }
        
        isSaving = true
        
        do {
            if let existing = existingChallenge, let id = existing.id {
                // Update existing
                try await service.updateSecretChallenge(
                    eventId: eventId,
                    challengeId: id,
                    data: [
                        "title": title.trimmingCharacters(in: .whitespaces),
                        "description": description.trimmingCharacters(in: .whitespaces),
                        "pointValue": pointValue
                    ]
                )
            } else {
                // Create new
                let challenge = Challenge(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    illustrationAsset: "secret_mission",
                    pointValue: pointValue,
                    difficulty: .medium,
                    category: .social,
                    isSecret: true,
                    createdByUserId: userId,
                    isDelivered: false,
                    isCompleted: false,
                    completedAt: nil,
                    proofUrl: nil,
                    proofType: nil,
                    proofText: nil,
                    createdAt: Date()
                )
                _ = try await service.createSecretChallenge(eventId: eventId, challenge: challenge)
            }
            
            saveSuccess = true
            BQDesign.Haptics.success()
            
            // Reset flag after brief display
            try? await Task.sleep(for: .milliseconds(1500))
            saveSuccess = false
            
        } catch {
            logger.error("Saving the secret dare failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save your dare. Try again!"
            showError = true
            BQDesign.Haptics.heavy()
        }
        
        isSaving = false
    }
    
    // MARK: - Deliver
    
    func deliver() async {
        guard let id = existingChallenge?.id else { return }
        
        do {
            try await service.updateSecretChallenge(
                eventId: eventId,
                challengeId: id,
                data: ["isDelivered": true]
            )
            BQDesign.Haptics.success()
        } catch {
            logger.error("Delivering the secret dare failed: \(error.localizedDescription)")
            errorMessage = "Delivery failed. Try again!"
            showError = true
        }
    }
}
