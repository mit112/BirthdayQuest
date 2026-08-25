import Foundation
import SwiftUI
import Combine
import OSLog

@MainActor
final class RewardsViewModel: ObservableObject {

    private let service: GameBackend
    private let eventId: String
    private let mediaStore: MediaStoring

    init(eventId: String, service: GameBackend = FirestoreService.shared, mediaStore: MediaStoring = MediaStore()) {
        self.eventId = eventId
        self.service = service
        self.mediaStore = mediaStore
    }
    
    // MARK: - Published
    
    @Published var rewards: [Reward] = []
    @Published var isLoading = true
    @Published var selectedReward: Reward?
    @Published var showUnlockConfirm = false
    @Published var showUnlockedContent = false
    @Published var isUnlocking = false
    @Published var justUnlockedReward: Reward?
    @Published var showTimelinePrompt = false
    @Published var errorMessage: String?
    @Published var showError = false
    /// Set when the rewards listener is refused. Kept apart from `errorMessage`, which
    /// drives the unlock alert: an alert is right for an action the user just took and
    /// wrong for a read that has been refused and will stay refused — it is dismissed once
    /// and leaves the empty state behind it.
    @Published var loadFailure: String?

    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Rewards")

    // MARK: - Computed
    
    // NOTE: Points are read from the EventSession @EnvironmentObject in views, NOT here.
    // A view model reading a session's game state is not observable by SwiftUI.
    
    var unlockedCount: Int {
        rewards.filter(\.isUnlocked).count
    }
    
    var totalCount: Int {
        rewards.count
    }

    /// The branch the carousel renders. A refused read outranks both the skeleton and the
    /// empty state, so "No gifts yet" can never stand in for "we were not allowed to look".
    var contentState: ContentState {
        if let loadFailure { return .failed(loadFailure) }
        if isLoading { return .loading }
        return rewards.isEmpty ? .empty : .ready
    }
    
    // MARK: - Media Lifecycle

    struct ExpiryReminderInfo: Equatable {
        let formattedDate: String
        let unopenedMediaCount: Int
    }

    private var lifecycleContext: (isCelebrant: Bool, occasionDate: Date?, now: Date)?
    private var didDismissReminder = false
    private var didRunLifecycle = false

    /// Pure so it is directly unit-testable. Non-nil iff the celebrant is within the reminder
    /// window before media expiry and at least one non-text reward is still unopened.
    static func makeExpiryReminder(
        isCelebrant: Bool,
        occasionDate: Date?,
        rewards: [Reward],
        now: Date
    ) -> ExpiryReminderInfo? {
        guard isCelebrant, let occasionDate else { return nil }
        guard MediaLifecycle.isWithinReminderWindow(occasionDate: occasionDate, now: now) else { return nil }

        let unopened = rewards.filter { $0.contentType != .text && !$0.isUnlocked }
        guard !unopened.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return ExpiryReminderInfo(
            formattedDate: formatter.string(from: MediaLifecycle.expiry(occasionDate: occasionDate)),
            unopenedMediaCount: unopened.count
        )
    }

    /// Recomputes from live `rewards` so unlocking a gift updates the count without a new trigger.
    var expiryReminder: ExpiryReminderInfo? {
        guard !didDismissReminder, let ctx = lifecycleContext else { return nil }
        return Self.makeExpiryReminder(
            isCelebrant: ctx.isCelebrant,
            occasionDate: ctx.occasionDate,
            rewards: rewards,
            now: ctx.now
        )
    }

    func dismissExpiryReminder() {
        didDismissReminder = true
        objectWillChange.send()
    }

    /// One-shot: safe to call repeatedly (e.g. from an `.onChange` gated on a delivered snapshot).
    func runMediaLifecycle(isCelebrant: Bool, occasionDate: Date?, now: Date = Date()) {
        guard !didRunLifecycle else { return }
        didRunLifecycle = true
        lifecycleContext = (isCelebrant, occasionDate, now)
        guard isCelebrant, let occasionDate else { return }
        Task { [mediaStore, eventId, rewards] in
            _ = await mediaStore.purgeExpiredArchived(rewards: rewards, eventId: eventId, occasionDate: occasionDate, now: now)
        }
    }

    // MARK: - Listeners

    func startListening() {
        service.listenToRewards(eventId: eventId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let rewards):
                    self.rewards = rewards
                    self.loadFailure = nil
                case .failure(let error):
                    self.logger.error("Rewards listener: \(error.localizedDescription)")
                    self.loadFailure = """
                        Your gifts didn't load. You may no longer have access to this \
                        occasion, or the connection dropped.
                        """
                }
            }
        }
    }
    
    func stopListening() {
        service.removeListener(forKey: ListenerKey.rewards(eventId))
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
                title: reward.title,
                subtitle: "-\(reward.pointCost) ✦",
                badgeType: .reward,
                badgeAsset: reward.badgeIllustration,
                fromFriendName: reward.fromName,
                fromFriendAvatar: nil,
                timestamp: Date()
            )
            
            try await service.unlockRewardAtomically(
                eventId: eventId,
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
            errorMessage = "Couldn't unlock that gift. Your points are safe — try again."
            showError = true
            BQDesign.Haptics.error()
        }
        
        isUnlocking = false
    }
    
    func dismissContent() {
        showUnlockedContent = false
        justUnlockedReward = nil
        showTimelinePrompt = true
    }
}
