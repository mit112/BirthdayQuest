import Testing
import Foundation
@testable import BirthdayQuest

// No view model calls uploadRewardMedia/deleteRewardMedia yet — that lands in a later task
// (media gift authoring). Until then this is a direct check that the mock's stubs record
// their calls the same way every other MockGameBackend method does.
@Suite("MockGameBackend reward media stubs")
struct RewardMediaBackendTests {

    @Test("upload records the reward id and content type, and returns a deterministic path")
    func uploadRecordsArgsAndReturnsPath() async throws {
        let mock = MockGameBackend()

        let path = try await mock.uploadRewardMedia(
            eventId: "evt_1", rewardId: "r1", data: Data([0xFF]), contentType: "image/jpeg"
        )

        #expect(path == "events/evt_1/rewards/r1/mock.jpg")
        #expect(mock.uploadedRewardMedia.count == 1)
        #expect(mock.uploadedRewardMedia[0].rewardId == "r1")
        #expect(mock.uploadedRewardMedia[0].contentType == "image/jpeg")
        #expect(mock.requestedEventIds == ["evt_1"])
    }

    @Test("delete records the storage paths it was asked to remove")
    func deleteRecordsPaths() async throws {
        let mock = MockGameBackend()
        let paths = ["events/evt_1/rewards/r1/a.jpg", "events/evt_1/rewards/r1/b.jpg"]

        try await mock.deleteRewardMedia(eventId: "evt_1", storagePaths: paths)

        #expect(mock.deletedRewardMediaPaths == [paths])
    }

    @Test("uploadProofData records the call and returns a deterministic path, never a URL")
    func uploadProofDataReturnsPath() async throws {
        let mock = MockGameBackend()

        let path = try await mock.uploadProofData(
            eventId: "evt_1", challengeId: "c1", data: Data([0xFF]), contentType: "image/jpeg"
        )

        #expect(path == "events/evt_1/proofs/c1/mock.jpg")
        #expect(mock.uploadedContentTypes == ["image/jpeg"])
        #expect(mock.requestedEventIds == ["evt_1"])
    }
}
