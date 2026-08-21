import Foundation
@testable import BirthdayQuest

/// In-memory `AuthProviding` for tests. Mirrors `MockGameBackend`'s shape: records what was
/// asked of it and lets each method be stubbed to succeed or throw.
final class MockAuthProviding: AuthProviding {
    var currentUid: String?
    var isAnonymous = true
    var anonymousSignInCount = 0
    var appleSignIns: [(idToken: String, nonce: String)] = []
    var errorToThrow: Error?

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
}
