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
        let vm = JoinOccasionViewModel(service: mock)
        vm.eventId = "evt_1"
        vm.code = "abcd2345"
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
        mock.errorToThrow = BackendError.invalidCode
        let vm = JoinOccasionViewModel(service: mock)
        vm.eventId = "evt_1"; vm.code = "ZZZZ2345"; vm.name = "Jordan"

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
