import Testing
import Foundation
@testable import BirthdayQuest

// View-model behaviour, exercised against MockGameBackend. These are possible because
// every view model takes a GameBackend rather than reaching for FirestoreService.shared.
//
// Note what is NOT covered here: the atomic transaction logic itself (balance re-check,
// idempotency guard) lives inside FirestoreService, so a mock replaces it rather than
// verifying it. That needs the Firebase emulator.

/// Listener callbacks and the roster fetch both hop through `Task { @MainActor in … }`, so
/// their effects land a turn or two after the call that started them.
@MainActor
private func settle(turns: Int = 8) async {
    for _ in 0..<turns { await Task.yield() }
}

/// The failure every content listener has to survive now that membership is revocable: a
/// host closing the occasion or removing a contributor turns every read into this.
private func permissionDenied() -> NSError {
    NSError(
        domain: "FIRFirestoreErrorDomain", code: 7,
        userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
    )
}

@MainActor
@Suite("RewardsViewModel unlock flow")
struct RewardsViewModelTests {

    @Test("a failed unlock surfaces an error to the user instead of failing silently")
    func failedUnlockSurfacesError() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = RewardsViewModel(eventId: "evt_1", service: mock)

        vm.requestUnlock(.fixture(id: "r1", pointCost: 100))
        await vm.confirmUnlock()

        #expect(vm.showError, "a failed unlock must tell the user, not just log")
        #expect(vm.errorMessage != nil)
        #expect(vm.justUnlockedReward == nil, "nothing should be presented as unlocked")
        #expect(vm.showUnlockedContent == false)
        #expect(vm.isUnlocking == false, "the spinner must be cleared even on failure")
    }

    @Test("a successful unlock presents the reward and raises no error")
    func successfulUnlockPresentsReward() async {
        let mock = MockGameBackend()
        let vm = RewardsViewModel(eventId: "evt_1", service: mock)

        vm.requestUnlock(.fixture(id: "r7", pointCost: 100))
        await vm.confirmUnlock()

        #expect(mock.unlockedRewardIds == ["r7"])
        #expect(vm.justUnlockedReward?.id == "r7")
        #expect(vm.showError == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.isUnlocking == false)
    }

    @Test("an already-unlocked reward cannot be re-purchased")
    func alreadyUnlockedIsIgnored() async {
        let mock = MockGameBackend()
        let vm = RewardsViewModel(eventId: "evt_1", service: mock)

        vm.requestUnlock(.fixture(id: "r1", isUnlocked: true))

        #expect(vm.showUnlockConfirm == false)
        #expect(vm.selectedReward == nil)

        await vm.confirmUnlock()
        #expect(mock.called("unlockRewardAtomically") == false)
    }

    @Test("the confirm dialog closes as soon as the unlock is underway")
    func confirmDialogDismisses() async {
        let mock = MockGameBackend()
        let vm = RewardsViewModel(eventId: "evt_1", service: mock)

        vm.requestUnlock(.fixture())
        #expect(vm.showUnlockConfirm)

        await vm.confirmUnlock()
        #expect(vm.showUnlockConfirm == false)
    }

    @Test("a refused rewards read renders as a failure, never as an empty occasion")
    func rewardsListenerFailureIsRendered() async {
        let mock = MockGameBackend()
        mock.listenerFailure = permissionDenied()
        let vm = RewardsViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.isLoading == false)
        // This is the assertion the old test was missing. It asserted `errorMessage != nil`,
        // which was *already true* while the screen rendered "No gifts yet" — the message
        // was written and read by nothing. `contentState` is what the view branches on, so
        // only this can fail if the failure becomes invisible again.
        guard case .failed(let message) = vm.contentState else {
            Issue.record("a refused read must render .failed, not \(String(describing: vm.contentState))")
            return
        }
        #expect(message.isEmpty == false)
        #expect(vm.showError == false, "losing access is persistent; an alert is dismissed and gone")
    }

    @Test("an occasion that genuinely has no gifts still reads as empty, not as a failure")
    func emptyRewardsAreStillEmpty() async {
        let mock = MockGameBackend()
        mock.rewards = []
        let vm = RewardsViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.contentState == .empty, "the fix must not turn every empty occasion into an error")
    }

    @Test("a later snapshot clears the failure instead of leaving a stale error on screen")
    func rewardsFailureClearsOnRecovery() async {
        let mock = MockGameBackend()
        mock.listenerFailure = permissionDenied()
        let vm = RewardsViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()
        mock.listenerFailure = nil
        mock.emitRewards([.fixture(id: "r1")])
        await settle()

        #expect(vm.contentState == .ready)
        #expect(vm.loadFailure == nil)
    }
}

