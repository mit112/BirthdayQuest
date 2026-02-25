import SwiftUI

// MARK: - Timeline Node View
// Each node on the journey path. Challenge nodes are blue-tinted circles,
// reward nodes are golden with double-ring halos. The newest node breathes.

struct TimelineNodeView: View {
    
    let event: TimelineEvent
    let isNew: Bool
    let index: Int
    let totalCount: Int
    
    @State private var appeared = false
    @State private var badgePop = false
    @State private var glowPulse = false
    @State private var breathe = false
    @State private var sparkleVisible = false
    
    private let nodeSize: CGFloat = 68
    private var isChallenge: Bool { event.type == .challengeCompleted }
    private var isReward: Bool { event.type == .rewardUnlocked }
    private var isLatest: Bool { index == totalCount - 1 }
    
    var body: some View {
        VStack(spacing: 8) {
            // The badge circle with glow layers
            ZStack {
                // Outer breathing glow (latest node only)
                if isLatest {
                    breathingGlow
                }
                
                // Reward double-ring halo
                if isReward {
                    rewardHalo
                }
                
                // Main badge circle
                badgeCircle
                
                // Icon or avatar content
                nodeContent
            }
            .scaleEffect(badgePop ? 1.0 : 0.01)
            
            // Title
            Text(cleanTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(BQDesign.Colors.textPrimary)
                .lineLimit(1)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
            
            // Points
            HStack(spacing: 3) {
                Text("✦")
                    .font(.system(size: 10, weight: .heavy))
                Text(pointsText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(pointsColor)
            .opacity(appeared ? 1 : 0)
            
            // Friend name for rewards
            if let friend = event.fromFriendName {
                Text("from \(friend)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(BQDesign.Colors.textTertiary)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear { animateEntrance() }
    }
    
    // MARK: - Animation
    
    private func animateEntrance() {
        let delay = isNew ? Double(index) * 0.18 + 0.15 : Double(index) * 0.03
        
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(delay)) {
            badgePop = true
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(delay + 0.1)) {
            appeared = true
        }
        
        // Reward glow pulse
        if isReward {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(delay + 0.3)) {
                glowPulse = true
            }
        }
        
        // Latest node breathing
        if isLatest {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(delay + 0.2)) {
                breathe = true
            }
        }
        
        // Sparkle burst for new nodes
        if isNew {
            withAnimation(.easeOut(duration: 0.6).delay(delay + 0.3)) {
                sparkleVisible = true
            }
        }
    }
}

// MARK: - Badge Components

private extension TimelineNodeView {
    
    // Breathing glow for the latest/active node
    var breathingGlow: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(breathe ? 0.15 : 0.04))
                .frame(width: nodeSize + 32, height: nodeSize + 32)
                .blur(radius: 8)
            
            Circle()
                .fill(accentColor.opacity(breathe ? 0.08 : 0.02))
                .frame(width: nodeSize + 48, height: nodeSize + 48)
                .blur(radius: 12)
        }
    }
    
    // Double-ring halo for reward nodes
    var rewardHalo: some View {
        ZStack {
            // Outer soft glow
            Circle()
                .fill(BQDesign.Colors.gold.opacity(glowPulse ? 0.18 : 0.05))
                .frame(width: nodeSize + 22, height: nodeSize + 22)
            
            // Thin decorative outer ring
            Circle()
                .stroke(BQDesign.Colors.gold.opacity(glowPulse ? 0.35 : 0.15), lineWidth: 1.5)
                .frame(width: nodeSize + 12, height: nodeSize + 12)
        }
    }
    
    // Main circle
    var badgeCircle: some View {
        Circle()
            .fill(circleFill)
            .frame(width: nodeSize, height: nodeSize)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 2.5)
                    .frame(width: nodeSize - 3, height: nodeSize - 3)
            )
            .shadow(color: shadowColor.opacity(0.4), radius: 8, y: 3)
            .shadow(color: shadowColor.opacity(0.15), radius: 16, y: 6)
    }
    
    // Icon or avatar inside the circle
    @ViewBuilder
    var nodeContent: some View {
        if isReward, let friendName = event.fromFriendName {
            AvatarView(name: friendName, size: nodeSize * 0.58)
        } else {
            Image(systemName: badgeIcon)
                .font(.system(size: nodeSize * 0.32, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        }
        
        // Sparkle burst overlay for new events
        if isNew && sparkleVisible {
            sparkleRing
        }
    }
    
    // Ring of tiny sparkles that appears on new nodes
    var sparkleRing: some View {
        ForEach(0..<6, id: \.self) { i in
            Image(systemName: "sparkle")
                .font(.system(size: 6, weight: .heavy))
                .foregroundStyle(BQDesign.Colors.gold.opacity(0.7))
                .offset(
                    x: cos(CGFloat(i) * .pi / 3) * (nodeSize * 0.55),
                    y: sin(CGFloat(i) * .pi / 3) * (nodeSize * 0.55)
                )
                .opacity(sparkleVisible ? 0 : 0.9)
                .scaleEffect(sparkleVisible ? 1.5 : 0.5)
        }
    }
}

// MARK: - Styling

private extension TimelineNodeView {
    
    var circleFill: some ShapeStyle {
        if isReward {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: "FFD166"), Color(hex: "F5A623")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: challengeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    var challengeColors: [Color] {
        let palettes: [[Color]] = [
            [Color(hex: "6DB3F2"), Color(hex: "4A8BD4")],   // sky blue
            [Color(hex: "A78BFA"), Color(hex: "7C5CFC")],   // purple
            [Color(hex: "F472B6"), Color(hex: "EC4899")],   // pink
            [Color(hex: "34D399"), Color(hex: "10B981")],   // mint
            [Color(hex: "FB923C"), Color(hex: "F97316")],   // orange
            [Color(hex: "60A5FA"), Color(hex: "3B82F6")],   // blue
        ]
        return palettes[index % palettes.count]
    }
    
    var accentColor: Color {
        isReward ? BQDesign.Colors.gold : challengeColors[0]
    }
    
    var shadowColor: Color {
        isReward ? BQDesign.Colors.gold : challengeColors[0]
    }
    
    var pointsColor: Color {
        isReward ? BQDesign.Colors.gold : challengeColors[0]
    }
    
    var badgeIcon: String {
        let asset = event.badgeAsset
        if UIImage(systemName: asset) != nil { return asset }
        return "bolt.fill"
    }
    
    var cleanTitle: String {
        var t = event.title
        if t.hasPrefix("Completed: ") { t = String(t.dropFirst(11)) }
        else if t.hasPrefix("Unlocked: ") { t = String(t.dropFirst(10)) }
        return t
    }
    
    var pointsText: String {
        event.subtitle.replacingOccurrences(of: " ✦", with: "")
    }
}

// MARK: - Star Shape (kept for FinalBadge)

struct StarShape: Shape {
    let points: Int
    let innerRatio: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let angleStep = .pi * 2 / CGFloat(points * 2)
        var path = Path()
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = angleStep * CGFloat(i) - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
