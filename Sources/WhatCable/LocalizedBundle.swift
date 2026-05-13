import Foundation

// The bundle used for all localized strings in WhatCable.
// Updated in tandem with _coreLocalizedBundle when language changes.
var _appLocalizedBundle: Bundle = .module

func setAppLocale(_ identifier: String) {
    if identifier.isEmpty {
        _appLocalizedBundle = .module
    } else if let url = Bundle.module.url(forResource: identifier, withExtension: "lproj"),
              let b = Bundle(url: url) {
        _appLocalizedBundle = b
    } else {
        _appLocalizedBundle = .module
    }
}
