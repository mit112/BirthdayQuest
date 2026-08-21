import SwiftUI

struct CreateOccasionView: View {

    @StateObject private var viewModel = CreateOccasionViewModel()
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    /// Called with the new event id once the occasion exists and the list has been
    /// refreshed. The caller decides what to open: this sheet is presented from the
    /// occasion list, outside any `EventSession`, so it cannot present in-occasion screens
    /// itself. Sharing the invite link lives inside the occasion, one tap later.
    var onCreated: ((String) -> Void)?

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
                        Text(errorMessage).foregroundStyle(BQDesign.Colors.error)
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
                            await session.refreshOccasions()
                            dismiss()
                            onCreated?(eventId)
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
