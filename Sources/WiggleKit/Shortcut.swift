import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// One key plus its modifiers, as assigned to a slot.
struct Shortcut: Equatable {
    var keyCode: UInt16
    var flags: CGEventFlags

    static let allowedModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskControl, .maskAlternate,
    ]

    init(keyCode: UInt16, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.flags = flags.intersection(Shortcut.allowedModifiers)
    }
}

/// The config file's spelling of a key combination, for example
/// `cmd+ctrl+shift+4`, or `cmd+ctrl+alt+shift` without a key. Modifier order
/// does not matter on read.
enum ShortcutSpelling {

    static func string(flags: CGEventFlags, keyCode: UInt16?) -> String {
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskAlternate) { parts.append("alt") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if let keyCode { parts.append(KeyNames.canonicalName(for: keyCode)) }
        return parts.joined(separator: "+")
    }

    /// `keyCode` is `nil` when the string names only modifiers.
    static func parse(_ raw: String) -> (flags: CGEventFlags, keyCode: UInt16?)? {
        let tokens = raw.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard !tokens.isEmpty else { return nil }

        var flags: CGEventFlags = []
        var keyToken: String?
        for token in tokens {
            switch token {
            case "cmd", "command": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default:
                guard keyToken == nil else { return nil }
                keyToken = token
            }
        }
        guard let keyToken else { return (flags, nil) }
        guard let keyCode = KeyNames.keyCode(forCanonicalName: keyToken) else { return nil }
        return (flags, keyCode)
    }
}

extension Shortcut {

    var shortcutString: String { ShortcutSpelling.string(flags: flags, keyCode: keyCode) }

    init?(shortcutString raw: String) {
        guard let (flags, keyCode) = ShortcutSpelling.parse(raw), let keyCode else { return nil }
        self.init(keyCode: keyCode, flags: flags)
    }
}

/// Also reads the `keyCode`/`modifiers` object written before shortcuts
/// were spelled out as strings.
extension Shortcut: Codable {
    private enum LegacyCodingKeys: String, CodingKey { case keyCode, modifiers }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let raw = try? container.decode(String.self) {
            guard let parsed = Shortcut(shortcutString: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unrecognized shortcut \"\(raw)\"")
            }
            self = parsed
            return
        }
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.init(
            keyCode: try legacy.decode(UInt16.self, forKey: .keyCode),
            flags: CGEventFlags(rawValue: try legacy.decode(UInt64.self, forKey: .modifiers)))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(shortcutString)
    }
}

/// Bridges to the recorder library's own shortcut type.
extension Shortcut {

    init(_ libraryShortcut: KeyboardShortcuts.Shortcut) {
        var flags: CGEventFlags = []
        let modifiers = libraryShortcut.modifiers
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        self.init(keyCode: UInt16(libraryShortcut.carbonKeyCode), flags: flags)
    }

    var libraryShortcut: KeyboardShortcuts.Shortcut {
        var carbonModifiers = 0
        if flags.contains(.maskCommand) { carbonModifiers |= cmdKey }
        if flags.contains(.maskShift) { carbonModifiers |= shiftKey }
        if flags.contains(.maskControl) { carbonModifiers |= controlKey }
        if flags.contains(.maskAlternate) { carbonModifiers |= optionKey }
        return KeyboardShortcuts.Shortcut(carbonKeyCode: Int(keyCode), carbonModifiers: carbonModifiers)
    }
}

/// The config file's key names, such as `a`, `4`, `space`. Fixed key codes,
/// not the active keyboard layout, so a saved shortcut means the same
/// physical key on every Mac.
enum KeyNames {

    static func canonicalName(for keyCode: UInt16) -> String {
        canonicalNamesByKeyCode[keyCode] ?? "keycode\(keyCode)"
    }

