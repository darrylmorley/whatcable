import XCTest
import WhatCableCore
@testable import WhatCable

/// The menu titles are built during plugin bootstrap, in `WhatCableApp.init`,
/// long before `AppSettings.shared` exists. These pin that the saved language
/// is applied first, and that applying it really changes what a localised
/// lookup returns.
final class AppLanguageStartupTests: XCTestCase {
    private func scratchDefaults(_ body: (UserDefaults, String) -> Void) {
        let name = "uk.whatcable.whatcable.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        body(suite, name)
    }

    @MainActor
    func testSavedLanguageIsAppliedBeforePluginBootstrap() {
        scratchDefaults { suite, _ in
            suite.set("de", forKey: "preferredLanguage")
            var events: [String] = []
            WhatCableApp.startUp(
                defaults: suite,
                applyLanguage: { events.append("language:\($0)") },
                bootstrap: { events.append("bootstrap") }
            )
            XCTAssertEqual(events, ["language:de", "bootstrap"],
                           "The saved language must be applied before plugin bootstrap builds the menu titles")
        }
    }

    @MainActor
    func testNoSavedLanguageAppliesTheSystemLanguage() {
        scratchDefaults { suite, _ in
            var applied: String?
            WhatCableApp.startUp(defaults: suite, applyLanguage: { applied = $0 }, bootstrap: {})
            XCTAssertEqual(applied, "", "An absent key means the system language, applied as an empty code")
        }
    }

    /// One catalogue now serves the app, notifications and Core, so switching
    /// it must change strings that used to live in each of the three files:
    /// "Refresh" (app and Core), "Behavior" (app only), "Charger connected"
    /// (notifications only) and "Power Monitor" (Core).
    func testApplyLocaleSwitchesTheOneCatalogue() {
        defer { AppSettings.applyLocale("") }
        AppSettings.applyLocale("de")
        XCTAssertEqual(String(localized: "Refresh", bundle: _coreLocalizedBundle), "Aktualisieren")
        XCTAssertEqual(String(localized: "Behavior", bundle: _coreLocalizedBundle), "Verhalten")
        XCTAssertEqual(String(localized: "Charger connected", bundle: _coreLocalizedBundle), "Ladegerät verbunden")
        XCTAssertEqual(String(localized: "Power Monitor", bundle: _coreLocalizedBundle), "Strommonitor")
        // The free build's Settings link, which used to resolve through the
        // app's catalogue where it had no entry, so it always showed English.
        XCTAssertEqual(String(localized: "Upgrade to WhatCable Pro", bundle: _coreLocalizedBundle),
                       "Auf WhatCable Pro upgraden")
    }

    /// The Settings language picker lists every language the catalogue ships,
    /// read from Core's bundle (the app target has no resources of its own).
    /// Compared with the `.lproj` directories in the source tree, so adding a
    /// language needs no edit here.
    func testPickerListsEveryShippedLanguage() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/WhatCableCore/Resources")
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: resources.path)
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
            .sorted()
        XCTAssertGreaterThan(onDisk.count, 1, "No translations found under \(resources.path)")
        XCTAssertEqual(AppLanguages.available.map(\.id), onDisk)
    }

    func testAppleLanguagesDecision() {
        XCTAssertEqual(AppSettings.appleLanguagesUpdate(preferred: "de", userChanged: false), .set(["de"]))
        XCTAssertEqual(AppSettings.appleLanguagesUpdate(preferred: "zh-Hans", userChanged: true), .set(["zh-Hans"]))
        XCTAssertEqual(AppSettings.appleLanguagesUpdate(preferred: "", userChanged: true), .remove,
                       "Choosing System default removes our override")
        XCTAssertEqual(AppSettings.appleLanguagesUpdate(preferred: "", userChanged: false), .leave,
                       "At launch an empty setting must not wipe a per-app language set in System Settings")
        XCTAssertEqual(AppSettings.appleLanguagesUpdate(preferred: "xx", userChanged: false), .leave,
                       "An unshipped code at launch must not be written back to AppleLanguages")
        XCTAssertEqual(AppSettings.appleLanguagesUpdate(preferred: "xx", userChanged: true), .remove,
                       "An unshipped code is treated as System default when the user chooses it")
        XCTAssertEqual(AppSettings.appleLanguagesUpdate(preferred: "zh-hans", userChanged: false), .set(["zh-hans"]),
                       "Matching is case-insensitive, so a lowercase shipped code is accepted")
    }

    func testSyncAppleLanguagesWritesNothingForAnUnshippedCode() {
        scratchDefaults { suite, name in
            AppSettings.syncAppleLanguages("xx", userChanged: false, in: suite)
            XCTAssertNil(suite.persistentDomain(forName: name)?["AppleLanguages"],
                         "A stale or corrupt saved code must not be persisted")
        }
    }

    func testSyncAppleLanguagesWritesAndRemovesInTheGivenDomain() {
        scratchDefaults { suite, name in
            AppSettings.syncAppleLanguages("de", userChanged: false, in: suite)
            XCTAssertEqual(suite.persistentDomain(forName: name)?["AppleLanguages"] as? [String], ["de"])
            AppSettings.syncAppleLanguages("", userChanged: false, in: suite)
            XCTAssertEqual(suite.persistentDomain(forName: name)?["AppleLanguages"] as? [String], ["de"],
                           "Launch with an empty setting leaves the entry alone")
            AppSettings.syncAppleLanguages("", userChanged: true, in: suite)
            XCTAssertNil(suite.persistentDomain(forName: name)?["AppleLanguages"])
        }
    }
}
