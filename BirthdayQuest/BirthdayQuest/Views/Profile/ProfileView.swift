import SwiftUI

struct ProfileView: View {
    
    @EnvironmentObject private var session: SessionManager
    @State private var appeared = false
    @State private var avatarGlow = false
    @State private var crownBounce = false
    
    private var user: BQUser? { session.currentUser }
    private var gameState: GameState { session.gameState }
    private var isBirthdayBoy: Bool { session.isBirthdayBoy }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Living gradient background
                ProfileBackgroundView(isBirthdayBoy: isBirthdayBoy)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BQDesign.Spacing.lg) {
                        // Hero avatar area
                        avatarHero
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.9)
                        
                        // Stats grid
                        statsSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 15)
                        
                        // Fun facts
                        funFactsSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                        
                        // Dev tools (organizer only)
                        if session.isOrganizer {
                            adminSection
                        }
                        
                        // Switch character
                        switchCharacterButton
                        
                        Spacer().frame(height: 100)
                    }
                    .padding(.top, BQDesign.Spacing.lg)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            withAnimation(BQDesign.Animation.smooth.delay(0.1)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(0.3)) {
                avatarGlow = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.4)) {
                crownBounce = true
            }
        }
    }
}

// MARK: - Profile Background

private struct ProfileBackgroundView: View {
    let isBirthdayBoy: Bool
    
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: isBirthdayBoy ? "FFF8EE" : "F5F0FA"), location: 0.0),
                    .init(color: Color(hex: "FBF7F4"), location: 0.3),
                    .init(color: Color(hex: "FFF5EE"), location: 0.6),
                    .init(color: Color(hex: isBirthdayBoy ? "FFF0E0" : "F0EAFA"), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            SparkleFieldView()
                .opacity(0.3)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Subviews

private extension ProfileView {
    
    // MARK: Avatar Hero
    var avatarHero: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            ZStack {
                // Breathing glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isBirthdayBoy
                                ? [BQDesign.Colors.gold.opacity(avatarGlow ? 0.25 : 0.08), Color.clear]
                                : [BQDesign.Colors.primaryPurple.opacity(avatarGlow ? 0.2 : 0.06), Color.clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 100
                        )
                    )
                    .frame(width: 180, height: 180)
                
                // Outer decorative ring
                Circle()
                    .stroke(
                        isBirthdayBoy
                            ? BQDesign.Colors.gold.opacity(0.2)
                            : BQDesign.Colors.primaryPurple.opacity(0.15),
                        lineWidth: 1.5
                    )
                    .frame(width: 140, height: 140)
                
                // Avatar background circle
                Circle()
                    .fill(
                        isBirthdayBoy
                        ? BQDesign.Colors.goldGradient
                        : BQDesign.Colors.primaryGradient
                    )
                    .frame(width: 128, height: 128)
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: 3)
                    )
                    .shadow(
                        color: isBirthdayBoy
                            ? BQDesign.Colors.gold.opacity(0.3)
                            : BQDesign.Colors.primaryPurple.opacity(0.2),
                        radius: 12, y: 4
                    )
                    .shadow(
                        color: isBirthdayBoy
                            ? BQDesign.Colors.gold.opacity(0.15)
                            : BQDesign.Colors.primaryPurple.opacity(0.1),
                        radius: 24, y: 8
                    )
                
                AvatarView(
                    name: user?.name ?? "Agent",
                    size: 118,
                    isBirthdayBoy: isBirthdayBoy,
                    showCrown: true
                )
            }
            
            // Name
            Text(user?.name ?? "Agent")
                .font(BQDesign.Typography.heroTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
            
            // Tagline
            Text(user?.tagline ?? "")
                .font(BQDesign.Typography.tagline)
                .foregroundColor(BQDesign.Colors.textSecondary)
                .italic()
                .multilineTextAlignment(.center)
                .padding(.horizontal, BQDesign.Spacing.xl)
            
            // Role badge
            Text(user?.roleBadge ?? "")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(isBirthdayBoy ? BQDesign.Colors.gold : BQDesign.Colors.primaryPurple)
                .padding(.horizontal, BQDesign.Spacing.md)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isBirthdayBoy
                        ? BQDesign.Colors.gold.opacity(0.12)
                        : BQDesign.Colors.primaryPurple.opacity(0.1)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        isBirthdayBoy
                            ? BQDesign.Colors.gold.opacity(0.15)
                            : BQDesign.Colors.primaryPurple.opacity(0.1),
                        lineWidth: 1
                    )
                )
        }
    }
    
    // MARK: Stats Section
    var statsSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("Stats")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BQDesign.Spacing.lg)
            
            if isBirthdayBoy {
                birthdayBoyStats
            } else {
                friendStats
            }
        }
    }
    
    var birthdayBoyStats: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            StatCard(icon: "✦", value: "\(gameState.currentPoints)", label: "Points", color: BQDesign.Colors.gold, index: 0)
            StatCard(icon: "⚔️", value: "\(gameState.challengesCompleted)", label: "Challenges", color: BQDesign.Colors.challengeBlue, index: 1)
            StatCard(icon: "🎁", value: "\(gameState.rewardsUnlocked)", label: "Rewards", color: BQDesign.Colors.primaryPink, index: 2)
            StatCard(icon: "🕵️", value: "\(gameState.secretChallengesCompleted)", label: "Secrets", color: BQDesign.Colors.secretAccent, index: 3)
        }
        .padding(.horizontal, BQDesign.Spacing.lg)
    }
    
    var friendStats: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(icon: "🕵️", value: "Active", label: "Secret Dare", color: BQDesign.Colors.secretAccent, index: 0)
                StatCard(icon: "👀", value: "Day \(gameState.currentDay)", label: "Watching", color: BQDesign.Colors.primaryPurple, index: 1)
            }
        }
        .padding(.horizontal, BQDesign.Spacing.lg)
    }
    
    // MARK: Fun Facts
    var funFactsSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("Character Intel")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BQDesign.Spacing.lg)
            
            VStack(spacing: 10) {
                ForEach(Array((user?.funFacts ?? []).enumerated()), id: \.element) { index, fact in
                    let emojis = ["💬", "🎯", "🦝", "🌮", "😴"]
                    
                    HStack(spacing: 14) {
                        // Emoji badge
                        ZStack {
                            Circle()
                                .fill(factColor(for: index).opacity(0.1))
                                .frame(width: 38, height: 38)
                            
                            Text(emojis[index % emojis.count])
                                .font(.system(size: 18))
                        }
                        
                        Text(fact)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(BQDesign.Colors.textPrimary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(factColor(for: index).opacity(0.08), lineWidth: 1)
                            )
                    )
                    .shadow(color: factColor(for: index).opacity(0.06), radius: 8, y: 3)
                }
            }
            .padding(.horizontal, BQDesign.Spacing.lg)
        }
    }
    
    private func factColor(for index: Int) -> Color {
        let colors: [Color] = [
            BQDesign.Colors.primaryPurple,
            BQDesign.Colors.primaryOrange,
            BQDesign.Colors.primaryPink,
            BQDesign.Colors.challengeBlue,
            BQDesign.Colors.gold,
        ]
        return colors[index % colors.count]
    }
    
    // MARK: Admin Section (Organizer Only)
    var adminSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("🔧 Organizer Tools")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BQDesign.Spacing.lg)
            
            NavigationLink {
                AdminControlsView()
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("Open Admin Panel")
                        .font(BQDesign.Typography.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(BQDesign.Colors.primaryPurple)
                .padding(BQDesign.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                        .fill(BQDesign.Colors.primaryPurple.opacity(0.08))
                )
            }
            .padding(.horizontal, BQDesign.Spacing.lg)
        }
    }
    
    // MARK: Switch Character (Organizer Only)
    var switchCharacterButton: some View {
        Button {
            session.clearSession()
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Switch Character")
                    .font(BQDesign.Typography.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.red.opacity(0.7))
            .padding(BQDesign.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                    .fill(Color.red.opacity(0.06))
            )
        }
        .padding(.horizontal, BQDesign.Spacing.lg)
    }
}
