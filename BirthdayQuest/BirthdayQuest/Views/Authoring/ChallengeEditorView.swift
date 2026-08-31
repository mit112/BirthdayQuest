import SwiftUI

/// Create or edit one challenge.
///
/// Save is never disabled. An invalid draft reveals its field errors on the first press and
/// writes nothing; a greyed-out button with no explanation is indistinguishable from a
/// broken one, and assistive technology routinely skips disabled controls entirely.
struct ChallengeEditorView: View {

    @ObservedObject var viewModel: ChallengeAuthoringViewModel
    let authorUid: String

    @Environment(\.dismiss) private var dismiss

    private var titleIsMissing: Bool {
        viewModel.showValidation
            && viewModel.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var descriptionIsMissing: Bool {
        viewModel.showValidation
            && viewModel.draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                scoringSection
                symbolSection
                optionBSection
            }
            .navigationTitle(viewModel.isEditing ? "Edit challenge" : "New challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.save(authorUid: authorUid) }
                    }
                    .font(BQDesign.Typography.bodyBold)
                }
            }
            .overlay {
                if viewModel.isPerformingAction {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .overlay(ProgressView().tint(BQDesign.Colors.primaryPurple))
                }
            }
        }
    }

    private var basicsSection: some View {
        Section("Basics") {
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text("Title")
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                TextField("", text: $viewModel.draft.title, prompt: Text("Sing in public"))
                    .font(BQDesign.Typography.body)
                    .accessibilityLabel("Title")
                if titleIsMissing {
                    fieldError("Give the challenge a title.")
                }
            }

            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text("What they have to do")
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                TextField(
                    "", text: $viewModel.draft.description,
                    prompt: Text("Somewhere busy, and get it on camera"),
                    axis: .vertical
                )
                .font(BQDesign.Typography.body)
                .lineLimit(3...8)
                .accessibilityLabel("What they have to do")
                if descriptionIsMissing {
                    fieldError("Say what they have to do.")
                }
            }
        }
    }

    private var scoringSection: some View {
        Section("Scoring") {
            Stepper(value: $viewModel.draft.pointValue, in: 5...500, step: 5) {
                HStack {
                    Text("Points").font(BQDesign.Typography.body)
                    Spacer()
                    Text("\(viewModel.draft.pointValue)")
                        .font(BQDesign.Typography.bodyBold)
                        .foregroundStyle(BQDesign.Colors.goldText)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Points")
            .accessibilityValue("\(viewModel.draft.pointValue)")

            Picker("Difficulty", selection: $viewModel.draft.difficulty) {
                ForEach(ChallengeDifficulty.allCases, id: \.self) { level in
                    Text(level.rawValue.capitalized).tag(level)
                }
            }
            // .menu, not .segmented: three word-labels (Easy/Medium/Hard) truncate in a
            // segmented control at large Dynamic Type sizes on narrow devices; a menu picker
            // shows the current selection and never clips.
            .pickerStyle(.menu)

            Picker("Category", selection: $viewModel.draft.category) {
                ForEach(ChallengeCategory.allCases, id: \.self) { category in
                    Text(category.rawValue.capitalized).tag(category)
                }
            }
        }
    }

    private var symbolSection: some View {
        Section("Symbol") {
            SymbolPickerView(selection: $viewModel.draft.symbol)
                .padding(.vertical, BQDesign.Spacing.xs)
        }
    }

    private var optionBSection: some View {
        Section {
            Toggle("Offer a second option", isOn: $viewModel.draft.hasOptionB)

            if viewModel.draft.hasOptionB {
                TextField(
                    "", text: $viewModel.draft.optionBTitle,
                    prompt: Text("Second option title")
                )
                .accessibilityLabel("Second option title")

                TextField(
                    "", text: $viewModel.draft.optionBDescription,
                    prompt: Text("What the second option involves"), axis: .vertical
                )
                .lineLimit(2...5)
                .accessibilityLabel("Second option description")
            }
        } footer: {
            Text("A 2-in-1 challenge lets them pick either option. Off unless you turn it on.")
                .font(BQDesign.Typography.captionSmall)
        }
    }

    /// The colour sits on the icon; the sentence stays at `textPrimary`. `Colors.error` is
    /// 3.59:1 — large-text-and-UI only, never a body sentence.
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
