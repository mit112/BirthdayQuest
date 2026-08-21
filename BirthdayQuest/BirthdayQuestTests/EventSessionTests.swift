import Testing
import Foundation
@testable import BirthdayQuest

@Suite("EventSession")
@MainActor
struct EventSessionTests {

    private func occasion(
        id: String = "evt_1", celebrantCode: String = "EFGH6789"
    ) -> Occasion {
        Occasion(
            id: id, name: "Alex's 30th", occasionType: .birthday, celebrantName: "Alex",
            hostUid: "uid_host", occasionDate: Date(), isOpen: true, createdAt: Date(),
            contributorCode: "ABCD2345", celebrantCode: celebrantCode
        )
    }

    private func participant(
        mode: ParticipantMode = .contributor, isHost: Bool = false
    ) -> Participant {
        var participant = Participant(
            name: "Sam", avatarId: AvatarCatalog.fallback,
            mode: mode, isHost: isHost, usedCode: "ABCD2345"
        )
        participant.id = "uid_sam"
        return participant
    }

    @Test("opening an occasion loads it and starts exactly one game-state listener")
    func startLoadsAndListens() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant()
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()

        #expect(session.isLoading == false)
        #expect(session.occasion?.name == "Alex's 30th")
        #expect(session.participant?.name == "Sam")
        #expect(session.errorMessage == nil)
        #expect(mock.callCount("listenToGameState") == 1)
        #expect(Set(mock.requestedEventIds) == ["evt_1"])
    }

    @Test("a failed open surfaces a message instead of spinning forever")
    func startFailureClearsLoading() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()

        #expect(session.isLoading == false)
        #expect(session.errorMessage != nil)
        #expect(mock.called("listenToGameState") == false, "no listener on a failed open")
    }

    @Test("stop removes only the keys this session registered, never all listeners")
    func stopIsScoped() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant()
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()
        session.stop()

        #expect(mock.removedListenerKeys == [ListenerKey.gameState("evt_1")])
        #expect(
            mock.called("removeAllListeners") == false,
            "a global teardown would kill a concurrently open occasion's listeners"
        )
    }

    @Test("stopping twice does not re-remove a listener it no longer owns")
    func stopIsIdempotent() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant()
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()
        session.stop()
        session.stop()

        #expect(mock.removedListenerKeys.count == 1)
    }

    @Test("a celebrant reopening the occasion retries the code consumption that failed")
    func celebrantCodeRetried() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion(celebrantCode: "EFGH6789")
        mock.stubbedParticipant = participant(mode: .celebrant)
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()

        #expect(mock.consumedCelebrantCodes == ["evt_1"])
    }

    @Test("an already-consumed celebrant code is not written again")
    func celebrantCodeNotRewritten() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion(celebrantCode: "")
        mock.stubbedParticipant = participant(mode: .celebrant)
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()

        #expect(mock.consumedCelebrantCodes.isEmpty)
    }

    @Test("a contributor never touches the celebrant code")
    func contributorLeavesCelebrantCodeAlone() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant(mode: .contributor)
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()

        #expect(mock.consumedCelebrantCodes.isEmpty)
    }

    @Test("host and celebrant are read off the participant, not guessed")
    func rolesComeFromTheParticipant() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant(mode: .celebrant, isHost: true)
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()

        #expect(session.isHost)
        #expect(session.isCelebrant)
    }

    @Test("navigating to the timeline switches the tab that matches the caller's mode")
    func navigateToTimelineUsesTheRightTabSet() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant(mode: .celebrant)
        let celebrant = EventSession(eventId: "evt_1", service: mock)
        await celebrant.start()

        celebrant.navigateToTimeline()
        #expect(celebrant.celebrantTab == .timeline)
        #expect(celebrant.scrollToLatestTimeline)

        let contributorMock = MockGameBackend()
        contributorMock.stubbedOccasion = occasion()
        contributorMock.stubbedParticipant = participant(mode: .contributor)
        let contributor = EventSession(eventId: "evt_1", service: contributorMock)
        await contributor.start()

        contributor.navigateToTimeline()
        #expect(contributor.contributorTab == .timeline)
    }

    @Test("a game state listener failure reports the loss of connection")
    func listenerFailureSurfaces() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant()
        mock.listenerFailure = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()
        await Task.yield()

        #expect(session.errorMessage != nil)
    }

    @Test("two sessions on different occasions register and release distinct keys")
    func twoOccasionsDoNotCollide() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant()

        let first = EventSession(eventId: "evt_a", service: mock)
        let second = EventSession(eventId: "evt_b", service: mock)
        await first.start()
        await second.start()

        first.stop()
        second.stop()

        #expect(mock.removedListenerKeys == [
            ListenerKey.gameState("evt_a"), ListenerKey.gameState("evt_b")
        ])
    }
}