@MainActor
@Suite("ProfileViewModel secret challenge status")
struct ProfileViewModelTests {

    @Test("no secret challenge authored yet")
    func noneAuthored() {
        #expect(ProfileViewModel.status(for: "u1", in: []) == .none)
    }

    @Test("authored but not sent reads as a draft")
    func draft() {
        let mine = Challenge.fixture(isSecret: true, createdByUserId: "u1")
        #expect(ProfileViewModel.status(for: "u1", in: [mine]) == .draft)
    }

    @Test("delivered but not completed reads as sent")
    func sent() {
        let mine = Challenge.fixture(isSecret: true, createdByUserId: "u1", isDelivered: true)
        #expect(ProfileViewModel.status(for: "u1", in: [mine]) == .sent)
    }

    @Test("completed wins over delivered")
    func done() {
        let mine = Challenge.fixture(
            isSecret: true, createdByUserId: "u1", isDelivered: true, isCompleted: true
        )
        #expect(ProfileViewModel.status(for: "u1", in: [mine]) == .done)
    }

    @Test("another friend's secret challenge is not mistaken for mine")
    func ignoresOtherUsers() {
        let theirs = Challenge.fixture(isSecret: true, createdByUserId: "u2", isCompleted: true)
        #expect(ProfileViewModel.status(for: "u1", in: [theirs]) == .none)
    }

    @Test("a regular challenge I created is not a secret dare")
    func ignoresNonSecret() {
        let regular = Challenge.fixture(isSecret: false, createdByUserId: "u1")
        #expect(ProfileViewModel.status(for: "u1", in: [regular]) == .none)
    }

    @Test("listening publishes the status and releases the right listener key")
    func listenerWiring() {
        let mock = MockGameBackend()
        mock.challenges = [Challenge.fixture(isSecret: true, createdByUserId: "u1", isDelivered: true)]
        let vm = ProfileViewModel(eventId: "evt_1", service: mock)

        vm.startListening(userId: "u1")
        #expect(mock.called("listenToChallenges"))

        vm.stopListening()
        #expect(
            mock.removedListenerKeys == [ListenerKey.scoped("profile_secret_status", eventId: "evt_1")],
            "listener keys carry the event id so one occasion cannot tear down another's"
        )
    }
}

@MainActor
@Suite("TimelineViewModel node detail")
struct TimelineViewModelTests {

    @Test("a challenge node resolves to its challenge")
    func resolvesChallenge() async {
        let mock = MockGameBackend()
        mock.stubbedChallenge = .fixture(id: "c9", title: "King's Address")
        let vm = TimelineViewModel(eventId: "evt_1", service: mock)

        let detail = await vm.detail(for: .fixture(type: .challengeCompleted, referenceId: "c9"))

        guard case .challenge(let challenge) = detail else {
            Issue.record("expected a challenge, got \(String(describing: detail))")
            return
        }
        #expect(challenge.id == "c9")
    }

    @Test("a reward node resolves to its reward")
    func resolvesReward() async {
        let mock = MockGameBackend()
        mock.stubbedReward = .fixture(id: "r3", fromName: "Riley")
        let vm = TimelineViewModel(eventId: "evt_1", service: mock)

        let detail = await vm.detail(for: .fixture(type: .rewardUnlocked, referenceId: "r3"))

        guard case .reward(let reward) = detail else {
            Issue.record("expected a reward, got \(String(describing: detail))")
            return
        }
        #expect(reward.fromName == "Riley")
    }

    @Test("a node pointing at a deleted document resolves to nil rather than crashing")
    func missingDocumentIsNil() async {
        let mock = MockGameBackend()
        mock.stubbedChallenge = nil
        let vm = TimelineViewModel(eventId: "evt_1", service: mock)

        let detail = await vm.detail(for: .fixture(type: .challengeCompleted))
        #expect(detail == nil)
    }

    @Test("a backend failure resolves to nil rather than propagating")
    func fetchFailureIsNil() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = TimelineViewModel(eventId: "evt_1", service: mock)

