import SwiftUI

// MARK: - Content State

/// What a content screen should render right now.
///
/// Deliberately an enum computed in the view model rather than a set of loose flags read by
/// the view body. The defect this replaces was exactly a lost branch: a listener set an
/// error message that no view read, so a refused read fell through to `isEmpty` and rendered
/// a cheerful empty state — worse than the shimmer it replaced, because a skeleton reads as
/// "still loading" while an empty state reads as authoritative.
///
/// Making `failed` and `empty` mutually exclusive by construction means a view cannot show
/// both, and a test can assert the branch a view will take instead of merely asserting that
/// an error string exists somewhere — which is exactly what was true while the bug shipped.
enum ContentState: Equatable {
    case loading
    /// The read was refused and will not recover on its own. Carries the user-facing line.
    case failed(String)
    case empty
    case ready
}

/// The recovery step, shared by every failure surface so the instruction cannot drift
/// between them. Reopening the occasion re-runs `EventSession.start()`, which resolves the
/// ambiguity for the user: either the content comes back, or they get "Can't open this".
enum ContentFailureCopy {
    static let recovery = "Leave this occasion and open it again to reconnect."
}

// MARK: - Content Failure View

/// The inline replacement for an empty state when the read was refused.
///
/// Inline rather than an alert on purpose: losing access to an occasion is a *persistent*
/// state, and an alert is dismissed once and then leaves the lying empty state behind it.
struct ContentFailureView: View {

    let message: String
    /// The secret-dare screen sits on `secretGradient`; every other surface is on
    /// `background`. `textPrimary` is unreadable on the dark one, so it flips to white.
    var onDarkBackground = false

    private var headline: Color {
        onDarkBackground ? .white : BQDesign.Colors.textPrimary
    }

    private var subhead: Color {
        onDarkBackground ? .white.opacity(0.75) : BQDesign.Colors.textPrimary.opacity(0.75)
    }

    @ScaledMetric private var failureIconSize: CGFloat = 40

    var body: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            // Decorative: the message below carries the meaning, so it is hidden from
            // VoiceOver rather than read out as "warning triangle".
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: failureIconSize))
                .foregroundStyle(BQDesign.Colors.error)
                .accessibilityHidden(true)

            Text(message)
                .font(BQDesign.Typography.bodyBold)
                .foregroundStyle(headline)
                .multilineTextAlignment(.center)

            Text(ContentFailureCopy.recovery)
                .font(BQDesign.Typography.caption)
                .foregroundStyle(subhead)
                .multilineTextAlignment(.center)
        }
        .padding(BQDesign.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message) \(ContentFailureCopy.recovery)")
    }
}

// MARK: - Connection Lost Banner

/// A persistent strip for a failure that does not make the screen unusable.
///
/// Used where the occasion is still on display and still legitimately readable — it has
/// just stopped updating. A banner rather than a takeover so the user keeps what they can
/// still see, and rather than silence so the last values on screen cannot read as current.
struct ConnectionLostBanner: View {

    let message: String

    @ScaledMetric private var bannerIconSize: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: BQDesign.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: bannerIconSize))
                .foregroundStyle(BQDesign.Colors.error)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text(message)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textPrimary)

                Text(ContentFailureCopy.recovery)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textPrimary.opacity(0.75))
            }

            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, BQDesign.Spacing.md)
        .padding(.vertical, BQDesign.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(BQDesign.Colors.error.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message) \(ContentFailureCopy.recovery)")
    }
}
