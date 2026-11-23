import Testing
import Foundation
@testable import WhatCableCore

/// Strings that SwiftUI views used to look up in Bundle.main (which carries
/// no translations), so they showed English in every language. They now go
/// through Core's catalogue; this resolves each one in German and in two
/// languages with several plural forms (Russian, Polish), through the same
/// `<lang>.lproj` bundles that `setCoreLocale(_:)` switches to.
@Suite("App view strings resolve in Core's catalogue")
struct AppViewStringsLocalisationTests {

    private func bundle(_ lang: String) throws -> Bundle {
        let url = try #require(
            Bundle.module.url(forResource: lang, withExtension: "lproj"),
            "\(lang).lproj missing from Core's bundle"
        )
        return try #require(Bundle(url: url))
    }

    @Test("Tooltips and widget title", arguments: [
        ("de", "Bildschirm-Diagnose", "Aushandlungs-Diagnose", "Kabelstatus"),
        ("ru", "Диагностика монитора", "Диагностика согласования", "Состояние кабеля"),
        ("pl", "Diagnostyka ekranu", "Diagnostyka negocjacji", "Stan kabla"),
    ])
    func fixedLabels(lang: String, display: String, negotiation: String, cableStatus: String) throws {
        let b = try bundle(lang)
        #expect(String(localized: "Display Diagnostics", bundle: b) == display)
        #expect(String(localized: "Negotiation Diagnostics", bundle: b) == negotiation)
        #expect(String(localized: "Cable Status", bundle: b) == cableStatus)
    }

    /// The relative date is formatted by the system and passed in as a
    /// string, so a fixed stand-in is used here.
    @Test("Saved Cables: last seen caption", arguments: [
        ("de", "SUMMARY  ·  Zuletzt gesehen WHEN"),
        ("ru", "SUMMARY  ·  Последний раз замечен WHEN"),
        ("pl", "SUMMARY  ·  Ostatnio widziany WHEN"),
    ])
    func lastSeen(lang: String, expected: String) throws {
        let b = try bundle(lang)
        let summary = "SUMMARY"
        let when = "WHEN"
        #expect(String(localized: "\(summary)  ·  Last seen \(when)", bundle: b) == expected)
    }

    @Test("Saved Cables: rated speed annotation", arguments: [
        ("de", 1, "Ausgelegt für 1 Gbps"),
        ("de", 40, "Ausgelegt für 40 Gbps"),
        ("ru", 2, "Рассчитан на 2 Гбит/с"),
        ("ru", 5, "Рассчитан на 5 Гбит/с"),
        ("ru", 40, "Рассчитан на 40 Гбит/с"),
        ("pl", 2, "Przystosowany do 2 Gbps"),
        ("pl", 40, "Przystosowany do 40 Gbps"),
    ])
    func rated(lang: String, gbps: Int, expected: String) throws {
        let b = try bundle(lang)
        #expect(String(localized: "Rated \(gbps) Gbps", bundle: b) == expected)
    }
}
