import Testing
import Foundation
@testable import BirthdayQuest

// View-model behaviour, exercised against MockGameBackend. These are possible because
// every view model takes a GameBackend rather than reaching for FirestoreService.shared.
//
// Note what is NOT covered here: the atomic transaction logic itself (balance re-check,
// idempotency guard) lives inside FirestoreService, so a mock replaces it rather than
// verifying it. That needs the Firebase emulator.

@MainActor
@Suite("RewardsViewModel unlock flow")
struct RewardsViewModelTests {

    @Test("a failed unlock surfaces an error to the user instead of failing silently")
    func failedUnlockSurfacesError() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = RewardsViewModel(service: mock)

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
        let vm = RewardsViewModel(service: mock)

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
        let vm = RewardsViewModel(service: mock)

        vm.requestUnlock(.fixture(id: "r1", isUnlocked: true))

        #expect(vm.showUnlockConfirm == false)
        #expect(vm.selectedReward == nil)

        await vm.confirmUnlock()
        #expect(mock.called("unlockRewardAtomically") == false)
    }

    @Test("the confirm dialog closes as soon as the unlock is underway")
    func confirmDialogDismisses() async {
        let mock = MockGameBackend()
        let vm = RewardsViewModel(service: mock)

        vm.requestUnlock(.fixture())
        #expect(vm.showUnlockConfirm)

        await vm.confirmUnlock()
        #expect(vm.showUnlockConfirm == false)
    }

    @Test("a rewards listener failure clears loading and surfaces an error")
    func rewardsListenerFailureStopsLoading() async {
        let mock = MockGameBackend()
        mock.listenerFailure = NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        let vm = RewardsViewModel(service: mock)

        vm.startListening()
        await Task.yield()

        #expect(vm.isLoading == false)
        #expect(vm.errorMessage != nil)
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
        let vm = ProfileViewModel(service: mock)

        vm.startListening(userId: "u1")
        #expect(mock.called("listenToChallenges"))

        vm.stopListening()
        #expect(mock.removedListenerKeys == ["profile_secret_status"])
    }
}

@MainActor
@Suite("TimelineViewModel node detail")
struct TimelineViewModelTests {

    @Test("a challenge node resolves to its challenge")
    func resolvesChallenge() async {
        let mock = MockGameBackend()
        mock.stubbedChallenge = .fixture(id: "c9", title: "King's Address")
        let vm = TimelineViewModel(service: mock)

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
        let vm = TimelineViewModel(service: mock)

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
        let vm = TimelineViewModel(service: mock)

        let detail = await vm.detail(for: .fixture(type: .challengeCompleted))
        #expect(detail == nil)
    }

    @Test("a backend failure resolves to nil rather than propagating")
    func fetchFailureIsNil() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = TimelineViewModel(service: mock)

        let detail = await vm.detail(for: .fixture(type: .rewardUnlocked))
        #expect(detail == nil)
    }

    @Test("only the timeline listener is torn down, not another screen's")
    func stopListeningUsesOwnKey() {
        let mock = MockGameBackend()
        let vm = TimelineViewModel(service: mock)
        vm.stopListening()
        #expect(mock.removedListenerKeys == ["timeline"])
    }
}

@MainActor
@Suite("AdminViewModel point adjustments")
struct AdminViewModelTests {

    @Test("adding points credits both the balance and the earned total")
    func addPointsCreditsEarned() async {
        let mock = MockGameBackend()
        let vm = AdminViewModel(service: mock)

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
        let vm = AdminViewModel(service: mock)

        await vm.removePoints(50)

        let fields = mock.updatedGameStateFields[0]
        #expect(fields["currentPoints"] != nil)
        #expect(fields["totalPointsEarned"] == nil, "correcting a balance must not rewrite what was earned")
    }

    @Test("advancing the day moves to the next day number")
    func advanceDay() async {
        let mock = MockGameBackend()
        let vm = AdminViewModel(service: mock)

        await vm.advanceDay(from: 2)

        let fields = mock.updatedGameStateFields[0]
        #expect(fields["currentDay"] as? Int == 3)
        #expect(vm.actionResult?.isError == false)
    }

    @Test("a failed adjustment is reported as an error, not silently dropped", arguments: [0, 1, 2])
    func failuresAreReported(variant: Int) async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = AdminViewModel(service: mock)

        switch variant {
        case 0: await vm.addPoints(10)
        case 1: await vm.removePoints(10)
        default: await vm.advanceDay(from: 1)
        }

        #expect(vm.actionResult?.isError == true)
        #expect(vm.isPerformingAction == false)
    }
}
