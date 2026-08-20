import Testing
@testable import BirthdayQuest

@Suite("Invite codes")
struct InviteCodeTests {

    @Test("generated codes are the declared length")
    func length() {
        #expect(InviteCode.generate().count == InviteCode.length)
    }

    @Test("codes avoid characters that are misread aloud")
    func unambiguousAlphabet() {
        let banned: Set<Character> = ["I", "O", "0", "1"]
        #expect(InviteCode.alphabet.allSatisfy { !banned.contains($0) })
        #expect(InviteCode.alphabet.count == 32)
    }

    @Test("codes are drawn only from the alphabet")
    func drawsFromAlphabet() {
        let allowed = Set(InviteCode.alphabet)
        for _ in 0..<200 {
            #expect(InviteCode.generate().allSatisfy { allowed.contains($0) })
        }
    }

    @Test("codes do not repeat in a small sample")
    func collisionResistance() {
        let codes = Set((0..<500).map { _ in InviteCode.generate() })
        #expect(codes.count == 500)
    }
}