        let detail = await vm.detail(for: .fixture(type: .rewardUnlocked))
        #expect(detail == nil)
    }

    @Test("only this occasion's timeline listener is torn down, not another's")
    func stopListeningUsesOwnKey() {
        let mock = MockGameBackend()
        let vm = TimelineViewModel(eventId: "evt_1", service: mock)
        vm.stopListening()
        #expect(mock.removedListenerKeys == [ListenerKey.timeline("evt_1")])
        #expect(mock.called("removeAllListeners") == false, "a global teardown would kill a sibling occasion")
    }

    @Test("every backend call is scoped to the occasion the view model was handed")
    func callsAreScopedToTheEvent() async {
        let mock = MockGameBackend()
        let vm = TimelineViewModel(eventId: "evt_9", service: mock)

        vm.startListening()
        _ = await vm.detail(for: .fixture(type: .challengeCompleted))

        #expect(Set(mock.requestedEventIds) == ["evt_9"])
    }
}

@MainActor
@Suite("AdminViewModel point adjustments")
struct AdminViewModelTests {

    @Test("adding points credits both the balance and the earned total")
    func addPointsCreditsEarned() async {
        let mock = MockGameBackend()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        await vm.addPoints(50)

        #expect(mock.callCount("updateGameState") == 1)
        let fields = mock.updatedGameStateFields[0]
        #expect(fields["currentPoints"] != nil)
        #expect(fields["totalPointsEarned"] != nil)
        #expect(vm.actionResult?.isError == false)
        #expect(vm.isPerformingAction == false)
    }

    @Test("removing points leaves the earned total untouched so history stays accurate")
    func removePointsPreservesEarnedHistory() async {
        let mock = MockGameBackend()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        await vm.removePoints(50)

        let fields = mock.updatedGameStateFields[0]
        #expect(fields["currentPoints"] != nil)
        #expect(fields["totalPointsEarned"] == nil, "correcting a balance must not rewrite what was earned")
    }

    @Test("advancing the day moves to the next day number")
    func advanceDay() async {
        let mock = MockGameBackend()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        await vm.advanceDay(from: 2)

        let fields = mock.updatedGameStateFields[0]
        #expect(fields["currentDay"] as? Int == 3)
        #expect(vm.actionResult?.isError == false)
    }

    @Test("a failed adjustment is reported as an error, not silently dropped", arguments: [0, 1, 2])
    func failuresAreReported(variant: Int) async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        switch variant {
        case 0: await vm.addPoints(10)
        case 1: await vm.removePoints(10)
        default: await vm.advanceDay(from: 1)
        }

        #expect(vm.actionResult?.isError == true)
        #expect(vm.isPerformingAction == false)
    }
}

@MainActor
@Suite("AdminViewModel listeners and the roster")
struct AdminViewModelListenerTests {

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

    @Test("the host panel and the celebrant carousel hold separate rewards listeners")
    func rewardsKeysDoNotCollide() {
        let mock = MockGameBackend()
        let carousel = RewardsViewModel(eventId: "evt_1", service: mock)
        let admin = AdminViewModel(eventId: "evt_1", service: mock)

        carousel.startListening()
        admin.startListening()

        #expect(mock.liveListenerKeys.contains(ListenerKey.rewards("evt_1")))
        #expect(mock.liveListenerKeys.contains(ListenerKey.scoped("admin_rewards", eventId: "evt_1")))
        #expect(mock.liveListenerKeys.count == 3, "two rewards listeners plus admin's challenges")
    }

    @Test("leaving the host panel leaves the carousel's rewards listener alive")
    func adminTeardownSparesTheCarousel() async {
        let mock = MockGameBackend()
        mock.rewards = [.fixture(id: "r1")]
        let carousel = RewardsViewModel(eventId: "evt_1", service: mock)
        let admin = AdminViewModel(eventId: "evt_1", service: mock)

        carousel.startListening()
        admin.startListening()
        admin.stopListening()

        #expect(
            mock.liveListenerKeys == [ListenerKey.rewards("evt_1")],
            "the carousel must survive the host panel being dismissed"
        )

