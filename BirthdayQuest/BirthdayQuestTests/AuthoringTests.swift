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

@MainActor
@Suite("Gift authoring")
struct GiftAuthoringTests {

    @Test("saving a new gift stamps the author and a non-zero price")
    func createStampsAuthorAndPrice() async {
        let mock = MockGameBackend()
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        vm.title = "A letter"
        vm.teaser = "Open me last"
        vm.letter = "Dear Alex..."

        await vm.save()

        let created = mock.createdRewards.first
        #expect(created?.fromUserId == "uid_jo")
        #expect(created?.fromName == "Jordan")
        #expect(created?.contentType == .text)
        #expect(created?.contentText == "Dear Alex...")
        #expect((created?.pointCost ?? 0) > 0, "a gift created free is instantly unlockable")
    }

    @Test("a new gift sorts to the end of the existing list")
    func newGiftSortsLast() async {
        let mock = MockGameBackend()
        mock.rewards = [.fixture(id: "r1"), .fixture(id: "r2")]
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        vm.title = "A letter"; vm.letter = "x"

        await vm.save()

        #expect(mock.createdRewards.first?.sortOrder == 2)
    }

    @Test("editing an existing gift sends only content fields, never the price")
    func editSendsOnlyContent() async {
        let mock = MockGameBackend()
        // fixture defaults to isUnlocked: false, which is what makes it still editable.
        let mine = Reward.fixture(id: "r_mine", contentType: .text)
        mock.rewards = [mine]
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "u1", name: "Jordan")   // fixture's fromUserId is "u1"
        for _ in 0..<8 { await Task.yield() }
        #expect(vm.hasExisting)
        vm.letter = "Rewritten"

        await vm.save()

        let sent = Set(mock.updatedRewards.first?.fields.keys ?? [:].keys)
        #expect(!sent.contains("pointCost"), "pricing is the host's, and a mixed write is denied")
        #expect(!sent.contains("sortOrder"))
        #expect(!sent.contains("isUnlocked"))
        #expect(sent.contains("contentText"))
    }

    @Test("save is a no-op once the celebrant has already opened the gift")
    func saveIsNoOpWhenAlreadyUnlocked() async {
        let mock = MockGameBackend()
        let mine = Reward.fixture(id: "r_mine", contentType: .text, isUnlocked: true)
        mock.rewards = [mine]
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "u1", name: "Jordan")   // fixture's fromUserId is "u1"
        for _ in 0..<8 { await Task.yield() }
        #expect(vm.hasExisting)
        vm.letter = "changed"

        await vm.save()

        #expect(mock.updatedRewards.isEmpty)
        #expect(mock.createdRewards.isEmpty)
    }

    @Test("a refused read renders as a failure, not as an invitation to write a gift")
    func refusedReadIsFailed() async {
        let mock = MockGameBackend()
        mock.listenerFailure = NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }

        guard case .failed = vm.contentState else {
            Issue.record("expected .failed, got \(String(describing: vm.contentState))")
            return
        }
    }

    /// A tiny solid-color image, just enough for `UIImage.jpegData` to produce real bytes.
    private func testImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    @Test("a new photo gift uploads every image once, to one shared folder, then creates once")
    func newPhotoGiftUploadsThenCreatesOnce() async {
        let mock = MockGameBackend()
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        vm.contentMode = .photos
        vm.title = "A few photos"
        vm.teaser = "For you"
        vm.photoPreviews = [testImage(), testImage(), testImage()]

        await vm.save()

        #expect(mock.callCount("uploadRewardMedia") == 3)
        let groups = Set(mock.uploadedRewardMedia.map(\.rewardId))
        #expect(groups.count == 1, "all three images should share one storage folder")
        #expect(mock.callCount("createReward") == 1)

        let created = mock.createdRewards.first
        #expect(created?.contentType == .image)
        #expect(created?.contentUrls?.count == 3)
        #expect(created?.contentText == nil)
        #expect(created?.contentUrl == nil, "images use contentUrls, never contentUrl")
    }

    @Test("a new letter gift never touches upload")
    func newLetterGiftDoesNotUpload() async {
        let mock = MockGameBackend()
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        vm.contentMode = .letter
        vm.title = "A letter"
        vm.letter = "Dear Alex..."

        await vm.save()

        #expect(!mock.called("uploadRewardMedia"))
        #expect(mock.createdRewards.first?.contentType == .text)
        #expect(mock.createdRewards.first?.contentText == "Dear Alex...")
    }

    @Test("isValid for photos requires a title and at least one image")
    func isValidForPhotos() async {
        let mock = MockGameBackend()
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "uid_jo", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        vm.contentMode = .photos

        #expect(!vm.isValid, "no title, no photos")
        vm.title = "A few photos"
        #expect(!vm.isValid, "title alone is not enough")
        vm.photoPreviews = [testImage()]
        #expect(vm.isValid)
    }

    @Test("editing an existing image gift with no new photos updates title and teaser only")
    func editExistingPhotoGiftWithoutNewPhotos() async {
        let mock = MockGameBackend()
        var mine = Reward(
            fromUserId: "u1", fromName: "Jordan", title: "A message from Jordan",
            teaser: "Teaser", pointCost: 100, contentType: .image, contentUrl: nil,
            contentUrls: ["events/evt_1/rewards/existing/photo.jpg"], contentText: nil,
            isUnlocked: false, unlockedAt: nil, sortOrder: 1,
            badgeIllustration: "photo.fill", createdAt: Date(timeIntervalSince1970: 0)
        )
        mine.id = "r_mine"
        mock.rewards = [mine]
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
        vm.loadExisting(userId: "u1", name: "Jordan")   // fixture's fromUserId is "u1"
        for _ in 0..<8 { await Task.yield() }
        #expect(vm.contentMode == .photos, "an existing image gift locks to photos mode")
        vm.teaser = "Updated teaser"

        await vm.save()

        #expect(!mock.called("uploadRewardMedia"))
        let sent = mock.updatedRewards.first?.fields ?? [:]
        #expect(!sent.keys.contains("contentUrls"), "no new photos were selected")
        #expect(sent["teaser"] as? String == "Updated teaser")
    }
}

