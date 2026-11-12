import XCTest
@testable import WhatCable

/// Issue #562: an opt-in solid background for the menu bar popover.
@MainActor
final class SolidMenuBarBackgroundSettingTests: XCTestCase {
    func testAbsentKeyDefaultsOff() {
        let name = "uk.whatcable.whatcable.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        XCTAssertFalse(AppSettings.storedSolidMenuBarBackground(in: suite),
                       "A never-touched key must leave the translucent popover unchanged")
    }

    func testTogglePersistsUnderItsKey() {
        withScratchAppSettingsDefaults {
            let settings = AppSettings.shared
            let original = settings.solidMenuBarBackground
            defer { settings.solidMenuBarBackground = original }

            // Cross the didSet guard both ways so the writes are real.
            settings.solidMenuBarBackground = false
            settings.solidMenuBarBackground = true
            XCTAssertEqual(settings.defaults.object(forKey: "solidMenuBarBackground") as? Bool, true)
            XCTAssertTrue(AppSettings.storedSolidMenuBarBackground(in: settings.defaults))

            settings.solidMenuBarBackground = false
            XCTAssertEqual(settings.defaults.object(forKey: "solidMenuBarBackground") as? Bool, false)
            XCTAssertFalse(AppSettings.storedSolidMenuBarBackground(in: settings.defaults))
        }
    }
}
