import Foundation
import WhatCableCore

/// A language the app ships, for the Settings language picker.
/// `id` is the BCP-47 code (also the picker tag and the `.lproj` name);
/// `name` is the language's own name (its autonym).
struct AppLanguage: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AppLanguages {
    /// Every language the app bundles, derived at runtime from the `.lproj`
    /// resources in WhatCableCore's resource bundle, which holds the one
    /// translation catalogue the app, CLI and widget all read (the same bundle
    /// `setCoreLocale` switches between). This is the single source of truth:
    /// adding a new `<code>.lproj` makes it appear in the picker automatically,
    /// with no code edit. Each entry's display name is the language's own
    /// autonym (e.g. "Deutsch", "日本語"), first letter capitalised in that
    /// language's own locale.
    ///
    /// Codes are canonicalised because SPM lowercases the script/region when it
    /// copies resources (`zh-Hans.lproj` lands as `zh-hans.lproj`), so the raw
    /// bundle names come back lowercased. `canonicalLanguageIdentifier` restores
    /// the BCP-47 case (`zh-hans` -> `zh-Hans`, `pt-br` -> `pt-BR`) so the picker
    /// tag matches what the system expects and what the old picker stored.
    static let available: [AppLanguage] = {
        coreLocalizationBundle.localizations
            .filter { $0 != "Base" }
            .map { rawCode in
                let code = Locale.canonicalLanguageIdentifier(from: rawCode)
                let locale = Locale(identifier: code)
                let display = locale.localizedString(forIdentifier: code) ?? code
                let name = display.isEmpty
                    ? code
                    : display.prefix(1).capitalized(with: locale) + display.dropFirst()
                return AppLanguage(id: code, name: name)
            }
            .sorted { $0.id < $1.id }
    }()
}
