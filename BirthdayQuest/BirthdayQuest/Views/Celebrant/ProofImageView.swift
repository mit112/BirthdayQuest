import SwiftUI

// MARK: - ProofImagePresentation

/// Branch selection for a proof photo, kept pure and out of the view body so it is directly
/// unit-testable — the same split `RewardContentPresentation` makes for reward media.
enum ProofImagePresentation: Equatable {
    case loading
    case ready(URL)
    /// The Storage object is gone. Past `MediaLifecycle` expiry the celebrant's device sweeps
    /// proof objects off the server, so "missing" is the expected end state for an old occasion,
    /// not a fault — and telling someone to retry a photo that no longer exists is a lie.
    case expired
    /// Anything else: offline, permission-denied, a corrupt file.
    case failed

    static func resolve(error: Error) -> ProofImagePresentation {
        if case MediaStore.MediaStoreError.objectMissing = error { return .expired }
        return .failed
    }
}

// MARK: - ProofImageView

/// Renders a challenge proof photo from its Storage object path via an authenticated download —
/// mirroring how reward media resolves through `MediaStore`, so `challenge.proofUrl` never needs
/// to hold a tokened download URL (see `ProofMediaLoading`).
struct ProofImageView: View {

    let path: String
    let eventId: String
    var loader: ProofMediaLoading = MediaStore()

    @State private var presentation: ProofImagePresentation = .loading
    @ScaledMetric private var proofPlaceholderIconSize: CGFloat = 18

    var body: some View {
        Group {
            switch presentation {
            case .loading:
                loadingPlaceholder
            case .expired:
                proofPlaceholder(icon: "clock.badge.xmark", text: "This photo isn't kept anymore")
            case .failed:
                proofPlaceholder(icon: "photo", text: "Couldn't load photo")
            case .ready(let localURL):
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
                        loadingPlaceholder
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .task {
            do {
                presentation = .ready(try await loader.localURL(forPath: path, eventId: eventId))
            } catch {
                presentation = ProofImagePresentation.resolve(error: error)
            }
        }
    }

    private var loadingPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .background(
                RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                    .fill(BQDesign.Colors.cardBackground)
            )
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
