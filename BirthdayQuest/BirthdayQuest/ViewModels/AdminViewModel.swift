import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import OSLog

// MARK: - Action Result

struct AdminActionResult: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

// MARK: - Celebrant Presence

/// Whether the guest of honour has joined — including the case where we could not find out.
///
/// This replaced a `Bool`, which had no way to say "the read failed". A refused or offline
/// roster read left it `false`, and the host panel rendered the spec's most important warning
/// — "they haven't joined yet" — as settled fact about a roster it had never seen. The host's
/// correct response to that warning is to chase the celebrant, so the lie costs them a real
/// conversation; and the same failure could equally be hiding a celebrant who *had* joined.
///
/// `unknown` is not a nicety. There is deliberately no handover mode, so this banner is the
/// entire mitigation for the spec's #1 risk, and a mitigation that fabricates its input is
/// worse than none.
nonisolated enum CelebrantPresence: Equatable {
    case unknown
    case joined
    case notJoined
}

// MARK: - Admin View Model

@MainActor
final class AdminViewModel: ObservableObject {
    
    // MARK: - Published Data
    
    @Published var challenges: [Challenge] = []
    @Published var rewards: [Reward] = []
    @Published var participants: [Participant] = []
    /// Whether the roster read has landed, and what to render if it has not.
    ///
    /// `failed` and `empty` are separate cases of one enum precisely so the view cannot show
    /// both, and so a test can assert the branch the view will take. See `ContentState`.
    @Published private(set) var rosterState: ContentState = .loading
    /// The occasion's invite codes. Loaded here rather than read off `EventSession.occasion`
    /// because they no longer live on the event document — they live at
    /// `events/{id}/private/codes`, which only the host can read. This view model is the host
    /// panel, so this is the one place in the app entitled to them.
    @Published var inviteCodes: InviteCodes?
    /// Whether the invite-code read has landed. See `loadInviteCodes()`.
    @Published private(set) var codesState: ContentState = .loading
    @Published var actionResult: AdminActionResult?
    @Published var isPerformingAction = false
    
    // MARK: - Confirmation State
    
    @Published var challengeToComplete: Challenge?
    @Published var rewardToUnlock: Reward?
    @Published var rewardUnlockDeductsPoints = false
    @Published var showFinalBadgeConfirm = false
    
    private let service: GameBackend
    private let eventId: String
    private let challengesListenerKey: String
    private let rewardsListenerKey: String
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Admin")

    init(eventId: String, service: GameBackend = FirestoreService.shared) {
        self.eventId = eventId
        self.service = service
        self.challengesListenerKey = ListenerKey.scoped("admin_challenges", eventId: eventId)
        self.rewardsListenerKey = ListenerKey.scoped("admin_rewards", eventId: eventId)
    }
    
    // MARK: - Computed Filters
    
    var incompleteChallenges: [Challenge] {
        challenges.filter { !$0.isCompleted }.sorted { $0.pointValue < $1.pointValue }
    }
    
