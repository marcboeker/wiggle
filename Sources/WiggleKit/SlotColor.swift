import AppKit

/// The raw value is what the configuration file stores, so a case must keep
/// its name.
enum SlotColor: String, CaseIterable, Sendable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case purple
    case pink

    var title: String { rawValue.capitalized }

    var color: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        }
    }
}
