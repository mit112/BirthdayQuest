import Testing
import Foundation
@testable import BirthdayQuest

@Suite("Create occasion")
@MainActor
struct CreateOccasionTests {

    @Test("submission is blocked until the required fields are filled")
    func validation() {
        let vm = CreateOccasionViewModel(service: MockGameBackend())
        #expect(vm.canSubmit == false)

        vm.name = "Alex's 30th"
        #expect(vm.canSubmit == false)

        vm.celebrantName = "Alex"
        vm.hostName = "Sam"
        #expect(vm.canSubmit == true)
    }

    @Test("whitespace-only input does not count as filled")
    func rejectsWhitespace() {
        let vm = CreateOccasionViewModel(service: MockGameBackend())
        vm.name = "   "
        vm.celebrantName = "Alex"
        vm.hostName = "Sam"
        #expect(vm.canSubmit == false)
    }

    @Test("creating passes the chosen occasion type through to the backend")
    func passesTypeThrough() async {
        let mock = MockGameBackend()
        let vm = CreateOccasionViewModel(service: mock)
        vm.name = "Priya's farewell"
        vm.celebrantName = "Priya"
        vm.hostName = "Sam"
        vm.occasionType = .farewell

        let eventId = await vm.create()

        #expect(eventId == "evt_mock")
        #expect(mock.createdOccasions.first?.type == .farewell)
    }

    @Test("a backend failure surfaces a message and no event id")
    func failureSurfaces() async {
        let mock = MockGameBackend()
        mock.errorToThrow = NSError(domain: "test", code: 1)
        let vm = CreateOccasionViewModel(service: mock)
        vm.name = "X"; vm.celebrantName = "Y"; vm.hostName = "Z"

        let eventId = await vm.create()

        #expect(eventId == nil)
        #expect(vm.errorMessage != nil)
        #expect(vm.isSubmitting == false)
    }
}
