import SwiftUI
import ConfettiSwiftUI

struct TimelineView: View {
    
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel = TimelineViewModel()
    @State private var confettiTrigger = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var headerAppeared = false
    @State private var crownBounce = false
    @State private var scrollOffset: CGFloat = 0
    
    // Node tap → detail sheets
    @State private var selectedChallenge: Challenge?
    @State private var selectedReward: Reward?
    @State private var showChallengeDetail = false
    @State private var showRewardContent = false
    @State private var isLoadingDetail = false
    
    var body: some View {
        ZStack {
            // Layer 1 & 2: Living gradient + bokeh + sparkles
            TimelineBackgroundView()
            
            if viewModel.isLoading {
                TimelineSkeletonView()
            } else {
                mainContent
            }
            
            Color.clear
                .confettiCannon(
                    trigger: $confettiTrigger, num: 120,
                    colors: [
                        Color(hex: "F5A623"), Color(hex: "7C5CFC"),
                        Color(hex: "FF6B9D"), Color(hex: "FFA45B"), Color(hex: "4CD964")
                    ],
                    rainHeight: 700, radius: 500
                )
                .allowsHitTesting(false)
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .onChange(of: session.gameState.finalBadgeUnlocked) { _, unlocked in
            if unlocked { viewModel.updateFinalBadge(from: session.gameState) }
        }
        .onChange(of: viewModel.showFinalCelebration) { _, show in
            if show { confettiTrigger += 1; BQDesign.Haptics.success() }
        }
        .onChange(of: session.scrollToLatestTimeline) { _, shouldScroll in
            if shouldScroll {
                session.scrollToLatestTimeline = false
                // Small delay ensures ScrollViewProxy and layout are ready after tab switch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let lastId = viewModel.events.last?.id {
                        withAnimation(BQDesign.Animation.smooth) {
                            scrollProxy?.scrollTo(lastId, anchor: .center)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showChallengeDetail) {
            if let challenge = selectedChallenge {
                ChallengeDetailView(challenge: challenge, onDismiss: { showChallengeDetail = false })
                    .environmentObject(session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
        .sheet(isPresented: $showRewardContent) {
            if let reward = selectedReward, reward.isUnlocked {
                RewardContentSheet(reward: reward, onDismiss: { showRewardContent = false })
                    .environmentObject(session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }
    
    // MARK: - Node Tap Handler
    
    private func handleNodeTap(_ event: TimelineEvent) {
        guard !isLoadingDetail else { return }
        isLoadingDetail = true
        
        Task {
            defer { isLoadingDetail = false }
            
            switch event.type {
            case .challengeCompleted:
                if let challenge = try? await FirestoreService.shared.fetchChallenge(byId: event.referenceId) {
                    selectedChallenge = challenge
                    showChallengeDetail = true
                }
            case .rewardUnlocked:
                if let reward = try? await FirestoreService.shared.fetchReward(byId: event.referenceId) {
                    selectedReward = reward
                    showRewardContent = true
                }
            }
        }
    }
}

// MARK: - Main Content

private extension TimelineView {
    
    var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    
                    if viewModel.isEmpty {
                        emptyState
                    } else {
                        timelinePathContent
                    }
                    
                    FinalBadgeView(
                        isUnlocked: viewModel.finalBadgeUnlocked,
                        progressText: viewModel.rewardProgress,
                        progressFraction: viewModel.progressFraction
                    )
                    .id("finalBadge")
                    .padding(.top, 20)
                    
                    Spacer().frame(height: 120)
                }
            }
            .onChange(of: viewModel.events.count) { oldCount, newCount in
                if newCount > oldCount, let lastId = viewModel.events.last?.id {
                    withAnimation(BQDesign.Animation.smooth) {
                        proxy.scrollTo(lastId, anchor: .center)
                    }
                }
            }
            .onAppear { scrollProxy = proxy }
        }
    }
}

// MARK: - Timeline Path Content (S-curve winding path with bezier connectors)

private extension TimelineView {
    
    /// 6-position organic S-curve wave. Wider swing for a more dramatic path.
    func nodeAlignment(for index: Int) -> HorizontalAlignment {
        let pattern: [HorizontalAlignment] = [
            .leading, .center, .trailing, .center, .leading, .trailing
        ]
        return pattern[index % pattern.count]
    }
    
    /// Horizontal padding to create the winding effect
    func nodePadding(for index: Int) -> (leading: CGFloat, trailing: CGFloat) {
        let positions: [(CGFloat, CGFloat)] = [
            (30, 130),    // left
            (85, 85),     // center
            (130, 30),    // right
            (70, 100),    // center-left
            (35, 135),    // left
            (120, 50),    // right-ish
        ]
        return positions[index % positions.count]
    }
    
    var timelinePathContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.events.enumerated()), id: \.element.id) { index, event in
                VStack(spacing: 0) {
                    // Bezier connector trail
                    if index > 0 {
                        BezierTrailConnector(
                            fromAlignment: nodeAlignment(for: index - 1),
                            toAlignment: nodeAlignment(for: index),
                            index: index,
                            isCompleted: true
                        )
                    }
                    
                    // The node
                    let padding = nodePadding(for: index)
                    
                    TimelineNodeView(
                        event: event,
                        isNew: viewModel.isNewEvent(event),
                        index: index,
                        totalCount: viewModel.events.count,
                        onTap: { handleNodeTap(event) }
                    )
                    .id(event.id)
                    .padding(.leading, padding.leading)
                    .padding(.trailing, padding.trailing)
                }
            }
            
            // Trail connector to final badge
            if !viewModel.events.isEmpty {
                BezierTrailConnector(
                    fromAlignment: nodeAlignment(for: viewModel.events.count - 1),
                    toAlignment: .center,
                    index: viewModel.events.count,
                    isCompleted: false
                )
            }
        }
        .padding(.top, BQDesign.Spacing.md)
    }
}

// MARK: - Bezier Trail Connector (organic curved lines between nodes)

struct BezierTrailConnector: View {
    let fromAlignment: HorizontalAlignment
    let toAlignment: HorizontalAlignment
    let index: Int
    let isCompleted: Bool
    
