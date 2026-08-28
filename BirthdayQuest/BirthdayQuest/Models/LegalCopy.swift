import Foundation

/// Terms of Use shown in-app (`TermsView`), written to satisfy App Store Guideline 1.2
/// (user-generated content apps must have users agree to terms with a zero-tolerance policy
/// for objectionable content and abusive users).
///
/// **This is product copy, not legal advice.** It was drafted to match the app's own voice —
/// see the README's "Why This Exists" section — and to describe this app's *actual* behaviour
/// (checked against `MediaLifecycle.swift`, `AdminControlsView.swift`, and the `reports`
/// collection). It has NOT been reviewed by a lawyer. Have it reviewed before shipping to the
/// App Store, and fill in the two placeholders below with real values before that review:
/// `LegalCopy.supportEmailPlaceholder` and `LegalCopy.privacyPolicyURLPlaceholder`.
enum LegalCopy {

    /// **Placeholder.** Replace with the developer's real support address before submission.
    static let supportEmailPlaceholder = "REPLACE_WITH_SUPPORT_EMAIL@example.com"

    /// **Placeholder.** Replace with a real, hosted privacy policy URL before submission.
    static let privacyPolicyURLPlaceholder = "https://REPLACE_WITH_PRIVACY_POLICY_URL"

    /// One section of the terms, rendered as a heading + body paragraphs so `TermsView` can
    /// mark each heading for VoiceOver navigation.
    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let paragraphs: [String]
    }

    static let lastUpdated = "August 2026"

    static let sections: [Section] = [
        Section(
            title: "Zero tolerance",
            paragraphs: [
                "This app exists so people can celebrate someone they care about. There is zero " +
                "tolerance here for objectionable content or abusive behaviour — that includes " +
                "harassment, hate speech, threats, nudity, or anything meant to hurt the person " +
                "you're supposed to be celebrating or anyone else in the occasion.",
                "If you see it, report it. If you post it, it comes down and you can be removed " +
                "from the occasion. There's no warning system for this — it's a party for one " +
                "person, not a place to be cruel."
            ]
        ),
        Section(
            title: "What you're agreeing to",
            paragraphs: [
                "By using this app you agree to these terms. If you don't agree, don't join an " +
                "occasion."
            ]
        ),
        Section(
            title: "What you post",
            paragraphs: [
                "An occasion is a small, invite-only group — but it's still a group. Photos, " +
                "videos, voice notes, and text you add as a gift, a challenge, or proof of a " +
                "challenge are visible to the other people in that occasion.",
                "You're responsible for what you upload. Only post things you have the right to " +
                "share, and don't post anything about someone else without their okay."
            ]
        ),
        Section(
            title: "Moderation",
            paragraphs: [
                "The person who created the occasion (the host) can remove any content in it, " +
                "and can remove any participant from the occasion entirely.",
                "Anyone in an occasion can report a gift or a challenge that shouldn't be there. " +
                "A report goes straight to the host, who can act on it."
            ]
        ),
        Section(
            title: "How long things stick around",
            paragraphs: [
                "Gifts with photos, video, or audio stop being needed on our servers 30 days after " +
                "the occasion date. Once the person being celebrated has opened a gift and their " +
                "device is holding its own copy, the app deletes the server copy for them. Until " +
                "both of those are true, the file stays where it is — so treat 30 days as the " +
                "point it becomes eligible to go, not a guarantee it already has.",
                "Open your gifts before then; that's what triggers the cleanup. Text gifts and the " +
                "point and challenge record aren't affected by any of this. The host can also " +
                "delete a gift's media at any time."
            ]
        ),
        Section(
            title: "Your account",
            paragraphs: [
                "You can delete your account from inside the app, and it takes effect immediately. " +
                "It removes who you are — your name, your avatar, and your place in every occasion " +
                "you joined.",
                "What it does not remove is what you made for other people. Gifts, dares, and " +
                "timeline entries you contributed stay with their occasions, because someone else's " +
                "celebration shouldn't lose a present just because you closed your account. If you " +
                "want something you made taken down as well, ask that occasion's host to delete it " +
                "before you go.",
                "One thing to know if you host: an occasion you created keeps running without you, " +
                "but nobody can administer it afterwards. The app tells you which occasions this " +
                "affects before you confirm."
            ]
        ),
        Section(
            title: "Contact",
            paragraphs: [
                "Questions, reports, or account requests: \(supportEmailPlaceholder).",
                "Privacy policy: \(privacyPolicyURLPlaceholder)."
            ]
        )
    ]
}
