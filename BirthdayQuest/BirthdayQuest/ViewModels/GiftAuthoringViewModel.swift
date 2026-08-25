import Foundation
import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import Combine
import OSLog

/// A movie picked from the photo library, materialised as a local file URL so its size can be
/// checked against the 200 MB Storage cap without loading the whole clip into memory. PhotosUI
/// hands back a file we do not own; the importing closure copies it into our temp dir so the URL
/// stays valid until `save()` reads it.
private struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Movie(url: copy)
        }
    }
}

/// One contributor's gift to the celebrant.
///
/// Shaped exactly like `SecretChallengeViewModel`: one per person, recovered by scanning the
/// shared listener for the row whose author is you rather than by remembering a document id
/// across launches.
///
/// The contributor writes the gift; the **host** sets its price and position. That split is
/// enforced in `firestore.rules` — a write from here carrying `pointCost` is denied — so
/// `contentFields` must never include one.
@MainActor
final class GiftAuthoringViewModel: ObservableObject {

    /// A gift is a letter, a set of photos, a video, or a voice recording. For an existing gift
    /// this is locked to its stored `contentType` — switching modes on an existing gift is a
    /// content rewrite and is out of scope.
    enum GiftContentMode {
        case letter
        case photos
        case video
        case voice
    }

    /// Selecting more than this many photos would make a single gift unreasonably heavy to
    /// upload and to view.
    static let maxPhotoCount = 10

    /// The Storage rules reject an upload of 200 MB or more (`request.resource.size <
    /// 200 * 1024 * 1024`), so a bigger clip would 403 after a long upload. Reject it up front.
    static let maxVideoBytes = 200 * 1024 * 1024

    /// Same 200 MB Storage cap as video. A recorded AAC/.m4a is only a few MB, but an *imported*
    /// audio file could be large, so both paths are size-checked through `acceptAudio`.
    static let maxAudioBytes = 200 * 1024 * 1024

    enum GiftAuthoringError: LocalizedError {
        case noPhotosUploaded

        var errorDescription: String? {
            switch self {
            case .noPhotosUploaded: return "Couldn't save your photos. Try again."
            }
        }
    }

    @Published var title = ""
    @Published var teaser = ""
    @Published var letter = ""
    @Published var contentMode: GiftContentMode = .letter {
        didSet { videoTooLarge = false; audioTooLarge = false }
    }
    @Published var selectedPhotos: [PhotosPickerItem] = [] {
        didSet { Task { await loadPhotoPreviews() } }
    }
    /// Settable rather than `private(set)`: tests inject preview images directly, the same
    /// way `ChallengeSubmissionViewModel.selectedImageData` bypasses `PhotosPickerItem`'s
    /// async load, which cannot be constructed from a unit test.
    @Published var photoPreviews: [UIImage] = []
    /// The library item the contributor picked. Loading it produces `selectedVideoURL`; tests set
    /// that directly, since a `PhotosPickerItem` cannot be built outside PhotosUI's live picker.
    @Published var selectedVideoItem: PhotosPickerItem? {
        didSet { Task { await loadVideoSelection() } }
    }
    /// The loaded, size-checked local file the video was copied to. Settable for tests.
    @Published var selectedVideoURL: URL?
    /// Set when the picked video is at or over `maxVideoBytes`; drives the inline error and keeps
    /// the oversized file out of `selectedVideoURL`.
    @Published var videoTooLarge = false
    /// The loaded, size-checked local file for the voice clip (recorded or imported). Settable
    /// for tests — a live recorder/file-importer result cannot be built in a unit test.
    @Published var selectedAudioURL: URL?
    /// Set when an imported audio file is at or over `maxAudioBytes`; drives the inline error and
    /// keeps the oversized file out of `selectedAudioURL`.
    @Published var audioTooLarge = false
    @Published private(set) var existingGift: Reward?
    @Published private(set) var isLoading = true
    @Published var isSaving = false
    @Published var saveSuccess = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showValidation = false
    /// Set when the gift listener is refused. Separate from `errorMessage`, which drives the
    /// save alert: a refused read is a persistent state, and an alert is dismissed straight
    /// back onto a blank form that invites writing a gift into an occasion that has stopped
    /// answering.
    @Published private(set) var loadFailure: String?

