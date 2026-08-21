import Foundation
import SwiftUI
import Combine
import OSLog

// MARK: - Celebrant Tabs

enum CelebrantTab: Int, CaseIterable {
    case rewards = 0
    case challenges
    case timeline
    case profile

    var title: String {
        switch self {
        case .rewards:    return "Rewards"
        case .challenges: return "Challenges"
        case .timeline:   return "Timeline"
        case .profile:    return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .rewards:    return "gift.fill"
        case .challenges: return "bolt.fill"
        case .timeline:   return "safari.fill"
        case .profile:    return "crown.fill"
        }
    }
}

// MARK: - Contributor Tabs

enum ContributorTab: Int, CaseIterable {
    case secretChallenge = 0
    case timeline
    case profile

    var title: String {
        switch self {
        case .secretChallenge: return "Secret Dare"
        case .timeline:        return "Timeline"
        case .profile:         return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .secretChallenge: return "eye.slash.fill"
        case .timeline:        return "safari.fill"
        case .profile:         return "person.crop.circle.fill"
        }
    }
}

// MARK: - EventSession

/// One occasion's scope. Created when the user opens an occasion, destroyed when they leave.
///
/// The split from `AppSession` is deliberate: `AppSession` owns identity and the occasion
/// list and never learns which occasion is open, so nothing about one occasion can leak into
/// the shell that lists them all.
///
/// Listeners registered here are recorded in `registeredListenerKeys` and removed by
/// `stop()` — never `removeAllListeners()`, which would also tear down listeners belonging
/// to a different occasion or to a screen that outlives this session.
@MainActor
final class EventSession: ObservableObject {

    let eventId: String

    @Published var occasion: Occasion?
    @Published var participant: Participant?
    @Published var gameState: GameState = .empty
    /// Set only when `start()` cannot open the occasion at all. Nothing is loaded behind
    /// it, so `EventContainerView` renders it as a full-screen takeover.
    @Published var errorMessage: String?
    /// Set when the game-state listener dies, and deliberately *not* `errorMessage`: the
    /// occasion is loaded and still usable, so this renders as a persistent banner instead
    /// of replacing the screen. Points and progress have stopped updating, and staying
    /// silent would leave the last values on display reading as current.
    @Published var connectionMessage: String?
    @Published var isLoading = true

    /// Tab selection lives here rather than in each tab view so that "check out your
    /// timeline" can switch tabs from a card buried inside another tab.
    @Published var celebrantTab: CelebrantTab = .rewards
    @Published var contributorTab: ContributorTab = .secretChallenge
    @Published var scrollToLatestTimeline = false

    var isHost: Bool { participant?.isHost ?? false }
    var isCelebrant: Bool { participant?.isCelebrant ?? false }
    var currentPoints: Int { gameState.currentPoints }
    var celebrantName: String { occasion?.celebrantName ?? "them" }

    private let service: GameBackend
    private var registeredListenerKeys: Set<String> = []
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "EventSession")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
    }

    func start() async {
        do {
            occasion = try await service.fetchOccasion(eventId: eventId)
            participant = try await service.fetchMyParticipant(eventId: eventId)
            isLoading = false
        } catch {
            logger.error("Opening occasion failed: \(error.localizedDescription)")
            errorMessage = "Couldn't open this occasion."
            isLoading = false
            return
        }

        await retireCelebrantCodeIfNeeded()

        let key = ListenerKey.gameState(eventId)
        registeredListenerKeys.insert(key)
        service.listenToGameState(eventId: eventId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let state):
                    self.gameState = state
                    self.connectionMessage = nil
                case .failure(let error):
                    self.logger.error("Game state listener: \(error.localizedDescription)")
                    self.connectionMessage =
                        "Live updates stopped. Your points and progress may be out of date."
                }
            }
        }
    }

    /// Re-reads the occasion document. The host panel changes `isOpen` through the backend,
    /// and the toggle it renders reads off this cached copy — without a re-read a
    /// successful close still reads "Open to new joins".
    func refreshOccasion() async {
        do {
            occasion = try await service.fetchOccasion(eventId: eventId)
        } catch {
            logger.error("Refreshing the occasion failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        for key in registeredListenerKeys {
            service.removeListener(forKey: key)
        }
        registeredListenerKeys.removeAll()
    }

    /// Retries the second write of the celebrant join.
    ///
    /// Consuming the celebrant code cannot share a transaction with the join that earns the
    /// right to do it, so it is a separate write that can fail on a dropped connection while
    /// the join itself succeeded. Left there, a live celebrant link would stay replayable
    /// forever. Opening the occasion is the one moment we know the caller is the celebrant,
    /// so the retry belongs here rather than in the join screen they have already dismissed.
    ///
    /// Unconditional, not conditional on the code still being set: the codes now live at
    /// `events/{id}/private/codes`, which the celebrant is allowed to write but **not** to
    /// read — that asymmetry is exactly what keeps the code out of member-readable storage.
    /// So the celebrant cannot check whether the first attempt landed, and the honest move is
    /// to re-clear every time. The rule accepts it: re-clearing an already-empty field
    /// produces an empty diff, which `hasOnly(['celebrantCode'])` permits. The cost is one
    /// small write per occasion open, for the celebrant only.
    ///
    /// Silent on failure — the occasion is perfectly usable either way.
    private func retireCelebrantCodeIfNeeded() async {
        guard isCelebrant else { return }
        do {
            try await service.consumeCelebrantCode(eventId: eventId)
            logger.info("Retired the celebrant invite code")
        } catch {
            logger.error("Couldn't retire the celebrant code: \(error.localizedDescription)")
        }
    }

    /// The heartbeat — "Check out your timeline →"
    func navigateToTimeline() {
        BQDesign.Haptics.light()
        withAnimation(BQDesign.Animation.snappy) {
            if isCelebrant {
                celebrantTab = .timeline
            } else {
                contributorTab = .timeline
            }
            scrollToLatestTimeline = true
        }
    }
}
