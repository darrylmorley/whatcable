import XCTest
@testable import WhatCable
import WhatCableCore

final class AppLocalizationTests: XCTestCase {
    @MainActor
    func testExplicitEnglishPluralResourcesKeepSingularForms() {
        XCTAssertEqual(appString("\(1) USB devices", language: .english), "1 USB device")
        XCTAssertEqual(appString("\(2) USB devices", language: .english), "2 USB devices")
        XCTAssertEqual(appString("\(1) devices removed", language: .english), "1 device removed")
        XCTAssertEqual(appString("\(2) devices removed", language: .english), "2 devices removed")
    }
}
