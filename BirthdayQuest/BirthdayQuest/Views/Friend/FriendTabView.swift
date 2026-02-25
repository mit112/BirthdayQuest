import SwiftUI

// MARK: - Friend Tab Layout
// 3 tabs: Secret Challenge → Timeline → Profile
// Secret agent themed — dark, mysterious entry point.

struct FriendTabView: View {
    
    @EnvironmentObject private var session: SessionManager
    
    var body: some View {
        TabView(selection: $session.friendTab) {
            SecretChallengeHomeView()
                .tabItem {
                    Label(FriendTab.secretChallenge.title, systemImage: FriendTab.secretChallenge.icon)
                }
                .tag(FriendTab.secretChallenge)
            
            TimelineView()
                .tabItem {
                    Label(FriendTab.timeline.title, systemImage: FriendTab.timeline.icon)
                }
                .tag(FriendTab.timeline)
            
            ProfileView()
                .tabItem {
                    Label(FriendTab.profile.title, systemImage: FriendTab.profile.icon)
                }
                .tag(FriendTab.profile)
        }
        .tint(BQDesign.Colors.secretAccent)
    }
}

// MARK: - Tab Enum

enum FriendTab: Int, CaseIterable {
    case secretChallenge = 0
    case timeline
    case profile
    
    var title: String {
        switch self {
        case .secretChallenge: return "Secret Dare"
        case .timeline: return "Timeline"
        case .profile: return "Profile"
        }
    }
    
    var icon: String {
        switch self {
        case .secretChallenge: return "eye.slash.fill"
        case .timeline: return "safari.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}
