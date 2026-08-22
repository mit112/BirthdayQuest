import Foundation

// MARK: - GameBackend

/// The backend surface the app depends on.
///
/// Every method is scoped to an `eventId` because every document lives under
/// `events/{eventId}`. That parameter is not ceremony — it is the tenant boundary, and
/// omitting it is not expressible.
///
/// Deliberately expresses no Firestore types — only Swift primitives and app models. That is
/// what makes it substitutable. The one leak is `updateGameState(eventId:fields:)` and
/// `updateChallenge(eventId:challengeId:fields:)`, which take `[String: Any]` dictionaries
/// that in practice contain `FieldValue.increment(...)` sentinels. A mock can record those
/// calls but cannot evaluate them.
///
/// The atomic transaction bodies still live inside `FirestoreService`
/// (`unlockRewardAtomically`, `completeChallengeAtomically`, `adminForceUnlockReward`), so
/// `MockGameBackend` replaces that logic rather than verifying it. The emulator suite in
/// `firebase-tests/` is what actually tests it.
protocol GameBackend: AnyObject {

    // MARK: Listener Management

    func removeListener(forKey key: String)
    func removeAllListeners()

    // MARK: Occasions

    /// Two-phase by necessity: rules for batched writes evaluate against committed state,
    /// so the event document must exist before its participant document can be validated.
    /// Returns the new event id.
    ///
    /// `hostMode` is the host's own way of playing. A host who is also the celebrant is a
    /// case the design calls for, and participant `mode` is immutable once written, so it
    /// has to be decided here or not at all.
    func createOccasion(
        name: String,
        occasionType: OccasionType,
        celebrantName: String,
        occasionDate: Date,
        hostName: String,
        hostAvatarId: String,
        hostMode: ParticipantMode
    ) async throws -> String

    /// Self-registers the caller into an occasion and mirrors the membership.
    ///
    /// Takes `eventId` *and* `code` because `inviteCodes` cannot be listed: a client cannot
    /// enumerate its way to one, which is what prevents codes being harvested. The host
    /// shares both in one deep link. `mode` must match the code recorded in the occasion's
    /// `private/codes` document or the rules reject the write.
    func joinOccasion(
        eventId: String,
        code: String,
        name: String,
        avatarId: String,
        mode: ParticipantMode
    ) async throws

    func fetchMyOccasions() async throws -> [Occasion]
    func fetchOccasion(eventId: String) async throws -> Occasion?
    func fetchParticipants(eventId: String) async throws -> [Participant]
    func fetchMyParticipant(eventId: String) async throws -> Participant?
    func setOccasionOpen(eventId: String, isOpen: Bool) async throws

    /// The occasion's two invite codes, read from `events/{eventId}/private/codes`.
    ///
    /// A method of its own rather than two more fields on `Occasion`, because only the host
    /// can read that document and only the host ever needs it. Folding it into
    /// `fetchOccasion` would spend a second read on every member opening any occasion, and
    /// that read would be denied for all of them.
    ///
    /// Returns nil when the caller is not the host or the document is missing.
    func fetchInviteCodes(eventId: String) async throws -> InviteCodes?

    /// Blanks `celebrantCode` in `events/{eventId}/private/codes` so the celebrant invite
    /// cannot be replayed. Deliberately a standalone write, not part of the join batch: the
    /// rule that permits it `get()`s the caller's participant document, and Firestore
    /// evaluates batched writes against committed state, so the participant must already
    /// exist. Idempotent — re-clearing an already-empty code produces an empty diff, which
    /// the rule accepts, which is what lets the celebrant's next app open retry a first
    /// attempt that failed. The celebrant cannot *read* that document, so retrying
    /// unconditionally is the only option available to them.
    func consumeCelebrantCode(eventId: String) async throws

    /// Resolves an invite code to the occasion it belongs to and the mode it authorises.
    /// Returns nil when no such code exists.
    ///
    /// Lives on the backend seam rather than in the join view model because it is the sole
    /// determinant of `mode` for a deep link — a celebrant link is textually identical to a
    /// contributor one — and a rule that can only be exercised against a live Firestore is a
    /// rule nothing tests. `inviteCodes/{CODE}` is `allow get` / deny `list`: resolving a
    /// code you already hold is what a code is for, but the collection cannot be enumerated.
    func resolveInviteCode(_ code: String) async throws -> (eventId: String, kind: String)?

    // MARK: Rewards

    /// `listenerKey` mirrors `listenToChallenges`: two screens can watch the same
    /// occasion's rewards at once (a host who is also the celebrant sees both the carousel
    /// and the host panel), and each must be able to release its own subscription without
    /// cancelling the other's.
    func listenToRewards(
        eventId: String,
        listenerKey: String,
        completion: @escaping (Result<[Reward], Error>) -> Void
    )
    func fetchReward(eventId: String, rewardId: String) async throws -> Reward?
    func unlockRewardAtomically(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        timelineEvent: TimelineEvent
    ) async throws

    /// Creates a gift and increments the occasion's gift counter in one batch.
    ///
    /// `reward.fromUserId` must be the calling uid unless the caller is the host: it is the
    /// field the content-edit rule reads to decide who may edit this gift later.
    func createReward(eventId: String, reward: Reward) async throws -> String

    /// Partial edit. `fields` must contain only content keys, only `pointCost`/`sortOrder`,
    /// or only gameplay keys — the rules reject a mixture, and the three tiers have
    /// different audiences.
    func updateReward(eventId: String, rewardId: String, fields: [String: Any]) async throws

