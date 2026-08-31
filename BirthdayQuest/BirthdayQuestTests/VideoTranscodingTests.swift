import Testing
import Foundation
import UIKit
@testable import BirthdayQuest

/// Stands in for `AVAssetExportSession`. The real encode is hardware-bound and cannot run in a
/// unit test — the same reason `AudioRecorderController` is untested — but everything the view
/// model decides *around* it can, and does here: which file survives, what happens when the
/// export fails, and whether the progress indicator ever gets stuck on.
final class StubVideoTranscoder: VideoTranscoding, @unchecked Sendable {

    /// Logical size of the file written to `destination` on success. `nil` means the export
    /// produced nothing and `error` is thrown instead.
    var outputBytes: Int?
    /// Thrown instead of writing an output. `outputBytes` is ignored when this is set.
    var error: Error?
    /// Fractions handed to `onProgress` before the export finishes.
    var progressToReport: [Double] = []
    /// When true, `transcode` parks until `release()` — long enough for a test to observe the
    /// view model mid-export.
    var holdUntilReleased = false

    private(set) var transcodeCount = 0
    private(set) var lastSource: URL?
    private(set) var lastDestination: URL?
    private var released = false

    func release() { released = true }

    func transcode(
        source: URL,
        destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        transcodeCount += 1
        lastSource = source
        lastDestination = destination
        for fraction in progressToReport { onProgress(fraction) }

        // Bounded, so a test that forgets to release fails on its assertions rather than hanging.
        var spins = 0
        while holdUntilReleased && !released && spins < 10_000 {
            await Task.yield()
            spins += 1
        }

        if let error { throw error }
        guard let outputBytes else { return }
        TranscodeTestFiles.write(bytes: outputBytes, to: destination)
    }
}

/// Sparse files: a 600 MB source has to *measure* 600 MB without costing 600 MB of disk or of
/// test runtime. `truncate` leaves the blocks unallocated while `NSFileSize` reports the logical
/// length, which is exactly what `prepareVideo` reads.
enum TranscodeTestFiles {
    static func write(bytes: Int, to url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        try? handle.truncate(atOffset: UInt64(bytes))
        try? handle.close()
    }

    static func file(bytes: Int, ext: String = "mov") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        write(bytes: bytes, to: url)
        return url
    }
}

@MainActor
@Suite("A picked clip is transcoded before it is measured")
struct VideoTranscodePreparationTests {

    private func viewModel(
        _ mock: MockGameBackend, _ transcoder: StubVideoTranscoder
    ) -> GiftAuthoringViewModel {
        GiftAuthoringViewModel(eventId: "evt_1", service: mock, transcoder: transcoder)
    }

    // MARK: The reason this exists

    @Test("a clip far over the cap is accepted once the transcode brings it under")
    func oversizedSourceSurvivesTranscoding() async {
        let transcoder = StubVideoTranscoder()
        transcoder.outputBytes = 40 * 1024 * 1024
        let vm = viewModel(MockGameBackend(), transcoder)
        let source = TranscodeTestFiles.file(bytes: 600 * 1024 * 1024)

        await vm.prepareVideo(source: source)

        #expect(!vm.videoTooLarge, "600 MB in, 40 MB out — the old cap never sees the source")
        #expect(vm.selectedVideoURL == transcoder.lastDestination)
        #expect(!FileManager.default.fileExists(atPath: source.path), "the original is dropped")
    }

