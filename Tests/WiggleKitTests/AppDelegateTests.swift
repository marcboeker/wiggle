import AppKit
import Carbon.HIToolbox
import Testing

@testable import WiggleKit

private func key(_ keyCode: Int, down: Bool, isRepeat: Bool = false) throws -> CGEvent {
    let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down))
    if isRepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    return event
}

private func middleButton(_ type: CGEventType, at point: CGPoint) throws -> CGEvent {
    try #require(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .center))
}

/// A press the wheel takes must take its repeats and its release with it,
/// or the app below sees a release without a press.
@Test @MainActor func theWheelSwallowsEachPressItTakesWithItsRepeatsAndRelease() throws {
    let screen = try #require(NSScreen.main)
    let store = SlotStore(url: temporaryConfigURL())
    store.setTriggers([.middleMouseButton])
    let app = AppDelegate(store: store)
    app.rebuildDetectors()
    // The centre of the main screen, so that the wheel needs no warp.
    let centre = Coords.cgPoint(from: NSPoint(x: screen.frame.midX, y: screen.frame.midY))

    #expect(app.handle(type: .otherMouseDown, event: try middleButton(.otherMouseDown, at: centre)) == nil)
    #expect(app.handle(type: .otherMouseUp, event: try middleButton(.otherMouseUp, at: centre)) == nil)

    #expect(app.handle(type: .keyDown, event: try key(kVK_ANSI_1, down: true)) == nil)
    #expect(app.handle(type: .keyDown, event: try key(kVK_ANSI_1, down: true, isRepeat: true)) == nil)
    #expect(app.handle(type: .keyUp, event: try key(kVK_ANSI_1, down: false)) == nil)

    // Escape closes the wheel and its release goes with it. After that,
    // keys reach the app below again.
    #expect(app.handle(type: .keyDown, event: try key(kVK_Escape, down: true)) == nil)
    #expect(app.handle(type: .keyUp, event: try key(kVK_Escape, down: false)) == nil)
    #expect(app.handle(type: .keyDown, event: try key(kVK_ANSI_1, down: true)) != nil)
    #expect(app.handle(type: .keyUp, event: try key(kVK_ANSI_1, down: false)) != nil)
}

/// The trigger shortcut opens the wheel, and the same press closes it. Its
/// release changes nothing, and the app below sees neither press nor release.
@Test @MainActor func theTriggerShortcutTogglesTheWheel() throws {
    let store = SlotStore(url: temporaryConfigURL())
    store.setTriggers([.shortcut])
    store.setTriggerShortcut(try #require(TriggerShortcut(keyCode: UInt16(kVK_F13), flags: [])))
    let app = AppDelegate(store: store)
    app.rebuildDetectors()

    #expect(app.handle(type: .keyDown, event: try key(kVK_F13, down: true)) == nil)
    #expect(app.handle(type: .keyUp, event: try key(kVK_F13, down: false)) == nil)
    // Still open: the key after the release is taken by the wheel.
    #expect(app.handle(type: .keyDown, event: try key(kVK_ANSI_1, down: true)) == nil)
    #expect(app.handle(type: .keyUp, event: try key(kVK_ANSI_1, down: false)) == nil)

    #expect(app.handle(type: .keyDown, event: try key(kVK_F13, down: true)) == nil)
    #expect(app.handle(type: .keyUp, event: try key(kVK_F13, down: false)) == nil)
    // Closed: keys reach the app below again.
    #expect(app.handle(type: .keyDown, event: try key(kVK_ANSI_1, down: true)) != nil)
    #expect(app.handle(type: .keyUp, event: try key(kVK_ANSI_1, down: false)) != nil)
}
