import SwiftUI

struct RewardsCarouselView: View {
    
    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: RewardsViewModel
    @State private var scrolledID: Int?
    @ScaledMetric private var scaledCardWidth: CGFloat = 260
    @ScaledMetric private var giftEmojiSize: CGFloat = 60
    @ScaledMetric private var timelineArrowIconSize: CGFloat = 14

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: RewardsViewModel(eventId: eventId))
    }

    private let loopMultiplier = 5
    private let baseCardWidth: CGFloat = 260

    /// A gift card's width, and with it the paging inset — one derivation, because
    /// `.viewAligned` only snaps cards to the centre while the two agree.
    ///
    /// It has to grow with Dynamic Type. At 260pt the unlocked card's "View" pill had ~164pt of
    /// room for a label that needs more than that at AX5, and "View" is a single word with no
    /// break opportunity, so it broke *mid-word* — "Vie / w".
    ///
    /// Two bounds, and the container one is what binds on a phone in portrait: 260pt scaled by
    /// the AX5 body factor is over 800pt, which is a page rather than a card, and an iPhone in
    /// landscape is wide enough to hand it that. 1.5x base is a judgement, not a measurement —
    /// it is a ceiling on absurdity, not the value any rendered layout depends on.
    private func cardWidth(in containerWidth: CGFloat) -> CGFloat {
        min(scaledCardWidth, baseCardWidth * 1.5, containerWidth - 2 * BQDesign.Spacing.lg)
    }

    private func horizontalInset(in containerWidth: CGFloat) -> CGFloat {
        (containerWidth - cardWidth(in: containerWidth)) / 2
    }
    
    private var loopedRewards: [Reward] {
        guard !viewModel.rewards.isEmpty else { return [] }
        return (0..<viewModel.rewards.count * loopMultiplier).map { i in
            viewModel.rewards[i % viewModel.rewards.count]
        }
    }
    
    /// Extracted from `body` so the scroll container above does not add its two nesting levels
    /// to an already heavily-modified `body` (this one carries six presentation modifiers) and
    /// push it over the SwiftUI type-checker's budget.
    @ViewBuilder
    private func contentBody(width: CGFloat) -> some View {
        switch viewModel.contentState {
        case .loading:
            RewardsSkeletonView()
        case .failed(let message):
            ContentFailureView(message: message)
        case .empty:
            emptyState
        case .ready:
            mainContent(width: width)
        }
    }

    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()

            // Somewhere to overflow *to*. `mainContent` is a plain VStack whose every element
            // grows with Dynamic Type — the points header, the hero title, the cards themselves
            // (their viewport is a `minHeight`, so they get taller, not clipped) and the footer —
            // and with no scroll container SwiftUI compresses them all instead. `minHeight` keeps
            // the two `Spacer()`s working, so the layout stays optically centred while it fits and
            // only scrolls once it doesn't.
            GeometryReader { proxy in
                ScrollView {
                    contentBody(width: proxy.size.width)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
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
    
    func mainContent(width: CGFloat) -> some View {
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
                            isAffordable: !reward.isUnlocked && event.currentPoints >= reward.pointCost,
                            width: cardWidth(in: width)
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
            .contentMargins(.horizontal, horizontalInset(in: width), for: .scrollContent)
            // minHeight, not a fixed height: the cards inside grow with Dynamic Type, and a
            // fixed viewport would clip them.
            .frame(minHeight: 400)
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
