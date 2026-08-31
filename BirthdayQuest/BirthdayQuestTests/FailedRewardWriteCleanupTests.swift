import Testing
import Foundation
import UIKit
@testable import BirthdayQuest

@MainActor
private func tempFile(ext: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
    FileManager.default.createFile(atPath: url.path, contents: Data([0x00, 0x01]))
    return url
}

@MainActor
private func newGift(_ mock: MockGameBackend) async -> GiftAuthoringViewModel {
    let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
    vm.loadExisting(userId: "u1", name: "Jordan")
    for _ in 0..<8 { await Task.yield() }
    return vm
}

private enum CleanupTestError: Error { case writeRefused }

/// A reward write that fails *after* its media uploaded used to strand the objects permanently:
/// every purge path — host curation, the celebrant's expiry sweep — builds its delete list from
/// the document's own `contentUrl`/`contentUrls`, so an object no document names is unreachable
/// by anyone, forever.
@MainActor
@Suite("A reward write that fails after its media uploaded")
struct FailedRewardWriteCleanupTests {

    @Test("discards the upload it stranded, naming exactly the path it uploaded")
    func failedCreateDiscardsItsUpload() async {
        let mock = MockGameBackend()
        mock.createRewardError = CleanupTestError.writeRefused
        let vm = await newGift(mock)
        vm.contentMode = .voice
        vm.title = "A song for you"
        vm.acceptAudio(url: tempFile(ext: "m4a"), sizeBytes: 1024)

        await vm.save()

        #expect(mock.uploadedRewardMedia.count == 1, "the upload happened")
        #expect(mock.createdRewards.count == 1, "and the write was attempted and refused")
        let rewardId = mock.createdRewardIds.first ?? "<none>"
        #expect(mock.deletedRewardMediaPaths == [["events/evt_1/rewards/\(rewardId)/mock.m4a"]],
                "so exactly the stranded object is deleted")
        #expect(vm.showError, "and the contributor is still told the save failed")
    }

    /// The existing-gift half, and the multi-object case: a gallery strands one object per photo.
    @Test("discards every object a failed gallery update stranded")
    func failedUpdateDiscardsAllItsUploads() async {
        let mock = MockGameBackend()
        mock.rewards = [
            .fixture(id: "r_mine", contentType: .image,
                     contentUrls: ["events/evt_1/rewards/r_mine/old.jpg"])
        ]
        mock.updateRewardError = CleanupTestError.writeRefused
        let vm = await newGift(mock)
        vm.contentMode = .photos
        vm.title = "Us, last summer"
        vm.photoPreviews = [UIImage(systemName: "star.fill") ?? UIImage(),
                            UIImage(systemName: "star.fill") ?? UIImage()]

        await vm.save()

        #expect(mock.uploadedRewardMedia.count == 2)
        #expect(mock.deletedRewardMediaPaths.count == 1)
        #expect(mock.deletedRewardMediaPaths.first?.count == 2,
                "both new objects are discarded, not just the last one")
        #expect(mock.deletedRewardMediaPaths.first?.allSatisfy {
            $0 == "events/evt_1/rewards/r_mine/mock.jpg"
        } == true)
        #expect(!(mock.deletedRewardMediaPaths.first ?? []).contains(
            "events/evt_1/rewards/r_mine/old.jpg"
        ), "and never the path the gift still names")
    }

    /// The over-deletion guard. Without this, a compensation wired to the wrong branch would
    /// delete the media of every gift that saved successfully, and the suite above would not
    /// notice.
    @Test("a save that succeeds deletes nothing")
    func successfulSaveDiscardsNothing() async {
        let mock = MockGameBackend()
        let vm = await newGift(mock)
        vm.contentMode = .voice
        vm.title = "A song for you"
        vm.acceptAudio(url: tempFile(ext: "m4a"), sizeBytes: 1024)

        await vm.save()

        #expect(mock.uploadedRewardMedia.count == 1)
        #expect(mock.createdRewards.count == 1)
        #expect(mock.deletedRewardMediaPaths.isEmpty)
    }

    /// Covers `uploadsThisSave = []` at the top of `save()`, and it has to be shaped this way to
    /// cover it at all. The obvious version — fail, then succeed, then assert one discard — is
    /// **vacuous**: without the reset, the retry appends to attempt 1's paths and then succeeds, so
    /// nothing discards and the count is still 1. Failing *both* attempts is what separates them,
    /// because attempt 2's discard would otherwise carry attempt 1's path along with its own and
    /// delete an object that was already deleted.
    @Test("each failed attempt discards only the upload it made itself")
    func retryDiscardsOnlyItsOwnUploads() async {
        let mock = MockGameBackend()
        mock.createRewardError = CleanupTestError.writeRefused
        let vm = await newGift(mock)
        vm.contentMode = .voice
        vm.title = "A song for you"
        vm.acceptAudio(url: tempFile(ext: "m4a"), sizeBytes: 1024)

        await vm.save()
        await vm.save()

        #expect(mock.uploadedRewardMedia.count == 2, "both attempts uploaded")
        #expect(mock.deletedRewardMediaPaths.count == 2, "and both discarded")
        #expect(mock.deletedRewardMediaPaths.allSatisfy { $0.count == 1 },
                "each naming exactly one path — its own")
        // A new id is minted per attempt, so the two paths must differ. If they did not, the
        // count-of-one assertion above could hold while still naming the wrong object.
        #expect(Set(mock.deletedRewardMediaPaths.flatMap { $0 }).count == 2)
    }

    /// The complement: a retry that succeeds discards nothing further.
    @Test("a retry that succeeds adds no discard")
    func successfulRetryDiscardsNothingFurther() async {
        let mock = MockGameBackend()
        mock.createRewardError = CleanupTestError.writeRefused
        let vm = await newGift(mock)
        vm.contentMode = .voice
        vm.title = "A song for you"
        vm.acceptAudio(url: tempFile(ext: "m4a"), sizeBytes: 1024)

        await vm.save()
        mock.createRewardError = nil
        await vm.save()

        #expect(mock.createdRewards.count == 2, "the retry really did attempt the write")
        #expect(mock.deletedRewardMediaPaths.count == 1,
                "only the failed attempt discarded anything")
    }
}
