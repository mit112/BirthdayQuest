import SwiftUI

// MARK: - Birthday Boy Tab Layout
// 4 tabs: Rewards → Challenges → Timeline → Profile
// Thematic icons, not generic. Warm tinted tab bar.

struct BirthdayBoyTabView: View {
    
    @EnvironmentObject private var session: SessionManager
    
    var body: some View {
        TabView(selection: $session.birthdayBoyTab) {
            RewardsCarouselView()
                .tabItem {
                    Label(BirthdayBoyTab.rewards.title, systemImage: BirthdayBoyTab.rewards.icon)
                }
                .tag(BirthdayBoyTab.rewards)
            
            ChallengesBoardView()
                .tabItem {
                    Label(BirthdayBoyTab.challenges.title, systemImage: BirthdayBoyTab.challenges.icon)
                }
                .tag(BirthdayBoyTab.challenges)
            
            TimelineView()
                .tabItem {
                    Label(BirthdayBoyTab.timeline.title, systemImage: BirthdayBoyTab.timeline.icon)
                }
                .tag(BirthdayBoyTab.timeline)
            
            ProfileView()
                .tabItem {
                    Label(BirthdayBoyTab.profile.title, systemImage: BirthdayBoyTab.profile.icon)
                }
                .tag(BirthdayBoyTab.profile)
        }
        .tint(BQDesign.Colors.primaryPurple)
    }
}

// MARK: - Tab Enum

enum BirthdayBoyTab: Int, CaseIterable {
    case rewards = 0
    case challenges
    case timeline
    case profile
    
    var title: String {
        switch self {
        case .rewards: return "Rewards"
        case .challenges: return "Challenges"
        case .timeline: return "Timeline"
        case .profile: return "Profile"
        }
    }
    
    var icon: String {
        switch self {
        case .rewards: return "gift.fill"
        case .challenges: return "bolt.fill"
        case .timeline: return "safari.fill"
        case .profile: return "crown.fill"
        }
    }
}
