import Foundation
import FirebaseFirestore

// MARK: - Game State (Single Document)

struct GameState: Codable {
    let birthdayBoyId: String
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
        birthdayBoyId: "",
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
