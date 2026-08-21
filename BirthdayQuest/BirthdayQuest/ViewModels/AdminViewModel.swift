import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import OSLog

// MARK: - Action Result

struct AdminActionResult: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

// MARK: - Admin View Model

@MainActor
final class AdminViewModel: ObservableObject {
    
    // MARK: - Published Data
    
    @Published var challenges: [Challenge] = []
    @Published var rewards: [Reward] = []
    @Published var participants: [Participant] = []
    @Published var actionResult: AdminActionResult?
    @Published var isPerformingAction = false
    
    // MARK: - Confirmation State
    
    @Published var challengeToComplete: Challenge?
    @Published var rewardToUnlock: Reward?
    @Published var rewardUnlockDeductsPoints = false
    @Published var showFinalBadgeConfirm = false
    
    private let service: GameBackend
    private let eventId: String
    private let challengesListenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Admin")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.challengesListenerKey = ListenerKey.scoped("admin_challenges", eventId: eventId)
    }
    
    // MARK: - Computed Filters
    
    var incompleteChallenges: [Challenge] {
        challenges.filter { !$0.isCompleted }.sorted { $0.pointValue < $1.pointValue }
    }
    
    var lockedRewards: [Reward] {
        rewards.filter { !$0.isUnlocked }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    /// Everyone in the occasion apart from the host looking at this screen.
    var otherParticipants: [Participant] {
        participants.filter { !$0.isHost }
    }
    
    // MARK: - Listener Lifecycle
    
    func startListening() {
        service.listenToChallenges(
            eventId: eventId, listenerKey: challengesListenerKey
        ) { [weak self] result in
            guard case .success(let challenges) = result else { return }
            Task { @MainActor in
                self?.challenges = challenges
            }
        }

        service.listenToRewards(eventId: eventId) { [weak self] result in
            // Shares the occasion's rewards key with the celebrant's carousel. Admin is a
            // push destination from Profile, which never shows that carousel, so the two
            // cannot be on screen at once.
            guard case .success(let rewards) = result else { return }
            Task { @MainActor in
                self?.rewards = rewards
            }
        }

        Task { await loadParticipants() }
    }
    
    func stopListening() {
        service.removeListener(forKey: challengesListenerKey)
        service.removeListener(forKey: ListenerKey.rewards(eventId))
    }

    /// The roster is a one-shot read, not a listener: participants change when someone
    /// joins, which is rare enough that a live subscription would cost more than it earns.
    private func loadParticipants() async {
        do {
            participants = try await service.fetchParticipants(eventId: eventId)
        } catch {
            logger.error("Loading the roster failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Force Complete Challenge
    
    func forceCompleteChallenge(_ challenge: Challenge) async {
        guard let challengeId = challenge.id else { return }
        isPerformingAction = true
        
        let timelineEvent = TimelineEvent(
            type: .challengeCompleted,
            referenceId: challengeId,
            title: "Completed: \(challenge.title)",
            subtitle: "+\(challenge.pointValue) ✦",
            badgeType: .challenge,
            badgeAsset: challenge.illustrationAsset,
            fromFriendName: nil,
            fromFriendAvatar: nil,
            timestamp: Date()
        )
        
        do {
            try await service.completeChallengeAtomically(
                eventId: eventId,
                challengeId: challengeId,
                pointValue: challenge.pointValue,
                isSecret: challenge.isSecret,
                proofUrl: nil,
                proofType: nil,
                proofText: nil,
                timelineEvent: timelineEvent
            )
            actionResult = AdminActionResult(
                message: "✅ Force completed \"\(challenge.title)\" (+\(challenge.pointValue)✦)",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
        
        isPerformingAction = false
    }
    
    // MARK: - Force Unlock Reward
    
    func forceUnlockReward(_ reward: Reward, deductPoints: Bool) async {
        guard let rewardId = reward.id else { return }
        isPerformingAction = true
        
        let timelineEvent = TimelineEvent(
            type: .rewardUnlocked,
            referenceId: rewardId,
            title: "Unlocked \(reward.fromName)'s gift",
            subtitle: deductPoints ? "-\(reward.pointCost) ✦" : "🎁 Free unlock",
            badgeType: .reward,
            badgeAsset: reward.badgeIllustration,
            fromFriendName: reward.fromName,
            fromFriendAvatar: nil,
            timestamp: Date()
        )
        
        do {
            try await service.adminForceUnlockReward(
                eventId: eventId,
                rewardId: rewardId,
                pointCost: reward.pointCost,
                deductPoints: deductPoints,
                timelineEvent: timelineEvent
            )
            let costLabel = deductPoints ? " (-\(reward.pointCost)✦)" : " (free)"
            actionResult = AdminActionResult(
                message: "✅ Unlocked \(reward.fromName)'s gift\(costLabel)",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
        
        isPerformingAction = false
    }
    
    // MARK: - Force Final Badge
    
    func forceFinalBadge() async {
        isPerformingAction = true
        
        do {
            try await service.updateGameState(eventId: eventId, fields: [
                "allRewardsUnlocked": true,
                "finalBadgeUnlocked": true,
                "finalBadgeUnlockedAt": Timestamp(date: Date())
            ])
            actionResult = AdminActionResult(
                message: "🎉 Final badge triggered! The big moment is here.",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
        
        isPerformingAction = false
    }
    
    // MARK: - Adjust Points

    /// Grants points and credits them to the earned total.
    func addPoints(_ amount: Int) async {
        isPerformingAction = true

        do {
            try await service.updateGameState(eventId: eventId, fields: [
                "currentPoints": FieldValue.increment(Int64(amount)),
                "totalPointsEarned": FieldValue.increment(Int64(amount))
            ])
            actionResult = AdminActionResult(
                message: "✦ Added \(amount) points.",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed to add points: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }

        isPerformingAction = false
    }

    /// Removes points from the current balance. Does not touch the earned total,
    /// so the running history of what was earned stays accurate.
    func removePoints(_ amount: Int) async {
        isPerformingAction = true

        do {
            try await service.updateGameState(eventId: eventId, fields: [
                "currentPoints": FieldValue.increment(Int64(-amount))
            ])
            actionResult = AdminActionResult(
                message: "✦ Removed \(amount) points.",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed to remove points: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }

        isPerformingAction = false
    }

    // MARK: - Advance Day

    func advanceDay(from currentDay: Int) async {
        isPerformingAction = true

        do {
            try await service.updateGameState(
                eventId: eventId, fields: ["currentDay": currentDay + 1]
            )
            actionResult = AdminActionResult(
                message: "📅 Now on day \(currentDay + 1).",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed to advance the day: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }

        isPerformingAction = false
    }

    // MARK: - Open / Close the Occasion

    /// Closing an occasion stops new joins. It is a plain host toggle, not a lifecycle
    /// state: nothing else in the app reads it as a phase.
    func setOpen(_ isOpen: Bool) async {
        isPerformingAction = true

        do {
            try await service.setOccasionOpen(eventId: eventId, isOpen: isOpen)
            actionResult = AdminActionResult(
                message: isOpen ? "🔓 Open to new joins." : "🔒 Closed to new joins.",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }

        isPerformingAction = false
    }
}
