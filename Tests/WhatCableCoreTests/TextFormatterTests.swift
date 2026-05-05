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
}
