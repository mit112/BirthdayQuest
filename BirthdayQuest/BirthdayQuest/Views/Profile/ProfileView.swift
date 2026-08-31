import SwiftUI

struct ProfileView: View {

    @EnvironmentObject private var event: EventSession
    @State private var appeared = false
    @State private var avatarGlow = false
    @StateObject private var viewModel: ProfileViewModel
    @Environment(\.bqMotionLevel) private var motionLevel
    @ScaledMetric private var occasionEmojiSize: CGFloat = 18
    @ScaledMetric private var chevronIconSize: CGFloat = 12

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(eventId: eventId))
    }

    private var participant: Participant? { event.participant }
    private var gameState: GameState { event.gameState }
    private var isCelebrant: Bool { event.isCelebrant }

    var body: some View {
        NavigationStack {
            ZStack {
                // Living gradient background
                ProfileBackgroundView(isCelebrant: isCelebrant)

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

                        // Occasion details
                        occasionSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)

                        // Host tools
                        if event.isHost {
                            adminSection
                        }

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
            if motionLevel.allowsPerpetual {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(0.3)) {
                    avatarGlow = true
                }
            }
            if !isCelebrant {
                loadSecretChallengeStatus()
            }
        }
        .onDisappear {
            if !isCelebrant {
                viewModel.stopListening()
            }
        }
    }
}

// MARK: - Profile Background

private struct ProfileBackgroundView: View {
    let isCelebrant: Bool

