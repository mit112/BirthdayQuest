import Testing
import Foundation
@testable import BirthdayQuest

@Suite("Join occasion")
@MainActor
struct JoinOccasionTests {

    @Test("a valid deep link populates the event id and code")
    func parsesLink() {
        let vm = JoinOccasionViewModel(service: MockGameBackend())
        #expect(vm.parse(link: URL(string: "birthdayquest://join?e=evt_1&c=ABCD2345")!))
        #expect(vm.eventId == "evt_1")
        #expect(vm.code == "ABCD2345")
    }

    @Test("a link missing either parameter is rejected")
    func rejectsIncompleteLink() {
        let vm = JoinOccasionViewModel(service: MockGameBackend())
        #expect(vm.parse(link: URL(string: "birthdayquest://join?e=evt_1")!) == false)
        #expect(vm.parse(link: URL(string: "birthdayquest://join?c=ABCD2345")!) == false)
        #expect(vm.parse(link: URL(string: "https://example.com/join?e=a&c=b")!) == false)
    }

    @Test("codes are normalised to uppercase before submission")
    func normalisesCode() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "contributor")
        let vm = JoinOccasionViewModel(service: mock)
        // Driven through `resolveCode()` rather than by assigning `eventId` directly. A
        // caller can no longer submit without resolving — `canSubmit` requires it, so that a
        // celebrant whose lookup failed cannot join with the default contributor mode — which
        // means hand-assigning the fields sets up a state the app cannot reach.
        vm.code = "abcd2345"
        await vm.resolveCode()
        vm.name = "Jordan"

        _ = await vm.join()

        #expect(mock.joinedOccasions.first?.code == "ABCD2345")
    }

    /// The crash case. `"birthdayquest://join?e=…".uppercased()` contains `//`, and pasting
    /// the whole invite URL into the code field was the documented workaround while the URL
    /// scheme was unregistered. That string reaches `document(_:)` as a PATH, and Firestore
    /// answers a malformed path by throwing an Objective-C `NSException` from its C++ core —
    /// which `do/catch` cannot intercept, so the process aborts. The only fix is to refuse it
    /// before a reference is built; asserting the error is what proves the guard is what
    /// stopped it, rather than luck.
    @Test("a pasted invite URL in the code field is refused before any lookup")
    func pastedUrlNeverReachesTheBackend() async {
        let mock = MockGameBackend()
        let vm = JoinOccasionViewModel(service: mock)

        vm.code = "birthdayquest://join?e=evt_1&c=ABCD2345"
        await vm.resolveCode()

        #expect(mock.called("resolveInviteCode") == false)
        #expect(mock.resolvedCodes.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.eventId.isEmpty)
        #expect(vm.isResolvingCode == false)
    }

    @Test("a code containing a slash is refused before any lookup")
    func slashInCodeNeverReachesTheBackend() async {
        let mock = MockGameBackend()
        let vm = JoinOccasionViewModel(service: mock)

        // Eight characters, so a length-only check would have passed it through, and
        // `inviteCodes/ABC/1234` is an odd segment count — the second abort shape.
        vm.code = "ABC/1234"
        await vm.resolveCode()

        #expect(mock.called("resolveInviteCode") == false)
        #expect(vm.errorMessage != nil)
    }

    @Test("a link whose event id could not be a document id is refused")
    func malformedEventIdInLinkIsRefused() {
        let vm = JoinOccasionViewModel(service: MockGameBackend())

        #expect(vm.parse(link: URL(string: "birthdayquest://join?e=a%2F%2Fb&c=ABCD2345")!) == false)
        #expect(vm.eventId.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("a link whose code could not be a code is refused")
    func malformedCodeInLinkIsRefused() {
        let vm = JoinOccasionViewModel(service: MockGameBackend())

        #expect(vm.parse(link: URL(string: "birthdayquest://join?e=evt_1&c=ABC")!) == false)
        #expect(vm.parse(link: URL(string: "birthdayquest://join?e=evt_1&c=AB%2F%2F2345")!) == false)
        #expect(vm.eventId.isEmpty)
    }

    @Test("a rejected code surfaces a specific message, not a generic failure")
    func invalidCodeMessage() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "contributor")
        let vm = JoinOccasionViewModel(service: mock)

        // Resolve first, then arm the failure. `errorToThrow` is global to the mock, so
        // setting it up front would reject the lookup too and never reach the join at all.
        vm.code = "ZZZZ2345"
        await vm.resolveCode()
        vm.name = "Jordan"
        mock.errorToThrow = BackendError.invalidCode

        #expect(await vm.join() == false)
        #expect(vm.errorMessage?.contains("invite") == true)
    }
}

