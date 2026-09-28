import CoreGraphics
import Foundation

/// A bump: the pointer touches an outer edge, leaves it, and stops. It must
/// stop at least `Config.edgeLeaveDistance` from the edge, and its last
/// movement must come within `Config.edgeBumpWindow` of the touch, so a
/// pointer that rests at the edge or runs along the menu bar does not
/// trigger when it finally leaves. An edge between two displays is no edge.
final class ScreenEdgeDetector: TriggerDetector {

    private enum Edge: Equatable {
        case left(CGFloat), right(CGFloat), top(CGFloat), bottom(CGFloat)

        func distance(to point: CGPoint) -> CGFloat {
            switch self {
            case .left(let x), .right(let x): abs(point.x - x)
            case .top(let y), .bottom(let y): abs(point.y - y)
            }
        }
    }

    private let displays: [CGRect]
    private var contact: (edge: Edge, time: TimeInterval)?
    private var lastPoint: CGPoint?

    /// `displays` are the display bounds in the space of `CGEvent.location`,
    /// origin at the top left of the main display. The caller builds a new
    /// detector when the displays change.
    init(displays: [CGRect] = ScreenEdgeDetector.activeDisplayBounds()) {
        self.displays = displays
    }

    func reset() {
        contact = nil
        lastPoint = nil
    }

    func feed(_ point: CGPoint, at now: TimeInterval) -> CGPoint? {
        // The pointer is on a display the list does not know, so the edge it
        // crossed was no outer edge.
        guard let display = ScreenEdgeDetector.display(at: point, in: displays) else {
            reset()
            return nil
        }
        if let edge = ScreenEdgeDetector.outerEdge(at: point, of: display, displays: displays) {
            if contact?.edge != edge { contact = (edge, now) }
        } else if let contact, now - contact.time > Config.edgeBumpWindow {
            reset()
            return nil
        } else if contact == nil {
            return nil
        }
        lastPoint = point
        return nil
    }

    func pointerStopped(at time: TimeInterval) -> CGPoint? {
        guard let contact, let lastPoint,
              time - contact.time <= Config.edgeBumpWindow,
              contact.edge.distance(to: lastPoint) >= Config.edgeLeaveDistance
        else { return nil }

        reset()
        return lastPoint
    }

    /// A real pointer stops one point short of a display's right and bottom
    /// bounds.
    private static let reach = Config.edgeContactTolerance + 1

    private static func display(at point: CGPoint, in displays: [CGRect]) -> CGRect? {
        displays.first(where: { $0.contains(point) })
            ?? displays.first(where: { $0.insetBy(dx: -reach, dy: -reach).contains(point) })
    }

    private static func outerEdge(at point: CGPoint, of display: CGRect, displays: [CGRect]) -> Edge? {
        let tolerance = Config.edgeContactTolerance
        let onDesktop = { (probe: CGPoint) in displays.contains { $0.contains(probe) } }

        if point.x <= display.minX + tolerance, !onDesktop(CGPoint(x: display.minX - 1, y: point.y)) {
            return .left(display.minX)
        }
        if point.x >= display.maxX - reach, !onDesktop(CGPoint(x: display.maxX, y: point.y)) {
            return .right(display.maxX)
        }
        if point.y <= display.minY + tolerance, !onDesktop(CGPoint(x: point.x, y: display.minY - 1)) {
            return .top(display.minY)
        }
        if point.y >= display.maxY - reach, !onDesktop(CGPoint(x: point.x, y: display.maxY)) {
            return .bottom(display.maxY)
        }
        return nil
    }

    static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }
}
