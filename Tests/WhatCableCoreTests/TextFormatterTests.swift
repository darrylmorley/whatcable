import XCTest
import WhatCableCore

final class TextFormatterTests: XCTestCase {

    // MARK: - Fixtures

    private func makePort(connected: Bool = true) -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: connected,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: true,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["USB2", "USB3"],
            transportsActive: connected ? ["USB3"] : [],
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: ["PortType": "2"]
        )
    }

    // MARK: - Smoke

    func testRenderProducesNonEmptyOutput() {
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        XCTAssertFalse(output.isEmpty)
    }

    func testRenderEmptyPortsProducesNonEmptyOutput() {
        let output = TextFormatter.render(
            ports: [], sources: [], identities: [], showRaw: false
        )
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains("No USB-C"))
    }

    // MARK: - Headline passthrough

    func testHeadlineFromPortSummaryAppearsVerbatim() {
        let port = makePort(connected: false)
        let summary = PortSummary(port: port)
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: false
        )
        XCTAssertTrue(
            output.contains(summary.headline),
            "expected headline \"\(summary.headline)\" in render output"
        )
    }

    // MARK: - ANSI escapes absent when not a TTY

    func testNoANSIEscapesInNonTTYOutput() {
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        XCTAssertFalse(
            output.contains("\u{1B}["),
            "ANSI escape sequences should not appear when stdout is not a TTY"
        )
    }

    // MARK: - Cable trust signals

    /// Build an SOP' identity for trust-signal tests. `cableVDO` is VDO[3].
    /// Default uses USB4 Gen3 / 5A / ~1m latency, which produces no flags.
    private func cableIdentity(
        portNumber: Int = 1,
        vendorID: Int = 0x05AC,
        cableVDO: UInt32 = (0b10 << 5) | 0b011 | (1 << 13)
    ) -> PDIdentity {
        PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: portNumber,
            vendorID: vendorID,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(vendorID), 0, 0, cableVDO],
            specRevision: 3
        )
    }

    func testNoTrustSignalsHeadingWhenCableIsClean() {
        let port = makePort()
        let cable = cableIdentity(portNumber: port.portNumber ?? 1)
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [cable], showRaw: false
        )
        XCTAssertFalse(
            output.contains("Cable trust signals"),
            "Clean cable should not surface a trust-signals section"
        )
    }

    func testTrustSignalsRenderWhenFlagFires() {
        let port = makePort()
        let cable = cableIdentity(portNumber: port.portNumber ?? 1, vendorID: 0)
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [cable], showRaw: false
        )
        XCTAssertTrue(output.contains("Cable trust signals"))
        XCTAssertTrue(output.contains(TrustFlag.zeroVendorID.title))
        XCTAssertTrue(output.contains(TrustFlag.zeroVendorID.detail))
    }

    func testMultipleTrustFlagsAllRender() {
        let port = makePort()
        // Unregistered VID + reserved speed = two flags.
        let vdo = UInt32(0b111) | UInt32(2 << 5) | UInt32(1 << 13)
        let cable = cableIdentity(
            portNumber: port.portNumber ?? 1,
            vendorID: 0xDEAD,
            cableVDO: vdo
        )
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [cable], showRaw: false
        )
        XCTAssertTrue(output.contains(TrustFlag.vidNotInUSBIFList(0xDEAD).title))
        XCTAssertTrue(output.contains(TrustFlag.reservedSpeedEncoding(7).title))
    }

    // MARK: - Active Cable VDO 2 raw view

    func testActiveCableVDO2SectionAppearsInRawMode() {
        let port = makePort()
        // VDO2 with optical + retimer + isolated + USB4 supported (bit 8 = 0).
        var vdo4: UInt32 = 0
        vdo4 |= UInt32(1) << 10  // optical
        vdo4 |= UInt32(1) << 9   // retimer
        vdo4 |= UInt32(1) << 2   // isolated
        // bits 8 / 5 / 4 left at 0 = USB4 / USB 3.2 / USB 2.0 supported.
        let vdo3: UInt32 = UInt32(0b011) | UInt32(2 << 5) | UInt32(1 << 13) | UInt32(0b10 << 11)
        let active = PDIdentity(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: port.portNumber ?? 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(4 << 27) | UInt32(0x05AC), 0, 0, vdo3, vdo4],
            specRevision: 3
        )
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [active], showRaw: true
        )
        XCTAssertTrue(output.contains("Active cable (VDO 2)"))
        XCTAssertTrue(output.contains("Physical connection") && output.contains("Optical"))
        XCTAssertTrue(output.contains("Active element") && output.contains("Re-timer"))
        XCTAssertTrue(output.contains("USB4 supported") && output.contains("Yes"))
    }

    func testActiveCableVDO2SectionAbsentWithoutRawFlag() {
        let port = makePort()
        let vdo3: UInt32 = UInt32(0b011) | UInt32(2 << 5) | UInt32(1 << 13) | UInt32(0b10 << 11)
        let active = PDIdentity(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: port.portNumber ?? 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(4 << 27) | UInt32(0x05AC), 0, 0, vdo3, 0],
            specRevision: 3
        )
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [active], showRaw: false
        )
        XCTAssertFalse(
            output.contains("Active cable (VDO 2)"),
            "VDO 2 deep view should only render with --raw"
        )
    }

    func testTrustSignalsSuppressedForNonCableEndpoint() {
        // SOP (port partner) shouldn't be evaluated as a cable, so even
        // a zero VID on a port-partner identity shouldn't trip the section.
        let port = makePort()
        let partner = PDIdentity(
            id: 1,
            endpoint: .sop,
            parentPortType: 2,
            parentPortNumber: port.portNumber ?? 1,
            vendorID: 0,
            productID: 0,
            bcdDevice: 0,
            vdos: [0, 0, 0, 0],
            specRevision: 3
        )
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [partner], showRaw: false
        )
        XCTAssertFalse(output.contains("Cable trust signals"))
    }
}
