import SwiftUI
import FirebaseFirestore

/// Hidden admin controls for the organizer (Mit).
/// Access from Profile tab. Allows managing game state.
struct AdminControlsView: View {
    
    @EnvironmentObject private var session: SessionManager
    @State private var pointsToAdd: String = ""
    @State private var showResetConfirm = false
    @State private var actionMessage: String?
    @State private var showMessage = false
    
    private var gameState: GameState { session.gameState }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: BQDesign.Spacing.lg) {
                    
                    // Game state overview
                    gameStateCard
                    
                    // Points management
                    pointsCard
                    
                    // Day management
                    dayCard
                    
                    // Danger zone
                    dangerZone
                    
                    Spacer().frame(height: BQDesign.Spacing.xxl)
                }
                .padding(BQDesign.Spacing.lg)
            }
            .background(BQDesign.Colors.background.ignoresSafeArea())
            .navigationTitle("🔧 Admin")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Done", isPresented: $showMessage) {
                Button("OK") {}
            } message: {
                Text(actionMessage ?? "")
            }
            .confirmationDialog("Reset Everything?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset Character Selection", role: .destructive) {
                    session.clearSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will take you back to the character select screen.")
            }
        }
    }
}

// MARK: - Subviews

private extension AdminControlsView {
    
    var gameStateCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            sectionHeader("Game Overview")
            
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
    
    var pointsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            sectionHeader("Points Management")
            
            HStack(spacing: BQDesign.Spacing.sm) {
                TextField("Amount", text: $pointsToAdd)
                    .keyboardType(.numberPad)
                    .font(BQDesign.Typography.body)
                    .padding(BQDesign.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: BQDesign.Radius.sm).stroke(Color.gray.opacity(0.3)))
                
                adminButton("Add", color: BQDesign.Colors.success) {
                    guard let amount = Int(pointsToAdd), amount > 0 else { return }
                    Task {
                        try? await FirestoreService.shared.updateGameState([
                            "currentPoints": FirebaseFirestore.FieldValue.increment(Int64(amount)),
                            "totalPointsEarned": FirebaseFirestore.FieldValue.increment(Int64(amount))
                        ])
                        pointsToAdd = ""
                        showResult("Added ✦\(amount)")
                    }
                }
                
                adminButton("Remove", color: BQDesign.Colors.secretAccent) {
                    guard let amount = Int(pointsToAdd), amount > 0 else { return }
                    Task {
                        try? await FirestoreService.shared.updateGameState([
                            "currentPoints": FirebaseFirestore.FieldValue.increment(Int64(-amount))
                        ])
                        pointsToAdd = ""
                        showResult("Removed ✦\(amount)")
                    }
                }
            }
        }
        .adminCard()
    }
    
    var dayCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            sectionHeader("Day Counter")
            
            HStack(spacing: BQDesign.Spacing.sm) {
                Text("Current: Day \(gameState.currentDay)")
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                
                Spacer()
                
                adminButton("+ Day", color: BQDesign.Colors.primaryPurple) {
                    Task {
                        try? await FirestoreService.shared.updateGameState([
                            "currentDay": gameState.currentDay + 1
                        ])
                        showResult("Advanced to Day \(gameState.currentDay + 1)")
                    }
                }
            }
        }
        .adminCard()
    }
    
    var dangerZone: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            sectionHeader("Danger Zone")
            
            Button {
                showResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Reset Character Selection")
                        .font(BQDesign.Typography.body)
                }
                .foregroundColor(BQDesign.Colors.secretAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .adminCard()
    }
    
    // MARK: Helpers
    
    func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(BQDesign.Typography.cardTitle)
            .foregroundColor(BQDesign.Colors.textPrimary)
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
    
    func adminButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
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
    
    func showResult(_ message: String) {
        actionMessage = message
        showMessage = true
        BQDesign.Haptics.success()
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
