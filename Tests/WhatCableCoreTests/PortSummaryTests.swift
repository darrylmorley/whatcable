import XCTest
@testable import WhatCableCore

/// Pins the user-facing headline strings produced by PortSummary so refactors
/// of the state machine can't silently change what users see in the popover.
final class PortSummaryTests: XCTestCase {

    // MARK: - Fixtures

    private func makePort(
        connected: Bool = true,
        active: [String] = [],
        supported: [String] = [],
        superSpeed: Bool? = nil,
        emarker: Bool? = nil
    ) -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: connected,
            activeCable: emarker,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: superSpeed,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: supported,
            transportsActive: active,
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: [:]
        )
    }

    private func usbPD(maxW: Int, winningW: Int) -> PowerSource {
        let winning = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: winningW * 50,
            maxPowerMW: winningW * 1000
        )
        let max = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: maxW * 50,
            maxPowerMW: maxW * 1000
        )
        return PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [max], winning: winning
        )
    }

    private func brickID(maxW: Int, winningW: Int) -> PowerSource {
        let winning = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: winningW * 50,
            maxPowerMW: winningW * 1000
        )
        let max = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: maxW * 50,
            maxPowerMW: maxW * 1000
        )
        return PowerSource(
            id: 2, name: "Brick ID", parentPortType: 0x11, parentPortNumber: 1,
            options: [max], winning: winning
        )
    }

    // MARK: - Disconnected

    func testNothingConnectedHeadline() {
        let summary = PortSummary(port: makePort(connected: false))
        XCTAssertEqual(summary.status, .empty)
        XCTAssertEqual(summary.headline, "Nothing connected")
        XCTAssertTrue(summary.bullets.isEmpty)
    }

    // MARK: - Charging

    func testChargingOnlyWithoutDataHasWattageSuffix() {
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 60)])
        XCTAssertEqual(summary.status, .charging)
        XCTAssertEqual(summary.headline, "Charging · 96W charger")
    }

    func testChargingOnlyWithoutPDOOptionsOmitsWattage() {
        // No options means no wattage suffix; the headline just says "Charging only".
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(port: port)
        XCTAssertEqual(summary.status, .charging)
        XCTAssertEqual(summary.headline, "Charging only")
    }

    func testMagSafeBrickIDSourceCountsAsChargingPower() {
        let port = makePort(connected: true, active: [], supported: [])
        let summary = PortSummary(port: port, sources: [brickID(maxW: 140, winningW: 140)])
        XCTAssertEqual(summary.status, .charging)
        XCTAssertEqual(summary.headline, "Charging · 140W charger")
    }

    // MARK: - USB

    func testUSB2OnlyIsSlowDevice() {
        let port = makePort(active: ["USB2"], supported: ["USB2"])
        let summary = PortSummary(port: port)
        XCTAssertEqual(summary.status, .dataDevice)
        XCTAssertTrue(
            summary.headline.hasPrefix("Slow USB device or charge-only cable"),
            "got: \(summary.headline)"
        )
    }

    func testUSB3IsUSBDevice() {
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        let summary = PortSummary(port: port)
        XCTAssertEqual(summary.status, .dataDevice)
        XCTAssertTrue(summary.headline.hasPrefix("USB device"), "got: \(summary.headline)")
    }

    // MARK: - Thunderbolt and Display

    func testThunderboltLink() {
        let port = makePort(active: ["CIO", "USB3"], supported: ["CIO", "USB3"])
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 60)])
        XCTAssertEqual(summary.status, .thunderboltCable)
        XCTAssertEqual(summary.headline, "Thunderbolt / USB4 · 96W charger")
    }

    func testUSBCWithVideo() {
        let port = makePort(active: ["USB3", "DisplayPort"], superSpeed: true)
        let summary = PortSummary(port: port)
        XCTAssertEqual(summary.status, .displayCable)
        XCTAssertEqual(summary.headline, "USB-C with video")
    }

    func testDisplayOnly() {
        let port = makePort(active: ["DisplayPort"])
        let summary = PortSummary(port: port)
        XCTAssertEqual(summary.status, .displayCable)
        XCTAssertEqual(summary.headline, "Display connected")
    }

    // MARK: - Bullets

    func testEmarkerCableProducesEmarkerBullet() {
        let port = makePort(active: ["USB3"], superSpeed: true, emarker: true)
        let summary = PortSummary(port: port)
        XCTAssertTrue(
            summary.bullets.contains(where: { $0.contains("e-marker") && $0.contains("advertises") }),
            "expected an e-marker bullet, got bullets: \(summary.bullets)"
        )
    }

    func testNoEmarkerCableProducesBasicCableBullet() {
        let port = makePort(active: ["USB2"], emarker: false)
        let summary = PortSummary(port: port)
        XCTAssertTrue(
            summary.bullets.contains(where: { $0.contains("does not advertise") }),
            "expected a basic-cable bullet, got: \(summary.bullets)"
        )
    }

    func testNegotiatedPDOAppearsInBullets() {
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 60)])
        XCTAssertTrue(
            summary.bullets.contains(where: { $0.contains("Currently negotiated") }),
            "expected a negotiated PDO bullet, got: \(summary.bullets)"
        )
    }
}
