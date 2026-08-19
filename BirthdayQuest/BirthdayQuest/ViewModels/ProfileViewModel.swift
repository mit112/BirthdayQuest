import Foundation
import SwiftUI
import Combine

/// Owns the friend-facing "have I sent my secret dare yet?" status on the Profile tab.
///
/// Small on purpose: the rest of Profile reads straight from `SessionManager`, so this only
/// exists to keep the Firestore listener out of the view body and make the status logic
/// testable with a `MockGameBackend`.
@MainActor
final class ProfileViewModel: ObservableObject {

    /// Status of the signed-in friend's secret challenge, ready for display.
    enum SecretChallengeStatus: String {
        case unknown = "—"
        case none = "None"
        case draft = "📝 Draft"
        case sent = "📨 Sent"
        case done = "✅ Done"
    }

    @Published var secretChallengeStatus: SecretChallengeStatus = .unknown

    private let service: GameBackend
    private let listenerKey = "profile_secret_status"

    init(service: GameBackend = FirestoreService.shared) {
        self.service = service
    }

    func startListening(userId: String) {
        service.listenToChallenges(listenerKey: listenerKey) { [weak self] challenges in
            let status = Self.status(for: userId, in: challenges)
            Task { @MainActor in
                self?.secretChallengeStatus = status
            }
        }
    }

    func stopListening() {
        service.removeListener(forKey: listenerKey)
    }

    /// Pure mapping from the challenge list to a display status. Static and side-effect free
    /// so it can be tested directly without a listener.
    static func status(for userId: String, in challenges: [Challenge]) -> SecretChallengeStatus {
        guard let mine = challenges.first(where: { $0.isSecret && $0.createdByUserId == userId }) else {
            return .none
        }
        if mine.isCompleted { return .done }
        if mine.isDelivered { return .sent }
        return .draft
    }
}
