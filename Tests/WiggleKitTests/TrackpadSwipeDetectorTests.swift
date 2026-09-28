import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

/// `count` fingers moving in a straight line from their landings to `dx`, `dy`.
private func swipe(_ count: Int = 4, dx: CGFloat = 0, dy: CGFloat, frames: Int = 10) -> [TouchFrame] {
    (0..<frames).map {
        let progress = CGFloat($0) / CGFloat(frames - 1)
        return fingers(count, dx: dx * progress, dy: dy * progress)
    }
}

private func up() -> TrackpadSwipeDetector { TrackpadSwipeDetector(fingers: 4, direction: .up) }
private func down() -> TrackpadSwipeDetector { TrackpadSwipeDetector(fingers: 4, direction: .down) }

@Test func aFourFingerSwipeUpTriggersOnlyTheUpSwipe() {
    #expect(playAndLift(swipe(dy: 0.3), detector: up()) != nil)
    #expect(playAndLift(swipe(dy: 0.3), detector: down()) == nil)
}

@Test func aFourFingerSwipeDownTriggersOnlyTheDownSwipe() {
    #expect(playAndLift(swipe(dy: -0.3), detector: down()) != nil)
    #expect(playAndLift(swipe(dy: -0.3), detector: up()) == nil)
}

@Test func theSwipeReportsThePointer() {
    #expect(playAndLift(swipe(dy: 0.3), detector: up()) == pointer)
}

@Test func aShortSwipeDoesNotTrigger() {
    #expect(playAndLift(swipe(dy: 0.05), detector: up()) == nil)
}

@Test func aHorizontalSwipeDoesNotTrigger() {
    #expect(playAndLift(swipe(dx: 0.3, dy: 0), detector: up()) == nil)
    #expect(playAndLift(swipe(dx: -0.3, dy: 0), detector: down()) == nil)
}

@Test func onlyAMostlyVerticalDiagonalTriggers() {
    #expect(playAndLift(swipe(dx: 0.2, dy: 0.3), detector: up()) == nil)
    #expect(playAndLift(swipe(dx: 0.1, dy: 0.3), detector: up()) != nil)
}

@Test func threeOrFiveFingersDoNotSwipe() {
    #expect(playAndLift(swipe(3, dy: 0.3), detector: up()) == nil)
    #expect(playAndLift(swipe(5, dy: 0.3), detector: up()) == nil)
}

@Test func upAndBackDownDoesNotTrigger() {
    let frames = swipe(dy: 0.3) + swipe(dy: 0.3).reversed()
    #expect(playAndLift(frames, detector: up()) == nil)
    #expect(playAndLift(frames, detector: down()) == nil)
}

@Test func aSlowSwipeDoesNotTrigger() {
    #expect(playAndLift(swipe(dy: 0.3), step: 0.15, detector: up()) == nil)
}

@Test func aClickDuringTheSwipeDoesNotTriggerButTheNextSwipeDoes() {
    let detector = up()
    _ = detector.touchesChanged(fingers(4), pointer: pointer, at: 990)
    detector.reset()
    #expect(playAndLift(swipe(dy: 0.3), detector: detector) == nil)
    #expect(playAndLift(swipe(dy: 0.3), detector: detector) != nil)
}

@Test func aFourFingerTapIsNoSwipe() {
    let tap = Array(repeating: fingers(4), count: 10)
    #expect(playAndLift(tap, detector: up()) == nil)
    #expect(playAndLift(tap, detector: down()) == nil)
}

@Test func aFourFingerSwipeIsNoFourFingerTap() {
    #expect(playAndLift(swipe(dy: 0.3), detector: TrackpadTapDetector(fingers: 4)) == nil)
}

/// The heel of the hand touches the trackpad's bottom right corner near the
/// end of a quick swipe up, and stays down after the fingers lift. It is no
/// fifth finger, and the swipe completes as soon as the fingers lift.
@Test func aStillTouchAtTheEdgeDoesNotSpoilTheSwipe() {
    let detector = up()
    let heel = CGPoint(x: 0.928, y: 0.001)
    var frames = swipe(dy: 0.3)
    for index in 6..<frames.count { frames[index][9] = heel }
    #expect(playAndLift(frames, lift: [9: heel], detector: detector) != nil)
    #expect(detector.touchesChanged([9: heel], pointer: pointer, at: 1000.11) == nil)
    #expect(detector.touchesChanged([:], pointer: pointer, at: 1000.2) == nil)
}

@Test func threeSwipingFingersAndAStillThumbDoNotSwipe() {
    var frames = swipe(3, dy: 0.3)
    for index in frames.indices { frames[index][9] = CGPoint(x: 0.1, y: 0.1) }
    #expect(playAndLift(frames, detector: up()) == nil)
}

/// Three fingers lift at the top of the swipe while the last one slides back
/// to 0.1. Their last positions still count: the mean travel is 0.25.
@Test func fingersThatLiftOneAfterAnotherKeepTheirLastPositions() {
    let top = fingers(4, dy: 0.3)
    let frames = swipe(dy: 0.3) + [
        top.filter { $0.key < 3 },
        top.filter { $0.key < 2 },
        fingers(1, dy: 0.1),
    ]
    #expect(playAndLift(frames, detector: up()) != nil)
}
