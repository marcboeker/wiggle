import Foundation

/// The centre (ring 0), one of the eight slices around it (ring 1), or one
/// of the sixteen finer slices around that (ring 2).
enum SlotID: Hashable {
    case center
    case inner(Int)
    case outer(Int)

    static let innerNumbers = 1...8
    static let outerNumbers = 1...16

    init?(ring: Int, slot: Int) {
        switch ring {
        case 0 where slot == 0: self = .center
        case 1 where SlotID.innerNumbers.contains(slot): self = .inner(slot)
        case 2 where SlotID.outerNumbers.contains(slot): self = .outer(slot)
        default: return nil
        }
    }

    static let all: [SlotID] = [.center] + innerNumbers.map { .inner($0) } + outerNumbers.map { .outer($0) }

    var index: Int { SlotID.all.firstIndex(of: self)! }

    init?(index: Int) {
        guard SlotID.all.indices.contains(index) else { return nil }
        self = SlotID.all[index]
    }

    var ring: Int {
        switch self {
        case .center: return 0
        case .inner: return 1
        case .outer: return 2
        }
    }

    var number: Int {
        switch self {
        case .center: return 0
        case .inner(let n), .outer(let n): return n
        }
    }

    var keyHint: String {
        switch self {
        case .center: return "↩"
        case .inner(let n): return "\(n)"
        case .outer(let n): return String(UnicodeScalar(UInt8(Character("a").asciiValue! + UInt8(n - 1))))
        }
    }

    var label: String {
        switch self {
        case .center: return "Center"
        case .inner(let n): return "Slot \(n)"
        case .outer: return "Slot \(keyHint)"
        }
    }

    var fileName: String {
        label.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
