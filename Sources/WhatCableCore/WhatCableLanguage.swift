import Foundation

/// Supported user-facing languages for WhatCable.
public enum WhatCableLanguage: String, CaseIterable, Codable, Hashable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static let `default`: WhatCableLanguage = .english
    public static let preferenceKey = "languageCode"
    public static let appDefaultsSuiteName = "uk.whatcable.whatcable"

    public var id: String { code }
    public var code: String { rawValue }
    public var locale: Locale { Locale(identifier: code) }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    public init(code: String?) {
        guard let code, let language = Self(rawValue: code) else {
            self = Self.default
            return
        }
        self = language
    }

    public static func persisted(in defaults: UserDefaults?) -> WhatCableLanguage {
        WhatCableLanguage(code: defaults?.string(forKey: preferenceKey))
    }

    public static func persistedForApp() -> WhatCableLanguage {
        persisted(in: UserDefaults(suiteName: appDefaultsSuiteName) ?? .standard)
    }

    public static func persistedForWidget() -> WhatCableLanguage {
        persisted(in: UserDefaults(suiteName: WidgetSnapshot.appGroupID))
    }

    public func persist(in defaults: UserDefaults?) {
        defaults?.set(code, forKey: Self.preferenceKey)
    }
}

public enum LocalizedCopy {
    public static func string(
        _ key: String.LocalizationValue,
        language: WhatCableLanguage = .default
    ) -> String {
        string(key, bundle: .module, language: language)
    }

    public static func string(
        _ key: String.LocalizationValue,
        bundle: Bundle,
        language: WhatCableLanguage = .default
    ) -> String {
        let lookupBundle = bundle.localizedLookupBundle(for: language)
        return String(localized: key, bundle: lookupBundle, locale: language.locale)
    }
}

private extension Bundle {
    func localizedLookupBundle(for language: WhatCableLanguage) -> Bundle {
        let candidates = [language.code, language.code.lowercased()]
        for candidate in candidates {
            if let path = path(forResource: candidate, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return self
    }
}
