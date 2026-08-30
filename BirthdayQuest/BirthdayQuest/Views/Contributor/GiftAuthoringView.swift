import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import AVFoundation

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
    /// A poster frame for the picked clip, or nil while it is being generated or if generation
    /// failed. Purely confirmatory, so a failure falls back to the icon rather than an error.
    @State private var videoThumbnail: UIImage?
    /// Duration of the picked/recorded voice clip, formatted. A waveform is out of scope; the
    /// length is the one fact that distinguishes "I recorded the right take" from the wrong one.
    @State private var audioDurationText: String?
    // Dimensions, not text sizes: @ScaledMetric is what scales a glyph or a thumbnail with the
    // user's content size category (a fixed `Font.system(size:)` would not be overridable).
    @ScaledMetric private var mediaThumbnailSize: CGFloat = 56

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
        // Keyed on the loaded gift's id so it runs once the listener has actually delivered it,
        // rather than on the empty state `onAppear` sees. `occasionDate` is the expiry anchor
        // and lives on the session, the same way `RewardsView` feeds the celebrant's purge.
        .task(id: viewModel.existingGift?.id) {
            await viewModel.checkMediaExpiry(occasionDate: event.occasion?.occasionDate)
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
                    // .menu, not .segmented: four word-labels (Letter/Photos/Video/Voice) truncate
                    // in a segmented control at large Dynamic Type sizes on narrow devices. A menu
                    // picker shows the current selection and never clips. (Closes the documented
                    // gift-type-picker reflow gap.)
                    .pickerStyle(.menu)
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
                .disabled(!viewModel.canAttachMedia)
            } footer: {
                Text(saveFooter)
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
            expiredMediaBanner()

            // The text half stays governed by `isEditable`. The section-level modifier below
            // uses the wider `canAttachMedia`, and `.disabled` only ever accumulates going
            // down the tree, so this is what keeps the words frozen while the media unlocks.
            Group {
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
            }
            .disabled(!viewModel.isEditable)

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
        .disabled(!viewModel.canAttachMedia)
    }

    private var videoSection: some View {
        Section("Your video") {
            expiredMediaBanner()

            Group {
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
            }
            .disabled(!viewModel.isEditable)

            PhotosPicker(selection: $viewModel.selectedVideoItem, matching: .videos) {
                HStack(spacing: BQDesign.Spacing.sm) {
                    Image(systemName: "video.badge.plus")
                    Text(viewModel.selectedVideoURL == nil ? "Add a video" : "Choose a different video")
                        .font(BQDesign.Typography.bodyBold)
                }
                .foregroundStyle(BQDesign.Colors.primaryPurple)
            }
            .accessibilityLabel("Add a video")

            if viewModel.isTranscoding {
                transcodingRow
            }

            if let videoURL = viewModel.selectedVideoURL {
                HStack(spacing: BQDesign.Spacing.sm) {
                    if let videoThumbnail {
                        Image(uiImage: videoThumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: mediaThumbnailSize, height: mediaThumbnailSize)
                            .clipShape(
                                RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                            )
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BQDesign.Colors.success)
                            .accessibilityHidden(true)
                    }
                    Text("Video selected")
                        .font(BQDesign.Typography.captionSmall)
                        .foregroundStyle(BQDesign.Colors.textPrimary)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                // Keyed on the URL so re-picking regenerates; cleared first so the previous
                // clip's frame is never shown next to the new selection.
                .task(id: videoURL) {
                    videoThumbnail = nil
                    videoThumbnail = await Self.videoThumbnail(for: videoURL)
                }
            } else if let existing = viewModel.existingGiftHasVideo {
                Text(existing)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }

            if viewModel.videoTooLarge {
                // Reaching this now means the clip was already shrunk and still does not fit,
                // so "pick a shorter one" is the only remaining advice that is actually true.
                fieldError("Even shrunk, that video is over 200 MB. Please pick a shorter one.")
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
            expiredMediaBanner()

            Group {
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
            }
            .disabled(!viewModel.isEditable)

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
        .disabled(!viewModel.canAttachMedia)
    }

    /// The wait while a picked clip is re-encoded.
    ///
    /// Determinate, not a spinner: the export reports a real fraction, and a long 4K source is a
    /// wait of tens of seconds, where a bare spinner would say nothing about whether it is nearly
    /// done or barely started.
    ///
    /// It carries **no animation of its own**. The fill moves only when the export reports
    /// progress — the one thing motion is allowed to mean here — and a bespoke transition would
    /// re-derive the Reduce Motion decision that `MotionLevel` owns in one place.
    ///
    /// The copy names the quality trade rather than hiding it behind "Processing…": the file the
    /// celebrant receives is genuinely not the file that was picked.
    private var transcodingRow: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.sm) {
                Text("Shrinking your video so it can be sent")
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
                    // Wrap rather than truncate at the largest content sizes.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(transcodeProgressText)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                    .monospacedDigit()
            }
            ProgressView(value: viewModel.transcodeProgress, total: 1)
                .tint(BQDesign.Colors.primaryPurple)
        }
        // One VoiceOver stop, whose *value* is the percentage — so progress is announced as the
        // row updates instead of only when someone re-focuses it.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shrinking your video so it can be sent")
        .accessibilityValue(transcodeProgressText)
    }

    private var transcodeProgressText: String {
        "\(Int((viewModel.transcodeProgress * 100).rounded()))%"
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

            // A waveform is out of scope; the length is the fact that tells a contributor they
            // kept the right take. Monospaced digits so the row does not jitter as it loads.
            Text(audioDurationText.map { "Voice gift ready · \($0)" } ?? "Voice gift ready")
                .font(BQDesign.Typography.captionSmall.monospacedDigit())
                .foregroundStyle(BQDesign.Colors.textPrimary)
                // The middle dot is a visual separator; VoiceOver gets a sentence instead.
                .accessibilityLabel(
                    audioDurationText.map { "Voice gift ready, length \($0)" } ?? "Voice gift ready"
                )
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .onAppear { reviewPlayer.loadAudio(from: url) }
        .onChange(of: url) { _, newURL in reviewPlayer.loadAudio(from: newURL) }
        .task(id: url) {
            audioDurationText = nil
            audioDurationText = await Self.audioDuration(for: url)
        }
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
            if viewModel.audioTooLarge {
                try? FileManager.default.removeItem(at: copy)
            }
        } catch {
            // A failed copy leaves selection unchanged; the validation error already covers "nothing selected".
        }
    }

    private var saveLabel: String {
        if viewModel.saveSuccess { return "Saved" }
        if viewModel.isResendOnly { return "Send it again" }
        return viewModel.hasExisting ? "Update gift" : "Save gift"
    }

    /// Three states, not two. The middle one is the whole point of the re-send carve-out: the
    /// gift is still locked as far as its words go, and the footer has to say so rather than
    /// reading as a general unlock.
    private var saveFooter: String {
        if viewModel.isResendOnly {
            return """
                \(event.celebrantName) already opened this, so the words stay as they were — \
                only the missing file is replaced.
                """
        }
        if viewModel.isEditable { return "Your host sets what it costs to unlock." }
        return "\(event.celebrantName) has opened this, so it can't be changed now."
    }

    /// A one-line, honest explanation of why the media controls are live on an opened gift.
    /// Rendered inside the media sections so it sits with the control it unlocks.
    @ViewBuilder
    private func expiredMediaBanner() -> some View {
        if let message = viewModel.expiredMediaMessage {
            HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.xs) {
                Image(systemName: "clock.badge.exclamationmark")
                    // The icon carries the colour; the sentence stays on textPrimary. Colors.error
                    // measures 3.59:1 and is large-text-only — same split the field errors use.
                    .foregroundStyle(BQDesign.Colors.error)
                    .accessibilityHidden(true)
                Text(message)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// A poster frame for a picked clip.
    ///
    /// `nonisolated` and `static`: the decode must not run on the main actor, and a
    /// MainActor-isolated instance method would carry the isolation with it (the target builds
    /// with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
    ///
    /// Returns nil rather than surfacing an error. A generator legitimately fails on files that
    /// play perfectly well — no video track, protected content, an unusual container — and a
    /// confirmation thumbnail is not worth blocking a save over.
    nonisolated private static func videoThumbnail(for url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        // Not .zero: some encodes have no displayable frame exactly at zero, and the tolerances
        // let the generator settle for the nearest keyframe rather than failing.
        guard let image = try? await generator.image(
            at: CMTime(seconds: 0.1, preferredTimescale: 600)
        ).image else { return nil }
        return UIImage(cgImage: image)
    }

    /// The picked voice clip's length, `m:ss`, or nil if it cannot be read.
    nonisolated private static func audioDuration(for url: URL) async -> String? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
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
