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

    @Test("every generated code is accepted by its own validator")
    func generatedCodesValidate() {
        for _ in 0..<200 {
            #expect(InviteCode.isWellFormed(InviteCode.generate()))
        }
    }
}

/// Path-safety validation.
///
/// These are not input-hygiene tests. An invite code becomes a Firestore document id and an
/// event id becomes a path segment, and `CollectionReference.document(_:)` treats its argument
/// as a *path*: `//` is rejected outright and an odd total segment count is rejected, both by
/// raising an Objective-C `NSException` from the Firestore C++ core. Swift `do/catch` cannot
/// intercept that — the process dies with SIGABRT. So each case below asserts the value is
/// *refused before a path is built*; if the guard were removed, the equivalent production call
/// would abort rather than throw, which no test can catch.
@Suite("Path-unsafe invite input is refused")
struct InviteInputValidationTests {

    // MARK: Codes

    @Test("a pasted invite URL is not a code")
    func pastedUrlRejected() {
        // The documented workaround while the URL scheme was unregistered, and the exact
        // input that crashed: uppercasing keeps the `//`.
        let pasted = "birthdayquest://join?e=evt_1&c=ABCD2345"
        #expect(InviteCode.normalized(pasted) == nil)
        #expect(InviteCode.isWellFormed(pasted.uppercased()) == false)
    }

    @Test("a code containing a slash is rejected")
    func slashRejected() {
        // 8 characters, so a length-only check would have let this through — and
        // `inviteCodes/ABC/1234` is three segments, an odd count, which aborts.
        #expect(InviteCode.normalized("ABC/1234") == nil)
        #expect(InviteCode.normalized("AB//2345") == nil)
    }

    @Test("a code of the wrong length is rejected")
    func lengthRejected() {
        #expect(InviteCode.normalized("") == nil)
        #expect(InviteCode.normalized("ABC") == nil)
        #expect(InviteCode.normalized("ABCD23456") == nil)
    }

    @Test("a code with an out-of-alphabet character is rejected")
    func alphabetRejected() {
        // I, O, 0 and 1 are deliberately not in the alphabet.
        #expect(InviteCode.normalized("ABCD234I") == nil)
        #expect(InviteCode.normalized("ABCD2340") == nil)
        #expect(InviteCode.normalized("ABCD 234") == nil)
        #expect(InviteCode.normalized("ABCD.234") == nil)
        #expect(InviteCode.normalized("ABCD-234") == nil)
        #expect(InviteCode.normalized("__ABCD__") == nil)
    }

    @Test("a well-formed code survives normalisation, lowercase and padded")
    func happyPathSurvives() {
        #expect(InviteCode.normalized("ABCD2345") == "ABCD2345")
        #expect(InviteCode.normalized("abcd2345") == "ABCD2345")
        #expect(InviteCode.normalized("  abcd2345\n") == "ABCD2345")
    }

    // MARK: Event ids

    @Test("an event id containing a slash is rejected")
    func eventIdSlashRejected() {
        #expect(EventID.isValid("a/b") == false)
        #expect(EventID.isValid("a//b") == false)
        #expect(EventID.isValid("evt_1/participants/uid") == false)
    }

    @Test("event ids Firestore itself forbids are rejected")
    func eventIdReservedShapesRejected() {
        #expect(EventID.isValid("") == false)
        #expect(EventID.isValid(".") == false)
        #expect(EventID.isValid("..") == false)
        #expect(EventID.isValid("__name__") == false)
        #expect(EventID.isValid(String(repeating: "a", count: 1501)) == false)
    }

    @Test("a real Firestore auto-id is accepted")
    func eventIdHappyPath() {
        #expect(EventID.isValid("evt_1"))
        #expect(EventID.isValid("KLh2Ys9QpVn3aBcDeFgH"))
        #expect(EventID.isValid(String(repeating: "a", count: 1500)))
    }
}
