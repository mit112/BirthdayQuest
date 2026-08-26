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

    private let db: Firestore
    private var listeners: [String: ListenerRegistration] = [:]
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Firestore")

    /// `db` is injectable only so the emulator-backed transaction integration tests
    /// (`TransactionIntegrationTests`) can hand in a `Firestore` pointed at the local
    /// emulator. Production always goes through `shared`, which uses the default
    /// `Firestore.firestore()`; its settings are configured in `BirthdayQuestApp.init()`
    /// before any access.
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    // MARK: - Path Helpers

    /// The single choke point for every event-scoped path, and the reason it throws.
    ///
    /// `CollectionReference.document(_:)` treats its argument as a *path*, not an id. A `//`
    /// or an odd final segment count raises an Objective-C `NSException` from the Firestore
    /// C++ core (`resource_path.cc` / `document_reference.cc`, thrown via
    /// `exception_apple.mm`), which Swift `do/catch` cannot intercept: the process aborts.
    /// Event ids arrive from a `birthdayquest://join` deep link and from the client-writable
    /// `inviteCodes.eventId` field, so "anyone who can send this user a link" could crash
    /// their app on tap. Validating here rather than in a view model is what makes it
    /// unbypassable — no path in this file can be built without going through it.
    private func eventRef(_ eventId: String) throws -> DocumentReference {
        guard EventID.isValid(eventId) else {
            logger.error("Rejected a malformed event id before building a path")
            throw BackendError.invalidEventId
        }
        return db.collection(Collections.events).document(eventId)
    }

    private func challengesRef(_ eventId: String) throws -> CollectionReference {
        try eventRef(eventId).collection(Collections.challenges)
    }

    private func rewardsRef(_ eventId: String) throws -> CollectionReference {
        try eventRef(eventId).collection(Collections.rewards)
    }

    private func timelineRef(_ eventId: String) throws -> CollectionReference {
        try eventRef(eventId).collection(Collections.timeline)
    }

    private func reportsRef(_ eventId: String) throws -> CollectionReference {
        try eventRef(eventId).collection(Collections.reports)
    }

    private func participantsRef(_ eventId: String) throws -> CollectionReference {
        try eventRef(eventId).collection(Collections.participants)
    }

    private func stateRef(_ eventId: String) throws -> DocumentReference {
        try eventRef(eventId).collection(Collections.state).document(Collections.stateDoc)
    }

    /// The invite codes. Host-readable only, which is why they are not on the event document.
    private func codesRef(_ eventId: String) throws -> DocumentReference {
        try eventRef(eventId)
            .collection(Collections.privateData).document(Collections.codesDoc)
    }

    private func membershipRef(uid: String, eventId: String) throws -> DocumentReference {
        guard EventID.isValid(eventId) else {
            logger.error("Rejected a malformed event id before building a membership path")
            throw BackendError.invalidEventId
        }
        return db.collection(Collections.memberships).document(uid)
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
        //
        // The invite codes are deliberately NOT on this document. Every member can read it,
        // and an invite code is a bearer secret: a member who could read the celebrant code
        // could hand it to a fresh anonymous uid, which would then claim celebrant and be
        // allowed to delete every gift. They go in phase 2, at private/codes.
        try await newEventRef.setData([
            "name": name,
            "occasionType": occasionType.rawValue,
            "celebrantName": celebrantName,
            "hostUid": uid,
            "occasionDate": Timestamp(date: occasionDate),
            "isOpen": true,
            "createdAt": Timestamp(date: Date())
        ])

        // Phase 2: host participant, invite codes, initial game state, membership mirror.
        // All four rules gate on the event's hostUid rather than on membership, precisely so
        // this can be one batch — batched writes are evaluated against committed state, and
        // the participant document that a membership check would look for is created here.
        //
        // If this fails the event document is orphaned — unreadable by every client,
        // because the membership check finds no participant — so it is invisible rather
        // than corrupt.
        let now = Timestamp(date: Date())
        let hostParticipantRef = try participantsRef(eventId).document(uid)
        let newCodesRef = try codesRef(eventId)
        let newStateRef = try stateRef(eventId)
        let newMembershipRef = try membershipRef(uid: uid, eventId: eventId)
        let batch = db.batch()

        batch.setData([
            "name": hostName,
            "avatarId": hostAvatarId,
            "mode": hostMode.rawValue,
            "isHost": true,
            // Inert for the host: the host branch of the participant rule authorises on
            // hostUid, never on the code.
            "usedCode": contributorCode
        ], forDocument: hostParticipantRef)

        batch.setData([
            "contributorCode": contributorCode,
            "celebrantCode": celebrantCode
        ], forDocument: newCodesRef)

        batch.setData([
            "totalPointsEarned": 0, "totalPointsSpent": 0, "currentPoints": 0,
            "challengesCompleted": 0, "totalChallenges": 0,
            "secretChallengesFound": 0, "secretChallengesCompleted": 0,
            "rewardsUnlocked": 0, "totalRewards": 0,
            "allRewardsUnlocked": false, "finalBadgeUnlocked": false,
            "currentDay": 1,
            "gameStartedAt": now,
            "updatedAt": now
        ], forDocument: newStateRef)

        batch.setData([
            "role": hostMode.rawValue,
            "isHost": true,
            "joinedAt": now
        ], forDocument: newMembershipRef)

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

        // Checked, not merely tidied. A code becomes nothing here, but the same string is a
        // document id in `resolveInviteCode`, and refusing malformed input at every entrance
        // is cheaper than remembering which entrances are dangerous.
        guard let normalized = InviteCode.normalized(code) else {
            throw BackendError.invalidCode
        }
        let participantDoc = try participantsRef(eventId).document(uid)

        do {
            try await participantDoc.setData([
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

        // Concurrent, not sequential. This is the occasion-list cold path — it runs on every
        // launch — and a serial loop made it N round trips deep, so the wait grew with the
        // number of occasions the user had.
        //
        // The skip-on-failure behaviour is load-bearing and must survive: a membership can
        // outlive the event document, or name one this user has since been removed from, and
        // either would otherwise fail the *whole* list and leave the user staring at an empty
        // account. So each child returns `Occasion?` and never throws, which also means the
        // group cannot cancel its siblings on one bad document.
        // The children are `@MainActor`, which is where this whole type already lives. That
        // is not a compromise on the parallelism: the cost here is network latency, and
        // `getDocument()` suspends, so the requests still overlap. What it buys is that no
        // value crosses an isolation boundary.
        let occasions = await withTaskGroup(of: Occasion?.self) { group in
            for membership in memberships.documents {
                let eventId = membership.documentID
                group.addTask { @MainActor in
                    do {
                        let doc = try await self.eventRef(eventId).getDocument()
                        guard let occasion = try? doc.data(as: Occasion.self) else {
                            self.logger.error(
                                "Skipping occasion \(eventId): event document did not decode"
                            )
                            return nil
                        }
                        return occasion
                    } catch {
                        self.logger.error(
                            "Skipping occasion \(eventId): \(error.localizedDescription)"
                        )
                        return nil
                    }
                }
            }

            var collected: [Occasion] = []
            for await occasion in group {
                if let occasion { collected.append(occasion) }
            }
            return collected
        }

        // Sorted after collection, because a task group yields in completion order.
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

    /// Deletes only the participant doc. See the doc-comment on `GameBackend.removeParticipant`
    /// for why the membership mirror is deliberately left behind.
    func removeParticipant(eventId: String, uid: String) async throws {
        try await participantsRef(eventId).document(uid).delete()
    }

    /// A field update, never a `setData`. `hostUid` is pinned immutable by the rules
    /// (`request.resource.data.hostUid == resource.data.hostUid`), so a full replace that
    /// omitted it would be denied.
    func setOccasionOpen(eventId: String, isOpen: Bool) async throws {
        try await eventRef(eventId).updateData(["isOpen": isOpen])
    }

    /// Only the host can read this. Everyone else gets permission-denied, which is the
    /// point — see the note on `codesRef`.
    func fetchInviteCodes(eventId: String) async throws -> InviteCodes? {
        let doc = try await codesRef(eventId).getDocument()
        return InviteCodes(eventId: eventId, data: doc.data())
    }

    /// A field update on `private/codes`, not on the event document. The celebrant is allowed
    /// to write exactly this one field to exactly the empty string, and cannot read the
    /// document at all — `diff()` is evaluated server-side, so the rule does not need them to.
    func consumeCelebrantCode(eventId: String) async throws {
        try await codesRef(eventId).updateData(["celebrantCode": ""])
    }

    func resolveInviteCode(_ code: String) async throws -> (eventId: String, kind: String)? {
        // The code becomes a document id, and `document(_:)` takes a PATH: a `/` makes the
        // segment count odd and a `//` is rejected, and both abort the process with an
        // Objective-C exception no `catch` can see. Pasting a whole invite URL into the code
        // field — the documented workaround while the URL scheme was unregistered — contains
        // `//`. So validate before building the reference, and never try to catch it.
        guard let normalized = InviteCode.normalized(code) else {
            logger.error("Rejected a malformed invite code before building a path")
            throw BackendError.invalidCode
        }

        let snapshot = try await db.collection(Collections.inviteCodes)
            .document(normalized).getDocument()
        guard snapshot.exists,
              let data = snapshot.data(),
              let eventId = data["eventId"] as? String,
              let kind = data["kind"] as? String
        else { return nil }

        // `inviteCodes` is client-writable by design, so this field is attacker-controlled:
        // anyone may mint a code pointing at "a//b" and share it. Reject it here rather than
        // letting the caller interpolate it into a path.
        guard EventID.isValid(eventId) else {
            logger.error("Invite code \(normalized) resolved to a malformed event id")
            throw BackendError.invalidEventId
        }

        return (eventId, kind)
    }

    // MARK: - Rewards

    func listenToRewards(
        eventId: String,
        listenerKey: String,
        completion: @escaping (Result<[Reward], Error>) -> Void
    ) {
        let key = listenerKey
        removeListener(forKey: key)

        let collection: CollectionReference
        do {
            collection = try rewardsRef(eventId)
        } catch {
            completion(.failure(error))
            return
        }

        listeners[key] = collection
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
        let gsRef = try stateRef(eventId)
        let rewardRef = try rewardsRef(eventId).document(rewardId)
        // Built here rather than inside the transaction body: it is a path, not a read, and
        // `runTransaction`'s closure cannot throw.
        let newTimelineRef = try timelineRef(eventId).document()
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
            do {
                try transaction.setData(from: timelineEvent, forDocument: newTimelineRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            return nil
        }
    }

    func createReward(eventId: String, reward: Reward) async throws -> String {
        let ref = try rewardsRef(eventId).document()
        let state = try stateRef(eventId)
        let batch = db.batch()
        try batch.setData(from: reward, forDocument: ref)
        batch.updateData([
            "totalRewards": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: state)
        try await batch.commit()
        logger.info("Created reward \(ref.documentID)")
        return ref.documentID
    }

    func updateReward(eventId: String, rewardId: String, fields: [String: Any]) async throws {
        try await rewardsRef(eventId).document(rewardId).updateData(fields)
    }

    func deleteReward(eventId: String, rewardId: String) async throws {
        let ref = try rewardsRef(eventId).document(rewardId)
        let state = try stateRef(eventId)
        let batch = db.batch()
        batch.deleteDocument(ref)
        batch.updateData([
            "totalRewards": FieldValue.increment(Int64(-1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: state)
        try await batch.commit()
        logger.info("Deleted reward \(rewardId)")
    }

    /// One batch, one write per gift. A Firestore batch caps at 500 writes; an occasion has
    /// one gift per contributor, so the cap is not reachable in practice and is not guarded
    /// against — a guard here would be error handling for an impossible case.
    func setRewardOrder(eventId: String, orderedRewardIds: [String]) async throws {
        let rewards = try rewardsRef(eventId)
        let batch = db.batch()
        for (index, rewardId) in orderedRewardIds.enumerated() {
            batch.updateData(["sortOrder": index], forDocument: rewards.document(rewardId))
        }
        try await batch.commit()
        logger.info("Reordered \(orderedRewardIds.count) rewards")
    }

    // MARK: - Challenges

    /// Listen to challenges with a unique key per consumer to avoid listener collisions.
    /// - Parameter listenerKey: Unique key for this listener (default: "challenges")
    func listenToChallenges(
        eventId: String,
        listenerKey: String,
        completion: @escaping (Result<[Challenge], Error>) -> Void
    ) {
        let key = listenerKey
        removeListener(forKey: key)

        let collection: CollectionReference
        do {
            collection = try challengesRef(eventId)
        } catch {
            completion(.failure(error))
            return
        }

        listeners[key] = collection
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
        let challengeRef = try challengesRef(eventId).document(challengeId)
        let gsRef = try stateRef(eventId)
        let newTimelineRef = try timelineRef(eventId).document()
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
            do {
                try transaction.setData(from: timelineEvent, forDocument: newTimelineRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            return nil
        }
    }

    /// Creates a challenge and moves the occasion's counter in the same batch.
    ///
    /// The counter is not decoration. `GameState.challengeProgress` divides by
    /// `totalChallenges`, which was seeded to 0 at occasion creation and incremented nowhere,
    /// so an occasion filled in by hand (which is what the README told hosts to do) could
    /// never converge past whatever fraction it started at. `createReward` carries the sibling
    /// case — `checkFinalBadge` refuses to fire while `totalRewards == 0` — mentioned here only
    /// because both counters were broken the same way. Batching the increment with the write is
    /// what stops that coming back: a caller cannot forget what it is never asked to remember.
    ///
    /// `increment` rather than a recomputed count because contributors add gifts
    /// concurrently, and a recompute races. Neither rule reads the other document, so the
    /// committed-state trap that forced two-phase occasion creation does not apply here.
    func createChallenge(eventId: String, challenge: Challenge) async throws -> String {
        let ref = try challengesRef(eventId).document()
        let state = try stateRef(eventId)
        let batch = db.batch()
        try batch.setData(from: challenge, forDocument: ref)
        batch.updateData([
            "totalChallenges": FieldValue.increment(Int64(1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: state)
        try await batch.commit()
        logger.info("Created challenge \(ref.documentID)")
        return ref.documentID
    }

    func updateChallenge(
        eventId: String,
        challengeId: String,
        fields: [String: Any]
    ) async throws {
        try await challengesRef(eventId).document(challengeId).updateData(fields)
    }

    func deleteChallenge(eventId: String, challengeId: String) async throws {
        let ref = try challengesRef(eventId).document(challengeId)
        let state = try stateRef(eventId)
        let batch = db.batch()
        batch.deleteDocument(ref)
        batch.updateData([
            "totalChallenges": FieldValue.increment(Int64(-1)),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: state)
        try await batch.commit()
        logger.info("Deleted challenge \(challengeId)")
    }

    // MARK: - Timeline Events

    func listenToTimeline(
        eventId: String,
        completion: @escaping (Result<[TimelineEvent], Error>) -> Void
    ) {
        let key = ListenerKey.timeline(eventId)
        removeListener(forKey: key)

        let collection: CollectionReference
        do {
            collection = try timelineRef(eventId)
        } catch {
            completion(.failure(error))
            return
        }

        listeners[key] = collection
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

    // MARK: - Reports

    func reportContent(
        eventId: String,
        contentType: String,
        contentId: String,
        reason: String?
    ) async throws {
        let uid = try currentUid()
        var data: [String: Any] = [
            "contentType": contentType,
            "contentId": contentId,
            "reportedByUserId": uid,
            "createdAt": Timestamp(date: Date())
        ]
        if let reason { data["reason"] = reason }
        try await reportsRef(eventId).addDocument(data: data)
        logger.info("Filed a report for \(contentType) \(contentId)")
    }

    func fetchReports(eventId: String) async throws -> [Report] {
        let snapshot = try await reportsRef(eventId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Report.self) }
    }

    // MARK: - Game State

    func listenToGameState(
        eventId: String,
        completion: @escaping (Result<GameState, Error>) -> Void
    ) {
        let key = ListenerKey.gameState(eventId)
        removeListener(forKey: key)

        let document: DocumentReference
        do {
            document = try stateRef(eventId)
        } catch {
            completion(.failure(error))
            return
        }

        listeners[key] = document.addSnapshotListener { snapshot, error in
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
            // The parse itself lives on `GameState` so its field-name literals are reachable
            // from a test; this type is replaced by a mock in every Swift test, so a typo in
            // any one of them used to be undetectable.
            let state = GameState(wire: data)
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
        return path
    }

    func uploadRewardMedia(
        eventId: String,
        rewardId: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        _ = try eventRef(eventId)
        let fileName = "\(UUID().uuidString).\(fileExtension(forContentType: contentType))"
        let path = StoragePaths.rewardMedia(
            eventId: eventId, rewardId: rewardId, fileName: fileName
        )
        let ref = Storage.storage().reference().child(path)

        // Required. putData does not infer a content type from the path, so without this
        // the object uploads as application/octet-stream and the Storage rule rejects it.
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        _ = try await ref.putDataAsync(data, metadata: metadata)
        return path
    }

    func deleteRewardMedia(eventId: String, storagePaths: [String]) async throws {
        _ = try eventRef(eventId)
        for path in storagePaths {
            do {
                try await Storage.storage().reference().child(path).delete()
            } catch let error as NSError where error.code == StorageErrorCode.objectNotFound.rawValue {
                logger.info("Reward media already absent, treating delete as success")
            }
        }
    }

    func markRewardFetched(eventId: String, rewardId: String, uid: String) async throws {
        try await rewardsRef(eventId).document(rewardId).updateData([
            "fetchedBy": FieldValue.arrayUnion([uid])
        ])
    }

    private func fileExtension(forContentType contentType: String) -> String {
        switch contentType {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "audio/mpeg": return "mp3"
        case "audio/mp4", "audio/x-m4a": return "m4a"
        default: return "bin"
        }
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
        let rewardRef = try rewardsRef(eventId).document(rewardId)
        let gsRef = try stateRef(eventId)
        let newTimelineRef = try timelineRef(eventId).document()
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
