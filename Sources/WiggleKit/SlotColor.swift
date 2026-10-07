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

    /// Tuned to one lightness, so no colour shouts over another on the
    /// wheel's graphite. Orange keeps clear of the coral hover.
    var color: NSColor {
        switch self {
        case .red: NSColor(srgbHex: 0xF2545B)
        case .orange: NSColor(srgbHex: 0xFFA94D)
        case .yellow: NSColor(srgbHex: 0xFFD45C)
        case .green: NSColor(srgbHex: 0x5DCB8B)
        case .teal: NSColor(srgbHex: 0x3EC1B9)
        case .blue: NSColor(srgbHex: 0x5E8FF0)
        case .purple: NSColor(srgbHex: 0xA880F4)
        case .pink: NSColor(srgbHex: 0xF06DB2)
        }
    }
}
