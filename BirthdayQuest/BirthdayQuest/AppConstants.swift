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

// MARK: - Listener Keys

/// Firestore listener registry keys, one namespace per event.
///
/// Registration and removal happen in different types — a view model starts a listener, its
/// `stopListening()` (or `EventSession.stop()`) removes it — so the key has to be composed
/// the same way in both places. Composing it here, rather than by repeating a string
/// literal, is what makes `removeListener(forKey:)` provably tear down the listener that was
/// registered and no other occasion's.
enum ListenerKey {

    static func scoped(_ name: String, eventId: String) -> String {
        "\(name)@\(eventId)"
    }

    static func rewards(_ eventId: String) -> String { scoped("rewards", eventId: eventId) }
    static func challenges(_ eventId: String) -> String { scoped("challenges", eventId: eventId) }
    static func timeline(_ eventId: String) -> String { scoped("timeline", eventId: eventId) }
    static func gameState(_ eventId: String) -> String { scoped("gameState", eventId: eventId) }
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
