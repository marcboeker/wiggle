import CoreGraphics
import Foundation

extension CGEventType {
    /// `NSEvent.EventType.gesture`, which Core Graphics has no name for.
    static let gesture = CGEventType(rawValue: 29)!
    /// The private `kCGSEventDockControl`, which carries the Dock swipe that
    /// opens Mission Control or App Exposé.
    static let dockControl = CGEventType(rawValue: 30)!
}

/// Private fields of a Dock control event, as recorded on macOS 26.
extension CGEventField {
    static let dockControlSubtype = CGEventField(rawValue: 110)!
    static let dockSwipeMotion = CGEventField(rawValue: 123)!
    static let dockSwipePhase = CGEventField(rawValue: 132)!
}

/// The handler returns `nil` to swallow an event.
final class EventTap {

    typealias Handler = @MainActor @Sendable (CGEventType, CGEvent) -> CGEvent?

    private struct Box<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    private let handler: Handler
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private static let mask: CGEventMask = {
        // Releases are included, because a swallowed press must take its
        // release with it.
        let types: [CGEventType] = [
            .mouseMoved, .scrollWheel,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp,
            .keyDown, .keyUp, .flagsChanged, .gesture, .dockControl,
        ]
        return types.reduce(into: CGEventMask(0)) { $0 |= 1 << $1.rawValue }
    }()

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() -> Bool {
        guard machPort == nil else { return true }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.dispatch(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: EventTap.mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        machPort = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        machPort = nil
        runLoopSource = nil
    }

    deinit { stop() }

    private func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that is too slow or that the user interrupts.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let machPort { CGEvent.tapEnable(tap: machPort, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Config.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        // The tap runs on the main run loop, so the isolation boundary is
        // only nominal. CGEvent is not Sendable, hence the box.
        let box = Box(event)
        let handler = self.handler
        let result = MainActor.assumeIsolated { Box(handler(type, box.value)) }
        guard let kept = result.value else { return nil }
        return Unmanaged.passUnretained(kept)
    }
}
