import SwiftUI

/// The mysterious entry point to secret challenges.
/// Hidden in plain sight at the bottom of the challenges list.
/// Wiggles and glimmers to draw attention.
struct SecretEntryCardView: View {
    
    let hasSecrets: Bool
    let onTap: () -> Void
    
    @State private var wiggle = false
    @State private var shimmerOffset: CGFloat = -200

    @Environment(\.bqMotionLevel) private var motionLevel
    @ScaledMetric private var keyholeIconSize: CGFloat = 24
    @ScaledMetric private var eyeIconSize: CGFloat = 16

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BQDesign.Spacing.md) {
                // Keyhole icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "questionmark")
                        .font(.system(size: keyholeIconSize, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                    Text("???")
                        .font(BQDesign.Typography.cardTitle)
                        .foregroundColor(.white)
                    
                    Text(hasSecrets ? "Something's hiding here..." : "Nothing to see here... yet")
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(.white.opacity(0.65))
                }
                
                Spacer()
                
                if hasSecrets {
                    Image(systemName: "eye.fill")
                        .font(.system(size: eyeIconSize))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(BQDesign.Spacing.md)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .fill(Color(hex: "1C1B2E"))
                    
                    // Shimmer sweep
                    if hasSecrets {
                        RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0), .white.opacity(0.06), .white.opacity(0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerOffset)
                    }
                    
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(wiggle ? 0.8 : -0.8))
        .allowsHitTesting(hasSecrets)
        .onAppear {
            guard hasSecrets else { return }
            // Reduce Motion / Low Power Mode: skip driving the state at all, rather
            // than passing a nil animation, which would snap both to their "on" pose.
            guard motionLevel.allowsPerpetual else { return }
            // Wiggle
            withAnimation(
                .easeInOut(duration: 0.15)
                .repeatCount(6, autoreverses: true)
                .delay(2)
                .repeatForever(autoreverses: false)
            ) {
                wiggle = true
            }
            // Shimmer
            withAnimation(
                .easeInOut(duration: 2)
                .repeatForever(autoreverses: false)
                .delay(1)
            ) {
                shimmerOffset = 400
            }
        }
    }
}
