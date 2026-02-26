import Foundation
import SwiftUI
import Combine

@MainActor
final class ChallengesViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var challenges: [Challenge] = []
    @Published var secretChallenges: [Challenge] = []
    @Published var isLoading = true
    @Published var selectedChallenge: Challenge?
    @Published var showDetail = false
    @Published var showSecretPortal = false
    @Published var secretsDiscovered = false
    
    // MARK: - Computed
    
    // NOTE: Points are read from @EnvironmentObject session in views, NOT here.
    // Using SessionManager.shared in computed properties is NOT observable by SwiftUI.
    
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
    
    // MARK: - Listeners
    
    func startListening() {
        FirestoreService.shared.listenToChallenges { [weak self] challenges in
            Task { @MainActor in
                guard let self else { return }
                self.challenges = challenges
                self.secretChallenges = challenges.filter { $0.isSecret && $0.isDelivered }
                self.isLoading = false
            }
        }
    }
    
    func stopListening() {
        FirestoreService.shared.removeListener(forKey: "challenges")
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
        
        // Update game state
        Task {
            try? await FirestoreService.shared.updateGameState([
                "secretChallengesFound": deliveredSecrets.count
            ])
        }
    }
}