@Suite("Invite code resolution")
@MainActor
struct InviteCodeResolutionTests {

    @Test("a celebrant link resolves to celebrant mode, not the contributor default")
    func celebrantLinkResolvesToCelebrantMode() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "celebrant")
        let vm = JoinOccasionViewModel(service: mock)

        #expect(vm.parse(link: URL(string: "birthdayquest://join?e=evt_1&c=EFGH6789")!))
        await vm.resolveCode()

        #expect(vm.mode == .celebrant, "the link carries no kind; only the lookup can tell")
        #expect(vm.eventId == "evt_1")
        #expect(vm.errorMessage == nil)
    }

    @Test("a celebrant join consumes the code so the link cannot be replayed")
    func celebrantJoinConsumesTheCode() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "celebrant")
        let vm = JoinOccasionViewModel(service: mock)

        _ = vm.parse(link: URL(string: "birthdayquest://join?e=evt_1&c=EFGH6789")!)
        await vm.resolveCode()
        vm.name = "Alex"
        let joined = await vm.join()

        #expect(joined)
        #expect(mock.joinedOccasions.first?.mode == .celebrant)
        #expect(mock.consumedCelebrantCodes == ["evt_1"])
    }

    @Test("a contributor join leaves the celebrant code alone")
    func contributorJoinLeavesTheCelebrantCode() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "contributor")
        let vm = JoinOccasionViewModel(service: mock)

        _ = vm.parse(link: URL(string: "birthdayquest://join?e=evt_1&c=ABCD2345")!)
        await vm.resolveCode()
        vm.name = "Jordan"
        _ = await vm.join()

        #expect(vm.mode == .contributor)
        #expect(mock.consumedCelebrantCodes.isEmpty)
    }

    @Test("manual entry of a code resolves the event id the user never typed")
    func manualCodeEntryResolvesTheEventId() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_7", kind: "contributor")
        let vm = JoinOccasionViewModel(service: mock)

        vm.code = "abcd2345"
        await vm.resolveCode()

        #expect(mock.resolvedCodes == ["ABCD2345"], "codes are normalised before the lookup")
        #expect(vm.eventId == "evt_7")
        #expect(vm.code == "ABCD2345")
    }

    @Test("an unknown code is rejected without inventing an event id")
    func unknownCodeIsRejected() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = nil
        let vm = JoinOccasionViewModel(service: mock)

        vm.code = "ZZZZ2345"
        await vm.resolveCode()

        #expect(vm.eventId.isEmpty)
        #expect(vm.errorMessage != nil)
        #expect(vm.isResolvingCode == false)
    }

    @Test("a failed lookup is reported rather than silently leaving the form blank")
    func lookupFailureSurfaces() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = JoinOccasionViewModel(service: mock)

        vm.code = "ABCD2345"
        await vm.resolveCode()

        #expect(vm.errorMessage != nil)
        #expect(vm.eventId.isEmpty)
        #expect(vm.isResolvingCode == false)
    }
}

// MARK: - A Failed Resolve Must Not Look Like A Successful One

/// R53's bug returning through the error path.
///
/// `parse(link:)` sets `eventId` straight off the URL, before anything is resolved. The view
/// used `eventId.isEmpty` to choose between the code field and the details form, so a deep
/// link whose `resolveCode()` then failed jumped to the details form with `mode` still at its
/// `.contributor` default — telling a celebrant their role was "A friend", with the code field
/// gone and no way to re-resolve. Joining from there is a permission denial the rules produce
/// by design, because celebrant claims are authorised against the celebrant code.
@Suite("Join occasion: unresolved state")
@MainActor
struct JoinOccasionUnresolvedTests {

