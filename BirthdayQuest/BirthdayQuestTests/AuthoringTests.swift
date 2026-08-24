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
