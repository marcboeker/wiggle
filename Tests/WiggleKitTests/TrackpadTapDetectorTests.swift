import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

private func tap(_ count: Int, frames: Int = 10) -> [TouchFrame] {
    Array(repeating: fingers(count), count: frames)
}

@Test func aThreeFingerTapTriggers() {
    #expect(playAndLift(tap(3), detector: TrackpadTapDetector(fingers: 3)) != nil)
}

@Test func aFourFingerTapTriggers() {
    #expect(playAndLift(tap(4), detector: TrackpadTapDetector(fingers: 4)) != nil)
}

@Test func theTapReportsThePointer() {
    #expect(playAndLift(tap(3), detector: TrackpadTapDetector(fingers: 3)) == pointer)
}

@Test func fingersThatLandOneAfterAnotherStillTap() {
    let frames = [fingers(1), fingers(2), fingers(3), fingers(3), fingers(2), fingers(1)]
    #expect(playAndLift(frames, detector: TrackpadTapDetector(fingers: 3)) != nil)
}

@Test func anotherNumberOfFingersDoesNotTrigger() {
    #expect(playAndLift(tap(2), detector: TrackpadTapDetector(fingers: 3)) == nil)
    #expect(playAndLift(tap(4), detector: TrackpadTapDetector(fingers: 3)) == nil)
    #expect(playAndLift(tap(3), detector: TrackpadTapDetector(fingers: 4)) == nil)
}

@Test func aLongTouchDoesNotTrigger() {
    #expect(playAndLift(tap(3, frames: 40), detector: TrackpadTapDetector(fingers: 3)) == nil)
}

@Test func aSwipeDoesNotTrigger() {
    let frames = (0..<10).map { fingers(3, dx: 0.02 * CGFloat($0)) }
    #expect(playAndLift(frames, detector: TrackpadTapDetector(fingers: 3)) == nil)
}

@Test func jitterStillTaps() {
    let frames = (0..<10).map { fingers(3, dx: $0.isMultiple(of: 2) ? 0.01 : 0) }
    #expect(playAndLift(frames, detector: TrackpadTapDetector(fingers: 3)) != nil)
}

@Test func aClickDuringTheTouchDoesNotTrigger() {
    let detector = TrackpadTapDetector(fingers: 3)
    _ = detector.touchesChanged(fingers(3), pointer: pointer, at: 1000)
    detector.reset()
    #expect(playAndLift(tap(3, frames: 3), detector: detector) == nil)
}

@Test func theTapAfterASpoiledTouchTriggers() {
    let detector = TrackpadTapDetector(fingers: 3)
    #expect(playAndLift(tap(3, frames: 40), detector: detector) == nil)
    #expect(playAndLift(tap(3), detector: detector) != nil)
}

@Test func aResetWithoutFingersDownDoesNotBlockTheNextTap() {
    let detector = TrackpadTapDetector(fingers: 3)
    detector.reset()
    #expect(playAndLift(tap(3), detector: detector) != nil)
}
