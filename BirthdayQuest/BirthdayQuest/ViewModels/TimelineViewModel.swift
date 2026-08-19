import Foundation
import SwiftUI
import Combine
import OSLog

/// What a timeline node resolves to when tapped.
enum TimelineNodeDetail {
    case challenge(Challenge)
    case reward(Reward)
}

@MainActor
final class TimelineViewModel: ObservableObject {

    private let service: GameBackend
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Timeline")

    init(service: GameBackend = FirestoreService.shared) {
        self.service = service
    }
    
    // MARK: - Published
    
    @Published var events: [TimelineEvent] = []
    @Published var isLoading = true
    @Published var previousEventCount = 0
    @Published var newEventIds: Set<String> = []
    @Published var finalBadgeUnlocked = false
    @Published var showFinalCelebration = false
    
    // MARK: - Computed
    
    var isEmpty: Bool { events.isEmpty }
    
    // MARK: - Listeners
    
    func startListening() {
        service.listenToTimeline { [weak self] events in
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
        service.removeListener(forKey: "timeline")
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
    
    // MARK: - Node Detail

    /// Resolves the challenge or reward a timeline node points at.
    /// Returns nil if the referenced document is gone or the fetch fails.
    func detail(for event: TimelineEvent) async -> TimelineNodeDetail? {
        do {
            switch event.type {
            case .challengeCompleted:
                if let challenge = try await service.fetchChallenge(byId: event.referenceId) {
                    return .challenge(challenge)
                }
            case .rewardUnlocked:
                if let reward = try await service.fetchReward(byId: event.referenceId) {
                    return .reward(reward)
                }
            }
            return nil
        } catch {
            logger.error("Timeline detail fetch failed: \(error.localizedDescription)")
            return nil
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
