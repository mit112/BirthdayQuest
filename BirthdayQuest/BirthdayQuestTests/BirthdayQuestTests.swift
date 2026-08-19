//
//  BirthdayQuestTests.swift
//  BirthdayQuestTests
//

import Testing
import Foundation
@testable import BirthdayQuest

// Pure-logic tests only. The Firestore layer is a singleton with no protocol seam
// (FirestoreService.shared), so anything touching the backend cannot be tested
// without a live Firebase project. See "Known Limitations" in the README.

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

    @Test("round-trips through Codable without losing progress fields")
    func codableRoundTrip() throws {
        var original = GameState.empty
        original.currentPoints = 250
        original.rewardsUnlocked = 3
        original.totalRewards = 8
        original.finalBadgeUnlocked = false

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)

        #expect(decoded.currentPoints == 250)
        #expect(decoded.rewardsUnlocked == 3)
        #expect(decoded.totalRewards == 8)
        #expect(abs(decoded.rewardProgress - 0.375) < 0.0001)
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
}
