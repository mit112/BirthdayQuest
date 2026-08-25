import Foundation
import FirebaseFirestore

// MARK: - Report Model

/// A member's flag on a piece of content, for the host to review.
///
/// `contentType` is generic (`"reward"` today, `"challenge"` later) so a future content type
/// needs no rules change. No hand-written `init(from:)` — see the `@DocumentID` rule.
struct Report: Identifiable, Codable {
    @DocumentID var id: String?
    let contentType: String
    let contentId: String
    let reportedByUserId: String
    let reason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, contentType, contentId, reportedByUserId, reason, createdAt
    }
}
