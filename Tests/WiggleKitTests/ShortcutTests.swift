import Carbon.HIToolbox
import CoreGraphics
import KeyboardShortcuts
import Foundation
import Testing

@testable import WiggleKit

@Test func modifiersAreReducedToTheAllowedSet() {
    let shortcut = Shortcut(
        keyCode: UInt16(kVK_ANSI_A),
        flags: [.maskCommand, .maskSecondaryFn, .maskNonCoalesced])
    #expect(shortcut.flags == .maskCommand)
}

@Test func shortcutSurvivesEncoding() throws {
    let shortcut = Shortcut(keyCode: 42, flags: [.maskControl, .maskAlternate])
    let data = try JSONEncoder().encode(shortcut)
    #expect(try JSONDecoder().decode(Shortcut.self, from: data) == shortcut)
}

@Test @MainActor func aRecordedShortcutKeepsEveryModifier() {
    let recorded = KeyboardShortcuts.Shortcut(.four, modifiers: [.command, .control, .shift])
    let shortcut = Shortcut(recorded)
    #expect(shortcut.keyCode == UInt16(kVK_ANSI_4))
    #expect(shortcut.flags == [.maskCommand, .maskControl, .maskShift])
}

@Test func aStoredShortcutSurvivesTheRoundTrip() {
    let shortcut = Shortcut(
        keyCode: UInt16(kVK_ANSI_K), flags: [.maskCommand, .maskShift, .maskControl, .maskAlternate])
    #expect(Shortcut(shortcut.libraryShortcut) == shortcut)
}

@Test func theConfigStringIsHumanReadable() {
    let shortcut = Shortcut(
        keyCode: UInt16(kVK_ANSI_4), flags: [.maskCommand, .maskControl, .maskShift])
    #expect(shortcut.shortcutString == "cmd+ctrl+shift+4")
}

@Test func theConfigStringParsesBackRegardlessOfModifierOrder() {
    #expect(Shortcut(shortcutString: "cmd+ctrl+shift+4") == Shortcut(shortcutString: "shift+4+ctrl+cmd"))
    #expect(
        Shortcut(shortcutString: "cmd+ctrl+shift+4")
            == Shortcut(keyCode: UInt16(kVK_ANSI_4), flags: [.maskCommand, .maskControl, .maskShift]))
}

@Test func theConfigStringAcceptsLongModifierNames() {
    #expect(
        Shortcut(shortcutString: "command+control+option+a")
            == Shortcut(
                keyCode: UInt16(kVK_ANSI_A), flags: [.maskCommand, .maskControl, .maskAlternate]))
}

@Test func aMalformedConfigStringFailsToParse() {
    #expect(Shortcut(shortcutString: "") == nil)
    #expect(Shortcut(shortcutString: "cmd+ctrl") == nil)
    #expect(Shortcut(shortcutString: "cmd+4+a") == nil)
    #expect(Shortcut(shortcutString: "cmd+nonsense") == nil)
}

@Test func theConfigJSONIsAPlainString() throws {
    let shortcut = Shortcut(keyCode: UInt16(kVK_ANSI_4), flags: [.maskCommand, .maskShift])
    let data = try JSONEncoder().encode(shortcut)
    #expect(String(data: data, encoding: .utf8) == "\"cmd+shift+4\"")
}

@Test func theOldObjectFormatStillDecodes() throws {
    let json = Data(#"{"keyCode":8,"modifiers":1048576}"#.utf8)
    let shortcut = try JSONDecoder().decode(Shortcut.self, from: json)
    #expect(shortcut == Shortcut(keyCode: 8, flags: .maskCommand))
}

@Test func theOldObjectFormatDropsModifiersThatCannotBePosted() throws {
    // Command plus the non-coalesced and numeric pad bits.
    let json = Data(#"{"keyCode":8,"modifiers":3145984}"#.utf8)
    let shortcut = try JSONDecoder().decode(Shortcut.self, from: json)
    #expect(shortcut.flags == .maskCommand)
}
