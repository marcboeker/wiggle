import CoreGraphics

/// Where each slot sits on the wheel. Free of AppKit.
enum SlotLayout {

    static let innerSliceWidthDegrees = 45.0
    static let outerSliceWidthDegrees = 22.5

    /// Ring 1 slot 1 spans 67.5°...112.5°, straddling the top. Ring 2 slot 1
    /// spans 90°...112.5°. Both rings count clockwise from 112.5°.
    static let topEdgeDegrees = 90 + innerSliceWidthDegrees / 2

    /// The centre angle of a slot's slice, in degrees counter-clockwise from
    /// the positive x-axis. `nil` for the centre.
    static func angleDegrees(for id: SlotID) -> Double? {
        switch id {
        case .center:
            return nil
        case .inner(let n):
            return normalized(90 - innerSliceWidthDegrees * Double(n - 1))
        case .outer(let n):
            return normalized(topEdgeDegrees - outerSliceWidthDegrees * (Double(n) - 0.5))
        }
    }

    /// In the flipped coordinates the overlay view draws in.
    static func point(angleDegrees: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y - radius * CGFloat(sin(radians)))
    }

    static func hub(side: CGFloat) -> CGPoint { CGPoint(x: side / 2, y: side / 2) }

    /// The inner and outer radius of a ring's slices. The hub is ring 0.
    static func radii(ring: Int) -> (inner: CGFloat, outer: CGFloat) {
        switch ring {
        case 0: (0, Config.circleHubRadius)
        case 1: (Config.circleHubRadius, Config.circleInnerRingOuterRadius)
        default: (Config.circleInnerRingOuterRadius, Config.circleOuterRingOuterRadius)
        }
    }

    /// Where a slot's content is centred.
    static func labelCenter(for id: SlotID, side: CGFloat) -> CGPoint {
        let center = hub(side: side)
        guard let angle = angleDegrees(for: id) else { return center }
        let radii = radii(ring: id.ring)
        return point(angleDegrees: angle, radius: (radii.inner + radii.outer) / 2, center: center)
    }

    /// The side of the square a slot's icon fills.
    static func iconBoxSide(for id: SlotID) -> CGFloat {
        switch id {
        case .center: Config.circleHubRadius * 2
        case .inner: Config.circleInnerSliceIconBoxSize
        case .outer: Config.circleOuterSliceIconBoxSize
        }
    }

    /// The slot at `dx`/`dy` from the hub. While ring 2 is hidden, a point
    /// beyond ring 1 hits nothing.
    static func slotID(dx: CGFloat, dy: CGFloat, showsOuterRing: Bool) -> SlotID? {
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance <= radii(ring: showsOuterRing ? 2 : 1).outer else { return nil }
        if distance <= Config.circleHubRadius { return .center }

        var angle = atan2(Double(-dy), Double(dx)) * 180 / .pi
        if angle < 0 { angle += 360 }

        if distance > Config.circleInnerRingOuterRadius {
            return .outer(outerSlotNumber(at: angle))
        }
        return .inner(innerSlotNumber(at: angle))
    }

    /// Degrees clockwise from `topEdgeDegrees`. A point on a boundary belongs
    /// to the slot clockwise of it, in both rings, so ring 2 slots `2n-1` and
    /// `2n` split ring 1 slot `n` exactly.
    private static func shift(from angle: Double) -> Double {
        normalized(topEdgeDegrees - angle)
    }

    static func innerSlotNumber(at angle: Double) -> Int {
        Int(shift(from: angle) / innerSliceWidthDegrees) % 8 + 1
    }

    static func outerSlotNumber(at angle: Double) -> Int {
        Int(shift(from: angle) / outerSliceWidthDegrees) % 16 + 1
    }

    private static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}

extension CGRect {
    init(center: CGPoint, size: CGSize) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
