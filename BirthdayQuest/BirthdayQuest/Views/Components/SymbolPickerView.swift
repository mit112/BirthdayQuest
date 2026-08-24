import SwiftUI

/// A grid picker over `ChallengeSymbolCatalog`.
///
/// Tiles are a fixed 44pt minimum because that is the tap-target floor, while the glyph
/// inside scales with Dynamic Type via `@ScaledMetric` — the target and the artwork are
/// different measurements and only one of them is a hit area.
///
/// Selection is shown by a border *and* a fill, not by colour alone: a colour-only
/// selection state is unreadable to anyone who cannot distinguish the two tints.
struct SymbolPickerView: View {

    @Binding var selection: String

    @ScaledMetric private var glyphSize: CGFloat = 20
    private let columns = [GridItem(.adaptive(minimum: 52), spacing: BQDesign.Spacing.sm)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: BQDesign.Spacing.sm) {
            ForEach(ChallengeSymbolCatalog.all, id: \.self) { name in
                let isSelected = selection == name
                Button {
                    selection = name
                    BQDesign.Haptics.selection()
                } label: {
                    Image(systemName: name)
                        .font(.system(size: glyphSize))
                        .foregroundStyle(
                            isSelected
                            ? BQDesign.Colors.primaryPurple
                            : BQDesign.Colors.textSecondary
                        )
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .fill(
                                    isSelected
                                    ? BQDesign.Colors.primaryPurple.opacity(0.12)
                                    : BQDesign.Colors.background
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .stroke(
                                    isSelected
                                    ? BQDesign.Colors.primaryPurple
                                    : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.spokenName(for: name))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// SF Symbol names are dot-separated identifiers, which VoiceOver reads literally
    /// ("music dot mic"). Spoken form instead.
    static func spokenName(for symbol: String) -> String {
        symbol
            .replacingOccurrences(of: ".fill", with: "")
            .split(separator: ".")
            .joined(separator: " ")
    }
}
