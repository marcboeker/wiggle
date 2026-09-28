import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// Backs the SwiftUI settings pages. A page writes through `SettingsActions`.
@MainActor
@Observable
final class SettingsModel {
    var overlayOpacity = Config.defaultOverlayOpacity
    var overlayAppearance = Config.defaultOverlayAppearance
    var triggers = TriggerKind.defaults
    var showsMenuBarItem = true
    var loginItemStatus = SMAppService.Status.notRegistered
    var showsSwipeNote = false
}

@MainActor
final class SettingsWindowController: NSWindowController {

    var onTriggersChanged: (() -> Void)?
    var onMenuBarItemChanged: (() -> Void)?

    private let store: SlotStore
    private let model = SettingsModel()
    private let wheelPane: WheelPaneViewController

    init(store: SlotStore) {
        self.store = store
        wheelPane = WheelPaneViewController(store: store)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Wiggle Settings"
        // Lets the sidebar reach the top of the window, like System Settings.
        // The title still names the window in Mission Control.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentMinSize = NSSize(width: 620, height: 460)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let actions = SettingsActions(
            setOpacity: { [weak self] in self?.setOpacity($0) },
            resetOpacity: { [weak self] in self?.resetOpacity() },
            setLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin($0) },
            refreshLoginItemStatus: { [weak self] in self?.refreshLoginItemStatus() },
            openLoginItemsSettings: { SMAppService.openSystemSettingsLoginItems() },
            setShowsMenuBarItem: { [weak self] in self?.setShowsMenuBarItem($0) },
            setTriggers: { [weak self] in self?.setTriggers($0) },
            openTrackpadSettings: { SettingsWindowController.openTrackpadSettings() },
            setOverlayAppearance: { [weak self] in self?.setOverlayAppearance($0) })
        let root = SettingsRootView(model: model, wheelPane: wheelPane, actions: actions)
        window.contentViewController = NSHostingController(rootView: root)
        // `contentViewController` shrinks the window to `General`'s ideal
        // size, which is too small for the wheel on `Actions`.
        window.setContentSize(NSSize(width: 680, height: 520))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Wiggle is a regular app while this window is open. The character
    /// palette hands its insertion to the frontmost regular app; while
    /// Wiggle is an accessory app, a click in the palette activates the app
    /// below and the emoji never arrives. `windowWillClose` switches back.
    /// `windowDidBecomeKey` refreshes the pages.
    func show() {
        // Activation is asynchronous and may be refused, so the window can
        // show before it becomes key.
        refresh()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        model.overlayOpacity = store.overlayOpacity
        model.overlayAppearance = store.overlayAppearance
        model.triggers = store.triggers
        model.showsMenuBarItem = store.showsMenuBarItem
        refreshLoginItemStatus()
        refreshSwipeNote()
        wheelPane.refresh()
    }

    private func refreshLoginItemStatus() {
        model.loginItemStatus = SMAppService.mainApp.status
    }

    private func refreshSwipeNote() {
        model.showsSwipeNote = model.triggers.contains(where: \.isFourFingerVerticalSwipe)
            && SystemTrackpadGestures.usesFourFingerVerticalSwipe()
    }

    private func setOpacity(_ opacity: CGFloat) {
        store.setOverlayOpacity(opacity)
        model.overlayOpacity = store.overlayOpacity
    }

    private func resetOpacity() { setOpacity(Config.defaultOverlayOpacity) }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("wiggle: could not change the login item: \(error.localizedDescription)")
        }
        // Registering may land on `.requiresApproval` instead of `.enabled`.
        refreshLoginItemStatus()
    }

    private func setShowsMenuBarItem(_ show: Bool) {
        store.setShowsMenuBarItem(show)
        model.showsMenuBarItem = show
        onMenuBarItemChanged?()
    }

    private func setOverlayAppearance(_ appearance: OverlayAppearance) {
        store.setOverlayAppearance(appearance)
        model.overlayAppearance = appearance
    }

    private func setTriggers(_ kinds: Set<TriggerKind>) {
        store.setTriggers(kinds)
        model.triggers = store.triggers
        refreshSwipeNote()
        onTriggersChanged?()
    }

    private static func openTrackpadSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// The user may have changed the Trackpad settings or the login item
    /// meanwhile.
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
