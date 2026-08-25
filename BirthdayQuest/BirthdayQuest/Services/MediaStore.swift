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

// MARK: - MediaStore

/// Downloads a reward's media through an authenticated Storage reference and persists it to
/// Documents, so playback never depends on a live network connection. `contentUrl`/`contentUrls`
/// are Storage object paths, never download URLs (D1 / Ruling P2) — this type resolves them
/// through `MediaTransferring`, it never constructs a remote URL from them.
actor MediaStore: MediaStoring {

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

    // MARK: - Private

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
