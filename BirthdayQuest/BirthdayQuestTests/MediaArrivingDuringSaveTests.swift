import Testing
import Foundation
import UIKit
@testable import BirthdayQuest

@MainActor
private func tempFile(ext: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
    FileManager.default.createFile(atPath: url.path, contents: Data([0x00, 0x01]))
    return url
}

@MainActor
private func newGift(_ mock: MockGameBackend) async -> GiftAuthoringViewModel {
    let vm = GiftAuthoringViewModel(eventId: "evt_1", service: mock)
    vm.loadExisting(userId: "u1", name: "Jordan")
    for _ in 0..<8 { await Task.yield() }
    return vm
}

/// Video, voice and re-send upload with `putFileAsync`, so the selected file is streamed off disk
/// for the whole transfer. `acceptVideo`/`acceptAudio` unlink the selection they supersede — which
/// is correct right up until the file they unlink is the one being streamed.
///
/// The view freezes its content sections on `isSaving`, but that blocks a *tap*, and the arrival
/// that matters here is not a tap: `AudioRecorderController`'s 5-minute auto-stop is a `Timer`
/// that calls `stop()` → `onFinish` → `acceptAudio` on its own, and disabling the section it lives
/// in does not cancel a recording already running.
@MainActor
@Suite("Media arriving during a save")
struct MediaArrivingDuringSaveTests {

    /// Both halves matter. A test asserting only the refusal would pass just as happily against an
    /// `acceptAudio` that had been gutted to do nothing at all — and the file-on-disk assertion is
    /// the one that actually discriminates, because the un-guarded version leaves
    /// `selectedAudioURL` pointing at a path it has already deleted.
    @Test("a recording that lands mid-save is discarded, and accepted normally afterwards")
    func audioArrivingMidSaveSparesTheStreamingFile() async {
        let vm = await newGift(MockGameBackend())
        vm.contentMode = .voice

        let streaming = tempFile(ext: "m4a")
        vm.acceptAudio(url: streaming, sizeBytes: 1024)
        #expect(vm.selectedAudioURL == streaming)

        // The upload is now in flight, streaming `streaming` off disk.
        vm.isSaving = true
        let fromTheTimer = tempFile(ext: "m4a")
        vm.acceptAudio(url: fromTheTimer, sizeBytes: 1024)

        #expect(vm.selectedAudioURL == streaming, "the selection must not move mid-upload")
        #expect(FileManager.default.fileExists(atPath: streaming.path),
                "and the file being streamed must still be on disk")
        #expect(!FileManager.default.fileExists(atPath: fromTheTimer.path),
                "the arrival is discarded rather than leaked into the temp directory")

        // Half 2: the guard is scoped to the upload, not a permanent refusal.
        vm.isSaving = false
        let picked = tempFile(ext: "m4a")
        vm.acceptAudio(url: picked, sizeBytes: 1024)

        #expect(vm.selectedAudioURL == picked, "a pick after the save lands is accepted")
        #expect(!FileManager.default.fileExists(atPath: streaming.path),
                "and now supersedes — and unlinks — the previous selection")
    }

    @Test("a video that lands mid-save is discarded, and accepted normally afterwards")
    func videoArrivingMidSaveSparesTheStreamingFile() async {
        let vm = await newGift(MockGameBackend())
        vm.contentMode = .video

        let streaming = tempFile(ext: "mov")
        vm.acceptVideo(url: streaming, sizeBytes: 1024)
        #expect(vm.selectedVideoURL == streaming)

        vm.isSaving = true
        let arriving = tempFile(ext: "mov")
        vm.acceptVideo(url: arriving, sizeBytes: 1024)

        #expect(vm.selectedVideoURL == streaming)
        #expect(FileManager.default.fileExists(atPath: streaming.path))
        #expect(!FileManager.default.fileExists(atPath: arriving.path))

        vm.isSaving = false
        let picked = tempFile(ext: "mov")
        vm.acceptVideo(url: picked, sizeBytes: 1024)
        #expect(vm.selectedVideoURL == picked)
    }

    /// The oversized branch unlinks the previous selection too, so it needs the same guard: a
    /// 300 MB import landing mid-upload must not take the clip being streamed down with it.
    @Test("an oversized arrival mid-save leaves the streaming file and its selection alone")
    func oversizedArrivalMidSaveSparesTheStreamingFile() async {
        let vm = await newGift(MockGameBackend())
        vm.contentMode = .voice

        let streaming = tempFile(ext: "m4a")
        vm.acceptAudio(url: streaming, sizeBytes: 1024)

        vm.isSaving = true
        vm.acceptAudio(url: tempFile(ext: "m4a"), sizeBytes: GiftAuthoringViewModel.maxAudioBytes + 1)

        #expect(vm.selectedAudioURL == streaming)
        #expect(FileManager.default.fileExists(atPath: streaming.path))
        #expect(!vm.audioTooLarge,
                "and the rejection banner does not fire for a file that was never considered")
    }
}
