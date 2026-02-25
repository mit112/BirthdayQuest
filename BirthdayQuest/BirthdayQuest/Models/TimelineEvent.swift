import Foundation
import FirebaseFirestore

// MARK: - Timeline Event Type

enum TimelineEventType: String, Codable {
    case challengeCompleted = "challenge_completed"
    case rewardUnlocked = "reward_unlocked"
    
    var accentColorHex: String {
        switch self {
        case .challengeCompleted: return "5B9FE6" // Blue tint
        case .rewardUnlocked: return "F5A623"     // Golden tint
        }
    }
}

// MARK: - Badge Type

enum TimelineBadgeType: String, Codable {
    case challenge
    case reward
}

// MARK: - Timeline Event Model

struct TimelineEvent: Identifiable, Codable {
    @DocumentID var id: String?
    let type: TimelineEventType
    let referenceId: String
    let title: String
    let subtitle: String
    let badgeType: TimelineBadgeType
    let badgeAsset: String
    let fromFriendName: String?
    let fromFriendAvatar: String?
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case id, type, referenceId, title, subtitle
        case badgeType, badgeAsset, fromFriendName, fromFriendAvatar, timestamp
    }
}
