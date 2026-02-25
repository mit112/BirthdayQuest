import Foundation
import FirebaseFirestore

// MARK: - User Roles

enum UserRole: String, Codable, CaseIterable {
    case birthdayBoy = "birthday_boy"
    case friend = "friend"
    case organizer = "organizer"
    
    var displayName: String {
        switch self {
        case .birthdayBoy: return "The Birthday King 👑"
        case .friend: return "Secret Agent 🕵️"
        case .organizer: return "Secret Agent 🕵️"
        }
    }
    
    var isBirthdayBoy: Bool { self == .birthdayBoy }
    var isFriend: Bool { self == .friend || self == .organizer }
    var isOrganizer: Bool { self == .organizer }
}

// MARK: - User Model

struct BQUser: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let role: UserRole
    let avatarId: String
    let tagline: String
    let funFacts: [String]
    let roleBadge: String
    var claimed: Bool
    var deviceId: String?
    var createdAt: Date
    
    // Computed — character select needs this
    var isAvailable: Bool { !claimed }
    
    enum CodingKeys: String, CodingKey {
        case id, name, role, avatarId, tagline
        case funFacts, roleBadge, claimed, deviceId, createdAt
    }
}
