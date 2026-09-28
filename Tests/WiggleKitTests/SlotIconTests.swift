import AppKit
import Testing

@testable import WiggleKit

/// A 32 x 32 image whose left half is opaque `color` and right half is clear.
private func halfTransparentImage(_ color: NSColor) -> NSImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    // `setColor(_:atX:y:)` leaves a fresh bitmap untouched, so fill it through a context.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color.setFill()
    NSRect(x: 0, y: 0, width: 16, height: 32).fill()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: 32, height: 32))
    image.addRepresentation(rep)
    return image
}

/// The colour at a pixel of the PNG file, or `nil` when there is no file.
private func pixel(_ url: URL, x: Int, y: Int) -> NSColor? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return NSBitmapImageRep(data: data)?.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

private func configText(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

private let copy = SlotAction.shortcut(Shortcut(keyCode: 8, flags: [.maskCommand]))

private func imageFace(_ color: NSColor) throws -> SlotAssignment {
    .action(copy, face: .image(try #require(SlotImage(halfTransparentImage(color)))))
}

@Test func anImageFaceIsStoredAsATransparentPNGAndSurvivesAReopen() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    let assignment = try imageFace(.red)
    store.assign(Slot(assignment), to: .inner(3))
    store.waitForWrites()

    let file = url.deletingLastPathComponent().appendingPathComponent("icons/slot-3.png")
    let opaque = try #require(pixel(file, x: 4, y: 4))
    let clear = try #require(pixel(file, x: 28, y: 4))
    #expect(opaque.alphaComponent == 1)
    #expect(opaque.redComponent == 1)
    #expect(clear.alphaComponent == 0)
    #expect(SlotStore(url: url)[.inner(3)] == assignment)
    #expect(configText(url).contains(#""kind" : "shortcut""#))
    #expect(!configText(url).contains("label"))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func replacingAnEmojiWithAnImageRemovesTheLabel() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.assign(Slot(.action(copy, face: .emoji("📋"))), to: .center)
    store.waitForWrites()
    #expect(configText(url).contains(#""label" : "📋""#))

    let image = try imageFace(.red)
    store.assign(Slot(image), to: .center)
    store.waitForWrites()
    #expect(!configText(url).contains("label"))
    #expect(SlotStore(url: url)[.center] == image)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func replacingAnImageWithAnEmojiDeletesThePNG() throws {
    let url = temporaryConfigURL()
    let file = url.deletingLastPathComponent().appendingPathComponent("icons/center.png")
    let store = SlotStore(url: url)
    store.assign(Slot(try imageFace(.red)), to: .center)
    store.waitForWrites()
    #expect(exists(file))

    store.assign(Slot(.action(copy, face: .emoji("📋"))), to: .center)
    store.waitForWrites()
    #expect(!exists(file))
    #expect(SlotStore(url: url)[.center] == .action(copy, face: .emoji("📋")))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func movingSlotsMovesTheirPNGs() throws {
    let url = temporaryConfigURL()
    let icons = url.deletingLastPathComponent().appendingPathComponent("icons")
    let store = SlotStore(url: url)
    let red = try imageFace(.red)
    let blue = try imageFace(.blue)
    store.assign(Slot(red), to: .inner(3))
    store.assign(Slot(blue), to: .center)

    store.swap(.inner(3), with: .outer(2))
    store.waitForWrites()
    #expect(try #require(pixel(icons.appendingPathComponent("slot-b.png"), x: 4, y: 4)).redComponent == 1)
    #expect(!exists(icons.appendingPathComponent("slot-3.png")))

    store.swap(.outer(2), with: .center)
    store.waitForWrites()
    #expect(try #require(pixel(icons.appendingPathComponent("center.png"), x: 4, y: 4)).redComponent == 1)
    #expect(try #require(pixel(icons.appendingPathComponent("slot-b.png"), x: 4, y: 4)).blueComponent == 1)
    let reopened = SlotStore(url: url)
    #expect(reopened[.center] == red)
    #expect(reopened[.outer(2)] == blue)
    #expect(reopened[.inner(3)] == nil)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func clearingASlotDeletesItsPNG() throws {
    let url = temporaryConfigURL()
    let file = url.deletingLastPathComponent().appendingPathComponent("icons/center.png")
    let store = SlotStore(url: url)
    store.assign(Slot(try imageFace(.red)), to: .center)
    store.waitForWrites()
    #expect(exists(file))

    store.assign(nil, to: .center)
    store.waitForWrites()
    #expect(!exists(file))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func anAppSlotIgnoresALeftoverPNGAndTheNextSaveDeletesIt() throws {
    let url = temporaryConfigURL()
    let icons = url.deletingLastPathComponent().appendingPathComponent("icons")
    try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
    try Data(
        #"{"version":4,"rings":[{},{"3":{"kind":"app","app":{"bundleIdentifier":"com.apple.Safari","name":"Safari"}}},{}]}"#
            .utf8
    ).write(to: url)
    let leftover = icons.appendingPathComponent("slot-3.png")
    try #require(SlotIcon.pngData(from: halfTransparentImage(.red))).write(to: leftover)

    let store = SlotStore(url: url)
    #expect(store[.inner(3)] == .app(AppRef(bundleIdentifier: "com.apple.Safari", name: "Safari")))
    store.setTriggers([.wiggle, .screenEdge])
    store.waitForWrites()
    #expect(!exists(leftover))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aLargeImageIsScaledDownKeepingItsAspectRatio() throws {
    let image = NSImage(size: NSSize(width: 1000, height: 500), flipped: false) { rect in
        NSColor.green.setFill()
        rect.fill()
        return true
    }
    let data = try #require(SlotIcon.pngData(from: image))
    let rep = try #require(NSBitmapImageRep(data: data))
    #expect(rep.pixelsWide == 256)
    #expect(rep.pixelsHigh == 128)
}
