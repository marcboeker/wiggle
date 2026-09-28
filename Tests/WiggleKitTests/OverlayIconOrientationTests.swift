import AppKit
import Testing

@testable import WiggleKit

/// An asymmetric calibration image: a distinct color in each quadrant, so a
/// rotation or flip of any kind changes which color lands where.
private func calibrationImage() -> NSImage {
    let size = NSSize(width: 40, height: 40)
    return NSImage(size: size, flipped: false) { rect in
        let half = rect.width / 2
        NSColor.red.setFill()  // top-left, in the image's own un-flipped space
        NSRect(x: 0, y: half, width: half, height: half).fill()
        NSColor.green.setFill()  // top-right
        NSRect(x: half, y: half, width: half, height: half).fill()
        NSColor.blue.setFill()  // bottom-left
        NSRect(x: 0, y: 0, width: half, height: half).fill()
        NSColor.yellow.setFill()  // bottom-right
        NSRect(x: half, y: 0, width: half, height: half).fill()
        return true
    }
}

/// The production code path: a flipped view (as `CircularOverlayView` is)
/// drawing an app icon via `OverlayText.drawIcon`.
private final class FlippedIconView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        OverlayText.drawIcon(calibrationImage(), in: bounds)
    }
}

/// The baseline: an un-flipped view drawing the same image with the plain,
/// unambiguous `NSImage.draw(in:)`, using the same centred-square geometry
/// `drawIcon` uses. This is how the image is supposed to look.
private final class PlainIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height) * 0.6
        let target = NSRect(
            x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        calibrationImage().draw(in: target)
    }
}

@MainActor
private func renderedBitmap(_ view: NSView, bounds: NSRect) -> NSBitmapImageRep {
    let window = NSWindow(
        contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    let rep = view.bitmapImageRepForCachingDisplay(in: bounds)!
    view.cacheDisplay(in: bounds, to: rep)
    return rep
}

/// `CircularOverlayView` flips its coordinate system (`isFlipped == true`).
/// `OverlayText.drawIcon` must draw an app's icon the same way a plain,
/// un-flipped view would, or every icon in the overlay renders rotated 180
/// degrees.
@Test @MainActor func iconDrawsUprightInAFlippedView() {
    let bounds = NSRect(x: 0, y: 0, width: 60, height: 60)
    let flipped = renderedBitmap(FlippedIconView(frame: bounds), bounds: bounds)
    let plain = renderedBitmap(PlainIconView(frame: bounds), bounds: bounds)

    for x in stride(from: 14, through: 46, by: 8) {
        for y in stride(from: 14, through: 46, by: 8) {
            let flippedColor = flipped.colorAt(x: x, y: y)
            let plainColor = plain.colorAt(x: x, y: y)
            #expect(
                flippedColor?.redComponent == plainColor?.redComponent
                    && flippedColor?.greenComponent == plainColor?.greenComponent
                    && flippedColor?.blueComponent == plainColor?.blueComponent,
                Comment(
                    rawValue:
                        "at (\(x), \(y)): flipped view drew \(String(describing: flippedColor)), "
                        + "plain view drew \(String(describing: plainColor))"))
        }
    }
}
