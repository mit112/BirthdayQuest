import SwiftUI

// MARK: - Celebrant Tab Layout
// 4 tabs: Rewards → Challenges → Timeline → Profile
// Thematic icons, not generic. Warm tinted tab bar.

struct CelebrantTabView: View {

    @EnvironmentObject private var event: EventSession

    var body: some View {
        TabView(selection: $event.celebrantTab) {
            RewardsCarouselView(eventId: event.eventId)
                .tabItem {
                    Label(CelebrantTab.rewards.title, systemImage: CelebrantTab.rewards.icon)
                }
                .tag(CelebrantTab.rewards)

            ChallengesBoardView(eventId: event.eventId)
                .tabItem {
                    Label(CelebrantTab.challenges.title, systemImage: CelebrantTab.challenges.icon)
                }
                .tag(CelebrantTab.challenges)

            TimelineView(eventId: event.eventId)
                .tabItem {
                    Label(CelebrantTab.timeline.title, systemImage: CelebrantTab.timeline.icon)
                }
                .tag(CelebrantTab.timeline)

            ProfileView(eventId: event.eventId)
                .tabItem {
                    Label(CelebrantTab.profile.title, systemImage: CelebrantTab.profile.icon)
                }
                .tag(CelebrantTab.profile)
        }
        .tint(BQDesign.Colors.primaryPurple)
    }
}
