import AppKit
import KeyboardShortcuts

/// In tab bar order.
enum SlotEditorTab: CaseIterable {
    case app, previousApp, keyboardShortcut, appleShortcut, appleScript

    var title: String {
        switch self {
        case .app: "App"
        case .previousApp: "Previous App"
        case .keyboardShortcut: "Keyboard Shortcut"
        case .appleShortcut: "Apple Shortcut"
        case .appleScript: "AppleScript"
        }
    }
}

enum SlotFaceKind: CaseIterable {
    case emoji, image

    var title: String {
        switch self {
        case .emoji: "Emoji"
        case .image: "Image"
        }
    }
}

/// Each tab keeps its own input, so switching tabs loses nothing.
struct SlotDraft: Equatable {
    var tab = SlotEditorTab.app
    var app: AppRef?
    var shortcut: Shortcut?
    var appleShortcut: AppleShortcutRef?
    var script = ""
    var emoji: String?
    var image: SlotImage?
    var faceKind = SlotFaceKind.emoji
    /// Kept across tabs, like the face.
    var color: SlotColor?

    init(_ assignment: SlotAssignment?, color: SlotColor? = nil) {
        self.color = color
        switch assignment {
        case nil:
            break
        case .app(let ref):
            app = ref
        case .previousApp:
            tab = .previousApp
        case .action(let action, let face):
            switch action {
            case .shortcut(let value):
                tab = .keyboardShortcut
                shortcut = value
            case .appleShortcut(let ref):
                tab = .appleShortcut
                appleShortcut = ref
            case .appleScript(let source):
                tab = .appleScript
                script = source
            }
            switch face {
            case .emoji(let value)?:
                emoji = value
            case .image(let value)?:
                image = value
                faceKind = .image
            case nil:
                break
            }
        }
    }

    /// `nil` while the selected tab's input or the selected face is missing.
    var assignment: SlotAssignment? {
        let action: SlotAction
        switch tab {
        case .app:
            return app.map(SlotAssignment.app)
        case .previousApp:
            return .previousApp
        case .keyboardShortcut:
            guard let shortcut else { return nil }
            action = .shortcut(shortcut)
        case .appleShortcut:
            guard let appleShortcut else { return nil }
            action = .appleShortcut(appleShortcut)
        case .appleScript:
            guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            action = .appleScript(script)
        }
        let face: SlotFace?
        switch faceKind {
        case .emoji: face = emoji.map(SlotFace.emoji)
        case .image: face = image.map(SlotFace.image)
        }
        return face.map { .action(action, face: $0) }
    }

    var slot: Slot? { assignment.map { Slot($0, color: color) } }
}

/// Edits a `SlotDraft`; nothing reaches the store until Save. Clear Slot
/// empties the slot at once.
@MainActor
final class SlotEditorSheet: NSObject {
    let window: NSWindow
    var onSave: ((Slot) -> Void)?
    var onClear: (() -> Void)?

    private var draft: SlotDraft { didSet { draftChanged() } }

    private let tabView = NSTabView()
    private let appIcon = NSImageView()
    private let appName = NSTextField(labelWithString: "")
    private let appleShortcutTable = NSTableView()
    private var appleShortcutNames: [String] = []
    private let scriptView = NSTextView()
    private let faceKindControl = NSSegmentedControl(
        labels: SlotFaceKind.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let emojiWell = EmojiWell()
    private let imageWell = NSImageView()
    private let faceAppIcon = NSImageView()
    private let faceHint = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var colorSwatches: [ColorSwatch] = []

    /// Allows every shortcut: Wiggle posts it rather than registering it,
    /// and the default policy refuses the ones in Wiggle's own Edit menu,
    /// such as ⌘C and ⌘V.
    private lazy var recorder: KeyboardShortcuts.RecorderCocoa = {
        let recorder = KeyboardShortcuts.RecorderCocoa(
            shortcut: draft.shortcut?.libraryShortcut,
            onChange: { [weak self] libraryShortcut in
                self?.draft.shortcut = libraryShortcut.map(Shortcut.init)
            })
        recorder.conflictPolicy = .allowAll
        return recorder
    }()

    init(label: String, slot: Slot?) {
        draft = SlotDraft(slot?.assignment, color: slot?.color)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 480, height: 460)
        window.title = label
        super.init()
        buildContent(isOccupied: slot != nil)
        draftChanged()
        AppleShortcutCatalog.list { [weak self] names in self?.showAppleShortcuts(names) }
    }

