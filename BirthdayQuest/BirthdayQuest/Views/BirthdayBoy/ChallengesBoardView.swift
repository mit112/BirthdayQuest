import SwiftUI

struct ChallengesBoardView: View {
    
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel = ChallengesViewModel()
    @State private var headerAppeared = false
    
    var body: some View {
        ZStack {
            // Living gradient background (matches timeline world)
            ChallengesBackgroundView()
            
            if viewModel.isLoading {
                ChallengesSkeletonView()
            } else if viewModel.regularChallenges.isEmpty {
                emptyState
            } else {
                mainContent
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .sheet(isPresented: $viewModel.showDetail) {
            if let challenge = viewModel.selectedChallenge {
                ChallengeDetailView(challenge: challenge) {
                    viewModel.showDetail = false
                }
            }
        }
        .sheet(isPresented: $viewModel.showSecretPortal) {
            SecretChallengesSheet(secrets: viewModel.deliveredSecrets) { secret in
                viewModel.showSecretPortal = false
                viewModel.selectChallenge(secret)
            }
        }
    }
}

// MARK: - Subviews

private extension ChallengesBoardView {
    
    var emptyState: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            ZStack {
                Circle()
                    .fill(BQDesign.Colors.primaryPurple.opacity(0.06))
                    .frame(width: 100, height: 100)
                Text("⚔️")
                    .font(.system(size: 60))
            }
            Text("No challenges yet")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
            Text("The adventure is being prepared...")
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.textSecondary)
        }
        .padding(BQDesign.Spacing.xl)
    }
    
    var mainContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                // Header with progress ring
                headerSection
                    .padding(.bottom, BQDesign.Spacing.xs)
                
                // Challenge cards with staggered entrance
                ForEach(Array(viewModel.regularChallenges.enumerated()), id: \.element.id) { index, challenge in
                    ChallengeCardView(
                        challenge: challenge,
                        index: index
                    ) {
                        viewModel.selectChallenge(challenge)
                    }
                }
                
                // Secret entry point
                SecretEntryCardView(
                    hasSecrets: viewModel.hasSecrets
                ) {
                    viewModel.discoverSecrets()
                }
                .padding(.top, BQDesign.Spacing.sm)
                
                Spacer().frame(height: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, BQDesign.Spacing.lg)
        }
    }
    
    // MARK: - Header
    
    var headerSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            PointsDisplayView(points: session.currentPoints, style: .large)
            
            Text("Challenges")
                .font(BQDesign.Typography.heroTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .opacity(headerAppeared ? 1 : 0)
            
            Text("\(viewModel.completedCount) of \(viewModel.totalRegular) completed")
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textSecondary)
                .opacity(headerAppeared ? 1 : 0)
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BQDesign.Colors.primaryPurple.opacity(0.1))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(BQDesign.Colors.primaryGradient)
                        .frame(width: geo.size.width * (headerAppeared ? progressFraction : 0), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, BQDesign.Spacing.xl)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1)) {
                headerAppeared = true
            }
        }
    }
    
    private var progressFraction: CGFloat {
        guard viewModel.totalRegular > 0 else { return 0 }
        return CGFloat(viewModel.completedCount) / CGFloat(viewModel.totalRegular)
    }
}

// MARK: - Challenges Background (warm gradient, lighter than timeline)

struct ChallengesBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "FBF7F4"), location: 0.0),
                    .init(color: Color(hex: "F8F2F0"), location: 0.25),
                    .init(color: Color(hex: "FFF5EE"), location: 0.5),
                    .init(color: Color(hex: "F5F0FA"), location: 0.75),
                    .init(color: Color(hex: "FBF7F4"), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Subtle sparkle field (fewer particles than timeline)
            SparkleFieldView()
                .opacity(0.4)
        }
        .ignoresSafeArea()
    }
}
