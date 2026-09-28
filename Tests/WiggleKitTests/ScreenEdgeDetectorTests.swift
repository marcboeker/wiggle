import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

private let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
private let rightOfLaptop = CGRect(x: 1728, y: 0, width: 1920, height: 1080)

/// Plays a movement path, then lets the pointer stop. Reports whether the
/// detector fires. A movement alone must never fire.
private func playAndStop(
    _ path: [CGPoint], step: TimeInterval = 0.01, displays: [CGRect] = [laptop],
    detector: ScreenEdgeDetector? = nil
) -> Bool {
    let detector = detector ?? ScreenEdgeDetector(displays: displays)
    var now: TimeInterval = 1000
    var lastMove = now
    for point in path {
        #expect(detector.feed(point, at: now) == nil)
        lastMove = now
        now += step
    }
    return detector.pointerStopped(at: lastMove) != nil
}

/// A straight line from `start` to `end` in steps of about 10 pt, both ends
/// included.
private func line(_ start: CGPoint, _ end: CGPoint) -> [CGPoint] {
    let steps = max(1, Int((hypot(end.x - start.x, end.y - start.y) / 10).rounded(.up)))
    return (0...steps).map { index in
        let t = CGFloat(index) / CGFloat(steps)
        return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }
}

/// Into the edge point and back out to `back`.
private func bump(from start: CGPoint, edge: CGPoint, back: CGPoint) -> [CGPoint] {
    line(start, edge) + line(edge, back).dropFirst()
}

@Test func stoppingAfterBumpingTheTopEdgeTriggers() {
    #expect(playAndStop(bump(from: CGPoint(x: 800, y: 300), edge: CGPoint(x: 800, y: 0), back: CGPoint(x: 800, y: 120))))
}

@Test func stoppingAfterBumpingTheBottomEdgeTriggers() {
    // A real pointer stops one point above the bottom bound.
    #expect(playAndStop(bump(from: CGPoint(x: 800, y: 800), edge: CGPoint(x: 800, y: 1116), back: CGPoint(x: 800, y: 1000))))
}

@Test func stoppingAfterBumpingTheLeftAndRightEdgesTriggers() {
    #expect(playAndStop(bump(from: CGPoint(x: 300, y: 500), edge: CGPoint(x: 0, y: 500), back: CGPoint(x: 80, y: 500))))
    #expect(playAndStop(bump(from: CGPoint(x: 1400, y: 500), edge: CGPoint(x: 1727, y: 500), back: CGPoint(x: 1600, y: 500))))
}

@Test func theGestureReportsWhereThePointerStopped() {
    let detector = ScreenEdgeDetector(displays: [laptop])
    let path = bump(from: CGPoint(x: 800, y: 300), edge: CGPoint(x: 800, y: 0), back: CGPoint(x: 780, y: 140))
    for (index, point) in path.enumerated() {
        _ = detector.feed(point, at: 1000 + Double(index) * 0.01)
    }
    #expect(detector.pointerStopped(at: 1000 + Double(path.count - 1) * 0.01) == CGPoint(x: 780, y: 140))
}

@Test func stoppingAtTheEdgeDoesNotTrigger() {
    #expect(!playAndStop(line(CGPoint(x: 800, y: 300), CGPoint(x: 800, y: 0))))
}

@Test func stoppingJustOffTheEdgeDoesNotTrigger() {
    #expect(!playAndStop(bump(from: CGPoint(x: 800, y: 300), edge: CGPoint(x: 800, y: 0), back: CGPoint(x: 800, y: 20))))
}

@Test func nearingTheEdgeWithoutTouchingItDoesNotTrigger() {
    #expect(!playAndStop(bump(from: CGPoint(x: 800, y: 300), edge: CGPoint(x: 800, y: 5), back: CGPoint(x: 800, y: 200))))
}

@Test func aSlowReturnDoesNotTrigger() {
    // 20 samples 120 ms apart after the touch take longer than the bump window.
    #expect(!playAndStop(bump(from: CGPoint(x: 800, y: 300), edge: CGPoint(x: 800, y: 0), back: CGPoint(x: 800, y: 200)), step: 0.12))
}

@Test func aBumpAsSlowAsARealOneTriggers() {
    // The slowest bump recorded by hand: 0.93 s from the touch to the stop.
    #expect(playAndStop(bump(from: CGPoint(x: 800, y: 300), edge: CGPoint(x: 800, y: 0), back: CGPoint(x: 800, y: 300)), step: 0.031))
}

@Test func restingAtTheEdgeBeforeLeavingDoesNotTrigger() {
    let rest = Array(repeating: CGPoint(x: 800, y: 0), count: 300)
    #expect(!playAndStop(line(CGPoint(x: 800, y: 300), CGPoint(x: 800, y: 0)) + rest + line(CGPoint(x: 800, y: 0), CGPoint(x: 800, y: 150))))
}

@Test func anEdgeBetweenTwoDisplaysIsNoEdge() {
    let path = bump(from: CGPoint(x: 1400, y: 500), edge: CGPoint(x: 1727, y: 500), back: CGPoint(x: 1600, y: 500))
    #expect(!playAndStop(path, displays: [laptop, rightOfLaptop]))
}

@Test func theOuterEdgeOfASecondDisplayTriggers() {
    let path = bump(from: CGPoint(x: 3300, y: 500), edge: CGPoint(x: 3647, y: 500), back: CGPoint(x: 3500, y: 500))
    #expect(playAndStop(path, displays: [laptop, rightOfLaptop]))
}

@Test func resetForgetsTheTouch() {
    let detector = ScreenEdgeDetector(displays: [laptop])
    for (index, point) in bump(from: CGPoint(x: 800, y: 300), edge: CGPoint(x: 800, y: 0), back: CGPoint(x: 800, y: 150)).enumerated() {
        _ = detector.feed(point, at: 1000 + Double(index) * 0.01)
    }
    detector.reset()
    #expect(detector.pointerStopped(at: 1000.5) == nil)
}

@Test func edgeTriggerRearmsAfterFiring() {
    let detector = ScreenEdgeDetector(displays: [laptop])
    let path = bump(from: CGPoint(x: 800, y: 300), edge: CGPoint(x: 800, y: 0), back: CGPoint(x: 800, y: 120))
    #expect(playAndStop(path, detector: detector))
    #expect(playAndStop(path, detector: detector))
}

@Test func crossingOntoADisplayMissingFromTheListIsNoBump() {
    // The display right of the laptop is on, but the detector's list does
    // not have it yet.
    let path = line(CGPoint(x: 1500, y: 500), CGPoint(x: 1800, y: 500))
    #expect(!playAndStop(path, displays: [laptop]))
    #expect(!playAndStop(path, displays: [laptop, rightOfLaptop]))
}
