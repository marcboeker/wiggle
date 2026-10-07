import AppKit

/// The wheel: a centre hub (ring 0), eight slices around it (ring 1), and,
/// while `showsOuterRing` is on, sixteen finer slices around that (ring 2).
/// Each slot draws as a rounded tile on one dark disc; the hovered tile turns
/// coral and lifts outward.
@MainActor
final class CircularOverlayView: NSView {

    var slots: [SlotID: Slot] = [:] { didSet { if slots != oldValue { needsDisplay = true } } }
    var hovered: SlotID? { didSet { if hovered != oldValue { hoverChanged() } } }

    /// A previous app slot shows this icon, or a symbol while it is `nil`,
    /// as in Settings.
    var previousAppIcon: NSImage? { didSet { if previousAppIcon !== oldValue { needsDisplay = true } } }

    /// The overlay shows ring 2 only while one of its slots is assigned.
    /// Settings always shows it, so an empty ring 2 slot can be assigned.
    var showsOuterRing = true { didSet { if showsOuterRing != oldValue { needsDisplay = true } } }

    /// The overlay hides empty slots; Settings shows them so they can be
    /// assigned.
    var backgroundOpacity = Config.defaultBackgroundOpacity { didSet { if backgroundOpacity != oldValue { needsDisplay = true } } }
    var showsEmptySlots = true { didSet { if showsEmptySlots != oldValue { needsDisplay = true } } }

    private func isShown(_ id: SlotID) -> Bool {
        (id.ring < 2 || showsOuterRing) && (showsEmptySlots || slots[id] != nil)
    }

    var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var palette: WheelPalette { isDarkMode ? .dark : .light }

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

    // MARK: Hover lift

