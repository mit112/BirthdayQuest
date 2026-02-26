import SwiftUI

// MARK: - Shimmer Effect Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, phase - 0.3)),
                            .init(color: Color.white.opacity(0.35), location: phase),
                            .init(color: .clear, location: min(1, phase + 0.3)),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: width * 2.5)
                    .offset(x: -width * 0.75)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.8)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 2.0
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Primitives

struct SkeletonRect: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var radius: CGFloat = 8
    
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(BQDesign.Colors.textTertiary.opacity(0.15))
            .frame(width: width, height: height)
    }
}

struct SkeletonCircle: View {
    var size: CGFloat = 52
    
    var body: some View {
        Circle()
            .fill(BQDesign.Colors.textTertiary.opacity(0.15))
            .frame(width: size, height: size)
    }
}

// MARK: - Rewards Carousel Skeleton

struct RewardsSkeletonView: View {
    var body: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            // Points placeholder
            SkeletonRect(width: 100, height: 36, radius: 18)
                .padding(.top, BQDesign.Spacing.xl)
            
            // Title placeholder
            SkeletonRect(width: 130, height: 28, radius: 10)
            
            Spacer()
            
            // Fake carousel — 3 ghost cards
            HStack(spacing: BQDesign.Spacing.md) {
                ForEach(0..<3, id: \.self) { i in
                    rewardCardSkeleton
                        .opacity(i == 1 ? 1.0 : 0.5)
                        .scaleEffect(i == 1 ? 1.0 : 0.92)
                }
            }
            .frame(height: 380)
            
            Spacer()
            
            // Footer placeholder
            SkeletonRect(width: 170, height: 14, radius: 7)
            
            Spacer().frame(height: BQDesign.Spacing.md)
        }
        .shimmer()
    }
    
    private var rewardCardSkeleton: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Spacer()
            
            SkeletonCircle(size: 80)
            
            SkeletonRect(width: 90, height: 12, radius: 6)
            
            SkeletonRect(width: 120, height: 20, radius: 8)
            
            SkeletonRect(width: 150, height: 12, radius: 6)
            
            Spacer()
            
            SkeletonRect(width: 80, height: 32, radius: 16)
            
            Spacer().frame(height: BQDesign.Spacing.lg)
        }
        .frame(width: 260, height: 380)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.xxl, style: .continuous)
                .fill(Color(hex: "F5F3F8").opacity(0.6))
        )
    }
}

// MARK: - Challenges Board Skeleton

struct ChallengesSkeletonView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // Header
                VStack(spacing: BQDesign.Spacing.sm) {
                    SkeletonRect(width: 100, height: 36, radius: 18)
                    SkeletonRect(width: 130, height: 28, radius: 10)
                    SkeletonRect(width: 160, height: 14, radius: 7)
                    SkeletonRect(height: 6, radius: 3)
                        .padding(.horizontal, BQDesign.Spacing.xl)
                }
                .padding(.bottom, BQDesign.Spacing.xs)
                
                // 5 ghost cards
                ForEach(0..<5, id: \.self) { i in
                    challengeCardSkeleton
                        .opacity(1.0 - Double(i) * 0.1)
                }
                
                Spacer().frame(height: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, BQDesign.Spacing.lg)
        }
        .shimmer()
    }
    
    private var challengeCardSkeleton: some View {
        HStack(spacing: 14) {
            // Illustration circle
            SkeletonCircle(size: 52)
            
            // Text block
            VStack(alignment: .leading, spacing: 6) {
                SkeletonRect(width: 140, height: 16, radius: 6)
                SkeletonRect(width: 200, height: 12, radius: 5)
                
                HStack(spacing: 8) {
                    SkeletonRect(width: 40, height: 10, radius: 4)
                    SkeletonRect(width: 30, height: 10, radius: 4)
                    SkeletonRect(width: 16, height: 10, radius: 4)
                }
            }
            
            Spacer()
            
            // Chevron
            SkeletonRect(width: 10, height: 14, radius: 3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
    }
}

// MARK: - Secret Challenge Dossier Skeleton

struct DossierSkeletonView: View {
    var body: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            // Classified stamp
            dossierRect(width: 140, height: 12)
            
            // Title field
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                dossierRect(width: 100, height: 10)
                    .opacity(0.5)
                dossierRect(height: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Description field
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                dossierRect(width: 90, height: 10)
                    .opacity(0.5)
                dossierRect(height: 14)
                dossierRect(width: 200, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Submission type pills
            HStack(spacing: BQDesign.Spacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    dossierRect(width: 70, height: 28, radius: 14)
                }
            }
            
            // Point value pills
            HStack(spacing: BQDesign.Spacing.sm) {
                ForEach(0..<4, id: \.self) { _ in
                    dossierRect(width: 55, height: 32, radius: 16)
                }
            }
        }
        .padding(BQDesign.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .shimmer()
    }
    
    private func dossierRect(width: CGFloat? = nil, height: CGFloat = 16, radius: CGFloat = 8) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.1))
            .frame(width: width, height: height)
    }
}

struct TimelineSkeletonView: View {
    var body: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            // Header
            VStack(spacing: BQDesign.Spacing.xs) {
                SkeletonCircle(size: 44)
                SkeletonRect(width: 140, height: 28, radius: 10)
            }
            
            Spacer().frame(height: BQDesign.Spacing.xxl)
            
            // Ghost nodes with trail connectors
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    if i > 0 {
                        // Connector
                        SkeletonRect(width: 4, height: 50, radius: 2)
                            .opacity(0.4)
                    }
                    
                    // Node
                    HStack {
                        if i % 2 == 0 { Spacer().frame(width: 40) }
                        
                        VStack(spacing: 6) {
                            SkeletonCircle(size: 48)
                            SkeletonRect(width: 80, height: 12, radius: 5)
                            SkeletonRect(width: 50, height: 10, radius: 4)
                        }
                        
                        if i % 2 != 0 { Spacer().frame(width: 40) }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(1.0 - Double(i) * 0.25)
                }
            }
            
            Spacer()
        }
        .padding(.top, BQDesign.Spacing.lg)
        .shimmer()
    }
}
