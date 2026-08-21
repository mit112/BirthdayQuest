import Foundation
import FirebaseFirestore

// MARK: - Reward Content Type

enum RewardContentType: String, Codable, CaseIterable {
    case video
    case audio
    case text
    case image
    
    var icon: String {
        switch self {
        case .video: return "play.circle.fill"
        case .audio: return "waveform.circle.fill"
        case .text: return "text.bubble.fill"
        case .image: return "photo.fill"
        }
    }
}

// MARK: - Reward Model

struct Reward: Identifiable, Codable {
    @DocumentID var id: String?
    let fromUserId: String?
    let fromName: String
    let title: String
    let teaser: String?
    let pointCost: Int
    let contentType: RewardContentType
    let contentUrl: String?
    let contentUrls: [String]?
    let contentText: String?
    var isUnlocked: Bool
    var unlockedAt: Date?
    let sortOrder: Int
    let badgeIllustration: String
    let createdAt: Date
    /// uids that have downloaded and locally persisted this reward's media. When every
    /// recipient appears here, the Storage object is deleted by the celebrant's device.
    var fetchedBy: [String]?

    enum CodingKeys: String, CodingKey {
        case id, fromUserId, fromName, title, teaser
        case pointCost, contentType, contentUrl, contentUrls, contentText
        case isUnlocked, unlockedAt, sortOrder, badgeIllustration, createdAt, fetchedBy
    }
}
