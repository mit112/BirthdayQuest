import Foundation

/// Editable starter challenges a host can seed for a new occasion, keyed by occasion type. These are
/// SUGGESTIONS: each is created as an ordinary challenge the host can rename, re-point, or delete. The
/// copy intentionally matches the app's warm, family tone and carries no personalisation — review or
/// replace it to taste. The switch is exhaustive over `OccasionType` on purpose, so a new occasion
/// type forces a starter set to be written rather than silently shipping none.
enum ChallengeTemplates {
    struct Starter: Equatable {
        let title: String
        let description: String
        let pointValue: Int
    }

    static func starters(for type: OccasionType) -> [Starter] {
        switch type {
        case .birthday:
            return [
                Starter(title: "Share a favorite memory",
                        description: "Post a photo or a few words about a moment with them you treasure.",
                        pointValue: 50),
                Starter(title: "Record a birthday message",
                        description: "Say happy birthday in a short video or voice note.",
                        pointValue: 75),
                Starter(title: "Throwback photo",
                        description: "Dig up an old picture of the two of you.",
                        pointValue: 50),
            ]
        case .anniversary:
            return [
                Starter(title: "How you met the couple",
                        description: "Share the story of when you first met them.",
                        pointValue: 50),
                Starter(title: "A favorite moment together",
                        description: "Post a photo of a time you spent with the two of them.",
                        pointValue: 50),
                Starter(title: "A wish for the years ahead",
                        description: "Leave a note for the next chapter.",
                        pointValue: 75),
            ]
        case .graduation:
            return [
                Starter(title: "Advice for what's next",
                        description: "Share one piece of advice for the road ahead.",
                        pointValue: 50),
                Starter(title: "A proud moment",
                        description: "Tell them about a time you were proud of them.",
                        pointValue: 75),
                Starter(title: "Then and now",
                        description: "Post an old photo next to a recent one.",
                        pointValue: 50),
            ]
        case .farewell:
            return [
                Starter(title: "A favorite memory",
                        description: "Share a moment with them you'll miss.",
                        pointValue: 50),
                Starter(title: "A message for the send-off",
                        description: "Record a short goodbye.",
                        pointValue: 75),
                Starter(title: "Keep in touch",
                        description: "Leave a note about the next time you'll see them.",
                        pointValue: 50),
            ]
        case .bachelor:
            return [
                Starter(title: "A story worth telling",
                        description: "Share a favorite (keep-it-PG!) story about them.",
                        pointValue: 50),
                Starter(title: "A wish for the big day",
                        description: "Leave a note for the wedding ahead.",
                        pointValue: 75),
                Starter(title: "Throwback photo",
                        description: "Post a memory from before all this.",
                        pointValue: 50),
            ]
        }
    }
}
