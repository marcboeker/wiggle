import CoreGraphics

/// Opens the overlay when the user presses one mouse button.
final class MouseButtonDetector: TriggerDetector {

    private let button: Int64

    init(button: Int64) {
        self.button = button
    }

    func mouseDown(button: Int64, pointer: CGPoint) -> CGPoint? {
        button == self.button ? pointer : nil
    }

    func reset() {}
}
