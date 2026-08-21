import Testing
import Foundation
@testable import BirthdayQuest

/// The game-state listener callback hops through `Task { @MainActor in … }`, so its effect
/// lands a turn or two after the call that started it. Matches the helper in
/// `ViewModelTests` and `HostInviteTests`, which are each file-private.
@MainActor
private func settle(turns: Int = 8) async {
    for _ in 0..<turns { await Task.yield() }
}

@Suite("EventSession")
@MainActor
struct EventSessionTests {

    private func occasion(id: String = "evt_1") -> Occasion {
        Occasion(
            id: id, name: "Alex's 30th", occasionType: .birthday, celebrantName: "Alex",
            hostUid: "uid_host", occasionDate: Date(), isOpen: true, createdAt: Date()
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

    /// The retry is deliberately unconditional. The codes moved to
    /// `events/{id}/private/codes`, which the celebrant may write but not read — that
    /// asymmetry is what keeps the code out of member-readable storage — so the celebrant
    /// has no way to check whether the first clear landed. Re-clearing is a permitted no-op
    /// in the rules (an empty diff satisfies `hasOnly(['celebrantCode'])`), so attempting it
    /// every open is correct, and gating it on a local copy of the code would be the bug.
    @Test("a celebrant reopening the occasion retries the clear without reading the code")
    func celebrantCodeRetried() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant(mode: .celebrant)
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()

        #expect(mock.consumedCelebrantCodes == ["evt_1"])
        #expect(mock.called("fetchInviteCodes") == false)
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

    @Test("a game state listener failure banners the loss without hijacking the occasion")
    func listenerFailureSurfaces() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant()
        mock.listenerFailure = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()
        await settle()

        // The old assertion was `errorMessage != nil`, which passed while the message was
        // unrenderable: `EventContainerView` gated it on `participant == nil`, and by the
        // time a listener fails the participant is loaded. These two assertions are the
        // ones that can fail if the message goes back to having nowhere to render.
        #expect(session.connectionMessage != nil, "a frozen points display must say so")
        #expect(session.participant != nil, "this is exactly the case the old gate excluded")
        #expect(
            session.errorMessage == nil,
            "the occasion is still readable — a takeover would hide tabs the user may still use"
        )
    }

    @Test("a later game state snapshot clears the banner")
    func listenerRecoveryClearsTheBanner() async {
        let mock = MockGameBackend()
        mock.stubbedOccasion = occasion()
        mock.stubbedParticipant = participant()
        mock.listenerFailure = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()
        await settle()
        mock.emitGameState(.empty)
        await settle()

        #expect(session.connectionMessage == nil)
    }

    @Test("a failed open is the only thing that takes the whole screen")
    func failedOpenIsTheOnlyTakeover() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let session = EventSession(eventId: "evt_1", service: mock)

        await session.start()

        // `EventContainerView` no longer re-derives "nothing is loaded" from the participant,
        // so this invariant is what keeps that takeover honest.
        #expect(session.errorMessage != nil)
        #expect(session.participant == nil, "the takeover must only fire when there is nothing behind it")
        #expect(session.connectionMessage == nil)
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
