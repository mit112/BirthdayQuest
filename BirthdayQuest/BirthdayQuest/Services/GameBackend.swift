import Foundation

// MARK: - GameBackend

/// The backend surface the app actually depends on.
///
/// Every ViewModel talks to this rather than to `FirestoreService` directly, so tests can
/// substitute `MockGameBackend` and exercise view-model logic without a live Firebase project.
///
/// Deliberately expresses no Firestore types — only Swift primitives and app models. That is
/// what makes it substitutable. The one leak is `updateGameState(_:)` and
/// `updateSecretChallenge(_:data:)`, which take `[String: Any]` dictionaries that in practice
/// contain `FieldValue.increment(...)` sentinels. A mock can record those calls but cannot
/// evaluate them.
///
/// **What this protocol does not buy you:** the atomic transaction logic lives inside
/// `FirestoreService` itself (`unlockRewardAtomically`, `completeChallengeAtomically`,
/// `adminForceUnlockReward`). Swapping in a mock replaces that logic rather than testing it.
/// Verifying the balance re-check and idempotency guards requires the Firebase emulator suite.
protocol GameBackend: AnyObject {

    // MARK: Listener Management

    func removeListener(forKey key: String)
    func removeAllListeners()

    // MARK: Users

    func listenToUsers(completion: @escaping (Result<[BQUser], Error>) -> Void)
    func claimCharacter(characterId: String, deviceId: String) async throws
    func fetchUser(characterId: String) async throws -> BQUser?
    func unclaimCharacter(characterId: String) async throws

    // MARK: Rewards

    func listenToRewards(completion: @escaping (Result<[Reward], Error>) -> Void)
    func fetchReward(byId id: String) async throws -> Reward?
    func unlockReward(rewardId: String) async throws
    func unlockRewardAtomically(
        rewardId: String,
        pointCost: Int,
        timelineEvent: TimelineEvent
    ) async throws

    // MARK: Challenges

    func listenToChallenges(
        listenerKey: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    )
    func fetchChallenge(byId id: String) async throws -> Challenge?
    func completeChallenge(
        challengeId: String,
        proofUrl: String?,
        proofType: String?,
        proofText: String?
    ) async throws
    func completeChallengeAtomically(
        challengeId: String,
        pointValue: Int,
        isSecret: Bool,
        proofUrl: String?,
        proofType: String?,
        proofText: String?,
        timelineEvent: TimelineEvent
    ) async throws
    func createSecretChallenge(_ challenge: Challenge) async throws -> String
    func updateSecretChallenge(challengeId: String, data: [String: Any]) async throws

    // MARK: Timeline

    func listenToTimeline(completion: @escaping (Result<[TimelineEvent], Error>) -> Void)
    func addTimelineEvent(_ event: TimelineEvent) async throws

    // MARK: Game State

    func listenToGameState(completion: @escaping (Result<GameState, Error>) -> Void)
    func updateGameState(_ fields: [String: Any]) async throws
    func earnPoints(amount: Int) async throws
    func spendPoints(amount: Int) async throws
    func checkFinalBadge() async throws
    func incrementSecretChallengesCompleted() async throws

    // MARK: Storage

    func uploadProofData(_ data: Data, path: String) async throws -> String

    // MARK: Admin

    func adminForceUnlockReward(
        rewardId: String,
        pointCost: Int,
        deductPoints: Bool,
        timelineEvent: TimelineEvent
    ) async throws
}

// MARK: - Default Arguments

/// `listenToChallenges` carries a default listener key on the concrete type. Protocol
/// requirements cannot declare default arguments, so it is restated here to keep the
/// existing call sites that omit the key compiling unchanged.
extension GameBackend {
    func listenToChallenges(completion: @escaping (Result<[Challenge], Error>) -> Void) {
        listenToChallenges(listenerKey: "challenges", completion: completion)
    }
}