    func present(on parent: NSWindow, completion: @escaping () -> Void) {
        parent.beginSheet(window) { _ in completion() }
        // AppKit makes the first control in the key view loop first
        // responder, which would arm the recorder before the user clicked
        // anything.
        window.makeFirstResponder(nil)
    }

    private func buildContent(isOccupied: Bool) {
        tabView.translatesAutoresizingMaskIntoConstraints = false
        for tab in SlotEditorTab.allCases {
            let item = NSTabViewItem(identifier: nil)
            item.label = tab.title
            item.view = editor(for: tab)
            tabView.addTabViewItem(item)
        }
        tabView.selectTabViewItem(at: SlotEditorTab.allCases.firstIndex(of: draft.tab)!)
        tabView.delegate = self

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let iconSection = makeIconSection()
        let colorSection = makeColorSection()

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        guard let content = window.contentView else { return }
        for view in [tabView, separator, iconSection, colorSection, buttons] { content.addSubview(view) }
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            separator.topAnchor.constraint(equalTo: tabView.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            iconSection.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            iconSection.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            iconSection.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            colorSection.topAnchor.constraint(equalTo: iconSection.bottomAnchor, constant: 12),
            colorSection.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            colorSection.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: colorSection.bottomAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])

        if isOccupied {
            let clearButton = NSButton(title: "Clear Slot", target: self, action: #selector(clear))
            clearButton.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(clearButton)
            NSLayoutConstraint.activate([
                clearButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                clearButton.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            ])
        }
    }

    private func editor(for tab: SlotEditorTab) -> NSView {
        switch tab {
        case .app: makeAppEditor()
        case .previousApp: makePreviousAppEditor()
        case .keyboardShortcut: makeShortcutEditor()
        case .appleShortcut: makeAppleShortcutEditor()
        case .appleScript: makeAppleScriptEditor()
        }
    }

    private func makeAppEditor() -> NSView {
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appName.alignment = .center
        let chooseButton = NSButton(title: "Choose App…", target: self, action: #selector(chooseApp))
        let stack = NSStackView(views: [appIcon, appName, chooseButton])
        stack.orientation = .vertical
        stack.spacing = 10
        NSLayoutConstraint.activate([
            appIcon.widthAnchor.constraint(equalToConstant: 64),
            appIcon.heightAnchor.constraint(equalToConstant: 64),
        ])
        return centered(stack)
    }

    private func makePreviousAppEditor() -> NSView {
        let icon = NSImageView(image: OverlayText.previousAppSymbol(color: .secondaryLabelColor) ?? NSImage())
        let text = NSTextField(
            wrappingLabelWithString: "Switches back to the app you used before the one in front, like ⌘⇥ does.")
        text.alignment = .center
        text.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [icon, text])
        stack.orientation = .vertical
        stack.spacing = 10
        NSLayoutConstraint.activate([text.widthAnchor.constraint(lessThanOrEqualToConstant: 360)])
        return centered(stack)
    }

