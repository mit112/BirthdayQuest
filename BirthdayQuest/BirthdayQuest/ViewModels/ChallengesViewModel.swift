import Foundation
import SwiftUI
import Combine
import OSLog

@MainActor
final class ChallengesViewModel: ObservableObject {

    private let service: GameBackend
    private let eventId: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Challenges")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
    }

    // MARK: - Published

    @Published var challenges: [Challenge] = []
    @Published var secretChallenges: [Challenge] = []
    @Published var isLoading = true
    @Published var selectedChallenge: Challenge?
    @Published var showDetail = false
    @Published var showSecretPortal = false
    @Published var secretsDiscovered = false
    /// Set when the challenges listener is refused. Rendered inline in place of the empty
    /// state, not as an alert: membership is revocable, so this is a persistent condition
    /// and an alert would be dismissed straight back onto "No challenges yet".
    @Published var loadFailure: String?
    
    // MARK: - Computed
    
    // NOTE: Points are read from @EnvironmentObject session in views, NOT here.
    // A view model reading a session's game state is not observable by SwiftUI.
    
    var regularChallenges: [Challenge] {
        challenges.filter { !$0.isSecret }
    }
    
    var completedCount: Int {
        regularChallenges.filter(\.isCompleted).count
    }   
    
    var totalRegular: Int {
        regularChallenges.count
    }
    
    var deliveredSecrets: [Challenge] {
        challenges.filter { $0.isSecret && $0.isDelivered }
    }
    
    var hasSecrets: Bool {
        !deliveredSecrets.isEmpty
    }

    /// The branch the board renders. A refused read outranks the empty state so an occasion
    /// with 13 challenges in it never reads as "The adventure is being prepared...".
    var contentState: ContentState {
        if let loadFailure { return .failed(loadFailure) }
        if isLoading { return .loading }
        return regularChallenges.isEmpty ? .empty : .ready
    }
    
    // MARK: - Listeners
    
    func startListening() {
        service.listenToChallenges(eventId: eventId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let challenges):
                    self.challenges = challenges
                    self.secretChallenges = challenges.filter { $0.isSecret && $0.isDelivered }
                    self.loadFailure = nil
                case .failure(let error):
                    self.logger.error("Challenges listener: \(error.localizedDescription)")
                    self.loadFailure = """
                        The challenges didn't load. You may no longer have access to this \
                        occasion, or the connection dropped.
                        """
                }
            }
        }
    }
    
    func stopListening() {
        service.removeListener(forKey: ListenerKey.challenges(eventId))
    }
    
    // MARK: - Actions
    
    func selectChallenge(_ challenge: Challenge) {
        selectedChallenge = challenge
        showDetail = true
        BQDesign.Haptics.light()
    }
    
    func discoverSecrets() {
        guard hasSecrets else { return }
        secretsDiscovered = true
        showSecretPortal = true
        BQDesign.Haptics.heavy()

        // Update game state — absolute set from current listener snapshot
        Task {
            try? await service.updateGameState(
                eventId: eventId,
                fields: ["secretChallengesFound": deliveredSecrets.count]
            )
        }
    }
}
