import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var session: AppSession
    @State private var pendingJoinLink: URL?

    var body: some View {
        Group {
            switch session.rootState {
            case .launching:
                LoadingView()
            case .empty:
                EmptyOccasionsView()
            case .occasions:
                OccasionListView()
            }
        }
        .task { await session.bootstrap() }
        // The app's only `.onOpenURL`. SwiftUI delivers an incoming URL to every handler in
        // the hierarchy, so a second one anywhere would present two join sheets for one link.
        .onOpenURL { pendingJoinLink = $0 }
        .sheet(item: $pendingJoinLink) { link in
            JoinOccasionView(incomingLink: link)
        }
    }
}

// MARK: - Empty State

/// The root when the user has no occasions — *or* when we could not find out.
///
/// `AppSession` routes both to `.empty`, because a failed bootstrap has no occasions to show
/// either. That made this screen assert "No occasions yet" to someone who may well have
/// several, and offer no way to try again: `bootstrap()` runs from a `.task` that never
/// re-fires, so the only exit was to force-quit the app. Failure therefore outranks empty
/// here, and it owns the whole screen rather than appending a red line under an invitation to
/// create something.
struct EmptyOccasionsView: View {

    @EnvironmentObject private var session: AppSession
    @State private var creating = false
    @State private var joining = false
    @State private var isRetrying = false
    @State private var showingAccount = false

    @ScaledMetric private var crownSize: CGFloat = 56
    @ScaledMetric private var errorIconSize: CGFloat = 48

    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()
            // Somewhere to overflow *to*. At the largest accessibility text sizes this content is
            // taller than a 390pt-wide phone's screen, and with no scroll container SwiftUI
            // compresses it instead: the invitation truncated to "or join w…" and the primary
            // button to "Create an occ…". `minHeight` keeps it optically centred while it fits,
            // and lets it grow and scroll once it doesn't.
            GeometryReader { proxy in
                ScrollView {
                    Group {
                        if let errorMessage = session.errorMessage {
                            failure(errorMessage)
                        } else {
                            empty
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        // Overlaid on the ZStack rather than placed inside either branch, so the account —
        // and with it the terms and account deletion — stays reachable whether this screen is
        // showing "no occasions yet" or a failed load. Someone with nothing to open is the
        // likeliest person to want to close their account, and this is the only root they see.
        .overlay(alignment: .topTrailing) {
            Button { showingAccount = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(BQDesign.Typography.sectionTitle)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }
            .accessibilityLabel("Account")
            .padding(BQDesign.Spacing.lg)
        }
        .sheet(isPresented: $creating) { CreateOccasionView() }
        .sheet(isPresented: $joining) { JoinOccasionView() }
        .sheet(isPresented: $showingAccount) { AccountView() }
    }

    private var empty: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            Text("👑").font(.system(size: crownSize))
            Text("No occasions yet")
                .font(BQDesign.Typography.heroTitle)
                .foregroundStyle(BQDesign.Colors.primaryGradient)
            Text("Create one for someone you love, or join with an invite link.")
                .font(BQDesign.Typography.body)
                .foregroundStyle(BQDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
                // Takes its full wrapped height rather than being squeezed into an ellipsis.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BQDesign.Spacing.xl)

            VStack(spacing: BQDesign.Spacing.sm) {
                // Spelled out with an explicit label, not `Button("…")`: the string form renders a
                // single-line Text that truncates, and a clipped verb is the one word on this
                // screen a new user needs to read.
                Button { creating = true } label: {
                    Text("Create an occasion")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderedProminent)

                Button { joining = true } label: {
                    Text("Join with a link")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, BQDesign.Spacing.lg)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            // The glyph carries the severity in colour so the sentence does not have to.
            // `Colors.error` measures 3.83:1 on this background, below the 4.5:1 floor for
            // body text, which is why the message itself is `textPrimary`.
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: errorIconSize))
                .foregroundStyle(BQDesign.Colors.error)
                .accessibilityHidden(true)

            Text(message)
                .font(BQDesign.Typography.body)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .multilineTextAlignment(.center)
                // Same reason as the empty state's invitation: a truncated error explains nothing.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BQDesign.Spacing.xl)

            if isRetrying {
                // Replaced rather than disabled: a dead button with no explanation is its
                // own defect, and taking it off screen is what makes a second tap impossible.
                HStack(spacing: BQDesign.Spacing.sm) {
                    ProgressView()
                    Text("Trying again…")
                        .font(BQDesign.Typography.caption)
                        .foregroundStyle(BQDesign.Colors.textPrimary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button("Try again") {
                    Task {
                        isRetrying = true
                        await session.bootstrap()
                        isRetrying = false
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            // Still reachable. An account with a valid invite link in hand should not be
            // blocked by a failed occasion-list read.
            Button("Join with a link") { joining = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Couldn't load your occasions")
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @State private var pulse = false
    @Environment(\.bqMotionLevel) private var motionLevel
    @ScaledMetric private var crownSize: CGFloat = 60

    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()

            VStack(spacing: BQDesign.Spacing.md) {
                Text("👑")
                    .font(.system(size: crownSize))
                    .scaleEffect(pulse ? 1.1 : 0.95)
                    .animation(
                        motionLevel.allowsPerpetual
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : nil,
                        value: pulse
                    )

                Text("BirthdayQuest")
                    .font(BQDesign.Typography.heroTitle)
                    .foregroundStyle(BQDesign.Colors.primaryGradient)
            }
        }
        .onAppear { pulse = true }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSession())
}
