import Foundation
import FirebaseFirestore

// MARK: - Submission Type

enum SubmissionType: String, Codable, CaseIterable {
    case photo
    case text
    case button
    
    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .text: return "text.cursor"
        case .button: return "checkmark.circle.fill"
        }
    }
    
    var label: String {
        switch self {
        case .photo: return "Photo"
        case .text: return "Text"
        case .button: return "Done"
        }
    }
    
    // Graceful fallback: any old "video" docs in Firestore decode as photo
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = SubmissionType(rawValue: value) ?? .photo
    }
}

// MARK: - Difficulty

enum ChallengeDifficulty: String, Codable, CaseIterable {
    case easy, medium, hard
    
    var stars: Int {
        switch self {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }
    
    var color: String {
        switch self {
        case .easy: return "4CAF50"
        case .medium: return "FF9800"
        case .hard: return "F44336"
        }
    }
}

// MARK: - Category

enum ChallengeCategory: String, Codable, CaseIterable {
    case physical, social, creative, sentimental, adventure
    
    var icon: String {
        switch self {
        case .physical: return "figure.walk"
        case .social: return "person.2.fill"
        case .creative: return "paintbrush.fill"
        case .sentimental: return "heart.fill"
        case .adventure: return "map.fill"
        }
    }
}

// MARK: - Challenge Model

struct Challenge: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let description: String
    let illustrationAsset: String
    let pointValue: Int
    let difficulty: ChallengeDifficulty
    let category: ChallengeCategory
    let isSecret: Bool
    let createdByUserId: String?
    var isDelivered: Bool
    var isCompleted: Bool
    var completedAt: Date?
    var proofUrl: String?
    var proofType: String?
    var proofText: String?
    let createdAt: Date
    
    // MARK: - 2-in-1 Challenge Support
    /// When non-nil, this challenge presents two options in the detail view.
    let optionBTitle: String?
    let optionBDescription: String?
    
    // MARK: - Computed
    
    var isPending: Bool { !isCompleted }
    var isTwoInOne: Bool { optionBTitle != nil }
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, illustrationAsset
        case pointValue, difficulty, category
        case isSecret, createdByUserId, isDelivered, isCompleted
        case completedAt, proofUrl, proofType, proofText, createdAt
        case optionBTitle, optionBDescription
    }
    
    // Memberwise init for code usage
    init(
        id: String? = nil,
        title: String,
        description: String,
        illustrationAsset: String,
        pointValue: Int,
        difficulty: ChallengeDifficulty,
        category: ChallengeCategory,
        isSecret: Bool,
        createdByUserId: String?,
        isDelivered: Bool,
        isCompleted: Bool,
        completedAt: Date? = nil,
        proofUrl: String? = nil,
        proofType: String? = nil,
        proofText: String? = nil,
        createdAt: Date,
        optionBTitle: String? = nil,
        optionBDescription: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.illustrationAsset = illustrationAsset
        self.pointValue = pointValue
        self.difficulty = difficulty
        self.category = category
        self.isSecret = isSecret
        self.createdByUserId = createdByUserId
        self.isDelivered = isDelivered
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.proofUrl = proofUrl
        self.proofType = proofType
        self.proofText = proofText
        self.createdAt = createdAt
        self.optionBTitle = optionBTitle
        self.optionBDescription = optionBDescription
    }
}
