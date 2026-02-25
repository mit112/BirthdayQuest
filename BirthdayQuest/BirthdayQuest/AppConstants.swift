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
    static let aaryan = "aaryan"
    static let mit = "mit"
    static let kashish = "kashish"
    static let gaurav = "gaurav"
    static let milloni = "milloni"
    
    static let birthdayBoy = aaryan
    static let organizer = mit
    static let birthdayBoyName = "Aaryan"
    
    static let all: [String] = [aaryan, mit, kashish, gaurav, milloni]
}
