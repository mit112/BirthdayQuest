import Foundation
import SwiftUI
import Combine

@MainActor
final class SecretChallengeViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var submissionType: SubmissionType = .photo
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
        if existingChallenge?.isDelivered == true { return "📨 Delivered — waiting on him..." }
        if hasExisting { return "📝 Draft — edit anytime" }
        return "Create your secret dare"
    }
    
    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSaving
    }
    
    // MARK: - Load
    
    func loadExisting() {
        guard let userId = SessionManager.shared.currentUser?.id else {
            isLoading = false
            return
        }
        
        FirestoreService.shared.listenToChallenges(listenerKey: "challenges_secret") { [weak self] challenges in
            Task { @MainActor in
                guard let self else { return }
                // Find this friend's secret challenge
                let mine = challenges.first {
                    $0.isSecret && $0.createdByUserId == userId
                }
                
                if let mine {
                    self.existingChallenge = mine
                    self.title = mine.title
                    self.description = mine.description
                    self.submissionType = mine.submissionType
                    self.pointValue = mine.pointValue
                }
                self.isLoading = false
            }
        }
    }
    
    func stopListening() {
        FirestoreService.shared.removeListener(forKey: "challenges_secret")
    }
    
    // MARK: - Save / Create
    
    func save() async {
        guard canSave else { return }
        guard let userId = SessionManager.shared.currentUser?.id else { return }
        
        isSaving = true
        
        do {
            if let existing = existingChallenge, let id = existing.id {
                // Update existing
                try await FirestoreService.shared.updateSecretChallenge(
                    challengeId: id,
                    data: [
                        "title": title.trimmingCharacters(in: .whitespaces),
                        "description": description.trimmingCharacters(in: .whitespaces),
                        "submissionType": submissionType.rawValue,
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
                    submissionType: submissionType,
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
                _ = try await FirestoreService.shared.createSecretChallenge(challenge)
            }
            
            saveSuccess = true
            BQDesign.Haptics.success()
            
            // Reset flag after brief display
            try? await Task.sleep(for: .milliseconds(1500))
            saveSuccess = false
            
        } catch {
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
            try await FirestoreService.shared.updateSecretChallenge(
                challengeId: id,
                data: ["isDelivered": true]
            )
            BQDesign.Haptics.success()
        } catch {
            errorMessage = "Delivery failed. Try again!"
            showError = true
        }
    }
}
