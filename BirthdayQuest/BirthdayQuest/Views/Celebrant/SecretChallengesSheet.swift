import SwiftUI

/// Dark "classified" sheet showing all delivered secret challenges.
struct SecretChallengesSheet: View {
    
    let secrets: [Challenge]
    let onSelect: (Challenge) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @ScaledMetric private var headerEmojiSize: CGFloat = 44
    
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
                        .font(.system(size: headerEmojiSize))

                    // Explicit text style, not a token: the monospaced design is the
                    // "classified transmission" look and no BQDesign token carries it.
                    Text("SECRET MISSIONS")
                        .font(.system(.title2, design: .monospaced, weight: .heavy))
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

    @ScaledMetric private var pointsSparkleSize: CGFloat = 11
    @ScaledMetric private var chevronSize: CGFloat = 12

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
                // From label
                // Document IDs are human-readable names by design (e.g. "sam", "jordan")
                if let fromId = challenge.createdByUserId {
                    // Explicit text style: monospaced design has no BQDesign token,
                    // and it carries the "classified" look here too.
                    Text("FROM: \(fromId.uppercased())")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
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
                        Text("✦").font(.system(size: pointsSparkleSize, weight: .bold))
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
                        Image(systemName: "chevron.right")
                            .font(.system(size: chevronSize))
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
