import AppKit

/// The wheel: a centre hub (ring 0), eight slices around it (ring 1), and,
/// while `showsOuterRing` is on, sixteen finer slices around that (ring 2).
@MainActor
final class CircularOverlayView: NSView {

    var slots: [SlotID: Slot] = [:] { didSet { if slots != oldValue { needsDisplay = true } } }
    var hovered: SlotID? { didSet { if hovered != oldValue { needsDisplay = true } } }

    /// A previous app slot shows this icon, or a symbol while it is `nil`,
    /// as in Settings.
    var previousAppIcon: NSImage? { didSet { if previousAppIcon !== oldValue { needsDisplay = true } } }

    /// The overlay shows ring 2 only while one of its slots is assigned.
    /// Settings always shows it, so an empty ring 2 slot can be assigned.
    var showsOuterRing = true { didSet { if showsOuterRing != oldValue { needsDisplay = true } } }

    /// The overlay hides empty slots; Settings shows them so they can be
    /// assigned.
    var showsEmptySlots = true { didSet { if showsEmptySlots != oldValue { needsDisplay = true } } }

    private func isShown(_ id: SlotID) -> Bool {
        (id.ring < 2 || showsOuterRing) && (showsEmptySlots || slots[id] != nil)
    }

    /// The wheel content takes the opposite colour of the backdrop.
    var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var contentColor: NSColor { isDarkMode ? .white : .black }

    /// The shade the backdrop leans toward, so a separator reads as a
    /// boundary rather than another highlight.
    private var separatorColor: NSColor { isDarkMode ? .black : .white }

    override var isFlipped: Bool { true }

    private var hub: NSPoint { SlotLayout.hub(side: bounds.width) }

    func slotID(at point: NSPoint) -> SlotID? {
        rawSlotID(at: point).flatMap { isShown($0) ? $0 : nil }
    }

    /// Also finds a hidden empty slot, so a click on one can be told apart
    /// from a click that missed the wheel.
    func rawSlotID(at point: NSPoint) -> SlotID? {
        SlotLayout.slotID(dx: point.x - hub.x, dy: point.y - hub.y, showsOuterRing: showsOuterRing)
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = hub

        if showsEmptySlots {
            let radius = SlotLayout.radii(ring: showsOuterRing ? 2 : 1).outer
            contentColor.withAlphaComponent(0.14).setStroke()
            let outline = NSBezierPath(ovalIn: NSRect(center: center, size: NSSize(width: radius * 2, height: radius * 2)))
            outline.lineWidth = 1
            outline.stroke()
        }

        // The hub last, on top of the slices' separators.
        for id in SlotID.all.dropFirst() + [.center] where isShown(id) { drawSlot(id, center: center) }
    }

    /// In unflipped coordinates, for the layer mask that clips the blurred
    /// backdrop, so the area of a hidden slot stays transparent.
    func backdropPath() -> CGPath {
        let center = hub
        let flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        let path = CGMutablePath()
        for id in SlotID.all where isShown(id) {
            path.addPath(slotPath(id, center: center).cgPath, transform: flip)
        }
        return path
    }

    private func slotPath(_ id: SlotID, center: NSPoint) -> NSBezierPath {
        let radii = SlotLayout.radii(ring: id.ring)
        guard let mid = SlotLayout.angleDegrees(for: id) else {
            return NSBezierPath(ovalIn: NSRect(center: center, size: NSSize(width: radii.outer * 2, height: radii.outer * 2)))
        }
        let half = (id.ring == 1 ? SlotLayout.innerSliceWidthDegrees : SlotLayout.outerSliceWidthDegrees) / 2
        return wedgePath(
            center: center, startAngle: mid - half, endAngle: mid + half,
            innerRadius: radii.inner, outerRadius: radii.outer)
    }

    private func drawSlot(_ id: SlotID, center: NSPoint) {
        let path = slotPath(id, center: center)
        let isHovered = hovered == id

        if let color = slots[id]?.color {
            color.color.withAlphaComponent(isHovered ? 0.45 : 0.25).setFill()
        } else {
            contentColor.withAlphaComponent(isHovered ? 0.20 : 0.08).setFill()
        }
        path.fill()
        // One device pixel: neighbours stroke the same shared edge.
        separatorColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1 / (window?.backingScaleFactor ?? 1)
        path.stroke()
        if isHovered {
            contentColor.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        // The hub's hint sits below its centre.
        let hintRadius = SlotLayout.radii(ring: id.ring).outer - Config.circleHintInset
        let hintPoint = SlotLayout.point(angleDegrees: SlotLayout.angleDegrees(for: id) ?? 270, radius: hintRadius, center: center)
        OverlayText.drawHint(id.keyHint, at: hintPoint, color: contentColor)

        let labelCenter = SlotLayout.labelCenter(for: id, side: bounds.width)
        let iconSide = SlotLayout.iconBoxSide(for: id)
        let iconRect = NSRect(center: labelCenter, size: NSSize(width: iconSide, height: iconSide))
        // A slice's text box stays narrow so text never spills into a
        // neighbour; its icon gets the larger square.
        let labelRect = id == .center ? iconRect : NSRect(center: labelCenter, size: NSSize(width: 60, height: 32))
        OverlayText.drawSlotContent(
            slots[id]?.assignment, previousAppIcon: previousAppIcon, in: labelRect, iconRect: iconRect, color: contentColor)
    }

    /// An annulus sector, approximated with straight segments.
    private func wedgePath(
        center: NSPoint, startAngle: Double, endAngle: Double,
        innerRadius: CGFloat, outerRadius: CGFloat
    ) -> NSBezierPath {
        let path = NSBezierPath()
        let steps = 16
        for step in 0...steps {
            let angle = startAngle + (endAngle - startAngle) * Double(step) / Double(steps)
            let p = SlotLayout.point(angleDegrees: angle, radius: outerRadius, center: center)
            step == 0 ? path.move(to: p) : path.line(to: p)
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let angle = startAngle + (endAngle - startAngle) * Double(step) / Double(steps)
            path.line(to: SlotLayout.point(angleDegrees: angle, radius: innerRadius, center: center))
        }
        path.close()
        return path
    }
}