    private func makeShortcutEditor() -> NSView {
        let hint = NSTextField(labelWithString: "Click the field, then press the key combination.")
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [recorder, hint])
        stack.orientation = .vertical
        stack.spacing = 10
        return centered(stack)
    }

    private func makeAppleShortcutEditor() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        appleShortcutTable.addTableColumn(column)
        appleShortcutTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        appleShortcutTable.headerView = nil
        appleShortcutTable.dataSource = self
        appleShortcutTable.delegate = self
        appleShortcutTable.target = self
        appleShortcutTable.doubleAction = #selector(save)
        appleShortcutTable.setAccessibilityLabel("Apple Shortcuts")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = appleShortcutTable
        return pinned(scroll)
    }

    private func makeAppleScriptEditor() -> NSView {
        scriptView.string = draft.script
        scriptView.isRichText = false
        scriptView.allowsUndo = true
        scriptView.isAutomaticQuoteSubstitutionEnabled = false
        scriptView.isAutomaticDashSubstitutionEnabled = false
        scriptView.isAutomaticTextReplacementEnabled = false
        scriptView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scriptView.isVerticallyResizable = true
        scriptView.isHorizontallyResizable = false
        scriptView.autoresizingMask = [.width]
        scriptView.textContainer?.widthTracksTextView = true
        scriptView.delegate = self
        scriptView.setAccessibilityTitle("AppleScript Source")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = scriptView
        return pinned(scroll)
    }

    private func makeIconSection() -> NSView {
        faceKindControl.target = self
        faceKindControl.action = #selector(faceKindChanged)
        faceKindControl.setAccessibilityTitle("Slot Icon Kind")

        emojiWell.emoji = draft.emoji
        emojiWell.onPick = { [weak self] emoji in self?.draft.emoji = emoji }

        imageWell.image = draft.image?.image
        imageWell.isEditable = true
        imageWell.allowsCutCopyPaste = true
        imageWell.imageFrameStyle = .grayBezel
        imageWell.imageScaling = .scaleProportionallyUpOrDown
        imageWell.target = self
        imageWell.action = #selector(imageWellChanged)
        imageWell.setAccessibilityTitle("Slot Icon")

        faceAppIcon.imageScaling = .scaleProportionallyUpOrDown
        faceHint.textColor = .secondaryLabelColor

        let wells = NSView()
        for well in [emojiWell, imageWell, faceAppIcon] {
            well.translatesAutoresizingMaskIntoConstraints = false
            wells.addSubview(well)
            NSLayoutConstraint.activate([
                well.leadingAnchor.constraint(equalTo: wells.leadingAnchor),
                well.trailingAnchor.constraint(equalTo: wells.trailingAnchor),
                well.topAnchor.constraint(equalTo: wells.topAnchor),
                well.bottomAnchor.constraint(equalTo: wells.bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            wells.widthAnchor.constraint(equalToConstant: 56),
            wells.heightAnchor.constraint(equalToConstant: 56),
        ])

        let stack = NSStackView(views: [NSTextField(labelWithString: "Icon:"), faceKindControl, wells, faceHint])
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// "None" first, then every color in declaration order.
    private func makeColorSection() -> NSView {
        colorSwatches = ([nil] + SlotColor.allCases.map(Optional.some)).map { color in
            let swatch = ColorSwatch(color: color)
            swatch.target = self
            swatch.action = #selector(colorPicked(_:))
            return swatch
        }
        let stack = NSStackView(views: [NSTextField(labelWithString: "Color:")] + colorSwatches)
        stack.spacing = 8
        stack.setCustomSpacing(12, after: stack.views[0])
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func centered(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func pinned(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        return container
    }

    private func draftChanged() {
        let isPreviousApp = draft.tab == .previousApp
        let isApp = draft.tab == .app || isPreviousApp
        appIcon.image = draft.app?.icon
        appName.stringValue = draft.app?.name ?? "No app chosen"

        faceKindControl.isEnabled = !isApp
        faceKindControl.selectedSegment = isApp ? -1 : SlotFaceKind.allCases.firstIndex(of: draft.faceKind)!
        emojiWell.isEnabled = !isApp
        faceAppIcon.image = isPreviousApp
            ? OverlayText.previousAppSymbol(color: .secondaryLabelColor) : draft.app?.icon
        faceAppIcon.isHidden = !isApp
        emojiWell.isHidden = isApp || draft.faceKind != .emoji
        imageWell.isHidden = isApp || draft.faceKind != .image
        switch (isApp, draft.faceKind) {
        case (true, _) where isPreviousApp:
            faceHint.stringValue = "The wheel shows the previous app's icon."
        case (true, _): faceHint.stringValue = "An app slot always shows the app's icon."
        case (false, .emoji): faceHint.stringValue = "Click the well to pick an emoji."
        case (false, .image): faceHint.stringValue = "Paste an image with ⌘V or drop one on the well."
        }

        for swatch in colorSwatches { swatch.isPicked = swatch.color == draft.color }

        saveButton.isEnabled = draft.assignment != nil
    }

    private func showAppleShortcuts(_ names: [String]) {
        appleShortcutNames = names
        appleShortcutTable.reloadData()
        guard let name = draft.appleShortcut?.name, let row = names.firstIndex(of: name) else { return }
        appleShortcutTable.selectRowIndexes([row], byExtendingSelection: false)
        appleShortcutTable.scrollRowToVisible(row)
    }

    @objc private func chooseApp() {
        let picker = NSOpenPanel()
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowedContentTypes = [.application]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.prompt = "Choose"
        picker.message = "Choose an app for \(window.title)"
        picker.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = picker.url,
                let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
            else { return }
            let name = FileManager.default.displayName(atPath: url.path)
            self?.draft.app = AppRef(bundleIdentifier: bundleIdentifier, name: name)
        }
    }

    @objc private func faceKindChanged() {
        draft.faceKind = SlotFaceKind.allCases[faceKindControl.selectedSegment]
        // The well takes the focus, so ⌘V pastes at once.
        if draft.faceKind == .image { window.makeFirstResponder(imageWell) }
    }

    /// Shows the stored PNG, exactly what the wheel will draw.
    @objc private func imageWellChanged() {
        draft.image = imageWell.image.flatMap(SlotImage.init)
        imageWell.image = draft.image?.image
    }

    @objc private func colorPicked(_ sender: ColorSwatch) {
        draft.color = sender.color
    }

    @objc private func save() {
        guard let slot = draft.slot else { return }
        onSave?(slot)
        end()
    }

    @objc private func clear() {
        onClear?()
        end()
    }

    @objc private func cancel() { end() }

    private func end() {
        window.sheetParent?.endSheet(window)
    }
}

extension SlotEditorSheet: NSTabViewDelegate {
    /// `NSTabView` hands the focus to the new tab's first control when the
    /// old tab held it, which would arm the recorder, and a recorder left
    /// recording on a hidden tab keeps swallowing keys.
    func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        window.makeFirstResponder(nil)
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let tabViewItem else { return }
        draft.tab = SlotEditorTab.allCases[tabView.indexOfTabViewItem(tabViewItem)]
    }
}

extension SlotEditorSheet: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { appleShortcutNames.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("AppleShortcutCell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
            ?? NSTextField(labelWithString: "")
        field.identifier = identifier
        field.isEditable = false
        field.isBordered = false
        field.drawsBackground = false
        field.stringValue = appleShortcutNames[row]
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = appleShortcutTable.selectedRow
        draft.appleShortcut = appleShortcutNames.indices.contains(row)
            ? AppleShortcutRef(name: appleShortcutNames[row]) : nil
    }
}

extension SlotEditorSheet: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        draft.script = scriptView.string
    }
}

