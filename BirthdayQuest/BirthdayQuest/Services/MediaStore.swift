import Foundation
import FirebaseStorage
import OSLog

// MARK: - MediaTransferring

/// Transfers a single Storage object. Production wraps FirebaseStorage; tests use a fake.
protocol MediaTransferring: Sendable {
    /// Download the object at `path` to `localURL` (parent dirs already created).
    func download(path: String, to localURL: URL) async throws
    /// Delete the object at `path`. Idempotent: an already-absent object is success.
    func delete(path: String) async throws
}

// MARK: - FirebaseMediaTransfer

struct FirebaseMediaTransfer: MediaTransferring {
    func download(path: String, to localURL: URL) async throws {
        _ = try await Storage.storage().reference(withPath: path).writeAsync(toFile: localURL)
    }

    func delete(path: String) async throws {
        do {
            try await Storage.storage().reference(withPath: path).delete()
        } catch let error as NSError where error.code == StorageErrorCode.objectNotFound.rawValue {
            // Already absent — idempotent success.
        }
    }
}

// MARK: - MediaStoring

protocol MediaStoring: Sendable {
    /// Local file URLs for a reward's media, downloading+persisting on first access, then
    /// recording the fetch. Image → one URL per `contentUrls` entry; video/audio → single-element
    /// array; text → empty. Order preserved.
    func localURLs(for reward: Reward, eventId: String) async throws -> [URL]
    /// Delete the remote objects for this reward. Called by the celebrant flow after a successful
    /// fetch (celebrant-only by the Storage rules). Idempotent.
    func purge(reward: Reward, eventId: String) async throws
    /// Celebrant-only. For each reward whose media this device already holds locally AND whose occasion
    /// is past media expiry, delete the remote Storage objects (idempotent, best-effort). Never deletes
    /// an object this device has not archived. Returns the number of rewards whose media was purged.
    func purgeExpiredArchived(rewards: [Reward], eventId: String, occasionDate: Date, now: Date) async -> Int
}

// MARK: - ProofMediaLoading

protocol ProofMediaLoading: Sendable {
    /// Local file URL for a single Storage object path (e.g. a challenge proof photo),
    /// downloading+persisting on first access. No fetch-recording — proofs are not rewards, so
    /// there is no `fetchedBy` to maintain (see `ProofMediaPurging` for why).
    func localURL(forPath path: String, eventId: String) async throws -> URL
}

// MARK: - ProofMediaPurging

/// Deliberately separate from `ProofMediaLoading`: loading is a *View* dependency
/// (`ProofImageView`), purging is a *ViewModel* dependency (`ChallengesViewModel`). Keeping them
/// apart means neither seam has to stub the other's method.
protocol ProofMediaPurging: Sendable {
    /// Celebrant-only. Delete the remote proof objects for every challenge whose occasion is past
    /// media expiry. Idempotent and best-effort. Returns the number of objects actually deleted.
    func purgeExpiredProofs(challenges: [Challenge], eventId: String, occasionDate: Date, now: Date) async -> Int
}

// MARK: - MediaStore

