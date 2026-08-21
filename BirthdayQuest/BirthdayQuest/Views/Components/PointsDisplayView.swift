import SwiftUI

/// Animated points counter with the ✦ symbol.
struct PointsDisplayView: View {
    
    let points: Int
    var style: PointsStyle = .large

    // ✦ is a decorative glyph, not text content, so it scales via ScaledMetric off the
    // style's own base size rather than through a Font token.
    @ScaledMetric private var largeSymbolSize: CGFloat = 22
    @ScaledMetric private var compactSymbolSize: CGFloat = 14

    private var symbolSize: CGFloat {
        style == .large ? largeSymbolSize : compactSymbolSize
    }

    var body: some View {
        HStack(spacing: BQDesign.Spacing.xs) {
            Text("✦")
                .font(.system(size: symbolSize, weight: .bold))
                .foregroundStyle(BQDesign.Colors.goldGradient)
            
            Text("\(points)")
                .font(style.numberFont)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .contentTransition(.numericText())
                .animation(BQDesign.Animation.snappy, value: points)
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(
            Capsule()
                .fill(BQDesign.Colors.goldLight)
        )
    }
}

// MARK: - Points Style

enum PointsStyle: Equatable {
    case large
    case compact

    var numberFont: Font {
        switch self {
        case .large: return BQDesign.Typography.pointsLarge
        case .compact: return BQDesign.Typography.points
        }
    }
    
    var horizontalPadding: CGFloat {
        switch self {
        case .large: return BQDesign.Spacing.lg
        case .compact: return BQDesign.Spacing.md
        }
    }
    
    var verticalPadding: CGFloat {
        switch self {
        case .large: return BQDesign.Spacing.sm
        case .compact: return BQDesign.Spacing.xs
        }
    }
}
