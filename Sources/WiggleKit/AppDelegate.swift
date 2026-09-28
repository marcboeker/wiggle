import AppKit
import ApplicationServices

/// Wires the event tap to the overlay.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private lazy var store = SlotStore(url: AppDelegate.configURL(from: CommandLine.arguments))
    private lazy var overlay = OverlayController(store: store)
    private lazy var settings = SettingsWindowController(store: store)
    private var detectors: [any TriggerDetector] = []
    private var swipeEventFilter: SwipeEventFilter?
    private var needsTouches = false
    private var tap: EventTap?
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var didPrompt = false
    private var blockedUntil: TimeInterval = 0
    private var lastPointerMove: TimeInterval = 0
    private var isStopCheckPending = false
    private var isRecordingShortcut = false
    private var pointerWarpGuard = PointerWarpGuard()

    /// A swallowed press must take its release with it, otherwise the app
    /// below sees a release without a press.
    private var swallowedKeys: Set<Int64> = []
    private var swallowedButtons: Set<Int64> = []

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        rebuildDetectors()
        updateStatusItem()
        overlay.onClose = { [weak self] in self?.startCooldown() }
        overlay.onOpenSettings = { [weak self] in self?.settings.show() }
        overlay.onWarp = { [weak self] target in self?.pointerWarpGuard.begin(target: target) }
        settings.onTriggersChanged = { [weak self] in self?.rebuildDetectors() }
        settings.onMenuBarItemChanged = { [weak self] in self?.updateStatusItem() }

        NotificationCenter.default.addObserver(
            forName: .recorderActiveStatusDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            let isActive = notification.userInfo?["isActive"] as? Bool ?? false
            MainActor.assumeIsolated { self?.isRecordingShortcut = isActive }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        checkPermission()
        let timer = Timer.scheduledTimer(
            timeInterval: Config.permissionCheckInterval, target: self,
            selector: #selector(checkPermission), userInfo: nil, repeats: true)
        timer.tolerance = Config.permissionCheckInterval / 2
        permissionTimer = timer
    }

    private static func configURL(from arguments: [String]) -> URL {
        guard let index = arguments.firstIndex(of: "--config"), index + 1 < arguments.count else {
            return SlotStore.defaultURL
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Reopening Wiggle.app opens Settings, so a user who turned the menu
    /// bar item off can still reach it. `false` keeps AppKit from trying to
    /// reveal a window of its own.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    /// Only drawn while Settings makes Wiggle a regular app. Without it, `⌘Q`
    /// has no `terminate:` to resolve to, and the Edit key equivalents never
    /// reach text views such as the AppleScript editor.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Wiggle", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func updateStatusItem() {
        guard store.showsMenuBarItem else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Wiggle")
        icon?.isTemplate = true
        item.button?.image = icon

        let menu = NSMenu()
        let versionItem = NSMenuItem(title: "Wiggle \(appVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(showSettingsFromMenuBar), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Wiggle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    /// The release tag, stamped into the bundle by `make bundle VERSION=…`;
    /// "main" for a local build.
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "main"
    }

    @objc private func showSettingsFromMenuBar() {
        settings.show()
    }

    /// The user can grant and revoke Accessibility access at any time, so
    /// this runs on a timer.
    @objc private func checkPermission() {
        if AXIsProcessTrusted() {
            if tap == nil { installTap() }
            return
        }
        if tap != nil {
            // A revoked permission leaves the tap dead.
            tap?.stop()
            tap = nil
            overlay.hide()
            NSLog("wiggle: the accessibility permission was taken away")
        }
        guard !didPrompt else { return }
        didPrompt = true
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func installTap() {
        let candidate = EventTap { [weak self] type, event in
            guard let self else { return event }
            return self.handle(type: type, event: event)
        }
        guard candidate.start() else {
            NSLog("wiggle: the event tap could not be created")
            return
        }
        tap = candidate
        NSLog("wiggle: event tap active")
    }

    private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        switch type {
        case .mouseMoved:
            var location = pointerWarpGuard.correct(event.location)
            if overlay.isVisible {
                overlay.handleMouseMoved(to: location)
            } else {
                let now = CFAbsoluteTimeGetCurrent()
                if canOpen(at: now) {
                    if let point = firstCompleted({ $0.feed(location, at: now) }) {
                        overlay.show(at: point)
                        // `show` may have warped the pointer, and this event
                        // still carries the pre-warp location.
                        location = pointerWarpGuard.correct(location)
                    } else {
                        notePointerMoved(at: now)
                    }
                }
            }
            if location != event.location { event.location = location }
            return event

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // A click ends every gesture. A click in the menu bar or the Dock
            // is work at the edge, not a bump against it.
            resetDetectors()
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            // A fresh press: the release of the last one never came.
            swallowedButtons.remove(button)
            guard overlay.handleMouseDown(at: event.location) else { return event }
            swallowedButtons.insert(button)
            return nil

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            return swallowedButtons.remove(button) == nil ? event : nil

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if swallowedKeys.contains(keyCode) {
                // The press went to the overlay, so its repeats do too.
                if isRepeat { return nil }
                // A fresh press: the release of the last one never came.
                swallowedKeys.remove(keyCode)
            }
            // A key held since before the overlay opened runs nothing, and
            // its release belongs to the app below.
            if isRepeat { return overlay.isVisible ? nil : event }
            if !overlay.isVisible {
                // Every press reaches the detectors, as it spoils a chord
                // trigger in progress.
                let now = CFAbsoluteTimeGetCurrent()
                let point = firstCompleted {
                    $0.keyDown(UInt16(keyCode), flags: event.flags, pointer: event.location)
                }
                guard let point, canOpen(at: now) else { return event }
                overlay.show(at: point)
            } else if !overlay.handleKeyDown(event) {
                return event
            }
            swallowedKeys.insert(keyCode)
            return nil

        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if shortcutDetector?.keyUp(UInt16(keyCode)) == true { overlay.hide() }
            return swallowedKeys.remove(keyCode) == nil ? event : nil

        case .flagsChanged:
            // A held modifier could switch the input source in the app below.
            // The event carries the absolute modifier state, so the app is in
            // step again with the first one it gets after the overlay closes.
            if overlay.isVisible {
                // The release that closes the overlay reaches the app below,
                // which saw the modifiers go down.
                guard shortcutDetector?.modifiersChanged(event.flags) == true else { return nil }
                overlay.hide()
                return event
            }
            // The press that opens the overlay reaches the app below too.
            let now = CFAbsoluteTimeGetCurrent()
            if let point = firstCompleted({ $0.flagsChanged(event.flags, pointer: event.location, at: now) }),
                canOpen(at: now)
            {
                overlay.show(at: point)
            }
            return event

        case .scrollWheel:
            let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            if swipeEventFilter?.shouldSwallowScroll(scrollPhase: scrollPhase, momentumPhase: momentumPhase) == true {
                return nil
            }
            // A scroll closes the overlay, but momentum does not: a quick
            // swipe trigger keeps sending it after the fingers lift, which is
            // when the overlay opens. Nor does the end of a swallowed swipe
            // scroll that the app below saw begin.
            let endsSwipeScroll = scrollPhase != 0 && swipeEventFilter?.isSwallowingScroll == true
            if overlay.isVisible, momentumPhase == 0, !endsSwipeScroll { overlay.hide() }
            return event

        case .dockControl:
            let swallow = swipeEventFilter?.shouldSwallowDockControl(
                subtype: event.getIntegerValueField(.dockControlSubtype),
                motion: event.getIntegerValueField(.dockSwipeMotion),
                phase: event.getIntegerValueField(.dockSwipePhase)) == true
            return swallow ? nil : event

        case .gesture:
            guard needsTouches, let gesture = NSEvent(cgEvent: event) else { return event }
            // Only a touch frame carries touches. The other gesture events
            // carry none, and their empty set would read as every finger
            // lifted. The frame in which the last finger lifts still carries
            // it, as ended.
            let touches = gesture.touches(matching: .any, in: nil)
            if !touches.isEmpty {
                noteTouches(touches.filter { $0.phase.isDisjoint(with: [.ended, .cancelled]) }, pointer: event.location)
            }
            return event

        default:
            return event
        }
    }

    @objc private func frontmostAppChanged() {
        overlay.hide()
    }

    /// Only the edge detector depends on the displays. Rebuilding the others
    /// would drop a touch or a swallowed swipe in progress.
    @objc private func screensChanged() {
        detectors = detectors.map { $0 is ScreenEdgeDetector ? ScreenEdgeDetector() : $0 }
    }

    private func startCooldown() {
        resetDetectors()
        blockedUntil = CFAbsoluteTimeGetCurrent() + Config.retriggerCooldown
    }

    private func canOpen(at now: TimeInterval) -> Bool {
        !overlay.isVisible && !isRecordingShortcut && now >= blockedUntil
    }

    /// Drops every gesture in progress.
    private func rebuildDetectors() {
        let kinds = TriggerKind.allCases.filter { store.triggers.contains($0) }
        detectors = kinds.map { $0.makeDetector(shortcut: store.triggerShortcut) }
        swipeEventFilter = kinds.contains(where: \.isFourFingerVerticalSwipe) ? SwipeEventFilter(fingers: 4) : nil
        needsTouches = kinds.contains(where: \.usesTrackpad)
    }

    private var shortcutDetector: ShortcutTriggerDetector? {
        detectors.lazy.compactMap { $0 as? ShortcutTriggerDetector }.first
    }

    private func resetDetectors() {
        for detector in detectors { detector.reset() }
    }

    /// Every detector sees every touch frame, also while the overlay is open
    /// or the cooldown runs, so that none misses where a touch began.
    private func noteTouches(_ touches: Set<NSTouch>, pointer: CGPoint) {
        swipeEventFilter?.touchesChanged(count: touches.count)
        let frame = TouchFrame(
            touches.map { ($0.identity.hash, $0.normalizedPosition) }, uniquingKeysWith: { first, _ in first })
        let now = CFAbsoluteTimeGetCurrent()
        var point: CGPoint?
        for detector in detectors {
            if let completed = detector.touchesChanged(frame, pointer: pointer, at: now), point == nil {
                point = completed
            }
        }
        guard let point, canOpen(at: now) else { return }
        overlay.show(at: point)
    }

    /// A stopped pointer sends no event, so a timer notices it. A movement
    /// only pushes the deadline back.
    private func notePointerMoved(at now: TimeInterval) {
        lastPointerMove = now
        guard !isStopCheckPending else { return }
        isStopCheckPending = true
        scheduleStopCheck(after: Config.pointerStopDelay)
    }

    private func scheduleStopCheck(after delay: TimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointerStopped() }
        }
        // Common modes, so the check also runs while a menu tracks the mouse.
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkPointerStopped() {
        let now = CFAbsoluteTimeGetCurrent()
        let still = now - lastPointerMove
        guard still >= Config.pointerStopDelay else {
            scheduleStopCheck(after: Config.pointerStopDelay - still)
            return
        }
        isStopCheckPending = false
        guard canOpen(at: now) else { return }
        if let point = firstCompleted({ $0.pointerStopped(at: lastPointerMove) }) {
            overlay.show(at: point)
        }
    }

    /// Asks each detector in turn and stops at the first completed gesture.
    /// Each detector is asked at most once: asking changes its state, and
    /// `lazy.compactMap(_:).first` asks the matching one twice.
    private func firstCompleted(_ ask: (any TriggerDetector) -> CGPoint?) -> CGPoint? {
        for detector in detectors {
            if let point = ask(detector) { return point }
        }
        return nil
    }
}
