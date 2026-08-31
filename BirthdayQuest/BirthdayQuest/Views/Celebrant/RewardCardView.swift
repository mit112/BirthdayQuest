import SwiftUI

struct RewardCardView: View {
    
    let reward: Reward
    let isAffordable: Bool
    /// Supplied by `RewardsCarouselView`, which also derives the carousel's paging inset from
    /// it. The card must not re-declare a width of its own: the two numbers have to agree or
    /// `.viewAligned` snaps the cards off centre.
    let width: CGFloat
    let onTap: () -> Void

    @State private var glowOpacity: Double = 0.0
    @Environment(\.bqMotionLevel) private var motionLevel
    @ScaledMetric private var lockIconSize: CGFloat = 20
    @ScaledMetric private var costGlyphSize: CGFloat = 14

    private var isLocked: Bool { !reward.isUnlocked && !isAffordable }
    private var isUnlocked: Bool { reward.isUnlocked }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Card background — an opaque surface token with a translucent tint composited
                // *on top of it*. Splitting the two is what lets the wash be a low-opacity design
                // token instead of a fixed cream hex: a translucent stop in a single gradient
                // would composite over the page instead, and in dark that makes a card fade into
                // its own background at whichever end the tint is strongest.
                RoundedRectangle(cornerRadius: BQDesign.Radius.xxl, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.xxl, style: .continuous)
                            .fill(cardTint)
                    )
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
                                .font(.system(size: lockIconSize))
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
                                .font(.system(size: costGlyphSize, weight: .bold))
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
                                // `textTertiary` is the palette's "faint fill" role. At 15% it
                                // lands within 2/255 of the system grey this replaced in light,
                                // and unlike `Color.gray` it lightens on a dark card instead of
                                // staying a fixed mid grey.
                                : BQDesign.Colors.textTertiary.opacity(0.15)
                            )
                        )
                    }
                    
                    Spacer().frame(height: BQDesign.Spacing.lg)
                }
                .padding(BQDesign.Spacing.lg)
            }
            .frame(width: width)
            .frame(minHeight: 380)
            .bqShadow(BQDesign.Shadows.card)
        }
        .buttonStyle(.plain)
        .onAppear {
            if isAffordable && motionLevel.allowsPerpetual {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.15
                }
            }
        }
    }
}

// MARK: - Computed Styling

private extension RewardCardView {
    
    /// The card's opaque base.
    ///
    /// A locked gift recedes toward the page in *both* appearances, which is what the original
    /// cool grey did in light; `background` is the token that means that, and in dark it also
    /// puts the locked card below `cardBackground` rather than above it.
    var cardSurface: Color {
        isLocked ? BQDesign.Colors.background : BQDesign.Colors.cardBackground
    }

    /// The wash drawn over `cardSurface`. Each opacity was solved so the light composite lands on
    /// the hex it replaces:
    ///
    /// - unlocked: `goldLight` at 50% -> 100% over white is `#FFF9ED` -> `#FFF3DC`, against the
    ///   original `#FFF8F0` -> `#FFF3E0`.
    /// - affordable: 30% `goldLight` over white is `#FFFBF4`, one unit off the original
    ///   `#FFFBF5`. This is the stop that used to mix the (now dynamic) `cardBackground` with a
    ///   fixed cream and would have seamed visibly in dark.
    /// - locked: `primaryPurple` at 4% -> 9% over `background` is `#F6F1F4` -> `#F0E9F5`, against
    ///   the original `#F5F3F8` -> `#EDEBF2` — the same faint violet cast, one token instead of two
    ///   hexes.
    var cardTint: LinearGradient {
        let stops: [Color]
        if isUnlocked {
            stops = [BQDesign.Colors.goldLight.opacity(0.5), BQDesign.Colors.goldLight]
        } else if isAffordable {
            stops = [BQDesign.Colors.goldLight.opacity(0), BQDesign.Colors.goldLight.opacity(0.3)]
        } else {
            stops = [
                BQDesign.Colors.primaryPurple.opacity(0.04),
                BQDesign.Colors.primaryPurple.opacity(0.09)
            ]
        }
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
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
            // Same faint-fill role as the cost pill: 50% `textTertiary` resolves to `#D5D1DD`
            // over the locked card in light, against the `#D8D5E0` it replaces.
            return AnyShapeStyle(BQDesign.Colors.textTertiary.opacity(0.5))
        }
    }
    
}
