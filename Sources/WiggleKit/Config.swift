import Foundation
import CoreGraphics

/// Every tuning value.
enum Config {

    /// Confirmed direction changes needed inside `wiggleWindow`.
    static let reversalsToTrigger = 3
    static let wiggleWindow: TimeInterval = 0.40
    /// A leg shorter than this does not count as a deliberate movement.
    static let minLegDistance: CGFloat = 25
    /// Movement against the current direction must exceed this before it counts
    /// as a reversal. Absorbs jitter at the turning points.
    static let reverseHysteresis: CGFloat = 2
    /// Largest bounding box the movement may span inside the window. A long
    /// mouse throw across the screen must not trigger the overlay.
    static let maxTravel: CGFloat = 500

    /// The pointer must stop at least this far from the edge it bumped, so
    /// that a pointer resting against the edge is no bump.
    static let edgeLeaveDistance: CGFloat = 30
    /// Longest time from touching the edge to the last movement before the
    /// pointer stops. Real bumps took up to 0.93 s, and a 1 s limit missed
    /// about two in three.
    static let edgeBumpWindow: TimeInterval = 2.0
    static let edgeContactTolerance: CGFloat = 1
    static let pointerStopDelay: TimeInterval = 0.15
    static let retriggerCooldown: TimeInterval = 0.2

    /// Longest time from the first finger touching the trackpad to the last
    /// one lifting.
    static let tapMaxDuration: TimeInterval = 0.35
    /// Farthest a finger may move during a tap, as a fraction of the
    /// trackpad's width or height. A finger that moves farther swipes.
    static let tapMaxTravel: CGFloat = 0.04

    // The swipe values are first guesses, not yet tuned on a real trackpad.

    /// Shortest net travel of a swipe, as a fraction of the trackpad's
    /// height, averaged over the fingers. Far above `tapMaxTravel`, so that
    /// no touch is both a tap and a swipe, and short enough for a flick.
    static let swipeMinTravel: CGFloat = 0.15
    /// Longest time from the first finger touching the trackpad to the last
    /// one lifting. A deliberate swipe is over well within it, a slow drag of
    /// four fingers is not.
    static let swipeMaxDuration: TimeInterval = 1.0
    /// A swipe must travel this many times farther vertically than
    /// horizontally, which allows a slant of about 27 degrees off vertical.
    static let swipeVerticalRatio: CGFloat = 2

    /// Gap between the wheel's outer edge and the panel border. Room for a
    /// lifted outer tile and its shadow.
    static let wheelPadding: CGFloat = 24
    /// Smallest gap between the overlay and the edge of the screen.
    static let screenMargin: CGFloat = 12

    /// Square, because the hub always sits at half the side.
    static func panelSide(showsOuterRing: Bool) -> CGFloat {
        (showsOuterRing ? circleOuterRingOuterRadius : circleInnerRingOuterRadius) * 2 + 2 * wheelPadding
    }

    static let circleHubRadius: CGFloat = 34
    static let circleInnerRingOuterRadius: CGFloat = 116
    /// Chosen so a ring 2 slice is about 60 pt wide at its middle radius.
    static let circleOuterRingDepth: CGFloat = 80
    static var circleOuterRingOuterRadius: CGFloat { circleInnerRingOuterRadius + circleOuterRingDepth }
    /// Bigger than a slice's text box, which stays narrow so text never
    /// spills into a neighbouring slice.
    static let circleInnerSliceIconBoxSize: CGFloat = 48
    static let circleOuterSliceIconBoxSize: CGFloat = 30
    /// How far in from a ring's outer edge its key hint sits.
    static let circleHintInset: CGFloat = 12
    /// The icon a tile draws is 60 % of this square. Larger than the icon box,
    /// which also sizes the Settings hit targets and must not overlap.
    static let circleInnerSliceTileIconSize: CGFloat = 66
    static let circleOuterSliceTileIconSize: CGFloat = 46

    /// The even gap between neighbouring tiles.
    static let wheelTileGap: CGFloat = 6
    /// The band along a tile's outer edge that shows the slot's colour.
    static let wheelRimWidth: CGFloat = 4
    /// A ring 1 tile's band, on its short hub side, needs more depth to show.
    static let wheelHubSideRimDepth: CGFloat = 9
    /// How far the disc under the tiles reaches past the outer ring.
    static let wheelDiscMargin: CGFloat = 5
    /// How far the hovered tile lifts outward.
    static let wheelLiftDistance: CGFloat = 7
    /// The ease-out of the lift: about 95 % of the way after 3 of these.
    static let wheelLiftTimeConstant: TimeInterval = 0.035

    static let defaultOverlayOpacity: CGFloat = 0.92
    /// The slider's range. Below 0.5 the key hints and the tiles fade into a
    /// light or busy background, and the overlay is something to read at a
    /// glance.
    static let overlayOpacityRange: ClosedRange<CGFloat> = 0.5...1
    /// The blur and the disc behind the tiles, apart from the whole wheel.
    static let defaultBackgroundOpacity: CGFloat = 0.9
    static let backgroundOpacityRange: ClosedRange<CGFloat> = 0...1
    static let defaultOverlayAppearance: OverlayAppearance = .auto

    static let permissionCheckInterval: TimeInterval = 2.0

    /// Pause between hiding the overlay and running a slot, so the window is
    /// off the screen before the slot takes effect.
    static let keystrokeDelay: TimeInterval = 0.05
    /// Marks the events Wiggle posts, so that the tap ignores them.
    static let syntheticMarker: Int64 = 0x5747_4C45  // "WGLE"
}
