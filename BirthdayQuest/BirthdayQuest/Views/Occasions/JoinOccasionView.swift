import SwiftUI

struct JoinOccasionView: View {

    @StateObject private var viewModel = JoinOccasionViewModel()
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    /// Set when arriving from a deep link; nil when the user opened this manually.
    var incomingLink: URL?

    var body: some View {
        NavigationStack {
            Form {
                // `isResolved`, not `eventId.isEmpty`. A deep link fills in `eventId` before
                // anything is resolved, so keying off it showed the details form — and a
                // role of "A friend" — to a celebrant whose lookup had just failed.
                if viewModel.isResolved {
                    detailsSection
                } else {
                    codeEntrySection
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        formError(errorMessage)
                    }
                }

                TermsAgreementSection(act: "Joining an occasion")
            }
            .navigationTitle("Join an occasion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task {
                            if await viewModel.join() {
                                await session.refreshOccasions()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .overlay {
                if viewModel.isSubmitting { ProgressView() }
            }
            .task {
                guard let incomingLink, viewModel.parse(link: incomingLink) else { return }
                await viewModel.resolveCode()
            }
        }
    }

    /// Shown until a code has actually resolved. `incomingLink` prefills the field via
    /// `.task` above, so a link that resolves cleanly skips straight to `detailsSection`
    /// (R14) — and a link that *fails* to resolve lands here with the code already filled
    /// in, which is what turns the retry into a single tap rather than a dead end.
    private var codeEntrySection: some View {
        Section("Invite code") {
            Text("Ask your host for their invite link, or type the code they shared.")
                .foregroundStyle(BQDesign.Colors.textSecondary)
            TextField("e.g. ABCD2345", text: $viewModel.code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            if viewModel.isResolvingCode {
                HStack(spacing: BQDesign.Spacing.sm) {
                    ProgressView()
                    Text("Checking that code…")
                        .foregroundStyle(BQDesign.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button("Continue") {
                    Task { await viewModel.resolveCode() }
                }
                .disabled(viewModel.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    /// The icon carries the severity in colour so the sentence can stay readable:
    /// `Colors.error` measures 3.83:1 on white, under the 4.5:1 floor for body text, and
    /// colour must not be the only signal regardless. Same split as `OccasionListView`.
    private func formError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BQDesign.Colors.error)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    private var detailsSection: some View {
        Group {
            Section("You") {
                TextField("Your name", text: $viewModel.name)
                AvatarPicker(selection: $viewModel.avatarId)
            }
            Section("Your role") {
                Text(viewModel.mode == .celebrant ? "The guest of honour" : "A friend")
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }
        }
    }
}
