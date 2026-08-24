import SwiftUI
// For `UIPasteboard`. SwiftUI re-exports UIKit on iOS, but the dependency is real, so it is
// named rather than inherited.
import UIKit

/// Host controls for one occasion.
/// Access from the Profile tab. Full game management while the occasion is live.
struct AdminControlsView: View {

    @EnvironmentObject private var event: EventSession
    /// Needed because closing the occasion changes which section of `OccasionListView` it
    /// belongs to. `EventSession` holds this occasion; `AppSession` holds the list.
    @EnvironmentObject private var session: AppSession
    @StateObject private var viewModel: AdminViewModel
    @State private var pointsToAdd: String = ""
    /// Which code the host most recently copied, so its button can confirm it. Held here
    /// rather than per-row because only one confirmation should ever be showing.
    @State private var copiedCode: String?
    @ScaledMetric private var chevronIconSize: CGFloat = 12
    @ScaledMetric private var secretChallengeIconSize: CGFloat = 10
    @ScaledMetric private var crownIconSize: CGFloat = 10
    @ScaledMetric private var sectionHeaderIconSize: CGFloat = 14

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: AdminViewModel(eventId: eventId))
    }

    private var gameState: GameState { event.gameState }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: BQDesign.Spacing.lg) {

                    // 0. Invite links + celebrant-joined status. Kept first: an occasion
                    // whose celebrant never installs the app is unrecoverable, so the host
                    // needs this the moment they open this screen, not after scrolling past
                    // everything else.
                    inviteCard

                    // 0b. Authoring. A row that pushes, not a card that expands: this file
                    // is already the largest view in the app, and R60 forbids a second host
                    // panel, not a second file.
                    authoringCard

                    // 1. Read-only game state dashboard
                    gameStateCard
                    
                    // 2. Points management (existing)
                    pointsCard
                    
                    // 3. Force complete challenges (NEW)
                    forceChallengesCard
                    
                    // 4. Force unlock rewards (NEW)
                    forceRewardsCard
                    
                    // 5. Nuclear options: final badge
                    nuclearOptionsCard

                    // 5b. Roster
                    rosterCard
                    
                    // 6. Day counter + join toggle
                    dayAndJoinsCard
                    
                    Spacer().frame(height: BQDesign.Spacing.xxl)
                }
                .padding(BQDesign.Spacing.lg)
            }
            .background(BQDesign.Colors.background.ignoresSafeArea())
            .navigationTitle("🔧 Host")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if viewModel.isPerformingAction {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .overlay(ProgressView().tint(BQDesign.Colors.primaryPurple))
                        .allowsHitTesting(true)
                }
            }
            // Result alert
            .alert(
                viewModel.actionResult?.isError == true ? "Error" : "Done",
                isPresented: Binding(
                    get: { viewModel.actionResult != nil },
                    set: { if !$0 { viewModel.actionResult = nil } }
                )
            ) {
                Button("OK") { viewModel.actionResult = nil }
            } message: {
                Text(viewModel.actionResult?.message ?? "")
            }
            // Force complete confirmation
            .confirmationDialog(
                "Force Complete Challenge?",
                isPresented: Binding(
                    get: { viewModel.challengeToComplete != nil },
                    set: { if !$0 { viewModel.challengeToComplete = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let challenge = viewModel.challengeToComplete {
                    Button("Complete (+\(challenge.pointValue)✦, no proof)") {
                        Task { await viewModel.forceCompleteChallenge(challenge) }
                    }
                    Button("Cancel", role: .cancel) { viewModel.challengeToComplete = nil }
                }
            } message: {
                if let challenge = viewModel.challengeToComplete {
                    Text("Force complete \"\(challenge.title)\"? Awards \(challenge.pointValue)✦ with no proof upload.")
                }
            }
            // Force unlock confirmation
            .confirmationDialog(
                "Force Unlock Reward?",
                isPresented: Binding(
                    get: { viewModel.rewardToUnlock != nil },
                    set: { if !$0 { viewModel.rewardToUnlock = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let reward = viewModel.rewardToUnlock {
                    Button("Free Unlock (no points deducted)") {
                        Task { await viewModel.forceUnlockReward(reward, deductPoints: false) }
                    }
                    Button("Unlock & Deduct \(reward.pointCost)✦") {
                        Task { await viewModel.forceUnlockReward(reward, deductPoints: true) }
                    }
                    Button("Cancel", role: .cancel) { viewModel.rewardToUnlock = nil }
                }
            } message: {
                if let reward = viewModel.rewardToUnlock {
                    Text("Unlock \"\(reward.fromName)'s gift\" (\(reward.pointCost)✦)?")
                }
            }
            // Force final badge confirmation
            .confirmationDialog(
                "Trigger Final Celebration?",
                isPresented: $viewModel.showFinalBadgeConfirm,
                titleVisibility: .visible
            ) {
                Button("🎉 Trigger It", role: .destructive) {
                    Task { await viewModel.forceFinalBadge() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is the big moment. The final badge celebration will trigger for everyone. Make sure you're ready.")
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }
}

// MARK: - Section 0: Invite Links + Celebrant Status

private extension AdminControlsView {

    var celebrantLabel: String {
        event.occasion?.occasionType.celebrantLabel ?? "guest of honour"
    }

    /// The codes come from `viewModel.inviteCodes`, not from `event.occasion`: they live at
    /// `events/{id}/private/codes`, which only the host can read, because a member who could
    /// read the celebrant code could hand it to anyone and have them claim the celebrant role.
    var inviteCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Invite", icon: "square.and.arrow.up")

            switch viewModel.codesState {
            case .loading:
                Text("Loading your invite links…")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textSecondary)

            case .failed(let message):
                adminInlineFailure(message) {
                    Task { await viewModel.loadInviteCodes() }
                }

            // A host's codes document always exists, so there is no legitimate empty state —
            // `loadInviteCodes()` reports a missing document as a failure. Handled rather than
            // defaulted so adding a case to `ContentState` cannot silently render nothing.
            case .empty, .ready:
                if let codes = viewModel.inviteCodes {
                    inviteRows(codes)
                }
            }

            celebrantStatusBanner
        }
        .adminCard()
    }

    @ViewBuilder
    func inviteRows(_ codes: InviteCodes) -> some View {
        // The friend code has no consumed state — it is reusable for the life of the
        // occasion — so a missing link here means the stored code is unusable rather than
        // spent. Still says so: rendering nothing is what this whole card is being fixed for.
        inviteBlock(
            title: "Friends",
            icon: "person.2.fill",
            shareLabel: "Share the friend link",
            code: codes.contributorCode,
            link: codes.contributorLink,
            missingNote: "The friend link isn't usable. Ask for help before sharing this occasion."
        )

        Divider()

        // A consumed celebrant code is blank, so there is no link and no code left to show.
        // Say that, rather than silently rendering nothing: the code is single-use by design
        // and "the row vanished" is not an explanation.
        inviteBlock(
            title: celebrantLabel,
            icon: "gift.fill",
            shareLabel: "Share the \(celebrantLabel) link",
            code: codes.celebrantCode,
            link: codes.celebrantLink,
            missingNote: "The \(celebrantLabel) link has already been used — it only works once."
        )
    }

    /// One invitation: the share sheet, and the code underneath it as a copyable fallback.
    ///
    /// The code is not a debug detail. `birthdayquest://` is a custom scheme, and Messages,
    /// WhatsApp and Mail all render an unknown scheme as inert plain text — so for most of
    /// the ways a host actually shares this, the tappable link the `ShareLink` produces
    /// arrives as something the recipient has to retype. The code *is* the delivery mechanism
    /// in that case, which is why it gets a real copy affordance rather than selectable text.
    /// `missingNote` is not optional. It was, and the friend row passed `nil` — so a code that
    /// failed to form a link rendered as nothing at all, in the same card being fixed for
    /// exactly that. Every branch here says something.
    @ViewBuilder
    func inviteBlock(
        title: String,
        icon: String,
        shareLabel: String,
        code: String,
        link: URL?,
        missingNote: String
    ) -> some View {
        if let link {
            VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
                ShareLink(item: link) {
                    adminLinkRow(shareLabel, icon: icon)
                }
                codeRow(title: title, code: code)
            }
        } else {
            Text(missingNote)
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `Copied` replaces the button's own label rather than appearing as a toast: the
    /// confirmation belongs where the tap happened, and a pasteboard write is instant, so
    /// there is nothing to wait for.
    func codeRow(title: String, code: String) -> some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Text(code)
                .font(BQDesign.Typography.body.monospaced())
                .foregroundColor(BQDesign.Colors.textPrimary)
                // Read out one character at a time. A code exists to be dictated or typed,
                // and VoiceOver pronounces "ABCD2345" as a mangled word by default.
                .accessibilityLabel("\(title) code, \(code.map(String.init).joined(separator: " "))")

            Spacer()

            Button {
                UIPasteboard.general.string = code
                BQDesign.Haptics.light()
                copiedCode = code
            } label: {
                // Both states carry a word, not just a tick: colour and glyph alone would
                // leave "did that work?" to be inferred.
                Label(
                    copiedCode == code ? "Copied" : "Copy",
                    systemImage: copiedCode == code ? "checkmark" : "doc.on.doc"
                )
                .font(BQDesign.Typography.captionSmall)
                .fontWeight(.semibold)
                .foregroundColor(BQDesign.Colors.primaryPurple)
                // 44pt is the HIG minimum; the label alone is about half that.
                .frame(minWidth: 88, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(copiedCode == code ? "Copied the \(title) code" : "Copy the \(title) code")
        }
        // Re-arms if the host copies the other code, and after the confirmation has been
        // read. Tied to the value rather than a timer started at tap, so copying the same
        // code twice still re-shows it.
        .task(id: copiedCode) {
            guard copiedCode == code else { return }
            try? await Task.sleep(for: .seconds(3))
            if copiedCode == code { copiedCode = nil }
        }
    }

    func adminLinkRow(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(BQDesign.Colors.primaryPurple)
            Text(title)
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.primaryPurple)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: chevronIconSize, weight: .semibold))
                .foregroundColor(BQDesign.Colors.textTertiary)
        }
        .frame(minHeight: 44)
    }

    /// The spec's #1 named risk: there is deliberately no handover mode, so a celebrant who
    /// never installs the app cannot be rescued on the day. Surfacing this unmissably, right
    /// where the invite links live, is the mitigation.
    ///
    /// Three branches, not two. The `unknown` case exists because a failed roster read used
    /// to render as a confident "they haven't joined yet" — a claim about data the app never
    /// received, on the one banner the host is meant to act on.
    @ViewBuilder
    var celebrantStatusBanner: some View {
        switch viewModel.celebrantPresence {
        case .joined:
            // `Colors.success` is used on the icon only; the sentence stays at
            // `textPrimary`, which clears 4.5:1. Same split as `OccasionListView.errorRow`.
            celebrantBanner(
                "\(celebrantDisplayName) has joined.",
                icon: "checkmark.circle.fill",
                tint: BQDesign.Colors.success
            )

        case .notJoined:
            celebrantBanner(
                "\(celebrantDisplayName) hasn't joined yet. Share the link above — they need "
                    + "the app installed to open their gifts.",
                icon: "exclamationmark.triangle.fill",
                tint: BQDesign.Colors.error
            )

        case .unknown:
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                celebrantBanner(
                    "Couldn't check whether \(celebrantDisplayName) has joined.",
                    icon: "questionmark.circle.fill",
                    tint: BQDesign.Colors.textSecondary
                )
                Button("Check again") {
                    Task { await viewModel.loadRoster() }
                }
                .font(BQDesign.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(BQDesign.Colors.primaryPurple)
                .frame(minHeight: 44)
            }
        }
    }

    var celebrantDisplayName: String {
        event.occasion?.celebrantName ?? "The \(celebrantLabel)"
    }

    func celebrantBanner(_ message: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(BQDesign.Typography.caption)
                .foregroundColor(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    /// Shared by the two one-shot reads on this screen. Both are single attempts with no
    /// second snapshot coming, so neither may end in a message without a way forward.
    func adminInlineFailure(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.error)
                    .accessibilityHidden(true)
                Text(message)
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)

            Button("Try again", action: retry)
                .font(BQDesign.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(BQDesign.Colors.primaryPurple)
                .frame(minHeight: 44)
        }
    }
}

// MARK: - Section 1: Game State Overview

private extension AdminControlsView {
    
    var gameStateCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Game Overview", icon: "chart.bar.fill")
            
            VStack(spacing: BQDesign.Spacing.xs) {
                adminRow("Points", "\(gameState.currentPoints) (earned: \(gameState.totalPointsEarned), spent: \(gameState.totalPointsSpent))")
                adminRow("Challenges", "\(gameState.challengesCompleted)/\(gameState.totalChallenges)")
                adminRow("Rewards", "\(gameState.rewardsUnlocked)/\(gameState.totalRewards)")
                adminRow("Secrets", "Found: \(gameState.secretChallengesFound), Done: \(gameState.secretChallengesCompleted)")
                adminRow("Day", "\(gameState.currentDay)")
                adminRow("Final Badge", gameState.finalBadgeUnlocked ? "✅ Unlocked" : "🔒 Locked")
            }
        }
        .adminCard()
    }
}

