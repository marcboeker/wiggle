import CoreGraphics
import Testing

@testable import WiggleKit

@Test func withoutAWarpEveryLocationPassesThroughUnchanged() {
    var guardian = PointerWarpGuard()
    let raw = CGPoint(x: 12, y: 34)
    #expect(guardian.correct(raw) == raw)
    #expect(guardian.correct(raw) == raw)
}

@Test func aPendingWarpSubstitutesItsTargetForADifferentRawLocation() {
    var guardian = PointerWarpGuard()
    let target = CGPoint(x: 100, y: 200)
    guardian.begin(target: target)

    // A straggler still carrying the pre-warp position is replaced.
    #expect(guardian.correct(CGPoint(x: 90, y: 190)) == target)
    #expect(guardian.correct(CGPoint(x: 95, y: 195)) == target)
}

@Test func aRawLocationThatAlreadyMatchesTheTargetStopsTheGuard() {
    var guardian = PointerWarpGuard()
    let target = CGPoint(x: 100, y: 200)
    guardian.begin(target: target)
    _ = guardian.correct(CGPoint(x: 90, y: 190))

    // Reality caught up: this event already reports the warp target.
    #expect(guardian.correct(target) == target)

    let elsewhere = CGPoint(x: 500, y: 500)
    #expect(guardian.correct(elsewhere) == elsewhere)
}

@Test func aWarpNothingEverConfirmsEventuallyStopsBeingCorrected() {
    var guardian = PointerWarpGuard()
    let target = CGPoint(x: 100, y: 200)
    let neverConverges = CGPoint(x: 700, y: 700)
    guardian.begin(target: target)

    var sawACorrection = false
    var results: [CGPoint] = []
    for _ in 0..<20 {
        let corrected = guardian.correct(neverConverges)
        if corrected == target { sawACorrection = true }
        results.append(corrected)
    }

    #expect(sawACorrection)
    #expect(results.last == neverConverges)
}

@Test func aNewWarpResetsTheCorrectionBudget() {
    var guardian = PointerWarpGuard()
    let firstTarget = CGPoint(x: 1, y: 1)
    guardian.begin(target: firstTarget)
    for _ in 0..<20 { _ = guardian.correct(CGPoint(x: 999, y: 999)) }
    // The budget from the first warp is exhausted by now.

    let secondTarget = CGPoint(x: 2, y: 2)
    guardian.begin(target: secondTarget)
    #expect(guardian.correct(CGPoint(x: 999, y: 999)) == secondTarget)
}
