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
            // Cable VDO: USB4 Gen 3 (0b011), 5A (0b10), passive
            (0b10 << 5) | 0b011
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
}
