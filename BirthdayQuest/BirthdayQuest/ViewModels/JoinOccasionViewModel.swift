import Foundation
import FirebaseFirestore
import Combine
import OSLog

@MainActor
final class JoinOccasionViewModel: ObservableObject {

    @Published var eventId = ""
    @Published var code = ""
    @Published var name = ""
    @Published var avatarId = AvatarCatalog.fallback
    @Published var mode: ParticipantMode = .contributor

    @Published var isResolvingCode = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    /// Whether `resolveCode()` has actually succeeded for the code currently held.
    ///
    /// This exists because `eventId` is not evidence of it. `parse(link:)` sets `eventId` and
    /// `code` straight off the URL, before anything has been resolved — so a deep link whose
    /// `resolveCode()` then failed left a non-empty `eventId` with `mode` still at its
    /// `.contributor` default. The view read `eventId.isEmpty` to decide which form to show,
    /// so it skipped to the details form and told a celebrant their role was "A friend", with
    /// the code field gone and no way to re-resolve.
    ///
    /// Joining on that state is the failure R53 was written about: the rules authorise
    /// celebrant claims against the celebrant code, so a celebrant joining as a contributor
    /// is a permission denial the user cannot diagnose. `canSubmit` therefore requires this,
    /// which makes an unresolved join unreachable rather than merely unlikely.
    @Published private(set) var isResolved = false

