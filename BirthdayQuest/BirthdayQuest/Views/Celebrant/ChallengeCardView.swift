import SwiftUI

struct ChallengeCardView: View {
    
    let challenge: Challenge
    let index: Int
    let onTap: () -> Void
    
    @State private var appeared = false

    @ScaledMetric private var badgeIconSize: CGFloat = 20
    @ScaledMetric private var pointsSparkleSize: CGFloat = 10
    @ScaledMetric private var difficultyStarSize: CGFloat = 7
    @ScaledMetric private var completionCheckSize: CGFloat = 10
    @ScaledMetric private var twoInOneBoltBadgeSize: CGFloat = 8
    @ScaledMetric private var statusCheckSize: CGFloat = 22
    @ScaledMetric private var chevronSize: CGFloat = 13

    private var isCompleted: Bool { challenge.isCompleted }
    
    var body: some View {
        Button {
            BQDesign.Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 14) {
                // Left: Illustration badge
                illustrationBadge
                
                // Center: Info
                VStack(alignment: .leading, spacing: 4) {
                    // Title truncation removed: at large Dynamic Type sizes a 1-line
                    // limit could reduce it to an unreadable fragment; let it wrap.
                    Text(challenge.title)
                        .font(BQDesign.Typography.cardTitle)
                        .foregroundColor(
                            isCompleted
                            ? BQDesign.Colors.textTertiary
                            : BQDesign.Colors.textPrimary
                        )

                    Text(challenge.description)
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(BQDesign.Colors.textSecondary)
                        .lineLimit(2)
                    
                    // Metadata row
                    metadataRow
                }
                
                Spacer(minLength: 4)
                
                // Right: Status indicator
                statusIndicator
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(cardBorder)
            .compositingGroup()
            .shadow(color: cardShadowColor, radius: isCompleted ? 4 : 8, y: isCompleted ? 2 : 3)
        }
        .buttonStyle(CardPressStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            guard !appeared else { return }
            withAnimation(
                .spring(response: 0.5, dampingFraction: 0.75)
                .delay(Double(index) * 0.05 + 0.1)
            ) {
                appeared = true
            }
        }
    }
}

// MARK: - Card Press Button Style

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Subviews

private extension ChallengeCardView {
    
    // MARK: Illustration Badge
    
    var illustrationBadge: some View {
        ZStack {
            // Soft glow behind active badges (no blur — just a larger soft circle)
            if !isCompleted {
                Circle()
                    .fill(categoryColors[0].opacity(0.15))
                    .frame(width: 60, height: 60)
            }
            
            // Main circle
            Circle()
                .fill(
                    isCompleted
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color(hex: "C5C0B8"), Color(hex: "B0A89E")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: categoryColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 49, height: 49)
                )
            
            // Icon
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: badgeIconSize, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Image(systemName: challenge.category.icon)
                    .font(.system(size: badgeIconSize, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: Metadata Row
    
    var metadataRow: some View {
        HStack(spacing: 8) {
            // Points chip
            HStack(spacing: 2) {
                Text("✦")
                    .font(.system(size: pointsSparkleSize, weight: .bold))
                Text("\(challenge.pointValue)")
                    .font(BQDesign.Typography.captionSmall)
                    .fontWeight(.bold)
            }
            .foregroundColor(BQDesign.Colors.goldText)
            
            // Difficulty stars
            HStack(spacing: 1) {
                ForEach(0..<challenge.difficulty.stars, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: difficultyStarSize))
                }
            }
            .foregroundColor(Color(hex: challenge.difficulty.color))
            
            // 2-in-1 badge or completion indicator
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: completionCheckSize))
                    .foregroundColor(BQDesign.Colors.success.opacity(0.6))
            } else if challenge.isTwoInOne {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: twoInOneBoltBadgeSize))
                    Text("2-in-1")
                        .font(BQDesign.Typography.captionSmall)
                        .fontWeight(.bold)
                }
                .foregroundColor(BQDesign.Colors.primaryOrange)
            }
        }
        .padding(.top, 2)
    }
    
    // MARK: Status Indicator
    
    @ViewBuilder
    var statusIndicator: some View {
        if isCompleted {
            ZStack {
                Circle()
                    .fill(BQDesign.Colors.success.opacity(0.12))
                    .frame(width: 34, height: 34)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: statusCheckSize))
                    .foregroundColor(BQDesign.Colors.success)
            }
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: chevronSize, weight: .semibold))
                .foregroundColor(BQDesign.Colors.textTertiary.opacity(0.6))
        }
    }
    
    // MARK: Card Background
    
    var cardBackground: some View {
        ZStack {
            Color.white
            
            if !isCompleted {
                LinearGradient(
                    colors: [
                        categoryColors[0].opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }
    
    // MARK: Card Border
    
    var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                isCompleted
                    ? BQDesign.Colors.success.opacity(0.12)
                    : categoryColors[0].opacity(0.08),
                lineWidth: 1
            )
    }
    
    // MARK: Shadow Color
    
    var cardShadowColor: Color {
        if isCompleted {
            return Color.black.opacity(0.04)
        }
        return categoryColors[0].opacity(0.1)
    }
    
    // MARK: Category Colors
    
    var categoryColors: [Color] {
        switch challenge.category {
        case .physical:
            return [Color(hex: "4CAF50"), Color(hex: "66BB6A")]
        case .social:
            return [Color(hex: "5B9FE6"), Color(hex: "7BB3ED")]
        case .creative:
            return [BQDesign.Colors.primaryPurple, BQDesign.Colors.primaryPink]
        case .sentimental:
            return [BQDesign.Colors.primaryPink, Color(hex: "FF8FB1")]
        case .adventure:
            return [BQDesign.Colors.primaryOrange, Color(hex: "FFB74D")]
        }
    }
}
