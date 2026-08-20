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
    /// The two invite codes, stored here because `inviteCodes` is deny-all read — the host
    /// must be able to reshare their link, and members can read the event document.
    let contributorCode: String
    let celebrantCode: String

    var contributorLink: URL? {
        URL(string: "birthdayquest://join?e=\(id ?? "")&c=\(contributorCode)")
    }

    var celebrantLink: URL? {
        URL(string: "birthdayquest://join?e=\(id ?? "")&c=\(celebrantCode)")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, occasionType, celebrantName, hostUid
        case occasionDate, isOpen, createdAt, contributorCode, celebrantCode
    }
}
