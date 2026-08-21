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
                if viewModel.eventId.isEmpty {
                    codeEntrySection
                } else {
                    detailsSection
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(BQDesign.Colors.error)
                    }
                }
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

    /// Shown when there is no event id yet: either nothing has been entered, or the code
    /// has not resolved. `incomingLink` prefills this via `.task` above, so a link that
    /// resolves cleanly skips straight to `detailsSection` (R14).
    private var codeEntrySection: some View {
        Section("Invite code") {
            Text("Ask your host for their invite link, or type the code they shared.")
                .foregroundStyle(BQDesign.Colors.textSecondary)
            TextField("e.g. ABCD2345", text: $viewModel.code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Continue") {
                Task { await viewModel.resolveCode() }
            }
            .disabled(viewModel.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || viewModel.isResolvingCode)
            if viewModel.isResolvingCode {
                ProgressView()
            }
        }
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