// MARK: - Section 2: Points Management

private extension AdminControlsView {
    
    var pointsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Points", icon: "star.fill")
            
            HStack(spacing: BQDesign.Spacing.sm) {
                TextField("Amount", text: $pointsToAdd)
                    .keyboardType(.numberPad)
                    .font(BQDesign.Typography.body)
                    .padding(BQDesign.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.sm)
                            .stroke(BQDesign.Colors.textTertiary.opacity(0.5))
                    )
                
                adminActionButton("Add", color: BQDesign.Colors.success) {
                    guard let amount = Int(pointsToAdd), amount > 0 else { return }
                    Task {
                        await viewModel.addPoints(amount)
                        pointsToAdd = ""
                    }
                }
                
                adminActionButton("Remove", color: BQDesign.Colors.secretAccent) {
                    guard let amount = Int(pointsToAdd), amount > 0 else { return }
                    Task {
                        await viewModel.removePoints(amount)
                        pointsToAdd = ""
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 3: Force Complete Challenges

private extension AdminControlsView {
    
    var forceChallengesCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Force Complete Challenge", icon: "bolt.fill")
            
            if viewModel.incompleteChallenges.isEmpty {
                adminEmptyState("✅ All challenges completed")
            } else {
                VStack(spacing: BQDesign.Spacing.sm) {
                    ForEach(viewModel.incompleteChallenges) { challenge in
                        HStack(spacing: BQDesign.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if challenge.isSecret {
                                        Image(systemName: "eye.slash.fill")
                                            .font(.system(size: secretChallengeIconSize))
                                            .foregroundColor(BQDesign.Colors.secretAccent)
                                    }
                                    // Kept single-line: this is a compact management-list row,
                                    // and the full title is still reachable via the "Force
                                    // Complete Challenge?" confirmation dialog this row opens.
                                    Text(challenge.title)
                                        .font(BQDesign.Typography.caption)
                                        .foregroundColor(BQDesign.Colors.textPrimary)
                                        .lineLimit(1)
                                }
                                Text("\(challenge.pointValue)✦ · \(challenge.difficulty.rawValue)")
                                    .font(BQDesign.Typography.captionSmall)
                                    .foregroundColor(BQDesign.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            adminActionButton("Complete", color: BQDesign.Colors.challengeBlue) {
                                viewModel.challengeToComplete = challenge
                            }
                        }
                        .padding(BQDesign.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .fill(BQDesign.Colors.background)
                        )
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 4: Force Unlock Rewards

private extension AdminControlsView {
    
    var forceRewardsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Force Unlock Reward", icon: "gift.fill")
            
            if viewModel.lockedRewards.isEmpty {
                adminEmptyState("✅ All rewards unlocked")
            } else {
                VStack(spacing: BQDesign.Spacing.sm) {
                    ForEach(viewModel.lockedRewards) { reward in
                        HStack(spacing: BQDesign.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reward.fromName)
                                    .font(BQDesign.Typography.caption)
                                    .foregroundColor(BQDesign.Colors.textPrimary)
                                Text("\(reward.pointCost)✦ · \(reward.contentType.rawValue)")
                                    .font(BQDesign.Typography.captionSmall)
                                    .foregroundColor(BQDesign.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            adminActionButton("Unlock", color: BQDesign.Colors.gold) {
                                viewModel.rewardToUnlock = reward
                            }
                        }
                        .padding(BQDesign.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .fill(BQDesign.Colors.background)
                        )
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 5: Nuclear Options

private extension AdminControlsView {
    
    var nuclearOptionsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Nuclear Options", icon: "exclamationmark.triangle.fill")
            
            // Force Final Badge
            if !gameState.finalBadgeUnlocked {
                Button {
                    viewModel.showFinalBadgeConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Force Final Badge")
                            .font(BQDesign.Typography.bodyBold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: chevronIconSize, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(BQDesign.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                            .fill(BQDesign.Colors.primaryGradient)
                    )
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(BQDesign.Colors.success)
                    Text("Final badge already triggered")
                        .font(BQDesign.Typography.caption)
                        .foregroundColor(BQDesign.Colors.textSecondary)
                }
            }
            
        }
        .adminCard()
    }

    /// Switches on `rosterState`, not on `otherParticipants.isEmpty`.
    ///
    /// Those two are not the same question, and conflating them is what made a refused or
    /// offline read render "Nobody else has joined yet" — an authoritative statement about a
    /// roster the app had never seen, complete with an instruction to go share a link the
    /// host may well have already shared successfully.
    @ViewBuilder
    var rosterCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Who's Here", icon: "person.2.fill")

            switch viewModel.rosterState {
            case .loading:
                adminEmptyState("Checking who has joined…")

            case .failed(let message):
                adminInlineFailure(message) {
                    Task { await viewModel.loadRoster() }
                }

            case .empty:
                adminEmptyState("Nobody else has joined yet. Share your invite link.")

            case .ready:
                VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                    ForEach(viewModel.otherParticipants) { participant in
                        HStack(spacing: BQDesign.Spacing.sm) {
                            AvatarView(avatarId: participant.avatarId, size: 28)
                            Text(participant.name)
                                .font(BQDesign.Typography.caption)
                                .foregroundColor(BQDesign.Colors.textPrimary)

                            if participant.isCelebrant {
                                Text("👑")
                                    .font(.system(size: crownIconSize))
                            }

                            Spacer()
                        }
                        .padding(BQDesign.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                                .fill(BQDesign.Colors.background)
                        )
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 6: Day Counter + Joins

private extension AdminControlsView {

    var isOpen: Bool { event.occasion?.isOpen ?? true }

    var dayAndJoinsCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.md) {
            adminSectionHeader("Day & Joins", icon: "calendar")
            
            // Day counter
            HStack(spacing: BQDesign.Spacing.sm) {
                Text("Current: Day \(gameState.currentDay)")
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                
                Spacer()
                
                adminActionButton("+ Day", color: BQDesign.Colors.primaryPurple) {
                    Task {
                        await viewModel.advanceDay(from: gameState.currentDay)
                    }
                }
            }
            
            Divider()

            // Open / close to new joins
            HStack(spacing: BQDesign.Spacing.sm) {
                Text(isOpen ? "Open to new joins" : "Closed to new joins")
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textPrimary)

                Spacer()

                adminActionButton(
                    isOpen ? "Close" : "Reopen",
                    color: BQDesign.Colors.secretAccent
                ) {
                    Task {
                        guard await viewModel.setOpen(!isOpen) else { return }
                        // Two caches hold this occasion, and both render `isOpen`. This
                        // screen's label reads `EventSession.occasion`; the Active/Past split
                        // on `OccasionListView` reads `AppSession.occasions`. Refreshing only
                        // the first left the list claiming a closed occasion was still open
                        // until something else happened to reload it.
                        await event.refreshOccasion()
                        await session.refreshOccasions()
                    }
                }
            }
        }
        .adminCard()
    }
}

// MARK: - Section 0b: Authoring

private extension AdminControlsView {

    var authoringCard: some View {
        VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
            adminSectionHeader("Content", icon: "square.and.pencil")

            NavigationLink {
                ChallengeAuthoringView(eventId: event.eventId)
                    .environmentObject(event)
            } label: {
                authoringRow(
                    "Challenges",
                    subtitle: "\(viewModel.challenges.filter { !$0.isSecret }.count) added",
                    icon: "flag.checkered"
                )
            }

            // Task 12 adds the Gifts link here, once GiftCurationView exists.
        }
        .adminCard()
    }

    func authoringRow(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: sectionHeaderIconSize))
                .foregroundStyle(BQDesign.Colors.primaryPurple)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
                Text(subtitle)
                    .font(BQDesign.Typography.captionSmall)
                    .foregroundStyle(BQDesign.Colors.textSecondary)
                    .monospacedDigit()
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: chevronIconSize))
                .foregroundStyle(BQDesign.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(BQDesign.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.sm, style: .continuous)
                .fill(BQDesign.Colors.background)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared Admin UI Components

private extension AdminControlsView {

    func adminSectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: BQDesign.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: sectionHeaderIconSize, weight: .semibold))
                .foregroundColor(BQDesign.Colors.primaryPurple)
            Text(text)
                .font(BQDesign.Typography.cardTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
        }
    }
    
    func adminRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(BQDesign.Typography.captionSmall)
                .foregroundColor(BQDesign.Colors.textPrimary)
        }
    }
    
    func adminActionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BQDesign.Typography.captionSmall)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, BQDesign.Spacing.md)
                .padding(.vertical, BQDesign.Spacing.sm)
                .background(Capsule().fill(color))
        }
    }
    
    func adminEmptyState(_ text: String) -> some View {
        Text(text)
            .font(BQDesign.Typography.caption)
            .foregroundColor(BQDesign.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, BQDesign.Spacing.sm)
    }
}

// MARK: - Admin Card Modifier

private extension View {
    func adminCard() -> some View {
        self
            .padding(BQDesign.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                    .fill(BQDesign.Colors.cardBackground)
            )
            .bqShadow(BQDesign.Shadows.card)
    }
}
