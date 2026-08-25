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

        var errorDescription: String? {
            switch self {
            case .missingRewardId: return "This reward has no id yet."
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
                try await transfer.download(path: path, to: localFile)
            }
            localURLs.append(localFile)
        }

        await recordFetchIfNeeded(reward: reward, eventId: eventId, rewardId: rewardId)

        return localURLs
    }

    func purge(reward: Reward, eventId: String) async throws {
        for path in storagePaths(for: reward) {
            try await transfer.delete(path: path)
        }
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
