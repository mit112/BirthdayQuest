import Testing
import Foundation
import Darwin
import FirebaseCore
import FirebaseFirestore
@testable import BirthdayQuest

// Emulator-backed proof of the ONE critical path a mock cannot simulate: the server-side
// transaction logic inside FirestoreService. MockGameBackend replaces `unlockRewardAtomically`
// and `completeChallengeAtomically` wholesale, so nothing in the unit suite ever runs the
// balance re-check or the idempotency guard — the two properties families actually depend on.
//
// These run only under `firebase emulators:exec` (see integration-tests/README.md). The whole
// suite is gated on `EmulatorProbe.isReachable`, so the normal
// `-only-testing:BirthdayQuestTests` pass — which has no emulator — SKIPS it rather than hanging.
//
// Authorization is deliberately out of scope here: the emulator runs with OPEN rules
// (integration-tests/firestore.rules) so each test can seed a document without standing up the
// Auth emulator + a membership. The strict production rules are covered by the 183-test suite in
// firebase-tests. This file proves the transaction control flow, nothing more.

// MARK: - Emulator availability probe

/// A fast, non-blocking-in-practice socket probe. A connect to a non-listening localhost port
/// is refused immediately (no timeout needed), so this is safe to evaluate at test-collection
/// time via `@Suite(.enabled(if:))`.
enum EmulatorProbe {
    /// Deliberately NOT Firestore's default 8080, and this must not be "tidied" back to it.
    /// 8080 is where the emulator carrying the STRICT PRODUCTION ruleset runs — that is what
    /// `cd firebase-tests && npm test` starts, from the repo-root `firebase.json`. This suite
    /// seeds its documents unauthenticated, so answering that emulator turns four correct skips
    /// into four permission-denied failures describing nothing real (measured: `xcodebuild
    /// -only-testing:BirthdayQuestTests/TransactionIntegrationTests` with the rules emulator up
    /// reports 4 failed / 0 skipped). A port of its own is what makes the probe mean "the OPEN
    /// ruleset from integration-tests/ is up", and it lets the two suites run at the same time.
    ///
    /// It must match `integration-tests/firebase.json`. A drift there shows up as a SKIP, which
    /// the CI integration job already fails on rather than passing green.
    static let port: UInt16 = 8181

    static var isReachable: Bool { canConnect(host: "127.0.0.1", port: port) }

    private static func canConnect(host: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return rc == 0
    }
}

// MARK: - Emulator-pointed Firebase

/// A secondary, named `FirebaseApp` wired to the local emulator, configured exactly once.
/// Kept separate from the host app's default app — whose settings `BirthdayQuestApp.init()`
/// already fixed to a persistent cache — so nothing here disturbs production configuration.
/// The emulator ignores credentials, so the dummy `FirebaseOptions` are sufficient.
enum EmulatorFirebase {
    private static let appName = "bq-integration-emulator"
    private static let lock = NSLock()
    private static var cached: Firestore?

    static func firestore() -> Firestore {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }

        let app: FirebaseApp
        if let existing = FirebaseApp.app(name: appName) {
            app = existing
        } else {
            let options = FirebaseOptions(
                googleAppID: "1:123456789012:ios:abcdef0123456789",
                gcmSenderID: "123456789012"
            )
            options.projectID = "birthdayquest-test"
            options.apiKey = "fake-emulator-api-key"
            FirebaseApp.configure(name: appName, options: options)
            // Force-unwrap: we just configured it under the lock.
            app = FirebaseApp.app(name: appName)!
        }

        // Configure the emulator connection EXPLICITLY rather than via `useEmulator(withHost:)`.
        // `useEmulator` mutates the live settings, but the canonical pattern below reads a fresh
        // settings copy and sets every field itself, so there is no chance of a subsequent
        // reassignment clobbering `isSSLEnabled` back to its `true` default — which would make the
        // SDK attempt TLS against the plaintext emulator and retry the failed handshake forever.
        let firestore = Firestore.firestore(app: app)
        let settings = firestore.settings
        settings.host = "127.0.0.1:\(EmulatorProbe.port)"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings

