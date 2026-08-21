import SwiftUI
import OSLog
import ConfettiSwiftUI

// `nonisolated` because the target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
// would otherwise make this pure value type — and therefore its `Equatable` conformance —
// MainActor-isolated. The tests assert on it from a nonisolated context, which is a warning today
// and an error in the Swift 6 language mode. Nothing here touches UI, so opting out is correct
// rather than merely convenient.
//
// Kept above the doc comment, not between it and the declaration: SwiftLint's
// `orphaned_doc_comment` fires on a `///` block separated from what it documents.

/// What `RewardContentSheet` should actually render for a reward.
///
/// Extracted from the view body because every defect this replaced was a branch-selection
/// mistake — a one-element `contentUrls` gallery falling through to the *different*
/// `contentUrl` field, and an empty-string `contentText` rendering as a real but blank
/// letter — and none of them was reachable by a test while the decision lived in `body`.
nonisolated enum RewardContentPresentation: Equatable {
    case text(String)
    case video(URL)
    case audio(URL)
    /// One *or more* images from `contentUrls`. A single-element array belongs here:
    /// `contentUrls` and `contentUrl` are different fields and an image reward only ever
    /// populates the former, so sending a lone image to `singleImage` sends it to a nil field.
    case gallery([URL])
    /// An image reward carrying `contentUrl` instead of `contentUrls`.
    case singleImage(URL)
    /// Nothing presentable. Permanent — there is nothing to wait for.
    case unavailable

    init(reward: Reward) {
        switch reward.contentType {
        case .text:
            // Empty and whitespace-only mean the same thing as missing. Rendering either as
            // a letter shows the celebrant a blank gift attributed to a real person.
            let message = (reward.contentText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self = message.isEmpty ? .unavailable : .text(message)

        case .video:
            if let url = Self.loadableURL(reward.contentUrl) {
                self = .video(url)
            } else {
                self = .unavailable
            }

        case .audio:
            if let url = Self.loadableURL(reward.contentUrl) {
                self = .audio(url)
            } else {
                self = .unavailable
            }

        case .image:
            // One guard owns emptiness, and it owns it *after* parsing. Guarding the raw
            // strings instead would let an array of unloadable entries through as an empty
            // gallery, which renders as a blank pager captioned "1 of 0".
            let gallery = (reward.contentUrls ?? []).compactMap { Self.loadableURL($0) }
            if !gallery.isEmpty {
                self = .gallery(gallery)
            } else if let url = Self.loadableURL(reward.contentUrl) {
                self = .singleImage(url)
            } else {
                self = .unavailable
            }
        }
    }

    /// A stored string is loadable only if it parses *and* carries a scheme. `URL(string:)`
    /// percent-encodes junk rather than rejecting it, so a bare Storage path such as
    /// `rewards/r1/clip.mp4` yields a non-nil relative URL that no player can ever fetch.
    private static func loadableURL(_ string: String?) -> URL? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else {
            return nil
        }
        return url
    }
}

/// Sheet that reveals the unlocked reward content.
/// Triggers confetti on appear. Displays based on contentType.
struct RewardContentSheet: View {
    
    let reward: Reward
    let onDismiss: () -> Void
    
    @State private var confettiCounter = 0
    @State private var appeared = false
    
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "RewardContent")
    
    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()
            
            VStack(spacing: BQDesign.Spacing.lg) {
                // Header
                Capsule()
                    .fill(BQDesign.Colors.textTertiary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, BQDesign.Spacing.md)
                
                Spacer()
                
                // Content area
                VStack(spacing: BQDesign.Spacing.md) {
                    Text("🎉")
                        .font(.system(size: 50))
                        .scaleEffect(appeared ? 1 : 0.3)
                    
                    Text("A gift from \(reward.fromName)")
                        .font(BQDesign.Typography.screenTitle)
                        .foregroundColor(BQDesign.Colors.textPrimary)
                        .opacity(appeared ? 1 : 0)
                    
                    // Content based on type
                    Group {
                        switch presentation {
                        case .text(let message):
                            TextRewardView(text: message, fromName: reward.fromName)
                        case .video(let url):
                            VideoPlayerView(url: url)
                        case .audio(let url):
                            AudioPlayerView(url: url, fromName: reward.fromName)
                        case .gallery(let urls):
                            ImageGalleryView(urls: urls, fromName: reward.fromName)
                        case .singleImage(let url):
                            imageContent(url: url)
                        case .unavailable:
                            contentUnavailable("Nothing was added to this gift")
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                }
                
                Spacer()
                
                // Dismiss
                Button {
                    BQDesign.Haptics.light()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(BQDesign.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(BQDesign.Colors.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous))
                        .padding(.horizontal, BQDesign.Spacing.xl)
                }
                .padding(.bottom, BQDesign.Spacing.xl)
            }
            .confettiCannon(
                trigger: $confettiCounter,
                num: 50,
                colors: [
                    Color(hex: "7C5CFC"),
                    Color(hex: "FF6B9D"),
                    Color(hex: "FFA45B"),
                    Color(hex: "F5A623"),
                    Color(hex: "4CD964")
                ],
                rainHeight: 600,
                radius: 400
            )
        }
        .onAppear {
            withAnimation(BQDesign.Animation.bouncy.delay(0.1)) {
                appeared = true
            }

            if presentation == .unavailable {
                // No confetti and no success haptic for a gift with nothing in it. Both fired
                // unconditionally, so the single worst moment in the product — the celebrant
                // opens a gift a friend recorded for them and finds it empty — was dressed up
                // as the biggest win. Celebrating a failure also teaches the celebrant that
                // the celebration means nothing.
                //
                // The reveal is the payoff of the whole product, so this is a data defect
                // worth a trail. Nothing else would ever surface it.
                let rewardId = reward.id ?? "<no id>"
                logger.warning("Reward \(rewardId, privacy: .public) (\(reward.contentType.rawValue, privacy: .public)) has no content to show")
            } else {
                confettiCounter += 1
                BQDesign.Haptics.success()
            }
        }
    }
    
    // MARK: - Helpers
    
    /// The single owner of the "what do we actually show?" decision, extracted from `body`
    /// so it can be unit-tested. See RewardContentPresentationTests.
    private var presentation: RewardContentPresentation {
        RewardContentPresentation(reward: reward)
    }
}

// MARK: - Content Subviews

private extension RewardContentSheet {
    
    /// Image content using AsyncImage
    func imageContent(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous))
            case .failure:
                contentUnavailable("Couldn't load this image")
            default:
                ProgressView()
                    .tint(BQDesign.Colors.primaryPurple)
                    .frame(height: 200)
            }
        }
        .bqShadow(BQDesign.Shadows.card)
        .padding(.horizontal, BQDesign.Spacing.lg)
    }
    
    /// Fallback when there is nothing to show. `reason` keeps this honest at both call
    /// sites: content that was never authored will never arrive, whereas an image that
    /// failed to fetch might. Neither may claim it is "loading soon" — that is a promise
    /// the app cannot keep, and this surface is the one the celebrant believes.
    func contentUnavailable(_ reason: String) -> some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Image(systemName: "heart.circle")
                .font(.system(size: 40))
                .foregroundStyle(BQDesign.Colors.primaryGradient)
            
            Text("From \(reward.fromName)")
                .font(BQDesign.Typography.cardTitle)
                .foregroundColor(BQDesign.Colors.textSecondary)
            
            Text(reason)
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BQDesign.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
        )
        .bqShadow(BQDesign.Shadows.card)
        .padding(.horizontal, BQDesign.Spacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(reward.fromName). \(reason).")
    }
}
