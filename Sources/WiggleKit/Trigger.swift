import CoreGraphics
import Foundation

/// The fingers on the trackpad in one touch frame: the identity of each touch
/// mapped to its position, from 0 to 1 across the trackpad on each axis.
typealias TouchFrame = [Int: CGPoint]

/// Recognises one gesture that opens the overlay. Each method returns where
/// the overlay opens once the gesture completes, `nil` otherwise.
protocol TriggerDetector: AnyObject {
    func feed(_ point: CGPoint, at now: TimeInterval) -> CGPoint?
    /// Called once the pointer has not moved for `Config.pointerStopDelay`;
    /// `time` is its last movement.
    func pointerStopped(at time: TimeInterval) -> CGPoint?
    /// `touches` is empty once the last finger lifted.
    func touchesChanged(_ touches: TouchFrame, pointer: CGPoint, at now: TimeInterval) -> CGPoint?
    /// A key press that completes a gesture is swallowed.
    func keyDown(_ keyCode: UInt16, flags: CGEventFlags, pointer: CGPoint) -> CGPoint?
    func flagsChanged(_ flags: CGEventFlags, pointer: CGPoint, at now: TimeInterval) -> CGPoint?
    /// Forgets a gesture in progress.
    func reset()
}

extension TriggerDetector {
    func feed(_ point: CGPoint, at now: TimeInterval) -> CGPoint? { nil }
    func pointerStopped(at time: TimeInterval) -> CGPoint? { nil }
    func touchesChanged(_ touches: TouchFrame, pointer: CGPoint, at now: TimeInterval) -> CGPoint? { nil }
    func keyDown(_ keyCode: UInt16, flags: CGEventFlags, pointer: CGPoint) -> CGPoint? { nil }
    func flagsChanged(_ flags: CGEventFlags, pointer: CGPoint, at now: TimeInterval) -> CGPoint? { nil }
}

/// Whether a finger moved farther than a tap allows from where it landed.
func movedAway(_ position: CGPoint, from landing: CGPoint) -> Bool {
    hypot(position.x - landing.x, position.y - landing.y) > Config.tapMaxTravel
}

/// The gestures the user can enable in Settings. The raw value is what the
/// configuration file stores, so a case must keep its name.
enum TriggerKind: String, CaseIterable, Sendable {
    case wiggle
    case screenEdge
    case threeFingerTap
    case fourFingerTap
    case fourFingerSwipeUp
    case fourFingerSwipeDown
    case shortcut

    /// Enabled when the configuration file names no known trigger.
    static let defaults: Set<TriggerKind> = [.wiggle]

    var title: String {
        switch self {
        case .wiggle: "Shake the pointer"
        case .screenEdge: "Bump a screen edge"
        case .threeFingerTap: "Tap with three fingers"
        case .fourFingerTap: "Tap with four fingers"
        case .fourFingerSwipeUp: "Swipe up with four fingers"
        case .fourFingerSwipeDown: "Swipe down with four fingers"
        case .shortcut: "Press a shortcut"
        }
    }

    var description: String {
        switch self {
        case .wiggle: "Move the pointer quickly left and right a few times."
        case .screenEdge: "Push the pointer against a screen edge and let it come to rest there."
        case .threeFingerTap: "Tap the trackpad with three fingers at once."
        case .fourFingerTap: "Tap the trackpad with four fingers at once."
        case .fourFingerSwipeUp: "Swipe up on the trackpad with four fingers."
        case .fourFingerSwipeDown: "Swipe down on the trackpad with four fingers."
        case .shortcut: "Press a key combination, or press and release only modifiers, such as the Hyper key."
        }
    }

    /// macOS uses the same gesture for Mission Control and App Exposé,
    /// unless the user switched it off in the Trackpad settings.
    var isFourFingerVerticalSwipe: Bool {
        switch self {
        case .wiggle, .screenEdge, .threeFingerTap, .fourFingerTap, .shortcut: false
        case .fourFingerSwipeUp, .fourFingerSwipeDown: true
        }
    }

    var usesTrackpad: Bool {
        switch self {
        case .wiggle, .screenEdge, .shortcut: false
        case .threeFingerTap, .fourFingerTap, .fourFingerSwipeUp, .fourFingerSwipeDown: true
        }
    }

    func makeDetector(shortcut: TriggerShortcut) -> any TriggerDetector {
        switch self {
        case .wiggle: WiggleDetector()
        case .screenEdge: ScreenEdgeDetector()
        case .threeFingerTap: TrackpadTapDetector(fingers: 3)
        case .fourFingerTap: TrackpadTapDetector(fingers: 4)
        case .fourFingerSwipeUp: TrackpadSwipeDetector(fingers: 4, direction: .up)
        case .fourFingerSwipeDown: TrackpadSwipeDetector(fingers: 4, direction: .down)
        case .shortcut: ShortcutTriggerDetector(shortcut: shortcut)
        }
    }
}
