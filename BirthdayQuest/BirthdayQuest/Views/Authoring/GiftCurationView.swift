import SwiftUI

/// The host's gift list: price, order, remove. Not edit — the words belong to whoever wrote
/// them.
///
/// Pushed from `AdminControlsView`, which owns the `NavigationStack`.
struct GiftCurationView: View {

    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: GiftCurationViewModel
    @ScaledMetric private var badgeGlyphSize: CGFloat = 18

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: GiftCurationViewModel(eventId: eventId))
    }

    var body: some View {
        Group {
            switch viewModel.contentState {
            case .loading:
                ProgressView().tint(BQDesign.Colors.primaryPurple)
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
        .navigationTitle("Gifts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // EditButton is what turns .onMove's drag handles on. It also carries the
            // keyboard and Switch Control path into reordering, which a bespoke drag
            // gesture would not.
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { viewModel.giftToDelete != nil },
                set: { if !$0 { viewModel.giftToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let gift = viewModel.giftToDelete {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete(gift) }
                }
                Button("Keep it", role: .cancel) { viewModel.giftToDelete = nil }
            }
        } message: {
            Text("This can't be undone, and they'd have to write it again.")
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
        .onChange(of: event.gameState.totalRewards) { _, _ in
            Task { await viewModel.reconcileCounter(storedTotal: event.gameState.totalRewards) }
        }
        .onChange(of: viewModel.gifts.count) { _, _ in
            Task { await viewModel.reconcileCounter(storedTotal: event.gameState.totalRewards) }
        }
    }

    private var deleteTitle: String {
        if let gift = viewModel.giftToDelete {
            return "Delete \(gift.fromName)'s gift?"
        }
        return "Delete this gift?"
    }

    private func contentTypeLabel(_ contentType: RewardContentType) -> String {
        switch contentType {
        case .video: return "Video gift"
        case .audio: return "Voice gift"
        case .text: return "Letter gift"
        case .image: return "Photo gift"
        }
    }

    private var emptyState: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Text("No gifts yet")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("""
                Gifts come from your guests — each of them can write one. Share the \
                contributor link and they'll appear here for you to price.
                """)
                .font(BQDesign.Typography.body)
                .foregroundStyle(BQDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(BQDesign.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            Section {
                ForEach(viewModel.gifts) { gift in
                    row(gift)
                        .listRowBackground(BQDesign.Colors.cardBackground)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.giftToDelete = gift
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove { source, destination in
                    Task { await viewModel.move(from: source, to: destination) }
                }
            } footer: {
                Text("Everything costs \(viewModel.totalCost) points in total.")
                    .font(BQDesign.Typography.captionSmall)
                    .monospacedDigit()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ gift: Reward) -> some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
            HStack(spacing: BQDesign.Spacing.xs) {
                Image(systemName: gift.contentType.icon)
                    .font(.system(size: badgeGlyphSize))
                    .foregroundStyle(BQDesign.Colors.primaryPurple)
                    .accessibilityLabel(contentTypeLabel(gift.contentType))

                Text(gift.title)
                    .font(BQDesign.Typography.cardTitle)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
            }

            Text("from \(gift.fromName)")
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textSecondary)

            Stepper(
                value: Binding(
                    get: { gift.pointCost },
                    set: { newValue in Task { await viewModel.setPrice(newValue, for: gift) } }
                ),
                in: 0...2000,
                step: 10
            ) {
                HStack {
                    Text("Costs").font(BQDesign.Typography.caption)
                    Spacer()
                    Text("\(gift.pointCost)")
                        .font(BQDesign.Typography.bodyBold)
                        .foregroundStyle(BQDesign.Colors.goldText)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Cost of \(gift.fromName)'s gift")
            .accessibilityValue("\(gift.pointCost) points")
        }
        .padding(.vertical, BQDesign.Spacing.xs)
    }
}