    var lockedRewards: [Reward] {
        rewards.filter { !$0.isUnlocked }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    /// Everyone in the occasion apart from the host looking at this screen.
    var otherParticipants: [Participant] {
        participants.filter { !$0.isHost }
    }

    /// Whether anyone with `mode == .celebrant` has joined yet. There is no handover mode,
    /// so an occasion whose celebrant never installs the app cannot be rescued on the day —
    /// this has to be checked from the moment the occasion is created, not discovered late.
    ///
    /// Derived from `rosterState` rather than from `participants` alone, so an unread roster
    /// cannot masquerade as an empty one.
    var celebrantPresence: CelebrantPresence {
        switch rosterState {
        case .loading, .failed:
            return .unknown
        case .empty, .ready:
            return participants.contains { $0.isCelebrant } ? .joined : .notJoined
        }
    }
    
    // MARK: - Listener Lifecycle
    
    func startListening() {
        service.listenToChallenges(
            eventId: eventId, listenerKey: challengesListenerKey
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let challenges):
                    self.challenges = challenges
                case .failure(let error):
                    self.report("challenges", error)
                }
            }
        }

        // A key of its own, not the carousel's. A host who is also the celebrant has both
        // screens alive in one tab bar, and SwiftUI runs the incoming tab's onAppear before
        // the outgoing hierarchy's onDisappear — sharing the key would let this screen's
        // teardown silently kill the carousel's listener and strand it loading.
        service.listenToRewards(
            eventId: eventId, listenerKey: rewardsListenerKey
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let rewards):
                    self.rewards = rewards
                case .failure(let error):
                    self.report("gifts", error)
                }
            }
        }

        Task { await loadRoster() }
        Task { await loadInviteCodes() }
    }
    
    func stopListening() {
        service.removeListener(forKey: challengesListenerKey)
        service.removeListener(forKey: rewardsListenerKey)
    }

    /// A listener failure is a first-class outcome now that membership can be revoked:
    /// permission-denied arrives here the moment a host removes themselves. Surfacing it
    /// through the same alert as every other admin action means it can't be mistaken for
    /// an empty occasion.
    private func report(_ subject: String, _ error: Error) {
        logger.error("Admin \(subject) listener: \(error.localizedDescription)")
        actionResult = AdminActionResult(
            message: "❌ Lost the live feed for \(subject). Reopen this panel to retry.",
            isError: true
        )
    }

    /// The roster is a one-shot read, not a listener: participants change when someone
    /// joins, which is rare enough that a live subscription would cost more than it earns.
    ///
    /// Being one-shot is also why the failure needs a retry the host can reach: there is no
    /// second snapshot coming to quietly correct it.
    func loadRoster() async {
        rosterState = .loading
        do {
            participants = try await service.fetchParticipants(eventId: eventId)
            rosterState = otherParticipants.isEmpty ? .empty : .ready
        } catch {
            logger.error("Loading the roster failed: \(error.localizedDescription)")
            // Cleared, not left stale. A retry that fails must not leave the previous read's
            // names on screen under a failure message.
            participants = []
            rosterState = .failed("Couldn't check who has joined.")
        }
    }

    /// Also one-shot: codes only change if the host rotates them, and the host is the person
    /// looking at this screen.
    ///
    /// Carries its own state for the same reason the roster does. A failure used to leave
    /// `inviteCodes` nil, which is indistinguishable from "not loaded yet" — so the card sat
    /// on "Loading your invite links…" permanently, with no spinner ever resolving and no way
    /// to retry. A one-shot read has no second chance to arrive.
    func loadInviteCodes() async {
        codesState = .loading
        do {
            inviteCodes = try await service.fetchInviteCodes(eventId: eventId)
            // A nil result without an error means the document is missing, which for a host
            // should not happen — phase 2 of occasion creation writes it. Reported as a
            // failure rather than as an empty state: there is nothing legitimate to show.
            codesState = inviteCodes == nil
                ? .failed("Couldn't find this occasion's invite codes.")
                : .ready
        } catch {
            logger.error("Loading the invite codes failed: \(error.localizedDescription)")
            inviteCodes = nil
            codesState = .failed("Couldn't load your invite links.")
        }
    }
    
    // MARK: - Force Complete Challenge
    
    func forceCompleteChallenge(_ challenge: Challenge) async {
        guard let challengeId = challenge.id else { return }
        isPerformingAction = true
        
        let timelineEvent = TimelineEvent(
            type: .challengeCompleted,
            referenceId: challengeId,
            title: challenge.title,
            subtitle: "+\(challenge.pointValue) ✦",
            badgeType: .challenge,
            badgeAsset: challenge.illustrationAsset,
            fromFriendName: nil,
            fromFriendAvatar: nil,
            timestamp: Date()
        )
        
        do {
            try await service.completeChallengeAtomically(
                eventId: eventId,
                challengeId: challengeId,
                pointValue: challenge.pointValue,
                isSecret: challenge.isSecret,
                proofUrl: nil,
                proofType: nil,
                proofText: nil,
                timelineEvent: timelineEvent
            )
            actionResult = AdminActionResult(
                message: "✅ Force completed \"\(challenge.title)\" (+\(challenge.pointValue)✦)",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
        
        isPerformingAction = false
    }
    
    // MARK: - Force Unlock Reward
    
    func forceUnlockReward(_ reward: Reward, deductPoints: Bool) async {
        guard let rewardId = reward.id else { return }
        isPerformingAction = true
        
        let timelineEvent = TimelineEvent(
            type: .rewardUnlocked,
            referenceId: rewardId,
            title: "Unlocked \(reward.fromName)'s gift",
            subtitle: deductPoints ? "-\(reward.pointCost) ✦" : "🎁 Free unlock",
            badgeType: .reward,
            badgeAsset: reward.badgeIllustration,
            fromFriendName: reward.fromName,
            fromFriendAvatar: nil,
            timestamp: Date()
        )
        
        do {
            try await service.adminForceUnlockReward(
                eventId: eventId,
                rewardId: rewardId,
                pointCost: reward.pointCost,
                deductPoints: deductPoints,
                timelineEvent: timelineEvent
            )
            let costLabel = deductPoints ? " (-\(reward.pointCost)✦)" : " (free)"
            actionResult = AdminActionResult(
                message: "✅ Unlocked \(reward.fromName)'s gift\(costLabel)",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
        
        isPerformingAction = false
    }
    
    // MARK: - Force Final Badge
    
    func forceFinalBadge() async {
        isPerformingAction = true
        
        do {
            try await service.updateGameState(eventId: eventId, fields: [
                "allRewardsUnlocked": true,
                "finalBadgeUnlocked": true,
                "finalBadgeUnlockedAt": Timestamp(date: Date())
            ])
            actionResult = AdminActionResult(
                message: "🎉 Final badge triggered! The big moment is here.",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }
        
        isPerformingAction = false
    }
    
    // MARK: - Adjust Points

    /// Grants points and credits them to the earned total.
    func addPoints(_ amount: Int) async {
        isPerformingAction = true

        do {
            try await service.updateGameState(eventId: eventId, fields: [
                "currentPoints": FieldValue.increment(Int64(amount)),
                "totalPointsEarned": FieldValue.increment(Int64(amount))
            ])
            actionResult = AdminActionResult(
                message: "✦ Added \(amount) points.",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed to add points: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }

        isPerformingAction = false
    }

    /// Removes points from the current balance. Does not touch the earned total,
    /// so the running history of what was earned stays accurate.
    func removePoints(_ amount: Int) async {
        isPerformingAction = true

        do {
            try await service.updateGameState(eventId: eventId, fields: [
                "currentPoints": FieldValue.increment(Int64(-amount))
            ])
            actionResult = AdminActionResult(
                message: "✦ Removed \(amount) points.",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed to remove points: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }

        isPerformingAction = false
    }

    // MARK: - Advance Day

    func advanceDay(from currentDay: Int) async {
        isPerformingAction = true

        do {
            try await service.updateGameState(
                eventId: eventId, fields: ["currentDay": currentDay + 1]
            )
            actionResult = AdminActionResult(
                message: "📅 Now on day \(currentDay + 1).",
                isError: false
            )
            BQDesign.Haptics.success()
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed to advance the day: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
        }

        isPerformingAction = false
    }

    // MARK: - Open / Close the Occasion

    /// Closing an occasion stops new joins. It is a plain host toggle, not a lifecycle
    /// state: nothing else in the app reads it as a phase.
    /// Returns whether the write landed, so the caller can re-read the occasion. The
    /// toggle's label comes from `EventSession.occasion`, which is fetched once at open —
    /// without a refresh a successful close still reads "Open to new joins".
    @discardableResult
    func setOpen(_ isOpen: Bool) async -> Bool {
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await service.setOccasionOpen(eventId: eventId, isOpen: isOpen)
            actionResult = AdminActionResult(
                message: isOpen ? "🔓 Open to new joins." : "🔒 Closed to new joins.",
                isError: false
            )
            BQDesign.Haptics.success()
            return true
        } catch {
            actionResult = AdminActionResult(
                message: "❌ Failed: \(error.localizedDescription)",
                isError: true
            )
            BQDesign.Haptics.error()
            return false
        }
    }
}
