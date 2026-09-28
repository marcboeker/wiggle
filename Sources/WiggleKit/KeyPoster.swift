import CoreGraphics
import Foundation

enum KeyPoster {

    static func post(_ shortcut: Shortcut) {
        // A private source state ignores the modifiers the user holds now.
        guard let source = CGEventSource(stateID: .privateState) else {
            NSLog("wiggle: cannot create an event source")
            return
        }
        source.userData = Config.syntheticMarker

        // Both halves are built before either is posted, because a lone press
        // would leave the focused app with a held key.
        let key = CGKeyCode(shortcut.keyCode)
        let events = [true, false].compactMap {
            CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: $0)
        }
        guard events.count == 2 else {
            NSLog("wiggle: cannot build the keystroke for \(shortcut.shortcutString)")
            return
        }
        for event in events {
            event.flags = shortcut.flags
            event.setIntegerValueField(.eventSourceUserData, value: Config.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