    var body: some View {
        ZStack {
            // Same construction as `TimelineBackgroundView`: a low-opacity brand tint over the
            // `background` token, so the page follows the appearance instead of being four fixed
            // pastels. The celebrant/contributor branch is preserved — it is now a choice of
            // *tint hue* (warm gold-orange for the celebrant, violet for a contributor) rather
            // than a choice of hex, and the opacities were solved against the original stops.
            LinearGradient(
                stops: [
                    .init(color: topTint, location: 0.0),
                    .init(color: BQDesign.Colors.primaryOrange.opacity(0), location: 0.3),
                    .init(color: BQDesign.Colors.primaryOrange.opacity(0.03), location: 0.6),
                    .init(color: bottomTint, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .background(BQDesign.Colors.background)

            SparkleFieldView()
                .opacity(0.3)
        }
        .ignoresSafeArea()
    }

    private var topTint: Color {
        isCelebrant
            ? BQDesign.Colors.primaryOrange.opacity(0.02)
            : BQDesign.Colors.primaryPurple.opacity(0.06)
    }

    private var bottomTint: Color {
        isCelebrant
            ? BQDesign.Colors.primaryOrange.opacity(0.11)
            : BQDesign.Colors.primaryPurple.opacity(0.085)
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
                            colors: isCelebrant
                                ? [BQDesign.Colors.gold.opacity(avatarGlow ? 0.25 : 0.08), BQDesign.Colors.gold.opacity(0)]
                                : [BQDesign.Colors.primaryPurple.opacity(avatarGlow ? 0.2 : 0.06), BQDesign.Colors.primaryPurple.opacity(0)],
                            center: .center,
                            startRadius: 50,
                            endRadius: 100
                        )
                    )
                    .frame(width: 180, height: 180)

                // Outer decorative ring
                Circle()
                    .stroke(
                        isCelebrant
                            ? BQDesign.Colors.gold.opacity(0.2)
                            : BQDesign.Colors.primaryPurple.opacity(0.15),
                        lineWidth: 1.5
                    )
                    .frame(width: 140, height: 140)

                // Avatar background circle
                Circle()
                    .fill(
                        isCelebrant
                        ? BQDesign.Colors.goldGradient
                        : BQDesign.Colors.primaryGradient
                    )
                    .frame(width: 128, height: 128)
                    .overlay(
                        // The surface colour, not white: the ring's job is to cut the gradient
                        // disc away from the page, and `cardBackground` is what does that in both
                        // appearances — byte-identical white in light, and a dark rim in dark,
                        // where a white one would bloom against a #15131C page.
                        Circle().stroke(BQDesign.Colors.cardBackground, lineWidth: 3)
                    )
                    .shadow(
                        color: isCelebrant
                            ? BQDesign.Colors.gold.opacity(0.3)
                            : BQDesign.Colors.primaryPurple.opacity(0.2),
                        radius: 12, y: 4
                    )
                    .shadow(
                        color: isCelebrant
                            ? BQDesign.Colors.gold.opacity(0.15)
                            : BQDesign.Colors.primaryPurple.opacity(0.1),
                        radius: 24, y: 8
                    )

                AvatarView(
                    avatarId: participant?.avatarId ?? AvatarCatalog.fallback,
                    size: 118,
                    showsCrown: isCelebrant
                )
            }

            // Name
            Text(participant?.name ?? "Guest")
                .font(BQDesign.Typography.heroTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)

            // Role badge
            Text(roleBadge)
                .font(BQDesign.Typography.caption)
                .foregroundColor(isCelebrant ? BQDesign.Colors.gold : BQDesign.Colors.primaryPurple)
                .padding(.horizontal, BQDesign.Spacing.md)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isCelebrant
                        ? BQDesign.Colors.gold.opacity(0.12)
                        : BQDesign.Colors.primaryPurple.opacity(0.1)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        isCelebrant
                            ? BQDesign.Colors.gold.opacity(0.15)
                            : BQDesign.Colors.primaryPurple.opacity(0.1),
                        lineWidth: 1
                    )
                )
        }
    }

    /// Role comes from the occasion, not from a hardcoded character sheet — a graduation's
    /// guest of honour should not be labelled "Birthday Boy".
    var roleBadge: String {
        let celebrantLabel = event.occasion?.occasionType.celebrantLabel ?? "Guest of Honour"
        if isCelebrant { return event.isHost ? "\(celebrantLabel) · Host" : celebrantLabel }
        return event.isHost ? "Host" : "Friend"
    }

    // MARK: Stats Section
    var statsSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("Stats")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BQDesign.Spacing.lg)

            if isCelebrant {
                celebrantStats
            } else {
                contributorStats
            }
        }
    }

    var celebrantStats: some View {
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

    var contributorStats: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(icon: "🕵️", value: viewModel.secretChallengeStatus.rawValue, label: "Secret Dare", color: BQDesign.Colors.secretAccent, index: 0)
                StatCard(icon: "🎁", value: "\(gameState.rewardsUnlocked)/\(gameState.totalRewards)", label: "Gifts Unlocked", color: BQDesign.Colors.primaryPink, index: 1)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.error)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, BQDesign.Spacing.lg)
    }

    // MARK: Occasion
    var occasionSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("This Occasion")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BQDesign.Spacing.lg)

            VStack(spacing: 10) {
                occasionRow("🎊", event.occasion?.name ?? "—")
                occasionRow("🗓", event.occasion.map { $0.occasionDate.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                occasionRow("👑", event.celebrantName)
            }
            .padding(.horizontal, BQDesign.Spacing.lg)
        }
    }

    func occasionRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BQDesign.Colors.primaryPurple.opacity(0.1))
                    .frame(width: 38, height: 38)

                Text(emoji)
                    .font(.system(size: occasionEmojiSize))
            }

            Text(text)
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BQDesign.Colors.primaryPurple.opacity(0.08), lineWidth: 1)
                )
        )
        .bqShadow(BQDesign.Shadows.card)
    }

    // MARK: - Secret Challenge Status (Contributors)

    func loadSecretChallengeStatus() {
        guard let userId = participant?.id else { return }
        viewModel.startListening(userId: userId)
    }

    // MARK: Host Tools
    var adminSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("🔧 Host Tools")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BQDesign.Spacing.lg)

            NavigationLink {
                AdminControlsView(eventId: event.eventId)
                    .environmentObject(event)
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("Open Host Panel")
                        .font(BQDesign.Typography.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: chevronIconSize, weight: .semibold))
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
}
