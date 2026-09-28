import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

@Test func aShortcutAssignmentSurvivesEncoding() throws {
    let assignment = SlotAssignment.action(
        .shortcut(Shortcut(keyCode: UInt16(kVK_ANSI_4), flags: [.maskCommand, .maskShift])), face: .emoji("📸"))
    let data = try JSONEncoder().encode(assignment)
    #expect(try JSONDecoder().decode(SlotAssignment.self, from: data) == assignment)
}

@Test func anAppAssignmentSurvivesEncoding() throws {
    let assignment = SlotAssignment.app(AppRef(bundleIdentifier: "com.apple.Safari", name: "Safari"))
    let data = try JSONEncoder().encode(assignment)
    #expect(try JSONDecoder().decode(SlotAssignment.self, from: data) == assignment)
}

@Test func anAppleScriptAssignmentSurvivesEncoding() throws {
    let assignment = SlotAssignment.action(.appleScript("display notification \"hi\""), face: .emoji("📜"))
    let data = try JSONEncoder().encode(assignment)
    #expect(try JSONDecoder().decode(SlotAssignment.self, from: data) == assignment)
}

@Test func anAppleShortcutAssignmentSurvivesEncoding() throws {
    let assignment = SlotAssignment.action(.appleShortcut(AppleShortcutRef(name: "Focus")), face: .emoji("🎯"))
    let data = try JSONEncoder().encode(assignment)
    #expect(try JSONDecoder().decode(SlotAssignment.self, from: data) == assignment)
}

@Test func onlyAnEmojiFaceWritesTheLabelKey() throws {
    let shortcut = SlotAction.shortcut(Shortcut(keyCode: UInt16(kVK_ANSI_A), flags: [.maskCommand]))
    let withEmoji = String(decoding: try JSONEncoder().encode(SlotAssignment.action(shortcut, face: .emoji("🅰️"))), as: UTF8.self)
    let withoutFace = String(decoding: try JSONEncoder().encode(SlotAssignment.action(shortcut, face: nil)), as: UTF8.self)
    #expect(withEmoji.contains(#""label":"🅰️""#))
    #expect(!withoutFace.contains("label"))
}
