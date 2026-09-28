import AppKit

/// The slots and settings, persisted to `~/.config/wiggle/config.json`. An
/// image face lives in `icons/<SlotID.fileName>.png` next to it.
///
/// The file is written on a background queue, because the event tap
/// callback must return quickly.
final class SlotStore {

    /// Version 4: one dictionary per ring, keyed by slot number. A missing
    /// key means an empty slot.
    private struct File: Codable {
        var version: Int
        var rings: [[Int: LenientAssignment]]
        var triggers: [String]?
        var overlayOpacity: CGFloat?
        var showMenuBarItem: Bool?
        var overlayAppearance: String?
    }

    /// `nil` for a slot this version cannot read, such as a typo in a hand
    /// edited shortcut, so that it does not take the other slots with it.
    private struct LenientAssignment: Codable {
        var value: SlotAssignment?

        init(_ value: SlotAssignment) { self.value = value }

        init(from decoder: Decoder) throws {
            value = try? SlotAssignment(from: decoder)
        }

        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }

    /// Version 3: nine slots, 1...8 around and 9 the centre. The older
    /// formats below are read once and upgraded on the next save.
    private struct V3File: Codable {
        var version: Int
        var slots: [Int: SlotAssignment]
        var triggers: [String]?
    }

    private struct LegacyArrayFile: Codable {
        var version: Int
        var slots: [SlotAssignment?]
    }

    private struct LegacyBareShortcutFile: Codable {
        var version: Int
        var slots: [Shortcut?]
    }

    /// The v3 slot number of each array position in a legacy file, so an
    /// assignment keeps its physical position.
    private static let legacySlotNumberByOldIndex = [8, 1, 2, 7, 9, 3, 6, 5, 4]

    static let defaultURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/wiggle/config.json")

    private(set) var slots: [SlotID: SlotAssignment] = [:]

    /// Never empty: without a trigger the overlay cannot open.
    private(set) var triggers = TriggerKind.defaults

    private(set) var overlayOpacity = Config.defaultOverlayOpacity

    private(set) var showsMenuBarItem = true

    private(set) var overlayAppearance = Config.defaultOverlayAppearance

    private let url: URL
    private let iconsURL: URL
    private let writeQueue = DispatchQueue(label: "com.marcboeker.wiggle.slotstore")

    init(url: URL = SlotStore.defaultURL) {
        self.url = url
        iconsURL = url.deletingLastPathComponent().appendingPathComponent("icons")
        load()
        attachImages()
    }

    var hasOuterRingAssignment: Bool {
        slots.keys.contains { if case .outer = $0 { return true }; return false }
    }

    subscript(id: SlotID) -> SlotAssignment? { slots[id] }

    func assign(_ assignment: SlotAssignment?, to id: SlotID) {
        slots[id] = assignment
        save()
    }

    func swap(_ source: SlotID, with destination: SlotID) {
        guard source != destination else { return }
        (slots[source], slots[destination]) = (slots[destination], slots[source])
        save()
    }

    func setTriggers(_ kinds: Set<TriggerKind>) {
        guard !kinds.isEmpty else { return }
        triggers = kinds
        save()
    }

    func setOverlayOpacity(_ opacity: CGFloat) {
        overlayOpacity = SlotStore.clampedOpacity(opacity)
        save()
    }

    func setShowsMenuBarItem(_ show: Bool) {
        showsMenuBarItem = show
        save()
    }

    func setOverlayAppearance(_ appearance: OverlayAppearance) {
        overlayAppearance = appearance
        save()
    }

    /// For tests.
    func waitForWrites() {
        writeQueue.sync {}
    }

    private func iconURL(for id: SlotID) -> URL {
        iconsURL.appendingPathComponent("\(id.fileName).png")
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let file = try? JSONDecoder().decode(File.self, from: data) {
            let rings = file.rings.map { $0.compactMapValues(\.value) }
            if rings.map(\.count) != file.rings.map(\.count) {
                // The next save drops the slots that could not be read.
                keepAside(data, reason: "has slots that cannot be read")
            }
            slots = SlotStore.clampedRings(rings)
            triggers = SlotStore.knownTriggers(file.triggers)
            overlayOpacity = file.overlayOpacity.map(SlotStore.clampedOpacity) ?? Config.defaultOverlayOpacity
            showsMenuBarItem = file.showMenuBarItem ?? true
            overlayAppearance = file.overlayAppearance.flatMap(OverlayAppearance.init(rawValue:))
                ?? Config.defaultOverlayAppearance
            return
        }
        if let file = try? JSONDecoder().decode(V3File.self, from: data) {
            slots = SlotStore.migrateV3(file.slots)
            triggers = SlotStore.knownTriggers(file.triggers)
            return
        }
        if let legacy = try? JSONDecoder().decode(LegacyArrayFile.self, from: data) {
            slots = SlotStore.migrateV3(SlotStore.migrateLegacyArray(legacy.slots))
            return
        }
        if let legacy = try? JSONDecoder().decode(LegacyBareShortcutFile.self, from: data) {
            slots = SlotStore.migrateV3(
                SlotStore.migrateLegacyArray(legacy.slots.map { $0.map { .action(.shortcut($0), face: nil) } }))
            return
        }
        // Overwriting an unreadable file would throw away assignments the
        // user may still rescue by hand.
        let backup = backupURL
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        NSLog("wiggle: \(url.path) is not readable, moved it to \(backup.lastPathComponent)")
    }

