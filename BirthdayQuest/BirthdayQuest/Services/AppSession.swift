import Foundation
import SwiftUI
import Combine
import OSLog

@MainActor
final class AppSession: ObservableObject {

    enum RootState: Equatable {
        case launching
        case empty
        case occasions
    }

    @Published var rootState: RootState = .launching
    @Published var occasions: [Occasion] = []
    @Published var isAnonymous = true
    @Published var errorMessage: String?

    /// An occasion that should be opened as soon as a list is on screen to open it from.
    ///
    /// It lives here, rather than being handed back through the create sheet's completion
    /// handler, because creating the *first* occasion changes `rootState` from `.empty` to
    /// `.occasions` — which replaces the whole root view. The handler therefore fired on a
    /// view already being torn down, and the first occasion a user ever made dropped them on
    /// the list instead of inside it, with no invite link in sight. Routing the request
    /// through the session is what lets it survive that swap, and it means the create flow
    /// behaves identically from either root instead of only from the populated one.
    ///
    /// Whoever acts on it clears it, so a back-swipe out of the occasion does not re-open it.
    @Published var pendingOpenEventId: String?

    /// Friction arrives only once there is something to lose: a user with more than one
    /// occasion, or any host, has accumulated history worth recovering after a reinstall.
    var shouldPromptAppleLink: Bool {
        isAnonymous && occasions.count > 1
    }

    private let service: GameBackend
    private let auth: AuthProviding
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "AppSession")

    init(service: GameBackend = FirestoreService.shared, auth: AuthProviding = AuthService.shared) {
        self.service = service
        self.auth = auth
    }

    func bootstrap() async {
        errorMessage = nil
        do {
            _ = try await auth.signInAnonymouslyIfNeeded()
            isAnonymous = auth.isAnonymous
            await loadOccasions()
        } catch {
            logger.error("Bootstrap failed: \(error.localizedDescription)")
            errorMessage = "Couldn't reach BirthdayQuest. Check your connection and try again."
            // Never leave the user on the splash screen — that was the old bootstrap's
            // failure mode, an indefinite pulse with no explanation.
            rootState = .empty
        }
    }

    func refreshOccasions() async {
        await loadOccasions()
    }

    private func loadOccasions() async {
        do {
            let fetched = try await service.fetchMyOccasions()
            occasions = fetched.sorted { $0.occasionDate > $1.occasionDate }
            rootState = fetched.isEmpty ? .empty : .occasions
            // A message from an earlier failed attempt must not outlive the retry that
            // fixed it — the empty state renders it unconditionally.
            errorMessage = nil
        } catch {
            logger.error("Loading occasions failed: \(error.localizedDescription)")
            errorMessage = "Couldn't load your occasions."
            rootState = occasions.isEmpty ? .empty : .occasions
        }
    }

    func linkApple(idToken: String, nonce: String) async {
        errorMessage = nil
        do {
            try await auth.signInWithApple(idToken: idToken, nonce: nonce)
            isAnonymous = auth.isAnonymous
            await loadOccasions()
        } catch {
            logger.error("Apple link failed: \(error.localizedDescription)")
            errorMessage = "Couldn't link your Apple ID. You can try again from My Occasions."
        }
    }
}
