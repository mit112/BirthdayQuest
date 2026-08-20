import Testing
import Foundation
import FirebaseCore
import FirebaseFirestore
@testable import BirthdayQuest

@Suite("Occasion model")
struct OccasionModelTests {

    @Test("every occasion type has display copy and a default challenge noun")
    func occasionTypeCopy() {
        for type in OccasionType.allCases {
            #expect(!type.displayName.isEmpty)
            #expect(!type.celebrantLabel.isEmpty)
        }
    }

    @Test("participant mode round-trips through its raw value")
    func participantModeRawValues() {
        #expect(ParticipantMode(rawValue: "contributor") == .contributor)
        #expect(ParticipantMode(rawValue: "celebrant") == .celebrant)
        #expect(ParticipantMode(rawValue: "host") == nil)
    }

    @Test("a reward with no fetchers defaults to an empty array via its memberwise init")
    func rewardFetchedByDefaultsViaInit() {
        // Guards the `= nil` default against a future edit that drops it. Does not exercise
        // decoding — see rewardFetchedByDefaultsViaFirestoreDecoder for that, which is also
        // the only thing standing between @DocumentID and a silent regression to a
        // hand-written init(from:) that would defeat it (R7).
        let reward = Reward(
            fromUserId: nil,
            fromName: "Sam",
            title: "A message",
            teaser: nil,
            pointCost: 50,
            contentType: .video,
            contentUrl: nil,
            contentUrls: nil,
            contentText: nil,
            isUnlocked: false,
            unlockedAt: nil,
            sortOrder: 0,
            badgeIllustration: "b",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect((reward.fetchedBy ?? []).isEmpty)
    }

    @Test("a reward with no fetchers decodes to an empty array via Firestore.Decoder, and its id comes from the document reference")
    func rewardFetchedByDefaultsViaFirestoreDecoder() throws {
        // FirebaseApp.configure() has already run by the time this executes: the test
        // target is app-hosted (TEST_HOST), so the app's own init() runs first, locally and
        // in CI (ci.yml stages GoogleService-Info.plist.example). Guarded defensively anyway.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        let ref = Firestore.firestore().collection("rewards").document("r1")
        let data: [String: Any] = [
            "fromName": "Sam",
            "title": "A message",
            "pointCost": 50,
            "contentType": "video",
            "isUnlocked": false,
            "sortOrder": 0,
            "badgeIllustration": "b",
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 0))
            // fetchedBy intentionally omitted — this is the pre-existing-document case.
        ]
        let reward = try Firestore.Decoder().decode(Reward.self, from: data, in: ref)
        #expect((reward.fetchedBy ?? []).isEmpty)
        // The regression guard for R7: if Reward ever regains a hand-written init(from:)
        // that decodes "id" as a plain String, @DocumentID stops being populated and this
        // becomes nil, silently breaking unlock-by-id for every Firestore-loaded reward.
        #expect(reward.id == "r1")
    }
}
