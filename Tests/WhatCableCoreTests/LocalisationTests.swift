import XCTest
import Foundation
@testable import WhatCableCore

final class LocalisationTests: XCTestCase {

    func testStringFilesHaveManyKeys() throws {
        let bundle = Bundle.module
        let url = try XCTUnwrap(
            bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj"),
            "en.lproj/Localizable.strings not found in bundle"
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        let keyLines = content.components(separatedBy: "\n").filter { $0.contains(" = ") && !$0.hasPrefix("//") }
        XCTAssertGreaterThan(keyLines.count, 50, "en.lproj/Localizable.strings should have more than 50 entries")
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
