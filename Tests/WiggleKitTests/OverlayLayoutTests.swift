import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import WiggleKit

@Test func slotIDRefusesANumberOutsideItsRing() {
    #expect(SlotID(ring: 0, slot: 0) == .center)
    #expect(SlotID(ring: 0, slot: 1) == nil)
    #expect(SlotID(ring: 1, slot: 1) == .inner(1))
    #expect(SlotID(ring: 1, slot: 8) == .inner(8))
    #expect(SlotID(ring: 1, slot: 0) == nil)
    #expect(SlotID(ring: 1, slot: 9) == nil)
    #expect(SlotID(ring: 2, slot: 1) == .outer(1))
    #expect(SlotID(ring: 2, slot: 16) == .outer(16))
    #expect(SlotID(ring: 2, slot: 0) == nil)
    #expect(SlotID(ring: 2, slot: 17) == nil)
    #expect(SlotID(ring: 3, slot: 0) == nil)
}

@Test func slotIDKeyHintsAreDigitsLettersOrReturn() {
    #expect(SlotID.center.keyHint == "↩")
    #expect(SlotID.inner(1).keyHint == "1")
    #expect(SlotID.inner(8).keyHint == "8")
    #expect(SlotID.outer(1).keyHint == "a")
    #expect(SlotID.outer(16).keyHint == "p")
}

@Test func slotIDLabelsNameTheSlotUnderstandably() {
    #expect(SlotID.center.label == "Center")
    #expect(SlotID.inner(3).label == "Slot 3")
    #expect(SlotID.outer(1).label == "Slot a")
}

@Test func innerSlotOneIsStraightUpAndRunsClockwise() {
    #expect(SlotLayout.angleDegrees(for: .inner(1)) == 90)
    #expect(SlotLayout.angleDegrees(for: .inner(3)) == 0)
    #expect(SlotLayout.angleDegrees(for: .inner(5)) == 270)
    #expect(SlotLayout.angleDegrees(for: .inner(7)) == 180)
    #expect(SlotLayout.angleDegrees(for: .center) == nil)
}

@Test func outerRingSlotsOneAndTwoSitAboveInnerRingSlotOne() {
    // Ring 2 slot 1 is the slice just left of 12 o'clock (112.5°...90°);
    // slot 2 is just right of it (90°...67.5°). Together they span exactly
    // ring 1 slot 1's own 67.5°...112.5° range.
    #expect(SlotLayout.angleDegrees(for: .outer(1)) == 101.25)
    #expect(SlotLayout.angleDegrees(for: .outer(2)) == 78.75)
}

/// The smallest angle between two directions, ignoring the 360° wraparound.
private func angularDistance(_ a: Double, _ b: Double) -> Double {
    let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(diff, 360 - diff)
}

@Test func everyInnerSlotIsCoveredByTwoOuterSlots() {
    // Ring 1 slot n is covered by ring 2 slots 2n-1 and 2n.
    for n in SlotID.innerNumbers {
        let innerAngle = SlotLayout.angleDegrees(for: .inner(n))!
        let firstOuter = SlotLayout.angleDegrees(for: .outer(2 * n - 1))!
        let secondOuter = SlotLayout.angleDegrees(for: .outer(2 * n))!
        #expect(angularDistance(firstOuter, innerAngle + 11.25) < 0.001)
        #expect(angularDistance(secondOuter, innerAngle - 11.25) < 0.001)
    }
}

@Test func hitTestFindsTheCentre() {
    #expect(
        SlotLayout.slotID(
            dx: 0, dy: 0, showsOuterRing: true) == .center)
    #expect(
        SlotLayout.slotID(
            dx: 10, dy: -10, showsOuterRing: true) == .center)
}

@Test func hitTestFindsInnerRingSlicesClockwiseFromTheTop() {
    let radius: CGFloat = 75
    func hit(_ dx: CGFloat, _ dy: CGFloat) -> SlotID? {
        SlotLayout.slotID(
            dx: dx, dy: dy, showsOuterRing: false)
    }
    #expect(hit(0, -radius) == .inner(1))
    #expect(hit(radius, 0) == .inner(3))
    #expect(hit(0, radius) == .inner(5))
    #expect(hit(-radius, 0) == .inner(7))
}

