import SwiftUI
import PhotosUI

/// The contributor's gift to the celebrant: a letter they unlock with points.
///
/// Light-surfaced on purpose. Its sibling tab, the secret dare, is a deliberately dark
/// "dossier"; a warm letter does not belong on that surface, and `textSecondary` measures
/// 3.18:1 there.
struct GiftAuthoringView: View {

    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: GiftAuthoringViewModel

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
        }
        .onDisappear { viewModel.stopListening() }
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