    @Test("a source still over the cap after transcoding is refused, and nothing is left behind")
    func stillOversizedAfterTranscodingIsRefused() async throws {
        let transcoder = StubVideoTranscoder()
        transcoder.outputBytes = GiftAuthoringViewModel.maxVideoBytes + 1
        let vm = viewModel(MockGameBackend(), transcoder)
        let source = TranscodeTestFiles.file(bytes: 900 * 1024 * 1024)

        await vm.prepareVideo(source: source)

        #expect(vm.videoTooLarge, "200 MB is still the backstop")
        #expect(vm.selectedVideoURL == nil)
        let destination = try #require(transcoder.lastDestination)
        #expect(
            !FileManager.default.fileExists(atPath: destination.path),
            "the refused export is deleted — acceptVideo only clears the *previous* selection"
        )
    }

    // MARK: Which file wins

    @Test("an export that is no smaller than the source is discarded")
    func nonShrinkingExportIsDiscarded() async throws {
        let transcoder = StubVideoTranscoder()
        transcoder.outputBytes = 8_000
        let vm = viewModel(MockGameBackend(), transcoder)
        let source = TranscodeTestFiles.file(bytes: 4_000)

        await vm.prepareVideo(source: source)

        #expect(vm.selectedVideoURL == source, "uploading less is the point; re-encoding is not")
        #expect(FileManager.default.fileExists(atPath: source.path))
        let destination = try #require(transcoder.lastDestination)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("an export that wrote nothing measurable is discarded, not uploaded")
    func unmeasurableExportIsDiscarded() async {
        let transcoder = StubVideoTranscoder()
        transcoder.outputBytes = nil   // returns without writing anything
        let vm = viewModel(MockGameBackend(), transcoder)
        let source = TranscodeTestFiles.file(bytes: 4_000)

        await vm.prepareVideo(source: source)

        #expect(vm.selectedVideoURL == source, "a zero-byte export must never win on size")
        #expect(!vm.videoTooLarge)
    }

    // MARK: Failure is not a refusal

    @Test("a failed transcode falls back to the original and keeps a valid clip usable")
    func failedTranscodeFallsBackToOriginal() async {
        let transcoder = StubVideoTranscoder()
        transcoder.error = MockGameBackend.StubbedError()
        let vm = viewModel(MockGameBackend(), transcoder)
        let source = TranscodeTestFiles.file(bytes: 4_000)

        await vm.prepareVideo(source: source)

        #expect(vm.selectedVideoURL == source, "an export failing is no reason to refuse the clip")
        #expect(!vm.videoTooLarge)
    }

    @Test("a failed transcode leaves the size cap in force for the original")
    func failedTranscodeStillEnforcesTheCap() async {
        let transcoder = StubVideoTranscoder()
        transcoder.error = MockGameBackend.StubbedError()
        let vm = viewModel(MockGameBackend(), transcoder)
        let source = TranscodeTestFiles.file(bytes: GiftAuthoringViewModel.maxVideoBytes)

        await vm.prepareVideo(source: source)

        #expect(vm.videoTooLarge, "this is exactly the behaviour that shipped before transcoding")
        #expect(vm.selectedVideoURL == nil)
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: The progress indicator

    @Test("the transcode flag is on during the export and off after it")
    func transcodingFlagBracketsTheExport() async {
        let transcoder = StubVideoTranscoder()
        transcoder.outputBytes = 1_000
        transcoder.holdUntilReleased = true
        let vm = viewModel(MockGameBackend(), transcoder)
        let source = TranscodeTestFiles.file(bytes: 4_000)

        let preparation = Task { await vm.prepareVideo(source: source) }
        for _ in 0..<8 { await Task.yield() }
        #expect(vm.isTranscoding, "nothing else on screen explains the wait")

        transcoder.release()
        await preparation.value
        #expect(!vm.isTranscoding, "and it must not stick on afterwards")
    }

    @Test("a transcode that throws still clears the progress flag")
    func failedTranscodeClearsTheFlag() async {
        let transcoder = StubVideoTranscoder()
        transcoder.error = MockGameBackend.StubbedError()
        let vm = viewModel(MockGameBackend(), transcoder)

        await vm.prepareVideo(source: TranscodeTestFiles.file(bytes: 4_000))

        #expect(!vm.isTranscoding)
    }

    @Test("reported progress reaches the published fraction")
    func progressIsPublished() async {
        let transcoder = StubVideoTranscoder()
        transcoder.outputBytes = 1_000
        transcoder.progressToReport = [0.25, 0.75]
        let vm = viewModel(MockGameBackend(), transcoder)

        await vm.prepareVideo(source: TranscodeTestFiles.file(bytes: 4_000))
        for _ in 0..<8 { await Task.yield() }

        #expect(vm.transcodeProgress == 0.75)
    }

    @Test("a cancelled preparation leaves the selection alone and cleans up both files")
    func cancelledPreparationTouchesNothing() async {
        let transcoder = StubVideoTranscoder()
        transcoder.outputBytes = 1_000
        transcoder.holdUntilReleased = true
        let vm = viewModel(MockGameBackend(), transcoder)
        let kept = TranscodeTestFiles.file(bytes: 100)
        vm.acceptVideo(url: kept, sizeBytes: 100)

        let source = TranscodeTestFiles.file(bytes: 4_000)
        let preparation = Task { await vm.prepareVideo(source: source) }
        for _ in 0..<4 { await Task.yield() }
        preparation.cancel()
        transcoder.release()
        await preparation.value

        #expect(vm.selectedVideoURL == kept, "the pick that replaced this one owns the state")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(!vm.isTranscoding)
    }
}

@MainActor
@Suite("Video and audio upload by streaming off disk")
struct StreamingUploadTests {

    /// `probe` is built inside rather than defaulted in the signature: a default argument is
    /// evaluated in a nonisolated context, and `MockRewardMediaProbe.init` is main-actor bound.
    private func loaded(
        _ mock: MockGameBackend, probe: MockRewardMediaProbe? = nil
    ) async -> GiftAuthoringViewModel {
        let vm = GiftAuthoringViewModel(
            eventId: "evt_1", service: mock, mediaProbe: probe ?? MockRewardMediaProbe()
        )
        vm.loadExisting(userId: "u1", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        return vm
    }

    @Test("a new video gift uploads from the file, never from an in-memory copy")
    func videoUploadsFromFile() async {
        let mock = MockGameBackend()
        let vm = await loaded(mock)
        vm.contentMode = .video
        vm.title = "A video"
        let url = TranscodeTestFiles.file(bytes: 4_000, ext: "mp4")
        vm.selectedVideoURL = url

        await vm.save()

        #expect(
            mock.uploadedRewardMediaFileURLs == [url],
            "Data(contentsOf:) is what made the ceiling free memory instead of the rules' cap"
        )
        #expect(mock.uploadedRewardMedia.first?.contentType == "video/mp4")
    }

    @Test("a new voice gift uploads from the file too")
    func audioUploadsFromFile() async {
        let mock = MockGameBackend()
        let vm = await loaded(mock)
        vm.contentMode = .voice
        vm.title = "A voice note"
        let url = TranscodeTestFiles.file(bytes: 4_000, ext: "m4a")
        vm.selectedAudioURL = url

        await vm.save()

        #expect(mock.uploadedRewardMediaFileURLs == [url])
        #expect(mock.uploadedRewardMedia.first?.contentType == "audio/mp4")
    }

    @Test("photos still upload in memory — they are compressed from a UIImage, not read off disk")
    func photosStayOnTheDataPath() async {
        let mock = MockGameBackend()
        let vm = await loaded(mock)
        vm.contentMode = .photos
        vm.title = "Some photos"
        vm.photoPreviews = [UIImage(systemName: "star.fill") ?? UIImage()]

        await vm.save()

        #expect(mock.callCount("uploadRewardMedia") == 1)
        #expect(mock.uploadedRewardMediaFileURLs.isEmpty)
    }

    @Test("a re-sent video streams off disk as well")
    func resendStreamsFromFile() async {
        let path = "events/evt_1/rewards/old/clip.mov"
        let mock = MockGameBackend()
        mock.rewards = [
            .fixture(id: "r_mine", contentType: .video, contentUrl: path, isUnlocked: true)
        ]
        let occasionDate = Date(timeIntervalSince1970: 1_700_000_000)
        let vm = await loaded(mock, probe: MockRewardMediaProbe(missingPaths: [path]))
        await vm.checkMediaExpiry(
            occasionDate: occasionDate,
            now: MediaLifecycle.expiry(occasionDate: occasionDate).addingTimeInterval(60)
        )
        #expect(vm.isResendOnly)
        let url = TranscodeTestFiles.file(bytes: 4_000, ext: "mp4")
        vm.selectedVideoURL = url

        await vm.save()

        #expect(mock.uploadedRewardMediaFileURLs == [url])
    }
}

@MainActor
@Suite("A save taken while a pick is still being prepared")
struct SaveDuringVideoPreparationTests {

    /// An editable video gift already on the server, the case where this bites hardest: `isValid`
    /// is satisfied by the *existing* `contentUrl`, so nothing else stops a mid-preparation save
    /// from writing `title`/`teaser` alone and reporting success.
    private func loadedVideoGift(
        _ mock: MockGameBackend, _ transcoder: StubVideoTranscoder
    ) async -> GiftAuthoringViewModel {
        mock.rewards = [
            .fixture(id: "r_mine", contentType: .video,
                     contentUrl: "events/evt_1/rewards/r_mine/old.mov")
        ]
        let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock, transcoder: transcoder)
        vm.loadExisting(userId: "u1", name: "Jordan")
        for _ in 0..<8 { await Task.yield() }
        return vm
    }

    /// Both halves matter, and a test asserting only the first would pass just as happily against
    /// a `save()` that never saves anything at all.
    @Test("is refused mid-transcode, and writes the new clip once it lands")
    func saveMidTranscodeDropsNothing() async {
        let mock = MockGameBackend()
        let transcoder = StubVideoTranscoder()
        transcoder.outputBytes = 8 * 1024 * 1024
        transcoder.holdUntilReleased = true
        let vm = await loadedVideoGift(mock, transcoder)

        let source = TranscodeTestFiles.file(bytes: 600 * 1024 * 1024)
        let preparation = Task { await vm.prepareVideo(source: source) }
        var spins = 0
        while !vm.isTranscoding && spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        #expect(vm.isTranscoding, "the stub should be parked mid-export")

        // Half 1: the save a contributor takes while the progress row is on screen.
        await vm.save()

        #expect(mock.updatedRewards.isEmpty, "a mid-transcode save must not write the old clip")
        #expect(mock.uploadedRewardMediaFileURLs.isEmpty, "and must not upload a stale selection")

        // Half 2: the same save, once the clip the contributor picked actually exists.
        transcoder.release()
        await preparation.value
        #expect(!vm.isTranscoding)

        await vm.save()

        #expect(mock.uploadedRewardMediaFileURLs.count == 1, "the new clip is what gets uploaded")
        #expect(mock.updatedRewards.count == 1)
        #expect(mock.updatedRewards.last?.fields["contentUrl"] != nil,
                "and its path is written to the gift")
    }
}