    private let service: GameBackend
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "JoinOccasion")

    init(service: GameBackend = FirestoreService.shared) {
        self.service = service
    }

    var canSubmit: Bool {
        !isSubmitting && !isResolvingCode && isResolved && !eventId.isEmpty && !code.isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `birthdayquest://join?e=<eventId>&c=<CODE>`
    ///
    /// Both parameters are required: the invite-code collection denies `list`, so a client
    /// cannot resolve an event id from a code by enumeration, which is what stops codes
    /// being harvested. The link does not carry `kind` — call `resolveCode()` afterward to
    /// learn whether it is a contributor or celebrant invite.
    /// Validates both parameters rather than merely requiring them to be non-empty. Now that
    /// the URL scheme is registered, anyone who can send this user a link can put anything in
    /// `e` and `c` — and an event id containing `//` reaches Firestore's `document(_:)` as a
    /// malformed *path*, which aborts the process from Objective-C where no `catch` can reach
    /// it. Refusing here keeps the hostile value out of the view model's state entirely.
    func parse(link: URL) -> Bool {
        guard link.scheme == "birthdayquest", link.host == "join" else { return false }

        guard let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let event = items.first(where: { $0.name == "e" })?.value,
              EventID.isValid(event),
              let inviteCode = items.first(where: { $0.name == "c" })?.value,
              let normalized = InviteCode.normalized(inviteCode)
        else {
            logger.error("Rejected a malformed join link")
            errorMessage = "That invite link isn't valid. Ask your host to send it again."
            return false
        }

        eventId = event
        code = normalized
        return true
    }

    /// Resolves a code to the occasion it belongs to and the mode it authorises.
    ///
    /// Two callers: manual entry, where the user has typed a code but arrived without a
    /// link, so there is no event id yet (R14); and the deep-link path, where `parse(link:)`
    /// already has an event id and code but not `kind` — a celebrant link is textually
    /// indistinguishable from a contributor one, so without this the mode picker would
    /// default wrong and every celebrant join would be rejected by the rules.
    ///
    /// The lookup itself lives behind `GameBackend.resolveInviteCode(_:)` so this — the
    /// only thing that decides whether a link is a celebrant invite — is drivable from a
    /// test rather than only against a live Firestore.
    /// Normalisation and validation both live in `InviteCode`, and the backend re-checks
    /// before it builds a path — a malformed code is a crash, not an error, if it reaches
    /// `document(_:)`, so it is refused at both ends rather than trusted from either.
    func resolveCode() async {
        // Dropped up front, not only on failure. Every exit below other than the success
        // path leaves the caller un-resolved, and re-deriving that per branch is how the
        // stranded-celebrant state got in.
        isResolved = false

        guard let normalized = InviteCode.normalized(code) else {
            errorMessage = "That doesn't look like an invite code. "
                + "Codes are \(InviteCode.length) letters and numbers."
            return
        }

        isResolvingCode = true
        errorMessage = nil
        defer { isResolvingCode = false }

        do {
            guard let resolved = try await service.resolveInviteCode(normalized) else {
                errorMessage = "That invite code doesn't match this occasion."
                return
            }
            code = normalized
            eventId = resolved.eventId
            mode = resolved.kind == ParticipantMode.celebrant.rawValue ? .celebrant : .contributor
            isResolved = true
        } catch let error as BackendError {
            // Malformed code, or a code whose stored eventId is not a usable one. Both are
            // "this invite is not real", not "the network failed".
            logger.error("Code lookup rejected: \(error.localizedDescription)")
            errorMessage = error.errorDescription
        } catch {
            logger.error("Code lookup failed: \(error.localizedDescription)")
            errorMessage = "Couldn't check that code. Check your connection and try again."
        }
    }

    /// Joins the occasion, then — if the caller just claimed the celebrant role — consumes
    /// the celebrant code as a second, separate write (R36/R43). Distinguishes the failures
    /// the spec calls out rather than collapsing them into one generic message: already a
    /// member, offline, and everything the rules reject a join for. "Invalid code" and
    /// "occasion closed" both surface as the same `PERMISSION_DENIED` — the create rule ANDs
    /// the code match with `isOpen`, and a non-member cannot read the event document to tell
    /// them apart beforehand — so that one message names both possibilities honestly instead
    /// of inventing a distinction the backend cannot support.
    func join() async -> Bool {
        guard canSubmit else { return false }
        errorMessage = nil

        // A genuine non-member gets permission-denied here, because event and participant
        // reads are gated on membership — that failure just means "not a member yet," so
        // the join attempt below is left to decide the rest. A successful read means the
        // caller is already in, which is worth a specific message rather than a confusing
        // rejection from the write.
        do {
            if let existing = try await service.fetchMyParticipant(eventId: eventId) {
                errorMessage = existing.mode == mode
                    ? "You've already joined this occasion."
                    : "You're already part of this occasion, just not in that role."
                return false
            }
        } catch {
            logger.debug("Membership pre-check did not resolve; attempting join anyway")
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await service.joinOccasion(
                eventId: eventId,
                code: code.uppercased(),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarId: avatarId,
                mode: mode
            )
        } catch BackendError.invalidCode {
            errorMessage = "That invite doesn't work. The code may be wrong or already used, "
                + "or the host may have closed this occasion to new joins."
            return false
        } catch let error as BackendError {
            // A malformed event id, or not signed in. Both carry their own copy.
            logger.error("Join rejected: \(error.localizedDescription)")
            errorMessage = error.errorDescription
            return false
        } catch let error as NSError where isOffline(error) {
            errorMessage = "You're offline. Check your connection and try again."
            return false
        } catch {
            logger.error("Join failed: \(error.localizedDescription)")
            errorMessage = "Couldn't join. Try again."
            return false
        }

        if mode == .celebrant {
            await consumeCelebrantCode()
        }

        return true
    }

    private func isOffline(_ error: NSError) -> Bool {
        error.domain == FirestoreErrorDomain
            && error.code == FirestoreErrorCode.unavailable.rawValue
    }

    /// Clears `celebrantCode` on the event document. A failure here is not surfaced — the
    /// join itself succeeded — only logged. `EventSession.start()` retries it the next time
    /// this celebrant opens the occasion, which is what keeps a dropped connection here from
    /// leaving the celebrant link replayable forever.
    private func consumeCelebrantCode() async {
        do {
            try await service.consumeCelebrantCode(eventId: eventId)
        } catch {
            logger.error("Failed to consume celebrant code: \(error.localizedDescription)")
        }
    }
}
