import Testing
import Foundation
@testable import BirthdayQuest

/// In-app account deletion (App Store 5.1.1(v)).
///
/// The thing worth testing here is not that deletion happens but that it happens in one
/// order and stops at the first failure. Firestore data first, auth user last: every rule in
/// this app is written against `request.auth.uid`, so a participant document that outlives
/// its uid is permanently unreachable — including by the person it describes. Getting the
/// order wrong produces no error, no crash and no visible symptom at the time.
@MainActor
@Suite("Account deletion")
struct DeleteAccountTests {

    private func occasion(_ id: String, name: String, hostUid: String) -> Occasion {
        Occasion(
            id: id, name: name, occasionType: .birthday, celebrantName: "Alex",
            hostUid: hostUid, occasionDate: Date(), isOpen: true, createdAt: Date()
        )
    }

    private func makeViewModel(
        _ backend: MockGameBackend,
        _ auth: MockAuthProviding
    ) -> DeleteAccountViewModel {
        auth.currentUid = "uid_me"
        return DeleteAccountViewModel(service: backend, auth: auth)
    }

    @Test("the Firestore data goes before the auth user, never after")
    func deletesDataBeforeAuthUser() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        let vm = makeViewModel(backend, auth)

        // Snapshotted from inside the auth delete: the only shared moment the two mocks have.
        var backendCallsWhenAuthWasDeleted: [String] = []
        auth.onDeleteAccount = { backendCallsWhenAuthWasDeleted = backend.calls }

        await vm.confirmDelete()

        #expect(
            backendCallsWhenAuthWasDeleted.contains("deleteMyAccountData"),
            "the auth user must not be deleted until the Firestore cleanup has returned"
        )
        #expect(backend.accountDataDeletionCount == 1)
        #expect(auth.accountDeletionCount == 1)
        #expect(vm.didDelete)
        #expect(vm.errorMessage == nil)
        #expect(vm.isDeleting == false)
        #expect(vm.isConfirming == false)
    }

    @Test("a Firestore failure leaves the auth user alone and stays retryable")
    func firestoreFailureSparesTheAuthUser() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        backend.errorToThrow = MockGameBackend.StubbedError()
        let vm = makeViewModel(backend, auth)

        await vm.confirmDelete()

        #expect(backend.accountDataDeletionCount == 1, "the attempt was made")
        #expect(
            auth.accountDeletionCount == 0,
            "an identity deleted over surviving data makes that data unreachable forever"
        )
        #expect(auth.currentUid == "uid_me", "the account has to survive to be retried")
        #expect(vm.didDelete == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.isDeleting == false)
    }

    @Test("a stale sign-in asks the user to sign in again, not to retry")
    func requiresRecentLoginSurfacesItsOwnMessage() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        auth.errorToThrow = AuthError.requiresRecentLogin
        let vm = makeViewModel(backend, auth)

        await vm.confirmDelete()

        #expect(vm.errorMessage == AuthError.requiresRecentLogin.errorDescription)
        #expect(
            vm.errorMessage != AuthError.signInFailed.errorDescription,
            "retrying cannot clear this one, so it must not read like a generic failure"
        )
        #expect(vm.didDelete == false)
        #expect(backend.accountDataDeletionCount == 1, "the data half ran and succeeded")
    }

    // `requiresRecentLogin` is only distinct if the mapping from Firebase's code survives.
    // Without this, deleting the case from `AuthError.init` would leave every test above
    // green — they inject the enum case directly, never the NSError Firebase actually raises.
    @Test("Firebase's requires-recent-login code maps to its own case")
    func mapsTheFirebaseErrorCode() {
        // AuthErrorCode.requiresRecentLogin.rawValue, as Firebase reports it.
        let raw = NSError(domain: "FIRAuthErrorDomain", code: 17014)
        #expect(AuthError(raw).errorDescription == AuthError.requiresRecentLogin.errorDescription)
    }

    @Test("hosted occasions are named so the warning can list what the user is walking away from")
    func exposesHostedOccasions() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        backend.stubOccasions = [
            occasion("evt_1", name: "Alex's 30th", hostUid: "uid_me"),
            occasion("evt_2", name: "Someone else's wedding", hostUid: "uid_other"),
            occasion("evt_3", name: "Jo's farewell", hostUid: "uid_me")
        ]
        let vm = makeViewModel(backend, auth)

        await vm.loadHostedOccasions()

        #expect(vm.hostsAnyOccasion)
        #expect(vm.hostedOccasionNames == ["Alex's 30th", "Jo's farewell"])
    }

    @Test("a user who hosts nothing gets no host warning")
    func noHostedOccasions() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        backend.stubOccasions = [occasion("evt_2", name: "Someone else's", hostUid: "uid_other")]
        let vm = makeViewModel(backend, auth)

        await vm.loadHostedOccasions()

        #expect(vm.hostsAnyOccasion == false)
        #expect(vm.hostedOccasionNames.isEmpty)
    }

    @Test("a failed occasion lookup says so rather than reading as hosting nothing")
    func hostedOccasionLoadFailureIsVisible() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        backend.errorToThrow = MockGameBackend.StubbedError()
        let vm = makeViewModel(backend, auth)

        await vm.loadHostedOccasions()

        #expect(vm.hostedOccasionNames.isEmpty)
        #expect(vm.errorMessage != nil, "an empty list must not silently mean 'you host nothing'")
    }

    @Test("requesting deletion opens the confirmation and clears a stale error")
    func requestAndCancel() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        backend.errorToThrow = MockGameBackend.StubbedError()
        let vm = makeViewModel(backend, auth)

        await vm.confirmDelete()
        #expect(vm.errorMessage != nil)

        vm.requestDelete()
        #expect(vm.isConfirming)
        #expect(vm.errorMessage == nil)

        vm.cancelDelete()
        #expect(vm.isConfirming == false)
    }
}
