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
            } else if let message = event.errorMessage {
                // No `participant == nil` clause any more. `errorMessage` is now set by
                // exactly one place — the `catch` in `start()`, which returns before a
                // participant is ever assigned — so "nothing is loaded" is structural
                // rather than a condition the view has to re-derive. Guarding on the
                // participant was what made a *listener* failure unrenderable: by then the
                // participant is non-nil, so the message had nowhere to go.
                ContentUnavailableView(
                    "Can't open this", systemImage: "lock", description: Text(message)
                )
            } else {
                // A dead game-state listener leaves the occasion perfectly readable, so it
                // gets a banner above the tabs rather than a takeover of them.
                VStack(spacing: 0) {
                    if let message = event.connectionMessage {
                        ConnectionLostBanner(message: message)
                    }

                    if event.isCelebrant {
                        CelebrantTabView()
                    } else {
                        ContributorTabView()
                    }
                }
            }
        }
        .environmentObject(event)
        .task { await event.start() }
        .onDisappear { event.stop() }
    }
}
