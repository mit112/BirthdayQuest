import Foundation
import SwiftUI
import Combine
import OSLog

@MainActor
final class RewardsViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var rewards: [Reward] = []
    @Published var isLoading = true
    @Published var selectedReward: Reward?
    @Published var showUnlockConfirm = false
    @Published var showUnlockedContent = false
    @Published var isUnlocking = false
    @Published var justUnlockedReward: Reward?
    @Published var showTimelinePrompt = false

    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Rewards")

    // MARK: - Computed
    
    // NOTE: Points are read from @EnvironmentObject session in views, NOT here.
    // Using SessionManager.shared in computed properties is NOT observable by SwiftUI.
    
    // Use this ONLY for non-UI logic (e.g., one-time checks). Views must use session.currentPoints.
    var currentPointsSnapshot: Int {
        SessionManager.shared.gameState.currentPoints
    }
    
    var unlockedCount: Int {
        rewards.filter(\.isUnlocked).count
    }
    
    var totalCount: Int {
        rewards.count
    }
    
    func isAffordable(_ reward: Reward) -> Bool {
        !reward.isUnlocked && currentPointsSnapshot >= reward.pointCost
    }
    
    // MARK: - Listeners
    
    func startListening() {
        FirestoreService.shared.listenToRewards { [weak self] rewards in
            Task { @MainActor in
                guard let self else { return }
                self.rewards = rewards
                self.isLoading = false
            }
        }
    }
    
    func stopListening() {
        FirestoreService.shared.removeListener(forKey: "rewards")
    }
    
    // MARK: - Unlock Flow
    
    func requestUnlock(_ reward: Reward) {
        guard !reward.isUnlocked else { return }
        selectedReward = reward
        showUnlockConfirm = true
        BQDesign.Haptics.medium()
    }
    
    func confirmUnlock() async {
        guard let reward = selectedReward, let rewardId = reward.id else { return }
        
        isUnlocking = true
        showUnlockConfirm = false
        
        do {
            // Single atomic transaction: verify balance → spend → unlock → timeline → final badge check
            let event = TimelineEvent(
                type: .rewardUnlocked,
                referenceId: rewardId,
                title: "Unlocked: \(reward.title)",
                subtitle: "-\(reward.pointCost) ✦",
                badgeType: .reward,
                badgeAsset: reward.badgeIllustration,
                fromFriendName: reward.fromName,
                fromFriendAvatar: nil,
                timestamp: Date()
            )
            
            try await FirestoreService.shared.unlockRewardAtomically(
                rewardId: rewardId,
                pointCost: reward.pointCost,
                timelineEvent: event
            )
            
            // Show content
            justUnlockedReward = reward
            BQDesign.Haptics.success()
            
            // Brief delay then show content
            try? await Task.sleep(for: .milliseconds(800))
            showUnlockedContent = true
            
        } catch {
            logger.error("Unlock error: \(error.localizedDescription)")
            BQDesign.Haptics.heavy()
        }
        
        isUnlocking = false
    }
    
    func dismissContent() {
        showUnlockedContent = false
        justUnlockedReward = nil
        showTimelinePrompt = true
    }
}
