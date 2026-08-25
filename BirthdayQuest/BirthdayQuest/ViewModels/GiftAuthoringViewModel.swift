import Foundation
import SwiftUI
import PhotosUI
import Combine
import OSLog

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

    /// A gift is a letter or a set of photos (video/voice arrive in later slices). For an
    /// existing gift this is locked to its stored `contentType` — switching modes on an
    /// existing gift is a content rewrite and is out of scope.
    enum GiftContentMode {
        case letter
        case photos
    }

    /// Selecting more than this many photos would make a single gift unreasonably heavy to
    /// upload and to view.
    static let maxPhotoCount = 10

    @Published var title = ""
    @Published var teaser = ""
    @Published var letter = ""
    @Published var contentMode: GiftContentMode = .letter
    @Published var selectedPhotos: [PhotosPickerItem] = [] {
        didSet { Task { await loadPhotoPreviews() } }
    }
    /// Settable rather than `private(set)`: tests inject preview images directly, the same
    /// way `ChallengeSubmissionViewModel.selectedImageData` bypasses `PhotosPickerItem`'s
    /// async load, which cannot be constructed from a unit test.
    @Published var photoPreviews: [UIImage] = []
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

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch contentMode {
        case .letter:
            return !letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photos:
            return !selectedPhotos.isEmpty || !(existingGift?.contentUrls ?? []).isEmpty
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
                        self.contentMode = mine.contentType == .image ? .photos : .letter
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
}
