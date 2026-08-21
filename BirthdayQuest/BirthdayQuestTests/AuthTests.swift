import Testing
@testable import BirthdayQuest

@Suite("Auth")
struct AuthTests {

    @Test("nonces are unique and long enough to resist replay")
    func nonceQuality() {
        let nonces = Set((0..<200).map { _ in AuthService.randomNonce() })
        #expect(nonces.count == 200)
        #expect(AuthService.randomNonce().count >= 32)
    }

    // R22: the brief's version of this test drove `MockAuthProviding` directly, which only
    // proves the mock's own "already have a uid" branch works — not `AuthService`'s. Here
    // the mock is injected into a real `AuthService`, so the assertion is about the guard
    // in `AuthService.signInAnonymouslyIfNeeded()` actually short-circuiting before it ever
    // reaches the provider.
    @Test("anonymous sign-in is skipped when a uid already exists")
    func reusesExistingUid() async throws {
        let mock = MockAuthProviding()
        mock.currentUid = "uid_existing"
        let auth = AuthService(provider: mock)

        let uid = try await auth.signInAnonymouslyIfNeeded()

        #expect(uid == "uid_existing")
        #expect(mock.anonymousSignInCount == 0)
    }
}
