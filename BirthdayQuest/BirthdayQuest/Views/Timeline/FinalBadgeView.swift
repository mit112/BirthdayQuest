import SwiftUI

struct FinalBadgeView: View {
    
    let isUnlocked: Bool
    let progressText: String
    let progressFraction: Double  // 0...1 how close to unlocking
    
    @State private var pulse = false
    @State private var appeared = false
    @State private var shimmerOffset: CGFloat = -200
    @State private var crownSpin: Double = 0
    @State private var revealScale: CGFloat = 0.6
    @State private var particlesBurst = false
    
    private let badgeSize: CGFloat = 96
    
    // Glow intensity increases as user gets closer to unlocking
    private var glowIntensity: Double {
        if isUnlocked { return 1.0 }
        // Ramp up glow as progress increases
        return 0.08 + (progressFraction * 0.5)
    }
    
    // Shimmer speed increases with progress
    private var shimmerDuration: Double {
        if isUnlocked { return 1.5 }
        return 4.0 - (progressFraction * 2.0) // 4s → 2s as progress increases
    }
    
    var body: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            ZStack {
                // Ambient glow rings (intensity scales with progress)
                ambientGlow
                
                // The badge itself
                badgeBody
                
                // Shimmer sweep across the badge
                shimmerSweep
                
                // Sparkle ring (appears at >50% progress)
                if progressFraction > 0.5 || isUnlocked {
                    orbitingSparkles
                }
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            
            // Label
            labelSection
                .opacity(appeared ? 1 : 0)
        }
        .padding(.vertical, BQDesign.Spacing.xxl)
        .onAppear { animateIn() }
    }
    
    // MARK: - Animation Triggers
    
    private func animateIn() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.15)) {
            appeared = true
        }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            pulse = true
        }
        // Shimmer sweep
        withAnimation(.linear(duration: shimmerDuration).repeatForever(autoreverses: false).delay(0.5)) {
            shimmerOffset = 200
        }
        if isUnlocked {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                crownSpin = 360
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5).delay(0.3)) {
                revealScale = 1.0
            }
        }
    }
}

// MARK: - Badge Components

private extension FinalBadgeView {
    
    // Layered radial glow — intensity ramps with progress
    var ambientGlow: some View {
        ZStack {
            // Outer diffuse glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: isUnlocked
                            ? [BQDesign.Colors.gold.opacity(0.25), Color.clear]
                            : [BQDesign.Colors.primaryPurple.opacity(glowIntensity * 0.4), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .scaleEffect(pulse ? 1.15 : 0.9)
            
            // Inner concentrated glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: isUnlocked
                            ? [BQDesign.Colors.gold.opacity(0.35), Color.clear]
                            : [BQDesign.Colors.primaryPurple.opacity(glowIntensity * 0.6), Color.clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 60
                    )
                )
                .frame(width: 140, height: 140)
                .scaleEffect(pulse ? 1.05 : 0.95)
        }
    }
    
    // Main badge circle
    var badgeBody: some View {
        ZStack {
            // Badge circle
            Circle()
                .fill(badgeFill)
                .frame(width: badgeSize, height: badgeSize)
                .overlay(
                    Circle()
                        .stroke(
                            isUnlocked
                                ? Color.white.opacity(0.6)
                                : Color.white.opacity(0.3),
                            lineWidth: 2.5
                        )
                )
                .shadow(
                    color: isUnlocked
                        ? BQDesign.Colors.gold.opacity(0.4)
                        : BQDesign.Colors.primaryPurple.opacity(glowIntensity * 0.3),
                    radius: 12, y: 4
                )
                .shadow(
                    color: isUnlocked
                        ? BQDesign.Colors.gold.opacity(0.2)
                        : BQDesign.Colors.primaryPurple.opacity(glowIntensity * 0.15),
                    radius: 24, y: 8
                )
            
            // Purple veil overlay (locked state) — lets gold bleed through
            if !isUnlocked {
                Circle()
                    .fill(Color(hex: "3D2C5E").opacity(0.35 - (progressFraction * 0.15)))
                    .frame(width: badgeSize, height: badgeSize)
                    .blendMode(.multiply)
            }
            
            // Icon
            if isUnlocked {
                Text("👑")
                    .font(.system(size: 42))
                    .scaleEffect(revealScale)
                    .rotationEffect(.degrees(crownSpin))
            } else {
                Text("?")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        // Question mark becomes more golden as progress increases
                        LinearGradient(
                            colors: [
                                BQDesign.Colors.primaryPurple.opacity(0.3 + (1.0 - progressFraction) * 0.2),
                                BQDesign.Colors.gold.opacity(progressFraction * 0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }
    
    var badgeFill: some ShapeStyle {
        if isUnlocked {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: "FFD166"), Color(hex: "F5A623"), Color(hex: "E8941E")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        // Locked: starts muted purple, warms toward gold as progress increases
        let purpleAmount = 1.0 - progressFraction
        let goldAmount = progressFraction
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(
                        red: 0.88 * purpleAmount + 1.0 * goldAmount,
                        green: 0.85 * purpleAmount + 0.91 * goldAmount,
                        blue: 0.95 * purpleAmount + 0.65 * goldAmount
                    ),
                    Color(
                        red: 0.82 * purpleAmount + 0.96 * goldAmount,
                        green: 0.78 * purpleAmount + 0.82 * goldAmount,
                        blue: 0.92 * purpleAmount + 0.55 * goldAmount
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // Diagonal shimmer sweep
    var shimmerSweep: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(isUnlocked ? 0.4 : 0.15 + progressFraction * 0.1),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 40, height: badgeSize + 20)
            .rotationEffect(.degrees(25))
            .offset(x: shimmerOffset)
            .clipShape(Circle().scale(1.0))
            .frame(width: badgeSize, height: badgeSize)
            .clipped()
            .allowsHitTesting(false)
    }
    
    // Orbiting sparkle dots around the badge
    var orbitingSparkles: some View {
        ForEach(0..<(isUnlocked ? 6 : 3), id: \.self) { i in
            Image(systemName: "sparkle")
                .font(.system(size: isUnlocked ? 8 : 5, weight: .bold))
                .foregroundStyle(
                    isUnlocked
                        ? BQDesign.Colors.gold.opacity(0.7)
                        : BQDesign.Colors.primaryPurple.opacity(0.4)
                )
                .offset(
                    x: cos(CGFloat(i) * .pi * 2 / CGFloat(isUnlocked ? 6 : 3)) * (badgeSize * 0.65),
                    y: sin(CGFloat(i) * .pi * 2 / CGFloat(isUnlocked ? 6 : 3)) * (badgeSize * 0.65)
                )
                .opacity(pulse ? 0.9 : 0.3)
        }
    }
}

// MARK: - Label

private extension FinalBadgeView {
    
    var labelSection: some View {
        VStack(spacing: 4) {
            if isUnlocked {
                Text("Quest Complete! 🎉")
                    .font(BQDesign.Typography.sectionTitle)
                    .foregroundColor(BQDesign.Colors.gold)
                
                Text("Your friends have one more surprise...")
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("The Final Surprise")
                    .font(BQDesign.Typography.cardTitle)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                
                Text(progressText)
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textTertiary)
            }
        }
    }
}
