import Foundation

// MARK: - Firestore Paths

/// Collection and document names. All event content is a subcollection of
/// `events/{eventId}`, which is what makes cross-occasion access impossible to express.
enum Collections {
    static let events = "events"
    static let memberships = "memberships"
    static let inviteCodes = "inviteCodes"

    // Subcollections of an event document
    static let participants = "participants"
    static let challenges = "challenges"
    static let rewards = "rewards"
    static let timeline = "timeline"
    static let state = "state"
    static let stateDoc = "main"
}

// MARK: - Invite Codes

enum InviteCode {
    /// 32 symbols, excluding I, O, 0 and 1 because codes get read aloud and typed by hand.
    /// 32^8 is roughly 2^40 combinations, and each guess costs a denied write.
    static let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 8

    static func generate() -> String {
        String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}

// MARK: - Storage Paths

enum StoragePaths {
    static func rewardMedia(eventId: String, rewardId: String, fileName: String) -> String {
        "\(Collections.events)/\(eventId)/\(Collections.rewards)/\(rewardId)/\(fileName)"
    }

    static func proof(eventId: String, challengeId: String, fileName: String) -> String {
        "\(Collections.events)/\(eventId)/proofs/\(challengeId)/\(fileName)"
    }
}
