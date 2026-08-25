import Testing
import Foundation
import FirebaseStorage
@testable import BirthdayQuest

// MARK: - FakeMediaTransfer

/// Records every `download`/`delete` call. `download` writes a tiny dummy file so cache-hit
/// logic can be exercised against a real file on disk.
final class FakeMediaTransfer: MediaTransferring, @unchecked Sendable {
    private(set) var downloadedPaths: [String] = []
    private(set) var deletedPaths: [String] = []
    /// When set, `download` throws this instead of writing the dummy file.
    var downloadErrorToThrow: Error?

    func download(path: String, to localURL: URL) async throws {
        downloadedPaths.append(path)
        if let downloadErrorToThrow {
            throw downloadErrorToThrow
        }
        try Data("dummy".utf8).write(to: localURL)
    }

    func delete(path: String) async throws {
        deletedPaths.append(path)
    }
}

// MARK: - Fixtures

private func makeReward(
    id: String = "r1",
    contentType: RewardContentType,
    contentUrl: String? = nil,
    contentUrls: [String]? = nil,
    fetchedBy: [String]? = nil
) -> Reward {
    var reward = Reward(
        fromUserId: "u1",
        fromName: "Sam",
        title: "A gift",
        teaser: "Teaser",
        pointCost: 100,
        contentType: contentType,
        contentUrl: contentUrl,
        contentUrls: contentUrls,
        contentText: nil,
        isUnlocked: true,
        unlockedAt: nil,
        sortOrder: 1,
        badgeIllustration: "heart_badge",
        createdAt: Date(timeIntervalSince1970: 0)
    )
    reward.id = id
    reward.fetchedBy = fetchedBy
    return reward
}

// MARK: - MediaStoreTests

@Suite("MediaStore")
struct MediaStoreTests {

    private func makeStore(
        transfer: FakeMediaTransfer = FakeMediaTransfer(),
        service: MockGameBackend = MockGameBackend(),
        auth: MockAuthProviding = MockAuthProviding()
    ) -> (MediaStore, URL) {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = MediaStore(
            transfer: transfer,
            service: service,
            auth: auth,
            baseDirectory: baseDirectory
        )
        return (store, baseDirectory)
    }

    @Test("cache miss downloads every image content url and returns existing local files")
    func cacheMissDownloadsAll() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(
            contentType: .image,
            contentUrls: ["events/e1/rewards/r1/a.jpg", "events/e1/rewards/r1/b.jpg"]
        )

        let urls = try await store.localURLs(for: reward, eventId: "e1")

        #expect(transfer.downloadedPaths.count == 2)
        #expect(urls.count == 2)
        for url in urls {
            #expect(url.isFileURL)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("cache hit skips download for a file already on disk")
    func cacheHitSkipsDownload() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")
        let expectedLocalFile = baseDirectory
            .appendingPathComponent("RewardMedia/e1/r1/v.mp4")
        try FileManager.default.createDirectory(
            at: expectedLocalFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preexisting".utf8).write(to: expectedLocalFile)

        _ = try await store.localURLs(for: reward, eventId: "e1")

        #expect(transfer.downloadedPaths.isEmpty)
    }

    @Test("records the fetch once for the current uid")
    func recordsFetch() async throws {
        let service = MockGameBackend()
        let auth = MockAuthProviding()
        auth.currentUid = "uid_1"
        let (store, baseDirectory) = makeStore(service: service, auth: auth)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")

        _ = try await store.localURLs(for: reward, eventId: "e1")

        #expect(service.markedRewardFetched.count == 1)
        #expect(service.markedRewardFetched[0].rewardId == "r1")
        #expect(service.markedRewardFetched[0].uid == "uid_1")
    }

    @Test("does not re-record a fetch when the uid is already in fetchedBy")
    func doesNotReRecordExistingFetch() async throws {
        let service = MockGameBackend()
        let auth = MockAuthProviding()
        auth.currentUid = "uid_1"
        let (store, baseDirectory) = makeStore(service: service, auth: auth)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(
            contentType: .video,
            contentUrl: "events/e1/rewards/r1/v.mp4",
            fetchedBy: ["uid_1"]
        )

        _ = try await store.localURLs(for: reward, eventId: "e1")

        #expect(service.markedRewardFetched.isEmpty)
    }

    @Test("a fetch-record failure is non-fatal and localURLs still returns the local files")
    func fetchRecordFailureIsNonFatal() async throws {
        let service = MockGameBackend()
        service.errorToThrow = MockGameBackend.StubbedError()
        let auth = MockAuthProviding()
        auth.currentUid = "uid_1"
        let (store, baseDirectory) = makeStore(service: service, auth: auth)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")

        let urls = try await store.localURLs(for: reward, eventId: "e1")

        #expect(urls.count == 1)
    }

    @Test("video content type resolves to a single url")
    func videoResolvesSingleUrl() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")

        let urls = try await store.localURLs(for: reward, eventId: "e1")

        #expect(urls.count == 1)
        #expect(transfer.downloadedPaths == ["events/e1/rewards/r1/v.mp4"])
    }

    @Test("text content type resolves to no urls")
    func textResolvesEmpty() async throws {
        let (store, baseDirectory) = makeStore()
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .text)

        let urls = try await store.localURLs(for: reward, eventId: "e1")

        #expect(urls.isEmpty)
    }

    @Test("a Storage objectNotFound download error translates to MediaStoreError.objectMissing")
    func downloadObjectNotFoundTranslatesToObjectMissing() async throws {
        let transfer = FakeMediaTransfer()
        transfer.downloadErrorToThrow = NSError(
            domain: StorageErrorDomain,
            code: StorageErrorCode.objectNotFound.rawValue
        )
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")

        do {
            _ = try await store.localURLs(for: reward, eventId: "e1")
            Issue.record("Expected MediaStoreError.objectMissing to be thrown")
        } catch MediaStore.MediaStoreError.objectMissing {
            // Expected.
        }
    }

    @Test("purge deletes every storage path for the reward")
    func purgeDeletesEveryPath() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(
            contentType: .image,
            contentUrls: ["events/e1/rewards/r1/a.jpg", "events/e1/rewards/r1/b.jpg"]
        )

        try await store.purge(reward: reward, eventId: "e1")

        #expect(transfer.deletedPaths == [
            "events/e1/rewards/r1/a.jpg", "events/e1/rewards/r1/b.jpg"
        ])
    }
}
