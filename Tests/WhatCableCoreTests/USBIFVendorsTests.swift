import XCTest
@testable import WhatCableCore

/// Direct tests for the bundled USB-IF vendor lookup. Most user-facing
/// behaviour is covered by VendorDBTests via the curated-then-bundled
/// fallback chain; these tests pin properties of the bundled list itself.
final class USBIFVendorsTests: XCTestCase {

    func testLoadsManyEntries() {
        // The bundled TSV from USB-IF's March 2026 list has ~13,000
        // vendors. If the resource fails to load (e.g. SPM resource
        // wiring breaks) the count would be 0; pin a generous lower
        // bound so future refreshes that grow the list don't fail
        // this test, but a regression to "nothing loaded" would.
        XCTAssertGreaterThan(USBIFVendors.entryCount, 10_000)
    }

    func testKnownVIDResolves() {
        XCTAssertEqual(USBIFVendors.name(for: 0x05AC), "Apple")
    }

    func testZeroVIDIsFiltered() {
        // VID 0 is "USB Implementers Forum" in USB-IF's own list, but
        // in PD identity contexts a zero VID means "no vendor info."
        // The lookup deliberately hides VID 0 so the trust signals
        // layer's zero-VID flag isn't contradicted.
        XCTAssertNil(USBIFVendors.name(for: 0))
    }

    func testZeroVIDIsRegisteredEvenThoughNameIsHidden() {
        // isRegistered ignores the VID-0 filter so callers who need
        // the raw "is this in USB-IF's list?" signal can still get it.
        XCTAssertTrue(USBIFVendors.isRegistered(0))
    }

    func testUnregisteredVIDReturnsNil() {
        // 0xDEAD (decimal 57005) is not a USB-IF assignment.
        XCTAssertNil(USBIFVendors.name(for: 0xDEAD))
        XCTAssertFalse(USBIFVendors.isRegistered(0xDEAD))
    }

    func testNoControlCharactersInBundledNames() {
        // pdftotext emits form-feed (\u{000C}) at the start of each
        // page, which can land glued onto vendor names if the parser
        // doesn't strip control chars. Pin specific entries that were
        // affected before the parser fix (page-boundary vendors per
        // USB-IF March 2026), and a generic "vendor names contain no
        // ASCII control characters" check on a couple more.
        XCTAssertEqual(VendorDB.name(for: 1011), "Adaptec, Inc.")
        XCTAssertEqual(VendorDB.name(for: 1069), "Micronics")
        XCTAssertEqual(VendorDB.name(for: 1196), "Micro Audiometrics Corp.")
        for vid in [1011, 1069, 1196, 1222, 1480] {
            let name = VendorDB.name(for: vid) ?? ""
            for scalar in name.unicodeScalars {
                XCTAssertFalse(
                    scalar.value < 0x20 || scalar.value == 0x7F,
                    "vendor name for \(String(format: "0x%04X", vid)) contains control char U+\(String(scalar.value, radix: 16))"
                )
            }
        }
    }

    func testCableEmarkerChipVendorsAllResolve() {
        // The six chip vendors observed in real cable reports.
        // Bundled list carries them with their full USB-IF names
        // (the curated VendorDB entries shorten these for display).
        XCTAssertNotNil(USBIFVendors.name(for: 0x20C2)) // Sumitomo
        XCTAssertNotNil(USBIFVendors.name(for: 0x315C)) // Convenientpower
        XCTAssertNotNil(USBIFVendors.name(for: 0x2095)) // CE LINK
        XCTAssertNotNil(USBIFVendors.name(for: 0x2E99)) // Hynetek
        XCTAssertNotNil(USBIFVendors.name(for: 0x201C)) // Freeport
        XCTAssertNotNil(USBIFVendors.name(for: 0x2B1D)) // Lintes
    }
}