        cached = firestore
        return firestore
    }
}

// MARK: - Tests

@Suite(.enabled(if: EmulatorProbe.isReachable))
struct TransactionIntegrationTests {

    // A distinct occasion per test so the suite needs no cleanup and can run in parallel;
    // the emulator's data is discarded when `emulators:exec` exits anyway.
    private func newEventId() -> String { "it-\(UUID().uuidString)" }

    private func makeTimeline(referenceId: String, type: TimelineEventType) -> TimelineEvent {
        TimelineEvent(
            type: type,
            referenceId: referenceId,
            title: "Integration test",
            subtitle: "—",
            badgeType: type == .rewardUnlocked ? .reward : .challenge,
            badgeAsset: "star.fill",
            fromFriendName: nil,
            fromFriendAvatar: nil,
            timestamp: Date()
        )
    }

    private func intValue(_ data: [String: Any]?, _ key: String) -> Int? {
        (data?[key] as? NSNumber)?.intValue
    }

    // MARK: unlockRewardAtomically

    @Test("unlockRewardAtomically deducts points and unlocks the reward on a sufficient balance")
    func unlockSucceedsWithSufficientBalance() async throws {
        let db = EmulatorFirebase.firestore()
        let service = FirestoreService(db: db)
        let eventId = newEventId()
        let rewardId = "reward-1"

        try await db.document("events/\(eventId)/state/main").setData([
            "currentPoints": 100,
            "rewardsUnlocked": 0,
            "totalRewards": 3,
            "totalPointsSpent": 0,
            "updatedAt": Timestamp(date: Date())
        ])
        try await db.document("events/\(eventId)/rewards/\(rewardId)").setData([
            "title": "A gift", "isUnlocked": false
        ])

        try await service.unlockRewardAtomically(
            eventId: eventId, rewardId: rewardId, pointCost: 50,
            timelineEvent: makeTimeline(referenceId: rewardId, type: .rewardUnlocked)
        )

        let state = try await db.document("events/\(eventId)/state/main").getDocument().data()
        #expect(intValue(state, "currentPoints") == 50)
        #expect(intValue(state, "rewardsUnlocked") == 1)

        let reward = try await db.document("events/\(eventId)/rewards/\(rewardId)").getDocument().data()
        #expect(reward?["isUnlocked"] as? Bool == true)

        let timeline = try await db.collection("events/\(eventId)/timeline").getDocuments()
        #expect(timeline.documents.count == 1)
    }

    /// The invariant the whole harness exists for. A member can write `state/main` freely (the
    /// no-Functions trust model), so the ONLY thing standing between a client and a free reward is
    /// the in-transaction `guard currentPoints >= pointCost`. This proves it holds AND that the
    /// failure is atomic: balance, unlock flag, and timeline all stay untouched.
    @Test("unlockRewardAtomically refuses the spend and writes nothing when the balance is short")
    func unlockRefusedWhenBalanceInsufficient() async throws {
        let db = EmulatorFirebase.firestore()
        let service = FirestoreService(db: db)
        let eventId = newEventId()
        let rewardId = "reward-1"

        try await db.document("events/\(eventId)/state/main").setData([
            "currentPoints": 10,
            "rewardsUnlocked": 0,
            "totalRewards": 3,
            "totalPointsSpent": 0,
            "updatedAt": Timestamp(date: Date())
        ])
        try await db.document("events/\(eventId)/rewards/\(rewardId)").setData([
            "title": "A gift", "isUnlocked": false
        ])

        await #expect(throws: (any Error).self) {
            try await service.unlockRewardAtomically(
                eventId: eventId, rewardId: rewardId, pointCost: 50,
                timelineEvent: makeTimeline(referenceId: rewardId, type: .rewardUnlocked)
            )
        }

