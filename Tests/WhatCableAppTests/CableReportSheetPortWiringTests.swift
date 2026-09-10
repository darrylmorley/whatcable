import XCTest
import SwiftUI
@testable import WhatCable
import WhatCableCore

/// The "Report this cable" sheet is how a user actually files a cable report,
/// so it has to hand `CableReport.payload` the port the cable is plugged into.
/// Without it, a cable the port controller measures as active is filed as
/// passive (issue #111). The SwiftUI body cannot be asserted on, so the test
/// reads the sheet's `payload` directly.
final class CableReportSheetPortWiringTests: XCTestCase {

    /// The CalDigit 2M Thunderbolt 4 cable, VDO[3] bit 3 clear: nothing
    /// structural to infer from, so only the port controller can promote it.
    private func caldigitBitThreeClear() -> USBPDSOP {
        USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0x97,
            vdos: [0x1C002B1D, 0x00000000, 0x19010097, 0x32084842],
            specRevision: 3
        )
    }

    private func port(activeCable: Bool?) -> AppleHPMInterface {
        AppleHPMInterface(
            id: 1, serviceName: "Port-USB-C@1", className: "AppleHPMInterfaceType10",
            portDescription: nil, portTypeDescription: "USB-C", portNumber: 1,
            connectionActive: true, activeCable: activeCable, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "CIO"], transportsActive: ["CIO"],
            transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
    }

    @MainActor
    func testSheetFilesAPortPromotedCableAsActive() throws {
        let sheet = CableReportSheet(
            cableIdentity: caldigitBitThreeClear(),
            cioCapability: nil,
            port: port(activeCable: true),
            dismiss: {}
        )
        let payload = try XCTUnwrap(sheet.payload)
        XCTAssertEqual(payload.cable.type, "active")
        XCTAssertEqual(payload.cable.typeSource, "portController")
        XCTAssertTrue(payload.markdown.contains("| Type source | port controller |"))
    }

    @MainActor
    func testSheetLeavesAnOrdinaryPassiveCableAlone() throws {
        let sheet = CableReportSheet(
            cableIdentity: caldigitBitThreeClear(),
            cioCapability: nil,
            port: port(activeCable: false),
            dismiss: {}
        )
        let payload = try XCTUnwrap(sheet.payload)
        XCTAssertEqual(payload.cable.type, "passive")
        XCTAssertEqual(payload.cable.typeSource, "emarker")
        XCTAssertFalse(payload.markdown.contains("| Type source |"))
    }
}
