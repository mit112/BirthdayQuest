import Foundation
import SwiftUI
import Combine
import OSLog

// MARK: - Challenge Draft

/// The editable shape of a challenge, separate from `Challenge` itself.
///
/// `Challenge` is almost entirely `let` and carries gameplay state (`isCompleted`, proof
/// fields) an author has no business setting. A draft holds only what the form edits, which
/// is also what makes `contentFields` provably free of gameplay keys — the rules reject a
/// write that mixes the two, so this is not a stylistic preference.
struct ChallengeDraft: Equatable {
    var title = ""
    var description = ""
    var pointValue = 50
    var difficulty: ChallengeDifficulty = .medium
    var category: ChallengeCategory = .social
    var symbol = ChallengeSymbolCatalog.fallback
    var hasOptionB = false
    var optionBTitle = ""
    var optionBDescription = ""

    init() {}

    init(from challenge: Challenge) {
        title = challenge.title
        description = challenge.description
        pointValue = challenge.pointValue
        difficulty = challenge.difficulty
        category = challenge.category
        symbol = ChallengeSymbolCatalog.resolved(challenge.illustrationAsset)
        hasOptionB = !(challenge.optionBTitle ?? "").isEmpty
        optionBTitle = challenge.optionBTitle ?? ""
        optionBDescription = challenge.optionBDescription ?? ""
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool { !trimmedTitle.isEmpty && !trimmedDescription.isEmpty }

    /// Content keys only. Never a gameplay key — the rules deny a mixed write, which is what
    /// stops a member smuggling a point-value change inside a completion.
    var contentFields: [String: Any] {
        [
            "title": trimmedTitle,
            "description": trimmedDescription,
            "pointValue": pointValue,
            "difficulty": difficulty.rawValue,
            "category": category.rawValue,
            "illustrationAsset": symbol,
            "optionBTitle": hasOptionB ? optionBTitle : "",
            "optionBDescription": hasOptionB ? optionBDescription : "",
        ]
    }

    /// `isDelivered: true` because a host-authored challenge is live the moment it is saved.
    /// Only a contributor's dare is held back for a separate "deliver" step.
    func newChallenge(authorUid: String) -> Challenge {
        Challenge(
            title: trimmedTitle,
            description: trimmedDescription,
            illustrationAsset: symbol,
            pointValue: pointValue,
            difficulty: difficulty,
            category: category,
            isSecret: false,
            createdByUserId: authorUid,
            isDelivered: true,
            isCompleted: false,
            completedAt: nil,
            proofUrl: nil,
            proofType: nil,
            proofText: nil,
            createdAt: Date(),
            optionBTitle: hasOptionB ? optionBTitle : nil,
            optionBDescription: hasOptionB ? optionBDescription : nil
        )
    }
}

// MARK: - Challenge Authoring View Model

@MainActor
final class ChallengeAuthoringViewModel: ObservableObject {

    @Published private(set) var challenges: [Challenge] = []
    @Published private(set) var contentState: ContentState = .loading
    @Published var draft = ChallengeDraft()
    @Published var isEditorPresented = false
    @Published var challengeToDelete: Challenge?
    @Published var actionResult: AdminActionResult?
    @Published var isPerformingAction = false
    /// Set the first time Save is pressed on an invalid draft, which is what reveals the
    /// inline field errors. Save is never disabled: a greyed-out button with no explanation
    /// is indistinguishable from a broken one.
    @Published var showValidation = false

    /// nil while creating, the document id while editing. The editor renders from `draft`
    /// either way, so this is the only thing distinguishing the two modes.
    private(set) var editingId: String?

    private let service: GameBackend
    private let eventId: String
    private let listenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Authoring")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.authoringChallenges(eventId)
    }

    /// Host-authored challenges only. A contributor's secret dare belongs to them — the host
    /// can still force-complete or delete it from the existing host panel, but editing
    /// someone else's dare is not what this screen is for, and the rules would refuse.
    private var authorable: [Challenge] { challenges.filter { !$0.isSecret } }

    var visibleChallenges: [Challenge] {
        authorable.sorted { $0.pointValue < $1.pointValue }
    }

    var isEditing: Bool { editingId != nil }

    // MARK: Listener

    func startListening() {
        service.listenToChallenges(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let challenges):
                    self.challenges = challenges
                    self.contentState = self.authorable.isEmpty ? .empty : .ready
                case .failure(let error):
                    self.logger.error("Authoring listener: \(error.localizedDescription)")
                    self.challenges = []
                    self.contentState = .failed("Couldn't load this occasion's challenges.")
                }
            }
        }
    }

    func stopListening() {
        service.removeListener(forKey: listenerKey)
    }

    // MARK: Editor lifecycle

    func beginCreating() {
        editingId = nil
        draft = ChallengeDraft()
        showValidation = false
        isEditorPresented = true
    }

    func beginEditing(_ challenge: Challenge) {
        editingId = challenge.id
        draft = ChallengeDraft(from: challenge)
        showValidation = false
        isEditorPresented = true
    }

    // MARK: Writes

    /// Never gated behind a disabled button. An invalid draft reveals its field errors and
    /// returns; a valid one writes.
    func save(authorUid: String) async {
        guard !isPerformingAction else { return }
        guard draft.isValid else {
            showValidation = true
            BQDesign.Haptics.error()
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            if let editingId {
                try await service.updateChallenge(
                    eventId: eventId, challengeId: editingId, fields: draft.contentFields
                )
            } else {
                _ = try await service.createChallenge(
                    eventId: eventId, challenge: draft.newChallenge(authorUid: authorUid)
                )
            }
            isEditorPresented = false
            actionResult = AdminActionResult(
                message: isEditing ? "Saved your changes." : "Added \"\(draft.title)\".",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            logger.error("Saving a challenge failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't save that challenge. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }

    func delete(_ challenge: Challenge) async {
        guard !isPerformingAction else { return }
        guard let challengeId = challenge.id else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await service.deleteChallenge(eventId: eventId, challengeId: challengeId)
            actionResult = AdminActionResult(
                message: "Deleted \"\(challenge.title)\".", isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            logger.error("Deleting a challenge failed: \(error.localizedDescription)")
            actionResult = AdminActionResult(
                message: "Couldn't delete that challenge. \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
    }

    /// Safety net for the non-idempotent counter. A re-issued delete (double tap, a retry after a
    /// timeout) drives totalChallenges below the true count, and checkFinalBadge gates on
    /// totalChallenges > 0, so drift silently kills the final celebration. When the listener holds a
    /// delivered snapshot and the stored counter disagrees with the observed count, write the correct
    /// absolute value. Idempotent, and it re-runs on the next snapshot, so a transient wrong value
    /// self-corrects. Writing state/main does not re-trigger the challenges listener, so there is no loop.
    func reconcileCounter(storedTotal: Int) async {
        guard contentState == .ready || contentState == .empty else { return }  // only a delivered snapshot
        let observed = challenges.count
        guard observed != storedTotal else { return }
        do {
            try await service.updateGameState(eventId: eventId, fields: ["totalChallenges": observed])
            logger.info("Reconciled totalChallenges \(storedTotal) -> \(observed)")
        } catch {
            logger.error("Counter reconcile failed: \(error.localizedDescription)")
        }
    }
}
