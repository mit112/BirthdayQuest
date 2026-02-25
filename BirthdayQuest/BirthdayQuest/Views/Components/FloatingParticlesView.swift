import SwiftUI

/// Subtle floating dots/sparkles for immersive backgrounds.
/// Lightweight — just animated circles, no SpriteKit needed.
struct FloatingParticlesView: View {
    
    private let particleCount = 25
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<particleCount, id: \.self) { i in
                    ParticleDot(
                        bounds: geo.size,
                        index: i
                    )
                }
            }
        }
    }
}

// MARK: - Individual Particle

private struct ParticleDot: View {
    let bounds: CGSize
    let index: Int
    
    @State private var position: CGPoint = .zero
    @State private var opacity: Double = 0
    
    // Deterministic from index — no flickering on redraw
    private var size: CGFloat {
        [3.0, 4.0, 2.5, 5.0, 3.5, 2.0, 4.5, 3.0][index % 8]
    }
    
    private var color: Color {
        [
            BQDesign.Colors.primaryPurple,
            BQDesign.Colors.primaryPink,
            BQDesign.Colors.gold,
            .white
        ][index % 4]
    }
    
    // Deterministic pseudo-random values derived from index
    private var delay: Double { Double(index % 7) * 0.3 }
    private var duration: Double { 4.0 + Double(index % 5) }
    private var targetOpacity: Double { 0.2 + Double(index % 4) * 0.1 }
    
    private func seededPosition(seed: Int) -> CGPoint {
        let xFrac = (Double(seed) * 37.7).truncatingRemainder(dividingBy: 1.0)
        let yFrac = (Double(seed) * 53.3).truncatingRemainder(dividingBy: 1.0)
        return CGPoint(x: xFrac * bounds.width, y: yFrac * bounds.height)
    }
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .position(position)
            .opacity(opacity)
            .onAppear {
                // Deterministic start position
                position = seededPosition(seed: index)
                
                withAnimation(.easeInOut(duration: 1.0).delay(delay)) {
                    opacity = targetOpacity
                }
                
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    position = seededPosition(seed: index + 100)
                }
            }
    }
}
