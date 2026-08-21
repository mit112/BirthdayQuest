import Testing
import Foundation
@testable import BirthdayQuest

// MARK: - Fixtures

// `Reward.fixture` in MockGameBackend.swift covers contentUrl-only rewards; these cases need
// contentUrls and contentText, which are `let` and so cannot be set after the fact.
private func reward(
    contentType: RewardContentType,
    contentUrl: String? = nil,
    contentUrls: [String]? = nil,
    contentText: String? = nil
) -> Reward {
    Reward(
        fromUserId: "u1",
        fromName: "Sam",
        title: "A message from Sam",
        teaser: "Teaser",
        pointCost: 100,
        contentType: contentType,
        contentUrl: contentUrl,
        contentUrls: contentUrls,
        contentText: contentText,
        isUnlocked: true,
        unlockedAt: nil,
        sortOrder: 1,
        badgeIllustration: "heart_badge",
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

private let imageA = URL(string: "https://example.com/a.jpg")!
private let imageB = URL(string: "https://example.com/b.jpg")!
private let clip = URL(string: "https://example.com/clip.mp4")!

// MARK: - Tests

@Suite("Reward content presentation")
struct RewardContentPresentationTests {

    // MARK: Images

    @Test("a one-element contentUrls array resolves to the gallery, not the single-URL branch")
    func oneImageResolvesToGallery() {
        // The regression guard for the shipped defect: the branch tested `urls.count > 1`, so a
        // valid one-image gift fell through to `contentUrl` — a *different* field, nil for every
        // image reward — and the celebrant saw the "Content loading soon" placeholder forever.
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .image, contentUrls: [imageA.absoluteString])
        )
        #expect(presentation == .gallery([imageA]))
    }

    @Test("a multi-element contentUrls array resolves to the gallery")
    func manyImagesResolveToGallery() {
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .image,
                           contentUrls: [imageA.absoluteString, imageB.absoluteString])
        )
        #expect(presentation == .gallery([imageA, imageB]))
    }

    @Test("an image reward carrying only contentUrl still resolves to the single-image branch")
    func imageWithOnlyContentUrlResolvesToSingleImage() {
        // Behaviour preservation: dropping this branch would break any image reward authored
        // against contentUrl rather than contentUrls.
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .image, contentUrl: imageA.absoluteString)
        )
        #expect(presentation == .singleImage(imageA))
    }

    @Test("an empty contentUrls array falls back to contentUrl")
    func emptyGalleryFallsBackToContentUrl() {
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .image, contentUrl: imageA.absoluteString, contentUrls: [])
        )
        #expect(presentation == .singleImage(imageA))
    }

    @Test("an image reward with nothing in either field is unavailable")
    func imageWithNoUrlsIsUnavailable() {
        #expect(RewardContentPresentation(reward: reward(contentType: .image)) == .unavailable)
    }

    @Test("a contentUrls array of unloadable entries is unavailable, not an empty gallery")
    func unloadableGalleryIsUnavailable() {
        // Emptiness must be judged *after* parsing. Guarding the raw strings lets this through
        // as `.gallery([])`, which renders a blank pager captioned "1 of 0".
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .image, contentUrls: ["rewards/r1/a.jpg", ""])
        )
        #expect(presentation == .unavailable)
    }

    @Test("unloadable entries are dropped from an otherwise valid gallery")
    func unloadableEntriesAreDroppedFromGallery() {
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .image,
                           contentUrls: ["rewards/r1/a.jpg", imageB.absoluteString])
        )
        #expect(presentation == .gallery([imageB]))
    }

    // MARK: Text

    @Test("a text reward with a message resolves to text")
    func textWithMessageResolvesToText() {
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .text, contentText: "Happy birthday, kiddo.")
        )
        #expect(presentation == .text("Happy birthday, kiddo."))
    }

    @Test("a text reward's message is trimmed")
    func textMessageIsTrimmed() {
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .text, contentText: "\n  Happy birthday.  \n")
        )
        #expect(presentation == .text("Happy birthday."))
    }

    @Test("an empty-string contentText is unavailable, not a blank letter")
    func emptyTextIsUnavailable() {
        // The second shipped defect: `contentText ?? placeholder` only caught nil, so an empty
        // string rendered the full letter card — gold quotation mark, "from Sam" attribution —
        // containing nothing, presented to the celebrant as the real gift.
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .text, contentText: "")
        )
        #expect(presentation == .unavailable)
    }

    @Test("a whitespace-only contentText is unavailable")
    func whitespaceTextIsUnavailable() {
        let presentation = RewardContentPresentation(
            reward: reward(contentType: .text, contentText: "   \n\t ")
        )
        #expect(presentation == .unavailable)
    }

    @Test("a nil contentText is unavailable")
    func nilTextIsUnavailable() {
        #expect(RewardContentPresentation(reward: reward(contentType: .text)) == .unavailable)
    }

    // MARK: Video and audio

    @Test("a video reward with a loadable contentUrl resolves to video")
    func videoResolvesToVideo() {
        let presentation = RewardContentPresentation(
            reward: .fixture(contentType: .video, contentUrl: clip.absoluteString)
        )
        #expect(presentation == .video(clip))
    }

    @Test("an audio reward with a loadable contentUrl resolves to audio")
    func audioResolvesToAudio() {
        let presentation = RewardContentPresentation(
            reward: .fixture(contentType: .audio, contentUrl: clip.absoluteString)
        )
        #expect(presentation == .audio(clip))
    }

    @Test("a video reward with an empty-string contentUrl is unavailable")
    func emptyVideoUrlIsUnavailable() {
        let presentation = RewardContentPresentation(
            reward: .fixture(contentType: .video, contentUrl: "")
        )
        #expect(presentation == .unavailable)
    }

    @Test("an audio reward with a nil contentUrl is unavailable")
    func nilAudioUrlIsUnavailable() {
        #expect(RewardContentPresentation(reward: .fixture(contentType: .audio)) == .unavailable)
    }

    @Test("a schemeless storage path is unavailable rather than a URL no player can fetch")
    func schemelessPathIsUnavailable() {
        // URL(string:) percent-encodes junk instead of rejecting it, so `rewards/r1/clip.mp4`
        // parses into a non-nil *relative* URL. Handing that to AVPlayer buffers forever.
        let presentation = RewardContentPresentation(
            reward: .fixture(contentType: .video, contentUrl: "rewards/r1/clip.mp4")
        )
        #expect(presentation == .unavailable)
    }

    @Test("a whitespace-padded contentUrl still resolves")
    func paddedUrlResolves() {
        let presentation = RewardContentPresentation(
            reward: .fixture(contentType: .video, contentUrl: "  \(clip.absoluteString)\n")
        )
        #expect(presentation == .video(clip))
    }
}
