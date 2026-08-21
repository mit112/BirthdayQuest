import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import OSLog

// MARK: - FirestoreService

/// Singleton Firestore gateway. All public methods are called from @MainActor contexts.
/// Not marked @MainActor itself because Firestore listener callbacks fire on background threads.
///
/// Every path is rooted at `events/{eventId}`. There is no global collection left, which is
/// what makes reaching another occasion's data unexpressible rather than merely forbidden.
final class FirestoreService: GameBackend {

    static let shared = FirestoreService()

    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Firestore")

    private init() {
        // Settings configured in BirthdayQuestApp.init() before any Firestore access
    }

    // MARK: - Path Helpers

    private func eventRef(_ eventId: String) -> DocumentReference {
        db.collection(Collections.events).document(eventId)
    }

    private func challengesRef(_ eventId: String) -> CollectionReference {
        eventRef(eventId).collection(Collections.challenges)
    }

    private func rewardsRef(_ eventId: String) -> CollectionReference {
        eventRef(eventId).collection(Collections.rewards)
    }

    private func timelineRef(_ eventId: String) -> CollectionReference {
        eventRef(eventId).collection(Collections.timeline)
    }

    private func participantsRef(_ eventId: String) -> CollectionReference {
        eventRef(eventId).collection(Collections.participants)
    }

    private func stateRef(_ eventId: String) -> DocumentReference {
        eventRef(eventId).collection(Collections.state).document(Collections.stateDoc)
    }

    private func membershipRef(uid: String, eventId: String) -> DocumentReference {
        db.collection(Collections.memberships).document(uid)
            .collection(Collections.events).document(eventId)
    }

