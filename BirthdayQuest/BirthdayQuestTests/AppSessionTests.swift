import Testing
import Foundation
@testable import BirthdayQuest

@Suite("AppSession")
@MainActor
struct AppSessionTests {

    private func occasion(_ id: String) -> Occasion {
        Occasion(
            id: id, name: "Alex's 30th", occasionType: .birthday, celebrantName: "Alex",
            hostUid: "uid_host", occasionDate: Date(), isOpen: true, createdAt: Date(),
            contributorCode: "ABCD2345", celebrantCode: "EFGH6789"
        )
    }

    @Test("a signed-in user with no occasions lands on the empty state")
    func emptyState() async {
        let backend = MockGameBackend()
        let auth = MockAuthProviding()
        let session = AppSession(service: backend, auth: auth)

        await session.bootstrap()

        #expect(session.rootState == .empty)
        #expect(auth.anonymousSignInCount == 1)
    }

    @Test("a user with occasions lands on the list")
    func occasionList() async {
        let backend = MockGameBackend()
        backend.stubOccasions = [occasion("evt_1"), occasion("evt_2")]
        let session = AppSession(service: backend, auth: MockAuthProviding())

        await session.bootstrap()

        #expect(session.rootState == .occasions)
        #expect(session.occasions.count == 2)
    }

    @Test("a failed bootstrap surfaces an error rather than hanging on the splash")
    func bootstrapFailure() async {
        let auth = MockAuthProviding()
        auth.errorToThrow = NSError(domain: "test", code: 1)
        let session = AppSession(service: MockGameBackend(), auth: auth)

        await session.bootstrap()

        #expect(session.rootState != .launching)
        #expect(session.errorMessage != nil)
    }

    @Test("the Apple link prompt appears on the second occasion, not the first")
    func linkPromptTiming() async {
        let backend = MockGameBackend()
        let session = AppSession(service: backend, auth: MockAuthProviding())

        backend.stubOccasions = [occasion("evt_1")]
        await session.bootstrap()
        #expect(session.shouldPromptAppleLink == false)

        backend.stubOccasions = [occasion("evt_1"), occasion("evt_2")]
        await session.refreshOccasions()
        #expect(session.shouldPromptAppleLink == true)
    }
}

@Suite("AppSession error lifecycle")
@MainActor
struct AppSessionErrorTests {

    private func occasion(_ id: String) -> Occasion {
        Occasion(
            id: id, name: "Alex's 30th", occasionType: .birthday, celebrantName: "Alex",
            hostUid: "uid_host", occasionDate: Date(), isOpen: true, createdAt: Date(),
            contributorCode: "ABCD2345", celebrantCode: "EFGH6789"
        )
    }

    @Test("a transient failure's message does not outlive the retry that fixed it")
    func errorClearsOnRecovery() async {
        let backend = MockGameBackend()
        backend.errorToThrow = NSError(domain: "test", code: 1)
        let session = AppSession(service: backend, auth: MockAuthProviding())

        await session.bootstrap()
        #expect(session.errorMessage != nil)

        backend.errorToThrow = nil
        backend.stubOccasions = [occasion("evt_1")]
        await session.refreshOccasions()

        #expect(session.errorMessage == nil, "the empty state renders this unconditionally")
        #expect(session.rootState == .occasions)
    }
}