    @State private var drawn = false
    @State private var shimmer: CGFloat = -0.3
    
    private let height: CGFloat = 60
    
    // Trail colors cycle through the palette
    private var trailColor: Color {
        let colors: [Color] = [
            Color(hex: "D4C5FC"),  // lavender
            Color(hex: "B8D4F0"),  // sky
            Color(hex: "FFE0B2"),  // peach
            Color(hex: "F5C6D0"),  // rose
            Color(hex: "C5E8D4"),  // mint
            Color(hex: "DDD0F8"),  // soft purple
        ]
        return colors[index % colors.count]
    }
    
    // Sparkle colors
    private var sparkleColor: Color {
        let colors: [Color] = [
            BQDesign.Colors.gold,
            BQDesign.Colors.primaryPurple,
            BQDesign.Colors.primaryPink,
            Color(hex: "4CD964"),
        ]
        return colors[index % colors.count]
    }
    
    var body: some View {
        ZStack {
            // The curved trail
            CurvedTrailShape(
                fromX: xPosition(for: fromAlignment),
                toX: xPosition(for: toAlignment)
            )
            .stroke(
                trailColor.opacity(isCompleted ? 0.6 : 0.25),
                style: StrokeStyle(
                    lineWidth: isCompleted ? 4 : 2.5,
                    lineCap: .round
                )
            )
            .frame(height: height)
            
            // Glow underneath for completed sections
            if isCompleted {
                CurvedTrailShape(
                    fromX: xPosition(for: fromAlignment),
                    toX: xPosition(for: toAlignment)
                )
                .stroke(
                    trailColor.opacity(0.2),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .blur(radius: 4)
                .frame(height: height)
            }
            
            // Decorative sparkle at midpoint
            if isCompleted {
                sparkleDecoration
            }
        }
        .opacity(drawn ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(Double(index) * 0.05)) {
                drawn = true
            }
            if isCompleted {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    shimmer = 1.3
                }
            }
        }
    }
    
    private var sparkleDecoration: some View {
        let midX = (xPosition(for: fromAlignment) + xPosition(for: toAlignment)) / 2
        return Image(systemName: ["sparkle", "star.fill", "sparkle"][index % 3])
            .font(.system(size: [7, 6, 8][index % 3], weight: .bold))
            .foregroundStyle(sparkleColor.opacity(0.5))
            .position(x: midX * UIScreen.main.bounds.width, y: height * 0.5)
            .opacity(drawn ? 1 : 0)
    }
    
    private func xPosition(for alignment: HorizontalAlignment) -> CGFloat {
        switch alignment {
        case .leading: return 0.25
        case .trailing: return 0.75
        default: return 0.5
        }
    }
}

// MARK: - Curved Trail Shape (bezier between two X positions)

struct CurvedTrailShape: Shape {
    let fromX: CGFloat  // 0...1 fraction
    let toX: CGFloat    // 0...1 fraction
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startX = fromX * rect.width
        let endX = toX * rect.width
        let midY = rect.height * 0.5
        
        // Control points create a smooth S-curve
        let cp1 = CGPoint(x: startX, y: midY)
        let cp2 = CGPoint(x: endX, y: midY)
        
        path.move(to: CGPoint(x: startX, y: 0))
        path.addCurve(
            to: CGPoint(x: endX, y: rect.height),
            control1: cp1,
            control2: cp2
        )
        return path
    }
}

// MARK: - Header

private extension TimelineView {
    
    var header: some View {
        VStack(spacing: BQDesign.Spacing.xs) {
            Text("👑")
                .font(.system(size: 44))
                .scaleEffect(crownBounce ? 1.0 : 0.85)
                .offset(y: crownBounce ? 0 : 5)
                .opacity(headerAppeared ? 1 : 0)
            
            Text("The Journey")
                .font(BQDesign.Typography.heroTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .opacity(headerAppeared ? 1 : 0)
            
            if !viewModel.isEmpty {
                Text("\(viewModel.events.count) moments captured")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                    .opacity(headerAppeared ? 1 : 0)
            }
        }
        .padding(.bottom, BQDesign.Spacing.md)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) {
                headerAppeared = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.2)) {
                crownBounce = true
            }
        }
    }
    
    var emptyState: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            Spacer().frame(height: BQDesign.Spacing.xxl * 2)
            
            ZStack {
                Circle()
                    .fill(BQDesign.Colors.primaryPurple.opacity(0.06))
                    .frame(width: 100, height: 100)
                
                Text("🗺️")
                    .font(.system(size: 48))
            }
            
            VStack(spacing: BQDesign.Spacing.sm) {
                Text("Your journey begins...")
                    .font(BQDesign.Typography.sectionTitle)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                Text("Complete challenges & unlock rewards\nto fill this path")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer().frame(height: BQDesign.Spacing.xxl)
        }
    }
}
