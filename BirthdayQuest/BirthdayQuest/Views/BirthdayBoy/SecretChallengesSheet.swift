import SwiftUI

/// Dark "classified" sheet showing all delivered secret challenges.
struct SecretChallengesSheet: View {
    
    let secrets: [Challenge]
    let onSelect: (Challenge) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    
    var body: some View {
        ZStack {
            BQDesign.Colors.secretGradient.ignoresSafeArea()
            
            VStack(spacing: BQDesign.Spacing.lg) {
                // Handle
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 5)
                    .padding(.top, BQDesign.Spacing.md)
                
                // Header
                VStack(spacing: BQDesign.Spacing.sm) {
                    Text("🕵️‍♂️")
                        .font(.system(size: 44))
                    
                    Text("SECRET MISSIONS")
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(3)
                    
                    Text("Complete these without anyone finding out")
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -10)
                
                // Secret challenge cards
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: BQDesign.Spacing.md) {
                        ForEach(Array(secrets.enumerated()), id: \.element.id) { index, secret in
                            SecretMissionCard(challenge: secret) {
                                onSelect(secret)
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(
                                BQDesign.Animation.smooth.delay(Double(index) * 0.1 + 0.2),
                                value: appeared
                            )
                        }
                    }
                    .padding(.horizontal, BQDesign.Spacing.lg)
                }
                
                Spacer()
            }
        }
        .onAppear {
            withAnimation(BQDesign.Animation.smooth) {
                appeared = true
            }
        }
    }
}

// MARK: - Secret Mission Card

private struct SecretMissionCard: View {
    
    let challenge: Challenge
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
                // From label
                if let fromId = challenge.createdByUserId {
                    Text("FROM: \(fromId.capitalized)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(BQDesign.Colors.secretAccent.opacity(0.7))
                }
                
                Text(challenge.title)
                    .font(BQDesign.Typography.cardTitle)
                    .foregroundColor(.white)
                
                Text(challenge.description)
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
                
                HStack {
                    // Points
                    HStack(spacing: 2) {
                        Text("✦").font(.system(size: 11, weight: .bold))
                        Text("\(challenge.pointValue)")
                            .font(BQDesign.Typography.captionSmall)
                    }
                    .foregroundColor(BQDesign.Colors.gold)
                    
                    Spacer()
                    
                    // Status
                    if challenge.isCompleted {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .font(BQDesign.Typography.captionSmall)
                            .foregroundColor(BQDesign.Colors.success)
                    } else {
                        Image(systemName: challenge.submissionType.icon)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(BQDesign.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                            .stroke(
                                challenge.isCompleted
                                ? BQDesign.Colors.success.opacity(0.3)
                                : BQDesign.Colors.secretAccent.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(challenge.isCompleted)
        .opacity(challenge.isCompleted ? 0.7 : 1)
    }
}
