import SwiftUI

/// Animated points counter with the ✦ symbol.
struct PointsDisplayView: View {
    
    let points: Int
    var style: PointsStyle = .large
    
    var body: some View {
        HStack(spacing: BQDesign.Spacing.xs) {
            Text("✦")
                .font(style.symbolFont)
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

enum PointsStyle {
    case large
    case compact
    
    var symbolFont: Font {
        switch self {
        case .large: return .system(size: 22, weight: .bold)
        case .compact: return .system(size: 14, weight: .bold)
        }
    }
    
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