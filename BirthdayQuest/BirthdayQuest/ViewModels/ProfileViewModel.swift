import Foundation
import SwiftUI
import Combine

/// Owns the friend-facing "have I sent my secret dare yet?" status on the Profile tab.
///
/// Small on purpose: the rest of Profile reads straight from `EventSession`, so this only
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
    private let eventId: String
    private let listenerKey: String

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.scoped("profile_secret_status", eventId: eventId)
    }

    func startListening(userId: String) {
        service.listenToChallenges(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            guard case .success(let challenges) = result else { return }
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
