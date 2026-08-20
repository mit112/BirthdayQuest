import Testing
import Foundation
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

    @Test("a reward with no fetchers defaults to an empty array")
    func rewardFetchedByDefaults() {
        // Reward carries @DocumentID, which Firestore.Decoder populates specially and
        // which throws on a plain JSONDecoder regardless of whether "id" is present —
        // so this exercises the memberwise init (omitting fetchedBy) rather than decoding.
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
}
