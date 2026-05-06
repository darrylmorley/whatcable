import XCTest
@testable import WhatCableCore

final class CableTrustReportTests: XCTestCase {

    /// Build a synthetic SOP' identity. `cableVDO` is the raw VDO[3].
    private func cableIdentity(
        vendorID: Int = 0x05AC,
        endpoint: PDIdentity.Endpoint = .sopPrime,
        cableVDO: UInt32 = (0b10 << 5) | 0b011 // USB4 Gen 3, 5A
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
        // speed=5 (reserved), current=1 (3A)
        let vdo = UInt32(0b101) | UInt32(1 << 5)
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        XCTAssertEqual(report.flags, [.reservedSpeedEncoding(5)])
    }

    func testReservedCurrentEncodingFlags() {
        // speed=1 (USB 3.2 Gen1), current=3 (reserved)
        let vdo = UInt32(0b001) | UInt32(3 << 5)
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        XCTAssertEqual(report.flags, [.reservedCurrentEncoding(3)])
    }

    func testAllThreeFlagsTogether() {
        // VID=0, speed=6 (reserved), current=3 (reserved)
        let vdo = UInt32(0b110) | UInt32(3 << 5)
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0, cableVDO: vdo))
        XCTAssertEqual(report.flags, [
            .zeroVendorID,
            .reservedSpeedEncoding(6),
            .reservedCurrentEncoding(3)
        ])
    }

    func testFlagCodesAreStable() {
        // Codes are part of the JSON contract; pin them.
        XCTAssertEqual(TrustFlag.zeroVendorID.code, "zeroVendorID")
        XCTAssertEqual(TrustFlag.reservedSpeedEncoding(5).code, "reservedSpeedEncoding")
        XCTAssertEqual(TrustFlag.reservedCurrentEncoding(3).code, "reservedCurrentEncoding")
    }
}
