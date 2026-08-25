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
    /// Media is still resolving through `MediaStore` (download, or a cache-hit disk read).
    case loading
    case text(String)
    case video(URL)
    case audio(URL)
    /// One *or more* images. Always used for image rewards, even a single one: a lone image
    /// resolving to `singleImage` instead was the shipped defect this type replaced — do not
    /// resurrect that branch.
    case gallery([URL])
    /// Nothing presentable. Permanent — there is nothing to wait for.
    case unavailable

    /// Resolves a reward's content asynchronously. Text is judged locally and synchronously;
    /// media (image/video/audio) is resolved through `MediaStore`, which downloads the Storage
    /// object(s) referenced by the reward's (schemeless) stored path(s) into local `file://`
    /// URLs. Media URLs come only from `MediaStore` — never built from the stored path directly
    /// (D1 / Ruling P2).
    static func resolve(
        reward: Reward,
        eventId: String,
        mediaStore: MediaStoring
    ) async -> RewardContentPresentation {
        switch reward.contentType {
        case .text:
            // Empty and whitespace-only mean the same thing as missing. Rendering either as
            // a letter shows the celebrant a blank gift attributed to a real person.
            let message = (reward.contentText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? .unavailable : .text(message)

        case .video:
            let urls = (try? await mediaStore.localURLs(for: reward, eventId: eventId)) ?? []
            return urls.first.map(RewardContentPresentation.video) ?? .unavailable

        case .audio:
            let urls = (try? await mediaStore.localURLs(for: reward, eventId: eventId)) ?? []
            return urls.first.map(RewardContentPresentation.audio) ?? .unavailable

        case .image:
            let urls = (try? await mediaStore.localURLs(for: reward, eventId: eventId)) ?? []
            return urls.isEmpty ? .unavailable : .gallery(urls)
        }
    }
}

/// Sheet that reveals the unlocked reward content.
/// Triggers confetti on appear. Displays based on contentType.
struct RewardContentSheet: View {
    
    let reward: Reward
    let eventId: String
    let onDismiss: () -> Void
    var mediaStore: MediaStoring = MediaStore()

    @State private var confettiCounter = 0
    @State private var appeared = false
    @State private var presentation: RewardContentPresentation = .loading
    @ScaledMetric private var confettiEmojiSize: CGFloat = 50
    @ScaledMetric private var unavailableHeartIconSize: CGFloat = 40

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
                        .font(.system(size: confettiEmojiSize))
                        .scaleEffect(appeared ? 1 : 0.3)
                    
                    Text("A gift from \(reward.fromName)")
                        .font(BQDesign.Typography.screenTitle)
                        .foregroundColor(BQDesign.Colors.textPrimary)
                        .opacity(appeared ? 1 : 0)
                    
                    // Content based on type
                    Group {
                        switch presentation {
                        case .loading:
                            ProgressView()
                                .tint(BQDesign.Colors.primaryPurple)
                                .frame(height: 200)
                        case .text(let message):
                            TextRewardView(text: message, fromName: reward.fromName)
                        case .video(let url):
                            VideoPlayerView(url: url)
                        case .audio(let url):
                            AudioPlayerView(url: url, fromName: reward.fromName)
                        case .gallery(let urls):
                            ImageGalleryView(urls: urls, fromName: reward.fromName)
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
                        .frame(minHeight: 52)
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
        }
        .task {
            presentation = await RewardContentPresentation.resolve(
                reward: reward,
                eventId: eventId,
                mediaStore: mediaStore
            )

            switch presentation {
            case .loading:
                // Never produced by `resolve`; nothing to celebrate or log.
                break
            case .unavailable:
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
            default:
                confettiCounter += 1
                BQDesign.Haptics.success()
            }
        }
    }
}

// MARK: - Content Subviews

private extension RewardContentSheet {

    /// Fallback when there is nothing to show. `reason` keeps this honest at both call
    /// sites: content that was never authored will never arrive, whereas an image that
    /// failed to fetch might. Neither may claim it is "loading soon" — that is a promise
    /// the app cannot keep, and this surface is the one the celebrant believes.
    func contentUnavailable(_ reason: String) -> some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Image(systemName: "heart.circle")
                .font(.system(size: unavailableHeartIconSize))
                .foregroundStyle(BQDesign.Colors.primaryGradient)
            
            Text("From \(reward.fromName)")
                .font(BQDesign.Typography.cardTitle)
                .foregroundColor(BQDesign.Colors.textSecondary)
            
            Text(reason)
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BQDesign.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
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