    static func keyCode(forCanonicalName name: String) -> UInt16? {
        if let known = keyCodesByCanonicalName[name] { return known }
        guard name.hasPrefix("keycode") else { return nil }
        return UInt16(name.dropFirst("keycode".count))
    }

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeyCodes.contains(keyCode)
    }

    private static let functionKeyCodes: Set<UInt16> = Set(
        [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ].map(UInt16.init))

    private static let canonicalKeyTable: [(UInt16, String)] = [
        (UInt16(kVK_ANSI_A), "a"), (UInt16(kVK_ANSI_B), "b"), (UInt16(kVK_ANSI_C), "c"),
        (UInt16(kVK_ANSI_D), "d"), (UInt16(kVK_ANSI_E), "e"), (UInt16(kVK_ANSI_F), "f"),
        (UInt16(kVK_ANSI_G), "g"), (UInt16(kVK_ANSI_H), "h"), (UInt16(kVK_ANSI_I), "i"),
        (UInt16(kVK_ANSI_J), "j"), (UInt16(kVK_ANSI_K), "k"), (UInt16(kVK_ANSI_L), "l"),
        (UInt16(kVK_ANSI_M), "m"), (UInt16(kVK_ANSI_N), "n"), (UInt16(kVK_ANSI_O), "o"),
        (UInt16(kVK_ANSI_P), "p"), (UInt16(kVK_ANSI_Q), "q"), (UInt16(kVK_ANSI_R), "r"),
        (UInt16(kVK_ANSI_S), "s"), (UInt16(kVK_ANSI_T), "t"), (UInt16(kVK_ANSI_U), "u"),
        (UInt16(kVK_ANSI_V), "v"), (UInt16(kVK_ANSI_W), "w"), (UInt16(kVK_ANSI_X), "x"),
        (UInt16(kVK_ANSI_Y), "y"), (UInt16(kVK_ANSI_Z), "z"),
        (UInt16(kVK_ANSI_0), "0"), (UInt16(kVK_ANSI_1), "1"), (UInt16(kVK_ANSI_2), "2"),
        (UInt16(kVK_ANSI_3), "3"), (UInt16(kVK_ANSI_4), "4"), (UInt16(kVK_ANSI_5), "5"),
        (UInt16(kVK_ANSI_6), "6"), (UInt16(kVK_ANSI_7), "7"), (UInt16(kVK_ANSI_8), "8"),
        (UInt16(kVK_ANSI_9), "9"),
        (UInt16(kVK_Return), "return"), (UInt16(kVK_Tab), "tab"), (UInt16(kVK_Space), "space"),
        (UInt16(kVK_Delete), "delete"), (UInt16(kVK_ForwardDelete), "forwarddelete"),
        (UInt16(kVK_Escape), "escape"), (UInt16(kVK_Help), "help"),
        (UInt16(kVK_Home), "home"), (UInt16(kVK_End), "end"),
        (UInt16(kVK_PageUp), "pageup"), (UInt16(kVK_PageDown), "pagedown"),
        (UInt16(kVK_LeftArrow), "left"), (UInt16(kVK_RightArrow), "right"),
        (UInt16(kVK_UpArrow), "up"), (UInt16(kVK_DownArrow), "down"),
        (UInt16(kVK_ANSI_Backslash), "backslash"), (UInt16(kVK_ANSI_Grave), "backtick"),
        (UInt16(kVK_ANSI_Comma), "comma"), (UInt16(kVK_ANSI_Equal), "equal"),
        (UInt16(kVK_ANSI_Minus), "minus"), (UInt16(kVK_ANSI_Period), "period"),
        (UInt16(kVK_ANSI_Quote), "quote"), (UInt16(kVK_ANSI_Semicolon), "semicolon"),
        (UInt16(kVK_ANSI_Slash), "slash"),
        (UInt16(kVK_ANSI_LeftBracket), "leftbracket"), (UInt16(kVK_ANSI_RightBracket), "rightbracket"),
        (UInt16(kVK_F1), "f1"), (UInt16(kVK_F2), "f2"), (UInt16(kVK_F3), "f3"),
        (UInt16(kVK_F4), "f4"), (UInt16(kVK_F5), "f5"), (UInt16(kVK_F6), "f6"),
        (UInt16(kVK_F7), "f7"), (UInt16(kVK_F8), "f8"), (UInt16(kVK_F9), "f9"),
        (UInt16(kVK_F10), "f10"), (UInt16(kVK_F11), "f11"), (UInt16(kVK_F12), "f12"),
        (UInt16(kVK_F13), "f13"), (UInt16(kVK_F14), "f14"), (UInt16(kVK_F15), "f15"),
        (UInt16(kVK_F16), "f16"), (UInt16(kVK_F17), "f17"), (UInt16(kVK_F18), "f18"),
        (UInt16(kVK_F19), "f19"), (UInt16(kVK_F20), "f20"),
    ]

    private static let canonicalNamesByKeyCode: [UInt16: String] =
        Dictionary(uniqueKeysWithValues: canonicalKeyTable)
    private static let keyCodesByCanonicalName: [String: UInt16] =
        Dictionary(uniqueKeysWithValues: canonicalKeyTable.map { ($0.1, $0.0) })
}
