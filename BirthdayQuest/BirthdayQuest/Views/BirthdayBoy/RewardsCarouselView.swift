import SwiftUI

struct RewardsCarouselView: View {
    
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel = RewardsViewModel()
    @State private var scrolledID: Int?
    @State private var scrollViewWidth: CGFloat = 0

    private let loopMultiplier = 5
    private let cardWidth: CGFloat = 260

    private var horizontalInset: CGFloat {
        let width = scrollViewWidth > 0 ? scrollViewWidth : 390
        return (width - cardWidth) / 2
    }
    
    private var loopedRewards: [Reward] {
        guard !viewModel.rewards.isEmpty else { return [] }
        return (0..<viewModel.rewards.count * loopMultiplier).map { i in
            viewModel.rewards[i % viewModel.rewards.count]
        }
    }
    
    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()
            
            if viewModel.isLoading {
                RewardsSkeletonView()
            } else if viewModel.rewards.isEmpty {
                emptyState
            } else {
                mainContent
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .confirmationDialog(
            "Unlock Gift",
            isPresented: $viewModel.showUnlockConfirm,
            titleVisibility: .visible
        ) {
            if let reward = viewModel.selectedReward {
                Button("Spend \(reward.pointCost) ✦ to unlock") {
                    Task { await viewModel.confirmUnlock() }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let reward = viewModel.selectedReward {
                Text("Unlock \(reward.fromName)'s gift?")
            }
        }
        .sheet(isPresented: $viewModel.showUnlockedContent) {
            if let reward = viewModel.justUnlockedReward {
                RewardContentSheet(reward: reward) {
                    viewModel.dismissContent()
                }
            }
        }
    }
}

// MARK: - Subviews

private extension RewardsCarouselView {
    
    var emptyState: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Text("🎁")
                .font(.system(size: 60))
            Text("No gifts yet")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
            Text("Your friends are preparing something special...")
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(BQDesign.Spacing.xl)
    }
    
    var mainContent: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            // Header: Points
            PointsDisplayView(points: session.currentPoints, style: .large)
                .padding(.top, BQDesign.Spacing.xl)
            
            Text("Your Gifts")
                .font(BQDesign.Typography.heroTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
            
            Spacer()
            
            // Infinite Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: BQDesign.Spacing.md) {
                    ForEach(Array(loopedRewards.enumerated()), id: \.offset) { index, reward in
                        RewardCardView(
                            reward: reward,
                            isAffordable: !reward.isUnlocked && session.currentPoints >= reward.pointCost
                        ) {
                            if reward.isUnlocked {
                                viewModel.justUnlockedReward = reward
                                viewModel.showUnlockedContent = true
                            } else if session.currentPoints >= reward.pointCost {
                                viewModel.requestUnlock(reward)
                            }
                        }
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledID)
            .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
            .frame(height: 400)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { scrollViewWidth = proxy.size.width }
            })
            .onAppear {
                jumpToCenter()
            }
            .onChange(of: viewModel.rewards.count) { _, _ in
                if scrolledID == nil { jumpToCenter() }
            }
            .onChange(of: scrolledID) { _, newID in
                // When near edges, silently jump back to center
                guard let newID = newID else { return }
                let count = viewModel.rewards.count
                guard count > 0 else { return }
                let totalCount = count * loopMultiplier
                let lowerBound = count * 2
                let upperBound = totalCount - count * 2
                if newID < lowerBound || newID > upperBound {
                    let currentIndex = newID % count
                    let midStart = loopMultiplier / 2 * count + currentIndex
                    Task { @MainActor in
                        scrolledID = midStart
                    }
                }
            }
            
            Spacer()
            
            // Progress footer
            Text("\(viewModel.unlockedCount) of \(viewModel.totalCount) gifts unlocked")
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textSecondary)
            
            // Timeline prompt (after unlock)
            if viewModel.showTimelinePrompt {
                Button {
                    viewModel.showTimelinePrompt = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        session.navigateToTimeline()
                    }
                } label: {
                    HStack(spacing: BQDesign.Spacing.sm) {
                        Text("Check out your timeline")
                            .font(BQDesign.Typography.bodyBold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, BQDesign.Spacing.lg)
                    .padding(.vertical, BQDesign.Spacing.md)
                    .background(
                        Capsule().fill(BQDesign.Colors.primaryGradient)
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Spacer().frame(height: BQDesign.Spacing.md)
        }
        .animation(BQDesign.Animation.smooth, value: viewModel.showTimelinePrompt)
    }
    
    func jumpToCenter() {
        let count = viewModel.rewards.count
        guard count > 0 else { return }
        let midStart = loopMultiplier / 2 * count
        scrolledID = midStart
    }
}
