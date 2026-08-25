import SwiftUI

/// Renders a challenge proof photo from its Storage object path via an authenticated download —
/// mirroring how reward media resolves through `MediaStore`, so `challenge.proofUrl` never needs
/// to hold a tokened download URL (see `ProofMediaLoading`).
struct ProofImageView: View {

    let path: String
    let eventId: String
    var loader: ProofMediaLoading = MediaStore()

    @State private var localURL: URL?
    @State private var failed = false
    @ScaledMetric private var proofPlaceholderIconSize: CGFloat = 18

    var body: some View {
        Group {
            if failed {
                proofPlaceholder(icon: "photo", text: "Couldn't load photo")
            } else if let localURL {
                AsyncImage(url: localURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous))
                            .bqShadow(BQDesign.Shadows.card)
                    case .failure:
                        proofPlaceholder(icon: "photo", text: "Couldn't load photo")
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .background(
                                RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                                    .fill(BQDesign.Colors.cardBackground)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .background(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                            .fill(BQDesign.Colors.cardBackground)
                    )
            }
        }
        .task {
            do {
                localURL = try await loader.localURL(forPath: path, eventId: eventId)
            } catch {
                failed = true
            }
        }
    }

    private func proofPlaceholder(icon: String, text: String) -> some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: proofPlaceholderIconSize))
                .foregroundColor(BQDesign.Colors.textTertiary)
            Text(text)
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(BQDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
        )
        .bqShadow(BQDesign.Shadows.card)
    }
}
