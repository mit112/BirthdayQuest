import SwiftUI
import AVKit
import Combine
import OSLog

/// Manages AVPlayer lifecycle and KVO observation for video playback.
@MainActor
final class VideoPlayerController: ObservableObject {

    @Published var player: AVPlayer?
    @Published var isBuffering = true
    @Published var isFailed = false

    private var statusObservation: NSKeyValueObservation?
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "VideoPlayer")

    func loadVideo(url: URL) {
        isFailed = false
        isBuffering = true
        statusObservation?.invalidate()

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isBuffering = false
                    try? await Task.sleep(for: .milliseconds(600))
                    // Only play if the player is still active (not cleaned up during the sleep)
                    guard self.player != nil else { return }
                    avPlayer.play()
                case .failed:
                    self.isBuffering = false
                    self.isFailed = true
                    self.logger.error("Video failed to load")
                default:
                    break
                }
            }
        }

        self.player = avPlayer
    }

    func cleanup() {
        player?.pause()
        player = nil
        statusObservation?.invalidate()
        statusObservation = nil
    }

    deinit {
        statusObservation?.invalidate()
    }
}

/// Video player for reward content. Wraps AVKit's VideoPlayer.
/// Auto-plays with a slight delay for dramatic reveal effect.
struct VideoPlayerView: View {

    let url: URL

    @StateObject private var controller = VideoPlayerController()
    @State private var appeared = false

    var body: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                    .fill(BQDesign.Colors.cardBackground)

                if controller.isFailed {
                    // Error state
                    VStack(spacing: BQDesign.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(BQDesign.Colors.textTertiary)
                        Text("Couldn't load video")
                            .font(BQDesign.Typography.caption)
                            .foregroundColor(BQDesign.Colors.textSecondary)
                        Button("Retry") {
                            controller.loadVideo(url: url)
                        }
                        .font(BQDesign.Typography.bodyBold)
                        .foregroundColor(BQDesign.Colors.primaryPurple)
                    }
                } else if let player = controller.player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous))
                        .opacity(controller.isBuffering ? 0 : 1)

                    if controller.isBuffering {
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
            controller.loadVideo(url: url)
            withAnimation(BQDesign.Animation.smooth.delay(0.3)) {
                appeared = true
            }
        }
        .onDisappear {
            controller.cleanup()
        }
    }
}
