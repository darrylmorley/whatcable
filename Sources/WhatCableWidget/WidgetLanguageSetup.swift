import Foundation
import os.log
import WhatCableCore

/// Applies the language picked in WhatCable (see `WidgetLanguage`) and logs
/// what the widget process sees, so a wrong language can be diagnosed from
/// the outside:
///
///     log show --predicate 'subsystem == "uk.whatcable.whatcable" AND category == "widget-language"' --last 10m --info
///
/// Only language codes and the bundle ID are logged, nothing about the user.
enum WidgetLanguageSetup {
    private static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "widget-language")

    static func apply(_ caller: String) {
        let url = WidgetLanguage.sharedFileURL
        let shared = WidgetLanguage.read(from: url)
        let global = WidgetLanguage.globalLanguages()
        let applied = WidgetLanguage.applyShared(from: url, systemLanguages: global)

        let key = appleLanguagesKey as CFString
        let appValue = CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication) as? [String]
        let anyAppValue = CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication) as? [String]
        let standardValue = UserDefaults.standard.stringArray(forKey: appleLanguagesKey)
        let launchArgument = ProcessInfo.processInfo.arguments.contains("-" + appleLanguagesKey)
        let sample = String(localized: "Cable Status", bundle: _coreLocalizedBundle)

        log.info("""
            \(caller, privacy: .public): shared=\(shared.isEmpty ? "<system default>" : shared, privacy: .public) \
            applied=\(applied.isEmpty ? "<process default>" : applied, privacy: .public) \
            sample=\(sample, privacy: .public) \
            globalAppleLanguages=\(global, privacy: .public) \
            Locale.preferredLanguages=\(Locale.preferredLanguages, privacy: .public) \
            main.preferredLocalizations=\(Bundle.main.preferredLocalizations, privacy: .public) \
            main.localizations=\(Bundle.main.localizations, privacy: .public) \
            core.preferredLocalizations=\(coreLocalizationBundle.preferredLocalizations, privacy: .public) \
            CFPrefs(currentApp)=\(appValue ?? [], privacy: .public) \
            CFPrefs(anyApp)=\(anyAppValue ?? [], privacy: .public) \
            UserDefaults.standard=\(standardValue ?? [], privacy: .public) \
            launchArgument=\(launchArgument, privacy: .public) \
            bundleID=\(Bundle.main.bundleIdentifier ?? "nil", privacy: .public)
            """)
    }
}
