import Testing
@testable import BirthdayQuest

// The whole point of `MotionLevel` is that the precedence order is one-way: Reduce Motion is
// tier 1 and no lower tier may reintroduce motion it disabled. A test that only checked
// `resolve(reduceMotion: true, lowPower: false) == .none` would pass just as happily against an
// implementation that returned `.none` whenever `lowPower` was false and never read
// `reduceMotion` at all — the expected value and the accidental one coincide. So every row of
// the truth table is asserted, and each input is asserted to *change* the result.

@Suite("Motion level precedence")
struct MotionLevelTests {

    // MARK: - Tier 1: reduce motion always wins

    @Test("Reduce Motion yields .none regardless of Low Power Mode")
    func reduceMotionWinsOverLowPower() {
        // Both rows matter. The second is the one that proves tier 1 *beats* tier 2 rather than
        // merely coinciding with it.
        #expect(MotionLevel.resolve(reduceMotion: true, lowPower: false) == .none)
        #expect(MotionLevel.resolve(reduceMotion: true, lowPower: true) == .none)
    }

    // MARK: - Tier 2: low power, but only once tier 1 has passed

    @Test("Low Power Mode alone yields .minimal")
    func lowPowerAloneIsMinimal() {
        #expect(MotionLevel.resolve(reduceMotion: false, lowPower: true) == .minimal)
    }

    @Test("Neither constraint yields .full")
    func unconstrainedIsFull() {
        #expect(MotionLevel.resolve(reduceMotion: false, lowPower: false) == .full)
    }

    // MARK: - Each input is load-bearing

    @Test("Flipping reduceMotion changes the result")
    func reduceMotionIsRead() {
        // Fails against an implementation that ignores `reduceMotion`.
        #expect(
            MotionLevel.resolve(reduceMotion: true, lowPower: false)
                != MotionLevel.resolve(reduceMotion: false, lowPower: false)
        )
    }

    @Test("Flipping lowPower changes the result when reduceMotion is off")
    func lowPowerIsRead() {
        // Fails against an implementation that ignores `lowPower`.
        #expect(
            MotionLevel.resolve(reduceMotion: false, lowPower: true)
                != MotionLevel.resolve(reduceMotion: false, lowPower: false)
        )
    }

    // MARK: - What callers actually branch on

    @Test("Perpetual decoration runs only when wholly unconstrained")
    func onlyFullAllowsPerpetual() {
        #expect(MotionLevel.full.allowsPerpetual)
        // `.minimal` withholds it too: a pulse that never stops is as bad for a dying battery
        // as it is for a vestibular disorder.
        #expect(!MotionLevel.minimal.allowsPerpetual)
        #expect(!MotionLevel.none.allowsPerpetual)
    }

    @Test("Every resolved level agrees with allowsPerpetual")
    func resolveAgreesWithAllowsPerpetual() {
        // Ties the two halves together, so a future change to `resolve` that returned `.full`
        // under Reduce Motion fails here even if the cases above were edited to match it.
        #expect(!MotionLevel.resolve(reduceMotion: true, lowPower: false).allowsPerpetual)
        #expect(!MotionLevel.resolve(reduceMotion: true, lowPower: true).allowsPerpetual)
        #expect(!MotionLevel.resolve(reduceMotion: false, lowPower: true).allowsPerpetual)
        #expect(MotionLevel.resolve(reduceMotion: false, lowPower: false).allowsPerpetual)
    }
}
