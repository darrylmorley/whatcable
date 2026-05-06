import XCTest
@testable import WhatCableCore

final class CableTrustReportTests: XCTestCase {

    /// Valid cable-latency bits (0001 = ~10 ns, ~1 m). The decoder
    /// flags 0000 as a reserved value, so test fixtures that aren't
    /// specifically about latency need a real value.
    private static let validLatency: UInt32 = 1 << 13

    /// Build a synthetic SOP' identity. `cableVDO` is the raw VDO[3].
    private func cableIdentity(
        vendorID: Int = 0x05AC,
        endpoint: PDIdentity.Endpoint = .sopPrime,
        cableVDO: UInt32 = (0b10 << 5) | 0b011 | (1 << 13) // USB4 Gen 3, 5A, ~1m
    ) -> PDIdentity {
        PDIdentity(
            id: 1,
            endpoint: endpoint,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: vendorID,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(vendorID),
                0,
                0,
                cableVDO
            ],
            specRevision: 3
        )
    }

    func testCleanCableProducesNoFlags() {
        let report = CableTrustReport(identity: cableIdentity())
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.flags, [])
    }

    func testNonCableEndpointProducesNoFlags() {
        // SOP (port partner) shouldn't be evaluated as a cable.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0, endpoint: .sop))
        XCTAssertTrue(report.isEmpty)
    }

    func testZeroVendorIDFlags() {
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0))
        XCTAssertEqual(report.flags, [.zeroVendorID])
    }

    func testReservedSpeedEncodingFlags() {
        // speed=5 (reserved), current=1 (3A), valid latency
        let vdo = UInt32(0b101) | UInt32(1 << 5) | Self.validLatency
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        XCTAssertEqual(report.flags, [.reservedSpeedEncoding(5)])
    }

    func testReservedCurrentEncodingFlags() {
        // speed=1 (USB 3.2 Gen1), current=3 (reserved), valid latency
        let vdo = UInt32(0b001) | UInt32(3 << 5) | Self.validLatency
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        XCTAssertEqual(report.flags, [.reservedCurrentEncoding(3)])
    }

    func testAllThreeFlagsTogether() {
        // VID=0, speed=6 (reserved), current=3 (reserved), valid latency
        let vdo = UInt32(0b110) | UInt32(3 << 5) | Self.validLatency
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0, cableVDO: vdo))
        XCTAssertEqual(report.flags, [
            .zeroVendorID,
            .reservedSpeedEncoding(6),
            .reservedCurrentEncoding(3)
        ])
    }

    // MARK: - Cable Latency

    func testReservedCableLatencyFlags() {
        // 0000 invalid for both cable types
        let zeroLatency = UInt32(0b011) | UInt32(2 << 5) // no latency bits
        let report = CableTrustReport(identity: cableIdentity(cableVDO: zeroLatency))
        XCTAssertEqual(report.flags, [.reservedCableLatencyEncoding(0)])
    }

    func testActiveCableLatencyOpticalRangeIsValid() {
        // Build an active-cable identity. ufpProductType bits 29..27 = 100 = 4 (active).
        // Latency 1010 = ~2000 ns optical. Should not flag.
        let activeIdentity = PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [
                UInt32(4 << 27) | UInt32(0x05AC), // active cable ID header
                0,
                0,
                UInt32(0b011) | UInt32(2 << 5) | (UInt32(0b1010) << 13) // ~2000 ns
            ],
            specRevision: 3
        )
        let report = CableTrustReport(identity: activeIdentity)
        XCTAssertTrue(
            report.isEmpty,
            "Active cable with optical latency 1010 should not flag"
        )
    }

    // MARK: - VID 0xFFFF sentinel (neutral metadata, not a flag)

    func testVID_FFFF_DoesNotFireAnyFlag() {
        // 0xFFFF is the spec-defined "vendor opted out of USB-IF
        // registration" sentinel. It's allowed by the spec, so we treat
        // it as neutral metadata (surfaced via the vendor-name path)
        // rather than a warning-style trust flag.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0xFFFF))
        XCTAssertTrue(
            report.isEmpty,
            "0xFFFF must not surface as any TrustFlag (would render as a warning)"
        )
    }

    func testVID_FFFF_RendersDescriptiveVendorName() {
        // The neutral surface for 0xFFFF: vendorName describes it.
        XCTAssertEqual(
            VendorDB.name(for: 0xFFFF),
            "No vendor ID assigned (USB-PD spec sentinel)"
        )
        XCTAssertFalse(VendorDB.isRegistered(0xFFFF))
    }

    // MARK: - H3: VID not in USB-IF list

    func testRegisteredVendorDoesNotFireH3() {
        // 0x05AC (Apple) is in both the curated map and the bundled list.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0x05AC))
        XCTAssertTrue(report.isEmpty)
    }

    func testCableEmarkerChipVendorsDoNotFireH3() {
        // The six chip vendors observed in real cable reports
        // (#44, #45, #48, #49, #60, #62). All registered with USB-IF
        // per the bundled March 2026 list, so H3 must not fire.
        for vid in [0x20C2, 0x315C, 0x2095, 0x2E99, 0x201C, 0x2B1D] {
            let report = CableTrustReport(identity: cableIdentity(vendorID: vid))
            XCTAssertTrue(
                report.isEmpty,
                "H3 should not fire on registered VID \(String(format: "0x%04X", vid))"
            )
        }
    }

    func testUnregisteredVIDFiresH3() {
        // 0xDEAD is not a USB-IF assignment in any source we carry.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0xDEAD))
        XCTAssertEqual(report.flags, [.vidNotInUSBIFList(0xDEAD)])
    }

    func testZeroVendorIDDoesNotDoubleFire() {
        // VID 0 fires zeroVendorID (stronger signal); we don't also
        // want H3 firing as a noisier "0x0000 not registered" message.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0))
        XCTAssertEqual(report.flags, [.zeroVendorID])
        XCTAssertFalse(report.flags.contains { flag in
            if case .vidNotInUSBIFList = flag { return true }
            return false
        })
    }

    func testH3CombinesWithReservedEncodings() {
        // Unregistered VID + reserved speed bits = both flags.
        let vdo = UInt32(0b111) | UInt32(2 << 5) | Self.validLatency
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0xDEAD, cableVDO: vdo))
        XCTAssertEqual(report.flags, [
            .vidNotInUSBIFList(0xDEAD),
            .reservedSpeedEncoding(7)
        ])
    }

    // MARK: - JSON contract

    func testFlagCodesAreStable() {
        // Codes are part of the JSON contract; pin them.
        XCTAssertEqual(TrustFlag.zeroVendorID.code, "zeroVendorID")
        XCTAssertEqual(TrustFlag.reservedSpeedEncoding(5).code, "reservedSpeedEncoding")
        XCTAssertEqual(TrustFlag.reservedCurrentEncoding(3).code, "reservedCurrentEncoding")
        XCTAssertEqual(TrustFlag.reservedCableLatencyEncoding(0).code, "reservedCableLatencyEncoding")
        XCTAssertEqual(TrustFlag.vidNotInUSBIFList(0xDEAD).code, "vidNotInUSBIFList")
    }

    func testH3DetailIncludesVIDInHex() {
        let detail = TrustFlag.vidNotInUSBIFList(0xABCD).detail
        XCTAssertTrue(detail.contains("0xABCD"))
    }
}
