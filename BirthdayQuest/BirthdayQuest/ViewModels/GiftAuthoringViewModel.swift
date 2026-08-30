import Foundation
import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import Combine
import OSLog
import FirebaseStorage

// MARK: - RewardMediaProbing

/// Answers one question about a reward's media: is the Storage object still there?
///
/// Deliberately **not** a `GameBackend` method. That seam is Firestore CRUD plus the two
/// uploads; this is a Storage metadata read with different failure semantics, and widening the
/// backend protocol for it would push a change into a file this work has no other reason to
/// touch. It is narrow and injectable for the same reason `ProofMediaLoading` is: so the
/// re-send carve-out can be tested without a network.
protocol RewardMediaProbing: Sendable {
    /// `true` **only** when the object at `path` is confirmed absent.
    ///
    /// Every other outcome — present, unauthorized, offline, malformed path — must answer
    /// `false`. This drives an editability carve-out on a gift the celebrant has already
    /// opened, so the two errors are not symmetric: a wrong `false` merely preserves today's
    /// behaviour, while a wrong `true` hands someone a rewrite of a gift that was already read.
    /// Fail closed.
    func isObjectMissing(path: String) async -> Bool
}

/// Production probe. `getMetadata()` is a small metadata request, not a download — the point of
/// using it rather than `MediaStore` is that confirming absence must not cost a media transfer.
/// The Storage rules grant reward-media `read` to any member, so a contributor is authorised to
/// ask about their own gift's objects.
struct FirebaseRewardMediaProbe: RewardMediaProbing {
    func isObjectMissing(path: String) async -> Bool {
        do {
            _ = try await Storage.storage().reference(withPath: path).getMetadata()
            return false
        } catch let error as NSError {
            // Same narrow test `MediaStore` uses to raise `objectMissing`: only a genuine
            // 404 counts. Anything else (permission, network) falls through to `false`.
            return error.code == StorageErrorCode.objectNotFound.rawValue
        }
    }
}

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
    ///
    /// **This number and the one in `storage.rules` have to move together** — a mismatch shows
    /// up only at runtime, as a permission-denied after the whole upload, and nothing catches it
    /// at compile time.
    ///
    /// It is now a *backstop*, not the gate a contributor meets. A picked clip is re-encoded to
    /// ~1080p first (see `prepareVideo(source:)`), so what is measured here is the transcode's
    /// output; a 4K phone clip that used to be turned away at 600 MB now arrives well inside the
    /// cap. Reaching this check at all means either the transcode failed and the original is
    /// being measured, or the source was long enough that even 1080p HEVC does not fit.
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
    ///
    /// Each pick cancels the one before it and *waits* for it to unwind before starting. Two
    /// overlapping preparations would race on `isTranscoding`, `transcodeProgress` and
    /// `selectedVideoURL` — and the loser, finishing last, would clear the winner's progress
    /// flag while its own transcode was still running.
    @Published var selectedVideoItem: PhotosPickerItem? {
        didSet {
            let previous = videoPreparation
            videoPreparation = Task { [weak self] in
                previous?.cancel()
                await previous?.value
                await self?.loadVideoSelection()
            }
        }
    }
    /// Set while a picked clip is being re-encoded — not instant on a long 4K source, and
    /// nothing else on screen would explain the wait.
    @Published private(set) var isTranscoding = false
    /// 0…1, meaningful only while `isTranscoding`.
    @Published private(set) var transcodeProgress: Double = 0
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
    /// Set only once this gift's Storage objects have been **confirmed gone** — never from the
    /// expiry date alone. See `checkMediaExpiry(occasionDate:now:)`.
    @Published private(set) var mediaExpired = false

    /// Every gift in the occasion, held only to place a new one at the end of the order.
    private var allGifts: [Reward] = []
    private var userId: String?
    private var authorName: String = ""
    /// `checkMediaExpiry` is one-shot per screen: the answer cannot change while the form is
    /// open except through a re-send, which sets `mediaExpired` itself.
    private var didCheckMediaExpiry = false
    /// The in-flight load-and-transcode for the most recent pick. See `selectedVideoItem`.
    private var videoPreparation: Task<Void, Never>?

    private let service: GameBackend
    private let mediaProbe: RewardMediaProbing
    private let transcoder: VideoTranscoding
    private let eventId: String
    private let listenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "GiftAuthoring")

    /// A gift created at zero is unlockable the instant it appears. The host retunes this;
    /// the default only has to be a price rather than a hole.
    private static let defaultPointCost = 100

    init(
        eventId: String,
        service: GameBackend = FirestoreService.shared,
        mediaProbe: RewardMediaProbing = FirebaseRewardMediaProbe(),
        transcoder: VideoTranscoding = AVFoundationVideoTranscoder()
    ) {
        self.eventId = eventId
        self.service = service
        self.mediaProbe = mediaProbe
        self.transcoder = transcoder
        self.listenerKey = ListenerKey.myGift(eventId)
    }

    var hasExisting: Bool { existingGift != nil }

    /// Locked once the celebrant has opened it. Rewriting a gift someone has already read
    /// would silently change what they were given.
    var isEditable: Bool { !(existingGift?.isUnlocked ?? false) }

    /// Whether media may be attached at all: normally only while the gift is still unopened,
    /// plus the one carve-out below.
    ///
    /// The carve-out is deliberately narrow. `isEditable` exists so a contributor cannot
    /// rewrite a gift the celebrant has already read, and that intent survives whole: this
    /// permits **replacing media that no longer exists** — the celebrant is at this moment
    /// looking at "isn't available anymore" — and nothing else.
    ///
    /// What it still forbids, in the `isResendOnly` state:
    /// - rewriting `title`, `teaser` or the letter text (the form keeps them disabled *and*
    ///   `save()` never puts them in the payload — the rules would happily accept them, since
    ///   they sit in the same content tier, so only this code stops it);
    /// - changing `contentType` (the picker is hidden once a gift exists, and neither write
    ///   path sends the key);
    /// - touching `pointCost`/`sortOrder` (host tier) or `isUnlocked`/`fetchedBy` (gameplay
    ///   tier) — a write spanning two tiers is rejected by the rules at runtime anyway;
    /// - re-sending on suspicion. `mediaExpired` is set only by a probe that *confirmed* the
    ///   objects are gone, never by the expiry date on its own.
    var canAttachMedia: Bool { isEditable || mediaExpired }

    /// Exactly the carve-out state: the celebrant has opened this gift, so its words are
    /// frozen, but its media is gone and may be sent again.
    var isResendOnly: Bool { !isEditable && mediaExpired }

    /// Whether the contributor has picked something new in this session, as opposed to the
    /// gift merely having a stored (and possibly dead) path.
    var hasNewMediaSelection: Bool {
        switch contentMode {
        case .letter: return false
        case .photos: return !photoPreviews.isEmpty
        case .video:  return selectedVideoURL != nil
        case .voice:  return selectedAudioURL != nil
        }
    }

    /// Banner copy for a gift whose media is confirmed gone, or `nil`. Name-free by the
    /// convention the other status strings here follow — the view owns the celebrant's name.
    var expiredMediaMessage: String? {
        guard mediaExpired else { return nil }
        switch contentMode {
        case .photos: return "These photos are no longer on the server. Add them again to send this gift back."
        case .video:  return "This video is no longer on the server. Add it again to send this gift back."
        case .voice:  return "This voice gift is no longer on the server. Record or choose it again to send it back."
        case .letter: return nil
        }
    }

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
        // In the re-send carve-out the only thing being written is replacement media, so the
        // already-stored path must not satisfy validity — it is the very path that is dead.
        // The title is not re-validated either: it is not in the payload and cannot be edited.
        if isResendOnly { return hasNewMediaSelection }

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
        if mediaExpired { return "Expired — send it again" }
        if existingGift?.isUnlocked == true { return "Opened — they've read it" }
        if hasExisting { return "Saved — edit any time" }
        return "Write your gift"
    }

    // MARK: Media expiry

    /// Detects that this contributor's own media gift can no longer be delivered.
    ///
    /// Two stages, and both are load-bearing:
    ///
    /// 1. **Date.** `MediaLifecycle.isExpired` is the same policy the celebrant's purge is
    ///    gated on, so before that instant nothing can have been deleted and no request is
    ///    worth making. This is also why the check is essentially free for every live occasion.
    /// 2. **Evidence.** Past that instant the media is only *eligible* for cleanup. The purge
    ///    runs on the celebrant's device and only for objects it has already archived, so a
    ///    gift can be months past expiry with its objects perfectly intact. Inferring from the
    ///    date alone would both lie to the contributor and — since this unlocks an editability
    ///    carve-out — hand them a rewrite of a gift that has already been read. So each stored
    ///    path is probed for real, and only a confirmed absence counts.
    ///
    /// Any path missing is enough, matching `RewardContentPresentation.resolve`: it raises
    /// `.expired` on the *first* object it cannot fetch, so a gallery with one dead photo is
    /// already broken from the celebrant's side.
    ///
    /// Runs at most once per screen and only for an existing gift that actually has media.
    /// Deliberately not conditioned on `isUnlocked`: an unopened gift can expire too, and
    /// while its form is already editable, nothing else would tell the contributor to act.
    func checkMediaExpiry(occasionDate: Date?, now: Date = Date()) async {
        guard !didCheckMediaExpiry, !mediaExpired else { return }
        guard let occasionDate, let gift = existingGift else { return }
        // Same union `GiftCurationViewModel` uses when purging: a text gift yields nothing.
        let paths = (gift.contentUrls ?? []) + [gift.contentUrl].compactMap { $0 }
        guard !paths.isEmpty else { return }
        guard MediaLifecycle.isExpired(occasionDate: occasionDate, now: now) else { return }

        didCheckMediaExpiry = true
        for path in paths where !mediaExpired {
            if await mediaProbe.isObjectMissing(path: path) {
                logger.info("Gift media is gone from Storage; offering a re-send")
                mediaExpired = true
            }
        }
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
        guard !isSaving, canAttachMedia, let userId else { return }
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
        // Read once: `resendMedia` clears `mediaExpired` on success, which would otherwise
        // change the branch out from under the code that follows it.
        let resendOnly = isResendOnly

        do {
            if resendOnly {
                guard let rewardId = existingGift?.id else { return }
                try await resendMedia(rewardId: rewardId)
            } else {
                switch contentMode {
                case .letter:
                    if let existing = existingGift, let id = existing.id {
                        // Content keys only. pointCost and sortOrder are the host's tier, and
                        // the rules reject a write that reaches across tiers.
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
                        // A text gift owns no media, but the id is still caller-chosen so
                        // every gift is created the same way as the media ones.
                        _ = try await service.createReward(
                            eventId: eventId, rewardId: UUID().uuidString, reward: gift
                        )
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

    /// Re-sends a gift whose media the server no longer holds: uploads the replacement and
    /// writes **only** the media key.
    ///
    /// The payload is the whole point of this method existing separately from `savePhotos` /
    /// `saveVideo` / `saveAudio`, which all also carry `title` and `teaser`. `title`/`teaser`
    /// sit in the same content tier as `contentUrl`, so the rules would accept them here —
    /// the thing that keeps a re-send from becoming a silent rewrite of an opened gift is this
    /// dictionary, not the backend. Nothing gameplay-side (`isUnlocked`, `fetchedBy`) may ride
    /// along either: that write spans two tiers and the rules reject it at runtime.
    ///
    /// Uploads into the gift's own `rewards/{rewardId}/…` folder (so the rules' path binding
    /// holds) under a fresh UUID *filename*, never the old path: the Storage rules deny
    /// overwrites outright. The dead objects are already gone, so there is nothing left to
    /// clean up server-side.
    private func resendMedia(rewardId: String) async throws {
        var fields: [String: Any] = [:]
        var temporaryFile: URL?

        switch contentMode {
        case .letter:
            // Unreachable — a text gift owns no Storage objects, so `mediaExpired` can never
            // become true for one. Returning is still the right answer if that ever changes.
            return
        case .photos:
            var uploaded: [String] = []
            for image in photoPreviews {
                guard let data = compressImage(image) else { continue }
                uploaded.append(try await service.uploadRewardMedia(
                    eventId: eventId, rewardId: rewardId, data: data, contentType: "image/jpeg"
                ))
            }
            // Replacing a dead gallery with an empty array would leave the celebrant on
            // `.unavailable` — a different, and equally wrong, dead end.
            guard !uploaded.isEmpty else { throw GiftAuthoringError.noPhotosUploaded }
            fields["contentUrls"] = uploaded
        case .video:
            guard let url = selectedVideoURL else { return }
            temporaryFile = url
            fields["contentUrl"] = try await service.uploadRewardMedia(
                eventId: eventId, rewardId: rewardId,
                fileURL: url, contentType: videoContentType(for: url)
            )
        case .voice:
            guard let url = selectedAudioURL else { return }
            temporaryFile = url
            fields["contentUrl"] = try await service.uploadRewardMedia(
                eventId: eventId, rewardId: rewardId,
                fileURL: url, contentType: audioContentType(for: url)
            )
        }

        try await service.updateReward(eventId: eventId, rewardId: rewardId, fields: fields)

        // Only after the write lands — an earlier throw leaves the file for a retry.
        if let temporaryFile {
            try? FileManager.default.removeItem(at: temporaryFile)
            selectedVideoURL = nil
            selectedAudioURL = nil
        }
        // The gift is deliverable again, so the carve-out closes and the form re-locks. The
        // celebrant's next resolve sees a live path and stops rendering `.expired`.
        mediaExpired = false
    }

    /// Uploads any newly-selected photos into the gift's own `rewards/{rewardId}/…` folder,
    /// then writes the reward exactly once. For a new gift the id is chosen up front (a UUID
    /// is a valid document id) so the upload lands in the gift's own folder before the document
    /// exists — which is what lets the rules bind `contentUrls` to it. This keeps `totalRewards`
    /// incrementing exactly once and never leaves an empty image reward behind.
    private func savePhotos(userId: String, title: String, teaser: String) async throws {
        let rewardId = existingGift?.id ?? UUID().uuidString
        var paths: [String]?
        if !photoPreviews.isEmpty {
            var uploaded: [String] = []
            for image in photoPreviews {
                guard let data = compressImage(image) else { continue }
                let path = try await service.uploadRewardMedia(
                    eventId: eventId, rewardId: rewardId, data: data, contentType: "image/jpeg"
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
            _ = try await service.createReward(eventId: eventId, rewardId: rewardId, reward: gift)
        }
    }

    // MARK: Video selection

    private func loadVideoSelection() async {
        guard let item = selectedVideoItem else { return }
        do {
            guard let movie = try await item.loadTransferable(type: Movie.self) else { return }
            await prepareVideo(source: movie.url)
        } catch {
            logger.error("Video load error: \(error.localizedDescription)")
        }
    }

    /// Re-encodes a picked clip, then hands whichever file is smaller to `acceptVideo`.
    ///
    /// This is what makes a modern phone clip sendable at all. A minute of 4K/60 is comfortably
    /// past 400 MB, and used to be turned away with "pick a shorter one" — a fail-safe answer,
    /// but the wrong one, since the same footage at 1080p HEVC is a fraction of that and is what
    /// the celebrant would watch either way.
    ///
    /// Three outcomes, and the ordering of the file deletes matters in each:
    /// - **Transcoded smaller.** The re-encode wins, the picked original is deleted.
    /// - **Transcoded no smaller.** A short, already-efficient clip can come out of a 1080p
    ///   re-encode *larger* than it went in. Keep the original and delete the export — the point
    ///   of this is to upload less, not to normalise containers.
    /// - **Transcode failed.** Fall back to the picked original and let `acceptVideo` size-check
    ///   it, which is exactly the behaviour that shipped before. An export failing is not a
    ///   reason to refuse a clip that would have been fine.
    ///
    /// Cancellation drops both files and clears the progress flag, but never touches
    /// `selectedVideoURL`: the pick that replaced this one owns the selection now.
    ///
    /// Split out from the PhotosUI load so it is unit-testable — a `PhotosPickerItem` cannot be
    /// constructed outside PhotosUI's live picker.
    func prepareVideo(source: URL) async {
        isTranscoding = true
        transcodeProgress = 0
        defer { isTranscoding = false }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        do {
            try await transcoder.transcode(source: source, destination: destination) { fraction in
                // Strong, deliberately: the enclosing closure already holds `self` for the
                // duration of a call this method is awaiting, so a weak capture would only
                // disagree with it. Nothing outlives `transcode`, so there is no cycle to break.
                Task { @MainActor in self.transcodeProgress = fraction }
            }
            // Asked of the task, not of the error, and asked on the *success* path too: an
            // exporter is free to notice a cancellation and return normally rather than throw,
            // and the guarantee here — a superseded pick never writes to the selection — has to
            // hold either way. Checking only in `catch` would let a cancelled preparation hand
            // its abandoned clip to `acceptVideo` behind the pick that replaced it.
            guard !Task.isCancelled else { return Self.discard(destination, source) }
            let sourceSize = Self.fileSize(of: source)
            let transcodedSize = Self.fileSize(of: destination)
            if transcodedSize > 0 && transcodedSize < sourceSize {
                Self.discard(source)
                accept(preparedVideo: destination, sizeBytes: transcodedSize)
            } else {
                Self.discard(destination)
                accept(preparedVideo: source, sizeBytes: sourceSize)
            }
        } catch {
            Self.discard(destination)
            guard !Task.isCancelled else { return Self.discard(source) }
            logger.error("Video transcode failed, offering the original: \(error.localizedDescription)")
            accept(preparedVideo: source, sizeBytes: Self.fileSize(of: source))
        }
    }

    /// Best-effort removal of temp files this screen created. A leftover clip in the temp
    /// directory is harmless; failing a gift over one would not be.
    private static func discard(_ urls: URL...) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// `acceptVideo` plus the rejected file's cleanup. A refused clip is left on disk by
    /// `acceptVideo` — it only deletes the *previous* selection — so whoever produced the file
    /// has to remove it, and after a transcode that is no longer always the picked original.
    private func accept(preparedVideo url: URL, sizeBytes: Int) {
        acceptVideo(url: url, sizeBytes: sizeBytes)
        if videoTooLarge { try? FileManager.default.removeItem(at: url) }
    }

    /// Bytes on disk, or 0 if the file cannot be measured. A 0 never reads as "small enough":
    /// the smaller-file comparison requires a positive size, so an unmeasurable export is
    /// discarded in favour of the original rather than silently uploaded.
    private static func fileSize(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
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

    /// Uploads the selected clip (if any) into the gift's own `rewards/{rewardId}/…` folder,
    /// then writes the reward once. Mirrors `savePhotos`: the id is chosen up front so the media
    /// lands in the gift's own folder and the rules can bind `contentUrl` to it. Video uses the
    /// single `contentUrl` field, never `contentUrls`. There is no partial-failure path to guard
    /// as in `savePhotos` — a single upload either throws (caught by `save`) or returns a path —
    /// and `isValid` guarantees `selectedVideoURL` for a new gift, so a `.video` reward is never
    /// created empty.
    private func saveVideo(userId: String, title: String, teaser: String) async throws {
        let rewardId = existingGift?.id ?? UUID().uuidString
        var path: String?
        let uploadedURL = selectedVideoURL
        if let url = uploadedURL {
            path = try await service.uploadRewardMedia(
                eventId: eventId, rewardId: rewardId, fileURL: url,
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
            _ = try await service.createReward(eventId: eventId, rewardId: rewardId, reward: gift)
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

    /// Uploads the selected clip (if any) into the gift's own `rewards/{rewardId}/…` folder,
    /// then writes the reward once. Mirrors `saveVideo`: the id is chosen up front so the media
    /// lands in the gift's own folder and the rules can bind `contentUrl` to it. Voice uses the
    /// single `contentUrl` field, never `contentUrls`. `isValid` guarantees `selectedAudioURL`
    /// for a new gift, so a `.audio` reward is never created empty.
    private func saveAudio(userId: String, title: String, teaser: String) async throws {
        let rewardId = existingGift?.id ?? UUID().uuidString
        var path: String?
        let uploadedURL = selectedAudioURL
        if let url = uploadedURL {
            path = try await service.uploadRewardMedia(
                eventId: eventId, rewardId: rewardId, fileURL: url,
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
            _ = try await service.createReward(eventId: eventId, rewardId: rewardId, reward: gift)
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
