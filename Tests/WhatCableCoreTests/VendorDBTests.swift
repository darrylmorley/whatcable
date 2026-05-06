import XCTest
@testable import WhatCableCore

final class VendorDBTests: XCTestCase {

    func testKnownVendorReturnsName() {
        XCTAssertEqual(VendorDB.name(for: 0x05AC), "Apple")
        XCTAssertEqual(VendorDB.name(for: 0x0BDA), "Realtek")
        // Anker's actual USB-IF VID is 0x291A (verified against the
        // March 2026 USB-IF vendor list).
        XCTAssertEqual(VendorDB.name(for: 0x291A), "Anker")
    }

    func testCableEmarkerChipVendorsResolve() {
        // E-marker silicon vendors observed in real cable reports
        // (#44, #45, #48, #49, #60, #62). Verified against USB-IF's
        // March 2026 vendor list.
        XCTAssertEqual(VendorDB.name(for: 0x20C2), "Sumitomo Electric Optical Comm")
        XCTAssertEqual(VendorDB.name(for: 0x315C), "Chengdu Convenientpower Semiconductor")
        XCTAssertEqual(VendorDB.name(for: 0x2095), "CE LINK")
        XCTAssertEqual(VendorDB.name(for: 0x2E99), "Hynetek Semiconductor")
        XCTAssertEqual(VendorDB.name(for: 0x201C), "Hongkong Freeport Electronics")
        XCTAssertEqual(VendorDB.name(for: 0x2B1D), "Lintes Technology")
    }

    func testRetiredIncorrectEntries() {
        // 0x2BCF was previously labelled "Anker" in the curated list
        // but is actually Magtrol, Inc. per USB-IF. 0x32AC was labelled
        // "Apple (Thunderbolt 4)" but is actually Framework Computer.
        // Both wrong labels are gone from the curated overrides; they
        // now fall through to the bundled USB-IF list and resolve to
        // the correct registered vendors. This test pins both the
        // removal of the wrong overrides and the correct fallback.
        XCTAssertEqual(VendorDB.name(for: 0x2BCF), "Magtrol, Inc.")
        XCTAssertEqual(VendorDB.name(for: 0x32AC), "Framework Computer Inc")
    }

    func testBundledUSBIFListProvidesFallbackNames() {
        // VIDs not in the curated list but registered with USB-IF
        // should now resolve via the bundled list. 0x121A is
        // TimeKeeping Systems per USB-IF March 2026.
        XCTAssertEqual(VendorDB.name(for: 0x121A), "TimeKeeping Systems, Inc.")
    }

    func testCuratedNamesOverrideBundledList() {
        // Apple's USB-IF entry says simply "Apple" in the bundled list,
        // which matches our curated entry. Pick a VID where the curated
        // form differs from USB-IF's verbose form to confirm the curated
        // override wins.
        // Hongkong Freeport: USB-IF lists the long form, our curated
        // entry uses the shorter "Hongkong Freeport Electronics".
        XCTAssertEqual(VendorDB.name(for: 0x201C), "Hongkong Freeport Electronics")
    }

    func testTotallyUnregisteredVIDStillReturnsNil() {
        // 0xDEAD is not a registered VID; both layers should miss.
        XCTAssertNil(VendorDB.name(for: 0xDEAD))
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
