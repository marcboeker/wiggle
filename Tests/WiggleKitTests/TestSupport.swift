import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

func temporaryConfigURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wiggle-test-\(UUID().uuidString)")
        .appendingPathComponent("config.json")
}

let pointer = CGPoint(x: 640, y: 400)

/// `count` fingers side by side, each moved by `dx` and `dy`.
func fingers(_ count: Int, dx: CGFloat = 0, dy: CGFloat = 0) -> TouchFrame {
    TouchFrame(uniqueKeysWithValues: (0..<count).map {
        ($0, CGPoint(x: 0.3 + 0.1 * CGFloat($0) + dx, y: 0.4 + dy))
    })
}

/// Plays touch frames `step` apart, then lifts every finger but those in
/// `lift`. No frame before the lift may complete a gesture.
func playAndLift(
    _ frames: [TouchFrame], step: TimeInterval = 0.01, lift: TouchFrame = [:], detector: any TriggerDetector
) -> CGPoint? {
    var now: TimeInterval = 1000
    for frame in frames {
        #expect(detector.touchesChanged(frame, pointer: pointer, at: now) == nil)
        now += step
    }
    return detector.touchesChanged(lift, pointer: pointer, at: now)
}
