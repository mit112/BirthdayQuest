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
    private let eventId: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Timeline")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
    }
    
    // MARK: - Published
    
    @Published var events: [TimelineEvent] = []
    @Published var isLoading = true
    @Published var previousEventCount = 0
    @Published var newEventIds: Set<String> = []
    @Published var finalBadgeUnlocked = false
    @Published var showFinalCelebration = false
    @Published var errorMessage: String?
    
    // MARK: - Computed
    
    var isEmpty: Bool { events.isEmpty }
    
    // MARK: - Listeners
    
    func startListening() {
        service.listenToTimeline(eventId: eventId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let events):
                    // Track new events for animation
                    let oldIds = Set(self.events.compactMap(\.id))
                    let incomingIds = Set(events.compactMap(\.id))
                    let brandNew = incomingIds.subtracting(oldIds)

                    if !oldIds.isEmpty && !brandNew.isEmpty {
                        self.newEventIds = brandNew
                    }

                    self.previousEventCount = self.events.count
                    self.events = events
                case .failure(let error):
                    self.errorMessage = "Couldn't load the timeline."
                    self.logger.error("Timeline listener: \(error.localizedDescription)")
                }
            }
        }
        // NOTE: Do NOT call listenToGameState here — EventSession owns that listener for
        // this occasion, and a second registration under the same key would replace it.
        // Final badge is checked via updateFinalBadge(from:) called by the view.
    }
    
    func stopListening() {
        service.removeListener(forKey: ListenerKey.timeline(eventId))
    }
    
    /// Called by the view when the EventSession's game state changes.
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
                if let challenge = try await service.fetchChallenge(
                    eventId: eventId, challengeId: event.referenceId
                ) {
                    return .challenge(challenge)
                }
            case .rewardUnlocked:
                if let reward = try await service.fetchReward(
                    eventId: eventId, rewardId: event.referenceId
                ) {
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
