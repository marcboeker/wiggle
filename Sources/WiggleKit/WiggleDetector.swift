import CoreGraphics
import Foundation

/// Counts direction changes along whichever axis moves the most, so a
/// horizontal and a vertical shake both qualify. A change counts only after
/// a leg long enough to be deliberate, and the movement must stay inside a
/// small area, so a fast throw across the screen never triggers.
final class WiggleDetector: TriggerDetector {

    private var lastPoint: CGPoint?
    private var direction = 0
    private var legLength: CGFloat = 0
    private var pendingReverse: CGFloat = 0
    private var reversals: [TimeInterval] = []
    private var samples: [(time: TimeInterval, point: CGPoint)] = []

    func reset() {
        lastPoint = nil
        direction = 0
        legLength = 0
        pendingReverse = 0
        reversals.removeAll()
        samples.removeAll()
    }

    func feed(_ point: CGPoint, at now: TimeInterval) -> CGPoint? {
        samples.append((now, point))
        dropStale(&samples, now: now) { $0.time }

        guard let previous = lastPoint else {
            lastPoint = point
            return nil
        }
        let dx = point.x - previous.x
        let dy = point.y - previous.y
        lastPoint = point
        let delta = abs(dx) >= abs(dy) ? dx : dy
        guard delta != 0 else { return nil }

        let currentDirection = delta > 0 ? 1 : -1
        guard direction != 0 else {
            direction = currentDirection
            legLength = abs(delta)
            return nil
        }
        if currentDirection == direction {
            legLength += abs(delta)
            pendingReverse = 0
            return nil
        }

        pendingReverse += abs(delta)
        guard pendingReverse >= Config.reverseHysteresis else { return nil }

        let finishedLeg = legLength
        direction = currentDirection
        legLength = pendingReverse
        pendingReverse = 0
        guard finishedLeg >= Config.minLegDistance else { return nil }

        reversals.append(now)
        dropStale(&reversals, now: now) { $0 }
        guard reversals.count >= Config.reversalsToTrigger,
              travelSpan() <= Config.maxTravel
        else { return nil }

        reset()
        return point
    }

    /// Both arrays are in time order, so stale entries are a leading run.
    private func dropStale<T>(_ items: inout [T], now: TimeInterval, time: (T) -> TimeInterval) {
        while let first = items.first, now - time(first) > Config.wiggleWindow {
            items.removeFirst()
        }
    }

    private func travelSpan() -> CGFloat {
        guard let first = samples.first else { return 0 }
        var minX = first.point.x, maxX = first.point.x
        var minY = first.point.y, maxY = first.point.y
        for sample in samples.dropFirst() {
            minX = min(minX, sample.point.x); maxX = max(maxX, sample.point.x)
            minY = min(minY, sample.point.y); maxY = max(maxY, sample.point.y)
        }
        return max(maxX - minX, maxY - minY)
    }
}
