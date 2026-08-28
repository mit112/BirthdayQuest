import SwiftUI

struct ChallengesBoardView: View {
    
    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: ChallengesViewModel
    @State private var headerAppeared = false
    @ScaledMetric private var emptyStateEmojiSize: CGFloat = 60

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: ChallengesViewModel(eventId: eventId))
    }
    
    var body: some View {
        ZStack {
            // Living gradient background (matches timeline world)
            ChallengesBackgroundView()
            
            switch viewModel.contentState {
            case .loading:
                ChallengesSkeletonView()
            case .failed(let message):
                ContentFailureView(message: message)
            case .empty:
                emptyState
            case .ready:
                mainContent
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .onChange(of: viewModel.contentState) { _, newState in
            guard newState == .ready || newState == .empty else { return }
            viewModel.runProofMediaLifecycle(isCelebrant: event.isCelebrant, occasionDate: event.occasion?.occasionDate)
        }
        .sheet(isPresented: $viewModel.showDetail) {
            if let challenge = viewModel.selectedChallenge {
                ChallengeDetailView(eventId: event.eventId, challenge: challenge) {
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
                    .font(.system(size: emptyStateEmojiSize))
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
            VStack(spacing: 14) {
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
            PointsDisplayView(points: event.currentPoints, style: .large)
            
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
            // Authored as a low-opacity brand tint *over* `background` rather than five fixed
            // pastel hexes, so the wash follows the appearance: the surface token carries the
            // scheme and the brand tokens only colour it. Same construction as
            // `TimelineBackgroundView`. Opacities were solved against the original stops, so
            // light resolves within ~6/255 of what it did before.
            //
            // The end stops are a brand token at zero alpha, not `.clear` — `.clear` is a
            // transparent *black*, and SwiftUI would interpolate the neighbours through it.
            LinearGradient(
                stops: [
                    .init(color: BQDesign.Colors.primaryOrange.opacity(0), location: 0.0),
                    .init(color: BQDesign.Colors.primaryOrange.opacity(0.026), location: 0.25),
                    .init(color: BQDesign.Colors.primaryOrange.opacity(0.039), location: 0.5),
                    .init(color: BQDesign.Colors.primaryPurple.opacity(0.047), location: 0.75),
                    .init(color: BQDesign.Colors.primaryPurple.opacity(0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .background(BQDesign.Colors.background)

        }
        .ignoresSafeArea()
    }
}
