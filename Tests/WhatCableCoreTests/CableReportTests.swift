import XCTest
@testable import WhatCableCore

final class CableReportTests: XCTestCase {

    private func cableIdentity(
        vendorID: Int = 0x05AC,
        productID: Int = 0x1234,
        endpoint: PDIdentity.Endpoint = .sopPrime,
        vdos: [UInt32] = [
            // ID Header VDO: passive cable from VID 0x05AC
            (3 << 27) | UInt32(0x05AC),
            0,
            0,
            // Cable VDO: USB4 Gen 3 (0b011), 5A (0b10), passive,
            // latency 0001 (~1 m). A bare-zero VDO would trip the
            // reservedCableLatencyEncoding warning even though these
            // tests aren't about trust signals.
            (0b10 << 5) | 0b011 | (1 << 13)
        ]
    ) -> PDIdentity {
        PDIdentity(
            id: 1,
            endpoint: endpoint,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: vendorID,
            productID: productID,
            bcdDevice: 0,
            vdos: vdos,
            specRevision: 3
        )
    }

    func testPayloadOnlyBuiltForCableEndpoints() {
        XCTAssertNotNil(CableReport.payload(for: cableIdentity(endpoint: .sopPrime)))
        XCTAssertNotNil(CableReport.payload(for: cableIdentity(endpoint: .sopDoublePrime)))
        XCTAssertNil(CableReport.payload(for: cableIdentity(endpoint: .sop)))
        XCTAssertNil(CableReport.payload(for: cableIdentity(endpoint: .unknown)))
    }

    func testFingerprintFormatsHexAsUppercaseFourDigits() {
        let payload = CableReport.payload(for: cableIdentity(vendorID: 0x05AC, productID: 0x004C))!
        XCTAssertEqual(payload.cable.vendorIDHex, "0x05AC")
        XCTAssertEqual(payload.cable.productIDHex, "0x004C")
    }

    func testFingerprintLabelsUnregisteredVendor() {
        let payload = CableReport.payload(for: cableIdentity(vendorID: 0xDEAD))!
        XCTAssertEqual(payload.cable.vendorName, "Unregistered / unknown")
    }

    func testMarkdownIncludesFingerprintAndEnvironment() {
        let payload = CableReport.payload(for: cableIdentity(), appVersion: "1.2.3")!
        let md = payload.markdown
        XCTAssertTrue(md.contains("### Cable e-marker fingerprint"))
        XCTAssertTrue(md.contains("`0x05AC`"))
        XCTAssertTrue(md.contains("Apple"))
        XCTAssertTrue(md.contains("### Environment"))
        XCTAssertTrue(md.contains("WhatCable: `1.2.3`"))
        // No system info opt-in: should be flagged as not included.
        XCTAssertTrue(md.contains("not included by reporter"))
    }

    func testMarkdownIncludesSystemInfoWhenProvided() {
        let payload = CableReport.Payload(
            cable: CableReport.CableFingerprint(identity: cableIdentity()),
            system: CableReport.SystemInfo(macModel: "Mac15,3", macOSVersion: "14.5.0"),
            appVersion: "1.2.3"
        )
        let md = payload.markdown
        XCTAssertTrue(md.contains("Mac: `Mac15,3`"))
        XCTAssertTrue(md.contains("macOS: `14.5.0`"))
        XCTAssertFalse(md.contains("not included by reporter"))
    }

