import SwiftUI

struct CreateOccasionView: View {

    @StateObject private var viewModel = CreateOccasionViewModel()
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("The occasion") {
                    TextField("Name it", text: $viewModel.name)
                    Picker("Type", selection: $viewModel.occasionType) {
                        ForEach(OccasionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    DatePicker(
                        "Date", selection: $viewModel.occasionDate, displayedComponents: .date
                    )
                }

                Section(viewModel.occasionType.celebrantLabel) {
                    TextField("Who is this for?", text: $viewModel.celebrantName)
                }

                Section("You") {
                    TextField("Your name", text: $viewModel.hostName)
                    AvatarPicker(selection: $viewModel.hostAvatarId)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        // Icon carries the severity in colour; the sentence stays at
                        // `textPrimary`. `Colors.error` is 3.83:1 on white — under the
                        // 4.5:1 floor for body text — and colour alone is not a signal.
                        HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(BQDesign.Colors.error)
                                .accessibilityHidden(true)
                            Text(errorMessage)
                                .foregroundStyle(BQDesign.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Error: \(errorMessage)")
                    }
                }
            }
            .navigationTitle("New occasion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            guard let eventId = await viewModel.create() else { return }
                            // Refresh, then dismiss, then ask for the open — in that order.
                            // The refresh is what moves an empty account to the occasion list
                            // root, and the request has to outlive that swap, so it is made
                            // on the session rather than handed back through this sheet.
                            // A new occasion is empty, so landing the host inside it is what
                            // puts the invite link in front of them.
                            await session.refreshOccasions()
                            dismiss()
                            session.pendingOpenEventId = eventId
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .overlay {
                if viewModel.isSubmitting { ProgressView() }
            }
        }
    }
}

/// Horizontal avatar strip. Shared by create and join — kept internal (not `private`) so
/// the join-occasion view can reuse it without duplicating this UI.
struct AvatarPicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BQDesign.Spacing.sm) {
                ForEach(AvatarCatalog.all, id: \.self) { id in
                    Button {
                        BQDesign.Haptics.light()
                        selection = id
                    } label: {
                        AvatarView(avatarId: id, size: 56)
                            .overlay(selectionRing(isSelected: selection == id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Avatar \(id)")
                    .accessibilityAddTraits(selection == id ? [.isSelected] : [])
                }
            }
            .padding(.vertical, BQDesign.Spacing.xs)
        }
    }

    /// Extracted from the `AvatarView` overlay above: inlining a ternary inside
    /// `strokeBorder` made SourceKit give up type-checking the whole expression.
    private func selectionRing(isSelected: Bool) -> some View {
        let color: Color = isSelected ? BQDesign.Colors.primaryPurple : .clear
        return Circle().strokeBorder(color, lineWidth: 3)
    }
}
