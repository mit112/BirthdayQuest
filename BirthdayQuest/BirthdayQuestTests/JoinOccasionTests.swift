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
