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

struct EmptyOccasionsView: View {

    @EnvironmentObject private var session: AppSession
    @State private var creating = false
    @State private var joining = false

    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()
            VStack(spacing: BQDesign.Spacing.lg) {
                Text("👑").font(.system(size: 56))
                Text("No occasions yet")
                    .font(BQDesign.Typography.heroTitle)
                    .foregroundStyle(BQDesign.Colors.primaryGradient)
                Text("Create one for someone you love, or join with an invite link.")
                    .font(BQDesign.Typography.body)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BQDesign.Spacing.xl)

                VStack(spacing: BQDesign.Spacing.sm) {
                    Button("Create an occasion") { creating = true }
                        .buttonStyle(.borderedProminent)
                    Button("Join with a link") { joining = true }
                }

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(BQDesign.Typography.caption)
                        .foregroundStyle(BQDesign.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BQDesign.Spacing.xl)
                }
            }
        }
        .sheet(isPresented: $creating) { CreateOccasionView() }
        .sheet(isPresented: $joining) { JoinOccasionView() }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()

            VStack(spacing: BQDesign.Spacing.md) {
                Text("👑")
                    .font(.system(size: 60))
                    .scaleEffect(pulse ? 1.1 : 0.95)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
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
