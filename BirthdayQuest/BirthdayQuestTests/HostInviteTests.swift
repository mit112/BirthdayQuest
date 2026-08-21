import Testing
import Foundation
@testable import BirthdayQuest

// Task 15: sharing the invite and surfacing whether the celebrant has joined. Both live on
// the real host panel (`AdminControlsView` / `AdminViewModel`) — there is exactly one host
// panel and exactly one `isOpen` toggle in the app, both shipped by Task 13.

@Suite("Occasion invite links")
struct OccasionInviteLinkTests {

    private func occasion(id: String?) -> Occasion {
        Occasion(
            id: id, name: "Alex's 30th", occasionType: .birthday, celebrantName: "Alex",
            hostUid: "uid_host", occasionDate: Date(), isOpen: true, createdAt: Date(),
            contributorCode: "ABCD2345", celebrantCode: "EFGH6789"
        )
    }

    @Test("the contributor link carries both the event id and the contributor code")
    func contributorLink() {
        let url = occasion(id: "evt_1").contributorLink
        #expect(url?.absoluteString == "birthdayquest://join?e=evt_1&c=ABCD2345")
    }

    @Test("the celebrant link uses the celebrant code, not the contributor one")
    func celebrantLinkIsDistinct() {
        let occasion = occasion(id: "evt_1")
        #expect(occasion.celebrantLink?.absoluteString.contains("EFGH6789") == true)
        #expect(occasion.celebrantLink != occasion.contributorLink)
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
}
