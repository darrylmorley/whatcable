import XCTest
import Foundation
@testable import WhatCableCore

final class LocalisationTests: XCTestCase {

    func testCoreStringCatalogIsValidJSON() throws {
        let bundle = Bundle.module
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "xcstrings"))
        let data = try Data(contentsOf: url)
        let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 50, "Core catalog should have many string keys")
        XCTAssertEqual(catalog?["sourceLanguage"] as? String, "en")
    }

    func testEnglishSourceStringsResolveToThemselves() {
        let bundle = Bundle.module
        let sample = String(localized: "Nothing connected", bundle: bundle)
        XCTAssertEqual(sample, "Nothing connected")
    }

    func testInterpolatedStringsResolve() {
        let bundle = Bundle.module
        let result = String(localized: "Cable speed: \("USB 3.2 Gen 2 (10 Gbps)")", bundle: bundle)
        XCTAssertEqual(result, "Cable speed: USB 3.2 Gen 2 (10 Gbps)")
    }
}
