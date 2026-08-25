import Foundation
import SwiftUI
import Combine
import OSLog

/// The host's view of every gift: what it costs, where it sits, and whether it stays.
///
/// Deliberately cannot edit a gift's text. A gift is a personal message and curating the
/// economy is a different job from rewriting what somebody wrote — `firestore.rules` enforces
/// that, so a stray content key here is a permission-denied rather than a style nit. The
/// host's moderation lever is `delete`.
@MainActor
final class GiftCurationViewModel: ObservableObject {

    @Published private(set) var gifts: [Reward] = []
    @Published private(set) var contentState: ContentState = .loading
    @Published var giftToDelete: Reward?
    @Published var actionResult: AdminActionResult?
    @Published var isPerformingAction = false

    private let service: GameBackend
    private let eventId: String
    private let listenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "GiftCuration")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.authoringRewards(eventId)
    }

    /// The total a celebrant would have to earn to unlock everything. The design intent is
    /// that challenges cannot quite cover it, so the host needs to see it while pricing.
    var totalCost: Int { gifts.reduce(0) { $0 + $1.pointCost } }

    func startListening() {
        service.listenToRewards(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let gifts):
                    self.gifts = gifts.sorted { $0.sortOrder < $1.sortOrder }
                    self.contentState = gifts.isEmpty ? .empty : .ready
                case .failure(let error):
                    self.logger.error("Curation listener: \(error.localizedDescription)")
                    self.gifts = []
                    self.contentState = .failed("Couldn't load this occasion's gifts.")
                }
            }
        }
    }

    func stopListening() {
        service.removeListener(forKey: listenerKey)
    }

    func setPrice(_ pointCost: Int, for gift: Reward) async {
        guard let giftId = gift.id else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            // pointCost alone. sortOrder is the same tier but a different action, and the
            // content keys are a different tier entirely — the rules reject a mixed write.
            try await service.updateReward(
                eventId: eventId, rewardId: giftId, fields: ["pointCost": pointCost]
            )
            BQDesign.Haptics.selection()
        } catch {
            logger.error("Repricing a gift failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't change that price. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }

    /// Applies the move locally first so the row lands where the finger left it, then writes
    /// the whole sequence. The listener will re-sort to the same order a moment later.
    func move(from source: IndexSet, to destination: Int) async {
        var reordered = gifts
        reordered.move(fromOffsets: source, toOffset: destination)
        gifts = reordered

        let ids = reordered.compactMap(\.id)
        do {
            try await service.setRewardOrder(eventId: eventId, orderedRewardIds: ids)
        } catch {
            logger.error("Reordering gifts failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't save the new order. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }

    func delete(_ gift: Reward) async {
        guard !isPerformingAction else { return }
        guard let giftId = gift.id else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await service.deleteReward(eventId: eventId, rewardId: giftId)
            actionResult = AdminActionResult(
                message: "Deleted \(gift.fromName)'s gift.", isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            logger.error("Deleting a gift failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't delete that gift. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
            return
        }

        // The Firestore doc — the source of truth and the counter — is already gone. A
        // media gift's Storage objects are purged best-effort: a failure here must not read
        // as a failed deletion, since there is nothing left to roll back. Orphans fall to
        // the GCS lifecycle backstop.
        let paths = (gift.contentUrls ?? []) + [gift.contentUrl].compactMap { $0 }
        guard !paths.isEmpty else { return }
        do {
            try await service.deleteRewardMedia(eventId: eventId, storagePaths: paths)
        } catch {
            logger.error("Purging gift media failed: \(error.localizedDescription)")
        }
    }

    /// Safety net for the non-idempotent totalRewards counter. A re-issued delete drives the counter
    /// below the true count, and checkFinalBadge gates on totalRewards > 0, so drift silently kills the
    /// final celebration. When the listener holds a delivered snapshot and the stored counter disagrees
    /// with the observed count, write the correct absolute value. Idempotent; re-runs on the next
    /// snapshot, so a transient wrong value self-corrects. Writing state/main does not re-trigger the
    /// rewards listener, so there is no loop.
    func reconcileCounter(storedTotal: Int) async {
        guard contentState == .ready || contentState == .empty else { return }
        let observed = gifts.count
        guard observed != storedTotal else { return }
        do {
            try await service.updateGameState(eventId: eventId, fields: ["totalRewards": observed])
            logger.info("Reconciled totalRewards \(storedTotal) -> \(observed)")
        } catch {
            logger.error("Counter reconcile failed: \(error.localizedDescription)")
        }
    }
}
