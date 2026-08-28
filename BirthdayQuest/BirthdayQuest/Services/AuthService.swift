import Foundation
import FirebaseAuth
import CryptoKit
import OSLog

// MARK: - AuthProviding

/// The identity surface the app depends on.
///
/// Mirrors `GameBackend`: `AuthService` is the production implementation, `MockAuthProviding`
/// (in `BirthdayQuestTests/`) is the test double, and both are injected via a default
/// argument — nothing outside a DI default should reference `AuthService.shared` directly.
protocol AuthProviding: AnyObject {
    var currentUid: String? { get }
    var isAnonymous: Bool { get }
    func signInAnonymouslyIfNeeded() async throws -> String
    func signInWithApple(idToken: String, nonce: String) async throws

    /// Deletes the signed-in Firebase Auth user. Identity only — it touches no Firestore
    /// document, because the two halves of account deletion have to be ordered and the
    /// ordering is one-way: every rule in this app is written against `request.auth.uid`,
    /// so once this returns nothing can satisfy any of them again. Whatever Firestore data
    /// still names that uid is then unreachable even by the person it describes. Call
    /// `GameBackend.deleteMyAccountData()` first, and only call this if it succeeded.
    func deleteAccount() async throws
}

// MARK: - AuthService

/// Anonymous-by-default identity, upgradeable to Sign in with Apple.
///
/// Delegates every Firebase Auth call to an injected `AuthProviding`, defaulting to
/// `FirebaseAuthProvider`. That seam exists so the "skip sign-in if a uid already exists"
/// guard below — the entire point of `signInAnonymouslyIfNeeded` — is something a test can
/// drive through `AuthService` itself via `MockAuthProviding`, instead of only ever
/// exercising the mock's own copy of that guard.
final class AuthService: AuthProviding {

    static let shared = AuthService()

    private let provider: AuthProviding
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Auth")

    init(provider: AuthProviding = FirebaseAuthProvider()) {
        self.provider = provider
    }

    var currentUid: String? { provider.currentUid }
    var isAnonymous: Bool { provider.isAnonymous }

    func signInAnonymouslyIfNeeded() async throws -> String {
        if let uid = provider.currentUid { return uid }
        let uid = try await provider.signInAnonymouslyIfNeeded()
        logger.info("Signed in anonymously")
        return uid
    }

    /// Links Apple to the current anonymous account, preserving its uid and all data.
    ///
    /// The uid never changes across this call: Firebase's `link(with:)` upgrades the
    /// existing `currentUser` in place, and the one recovery path — an Apple ID that
    /// already owns an account — explicitly *adopts* that existing uid rather than minting
    /// a new one. Every `events/{eventId}/participants/{uid}` and `memberships/{uid}/…`
    /// document stays reachable either way.
    func signInWithApple(idToken: String, nonce: String) async throws {
        try await provider.signInWithApple(idToken: idToken, nonce: nonce)
        logger.info("Signed in with Apple")
    }

    /// Closes the account for good. Logged because it is the one action in the app with no
    /// undo and no server-side record left to consult afterwards — the uid is the key to
    /// everything, so once it is gone there is nothing to look the user up by.
    func deleteAccount() async throws {
        try await provider.deleteAccount()
        logger.info("Deleted the signed-in account")
    }

    /// Raw nonce for Sign in with Apple. Apple receives its SHA-256; Firebase receives this.
    /// Uses `SecRandomCopyBytes` rather than `Int.random` because the nonce must resist
    /// replay — a PRNG seeded predictably would defeat the point of having one.
    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "Unable to generate a secure nonce")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AuthError

/// Typed auth failures. A revoked membership or an expired credential is routine, not
/// exceptional, so callers get a case to switch on instead of a generic failure message.
enum AuthError: LocalizedError {
    case sessionExpired
    case accountDisabled
    case signInFailed
    /// Firebase refuses to delete a user whose sign-in is stale, and the only cure is to
    /// sign in again — retrying the delete cannot ever clear it. Its own case rather than
    /// `signInFailed` so the deletion UI can say what to do instead of offering a retry
    /// that is guaranteed to fail the same way.
    case requiresRecentLogin

    init(_ error: Error) {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .userTokenExpired, .invalidUserToken:
            self = .sessionExpired
        case .userDisabled:
            self = .accountDisabled
        case .requiresRecentLogin:
            self = .requiresRecentLogin
        default:
            self = .signInFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .sessionExpired:  return "Your session expired. Sign in again to continue."
        case .accountDisabled: return "This account has been disabled."
        case .signInFailed:    return "Couldn't sign in. Check your connection and try again."
        case .requiresRecentLogin:
            return "For your security, sign in again before deleting your account."
        }
    }
}

// MARK: - FirebaseAuthProvider

/// The one type in this file that touches `Auth.auth()`. Contains no "already signed in"
/// logic of its own — that guard lives in `AuthService`, which is what keeps the guard
/// testable instead of buried inside a call to a singleton.
private final class FirebaseAuthProvider: AuthProviding {

    var currentUid: String? { Auth.auth().currentUser?.uid }
    var isAnonymous: Bool { Auth.auth().currentUser?.isAnonymous ?? true }

    func signInAnonymouslyIfNeeded() async throws -> String {
        do {
            let result = try await Auth.auth().signInAnonymously()
            return result.user.uid
        } catch {
            throw AuthError(error)
        }
    }

    /// If the Apple ID already owns an account, linking fails with `credentialAlreadyInUse`
    /// — and that case *is* the recovery path we want: the user is returning on a new
    /// device, so we adopt the existing account and discard the throwaway anonymous uid.
    func signInWithApple(idToken: String, nonce: String) async throws {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken, rawNonce: nonce, fullName: nil
        )

        guard let user = Auth.auth().currentUser else {
            do {
                _ = try await Auth.auth().signIn(with: credential)
            } catch {
                throw AuthError(error)
            }
            return
        }

        do {
            _ = try await user.link(with: credential)
        } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
            do {
                _ = try await Auth.auth().signIn(with: credential)
            } catch {
                throw AuthError(error)
            }
        } catch {
            throw AuthError(error)
        }
    }

    /// No `currentUser` means there is no account to close. Reported as `sessionExpired`
    /// rather than swallowed as success: the caller has already deleted this uid's Firestore
    /// data by the time it gets here, and "it worked" would hide an identity that outlived
    /// the erasure.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.sessionExpired }
        do {
            try await user.delete()
        } catch {
            throw AuthError(error)
        }
    }
}
