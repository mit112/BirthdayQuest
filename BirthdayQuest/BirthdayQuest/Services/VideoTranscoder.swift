import Foundation
import AVFoundation

// MARK: - VideoTranscoding

/// Re-encodes a picked clip into something worth uploading.
///
/// Injectable for the same reason `MediaTransferring` is: the production implementation is
/// hardware video encoding, which a unit test cannot run, but everything the view model does
/// *around* it — which file wins on size, the fall back to the original when an export fails,
/// the cancel-on-re-pick — is ordinary logic worth pinning.
protocol VideoTranscoding: Sendable {
    /// Writes a re-encoded copy of `source` to `destination`, which must not already exist.
    ///
    /// `onProgress` receives a 0…1 fraction and may be called from any context. Throws
    /// `CancellationError` if the enclosing task is cancelled, leaving nothing usable at
    /// `destination` — the caller cleans it up.
    func transcode(
        source: URL,
        destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// `AVAssetExportSession` refused to initialise for this asset. Rare — a file with no video
/// track, or protected content — and the caller falls back to uploading the original.
struct VideoTranscodeUnsupported: Error {}

// MARK: - AVFoundationVideoTranscoder

/// Exports through `AVAssetExportSession` at ~1080p, into an `.mp4`.
///
/// HEVC first, H.264 as the fallback. At 1080p HEVC lands roughly half the bitrate of H.264 at
/// the same quality, which is the difference between a modern 4K clip arriving as tens of MB and
/// as hundreds. Every device that can run this app (iOS 26 ⇒ A12 or later) has a hardware HEVC
/// encoder, and the only thing that ever plays the file is this same app's `AVPlayer`, so there
/// is no compatibility argument for H.264 — but a preset can still be genuinely incompatible with
/// an unusual source, so the SDK's compatibility check decides rather than an assumption.
///
/// Presets scale **down** only: a 720p source is re-encoded at 720p, never upscaled to 1080p.
struct AVFoundationVideoTranscoder: VideoTranscoding {

    /// How often the export is polled. Fast enough that the bar visibly moves on a short clip,
    /// slow enough that a multi-minute export is not four actor hops a second throughout.
    private static let progressInterval: TimeInterval = 0.25

    func transcode(
        source: URL,
        destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(
            asset: asset, presetName: await Self.preset(for: asset)
        ) else {
            throw VideoTranscodeUnsupported()
        }

        // Started before the export so the first tick is not missed, and cancelled in `defer` so
        // a failed or cancelled export cannot leave it iterating. The sequence's failure type is
        // `Never`, so there is nothing here to catch.
        let progressTask = Task {
            for await state in session.states(updateInterval: Self.progressInterval) {
                if case .exporting(let progress) = state {
                    onProgress(progress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }

        // `export(to:as:)` honours task cancellation directly on iOS 26 — `cancelExport()` is
        // deprecated in favour of exactly that — so re-picking a clip stops the encode rather
        // than leaving it running behind the new one.
        try await session.export(to: destination, as: .mp4)
    }

    /// The best preset this asset actually supports, preferring HEVC.
    private static func preset(for asset: AVURLAsset) async -> String {
        let hevc = AVAssetExportPresetHEVC1920x1080
        let compatible = await AVAssetExportSession.compatibility(
            ofExportPreset: hevc, with: asset, outputFileType: .mp4
        )
        return compatible ? hevc : AVAssetExportPreset1920x1080
    }
}
