import Testing
import Foundation
import UIKit
@testable import BirthdayQuest

/// A probe that answers from a fixed set of "gone" paths, so the expired-media carve-out can be
/// exercised without Storage. Mirrors the established seam pattern: hardware- and network-bound
/// pieces are injected, and only the *decision* is tested.
final class MockRewardMediaProbe: RewardMediaProbing, @unchecked Sendable {
    /// Paths this probe reports as confirmed-missing. Everything else answers "still there".
    var missingPaths: Set<String> = []
    private(set) var probedPaths: [String] = []

    init(missingPaths: Set<String> = []) {
        self.missingPaths = missingPaths
    }

    func isObjectMissing(path: String) async -> Bool {
        probedPaths.append(path)
        return missingPaths.contains(path)
    }
}

@MainActor
@Suite("Expired-gift re-send")
struct GiftResendTests {

    private static let occasionDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static var pastExpiry: Date {
        MediaLifecycle.expiry(occasionDate: occasionDate).addingTimeInterval(60)
    }
    private static var beforeExpiry: Date {
        MediaLifecycle.expiry(occasionDate: occasionDate).addingTimeInterval(-60)
    }

    private static let videoPath = "events/evt_1/rewards/old/clip.mov"

    /// An opened video gift belonging to "u1" — the uid every `Reward.fixture` is authored by.
    private func openedVideoGift() -> Reward {
        .fixture(id: "r_mine", contentType: .video, contentUrl: Self.videoPath, isUnlocked: true)
    }

    private func loaded(
        _ mock: MockGameBackend, _ probe: MockRewardMediaProbe
    ) async -> GiftAuthoringViewModel {
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock, mediaProbe: probe)
        vm.loadExisting(userId: "u1", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        return vm
    }