/// Downloads a reward's media through an authenticated Storage reference and persists it to
/// Documents, so playback never depends on a live network connection. `contentUrl`/`contentUrls`
/// are Storage object paths, never download URLs (D1 / Ruling P2) — this type resolves them
/// through `MediaTransferring`, it never constructs a remote URL from them.
actor MediaStore: MediaStoring, ProofMediaLoading, ProofMediaPurging {

    private let transfer: MediaTransferring
    private let service: GameBackend
    private let auth: AuthProviding
    private let baseDirectory: URL
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "MediaStore")

    init(
        transfer: MediaTransferring = FirebaseMediaTransfer(),
        service: GameBackend = FirestoreService.shared,
        auth: AuthProviding = AuthService.shared,
        baseDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) {
        self.transfer = transfer
        self.service = service
        self.auth = auth
        self.baseDirectory = baseDirectory
    }

    enum MediaStoreError: LocalizedError {
        case missingRewardId
        /// The Storage object this reward points to is gone — purged or never fully uploaded.
        /// Distinct from a generic failure so the celebrant sees an honest "expired" state
        /// rather than the "never authored" one.
        case objectMissing

        var errorDescription: String? {
            switch self {
            case .missingRewardId: return "This reward has no id yet."
            case .objectMissing: return "This gift's media is no longer available."
            }
        }
    }

    func localURLs(for reward: Reward, eventId: String) async throws -> [URL] {
        let paths = storagePaths(for: reward)
        guard !paths.isEmpty else { return [] }
        guard let rewardId = reward.id else { throw MediaStoreError.missingRewardId }

        var localURLs: [URL] = []
        for path in paths {
            let localFile = localFileURL(eventId: eventId, rewardId: rewardId, path: path)
            try FileManager.default.createDirectory(
                at: localFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: localFile.path) {
                do {
                    try await transfer.download(path: path, to: localFile)
                } catch let error as NSError where error.code == StorageErrorCode.objectNotFound.rawValue {
                    throw MediaStoreError.objectMissing
                }
            }
            localURLs.append(localFile)
        }

        await recordFetchIfNeeded(reward: reward, eventId: eventId, rewardId: rewardId)

        return localURLs
    }

    /// Deletes the remote Storage objects for this reward's media, once the celebrant's device
    /// already holds them locally — "server as courier, device as archive."
    ///
    /// **Deferred to a later slice (media lifecycle).** It intentionally has no production caller
    /// yet in Slice 1: the leak this closes is already bounded by storing Storage *paths* (never
    /// download URLs) behind an authenticated reference, so purge exists only to bound storage
    /// cost, not to close a security gap. Wiring it correctly needs the "expired after purge"
    /// state the media-lifecycle slice adds, so a reward isn't left pointing at deleted objects.
    ///
    /// When wired, this must be called **only on the celebrant's device** — the Storage rules
    /// grant reward-media delete to celebrant-or-host only, so calling it as an ordinary member
    /// throws.
    func purge(reward: Reward, eventId: String) async throws {
        for path in storagePaths(for: reward) {
            try await transfer.delete(path: path)
        }
    }

    /// Sweeps every reward whose media this device has already archived once the occasion is past
    /// media expiry. "Archive-before-purge": eligibility is decided by checking the local file
    /// exists on disk right now, never by trusting `fetchedBy`, so a reward can only be purged once
    /// this device actually holds a copy.
    func purgeExpiredArchived(rewards: [Reward], eventId: String, occasionDate: Date, now: Date) async -> Int {
        guard MediaLifecycle.isExpired(occasionDate: occasionDate, now: now) else { return 0 }

        var purgedCount = 0
        for reward in rewards {
            let paths = storagePaths(for: reward)
            guard !paths.isEmpty else { continue }
            guard let rewardId = reward.id else { continue }

            let localFiles = paths.map { localFileURL(eventId: eventId, rewardId: rewardId, path: $0) }
            let isArchived = localFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
            guard isArchived else { continue }

            for path in paths {
                do {
                    try await transfer.delete(path: path)
                } catch {
                    logger.error("purgeExpiredArchived delete failed for \(path): \(error.localizedDescription)")
                }
            }
            purgedCount += 1
        }
        return purgedCount
    }

    /// Resolves a single Storage object path (e.g. a challenge proof photo) to a local file URL,
    /// downloading+persisting on first access. Unlike `localURLs(for:eventId:)`, this has no
    /// reward to key its cache dir by and no `fetchedBy` to record — proofs are not rewards.
    func localURL(forPath path: String, eventId: String) async throws -> URL {
        let localFile = sharedFileURL(eventId: eventId, path: path)
        try FileManager.default.createDirectory(
            at: localFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: localFile.path) {
            do {
                try await transfer.download(path: path, to: localFile)
            } catch let error as NSError where error.code == StorageErrorCode.objectNotFound.rawValue {
                throw MediaStoreError.objectMissing
            }
        }
        return localFile
    }

    /// Sweeps every challenge's proof photo off the server once the occasion is past
    /// `MediaLifecycle` expiry. Celebrant-only: `storage.rules` grants proof *delete* to the
    /// celebrant alone (`request.resource == null ? isCelebrant(eventId) : ...`), so no rules
    /// change was needed to wire this — and calling it as an ordinary member simply fails every
    /// delete, which this method swallows.
    ///
    /// **There is deliberately no archive-before-purge gate here, unlike `purgeExpiredArchived`.**
    /// That gate exists for rewards because a gift is an irreplaceable keepsake and the server
    /// copy may be the only one. A proof photo is transient evidence that a dare was done, and
    /// everything durable about it — `isCompleted`, `completedAt`, `proofType`, `proofText`, the
    /// points awarded and the timeline entry — lives in Firestore and is untouched by this sweep.
    /// Copying the reward rule would also invert the intent: proofs are only downloaded when
    /// someone opens that one challenge's detail, so the great majority are never archived on the
    /// celebrant's device, and "purge only what this device already holds" would spare exactly the
    /// objects the sweep exists to reclaim. Time is therefore the only gate, and
    /// `MediaLifecycle.isExpired` is the load-bearing guard: purging early destroys evidence the
    /// celebrant may not have seen yet.
    ///
    /// The second guard is a path check, and it is load-bearing for a less obvious reason.
    /// `challenge.proofUrl` sits in the *gameplay* tier of the Firestore rules, so **any member can
    /// write it to any string**. The celebrant is authorised to delete both proof objects and
    /// reward media in their own event, so a contributor who wrote another contributor's gift path
    /// into `proofUrl` would have the celebrant's own sweep destroy that gift — the Storage rules
    /// cannot catch it, because both deletes are legitimately theirs to make. Rebuilding the
    /// expected path with the same `StoragePaths.proof` constructor the upload uses, and demanding
    /// exact equality, makes the sweep unable to aim anywhere but this challenge's own proof.
    func purgeExpiredProofs(challenges: [Challenge], eventId: String, occasionDate: Date, now: Date) async -> Int {
        guard MediaLifecycle.isExpired(occasionDate: occasionDate, now: now) else { return 0 }

        var purgedCount = 0
        for challenge in challenges {
            guard let challengeId = challenge.id else { continue }
            guard let path = challenge.proofUrl, !path.isEmpty else { continue }

            let expectedPath = StoragePaths.proof(
                eventId: eventId,
                challengeId: challengeId,
                fileName: URL(fileURLWithPath: path).lastPathComponent
            )
            guard path == expectedPath else {
                logger.error("Refusing to purge proofUrl outside this challenge's own proof path")
                continue
            }

            do {
                try await transfer.delete(path: path)
                purgedCount += 1
            } catch {
                // Best-effort: a failed delete is retried on the next sweep, and the count stays
                // honest about what actually left the server.
                logger.error("purgeExpiredProofs delete failed for \(path): \(error.localizedDescription)")
            }
        }
        return purgedCount
    }

    // MARK: - Private

    private func sharedFileURL(eventId: String, path: String) -> URL {
        baseDirectory
            .appendingPathComponent("SharedMedia", isDirectory: true)
            .appendingPathComponent(eventId, isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
    }

    private func storagePaths(for reward: Reward) -> [String] {
        switch reward.contentType {
        case .image: return reward.contentUrls ?? []
        case .video, .audio: return [reward.contentUrl].compactMap { $0 }
        case .text: return []
        }
    }

    private func localFileURL(eventId: String, rewardId: String, path: String) -> URL {
        baseDirectory
            .appendingPathComponent("RewardMedia", isDirectory: true)
            .appendingPathComponent(eventId, isDirectory: true)
            .appendingPathComponent(rewardId, isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
    }

    private func recordFetchIfNeeded(reward: Reward, eventId: String, rewardId: String) async {
        guard let uid = auth.currentUid, !(reward.fetchedBy ?? []).contains(uid) else { return }
        do {
            try await service.markRewardFetched(eventId: eventId, rewardId: rewardId, uid: uid)
        } catch {
            // Best-effort: the media is already local, so a failure here must not fail the resolve.
            logger.error("markRewardFetched failed: \(error.localizedDescription)")
        }
    }
}
