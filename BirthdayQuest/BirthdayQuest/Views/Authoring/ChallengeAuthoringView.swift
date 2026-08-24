import SwiftUI

/// The host's challenge list.
///
/// Pushed from `AdminControlsView`, which owns the `NavigationStack` — this view must not
/// add another, or the pushed screen gets a second nav bar.
struct ChallengeAuthoringView: View {

    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: ChallengeAuthoringViewModel

    @ScaledMetric private var rowGlyphSize: CGFloat = 18

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: ChallengeAuthoringViewModel(eventId: eventId))
    }

    var body: some View {
        Group {
            switch viewModel.contentState {
            case .loading:
                ProgressView()
                    .tint(BQDesign.Colors.primaryPurple)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentFailureView(message: message)
            case .empty:
                emptyState
            case .ready:
                list
            }
        }
        .background(BQDesign.Colors.background.ignoresSafeArea())
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.beginCreating()
                } label: {
                    Label("New challenge", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isEditorPresented) {
            ChallengeEditorView(
                viewModel: viewModel,
                authorUid: event.participant?.id ?? ""
            )
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { viewModel.challengeToDelete != nil },
                set: { if !$0 { viewModel.challengeToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let challenge = viewModel.challengeToDelete {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(challenge) }
                }
                Button("Keep it", role: .cancel) { viewModel.challengeToDelete = nil }
            }
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            viewModel.actionResult?.isError == true ? "Couldn't do that" : "Done",
            isPresented: Binding(
                get: { viewModel.actionResult != nil },
                set: { if !$0 { viewModel.actionResult = nil } }
            )
        ) {
            Button("OK") { viewModel.actionResult = nil }
        } message: {
            Text(viewModel.actionResult?.message ?? "")
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .onChange(of: event.gameState.totalChallenges) { _, _ in
            Task { await viewModel.reconcileCounter(storedTotal: event.gameState.totalChallenges) }
        }
        .onChange(of: viewModel.challenges.count) { _, _ in
            Task { await viewModel.reconcileCounter(storedTotal: event.gameState.totalChallenges) }
        }
    }

    /// Names the specific challenge rather than asking "Are you sure?", so the host can act
    /// without rereading the row behind the dialog.
    private var deleteTitle: String {
        if let title = viewModel.challengeToDelete?.title {
            return "Delete \"\(title)\"?"
        }
        return "Delete this challenge?"
    }

    /// The first thing a host sees in a brand-new occasion, so it carries the instruction
    /// rather than decorating the absence of one.
    private var emptyState: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Text("No challenges yet")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("""
                Challenges are how \(event.celebrantName) earns points. Add a few, and keep \
                the total just short of what the gifts cost — the secret dares close the gap.
                """)
                .font(BQDesign.Typography.body)
                .foregroundStyle(BQDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button("Create your first challenge") {
                viewModel.beginCreating()
            }
            .font(BQDesign.Typography.bodyBold)
            .buttonStyle(.borderedProminent)
            .tint(BQDesign.Colors.primaryPurple)
        }
        .padding(BQDesign.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(viewModel.visibleChallenges) { challenge in
                Button {
                    viewModel.beginEditing(challenge)
                } label: {
                    row(challenge)
                }
                .buttonStyle(.plain)
                .listRowBackground(BQDesign.Colors.cardBackground)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.challengeToDelete = challenge
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// The title deliberately has no `lineLimit`: truncating it with no way to see the rest
    /// would hide the one thing that distinguishes one row from another, and this list has
    /// no detail view that would recover it — tapping opens the editor, not a reader.
    private func row(_ challenge: Challenge) -> some View {
        HStack(spacing: BQDesign.Spacing.md) {
            Image(systemName: ChallengeSymbolCatalog.resolved(challenge.illustrationAsset))
                .font(.system(size: rowGlyphSize))
                .foregroundStyle(BQDesign.Colors.primaryPurple)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text(challenge.title)
                    .font(BQDesign.Typography.cardTitle)
                    .foregroundStyle(BQDesign.Colors.textPrimary)

                Text("\(challenge.pointValue) points · \(challenge.difficulty.rawValue)")
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, BQDesign.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the challenge editor")
    }
}
