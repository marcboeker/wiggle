import CoreGraphics
import Foundation

/// Keeps what macOS makes of a swipe trigger from reaching anything else.
///
/// With Mission Control off in the Trackpad settings, macOS turns a four
/// finger swipe into ordinary scroll events while the fingers are down, and
/// into momentum after they lift. With a three or four finger swipe on in
/// the Trackpad settings, it sends the Dock a Dock swipe, which opens
/// Mission Control or App Exposé.
///
/// Neither event says how many fingers make it, so the filter follows the
/// touch frames. A scroll swallows from the first event that has `fingers` or
/// more fingers down in the current touch, and so does the momentum that
/// follows it. A scroll with fewer fingers, and a mouse wheel, pass. An app
/// that saw a scroll begin still sees it end, so that it is not left in the
/// middle of one. A vertical Dock swipe swallows, from its beginning to its
/// end, when `fingers` or more fingers are down as it begins. One that began
/// with fewer fingers passes whole, so that Mission Control never stays half
/// open.
struct SwipeEventFilter {

    /// Values of the private Dock control fields, as recorded on macOS 26.
    static let dockSwipeSubtype: Int64 = 23
    static let verticalDockSwipeMotion: Int64 = 2

    let fingers: Int
    private var mostFingers = 0
    /// Also covers the momentum after the scroll.
    private(set) var isSwallowingScroll = false
    private var appSawBegin = false
    private var isSwallowingDockSwipe = false

    init(fingers: Int) {
        self.fingers = fingers
    }

    mutating func touchesChanged(count: Int) {
        mostFingers = count == 0 ? 0 : max(mostFingers, count)
    }

    /// A mouse wheel has 0 for both phases.
    mutating func shouldSwallowScroll(scrollPhase: Int64, momentumPhase: Int64) -> Bool {
        if momentumPhase != 0 { return isSwallowingScroll }
        guard scrollPhase != 0 else { return false }
        let begins = Self.begins(scrollPhase)
        if begins {
            isSwallowingScroll = false
            appSawBegin = false
        }
        isSwallowingScroll = isSwallowingScroll || mostFingers >= fingers
        if !isSwallowingScroll {
            appSawBegin = appSawBegin || begins
            return false
        }
        let ends = scrollPhase == CGScrollPhase.ended.rawValue || scrollPhase == CGScrollPhase.cancelled.rawValue
        return !(ends && appSawBegin)
    }

    /// A Dock swipe uses the `CGScrollPhase` values too.
    private static func begins(_ phase: Int64) -> Bool {
        phase == CGScrollPhase.began.rawValue || phase == CGScrollPhase.mayBegin.rawValue
    }

    mutating func shouldSwallowDockControl(subtype: Int64, motion: Int64, phase: Int64) -> Bool {
        guard subtype == Self.dockSwipeSubtype, motion == Self.verticalDockSwipeMotion else { return false }
        if Self.begins(phase) {
            isSwallowingDockSwipe = mostFingers >= fingers
        }
        return isSwallowingDockSwipe
    }
}
