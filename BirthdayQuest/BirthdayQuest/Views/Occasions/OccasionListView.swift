import SwiftUI

struct OccasionListView: View {

    @EnvironmentObject private var session: AppSession
    @State private var creating = false
    @State private var joining = false
    @State private var openEventId: String?

    private var active: [Occasion] { session.occasions.filter(\.isOpen) }
    private var past: [Occasion] { session.occasions.filter { !$0.isOpen } }

    var body: some View {
        NavigationStack {
            List {
                if !active.isEmpty {
                    Section("Active") {
                        ForEach(active) { row($0) }
                    }
                }
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { row($0) }
                    }
                }
            }
            .navigationTitle("My Occasions")
            .refreshable { await session.refreshOccasions() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create an occasion") { creating = true }
                        Button("Join with a link") { joining = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add an occasion")
                }
            }
            .sheet(isPresented: $creating) { CreateOccasionView(onCreated: { openEventId = $0 }) }
            .sheet(isPresented: $joining) { JoinOccasionView() }
            .navigationDestination(item: $openEventId) { eventId in
                EventContainerView(eventId: eventId)
            }
        }
    }

    private func row(_ occasion: Occasion) -> some View {
        Button {
            openEventId = occasion.id
        } label: {
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text(occasion.name)
                    .font(BQDesign.Typography.cardTitle)
                Text("\(occasion.occasionType.displayName) · \(occasion.celebrantName)")
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
            }
        }
    }
}
