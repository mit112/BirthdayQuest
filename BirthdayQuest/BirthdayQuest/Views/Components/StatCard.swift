import SwiftUI

/// Reusable stat card for profile grids.
struct StatCard: View {
    
    let icon: String
    let value: String
    let label: String
    let color: Color
    var index: Int = 0
    
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 26))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(BQDesign.Colors.textPrimary)
            
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(BQDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                
                // Subtle accent gradient wash from top
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.04), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.06), radius: 8, y: 3)
        .shadow(color: Color.black.opacity(0.03), radius: 4, y: 2)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(
                .spring(response: 0.5, dampingFraction: 0.7)
                .delay(Double(index) * 0.08 + 0.2)
            ) {
                appeared = true
            }
        }
    }
}
