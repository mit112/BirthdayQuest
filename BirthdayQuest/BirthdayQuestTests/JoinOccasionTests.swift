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

    @Test("a rejected code surfaces a specific message, not a generic failure")
    func invalidCodeMessage() async {
        let mock = MockGameBackend()
        mock.errorToThrow = BackendError.invalidCode
        let vm = JoinOccasionViewModel(service: mock)
        vm.eventId = "evt_1"; vm.code = "WRONG123"; vm.name = "Jordan"

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

        vm.code = "NOTACODE"
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
