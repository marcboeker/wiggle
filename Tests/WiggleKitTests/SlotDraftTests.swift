import AppKit
import Carbon.HIToolbox
import Testing

@testable import WiggleKit

private let rocketKey = Shortcut(keyCode: UInt16(kVK_ANSI_R), flags: [.maskCommand, .maskShift])
private let safari = AppRef(bundleIdentifier: "com.apple.Safari", name: "Safari")

private func redImage() throws -> SlotImage {
    let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
        NSColor.red.setFill()
        rect.fill()
        return true
    }
    return try #require(SlotImage(image))
}

@Test func anEmptySlotOpensOnTheAppTabWithNothingToSave() {
    let draft = SlotDraft(nil)
    #expect(draft.tab == .app)
    #expect(draft.assignment == nil)
}

@Test func aRecordedShortcutWithoutAFaceCannotBeSaved() {
    var draft = SlotDraft(nil)
    draft.tab = .keyboardShortcut
    draft.shortcut = rocketKey
    #expect(draft.assignment == nil)
}

@Test func aRecordedShortcutWithAnEmojiSavesBoth() {
    var draft = SlotDraft(nil)
    draft.tab = .keyboardShortcut
    draft.shortcut = rocketKey
    draft.emoji = "🚀"
    #expect(draft.assignment == .action(.shortcut(rocketKey), face: .emoji("🚀")))
}

@Test func switchingTabsKeepsTheRecordedShortcut() {
    var draft = SlotDraft(nil)
    draft.tab = .keyboardShortcut
    draft.shortcut = rocketKey
    draft.emoji = "🚀"
    draft.tab = .appleScript
    #expect(draft.assignment == nil)
    draft.tab = .keyboardShortcut
    #expect(draft.assignment == .action(.shortcut(rocketKey), face: .emoji("🚀")))
}

@Test func theAppTabIgnoresTheEmoji() {
    var draft = SlotDraft(nil)
    draft.emoji = "🚀"
    #expect(draft.assignment == nil)
    draft.app = safari
    #expect(draft.assignment == .app(safari))
}

@Test func aBlankScriptCannotBeSaved() {
    var draft = SlotDraft(nil)
    draft.tab = .appleScript
    draft.emoji = "📜"
    draft.script = " \n\t"
    #expect(draft.assignment == nil)
    draft.script = "beep"
    #expect(draft.assignment == .action(.appleScript("beep"), face: .emoji("📜")))
}

@Test func anAppleShortcutNeedsAChosenRow() {
    var draft = SlotDraft(nil)
    draft.tab = .appleShortcut
    draft.emoji = "🎯"
    #expect(draft.assignment == nil)
    draft.appleShortcut = AppleShortcutRef(name: "Focus")
    #expect(draft.assignment == .action(.appleShortcut(AppleShortcutRef(name: "Focus")), face: .emoji("🎯")))
}

@Test func onlyTheSelectedFaceKindIsSaved() throws {
    let image = try redImage()
    var draft = SlotDraft(nil)
    draft.tab = .keyboardShortcut
    draft.shortcut = rocketKey
    draft.emoji = "🚀"
    draft.image = image
    draft.faceKind = .image
    #expect(draft.assignment == .action(.shortcut(rocketKey), face: .image(image)))
    draft.faceKind = .emoji
    #expect(draft.assignment == .action(.shortcut(rocketKey), face: .emoji("🚀")))
}

@Test func anImageFaceKindWithNoImageCannotBeSaved() {
    var draft = SlotDraft(nil)
    draft.tab = .keyboardShortcut
    draft.shortcut = rocketKey
    draft.emoji = "🚀"
    draft.faceKind = .image
    #expect(draft.assignment == nil)
}

@Test func anOccupiedSlotOpensOnItsTabWithItsFace() throws {
    let image = try redImage()
    let script = SlotDraft(.action(.appleScript("beep"), face: .image(image)))
    #expect(script.tab == .appleScript)
    #expect(script.faceKind == .image)
    #expect(script.assignment == .action(.appleScript("beep"), face: .image(image)))

    let shortcut = SlotDraft(.action(.shortcut(rocketKey), face: .emoji("🚀")))
    #expect(shortcut.tab == .keyboardShortcut)
    #expect(shortcut.faceKind == .emoji)
    #expect(shortcut.assignment == .action(.shortcut(rocketKey), face: .emoji("🚀")))

    let app = SlotDraft(.app(safari))
    #expect(app.tab == .app)
    #expect(app.assignment == .app(safari))
}

@Test func aLegacySlotWithoutAFaceOpensUnsaveable() {
    let draft = SlotDraft(.action(.appleShortcut(AppleShortcutRef(name: "Focus")), face: nil))
    #expect(draft.tab == .appleShortcut)
    #expect(draft.assignment == nil)
}

@Test func thePreviousAppTabSavesWithoutAFace() {
    var draft = SlotDraft(nil)
    draft.tab = .previousApp
    #expect(draft.assignment == .previousApp)
    #expect(SlotDraft(.previousApp).tab == .previousApp)
}

@Test func theColorSurvivesChangingTheActionType() {
    var draft = SlotDraft(.action(.shortcut(rocketKey), face: .emoji("🚀")), color: .green)
    draft.tab = .appleScript
    draft.script = "beep"
    #expect(draft.slot == Slot(.action(.appleScript("beep"), face: .emoji("🚀")), color: .green))
    draft.tab = .previousApp
    #expect(draft.slot == Slot(.previousApp, color: .green))
}

@Test func aDraftWithoutAColorSavesWithoutOne() {
    var draft = SlotDraft(.app(safari), color: .red)
    draft.color = nil
    #expect(draft.slot == Slot(.app(safari)))
}
