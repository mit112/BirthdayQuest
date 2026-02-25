import SwiftUI

// MARK: - Shadow Modifier

extension View {
    func bqShadow(_ shadow: Shadow) -> some View {
        self.shadow(
            color: shadow.color,
            radius: shadow.radius,
            x: shadow.x,
            y: shadow.y
        )
    }
    
    func bqCard() -> some View {
        self
            .background(BQDesign.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous))
            .bqShadow(BQDesign.Shadows.card)
    }
    
    /// Press-down scale animation for buttons
    func pressAnimation(scale: Binding<CGFloat>) -> some View {
        self
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(BQDesign.Animation.snappy) {
                            scale.wrappedValue = 0.95
                        }
                    }
                    .onEnded { _ in
                        withAnimation(BQDesign.Animation.bouncy) {
                            scale.wrappedValue = 1.0
                        }
                    }
            )
    }
    
    func bqGradientBackground() -> some View {
        self.background(
            LinearGradient(
                colors: [
                    BQDesign.Colors.background,
                    BQDesign.Colors.background.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}
