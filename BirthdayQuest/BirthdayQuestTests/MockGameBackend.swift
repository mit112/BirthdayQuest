import Foundation
@testable import BirthdayQuest

/// In-memory `GameBackend` for tests.
///
/// Records every call so tests can assert what a view model asked the backend to do, and lets
/// each method be stubbed to succeed with a value or throw.
///
/// Not thread-safe, and does not need to be: view models are `@MainActor`, so every call
/// arrives on the main actor.
final class MockGameBackend: GameBackend {

    struct StubbedError: Error, Equatable {
        let message: String
        init(_ message: String = "stubbed failure") { self.message = message }
    }

    // MARK: Recorded calls

    /// Every method name invoked, in order.
    private(set) var calls: [String] = []
    private(set) var updatedGameStateFields: [[String: Any]] = []
    private(set) var removedListenerKeys: [String] = []
    private(set) var unlockedRewardIds: [String] = []
    private(set) var completedChallengeIds: [String] = []

    func called(_ name: String) -> Bool { calls.contains(name) }
    func callCount(_ name: String) -> Int { calls.filter { $0 == name }.count }

    // MARK: Stubs

    var users: [BQUser] = []
    var rewards: [Reward] = []
    var challenges: [Challenge] = []
    var timeline: [TimelineEvent] = []
    var gameState: GameState?
    var stubbedUser: BQUser?
    var stubbedChallenge: Challenge?
    var stubbedReward: Reward?
    var stubbedUploadUrl = "https://example.com/upload.jpg"
    var stubbedSecretChallengeId = "secret-1"

    /// When set, every `async throws` method throws this instead of succeeding.
    var errorToThrow: Error?

    /// When set, every listener reports this failure instead of data. Lets tests exercise
    /// the permission-denied path that the real backend produces when membership is revoked.
    var listenerFailure: Error?

    private func throwIfNeeded() throws {
        if let errorToThrow { throw errorToThrow }
    }

    // MARK: Captured listener callbacks
    //
    // Held so a test can drive a listener manually: call startListening(), then invoke
    // emitRewards(...) to simulate a Firestore snapshot arriving.

    private var usersHandler: ((Result<[BQUser], Error>) -> Void)?
    private var rewardsHandler: ((Result<[Reward], Error>) -> Void)?
    private var challengesHandler: ((Result<[Challenge], Error>) -> Void)?
    private var timelineHandler: ((Result<[TimelineEvent], Error>) -> Void)?
    private var gameStateHandler: ((Result<GameState, Error>) -> Void)?

    func emitUsers(_ value: [BQUser]) { usersHandler?(.success(value)) }
    func emitRewards(_ value: [Reward]) { rewardsHandler?(.success(value)) }
    func emitChallenges(_ value: [Challenge]) { challengesHandler?(.success(value)) }
    func emitTimeline(_ value: [TimelineEvent]) { timelineHandler?(.success(value)) }
    func emitGameState(_ value: GameState) { gameStateHandler?(.success(value)) }

    // MARK: - GameBackend: Listener Management

    func removeListener(forKey key: String) {
        calls.append("removeListener")
        removedListenerKeys.append(key)
    }

    func removeAllListeners() {
        calls.append("removeAllListeners")
    }

    // MARK: - GameBackend: Users

