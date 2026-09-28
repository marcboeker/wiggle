import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import WiggleKit

@Test func aFreshStoreHasNoAssignments() {
    let store = SlotStore(url: temporaryConfigURL())
    #expect(store.slots.isEmpty)
    for id in SlotID.all { #expect(store[id] == nil) }
}

@Test func assignmentsReachTheNextStore() {
    let url = temporaryConfigURL()
    let shortcut = SlotAssignment.action(
        .shortcut(Shortcut(keyCode: UInt16(kVK_ANSI_C), flags: [.maskCommand])), face: nil)
    let store = SlotStore(url: url)
    store.assign(Slot(shortcut), to: .inner(4))
    store.waitForWrites()

    let reopened = SlotStore(url: url)
    #expect(reopened[.inner(4)] == shortcut)
    #expect(reopened[.inner(1)] == nil)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func anEmojiSurvivesAReopen() {
    let url = temporaryConfigURL()
    let shortcut = SlotAssignment.action(
        .shortcut(Shortcut(keyCode: UInt16(kVK_ANSI_4), flags: [.maskCommand, .maskShift])), face: .emoji("📸"))
    let store = SlotStore(url: url)
    store.assign(Slot(shortcut), to: .inner(2))
    store.waitForWrites()

    #expect(SlotStore(url: url)[.inner(2)] == shortcut)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func anAppAssignmentSurvivesAReopen() {
    let url = temporaryConfigURL()
    let app = SlotAssignment.app(AppRef(bundleIdentifier: "com.apple.Safari", name: "Safari"))
    let store = SlotStore(url: url)
    store.assign(Slot(app), to: .outer(6))
    store.waitForWrites()

    #expect(SlotStore(url: url)[.outer(6)] == app)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aCentreAssignmentSurvivesAReopen() {
    let url = temporaryConfigURL()
    let shortcut = SlotAssignment.action(.shortcut(Shortcut(keyCode: 36, flags: [])), face: nil)
    let store = SlotStore(url: url)
    store.assign(Slot(shortcut), to: .center)
    store.waitForWrites()

    #expect(SlotStore(url: url)[.center] == shortcut)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func clearingASlotIsPersisted() {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.assign(Slot(.action(.shortcut(Shortcut(keyCode: 8, flags: [.maskCommand])), face: nil)), to: .outer(8))
    store.assign(nil, to: .outer(8))
    store.waitForWrites()
    #expect(SlotStore(url: url)[.outer(8)] == nil)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func movingOntoAnEmptySlotEmptiesTheSource() {
    let url = temporaryConfigURL()
    let app = SlotAssignment.app(AppRef(bundleIdentifier: "com.apple.Safari", name: "Safari"))
    let store = SlotStore(url: url)
    store.assign(Slot(app), to: .inner(3))
    store.swap(.inner(3), with: .outer(5))
    store.waitForWrites()

    let reopened = SlotStore(url: url)
    #expect(reopened[.outer(5)] == app)
    #expect(reopened[.inner(3)] == nil)
    #expect(reopened.slots.count == 1)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func movingOntoAnOccupiedSlotSwapsThem() {
    let url = temporaryConfigURL()
    let app = SlotAssignment.app(AppRef(bundleIdentifier: "com.apple.Safari", name: "Safari"))
    let shortcut = SlotAssignment.action(.shortcut(Shortcut(keyCode: 8, flags: [.maskCommand])), face: .emoji("✂️"))
    let store = SlotStore(url: url)
    store.assign(Slot(app), to: .center)
    store.assign(Slot(shortcut), to: .inner(1))
    store.swap(.center, with: .inner(1))
    store.waitForWrites()

    let reopened = SlotStore(url: url)
    #expect(reopened[.center] == shortcut)
    #expect(reopened[.inner(1)] == app)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func onlyAnOuterAssignmentTurnsOnHasOuterRingAssignment() {
    let store = SlotStore(url: temporaryConfigURL())
    #expect(!store.hasOuterRingAssignment)
    store.assign(Slot(.action(.shortcut(Shortcut(keyCode: 8, flags: [])), face: nil)), to: .inner(1))
    #expect(!store.hasOuterRingAssignment)
    store.assign(Slot(.action(.shortcut(Shortcut(keyCode: 8, flags: [])), face: nil)), to: .outer(1))
    #expect(store.hasOuterRingAssignment)
    store.assign(nil, to: .outer(1))
    #expect(!store.hasOuterRingAssignment)
}

@Test func aSaveWritesTheV4RingsShape() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.assign(Slot(.action(.shortcut(Shortcut(keyCode: 8, flags: [.maskCommand])), face: nil)), to: .center)
    store.assign(Slot(.action(.shortcut(Shortcut(keyCode: 1, flags: [])), face: nil)), to: .inner(1))
    store.assign(Slot(.action(.shortcut(Shortcut(keyCode: 2, flags: [])), face: nil)), to: .outer(16))
    store.waitForWrites()

    let data = try Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["version"] as? Int == 4)
    let rings = json?["rings"] as? [[String: Any]]
    #expect(rings?.count == 3)
    #expect(rings?[0]["0"] != nil)
    #expect(rings?[1]["1"] != nil)
    #expect(rings?[2]["16"] != nil)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func outOfRangeSlotNumbersAreDroppedOnLoad() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(
        #"""
        {"version":4,"rings":[
            {"0":{"kind":"shortcut","shortcut":{"keyCode":1,"modifiers":0}},"1":{"kind":"shortcut","shortcut":{"keyCode":2,"modifiers":0}}},
            {"1":{"kind":"shortcut","shortcut":{"keyCode":3,"modifiers":0}},"9":{"kind":"shortcut","shortcut":{"keyCode":4,"modifiers":0}}},
            {"16":{"kind":"shortcut","shortcut":{"keyCode":5,"modifiers":0}},"17":{"kind":"shortcut","shortcut":{"keyCode":6,"modifiers":0}},"0":{"kind":"shortcut","shortcut":{"keyCode":7,"modifiers":0}}}
        ]}
        """#.utf8
    ).write(to: url)

    let store = SlotStore(url: url)
    #expect(store[.center] == .action(.shortcut(Shortcut(keyCode: 1, flags: [])), face: nil))
    #expect(store[.inner(1)] == .action(.shortcut(Shortcut(keyCode: 3, flags: [])), face: nil))
    #expect(store[.outer(16)] == .action(.shortcut(Shortcut(keyCode: 5, flags: [])), face: nil))
    // The out-of-range keys (ring 0 slot 1, ring 1 slot 9, ring 2 slots 17
    // and 0) must not have landed anywhere.
    #expect(store.slots.count == 3)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aMissingRingLoadsAsEmptyAndAnExtraRingIsIgnored() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Only ring 0 is present; a fourth ring is extra.
    try Data(
        #"""
        {"version":4,"rings":[
            {"0":{"kind":"shortcut","shortcut":{"keyCode":1,"modifiers":0}}},
            {"9":{"kind":"shortcut","shortcut":{"keyCode":2,"modifiers":0}}}
        ]}
        """#.utf8
    ).write(to: url)
    let store = SlotStore(url: url)
    #expect(store[.center] == .action(.shortcut(Shortcut(keyCode: 1, flags: [])), face: nil))
    #expect(store.slots.count == 1)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aV3CentreSlotMigratesToRingZero() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(
        #"{"version":3,"slots":{"9":{"kind":"shortcut","shortcut":{"keyCode":1,"modifiers":0}}}}"#.utf8
    ).write(to: url)

    let store = SlotStore(url: url)
    #expect(store[.center] == .action(.shortcut(Shortcut(keyCode: 1, flags: [])), face: nil))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aV3RingSlotMigratesToRingOne() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(
        #"{"version":3,"slots":{"1":{"kind":"shortcut","shortcut":{"keyCode":1,"modifiers":0}}},"triggers":["screenEdge"]}"#
            .utf8
    ).write(to: url)

    let store = SlotStore(url: url)
    #expect(store[.inner(1)] == .action(.shortcut(Shortcut(keyCode: 1, flags: [])), face: nil))
    #expect(store.triggers == [.screenEdge])
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aLegacyBareShortcutFileIsMigratedToRingOne() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Under the pre-reorder layout, array index 1 sat at the top of the wheel.
    try Data(
        #"{"version":1,"slots":[null,{"keyCode":46,"modifiers":1966080},null]}"#.utf8
    ).write(to: url)

    let store = SlotStore(url: url)
    // Slot 1 (the top of the wheel) is still where the assignment lands.
    #expect(
        store[.inner(1)]
            == .action(.shortcut(Shortcut(keyCode: 46, flags: CGEventFlags(rawValue: 1_966_080))), face: nil))
    #expect(store[.inner(2)] == nil)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aLegacyArrayFileMigratesTheHubToTheCentre() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Old array index 4 was the hub (now the centre); old index 0 was the
    // upper-left slice (now ring 1 slot 8).
    try Data(
        #"""
        {"version":2,"slots":[
            {"kind":"shortcut","shortcut":{"keyCode":1,"modifiers":0}},
            null, null, null,
            {"kind":"shortcut","shortcut":{"keyCode":2,"modifiers":0}},
            null, null, null, null
        ]}
        """#.utf8
    ).write(to: url)

    let store = SlotStore(url: url)
    #expect(store[.inner(8)] == .action(.shortcut(Shortcut(keyCode: 1, flags: [])), face: nil))
    #expect(store[.center] == .action(.shortcut(Shortcut(keyCode: 2, flags: [])), face: nil))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func anUnreadableFileIsKeptAside() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("this is not json".utf8).write(to: url)

    let store = SlotStore(url: url)
    #expect(store.slots.isEmpty)
    // The file must survive, so that the user can still read it.
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("broken").path))
    #expect(!FileManager.default.fileExists(atPath: url.path))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aWriteReplacesAnEarlierOne() {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    for n in SlotID.innerNumbers {
        store.assign(Slot(.action(.shortcut(Shortcut(keyCode: UInt16(n), flags: [.maskCommand])), face: nil)), to: .inner(n))
    }
    store.waitForWrites()
    let reopened = SlotStore(url: url)
    for n in SlotID.innerNumbers {
        guard case .action(.shortcut(let shortcut), _) = reopened[.inner(n)] else {
            Issue.record("slot \(n) did not reload")
            continue
        }
        #expect(shortcut.keyCode == UInt16(n))
    }
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aFreshStoreEnablesOnlyTheWiggle() {
    #expect(SlotStore(url: temporaryConfigURL()).triggers == [.wiggle])
}

@Test func enabledTriggersReachTheNextStore() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.setTriggers([.wiggle, .screenEdge])
    store.waitForWrites()

    #expect(SlotStore(url: url).triggers == [.wiggle, .screenEdge])
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect(json?["triggers"] as? [String] == ["wiggle", "screenEdge"])
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func theLastTriggerCannotBeSwitchedOff() {
    let store = SlotStore(url: temporaryConfigURL())
    store.setTriggers([.screenEdge])
    store.setTriggers([])
    #expect(store.triggers == [.screenEdge])
}

@Test func unknownTriggersAreSkippedAndSlotsStillLoad() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(
        #"{"version":4,"rings":[{},{"2":{"kind":"shortcut","shortcut":{"keyCode":1,"modifiers":0}}},{}],"triggers":["hotCorner"]}"#
            .utf8
    ).write(to: url)

    let store = SlotStore(url: url)
    #expect(store.triggers == [.wiggle])
    #expect(store[.inner(2)] == .action(.shortcut(Shortcut(keyCode: 1, flags: [])), face: nil))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aFreshStoreUsesTheDefaultOpacity() {
    #expect(SlotStore(url: temporaryConfigURL()).overlayOpacity == 0.92)
}

@Test func theOverlayOpacityReachesTheNextStore() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.setOverlayOpacity(0.75)
    store.waitForWrites()

    #expect(SlotStore(url: url).overlayOpacity == 0.75)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func anOpacityOutsideTheRangeIsClamped() throws {
    let store = SlotStore(url: temporaryConfigURL())
    store.setOverlayOpacity(0.1)
    #expect(store.overlayOpacity == 0.5)
    store.setOverlayOpacity(3)
    #expect(store.overlayOpacity == 1)

    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version":4,"rings":[{},{},{}],"overlayOpacity":0}"#.utf8).write(to: url)
    #expect(SlotStore(url: url).overlayOpacity == 0.5)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aFreshStoreShowsTheMenuBarItem() {
    #expect(SlotStore(url: temporaryConfigURL()).showsMenuBarItem)
}

@Test func showsMenuBarItemReachesTheNextStore() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.setShowsMenuBarItem(false)
    store.waitForWrites()

    #expect(!SlotStore(url: url).showsMenuBarItem)
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect(json?["showMenuBarItem"] as? Bool == false)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aFileWithoutTheMenuBarItemKeyLoadsAsShown() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version":4,"rings":[{},{},{}]}"#.utf8).write(to: url)

    #expect(SlotStore(url: url).showsMenuBarItem)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aNonAppSlotWithNoLabelAndNoPNGLoadsWithoutAFace() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(
        #"""
        {"version":4,"rings":[
            {"0":{"kind":"appleScript","script":"beep"}},
            {"1":{"kind":"appleShortcut","appleShortcut":{"name":"Focus"}},"2":{"kind":"appleScript","script":"beep","label":"🔔"}},
            {}
        ]}
        """#.utf8
    ).write(to: url)

    let store = SlotStore(url: url)
    #expect(store[.center] == .action(.appleScript("beep"), face: nil))
    #expect(store[.inner(1)] == .action(.appleShortcut(AppleShortcutRef(name: "Focus")), face: nil))
    #expect(store[.inner(2)] == .action(.appleScript("beep"), face: .emoji("🔔")))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aSlotThatCannotBeReadLeavesTheOthersAndACopy() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = #"""
        {"version":4,"triggers":["screenEdge"],"rings":[{},
        {"1":{"kind":"shortcut","shortcut":"cmd+c","label":"📋"},"2":{"kind":"shortcut","shortcut":"cmd+nokey"}},
        {}]}
        """#
    try Data(json.utf8).write(to: url)

    let store = SlotStore(url: url)
    #expect(store[.inner(1)] == .action(.shortcut(Shortcut(shortcutString: "cmd+c")!), face: .emoji("📋")))
    #expect(store[.inner(2)] == nil)
    #expect(store.triggers == [.screenEdge])
    #expect(try Data(contentsOf: url.appendingPathExtension("broken")) == Data(json.utf8))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aSaveWritesThroughASymlinkedConfig() throws {
    let directory = temporaryConfigURL().deletingLastPathComponent()
    let target = directory.appendingPathComponent("dotfiles/config.json")
    let link = directory.appendingPathComponent("config.json")
    try FileManager.default.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version":4,"rings":[{},{},{}]}"#.utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let store = SlotStore(url: link)
    store.assign(Slot(.action(.shortcut(Shortcut(keyCode: 1, flags: [])), face: .emoji("🙂"))), to: .center)
    store.waitForWrites()

    let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
    #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
    #expect(SlotStore(url: target)[.center] != nil)
    try? FileManager.default.removeItem(at: directory)
}

@Test func aFreshStoreUsesTheHyperKey() {
    #expect(SlotStore(url: temporaryConfigURL()).triggerShortcut == .hyper)
}

@Test func theTriggerShortcutReachesTheNextStore() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    let shortcut = try #require(TriggerShortcut(shortcutString: "ctrl+alt+space"))
    store.setTriggers([.shortcut])
    store.setTriggerShortcut(shortcut)
    store.waitForWrites()

    let next = SlotStore(url: url)
    #expect(next.triggers == [.shortcut])
    #expect(next.triggerShortcut == shortcut)
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect(json?["triggerShortcut"] as? String == "ctrl+alt+space")
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func anUnreadableTriggerShortcutFallsBackToHyper() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version":4,"rings":[{},{},{}],"triggers":["shortcut"],"triggerShortcut":"k"}"#.utf8)
        .write(to: url)

    let store = SlotStore(url: url)
    #expect(store.triggers == [.shortcut])
    #expect(store.triggerShortcut == .hyper)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aPreviousAppAssignmentSurvivesAReopen() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.assign(Slot(.previousApp), to: .inner(1))
    store.waitForWrites()

    #expect(SlotStore(url: url)[.inner(1)] == .previousApp)
    #expect(try String(contentsOf: url, encoding: .utf8).contains(#""kind" : "previousApp""#))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aSlotColorSurvivesAReopenForEveryKindAndTheCentre() throws {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.assign(Slot(.app(AppRef(bundleIdentifier: "com.apple.Safari", name: "Safari")), color: .blue), to: .inner(1))
    store.assign(Slot(.previousApp, color: .teal), to: .inner(2))
    store.assign(Slot(.action(.appleScript("beep"), face: .emoji("🔔")), color: .pink), to: .outer(3))
    store.assign(Slot(.action(.appleScript("beep"), face: .emoji("🔔")), color: .red), to: .center)
    store.assign(Slot(.previousApp), to: .inner(3))
    store.waitForWrites()

    let reopened = SlotStore(url: url)
    #expect(reopened.slots[.inner(1)]?.color == .blue)
    #expect(reopened.slots[.inner(2)]?.color == .teal)
    #expect(reopened.slots[.outer(3)]?.color == .pink)
    #expect(reopened.slots[.center]?.color == .red)
    #expect(reopened.slots[.inner(3)]?.color == nil)
    #expect(reopened[.outer(3)] == .action(.appleScript("beep"), face: .emoji("🔔")))
    let json = try String(contentsOf: url, encoding: .utf8)
    #expect(json.contains(#""color" : "blue""#))
    #expect(json.components(separatedBy: #""color""#).count == 5)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func aMissingColorKeyLoadsAsNoColor() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version":4,"rings":[{},{"1":{"kind":"previousApp"}},{}]}"#.utf8).write(to: url)

    let store = SlotStore(url: url)
    #expect(store[.inner(1)] == .previousApp)
    #expect(store.slots[.inner(1)]?.color == nil)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func anUnknownColorNameLoadsAsNoColorAndKeepsTheSlot() throws {
    let url = temporaryConfigURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(
        #"""
        {"version":4,"rings":[{},
        {"1":{"kind":"previousApp","color":"chartreuse"},"2":{"kind":"previousApp","color":7},"3":{"kind":"previousApp","color":"green"}},
        {}]}
        """#.utf8
    ).write(to: url)

    let store = SlotStore(url: url)
    #expect(store[.inner(1)] == .previousApp)
    #expect(store.slots[.inner(1)]?.color == nil)
    #expect(store[.inner(2)] == .previousApp)
    #expect(store.slots[.inner(2)]?.color == nil)
    #expect(store.slots[.inner(3)]?.color == .green)
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("broken").path))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func movingASlotMovesItsColorWithIt() {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.assign(Slot(.previousApp, color: .orange), to: .inner(1))
    store.assign(Slot(.action(.appleScript("beep"), face: .emoji("🔔"))), to: .inner(2))
    store.swap(.inner(1), with: .inner(2))
    #expect(store.slots[.inner(2)]?.color == .orange)
    #expect(store.slots[.inner(1)]?.color == nil)

    store.swap(.inner(2), with: .outer(4))
    store.waitForWrites()
    let reopened = SlotStore(url: url)
    #expect(reopened.slots[.outer(4)]?.color == .orange)
    #expect(reopened.slots[.inner(2)]?.color == nil)
    #expect(reopened[.outer(4)] == .previousApp)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func clearingASlotRemovesItsColor() {
    let url = temporaryConfigURL()
    let store = SlotStore(url: url)
    store.assign(Slot(.previousApp, color: .purple), to: .inner(1))
    store.assign(nil, to: .inner(1))
    #expect(store.slots[.inner(1)]?.color == nil)

    store.assign(Slot(.previousApp), to: .inner(1))
    #expect(store.slots[.inner(1)]?.color == nil)
    store.waitForWrites()
    #expect(SlotStore(url: url).slots[.inner(1)]?.color == nil)
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func everySlotColorNameIsStable() {
    #expect(SlotColor.allCases.map(\.rawValue) == ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink"])
}
