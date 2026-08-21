import Testing
import Foundation
@testable import BirthdayQuest

// Task 15: sharing the invite and surfacing whether the celebrant has joined. Both live on
// the real host panel (`AdminControlsView` / `AdminViewModel`) — there is exactly one host
// panel and exactly one `isOpen` toggle in the app, both shipped by Task 13.

@Suite("Occasion invite links")
struct OccasionInviteLinkTests {

    private func codes(
        eventId: String = "evt_1",
        contributor: String = "ABCD2345",
        celebrant: String = "EFGH6789"
    ) -> InviteCodes {
        InviteCodes(eventId: eventId, contributorCode: contributor, celebrantCode: celebrant)
    }

    @Test("the contributor link carries both the event id and the contributor code")
    func contributorLink() {
        #expect(codes().contributorLink?.absoluteString
            == "birthdayquest://join?e=evt_1&c=ABCD2345")
    }

    @Test("the celebrant link uses the celebrant code, not the contributor one")
    func celebrantLinkIsDistinct() {
        let codes = codes()
        #expect(codes.celebrantLink?.absoluteString.contains("EFGH6789") == true)
        #expect(codes.celebrantLink != codes.contributorLink)
    }

    /// `URL(string: "birthdayquest://join?e=&c=")` is a perfectly valid URL, so interpolating
    /// an empty component used to produce a non-nil, permanently dead link the host could
    /// share with no indication anything was wrong.
    @Test("a link cannot be formed from an empty event id")
    func emptyEventIdYieldsNoLink() {
        #expect(codes(eventId: "").contributorLink == nil)
    }

    @Test("a consumed celebrant code yields no link rather than a dead one")
    func consumedCelebrantCodeYieldsNoLink() {
        let codes = codes(celebrant: "")
        #expect(codes.celebrantLink == nil)
        // The contributor link is unaffected — it is reusable by design.
        #expect(codes.contributorLink != nil)
    }

    @Test("a code that is not a real code yields no link")
    func malformedCodeYieldsNoLink() {
        #expect(codes(contributor: "ABC").contributorLink == nil)
        #expect(codes(contributor: "ABCD/345").contributorLink == nil)
    }

    @Test("an event id that could not be a document id yields no link")
    func malformedEventIdYieldsNoLink() {
        #expect(codes(eventId: "a//b").contributorLink == nil)
    }

    @Test("codes decode from the private document, taking the event id from the path")
    func decodesFromDocumentData() {
        let decoded = InviteCodes(
            eventId: "evt_1",
            data: ["contributorCode": "ABCD2345", "celebrantCode": "EFGH6789"]
        )
        #expect(decoded?.eventId == "evt_1")
        #expect(decoded?.contributorCode == "ABCD2345")
        #expect(decoded?.celebrantCode == "EFGH6789")
    }

    @Test("a missing or unreadable codes document decodes to nil")
    func missingDocumentDecodesToNil() {
        #expect(InviteCodes(eventId: "evt_1", data: nil) == nil)
        #expect(InviteCodes(eventId: "evt_1", data: [:]) == nil)
        #expect(InviteCodes(eventId: "evt_1", data: ["contributorCode": "ABCD2345"]) == nil)
    }
}

/// `AdminViewModel.startListening()` fetches the roster via `Task { @MainActor in ... }`,
/// so its effect on `celebrantHasJoined` lands a turn or two later.
@MainActor
private func settle(turns: Int = 8) async {
    for _ in 0..<turns { await Task.yield() }
}

@MainActor
@Suite("AdminViewModel celebrant-joined visibility")
struct AdminViewModelCelebrantJoinedTests {

    private func participant(
        id: String, name: String, mode: ParticipantMode = .contributor, isHost: Bool = false
    ) -> Participant {
        var participant = Participant(
            name: name, avatarId: AvatarCatalog.fallback,
            mode: mode, isHost: isHost, usedCode: "ABCD2345"
        )
        participant.id = id
        return participant
    }

    @Test("an empty roster reads as the celebrant not having joined")
    func celebrantMissingWhenRosterIsJustTheHost() async {
        let mock = MockGameBackend()
        mock.stubParticipants = [
            participant(id: "uid_host", name: "Sam", isHost: true),
            participant(id: "uid_jo", name: "Jordan"),
        ]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.celebrantHasJoined == false)
    }

    @Test("a participant with mode == celebrant flips the status to joined")
    func celebrantPresentIsReported() async {
        let mock = MockGameBackend()
        mock.stubParticipants = [
            participant(id: "uid_host", name: "Sam", isHost: true),
            participant(id: "uid_alex", name: "Alex", mode: .celebrant),
        ]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.celebrantHasJoined == true)
    }

    @Test("a host who is also the celebrant counts as joined")
    func hostCelebrantCountsAsJoined() async {
        let mock = MockGameBackend()
        mock.stubParticipants = [
            participant(id: "uid_host", name: "Sam", mode: .celebrant, isHost: true)
        ]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.celebrantHasJoined == true)
    }

    /// The codes are no longer on the occasion, so the host panel has to ask for them. If it
    /// stopped doing so, the share rows would silently disappear rather than fail loudly.
    @Test("the host panel loads the invite codes for its own occasion")
    func loadsInviteCodes() async {
        let mock = MockGameBackend()
        mock.stubbedInviteCodes = InviteCodes(
            eventId: "evt_1", contributorCode: "ABCD2345", celebrantCode: "EFGH6789"
        )
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.inviteCodes?.contributorCode == "ABCD2345")
        #expect(vm.inviteCodes?.contributorLink != nil)
        #expect(mock.requestedEventIds.allSatisfy { $0 == "evt_1" })
    }

    /// A non-host is denied the codes document, so nil is a real runtime state, not just a
    /// loading placeholder. It must not turn into a link built from empty strings.
    @Test("codes the backend refuses to hand over leave the panel with no link")
    func deniedInviteCodesLeaveNoLink() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError("permission denied")
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.inviteCodes == nil)
    }
}
