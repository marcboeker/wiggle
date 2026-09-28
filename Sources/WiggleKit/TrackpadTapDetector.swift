import CoreGraphics
import Foundation

/// The fingers touch the trackpad and all lift within
/// `Config.tapMaxDuration`. The most fingers down at once must be exactly
/// `fingers`, so a four finger tap is no three finger tap. A finger that
/// moves too far, or a click (a `reset()`), spoils the touch until every
/// finger has lifted.
final class TrackpadTapDetector: TriggerDetector {

    private struct Touch {
        let startTime: TimeInterval
        var landings: TouchFrame = [:]
        var mostFingers = 0
    }

    private enum State {
        case idle
        case touching(Touch)
        case spoiled
    }

    let fingers: Int
    private var state = State.idle

    init(fingers: Int) {
        self.fingers = fingers
    }

    func reset() {
        if case .touching = state { state = .spoiled }
    }

    func touchesChanged(_ touches: TouchFrame, pointer: CGPoint, at now: TimeInterval) -> CGPoint? {
        if touches.isEmpty {
            defer { state = .idle }
            guard case .touching(let touch) = state, touch.mostFingers == fingers,
                  now - touch.startTime <= Config.tapMaxDuration
            else { return nil }
            return pointer
        }

        var touch: Touch
        switch state {
        case .spoiled: return nil
        case .idle: touch = Touch(startTime: now)
        case .touching(let current): touch = current
        }
        for (id, position) in touches {
            let landing = touch.landings[id] ?? position
            touch.landings[id] = landing
            if movedAway(position, from: landing) {
                state = .spoiled
                return nil
            }
        }
        touch.mostFingers = max(touch.mostFingers, touches.count)
        let isTap = touch.mostFingers <= fingers && now - touch.startTime <= Config.tapMaxDuration
        state = isTap ? .touching(touch) : .spoiled
        return nil
    }
}
