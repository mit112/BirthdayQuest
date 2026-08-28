import Foundation
@testable import BirthdayQuest

/// In-memory `AuthProviding` for tests. Mirrors `MockGameBackend`'s shape: records what was
/// asked of it and lets each method be stubbed to succeed or throw.
final class MockAuthProviding: AuthProviding {
    var currentUid: String?
    var isAnonymous = true
    var anonymousSignInCount = 0
    var appleSignIns: [(idToken: String, nonce: String)] = []
    var accountDeletionCount = 0
    var errorToThrow: Error?

    /// Fired at the top of `deleteAccount()`, before it records anything. The ordering that
    /// account deletion depends on — Firestore data first, the auth user last — is the one
    /// thing two independent mocks cannot prove between them, so this is the shared
    /// observation point: a test snapshots `MockGameBackend.calls` from here.
    var onDeleteAccount: (() -> Void)?

    func signInAnonymouslyIfNeeded() async throws -> String {
        if let errorToThrow { throw errorToThrow }
        if let currentUid { return currentUid }
        anonymousSignInCount += 1
        let uid = "uid_anon_\(anonymousSignInCount)"
        currentUid = uid
        return uid
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        if let errorToThrow { throw errorToThrow }
        appleSignIns.append((idToken, nonce))
        isAnonymous = false
        currentUid = "uid_apple"
    }

    func deleteAccount() async throws {
        onDeleteAccount?()
        if let errorToThrow { throw errorToThrow }
        accountDeletionCount += 1
        currentUid = nil
    }
}
