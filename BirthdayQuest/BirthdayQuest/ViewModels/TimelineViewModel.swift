import Foundation
import SwiftUI
import Combine

@MainActor
final class TimelineViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var events: [TimelineEvent] = []
    @Published var isLoading = true
    @Published var previousEventCount = 0
    @Published var newEventIds: Set<String> = []
    @Published var finalBadgeUnlocked = false
    @Published var showFinalCelebration = false
    
    // MARK: - Computed
    
    var isEmpty: Bool { events.isEmpty }
    
    var gameState: GameState {
        SessionManager.shared.gameState
    }
    
    var rewardProgress: String {
        "\(gameState.rewardsUnlocked)/\(gameState.totalRewards) gifts unlocked"
    }
    
    /// 0...1 fraction of rewards unlocked (drives Final Badge progressive glow)
    var progressFraction: Double {
        guard gameState.totalRewards > 0 else { return 0 }
        return Double(gameState.rewardsUnlocked) / Double(gameState.totalRewards)
    }
    
    // MARK: - Listeners
    
    func startListening() {
        FirestoreService.shared.listenToTimeline { [weak self] events in
            Task { @MainActor in
                guard let self else { return }
                
                // Track new events for animation
                let oldIds = Set(self.events.compactMap(\.id))
                let incomingIds = Set(events.compactMap(\.id))
                let brandNew = incomingIds.subtracting(oldIds)
                
                if !oldIds.isEmpty && !brandNew.isEmpty {
                    self.newEventIds = brandNew
                }
                
                self.previousEventCount = self.events.count
                self.events = events
                self.isLoading = false
            }
        }
        // NOTE: Do NOT call listenToGameState here — it hijacks SessionManager's
        // listener (same key "gameState") and breaks points updates everywhere.
        // Final badge is checked via updateFinalBadge(from:) called by the view.
    }
    
    func stopListening() {
        FirestoreService.shared.removeListener(forKey: "timeline")
    }
    
    /// Called by the view when session.gameState changes (via @EnvironmentObject)
    func updateFinalBadge(from gameState: GameState) {
        if gameState.finalBadgeUnlocked && !finalBadgeUnlocked {
            finalBadgeUnlocked = true
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                showFinalCelebration = true
            }
        }
    }
    
    func isNewEvent(_ event: TimelineEvent) -> Bool {
        guard let id = event.id else { return false }
        return newEventIds.contains(id)
    }
    
    func clearNewFlags() {
        newEventIds.removeAll()
    }
}
