import Testing
import UIKit
import FirebaseFirestore
@testable import BirthdayQuest

@Suite("Challenge wire shape")
struct ChallengeWireShapeTests {

    /// Pins which keys Firestore's encoder actually writes for a Challenge with six nil
    /// optionals. The create rule in firestore.rules lists fields explicitly, so a change
    /// here silently breaks every create against a live project — where no test runs.
    @Test func encodesOnlyNonNilFields() throws {
        let challenge = Challenge(
            title: "Sing", description: "In public", illustrationAsset: "music.mic",
            pointValue: 50, difficulty: .medium, category: .social,
            isSecret: false, createdByUserId: "uid_host",
            isDelivered: true, isCompleted: false,
            completedAt: nil, proofUrl: nil, proofType: nil, proofText: nil,
            createdAt: Date()
        )

        let encoded = try Firestore.Encoder().encode(challenge)
        let keys = Set(encoded.keys)

        // The six nil optionals must be ABSENT, not present-as-null.
        #expect(!keys.contains("completedAt"))
        #expect(!keys.contains("proofUrl"))
        #expect(!keys.contains("proofType"))
        #expect(!keys.contains("proofText"))
        #expect(!keys.contains("optionBTitle"))
        #expect(!keys.contains("optionBDescription"))

        // @DocumentID is never encoded into the body.
        #expect(!keys.contains("id"))

        // And these eleven must be present.
        #expect(keys == [
            "title", "description", "illustrationAsset", "pointValue", "difficulty",
            "category", "isSecret", "createdByUserId", "isDelivered", "isCompleted",
            "createdAt",
        ])
    }
}

@Suite("Challenge symbols")
struct ChallengeSymbolCatalogTests {

    @Test("every catalogued symbol is a real SF Symbol")
    func allSymbolsResolve() {
        for name in ChallengeSymbolCatalog.all {
            #expect(UIImage(systemName: name) != nil, "\(name) is not an SF Symbol")
        }
    }

    @Test("the fallback is itself catalogued and real")
    func fallbackIsValid() {
        #expect(ChallengeSymbolCatalog.all.contains(ChallengeSymbolCatalog.fallback))
        #expect(UIImage(systemName: ChallengeSymbolCatalog.fallback) != nil)
    }

    @Test("an uncatalogued name resolves to the fallback rather than rendering nothing")
    func unknownResolvesToFallback() {
        #expect(ChallengeSymbolCatalog.resolved("secret_mission") == ChallengeSymbolCatalog.fallback)
        #expect(ChallengeSymbolCatalog.resolved("music.mic") == "music.mic")
    }

    @Test("the catalogue has no duplicates")
    func noDuplicates() {
        #expect(Set(ChallengeSymbolCatalog.all).count == ChallengeSymbolCatalog.all.count)
    }
}

@MainActor
@Suite("Authoring keeps the occasion's counters honest")
struct AuthoringCounterTests {

    @Test("creating a challenge is recorded with its author stamp")
    func createStampsAuthor() async throws {
        let mock = MockGameBackend()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.beginCreating()
        vm.draft.title = "Sing in public"
        vm.draft.description = "Somewhere busy"
        vm.draft.pointValue = 50

        await vm.save(authorUid: "uid_host")

        #expect(mock.called("createChallenge"))
        #expect(mock.createdChallenges.first?.createdByUserId == "uid_host")
        #expect(mock.createdChallenges.first?.isSecret == false)
    }

    @Test("deleting a challenge asks the backend to delete it")
    func deleteCallsBackend() async {
        let mock = MockGameBackend()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        await vm.delete(.fixture(id: "c9"))

        #expect(mock.deletedChallengeIds == ["c9"])
    }

    @Test("an edit sends only content fields, never a gameplay field")
    func editSendsOnlyContent() async {
        let mock = MockGameBackend()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.beginEditing(.fixture(id: "c1", title: "Old"))
        vm.draft.title = "New"

        await vm.save(authorUid: "uid_host")

        let sent = Set(mock.updatedChallenges.first?.fields.keys ?? [:].keys)
        let gameplay: Set<String> = [
            "isCompleted", "completedAt", "proofUrl", "proofType", "proofText",
        ]
        #expect(sent.isDisjoint(with: gameplay), "the rules reject a mixed write")
        #expect(sent.contains("title"))
    }

    @Test("a failed write is reported, not swallowed")
    func failureIsReported() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.beginCreating()
        vm.draft.title = "X"
        vm.draft.description = "Y"

        await vm.save(authorUid: "uid_host")

        #expect(vm.actionResult?.isError == true)
        #expect(vm.isPerformingAction == false)
    }

    @Test("reconcile writes the true absolute count when the stored counter has drifted")
    func reconcileWritesTrueCount() async {
        let mock = MockGameBackend()
        mock.challenges = [.fixture(id: "c1"), .fixture(id: "c2"), .fixture(id: "c3")]
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        await vm.reconcileCounter(storedTotal: 5)

        #expect(mock.called("updateGameState"))
        #expect(mock.updatedGameStateFields.last?["totalChallenges"] as? Int == 3)
    }

    @Test("a stored empty optionBTitle round-trips as option B off, not on with blank fields")
    func emptyOptionBRoundTripsAsOff() {
        let challenge = Challenge.fixture(id: "c1", optionBTitle: "")
        let draft = ChallengeDraft(from: challenge)

        #expect(draft.hasOptionB == false)
        #expect(draft.optionBTitle == "")
        #expect(draft.optionBDescription == "")
    }

    @Test("a stored real optionBTitle round-trips as option B on, with its text")
    func realOptionBRoundTripsAsOn() {
        let challenge = Challenge.fixture(id: "c1", optionBTitle: "Sing a duet")
        let draft = ChallengeDraft(from: challenge)

        #expect(draft.hasOptionB == true)
        #expect(draft.optionBTitle == "Sing a duet")
        #expect(draft.optionBDescription == "Option B")
    }

    @Test("reconcile is a no-op when the stored counter already matches")
    func reconcileNoOpWhenMatching() async {
        let mock = MockGameBackend()
        mock.challenges = [.fixture(id: "c1"), .fixture(id: "c2"), .fixture(id: "c3")]
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        await vm.reconcileCounter(storedTotal: 3)

        #expect(!mock.called("updateGameState"))
    }
}

@MainActor
@Suite("Challenge authoring renders a refused read as a failure")
struct ChallengeAuthoringStateTests {

    private func permissionDenied() -> NSError {
        NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
    }

    @Test("a refused read is .failed, never an invitation to start authoring")
    func refusedReadIsFailed() async {
        let mock = MockGameBackend()
        mock.listenerFailure = permissionDenied()
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        guard case .failed(let message) = vm.contentState else {
            Issue.record("expected .failed, got \(String(describing: vm.contentState))")
            return
        }
        #expect(message.isEmpty == false)
    }

    @Test("a genuinely empty occasion still reads as empty")
    func emptyIsEmpty() async {
        let mock = MockGameBackend()
        mock.challenges = []
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        #expect(vm.contentState == .empty)
    }

    @Test("an occasion holding only secret dares still reads as empty to the host")
    func onlySecretDaresIsEmpty() async {
        let mock = MockGameBackend()
        mock.challenges = [.fixture(id: "s1", isSecret: true)]
        let vm = ChallengeAuthoringViewModel(eventId: "evt_1", service: mock)

        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        #expect(vm.contentState == .empty)
        #expect(vm.visibleChallenges.isEmpty, "a contributor's dare is not the host's to edit")
    }
}
