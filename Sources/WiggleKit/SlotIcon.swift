import AppKit

enum SlotIcon {

    /// Enough for the hub on a Retina display, small enough that loading
    /// every icon stays cheap.
    static let maxPixelSide: CGFloat = 256

    /// An RGBA PNG, so transparency survives. Never scales a small bitmap up
    /// beyond its own pixels.
    static func pngData(from image: NSImage) -> Data? {
        let pointSide = max(image.size.width, image.size.height)
        guard pointSide > 0 else { return nil }
        let largestPixelSide = image.representations.map { CGFloat(max($0.pixelsWide, $0.pixelsHigh)) }.max() ?? 0
        let targetSide = min(maxPixelSide, largestPixelSide > 0 ? largestPixelSide : pointSide)
        let width = max(1, Int((image.size.width * targetSide / pointSide).rounded()))
        let height = max(1, Int((image.size.height * targetSide / pointSide).rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy,
            fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// Two faces are equal when their PNG bytes are.
struct SlotImage: Equatable {
    let png: Data
    let image: NSImage

    init?(png: Data) {
        guard let image = NSImage(data: png) else { return nil }
        self.png = png
        self.image = image
    }

    init?(_ image: NSImage) {
        guard let png = SlotIcon.pngData(from: image) else { return nil }
        self.init(png: png)
    }

    static func == (lhs: SlotImage, rhs: SlotImage) -> Bool { lhs.png == rhs.png }
}
