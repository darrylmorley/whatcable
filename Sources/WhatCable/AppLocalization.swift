import Foundation
import WhatCableCore

@MainActor
func appString(
    _ key: String.LocalizationValue
) -> String {
    appString(key, language: AppSettings.shared.language)
}

func appString(
    _ key: String.LocalizationValue,
    language: WhatCableLanguage
) -> String {
    LocalizedCopy.string(key, bundle: .module, language: language)
}