        let state = try await db.document("events/\(eventId)/state/main").getDocument().data()
        #expect(intValue(state, "currentPoints") == 10)
        #expect(intValue(state, "rewardsUnlocked") == 0)

        let reward = try await db.document("events/\(eventId)/rewards/\(rewardId)").getDocument().data()
        #expect(reward?["isUnlocked"] as? Bool == false)

        let timeline = try await db.collection("events/\(eventId)/timeline").getDocuments()
        #expect(timeline.documents.isEmpty)
    }

    // MARK: completeChallengeAtomically

    /// Proves the idempotency guard: a double-submit (retry, double-tap, at-least-once delivery)
    /// awards points exactly once. The timeline-count assertion is the discriminator — a
    /// non-idempotent implementation both double-awards AND appends a second timeline entry.
    @Test("completeChallengeAtomically awards points at most once across repeated calls")
    func challengeCompletionIsIdempotent() async throws {
        let db = EmulatorFirebase.firestore()
        let service = FirestoreService(db: db)
        let eventId = newEventId()
        let challengeId = "chal-1"

        try await db.document("events/\(eventId)/state/main").setData([
            "currentPoints": 0,
            "totalPointsEarned": 0,
            "challengesCompleted": 0,
            "updatedAt": Timestamp(date: Date())
        ])
        try await db.document("events/\(eventId)/challenges/\(challengeId)").setData([
            "title": "Do a thing", "isCompleted": false
        ])

        func complete() async throws {
            try await service.completeChallengeAtomically(
                eventId: eventId, challengeId: challengeId, pointValue: 30,
                isSecret: false, proofUrl: nil, proofType: nil, proofText: nil,
                timelineEvent: makeTimeline(referenceId: challengeId, type: .challengeCompleted)
            )
        }

        try await complete()
        try await complete() // the second call must be a no-op

        let state = try await db.document("events/\(eventId)/state/main").getDocument().data()
        #expect(intValue(state, "currentPoints") == 30)       // 30, not 60
        #expect(intValue(state, "challengesCompleted") == 1)  // 1, not 2

        let challenge = try await db.document("events/\(eventId)/challenges/\(challengeId)").getDocument().data()
        #expect(challenge?["isCompleted"] as? Bool == true)

        let timeline = try await db.collection("events/\(eventId)/timeline").getDocuments()
        #expect(timeline.documents.count == 1)                // one entry, not two
    }

    // MARK: adminForceUnlockReward

    /// The host's force-unlock exists precisely to unlock WITHOUT spending. Proves the
    /// `deductPoints: false` branch leaves the balance alone even when it is below `pointCost`
    /// (a bug that always deducted would drive the balance negative here).
    @Test("adminForceUnlockReward unlocks without deducting when deductPoints is false")
    func adminForceUnlockDoesNotDeductWhenAsked() async throws {
        let db = EmulatorFirebase.firestore()
        let service = FirestoreService(db: db)
        let eventId = newEventId()
        let rewardId = "reward-1"

        try await db.document("events/\(eventId)/state/main").setData([
            "currentPoints": 5,
            "rewardsUnlocked": 0,
            "totalRewards": 2,
            "totalPointsSpent": 0,
            "updatedAt": Timestamp(date: Date())
        ])
        try await db.document("events/\(eventId)/rewards/\(rewardId)").setData([
            "title": "A gift", "isUnlocked": false
        ])

        try await service.adminForceUnlockReward(
            eventId: eventId, rewardId: rewardId, pointCost: 50, deductPoints: false,
            timelineEvent: makeTimeline(referenceId: rewardId, type: .rewardUnlocked)
        )

        let state = try await db.document("events/\(eventId)/state/main").getDocument().data()
        #expect(intValue(state, "currentPoints") == 5)        // untouched, not -45
        #expect(intValue(state, "rewardsUnlocked") == 1)

        let reward = try await db.document("events/\(eventId)/rewards/\(rewardId)").getDocument().data()
        #expect(reward?["isUnlocked"] as? Bool == true)
    }
}
