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
/// so its effect on `celebrantPresence` lands a turn or two later.
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

        #expect(vm.celebrantPresence == .notJoined)
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

        #expect(vm.celebrantPresence == .joined)
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

        #expect(vm.celebrantPresence == .joined)
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

// MARK: - The Host Panel Must Not Invent Its Answers

/// The host panel's two one-shot reads used to be indistinguishable from their own failures.
///
/// A refused `fetchParticipants` left `participants` empty, and the panel rendered
/// "they haven't joined yet" and "Nobody else has joined yet" — two authoritative claims
/// about a roster it had never received, on the screen whose whole job is telling the host
/// whether to go chase the celebrant. A refused `fetchInviteCodes` left `inviteCodes` nil,
/// which the card could not tell apart from "still loading", so it sat on a spinner forever.
///
/// These tests assert the branch the view will take, not merely that some error string
/// exists somewhere — that was true the entire time the old screen was lying.
@MainActor
@Suite("Host panel read failures are not empty states")
struct AdminViewModelReadFailureTests {

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

    @Test("a failed roster read reports unknown, not 'the celebrant hasn't joined'")
    func failedRosterIsNotNotJoined() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.celebrantPresence == .unknown)
        #expect(vm.celebrantPresence != .notJoined, "a failure must not read as an answer")
        guard case .failed = vm.rosterState else {
            Issue.record("expected .failed, got \(vm.rosterState)")
            return
        }
    }

    /// The inverse regression. Making failure loud is worthless if it also swallows the
    /// genuine empty state — a real occasion where nobody has joined yet must still say so,
    /// because that is the case the host is supposed to act on.
    @Test("a genuinely empty roster still reads as empty, and as not joined")
    func genuineEmptyRosterStillReadsEmpty() async {
        let mock = MockGameBackend()
        mock.stubParticipants = [participant(id: "uid_host", name: "Sam", isHost: true)]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.rosterState == .empty)
        #expect(vm.celebrantPresence == .notJoined)
    }

    @Test("a roster with other people in it is ready, not empty")
    func populatedRosterIsReady() async {
        let mock = MockGameBackend()
        mock.stubParticipants = [
            participant(id: "uid_host", name: "Sam", isHost: true),
            participant(id: "uid_jo", name: "Jordan"),
        ]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.rosterState == .ready)
        #expect(vm.otherParticipants.map(\.name) == ["Jordan"])
    }

    /// The read is one-shot, so nothing arrives later to correct a failure. The retry is the
    /// only recovery path, which is why it is on the view model rather than left to a
    /// reopen-the-screen instruction.
    @Test("retrying the roster after a failure recovers")
    func rosterRetryRecovers() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()
        #expect(vm.celebrantPresence == .unknown)

        mock.errorToThrow = nil
        mock.stubParticipants = [
            participant(id: "uid_host", name: "Sam", isHost: true),
            participant(id: "uid_alex", name: "Alex", mode: .celebrant),
        ]
        await vm.loadRoster()

        #expect(vm.celebrantPresence == .joined)
        #expect(vm.rosterState == .ready)
    }

    /// A retry that fails again must not leave the previous read's names on screen underneath
    /// a failure message — that is a worse lie than either state alone.
    @Test("a retry that fails again clears the stale roster")
    func failedRetryClearsStaleRoster() async {
        let mock = MockGameBackend()
        mock.stubParticipants = [
            participant(id: "uid_host", name: "Sam", isHost: true),
            participant(id: "uid_jo", name: "Jordan"),
        ]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()
        #expect(vm.otherParticipants.isEmpty == false)

        mock.errorToThrow = MockGameBackend.StubbedError()
        await vm.loadRoster()

        #expect(vm.otherParticipants.isEmpty)
        #expect(vm.celebrantPresence == .unknown)
    }

    @Test("a failed invite-code read fails instead of loading forever")
    func failedCodesReadDoesNotHangOnLoading() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.codesState != .loading, "a one-shot failure must not read as still loading")
        guard case .failed = vm.codesState else {
            Issue.record("expected .failed, got \(vm.codesState)")
            return
        }
        #expect(vm.inviteCodes == nil)
    }

    /// A host's codes document is written by phase 2 of occasion creation, so its absence is
    /// a defect rather than a legitimate empty state. Reporting it as `.ready` would render
    /// the card with no rows and no explanation.
    @Test("a missing codes document is a failure, not a silent blank card")
    func missingCodesDocumentIsAFailure() async {
        let mock = MockGameBackend()
        mock.stubbedInviteCodes = nil
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        guard case .failed = vm.codesState else {
            Issue.record("expected .failed, got \(vm.codesState)")
            return
        }
    }

    @Test("a successful codes read is ready")
    func successfulCodesReadIsReady() async {
        let mock = MockGameBackend()
        mock.stubbedInviteCodes = InviteCodes(
            eventId: "evt_1", contributorCode: "ABCD2345", celebrantCode: "EFGH6789"
        )
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.codesState == .ready)
        #expect(vm.inviteCodes?.celebrantCode == "EFGH6789")
    }
}
