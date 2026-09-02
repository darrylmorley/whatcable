import XCTest
@testable import WhatCable

/// Issue #571. The decision that gates the USB bus: probe only if the user has
/// been through the welcome screen AND the Settings switch allows it.
final class USBProbeGateTests: XCTestCase {
    func testNoProbeBeforeOnboarding() {
        XCTAssertFalse(USBProbeGate.shouldProbe(hasCompletedOnboarding: false, skipDeepUSBProbing: false),
                       "A first run must not touch the bus, whatever the switch says")
        XCTAssertFalse(USBProbeGate.shouldProbe(hasCompletedOnboarding: false, skipDeepUSBProbing: true))
    }

    func testAfterOnboardingTheSwitchDecides() {
        XCTAssertTrue(USBProbeGate.shouldProbe(hasCompletedOnboarding: true, skipDeepUSBProbing: false))
        XCTAssertFalse(USBProbeGate.shouldProbe(hasCompletedOnboarding: true, skipDeepUSBProbing: true))
    }
}