/// A click opens the character palette, and what it inserts becomes the
/// emoji. Delete clears it. The view is its own text input client instead of
/// an `NSTextField`: the palette takes key status from the sheet, and the
/// recorder in the same sheet answers every resign-key with
/// `makeFirstResponder(nil)`, which dropped a text field's field editor and
/// the palette's insertion with it.
@MainActor
private final class EmojiWell: NSView, @preconcurrency NSTextInputClient {
    var emoji: String? {
        didSet {
            needsDisplay = true
            setAccessibilityValue(emoji ?? "")
        }
    }
    var onPick: ((String?) -> Void)?
    var isEnabled = true {
        didSet {
            needsDisplay = true
            setAccessibilityEnabled(isEnabled)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityTitle("Slot Emoji")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { isEnabled }

    /// The window is not key exactly while the palette is open, and the
    /// insertion must still find this view.
    override func resignFirstResponder() -> Bool { window?.isKeyWindow ?? true }

    override func mouseDown(with event: NSEvent) { openPalette() }

    override func accessibilityPerformPress() -> Bool {
        openPalette()
        return isEnabled
    }

    private func openPalette() {
        guard isEnabled, let window, window.makeFirstResponder(self) else { return }
        NSApp.orderFrontCharacterPalette(self)
    }

    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.stroke()

        let alpha: CGFloat = isEnabled ? (emoji == nil ? 0.3 : 1) : 0.25
        OverlayText.draw(emoji ?? "🙂", in: bounds, size: 28, alpha: alpha, weight: .regular, color: .labelColor)
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    private func pick(_ emoji: String?) {
        self.emoji = emoji
        onPick?(emoji)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        guard let picked = SlotFace.normalizedEmoji(text) else { return }
        pick(picked)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(deleteBackward(_:)) || selector == #selector(deleteForward(_:)) {
            pick(nil)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { false }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { 0 }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
        -> NSAttributedString?
    { nil }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }
}

/// A round color chip; the one in use gets a ring. `color` is `nil` for the
/// slashed "None" chip.
@MainActor
private final class ColorSwatch: NSButton {
    static let side: CGFloat = 20

    let color: SlotColor?
    var isPicked = false {
        didSet {
            needsDisplay = true
            setAccessibilityValue(isPicked ? "Selected" : "")
        }
    }

    init(color: SlotColor?) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        title = ""
        isBordered = false
        let name = color?.title ?? "None"
        toolTip = name
        setAccessibilityTitle(name)
        widthAnchor.constraint(equalToConstant: Self.side).isActive = true
        heightAnchor.constraint(equalToConstant: Self.side).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let chip = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        if let color {
            color.color.setFill()
            chip.fill()
        } else {
            NSColor.separatorColor.setStroke()
            chip.lineWidth = 1
            chip.stroke()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: bounds.minX + 5, y: bounds.maxY - 5))
            slash.line(to: NSPoint(x: bounds.maxX - 5, y: bounds.minY + 5))
            NSColor.secondaryLabelColor.setStroke()
            slash.lineWidth = 1
            slash.stroke()
        }
        if isPicked {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            NSColor.labelColor.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
