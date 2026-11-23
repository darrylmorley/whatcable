import Testing
import Foundation
@testable import WhatCableCore

/// The app shares its chosen language with the widget through a small file
/// in the App Group container; the widget applies it so its strings match the
/// app's instead of the Mac's system language.
@Suite("Widget language")
struct WidgetLanguageTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("widgetLanguage-\(UUID().uuidString).json")
    }

    @Test("Write then read returns the app's choice", arguments: ["de", "pt-BR", ""])
    func roundTrip(identifier: String) throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WidgetLanguage.write(identifier, to: url))
        #expect(WidgetLanguage.read(from: url) == identifier)
    }

    @Test("A missing or unreadable file reads as the system language")
    func missingOrGarbage() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WidgetLanguage.read(from: url) == "")
        #expect(WidgetLanguage.read(from: nil) == "")
        try Data("not json".utf8).write(to: url)
        #expect(WidgetLanguage.read(from: url) == "")
    }

    @Test("Resolve keeps a shipped app choice over the system list", arguments: [
        ("de", "de"),
        ("DE", "de"),
        ("pt-br", "pt-BR"),
    ])
    func resolveAppChoice(choice: String, expected: String) {
        let available = ["en", "de", "pt-BR", "ru"]
        #expect(WidgetLanguage.resolve(appChoice: choice, available: available, systemLanguages: ["en-GB"]) == expected)
    }

    /// "System default" (or a choice the catalogue doesn't ship) resolves
    /// from the user's own language list to an explicit catalogue language,
    /// the same path an explicit choice takes, so a language the widget
    /// process inherited can't decide it.
    @Test("System default resolves from the user's language list", arguments: [
        ("", ["en-GB"], "en"),
        ("", ["de-DE", "en-GB"], "de"),
        ("", ["fr-CA", "en"], "en"),
        ("", ["pt-BR"], "pt-BR"),
        ("xx", ["ru-RU"], "ru"),
        ("", ["ja-JP"], ""),
        ("", [String](), ""),
    ])
    func resolveSystemDefault(choice: String, system: [String], expected: String) {
        let available = ["en", "de", "pt-BR", "ru"]
        #expect(WidgetLanguage.resolve(appChoice: choice, available: available, systemLanguages: system) == expected)
    }

    /// The test process runs in the Mac's language (whatever that is); the
    /// app's choice must win over it.
    @Test("The widget applies the app's language, not the system one")
    func appliesAppLanguage() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WidgetLanguage.write("de", to: url))

        var applied: String?
        let result = WidgetLanguage.applyShared(from: url, systemLanguages: ["en-GB"], apply: { applied = $0 })
        #expect(result == "de")
        #expect(applied == "de")

        // What setCoreLocale("de") points the catalogue at.
        let lproj = try #require(coreLocalizationBundle.url(forResource: "de", withExtension: "lproj"))
        let bundle = try #require(Bundle(url: lproj))
        #expect(String(localized: "Cable Status", bundle: bundle) == "Kabelstatus")
    }

    /// The case the MacBook check failed: the app is back on System default
    /// and the user's list is English, so the widget must apply English
    /// explicitly, whatever language its process came up in.
    @Test("System default applies the user's language explicitly")
    func systemDefault() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WidgetLanguage.write("", to: url))
        var applied: String?
        WidgetLanguage.applyShared(from: url, systemLanguages: ["en-GB"], apply: { applied = $0 })
        #expect(applied == "en")
    }

    @Test("The app's choice still wins over the user's language list")
    func appChoiceWinsOverSystemList() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(WidgetLanguage.write("de", to: url))
        var applied: String?
        WidgetLanguage.applyShared(from: url, systemLanguages: ["en-GB"], apply: { applied = $0 })
        #expect(applied == "de")
    }
}
