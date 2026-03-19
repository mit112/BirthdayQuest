import SwiftUI

struct RewardCardView: View {
    
    let reward: Reward
    let isAffordable: Bool
    let onTap: () -> Void
    
    @State private var glowOpacity: Double = 0.0
    
    private var isLocked: Bool { !reward.isUnlocked && !isAffordable }
    private var isUnlocked: Bool { reward.isUnlocked }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Card background
                RoundedRectangle(cornerRadius: BQDesign.Radius.xxl, style: .continuous)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.xxl, style: .continuous)
                            .stroke(borderColor, lineWidth: isAffordable ? 2 : 0)
                    )
                
                // Affordable glow
                if isAffordable {
                    RoundedRectangle(cornerRadius: BQDesign.Radius.xxl, style: .continuous)
                        .fill(BQDesign.Colors.gold.opacity(glowOpacity))
                        .blur(radius: 20)
                }
                
                // Card content
                VStack(spacing: BQDesign.Spacing.md) {
                    Spacer()
                    
                    // Avatar circle
                    ZStack {
                        Circle()
                            .fill(avatarBackground)
                            .frame(width: 80, height: 80)
                        
                        AvatarView(name: reward.fromName, size: 70)
                        
                        if isLocked {
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 80, height: 80)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    // From name
                    Text("A gift from")
                        .font(BQDesign.Typography.captionSmall)
                        .foregroundColor(textColor.opacity(0.6))
                    
                    Text(reward.fromName)
                        .font(BQDesign.Typography.sectionTitle)
                        .foregroundColor(textColor)
                    
                    // Teaser
                    if let teaser = reward.teaser, !teaser.isEmpty {
                        Text(teaser)
                            .font(BQDesign.Typography.caption)
                            .foregroundColor(textColor.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, BQDesign.Spacing.md)
                    }
                    
                    Spacer()
                    
                    // Cost / Status badge
                    if isUnlocked {
                        Label("View", systemImage: "play.circle.fill")
                            .font(BQDesign.Typography.bodyBold)
                            .foregroundColor(.white)
                            .padding(.horizontal, BQDesign.Spacing.lg)
                            .padding(.vertical, BQDesign.Spacing.sm)
                            .background(
                                Capsule().fill(BQDesign.Colors.primaryGradient)
                            )
                    } else {
                        HStack(spacing: BQDesign.Spacing.xs) {
                            Text("✦")
                                .font(.system(size: 14, weight: .bold))
                            Text("\(reward.pointCost)")
                                .font(BQDesign.Typography.bodyBold)
                        }
                        .foregroundColor(isAffordable ? BQDesign.Colors.gold : textColor.opacity(0.5))
                        .padding(.horizontal, BQDesign.Spacing.lg)
                        .padding(.vertical, BQDesign.Spacing.sm)
                        .background(
                            Capsule().fill(
                                isAffordable
                                ? BQDesign.Colors.gold.opacity(0.15)
                                : Color.gray.opacity(0.1)
                            )
                        )
                    }
                    
                    Spacer().frame(height: BQDesign.Spacing.lg)
                }
                .padding(BQDesign.Spacing.lg)
            }
            .frame(width: 260, height: 380)
            .bqShadow(BQDesign.Shadows.card)
        }
        .buttonStyle(.plain)
        .onAppear {
            if isAffordable {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.15
                }
            }
        }
    }
}

// MARK: - Computed Styling

private extension RewardCardView {
    
    var cardFill: some ShapeStyle {
        if isUnlocked {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: "FFF8F0"), Color(hex: "FFF3E0")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else if isAffordable {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [BQDesign.Colors.cardBackground, Color(hex: "FFFBF5")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: "F5F3F8"), Color(hex: "EDEBF2")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
    
    var borderColor: Color {
        if isAffordable { return BQDesign.Colors.gold.opacity(0.5) }
        if isUnlocked { return BQDesign.Colors.gold.opacity(0.3) }
        return .clear
    }
    
    var textColor: Color {
        isLocked ? BQDesign.Colors.textSecondary : BQDesign.Colors.textPrimary
    }
    
    var avatarBackground: some ShapeStyle {
        if isUnlocked {
            return AnyShapeStyle(BQDesign.Colors.warmGradient)
        } else if isAffordable {
            return AnyShapeStyle(BQDesign.Colors.primaryGradient)
        } else {
            return AnyShapeStyle(Color(hex: "D8D5E0"))
        }
    }
    
}