    private func tempMediaURL(ext: String = "mov") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        FileManager.default.createFile(atPath: url.path, contents: Data([0x00, 0x01]))
        return url
    }

    // MARK: Detection

    @Test("past expiry AND confirmed gone unlocks the re-send carve-out")
    func confirmedGoneUnlocksResend() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [Self.videoPath])
        let vm = await loaded(mock, probe)

        #expect(!vm.isEditable, "an opened gift is still locked for its words")
        #expect(!vm.canAttachMedia, "and locked for media until expiry is confirmed")

        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)

        #expect(vm.mediaExpired)
        #expect(vm.canAttachMedia, "the carve-out opens the media half")
        #expect(vm.isResendOnly)
        #expect(!vm.isEditable, "and leaves the words locked — that is the whole carve-out")
    }

    @Test("past expiry but the objects are still there is NOT a re-send")
    func stillPresentIsNotExpired() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [])
        let vm = await loaded(mock, probe)

        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)

        #expect(probe.probedPaths == [Self.videoPath], "the date alone is not evidence")
        #expect(!vm.mediaExpired)
        #expect(!vm.canAttachMedia, "the celebrant can still open this gift; nothing to re-send")
    }

    @Test("before expiry nothing is probed at all")
    func beforeExpiryNoProbe() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [Self.videoPath])
        let vm = await loaded(mock, probe)

        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.beforeExpiry)

        #expect(probe.probedPaths.isEmpty, "the celebrant's purge cannot have run yet")
        #expect(!vm.mediaExpired)
    }

    @Test("a letter gift is never probed and never expires")
    func letterGiftNeverExpires() async {
        let mock = MockGameBackend()
        mock.rewards = [.fixture(id: "r_mine", contentType: .text, isUnlocked: true)]
        let probe = MockRewardMediaProbe(missingPaths: [Self.videoPath])
        let vm = await loaded(mock, probe)

        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)

        #expect(probe.probedPaths.isEmpty, "a text gift owns no Storage objects")
        #expect(!vm.mediaExpired)
        #expect(vm.expiredMediaMessage == nil)
    }

    @Test("one dead photo in a gallery is enough, matching what the celebrant sees")
    func oneDeadPhotoExpiresTheGallery() async {
        let mock = MockGameBackend()
        var gallery = Reward(
            fromUserId: "u1", fromName: "Jordan", title: "Photos", teaser: "t",
            pointCost: 100, contentType: .image, contentUrl: nil,
            contentUrls: ["events/evt_1/rewards/g/a.jpg", "events/evt_1/rewards/g/b.jpg"],
            contentText: nil, isUnlocked: true, unlockedAt: nil, sortOrder: 0,
            badgeIllustration: "photo.fill", createdAt: Date(timeIntervalSince1970: 0)
        )
        gallery.id = "r_mine"
        mock.rewards = [gallery]
        let probe = MockRewardMediaProbe(missingPaths: ["events/evt_1/rewards/g/b.jpg"])
        let vm = await loaded(mock, probe)

        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)

        #expect(vm.mediaExpired, "resolve() raises .expired on the first object it cannot fetch")
    }

    // MARK: The carve-out's limits

    @Test("a re-send writes ONLY the media key — never the title, teaser or letter")
    func resendWritesOnlyMedia() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [Self.videoPath])
        let vm = await loaded(mock, probe)
        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)

        // The attacker move this guards: edit the words while the media half is open.
        vm.title = "Rewritten title"
        vm.teaser = "Rewritten teaser"
        vm.letter = "Rewritten letter"
        vm.selectedVideoURL = tempMediaURL()

        await vm.save()

        let sent = mock.updatedRewards.first?.fields ?? [:]
        #expect(mock.updatedRewards.count == 1)
        #expect(Set(sent.keys) == ["contentUrl"], "only the replacement media may be written")
        #expect(sent["contentUrl"] as? String != Self.videoPath, "a fresh object path")
        #expect(mock.createdRewards.isEmpty)
    }

    @Test("a re-send never touches a gameplay or host key, which would span two rules tiers")
    func resendStaysInOneTier() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [Self.videoPath])
        let vm = await loaded(mock, probe)
        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)
        vm.selectedVideoURL = tempMediaURL()

        await vm.save()

        // Not vacuous: without this the whole assertion holds trivially when nothing is written
        // at all, which is exactly what a reverted carve-out produces.
        #expect(mock.updatedRewards.count == 1)
        let sent = Set(mock.updatedRewards.first?.fields.keys ?? [:].keys)
        for forbidden in ["isUnlocked", "unlockedAt", "fetchedBy", "pointCost", "sortOrder"] {
            #expect(!sent.contains(forbidden), "\(forbidden) is another tier; the rules deny a mix")
        }
    }

    @Test("with no replacement picked, a re-send saves nothing")
    func resendNeedsANewSelection() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [Self.videoPath])
        let vm = await loaded(mock, probe)
        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)

        #expect(!vm.isValid, "the stored path is the dead one; it cannot stand in for a new pick")

        await vm.save()

        #expect(mock.updatedRewards.isEmpty)
        #expect(vm.showValidation)
    }

    @Test("an opened gift whose media is intact still saves nothing at all")
    func openedIntactGiftStillLocked() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [])
        let vm = await loaded(mock, probe)
        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)
        vm.title = "Rewritten"
        vm.selectedVideoURL = tempMediaURL()

        await vm.save()

        #expect(mock.updatedRewards.isEmpty, "the original lockout is untouched")
        #expect(mock.createdRewards.isEmpty)
    }

    @Test("a successful re-send closes the carve-out and re-locks the form")
    func successfulResendReLocks() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [Self.videoPath])
        let vm = await loaded(mock, probe)
        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)
        vm.selectedVideoURL = tempMediaURL()

        await vm.save()

        #expect(!vm.mediaExpired)
        #expect(!vm.canAttachMedia)
        #expect(!vm.isResendOnly)
        #expect(vm.expiredMediaMessage == nil)
    }

    @Test("re-sending a voice gift uploads audio and writes the single contentUrl")
    func resendVoiceGift() async {
        let mock = MockGameBackend()
        let audioPath = "events/evt_1/rewards/old/take.m4a"
        mock.rewards = [
            .fixture(id: "r_mine", contentType: .audio, contentUrl: audioPath, isUnlocked: true),
        ]
        let probe = MockRewardMediaProbe(missingPaths: [audioPath])
        let vm = await loaded(mock, probe)
        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)
        #expect(vm.contentMode == .voice)
        vm.acceptAudio(url: tempMediaURL(ext: "m4a"), sizeBytes: 1024)

        await vm.save()

        #expect(mock.uploadedRewardMedia.first?.contentType == "audio/mp4")
        let sent = mock.updatedRewards.first?.fields ?? [:]
        #expect(Set(sent.keys) == ["contentUrl"])
    }

    @Test("re-sending photos replaces the whole gallery and never writes an empty one")
    func resendPhotoGift() async {
        let mock = MockGameBackend()
        var gallery = Reward(
            fromUserId: "u1", fromName: "Jordan", title: "Photos", teaser: "t",
            pointCost: 100, contentType: .image, contentUrl: nil,
            contentUrls: ["events/evt_1/rewards/g/a.jpg"],
            contentText: nil, isUnlocked: true, unlockedAt: nil, sortOrder: 0,
            badgeIllustration: "photo.fill", createdAt: Date(timeIntervalSince1970: 0)
        )
        gallery.id = "r_mine"
        mock.rewards = [gallery]
        let probe = MockRewardMediaProbe(missingPaths: ["events/evt_1/rewards/g/a.jpg"])
        let vm = await loaded(mock, probe)
        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)
        #expect(vm.contentMode == .photos)

        // No new photos yet: nothing may be written, or the celebrant trades ".expired" for
        // ".unavailable" — a different dead end, not a fix.
        await vm.save()
        #expect(mock.updatedRewards.isEmpty)

        vm.photoPreviews = [Self.solidImage(), Self.solidImage()]
        await vm.save()

        let sent = mock.updatedRewards.first?.fields ?? [:]
        #expect(Set(sent.keys) == ["contentUrls"])
        #expect((sent["contentUrls"] as? [String])?.count == 2)
        #expect(mock.callCount("uploadRewardMedia") == 2)
    }

    // MARK: Copy

    @Test("the expired banner names the medium and stays silent otherwise")
    func bannerCopy() async {
        let mock = MockGameBackend()
        mock.rewards = [openedVideoGift()]
        let probe = MockRewardMediaProbe(missingPaths: [Self.videoPath])
        let vm = await loaded(mock, probe)

        #expect(vm.expiredMediaMessage == nil, "nothing to say before the carve-out opens")

        await vm.checkMediaExpiry(occasionDate: Self.occasionDate, now: Self.pastExpiry)

        #expect(vm.expiredMediaMessage?.contains("video") == true)
        #expect(vm.statusText == "Expired — send it again")
    }

    private static func solidImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
