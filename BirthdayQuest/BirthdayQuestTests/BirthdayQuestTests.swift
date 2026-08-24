//
//  BirthdayQuestTests.swift
//  BirthdayQuestTests
//

import Testing
import Foundation
// For `Timestamp`, which is the wire type the game-state parser has to accept.
import FirebaseFirestore
@testable import BirthdayQuest

// Pure model logic — no backend involved, so nothing to inject here.
// View-model behaviour lives in ViewModelTests.swift, which drives MockGameBackend.

@Suite("GameState progress math")
struct GameStateTests {

    @Test("empty default is a zeroed, day-one state")
    func emptyDefault() {
        let s = GameState.empty
        #expect(s.currentPoints == 0)
        #expect(s.challengesCompleted == 0)
        #expect(s.finalBadgeUnlocked == false)
        #expect(s.currentDay == 1)
    }

    @Test("progress is zero when the denominator is zero, not a crash or NaN")
    func zeroDenominatorIsSafe() {
        let s = GameState.empty
        #expect(s.challengeProgress == 0)
        #expect(s.rewardProgress == 0)
        #expect(!s.challengeProgress.isNaN)
        #expect(!s.rewardProgress.isNaN)
    }

    @Test("progress fractions match completed over total", arguments: [
        (0, 13, 0.0),
        (13, 13, 1.0),
        (9, 12, 0.75),
    ])
    func challengeProgressFraction(done: Int, total: Int, expected: Double) {
        var s = GameState.empty
        s.challengesCompleted = done
        s.totalChallenges = total
        #expect(abs(s.challengeProgress - expected) < 0.0001)
    }

    @Test("points display uses the star glyph the UI expects")
    func pointsDisplay() {
        var s = GameState.empty
        s.currentPoints = 715
        #expect(s.pointsDisplay == "✦ 715")
    }

}

// MARK: - Wire Parser

/// The parse that reads `events/{id}/state/main`.
///
/// It lived inside `FirestoreService` — the one type every other Swift test replaces with
/// `MockGameBackend` — so none of its field-name literals was reachable. A typo in any single
/// key yielded `0` for that counter forever: no compile error, no failing test, and a
/// scoreboard that reads exactly like a legitimately zeroed game.
@Suite("GameState wire parser")
struct GameStateWireTests {

    /// Every value distinct, so a key wired to the wrong field fails rather than coinciding.
    private static let fullDocument: [String: Any] = [
        "totalPointsEarned": NSNumber(value: 715),
        "totalPointsSpent": NSNumber(value: 250),
        "currentPoints": NSNumber(value: 465),
        "challengesCompleted": NSNumber(value: 9),
        "totalChallenges": NSNumber(value: 13),
        "secretChallengesFound": NSNumber(value: 4),
        "secretChallengesCompleted": NSNumber(value: 2),
        "rewardsUnlocked": NSNumber(value: 3),
        "totalRewards": NSNumber(value: 8),
        "allRewardsUnlocked": true,
        "finalBadgeUnlocked": true,
        "currentDay": NSNumber(value: 6)
    ]