@MainActor
@Suite("Gift curation")
struct GiftCurationTests {

    @Test("repricing sends only pointCost")
    func repriceSendsOnlyPrice() async {
        let mock = MockGameBackend()
        let vm = GiftCurationViewModel(eventId: "evt_1", service: mock)

        await vm.setPrice(150, for: .fixture(id: "r1"))

        #expect(mock.updatedRewards.first?.id == "r1")
        let sent = Set(mock.updatedRewards.first?.fields.keys ?? [:].keys)
        #expect(sent == ["pointCost"], "the rules deny a write that crosses tiers")
    }

    @Test("moving a gift rewrites the whole order, in the new sequence")
    func moveRewritesOrder() async {
        let mock = MockGameBackend()
        mock.rewards = [.fixture(id: "a", sortOrder: 0), .fixture(id: "b", sortOrder: 1),
                        .fixture(id: "c", sortOrder: 2)]
        let vm = GiftCurationViewModel(eventId: "evt_1", service: mock)
        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        await vm.move(from: IndexSet(integer: 2), to: 0)

        #expect(mock.rewardOrders.first == ["c", "a", "b"])
    }

    @Test("deleting a gift asks the backend to delete it")
    func deleteCallsBackend() async {
        let mock = MockGameBackend()
        let vm = GiftCurationViewModel(eventId: "evt_1", service: mock)

        await vm.delete(.fixture(id: "r7"))

        #expect(mock.deletedRewardIds == ["r7"])
    }

    @Test("an occasion with no gifts reads as empty, a refused read as failed")
    func statesAreDistinct() async {
        let empty = MockGameBackend()
        empty.rewards = []
        let emptyVM = GiftCurationViewModel(eventId: "evt_1", service: empty)
        emptyVM.startListening()
        for _ in 0..<8 { await Task.yield() }
        #expect(emptyVM.contentState == .empty)

        let refused = MockGameBackend()
        refused.listenerFailure = NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        let refusedVM = GiftCurationViewModel(eventId: "evt_1", service: refused)
        refusedVM.startListening()
        for _ in 0..<8 { await Task.yield() }
        guard case .failed = refusedVM.contentState else {
            Issue.record("expected .failed")
            return
        }
    }

    @Test("reconcile writes the true absolute count on drift")
    func reconcileWritesTrueCount() async {
        let mock = MockGameBackend()
        mock.rewards = [.fixture(id: "a"), .fixture(id: "b"), .fixture(id: "c")]
        let vm = GiftCurationViewModel(eventId: "evt_1", service: mock)
        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        await vm.reconcileCounter(storedTotal: 5)

        #expect(mock.called("updateGameState"))
        #expect(mock.updatedGameStateFields.last?["totalRewards"] as? Int == 3)
    }

    @Test("reconcile is a no-op when the stored count already matches")
    func reconcileNoOpWhenMatching() async {
        let mock = MockGameBackend()
        mock.rewards = [.fixture(id: "a"), .fixture(id: "b"), .fixture(id: "c")]
        let vm = GiftCurationViewModel(eventId: "evt_1", service: mock)
        vm.startListening()
        for _ in 0..<8 { await Task.yield() }

        await vm.reconcileCounter(storedTotal: 3)

        #expect(!mock.called("updateGameState"))
    }
}
