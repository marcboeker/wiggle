import CoreGraphics
import Testing

@testable import WiggleKit

private let began = Int64(CGScrollPhase.began.rawValue)
private let changed = Int64(CGScrollPhase.changed.rawValue)
private let ended = Int64(CGScrollPhase.ended.rawValue)
private let momentumBegin = Int64(CGMomentumScrollPhase.begin.rawValue)
private let momentumContinue = Int64(CGMomentumScrollPhase.continuous.rawValue)
private let momentumEnd = Int64(CGMomentumScrollPhase.end.rawValue)

/// Plays a trackpad scroll with its momentum and returns, for each event,
/// whether the filter swallowed it: began, changed, ended, then momentum.
private func scroll(_ filter: inout SwipeEventFilter) -> [Bool] {
    [
        filter.shouldSwallowScroll(scrollPhase: began, momentumPhase: 0),
        filter.shouldSwallowScroll(scrollPhase: changed, momentumPhase: 0),
        filter.shouldSwallowScroll(scrollPhase: ended, momentumPhase: 0),
        filter.shouldSwallowScroll(scrollPhase: 0, momentumPhase: momentumBegin),
        filter.shouldSwallowScroll(scrollPhase: 0, momentumPhase: momentumContinue),
        filter.shouldSwallowScroll(scrollPhase: 0, momentumPhase: momentumEnd),
    ]
}

/// Whether the filter swallows one Dock swipe event in `phase`.
private func dock(
    _ filter: inout SwipeEventFilter, _ phase: Int64, motion: Int64 = SwipeEventFilter.verticalDockSwipeMotion
) -> Bool {
    filter.shouldSwallowDockControl(subtype: SwipeEventFilter.dockSwipeSubtype, motion: motion, phase: phase)
}

/// Plays a Dock swipe and returns, for each event, whether the filter
/// swallowed it: began, changed, ended.
private func dockSwipe(
    _ filter: inout SwipeEventFilter, motion: Int64 = SwipeEventFilter.verticalDockSwipeMotion
) -> [Bool] {
    [began, changed, ended].map { dock(&filter, $0, motion: motion) }
}

@Test func theScrollOfAFourFingerSwipeAndItsMomentumAreSwallowed() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 4)
    #expect(scroll(&filter) == [true, true, true, true, true, true])
}

@Test func aTwoFingerScrollAndItsMomentumPass() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 2)
    #expect(scroll(&filter) == [false, false, false, false, false, false])
}

@Test func aMouseWheelPassesEvenWithFourFingersDown() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 4)
    #expect(filter.shouldSwallowScroll(scrollPhase: 0, momentumPhase: 0) == false)
}

/// The fingers land one after another, so the scroll begins with two. The
/// app saw that beginning, so it still gets the end, but nothing in between
/// and no momentum.
@Test func aScrollThatGainsFingersSwallowsFromThenOnButStillEnds() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 2)
    #expect(filter.shouldSwallowScroll(scrollPhase: began, momentumPhase: 0) == false)
    filter.touchesChanged(count: 4)
    #expect(filter.shouldSwallowScroll(scrollPhase: changed, momentumPhase: 0) == true)
    #expect(filter.shouldSwallowScroll(scrollPhase: ended, momentumPhase: 0) == false)
    // That end still belongs to the swipe, so it must not close the overlay.
    #expect(filter.isSwallowingScroll == true)
    #expect(filter.shouldSwallowScroll(scrollPhase: 0, momentumPhase: momentumContinue) == true)
}

@Test func aTwoFingerScrollAfterASwipeIsNoSwipeScroll() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 4)
    _ = scroll(&filter)
    filter.touchesChanged(count: 0)
    filter.touchesChanged(count: 2)
    #expect(filter.shouldSwallowScroll(scrollPhase: began, momentumPhase: 0) == false)
    #expect(filter.isSwallowingScroll == false)
}

@Test func theMomentumAfterTheFingersLiftIsStillSwallowed() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 4)
    #expect(filter.shouldSwallowScroll(scrollPhase: began, momentumPhase: 0) == true)
    #expect(filter.shouldSwallowScroll(scrollPhase: ended, momentumPhase: 0) == true)
    filter.touchesChanged(count: 0)
    #expect(filter.shouldSwallowScroll(scrollPhase: 0, momentumPhase: momentumContinue) == true)
}

@Test func aTwoFingerScrollAfterASwipePasses() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 4)
    _ = scroll(&filter)
    filter.touchesChanged(count: 0)
    filter.touchesChanged(count: 2)
    #expect(scroll(&filter) == [false, false, false, false, false, false])
}

/// Recorded on a MacBook: the Dock swipe began 150 ms after the fourth
/// finger landed, and ended just after the last one lifted.
@Test func theDockSwipeOfAFourFingerSwipeIsSwallowedToItsEnd() {
    var filter = SwipeEventFilter(fingers: 4)
    for count in [1, 2, 3, 4] { filter.touchesChanged(count: count) }
    #expect(dock(&filter, began) == true)
    #expect(dock(&filter, changed) == true)
    for count in [3, 2, 1, 0] { filter.touchesChanged(count: count) }
    #expect(dock(&filter, ended) == true)
}

@Test func theDockSwipeOfAThreeFingerSwipePasses() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 3)
    #expect(dockSwipe(&filter) == [false, false, false])
}

/// Mission Control already follows the fingers, so a fourth finger that
/// lands late must not cut the Dock swipe off before its end.
@Test func aDockSwipeThatBeganWithThreeFingersPassesWhole() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 3)
    #expect(dock(&filter, began) == false)
    filter.touchesChanged(count: 4)
    #expect(dock(&filter, changed) == false)
    #expect(dock(&filter, ended) == false)
}

@Test func aHorizontalDockSwipeAndOtherDockEventsPass() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 4)
    #expect(dockSwipe(&filter, motion: 1) == [false, false, false])
    #expect(filter.shouldSwallowDockControl(subtype: 22, motion: 2, phase: began) == false)
}

@Test func aThreeFingerDockSwipeAfterASwallowedOnePasses() {
    var filter = SwipeEventFilter(fingers: 4)
    filter.touchesChanged(count: 4)
    #expect(dockSwipe(&filter) == [true, true, true])
    filter.touchesChanged(count: 0)
    filter.touchesChanged(count: 3)
    #expect(dockSwipe(&filter) == [false, false, false])
}
