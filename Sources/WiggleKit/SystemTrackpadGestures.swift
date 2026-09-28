import Foundation

/// Reads the trackpad preferences that System Settings writes.
enum SystemTrackpadGestures {

    /// The built-in trackpad and a Bluetooth Magic Trackpad keep separate
    /// copies of the trackpad preferences.
    private static let domains = [
        "com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]

    static func usesFourFingerVerticalSwipe() -> Bool {
        let key = "TrackpadFourFingerVertSwipeGesture" as CFString
        return usesFourFingerVerticalSwipe(values: domains.map { domain in
            // Picks up a change that System Settings made after the first read.
            CFPreferencesAppSynchronize(domain as CFString)
            return CFPreferencesCopyAppValue(key, domain as CFString) as? Int
        })
    }

    /// 2 means the system uses the swipe, 0 means it does not. A key that no
    /// domain has means the macOS default, which uses the swipe.
    static func usesFourFingerVerticalSwipe(values: [Int?]) -> Bool {
        let stored = values.compactMap { $0 }
        return stored.isEmpty || stored.contains(2)
    }
}