    func listenToUsers(completion: @escaping (Result<[BQUser], Error>) -> Void) {
        calls.append("listenToUsers")
        usersHandler = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(users))
    }

    func claimCharacter(characterId: String, deviceId: String) async throws {
        calls.append("claimCharacter")
        try throwIfNeeded()
    }

    func fetchUser(characterId: String) async throws -> BQUser? {
        calls.append("fetchUser")
        try throwIfNeeded()
        return stubbedUser
    }

    func unclaimCharacter(characterId: String) async throws {
        calls.append("unclaimCharacter")
        try throwIfNeeded()
    }

    // MARK: - GameBackend: Rewards

    func listenToRewards(completion: @escaping (Result<[Reward], Error>) -> Void) {
        calls.append("listenToRewards")
        rewardsHandler = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(rewards))
    }

    func fetchReward(byId id: String) async throws -> Reward? {
        calls.append("fetchReward")
        try throwIfNeeded()
        return stubbedReward
    }

    func unlockReward(rewardId: String) async throws {
        calls.append("unlockReward")
        try throwIfNeeded()
        unlockedRewardIds.append(rewardId)
    }

    func unlockRewardAtomically(
        rewardId: String,
        pointCost: Int,
        timelineEvent: TimelineEvent
    ) async throws {
        calls.append("unlockRewardAtomically")
        try throwIfNeeded()
        unlockedRewardIds.append(rewardId)
    }

    // MARK: - GameBackend: Challenges

    func listenToChallenges(
        listenerKey: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    ) {
        calls.append("listenToChallenges")
        challengesHandler = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(challenges))
    }

    func fetchChallenge(byId id: String) async throws -> Challenge? {
        calls.append("fetchChallenge")
        try throwIfNeeded()
        return stubbedChallenge
    }

    func completeChallenge(
        challengeId: String,
        proofUrl: String?,
        proofType: String?,
        proofText: String?
    ) async throws {
        calls.append("completeChallenge")
        try throwIfNeeded()
        completedChallengeIds.append(challengeId)
    }

    func completeChallengeAtomically(
        challengeId: String,
        pointValue: Int,
        isSecret: Bool,
        proofUrl: String?,
        proofType: String?,
        proofText: String?,
        timelineEvent: TimelineEvent
    ) async throws {
        calls.append("completeChallengeAtomically")
        try throwIfNeeded()
        completedChallengeIds.append(challengeId)
    }

    func createSecretChallenge(_ challenge: Challenge) async throws -> String {
        calls.append("createSecretChallenge")
        try throwIfNeeded()
        return stubbedSecretChallengeId
    }

    func updateSecretChallenge(challengeId: String, data: [String: Any]) async throws {
        calls.append("updateSecretChallenge")
        try throwIfNeeded()
    }

    // MARK: - GameBackend: Timeline

    func listenToTimeline(completion: @escaping (Result<[TimelineEvent], Error>) -> Void) {
        calls.append("listenToTimeline")
        timelineHandler = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(timeline))
    }

    func addTimelineEvent(_ event: TimelineEvent) async throws {
        calls.append("addTimelineEvent")
        try throwIfNeeded()
    }

    // MARK: - GameBackend: Game State

    func listenToGameState(completion: @escaping (Result<GameState, Error>) -> Void) {
        calls.append("listenToGameState")
        gameStateHandler = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(gameState ?? .empty))
    }

    func updateGameState(_ fields: [String: Any]) async throws {
        calls.append("updateGameState")
        try throwIfNeeded()
        updatedGameStateFields.append(fields)
    }

    func earnPoints(amount: Int) async throws {
        calls.append("earnPoints")
        try throwIfNeeded()
    }

    func spendPoints(amount: Int) async throws {
        calls.append("spendPoints")
        try throwIfNeeded()
    }

    func checkFinalBadge() async throws {
        calls.append("checkFinalBadge")
        try throwIfNeeded()
    }

    func incrementSecretChallengesCompleted() async throws {
        calls.append("incrementSecretChallengesCompleted")
        try throwIfNeeded()
    }

    // MARK: - GameBackend: Storage

    func uploadProofData(_ data: Data, path: String) async throws -> String {
        calls.append("uploadProofData")
        try throwIfNeeded()
        return stubbedUploadUrl
    }

    // MARK: - GameBackend: Admin

    func adminForceUnlockReward(
        rewardId: String,
        pointCost: Int,
        deductPoints: Bool,
        timelineEvent: TimelineEvent
    ) async throws {
        calls.append("adminForceUnlockReward")
        try throwIfNeeded()
        unlockedRewardIds.append(rewardId)
    }
}

// MARK: - Fixtures

extension Challenge {
    static func fixture(
        id: String = "c1",
        title: String = "Test Challenge",
        pointValue: Int = 50,
        isSecret: Bool = false,
        createdByUserId: String? = nil,
        isDelivered: Bool = false,
        isCompleted: Bool = false,
        optionBTitle: String? = nil
    ) -> Challenge {
        var challenge = Challenge(
            title: title,
            description: "A test challenge",
            illustrationAsset: "test_badge",
            pointValue: pointValue,
            difficulty: .medium,
            category: .social,
            isSecret: isSecret,
            createdByUserId: createdByUserId,
            isDelivered: isDelivered,
            isCompleted: isCompleted,
            completedAt: nil,
            proofUrl: nil,
            proofType: nil,
            proofText: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            optionBTitle: optionBTitle,
            optionBDescription: optionBTitle == nil ? nil : "Option B"
        )
        challenge.id = id
        return challenge
    }
}

extension Reward {
    static func fixture(
        id: String = "r1",
        fromName: String = "Sam",
        pointCost: Int = 100,
        contentType: RewardContentType = .video,
        contentUrl: String? = nil,
        isUnlocked: Bool = false,
        sortOrder: Int = 1
    ) -> Reward {
        var reward = Reward(
            fromUserId: "u1",
            fromName: fromName,
            title: "A message from \(fromName)",
            teaser: "Teaser",
            pointCost: pointCost,
            contentType: contentType,
            contentUrl: contentUrl,
            contentUrls: nil,
            contentText: nil,
            isUnlocked: isUnlocked,
            unlockedAt: nil,
            sortOrder: sortOrder,
            badgeIllustration: "heart_badge",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        reward.id = id
        return reward
    }
}

extension TimelineEvent {
    static func fixture(
        id: String = "t1",
        type: TimelineEventType = .challengeCompleted,
        referenceId: String = "c1"
    ) -> TimelineEvent {
        var event = TimelineEvent(
            type: type,
            referenceId: referenceId,
            title: "Completed: Test",
            subtitle: "+50 points",
            badgeType: .challenge,
            badgeAsset: "test_badge",
            fromFriendName: nil,
            fromFriendAvatar: nil,
            timestamp: Date(timeIntervalSince1970: 0)
        )
        event.id = id
        return event
    }
}