    /// How far each tile is lifted, 0 at rest and 1 fully out. Only the
    /// hovered tile and the ones still settling have an entry.
    private var lift: [SlotID: CGFloat] = [:]
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    private func hoverChanged() {
        needsDisplay = true
        if let hovered, lift[hovered] == nil { lift[hovered] = 0 }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || window == nil {
            lift = hovered.map { [$0: 1] } ?? [:]
            return
        }
        guard displayLink == nil else { return }
        lastFrame = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Exponential ease-out toward the target, the same speed for every frame
    /// rate.
    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let k = CGFloat(1 - exp(-(now - lastFrame) / Config.wheelLiftTimeConstant))
        lastFrame = now
        var settled = true
        for (id, value) in lift {
            let target: CGFloat = id == hovered ? 1 : 0
            let next = value + (target - value) * k
            if abs(target - next) < 0.01 {
                lift[id] = target == 0 ? nil : target
            } else {
                lift[id] = next
                settled = false
            }
        }
        needsDisplay = true
        if settled {
            link.invalidate()
            displayLink = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
            lift = hovered.map { [$0: 1] } ?? [:]
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let center = hub
        // The lifted tiles last, on top of their neighbours' shadows.
        let order = SlotID.all.dropFirst().sorted { (lift[$0] ?? 0) < (lift[$1] ?? 0) }
        drawDisc(center: center)
        for id in order where isShown(id) { drawTile(id, center: center) }
        if isShown(.center) { drawHub(center: center) }
    }

    /// In unflipped coordinates, for the layer mask that clips the blurred
    /// backdrop to the disc. The disc is round about the hub, so flipping
    /// it changes nothing.
    func backdropPath() -> CGPath {
        CGPath(ellipseIn: discRect, transform: nil)
    }

    /// Under every ring, also behind hidden slots, so text in the window
    /// below never runs through the wheel.
    private var discRect: NSRect {
        let r = SlotLayout.radii(ring: showsOuterRing ? 2 : 1).outer + Config.wheelDiscMargin
        return NSRect(center: hub, size: NSSize(width: r * 2, height: r * 2))
    }

    private func drawDisc(center: NSPoint) {
        let colors = palette
        NSGraphicsContext.saveGraphicsState()
        // A wide, soft shadow sets the disc apart from a busy window below.
        let scrim = NSShadow()
        scrim.shadowColor = colors.scrim
        scrim.shadowBlurRadius = 18
        scrim.shadowOffset = .zero
        scrim.set()
        colors.disc.withAlphaComponent(backgroundOpacity).setFill()
        NSBezierPath(ovalIn: discRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The tile's centre point, moved outward along the slice by its lift.
    private func tileCenter(_ id: SlotID, center: NSPoint) -> NSPoint {
        guard let angle = SlotLayout.angleDegrees(for: id), let value = lift[id], value > 0 else { return center }
        return SlotLayout.point(angleDegrees: angle, radius: Config.wheelLiftDistance * value, center: center)
    }

    private func drawTile(_ id: SlotID, center: NSPoint) {
        let colors = palette
        let shape = TileShape(id: id)
        let mid = SlotLayout.angleDegrees(for: id) ?? 0
        let origin = tileCenter(id, center: center)
        let path = shape.path(mid: mid, center: origin)
        let isHovered = hovered == id
        let raised = lift[id] ?? (isHovered ? 1 : 0)

        // The shadow deepens as the tile lifts.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = colors.shadow.withAlphaComponent(colors.shadowAlpha * (1 + raised * 0.4))
        shadow.shadowBlurRadius = 8 + 4 * raised
        shadow.shadowOffset = NSSize(width: 0, height: -(3 + raised))
        shadow.set()
        colors.base.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        (id.ring == 1 ? colors.innerTile : colors.outerTile).setFill()
        path.fill()
        if let edge = colors.tileEdge {
            // Clipped, so half the stroke shows: a 1 pt edge inside the tile.
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            edge.setStroke()
            path.lineWidth = 2
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        if raised > 0 {
            colors.accent.withAlphaComponent(raised).setFill()
            path.fill()
        }

        if let tint = slots[id]?.color {
            drawRim(tint.color, shape: shape, ring: id.ring, mid: mid, clip: path, center: origin)
        }

        let hintPoint = SlotLayout.point(angleDegrees: mid, radius: shape.inner + shape.hintInset, center: origin)
        let hintColor = isHovered ? colors.onAccent : colors.hint
        OverlayText.drawHint(id.keyHint, at: hintPoint, size: shape.hintSize, color: hintColor)

        let contentCenter = SlotLayout.point(angleDegrees: mid, radius: shape.contentRadius, center: origin)
        let iconSide = shape.iconBox * (1 + 0.1 * raised)
        let iconRect = NSRect(center: contentCenter, size: NSSize(width: iconSide, height: iconSide))
        // A slice's text box stays narrow so text never spills into a
        // neighbour; its icon gets the larger square.
        let labelRect = NSRect(center: contentCenter, size: NSSize(width: 60, height: 32))
        drawContent(id, in: labelRect, iconRect: iconRect, color: isHovered ? colors.onAccent : colors.ink, lifted: raised > 0)
    }

    /// A slot's colour as a band along one edge of the tile. Ring 2 uses its
    /// outer edge, the rim of the wheel. Ring 1 uses its hub side, so the
    /// gap between the rings never carries two edges. The outer band stops
    /// short of the rounded corners. The hub side is too short for that, so
    /// its band runs the full width and goes deeper, a cap on the tile's tip.
    private func drawRim(_ color: NSColor, shape: TileShape, ring: Int, mid: Double, clip: NSBezierPath, center: NSPoint) {
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        let onHubSide = ring == 1
        let inset = onHubSide ? 0 : Double(shape.corner / shape.outer) * 180 / .pi
        let band = TileShape.wedge(
            center: center, startAngle: mid - shape.halfWidth + inset, endAngle: mid + shape.halfWidth - inset,
            innerRadius: onHubSide ? shape.inner - 2 : shape.outer - Config.wheelRimWidth,
            outerRadius: onHubSide ? shape.inner + Config.wheelHubSideRimDepth : shape.outer + 2,
            gap: Config.wheelTileGap, corner: 0)
        color.setFill()
        band.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawHub(center: NSPoint) {
        let colors = palette
        let r = Config.circleHubRadius
        let disc = NSBezierPath(ovalIn: NSRect(center: center, size: NSSize(width: r * 2, height: r * 2)))
        let isHovered = hovered == .center

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = colors.shadow.withAlphaComponent(colors.shadowAlpha)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        (isHovered ? colors.accent : colors.base).setFill()
        disc.fill()
        NSGraphicsContext.restoreGraphicsState()

        // The hub's colour takes the place of the coral ring.
        let ringSide = (r - 5) * 2
        let ring = NSBezierPath(ovalIn: NSRect(center: center, size: NSSize(width: ringSide, height: ringSide)))
        ring.lineWidth = 3
        (isHovered ? colors.onAccent : slots[.center]?.color?.color ?? colors.accent).setStroke()
        ring.stroke()

        // The hub's hint sits below its centre.
        let hintPoint = SlotLayout.point(angleDegrees: 270, radius: r - Config.circleHintInset, center: center)
        OverlayText.drawHint(SlotID.center.keyHint, at: hintPoint, size: 9, color: isHovered ? colors.onAccent : colors.hint)

        let iconSide = SlotLayout.iconBoxSide(for: .center)
        let iconRect = NSRect(center: center, size: NSSize(width: iconSide, height: iconSide))
        drawContent(.center, in: iconRect, iconRect: iconRect, color: isHovered ? colors.onAccent : colors.ink, lifted: false)
    }

    private func drawContent(_ id: SlotID, in rect: NSRect, iconRect: NSRect, color: NSColor, lifted: Bool) {
        NSGraphicsContext.saveGraphicsState()
        if lifted {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 5
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
        }
        OverlayText.drawSlotContent(
            slots[id]?.assignment, previousAppIcon: previousAppIcon, in: rect, iconRect: iconRect, color: color)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// The graphite and coral of the wheel. The accent matches the app icon's
/// coral; the tiles stay neutral so app icons keep their own colours.
private struct WheelPalette {
    let disc: NSColor
    let scrim: NSColor
    /// The hub and the ground under every tile.
    let base: NSColor
    let innerTile: NSColor
    let outerTile: NSColor
    /// A light edge inside each tile, where shadows alone do not lift it.
    let tileEdge: NSColor?
    let ink: NSColor
    let hint: NSColor
    let accent: NSColor
    /// Text and rings on a coral fill.
    let onAccent: NSColor
    let shadow: NSColor
    let shadowAlpha: CGFloat

    /// The tiles sit well above the disc, which a dark window below would
    /// otherwise match.
    static let dark = WheelPalette(
        disc: NSColor(srgbHex: 0x0B0A0D), scrim: NSColor.black.withAlphaComponent(0.8),
        base: NSColor(srgbHex: 0x141316), innerTile: NSColor(srgbHex: 0x3B3842), outerTile: NSColor(srgbHex: 0x322F38),
        tileEdge: NSColor.white.withAlphaComponent(0.12),
        ink: NSColor(srgbHex: 0xF4EFEA), hint: NSColor(srgbHex: 0xF4EFEA, alpha: 0.92),
        accent: NSColor(srgbHex: 0xFF7A45), onAccent: NSColor(srgbHex: 0x1A1416),
        shadow: .black, shadowAlpha: 0.5)

    static let light = WheelPalette(
        disc: NSColor(srgbHex: 0xE4E0DA), scrim: NSColor(srgbHex: 0x1B1A1F, alpha: 0.25),
        base: NSColor(srgbHex: 0xFCFBF9), innerTile: NSColor(srgbHex: 0xFAF8F5), outerTile: NSColor(srgbHex: 0xF4F1ED),
        tileEdge: nil,
        ink: NSColor(srgbHex: 0x1B1A1F), hint: NSColor(srgbHex: 0x5E5A57, alpha: 0.85),
        accent: NSColor(srgbHex: 0xFF6A33), onAccent: NSColor(srgbHex: 0x1A1416),
        shadow: NSColor(srgbHex: 0x1B1A1F), shadowAlpha: 0.16)
}

/// A ring 1 or ring 2 tile: its radii, corner and where its content sits.
private struct TileShape {
    let inner: CGFloat
    let outer: CGFloat
    let halfWidth: Double
    let corner: CGFloat
    let hintInset: CGFloat
    let hintSize: CGFloat
    let iconBox: CGFloat
    let contentRadius: CGFloat

    init(id: SlotID) {
        let radii = SlotLayout.radii(ring: id.ring)
        let gap = Config.wheelTileGap
        if id.ring == 1 {
            inner = radii.inner + gap * 0.67
            outer = radii.outer - gap / 2
            halfWidth = SlotLayout.innerSliceWidthDegrees / 2
            corner = 11
            hintInset = 15
            hintSize = 11
            iconBox = Config.circleInnerSliceTileIconSize
            contentRadius = (radii.inner + radii.outer) / 2 + 5
        } else {
            inner = radii.inner + gap / 2
            outer = radii.outer
            halfWidth = SlotLayout.outerSliceWidthDegrees / 2
            corner = 9
            hintInset = 10
            hintSize = 10.5
            iconBox = Config.circleOuterSliceTileIconSize
            contentRadius = (radii.inner + radii.outer) / 2 + 2
        }
    }

    func path(mid: Double, center: NSPoint) -> NSBezierPath {
        Self.wedge(
            center: center, startAngle: mid - halfWidth, endAngle: mid + halfWidth,
            innerRadius: inner, outerRadius: outer, gap: Config.wheelTileGap, corner: corner)
    }

    /// An annulus sector whose straight edges run `gap / 2` inside the
    /// slice's rays, so neighbours keep an even gap, with rounded corners.
    static func wedge(
        center: NSPoint, startAngle: Double, endAngle: Double,
        innerRadius: CGFloat, outerRadius: CGFloat, gap: CGFloat, corner: CGFloat
    ) -> NSBezierPath {
        let h = gap / 2
        // Degrees the edge sits inside its ray at radius r.
        func inset(_ r: CGFloat) -> Double { Double(asin(min(1, h / r))) * 180 / .pi }
        // The point at radius r on the edge parallel to ray `angle`,
        // `side` +1 toward larger angles.
        func edge(_ angle: Double, _ r: CGFloat, _ side: CGFloat) -> NSPoint {
            let radians = angle * .pi / 180
            let along = max(r * r - h * h, 0).squareRoot()
            let x = CGFloat(cos(radians)) * along - CGFloat(sin(radians)) * side * h
            let y = CGFloat(sin(radians)) * along + CGFloat(cos(radians)) * side * h
            return NSPoint(x: center.x + x, y: center.y - y)
        }
        func arcPoint(_ angle: Double, _ r: CGFloat) -> NSPoint {
            SlotLayout.point(angleDegrees: angle, radius: r, center: center)
        }

        let path = NSBezierPath()
        func arc(_ r: CGFloat, from: Double, to: Double) {
            let steps = 16
            for step in 1...steps { path.line(to: arcPoint(from + (to - from) * Double(step) / Double(steps), r)) }
        }
        let k = corner, c = 0.45 as CGFloat
        let outerStart = startAngle + inset(outerRadius), outerEnd = endAngle - inset(outerRadius)
        let innerStart = startAngle + inset(innerRadius), innerEnd = endAngle - inset(innerRadius)
        let outerCorner = Double(k / outerRadius) * 180 / .pi
        let innerCorner = Double(k / innerRadius) * 180 / .pi

        path.move(to: edge(startAngle, outerRadius - k, 1))
        path.curve(
            to: arcPoint(outerStart + outerCorner, outerRadius),
            controlPoint1: edge(startAngle, outerRadius - k * c, 1),
            controlPoint2: arcPoint(outerStart + outerCorner * Double(c), outerRadius))
        arc(outerRadius, from: outerStart + outerCorner, to: outerEnd - outerCorner)
        path.curve(
            to: edge(endAngle, outerRadius - k, -1),
            controlPoint1: arcPoint(outerEnd - outerCorner * Double(c), outerRadius),
            controlPoint2: edge(endAngle, outerRadius - k * c, -1))
        path.line(to: edge(endAngle, innerRadius + k, -1))
        path.curve(
            to: arcPoint(innerEnd - innerCorner, innerRadius),
            controlPoint1: edge(endAngle, innerRadius + k * c, -1),
            controlPoint2: arcPoint(innerEnd - innerCorner * Double(c), innerRadius))
        arc(innerRadius, from: innerEnd - innerCorner, to: innerStart + innerCorner)
        path.curve(
            to: edge(startAngle, innerRadius + k, 1),
            controlPoint1: arcPoint(innerStart + innerCorner * Double(c), innerRadius),
            controlPoint2: edge(startAngle, innerRadius + k * c, 1))
        path.close()
        return path
    }
}

extension NSColor {
    convenience init(srgbHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
