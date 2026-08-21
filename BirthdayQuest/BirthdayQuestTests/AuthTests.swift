import Testing
import Foundation
@testable import BirthdayQuest

@Suite("Auth")
struct AuthTests {

    @Test("nonces are unique and long enough to resist replay")
    func nonceQuality() {
        let nonces = Set((0..<200).map { _ in AuthService.randomNonce() })
        #expect(nonces.count == 200)
        #expect(AuthService.randomNonce().count >= 32)
    }

    // Pinned against the published SHA-256 test vector for "abc". Apple signs whatever digest
    // it is handed and Firebase re-derives its own from the raw nonce, so a wrong digest here
    // surfaces only as an opaque invalid-credential error at runtime — nothing else catches it.
    @Test("sha256 produces the standard lowercase hex digest")
    func sha256IsAStandardDigest() {
        #expect(
            AuthService.sha256("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(AuthService.sha256(AuthService.randomNonce()).count == 64)
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

// MARK: - Apple link

/// Covers the upgrade path `OccasionListView`'s Sign in with Apple button drives. The button
/// itself is only reachable from a UI test, so these pin the seam directly underneath it:
/// what `AppSession.linkApple` does with a credential, and which of the two nonces it forwards.
@Suite("Apple link")
@MainActor
struct AppleLinkTests {

    private func occasion(_ id: String) -> Occasion {
        Occasion(
            id: id, name: "Alex's 30th", occasionType: .birthday, celebrantName: "Alex",
            hostUid: "uid_host", occasionDate: Date(), isOpen: true, createdAt: Date()
        )
    }

    @Test("a successful link drops the anonymous flag and reloads the occasion list")
    func linkSucceeds() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        backend.stubOccasions = [occasion("evt_1"), occasion("evt_2")]
        let session = AppSession(service: backend, auth: auth)
        await session.bootstrap()
        #expect(session.isAnonymous)
        #expect(session.shouldPromptAppleLink)

        // A third occasion appears server-side; only a genuine reload can see it.
        backend.stubOccasions.append(occasion("evt_3"))
        await session.linkApple(idToken: "id.token", nonce: AuthService.randomNonce())

        #expect(session.isAnonymous == false)
        #expect(session.shouldPromptAppleLink == false, "nothing left to prompt about")
        #expect(session.occasions.count == 3, "linkApple must reload, not just flip a flag")
        #expect(session.errorMessage == nil)
    }

    @Test("a failed link says so and leaves the anonymous session usable")
    func linkFails() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        backend.stubOccasions = [occasion("evt_1"), occasion("evt_2")]
        let session = AppSession(service: backend, auth: auth)
        await session.bootstrap()

        auth.errorToThrow = AuthError.signInFailed
        await session.linkApple(idToken: "id.token", nonce: AuthService.randomNonce())

        #expect(
            session.errorMessage
                == "Couldn't link your Apple ID. You can try again from My Occasions.",
            "the copy has to point at a surface that exists — Profile has no link button"
        )
        #expect(session.isAnonymous, "a failed upgrade must not strip the working identity")
        #expect(auth.appleSignIns.isEmpty)
        #expect(session.occasions.count == 2, "the list the user was looking at survives")
    }

    // The one inversion that is invisible until a real Apple ID is used: Apple must receive
    // `sha256(raw)` and Firebase must receive `raw`. Swapping them fails with an opaque
    // credential error, so this pins the direction.
    @Test("Firebase receives the raw nonce, not the digest handed to Apple")
    func forwardsTheRawNonce() async {
        let auth = MockAuthProviding()
        let session = AppSession(service: MockGameBackend(), auth: auth)
        await session.bootstrap()

        let raw = AuthService.randomNonce()
        let digestSentToApple = AuthService.sha256(raw)
        #expect(digestSentToApple != raw)

        await session.linkApple(idToken: "id.token", nonce: raw)

        #expect(auth.appleSignIns.count == 1)
        #expect(auth.appleSignIns.first?.nonce == raw)
        #expect(auth.appleSignIns.first?.nonce != digestSentToApple)
        #expect(auth.appleSignIns.first?.idToken == "id.token")
    }
}
