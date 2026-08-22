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
    /// Every key a listener was registered under. Paired with `removedListenerKeys`, this
    /// is what lets a test prove two screens can watch the same collection at once and that
    /// one leaving does not cancel the other.
    private(set) var registeredListenerKeys: [String] = []
    private(set) var unlockedRewardIds: [String] = []
    private(set) var completedChallengeIds: [String] = []
    /// Every `eventId` the backend was asked for, in order. Lets a test prove a view model
    /// scoped its calls to the occasion it was given rather than to some ambient default.
    private(set) var requestedEventIds: [String] = []
    private(set) var createdOccasions: [(name: String, type: OccasionType, hostMode: ParticipantMode)] = []
    private(set) var joinedOccasions: [(eventId: String, code: String, mode: ParticipantMode)] = []
    private(set) var openStateChanges: [(eventId: String, isOpen: Bool)] = []

    func called(_ name: String) -> Bool { calls.contains(name) }
    func callCount(_ name: String) -> Int { calls.filter { $0 == name }.count }

    // MARK: Stubs

    var rewards: [Reward] = []
    var challenges: [Challenge] = []
    var timeline: [TimelineEvent] = []
    var gameState: GameState?
    var stubOccasions: [Occasion] = []
    var stubParticipants: [Participant] = []
    var stubbedOccasion: Occasion?
    var stubbedParticipant: Participant?
    var stubbedChallenge: Challenge?
    var stubbedReward: Reward?
    var stubbedUploadUrl = "https://example.com/upload.jpg"
    var stubbedSecretChallengeId = "secret-1"
    var stubbedCreatedEventId = "evt_mock"

    /// When set, every `async throws` method throws this instead of succeeding.
    var errorToThrow: Error?

    /// When set, every listener reports this failure instead of data. Lets tests exercise
    /// the permission-denied path that the real backend produces when membership is revoked.
    var listenerFailure: Error?

    private func throwIfNeeded() throws {
        if let errorToThrow { throw errorToThrow }
    }

    private func record(_ name: String, eventId: String) {
        calls.append(name)
        requestedEventIds.append(eventId)
    }

    // MARK: Captured listener callbacks
    //
    // Held so a test can drive a listener manually: call startListening(), then invoke
    // emitRewards(...) to simulate a Firestore snapshot arriving.

    // Rewards and challenges are held per listener key, because both are legitimately
    // watched by two screens of one occasion at once. Emitting reaches every live handler,
    // so a test can prove that releasing one key leaves the other still receiving.
    private var rewardsHandlers: [String: (Result<[Reward], Error>) -> Void] = [:]
    private var challengesHandlers: [String: (Result<[Challenge], Error>) -> Void] = [:]
    private var timelineHandler: ((Result<[TimelineEvent], Error>) -> Void)?
    private var gameStateHandler: ((Result<GameState, Error>) -> Void)?

    func emitRewards(_ value: [Reward]) { rewardsHandlers.values.forEach { $0(.success(value)) } }
    func emitChallenges(_ value: [Challenge]) { challengesHandlers.values.forEach { $0(.success(value)) } }
    func emitTimeline(_ value: [TimelineEvent]) { timelineHandler?(.success(value)) }
    func emitGameState(_ value: GameState) { gameStateHandler?(.success(value)) }

    /// Listener keys still receiving emissions.
    var liveListenerKeys: Set<String> {
        Set(rewardsHandlers.keys).union(challengesHandlers.keys)
    }

    // MARK: - GameBackend: Listener Management

    func removeListener(forKey key: String) {
        calls.append("removeListener")
        removedListenerKeys.append(key)
        rewardsHandlers.removeValue(forKey: key)
        challengesHandlers.removeValue(forKey: key)
    }

    func removeAllListeners() {
        calls.append("removeAllListeners")
    }

    // MARK: - GameBackend: Occasions

    func createOccasion(
        name: String,
        occasionType: OccasionType,
        celebrantName: String,
        occasionDate: Date,
        hostName: String,
        hostAvatarId: String,
        hostMode: ParticipantMode
    ) async throws -> String {
        calls.append("createOccasion")
        try throwIfNeeded()
        createdOccasions.append((name, occasionType, hostMode))
        return stubbedCreatedEventId
    }

    func joinOccasion(
        eventId: String,
        code: String,
        name: String,
        avatarId: String,
        mode: ParticipantMode
    ) async throws {
        record("joinOccasion", eventId: eventId)
        try throwIfNeeded()
        joinedOccasions.append((eventId, code, mode))
    }

    func fetchMyOccasions() async throws -> [Occasion] {
        calls.append("fetchMyOccasions")
        try throwIfNeeded()
        return stubOccasions
    }

    func fetchOccasion(eventId: String) async throws -> Occasion? {
        record("fetchOccasion", eventId: eventId)
        try throwIfNeeded()
        return stubbedOccasion ?? stubOccasions.first { $0.id == eventId }
    }

    func fetchParticipants(eventId: String) async throws -> [Participant] {
        record("fetchParticipants", eventId: eventId)
        try throwIfNeeded()
        return stubParticipants
    }

    func fetchMyParticipant(eventId: String) async throws -> Participant? {
        record("fetchMyParticipant", eventId: eventId)
        try throwIfNeeded()
        return stubbedParticipant
    }

    func setOccasionOpen(eventId: String, isOpen: Bool) async throws {
        record("setOccasionOpen", eventId: eventId)
        try throwIfNeeded()
        openStateChanges.append((eventId, isOpen))
    }

    func fetchInviteCodes(eventId: String) async throws -> InviteCodes? {
        record("fetchInviteCodes", eventId: eventId)
        try throwIfNeeded()
        return stubbedInviteCodes
    }

    /// Stub for `fetchInviteCodes`. Defaults to nil, which is what a non-host actually gets.
    var stubbedInviteCodes: InviteCodes?

    func resolveInviteCode(_ code: String) async throws -> (eventId: String, kind: String)? {
        calls.append("resolveInviteCode")
        resolvedCodes.append(code)
        try throwIfNeeded()
        return stubbedCodeResolution
    }

    /// Stub for `resolveInviteCode`. Defaults to nil so an unstubbed lookup reads as
    /// "no such code" rather than silently succeeding.
    var stubbedCodeResolution: (eventId: String, kind: String)?
    private(set) var resolvedCodes: [String] = []

    func consumeCelebrantCode(eventId: String) async throws {
        record("consumeCelebrantCode", eventId: eventId)
        try throwIfNeeded()
        consumedCelebrantCodes.append(eventId)
    }

    /// Recorded so a test can prove the celebrant invite is retired exactly when it should
    /// be — once on join, and again on reopen only if the first attempt failed.
    private(set) var consumedCelebrantCodes: [String] = []

    // MARK: - GameBackend: Rewards

    func listenToRewards(
        eventId: String,
        listenerKey: String,
        completion: @escaping (Result<[Reward], Error>) -> Void
    ) {
        record("listenToRewards", eventId: eventId)
        registeredListenerKeys.append(listenerKey)
        rewardsHandlers[listenerKey] = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(rewards))
    }

    func fetchReward(eventId: String, rewardId: String) async throws -> Reward? {
        record("fetchReward", eventId: eventId)
        try throwIfNeeded()
        return stubbedReward
    }

    func unlockRewardAtomically(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        timelineEvent: TimelineEvent
    ) async throws {
        record("unlockRewardAtomically", eventId: eventId)
        try throwIfNeeded()
        unlockedRewardIds.append(rewardId)
    }

    func createReward(eventId: String, reward: Reward) async throws -> String {
        record("createReward", eventId: eventId)
        createdRewards.append(reward)
        try throwIfNeeded()
        return stubbedCreatedRewardId
    }

    var stubbedCreatedRewardId = "gift-1"
    /// Every reward a create was attempted for, recorded before `throwIfNeeded()`, so a
    /// stubbed failure still leaves this non-empty. Assert on view-model state for the
    /// failure path, not on this array's absence.
    private(set) var createdRewards: [Reward] = []

    func updateReward(eventId: String, rewardId: String, fields: [String: Any]) async throws {
        record("updateReward", eventId: eventId)
        updatedRewards.append((rewardId, fields))
        try throwIfNeeded()
    }

    /// Every edit attempted, recorded before `throwIfNeeded()`, so a stubbed failure still
    /// leaves this non-empty. Assert on view-model state for the failure path, not on this
    /// array's absence.
    private(set) var updatedRewards: [(id: String, fields: [String: Any])] = []

    func deleteReward(eventId: String, rewardId: String) async throws {
        record("deleteReward", eventId: eventId)
        deletedRewardIds.append(rewardId)
        try throwIfNeeded()
    }

    /// Every id a delete was attempted for, recorded before `throwIfNeeded()`, so a stubbed
    /// failure still leaves this non-empty. Assert on view-model state for the failure path,
    /// not on this array's absence.
    private(set) var deletedRewardIds: [String] = []

    func setRewardOrder(eventId: String, orderedRewardIds: [String]) async throws {
        record("setRewardOrder", eventId: eventId)
        rewardOrders.append(orderedRewardIds)
        try throwIfNeeded()
    }

    /// Every reorder the caller asked for, so a test can assert the resulting sequence
    /// rather than merely that a reorder happened. Recorded before `throwIfNeeded()`, so a
    /// stubbed failure still leaves this non-empty — assert on view-model state for the
    /// failure path, not on this array's absence.
    private(set) var rewardOrders: [[String]] = []

    // MARK: - GameBackend: Challenges

    func listenToChallenges(
        eventId: String,
        listenerKey: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    ) {
        record("listenToChallenges", eventId: eventId)
        registeredListenerKeys.append(listenerKey)
        challengesHandlers[listenerKey] = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(challenges))
    }

    func fetchChallenge(eventId: String, challengeId: String) async throws -> Challenge? {
        record("fetchChallenge", eventId: eventId)
        try throwIfNeeded()
        return stubbedChallenge
    }

    func completeChallengeAtomically(
        eventId: String,
        challengeId: String,
        pointValue: Int,
        isSecret: Bool,
        proofUrl: String?,
        proofType: String?,
        proofText: String?,
        timelineEvent: TimelineEvent
    ) async throws {
        record("completeChallengeAtomically", eventId: eventId)
        try throwIfNeeded()
        completedChallengeIds.append(challengeId)
    }

    func createChallenge(eventId: String, challenge: Challenge) async throws -> String {
        record("createChallenge", eventId: eventId)
        createdChallenges.append(challenge)
        try throwIfNeeded()
        return stubbedSecretChallengeId
    }

    /// Every challenge the caller asked to create, so a test can assert what was stamped on
    /// it — `createdByUserId` in particular, which the rules require to be the caller's uid.
    private(set) var createdChallenges: [Challenge] = []

    func updateChallenge(
        eventId: String,
        challengeId: String,
        fields: [String: Any]
    ) async throws {
        record("updateChallenge", eventId: eventId)
        updatedChallenges.append((challengeId, fields))
        try throwIfNeeded()
    }

    /// Recorded so a test can prove an edit sent only content fields — the rules reject a
    /// write that mixes content and gameplay keys. Recorded before `throwIfNeeded()`, so this
    /// captures every attempted update, not just the ones that succeeded — assert on
    /// view-model state for the failure path, not on this array's absence.
    private(set) var updatedChallenges: [(id: String, fields: [String: Any])] = []

    func deleteChallenge(eventId: String, challengeId: String) async throws {
        record("deleteChallenge", eventId: eventId)
        deletedChallengeIds.append(challengeId)
        try throwIfNeeded()
    }

    /// Every id a delete was attempted for, recorded before `throwIfNeeded()`, so a stubbed
    /// failure still leaves this non-empty. Assert on view-model state for the failure path,
    /// not on this array's absence.
    private(set) var deletedChallengeIds: [String] = []

    // MARK: - GameBackend: Timeline

    func listenToTimeline(
        eventId: String,
        completion: @escaping (Result<[TimelineEvent], Error>) -> Void
    ) {
        record("listenToTimeline", eventId: eventId)
        timelineHandler = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(timeline))
    }

    func addTimelineEvent(eventId: String, event: TimelineEvent) async throws {
        record("addTimelineEvent", eventId: eventId)
        try throwIfNeeded()
    }

    // MARK: - GameBackend: Game State

    func listenToGameState(
        eventId: String,
        completion: @escaping (Result<GameState, Error>) -> Void
    ) {
        record("listenToGameState", eventId: eventId)
        gameStateHandler = completion
        if let listenerFailure {
            completion(.failure(listenerFailure))
            return
        }
        completion(.success(gameState ?? .empty))
    }

    func updateGameState(eventId: String, fields: [String: Any]) async throws {
        record("updateGameState", eventId: eventId)
        try throwIfNeeded()
        updatedGameStateFields.append(fields)
    }

    func earnPoints(eventId: String, amount: Int) async throws {
        record("earnPoints", eventId: eventId)
        try throwIfNeeded()
    }

    func spendPoints(eventId: String, amount: Int) async throws {
        record("spendPoints", eventId: eventId)
        try throwIfNeeded()
    }

    func checkFinalBadge(eventId: String) async throws {
        record("checkFinalBadge", eventId: eventId)
        try throwIfNeeded()
    }

    func incrementSecretChallengesCompleted(eventId: String) async throws {
        record("incrementSecretChallengesCompleted", eventId: eventId)
        try throwIfNeeded()
    }

    // MARK: - GameBackend: Storage

    func uploadProofData(
        eventId: String,
        challengeId: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        record("uploadProofData", eventId: eventId)
        uploadedContentTypes.append(contentType)
        try throwIfNeeded()
        return stubbedUploadUrl
    }

    /// Pinned by `ChallengeSubmissionTests.sendsAnImageContentType`: `putData` with no
    /// metadata uploads as application/octet-stream, which `storage.rules` rejects, and
    /// that 403 was the audit's headline bug.
    private(set) var uploadedContentTypes: [String] = []

    // MARK: - GameBackend: Admin

    func adminForceUnlockReward(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        deductPoints: Bool,
        timelineEvent: TimelineEvent
    ) async throws {
        record("adminForceUnlockReward", eventId: eventId)
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
