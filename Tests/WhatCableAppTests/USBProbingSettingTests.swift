import XCTest
@testable import WhatCable
import WhatCableDarwinBackend

/// Issues #429 and #571. Two things gate the USB bus: the app has loaded (the
/// user has been through the welcome screen), and the Settings switch allows it.
@MainActor
final class USBProbingSettingTests: XCTestCase {
    /// Was a raw `UserDefaults.standard(forKey: "hasCompletedOnboarding")`
    /// snapshot/restore, which bypassed `AppSettings` entirely and still hit
    /// the real, cross-process-shared `.standard` domain. A throwaway suite
    /// needs no snapshot/restore of that domain at all: it is discarded
    /// whole afterward, and isolates this test from every concurrent
    /// `swift test` process on the machine.
    private func withRestoredOnboarding(_ body: () -> Void) {
        withScratchAppSettingsDefaults {
            body()
        }
    }

    func testTogglingSkipDeepUSBProbingDrivesTheWatcherGate() {
        withRestoredOnboarding {
            let settings = AppSettings.shared
            let originalSetting = settings.skipDeepUSBProbing
            let originalStatic = USBWatcher.probeBillboardDescriptors
            defer {
                settings.skipDeepUSBProbing = originalSetting
                USBWatcher.probeBillboardDescriptors = originalStatic
            }

            settings.hasCompletedOnboarding = true

            // Force each flip to cross the didSet guard, which no-ops on an
            // unchanged value. Without this the assertions can rest on residual
            // static state rather than on the code under test.
            settings.skipDeepUSBProbing = true
            settings.skipDeepUSBProbing = false
            XCTAssertTrue(USBWatcher.probeBillboardDescriptors)

            settings.skipDeepUSBProbing = true
            XCTAssertFalse(USBWatcher.probeBillboardDescriptors)
        }
    }

    func testNoProbingBeforeOnboardingWhateverTheSwitchSays() {
        withRestoredOnboarding {
            let settings = AppSettings.shared
            let originalSetting = settings.skipDeepUSBProbing
            let originalStatic = USBWatcher.probeBillboardDescriptors
            defer {
                settings.skipDeepUSBProbing = originalSetting
                USBWatcher.probeBillboardDescriptors = originalStatic
            }

            settings.hasCompletedOnboarding = false
            settings.skipDeepUSBProbing = true
            settings.skipDeepUSBProbing = false
            settings.applyUSBProbeGate()
            XCTAssertFalse(USBWatcher.probeBillboardDescriptors,
                           "Before onboarding the bus must stay quiet even with the switch clear")

            settings.hasCompletedOnboarding = true
            settings.applyUSBProbeGate()
            XCTAssertTrue(USBWatcher.probeBillboardDescriptors)
        }
    }
}
