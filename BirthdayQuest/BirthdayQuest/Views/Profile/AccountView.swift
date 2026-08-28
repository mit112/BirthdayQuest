import SwiftUI

/// Account-scoped settings: the terms, and closing the account.
///
/// Deliberately NOT part of `ProfileView`, which is occasion-scoped — it takes an `eventId` and
/// reads `EventSession`. Neither thing here belongs to an occasion, and hanging them off that
/// screen would have hidden both from anyone with no occasions to open, which is exactly the
/// person most likely to want to delete their account. So this is reachable from the two roots
/// that own the account instead: `OccasionListView` and `EmptyOccasionsView`.
struct AccountView: View {

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = DeleteAccountViewModel()

    var body: some View {
        NavigationStack {
            List {
                legalSection
                deleteSection
                if let errorMessage = viewModel.errorMessage { errorRow(errorMessage) }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await viewModel.loadHostedOccasions() }
        .alert("Delete your account?", isPresented: $viewModel.isConfirming) {
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
        } message: {
            Text(confirmationMessage)
        }
        // Deleting the auth user leaves no signed-in identity, so there is nothing to return
        // to — `bootstrap()` mints a fresh anonymous uid and the root falls back to the empty
        // state, which is the honest end position: a new person on the same phone.
        .onChange(of: viewModel.didDelete) { _, didDelete in
            guard didDelete else { return }
            dismiss()
            Task { await session.bootstrap() }
        }
    }

    // MARK: - Sections

    private var legalSection: some View {
        Section {
            NavigationLink {
                TermsView()
            } label: {
                Label("Terms of Use", systemImage: "doc.text")
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            if viewModel.isDeleting {
                // Replaced rather than disabled, matching `appleLinkControl` and the empty
                // state's retry: a dead control explaining nothing is its own defect, and
                // removing it is also what makes a second tap impossible.
                HStack(spacing: BQDesign.Spacing.sm) {
                    ProgressView()
                    Text("Deleting your account…")
                        .font(BQDesign.Typography.caption)
                        .foregroundStyle(BQDesign.Colors.textPrimary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Deleting your account")
            } else {
                Button("Delete my account", role: .destructive) {
                    viewModel.requestDelete()
                }
            }
        } footer: {
            Text(deleteFooter)
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorRow(_ message: String) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.sm) {
                // Colour carries severity on the glyph only; `Colors.error` is under the 4.5:1
                // floor for body text, so the sentence itself stays at `textPrimary`.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.error)
                Text(message)
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(message)")
        }
    }

    // MARK: - Copy

    /// Says what survives as well as what goes. "Delete my account" reads as "delete everything
    /// I made", and here it deliberately does not — the gifts stay with the people they were
    /// made for, so leaving that unsaid would be the surprising half.
    private var deleteFooter: String {
        """
        This removes your name, your avatar, and your place in every occasion you joined. \
        Gifts and dares you made for other people stay with their occasions — ask that \
        occasion's host if you want yours taken down too.
        """
    }

    /// The hosted-occasion warning is folded into the confirmation rather than shown only in
    /// the footer, because it is the one consequence with no remedy afterwards: `hostUid` is
    /// immutable in the rules and host transfer is not a feature, so an occasion whose host
    /// deletes their account can never be administered again.
    private var confirmationMessage: String {
        let base = "This can't be undone."
        guard viewModel.hostsAnyOccasion else { return base }
        let names = viewModel.hostedOccasionNames.joined(separator: ", ")
        return """
        \(base) You host \(names). \
        Those occasions keep working for everyone in them, but nobody will be able to \
        administer them — host transfer isn't possible.
        """
    }
}

#Preview {
    AccountView()
        .environmentObject(AppSession())
}
