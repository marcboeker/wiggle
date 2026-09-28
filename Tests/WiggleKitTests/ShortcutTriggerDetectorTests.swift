import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

private let hyper: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
private let k = UInt16(kVK_ANSI_K)

private func hyperDetector() -> ShortcutTriggerDetector { ShortcutTriggerDetector(shortcut: .hyper) }

@Test func aHyperChordShowsTheWheelOnceAllModifiersAreHeld() {
    let detector = hyperDetector()
    var held: CGEventFlags = []
    for modifier: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate] {
        held.insert(modifier)
        #expect(detector.flagsChanged(held, pointer: pointer, at: 1000) == nil)
    }
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == pointer)
    #expect(detector.isHeld)
}

@Test func aHyperChordIgnoresFlagsOutsideTheModifiers() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper.union([.maskAlphaShift, .maskNonCoalesced]), pointer: pointer, at: 1000) == pointer)
}

@Test func anExtraModifierDoesNotShowTheWheel() {
    let detector = ShortcutTriggerDetector(shortcut: TriggerShortcut(keyCode: nil, flags: [.maskCommand, .maskShift])!)
    #expect(detector.flagsChanged([.maskCommand, .maskShift, .maskControl], pointer: pointer, at: 1000) == nil)
    #expect(!detector.isHeld)
}

@Test func releasingAModifierOfTheChordEndsTheHold() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == pointer)
    #expect(!detector.modifiersChanged(hyper))
    #expect(detector.modifiersChanged([.maskCommand, .maskControl, .maskAlternate]))
    #expect(!detector.isHeld)
    #expect(!detector.modifiersChanged([]))
}

@Test func aResetEndsTheHold() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == pointer)
    detector.reset()
    #expect(!detector.modifiersChanged([]))
}

@Test func aKeyCombinationTriggersOnItsKey() {
    let detector = ShortcutTriggerDetector(shortcut: TriggerShortcut(keyCode: k, flags: hyper)!)
    #expect(detector.keyDown(k, flags: hyper.union(.maskNonCoalesced), pointer: pointer) == pointer)
}

@Test func aKeyCombinationNeedsItsExactModifiers() {
    let detector = ShortcutTriggerDetector(shortcut: TriggerShortcut(keyCode: k, flags: [.maskCommand, .maskAlternate])!)
    #expect(detector.keyDown(k, flags: .maskCommand, pointer: pointer) == nil)
    #expect(detector.keyDown(k, flags: [.maskCommand, .maskAlternate, .maskShift], pointer: pointer) == nil)
    #expect(detector.keyDown(UInt16(kVK_ANSI_J), flags: [.maskCommand, .maskAlternate], pointer: pointer) == nil)
}

@Test func aKeyCombinationIgnoresItsModifiersAlone() {
    let detector = ShortcutTriggerDetector(shortcut: TriggerShortcut(keyCode: k, flags: hyper)!)
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == nil)
    #expect(!detector.isHeld)
}

@Test func releasingTheKeyEndsTheHold() {
    let detector = ShortcutTriggerDetector(shortcut: TriggerShortcut(keyCode: k, flags: hyper)!)
    #expect(!detector.keyUp(k))
    #expect(detector.keyDown(k, flags: hyper, pointer: pointer) == pointer)
    #expect(!detector.keyUp(UInt16(kVK_ANSI_J)))
    #expect(detector.keyUp(k))
    #expect(!detector.keyUp(k))
}

@Test func releasingTheModifiersEndsAKeyHold() {
    let detector = ShortcutTriggerDetector(shortcut: TriggerShortcut(keyCode: k, flags: hyper)!)
    #expect(detector.keyDown(k, flags: hyper, pointer: pointer) == pointer)
    #expect(detector.modifiersChanged(.maskCommand))
}

@Test func aTriggerShortcutMustNotTakeTyping() {
    #expect(TriggerShortcut(keyCode: k, flags: []) == nil)
    #expect(TriggerShortcut(keyCode: k, flags: .maskShift) == nil)
    #expect(TriggerShortcut(keyCode: nil, flags: []) == nil)
    #expect(TriggerShortcut(keyCode: UInt16(kVK_F13), flags: []) != nil)
    #expect(TriggerShortcut(keyCode: k, flags: .maskControl) != nil)
    #expect(TriggerShortcut(keyCode: nil, flags: .maskShift) != nil)
}

@Test func theTriggerShortcutSpellsLikeASlotShortcut() {
    #expect(TriggerShortcut.hyper.shortcutString == "cmd+ctrl+alt+shift")
    #expect(TriggerShortcut(shortcutString: "shift+alt+ctrl+cmd") == .hyper)
    #expect(TriggerShortcut(shortcutString: "cmd+alt+k") == TriggerShortcut(keyCode: k, flags: [.maskCommand, .maskAlternate]))
    #expect(TriggerShortcut(shortcutString: "k") == nil)
    #expect(TriggerShortcut(shortcutString: "cmd+nonsense") == nil)
}

@Test func theRecorderRecordsAHyperTap() {
    var recording = TriggerShortcutRecording()
    #expect(recording.flagsChanged(.maskCommand) == nil)
    #expect(recording.flagsChanged([.maskCommand, .maskControl, .maskAlternate]) == nil)
    #expect(recording.flagsChanged(hyper) == nil)
    #expect(recording.held == hyper)
    #expect(recording.flagsChanged(.maskShift) == nil)
    #expect(recording.flagsChanged([]) == .hyper)
}

@Test func theRecorderRecordsAKeyCombination() {
    var recording = TriggerShortcutRecording()
    #expect(recording.flagsChanged([.maskCommand, .maskAlternate]) == nil)
    #expect(recording.keyDown(k, flags: [.maskCommand, .maskAlternate]) == TriggerShortcut(keyCode: k, flags: [.maskCommand, .maskAlternate]))
}

@Test func theRecorderRefusesTypingAndItsModifiers() {
    var recording = TriggerShortcutRecording()
    #expect(recording.flagsChanged(.maskShift) == nil)
    #expect(recording.keyDown(k, flags: .maskShift) == nil)
    #expect(recording.flagsChanged([]) == nil)
}
