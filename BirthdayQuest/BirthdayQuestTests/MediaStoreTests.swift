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
    /// When set, `delete` records the attempt and then throws — a purge must survive it.
    var deleteErrorToThrow: Error?

    func download(path: String, to localURL: URL) async throws {
        downloadedPaths.append(path)
        if let downloadErrorToThrow {
            throw downloadErrorToThrow
        }
        try Data("dummy".utf8).write(to: localURL)
    }

    func delete(path: String) async throws {
        deletedPaths.append(path)
        if let deleteErrorToThrow {
            throw deleteErrorToThrow
        }
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

private func makeProofChallenge(
    id: String? = "c1",
    proofUrl: String? = "events/e1/proofs/c1/photo.jpg"
) -> Challenge {
    Challenge(
        id: id,
        title: "Do the dare",
        description: "Go on then",
        illustrationAsset: "dare",
        pointValue: 50,
        difficulty: .easy,
        category: .social,
        isSecret: false,
        createdByUserId: "u1",
        isDelivered: true,
        isCompleted: proofUrl != nil,
        completedAt: proofUrl == nil ? nil : Date(timeIntervalSince1970: 0),
        proofUrl: proofUrl,
        proofType: proofUrl == nil ? nil : "photo",
        createdAt: Date(timeIntervalSince1970: 0)
    )
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

    // MARK: - purgeExpiredArchived

    private let occasionDate = Date(timeIntervalSince1970: 0)

    private func archive(reward: Reward, at baseDirectory: URL, eventId: String, paths: [String]) throws {
        guard let rewardId = reward.id else { return }
        for path in paths {
            let localFile = baseDirectory
                .appendingPathComponent("RewardMedia", isDirectory: true)
                .appendingPathComponent(eventId, isDirectory: true)
                .appendingPathComponent(rewardId, isDirectory: true)
                .appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
            try FileManager.default.createDirectory(
                at: localFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("archived".utf8).write(to: localFile)
        }
    }

    @Test("not yet expired: purgeExpiredArchived returns 0 and deletes nothing")
    func purgeExpiredArchivedNotYetExpired() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")
        try archive(reward: reward, at: baseDirectory, eventId: "e1", paths: ["events/e1/rewards/r1/v.mp4"])
        let now = MediaLifecycle.expiry(occasionDate: occasionDate).addingTimeInterval(-1)

        let count = await store.purgeExpiredArchived(
            rewards: [reward], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("expired with the local file archived: purges and returns 1")
    func purgeExpiredArchivedDeletesArchivedReward() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")
        try archive(reward: reward, at: baseDirectory, eventId: "e1", paths: ["events/e1/rewards/r1/v.mp4"])
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredArchived(
            rewards: [reward], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 1)
        #expect(transfer.deletedPaths == ["events/e1/rewards/r1/v.mp4"])
    }

    @Test("expired but the local file is absent: does not purge (archive-before-purge)")
    func purgeExpiredArchivedSkipsUnarchivedReward() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredArchived(
            rewards: [reward], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("a text reward (no storage paths) is skipped and not counted")
    func purgeExpiredArchivedSkipsTextReward() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let textReward = makeReward(id: "r-text", contentType: .text)
        let videoReward = makeReward(id: "r-video", contentType: .video, contentUrl: "events/e1/rewards/r-video/v.mp4")
        try archive(
            reward: videoReward, at: baseDirectory, eventId: "e1", paths: ["events/e1/rewards/r-video/v.mp4"]
        )
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredArchived(
            rewards: [textReward, videoReward], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 1)
        #expect(transfer.deletedPaths == ["events/e1/rewards/r-video/v.mp4"])
    }

    @Test("running purgeExpiredArchived twice does not throw (idempotent)")
    func purgeExpiredArchivedIsIdempotent() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(contentType: .video, contentUrl: "events/e1/rewards/r1/v.mp4")
        try archive(reward: reward, at: baseDirectory, eventId: "e1", paths: ["events/e1/rewards/r1/v.mp4"])
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        _ = await store.purgeExpiredArchived(rewards: [reward], eventId: "e1", occasionDate: occasionDate, now: now)
        _ = await store.purgeExpiredArchived(rewards: [reward], eventId: "e1", occasionDate: occasionDate, now: now)

        #expect(transfer.deletedPaths.count == 2)
    }

    @Test("expired with fetchedBy set but the local file absent: does not purge (never trusts fetchedBy)")
    func purgeExpiredArchivedNeverTrustsFetchedBy() async throws {
        // The ML2 catastrophe: the flag says a device once archived this, but the file is not on
        // disk now. Trusting the flag would delete the last surviving copy. The uid is aligned with
        // the auth mock so this fails against BOTH plausible regressions — `!fetchedBy.isEmpty` and
        // `fetchedBy.contains(currentUid)`.
        let transfer = FakeMediaTransfer()
        let auth = MockAuthProviding()
        auth.currentUid = "celebrant-uid"
        let (store, baseDirectory) = makeStore(transfer: transfer, auth: auth)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(
            contentType: .video,
            contentUrl: "events/e1/rewards/r1/v.mp4",
            fetchedBy: ["celebrant-uid"]
        )
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredArchived(
            rewards: [reward], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        #expect(transfer.deletedPaths.isEmpty)
    }

    // MARK: - localURL(forPath:eventId:) — proof photos

    @Test("localURL downloads on cache miss and returns a local file url")
    func localURLDownloadsOnCacheMiss() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let url = try await store.localURL(forPath: "events/e1/proofs/c1/photo.jpg", eventId: "e1")

        #expect(transfer.downloadedPaths == ["events/e1/proofs/c1/photo.jpg"])
        #expect(url.isFileURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("localURL skips download for a file already on disk")
    func localURLSkipsDownloadOnCacheHit() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let expectedLocalFile = baseDirectory.appendingPathComponent("SharedMedia/e1/photo.jpg")
        try FileManager.default.createDirectory(
            at: expectedLocalFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preexisting".utf8).write(to: expectedLocalFile)

        _ = try await store.localURL(forPath: "events/e1/proofs/c1/photo.jpg", eventId: "e1")

        #expect(transfer.downloadedPaths.isEmpty)
    }

    @Test("localURL translates a Storage objectNotFound download error to objectMissing")
    func localURLTranslatesObjectNotFound() async throws {
        let transfer = FakeMediaTransfer()
        transfer.downloadErrorToThrow = NSError(
            domain: StorageErrorDomain,
            code: StorageErrorCode.objectNotFound.rawValue
        )
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        do {
            _ = try await store.localURL(forPath: "events/e1/proofs/c1/photo.jpg", eventId: "e1")
            Issue.record("Expected MediaStoreError.objectMissing to be thrown")
        } catch MediaStore.MediaStoreError.objectMissing {
            // Expected.
        }
    }

    @Test("expired image with only some files archived: does not purge (every path must be on disk)")
    func purgeExpiredArchivedRequiresEveryPathArchived() async throws {
        // Pins `allSatisfy`, not `contains(where:)`: a partially-archived gallery must not be purged,
        // or the un-archived images become the last-copy loss ML2 guards against.
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let reward = makeReward(
            contentType: .image,
            contentUrls: ["events/e1/rewards/r1/a.jpg", "events/e1/rewards/r1/b.jpg"]
        )
        // Only one of the two images is on disk.
        try archive(reward: reward, at: baseDirectory, eventId: "e1", paths: ["events/e1/rewards/r1/a.jpg"])
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredArchived(
            rewards: [reward], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        #expect(transfer.deletedPaths.isEmpty)
    }

    // MARK: - purgeExpiredProofs

    @Test("not yet expired: purgeExpiredProofs returns 0 and deletes nothing")
    func purgeExpiredProofsNotYetExpired() async throws {
        // The load-bearing guard. Purging early destroys evidence of a dare the celebrant may
        // not have looked at yet, and there is no second copy anywhere to restore it from.
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let now = MediaLifecycle.expiry(occasionDate: occasionDate).addingTimeInterval(-1)

        let count = await store.purgeExpiredProofs(
            challenges: [makeProofChallenge()], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("expired: purgeExpiredProofs deletes the proof object and returns 1")
    func purgeExpiredProofsDeletesExpiredProof() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredProofs(
            challenges: [makeProofChallenge()], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 1)
        #expect(transfer.deletedPaths == ["events/e1/proofs/c1/photo.jpg"])
    }

    @Test("expired and never downloaded on this device: still purges (proofs have no archive gate)")
    func purgeExpiredProofsDoesNotRequireLocalArchive() async throws {
        // Deliberately the OPPOSITE of purgeExpiredArchived. A proof is transient evidence, not a
        // keepsake, and proofs are only fetched when someone opens that one challenge — so an
        // archive-before-purge gate would spare exactly the never-opened objects the sweep exists
        // to reclaim. This test reddens if someone copies the reward rule across.
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let localFile = baseDirectory.appendingPathComponent("SharedMedia/e1/photo.jpg")
        #expect(!FileManager.default.fileExists(atPath: localFile.path))
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredProofs(
            challenges: [makeProofChallenge()], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 1)
        #expect(transfer.deletedPaths == ["events/e1/proofs/c1/photo.jpg"])
    }

    @Test("a proofUrl aimed at reward media in the same event is refused")
    func purgeExpiredProofsRefusesForeignPathInSameEvent() async throws {
        // proofUrl is member-writable (gameplay tier), and the celebrant may legitimately delete
        // BOTH proofs and reward media in their own event — so the Storage rules cannot catch
        // this. Only the path check can: without it, a contributor turns the celebrant's own
        // sweep into a weapon against another contributor's gift.
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let hostile = makeProofChallenge(proofUrl: "events/e1/rewards/r1/gift.mp4")
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredProofs(
            challenges: [hostile], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("a proofUrl aimed at another challenge's proof is refused")
    func purgeExpiredProofsRefusesOtherChallengesProof() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let hostile = makeProofChallenge(id: "c1", proofUrl: "events/e1/proofs/c2/photo.jpg")
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredProofs(
            challenges: [hostile], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("a proofUrl aimed at another event is refused")
    func purgeExpiredProofsRefusesOtherEvent() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let hostile = makeProofChallenge(proofUrl: "events/e2/proofs/c1/photo.jpg")
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredProofs(
            challenges: [hostile], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("challenges with no photo proof are skipped and not counted")
    func purgeExpiredProofsSkipsNonPhotoChallenges() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let noProof = makeProofChallenge(id: "c-none", proofUrl: nil)
        let emptyProof = makeProofChallenge(id: "c-empty", proofUrl: "")
        let noId = makeProofChallenge(id: nil, proofUrl: "events/e1/proofs/c1/photo.jpg")
        let real = makeProofChallenge()
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredProofs(
            challenges: [noProof, emptyProof, noId, real],
            eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 1)
        #expect(transfer.deletedPaths == ["events/e1/proofs/c1/photo.jpg"])
    }

    @Test("a failing delete is swallowed, does not throw, and is not counted")
    func purgeExpiredProofsIsBestEffort() async throws {
        let transfer = FakeMediaTransfer()
        transfer.deleteErrorToThrow = NSError(domain: "test", code: 1)
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        let count = await store.purgeExpiredProofs(
            challenges: [makeProofChallenge(id: "c1"), makeProofChallenge(id: "c2", proofUrl: "events/e1/proofs/c2/p.jpg")],
            eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(count == 0)
        // Both were attempted — one failure must not abandon the rest of the sweep.
        #expect(transfer.deletedPaths.count == 2)
    }

    @Test("running purgeExpiredProofs twice does not throw (idempotent)")
    func purgeExpiredProofsIsIdempotent() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let now = MediaLifecycle.expiry(occasionDate: occasionDate)

        _ = await store.purgeExpiredProofs(
            challenges: [makeProofChallenge()], eventId: "e1", occasionDate: occasionDate, now: now
        )
        _ = await store.purgeExpiredProofs(
            challenges: [makeProofChallenge()], eventId: "e1", occasionDate: occasionDate, now: now
        )

        #expect(transfer.deletedPaths.count == 2)
    }

    // MARK: purgeProof — single challenge, host moderation, NO expiry gate

    @Test("purgeProof deletes a matching proof object and reports success")
    func purgeProofDeletesMatchingProof() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        // No occasionDate/now: this path is deliberately ungated on expiry — the host deleting a
        // challenge should reclaim its proof whether the occasion has passed expiry or not.
        let deleted = await store.purgeProof(for: makeProofChallenge(), eventId: "e1")

        #expect(deleted)
        #expect(transfer.deletedPaths == ["events/e1/proofs/c1/photo.jpg"])
    }

    @Test("purgeProof refuses a proofUrl aimed at reward media in the same event")
    func purgeProofRefusesForeignPathInSameEvent() async throws {
        // The same guard as purgeExpiredProofs, and load-bearing for the same reason: proofUrl is
        // member-writable, and the host now deletes both proofs AND reward media, so only the path
        // reconstruction stops a challenge delete from taking out another contributor's gift.
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let hostile = makeProofChallenge(proofUrl: "events/e1/rewards/r1/gift.mp4")

        let deleted = await store.purgeProof(for: hostile, eventId: "e1")

        #expect(!deleted)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("purgeProof refuses a proofUrl aimed at another challenge's proof")
    func purgeProofRefusesOtherChallengesProof() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let hostile = makeProofChallenge(id: "c1", proofUrl: "events/e1/proofs/c2/photo.jpg")

        let deleted = await store.purgeProof(for: hostile, eventId: "e1")

        #expect(!deleted)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("purgeProof on a challenge with no proof is a no-op")
    func purgeProofSkipsChallengeWithoutProof() async throws {
        let transfer = FakeMediaTransfer()
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let deletedNil = await store.purgeProof(for: makeProofChallenge(proofUrl: nil), eventId: "e1")
        let deletedEmpty = await store.purgeProof(for: makeProofChallenge(proofUrl: ""), eventId: "e1")

        #expect(!deletedNil)
        #expect(!deletedEmpty)
        #expect(transfer.deletedPaths.isEmpty)
    }

    @Test("purgeProof survives a failing delete without throwing and reports failure")
    func purgeProofIsBestEffort() async throws {
        let transfer = FakeMediaTransfer()
        transfer.deleteErrorToThrow = NSError(domain: "test", code: 1)
        let (store, baseDirectory) = makeStore(transfer: transfer)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let deleted = await store.purgeProof(for: makeProofChallenge(), eventId: "e1")

        #expect(!deleted)
        #expect(transfer.deletedPaths == ["events/e1/proofs/c1/photo.jpg"])  // attempted, then failed
    }
}
