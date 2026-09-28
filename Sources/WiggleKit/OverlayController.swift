import AppKit
import Carbon.HIToolbox

/// Converts between Core Graphics global coordinates (origin at the top left of
/// the primary display) and AppKit screen coordinates (origin at the bottom
/// left of the primary display).
enum Coords {

    private static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }

    static func appKitPoint(from point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func cgPoint(from point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Into `frame`'s flipped coordinates, the ones `CircularOverlayView`
    /// draws in.
    static func viewPoint(from screenPoint: NSPoint, in frame: NSRect) -> NSPoint {
        NSPoint(x: screenPoint.x - frame.minX, y: frame.maxY - screenPoint.y)
    }

    static func screenPoint(from viewPoint: NSPoint, in frame: NSRect) -> NSPoint {
        NSPoint(x: frame.minX + viewPoint.x, y: frame.maxY - viewPoint.y)
    }

    /// The origin of a `size`-sized frame that puts `viewPoint`, in the
    /// frame's flipped coordinates, on `screenPoint`.
    static func origin(placing viewPoint: NSPoint, at screenPoint: NSPoint, size: NSSize) -> NSPoint {
        NSPoint(x: screenPoint.x - viewPoint.x, y: screenPoint.y - (size.height - viewPoint.y))
    }
}

/// Only Escape and running a slot put a warped pointer back. A click
/// outside leaves it where the user clicked.
enum CloseReason {
    case escape
    case ranASlot
    case clickedOutside
    case openedSettings
    case other

    var restoresPointer: Bool {
        switch self {
        case .escape, .ranASlot: return true
        case .clickedOutside, .openedSettings, .other: return false
        }
    }
}

/// The panel never takes the keyboard focus and never receives mouse events
/// itself. All input arrives from the event tap, so the focused app keeps
/// the focus and the overlay can swallow the events it consumes.
@MainActor
final class OverlayController {

    private let store: SlotStore
    private let panel: NSPanel
    private let backdrop: NSVisualEffectView
    private let container: NSView
    private let view: CircularOverlayView

    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Gets every warp target, in `CGEvent` coordinates.
    var onWarp: ((CGPoint) -> Void)?

    private(set) var isVisible = false

    /// Where the pointer was before `show` warped it to the hub.
    private var warpedFrom: CGPoint?

    var panelFrame: NSRect { panel.frame }

    init(store: SlotStore) {
        self.store = store
        let side = Config.panelSide(showsOuterRing: true)
        let frame = NSRect(origin: .zero, size: CGSize(width: side, height: side))

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]

        let backdrop = NSVisualEffectView(frame: frame)
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        self.backdrop = backdrop

        let view = CircularOverlayView(frame: frame)
        view.showsEmptySlots = false
        self.view = view

        // The blur lives in its own view, so the mask that clips it to the
        // slots never clips the content drawn on top.
        let container = NSView(frame: frame)
        container.addSubview(backdrop)
        container.addSubview(view)
        self.container = container

        panel.contentView = container
        updateBackdropShape()
    }

    /// Pins the overlay with its hub under the pointer. Ring 2 shows only
    /// when one of its slots has an assignment.
    func show(at pointerLocation: CGPoint) {
        let showsOuterRing = store.hasOuterRingAssignment
        let side = Config.panelSide(showsOuterRing: showsOuterRing)
        let size = CGSize(width: side, height: side)

        // The backdrop and the wheel both follow the panel's appearance.
        panel.appearance = store.overlayAppearance.appearance

        let pointer = Coords.appKitPoint(from: pointerLocation)
        let hub = SlotLayout.hub(side: side)
        var origin = Coords.origin(placing: hub, at: pointer, size: size)

        // Not `contains`: a pointer on a display's top row flips to the
        // frame's `maxY`, which `contains` leaves to the display above.
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        if let limit = screen?.visibleFrame.insetBy(dx: Config.screenMargin, dy: Config.screenMargin) {
            origin.x = clamp(origin.x, from: limit.minX, to: limit.maxX - size.width)
            origin.y = clamp(origin.y, from: limit.minY, to: limit.maxY - size.height)
        }

        view.showsOuterRing = showsOuterRing
        // An overlay with every slot hidden would still hold the keyboard.
        view.showsEmptySlots = store.slots.isEmpty
        view.slots = store.slots
        // After the slots: the backdrop is clipped to their shapes.
        resize(to: size)
        view.hovered = nil
        panel.alphaValue = store.overlayOpacity
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        isVisible = true

        // The clamp moved the hub away from the pointer, so the pointer
        // follows the hub.
        let hubScreen = Coords.screenPoint(from: hub, in: NSRect(origin: origin, size: size))
        if hubScreen != pointer {
            warpedFrom = pointerLocation
            warp(to: Coords.cgPoint(from: hubScreen))
        } else {
            warpedFrom = nil
        }
    }

    func hide(_ reason: CloseReason = .other) {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
        if reason.restoresPointer, let warpedFrom {
            warp(to: warpedFrom)
        }
        warpedFrom = nil
        onClose?()
    }

    /// Returns `true` when the event must not reach the app below.
    func handleMouseDown(at location: CGPoint) -> Bool {
        guard isVisible else { return false }
        // A hidden empty slot and the panel's empty corners count as outside.
        let point = viewPoint(from: Coords.appKitPoint(from: location))
        if let id = view.rawSlotID(at: point), store[id] != nil {
            run(id)
        } else {
            hide(.clickedOutside)
        }
        return true
    }

    func handleMouseMoved(to location: CGPoint) {
        guard isVisible else { return }
        let point = Coords.appKitPoint(from: location)
        view.hovered = panel.frame.contains(point) ? view.slotID(at: viewPoint(from: point)) : nil
    }

    /// Returns `true` when the event must not reach the app below.
    func handleKeyDown(_ event: CGEvent) -> Bool {
        guard isVisible else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if Int(keyCode) == kVK_ANSI_Comma, event.flags.contains(.maskCommand) {
            hide(.openedSettings)
            onOpenSettings?()
        } else if Int(keyCode) == kVK_Escape {
            hide(.escape)
        } else if let id = OverlayController.slotID(for: keyCode) {
            run(id)
        }
        // While the overlay is open it owns the keyboard.
        return true
    }

    /// On a screen smaller than the overlay the lower edge wins.
    private func clamp(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        upper < lower ? lower : min(max(value, lower), upper)
    }

    private func resize(to size: CGSize) {
        let frame = NSRect(origin: .zero, size: size)
        container.frame = frame
        backdrop.frame = frame
        view.frame = frame
        updateBackdropShape()
    }

    private func updateBackdropShape() {
        let mask = CAShapeLayer()
        mask.path = view.backdropPath()
        backdrop.layer?.mask = mask
    }

    /// Dissociating the mouse keeps the hardware deltas that follow from
    /// piling on top of the jump.
    private func warp(to point: CGPoint) {
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
        onWarp?(point)
    }

    private func run(_ id: SlotID) {
        guard let assignment = store[id] else { return }
        hide(.ranASlot)
        // A window or menu that the slot opens must not appear behind the
        // wheel.
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.keystrokeDelay) {
            assignment.run()
        }
    }

    private func viewPoint(from screenPoint: NSPoint) -> NSPoint {
        Coords.viewPoint(from: screenPoint, in: panel.frame)
    }

    private static let innerKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4,
        kVK_ANSI_5: 5, kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3,
        kVK_ANSI_Keypad4: 4, kVK_ANSI_Keypad5: 5, kVK_ANSI_Keypad6: 6,
        kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8,
    ]

    private static let outerKeys: [Int: Int] = [
        kVK_ANSI_A: 1, kVK_ANSI_B: 2, kVK_ANSI_C: 3, kVK_ANSI_D: 4,
        kVK_ANSI_E: 5, kVK_ANSI_F: 6, kVK_ANSI_G: 7, kVK_ANSI_H: 8,
        kVK_ANSI_I: 9, kVK_ANSI_J: 10, kVK_ANSI_K: 11, kVK_ANSI_L: 12,
        kVK_ANSI_M: 13, kVK_ANSI_N: 14, kVK_ANSI_O: 15, kVK_ANSI_P: 16,
    ]

    /// Ignores modifiers.
    static func slotID(for keyCode: UInt16) -> SlotID? {
        let key = Int(keyCode)
        if key == kVK_Return || key == kVK_ANSI_KeypadEnter { return .center }
        if let number = innerKeys[key] { return .inner(number) }
        if let number = outerKeys[key] { return .outer(number) }
        return nil
    }
}