        // Prove it is still receiving, not merely still registered. The view model hops to
        // the main actor inside its handler, so the emission lands one turn later.
        mock.emitRewards([.fixture(id: "r1"), .fixture(id: "r2")])
        await settle()
        #expect(carousel.rewards.count == 2)
        #expect(carousel.isLoading == false)
    }

    @Test("a failed listener is reported rather than left looking like an empty occasion")
    func listenerFailureIsReported() async {
        let mock = MockGameBackend()
        mock.listenerFailure = NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.actionResult?.isError == true)
    }

    @Test("the roster excludes the host looking at it")
    func rosterExcludesHost() async {
        let mock = MockGameBackend()
        mock.stubParticipants = [
            participant(id: "uid_host", name: "Sam", isHost: true),
            participant(id: "uid_alex", name: "Alex", mode: .celebrant),
            participant(id: "uid_jo", name: "Jordan"),
        ]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.otherParticipants.map(\.name) == ["Alex", "Jordan"])
    }

    @Test("closing the occasion writes the new state and reports success to the caller")
    func setOpenWritesAndReportsSuccess() async {
        let mock = MockGameBackend()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        let succeeded = await vm.setOpen(false)

        #expect(succeeded, "the caller re-reads the occasion only on success")
        #expect(mock.openStateChanges.map(\.isOpen) == [false])
        #expect(mock.openStateChanges.map(\.eventId) == ["evt_1"])
        #expect(vm.actionResult?.isError == false)
        #expect(vm.isPerformingAction == false)
    }

    @Test("a failed close reports failure so the stale label is not refreshed over a no-op")
    func setOpenFailureReportsFalse() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        let succeeded = await vm.setOpen(false)

        #expect(succeeded == false)
        #expect(vm.actionResult?.isError == true)
        #expect(vm.isPerformingAction == false)
    }

    @Test("removing a contributor calls the backend with the right ids and reloads the roster")
    func removeParticipantCallsBackendAndReloadsRoster() async {
        let mock = MockGameBackend()
        let jordan = participant(id: "uid_jo", name: "Jordan")
        mock.stubParticipants = [
            participant(id: "uid_host", name: "Sam", isHost: true),
            jordan,
        ]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        await vm.loadRoster()
        #expect(vm.otherParticipants.map(\.name) == ["Jordan"])

        // Simulate the removal landing server-side: the next roster read no longer sees Jordan.
        mock.stubParticipants = [participant(id: "uid_host", name: "Sam", isHost: true)]

        await vm.removeParticipant(jordan)

        #expect(mock.removedParticipants.map(\.eventId) == ["evt_1"])
        #expect(mock.removedParticipants.map(\.uid) == ["uid_jo"])
        #expect(mock.callCount("fetchParticipants") == 2, "removal reloads the roster")
        #expect(vm.otherParticipants.isEmpty, "the reload must reflect the removal")
        #expect(vm.actionResult?.isError == false)
        #expect(vm.isPerformingAction == false)
    }

    @Test("a backend failure removing a participant surfaces an error and does not crash")
    func removeParticipantFailureSurfacesError() async {
        let mock = MockGameBackend()
        let jordan = participant(id: "uid_jo", name: "Jordan")
        mock.stubParticipants = [jordan]
        let vm = AdminViewModel(eventId: "evt_1", service: mock)
        await vm.loadRoster()

        mock.errorToThrow = MockGameBackend.StubbedError()
        await vm.removeParticipant(jordan)

        #expect(mock.removedParticipants.map(\.uid) == ["uid_jo"], "the attempt still happened")
        #expect(vm.actionResult?.isError == true)
        #expect(vm.isPerformingAction == false)
    }

    @Test("removing the host or the celebrant is a no-op — the backend is never called")
    func removeParticipantGuardsHostAndCelebrant() async {
        let mock = MockGameBackend()
        let host = participant(id: "uid_host", name: "Sam", isHost: true)
        let celebrant = participant(id: "uid_alex", name: "Alex", mode: .celebrant)
        let vm = AdminViewModel(eventId: "evt_1", service: mock)

        await vm.removeParticipant(host)
        await vm.removeParticipant(celebrant)

        #expect(mock.called("removeParticipant") == false)
        #expect(vm.actionResult == nil, "a silent no-op must not report success or failure")
    }
}

@MainActor
@Suite("ProfileViewModel listener failures")
struct ProfileViewModelFailureTests {

    @Test("a permission-denied status listener says so instead of reading as no dare")
    func listenerFailureSurfaces() async {
        let mock = MockGameBackend()
        mock.listenerFailure = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        let vm = ProfileViewModel(eventId: "evt_1", service: mock)

        vm.startListening(userId: "uid_1")
        await settle()

        #expect(vm.errorMessage != nil)
        #expect(vm.secretChallengeStatus == .unknown, "'None' would be a lie about a denied read")
    }
}

/// The defect these pin: four listeners set an error message that no view read, so a refused
/// read fell through to `isEmpty` and rendered a cheerful empty state on an occasion with 13
/// challenges, 8 gifts and 20 timeline entries in it. Each test asserts the branch the view
/// takes — `.failed` — because "the view model holds a string" was true the whole time the
/// bug shipped.
@MainActor
@Suite("Refused content reads are rendered, not swallowed")
struct RefusedReadTests {

