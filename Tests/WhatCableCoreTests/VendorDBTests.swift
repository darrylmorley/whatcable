import XCTest
@testable import WhatCableCore

final class VendorDBTests: XCTestCase {

    // MARK: - Names come from the bundled USB-IF list

    func testKnownVendorsReturnUSBIFNames() {
        // No curated overrides. USB-IF's published name is what we show,
        // verbatim. The legal-suffix forms are accurate and not misleading.
        XCTAssertEqual(VendorDB.name(for: 0x05AC), "Apple")
        XCTAssertEqual(VendorDB.name(for: 0x0BDA), "Realtek Semiconductor Corp.")
        XCTAssertEqual(VendorDB.name(for: 0x046D), "Logitech Inc.")
        XCTAssertEqual(VendorDB.name(for: 0x291A), "Anker Innovations Limited")
        XCTAssertEqual(VendorDB.name(for: 0x18D1), "Google Inc.")
    }

    func testCableEmarkerChipVendorsResolve() {
        // E-marker silicon vendors observed in real cable reports
        // (#44, #45, #48, #49, #60, #62). USB-IF carries each of them
        // with its full legal name; we surface that as-is.
        XCTAssertEqual(
            VendorDB.name(for: 0x20C2),
            "Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab"
        )
        XCTAssertEqual(
            VendorDB.name(for: 0x315C),
            "Chengdu Convenientpower Semiconductor Co., LTD"
        )
        XCTAssertEqual(VendorDB.name(for: 0x2095), "CE LINK LIMITED")
        XCTAssertEqual(VendorDB.name(for: 0x2E99), "Hynetek Semiconductor Co., Ltd")
        XCTAssertEqual(
            VendorDB.name(for: 0x201C),
            "Hongkong Freeport Electronics Co., Limited"
        )
        XCTAssertEqual(VendorDB.name(for: 0x2B1D), "Lintes Technology Co., Ltd.")
    }

    // MARK: - Formerly-wrong curated entries now resolve correctly

    func testFormerlyWrongCuratedEntriesNowReflectUSBIF() {
        // Before this audit several curated entries attributed VIDs to
        // the wrong companies. With the curated layer dropped, each
        // resolves via the bundled USB-IF list to the correct vendor.
        // Pin them so a future "let's add an override" can't silently
        // restore the bad data without going through review.
        XCTAssertEqual(VendorDB.name(for: 0x2BCF), "Magtrol, Inc.")
        XCTAssertEqual(VendorDB.name(for: 0x32AC), "Framework Computer Inc")
        XCTAssertEqual(VendorDB.name(for: 0x103C), "AMX Corp.")
        XCTAssertEqual(VendorDB.name(for: 0x0FFE), "ASKA Corporation")
        XCTAssertEqual(VendorDB.name(for: 0x152E), "HLDS (Hitachi-LG Data Storage, Inc.)")
        XCTAssertEqual(VendorDB.name(for: 0x0AF8), "Taiwan Regular Electronics Co., Ltd.")
    }

    // MARK: - Unregistered VIDs

    func testUnregisteredVIDReturnsNil() {
        XCTAssertNil(VendorDB.name(for: 0xDEAD))
    }

    // MARK: - label()

    func testLabelIncludesNameAndHex() {
        XCTAssertEqual(VendorDB.label(for: 0x05AC), "Apple (0x05AC)")
        XCTAssertEqual(
            VendorDB.label(for: 0x0BDA),
            "Realtek Semiconductor Corp. (0x0BDA)"
        )
    }

    func testLabelFallsBackToHexOnly() {
        XCTAssertEqual(VendorDB.label(for: 0xDEAD), "0xDEAD")
        XCTAssertEqual(VendorDB.label(for: 0x0001), "0x0001")
    }

    // MARK: - isRegistered

    func testIsRegisteredCoversBundledList() {
        XCTAssertTrue(VendorDB.isRegistered(0x05AC))
        XCTAssertTrue(VendorDB.isRegistered(0x291A))
        XCTAssertFalse(VendorDB.isRegistered(0xDEAD))
    }
}
