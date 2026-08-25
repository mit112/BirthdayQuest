import SwiftUI

struct RewardsCarouselView: View {
    
    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: RewardsViewModel
    @State private var scrolledID: Int?
    @State private var scrollViewWidth: CGFloat = 0
    @ScaledMetric private var giftEmojiSize: CGFloat = 60
    @ScaledMetric private var timelineArrowIconSize: CGFloat = 14

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: RewardsViewModel(eventId: eventId))
    }

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
            
            switch viewModel.contentState {
            case .loading:
                RewardsSkeletonView()
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
            viewModel.runMediaLifecycle(isCelebrant: event.isCelebrant, occasionDate: event.occasion?.occasionDate)
        }
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
                RewardContentSheet(
                    reward: reward,
                    eventId: event.eventId,
                    onDismiss: { viewModel.dismissContent() },
                    onReport: { await viewModel.reportReward(reward) }
                )
            }
        }
        .alert("Oops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
    }
}

// MARK: - Subviews

private extension RewardsCarouselView {
    
    var emptyState: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Text("🎁")
                .font(.system(size: giftEmojiSize))
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
            if let info = viewModel.expiryReminder {
                expiryReminderBanner(info)
            }

            // Header: Points
            PointsDisplayView(points: event.currentPoints, style: .large)
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
                            isAffordable: !reward.isUnlocked && event.currentPoints >= reward.pointCost
                        ) {
                            if reward.isUnlocked {
                                viewModel.justUnlockedReward = reward
                                viewModel.showUnlockedContent = true
                            } else if event.currentPoints >= reward.pointCost {
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
            // minHeight, not a fixed height: the cards inside grow with Dynamic Type, and a
            // fixed viewport would clip them.
            .frame(minHeight: 400)
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
                        event.navigateToTimeline()
                    }
                } label: {
                    HStack(spacing: BQDesign.Spacing.sm) {
                        Text("Check out your timeline")
                            .font(BQDesign.Typography.bodyBold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: timelineArrowIconSize, weight: .semibold))
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
        .animation(BQDesign.Animation.gentle, value: viewModel.expiryReminder)
    }

    func expiryReminderBanner(_ info: RewardsViewModel.ExpiryReminderInfo) -> some View {
        HStack(alignment: .top, spacing: BQDesign.Spacing.sm) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.goldText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text("\(info.unopenedMediaCount) gift\(info.unopenedMediaCount == 1 ? "" : "s") will expire soon")
                    .font(BQDesign.Typography.bodyBold)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                Text("Your gifts get tidied up after \(info.formattedDate). Open them to keep them on this device.")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.dismissExpiryReminder()
            } label: {
                Image(systemName: "xmark")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss reminder")
        }
        .padding(.leading, BQDesign.Spacing.md)
        .padding(.trailing, BQDesign.Spacing.xs)
        .padding(.vertical, BQDesign.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.lg)
                .fill(BQDesign.Colors.cardBackground)
                .shadow(
                    color: BQDesign.Shadows.card.color,
                    radius: BQDesign.Shadows.card.radius,
                    x: BQDesign.Shadows.card.x,
                    y: BQDesign.Shadows.card.y
                )
        )
        .padding(.horizontal, BQDesign.Spacing.md)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    func jumpToCenter() {
        let count = viewModel.rewards.count
        guard count > 0 else { return }
        let midStart = loopMultiplier / 2 * count
        scrolledID = midStart
    }
}
