import SwiftUI

/// Styled card for displaying text-based reward messages.
/// Feels like reading a heartfelt letter — warm tones, nice typography.
struct TextRewardView: View {
    
    let text: String
    let fromName: String
    
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Decorative quotation mark
            Text("\u{201C}")
                .font(.system(size: 80, weight: .bold, design: .serif))
                .foregroundColor(BQDesign.Colors.gold.opacity(0.15))
                .frame(height: 50)
                .padding(.top, BQDesign.Spacing.md)
            
            // Message body
            ScrollView(showsIndicators: false) {
                Text(text)
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, BQDesign.Spacing.xl)
                    .padding(.vertical, BQDesign.Spacing.md)
            }
            .frame(maxHeight: 250)
            
            // Sender attribution
            HStack(spacing: BQDesign.Spacing.xs) {
                Rectangle()
                    .fill(BQDesign.Colors.gold.opacity(0.3))
                    .frame(width: 20, height: 1)
                
                Text("from \(fromName)")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                
                Rectangle()
                    .fill(BQDesign.Colors.gold.opacity(0.3))
                    .frame(width: 20, height: 1)
            }
            .padding(.bottom, BQDesign.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                .fill(BQDesign.Colors.goldLight.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                        .stroke(BQDesign.Colors.gold.opacity(0.2), lineWidth: 1)
                )
        )
        .bqShadow(BQDesign.Shadows.card)
        .padding(.horizontal, BQDesign.Spacing.lg)
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(BQDesign.Animation.smooth.delay(0.2)) {
                appeared = true
            }
        }
    }
}
