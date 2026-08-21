import SwiftUI

/// The boundary of one occasion. Owns the `EventSession` and routes on the caller's mode.
///
/// The session is a `@StateObject` keyed to this view's lifetime, so leaving the occasion
/// deallocates it and `stop()` releases exactly the listeners it registered.
struct EventContainerView: View {

    let eventId: String
    @StateObject private var event: EventSession

    init(eventId: String) {
        self.eventId = eventId
        _event = StateObject(wrappedValue: EventSession(eventId: eventId))
    }

    var body: some View {
        Group {
            if event.isLoading {
                ProgressView()
            } else if let message = event.errorMessage, event.participant == nil {
                ContentUnavailableView(
                    "Can't open this", systemImage: "lock", description: Text(message)
                )
            } else if event.isCelebrant {
                CelebrantTabView()
            } else {
                ContributorTabView()
            }
        }
        .environmentObject(event)
        .task { await event.start() }
        .onDisappear { event.stop() }
    }
}