    private let celebrantLink = URL(string: "birthdayquest://join?e=evt_1&c=EFGH6789")!

    @Test("a parsed link is not resolved until the lookup succeeds")
    func parsingAloneDoesNotResolve() {
        let vm = JoinOccasionViewModel(service: MockGameBackend())

        #expect(vm.parse(link: celebrantLink))
        #expect(vm.eventId == "evt_1", "the id is populated…")
        #expect(vm.isResolved == false, "…but that is not evidence the code resolved")
    }

    @Test("a thrown lookup leaves the celebrant unresolved rather than a contributor")
    func failedLookupDoesNotFallThroughToContributor() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = JoinOccasionViewModel(service: mock)

        _ = vm.parse(link: celebrantLink)
        await vm.resolveCode()

        #expect(vm.isResolved == false)
        #expect(vm.errorMessage != nil)
        // The code survives, which is what makes the retry one tap rather than a retype.
        #expect(vm.code == "EFGH6789")
    }

    @Test("an unknown code leaves the caller unresolved")
    func unknownCodeIsUnresolved() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = nil
        let vm = JoinOccasionViewModel(service: mock)

        _ = vm.parse(link: celebrantLink)
        await vm.resolveCode()

        #expect(vm.isResolved == false)
        #expect(vm.errorMessage != nil)
    }

    /// The assertion that actually closes the hole: an unresolved caller cannot submit at all,
    /// so joining with an unresolved `mode` is unreachable rather than merely unlikely.
    @Test("an unresolved caller cannot submit, even with every other field filled in")
    func unresolvedCannotSubmit() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = JoinOccasionViewModel(service: mock)

        _ = vm.parse(link: celebrantLink)
        await vm.resolveCode()
        vm.name = "Alex"

        #expect(vm.canSubmit == false)
    }

    /// The inverse regression: the gate must not block the happy path.
    @Test("a resolved celebrant link can submit, and carries the celebrant mode")
    func resolvedCelebrantCanSubmit() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "celebrant")
        let vm = JoinOccasionViewModel(service: mock)

        _ = vm.parse(link: celebrantLink)
        await vm.resolveCode()
        vm.name = "Alex"

        #expect(vm.isResolved)
        #expect(vm.mode == .celebrant)
        #expect(vm.canSubmit)
    }

    /// Retrying after a failure resolves cleanly — the recovery path the code field now offers.
    @Test("retrying a failed lookup resolves")
    func retryAfterFailureResolves() async {
        let mock = MockGameBackend()
        mock.errorToThrow = MockGameBackend.StubbedError()
        let vm = JoinOccasionViewModel(service: mock)

        _ = vm.parse(link: celebrantLink)
        await vm.resolveCode()
        #expect(vm.isResolved == false)

        mock.errorToThrow = nil
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "celebrant")
        await vm.resolveCode()

        #expect(vm.isResolved)
        #expect(vm.mode == .celebrant)
    }

    /// A malformed code is rejected before any lookup, and must also leave the caller
    /// unresolved — the early return used to be the one branch that skipped the flag.
    @Test("a malformed code is rejected and stays unresolved")
    func malformedCodeStaysUnresolved() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "celebrant")
        let vm = JoinOccasionViewModel(service: mock)

        vm.code = "ABC"
        await vm.resolveCode()

        #expect(vm.isResolved == false)
        #expect(mock.called("resolveInviteCode") == false, "no lookup for a malformed code")
    }

    /// A second resolve that fails must drop a previously-good resolution rather than leave
    /// the caller submittable against a stale mode.
    @Test("a failed re-resolve drops an earlier success")
    func failedReResolveDropsEarlierSuccess() async {
        let mock = MockGameBackend()
        mock.stubbedCodeResolution = (eventId: "evt_1", kind: "celebrant")
        let vm = JoinOccasionViewModel(service: mock)

        _ = vm.parse(link: celebrantLink)
        await vm.resolveCode()
        #expect(vm.isResolved)

        mock.errorToThrow = MockGameBackend.StubbedError()
        await vm.resolveCode()

        #expect(vm.isResolved == false)
    }
}
