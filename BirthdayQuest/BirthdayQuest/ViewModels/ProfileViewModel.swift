import Foundation
import SwiftUI
import Combine
import OSLog

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
    /// Set when the listener fails. Membership is revocable, so permission-denied is an
    /// expected outcome here, not an impossible one — leaving the status on "—" would make
    /// a revoked contributor look like one who simply hasn't written a dare.
    @Published var errorMessage: String?

    private let service: GameBackend
    private let eventId: String
    private let listenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Profile")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.listenerKey = ListenerKey.scoped("profile_secret_status", eventId: eventId)
    }

    func startListening(userId: String) {
        service.listenToChallenges(eventId: eventId, listenerKey: listenerKey) { [weak self] result in
            switch result {
            case .success(let challenges):
                let status = Self.status(for: userId, in: challenges)
                Task { @MainActor in
                    self?.secretChallengeStatus = status
                    self?.errorMessage = nil
                }
            case .failure(let error):
                Task { @MainActor in
                    guard let self else { return }
                    self.logger.error("Secret dare status listener: \(error.localizedDescription)")
                    self.secretChallengeStatus = .unknown
                    self.errorMessage = "Couldn't check your secret dare."
                }
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
