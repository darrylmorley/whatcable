import Foundation

// The bundle used for all localized strings in WhatCableCore.
// Defaults to the module bundle (system language). Call setCoreLocale(_:)
// to switch to a specific lproj bundle for live language switching.
var _coreLocalizedBundle: Bundle = .module

public func setCoreLocale(_ identifier: String) {
    if identifier.isEmpty {
        _coreLocalizedBundle = .module
    } else if let url = Bundle.module.url(forResource: identifier, withExtension: "lproj"),
              let b = Bundle(url: url) {
        _coreLocalizedBundle = b
    } else {
        _coreLocalizedBundle = .module
    }
}
