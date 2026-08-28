import SwiftUI

/// Terms of Use, rendered from `LegalCopy.sections`. Self-contained — no `NavigationStack` of its
/// own, so it can be pushed onto an existing stack (`NavigationLink`) or wrapped in one when
/// presented as a sheet, without doubling up navigation chrome. `.dismiss` works in either
/// context, so the toolbar button behaves correctly both ways.
struct TermsView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BQDesign.Spacing.lg) {
                Text("Last updated \(LegalCopy.lastUpdated)")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textSecondary)

                ForEach(LegalCopy.sections) { section in
                    sectionView(section)
                }
            }
            .padding(BQDesign.Spacing.lg)
        }
        .background(BQDesign.Colors.background)
        .navigationTitle("Terms of Use")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func sectionView(_ section: LegalCopy.Section) -> some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            Text(section.title)
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(section.paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BQDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .stroke(BQDesign.Colors.primaryPurple.opacity(0.08), lineWidth: 1)
                )
        )
        .bqShadow(BQDesign.Shadows.card)
    }
}

#Preview {
    NavigationStack {
        TermsView()
    }
}
