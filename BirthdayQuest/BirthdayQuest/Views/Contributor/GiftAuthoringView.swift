import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// The contributor's gift to the celebrant: a letter they unlock with points.
///
/// Light-surfaced on purpose. Its sibling tab, the secret dare, is a deliberately dark
/// "dossier"; a warm letter does not belong on that surface, and `textSecondary` measures
/// 3.18:1 there.
struct GiftAuthoringView: View {

    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: GiftAuthoringViewModel
    @State private var isImportingAudio = false
    // @StateObject, not @State: AudioPlayerController is an ObservableObject, so the play/pause
    // icon must observe its @Published isPlaying.
    @StateObject private var reviewPlayer = AudioPlayerController()
    @ScaledMetric private var reviewPlayerIconSize: CGFloat = 28
    @StateObject private var recorder = AudioRecorderController()
    @State private var recordingDotOn = false
    @Environment(\.bqMotionLevel) private var motionLevel

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: GiftAuthoringViewModel(eventId: eventId))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.contentState {
                case .loading:
                    ProgressView().tint(BQDesign.Colors.primaryPurple)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentFailureView(message: message)
                case .empty, .ready:
                    form
                }
            }
            .background(BQDesign.Colors.background.ignoresSafeArea())
            .navigationTitle("Your gift")
            .alert("Couldn't save", isPresented: $viewModel.showError) {
                Button("OK") { viewModel.showError = false }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear {
            viewModel.loadExisting(
                userId: event.participant?.id,
                name: event.participant?.name ?? "A friend"
            )
            recorder.onFinish = { url in
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                viewModel.acceptAudio(url: url, sizeBytes: size)
            }
        }
        .onDisappear {
            viewModel.stopListening()
            recorder.cancel()
        }
    }

    private var form: some View {
        Form {
            Section {
                Text(viewModel.statusText)
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }

            if !viewModel.hasExisting {
                Section {
                    Picker("Gift type", selection: $viewModel.contentMode) {
                        Text("Letter").tag(GiftAuthoringViewModel.GiftContentMode.letter)
                        Text("Photos").tag(GiftAuthoringViewModel.GiftContentMode.photos)
                        Text("Video").tag(GiftAuthoringViewModel.GiftContentMode.video)
                        Text("Voice").tag(GiftAuthoringViewModel.GiftContentMode.voice)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Gift type")
                }
            }

            switch viewModel.contentMode {
            case .letter:
                letterSection
            case .photos:
                photosSection
            case .video:
                videoSection
            case .voice:
                voiceSection
            }

            Section {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(saveLabel).font(BQDesign.Typography.bodyBold)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(BQDesign.Colors.primaryPurple)
                .disabled(!viewModel.isEditable)
            } footer: {
                Text(
                    viewModel.isEditable
                    ? "Your host sets what it costs to unlock."
                    : "\(event.celebrantName) has opened this, so it can't be changed now."
                )
                .font(BQDesign.Typography.captionSmall)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var letterSection: some View {
        Section("Your letter") {
            labelled("Title", hint: "What \(event.celebrantName) sees before unlocking") {
                TextField("", text: $viewModel.title, prompt: Text("A letter from me"))
                    .accessibilityLabel("Title")
            }
            if viewModel.showValidation
                && viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fieldError("Give your gift a title.")
            }

            labelled("Teaser", hint: "One line, shown while it's still locked") {
                TextField("", text: $viewModel.teaser, prompt: Text("Open this one last"))
                    .accessibilityLabel("Teaser")
            }

            labelled("The letter itself", hint: nil) {
                TextField(
                    "", text: $viewModel.letter,
                    prompt: Text("Say the thing you'd say in person"), axis: .vertical
                )
                .lineLimit(6...20)
                .accessibilityLabel("The letter itself")
            }
            if viewModel.showValidation
                && viewModel.letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fieldError("Write something for them to read.")
            }
        }
        .disabled(!viewModel.isEditable)
    }

    private var photosSection: some View {
        Section("Your photos") {
            labelled("Title", hint: "What \(event.celebrantName) sees before unlocking") {
                TextField("", text: $viewModel.title, prompt: Text("Photos from me"))
                    .accessibilityLabel("Title")
            }
            if viewModel.showValidation
                && viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fieldError("Give your gift a title.")
            }

            labelled("Teaser", hint: "One line, shown while it's still locked") {
                TextField("", text: $viewModel.teaser, prompt: Text("Open this one last"))
                    .accessibilityLabel("Teaser")
            }

            PhotosPicker(
                selection: $viewModel.selectedPhotos,
                maxSelectionCount: GiftAuthoringViewModel.maxPhotoCount,
                matching: .images
            ) {
                HStack(spacing: BQDesign.Spacing.sm) {
                    Image(systemName: "photo.badge.plus")
                    Text("Add photos").font(BQDesign.Typography.bodyBold)
                }
                .foregroundStyle(BQDesign.Colors.primaryPurple)
            }
            .accessibilityLabel("Add photos")

            if !viewModel.photoPreviews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BQDesign.Spacing.sm) {
                        ForEach(Array(viewModel.photoPreviews.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous))
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityLabel("\(viewModel.photoPreviews.count) photos selected")
            } else if let existing = viewModel.existingGiftHasPhotos {
                Text(existing)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }

            if viewModel.showValidation
                && viewModel.photoPreviews.isEmpty
                && (viewModel.existingGiftHasPhotos == nil) {
                fieldError("Add at least one photo.")
            }
        }
        .disabled(!viewModel.isEditable)
    }

    private var videoSection: some View {
        Section("Your video") {
            labelled("Title", hint: "What \(event.celebrantName) sees before unlocking") {
                TextField("", text: $viewModel.title, prompt: Text("A video from me"))
                    .accessibilityLabel("Title")
            }
            if viewModel.showValidation
                && viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fieldError("Give your gift a title.")
            }

            labelled("Teaser", hint: "One line, shown while it's still locked") {
                TextField("", text: $viewModel.teaser, prompt: Text("Open this one last"))
                    .accessibilityLabel("Teaser")
            }

            PhotosPicker(selection: $viewModel.selectedVideoItem, matching: .videos) {
                HStack(spacing: BQDesign.Spacing.sm) {
                    Image(systemName: "video.badge.plus")
                    Text(viewModel.selectedVideoURL == nil ? "Add a video" : "Choose a different video")
                        .font(BQDesign.Typography.bodyBold)
                }
                .foregroundStyle(BQDesign.Colors.primaryPurple)
            }
            .accessibilityLabel("Add a video")

            if viewModel.selectedVideoURL != nil {
                HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BQDesign.Colors.success)
                        .accessibilityHidden(true)
                    Text("Video selected")
                        .font(BQDesign.Typography.captionSmall)
                        .foregroundStyle(BQDesign.Colors.textPrimary)
                }
                .accessibilityElement(children: .combine)
            } else if let existing = viewModel.existingGiftHasVideo {
                Text(existing)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }

            if viewModel.videoTooLarge {
                fieldError("That video is over 200 MB. Please pick a shorter one.")
            }

            if viewModel.showValidation
                && viewModel.selectedVideoURL == nil
                && (viewModel.existingGiftHasVideo == nil) {
                fieldError("Add a video.")
            }
        }
        .disabled(!viewModel.isEditable)
    }

    private var voiceSection: some View {
        Section("Your voice gift") {
            labelled("Title", hint: "What \(event.celebrantName) sees before unlocking") {
                TextField("", text: $viewModel.title, prompt: Text("A voice note from me"))
                    .accessibilityLabel("Title")
            }
            if viewModel.showValidation
                && viewModel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fieldError("Give your gift a title.")
            }

            labelled("Teaser", hint: "One line, shown while it's still locked") {
                TextField("", text: $viewModel.teaser, prompt: Text("Open this one last"))
                    .accessibilityLabel("Teaser")
            }

            if recorder.isRecording {
                recordingRow
            } else {
                Button {
                    BQDesign.Haptics.light()
                    recorder.start()
                } label: {
                    HStack(spacing: BQDesign.Spacing.sm) {
                        Image(systemName: "mic.circle.fill")
                        Text(viewModel.selectedAudioURL == nil ? "Record a voice gift" : "Re-record")
                            .font(BQDesign.Typography.bodyBold)
                    }
                    .foregroundStyle(BQDesign.Colors.primaryPurple)
                }
                .accessibilityLabel("Record a voice gift")
            }

            if recorder.permissionDenied {
                permissionDeniedRow
            }

            // Import path.
            Button {
                isImportingAudio = true
            } label: {
                HStack(spacing: BQDesign.Spacing.sm) {
                    Image(systemName: "waveform.badge.plus")
                    Text(viewModel.selectedAudioURL == nil ? "Choose an audio file" : "Choose a different file")
                        .font(BQDesign.Typography.bodyBold)
                }
                .foregroundStyle(BQDesign.Colors.primaryPurple)
            }
            .accessibilityLabel("Choose an audio file")
            .fileImporter(
                isPresented: $isImportingAudio,
                allowedContentTypes: [.mpeg4Audio, .mp3],
                allowsMultipleSelection: false
            ) { result in
                handleAudioImport(result)
            }

            if let url = viewModel.selectedAudioURL {
                audioReviewRow(url: url)
            } else if let existing = viewModel.existingGiftHasAudio {
                Text(existing)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }

            if viewModel.audioTooLarge {
                fieldError("That audio file is over 200 MB. Please choose a smaller one.")
            }

            if viewModel.showValidation
                && viewModel.selectedAudioURL == nil
                && (viewModel.existingGiftHasAudio == nil) {
                fieldError("Record or choose a voice gift.")
            }
        }
        .disabled(!viewModel.isEditable)
    }

    private var recordingRow: some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Circle()
                .fill(BQDesign.Colors.error)
                .frame(width: 12, height: 12)
                .opacity(recordingDotOn ? 1 : 0.3)
                .animation(
                    motionLevel.allowsPerpetual
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : nil,
                    value: recordingDotOn
                )
                .accessibilityHidden(true)
            Text(recorderTimeString)
                .font(BQDesign.Typography.body.monospacedDigit())
                .foregroundStyle(BQDesign.Colors.textPrimary)
            Spacer()
            Button("Stop") {
                BQDesign.Haptics.light()
                recorder.stop()
            }
            .font(BQDesign.Typography.bodyBold)
            .foregroundStyle(BQDesign.Colors.primaryPurple)
        }
        .onAppear { recordingDotOn = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording, \(recorderTimeString). Double-tap Stop to finish.")
    }

    private var permissionDeniedRow: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
            Text("Microphone access is off. Turn it on in Settings to record a voice gift.")
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textPrimary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(BQDesign.Typography.captionSmall)
            .foregroundStyle(BQDesign.Colors.primaryPurple)
        }
    }

    private var recorderTimeString: String {
        let seconds = Int(recorder.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// A review row for the selected/recorded clip: play it back before saving. Reuses the
    /// celebrant-side `AudioPlayerController` pointed at the local temp file.
    private func audioReviewRow(url: URL) -> some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Button {
                BQDesign.Haptics.light()
                reviewPlayer.togglePlayback()
            } label: {
                Image(systemName: reviewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: reviewPlayerIconSize))
                    .foregroundStyle(BQDesign.Colors.primaryPurple)
            }
            .accessibilityLabel(reviewPlayer.isPlaying ? "Pause review" : "Play review")

            Text("Voice gift ready")
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textPrimary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .onAppear { reviewPlayer.loadAudio(from: url) }
        .onChange(of: url) { _, newURL in reviewPlayer.loadAudio(from: newURL) }
        .onDisappear { reviewPlayer.pause() }
    }

    /// Copies the imported file into our temp dir (the picked URL is security-scoped and only
    /// valid inside the access block), reads its size, and hands it to the view model.
    private func handleAudioImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let picked = urls.first else { return }
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(picked.pathExtension)
        do {
            try FileManager.default.copyItem(at: picked, to: copy)
            let size = (try? FileManager.default.attributesOfItem(atPath: copy.path))?[.size] as? Int ?? 0
            viewModel.acceptAudio(url: copy, sizeBytes: size)
        } catch {
            // A failed copy leaves selection unchanged; the validation error already covers "nothing selected".
        }
    }

    private var saveLabel: String {
        if viewModel.saveSuccess { return "Saved" }
        return viewModel.hasExisting ? "Update gift" : "Save gift"
    }

    private func labelled<Content: View>(
        _ label: String, hint: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
            Text(label)
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textSecondary)
            content()
                .font(BQDesign.Typography.body)
            if let hint {
                Text(hint)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }
        }
    }

    private func fieldError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(BQDesign.Colors.error)
                .accessibilityHidden(true)
            Text(message)
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