    func testGitHubURLTargetsTemplateAndCarriesFingerprint() throws {
        let payload = CableReport.payload(for: cableIdentity())!
        let url = payload.githubURL
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.host, "github.com")
        XCTAssertEqual(comps.path, "/darrylmorley/whatcable/issues/new")
        let items = Dictionary(uniqueKeysWithValues:
            (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(items["template"], "cable-report.yml")
        XCTAssertEqual(items["labels"], "cable-report")
        XCTAssertTrue(items["title"]?.hasPrefix("[Cable Report]") == true)
        XCTAssertTrue(items["fingerprint"]?.contains("0x05AC") == true)
    }

    func testIssueTitleIncludesVendorAndSpeed() {
        let payload = CableReport.payload(for: cableIdentity())!
        XCTAssertTrue(payload.issueTitle.contains("Apple"))
        XCTAssertTrue(payload.issueTitle.contains("USB4"))
    }

    func testFingerprintCarriesRawVDOs() {
        let payload = CableReport.payload(for: cableIdentity())!
        // Fixture has 4 VDOs: ID Header, Cert Stat, Product, Cable.
        XCTAssertEqual(payload.cable.vdos.count, 4)
        // VDO[0] = passive cable header (3 << 27) | 0x05AC.
        XCTAssertEqual(payload.cable.vdos[0], (3 << 27) | UInt32(0x05AC))
    }

    func testMarkdownIncludesRawVDOSection() {
        let payload = CableReport.payload(for: cableIdentity())!
        let md = payload.markdown
        XCTAssertTrue(md.contains("### Raw VDOs"))
        // ID Header VDO from the fixture: (3 << 27) | 0x05AC = 0x180005AC.
        XCTAssertTrue(md.contains("`0x180005AC`"))
        // Role labels appear so future readers can tell which is which
        // without having to know the spec layout.
        XCTAssertTrue(md.contains("ID Header"))
        XCTAssertTrue(md.contains("Cable"))
        XCTAssertTrue(md.contains("Product"))
    }

    func testMarkdownOmitsRawVDOSectionWhenAbsent() {
        // Identity with no VDOs (e.g. a cable that didn't respond to
        // Discover Identity at all) shouldn't render an empty Raw VDOs table.
        let id = PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [],
            specRevision: 3
        )
        let payload = CableReport.payload(for: id)!
        let md = payload.markdown
        XCTAssertFalse(md.contains("### Raw VDOs"))
    }

    // MARK: - USB-IF certification ID (from Cert Stat VDO)

    func testUSBIFCertIDPresentWhenNonZero() {
        let id = PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC),
                0x00012345,             // Cert Stat with XID
                0,
                (0b10 << 5) | 0b011 | (1 << 13)
            ],
            specRevision: 3
        )
        let payload = CableReport.payload(for: id)!
        XCTAssertEqual(payload.cable.usbifCertID, 0x00012345)
        let md = payload.markdown
        XCTAssertTrue(md.contains("USB-IF certification ID"))
        XCTAssertTrue(md.contains("0x00012345"))
    }

    func testUSBIFCertIDAbsentWhenZero() {
        // Calibration: Anker #60 and Caldigit #62 both ship with XID = 0.
        // We surface that as "none" rather than a trust signal.
        let payload = CableReport.payload(for: cableIdentity())!
        XCTAssertNil(payload.cable.usbifCertID)
        let md = payload.markdown
        XCTAssertTrue(md.contains("USB-IF certification ID"))
        XCTAssertTrue(md.contains("none (XID = 0)"))
    }

    func testUSBIFCertIDDistinguishesAbsentVDOFromZeroValue() {
        // Identity with only an ID Header VDO — macOS didn't surface a
        // Cert Stat. The fingerprint should record that explicitly,
        // not flatten it to "XID = 0", so calibration data stays
        // faithful to what the cable actually reported.
        let id = PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC) // only ID Header, no Cert Stat
            ],
            specRevision: 3
        )
        let payload = CableReport.payload(for: id)!
        XCTAssertNil(payload.cable.usbifCertID)
        let md = payload.markdown
        XCTAssertTrue(md.contains("USB-IF certification ID"))
        XCTAssertTrue(md.contains("not provided by this Mac"))
        XCTAssertFalse(
            md.contains("none (XID = 0)"),
            "Missing VDO[1] must not be rendered the same as a real zero XID"
        )
    }

    func testMarkdownLabelsExtraVDOsAsOther() {
        // PD response can include up to 7 VDOs (ID Header + Cert Stat +
        // Product + up to 4 Product Type VDOs). Anything past index 3 we
        // label "Other" rather than guessing.
        let id = PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC),
                0,
                0,
                (0b10 << 5) | 0b011 | (1 << 13), // valid 1m latency
                0xDEADBEEF,
                0xCAFEBABE
            ],
            specRevision: 3
        )
        let payload = CableReport.payload(for: id)!
        let md = payload.markdown
        XCTAssertTrue(md.contains("`0xDEADBEEF`"))
        XCTAssertTrue(md.contains("`0xCAFEBABE`"))
        XCTAssertTrue(md.contains("Other"))
    }
}
