import CoreGraphics

/// After `CGWarpMouseCursorPosition`, the tap still sees a few `mouseMoved`
/// events that carry the pre-warp position. Returning one unchanged drags
/// the cursor back and undoes the warp. While a warp is pending, `correct`
/// substitutes its target, until a real event agrees with it or
/// `maxCorrections` runs out.
struct PointerWarpGuard {

    /// Observed stragglers are a handful of events at most. The limit keeps
    /// a warp that nothing confirms from pinning the cursor.
    private static let maxCorrections = 5

    private var target: CGPoint?
    private var correctionsLeft = 0

    mutating func begin(target: CGPoint) {
        self.target = target
        correctionsLeft = PointerWarpGuard.maxCorrections
    }

    mutating func correct(_ raw: CGPoint) -> CGPoint {
        guard let target else { return raw }
        if raw == target || correctionsLeft <= 0 {
            self.target = nil
            return raw
        }
        correctionsLeft -= 1
        return target
    }
}
