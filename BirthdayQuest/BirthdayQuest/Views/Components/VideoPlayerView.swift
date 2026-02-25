import SwiftUI
import AVKit

/// Video player for reward content. Wraps AVKit's VideoPlayer.
/// Auto-plays with a slight delay for dramatic reveal effect.
struct VideoPlayerView: View {
    
    let url: URL
    
    @State private var player: AVPlayer?
    @State private var isBuffering = true
    @State private var isFailed = false
    @State private var appeared = false
    @State private var statusObservation: NSKeyValueObservation?
    
    var body: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                    .fill(BQDesign.Colors.cardBackground)
                
                if isFailed {
                    // Error state
                    VStack(spacing: BQDesign.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(BQDesign.Colors.textTertiary)
                        Text("Couldn't load video")
                            .font(BQDesign.Typography.caption)
                            .foregroundColor(BQDesign.Colors.textSecondary)
                        Button("Retry") {
                            loadVideo()
                        }
                        .font(BQDesign.Typography.bodyBold)
                        .foregroundColor(BQDesign.Colors.primaryPurple)
                    }
                } else if let player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous))
                        .opacity(isBuffering ? 0 : 1)
                    
                    if isBuffering {
                        // Loading shimmer
                        VStack(spacing: BQDesign.Spacing.md) {
                            ProgressView()
                                .tint(BQDesign.Colors.primaryPurple)
                                .scaleEffect(1.2)
                            Text("Loading video...")
                                .font(BQDesign.Typography.caption)
                                .foregroundColor(BQDesign.Colors.textSecondary)
                        }
                    }
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous))
            .bqShadow(BQDesign.Shadows.card)
        }
        .padding(.horizontal, BQDesign.Spacing.lg)
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            loadVideo()
            withAnimation(BQDesign.Animation.smooth.delay(0.3)) {
                appeared = true
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
            statusObservation?.invalidate()
            statusObservation = nil
        }
    }
    
    private func loadVideo() {
        isFailed = false
        isBuffering = true
        
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    isBuffering = false
                    // Auto-play after a brief dramatic pause
                    try? await Task.sleep(for: .milliseconds(600))
                    avPlayer.play()
                case .failed:
                    isBuffering = false
                    isFailed = true
                default:
                    break
                }
            }
        }
        
        self.player = avPlayer
    }
}
