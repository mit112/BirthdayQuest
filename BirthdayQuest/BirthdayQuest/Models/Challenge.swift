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
    let submissionType: SubmissionType
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
    
    // MARK: - Computed
    
    var isPending: Bool { !isCompleted }
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, illustrationAsset
        case pointValue, difficulty, submissionType, category
        case isSecret, createdByUserId, isDelivered, isCompleted
        case completedAt, proofUrl, proofType, proofText, createdAt
    }
}