@Test func hitTestIgnoresRing2WhenItIsNotShown() {
    // A point that would land in ring 2 hits nothing while ring 2 is hidden,
    // even though it is inside ring 2's own outer radius.
    let hit = SlotLayout.slotID(
        dx: 0, dy: -160, showsOuterRing: false)
    #expect(hit == nil)
}

@Test func hitTestFindsOuterRingSlices() {
    let radius: CGFloat = 160
    func hit(_ dx: CGFloat, _ dy: CGFloat) -> SlotID? {
        SlotLayout.slotID(
            dx: dx, dy: dy, showsOuterRing: true)
    }
    // Slightly left and right of straight up, inside ring 1 slot 1's span.
    #expect(hit(-5, -radius) == .outer(1))
    #expect(hit(5, -radius) == .outer(2))
}

@Test func theTwelveOClockBoundaryOfRingTwoBelongsToTheSliceClockwiseOfIt() {
    let hit = SlotLayout.slotID(
        dx: 0, dy: -160, showsOuterRing: true)
    #expect(hit == .outer(2))
}

@Test func pointsOutsideEveryShownRingHitNothing() {
    let hitWithOuter = SlotLayout.slotID(
        dx: 0, dy: -210, showsOuterRing: true)
    #expect(hitWithOuter == nil)
}

@Test @MainActor func theHubSitsAtHalfTheWheelsSide() {
    let side: CGFloat = Config.panelSide(showsOuterRing: false)
    #expect(SlotLayout.hub(side: side) == CGPoint(x: side / 2, y: side / 2))
}

@Test func placingTheHubLandsExactlyOnTheGivenScreenPointForBothPanelSizes() {
    for showsOuterRing in [false, true] {
        let side = Config.panelSide(showsOuterRing: showsOuterRing)
        let size = CGSize(width: side, height: side)
        let hub = SlotLayout.hub(side: side)
        let pointer = NSPoint(x: 682, y: 754)

        let origin = Coords.origin(placing: hub, at: pointer, size: size)
        let hubScreen = Coords.screenPoint(from: hub, in: NSRect(origin: origin, size: size))
        #expect(hubScreen == pointer)
    }
}

@Test func aClampedOriginsHubIsWhereTheWarpMustTarget() {
    for showsOuterRing in [false, true] {
        let side = Config.panelSide(showsOuterRing: showsOuterRing)
        let size = CGSize(width: side, height: side)
        let hub = SlotLayout.hub(side: side)
        let pointer = NSPoint(x: 20, y: 20)  // near a corner: a real clamp would move the panel

        let desiredOrigin = Coords.origin(placing: hub, at: pointer, size: size)
        let clampedOrigin = NSPoint(x: max(desiredOrigin.x, 12), y: max(desiredOrigin.y, 12))
        #expect(clampedOrigin != desiredOrigin)  // this pointer must force the simulated clamp

        let warpTarget = Coords.screenPoint(from: hub, in: NSRect(origin: clampedOrigin, size: size))
        #expect(warpTarget != pointer)
        #expect(warpTarget == NSPoint(x: clampedOrigin.x + side / 2, y: clampedOrigin.y + side / 2))
    }
}

@Test @MainActor func showPutsTheHubExactlyOnAnUnclampedPointer() throws {
    let screen = try #require(NSScreen.main)
    let store = SlotStore(url: temporaryConfigURL())
    let overlay = OverlayController(store: store)

    // The centre of the main screen, far from every edge, so the panel is
    // never clamped and the hub must land exactly on the pointer.
    let centreAppKit = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    overlay.show(at: Coords.cgPoint(from: centreAppKit))
    defer { overlay.hide() }

    let hubScreen = Coords.screenPoint(from: SlotLayout.hub(side: overlay.panelFrame.width), in: overlay.panelFrame)
    #expect(abs(hubScreen.x - centreAppKit.x) <= 0.5)
    #expect(abs(hubScreen.y - centreAppKit.y) <= 0.5)
}

@Test func onlyEscapeAndRunningASlotRestoreThePointer() {
    #expect(CloseReason.escape.restoresPointer)
    #expect(CloseReason.ranASlot.restoresPointer)
    #expect(!CloseReason.clickedOutside.restoresPointer)
    #expect(!CloseReason.openedSettings.restoresPointer)
    #expect(!CloseReason.other.restoresPointer)
}

@MainActor
private func circularView(showsOuterRing: Bool = true) -> CircularOverlayView {
    let side = Config.panelSide(showsOuterRing: showsOuterRing)
    let view = CircularOverlayView(frame: NSRect(x: 0, y: 0, width: side, height: side))
    view.showsOuterRing = showsOuterRing
    return view
}

