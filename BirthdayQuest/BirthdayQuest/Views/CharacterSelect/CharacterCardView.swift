import SwiftUI

struct CharacterCardView: View {
    
    let character: BQUser
    let isSelected: Bool
    
    // MARK: - Animation State
    @State private var glowPulse = false
    @State private var floatOffset: CGFloat = 0
    @State private var ringRotation: Double = 0
    @State private var appeared = false
    
    private var isBirthdayBoy: Bool { character.role == .birthdayBoy }
    private var isClaimed: Bool { character.claimed }
    
    private var accentColor: Color {
        isBirthdayBoy ? BQDesign.Colors.gold : BQDesign.Colors.primaryPurple
    }
    
    private var accentGradient: LinearGradient {
        isBirthdayBoy
            ? BQDesign.Colors.goldGradient
            : BQDesign.Colors.primaryGradient
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Avatar Platform
            ZStack {
                // Large ambient glow
                if isSelected {
                    ambientGlow
                }
                
                // Decorative orbit ring
                if isSelected {
                    orbitRing
                }
                
                // Platform shadow
                Ellipse()
                    .fill(accentColor.opacity(isSelected ? 0.15 : 0.06))
                    .frame(width: 120, height: 24)
                    .blur(radius: 6)
                    .offset(y: 78)
                
                // Avatar circle
                avatarCircle
                    .offset(y: floatOffset)
            }
            .frame(height: 210)
            
            // Character Info
            VStack(spacing: 10) {
                Text(character.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(appeared ? 1 : 0)
                
                Text(character.tagline)
                    .font(BQDesign.Typography.tagline)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .opacity(appeared ? 1 : 0)
                
                // Role badge pill
                roleBadge
                    .opacity(appeared ? 1 : 0)
                
                if isClaimed {
                    Text("Already chosen")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.top, 2)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
            startAnimations()
        }
        .onChange(of: isSelected) { _, selected in
            if selected { startAnimations() }
        }
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        guard isSelected else { return }
        
        // Floating avatar
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            floatOffset = -10
        }
        
        // Glow pulse
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
        
        // Ring rotation
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
    }
}

// MARK: - Components

private extension CharacterCardView {
    
    // Layered radial glow behind avatar
    var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(glowPulse ? 0.2 : 0.06), Color.clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 130
                    )
                )
                .frame(width: 260, height: 260)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(glowPulse ? 0.12 : 0.03), Color.clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 170
                    )
                )
                .frame(width: 340, height: 340)
        }
    }
    
    // Thin rotating dashed ring with sparkle dots
    var orbitRing: some View {
        ZStack {
            // Dashed orbit
            Circle()
                .stroke(
                    accentColor.opacity(0.15),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 8])
                )
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(ringRotation))
            
            // Orbiting sparkle dots
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(accentColor.opacity(glowPulse ? 0.6 : 0.25))
                    .frame(width: 4, height: 4)
                    .offset(x: 95)
                    .rotationEffect(.degrees(ringRotation + Double(i) * 120))
            }
        }
    }
    
    // Main avatar with gradient ring
    var avatarCircle: some View {
        ZStack {
            // Gradient border ring
            Circle()
                .fill(accentGradient)
                .frame(width: 152, height: 152)
            
            // Inner white ring
            Circle()
                .fill(Color.white)
                .frame(width: 146, height: 146)
            
            // Gradient fill behind avatar
            Circle()
                .fill(accentGradient)
                .frame(width: 142, height: 142)
            
            // Avatar
            AvatarView(
                name: character.name,
                size: 134,
                isBirthdayBoy: isBirthdayBoy,
                showCrown: true
            )
            
            // Claimed indicator — small lock badge in bottom-right, avatar stays visible
            if isClaimed {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 30, height: 30)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .offset(x: 50, y: 50)
            }
        }
        .shadow(color: accentColor.opacity(isSelected ? 0.3 : 0.1), radius: 16, y: 6)
        .shadow(color: accentColor.opacity(isSelected ? 0.15 : 0.05), radius: 32, y: 10)
    }
    
    // Role badge
    var roleBadge: some View {
        Text(character.roleBadge)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(accentColor.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}
