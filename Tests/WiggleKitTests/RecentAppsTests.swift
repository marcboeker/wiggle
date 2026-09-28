import Testing

@testable import WiggleKit

private let arc = "Arc"
private let finder = "Finder"
private let notes = "Notes"

@Test func thePreviousAppIsTheOneBeforeTheAppInFront() {
    var recent = RecentApps<String>()
    recent.activated(arc, pid: 1)
    recent.activated(finder, pid: 2)
    #expect(recent.previous(frontmost: 2) == arc)
}

@Test func switchingBackAndForthSwapsThePreviousApp() {
    var recent = RecentApps<String>()
    recent.activated(notes, pid: 3)
    recent.activated(arc, pid: 1)
    recent.activated(finder, pid: 2)
    recent.activated(arc, pid: 1)
    #expect(recent.previous(frontmost: 1) == finder)
}

@Test func aQuitAppIsNoLongerThePreviousApp() {
    var recent = RecentApps<String>()
    recent.activated(notes, pid: 3)
    recent.activated(arc, pid: 1)
    recent.activated(finder, pid: 2)
    recent.terminated(1)
    #expect(recent.previous(frontmost: 2) == notes)
}

@Test func withOnlyTheAppInFrontThereIsNoPreviousApp() {
    var recent = RecentApps<String>()
    recent.activated(finder, pid: 2)
    #expect(recent.previous(frontmost: 2) == nil)
}

/// While Wiggle's Settings is in front, the app in front is not recorded.
@Test func anUnrecordedAppInFrontLeavesTheNewestAppAsPrevious() {
    var recent = RecentApps<String>()
    recent.activated(arc, pid: 1)
    #expect(recent.previous(frontmost: 99) == arc)
}
