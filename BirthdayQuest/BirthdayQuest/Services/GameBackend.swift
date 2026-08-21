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
/// `updateSecretChallenge(eventId:challengeId:data:)`, which take `[String: Any]` dictionaries
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
    /// shares both in one deep link. `mode` must match the code recorded on the event
    /// document or the rules reject the write.
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

    // MARK: Rewards

    func listenToRewards(eventId: String, completion: @escaping (Result<[Reward], Error>) -> Void)
    func fetchReward(eventId: String, rewardId: String) async throws -> Reward?
    func unlockRewardAtomically(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        timelineEvent: TimelineEvent
    ) async throws

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
    func createSecretChallenge(eventId: String, challenge: Challenge) async throws -> String
    func updateSecretChallenge(
        eventId: String,
        challengeId: String,
        data: [String: Any]
    ) async throws

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

    func listenToChallenges(
        eventId: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    ) {
        listenToChallenges(eventId: eventId, listenerKey: "challenges", completion: completion)
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

    var errorDescription: String? {
        switch self {
        case .notSignedIn:         return "You're not signed in yet."
        case .invalidCode:         return "That invite code doesn't match this occasion."
        case .couldNotReserveCode: return "Couldn't create an invite code. Try again."
        }
    }
}