    private var backupURL: URL { url.appendingPathExtension("broken") }

    private func keepAside(_ data: Data, reason: String) {
        do {
            try data.write(to: backupURL, options: .atomic)
            NSLog("wiggle: \(url.path) \(reason), kept a copy in \(backupURL.lastPathComponent)")
        } catch {
            NSLog("wiggle: \(url.path) \(reason), and no copy could be kept: \(error.localizedDescription)")
        }
    }

    /// The JSON has no trace of an image face, so the PNG file decides. The
    /// next save deletes a file left over at an app slot.
    private func attachImages() {
        for case (let id, .action(let action, _)) in slots {
            guard let png = try? Data(contentsOf: iconURL(for: id)), let image = SlotImage(png: png)
            else { continue }
            slots[id] = .action(action, face: .image(image))
        }
    }

    /// Drops what does not fit the wheel, so a file from another version
    /// still loads.
    private static func clampedRings(_ rings: [[Int: SlotAssignment]]) -> [SlotID: SlotAssignment] {
        var result: [SlotID: SlotAssignment] = [:]
        for (ring, slots) in rings.enumerated() where ring < 3 {
            for (number, assignment) in slots {
                guard let id = SlotID(ring: ring, slot: number) else { continue }
                result[id] = assignment
            }
        }
        return result
    }

    /// Skips names written by a newer version, so that such a file still loads.
    private static func knownTriggers(_ names: [String]?) -> Set<TriggerKind> {
        let kinds = Set((names ?? []).compactMap(TriggerKind.init(rawValue:)))
        return kinds.isEmpty ? TriggerKind.defaults : kinds
    }

    private static func clampedOpacity(_ opacity: CGFloat) -> CGFloat {
        min(max(opacity, Config.overlayOpacityRange.lowerBound), Config.overlayOpacityRange.upperBound)
    }

    private static func migrateV3(_ slots: [Int: SlotAssignment]) -> [SlotID: SlotAssignment] {
        var result: [SlotID: SlotAssignment] = [:]
        for (number, assignment) in slots {
            if number == 9 {
                result[.center] = assignment
            } else if SlotID.innerNumbers.contains(number) {
                result[.inner(number)] = assignment
            }
        }
        return result
    }

    private static func migrateLegacyArray(_ loaded: [SlotAssignment?]) -> [Int: SlotAssignment] {
        var assignments: [Int: SlotAssignment] = [:]
        for (index, assignment) in loaded.enumerated() {
            guard let assignment, legacySlotNumberByOldIndex.indices.contains(index) else { continue }
            assignments[legacySlotNumberByOldIndex[index]] = assignment
        }
        return assignments
    }

    /// PNGs go first and stale files last, so a crash in between never
    /// leaves the config pointing at an image that is gone.
    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var rings: [[Int: LenientAssignment]] = [[:], [:], [:]]
        var pngs: [String: Data] = [:]
        for (id, assignment) in slots {
            rings[id.ring][id.number] = LenientAssignment(assignment)
            if case .action(_, face: .image(let image)) = assignment {
                pngs[iconURL(for: id).lastPathComponent] = image.png
            }
        }
        let images = pngs
        let file = File(
            version: 4, rings: rings,
            triggers: TriggerKind.allCases.filter { triggers.contains($0) }.map(\.rawValue),
            overlayOpacity: overlayOpacity, showMenuBarItem: showsMenuBarItem,
            overlayAppearance: overlayAppearance.rawValue)
        guard let data = try? encoder.encode(file) else { return }
        let iconsURL = self.iconsURL
        // An atomic write would replace a symlink, as dotfile managers use,
        // with a plain file.
        let unresolvedURL = self.url
        writeQueue.async {
            let url = unresolvedURL.resolvingSymlinksInPath()
            let files = FileManager.default
            do {
                try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !images.isEmpty { try files.createDirectory(at: iconsURL, withIntermediateDirectories: true) }
                for (name, png) in images {
                    let icon = iconsURL.appendingPathComponent(name)
                    if (try? Data(contentsOf: icon)) != png { try png.write(to: icon, options: .atomic) }
                }
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("wiggle: cannot save \(url.path): \(error.localizedDescription)")
                return
            }
            let present = (try? files.contentsOfDirectory(at: iconsURL, includingPropertiesForKeys: nil)) ?? []
            for icon in present where icon.pathExtension == "png" && images[icon.lastPathComponent] == nil {
                try? files.removeItem(at: icon)
            }
        }
    }
}