    /// Deletes a gift and decrements the counter in one batch. Host-only at the rules layer.
    ///
    /// The decrement is relative, not idempotent: Firestore's delete on an already-missing
    /// document succeeds silently, but the paired decrement does not, so a repeated delete of
    /// the same id decrements `totalRewards` again. Callers must not re-issue a delete for an
    /// id they have already deleted.
    func deleteReward(eventId: String, rewardId: String) async throws

    /// Rewrites `sortOrder` across the whole list to match the given order, in one batch.
    /// Host-only at the rules layer, because `sortOrder` is host-only.
    ///
    /// The caller must pass every gift id in the occasion, in the intended order. This writes
    /// index 0...n-1 only for the ids given, so passing a subset assigns those rows 0...n-1
    /// and collides with whatever gift was left out.
    func setRewardOrder(eventId: String, orderedRewardIds: [String]) async throws

    // MARK: Challenges

    func listenToChallenges(
        eventId: String,
        listenerKey: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    )
    func fetchChallenge(eventId: String, challengeId: String) async throws -> Challenge?
    func completeChallengeAtomically(
        eventId: String,
        challengeId: String,
        pointValue: Int,
        isSecret: Bool,
        proofUrl: String?,
        proofType: String?,
        proofText: String?,
        timelineEvent: TimelineEvent
    ) async throws
    /// Creates a challenge. The caller supplies the whole `Challenge`, including `isSecret`
    /// and `createdByUserId` — this method has never enforced either, and the rules do.
    ///
    /// `createdByUserId` must be the calling uid or the write is denied: it is the field the
    /// content-edit rule reads to decide who may edit this challenge later.
    func createChallenge(eventId: String, challenge: Challenge) async throws -> String

    /// Partial edit. `fields` must contain only content fields (`title`, `description`,
    /// `pointValue`, `difficulty`, `category`, `illustrationAsset`, `isDelivered`,
    /// `optionBTitle`, `optionBDescription`) or only gameplay fields — the rules reject a
    /// mixture, because a gameplay write that also carries a point value is how a member
    /// would smuggle an edit past the author check.
    func updateChallenge(
        eventId: String,
        challengeId: String,
        fields: [String: Any]
    ) async throws

    /// Deletes a challenge and decrements the occasion's challenge counter in one batch.
    /// Host-only at the rules layer.
    ///
    /// The decrement is relative, not idempotent: Firestore's delete on an already-missing
    /// document succeeds silently, but the paired decrement does not, so a repeated delete of
    /// the same id decrements `totalChallenges` again. Callers must not re-issue a delete for
    /// an id they have already deleted.
    func deleteChallenge(eventId: String, challengeId: String) async throws

    // MARK: Timeline

    func listenToTimeline(
        eventId: String,
        completion: @escaping (Result<[TimelineEvent], Error>) -> Void
    )
    func addTimelineEvent(eventId: String, event: TimelineEvent) async throws

    // MARK: Game State

    func listenToGameState(eventId: String, completion: @escaping (Result<GameState, Error>) -> Void)
    func updateGameState(eventId: String, fields: [String: Any]) async throws
    func earnPoints(eventId: String, amount: Int) async throws
    func spendPoints(eventId: String, amount: Int) async throws
    func checkFinalBadge(eventId: String) async throws
    func incrementSecretChallengesCompleted(eventId: String) async throws

    // MARK: Storage

    /// `contentType` is required, not optional. The Storage rules demand a usable content
    /// type, and `putData` does not infer one from the path — omitting it was the audit's
    /// suspected cause of every proof upload failing with 403.
    func uploadProofData(
        eventId: String,
        challengeId: String,
        data: Data,
        contentType: String
    ) async throws -> String

    // MARK: Admin

    func adminForceUnlockReward(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        deductPoints: Bool,
        timelineEvent: TimelineEvent
    ) async throws
}

// MARK: - Default Arguments

/// Protocol requirements cannot declare default arguments, so the two that have one are
/// restated here as convenience overloads.
extension GameBackend {

    func listenToRewards(
        eventId: String,
        completion: @escaping (Result<[Reward], Error>) -> Void
    ) {
        listenToRewards(
            eventId: eventId,
            listenerKey: ListenerKey.rewards(eventId),
            completion: completion
        )
    }

    func listenToChallenges(
        eventId: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    ) {
        listenToChallenges(
            eventId: eventId,
            listenerKey: ListenerKey.challenges(eventId),
            completion: completion
        )
    }

    func createOccasion(
        name: String,
        occasionType: OccasionType,
        celebrantName: String,
        occasionDate: Date,
        hostName: String,
        hostAvatarId: String
    ) async throws -> String {
        try await createOccasion(
            name: name,
            occasionType: occasionType,
            celebrantName: celebrantName,
            occasionDate: occasionDate,
            hostName: hostName,
            hostAvatarId: hostAvatarId,
            hostMode: .contributor
        )
    }
}

// MARK: - Errors

/// Failures the backend raises itself, as opposed to the ones Firestore raises. Every case
/// is something a person can act on, which is why they all carry user-facing copy.
enum BackendError: LocalizedError {
    case notSignedIn
    case invalidCode
    case couldNotReserveCode
    /// An event id that cannot legally be a Firestore document id. Thrown rather than used,
    /// because using it means interpolating it into a path, and the SDK answers a malformed
    /// path with an Objective-C exception that kills the process instead of an error a
    /// `catch` can see.
    case invalidEventId

    var errorDescription: String? {
        switch self {
        case .notSignedIn:         return "You're not signed in yet."
        case .invalidCode:         return "That invite code doesn't match this occasion."
        case .couldNotReserveCode: return "Couldn't create an invite code. Try again."
        case .invalidEventId:      return "That invite link doesn't point to a real occasion."
        }
    }
}
