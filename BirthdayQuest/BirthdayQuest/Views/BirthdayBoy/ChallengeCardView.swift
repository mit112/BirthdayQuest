import SwiftUI

struct ChallengeCardView: View {
    
    let challenge: Challenge
    let index: Int
    let onTap: () -> Void
    
    @State private var appeared = false
    @State private var pressed = false
    
    private var isCompleted: Bool { challenge.isCompleted }
    
    var body: some View {
        Button(action: {
            BQDesign.Haptics.light()
            onTap()
        }) {
            HStack(spacing: 14) {
                // Left: Illustration badge with glow
                illustrationBadge
                
                // Center: Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(
                            isCompleted
                            ? BQDesign.Colors.textTertiary
                            : BQDesign.Colors.textPrimary
                        )
                        .lineLimit(1)
                    
                    Text(challenge.description)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
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
            .shadow(color: cardShadowColor, radius: isCompleted ? 6 : 10, y: isCompleted ? 2 : 4)
            .shadow(color: cardShadowColor.opacity(0.5), radius: isCompleted ? 2 : 4, y: 1)
        }
        .buttonStyle(CardPressStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
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
            // Subtle glow behind active badges
            if !isCompleted {
                Circle()
                    .fill(categoryColors[0].opacity(0.12))
                    .frame(width: 62, height: 62)
                    .blur(radius: 4)
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
                .shadow(
                    color: isCompleted
                        ? Color.clear
                        : categoryColors[0].opacity(0.25),
                    radius: 6, y: 2
                )
            
            // Icon
            if isCompleted {
                // Checkmark overlay
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Image(systemName: challenge.category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            }
        }
    }
    
    // MARK: Metadata Row
    
    var metadataRow: some View {
        HStack(spacing: 8) {
            // Points chip
            HStack(spacing: 2) {
                Text("✦")
                    .font(.system(size: 10, weight: .bold))
                Text("\(challenge.pointValue)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(BQDesign.Colors.gold)
            
            // Difficulty stars
            HStack(spacing: 1) {
                ForEach(0..<challenge.difficulty.stars, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 7))
                }
            }
            .foregroundColor(Color(hex: challenge.difficulty.color))
            
            // Submission type icon
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(BQDesign.Colors.success.opacity(0.6))
            } else {
                Image(systemName: challenge.submissionType.icon)
                    .font(.system(size: 10))
                    .foregroundColor(BQDesign.Colors.textTertiary)
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
                    .font(.system(size: 22))
                    .foregroundColor(BQDesign.Colors.success)
            }
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BQDesign.Colors.textTertiary.opacity(0.6))
        }
    }
    
    // MARK: Card Background
    
    var cardBackground: some View {
        ZStack {
            // Base white
            Color.white
            
            // Subtle category tint for active cards
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
        return categoryColors[0].opacity(0.08)
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