    /// Every gift in the occasion, held only to place a new one at the end of the order.
    private var allGifts: [Reward] = []
    private var userId: String?
    private var authorName: String = ""

    private let service: GameBackend
    private let eventId: String
    private let listenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "GiftAuthoring")

    /// A gift created at zero is unlockable the instant it appears. The host retunes this;
    /// the default only has to be a price rather than a hole.
    private static let defaultPointCost = 100

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.myGift(eventId)
    }

    var hasExisting: Bool { existingGift != nil }

    /// Locked once the celebrant has opened it. Rewriting a gift someone has already read
    /// would silently change what they were given.
    var isEditable: Bool { !(existingGift?.isUnlocked ?? false) }

    var contentState: ContentState {
        if let loadFailure { return .failed(loadFailure) }
        return isLoading ? .loading : .ready
    }

    /// A status line for an existing image gift's already-saved photos, or `nil` if there are
    /// none — used to explain why Save stays valid with nothing newly selected.
    var existingGiftHasPhotos: String? {
        guard let count = existingGift?.contentUrls?.count, count > 0 else { return nil }
        return "\(count) photo\(count == 1 ? "" : "s") already saved"
    }

    /// A note that an existing video gift already has a saved clip, or `nil` — explains why Save
    /// stays valid with nothing newly selected.
    var existingGiftHasVideo: String? {
        guard existingGift?.contentType == .video, existingGift?.contentUrl != nil else { return nil }
        return "A video is already saved"
    }

    /// A note that an existing voice gift already has a saved clip, or `nil` — explains why Save
    /// stays valid with nothing newly selected.
    var existingGiftHasAudio: String? {
        guard existingGift?.contentType == .audio, existingGift?.contentUrl != nil else { return nil }
        return "A voice recording is already saved"
    }

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch contentMode {
        case .letter:
            return !letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photos:
            // `photoPreviews`, not `selectedPhotos`: it is the loaded-image state `save()`
            // actually uploads from, and the only one a unit test can populate directly
            // (a `PhotosPickerItem` cannot be constructed outside `PhotosUI`'s live picker).
            return !photoPreviews.isEmpty || !(existingGift?.contentUrls ?? []).isEmpty
        case .video:
            return selectedVideoURL != nil || existingGift?.contentUrl != nil
        case .voice:
            return selectedAudioURL != nil || existingGift?.contentUrl != nil
        }
    }

    var statusText: String {
        if loadFailure != nil { return "Couldn't load your gift" }
        if existingGift?.isUnlocked == true { return "Opened — they've read it" }
        if hasExisting { return "Saved — edit any time" }
        return "Write your gift"
    }

    // MARK: Load

    func loadExisting(userId: String?, name: String) {
        self.userId = userId
        self.authorName = name
        guard let userId else {
            isLoading = false
            return
        }

        service.listenToRewards(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let gifts):
                    self.allGifts = gifts
                    if let mine = gifts.first(where: { $0.fromUserId == userId }) {
                        self.existingGift = mine
                        self.title = mine.title
                        self.teaser = mine.teaser ?? ""
                        self.letter = mine.contentText ?? ""
                        switch mine.contentType {
                        case .image: self.contentMode = .photos
                        case .video: self.contentMode = .video
                        case .audio: self.contentMode = .voice
                        case .text: self.contentMode = .letter
                        }
                    }
                    self.loadFailure = nil
                case .failure(let error):
                    self.logger.error("Gift listener: \(error.localizedDescription)")
                    self.loadFailure = """
                        Your gift didn't load. You may no longer have access to this \
                        occasion, or the connection dropped.
                        """
                }
            }
        }
    }

    func stopListening() {
        service.removeListener(forKey: listenerKey)
    }

    // MARK: Photo selection

    /// Reloads `photoPreviews` from `selectedPhotos`. Caps at `maxPhotoCount` — the picker's
    /// own `maxSelectionCount` already enforces this, but a re-pick could still hand back a
    /// larger array, and uploading past the cap is what this guard closes.
    private func loadPhotoPreviews() async {
        let capped = Array(selectedPhotos.prefix(Self.maxPhotoCount))
        if capped.count != selectedPhotos.count { selectedPhotos = capped }

        var images: [UIImage] = []
        for item in capped {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            } catch {
                logger.error("Photo load error: \(error.localizedDescription)")
            }
        }
        photoPreviews = images
    }

    /// Compresses image data to ~500KB JPEG, mirroring `ChallengeSubmissionViewModel`'s
    /// pattern: raw photos are too heavy to upload as-is.
    private func compressImage(_ image: UIImage, maxKB: Int = 500) -> Data? {
        var quality: CGFloat = 0.8
        var compressed = image.jpegData(compressionQuality: quality)
        while let data = compressed, data.count > maxKB * 1024, quality > 0.15 {
            quality -= 0.1
            compressed = image.jpegData(compressionQuality: quality)
        }
        return compressed
    }

    // MARK: Save

    func save() async {
        guard !isSaving, isEditable, let userId else { return }
        guard isValid else {
            showValidation = true
            BQDesign.Haptics.error()
            return
        }

        isSaving = true
        defer { isSaving = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTeaser = teaser.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLetter = letter.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            switch contentMode {
            case .letter:
                if let existing = existingGift, let id = existing.id {
                    // Content keys only. pointCost and sortOrder are the host's tier, and the
                    // rules reject a write that reaches across tiers.
                    try await service.updateReward(eventId: eventId, rewardId: id, fields: [
                        "title": trimmedTitle,
                        "teaser": trimmedTeaser,
                        "contentText": trimmedLetter,
                    ])
                } else {
                    let gift = Reward(
                        fromUserId: userId,
                        fromName: authorName,
                        title: trimmedTitle,
                        teaser: trimmedTeaser,
                        pointCost: Self.defaultPointCost,
                        contentType: .text,
                        contentUrl: nil,
                        contentUrls: nil,
                        contentText: trimmedLetter,
                        isUnlocked: false,
                        unlockedAt: nil,
                        sortOrder: allGifts.count,
                        badgeIllustration: "envelope.fill",
                        createdAt: Date()
                    )
                    _ = try await service.createReward(eventId: eventId, reward: gift)
                }
            case .photos:
                try await savePhotos(
                    userId: userId, title: trimmedTitle, teaser: trimmedTeaser
                )
            case .video:
                try await saveVideo(userId: userId, title: trimmedTitle, teaser: trimmedTeaser)
            case .voice:
                try await saveAudio(userId: userId, title: trimmedTitle, teaser: trimmedTeaser)
            }

            isSaving = false
            saveSuccess = true
            BQDesign.Haptics.success()
            try? await Task.sleep(for: .milliseconds(1500))
            saveSuccess = false
        } catch {
            logger.error("Saving the gift failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save your gift. Try again."
            showError = true
            BQDesign.Haptics.error()
        }
    }

    /// Uploads any newly-selected photos to a client-generated storage folder, then writes
    /// the reward exactly once. A new gift's Firestore id does not exist until `createReward`
    /// returns, so the upload folder is a `UUID` the rules only check `eventId` against — it
    /// need not equal the eventual document id. This keeps `totalRewards` incrementing exactly
    /// once and never leaves an empty image reward behind.
    private func savePhotos(userId: String, title: String, teaser: String) async throws {
        var paths: [String]?
        if !photoPreviews.isEmpty {
            let group = UUID().uuidString
            var uploaded: [String] = []
            for image in photoPreviews {
                guard let data = compressImage(image) else { continue }
                let path = try await service.uploadRewardMedia(
                    eventId: eventId, rewardId: group, data: data, contentType: "image/jpeg"
                )
                uploaded.append(path)
            }
            paths = uploaded
        }

        // A new gift with no successfully-compressed photo must not create an empty `.image`
        // reward (it resolves to `.unavailable` — a broken gift). An existing gift keeps its
        // prior `contentUrls` when every re-selected photo fails, since `fields` above only
        // sets `contentUrls` when `paths` is non-nil.
        if existingGift == nil, let paths, paths.isEmpty {
            throw GiftAuthoringError.noPhotosUploaded
        }

        if let existing = existingGift, let id = existing.id {
            var fields: [String: Any] = ["title": title, "teaser": teaser]
            if let paths { fields["contentUrls"] = paths }
            try await service.updateReward(eventId: eventId, rewardId: id, fields: fields)
        } else {
            let gift = Reward(
                fromUserId: userId,
                fromName: authorName,
                title: title,
                teaser: teaser,
                pointCost: Self.defaultPointCost,
                contentType: .image,
                contentUrl: nil,
                contentUrls: paths ?? [],
                contentText: nil,
                isUnlocked: false,
                unlockedAt: nil,
                sortOrder: allGifts.count,
                badgeIllustration: "photo.fill",
                createdAt: Date()
            )
            _ = try await service.createReward(eventId: eventId, reward: gift)
        }
    }

    // MARK: Video selection

    private func loadVideoSelection() async {
        guard let item = selectedVideoItem else { return }
        do {
            guard let movie = try await item.loadTransferable(type: Movie.self) else { return }
            let size = (try? FileManager.default.attributesOfItem(atPath: movie.url.path))?[.size] as? Int ?? 0
            acceptVideo(url: movie.url, sizeBytes: size)
            if videoTooLarge {
                try? FileManager.default.removeItem(at: movie.url)
            }
        } catch {
            logger.error("Video load error: \(error.localizedDescription)")
        }
    }

    /// Accepts a picked video only if it is under the Storage cap, so an oversized clip is rejected
    /// before a doomed upload. Split out from the PhotosUI load so it is unit-testable — a
    /// `PhotosPickerItem` cannot be constructed in a test.
    func acceptVideo(url: URL, sizeBytes: Int) {
        guard sizeBytes < Self.maxVideoBytes else {
            videoTooLarge = true
            if let previous = selectedVideoURL {
                try? FileManager.default.removeItem(at: previous)
            }
            selectedVideoURL = nil
            return
        }
        videoTooLarge = false
        if let previous = selectedVideoURL, previous != url {
            try? FileManager.default.removeItem(at: previous)
        }
        selectedVideoURL = url
    }

    /// Uploads the selected clip (if any) to a client-generated folder, then writes the reward
    /// once. Mirrors `savePhotos`: the folder is a `UUID`, independent of the eventual document id.
    /// Video uses the single `contentUrl` field, never `contentUrls`. There is no partial-failure
    /// path to guard as in `savePhotos` — a single upload either throws (caught by `save`) or
    /// returns a path — and `isValid` guarantees `selectedVideoURL` for a new gift, so a `.video`
    /// reward is never created empty.
    private func saveVideo(userId: String, title: String, teaser: String) async throws {
        var path: String?
        let uploadedURL = selectedVideoURL
        if let url = uploadedURL {
            let data = try Data(contentsOf: url)
            let group = UUID().uuidString
            path = try await service.uploadRewardMedia(
                eventId: eventId, rewardId: group, data: data,
                contentType: videoContentType(for: url)
            )
        }

        if let existing = existingGift, let id = existing.id {
            var fields: [String: Any] = ["title": title, "teaser": teaser]
            if let path { fields["contentUrl"] = path }
            try await service.updateReward(eventId: eventId, rewardId: id, fields: fields)
        } else {
            let gift = Reward(
                fromUserId: userId,
                fromName: authorName,
                title: title,
                teaser: teaser,
                pointCost: Self.defaultPointCost,
                contentType: .video,
                contentUrl: path,
                contentUrls: nil,
                contentText: nil,
                isUnlocked: false,
                unlockedAt: nil,
                sortOrder: allGifts.count,
                badgeIllustration: "video.fill",
                createdAt: Date()
            )
            _ = try await service.createReward(eventId: eventId, reward: gift)
        }

        // Only after the whole write succeeds — an earlier throw leaves the file for a retry.
        if let uploadedURL {
            try? FileManager.default.removeItem(at: uploadedURL)
            selectedVideoURL = nil
        }
    }

    /// The clip's MIME type from its file extension. PhotosUI exports `.mov` (QuickTime) most
    /// often; `.mp4` is the other common case. Both are accepted by `isPlayableMedia` in the
    /// Storage rules and mapped to an extension by `FirestoreService.fileExtension`.
    private func videoContentType(for url: URL) -> String {
        url.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
    }

    // MARK: Audio selection

    /// Accepts a picked/recorded audio clip only if it is under the Storage cap. Mirrors
    /// `acceptVideo`: an oversized import is rejected before a doomed upload, and a replacement
    /// deletes the prior temp file. The recorder and the file importer both funnel through here.
    func acceptAudio(url: URL, sizeBytes: Int) {
        guard sizeBytes < Self.maxAudioBytes else {
            audioTooLarge = true
            if let previous = selectedAudioURL {
                try? FileManager.default.removeItem(at: previous)
            }
            selectedAudioURL = nil
            return
        }
        audioTooLarge = false
        if let previous = selectedAudioURL, previous != url {
            try? FileManager.default.removeItem(at: previous)
        }
        selectedAudioURL = url
    }

    /// Uploads the selected clip (if any) to a client-generated folder, then writes the reward
    /// once. Mirrors `saveVideo`: the folder is a `UUID`, independent of the eventual document id.
    /// Voice uses the single `contentUrl` field, never `contentUrls`. `isValid` guarantees
    /// `selectedAudioURL` for a new gift, so a `.audio` reward is never created empty.
    private func saveAudio(userId: String, title: String, teaser: String) async throws {
        var path: String?
        let uploadedURL = selectedAudioURL
        if let url = uploadedURL {
            let data = try Data(contentsOf: url)
            let group = UUID().uuidString
            path = try await service.uploadRewardMedia(
                eventId: eventId, rewardId: group, data: data,
                contentType: audioContentType(for: url)
            )
        }

        if let existing = existingGift, let id = existing.id {
            var fields: [String: Any] = ["title": title, "teaser": teaser]
            if let path { fields["contentUrl"] = path }
            try await service.updateReward(eventId: eventId, rewardId: id, fields: fields)
        } else {
            let gift = Reward(
                fromUserId: userId,
                fromName: authorName,
                title: title,
                teaser: teaser,
                pointCost: Self.defaultPointCost,
                contentType: .audio,
                contentUrl: path,
                contentUrls: nil,
                contentText: nil,
                isUnlocked: false,
                unlockedAt: nil,
                sortOrder: allGifts.count,
                badgeIllustration: "waveform",
                createdAt: Date()
            )
            _ = try await service.createReward(eventId: eventId, reward: gift)
        }

        if let uploadedURL {
            try? FileManager.default.removeItem(at: uploadedURL)
            selectedAudioURL = nil
        }
    }

    /// The clip's MIME type from its file extension. The recorder writes `.m4a`; imports are
    /// restricted to `.m4a`/`.mp3`. Both `audio/mp4` and `audio/mpeg` are mapped by
    /// `FirestoreService.fileExtension` and accepted by `isPlayableMedia` in the Storage rules.
    private func audioContentType(for url: URL) -> String {
        url.pathExtension.lowercased() == "mp3" ? "audio/mpeg" : "audio/mp4"
    }
}
