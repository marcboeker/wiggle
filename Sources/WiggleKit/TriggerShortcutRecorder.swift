import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records the trigger shortcut. The KeyboardShortcuts recorder cannot
/// record modifiers alone, such as the Hyper key.
///
/// A click starts recording. A key combination, or modifiers pressed and
/// released on their own, end it. Escape, a second click, or a click
/// elsewhere cancel it.
@MainActor
final class TriggerShortcutRecorder: NSButton {

    var shortcut: TriggerShortcut { didSet { updateTitle() } }
    var onChange: ((TriggerShortcut) -> Void)?

    private var recording: TriggerShortcutRecording? {
        didSet {
            updateTitle()
            // Wiggle's own event tap must not open the overlay while this records.
            if (oldValue == nil) != (recording == nil) {
                NotificationCenter.default.post(
                    name: .recorderActiveStatusDidChange, object: nil, userInfo: ["isActive": recording != nil])
            }
        }
    }

    init(shortcut: TriggerShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .push
        target = self
        action = #selector(toggleRecording)
        setAccessibilityLabel("Trigger Shortcut")
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        recording = nil
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { recording = nil }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func toggleRecording() {
        if recording == nil, window?.makeFirstResponder(self) == true {
            recording = TriggerShortcutRecording()
        } else {
            window?.makeFirstResponder(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard var recording else { return super.keyDown(with: event) }
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if Int(event.keyCode) == kVK_Escape, flags.intersection(Shortcut.allowedModifiers).isEmpty {
            window?.makeFirstResponder(nil)
            return
        }
        if event.isARepeat { return }
        guard let recorded = recording.keyDown(event.keyCode, flags: flags) else {
            self.recording = recording
            NSSound.beep()
            return
        }
        finish(recorded)
    }

    /// A combination with Command reaches the window's key equivalents
    /// before `keyDown`, and every view in the window is asked.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording != nil, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard var recording else { return super.flagsChanged(with: event) }
        let recorded = recording.flagsChanged(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
        self.recording = recording
        if let recorded { finish(recorded) }
    }

    private func finish(_ recorded: TriggerShortcut) {
        window?.makeFirstResponder(nil)
        shortcut = recorded
        onChange?(recorded)
    }

    private func updateTitle() {
        guard let recording else {
            title = shortcut.displayString
            return
        }
        title = recording.held.isEmpty ? "Press keys…" : TriggerShortcut.symbols(for: recording.held)
    }
}

extension Notification.Name {
    /// KeyboardShortcuts posts this when its recorder starts or stops
    /// holding the keyboard, and `TriggerShortcutRecorder` posts it too. The
    /// library keeps the name internal, so it is mirrored here.
    static let recorderActiveStatusDidChange = Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")
}

struct TriggerShortcutField: NSViewRepresentable {
    let shortcut: TriggerShortcut
    let onChange: (TriggerShortcut) -> Void

    func makeNSView(context: Context) -> TriggerShortcutRecorder {
        let recorder = TriggerShortcutRecorder(shortcut: shortcut)
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        return recorder
    }

    func updateNSView(_ recorder: TriggerShortcutRecorder, context: Context) {
        recorder.onChange = onChange
        recorder.shortcut = shortcut
    }
}
