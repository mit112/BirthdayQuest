import Foundation
import AVFoundation
import Combine
import OSLog

/// Records a voice gift to a local `.m4a` file (AAC, mono), reporting elapsed time and
/// permission state. Hardware-bound, so it is kept thin and out of unit tests — all authoring
/// *logic* is tested through `GiftAuthoringViewModel.acceptAudio`, which this feeds.
///
/// The app configures `AVAudioSession(.playback)` at launch for reward playback; recording needs
/// `.playAndRecord`, so this sets that (with `.defaultToSpeaker` so review playback isn't routed
/// to the quiet earpiece) on `start()` and restores `.playback` on `stop()`/`cancel()`/`deinit`.
@MainActor
final class AudioRecorderController: NSObject, ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var permissionDenied = false

    /// Auto-stop cap. A 5-minute AAC/.m4a is only ~5 MB, well under the 200 MB Storage cap.
    static let maxDuration: TimeInterval = 5 * 60

    /// Delivered on a successful stop (manual or auto). The caller hands this to `acceptAudio`.
    var onFinish: ((URL) -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentURL: URL?
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "AudioRecorder")

    /// Requests permission if needed, then begins recording. No-op if already recording.
    func start() {
        guard !isRecording else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.permissionDenied = true; return }
                self.permissionDenied = false
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            logger.error("Audio session setup failed: \(error.localizedDescription)")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            guard recorder.record() else {
                logger.error("AVAudioRecorder.record() returned false")
                restoreSession()
                return
            }
            self.recorder = recorder
            self.currentURL = url
            self.isRecording = true
            self.elapsed = 0
            startTimer()
        } catch {
            logger.error("Recorder init failed: \(error.localizedDescription)")
            restoreSession()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
                if self.elapsed >= Self.maxDuration { self.stop() }
            }
        }
    }

    /// Stops recording and delivers the finished file via `onFinish`.
    func stop() {
        guard isRecording else { return }
        recorder?.stop()
        timer?.invalidate(); timer = nil
        isRecording = false
        restoreSession()
        if let url = currentURL { onFinish?(url) }
        recorder = nil
        currentURL = nil
    }

    /// Aborts recording and discards the temp file without delivering it.
    func cancel() {
        recorder?.stop()
        timer?.invalidate(); timer = nil
        isRecording = false
        if let url = currentURL { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        currentURL = nil
        restoreSession()
    }

    private func restoreSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            logger.error("Restoring playback session failed: \(error.localizedDescription)")
        }
    }

    deinit {
        timer?.invalidate()
        // deinit is nonisolated; restore the shared category directly (best-effort cleanup —
        // setCategory is thread-safe and touches no actor state).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }
}

extension AudioRecorderController: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Manual/auto stop already handled delivery; nothing to do on the normal path.
    }
}
