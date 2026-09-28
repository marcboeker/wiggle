import AppKit
import KeyboardShortcuts

/// The key combination that opens the overlay. Without a key it is a chord
/// of modifiers alone, such as the Hyper key, which opens the overlay when
/// released.
struct TriggerShortcut: Equatable {
    let keyCode: UInt16?
    let flags: CGEventFlags

    /// Command, Control, Option and Shift at once.
    static let hyper = TriggerShortcut(keyCode: nil, flags: Shortcut.allowedModifiers)!

    /// `nil` for a combination that would take keys from normal typing: a
    /// key with no modifier or only Shift, except a function key, or a
    /// chord with no modifier.
    init?(keyCode: UInt16?, flags: CGEventFlags) {
        let flags = flags.intersection(Shortcut.allowedModifiers)
        if let keyCode {
            let hasCommandModifier = !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
            guard hasCommandModifier || KeyNames.isFunctionKey(keyCode) else { return nil }
        } else {
            guard !flags.isEmpty else { return nil }
        }
        self.keyCode = keyCode
        self.flags = flags
    }

    init?(shortcutString raw: String) {
        guard let (flags, keyCode) = ShortcutSpelling.parse(raw) else { return nil }
        self.init(keyCode: keyCode, flags: flags)
    }

    var shortcutString: String { ShortcutSpelling.string(flags: flags, keyCode: keyCode) }

    @MainActor
    var displayString: String {
        if let keyCode { return Shortcut(keyCode: keyCode, flags: flags).libraryShortcut.description }
        let symbols = TriggerShortcut.symbols(for: flags)
        return self == .hyper ? "Hyper \(symbols)" : symbols
    }

    static func symbols(for flags: CGEventFlags) -> String {
        NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)).ks_symbolicRepresentation
    }
}

/// Opens the overlay on the trigger shortcut. A chord of modifiers must be
/// released without a key or a click in between, so the same modifiers
/// still work with a key for other shortcuts.
final class ShortcutTriggerDetector: TriggerDetector {

    private let shortcut: TriggerShortcut
    /// When every modifier of the chord was last held at once.
    private var chordHeld: TimeInterval?

    init(shortcut: TriggerShortcut) {
        self.shortcut = shortcut
    }

    func keyDown(_ keyCode: UInt16, flags: CGEventFlags, pointer: CGPoint) -> CGPoint? {
        chordHeld = nil
        let matches = keyCode == shortcut.keyCode && flags.intersection(Shortcut.allowedModifiers) == shortcut.flags
        return matches ? pointer : nil
    }

    func flagsChanged(_ flags: CGEventFlags, pointer: CGPoint, at now: TimeInterval) -> CGPoint? {
        guard shortcut.keyCode == nil else { return nil }
        let held = flags.intersection(Shortcut.allowedModifiers)
        if held == shortcut.flags {
            chordHeld = now
            return nil
        }
        // Modifiers of the chord come up one after another.
        if held.isSubset(of: shortcut.flags), !held.isEmpty { return nil }
        defer { chordHeld = nil }
        guard held.isEmpty, let chordHeld, now - chordHeld <= Config.chordMaxHold else { return nil }
        return pointer
    }

    func reset() {
        chordHeld = nil
    }
}

/// What a recorder has seen since recording began. Each method returns
/// the recorded shortcut once the input is complete.
struct TriggerShortcutRecording {

    /// The modifiers held now.
    private(set) var held: CGEventFlags = []
    /// Every modifier pressed since none were held.
    private var chord: CGEventFlags = []

    mutating func flagsChanged(_ flags: CGEventFlags) -> TriggerShortcut? {
        held = flags.intersection(Shortcut.allowedModifiers)
        guard held.isEmpty else {
            chord.formUnion(held)
            return nil
        }
        defer { chord = [] }
        return TriggerShortcut(keyCode: nil, flags: chord)
    }

    /// `nil` also for a key that cannot be a trigger. The modifiers held
    /// with it are then no chord of their own.
    mutating func keyDown(_ keyCode: UInt16, flags: CGEventFlags) -> TriggerShortcut? {
        chord = []
        return TriggerShortcut(keyCode: keyCode, flags: flags)
    }
}
