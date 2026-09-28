import Testing

@testable import WiggleKit

@Test func onePreferenceDomainWithTheSwipeOnMeansTheSystemUsesIt() {
    #expect(SystemTrackpadGestures.usesFourFingerVerticalSwipe(values: [2, nil]) == true)
    #expect(SystemTrackpadGestures.usesFourFingerVerticalSwipe(values: [0, 2]) == true)
}

@Test func theSwipeSwitchedOffMeansTheSystemDoesNotUseIt() {
    #expect(SystemTrackpadGestures.usesFourFingerVerticalSwipe(values: [0, 0]) == false)
    #expect(SystemTrackpadGestures.usesFourFingerVerticalSwipe(values: [0, nil]) == false)
}

@Test func noStoredValueMeansTheMacOSDefaultUsesTheSwipe() {
    #expect(SystemTrackpadGestures.usesFourFingerVerticalSwipe(values: [nil, nil]) == true)
}
