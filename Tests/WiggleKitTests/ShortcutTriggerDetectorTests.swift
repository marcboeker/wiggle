import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

private let hyper: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
private let k = UInt16(kVK_ANSI_K)

/// Presses the modifiers one after another, then releases them in the same
/// order, `step` apart. Returns what the last release reports.
private func pressAndRelease(
    _ modifiers: [CGEventFlags], step: TimeInterval = 0.05, detector: ShortcutTriggerDetector
) -> CGPoint? {
    var now: TimeInterval = 1000
    var held: CGEventFlags = []
    for modifier in modifiers {
        held.insert(modifier)
        #expect(detector.flagsChanged(held, pointer: pointer, at: now) == nil)
        now += step
    }
    for modifier in modifiers.dropLast() {
        held.remove(modifier)
        #expect(detector.flagsChanged(held, pointer: pointer, at: now) == nil)
        now += step
    }
    return detector.flagsChanged([], pointer: pointer, at: now)
}

private func hyperDetector() -> ShortcutTriggerDetector { ShortcutTriggerDetector(shortcut: .hyper) }

@Test func aHyperTapTriggersAtThePointer() {
    #expect(
        pressAndRelease([.maskCommand, .maskControl, .maskAlternate, .maskShift], detector: hyperDetector())
            == pointer)
}

@Test func aHyperTapTriggersWhenTheModifiersComeAtOnce() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == nil)
    #expect(detector.flagsChanged([], pointer: pointer, at: 1000.1) == pointer)
}

@Test func aHyperTapIgnoresFlagsOutsideTheModifiers() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper.union([.maskAlphaShift, .maskNonCoalesced]), pointer: pointer, at: 1000) == nil)
    #expect(detector.flagsChanged(.maskNonCoalesced, pointer: pointer, at: 1000.1) == pointer)
}

@Test func onlySomeOfTheChordDoesNotTrigger() {
    #expect(pressAndRelease([.maskCommand, .maskControl, .maskAlternate], detector: hyperDetector()) == nil)
}

@Test func anExtraModifierDoesNotTrigger() {
    let detector = ShortcutTriggerDetector(shortcut: TriggerShortcut(keyCode: nil, flags: [.maskCommand, .maskShift])!)
    #expect(pressAndRelease([.maskCommand, .maskShift, .maskControl], detector: detector) == nil)
}

@Test func aKeyDuringTheChordDoesNotTrigger() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == nil)
    #expect(detector.keyDown(k, flags: hyper, pointer: pointer) == nil)
    #expect(detector.flagsChanged([], pointer: pointer, at: 1000.2) == nil)
}

@Test func aClickDuringTheChordDoesNotTrigger() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == nil)
    detector.reset()
    #expect(detector.flagsChanged([], pointer: pointer, at: 1000.1) == nil)
}

@Test func aLongHoldDoesNotTrigger() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == nil)
    #expect(detector.flagsChanged([], pointer: pointer, at: 1000 + Config.chordMaxHold + 0.1) == nil)
}

@Test func theChordAfterASpoiledOneTriggers() {
    let detector = hyperDetector()
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1000) == nil)
    #expect(detector.keyDown(k, flags: hyper, pointer: pointer) == nil)
    #expect(detector.flagsChanged([], pointer: pointer, at: 1000.2) == nil)
    #expect(detector.flagsChanged(hyper, pointer: pointer, at: 1001) == nil)
    #expect(detector.flagsChanged([], pointer: pointer, at: 1001.1) == pointer)
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
    #expect(pressAndRelease([.maskCommand, .maskControl, .maskAlternate, .maskShift], detector: detector) == nil)
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
