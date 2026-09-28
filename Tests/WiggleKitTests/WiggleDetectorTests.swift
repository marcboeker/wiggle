import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

/// Plays a movement path into the detector and reports when it fires.
private func play(
    _ path: [CGPoint], step: TimeInterval = 0.01, detector: WiggleDetector = WiggleDetector()
) -> Bool {
    var now: TimeInterval = 1000
    for point in path {
        if detector.feed(point, at: now) != nil { return true }
        now += step
    }
    return false
}

/// A shake of `legs` legs, each `length` wide, around x = 500 (or y = 400
/// when `vertical` is set).
private func shake(
    legs: Int, length: CGFloat, sampleSize: CGFloat = 4, vertical: Bool = false
) -> [CGPoint] {
    var points: [CGPoint] = []
    var offset: CGFloat = vertical ? 400 : 500
    for leg in 0..<legs {
        let direction: CGFloat = leg.isMultiple(of: 2) ? 1 : -1
        var moved: CGFloat = 0
        while moved < length {
            let delta = min(sampleSize, length - moved)
            offset += direction * delta
            moved += delta
            points.append(vertical ? CGPoint(x: 500, y: offset) : CGPoint(x: offset, y: 400))
        }
    }
    return points
}

@Test func shortShakeTriggers() {
    #expect(play(shake(legs: 5, length: 30)))
}

@Test func verticalShakeTriggers() {
    #expect(play(shake(legs: 5, length: 30, vertical: true)))
}

@Test func straightLineDoesNotTrigger() {
    let line = (0..<200).map { CGPoint(x: 100 + CGFloat($0) * 5, y: 400) }
    #expect(!play(line))
}

@Test func oneReversalDoesNotTrigger() {
    #expect(!play(shake(legs: 2, length: 40)))
}

@Test func tinyJitterDoesNotTrigger() {
    // Legs below `minLegDistance` must not count, however many there are.
    #expect(!play(shake(legs: 12, length: 3, sampleSize: 1)))
}

@Test func slowShakeDoesNotTrigger() {
    // The same path, but each reversal falls outside the time window.
    #expect(!play(shake(legs: 6, length: 20), step: 0.2))
}

@Test func longLegShakeTriggers() {
    // Fast legs of 350 pt still fit inside `maxTravel`.
    #expect(play(shake(legs: 5, length: 350, sampleSize: 50)))
}

@Test func wideSweepsDoNotTrigger() {
    // Long legs exceed `maxTravel`, so dragging a window is not a wiggle.
    #expect(!play(shake(legs: 6, length: 600, sampleSize: 60)))
}

@Test func resetClearsProgress() {
    let detector = WiggleDetector()
    #expect(!play(shake(legs: 2, length: 20), detector: detector))
    detector.reset()
    #expect(!play(shake(legs: 2, length: 20), detector: detector))
}

@Test func triggerRearmsAfterFiring() {
    let detector = WiggleDetector()
    #expect(play(shake(legs: 5, length: 30), detector: detector))
    #expect(play(shake(legs: 5, length: 30), detector: detector))
}
