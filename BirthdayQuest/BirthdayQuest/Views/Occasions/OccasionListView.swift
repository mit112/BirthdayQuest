import AuthenticationServices
import OSLog
import SwiftUI

struct OccasionListView: View {

    @EnvironmentObject private var session: AppSession

    /// Read only to pick between Apple's two *provided* Sign in with Apple button styles — see
    /// `appleLinkControl`. Nothing else in this file may branch on it; every colour is a token.
    @Environment(\.colorScheme) private var colorScheme

    @State private var creating = false
    @State private var joining = false
    @State private var showingAccount = false
    @State private var openEventId: String?

    /// The raw nonce has to survive from `onRequest` to `onCompletion`. Apple is handed its
    /// SHA-256 and signs the digest; Firebase is handed *this* value and re-derives the digest
    /// to compare. Sending the digest on to Firebase — or the raw value to Apple — fails the
    /// comparison with an opaque invalid-credential error, so the two must not be confused.
    @State private var rawNonce: String?
    @State private var isLinking = false

    /// An opt-in prompt gets asked at most once per session; declining demotes the banner to
    /// the quieter footer row rather than hiding the affordance, so "no" is honoured without
    /// stranding a user who changes their mind.
    @State private var linkPromptDeclined = false

    private static let logger = Logger(subsystem: "com.example.birthdayquest", category: "AppleLink")

    /// 48pt clears the 44pt HIG touch minimum and sits on the 8pt scale, so Apple's button
    /// keeps the list's rhythm. Everything else about the button is left to Apple.
    private static let appleButtonHeight = BQDesign.Spacing.xxl

    private var active: [Occasion] { session.occasions.filter(\.isOpen) }
    private var past: [Occasion] { session.occasions.filter { !$0.isOpen } }

    /// `shouldPromptAppleLink` is the spec's "second join" trigger — it already guarantees
    /// more than one occasion, which is why the banner copy can say "occasions" unhedged.
    private var showsLinkBanner: Bool { session.shouldPromptAppleLink && !linkPromptDeclined }
    private var showsLinkRow: Bool { session.isAnonymous && !showsLinkBanner }

