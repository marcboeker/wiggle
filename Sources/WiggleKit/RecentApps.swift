import AppKit

/// The apps in the order they last came to the front, newest first, one
/// entry per process.
struct RecentApps<App> {
    private var entries: [(pid: pid_t, app: App)] = []

    mutating func activated(_ app: App, pid: pid_t) {
        terminated(pid)
        entries.insert((pid, app), at: 0)
    }

    mutating func terminated(_ pid: pid_t) {
        entries.removeAll { $0.pid == pid }
    }

    /// The newest app that is not the one in front.
    func previous(frontmost pid: pid_t?) -> App? {
        entries.first { $0.pid != pid }?.app
    }
}

/// Feeds `RecentApps` from the workspace. Wiggle itself never counts, so
/// while Settings is in front the previous app is the one before it.
///
/// Keeps the running app rather than an `AppRef`: Launch Services may not
/// know its bundle identifier, as for a build outside `/Applications`, or
/// may know another copy of it.
@MainActor
final class RecentAppsTracker {
    private var recent = RecentApps<NSRunningApplication>()

    init() {
        if let front = NSWorkspace.shared.frontmostApplication { record(front) }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = RecentAppsTracker.app(in: notification) else { return }
            MainActor.assumeIsolated { self?.record(app) }
        }
        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let pid = RecentAppsTracker.app(in: notification)?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.recent.terminated(pid) }
        }
    }

    var previous: NSRunningApplication? {
        recent.previous(frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    private nonisolated static func app(in notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    /// Skips a process without a bundle, which nothing could reopen.
    private func record(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier, app.bundleURL != nil
        else { return }
        recent.activated(app, pid: app.processIdentifier)
    }
}
