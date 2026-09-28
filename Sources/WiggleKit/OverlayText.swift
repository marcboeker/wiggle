import AppKit

/// Text and icon drawing for the wheel.
enum OverlayText {

    static func draw(
        _ string: String, in rect: NSRect, size: CGFloat, alpha: CGFloat, weight: NSFont.Weight, color: NSColor
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color.withAlphaComponent(alpha),
        ]
        let text = NSAttributedString(string: string, attributes: attributes)
        let textSize = text.size()
        text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }

    /// An image face is scaled to the same square as an app icon.
    static func drawIcon(_ image: NSImage, in rect: NSRect) {
        let box = min(rect.width, rect.height) * 0.6
        let scale = box / max(image.size.width, image.size.height, 1)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(
            in: NSRect(center: NSPoint(x: rect.midX, y: rect.midY), size: size), from: .zero,
            operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    /// An app's icon, the previous app's icon or a symbol without one, a
    /// face, `❓` for a face-less slot from an old config, or the empty `+`.
    @MainActor
    static func drawSlotContent(
        _ assignment: SlotAssignment?, previousAppIcon: NSImage?, in rect: NSRect, iconRect: NSRect, color: NSColor
    ) {
        switch assignment {
        case .app(let ref):
            drawIcon(ref.icon, in: iconRect)
        case .previousApp:
            if let icon = previousAppIcon ?? previousAppSymbol(color: color) { drawIcon(icon, in: iconRect) }
        case .action(_, face: .emoji(let emoji)):
            draw(emoji, in: rect, size: 20, alpha: 1, weight: .semibold, color: color)
        case .action(_, face: .image(let image)):
            drawIcon(image.image, in: iconRect)
        case .action(_, face: nil):
            draw("❓", in: rect, size: 20, alpha: 1, weight: .semibold, color: color)
        case nil:
            draw("+", in: rect, size: 22, alpha: 0.3, weight: .light, color: color)
        }
    }

    /// One image per color: the overlay draws it again on every hover change.
    @MainActor private static var previousAppSymbols: [NSColor: NSImage] = [:]

    @MainActor
    static func previousAppSymbol(color: NSColor) -> NSImage? {
        if let symbol = previousAppSymbols[color] { return symbol }
        let configuration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let symbol = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Previous App")?
            .withSymbolConfiguration(configuration)
        previousAppSymbols[color] = symbol
        return symbol
    }

    static func drawHint(_ text: String, at point: NSPoint, color: NSColor) {
        draw(text, in: NSRect(origin: point, size: .zero), size: 9, alpha: 0.3, weight: .medium, color: color)
    }
}