@Test @MainActor func theHubHitsTheCentre() {
    let view = circularView()
    let hub = SlotLayout.hub(side: view.bounds.width)
    #expect(view.slotID(at: hub) == .center)
}

@Test @MainActor func slicesGoClockwiseFromTheTop() {
    let view = circularView(showsOuterRing: false)
    let hub = SlotLayout.hub(side: view.bounds.width)
    let radius = (Config.circleHubRadius + Config.circleInnerRingOuterRadius) / 2

    #expect(view.slotID(at: NSPoint(x: hub.x, y: hub.y - radius)) == .inner(1))
    #expect(view.slotID(at: NSPoint(x: hub.x + radius, y: hub.y)) == .inner(3))
    #expect(view.slotID(at: NSPoint(x: hub.x, y: hub.y + radius)) == .inner(5))
    #expect(view.slotID(at: NSPoint(x: hub.x - radius, y: hub.y)) == .inner(7))
}

@Test @MainActor func pointsOutsideTheWheelHitNothing() {
    let view = circularView(showsOuterRing: false)
    let hub = SlotLayout.hub(side: view.bounds.width)
    let outside = NSPoint(x: hub.x, y: hub.y - Config.circleInnerRingOuterRadius - 5)
    #expect(view.slotID(at: outside) == nil)
}

@Test @MainActor func hidingRing2AlsoHidesItFromHitTesting() {
    let view = circularView(showsOuterRing: false)
    let hub = SlotLayout.hub(side: view.bounds.width)
    // Inside ring 2's outer radius, so this would hit an outer slice if ring
    // 2 were shown.
    let point = NSPoint(x: hub.x, y: hub.y - Config.circleInnerRingOuterRadius - 10)
    #expect(view.slotID(at: point) == nil)
}

@Test @MainActor func hidingEmptySlotsAlsoHidesThemFromHitTesting() {
    let view = circularView(showsOuterRing: false)
    view.showsEmptySlots = false
    view.slots = [.inner(3): Slot(.app(AppRef(bundleIdentifier: "com.apple.calculator", name: "Calculator")))]
    let hub = SlotLayout.hub(side: view.bounds.width)
    let radius = (Config.circleHubRadius + Config.circleInnerRingOuterRadius) / 2

    #expect(view.slotID(at: NSPoint(x: hub.x + radius, y: hub.y)) == .inner(3))
    #expect(view.slotID(at: NSPoint(x: hub.x, y: hub.y - radius)) == nil)
    #expect(view.slotID(at: hub) == nil)
}

@Test @MainActor func rawSlotIDStillFindsHiddenEmptySlots() {
    let view = circularView(showsOuterRing: false)
    view.showsEmptySlots = false
    view.slots = [.inner(3): Slot(.app(AppRef(bundleIdentifier: "com.apple.calculator", name: "Calculator")))]
    let hub = SlotLayout.hub(side: view.bounds.width)
    let radius = (Config.circleHubRadius + Config.circleInnerRingOuterRadius) / 2

    let emptySlotPoint = NSPoint(x: hub.x, y: hub.y - radius)
    #expect(view.slotID(at: emptySlotPoint) == nil)
    #expect(view.rawSlotID(at: emptySlotPoint) == .inner(1))

    let outside = NSPoint(x: hub.x, y: hub.y - Config.circleInnerRingOuterRadius - 5)
    #expect(view.rawSlotID(at: outside) == nil)
}

@Test @MainActor func returnAndKeypadEnterRunTheCentre() {
    #expect(OverlayController.slotID(for: UInt16(kVK_Return)) == .center)
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_KeypadEnter)) == .center)
}

@Test @MainActor func topRowAndKeypadDigitsOneToEightRunRingOne() {
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_1)) == .inner(1))
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_8)) == .inner(8))
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_Keypad1)) == .inner(1))
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_Keypad8)) == .inner(8))
}

@Test @MainActor func lettersAToPRunRingTwo() {
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_A)) == .outer(1))
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_P)) == .outer(16))
}

@Test @MainActor func zeroAndNineAndEscapeRunNothing() {
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_0)) == nil)
    #expect(OverlayController.slotID(for: UInt16(kVK_ANSI_9)) == nil)
    #expect(OverlayController.slotID(for: UInt16(kVK_Escape)) == nil)
}
