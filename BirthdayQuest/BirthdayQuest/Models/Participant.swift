import Foundation
import FirebaseFirestore

// MARK: - Participant Mode

/// How a participant plays. Orthogonal to `isHost`, which is a permission — this is why
/// a host can also be the celebrant.
enum ParticipantMode: String, Codable, CaseIterable {
    case contributor
    case celebrant
}

// MARK: - Participant

/// Membership in one occasion. The document ID is the Firebase uid, which is what makes
/// impersonation structurally impossible: rules only permit writing your own document.
struct Participant: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var avatarId: String
    let mode: ParticipantMode
    let isHost: Bool
    /// The invite code presented at join. Rules read this to validate the join; it is never
    /// displayed. The host's own document carries the contributor code.
    let usedCode: String

    var isCelebrant: Bool { mode == .celebrant }

    enum CodingKeys: String, CodingKey {
        case id, name, avatarId, mode, isHost, usedCode
    }
}
