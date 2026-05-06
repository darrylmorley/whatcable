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
        let port = makePort(active: ["USB3"], superSpeed: true)
        let cable = PDIdentity(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [], specRevision: 0
        )
        let summary = PortSummary(port: port, identities: [cable])
        XCTAssertTrue(
            summary.bullets.contains(where: { $0.contains("e-marker") && $0.contains("advertises") }),
            "expected an e-marker bullet, got bullets: \(summary.bullets)"
        )
    }

    func testNoEmarkerCableProducesBasicCableBullet() {
        // PD-capable port (CC present) with no e-marker: existing wording.
        let port = makePort(active: ["USB2"], supported: ["CC", "USB2"], emarker: false)
        let summary = PortSummary(port: port)
        XCTAssertTrue(
            summary.bullets.contains(where: { $0.contains("does not advertise") }),
            "expected a basic-cable bullet, got: \(summary.bullets)"
        )
    }

    func testNoPDPortDoesNotClaimBasicCable() {
        // USB-only port (no CC = no PD = no SOP' query possible). Don't blame
        // the cable for a missing e-marker the OS could never have read. This
        // is the M4 Mac Mini front-port case from issue #50.
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        let summary = PortSummary(port: port)
        XCTAssertFalse(
            summary.bullets.contains(where: { $0.contains("does not advertise") }),
            "no-PD port should not claim 'basic cable', got: \(summary.bullets)"
        )
        XCTAssertTrue(
            summary.bullets.contains(where: { $0.contains("can't read cable details") }),
            "expected the 'port can't read cable details' bullet, got: \(summary.bullets)"
        )
    }

    func testMagSafePortDoesNotClaimNoPowerDelivery() {
        // Regression: a charging MagSafe port reports an empty
        // TransportsSupported (MagSafe negotiates PD over its own pins,
        // not the CC line). The previous logic tripped the "no Power
        // Delivery" branch because `pdCapable` is gated on CC. MagSafe
        // ports must not get any "can't read cable details" bullet at
        // all, since the cable is built into the brick.
        let magSafePort = USBCPort(
            id: 1,
            serviceName: "Port-MagSafe 3@1",
            className: "AppleHPMInterfaceType11",
            portDescription: "Port-MagSafe 3@1",
            portTypeDescription: "MagSafe 3",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [],
            transportsActive: ["CC"],
            transportsProvisioned: ["CC"],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
        let summary = PortSummary(
            port: magSafePort,
            sources: [usbPD(maxW: 100, winningW: 100)]
        )
        XCTAssertFalse(
            summary.bullets.contains(where: { $0.contains("no Power Delivery") }),
            "MagSafe must not claim 'no Power Delivery', got: \(summary.bullets)"
        )
        XCTAssertFalse(
            summary.bullets.contains(where: { $0.contains("can't read cable details") }),
            "MagSafe must not show the 'can't read cable details' bullet, got: \(summary.bullets)"
        )
        XCTAssertFalse(
            summary.bullets.contains(where: { $0.contains("does not advertise") }),
            "MagSafe must not show the 'basic cable' bullet, got: \(summary.bullets)"
        )
    }

    func testPDPortWithEmarkerStillShowsEmarker() {
        // Sanity: presence of an e-marker means PD must have fired, regardless
        // of whether the test fixture happens to set CC explicitly. We don't
        // want the new gate to suppress legitimate e-marker bullets.
        let port = makePort(
            active: ["USB3"],
            supported: ["CC", "USB2", "USB3"],
            superSpeed: true
        )
        let cable = PDIdentity(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [], specRevision: 0
        )
        let summary = PortSummary(port: port, identities: [cable])
        XCTAssertTrue(
            summary.bullets.contains(where: { $0.contains("e-marker") && $0.contains("advertises") }),
            "expected e-marker bullet on PD-capable port, got: \(summary.bullets)"
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
