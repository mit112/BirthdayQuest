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

private let localA = URL(fileURLWithPath: "/tmp/a.jpg")
private let localB = URL(fileURLWithPath: "/tmp/b.jpg")
private let localClip = URL(fileURLWithPath: "/tmp/clip.mp4")

// MARK: - MockMediaStoring

/// Returns a fixed array of local URLs, or throws, regardless of the reward passed in — the
/// presenter's job is to react to what `MediaStore` hands back, not to inspect the reward itself.
private final class MockMediaStoring: MediaStoring, @unchecked Sendable {
    var urlsToReturn: [URL] = []
    var errorToThrow: Error?

    func localURLs(for reward: Reward, eventId: String) async throws -> [URL] {
        if let errorToThrow { throw errorToThrow }
        return urlsToReturn
    }

    func purge(reward: Reward, eventId: String) async throws {}
}

private struct StubbedError: Error {}

// MARK: - Tests

@Suite("Reward content presentation")
struct RewardContentPresentationTests {

    // MARK: Images

    @Test("image, mock returns 2 file urls resolves to a gallery, order preserved")
    func twoImagesResolveToGallery() async {
        let store = MockMediaStoring()
        store.urlsToReturn = [localA, localB]
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .image, contentUrls: ["events/e1/a.jpg", "events/e1/b.jpg"]),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .gallery([localA, localB]))
    }

    @Test("image, mock returns 1 url resolves to a gallery of one, not singleImage")
    func oneImageResolvesToGalleryNotSingleImage() async {
        // The regression guard for the shipped defect: a valid one-image gift must never route
        // through `singleImage`, which reads a different (nil) field.
        let store = MockMediaStoring()
        store.urlsToReturn = [localA]
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .image, contentUrls: ["events/e1/a.jpg"]),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .gallery([localA]))
    }

    @Test("image, mock throws resolves to unavailable")
    func imageMediaStoreThrowIsUnavailable() async {
        let store = MockMediaStoring()
        store.errorToThrow = StubbedError()
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .image, contentUrls: ["events/e1/a.jpg"]),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .unavailable)
    }

    @Test("image, mock returns an empty array resolves to unavailable")
    func imageEmptyUrlsIsUnavailable() async {
        let store = MockMediaStoring()
        store.urlsToReturn = []
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .image, contentUrls: ["events/e1/a.jpg"]),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .unavailable)
    }

    @Test("image, mock throws objectMissing resolves to expired")
    func imageObjectMissingIsExpired() async {
        let store = MockMediaStoring()
        store.errorToThrow = MediaStore.MediaStoreError.objectMissing
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .image, contentUrls: ["events/e1/a.jpg"]),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .expired)
    }

    // MARK: Text — resolved synchronously, no MediaStore involvement

    @Test("a text reward with a message resolves to text")
    func textWithMessageResolvesToText() async {
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .text, contentText: "Happy birthday, kiddo."),
            eventId: "e1",
            mediaStore: MockMediaStoring()
        )
        #expect(presentation == .text("Happy birthday, kiddo."))
    }

    @Test("a text reward's message is trimmed")
    func textMessageIsTrimmed() async {
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .text, contentText: "\n  Happy birthday.  \n"),
            eventId: "e1",
            mediaStore: MockMediaStoring()
        )
        #expect(presentation == .text("Happy birthday."))
    }

    @Test("an empty-string contentText is unavailable, not a blank letter")
    func emptyTextIsUnavailable() async {
        // The second shipped defect: `contentText ?? placeholder` only caught nil, so an empty
        // string rendered the full letter card — gold quotation mark, "from Sam" attribution —
        // containing nothing, presented to the celebrant as the real gift.
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .text, contentText: ""),
            eventId: "e1",
            mediaStore: MockMediaStoring()
        )
        #expect(presentation == .unavailable)
    }

    @Test("a whitespace-only contentText is unavailable")
    func whitespaceTextIsUnavailable() async {
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .text, contentText: "   \n\t "),
            eventId: "e1",
            mediaStore: MockMediaStoring()
        )
        #expect(presentation == .unavailable)
    }

    @Test("a nil contentText is unavailable")
    func nilTextIsUnavailable() async {
        let presentation = await RewardContentPresentation.resolve(
            reward: reward(contentType: .text),
            eventId: "e1",
            mediaStore: MockMediaStoring()
        )
        #expect(presentation == .unavailable)
    }

    // MARK: Video and audio

    @Test("video, mock returns 1 url resolves to video")
    func videoResolvesToVideo() async {
        let store = MockMediaStoring()
        store.urlsToReturn = [localClip]
        let presentation = await RewardContentPresentation.resolve(
            reward: .fixture(contentType: .video, contentUrl: "events/e1/clip.mp4"),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .video(localClip))
    }

    @Test("audio, mock returns 1 url resolves to audio")
    func audioResolvesToAudio() async {
        let store = MockMediaStoring()
        store.urlsToReturn = [localClip]
        let presentation = await RewardContentPresentation.resolve(
            reward: .fixture(contentType: .audio, contentUrl: "events/e1/clip.mp4"),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .audio(localClip))
    }

    @Test("video, mock returns an empty array resolves to unavailable")
    func videoEmptyUrlsIsUnavailable() async {
        let presentation = await RewardContentPresentation.resolve(
            reward: .fixture(contentType: .video, contentUrl: "events/e1/clip.mp4"),
            eventId: "e1",
            mediaStore: MockMediaStoring()
        )
        #expect(presentation == .unavailable)
    }

    @Test("audio, mock throws resolves to unavailable")
    func audioMediaStoreThrowIsUnavailable() async {
        let store = MockMediaStoring()
        store.errorToThrow = StubbedError()
        let presentation = await RewardContentPresentation.resolve(
            reward: .fixture(contentType: .audio, contentUrl: "events/e1/clip.mp4"),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .unavailable)
    }

    @Test("video, mock throws objectMissing resolves to expired")
    func videoObjectMissingIsExpired() async {
        let store = MockMediaStoring()
        store.errorToThrow = MediaStore.MediaStoreError.objectMissing
        let presentation = await RewardContentPresentation.resolve(
            reward: .fixture(contentType: .video, contentUrl: "events/e1/clip.mp4"),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .expired)
    }

    @Test("audio, mock throws objectMissing resolves to expired")
    func audioObjectMissingIsExpired() async {
        let store = MockMediaStoring()
        store.errorToThrow = MediaStore.MediaStoreError.objectMissing
        let presentation = await RewardContentPresentation.resolve(
            reward: .fixture(contentType: .audio, contentUrl: "events/e1/clip.mp4"),
            eventId: "e1",
            mediaStore: store
        )
        #expect(presentation == .expired)
    }
}
