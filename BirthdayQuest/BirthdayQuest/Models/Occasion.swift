import Foundation
import FirebaseFirestore

// MARK: - Occasion Type

enum OccasionType: String, Codable, CaseIterable {
    case birthday
    case anniversary
    case graduation
    case farewell
    case bachelor

    var displayName: String {
        switch self {
        case .birthday:    return "Birthday"
        case .anniversary: return "Anniversary"
        case .graduation:  return "Graduation"
        case .farewell:    return "Farewell"
        case .bachelor:    return "Bachelor/ette"
        }
    }

    /// What the app calls the person being celebrated. Replaces the hardcoded, gendered
    /// "Birthday Boy" copy that the audit found scattered through the views.
    var celebrantLabel: String {
        switch self {
        case .birthday:    return "Birthday Star"
        case .anniversary: return "Happy Couple"
        case .graduation:  return "Graduate"
        case .farewell:    return "Guest of Honour"
        case .bachelor:    return "Guest of Honour"
        }
    }
}

// MARK: - Occasion

/// One celebration. The tenant boundary: all challenges, rewards, timeline entries and
/// game state live in subcollections of this document.
struct Occasion: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let occasionType: OccasionType
    let celebrantName: String
    let hostUid: String
    /// Sorting, reminders, and the media-purge backstop. Deliberately gates nothing.
    let occasionDate: Date
    var isOpen: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, occasionType, celebrantName, hostUid
        case occasionDate, isOpen, createdAt
    }
}

// MARK: - Invite Codes

/// One occasion's two invite codes.
///
/// Stored at `events/{eventId}/private/codes`, which only the host can read. They are
/// deliberately NOT on the `Occasion` document: that is readable by every member, and an
/// invite code is a bearer secret. Whoever holds the celebrant code can claim celebrant, and
/// the celebrant is the one role allowed to delete gift media — so publishing the code to
/// every member let any recipient of the broadly-shared contributor link destroy every gift.
///
/// `eventId` is not a stored field; it is the parent path, filled in by the backend so a
/// share link can be built from this value alone.
struct InviteCodes: Equatable {
    let eventId: String
    let contributorCode: String
    let celebrantCode: String

    var contributorLink: URL? { Self.joinLink(eventId: eventId, code: contributorCode) }
    var celebrantLink: URL? { Self.joinLink(eventId: eventId, code: celebrantCode) }

    /// `nil` rather than a broken URL.
    ///
    /// `URL(string: "birthdayquest://join?e=&c=")` is a perfectly valid URL, so interpolating
    /// an empty id or code used to yield a shareable link that could never resolve, with
    /// nothing to tell the host it was dead. A consumed celebrant code is empty, so this
    /// correctly reports that link as gone rather than offering it again.
    static func joinLink(eventId: String, code: String) -> URL? {
        guard EventID.isValid(eventId), InviteCode.isWellFormed(code) else { return nil }
        return URL(string: "birthdayquest://join?e=\(eventId)&c=\(code)")
    }
}

extension InviteCodes {
    /// `eventId` comes from the parent path rather than the document body, so this cannot be
    /// a plain `Codable` decode.
    init?(eventId: String, data: [String: Any]?) {
        guard let data,
              let contributorCode = data["contributorCode"] as? String,
              let celebrantCode = data["celebrantCode"] as? String
        else { return nil }
        self.eventId = eventId
        self.contributorCode = contributorCode
        self.celebrantCode = celebrantCode
    }
}
