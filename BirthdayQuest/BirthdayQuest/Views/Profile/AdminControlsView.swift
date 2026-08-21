import SwiftUI

/// Host controls for one occasion.
/// Access from the Profile tab. Full game management while the occasion is live.
struct AdminControlsView: View {

    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: AdminViewModel
    @State private var pointsToAdd: String = ""

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: AdminViewModel(eventId: eventId))
    }

    private var gameState: GameState { event.gameState }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: BQDesign.Spacing.lg) {

                    // 0. Invite links + celebrant-joined status. Kept first: an occasion
                    // whose celebrant never installs the app is unrecoverable, so the host
                    // needs this the moment they open this screen, not after scrolling past
                    // everything else.
                    inviteCard

                    // 1. Read-only game state dashboard
                    gameStateCard
                    
                    // 2. Points management (existing)
                    pointsCard
                    
                    // 3. Force complete challenges (NEW)
                    forceChallengesCard
                    
                    // 4. Force unlock rewards (NEW)
                    forceRewardsCard
                    
                    // 5. Nuclear options: final badge
                    nuclearOptionsCard

                    // 5b. Roster
                    rosterCard
                    
                    // 6. Day counter + join toggle
                    dayAndJoinsCard
                    
                    Spacer().frame(height: BQDesign.Spacing.xxl)
                }
                .padding(BQDesign.Spacing.lg)
            }
            .background(BQDesign.Colors.background.ignoresSafeArea())
            .navigationTitle("🔧 Host")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if viewModel.isPerformingAction {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .overlay(ProgressView().tint(BQDesign.Colors.primaryPurple))
                        .allowsHitTesting(true)
                }
            }
            // Result alert
            .alert(
                viewModel.actionResult?.isError == true ? "Error" : "Done",
                isPresented: Binding(
                    get: { viewModel.actionResult != nil },
                    set: { if !$0 { viewModel.actionResult = nil } }
                )
            ) {
                Button("OK") { viewModel.actionResult = nil }
            } message: {
                Text(viewModel.actionResult?.message ?? "")
            }
            // Force complete confirmation
            .confirmationDialog(
                "Force Complete Challenge?",
                isPresented: Binding(
                    get: { viewModel.challengeToComplete != nil },
                    set: { if !$0 { viewModel.challengeToComplete = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let challenge = viewModel.challengeToComplete {
                    Button("Complete (+\(challenge.pointValue)✦, no proof)") {
                        Task { await viewModel.forceCompleteChallenge(challenge) }
                    }
                    Button("Cancel", role: .cancel) { viewModel.challengeToComplete = nil }
                }
            } message: {
                if let challenge = viewModel.challengeToComplete {
                    Text("Force complete \"\(challenge.title)\"? Awards \(challenge.pointValue)✦ with no proof upload.")
                }
            }
            // Force unlock confirmation
            .confirmationDialog(
                "Force Unlock Reward?",
                isPresented: Binding(
                    get: { viewModel.rewardToUnlock != nil },
                    set: { if !$0 { viewModel.rewardToUnlock = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let reward = viewModel.rewardToUnlock {
                    Button("Free Unlock (no points deducted)") {
                        Task { await viewModel.forceUnlockReward(reward, deductPoints: false) }
                    }
                    Button("Unlock & Deduct \(reward.pointCost)✦") {
                        Task { await viewModel.forceUnlockReward(reward, deductPoints: true) }
                    }
                    Button("Cancel", role: .cancel) { viewModel.rewardToUnlock = nil }
                }
            } message: {
                if let reward = viewModel.rewardToUnlock {
                    Text("Unlock \"\(reward.fromName)'s gift\" (\(reward.pointCost)✦)?")
                }
            }
            // Force final badge confirmation
            .confirmationDialog(
                "Trigger Final Celebration?",
                isPresented: $viewModel.showFinalBadgeConfirm,
                titleVisibility: .visible
            ) {
                Button("🎉 Trigger It", role: .destructive) {
                    Task { await viewModel.forceFinalBadge() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is the big moment. The final badge celebration will trigger for everyone. Make sure you're ready.")
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }
}

// MARK: - Section 0: Invite Links + Celebrant Status

private extension AdminControlsView {

    var celebrantLabel: String {
        event.occasion?.occasionType.celebrantLabel ?? "guest of honour"
    }

    /// The codes come from `viewModel.inviteCodes`, not from `event.occasion`: they live at
    /// `events/{id}/private/codes`, which only the host can read, because a member who could
    /// read the celebrant code could hand it to anyone and have them claim the celebrant role.
    var inviteCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Invite", icon: "square.and.arrow.up")

            if let codes = viewModel.inviteCodes {
                if let link = codes.contributorLink {
                    VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                        ShareLink(item: link) {
                            adminLinkRow("Share the friend link", icon: "person.2.fill")
                        }
                        Text(codes.contributorCode)
                            .font(BQDesign.Typography.captionSmall.monospaced())
                            .foregroundColor(BQDesign.Colors.textSecondary)
                    }
                }

                Divider()

                // A consumed celebrant code is blank, so there is no link left to build. Say
                // that, rather than silently rendering nothing: the code is single-use by
                // design and "the row vanished" is not an explanation.
                if let link = codes.celebrantLink {
                    ShareLink(item: link) {
                        adminLinkRow("Share the \(celebrantLabel) link", icon: "gift.fill")
                    }
                } else {
                    Text("The \(celebrantLabel) link has already been used — it only works once.")
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(BQDesign.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Loading your invite links…")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textSecondary)
            }

            celebrantStatusBanner
        }
        .adminCard()
    }

    func adminLinkRow(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(BQDesign.Colors.primaryPurple)
            Text(title)
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.primaryPurple)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BQDesign.Colors.textTertiary)
        }
    }

    /// The spec's #1 named risk: there is deliberately no handover mode, so a celebrant who
    /// never installs the app cannot be rescued on the day. Surfacing this unmissably, right
    /// where the invite links live, is the mitigation.
    var celebrantStatusBanner: some View {
        Group {
            if viewModel.celebrantHasJoined {
                Label(
                    "\(event.occasion?.celebrantName ?? "They") have joined.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundColor(BQDesign.Colors.success)
            } else {
                Label(
                    "\(event.occasion?.celebrantName ?? "They") haven't joined yet. "
                        + "Share the link above — they need the app installed to open their gifts.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundColor(BQDesign.Colors.error)
            }
        }
        .font(BQDesign.Typography.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Section 1: Game State Overview

private extension AdminControlsView {
    
    var gameStateCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Game Overview", icon: "chart.bar.fill")
            
            VStack(spacing: BQDesign.Spacing.xs) {
                adminRow("Points", "\(gameState.currentPoints) (earned: \(gameState.totalPointsEarned), spent: \(gameState.totalPointsSpent))")
                adminRow("Challenges", "\(gameState.challengesCompleted)/\(gameState.totalChallenges)")
                adminRow("Rewards", "\(gameState.rewardsUnlocked)/\(gameState.totalRewards)")
                adminRow("Secrets", "Found: \(gameState.secretChallengesFound), Done: \(gameState.secretChallengesCompleted)")
                adminRow("Day", "\(gameState.currentDay)")
                adminRow("Final Badge", gameState.finalBadgeUnlocked ? "✅ Unlocked" : "🔒 Locked")
            }
        }
        .adminCard()
    }
}

// MARK: - Section 2: Points Management

private extension AdminControlsView {
    
    var pointsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Points", icon: "star.fill")
            
            HStack(spacing: BQDesign.Spacing.sm) {
                TextField("Amount", text: $pointsToAdd)
                    .keyboardType(.numberPad)
                    .font(BQDesign.Typography.body)
                    .padding(BQDesign.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.sm)
                            .stroke(BQDesign.Colors.textTertiary.opacity(0.5))
                    )
                
                adminActionButton("Add", color: BQDesign.Colors.success) {
                    guard let amount = Int(pointsToAdd), amount > 0 else { return }
                    Task {
                        await viewModel.addPoints(amount)
                        pointsToAdd = ""
                    }
                }
                
                adminActionButton("Remove", color: BQDesign.Colors.secretAccent) {
                    guard let amount = Int(pointsToAdd), amount > 0 else { return }
                    Task {
                        await viewModel.removePoints(amount)
                        pointsToAdd = ""
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 3: Force Complete Challenges

private extension AdminControlsView {
    
    var forceChallengesCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Force Complete Challenge", icon: "bolt.fill")
            
            if viewModel.incompleteChallenges.isEmpty {
                adminEmptyState("✅ All challenges completed")
            } else {
                VStack(spacing: BQDesign.Spacing.sm) {
                    ForEach(viewModel.incompleteChallenges) { challenge in
                        HStack(spacing: BQDesign.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if challenge.isSecret {
                                        Image(systemName: "eye.slash.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(BQDesign.Colors.secretAccent)
                                    }
                                    Text(challenge.title)
                                        .font(BQDesign.Typography.caption)
                                        .foregroundColor(BQDesign.Colors.textPrimary)
                                        .lineLimit(1)
                                }
                                Text("\(challenge.pointValue)✦ · \(challenge.difficulty.rawValue)")
                                    .font(BQDesign.Typography.captionSmall)
                                    .foregroundColor(BQDesign.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            adminActionButton("Complete", color: BQDesign.Colors.challengeBlue) {
                                viewModel.challengeToComplete = challenge
                            }
                        }
                        .padding(BQDesign.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .fill(BQDesign.Colors.background)
                        )
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 4: Force Unlock Rewards

private extension AdminControlsView {
    
    var forceRewardsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Force Unlock Reward", icon: "gift.fill")
            
            if viewModel.lockedRewards.isEmpty {
                adminEmptyState("✅ All rewards unlocked")
            } else {
                VStack(spacing: BQDesign.Spacing.sm) {
                    ForEach(viewModel.lockedRewards) { reward in
                        HStack(spacing: BQDesign.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reward.fromName)
                                    .font(BQDesign.Typography.caption)
                                    .foregroundColor(BQDesign.Colors.textPrimary)
                                Text("\(reward.pointCost)✦ · \(reward.contentType.rawValue)")
                                    .font(BQDesign.Typography.captionSmall)
                                    .foregroundColor(BQDesign.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            adminActionButton("Unlock", color: BQDesign.Colors.gold) {
                                viewModel.rewardToUnlock = reward
                            }
                        }
                        .padding(BQDesign.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .fill(BQDesign.Colors.background)
                        )
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 5: Nuclear Options

private extension AdminControlsView {
    
    var nuclearOptionsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Nuclear Options", icon: "exclamationmark.triangle.fill")
            
            // Force Final Badge
            if !gameState.finalBadgeUnlocked {
                Button {
                    viewModel.showFinalBadgeConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Force Final Badge")
                            .font(BQDesign.Typography.bodyBold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(BQDesign.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                            .fill(BQDesign.Colors.primaryGradient)
                    )
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(BQDesign.Colors.success)
                    Text("Final badge already triggered")
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(BQDesign.Colors.textSecondary)
                }
            }
            
        }
        .adminCard()
    }

    var rosterCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Who's Here", icon: "person.2.fill")

            if viewModel.otherParticipants.isEmpty {
                adminEmptyState("Nobody else has joined yet. Share your invite link.")
            } else {
                VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                    ForEach(viewModel.otherParticipants) { participant in
                        HStack(spacing: BQDesign.Spacing.sm) {
                            AvatarView(avatarId: participant.avatarId, size: 28)
                            Text(participant.name)
                                .font(BQDesign.Typography.caption)
                                .foregroundColor(BQDesign.Colors.textPrimary)

                            if participant.isCelebrant {
                                Text("👑")
                                    .font(.system(size: 10))
                            }

                            Spacer()
                        }
                        .padding(BQDesign.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .fill(BQDesign.Colors.background)
                        )
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 6: Day Counter + Joins

private extension AdminControlsView {

    var isOpen: Bool { event.occasion?.isOpen ?? true }

    var dayAndJoinsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Day & Joins", icon: "calendar")
            
            // Day counter
            HStack(spacing: BQDesign.Spacing.sm) {
                Text("Current: Day \(gameState.currentDay)")
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                
                Spacer()
                
                adminActionButton("+ Day", color: BQDesign.Colors.primaryPurple) {
                    Task {
                        await viewModel.advanceDay(from: gameState.currentDay)
                    }
                }
            }
            
            Divider()

            // Open / close to new joins
            HStack(spacing: BQDesign.Spacing.sm) {
                Text(isOpen ? "Open to new joins" : "Closed to new joins")
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textPrimary)

                Spacer()

                adminActionButton(
                    isOpen ? "Close" : "Reopen",
                    color: BQDesign.Colors.secretAccent
                ) {
                    Task {
                        if await viewModel.setOpen(!isOpen) {
                            await event.refreshOccasion()
                        }
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Shared Admin UI Components

private extension AdminControlsView {
    
    func adminSectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: BQDesign.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BQDesign.Colors.primaryPurple)
            Text(text)
                .font(BQDesign.Typography.cardTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
        }
    }
    
    func adminRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(BQDesign.Typography.captionSmall)
                .foregroundColor(BQDesign.Colors.textPrimary)
        }
    }
    
    func adminActionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BQDesign.Typography.captionSmall)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, BQDesign.Spacing.md)
                .padding(.vertical, BQDesign.Spacing.sm)
                .background(Capsule().fill(color))
        }
    }
    
    func adminEmptyState(_ text: String) -> some View {
        Text(text)
            .font(BQDesign.Typography.caption)
            .foregroundColor(BQDesign.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, BQDesign.Spacing.sm)
    }
}

// MARK: - Admin Card Modifier

private extension View {
    func adminCard() -> some View {
        self
            .padding(BQDesign.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                    .fill(BQDesign.Colors.cardBackground)
            )
            .bqShadow(BQDesign.Shadows.card)
    }
}
