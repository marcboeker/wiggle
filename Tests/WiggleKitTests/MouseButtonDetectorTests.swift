import CoreGraphics
import Testing

@testable import WiggleKit

@Suite struct MouseButtonDetectorTests {
    @Test func opensAtThePointerOnItsButton() {
        let detector = MouseButtonDetector(button: 2)
        #expect(detector.mouseDown(button: 2, pointer: CGPoint(x: 10, y: 20)) == CGPoint(x: 10, y: 20))
    }

    @Test func ignoresOtherButtons() {
        let detector = MouseButtonDetector(button: 2)
        for button: Int64 in [0, 1, 3, 4] {
            #expect(detector.mouseDown(button: button, pointer: .zero) == nil)
        }
    }
}
