import AppKit

/// The raw value is what the configuration file stores, so a case must keep
/// its name.
enum OverlayAppearance: String, CaseIterable, Sendable {
    case light
    case dark
    case auto

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .auto: "Automatic"
        }
    }

    /// `nil` follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .auto: nil
        }
    }
}
