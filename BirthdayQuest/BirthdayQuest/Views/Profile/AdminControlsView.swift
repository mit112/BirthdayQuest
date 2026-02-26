import SwiftUI
import FirebaseFirestore

/// Enhanced admin controls for the organizer (Mit).
/// Access from Profile tab. Full game management for live birthday weekend.
struct AdminControlsView: View {
    
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel = AdminViewModel()
    @State private var pointsToAdd: String = ""
    @State private var showResetConfirm = false
    
    private var gameState: GameState { session.gameState }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: BQDesign.Spacing.lg) {
                    
                    // 1. Read-only game state dashboard
                    gameStateCard
                    
                    // 2. Points management (existing)
                    pointsCard
                    
                    // 3. Force complete challenges (NEW)
                    forceChallengesCard
                    
                    // 4. Force unlock rewards (NEW)
                    forceRewardsCard
                    
                    // 5. Nuclear options: final badge + unclaim (NEW)
                    nuclearOptionsCard
                    
                    // 6. Day counter + reset (existing, reorganized)
                    dayAndResetCard
                    
                    Spacer().frame(height: BQDesign.Spacing.xxl)
                }
                .padding(BQDesign.Spacing.lg)
            }
            .background(BQDesign.Colors.background.ignoresSafeArea())
            .navigationTitle("🔧 Admin")
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
            // Unclaim confirmation
            .confirmationDialog(
                "Unclaim Character?",
                isPresented: Binding(
                    get: { viewModel.userToUnclaim != nil },
                    set: { if !$0 { viewModel.userToUnclaim = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let user = viewModel.userToUnclaim {
                    Button("Unclaim \(user.name)", role: .destructive) {
                        Task { await viewModel.unclaimCharacter(user) }
                    }
                    Button("Cancel", role: .cancel) { viewModel.userToUnclaim = nil }
                }
            } message: {
                if let user = viewModel.userToUnclaim {
                    Text("Remove \(user.name)'s character claim? They'll need to re-select on next app open.")
                }
            }
            // Reset own character
            .confirmationDialog("Reset Your Character?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { session.clearSession() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This takes you back to character select.")
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
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
                        try? await FirestoreService.shared.updateGameState([
                            "currentPoints": FieldValue.increment(Int64(amount)),
                            "totalPointsEarned": FieldValue.increment(Int64(amount))
                        ])
                        pointsToAdd = ""
                        BQDesign.Haptics.success()
                    }
                }
                
                adminActionButton("Remove", color: BQDesign.Colors.secretAccent) {
                    guard let amount = Int(pointsToAdd), amount > 0 else { return }
                    Task {
                        try? await FirestoreService.shared.updateGameState([
                            "currentPoints": FieldValue.increment(Int64(-amount))
                        ])
                        pointsToAdd = ""
                        BQDesign.Haptics.success()
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
            
            // Unclaim Characters
            if viewModel.claimedUsers.isEmpty {
                HStack {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundColor(BQDesign.Colors.textTertiary)
                    Text("No other characters claimed")
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(BQDesign.Colors.textSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                    Text("Unclaim Characters")
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(BQDesign.Colors.textSecondary)
                    
                    ForEach(viewModel.claimedUsers) { user in
                        HStack(spacing: BQDesign.Spacing.sm) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                                .foregroundColor(BQDesign.Colors.textSecondary)
                            Text(user.name)
                                .font(BQDesign.Typography.caption)
                                .foregroundColor(BQDesign.Colors.textPrimary)
                            
                            if user.role == .birthdayBoy {
                                Text("👑")
                                    .font(.system(size: 10))
                            }
                            
                            Spacer()
                            
                            adminActionButton("Unclaim", color: BQDesign.Colors.secretAccent) {
                                viewModel.userToUnclaim = user
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

// MARK: - Section 6: Day Counter + Reset

private extension AdminControlsView {
    
    var dayAndResetCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Day & Session", icon: "calendar")
            
            // Day counter
            HStack(spacing: BQDesign.Spacing.sm) {
                Text("Current: Day \(gameState.currentDay)")
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                
                Spacer()
                
                adminActionButton("+ Day", color: BQDesign.Colors.primaryPurple) {
                    Task {
                        try? await FirestoreService.shared.updateGameState([
                            "currentDay": gameState.currentDay + 1
                        ])
                        BQDesign.Haptics.success()
                    }
                }
            }
            
            Divider()
            
            // Reset own character
            Button {
                showResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Reset My Character")
                        .font(BQDesign.Typography.body)
                    Spacer()
                }
                .foregroundColor(BQDesign.Colors.secretAccent)
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