    /// Two assertions per key, and both are needed.
    ///
    /// The first pins the key to *its own* field — every value in `fullDocument` is distinct,
    /// so a key wired to the wrong field fails instead of coincidentally matching.
    ///
    /// The second is the vacuity guard, and it is the one that would have caught the original
    /// bug: removing the key must change the parse. A test that only reads a fully-populated
    /// document passes just as happily against a parser that never mentions the key at all,
    /// because the expected value and the fallback are both whatever the document said.
    @Test("each counter is read from its own key, and only from that key", arguments: [
        ("totalPointsEarned", 715, \GameState.totalPointsEarned),
        ("totalPointsSpent", 250, \GameState.totalPointsSpent),
        ("currentPoints", 465, \GameState.currentPoints),
        ("challengesCompleted", 9, \GameState.challengesCompleted),
        ("totalChallenges", 13, \GameState.totalChallenges),
        ("secretChallengesFound", 4, \GameState.secretChallengesFound),
        ("secretChallengesCompleted", 2, \GameState.secretChallengesCompleted),
        ("rewardsUnlocked", 3, \GameState.rewardsUnlocked),
        ("totalRewards", 8, \GameState.totalRewards),
        ("currentDay", 6, \GameState.currentDay)
    ] as [(String, Int, KeyPath<GameState, Int>)])
    func counterIsReadFromItsOwnKey(
        key: String, expected: Int, field: KeyPath<GameState, Int>
    ) {
        let full = GameState(wire: Self.fullDocument)
        #expect(full[keyPath: field] == expected, "\(key) did not reach its field")

        var without = Self.fullDocument
        without.removeValue(forKey: key)
        let partial = GameState(wire: without)

        #expect(
            partial[keyPath: field] != expected,
            "removing \(key) left the field unchanged — the parser never reads that key"
        )
    }

    @Test("booleans parse, and default to false when absent")
    func booleans() {
        let present = GameState(wire: Self.fullDocument)
        #expect(present.allRewardsUnlocked)
        #expect(present.finalBadgeUnlocked)

        let absent = GameState(wire: [:])
        #expect(absent.allRewardsUnlocked == false)
        #expect(absent.finalBadgeUnlocked == false)
    }

    @Test("timestamps convert to dates")
    func timestamps() {
        let moment = Date(timeIntervalSince1970: 1_770_000_000)
        let state = GameState(wire: [
            "finalBadgeUnlockedAt": Timestamp(date: moment),
            "gameStartedAt": Timestamp(date: moment),
            "updatedAt": Timestamp(date: moment)
        ])

        #expect(state.finalBadgeUnlockedAt == moment)
        #expect(state.gameStartedAt == moment)
        #expect(state.updatedAt == moment)
    }

    @Test("an empty document parses to the zeroed day-one state, not a failure")
    func emptyDocument() {
        #expect(GameState(wire: [:]) == .empty)
    }

    /// `currentDay` is the one counter whose fallback is not zero. A game is on day 1 before
    /// anything has happened; day 0 would render as "Day 0" on the host panel.
    @Test("currentDay falls back to 1, not 0")
    func currentDayFallback() {
        #expect(GameState(wire: [:]).currentDay == 1)
        #expect(GameState(wire: ["currentDay": NSNumber(value: 4)]).currentDay == 4)
    }

    /// Firestore hands integers back as `NSNumber`, and the width it picks is not ours to
    /// choose — this is the Int64/Int mismatch that made `Codable` unusable here.
    @Test("an Int64-backed NSNumber still reads as an Int")
    func int64Widths() {
        let state = GameState(wire: ["currentPoints": NSNumber(value: Int64(465))])
        #expect(state.currentPoints == 465)
    }

    /// A wrongly-typed value must fall back rather than trap. `as? NSNumber` on a string is
    /// nil, and the alternative — a force-unwrap or an `as!` — would crash the listener for
    /// every member of the occasion, permanently, on one bad field.
    @Test("a wrongly-typed value falls back instead of crashing")
    func wrongTypes() {
        let state = GameState(wire: [
            "currentPoints": "465",
            "updatedAt": "not-a-timestamp"
        ])
        #expect(state.currentPoints == 0, "a String does not bridge to NSNumber")
        #expect(state.updatedAt == nil)
    }

    /// Not a fallback case — a genuine bridging behaviour worth pinning.
    ///
    /// `NSNumber(value: 1) as? Bool` **succeeds** and yields `true`, because `NSNumber`
    /// bridges to `Bool`. That is what we want here: Firestore is free to hand a boolean back
    /// as an `NSNumber`, and a strict `as? Bool` that rejected it would silently read every
    /// such document as `false` — which for `finalBadgeUnlocked` means the final celebration
    /// never fires. Asserted rather than assumed, because it reads like a bug otherwise.
    @Test("a boolean delivered as NSNumber still reads as true")
    func numericBooleans() {
        #expect(GameState(wire: ["finalBadgeUnlocked": NSNumber(value: 1)]).finalBadgeUnlocked)
        #expect(GameState(wire: ["finalBadgeUnlocked": NSNumber(value: 0)]).finalBadgeUnlocked == false)
    }
}

@Suite("Challenge model")
struct ChallengeModelTests {

    @Test("difficulty maps to the documented star count")
    func difficultyStars() {
        #expect(ChallengeDifficulty.easy.stars == 1)
        #expect(ChallengeDifficulty.medium.stars == 2)
        #expect(ChallengeDifficulty.hard.stars == 3)
    }

    @Test("every difficulty and category exposes a non-empty icon or color")
    func enumsAreFullyPopulated() {
        for d in ChallengeDifficulty.allCases {
            #expect(!d.color.isEmpty, "difficulty \(d.rawValue) has no color")
        }
        for c in ChallengeCategory.allCases {
            #expect(!c.icon.isEmpty, "category \(c.rawValue) has no icon")
        }
        for t in SubmissionType.allCases {
            #expect(!t.icon.isEmpty)
            #expect(!t.label.isEmpty)
        }
    }

    @Test("isTwoInOne treats a stored empty optionBTitle as off, not on with a blank option")
    func isTwoInOneTreatsEmptyAsOff() {
        #expect(Challenge.fixture(optionBTitle: "").isTwoInOne == false)
        #expect(Challenge.fixture(optionBTitle: "Sing a duet").isTwoInOne == true)
    }
}
