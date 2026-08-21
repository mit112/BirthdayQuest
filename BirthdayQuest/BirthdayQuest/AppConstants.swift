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
    /// Host-only-readable corner of an event. The invite codes live here rather than on the
    /// event document, which every member can read — a bearer secret published to every
    /// member is not an authorisation factor.
    static let privateData = "private"
    static let codesDoc = "codes"
}

// MARK: - Invite Codes

enum InviteCode {
    /// 32 symbols, excluding I, O, 0 and 1 because codes get read aloud and typed by hand.
    /// 32^8 is roughly 2^40 combinations, and each guess costs a denied write.
    static let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 8

    private static let alphabetSet = Set(alphabet)

    static func generate() -> String {
        String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    /// Exactly `length` characters, every one of them from `alphabet`.
    ///
    /// This is a safety check, not just input hygiene. A code becomes a Firestore document
    /// id, and `CollectionReference.document(_:)` treats its argument as a *path*: a `/`
    /// makes the segment count odd and a `//` is rejected outright, and both raise an
    /// Objective-C `NSException` from the C++ core that no Swift `do/catch` can intercept —
    /// the process dies with SIGABRT. Since `alphabet` contains no `/`, `.` or `_`, anything
    /// this accepts is also a legal document id.
    static func isWellFormed(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(alphabetSet.contains)
    }

    /// Trim, uppercase, then validate — in that order, deliberately.
    ///
    /// Uppercasing first is what lets a hand-typed lowercase code work at all, since the
    /// alphabet is uppercase-only. Validating afterwards is what makes the result safe as a
    /// path segment, because the check is applied to the exact string that will be used.
    /// The two orders differ for non-ASCII input ("ß".uppercased() is "SS", two characters),
    /// and validating last is the order where that cannot smuggle anything through.
    ///
    /// Rejects rather than repairs: silently stripping stray characters would turn a typo
    /// into a lookup of somebody else's code.
    static func normalized(_ raw: String) -> String? {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return isWellFormed(candidate) ? candidate : nil
    }
}

// MARK: - Event IDs

/// Validation for event ids that arrive from outside the app — the `e` parameter of a
/// `birthdayquest://join` deep link, and the `eventId` field of an `inviteCodes` document,
/// which any signed-in client may write.
///
/// Same hazard as `InviteCode.isWellFormed`: an id is interpolated into a Firestore path,
/// and a malformed one aborts the process rather than throwing. Registering the URL scheme
/// widened that from "the user pasted the wrong thing" to "anyone who can send this user a
/// link can crash their app on tap", so it is checked before any path is built.
enum EventID {

    /// Firestore's own document-id limit.
    static let maxByteLength = 1500

    static func isValid(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= maxByteLength else { return false }
        // A `/` splits the string into extra path segments; `//` is rejected outright.
        guard !id.contains("/") else { return false }
        // Firestore forbids these three shapes for document ids.
        guard id != ".", id != ".." else { return false }
        guard !id.hasPrefix("__") else { return false }
        return true
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