    var body: some View {
        NavigationStack {
            List {
                if showsLinkBanner { appleLinkBanner }
                if let errorMessage = session.errorMessage { errorRow(errorMessage) }
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
                if showsLinkRow { appleLinkRow }
            }
            .navigationTitle("My Occasions")
            .refreshable { await session.refreshOccasions() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingAccount = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Account")
                }
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
            .sheet(isPresented: $creating) { CreateOccasionView() }
            .sheet(isPresented: $joining) { JoinOccasionView() }
            .sheet(isPresented: $showingAccount) { AccountView() }
            .navigationDestination(item: $openEventId) { eventId in
                EventContainerView(eventId: eventId)
            }
            // `task(id:)` rather than `onChange` because this view is often *new* when the
            // request arrives: creating a first occasion swaps the root from
            // `EmptyOccasionsView` to this one, and an `onChange` on a freshly-appeared view
            // never sees the value that was set before it existed.
            .task(id: session.pendingOpenEventId) {
                guard let pending = session.pendingOpenEventId else { return }
                openEventId = pending
                session.pendingOpenEventId = nil
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

    // MARK: - Errors

    /// `AppSession.errorMessage` had no renderer on this screen at all, so a failed refresh
    /// — and now a failed Apple link — had nowhere to surface.
    private func errorRow(_ message: String) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: BQDesign.Spacing.sm) {
                // The icon carries the severity in colour so the sentence can stay at full
                // contrast: `Colors.error` measures 3.8:1 on white, under the 4.5:1 floor
                // for 14pt text, and colour must not be the only signal regardless.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.error)
                Text(message)
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(message)")
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: - Apple link

    /// The loud form. Identity here is an anonymous Firebase uid held by this install, and
    /// `hostUid` is immutable in the security rules, so the risk being described is literal:
    /// there is no recovery path and no host transfer.
    private var appleLinkBanner: some View {
        Section {
            Text("This iPhone is the only key to your occasions")
                .font(BQDesign.Typography.cardTitle)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("""
                 Nothing but this app install identifies you. Delete BirthdayQuest or move to a \
                 new iPhone and your \(session.occasions.count) occasions can't be recovered — \
                 including the ones you host, which nobody can transfer for you.
                 """)
                .font(BQDesign.Typography.caption)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            appleLinkControl

            Button("Not now") { linkPromptDeclined = true }
                .font(BQDesign.Typography.caption)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .accessibilityHint("Keeps the shorter reminder at the bottom of this list.")
        }
    }

    /// The quiet form: still reachable, no longer the loudest thing on the screen.
    private var appleLinkRow: some View {
        Section {
            appleLinkControl
        } footer: {
            Text("""
                 Your occasions are tied to this app install. Linking your Apple ID is the only \
                 way to open them on a new iPhone.
                 """)
                .font(BQDesign.Typography.captionSmall)
                .foregroundStyle(BQDesign.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shared by both forms. While a link is in flight the button is *replaced* rather than
    /// disabled — a dead control with no explanation is its own defect, and taking it off the
    /// screen is also what makes a second request impossible.
    @ViewBuilder
    private var appleLinkControl: some View {
        if isLinking {
            HStack(spacing: BQDesign.Spacing.sm) {
                ProgressView()
                Text("Linking your Apple ID…")
                    .font(BQDesign.Typography.caption)
                    .foregroundStyle(BQDesign.Colors.textPrimary)
            }
            // `minHeight`, not `height`: this row matches the Apple button's height at the default
            // text size, but the label scales with Dynamic Type and a fixed height would clip it.
            // The button below keeps a fixed height because it is a system control that sizes itself.
            .frame(minHeight: Self.appleButtonHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Linking your Apple ID")
        } else {
            SignInWithAppleButton(.continue) { request in
                prepare(request)
            } onCompletion: { result in
                finish(result)
            }
            // The one place reading `colorScheme` directly is correct: this selects between two
            // Apple-*provided* button styles rather than choosing a colour, and Apple's own
            // guidance is black on light, white on dark. A `.black` button disappears into the
            // #15131C dark background.
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: Self.appleButtonHeight)
            .accessibilityHint("Links your Apple ID so these occasions can be opened on another iPhone.")
        }
    }

    private func prepare(_ request: ASAuthorizationAppleIDRequest) {
        session.errorMessage = nil
        isLinking = true

        let nonce = AuthService.randomNonce()
        rawNonce = nonce
        request.nonce = AuthService.sha256(nonce)
        // `requestedScopes` is deliberately left unset. `FirebaseAuthProvider` builds its
        // credential with `fullName: nil` and never reads `credential.email`, so requesting
        // the name and email scopes would collect personal data only to discard it.
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        let nonce = rawNonce
        rawNonce = nil

        switch result {
        case .failure(let error):
            report(error)

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                fail("Apple returned a sign-in type this app can't use. Try again.",
                     diagnosis: "unexpected credential \(type(of: authorization.credential))")
                return
            }
            guard let tokenData = credential.identityToken else {
                fail("Apple didn't include a sign-in token. Try again.",
                     diagnosis: "credential carried no identityToken")
                return
            }
            guard let idToken = String(data: tokenData, encoding: .utf8) else {
                fail("Apple's sign-in token couldn't be read. Try again.",
                     diagnosis: "identityToken was not valid UTF-8 (\(tokenData.count) bytes)")
                return
            }
            guard let nonce else {
                fail("Something interrupted the sign-in. Try again.",
                     diagnosis: "completion arrived with no nonce from onRequest")
                return
            }

            Task {
                // The *raw* nonce, never the digest sent to Apple above.
                await session.linkApple(idToken: idToken, nonce: nonce)
                isLinking = false
            }
        }
    }

    private func report(_ error: Error) {
        // Cancelling is a decision, not a failure. Showing it as an error message would be
        // the app arguing with the user about an answer they already gave.
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            Self.logger.info("Apple link cancelled by the user")
            isLinking = false
            return
        }
        let nsError = error as NSError
        fail("Apple couldn't complete the sign-in. Check your connection and try again.",
             diagnosis: "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
    }

    /// Every failure funnels through here so no path can end without both halves: a log line
    /// carrying the diagnosis and a sentence the user actually reads.
    private func fail(_ message: String, diagnosis: String) {
        Self.logger.error("Apple link failed — \(diagnosis, privacy: .public)")
        isLinking = false
        session.errorMessage = message
    }
}
