import XCTest
@testable import WhatCableCore

final class ChargingDiagnosticTests: XCTestCase {

    // MARK: - Fixtures

    private var port: USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [],
            transportsActive: [],
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

    /// Build a USB-PD source advertising up to `maxW` and currently negotiating `winningW`.
    private func usbPD(maxW: Int, winningW: Int) -> PowerSource {
        let winning = PowerOption(voltageMV: 20_000, maxCurrentMA: winningW * 50, maxPowerMW: winningW * 1000)
        let max = PowerOption(voltageMV: 20_000, maxCurrentMA: maxW * 50, maxPowerMW: maxW * 1000)
        return PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [max], winning: winning
        )
    }

    private func brickID(maxW: Int, winningW: Int) -> PowerSource {
        let winning = PowerOption(voltageMV: 20_000, maxCurrentMA: winningW * 50, maxPowerMW: winningW * 1000)
        let max = PowerOption(voltageMV: 20_000, maxCurrentMA: maxW * 50, maxPowerMW: maxW * 1000)
        return PowerSource(
            id: 2, name: "Brick ID", parentPortType: 0x11, parentPortNumber: 1,
            options: [max], winning: winning
        )
    }

    private func brickIDWithoutPDOs() -> PowerSource {
        PowerSource(
            id: 2, name: "Brick ID", parentPortType: 0x11, parentPortNumber: 1,
            options: [], winning: nil
        )
    }

    /// Build a cable e-marker identity advertising the given watt rating.
    /// We pin watts via maxV/current bits: 5A @ 20V = 100W, 3A @ 20V = 60W.
    private func cableIdentity(watts: Int) -> PDIdentity {
        // Latency = 0001 (~10 ns / ~1 m). Real cables emit a non-zero
        // latency; using 0 here would make every fixture trip the
        // reservedCableLatencyEncoding warning even though these tests
        // care only about the wattage maths.
        let validLatency: UInt32 = 1 << 13
        let cableVDO: UInt32 = {
            switch watts {
            case 100: return 0b011 | (1 << 4) | (2 << 5) | validLatency  // 5A passive
            case 60:  return 0b000 | (1 << 5)            | validLatency  // 3A USB2
            case 240: return 0b011 | (2 << 5) | (3 << 9) | validLatency  // 5A @ 50V (EPR)
            default:  fatalError("unhandled fixture wattage \(watts)")
            }
        }()
        // ID header: ufpProductType = 3 (passive cable), bits 29..27 = 011
        let idHeader: UInt32 = 0x1800_0000
        // VDO[3] holds the cable VDO; pad indices 1 and 2 with zero.
        return PDIdentity(
            id: 2, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 0
        )
    }

    // MARK: - Cases

    /// Same shape as `port` but with ConnectionActive=false. Reproduces the
    /// "Charging well at 94W" bug on a disconnected MagSafe port: the
    /// PowerSource node still exposes a winning PDO with cached values, and
    /// without this guard we would still report active charging.
    private var inactiveMagSafePort: USBCPort {
        USBCPort(
            id: 1, serviceName: "Port-MagSafe 3@1", className: "AppleHPMInterfaceType11",
            portDescription: nil, portTypeDescription: "MagSafe 3", portNumber: 1,
            connectionActive: false,
            activeCable: nil, opticalCable: nil, usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
    }

    func testReturnsNilOnInactivePortWithStalePDO() {
        let diag = ChargingDiagnostic(
            port: inactiveMagSafePort,
            sources: [usbPD(maxW: 94, winningW: 94)],
            identities: []
        )
        XCTAssertNil(diag)
    }

    func testReturnsNilWithoutUSBPDSource() {
        let diag = ChargingDiagnostic(port: port, sources: [], identities: [])
        XCTAssertNil(diag)
    }

    func testCableLimitsCharger() {
        // 96W charger + 60W cable -> cable is the bottleneck
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [cableIdentity(watts: 60)]
        )
        guard case .cableLimit(let cableW, let chargerW) = diag?.bottleneck else {
            return XCTFail("expected .cableLimit, got \(String(describing: diag?.bottleneck))")
        }
        XCTAssertEqual(cableW, 60)
        XCTAssertEqual(chargerW, 96)
        XCTAssertTrue(diag!.isWarning)
    }

    func testMacIsRequestingLess() {
        // 96W charger + 100W cable, but Mac is only pulling 30W (battery near full)
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 30)],
            identities: [cableIdentity(watts: 100)]
        )
        guard case .macLimit(let n, let chargerW, let cableW) = diag?.bottleneck else {
            return XCTFail("expected .macLimit, got \(String(describing: diag?.bottleneck))")
        }
        XCTAssertEqual(n, 30)
        XCTAssertEqual(chargerW, 96)
        XCTAssertEqual(cableW, 100)
    }

    func testEverythingMatched() {
        // 96W charger + 100W cable + 96W winning -> .fine
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)]
        )
        guard case .fine(let n) = diag?.bottleneck else {
            return XCTFail("expected .fine, got \(String(describing: diag?.bottleneck))")
        }
        XCTAssertEqual(n, 96)
        XCTAssertFalse(diag!.isWarning)
    }

    func testNoCableEmarker_FineIfMatched() {
        // Charger advertises 60W, Mac negotiates 60W, no cable identity.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 60, winningW: 60)],
            identities: []
        )
        if case .fine = diag?.bottleneck { return }
        XCTFail("expected .fine without cable identity, got \(String(describing: diag?.bottleneck))")
    }

    func testBrickIDPowerSourceIsValidForMagSafe() {
        let diag = ChargingDiagnostic(
            port: port,
            sources: [brickID(maxW: 140, winningW: 140)],
            identities: []
        )
        guard case .fine(let n) = diag?.bottleneck else {
            return XCTFail("expected .fine from Brick ID source, got \(String(describing: diag?.bottleneck))")
        }
        XCTAssertEqual(n, 140)
    }

    func testUSBPDIsPreferredWhenUSBPDAndBrickIDAreBothPresent() {
        let diag = ChargingDiagnostic(
            port: port,
            sources: [brickID(maxW: 30, winningW: 30), usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)]
        )
        guard case .fine(let n) = diag?.bottleneck else {
            return XCTFail("expected .fine from USB-PD source, got \(String(describing: diag?.bottleneck))")
        }
        XCTAssertEqual(n, 96)
    }

    func testSystemAdapterWattsAreNotUsedAsPerPortFallback() {
        // Regression for issue #46. Per-port USB-PD source has no winning PDO
        // and no options, so we have nothing real to report. The system-wide
        // adapter wattage must NOT be substituted, because on a Mac with two
        // chargers attached it belongs to a different port.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [brickIDWithoutPDOs()],
            identities: [],
            adapter: AdapterInfo(watts: 140, isCharging: nil, source: "AC")
        )
        XCTAssertNil(diag)
    }

    func testZeroWattWinningPDOSuppressesDiagnostic() {
        // A winning PDO with maxPowerMW rounding to 0 is just as useless as
        // a missing one. Don't render "Charging well at 0W".
        let zeroWinning = PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [],
            winning: PowerOption(voltageMV: 0, maxCurrentMA: 0, maxPowerMW: 0)
        )
        let diag = ChargingDiagnostic(port: port, sources: [zeroWinning], identities: [])
        XCTAssertNil(diag)
    }

    func testTwoPortsWithDifferentChargersDoNotCrossContaminate() {
        // Issue #46: M1 MBA with an 87W adapter on @1 and a 30W power bank on
        // @2 that briefly reports a USB-PD source without a winning PDO.
        // The diagnostic for @2 must not borrow the 87W system adapter watts.
        let port2 = USBCPort(
            id: 2, serviceName: "Port-USB-C@2", className: "AppleHPMInterfaceType10",
            portDescription: nil, portTypeDescription: "USB-C", portNumber: 2,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
        let bareUSBPDOnPort2 = PowerSource(
            id: 99, name: "USB-PD", parentPortType: 2, parentPortNumber: 2,
            options: [], winning: nil
        )
        let diag = ChargingDiagnostic(
            port: port2,
            sources: [bareUSBPDOnPort2],
            identities: [],
            adapter: AdapterInfo(watts: 87, isCharging: nil, source: "AC")
        )
        XCTAssertNil(diag, "port @2 must not inherit port @1's adapter wattage")
    }

    // MARK: - Edge cases (#15)

    func testStalePDOAtZeroWattsOnDisconnectedPort() {
        let diag = ChargingDiagnostic(
            port: inactiveMagSafePort,
            sources: [usbPD(maxW: 0, winningW: 0)],
            identities: []
        )
        XCTAssertNil(diag)
    }

    func testStalePDOAt240WOnDisconnectedPort() {
        let diag = ChargingDiagnostic(
            port: inactiveMagSafePort,
            sources: [usbPD(maxW: 240, winningW: 240)],
            identities: []
        )
        XCTAssertNil(diag)
    }

    func testCable240W_Charger60W_CableIsNotBottleneck() {
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 60, winningW: 60)],
            identities: [cableIdentity(watts: 240)]
        )
        guard case .fine(let n) = diag?.bottleneck else {
            return XCTFail("expected .fine, got \(String(describing: diag?.bottleneck))")
        }
        XCTAssertEqual(n, 60)
    }

    func testMagSafePowerSourceUsesCorrectPortType() {
        let magSafeSource = PowerSource(
            id: 1, name: "USB-PD", parentPortType: 0x11, parentPortNumber: 1,
            options: [PowerOption(voltageMV: 20_000, maxCurrentMA: 4700, maxPowerMW: 94_000)],
            winning: PowerOption(voltageMV: 20_000, maxCurrentMA: 4700, maxPowerMW: 94_000)
        )
        let magSafePort = USBCPort(
            id: 1, serviceName: "Port-MagSafe 3@1", className: "AppleHPMInterfaceType11",
            portDescription: nil, portTypeDescription: "MagSafe 3", portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: ["PortType": "17"]
        )
        let diag = ChargingDiagnostic(
            port: magSafePort,
            sources: [magSafeSource],
            identities: []
        )
        guard case .fine(let n) = diag?.bottleneck else {
            return XCTFail("expected .fine, got \(String(describing: diag?.bottleneck))")
        }
        XCTAssertEqual(n, 94)
        XCTAssertEqual(magSafePort.portKey, magSafeSource.portKey)
    }

    func testMultipleSourcesPicksUSBPD() {
        let brickID = PowerSource(
            id: 10, name: "Brick ID", parentPortType: 2, parentPortNumber: 1,
            options: [PowerOption(voltageMV: 20_000, maxCurrentMA: 1500, maxPowerMW: 30_000)],
            winning: PowerOption(voltageMV: 20_000, maxCurrentMA: 1500, maxPowerMW: 30_000)
        )
        let usbPDSource = usbPD(maxW: 96, winningW: 96)
        // Brick ID listed first to ensure USB-PD is found regardless of order
        let diag = ChargingDiagnostic(
            port: port,
            sources: [brickID, usbPDSource],
            identities: [cableIdentity(watts: 100)]
        )
        guard case .fine(let n) = diag?.bottleneck else {
            return XCTFail("expected .fine from USB-PD source, got \(String(describing: diag?.bottleneck))")
        }
        XCTAssertEqual(n, 96)
    }
}