    @Test("a refused challenges read renders as a failure, never as no challenges")
    func challengesFailureIsRendered() async {
        let mock = MockGameBackend()
        mock.listenerFailure = permissionDenied()
        let vm = ChallengesViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.isLoading == false)
        guard case .failed(let message) = vm.contentState else {
            Issue.record("a refused read must render .failed, not \(String(describing: vm.contentState))")
            return
        }
        #expect(message.isEmpty == false)
    }

    @Test("an occasion that genuinely has no challenges still reads as empty")
    func emptyChallengesAreStillEmpty() async {
        let mock = MockGameBackend()
        mock.challenges = []
        let vm = ChallengesViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.contentState == .empty)
    }

    @Test("a refused timeline read renders as a failure, never as a journey not yet begun")
    func timelineFailureIsRendered() async {
        let mock = MockGameBackend()
        mock.listenerFailure = permissionDenied()
        let vm = TimelineViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.isLoading == false)
        guard case .failed(let message) = vm.contentState else {
            Issue.record("a refused read must render .failed, not \(String(describing: vm.contentState))")
            return
        }
        #expect(message.isEmpty == false)
        #expect(vm.isEmpty, "the events list really is empty — .failed has to outrank it")
    }

    @Test("an occasion that genuinely has no timeline entries still reads as empty")
    func emptyTimelineIsStillEmpty() async {
        let mock = MockGameBackend()
        mock.timeline = []
        let vm = TimelineViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        await settle()

        #expect(vm.contentState == .empty)
    }

    @Test("a refused dossier read renders as a failure and stops inviting a new dare")
    func secretDareFailureIsRendered() async {
        let mock = MockGameBackend()
        mock.listenerFailure = permissionDenied()
        let vm = SecretChallengeViewModel(eventId: "evt_1", service: mock)

        vm.loadExisting(userId: "uid_1")
        await settle()

        #expect(vm.isLoading == false)
        guard case .failed(let message) = vm.contentState else {
            Issue.record("a refused read must render .failed, not \(String(describing: vm.contentState))")
            return
        }
        #expect(message.isEmpty == false)
        #expect(
            vm.statusText != "Create your secret dare",
            "the badge would otherwise invite authoring into an occasion that stopped answering"
        )
        #expect(vm.showError == false, "the save alert must not be the vehicle for a persistent state")
    }

    @Test("a contributor who simply has not written a dare still gets the editable dossier")
    func noDareYetIsStillReady() async {
        let mock = MockGameBackend()
        mock.challenges = []
        let vm = SecretChallengeViewModel(eventId: "evt_1", service: mock)

        vm.loadExisting(userId: "uid_1")
        await settle()

        #expect(vm.contentState == .ready)
        #expect(vm.statusText == "Create your secret dare")
    }
}

@MainActor
@Suite("ChallengeSubmissionViewModel proof upload")
struct ChallengeSubmissionTests {

    @Test("a photo proof is uploaded with an image content type, never octet-stream")
    func sendsAnImageContentType() async {
        let mock = MockGameBackend()
        let vm = ChallengeSubmissionViewModel(
            eventId: "evt_1", challenge: .fixture(id: "c1"), service: mock
        )
        vm.selectedSubmissionType = .photo
        vm.selectedImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])

        await vm.submit()

        #expect(
            mock.uploadedContentTypes == ["image/jpeg"],
            "storage.rules requires image/*; putData with no metadata sends octet-stream and 403s"
        )
        #expect(mock.completedChallengeIds == ["c1"])
        #expect(Set(mock.requestedEventIds) == ["evt_1"])
        #expect(vm.showError == false)
    }

    @Test("a text proof uploads nothing at all")
    func textProofSkipsUpload() async {
        let mock = MockGameBackend()
        let vm = ChallengeSubmissionViewModel(
            eventId: "evt_1", challenge: .fixture(id: "c1"), service: mock
        )
        vm.selectedSubmissionType = .text
        vm.textProof = "Done it"

        await vm.submit()

        #expect(mock.uploadedContentTypes.isEmpty)
        #expect(mock.completedChallengeIds == ["c1"])
    }

    @Test("a failed upload surfaces an error and completes nothing")
    func failedUploadSurfaces() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = ChallengeSubmissionViewModel(
            eventId: "evt_1", challenge: .fixture(id: "c1"), service: mock
        )
        vm.selectedSubmissionType = .photo
        vm.selectedImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])

        await vm.submit()

        #expect(vm.showError)
        #expect(mock.completedChallengeIds.isEmpty)
        #expect(vm.isSubmitting == false)
    }
}
