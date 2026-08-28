import SwiftUI
import ConfettiSwiftUI

struct TimelineView: View {
    
    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: TimelineViewModel
    @State private var confettiTrigger = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var headerAppeared = false
    @State private var crownBounce = false
    @State private var scrollOffset: CGFloat = 0

    // Node tap → detail sheets
    @State private var selectedChallenge: Challenge?
    @State private var selectedReward: Reward?
    @State private var isLoadingDetail = false

    @ScaledMetric private var headerCrownSize: CGFloat = 44
    @ScaledMetric private var emptyStateMapGlyphSize: CGFloat = 48

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: TimelineViewModel(eventId: eventId))
    }
    
    var body: some View {
        ZStack {
            // Layer 1 & 2: Living gradient + bokeh + sparkles
            TimelineBackgroundView()
            
            switch viewModel.contentState {
            case .loading:
                TimelineSkeletonView()
            case .failed(let message):
                // Replaces the whole scroll rather than just the path. Keeping the header
                // and the final-badge progress around a failure notice would frame the
                // screen as working, with one apologetic paragraph where the journey was.
                ContentFailureView(message: message)
            case .empty, .ready:
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
        .onChange(of: event.gameState.finalBadgeUnlocked) { _, unlocked in
            if unlocked { viewModel.updateFinalBadge(from: event.gameState) }
        }
        .onChange(of: viewModel.showFinalCelebration) { _, show in
            if show { confettiTrigger += 1; BQDesign.Haptics.success() }
        }
        .onChange(of: event.scrollToLatestTimeline) { _, shouldScroll in
            if shouldScroll {
                event.scrollToLatestTimeline = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    if let lastId = viewModel.events.last?.id {
                        withAnimation(BQDesign.Animation.smooth) {
                            scrollProxy?.scrollTo(lastId, anchor: .center)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedChallenge) { challenge in
            ChallengeDetailView(
                eventId: event.eventId,
                challenge: challenge,
                onDismiss: { selectedChallenge = nil }
            )
                .environmentObject(event)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $selectedReward) { reward in
            if reward.isUnlocked {
                RewardContentSheet(reward: reward, eventId: event.eventId, onDismiss: { selectedReward = nil }, onReport: nil)
                    .environmentObject(event)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }
    
    // MARK: - Node Tap Handler
    
    private func handleNodeTap(_ node: TimelineEvent) {
        guard !isLoadingDetail else { return }
        isLoadingDetail = true
        
        Task {
            defer { isLoadingDetail = false }

            switch await viewModel.detail(for: node) {
            case .challenge(let challenge):
                selectedChallenge = challenge
            case .reward(let reward):
                selectedReward = reward
            case nil:
                break
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
                        progressText: "\(event.gameState.rewardsUnlocked)/\(event.gameState.totalRewards) gifts unlocked",
                        progressFraction: event.gameState.totalRewards > 0
                            ? Double(event.gameState.rewardsUnlocked) / Double(event.gameState.totalRewards)
                            : 0
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
            ForEach(Array(viewModel.events.enumerated()), id: \.element.id) { index, node in
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
                        event: node,
                        isNew: viewModel.isNewEvent(node),
                        index: index,
                        totalCount: viewModel.events.count,
                        onTap: { handleNodeTap(node) }
                    )
                    .id(node.id)
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
    @Environment(\.bqMotionLevel) private var motionLevel

    // Decorative sparkle glyph; one size per index%3 slot since the original picked
    // from a fixed array rather than a single literal.
    @ScaledMetric private var sparkleGlyphSizeA: CGFloat = 7
    @ScaledMetric private var sparkleGlyphSizeB: CGFloat = 6
    @ScaledMetric private var sparkleGlyphSizeC: CGFloat = 8

    private let height: CGFloat = 60
    
    // Trail colors cycle through the palette
    private var trailColor: Color {
        // Tints of the palette's own hues, not six fixed pastels. The call sites multiply this
        // (`.opacity(0.6)` completed, `0.25` pending, `0.2` glow — `Color.opacity` multiplies),
        // and each base was solved so the *completed* light composite lands within a few units of
        // the pastel it replaces. Doing it with tokens matters more here than it looks: a pale
        // fixed pastel is a barely-there wash on a cream page and a bright line on a near-black
        // one, so the hardcoded version did not degrade in dark, it shouted. Tinting a token
        // keeps the trail equally faint in both, which is the intent — the completed state is
        // carried by the node badges, not by this.
        let colors: [Color] = [
            BQDesign.Colors.primaryPurple.opacity(0.32),   // lavender
            BQDesign.Colors.challengeBlue.opacity(0.41),   // sky
            BQDesign.Colors.primaryOrange.opacity(0.35),   // peach
            BQDesign.Colors.primaryPink.opacity(0.38),     // rose
            BQDesign.Colors.success.opacity(0.32),         // mint
            BQDesign.Colors.primaryPurple.opacity(0.25),   // soft purple
        ]
        return colors[index % colors.count]
    }
    
    // Sparkle colors
    private var sparkleColor: Color {
        let colors: [Color] = [
            BQDesign.Colors.gold,
            BQDesign.Colors.primaryPurple,
            BQDesign.Colors.primaryPink,
            // `4CD964` was the literal light value of `success`; the token is an exact swap.
            BQDesign.Colors.success,
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
            if isCompleted && motionLevel.allowsPerpetual {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    shimmer = 1.3
                }
            }
        }
    }

    private var sparkleDecoration: some View {
        let midX = (xPosition(for: fromAlignment) + xPosition(for: toAlignment)) / 2
        let sparkleGlyphSize = [sparkleGlyphSizeA, sparkleGlyphSizeB, sparkleGlyphSizeC][index % 3]
        return GeometryReader { geo in
            Image(systemName: ["sparkle", "star.fill", "sparkle"][index % 3])
                .font(.system(size: sparkleGlyphSize, weight: .bold))
                .foregroundStyle(sparkleColor.opacity(0.5))
                .position(x: midX * geo.size.width, y: height * 0.5)
                .opacity(drawn ? 1 : 0)
        }
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
                .font(.system(size: headerCrownSize))
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
                    .font(.system(size: emptyStateMapGlyphSize))
            }
            
            VStack(spacing: BQDesign.Spacing.sm) {
                Text("Your journey begins...")
                    .font(BQDesign.Typography.sectionTitle)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                Text("Complete challenges & unlock rewards\nto fill this path")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer().frame(height: BQDesign.Spacing.xxl)
        }
    }
}
