import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject private var session: SessionManager
    
    var body: some View {
        Group {
            switch session.appState {
            case .loading:
                LoadingView()
            case .characterSelect:
                CharacterSelectView()
            case .birthdayBoyHome:
                BirthdayBoyTabView()
            case .friendHome:
                FriendTabView()
            }
        }
        .task {
            await session.bootstrap()
        }
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
        .environmentObject(SessionManager.shared)
}
