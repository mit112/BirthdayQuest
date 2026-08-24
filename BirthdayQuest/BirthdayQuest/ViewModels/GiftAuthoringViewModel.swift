import Foundation
import SwiftUI
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

    @Published var title = ""
    @Published var teaser = ""
    @Published var letter = ""
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

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    // MARK: Save

    func save() async {
        guard !isSaving, let userId else { return }
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
}
