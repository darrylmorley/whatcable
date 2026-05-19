import Testing
@testable import WhatCableCore

/// Tests for the bundled SQLite vendor database. Most user-facing behaviour
/// is covered by VendorDBTests via the curated-then-bundled fallback chain;
/// these tests pin properties of the bundled data itself.
@Suite("CableDB bundled database")
struct CableDBTests {

    @Test("loads many entries")
    func loadsManyEntries() {
        // The bundled DB from USB-IF's March 2026 list has ~13,000
        // vendors. If the resource fails to load (e.g. SPM resource
        // wiring breaks) the count would be 0; pin a generous lower
        // bound so future refreshes that grow the list don't fail
        // this test, but a regression to "nothing loaded" would.
        #expect(CableDB.vendorCount > 10_000)
    }

    @Test("known VID resolves")
    func knownVIDResolves() {
        #expect(CableDB.vendorName(vid: 0x05AC) == "Apple")
    }

    @Test("zero VID returns name")
    func zeroVIDReturnsName() {
        // VID 0 is "USB Implementers Forum" in the USB-IF list. CableDB
        // returns the raw name; VendorDB filters it for display purposes.
        #expect(CableDB.vendorName(vid: 0) != nil)
    }

    @Test("zero VID is USB-IF registered")
    func zeroVIDIsUSBIFRegistered() {
        #expect(CableDB.isUSBIFRegistered(0))
    }

    @Test("unregistered VID returns nil")
    func unregisteredVIDReturnsNil() {
        // 0xDEAD (decimal 57005) is not a USB-IF assignment.
        #expect(CableDB.vendorName(vid: 0xDEAD) == nil)
        #expect(CableDB.isUSBIFRegistered(0xDEAD) == false)
    }

    @Test("USB-IF source tracking")
    func usbIFSourceTracking() {
        // Apple should be sourced from USB-IF.
        #expect(CableDB.isUSBIFRegistered(0x05AC))
    }

    @Test("no control characters in bundled names")
    func noControlCharactersInBundledNames() {
        // pdftotext emits form-feed (\u{000C}) at the start of each
        // page, which can land glued onto vendor names if the parser
        // doesn't strip control chars. Pin specific entries that were
        // affected before the parser fix (page-boundary vendors per
        // USB-IF March 2026), and a generic "vendor names contain no
        // ASCII control characters" check on a couple more.
        #expect(VendorDB.name(for: 1011) == "Adaptec, Inc.")
        #expect(VendorDB.name(for: 1069) == "Micronics")
        #expect(VendorDB.name(for: 1196) == "Micro Audiometrics Corp.")
        for vid in [1011, 1069, 1196, 1222, 1480] {
            let name = VendorDB.name(for: vid) ?? ""
            for scalar in name.unicodeScalars {
                #expect(
                    scalar.value >= 0x20 && scalar.value != 0x7F,
                    "vendor name for \(String(format: "0x%04X", vid)) contains control char U+\(String(scalar.value, radix: 16))"
                )
            }
        }
    }

    @Test("cable e-marker chip vendors all resolve")
    func cableEmarkerChipVendorsAllResolve() {
        // The six chip vendors observed in real cable reports.
        #expect(CableDB.vendorName(vid: 0x20C2) != nil) // Sumitomo
        #expect(CableDB.vendorName(vid: 0x315C) != nil) // Convenientpower
        #expect(CableDB.vendorName(vid: 0x2095) != nil) // CE LINK
        #expect(CableDB.vendorName(vid: 0x2E99) != nil) // Hynetek
        #expect(CableDB.vendorName(vid: 0x201C) != nil) // Freeport
        #expect(CableDB.vendorName(vid: 0x2B1D) != nil) // Lintes
    }

    @Test("usb.ids vendor resolves name")
    func usbIDsVendorResolvesName() {
        // VID 0x6666 ("Prototype product Vendor ID") is in the community
        // usb.ids list but not in USB-IF's official registry.
        #expect(CableDB.vendorName(vid: 0x6666) != nil)
    }

    @Test("usb.ids vendor not USB-IF registered")
    func usbIDsVendorNotUSBIFRegistered() {
        // Critical invariant: usb.ids entries resolve names for display
        // but must NOT suppress the vidNotInUSBIFList trust flag.
        #expect(CableDB.isUSBIFRegistered(0x6666) == false)
    }

    @Test("curated cable not found for unknown")
    func curatedCableNotFoundForUnknown() {
        #expect(CableDB.curatedCable(vid: 0xDEAD, pid: 0xBEEF, cableVDO: 0) == nil)
    }

    @Test("curated cable lookup")
    func curatedCableLookup() {
        // CalDigit TS5 Plus bundled cable: VID 0x01B6, PID 0x4003.
        let cable = CableDB.curatedCable(vid: 0x01B6, pid: 0x4003, cableVDO: 0x110A2644)
        #expect(cable != nil)
        #expect(cable?.brand.contains("CalDigit") ?? false)
    }

    @Test("cable count matches expected")
    func cableCountMatchesExpected() {
        // 12 distinct fingerprints from 13 reports (two CalDigit reports
        // share the same VID/PID/VDO, so they collapse to one row).
        #expect(CableDB.cableCount >= 10)
    }

    @Test("zeroed VID and PID never match a curated cable")
    func curatedCableRejectsZeroedVidPid() {
        // VID 0 + PID 0 means no vendor and no product identity. The
        // Cable VDO is a capability descriptor shared by every cable
        // using the same e-marker chip, not an identity, so it cannot
        // disambiguate them. Refuse any curated match. See #161.
        #expect(CableDB.curatedCable(vid: 0, pid: 0, cableVDO: 0) == nil)
        #expect(CableDB.curatedCable(vid: 0, pid: 0, cableVDO: 0x00082042) == nil)
        #expect(CableDB.curatedCable(vid: 0, pid: 0, cableVDO: 0x000A6642) == nil)
    }
}
