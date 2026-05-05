import XCTest
@testable import WhatCableCore

final class VendorDBTests: XCTestCase {

    func testKnownVendorReturnsName() {
        XCTAssertEqual(VendorDB.name(for: 0x05AC), "Apple")
        XCTAssertEqual(VendorDB.name(for: 0x0BDA), "Realtek")
        XCTAssertEqual(VendorDB.name(for: 0x2BCF), "Anker")
    }

    func testUnknownVendorReturnsNil() {
        XCTAssertNil(VendorDB.name(for: 0xDEAD))
    }

    func testLabelIncludesNameAndHex() {
        XCTAssertEqual(VendorDB.label(for: 0x05AC), "Apple (0x05AC)")
        XCTAssertEqual(VendorDB.label(for: 0x0BDA), "Realtek (0x0BDA)")
    }

    func testLabelFallsBackToHexOnly() {
        XCTAssertEqual(VendorDB.label(for: 0xDEAD), "0xDEAD")
        XCTAssertEqual(VendorDB.label(for: 0x0001), "0x0001")
    }

    func testLabelHexIsUppercaseFourDigits() {
        // VID 0x004C should render as 004C (zero-padded), uppercase.
        XCTAssertEqual(VendorDB.label(for: 0x004C), "Apple (legacy) (0x004C)")
    }
}
