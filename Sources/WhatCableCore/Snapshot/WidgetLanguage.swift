import Foundation

/// The language picked in WhatCable's Settings, shared with the widget so its
/// strings match the app's.
///
/// The widget is a separate process. Without this, its own strings follow the
/// Mac's system language while the port headlines in `widgetSnapshot.json`,
/// written by the app, follow the app's chosen language, so one widget could
/// mix two languages. The app writes its choice here on launch and whenever it
/// changes; the widget reads it at the start of each provider run and points
/// `_coreLocalizedBundle` at it.
///
/// It is a file in the App Group container, next to `widgetSnapshot.json`, for
/// the same reason that is: the host app is not sandboxed, so a shared
/// `UserDefaults` suite would land in a different place from the sandboxed
/// widget's.
///
/// An empty identifier means "System default": the widget then resolves the
/// user's own language list (the global AppleLanguages) to a catalogue
/// language itself, rather than trusting the language its process came up in.
///
/// Not covered: the widget's configuration sheet and App Intents titles are
/// drawn by macOS, which always uses the system language for them.
public enum WidgetLanguage {
    struct Payload: Codable, Equatable {
        var preferredLanguage: String
    }

    /// `widgetLanguage.json` in the App Group container, or nil when the
    /// container can't be resolved.
    public static var sharedFileURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID
        )?.appendingPathComponent("widgetLanguage.json")
    }

    /// Writes the app's chosen language (empty for the system language).
    /// Returns false when there is no URL or the write fails.
    @discardableResult
    public static func write(_ identifier: String, to url: URL?) -> Bool {
        guard let url else { return false }
        do {
            let data = try JSONEncoder().encode(Payload(preferredLanguage: identifier))
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The app's chosen language, or empty when the file is missing or
    /// unreadable (the app has never written it, or is an older version).
    public static func read(from url: URL?) -> String {
        guard let url,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return "" }
        return payload.preferredLanguage
    }

    /// The catalogue language the widget should use, always as an explicit
    /// catalogue language when one can be found:
    /// - the app's choice when Core's catalogue ships it (matched without
    ///   regard to case, returned in the catalogue's own spelling);
    /// - otherwise ("System default", or a choice the catalogue doesn't ship)
    ///   the best catalogue match for `systemLanguages`, the user's own list;
    /// - empty only when neither gives a match, which leaves the catalogue on
    ///   whatever the process resolves by itself.
    ///
    /// System default is resolved explicitly, not left to the process,
    /// because a widget process can come up in a language the user didn't
    /// pick for it (seen live: German after the app went back to System
    /// default on an English Mac).
    public static func resolve(appChoice: String, available: [String], systemLanguages: [String]) -> String {
        if !appChoice.isEmpty,
           let match = available.first(where: { $0.caseInsensitiveCompare(appChoice) == .orderedSame }) {
            return match
        }
        let candidates = available.filter { $0.lowercased() != "base" }
        guard !systemLanguages.isEmpty, !candidates.isEmpty else { return "" }
        // preferredLocalizations falls back to a catalogue language even when
        // nothing in the list matches; only accept a real match.
        guard let best = Bundle.preferredLocalizations(from: candidates, forPreferences: systemLanguages).first,
              systemLanguages.contains(where: { Self.matches(best, $0) })
        else { return "" }
        return best
    }

    /// True when the catalogue language `catalogue` and the preferred
    /// language `preferred` share a language ("en" and "en-GB"; "zh-Hant"
    /// and "zh-TW"). Used only to reject preferredLocalizations' fallback
    /// pick when nothing in the user's list is in the catalogue.
    static func matches(_ catalogue: String, _ preferred: String) -> Bool {
        func language(_ id: String) -> Substring {
            id.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? ""
        }
        return language(catalogue) == language(preferred)
    }

    /// The user's own language list from the global preferences domain
    /// (System Settings > General > Language & Region), read directly rather
    /// than through the process's preferences, which can carry a language
    /// the process inherited instead of the user's.
    public static func globalLanguages() -> [String] {
        CFPreferencesCopyValue(
            appleLanguagesKey as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String] ?? []
    }

    /// Reads the app's choice from `url` and applies it through `apply`
    /// (`setCoreLocale` in the widget). Returns the identifier applied.
    @discardableResult
    public static func applyShared(
        from url: URL? = sharedFileURL,
        available: [String] = coreLocalizationBundle.localizations,
        systemLanguages: [String] = globalLanguages(),
        apply: (String) -> Void = setCoreLocale
    ) -> String {
        let resolved = resolve(appChoice: read(from: url), available: available, systemLanguages: systemLanguages)
        apply(resolved)
        return resolved
    }
}