    private func currentUid() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw BackendError.notSignedIn }
        return uid
    }

    // MARK: - Listener Management

    func removeListener(forKey key: String) {
        listeners[key]?.remove()
        listeners.removeValue(forKey: key)
    }

    func removeAllListeners() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }

    // MARK: - Occasions

    func createOccasion(
        name: String,
        occasionType: OccasionType,
        celebrantName: String,
        occasionDate: Date,
        hostName: String,
        hostAvatarId: String,
        hostMode: ParticipantMode
    ) async throws -> String {
        let uid = try currentUid()

        // The document reference assigns an id locally without writing anything, which
        // lets the codes be minted against the event before the event exists.
        let newEventRef = db.collection(Collections.events).document()
        let eventId = newEventRef.documentID

        // Codes first. Reserving one only requires being signed in, not the event existing.
        let contributorCode = try await reserveCode(eventId: eventId, kind: "contributor")
        let celebrantCode = try await reserveCode(eventId: eventId, kind: "celebrant")

        // Phase 1: the event document, written once and complete. Rules validating the
        // host's participant document call get() on this event, and a batched write cannot
        // see its own siblings — so it must be committed before phase 2.
        try await newEventRef.setData([
            "name": name,
            "occasionType": occasionType.rawValue,
            "celebrantName": celebrantName,
            "hostUid": uid,
            "occasionDate": Timestamp(date: occasionDate),
            "isOpen": true,
            "createdAt": Timestamp(date: Date()),
            "contributorCode": contributorCode,
            "celebrantCode": celebrantCode
        ])

        // Phase 2: host participant, initial game state, membership mirror. All three rules
        // gate on the event's hostUid rather than on membership, precisely so this can be
        // one batch — batched writes are evaluated against committed state, and the
        // participant document that a membership check would look for is created here.
        //
        // If this fails the event document is orphaned — unreadable by every client,
        // because the membership check finds no participant — so it is invisible rather
        // than corrupt.
        let now = Timestamp(date: Date())
        let batch = db.batch()

        batch.setData([
            "name": hostName,
            "avatarId": hostAvatarId,
            "mode": hostMode.rawValue,
            "isHost": true,
            // Inert for the host: the host branch of the participant rule authorises on
            // hostUid, never on the code.
            "usedCode": contributorCode
        ], forDocument: participantsRef(eventId).document(uid))

        batch.setData([
            "totalPointsEarned": 0, "totalPointsSpent": 0, "currentPoints": 0,
            "challengesCompleted": 0, "totalChallenges": 0,
            "secretChallengesFound": 0, "secretChallengesCompleted": 0,
            "rewardsUnlocked": 0, "totalRewards": 0,
            "allRewardsUnlocked": false, "finalBadgeUnlocked": false,
            "currentDay": 1,
            "gameStartedAt": now,
            "updatedAt": now
        ], forDocument: stateRef(eventId))

        batch.setData([
            "role": hostMode.rawValue,
            "isHost": true,
            "joinedAt": now
        ], forDocument: membershipRef(uid: uid, eventId: eventId))

        try await batch.commit()
        logger.info("Created occasion \(eventId)")
        return eventId
    }

    /// Claims an unused code. `allow create` in Firestore only fires when the document does
    /// not exist, so a genuine collision surfaces as permission-denied. Anything else —
    /// offline, quota, a broken network — is not a collision and must not be retried as one.
    private func reserveCode(eventId: String, kind: String) async throws -> String {
        for _ in 0..<8 {
            let code = InviteCode.generate()
            do {
                try await db.collection(Collections.inviteCodes).document(code)
                    .setData(["eventId": eventId, "kind": kind])
                return code
            } catch let error as NSError
                        where error.domain == FirestoreErrorDomain
                        && error.code == FirestoreErrorCode.permissionDenied.rawValue {
                // Taken. A squatted code can never be reclaimed — deletion is host-only —
                // so the only move is a different code.
                logger.error("Invite code \(code) already taken; retrying")
                continue
            }
        }
        throw BackendError.couldNotReserveCode
    }

    func joinOccasion(
        eventId: String,
        code: String,
        name: String,
        avatarId: String,
        mode: ParticipantMode
    ) async throws {
        let uid = try currentUid()
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)

        do {
            try await participantsRef(eventId).document(uid).setData([
                "name": name,
                "avatarId": avatarId,
                "mode": mode.rawValue,
                "isHost": false,
                "usedCode": normalized
            ])
        } catch let error as NSError
                    where error.domain == FirestoreErrorDomain
                    && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            // The rules rejected the code, or its kind did not match the requested mode.
            // Both are user-facing input errors, not faults.
            throw BackendError.invalidCode
        }

        try await membershipRef(uid: uid, eventId: eventId).setData([
            "role": mode.rawValue,
            "isHost": false,
            "joinedAt": Timestamp(date: Date())
        ])

        logger.info("Joined occasion \(eventId)")
    }

    /// The caller's occasions, read from their membership mirror and hydrated one document
    /// at a time.
    ///
    /// A membership whose event will not load is skipped rather than fatal: the host may
    /// have removed this participant, which revokes read on the event but leaves the mirror
    /// behind. One stale row must not blank the whole list.
    func fetchMyOccasions() async throws -> [Occasion] {
        let uid = try currentUid()
        let memberships = try await db.collection(Collections.memberships).document(uid)
            .collection(Collections.events).getDocuments()

        var occasions: [Occasion] = []
        for membership in memberships.documents {
            let eventId = membership.documentID
            do {
                let doc = try await eventRef(eventId).getDocument()
                guard let occasion = try? doc.data(as: Occasion.self) else {
                    logger.error("Skipping occasion \(eventId): event document did not decode")
                    continue
                }
                occasions.append(occasion)
            } catch {
                logger.error("Skipping occasion \(eventId): \(error.localizedDescription)")
            }
        }
        return occasions.sorted { $0.occasionDate > $1.occasionDate }
    }

    func fetchOccasion(eventId: String) async throws -> Occasion? {
        let doc = try await eventRef(eventId).getDocument()
        return try? doc.data(as: Occasion.self)
    }

    func fetchParticipants(eventId: String) async throws -> [Participant] {
        let snapshot = try await participantsRef(eventId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Participant.self) }
    }

    func fetchMyParticipant(eventId: String) async throws -> Participant? {
        let uid = try currentUid()
        let doc = try await participantsRef(eventId).document(uid).getDocument()
        return try? doc.data(as: Participant.self)
    }

    /// A field update, never a `setData`. `hostUid` is pinned immutable by the rules
    /// (`request.resource.data.hostUid == resource.data.hostUid`), so a full replace that
    /// omitted it would be denied.
    func setOccasionOpen(eventId: String, isOpen: Bool) async throws {
        try await eventRef(eventId).updateData(["isOpen": isOpen])
    }

    // MARK: - Rewards

    func listenToRewards(eventId: String, completion: @escaping (Result<[Reward], Error>) -> Void) {
        let key = "rewards"
        removeListener(forKey: key)

        listeners[key] = rewardsRef(eventId)
            .order(by: "sortOrder")
            .addSnapshotListener { snapshot, error in
                if let error {
                    self.logger.error("Rewards listener error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                guard let docs = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                let rewards = docs.compactMap { try? $0.data(as: Reward.self) }
                completion(.success(rewards))
            }
    }

    /// Atomic reward unlock: verifies balance → spends points → unlocks reward → creates timeline event → checks final badge.
    /// Uses a Transaction for the balance check + a Batch for the multi-doc write.
    func unlockRewardAtomically(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        timelineEvent: TimelineEvent
    ) async throws {
        let gsRef = stateRef(eventId)
        let rewardRef = rewardsRef(eventId).document(rewardId)
        let now = Timestamp(date: Date())

        // Transaction: read balance → verify → write everything atomically
        _ = try await db.runTransaction { [self] transaction, errorPointer in
            // Read current game state
            let gsDoc: DocumentSnapshot
            do {
                gsDoc = try transaction.getDocument(gsRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard let data = gsDoc.data() else {
                errorPointer?.pointee = NSError(domain: "BQ", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Game state not found"])
                return nil
            }

            let currentPoints = (data["currentPoints"] as? NSNumber)?.intValue ?? 0
            let rewardsUnlocked = (data["rewardsUnlocked"] as? NSNumber)?.intValue ?? 0
            let totalRewards = (data["totalRewards"] as? NSNumber)?.intValue ?? 0

            // Guard: sufficient balance
            guard currentPoints >= pointCost else {
                errorPointer?.pointee = NSError(domain: "BQ", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Not enough points (have \(currentPoints), need \(pointCost))"])
                return nil
            }

            // 1. Deduct points
            var gsUpdate: [String: Any] = [
                "totalPointsSpent": FieldValue.increment(Int64(pointCost)),
                "currentPoints": FieldValue.increment(Int64(-pointCost)),
                "rewardsUnlocked": FieldValue.increment(Int64(1)),
                "updatedAt": now
            ]

            // Check if this unlock triggers the final badge
            let newUnlockedCount = rewardsUnlocked + 1
            if newUnlockedCount >= totalRewards && totalRewards > 0 {
                gsUpdate["allRewardsUnlocked"] = true
                gsUpdate["finalBadgeUnlocked"] = true
                gsUpdate["finalBadgeUnlockedAt"] = now
            }

            transaction.updateData(gsUpdate, forDocument: gsRef)

            // 2. Mark reward unlocked
            transaction.updateData([
                "isUnlocked": true,
                "unlockedAt": now
            ], forDocument: rewardRef)

            // 3. Add timeline event
            let newTimelineRef = self.timelineRef(eventId).document()
            do {
                try transaction.setData(from: timelineEvent, forDocument: newTimelineRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            return nil
        }
    }

    // MARK: - Challenges

    /// Listen to challenges with a unique key per consumer to avoid listener collisions.
    /// - Parameter listenerKey: Unique key for this listener (default: "challenges")
    func listenToChallenges(
        eventId: String,
        listenerKey: String = "challenges",
        completion: @escaping (Result<[Challenge], Error>) -> Void
    ) {
        let key = listenerKey
        removeListener(forKey: key)

        listeners[key] = challengesRef(eventId)
            .order(by: "pointValue")
            .addSnapshotListener { snapshot, error in
                if let error {
                    self.logger.error("Challenges listener error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                guard let docs = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                let challenges = docs.compactMap { try? $0.data(as: Challenge.self) }
                completion(.success(challenges))
            }
    }

    /// Atomic challenge completion: reads challenge to verify not already completed,
    /// then marks done + awards points + creates timeline event in one transaction.
    /// Proof upload must happen BEFORE calling this (upload is not transactionable).
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
        let challengeRef = challengesRef(eventId).document(challengeId)
        let gsRef = stateRef(eventId)
        let now = Timestamp(date: Date())

        _ = try await db.runTransaction { [self] transaction, errorPointer in
            // Read both documents to establish optimistic locks
            let challengeDoc: DocumentSnapshot
            do {
                challengeDoc = try transaction.getDocument(challengeRef)
                _ = try transaction.getDocument(gsRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard let existingData = challengeDoc.data(),
                  existingData["isCompleted"] as? Bool != true else {
                // Already completed — idempotent success
                return nil
            }

            // 1. Mark challenge completed
            var challengeData: [String: Any] = [
                "isCompleted": true,
                "completedAt": now
            ]
            if let proofUrl { challengeData["proofUrl"] = proofUrl }
            if let proofType { challengeData["proofType"] = proofType }
            if let proofText { challengeData["proofText"] = proofText }
            transaction.updateData(challengeData, forDocument: challengeRef)

            // 2. Award points + increment counters
            var gsData: [String: Any] = [
                "totalPointsEarned": FieldValue.increment(Int64(pointValue)),
                "currentPoints": FieldValue.increment(Int64(pointValue)),
                "challengesCompleted": FieldValue.increment(Int64(1)),
                "updatedAt": now
            ]
            if isSecret {
                gsData["secretChallengesCompleted"] = FieldValue.increment(Int64(1))
            }
            transaction.updateData(gsData, forDocument: gsRef)

            // 3. Add timeline event
            let newTimelineRef = self.timelineRef(eventId).document()
            do {
                try transaction.setData(from: timelineEvent, forDocument: newTimelineRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            return nil
        }
    }

    func createSecretChallenge(eventId: String, challenge: Challenge) async throws -> String {
        let ref = try challengesRef(eventId).addDocument(from: challenge)
        return ref.documentID
    }

    func updateSecretChallenge(
        eventId: String,
        challengeId: String,
        data: [String: Any]
    ) async throws {
        try await challengesRef(eventId).document(challengeId).updateData(data)
    }

    // MARK: - Timeline Events

    func listenToTimeline(
        eventId: String,
        completion: @escaping (Result<[TimelineEvent], Error>) -> Void
    ) {
        let key = "timeline"
        removeListener(forKey: key)

        listeners[key] = timelineRef(eventId)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    self.logger.error("Timeline listener error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                guard let docs = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                let events = docs.compactMap { try? $0.data(as: TimelineEvent.self) }
                completion(.success(events))
            }
    }

    func addTimelineEvent(eventId: String, event: TimelineEvent) async throws {
        try timelineRef(eventId).addDocument(from: event)
    }

    // MARK: - Game State

    func listenToGameState(
        eventId: String,
        completion: @escaping (Result<GameState, Error>) -> Void
    ) {
        let key = "gameState"
        removeListener(forKey: key)

        listeners[key] = stateRef(eventId).addSnapshotListener { snapshot, error in
            if let error {
                self.logger.error("GameState listener error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                completion(.success(.empty))
                return
            }

            // Manual parsing — avoids Codable decode failures from Firestore type mismatches.
            // Every field nil-coalesces, so documents written without the retired
            // `birthdayBoyId` parse cleanly.
            let state = GameState(
                birthdayBoyId: data["birthdayBoyId"] as? String ?? "",
                totalPointsEarned: (data["totalPointsEarned"] as? NSNumber)?.intValue ?? 0,
                totalPointsSpent: (data["totalPointsSpent"] as? NSNumber)?.intValue ?? 0,
                currentPoints: (data["currentPoints"] as? NSNumber)?.intValue ?? 0,
                challengesCompleted: (data["challengesCompleted"] as? NSNumber)?.intValue ?? 0,
                totalChallenges: (data["totalChallenges"] as? NSNumber)?.intValue ?? 0,
                secretChallengesFound: (data["secretChallengesFound"] as? NSNumber)?.intValue ?? 0,
                secretChallengesCompleted: (data["secretChallengesCompleted"] as? NSNumber)?.intValue ?? 0,
                rewardsUnlocked: (data["rewardsUnlocked"] as? NSNumber)?.intValue ?? 0,
                totalRewards: (data["totalRewards"] as? NSNumber)?.intValue ?? 0,
                allRewardsUnlocked: data["allRewardsUnlocked"] as? Bool ?? false,
                finalBadgeUnlocked: data["finalBadgeUnlocked"] as? Bool ?? false,
                finalBadgeUnlockedAt: (data["finalBadgeUnlockedAt"] as? Timestamp)?.dateValue(),
                gameStartedAt: (data["gameStartedAt"] as? Timestamp)?.dateValue(),
                currentDay: (data["currentDay"] as? NSNumber)?.intValue ?? 1,
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
            )
            self.logger.debug("GameState updated: \(state.currentPoints) pts, \(state.challengesCompleted) challenges, \(state.rewardsUnlocked) rewards")
            completion(.success(state))
        }
    }

    func updateGameState(eventId: String, fields: [String: Any]) async throws {
        var data = fields
        data["updatedAt"] = Timestamp(date: Date())
        try await stateRef(eventId).updateData(data)
    }

    // MARK: - Legacy Individual Operations (kept for admin/fallback use)

    /// Earn points — prefer completeChallengeAtomically() for normal flow
    func earnPoints(eventId: String, amount: Int) async throws {
        try await stateRef(eventId).updateData([
            "totalPointsEarned": FieldValue.increment(Int64(amount)),
            "currentPoints": FieldValue.increment(Int64(amount)),
            "challengesCompleted": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ])
    }

    /// Spend points — prefer unlockRewardAtomically() for normal flow
    func spendPoints(eventId: String, amount: Int) async throws {
        try await stateRef(eventId).updateData([
            "totalPointsSpent": FieldValue.increment(Int64(amount)),
            "currentPoints": FieldValue.increment(Int64(-amount)),
            "rewardsUnlocked": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ])
    }

    /// Check and trigger final badge — now handled inside unlockRewardAtomically()
    func checkFinalBadge(eventId: String) async throws {
        let doc = try await stateRef(eventId).getDocument()
        guard let data = doc.data() else { return }

        let rewardsUnlocked = (data["rewardsUnlocked"] as? NSNumber)?.intValue ?? 0
        let totalRewards = (data["totalRewards"] as? NSNumber)?.intValue ?? 0
        let finalBadgeUnlocked = data["finalBadgeUnlocked"] as? Bool ?? false

        if rewardsUnlocked >= totalRewards && totalRewards > 0 && !finalBadgeUnlocked {
            try await updateGameState(eventId: eventId, fields: [
                "allRewardsUnlocked": true,
                "finalBadgeUnlocked": true,
                "finalBadgeUnlockedAt": Timestamp(date: Date())
            ])
        }
    }

    /// Increment secret challenges completed — now handled inside completeChallengeAtomically()
    func incrementSecretChallengesCompleted(eventId: String) async throws {
        try await stateRef(eventId).updateData([
            "secretChallengesCompleted": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Fetch by ID

    func fetchChallenge(eventId: String, challengeId: String) async throws -> Challenge? {
        let doc = try await challengesRef(eventId).document(challengeId).getDocument()
        return try? doc.data(as: Challenge.self)
    }

    func fetchReward(eventId: String, rewardId: String) async throws -> Reward? {
        let doc = try await rewardsRef(eventId).document(rewardId).getDocument()
        return try? doc.data(as: Reward.self)
    }

    // MARK: - Storage Upload

    func uploadProofData(
        eventId: String,
        challengeId: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let path = StoragePaths.proof(
            eventId: eventId, challengeId: challengeId, fileName: fileName
        )
        let ref = Storage.storage().reference().child(path)

        // Required. putData does not infer a content type from the path, so without this
        // the object uploads as application/octet-stream and the Storage rule requiring
        // image/* rejects it.
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    // MARK: - Admin Operations

    /// Admin force-unlock: bypasses balance check. Optionally deducts points.
    /// Uses a transaction to atomically check and trigger the final badge.
    func adminForceUnlockReward(
        eventId: String,
        rewardId: String,
        pointCost: Int,
        deductPoints: Bool,
        timelineEvent: TimelineEvent
    ) async throws {
        let rewardRef = rewardsRef(eventId).document(rewardId)
        let gsRef = stateRef(eventId)
        let now = Timestamp(date: Date())

        _ = try await db.runTransaction { [self] transaction, errorPointer in
            // Read game state for final badge check
            let gsDoc: DocumentSnapshot
            do {
                gsDoc = try transaction.getDocument(gsRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            let data = gsDoc.data() ?? [:]
            let rewardsUnlocked = (data["rewardsUnlocked"] as? NSNumber)?.intValue ?? 0
            let totalRewards = (data["totalRewards"] as? NSNumber)?.intValue ?? 0

            // 1. Mark reward unlocked
            transaction.updateData([
                "isUnlocked": true,
                "unlockedAt": now
            ], forDocument: rewardRef)

            // 2. Update game state
            var gsUpdate: [String: Any] = [
                "rewardsUnlocked": FieldValue.increment(Int64(1)),
                "updatedAt": now
            ]
            if deductPoints {
                gsUpdate["totalPointsSpent"] = FieldValue.increment(Int64(pointCost))
                gsUpdate["currentPoints"] = FieldValue.increment(Int64(-pointCost))
            }

            // Check if this unlock triggers the final badge
            let newUnlockedCount = rewardsUnlocked + 1
            if newUnlockedCount >= totalRewards && totalRewards > 0 {
                gsUpdate["allRewardsUnlocked"] = true
                gsUpdate["finalBadgeUnlocked"] = true
                gsUpdate["finalBadgeUnlockedAt"] = now
            }

            transaction.updateData(gsUpdate, forDocument: gsRef)

            // 3. Add timeline event
            let newTimelineRef = self.timelineRef(eventId).document()
            do {
                try transaction.setData(from: timelineEvent, forDocument: newTimelineRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            return nil
        }
    }
}
