import Foundation
import FirebaseFirestore
import FirebaseStorage
import Combine

// MARK: - FirestoreService

final class FirestoreService: ObservableObject {
    
    static let shared = FirestoreService()
    
    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]
    
    private init() {
        // Settings configured in BirthdayQuestApp.init() before any Firestore access
    }
    
    deinit {
        removeAllListeners()
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
    
    // MARK: - Users
    
    func listenToUsers(completion: @escaping ([BQUser]) -> Void) {
        let key = "users"
        removeListener(forKey: key)
        
        listeners[key] = db.collection(Collections.users)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else {
                    print("❌ Users listener error: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                let users = docs.compactMap { try? $0.data(as: BQUser.self) }
                completion(users)
            }
    }
    
    func claimCharacter(characterId: String, deviceId: String) async throws {
        try await db.collection(Collections.users).document(characterId).updateData([
            "claimed": true,
            "deviceId": deviceId
        ])
    }
    
    func fetchUser(characterId: String) async throws -> BQUser? {
        let doc = try await db.collection(Collections.users).document(characterId).getDocument()
        return try? doc.data(as: BQUser.self)
    }
    
    // MARK: - Rewards
    
    func listenToRewards(completion: @escaping ([Reward]) -> Void) {
        let key = "rewards"
        removeListener(forKey: key)
        
        listeners[key] = db.collection(Collections.rewards)
            .order(by: "sortOrder")
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else {
                    print("❌ Rewards listener error: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                let rewards = docs.compactMap { try? $0.data(as: Reward.self) }
                completion(rewards)
            }
    }
    
    /// Atomic reward unlock: verifies balance → spends points → unlocks reward → creates timeline event → checks final badge.
    /// Uses a Transaction for the balance check + a Batch for the multi-doc write.
    func unlockRewardAtomically(
        rewardId: String,
        pointCost: Int,
        timelineEvent: TimelineEvent
    ) async throws {
        let gsRef = db.collection(Collections.gameState).document(Collections.gameStateDoc)
        let rewardRef = db.collection(Collections.rewards).document(rewardId)
        let now = Timestamp(date: Date())
        
        // Transaction: read balance → verify → write everything atomically
        try await db.runTransaction { [self] transaction, errorPointer in
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
            let timelineRef = self.db.collection(Collections.timelineEvents).document()
            do {
                try transaction.setData(from: timelineEvent, forDocument: timelineRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            return nil
        }
    }
    
    /// Legacy non-batched unlock (kept for admin use)
    func unlockReward(rewardId: String) async throws {
        try await db.collection(Collections.rewards).document(rewardId).updateData([
            "isUnlocked": true,
            "unlockedAt": Timestamp(date: Date())
        ])
    }
    
    // MARK: - Challenges
    
    /// Listen to challenges with a unique key per consumer to avoid listener collisions.
    /// - Parameter listenerKey: Unique key for this listener (default: "challenges")
    func listenToChallenges(listenerKey: String = "challenges", completion: @escaping ([Challenge]) -> Void) {
        let key = listenerKey
        removeListener(forKey: key)
        
        listeners[key] = db.collection(Collections.challenges)
            .order(by: "pointValue")
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else {
                    print("❌ Challenges listener error: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                let challenges = docs.compactMap { try? $0.data(as: Challenge.self) }
                completion(challenges)
            }
    }
    
    /// Atomic challenge completion: marks challenge done + awards points + creates timeline event in one batch.
    /// Proof upload must happen BEFORE calling this (upload is not batchable).
    func completeChallengeAtomically(
        challengeId: String,
        pointValue: Int,
        isSecret: Bool,
        proofUrl: String?,
        proofType: String?,
        proofText: String?,
        timelineEvent: TimelineEvent
    ) async throws {
        let batch = db.batch()
        let now = Timestamp(date: Date())
        
        // 1. Mark challenge completed
        let challengeRef = db.collection(Collections.challenges).document(challengeId)
        var challengeData: [String: Any] = [
            "isCompleted": true,
            "completedAt": now
        ]
        if let proofUrl { challengeData["proofUrl"] = proofUrl }
        if let proofType { challengeData["proofType"] = proofType }
        if let proofText { challengeData["proofText"] = proofText }
        batch.updateData(challengeData, forDocument: challengeRef)
        
        // 2. Award points + increment counters
        let gsRef = db.collection(Collections.gameState).document(Collections.gameStateDoc)
        var gsData: [String: Any] = [
            "totalPointsEarned": FieldValue.increment(Int64(pointValue)),
            "currentPoints": FieldValue.increment(Int64(pointValue)),
            "challengesCompleted": FieldValue.increment(Int64(1)),
            "updatedAt": now
        ]
        if isSecret {
            gsData["secretChallengesCompleted"] = FieldValue.increment(Int64(1))
        }
        batch.updateData(gsData, forDocument: gsRef)
        
        // 3. Add timeline event
        let timelineRef = db.collection(Collections.timelineEvents).document()
        try batch.setData(from: timelineEvent, forDocument: timelineRef)
        
        try await batch.commit()
    }
    
    /// Legacy non-batched complete (kept for potential one-off admin use)
    func completeChallenge(challengeId: String, proofUrl: String?, proofType: String?, proofText: String?) async throws {
        var data: [String: Any] = [
            "isCompleted": true,
            "completedAt": Timestamp(date: Date())
        ]
        if let proofUrl { data["proofUrl"] = proofUrl }
        if let proofType { data["proofType"] = proofType }
        if let proofText { data["proofText"] = proofText }
        
        try await db.collection(Collections.challenges).document(challengeId).updateData(data)
    }
    
    func createSecretChallenge(_ challenge: Challenge) async throws -> String {
        let ref = try db.collection(Collections.challenges).addDocument(from: challenge)
        return ref.documentID
    }
    
    func updateSecretChallenge(challengeId: String, data: [String: Any]) async throws {
        try await db.collection(Collections.challenges).document(challengeId).updateData(data)
    }
    
    // MARK: - Timeline Events
    
    func listenToTimeline(completion: @escaping ([TimelineEvent]) -> Void) {
        let key = "timeline"
        removeListener(forKey: key)
        
        listeners[key] = db.collection(Collections.timelineEvents)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else {
                    print("❌ Timeline listener error: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                let events = docs.compactMap { try? $0.data(as: TimelineEvent.self) }
                completion(events)
            }
    }
    
    func addTimelineEvent(_ event: TimelineEvent) async throws {
        try db.collection(Collections.timelineEvents).addDocument(from: event)
    }
    
    // MARK: - Game State
    
    func listenToGameState(completion: @escaping (GameState?) -> Void) {
        let key = "gameState"
        removeListener(forKey: key)
        
        let ref = db.collection(Collections.gameState).document(Collections.gameStateDoc)
        listeners[key] = ref.addSnapshotListener { snapshot, error in
            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                print("❌ GameState listener error: \(error?.localizedDescription ?? "no doc")")
                completion(nil)
                return
            }
            
            // Manual parsing — avoids Codable decode failures from Firestore type mismatches
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
            print("✅ GameState updated: \(state.currentPoints) pts, \(state.challengesCompleted) challenges, \(state.rewardsUnlocked) rewards")
            completion(state)
        }
    }
    
    func updateGameState(_ fields: [String: Any]) async throws {
        var data = fields
        data["updatedAt"] = Timestamp(date: Date())
        try await db.collection(Collections.gameState)
            .document(Collections.gameStateDoc)
            .updateData(data)
    }
    
    // MARK: - Legacy Individual Operations (kept for admin/fallback use)
    
    /// Earn points — prefer completeChallengeAtomically() for normal flow
    func earnPoints(amount: Int) async throws {
        try await db.collection(Collections.gameState)
            .document(Collections.gameStateDoc)
            .updateData([
                "totalPointsEarned": FieldValue.increment(Int64(amount)),
                "currentPoints": FieldValue.increment(Int64(amount)),
                "challengesCompleted": FieldValue.increment(Int64(1)),
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    /// Spend points — prefer unlockRewardAtomically() for normal flow
    func spendPoints(amount: Int) async throws {
        try await db.collection(Collections.gameState)
            .document(Collections.gameStateDoc)
            .updateData([
                "totalPointsSpent": FieldValue.increment(Int64(amount)),
                "currentPoints": FieldValue.increment(Int64(-amount)),
                "rewardsUnlocked": FieldValue.increment(Int64(1)),
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    /// Check and trigger final badge — now handled inside unlockRewardAtomically()
    func checkFinalBadge() async throws {
        let doc = try await db.collection(Collections.gameState)
            .document(Collections.gameStateDoc).getDocument()
        guard let data = doc.data() else { return }
        
        let rewardsUnlocked = (data["rewardsUnlocked"] as? NSNumber)?.intValue ?? 0
        let totalRewards = (data["totalRewards"] as? NSNumber)?.intValue ?? 0
        let finalBadgeUnlocked = data["finalBadgeUnlocked"] as? Bool ?? false
        
        if rewardsUnlocked >= totalRewards && totalRewards > 0 && !finalBadgeUnlocked {
            try await updateGameState([
                "allRewardsUnlocked": true,
                "finalBadgeUnlocked": true,
                "finalBadgeUnlockedAt": Timestamp(date: Date())
            ])
        }
    }
    
    /// Increment secret challenges completed — now handled inside completeChallengeAtomically()
    func incrementSecretChallengesCompleted() async throws {
        try await db.collection(Collections.gameState)
            .document(Collections.gameStateDoc)
            .updateData([
                "secretChallengesCompleted": FieldValue.increment(Int64(1)),
                "updatedAt": Timestamp(date: Date())
            ])
    }
    
    // MARK: - Fetch by ID
    
    func fetchChallenge(byId id: String) async throws -> Challenge? {
        let doc = try await db.collection(Collections.challenges).document(id).getDocument()
        return try? doc.data(as: Challenge.self)
    }
    
    func fetchReward(byId id: String) async throws -> Reward? {
        let doc = try await db.collection(Collections.rewards).document(id).getDocument()
        return try? doc.data(as: Reward.self)
    }
    
    // MARK: - Storage Upload
    
    func uploadProofData(_ data: Data, path: String) async throws -> String {
        let ref = Storage.storage().reference().child(path)
        let _ = try await ref.putDataAsync(data)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }
    
    // MARK: - Admin Operations
    
    /// Unclaim a character so it can be re-selected by someone else.
    /// The affected user's next `bootstrap()` check will detect the mismatch and bounce them to character select.
    func unclaimCharacter(characterId: String) async throws {
        try await db.collection(Collections.users)
            .document(characterId)
            .updateData([
                "claimed": false,
                "deviceId": NSNull()
            ])
    }
    
    /// Admin force-unlock: bypasses balance check. Optionally deducts points.
    /// Uses a batch write (no transaction needed — admin is sole writer).
    func adminForceUnlockReward(
        rewardId: String,
        pointCost: Int,
        deductPoints: Bool,
        timelineEvent: TimelineEvent
    ) async throws {
        let batch = db.batch()
        let now = Timestamp(date: Date())
        
        // 1. Mark reward unlocked
        let rewardRef = db.collection(Collections.rewards).document(rewardId)
        batch.updateData([
            "isUnlocked": true,
            "unlockedAt": now
        ], forDocument: rewardRef)
        
        // 2. Update game state
        let gsRef = db.collection(Collections.gameState).document(Collections.gameStateDoc)
        var gsUpdate: [String: Any] = [
            "rewardsUnlocked": FieldValue.increment(Int64(1)),
            "updatedAt": now
        ]
        if deductPoints {
            gsUpdate["totalPointsSpent"] = FieldValue.increment(Int64(pointCost))
            gsUpdate["currentPoints"] = FieldValue.increment(Int64(-pointCost))
        }
        batch.updateData(gsUpdate, forDocument: gsRef)
        
        // 3. Add timeline event
        let timelineRef = db.collection(Collections.timelineEvents).document()
        try batch.setData(from: timelineEvent, forDocument: timelineRef)
        
        try await batch.commit()
    }
}
