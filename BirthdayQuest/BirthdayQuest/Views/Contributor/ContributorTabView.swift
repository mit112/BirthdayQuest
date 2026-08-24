import SwiftUI

// MARK: - Contributor Tab Layout
// 4 tabs: Secret Challenge → Gift → Timeline → Profile
// Secret agent themed — dark, mysterious entry point.

struct ContributorTabView: View {

    @EnvironmentObject private var event: EventSession

    var body: some View {
        TabView(selection: $event.contributorTab) {
            SecretChallengeHomeView(eventId: event.eventId)
                .tabItem {
                    Label(
                        ContributorTab.secretChallenge.title,
                        systemImage: ContributorTab.secretChallenge.icon
                    )
                }
                .tag(ContributorTab.secretChallenge)

            GiftAuthoringView(eventId: event.eventId)
                .tabItem {
                    Label(ContributorTab.gift.title, systemImage: ContributorTab.gift.icon)
                }
                .tag(ContributorTab.gift)

            TimelineView(eventId: event.eventId)
                .tabItem {
                    Label(ContributorTab.timeline.title, systemImage: ContributorTab.timeline.icon)
                }
                .tag(ContributorTab.timeline)

            ProfileView(eventId: event.eventId)
                .tabItem {
                    Label(ContributorTab.profile.title, systemImage: ContributorTab.profile.icon)
                }
                .tag(ContributorTab.profile)
        }
        .tint(BQDesign.Colors.secretAccent)
    }
}
