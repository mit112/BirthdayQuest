import SwiftUI
import ConfettiSwiftUI

/// Sheet that reveals the unlocked reward content.
/// Triggers confetti on appear. Displays based on contentType.
struct RewardContentSheet: View {
    
    let reward: Reward
    let onDismiss: () -> Void
    
    @State private var confettiCounter = 0
    @State private var appeared = false
    
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
                        switch reward.contentType {
                        case .text:
                            TextRewardView(
                                text: reward.contentText ?? "A heartfelt message awaits...",
                                fromName: reward.fromName
                            )
                        case .video:
                            if let url = contentURL {
                                VideoPlayerView(url: url)
                            } else {
                                contentUnavailable
                            }
                        case .audio:
                            if let url = contentURL {
                                AudioPlayerView(url: url, fromName: reward.fromName)
                            } else {
                                contentUnavailable
                            }
                        case .image:
                            if let urls = galleryURLs, urls.count > 1 {
                                ImageGalleryView(urls: urls, fromName: reward.fromName)
                            } else if let url = contentURL {
                                imageContent(url: url)
                            } else {
                                contentUnavailable
                            }
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
            confettiCounter += 1
            BQDesign.Haptics.success()
            withAnimation(BQDesign.Animation.bouncy.delay(0.1)) {
                appeared = true
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Resolves contentUrl string to a URL (expects HTTPS download URL stored in Firestore)
    private var contentURL: URL? {
        guard let urlString = reward.contentUrl, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
    
    /// Resolves contentUrls array to URLs for multi-image gallery
    private var galleryURLs: [URL]? {
        guard let urls = reward.contentUrls, !urls.isEmpty else { return nil }
        return urls.compactMap { URL(string: $0) }
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
                contentUnavailable
            default:
                ProgressView()
                    .tint(BQDesign.Colors.primaryPurple)
                    .frame(height: 200)
            }
        }
        .bqShadow(BQDesign.Shadows.card)
        .padding(.horizontal, BQDesign.Spacing.lg)
    }
    
    /// Fallback when content URL is missing or invalid
    var contentUnavailable: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Image(systemName: "heart.circle")
                .font(.system(size: 40))
                .foregroundStyle(BQDesign.Colors.primaryGradient)
            
            Text("From \(reward.fromName)")
                .font(BQDesign.Typography.cardTitle)
                .foregroundColor(BQDesign.Colors.textSecondary)
            
            Text("Content loading soon")
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
        )
        .bqShadow(BQDesign.Shadows.card)
        .padding(.horizontal, BQDesign.Spacing.lg)
    }
}
