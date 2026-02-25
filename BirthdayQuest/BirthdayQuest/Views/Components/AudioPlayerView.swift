import SwiftUI
import AVFoundation
import Combine

/// Custom audio player with decorative waveform visualization.
/// Uses AVPlayer for remote URL streaming.
struct AudioPlayerView: View {
    
    let url: URL
    let fromName: String
    
    @StateObject private var player = AudioPlayerController()
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            // Sender label
            Text("Audio from \(fromName)")
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textSecondary)
            
            // Decorative waveform
            waveformBars
                .frame(height: 50)
                .padding(.horizontal, BQDesign.Spacing.md)
            
            // Transport controls: skip back, play/pause, skip forward
            HStack(spacing: BQDesign.Spacing.xl) {
                // Skip back 10s
                Button {
                    BQDesign.Haptics.light()
                    player.skip(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(BQDesign.Colors.textSecondary)
                }
                .disabled(player.isFailed || player.isBuffering)
                
                // Play/Pause
                Button {
                    BQDesign.Haptics.light()
                    player.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(BQDesign.Colors.primaryGradient)
                            .frame(width: 64, height: 64)
                            .bqShadow(BQDesign.Shadows.glow)
                        
                        if player.isBuffering {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .offset(x: player.isPlaying ? 0 : 2)
                        }
                    }
                }
                .disabled(player.isFailed)
                
                // Skip forward 10s
                Button {
                    BQDesign.Haptics.light()
                    player.skip(by: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(BQDesign.Colors.textSecondary)
                }
                .disabled(player.isFailed || player.isBuffering)
            }

            // Scrubbable progress bar + time
            if player.duration > 0 {
                VStack(spacing: BQDesign.Spacing.xs) {
                    // Scrub track
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(BQDesign.Colors.textTertiary.opacity(0.15))
                            
                            Capsule()
                                .fill(BQDesign.Colors.primaryGradient)
                                .frame(width: geo.size.width * (player.isScrubbing ? player.scrubProgress : player.progress))
                            
                            // Drag thumb
                            Circle()
                                .fill(.white)
                                .frame(width: player.isScrubbing ? 16 : 10, height: player.isScrubbing ? 16 : 10)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                                .offset(x: geo.size.width * (player.isScrubbing ? player.scrubProgress : player.progress) - (player.isScrubbing ? 8 : 5))
                                .animation(.easeOut(duration: 0.1), value: player.isScrubbing)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let fraction = max(0, min(1, value.location.x / geo.size.width))
                                    player.beginScrubbing(to: CGFloat(fraction))
                                }
                                .onEnded { value in
                                    let fraction = max(0, min(1, value.location.x / geo.size.width))
                                    player.endScrubbing(at: CGFloat(fraction))
                                    BQDesign.Haptics.light()
                                }
                        )
                    }
                    .frame(height: 20) // Larger hit area
                    
                    // Time labels
                    HStack {
                        Text(player.isScrubbing ? player.scrubTimeString : player.currentTimeString)
                            .font(BQDesign.Typography.captionSmall)
                            .foregroundColor(BQDesign.Colors.textTertiary)
                        Spacer()
                        Text(player.durationString)
                            .font(BQDesign.Typography.captionSmall)
                            .foregroundColor(BQDesign.Colors.textTertiary)
                    }
                }
                .padding(.horizontal, BQDesign.Spacing.lg)
            }
            
            // Error state
            if player.isFailed {
                VStack(spacing: BQDesign.Spacing.sm) {
                    Text("Couldn't load audio")
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(BQDesign.Colors.textSecondary)
                    Button("Retry") {
                        player.loadAudio(from: url)
                    }
                    .font(BQDesign.Typography.bodyBold)
                    .foregroundColor(BQDesign.Colors.primaryPurple)
                }
            }
        }
        .padding(BQDesign.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                        .stroke(BQDesign.Colors.primaryPurple.opacity(0.1), lineWidth: 1)
                )
        )
        .bqShadow(BQDesign.Shadows.card)
        .padding(.horizontal, BQDesign.Spacing.lg)
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            player.loadAudio(from: url)
            withAnimation(BQDesign.Animation.smooth.delay(0.3)) {
                appeared = true
            }
        }
        .onDisappear {
            player.pause()
        }
    }
}

// MARK: - Waveform Bars

private extension AudioPlayerView {
    var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<24, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor(for: i))
                    .frame(width: 4)
                    .frame(height: barHeight(for: i))
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.05),
                        value: player.isPlaying
                    )
            }
        }
    }
    
    func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = player.isPlaying ? 8 : 4
        let heights: [CGFloat] = [0.3, 0.5, 0.7, 1.0, 0.8, 0.5, 0.9, 0.6, 1.0, 0.4, 0.7, 0.9,
                                   0.5, 0.8, 1.0, 0.6, 0.3, 0.7, 0.9, 0.5, 0.8, 0.4, 0.6, 0.7]
        let multiplier = heights[index % heights.count]
        return base + (42 * multiplier * (player.isPlaying ? 1 : 0.3))
    }
    
    func barColor(for index: Int) -> Color {
        let fraction = CGFloat(index) / 24.0
        if fraction < player.progress {
            return BQDesign.Colors.primaryPurple
        } else {
            return BQDesign.Colors.textTertiary.opacity(0.25)
        }
    }
}


// MARK: - Audio Player Controller

@MainActor
final class AudioPlayerController: ObservableObject {
    
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var isFailed = false
    @Published var progress: CGFloat = 0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isScrubbing = false
    @Published var scrubProgress: CGFloat = 0
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endOfPlaybackObserver: Any?
    private var wasPlayingBeforeScrub = false
    
    var currentTimeString: String { formatTime(currentTime) }
    var durationString: String { formatTime(duration) }
    var scrubTimeString: String { formatTime(Double(scrubProgress) * duration) }
    
    func loadAudio(from url: URL) {
        isFailed = false
        isBuffering = true
        
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
        
        // Observe item status
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isBuffering = false
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                case .failed:
                    self.isBuffering = false
                    self.isFailed = true
                default:
                    break
                }
            }
        }
        
        // Periodic time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.duration > 0, !self.isScrubbing else { return }
                self.currentTime = time.seconds
                self.progress = CGFloat(time.seconds / self.duration)
            }
        }
        
        // Observe end of playback (store token for proper removal)
        endOfPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.player?.seek(to: .zero)
                self?.progress = 0
                self?.currentTime = 0
            }
        }
    }
    
    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            pause()
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func skip(by seconds: Double) {
        guard let player, duration > 0 else { return }
        let target = max(0, min(duration, currentTime + seconds))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func beginScrubbing(to fraction: CGFloat) {
        if !isScrubbing {
            wasPlayingBeforeScrub = isPlaying
            isScrubbing = true
            player?.pause()
        }
        scrubProgress = fraction
    }
    
    func endScrubbing(at fraction: CGFloat) {
        guard let player, duration > 0 else {
            isScrubbing = false
            return
        }
        let target = Double(fraction) * duration
        let time = CMTime(seconds: target, preferredTimescale: 600)
        let shouldResume = wasPlayingBeforeScrub
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isScrubbing = false
                if shouldResume {
                    self.player?.play()
                    self.isPlaying = true
                }
            }
        }
        // Update displayed progress immediately
        progress = fraction
        currentTime = target
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
    
    deinit {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        statusObservation?.invalidate()
        if let observer = endOfPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
