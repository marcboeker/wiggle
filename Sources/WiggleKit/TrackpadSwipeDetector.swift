import CoreGraphics
import Foundation

enum SwipeDirection {
    case up, down
}

/// Completes once the swiping fingers lift within `Config.swipeMaxDuration`.
///
/// Only a touch that moves away from where it landed swipes. A quick swipe
/// often brings the heel of the hand or the thumb down on the trackpad's
/// edge, and such a still touch must not count as a finger. Exactly
/// `fingers` touches must swipe, and their mean net travel decides, so a
/// swipe up and back down is no swipe. A click (a `reset()`) spoils the
/// touch until every finger has lifted.
final class TrackpadSwipeDetector: TriggerDetector {

    private struct Touch {
        let startTime: TimeInterval
        var landings: TouchFrame = [:]
        /// Also keeps a finger that lifted before the others.
        var latest: TouchFrame = [:]

        var swipers: Set<Int> {
            Set(landings.compactMap { id, landing in
                let position = latest[id] ?? landing
                return movedAway(position, from: landing) ? id : nil
            })
        }

        /// `NSTouch.normalizedPosition` has its origin at the bottom left, so
        /// a swipe up has a positive `dy`.
        func travel(of ids: Set<Int>) -> CGVector {
            var sum = CGVector.zero
            for id in ids {
                guard let landing = landings[id], let position = latest[id] else { continue }
                sum.dx += position.x - landing.x
                sum.dy += position.y - landing.y
            }
            let count = CGFloat(max(ids.count, 1))
            return CGVector(dx: sum.dx / count, dy: sum.dy / count)
        }
    }

    private enum State {
        case idle
        case touching(Touch)
        case spoiled
    }

    let fingers: Int
    let direction: SwipeDirection
    private var state = State.idle

    init(fingers: Int, direction: SwipeDirection) {
        self.fingers = fingers
        self.direction = direction
    }

    func reset() {
        if case .touching = state { state = .spoiled }
    }

    func touchesChanged(_ touches: TouchFrame, pointer: CGPoint, at now: TimeInterval) -> CGPoint? {
        if touches.isEmpty {
            defer { state = .idle }
            guard case .touching(let touch) = state else { return nil }
            return complete(touch, swipers: touch.swipers, pointer: pointer, at: now)
        }

        var touch: Touch
        switch state {
        case .spoiled: return nil
        case .idle: touch = Touch(startTime: now)
        case .touching(let current): touch = current
        }
        for (id, position) in touches {
            touch.landings[id] = touch.landings[id] ?? position
            touch.latest[id] = position
        }
        guard now - touch.startTime <= Config.swipeMaxDuration else {
            state = .spoiled
            return nil
        }
        // Only still touches remain: the swiping fingers have lifted.
        let swipers = touch.swipers
        if !swipers.isEmpty, swipers.isDisjoint(with: touches.keys) {
            state = .spoiled
            return complete(touch, swipers: swipers, pointer: pointer, at: now)
        }
        state = .touching(touch)
        return nil
    }

    private func complete(_ touch: Touch, swipers: Set<Int>, pointer: CGPoint, at now: TimeInterval) -> CGPoint? {
        guard swipers.count == fingers, now - touch.startTime <= Config.swipeMaxDuration,
              isSwipe(touch.travel(of: swipers))
        else { return nil }
        return pointer
    }

    private func isSwipe(_ travel: CGVector) -> Bool {
        let forward = direction == .up ? travel.dy : -travel.dy
        return forward >= Config.swipeMinTravel && forward >= Config.swipeVerticalRatio * abs(travel.dx)
    }
}
