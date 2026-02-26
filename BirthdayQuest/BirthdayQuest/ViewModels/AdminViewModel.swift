import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

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
    @Published var users: [BQUser] = []
    @Published var actionResult: AdminActionResult?
    @Published var isPerformingAction = false
    
    // MARK: - Confirmation State
    
    @Published var challengeToComplete: Challenge?
    @Published var rewardToUnlock: Reward?
    @Published var rewardUnlockDeductsPoints = false
    @Published var userToUnclaim: BQUser?
    @Published var showFinalBadgeConfirm = false
    
    private let service = FirestoreService.shared
    
    // MARK: - Computed Filters
    
    var incompleteChallenges: [Challenge] {
        challenges.filter { !$0.isCompleted }.sorted { $0.pointValue < $1.pointValue }
    }
    
    var lockedRewards: [Reward] {
        rewards.filter { !$0.isUnlocked }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    /// All claimed users except the organizer (you can't unclaim yourself from here — use "Reset My Character" instead)
    var claimedUsers: [BQUser] {
        users.filter { $0.claimed && $0.id != CharacterID.organizer }
    }
    
    // MARK: - Listener Lifecycle
    
    func startListening() {
        service.listenToChallenges(listenerKey: "admin_challenges") { [weak self] challenges in
            Task { @MainActor in
                self?.challenges = challenges
            }
        }
        
        service.listenToRewards { [weak self] rewards in
            // Note: listenToRewards uses the default "rewards" key.
            // Admin opens from Profile which doesn't have its own reward listener,
            // so no collision. But if this changes, add a keyed variant.
            Task { @MainActor in
                self?.rewards = rewards
            }
        }
        
        service.listenToUsers { [weak self] users in
            Task { @MainActor in
                self?.users = users
            }
        }
    }
    
    func stopListening() {
        service.removeListener(forKey: "admin_challenges")
        // rewards + users listeners are shared keys — only remove if we own them.
        // Since admin is a push destination from Profile (which has no reward/user listeners),
        // it's safe to remove here. But leave them if the architecture changes.
        service.removeListener(forKey: "rewards")
        service.removeListener(forKey: "users")
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
            try await service.updateGameState([
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
    
    // MARK: - Unclaim Character
    
    func unclaimCharacter(_ user: BQUser) async {
        guard let userId = user.id else { return }
        isPerformingAction = true
        
        do {
            try await service.unclaimCharacter(characterId: userId)
            actionResult = AdminActionResult(
                message: "✅ Unclaimed \(user.name). They'll re-select on next open.",
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
