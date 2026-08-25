import Testing
import Foundation
@testable import BirthdayQuest

// MARK: - Fixtures

private func reward(
    id: String = "r1",
    contentType: RewardContentType,
    isUnlocked: Bool
) -> Reward {
    var reward = Reward(
        fromUserId: "u1",
        fromName: "Sam",
        title: "A gift",
        teaser: "Teaser",
        pointCost: 100,
        contentType: contentType,
        contentUrl: contentType == .text ? nil : "events/e1/rewards/\(id)/f",
        contentUrls: nil,
        contentText: contentType == .text ? "Happy birthday" : nil,
        isUnlocked: isUnlocked,
        unlockedAt: nil,
        sortOrder: 1,
        badgeIllustration: "heart_badge",
        createdAt: Date(timeIntervalSince1970: 0)
    )
    reward.id = id
    return reward
}

// MARK: - SpyMediaStoring

/// Records `purgeExpiredArchived` calls; the other two methods are unused by these tests.
private final class SpyMediaStoring: MediaStoring, @unchecked Sendable {
    private(set) var purgeExpiredArchivedCallCount = 0

    func localURLs(for reward: Reward, eventId: String) async throws -> [URL] { [] }
    func purge(reward: Reward, eventId: String) async throws {}

    func purgeExpiredArchived(rewards: [Reward], eventId: String, occasionDate: Date, now: Date) async -> Int {
        purgeExpiredArchivedCallCount += 1
        return 0
    }
}

// MARK: - RewardsViewModelLifecycleTests

@Suite("RewardsViewModel media lifecycle")
@MainActor
struct RewardsViewModelLifecycleTests {

    private let occasionDate = Date(timeIntervalSince1970: 0)

    // MARK: makeExpiryReminder — pure matrix

    @Test("not celebrant: no reminder")
    func notCelebrantIsNil() {
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)
        let info = RewardsViewModel.makeExpiryReminder(
            isCelebrant: false,
            occasionDate: occasionDate,
            rewards: [reward(contentType: .video, isUnlocked: false)],
            now: now
        )
        #expect(info == nil)
    }

    @Test("nil occasionDate: no reminder")
    func nilOccasionDateIsNil() {
        let info = RewardsViewModel.makeExpiryReminder(
            isCelebrant: true,
            occasionDate: nil,
            rewards: [reward(contentType: .video, isUnlocked: false)],
            now: Date()
        )
        #expect(info == nil)
    }

    @Test("outside the reminder window: no reminder")
    func outsideWindowIsNil() {
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)
            .addingTimeInterval(-MediaLifecycle.reminderWindow - 1)
        let info = RewardsViewModel.makeExpiryReminder(
            isCelebrant: true,
            occasionDate: occasionDate,
            rewards: [reward(contentType: .video, isUnlocked: false)],
            now: now
        )
        #expect(info == nil)
    }

    @Test("in window but no unopened media: no reminder")
    func inWindowNoUnopenedMediaIsNil() {
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)
        let info = RewardsViewModel.makeExpiryReminder(
            isCelebrant: true,
            occasionDate: occasionDate,
            rewards: [
                reward(id: "r1", contentType: .video, isUnlocked: true),
                reward(id: "r2", contentType: .text, isUnlocked: false)
            ],
            now: now
        )
        #expect(info == nil)
    }

    @Test("in window with unopened media: reminder with correct count")
    func inWindowWithUnopenedMediaIsNonNil() {
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)
        let info = RewardsViewModel.makeExpiryReminder(
            isCelebrant: true,
            occasionDate: occasionDate,
            rewards: [
                reward(id: "r1", contentType: .video, isUnlocked: false),
                reward(id: "r2", contentType: .audio, isUnlocked: false),
                reward(id: "r3", contentType: .text, isUnlocked: false),
                reward(id: "r4", contentType: .image, isUnlocked: true)
            ],
            now: now
        )
        #expect(info != nil)
        #expect(info?.unopenedMediaCount == 2)
    }

    // MARK: runMediaLifecycle — one-shot purge trigger

    @Test("celebrant: runMediaLifecycle triggers a purge sweep")
    func celebrantTriggersPurge() async {
        let mediaStore = SpyMediaStoring()
        let viewModel = RewardsViewModel(eventId: "e1", service: MockGameBackend(), mediaStore: mediaStore)

        viewModel.runMediaLifecycle(isCelebrant: true, occasionDate: occasionDate)
        await Task.yield()
        await Task.yield()

        #expect(mediaStore.purgeExpiredArchivedCallCount == 1)
    }

    @Test("non-celebrant: runMediaLifecycle does not trigger a purge sweep")
    func nonCelebrantDoesNotTriggerPurge() async {
        let mediaStore = SpyMediaStoring()
        let viewModel = RewardsViewModel(eventId: "e1", service: MockGameBackend(), mediaStore: mediaStore)

        viewModel.runMediaLifecycle(isCelebrant: false, occasionDate: occasionDate)
        await Task.yield()
        await Task.yield()

        #expect(mediaStore.purgeExpiredArchivedCallCount == 0)
    }

    @Test("a second runMediaLifecycle call does not re-run (one-shot)")
    func secondCallDoesNotRerun() async {
        let mediaStore = SpyMediaStoring()
        let viewModel = RewardsViewModel(eventId: "e1", service: MockGameBackend(), mediaStore: mediaStore)

        viewModel.runMediaLifecycle(isCelebrant: true, occasionDate: occasionDate)
        await Task.yield()
        await Task.yield()
        viewModel.runMediaLifecycle(isCelebrant: true, occasionDate: occasionDate)
        await Task.yield()
        await Task.yield()

        #expect(mediaStore.purgeExpiredArchivedCallCount == 1)
    }
}
