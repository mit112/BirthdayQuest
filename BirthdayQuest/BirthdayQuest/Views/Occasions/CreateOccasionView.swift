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
                            if await viewModel.create() != nil {
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
                            .overlay(
                                Circle().strokeBorder(
                                    selection == id
                                        ? BQDesign.Colors.primaryPurple : .clear,
                                    lineWidth: 3
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Avatar \(id)")
                    .accessibilityAddTraits(selection == id ? [.isSelected] : [])
                }
            }
            .padding(.vertical, BQDesign.Spacing.xs)
        }
    }
}
