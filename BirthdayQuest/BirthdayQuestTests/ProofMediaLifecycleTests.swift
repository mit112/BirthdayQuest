import Testing
import Foundation
@testable import BirthdayQuest

// MARK: - Fixtures

private func challenge(id: String, isSecret: Bool = false) -> Challenge {
    Challenge(
        id: id,
        title: "Dare \(id)",
        description: "Do it",
        illustrationAsset: "dare",
        pointValue: 50,
        difficulty: .easy,
        category: .social,
        isSecret: isSecret,
        createdByUserId: "u1",
        isDelivered: true,
        isCompleted: true,
        completedAt: Date(timeIntervalSince1970: 0),
        proofUrl: "events/e1/proofs/\(id)/photo.jpg",
        proofType: "photo",
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

// MARK: - SpyProofMediaPurging

private final class SpyProofMediaPurging: ProofMediaPurging, @unchecked Sendable {
    private(set) var calls: [(challengeIds: [String], eventId: String, occasionDate: Date, now: Date)] = []

    func purgeExpiredProofs(
        challenges: [Challenge], eventId: String, occasionDate: Date, now: Date
    ) async -> Int {
        calls.append((challenges.compactMap(\.id), eventId, occasionDate, now))
        return 0
    }

    func purgeProof(for challenge: Challenge, eventId: String) async -> Bool { false }
}

// MARK: - ChallengesViewModel proof lifecycle

@Suite("ChallengesViewModel proof media lifecycle")
@MainActor
struct ChallengesViewModelProofLifecycleTests {

    private let occasionDate = Date(timeIntervalSince1970: 0)

    /// `startListening` hops the snapshot onto a `Task { @MainActor in ... }`, so the view model's
    /// `challenges` is still empty on the line after the call. In production this cannot bite —
    /// the sweep fires from an `.onChange(of: contentState)`, which by definition has already
    /// observed the delivered snapshot — but a test that skipped this would silently sweep an
    /// empty list and still see one call.
    private func makeViewModel(
        challenges: [Challenge]
    ) async -> (ChallengesViewModel, SpyProofMediaPurging) {
        let service = MockGameBackend()
        service.challenges = challenges
        let spy = SpyProofMediaPurging()
        let viewModel = ChallengesViewModel(eventId: "e1", service: service, proofMedia: spy)
        viewModel.startListening()
        await settle()
        return (viewModel, spy)
    }

    /// The spy's `purgeExpiredProofs` runs in a detached Task, so give the runtime a turn.
    private func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test("celebrant with an occasion date: sweeps once")
    func celebrantSweeps() async {
        let (viewModel, spy) = await makeViewModel(challenges: [challenge(id: "c1")])

        viewModel.runProofMediaLifecycle(isCelebrant: true, occasionDate: occasionDate, now: occasionDate)
        await settle()

        #expect(spy.calls.count == 1)
        #expect(spy.calls.first?.eventId == "e1")
        #expect(spy.calls.first?.occasionDate == occasionDate)
        #expect(spy.calls.first?.challengeIds == ["c1"])
    }

    @Test("a contributor never sweeps — proof delete is celebrant-only in the Storage rules")
    func contributorDoesNotSweep() async {
        let (viewModel, spy) = await makeViewModel(challenges: [challenge(id: "c1")])

        viewModel.runProofMediaLifecycle(isCelebrant: false, occasionDate: occasionDate, now: occasionDate)
        await settle()

        #expect(spy.calls.isEmpty)
    }

    @Test("no occasion date: nothing to anchor expiry to, so no sweep")
    func missingOccasionDateDoesNotSweep() async {
        let (viewModel, spy) = await makeViewModel(challenges: [challenge(id: "c1")])

        viewModel.runProofMediaLifecycle(isCelebrant: true, occasionDate: nil, now: occasionDate)
        await settle()

        #expect(spy.calls.isEmpty)
    }

    @Test("one-shot: repeated calls sweep only once")
    func sweepIsOneShot() async {
        let (viewModel, spy) = await makeViewModel(challenges: [challenge(id: "c1")])

        viewModel.runProofMediaLifecycle(isCelebrant: true, occasionDate: occasionDate, now: occasionDate)
        viewModel.runProofMediaLifecycle(isCelebrant: true, occasionDate: occasionDate, now: occasionDate)
        viewModel.runProofMediaLifecycle(isCelebrant: true, occasionDate: occasionDate, now: occasionDate)
        await settle()

        #expect(spy.calls.count == 1)
    }

    @Test("secret challenges are swept too — the board filters them out, the sweep must not")
    func sweepIncludesSecretChallenges() async {
        let (viewModel, spy) = await makeViewModel(
            challenges: [challenge(id: "c1"), challenge(id: "c-secret", isSecret: true)]
        )

        viewModel.runProofMediaLifecycle(isCelebrant: true, occasionDate: occasionDate, now: occasionDate)
        await settle()

        #expect(spy.calls.first?.challengeIds.sorted() == ["c-secret", "c1"])
    }
}

// MARK: - ProofImagePresentation

@Suite("ProofImagePresentation")
@MainActor
struct ProofImagePresentationTests {

    @Test("a missing Storage object reads as expired, not as a load failure")
    func objectMissingIsExpired() {
        #expect(ProofImagePresentation.resolve(error: MediaStore.MediaStoreError.objectMissing) == .expired)
    }

    @Test("any other error reads as a load failure")
    func otherErrorIsFailed() {
        #expect(ProofImagePresentation.resolve(error: NSError(domain: "test", code: 1)) == .failed)
        #expect(ProofImagePresentation.resolve(error: MediaStore.MediaStoreError.missingRewardId) == .failed)
    }
}
