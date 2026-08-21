import Foundation
import FirebaseFirestore

// MARK: - Game State (Single Document)

/// One occasion's scoreboard, stored at `events/{eventId}/state/main`.
///
/// Deliberately **not** `Codable`. The wire format mixes Firestore `NSNumber` and `Timestamp`
/// values that a synthesised decoder rejects on an Int64/Int mismatch, so decoding goes
/// through `init(wire:)` instead. The conformance used to exist and nothing in the app used
/// it — leaving it in place invited someone to reach for `data(as:)` and rediscover that trap.
///
/// `nonisolated` for the same reason as `RewardContentPresentation`: the target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and this is a pure value type that tests read
/// from a nonisolated context.
nonisolated struct GameState: Equatable {
    var totalPointsEarned: Int
    var totalPointsSpent: Int
    var currentPoints: Int
    var challengesCompleted: Int
    var totalChallenges: Int
    var secretChallengesFound: Int
    var secretChallengesCompleted: Int
    var rewardsUnlocked: Int
    var totalRewards: Int
    var allRewardsUnlocked: Bool
    var finalBadgeUnlocked: Bool
    var finalBadgeUnlockedAt: Date?
    var gameStartedAt: Date?
    var currentDay: Int
    var updatedAt: Date?

    // MARK: - Computed

    var challengeProgress: Double {
        guard totalChallenges > 0 else { return 0 }
        return Double(challengesCompleted) / Double(totalChallenges)
    }

    var rewardProgress: Double {
        guard totalRewards > 0 else { return 0 }
        return Double(rewardsUnlocked) / Double(totalRewards)
    }

    var pointsDisplay: String {
        "✦ \(currentPoints)"
    }

    // MARK: - Static Default

    static let empty = GameState(
        totalPointsEarned: 0,
        totalPointsSpent: 0,
        currentPoints: 0,
        challengesCompleted: 0,
        totalChallenges: 0,
        secretChallengesFound: 0,
        secretChallengesCompleted: 0,
        rewardsUnlocked: 0,
        totalRewards: 0,
        allRewardsUnlocked: false,
        finalBadgeUnlocked: false,
        finalBadgeUnlockedAt: nil,
        gameStartedAt: nil,
        currentDay: 1,
        updatedAt: nil
    )
}

// MARK: - Wire Format

extension GameState {

    /// Field names as they are spelled in Firestore. These strings are the actual contract
    /// with the database — the rules compare against them literally and no compiler checks
    /// them — so they are named once here rather than repeated at each read site.
    enum WireKey {
        static let totalPointsEarned = "totalPointsEarned"
        static let totalPointsSpent = "totalPointsSpent"
        static let currentPoints = "currentPoints"
        static let challengesCompleted = "challengesCompleted"
        static let totalChallenges = "totalChallenges"
        static let secretChallengesFound = "secretChallengesFound"
        static let secretChallengesCompleted = "secretChallengesCompleted"
        static let rewardsUnlocked = "rewardsUnlocked"
        static let totalRewards = "totalRewards"
        static let allRewardsUnlocked = "allRewardsUnlocked"
        static let finalBadgeUnlocked = "finalBadgeUnlocked"
        static let finalBadgeUnlockedAt = "finalBadgeUnlockedAt"
        static let gameStartedAt = "gameStartedAt"
        static let currentDay = "currentDay"
        static let updatedAt = "updatedAt"
    }

    /// Parses a `state/main` document body.
    ///
    /// Extracted from `FirestoreService.listenToGameState` so the field-name literals are
    /// reachable from a test. They were not: the parse lived inside the one type every Swift
    /// test replaces with `MockGameBackend`, so a typo in any single key silently yielded `0`
    /// for that counter forever — no compile error, no failing test, and a scoreboard that
    /// reads as a legitimately zeroed game.
    ///
    /// Every field falls back rather than failing. A partial document is the normal case:
    /// `createOccasion` seeds a subset, and documents written before a counter existed are
    /// still valid. `currentDay` falls back to 1 because day zero is not a thing.
    init(wire data: [String: Any]) {
        func int(_ key: String, default fallback: Int = 0) -> Int {
            (data[key] as? NSNumber)?.intValue ?? fallback
        }
        func bool(_ key: String) -> Bool {
            data[key] as? Bool ?? false
        }
        func date(_ key: String) -> Date? {
            (data[key] as? Timestamp)?.dateValue()
        }

        self.init(
            totalPointsEarned: int(WireKey.totalPointsEarned),
            totalPointsSpent: int(WireKey.totalPointsSpent),
            currentPoints: int(WireKey.currentPoints),
            challengesCompleted: int(WireKey.challengesCompleted),
            totalChallenges: int(WireKey.totalChallenges),
            secretChallengesFound: int(WireKey.secretChallengesFound),
            secretChallengesCompleted: int(WireKey.secretChallengesCompleted),
            rewardsUnlocked: int(WireKey.rewardsUnlocked),
            totalRewards: int(WireKey.totalRewards),
            allRewardsUnlocked: bool(WireKey.allRewardsUnlocked),
            finalBadgeUnlocked: bool(WireKey.finalBadgeUnlocked),
            finalBadgeUnlockedAt: date(WireKey.finalBadgeUnlockedAt),
            gameStartedAt: date(WireKey.gameStartedAt),
            currentDay: int(WireKey.currentDay, default: 1),
            updatedAt: date(WireKey.updatedAt)
        )
    }
}
