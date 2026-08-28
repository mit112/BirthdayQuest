import Foundation
import SwiftUI
import Combine
import OSLog

/// Drives in-app account deletion (App Store Guideline 5.1.1(v)).
///
/// Deletion is anonymise-and-keep. What goes is who the user was: their participant document
/// in every occasion — the name, the avatar and the invite code they presented — and every
/// membership mirror row. What stays is what they made for other people: the gifts, the dares,
/// the timeline entries. A celebrant must not lose a present because the person who sent it
/// closed their account, and there is no way to give it back once it is gone.
///
/// The two halves are ordered and the order is not a preference. Firestore first, auth user
/// last: every security rule in this app is written against `request.auth.uid`, so a document
/// still naming a deleted uid is unreachable and undeletable by anyone, forever — including
/// the person it describes.
@MainActor
final class DeleteAccountViewModel: ObservableObject {

    /// The confirmation gate. Lives here rather than in the view so the warning copy and the
    /// hosted-occasion list it has to mention are read from one place at one moment.
    @Published var isConfirming = false
    @Published private(set) var isDeleting = false
    @Published private(set) var errorMessage: String?

    /// Set once, after both halves have succeeded, and never cleared. The view watches it to
    /// leave the account UI — there is no signed-in state left to return to.
    @Published private(set) var didDelete = false

    /// Occasions this user hosts, by name. They survive deletion untouched — the event
    /// document, the gifts, the remaining members — but the only uid that could administer
    /// them will not, and host transfer is not a feature. So this has to be shown before the
    /// fact; there is no discovering it afterwards.
    @Published private(set) var hostedOccasionNames: [String] = []

    var hostsAnyOccasion: Bool { !hostedOccasionNames.isEmpty }

    private let service: GameBackend
    private let auth: AuthProviding
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "DeleteAccount")

    init(service: GameBackend = FirestoreService.shared, auth: AuthProviding = AuthService.shared) {
        self.service = service
        self.auth = auth
    }

    /// Loads the hosted-occasion warning. Call before presenting the confirmation.
    ///
    /// A failure here does not block deletion — the user is entitled to close their account
    /// whether or not this list loaded — but it does surface, because a silently empty list
    /// is indistinguishable from "you host nothing", and that is the one thing the warning
    /// exists to tell them.
    func loadHostedOccasions() async {
        guard let uid = auth.currentUid else { return }
        do {
            let occasions = try await service.fetchMyOccasions()
            hostedOccasionNames = occasions.filter { $0.hostUid == uid }.map(\.name)
        } catch {
            logger.error("Couldn't load hosted occasions: \(error.localizedDescription)")
            errorMessage = "Couldn't check which occasions you host. You can still delete your account."
        }
    }

    func requestDelete() {
        errorMessage = nil
        isConfirming = true
    }

    func cancelDelete() {
        isConfirming = false
    }

    /// Runs both halves in order and stops at the first failure.
    ///
    /// The `catch` is the load-bearing part: `deleteMyAccountData()` throws rather than
    /// pressing on, so reaching `auth.deleteAccount()` at all means the Firestore cleanup
    /// returned cleanly. A failed cleanup leaves the account intact and retryable, which is
    /// the only recoverable ordering of the two.
    func confirmDelete() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil

        do {
            try await service.deleteMyAccountData()
            try await auth.deleteAccount()
            isConfirming = false
            didDelete = true
        } catch let error as AuthError {
            // Carries its own copy — `requiresRecentLogin` in particular has to say "sign in
            // again", because retrying cannot ever clear it.
            logger.error("Account deletion failed at the auth step: \(error.localizedDescription)")
            errorMessage = error.errorDescription
        } catch {
            logger.error("Account deletion failed: \(error.localizedDescription)")
            errorMessage = "Couldn't delete your account. Check your connection and try again."
        }

        isDeleting = false
    }
}
