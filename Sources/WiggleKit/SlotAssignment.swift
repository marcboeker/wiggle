import AppKit

/// An app always shows its own icon, so it carries no face.
enum SlotAssignment: Equatable {
    case app(AppRef)
    /// `face` is nil only for a slot from a config written before every
    /// non-app slot needed one.
    case action(SlotAction, face: SlotFace?)
}

enum SlotAction: Equatable {
    case shortcut(Shortcut)
    /// A shortcut from the Shortcuts app.
    case appleShortcut(AppleShortcutRef)
    case appleScript(String)
}

enum SlotFace: Equatable {
    case emoji(String)
    case image(SlotImage)

    /// Keeps only the first grapheme cluster of what the emoji picker
    /// inserted, so a slot never holds more than one glyph.
    static func normalizedEmoji(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map(String.init)
    }
}

/// An installed application, kept by bundle identifier so a slot survives
/// the app moving on disk or being reinstalled.
struct AppRef: Codable, Equatable {
    var bundleIdentifier: String
    var name: String

    var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    @MainActor private static var iconCache: [String: NSImage] = [:]

    /// Cached, because the wheel draws it on every hover change. A missing
    /// app gets Launch Services' generic icon.
    @MainActor var icon: NSImage {
        if let cached = AppRef.iconCache[bundleIdentifier] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url?.path ?? "/nonexistent")
        AppRef.iconCache[bundleIdentifier] = icon
        return icon
    }
}

/// Kept by name, the only handle the `shortcuts` tool accepts.
struct AppleShortcutRef: Codable, Equatable {
    var name: String
}

/// An image face encodes nothing and decodes as no face: its PNG lives next
/// to the config, where `SlotStore` reads and writes it.
extension SlotAssignment: Codable {
    private enum Kind: String, Codable { case shortcut, app, appleShortcut, appleScript }
    /// The key stays `label` from before emoji replaced free-text labels.
    private enum CodingKeys: String, CodingKey {
        case kind, shortcut, emoji = "label", app, appleShortcut, script
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action: SlotAction
        switch try container.decode(Kind.self, forKey: .kind) {
        case .app:
            self = .app(try container.decode(AppRef.self, forKey: .app))
            return
        case .shortcut:
            action = .shortcut(try container.decode(Shortcut.self, forKey: .shortcut))
        case .appleShortcut:
            action = .appleShortcut(try container.decode(AppleShortcutRef.self, forKey: .appleShortcut))
        case .appleScript:
            action = .appleScript(try container.decode(String.self, forKey: .script))
        }
        let emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        self = .action(action, face: emoji.map(SlotFace.emoji))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let ref):
            try container.encode(Kind.app, forKey: .kind)
            try container.encode(ref, forKey: .app)
        case .action(let action, let face):
            switch action {
            case .shortcut(let shortcut):
                try container.encode(Kind.shortcut, forKey: .kind)
                try container.encode(shortcut, forKey: .shortcut)
            case .appleShortcut(let ref):
                try container.encode(Kind.appleShortcut, forKey: .kind)
                try container.encode(ref, forKey: .appleShortcut)
            case .appleScript(let source):
                try container.encode(Kind.appleScript, forKey: .kind)
                try container.encode(source, forKey: .script)
            }
            if case .emoji(let emoji)? = face { try container.encode(emoji, forKey: .emoji) }
        }
    }
}

extension SlotAssignment {
    func run() {
        switch self {
        case .app(let ref):
            guard let url = ref.url else {
                NSLog("wiggle: cannot find \(ref.name) (\(ref.bundleIdentifier))")
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .action(.shortcut(let shortcut), _):
            KeyPoster.post(shortcut)
        case .action(.appleShortcut(let ref), _):
            launch(shortcutsTool, ["run", ref.name])
        case .action(.appleScript(let source), _):
            // Over stdin, so a multi-line script needs no escaping.
            launch("/usr/bin/osascript", ["-"], stdin: Data(source.utf8))
        }
    }
}

private let shortcutsTool = "/usr/bin/shortcuts"

@discardableResult
private func launch(_ path: String, _ arguments: [String], stdin: Data? = nil, stdout: Pipe? = nil) -> Process? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let input = stdin.map { _ in Pipe() }
    process.standardInput = input
    if let stdout {
        process.standardOutput = stdout
        process.standardError = Pipe()
    }
    // An app launched from Finder has no terminal for the tool's own error.
    process.terminationHandler = { process in
        guard process.terminationStatus != 0 else { return }
        NSLog("wiggle: \(path) \(arguments.first ?? "") exited with status \(process.terminationStatus)")
    }
    do {
        try process.run()
    } catch {
        NSLog("wiggle: cannot run \(path) \(arguments.joined(separator: " ")): \(error.localizedDescription)")
        return nil
    }
    if let input, let stdin {
        input.fileHandleForWriting.write(stdin)
        try? input.fileHandleForWriting.close()
    }
    return process
}

enum AppleShortcutCatalog {
    static func list(completion: @escaping @MainActor ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let pipe = Pipe()
            var names: [String] = []
            if let process = launch(shortcutsTool, ["list"], stdout: pipe) {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                names = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n")
                    .map(String.init)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(names) } }
        }
    }
}
