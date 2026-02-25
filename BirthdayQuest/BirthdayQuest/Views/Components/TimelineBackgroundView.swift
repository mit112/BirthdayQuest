import SwiftUI

// MARK: - Timeline Background
// Layered: animated gradient + floating bokeh + tiny sparkle particles
// Creates the "living world" feel behind the timeline path.

struct TimelineBackgroundView: View {
    
    @State private var phase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Layer 1: Animated gradient that shifts color temperature
            animatedGradient
            
            // Layer 2: Large soft bokeh circles (atmospheric depth)
            BokehFieldView()
            
            // Layer 3: Tiny twinkling star particles
            SparkleFieldView()
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
    
    private var animatedGradient: some View {
        // Color temperature shifts: cool lavender top → warm peach mid → mystical purple bottom
        LinearGradient(
            stops: [
                .init(color: Color(hex: "F5F0FA"), location: 0.0),
                .init(color: Color(hex: "FBF7F4"), location: 0.15),
                .init(color: Color(hex: "FFF5EE"), location: 0.35),
                .init(color: Color(hex: "FFF0E8"), location: 0.55),
                .init(color: Color(hex: "F5EEFA"), location: 0.75),
                .init(color: Color(hex: "EDE5F5"), location: 0.9),
                .init(color: Color(hex: "E8D8F0"), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Bokeh Field (large soft blurred circles)

private struct BokehFieldView: View {
    
    private let bokehCount = 8
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // Static bokeh — drawn once, no per-frame cost
            } symbols: {
                ForEach(0..<bokehCount, id: \.self) { i in
                    BokehDot(index: i, bounds: geo.size)
                        .tag(i)
                }
            }
            
            // Use real views for animation (lightweight at 8 count)
            ForEach(0..<bokehCount, id: \.self) { i in
                BokehDot(index: i, bounds: geo.size)
            }
        }
    }
}

private struct BokehDot: View {
    let index: Int
    let bounds: CGSize
    
    @State private var driftOffset: CGSize = .zero
    @State private var opacity: Double = 0
    
    private var config: BokehConfig {
        // Deterministic from index so layout is stable
        let seed = Double(index)
        let size = CGFloat(25 + (seed * 7).truncatingRemainder(dividingBy: 45))
        let xFrac = (seed * 0.13 + 0.1).truncatingRemainder(dividingBy: 1.0)
        let yFrac = (seed * 0.17 + 0.05).truncatingRemainder(dividingBy: 1.0)
        let colors: [Color] = [
            BQDesign.Colors.primaryPurple,
            BQDesign.Colors.primaryPink,
            BQDesign.Colors.gold,
            Color(hex: "A78BFA"),
            Color(hex: "6DB3F2"),
            Color(hex: "F472B6"),
            Color(hex: "FFD166"),
            Color(hex: "34D399"),
        ]
        return BokehConfig(
            size: size,
            x: xFrac * bounds.width,
            y: yFrac * bounds.height,
            color: colors[index % colors.count],
            baseOpacity: 0.06 + (seed * 0.008).truncatingRemainder(dividingBy: 0.08),
            duration: 6 + seed.truncatingRemainder(dividingBy: 5)
        )
    }
    
    var body: some View {
        Circle()
            .fill(config.color.opacity(config.baseOpacity))
            .frame(width: config.size, height: config.size)
            .blur(radius: config.size * 0.3)
            .position(x: config.x, y: config.y)
            .offset(driftOffset)
            .opacity(opacity)
            .onAppear {
                let delay = Double(index) * 0.3
                withAnimation(.easeIn(duration: 1.5).delay(delay)) {
                    opacity = 1
                }
                withAnimation(
                    .easeInOut(duration: config.duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    driftOffset = CGSize(
                        width: CGFloat.random(in: -20...20),
                        height: CGFloat.random(in: -15...15)
                    )
                }
            }
    }
}

private struct BokehConfig {
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
    let color: Color
    let baseOpacity: Double
    let duration: Double
}

// MARK: - Sparkle Field (tiny twinkling stars)

struct SparkleFieldView: View {
    
    private let sparkleCount = 18
    
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<sparkleCount, id: \.self) { i in
                SparkleParticle(index: i, bounds: geo.size)
            }
        }
    }
}

private struct SparkleParticle: View {
    let index: Int
    let bounds: CGSize
    
    @State private var twinkle: Bool = false
    
    private var x: CGFloat {
        let seed = Double(index)
        return CGFloat((seed * 37.7).truncatingRemainder(dividingBy: Double(bounds.width)))
    }
    
    private var y: CGFloat {
        let seed = Double(index)
        return CGFloat((seed * 53.3).truncatingRemainder(dividingBy: Double(bounds.height)))
    }
    
    private var size: CGFloat {
        CGFloat([2.0, 2.5, 3.0, 3.5, 4.0][index % 5])
    }
    
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(
                [
                    BQDesign.Colors.gold,
                    BQDesign.Colors.primaryPurple.opacity(0.7),
                    BQDesign.Colors.primaryPink.opacity(0.6),
                    Color.white.opacity(0.5),
                ][index % 4]
            )
            .position(x: x, y: y)
            .opacity(twinkle ? 0.8 : 0.15)
            .scaleEffect(twinkle ? 1.2 : 0.7)
            .onAppear {
                let delay = Double(index) * 0.2
                let duration = Double.random(in: 1.8...3.5)
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    twinkle = true
                }
            }
    }
}
