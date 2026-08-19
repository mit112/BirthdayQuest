import Foundation

// MARK: - Firestore Collection Names

enum Collections {
    static let users = "users"
    static let rewards = "rewards"
    static let challenges = "challenges"
    static let timelineEvents = "timeline_events"
    static let gameState = "game_state"
    static let gameStateDoc = "main"
}

// MARK: - Character IDs (stable, used everywhere)

enum CharacterID {
    static let alex = "alex"
    static let sam = "sam"
    static let jordan = "jordan"
    static let riley = "riley"
    static let morgan = "morgan"

    static let birthdayBoy = alex
    static let organizer = sam
    static let birthdayBoyName = "Alex"

    static let all: [String] = [alex, sam, jordan, riley, morgan]
}
