import Testing
@testable import WhatCableCore

@Suite("Charging Diagnostic")
struct ChargingDiagnosticTests {

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

    /// A plain Type-C source: a non-PD charger delivering default USB-C
    /// current (5V/3A = 15W). This is the only source such a charger
    /// publishes; before "TypeC" was added to preferredChargingSource it was
    /// invisible and this port produced no diagnostic at all.
    private func typeC(winningW: Int) -> PowerSource {
        let winning = PowerOption(voltageMV: 5_000, maxCurrentMA: 3_000, maxPowerMW: winningW * 1000)
        return PowerSource(
            id: 3, name: "TypeC", parentPortType: 2, parentPortNumber: 1,
            options: [winning], winning: winning
        )
    }

    /// Build a cable e-marker identity advertising the given watt rating.
    /// We pin watts via maxV/current bits: 5A @ 20V = 100W, 3A @ 20V = 60W.
    private func cableIdentity(watts: Int) -> USBPDSOP {
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
        return USBPDSOP(
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

    @Test("Returns nil on inactive port with stale PDO")
    func returnsNilOnInactivePortWithStalePDO() {
        let diag = ChargingDiagnostic(
            port: inactiveMagSafePort,
            sources: [usbPD(maxW: 94, winningW: 94)],
            identities: []
        )
        #expect(diag == nil)
    }

    @Test("Returns nil without USB-PD source")
    func returnsNilWithoutUSBPDSource() {
        let diag = ChargingDiagnostic(port: port, sources: [], identities: [])
        #expect(diag == nil)
    }

    @Test("A non-PD Type-C charger is recognised, not ignored")
    func typeCChargerRecognised() {
        // Before "TypeC" joined preferredChargingSource this returned nil: a
        // basic 15W USB-C charger showed no charging diagnostic at all.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [typeC(winningW: 15)],
            identities: []
        )
        #expect(diag != nil)
        #expect(diag?.chargerW == 15)
    }

    @Test("A winning Type-C source is not shadowed by a bare Brick ID identity")
    func typeCWinnerNotShadowedByBrickID() {
        // m2_macos27.0 shape: a bare Brick ID node with no contract sits
        // alongside a winning TypeC (15W). Name priority alone would pick the
        // contract-less Brick ID and report nothing; the winning-preferred
        // selection must surface the 15W TypeC instead.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [brickIDWithoutPDOs(), typeC(winningW: 15)],
            identities: []
        )
        #expect(diag != nil)
        #expect(diag?.chargerW == 15)
    }

    @Test("USB-PD still wins over a co-present Type-C source")
    func usbPDPreferredOverTypeC() {
        // A port advertising both a negotiated USB-PD contract and the plain
        // Type-C fallback must diagnose from the PD contract, not the 15W floor.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [typeC(winningW: 15), usbPD(maxW: 96, winningW: 96)],
            identities: []
        )
        #expect(diag?.chargerW == 96)
    }

    @Test("Cable limits charger")
    func cableLimitsCharger() {
        // 96W charger + 60W cable -> cable is the bottleneck
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [cableIdentity(watts: 60)]
        )
        guard case .cableLimit(let cableW, let chargerW) = diag?.bottleneck else {
            Issue.record("expected .cableLimit, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(cableW == 60)
        #expect(chargerW == 96)
        #expect(diag!.isWarning)
    }

    @Test("Mac is requesting less")
    func macIsRequestingLess() {
        // 96W charger + 100W cable, but Mac is only pulling 30W (battery near full)
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 30)],
            identities: [cableIdentity(watts: 100)]
        )
        guard case .macLimit(let n, let chargerW, let cableW) = diag?.bottleneck else {
            Issue.record("expected .macLimit, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(n == 30)
        #expect(chargerW == 96)
        #expect(cableW == 100)
        // The Mac drawing less than the charger/cable can do is normal
        // (battery near full / idle), so this is informational, not a warning.
        #expect(diag!.isWarning == false)
    }

    @Test("Everything matched")
    func everythingMatched() {
        // 96W charger + 100W cable + 96W winning -> .fine
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)]
        )
        guard case .fine(let n) = diag?.bottleneck else {
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(n == 96)
        #expect(diag!.isWarning == false)
    }

    @Test("Battery full: banner says 'not charging', not 'charging well'")
    func batteryFull_BannerSaysNotCharging() {
        // Same as "Everything matched" but the battery is full. The banner
        // is the single place that explains it (PortSummary drops its
        // redundant battery-full subtitle), so it must still appear here.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)],
            batteryFullyCharged: true
        )
        guard case .fine(let n) = diag?.bottleneck else {
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(n == 96)
        #expect(diag!.isWarning == false)
        #expect(diag!.summary == "Battery full, not charging")
    }

    @Test("Battery not full: still 'charging well'")
    func batteryNotFull_ChargingWell() {
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)],
            batteryFullyCharged: false
        )
        guard case .fine = diag?.bottleneck else {
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(diag!.summary == "Charging well · up to 96W")
    }

    @Test("No cable e-marker, fine if matched")
    func noCableEmarker_FineIfMatched() {
        // Charger advertises 60W, Mac negotiates 60W, no cable identity.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 60, winningW: 60)],
            identities: []
        )
        if case .fine = diag?.bottleneck { return }
        Issue.record("expected .fine without cable identity, got \(String(describing: diag?.bottleneck))")
    }

    @Test("Brick ID power source is valid for MagSafe")
    func brickIDPowerSourceIsValidForMagSafe() {
        let diag = ChargingDiagnostic(
            port: port,
            sources: [brickID(maxW: 140, winningW: 140)],
            identities: []
        )
        guard case .fine(let n) = diag?.bottleneck else {
            Issue.record("expected .fine from Brick ID source, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(n == 140)
    }

    @Test("USB-PD is preferred when both USB-PD and Brick ID present")
    func usbPDIsPreferredWhenBothPresent() {
        let diag = ChargingDiagnostic(
            port: port,
            sources: [brickID(maxW: 30, winningW: 30), usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)]
        )
        guard case .fine(let n) = diag?.bottleneck else {
            Issue.record("expected .fine from USB-PD source, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(n == 96)
    }

    @Test("System adapter watts are not used as per-port fallback")
    func systemAdapterWattsAreNotUsedAsPerPortFallback() {
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
        #expect(diag == nil)
    }

    @Test("Zero watt winning PDO suppresses diagnostic")
    func zeroWattWinningPDOSuppressesDiagnostic() {
        // A winning PDO with maxPowerMW rounding to 0 is just as useless as
        // a missing one. Don't render "Charging well at 0W".
        let zeroWinning = PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [],
            winning: PowerOption(voltageMV: 0, maxCurrentMA: 0, maxPowerMW: 0)
        )
        let diag = ChargingDiagnostic(port: port, sources: [zeroWinning], identities: [])
        #expect(diag == nil)
    }

    @Test("Two ports with different chargers do not cross-contaminate")
    func twoPortsWithDifferentChargersDoNotCrossContaminate() {
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
        #expect(diag == nil, "port @2 must not inherit port @1's adapter wattage")
    }

    // MARK: - Edge cases (#15)

    @Test("Stale PDO at zero watts on disconnected port")
    func stalePDOAtZeroWattsOnDisconnectedPort() {
        let diag = ChargingDiagnostic(
            port: inactiveMagSafePort,
            sources: [usbPD(maxW: 0, winningW: 0)],
            identities: []
        )
        #expect(diag == nil)
    }

    @Test("Stale PDO at 240W on disconnected port")
    func stalePDOAt240WOnDisconnectedPort() {
        let diag = ChargingDiagnostic(
            port: inactiveMagSafePort,
            sources: [usbPD(maxW: 240, winningW: 240)],
            identities: []
        )
        #expect(diag == nil)
    }

    @Test("Cable 240W, charger 60W, cable is not bottleneck")
    func cable240W_Charger60W_CableIsNotBottleneck() {
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 60, winningW: 60)],
            identities: [cableIdentity(watts: 240)]
        )
        guard case .fine(let n) = diag?.bottleneck else {
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(n == 60)
    }

    @Test("MagSafe power source uses correct port type")
    func magSafePowerSourceUsesCorrectPortType() {
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
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(n == 94)
        #expect(magSafePort.portKey == magSafeSource.portKey)
    }

    @Test("Multiple sources picks USB-PD")
    func multipleSourcesPicksUSBPD() {
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
            Issue.record("expected .fine from USB-PD source, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(n == 96)
    }

    // MARK: - System adapter fallback (issue #141)

    @Test("System adapter fallback shows wattage")
    func systemAdapterFallbackShowsWattage() {
        // Issue #141: TB dock delivers power but only registers a Brick ID
        // source with no PDOs. With a single active port and a system
        // adapter reading, the fallback should produce a diagnostic.
        let wattageSource = ChargerWattageSource.resolve(
            portSources: [brickIDWithoutPDOs()],
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: AdapterInfo(watts: 96, isCharging: nil, source: "AC")
        )
        #expect(wattageSource == .systemAdapterFallback(watts: 96))

        let diag = ChargingDiagnostic(
            port: port,
            sources: [brickIDWithoutPDOs()],
            identities: [],
            wattageSource: wattageSource
        )
        guard case .chargerLimit(let w) = diag?.bottleneck else {
            Issue.record("expected .chargerLimit from adapter fallback, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(w == 96)
        #expect(diag?.summary == "System reports charger at 96W")
    }

    @Test("System adapter fallback blocked when USB-PD present")
    func systemAdapterFallbackBlockedWhenUSBPDPresent() {
        // Issue #46 regression: a USB-PD source exists (even with no
        // options), so the resolver must not fall back to the system
        // adapter. The USB-PD source owns this port's wattage.
        let bareUSBPD = PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [], winning: nil
        )
        let wattageSource = ChargerWattageSource.resolve(
            portSources: [bareUSBPD],
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: AdapterInfo(watts: 87, isCharging: nil, source: "AC")
        )
        #expect(wattageSource == .unknown)
    }

    @Test("System adapter fallback blocked with two charger candidates")
    func systemAdapterFallbackBlockedWhenMultiplePortsActive() {
        // Two ports could be feeding power in, both with Brick ID only. We
        // can't tell which one the system adapter reading belongs to. A count
        // of 2 here means two real charger candidates, not a charger plus a
        // data/display port (issue #443, which no longer inflates the count).
        let wattageSource = ChargerWattageSource.resolve(
            portSources: [brickIDWithoutPDOs()],
            activePortCount: 2,
            chargerSourceCount: 2,
            adapter: AdapterInfo(watts: 96, isCharging: nil, source: "AC")
        )
        #expect(wattageSource == .unknown)
    }

    @Test("Resolver returns portNegotiated for normal USB-PD")
    func resolverReturnsPortNegotiatedForNormalUSBPD() {
        let wattageSource = ChargerWattageSource.resolve(
            portSources: [usbPD(maxW: 96, winningW: 96)],
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: nil
        )
        #expect(wattageSource == .portNegotiated(watts: 96))
    }

    // MARK: - MagSafe Brick ID vs system adapter (issue #154)

    /// A third-party 100W PD brick via Apple MagSafe: the port exposes
    /// only a low-power "Brick ID" (no winning PDO), the real contract
    /// is in the system adapter reading.
    private func lowMagSafeBrickID() -> PowerSource {
        PowerSource(
            id: 2, name: "Brick ID", parentPortType: 0x11, parentPortNumber: 1,
            options: [PowerOption(voltageMV: 5_000, maxCurrentMA: 500, maxPowerMW: 2_500)],
            winning: nil
        )
    }

    @Test("MagSafe Brick ID defers to higher system adapter wattage")
    func magSafeBrickIDPrefersSystemAdapter() {
        let wattageSource = ChargerWattageSource.resolve(
            portSources: [lowMagSafeBrickID()],
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: AdapterInfo(watts: 100, isCharging: nil, source: "AC")
        )
        #expect(wattageSource == .systemAdapterFallback(watts: 100))
    }

    @Test("Brick ID kept when system adapter is not higher")
    func brickIDKeptWhenAdapterNotHigher() {
        // A legitimate high-wattage Brick ID equal to the adapter reading
        // must stay port-negotiated, not get rewritten as a fallback.
        let wattageSource = ChargerWattageSource.resolve(
            portSources: [brickID(maxW: 100, winningW: 100)],
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: AdapterInfo(watts: 100, isCharging: nil, source: "AC")
        )
        #expect(wattageSource == .portNegotiated(watts: 100))
    }

    @Test("Brick ID divert blocked with two charger candidates")
    func brickIDDivertBlockedWhenMultiplePortsActive() {
        // #46 protection: with two ports that could each be feeding power in,
        // we can't attribute the system adapter reading, so the low Brick ID
        // stands. The count of 2 is two real charger candidates. A data or
        // display port no longer counts here (issue #443).
        let wattageSource = ChargerWattageSource.resolve(
            portSources: [lowMagSafeBrickID()],
            activePortCount: 2,
            chargerSourceCount: 2,
            adapter: AdapterInfo(watts: 100, isCharging: nil, source: "AC")
        )
        #expect(wattageSource == .portNegotiated(watts: 3))
    }

    @Test("Third-party MagSafe brick reports adapter wattage, not 3W")
    func magSafeThirdPartyBrickShowsAdapterWattage() {
        // Before the fix this rendered "Charger advertises up to 3W /
        // Negotiation hasn't completed yet". It must now read 100W.
        let adapter = AdapterInfo(watts: 100, isCharging: nil, source: "AC")
        let wattageSource = ChargerWattageSource.resolve(
            portSources: [lowMagSafeBrickID()],
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapter
        )
        #expect(wattageSource == .systemAdapterFallback(watts: 100))

        let diag = ChargingDiagnostic(
            port: port,
            sources: [lowMagSafeBrickID()],
            identities: [],
            adapter: adapter,
            wattageSource: wattageSource
        )
        guard case .chargerLimit(let w) = diag?.bottleneck else {
            Issue.record("expected .chargerLimit from adapter fallback, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(w == 100)
        #expect(diag?.summary == "System reports charger at 100W")
    }

    // MARK: - Charger source count (issue #443)

    /// Build a port with just the fields the charger-source count reads.
    /// No `hpmControllerUUID` (rawProperties empty), so joins fall back to the
    /// portKey string comparison, which is exactly the M1/M2 path.
    private func makePort(
        number: Int, type: String, active: Bool
    ) -> USBCPort {
        USBCPort(
            id: UInt64(number),
            serviceName: "Port-\(type)@\(number)",
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: type,
            portNumber: number,
            connectionActive: active,
            activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
    }

    /// A Brick ID source bound to a specific port (type/number join key).
    private func brickIDOnPort(type: Int, number: Int) -> PowerSource {
        PowerSource(
            id: UInt64(100 + number), name: "Brick ID",
            parentPortType: type, parentPortNumber: number,
            options: [PowerOption(voltageMV: 5_000, maxCurrentMA: 500, maxPowerMW: 2_500)],
            winning: nil
        )
    }

    @Test("A USB-C display port with no power source is not counted")
    func displayPortDoesNotCountAsCharger() {
        // The #443 shape: MagSafe is charging (it has a Brick ID source node),
        // the USB-C port only carries video/data to a monitor (no source node).
        // Only the MagSafe port has a power source, so the count is 1.
        let magsafe = makePort(number: 1, type: "MagSafe 3", active: true)
        let display = makePort(number: 2, type: "USB-C", active: true)
        let sources = [brickIDOnPort(type: 0x11, number: 1)]
        let count = ChargerWattageSource.chargerSourceCount(
            ports: [magsafe, display], sources: sources)
        #expect(count == 1)
    }

    @Test("Two real chargers both count (#46 preserved)")
    func twoChargersBothCount() {
        // Two USB-C ports each with their own Brick ID node. Both have a power
        // source, so the count is 2 and the Brick ID divert stays blocked.
        let portA = makePort(number: 1, type: "USB-C", active: true)
        let portB = makePort(number: 2, type: "USB-C", active: true)
        let sources = [
            brickIDOnPort(type: 2, number: 1),
            brickIDOnPort(type: 2, number: 2),
        ]
        let count = ChargerWattageSource.chargerSourceCount(
            ports: [portA, portB], sources: sources)
        #expect(count == 2)
    }

    @Test("M1/M2 portKey join: two USB-C chargers still both count")
    func m1PortKeyFallbackTwoChargers() {
        // M1/M2 ports carry no HPM controller UUID, so canonicallyMatches uses
        // the portKey string. Two USB-C Brick ID chargers must still both count
        // so the #46 divert protection holds on that hardware too.
        let a = makePort(number: 1, type: "USB-C", active: true)
        let b = makePort(number: 2, type: "USB-C", active: true)
        let sources = [brickIDOnPort(type: 2, number: 1), brickIDOnPort(type: 2, number: 2)]
        let count = ChargerWattageSource.chargerSourceCount(ports: [a, b], sources: sources)
        #expect(count == 2)
    }

    @Test("An inactive port is never counted, even with a stale source node")
    func inactivePortDoesNotCount() {
        // Ports keep the last source after unplug. An inactive port with a
        // lingering source node must not count as a charger.
        let active = makePort(number: 1, type: "MagSafe 3", active: true)
        let idle = makePort(number: 2, type: "USB-C", active: false)
        let sources = [brickIDOnPort(type: 0x11, number: 1), brickIDOnPort(type: 2, number: 2)]
        let count = ChargerWattageSource.chargerSourceCount(
            ports: [active, idle], sources: sources)
        #expect(count == 1)  // only the active MagSafe; the idle USB-C excluded
    }

    @Test("End to end #443: MagSafe reads full wattage, the display port is NOT a charger")
    func magSafePlusDisplayResolvesCorrectly() {
        // Full #443 reproduction, resolving BOTH ports. Before the fix the
        // display cable inflated the active count, blocking the #154 divert so
        // MagSafe froze at the junk 3W Brick ID while the Mac charged at 65W.
        let magsafe = makePort(number: 1, type: "MagSafe 3", active: true)
        let display = makePort(number: 2, type: "USB-C", active: true)
        let magsafeSource = brickIDOnPort(type: 0x11, number: 1)  // MagSafe's only source
        let ports = [magsafe, display]
        let allSources = [magsafeSource]
        let adapter = AdapterInfo(watts: 65, isCharging: nil, source: "AC")

        let activePortCount = ports.filter { $0.connectionActive == true }.count
        let sourceCount = ChargerWattageSource.chargerSourceCount(ports: ports, sources: allSources)
        #expect(activePortCount == 2)
        #expect(sourceCount == 1)

        // MagSafe port: diverts to the real adapter wattage.
        let magsafeWattage = ChargerWattageSource.resolve(
            portSources: allSources.filter { $0.canonicallyMatches(port: magsafe) },
            activePortCount: activePortCount,
            chargerSourceCount: sourceCount,
            adapter: adapter
        )
        #expect(magsafeWattage == .systemAdapterFallback(watts: 65))

        // Display port: no power source of its own, so the adapter reading must
        // NOT be attributed to it. This is the regression Codex caught: a single
        // shared count here handed the display port the charger's 65W.
        let displayWattage = ChargerWattageSource.resolve(
            portSources: allSources.filter { $0.canonicallyMatches(port: display) },
            activePortCount: activePortCount,
            chargerSourceCount: sourceCount,
            adapter: adapter
        )
        #expect(displayWattage == .unknown)
        #expect(displayWattage.watts == nil)
    }

    @Test("Source-less TB dock still gets the adapter fallback (#141 preserved)")
    func sourcelessDockUsesActivePortCountFallback() {
        // A dock delivers power with no per-port source node. It is the only
        // active port, so the source-less fallback (gated on the plain active
        // count, not the source count) must still fire. chargerSourceCount is 0
        // here; if that fallback keyed off it, the dock would show no wattage.
        let dock = makePort(number: 1, type: "USB-C", active: true)
        let sourceCount = ChargerWattageSource.chargerSourceCount(ports: [dock], sources: [])
        #expect(sourceCount == 0)
        let wattage = ChargerWattageSource.resolve(
            portSources: [],
            activePortCount: 1,
            chargerSourceCount: 0,
            adapter: AdapterInfo(watts: 96, isCharging: nil, source: "AC")
        )
        #expect(wattage == .systemAdapterFallback(watts: 96))
    }

    @Test("Accepted #443/#46 trade-off: a source-less second charger cannot block the Brick ID divert")
    func brickIDDivertTradeoffWithSourcelessSecondCharger() {
        // A MagSafe third-party Brick ID charger + a second active port that
        // delivers power but exposes NO source node (a #141-shape dock) looks,
        // from the port data alone, identical to a MagSafe charger + a plain
        // display cable (#443). The display case is an everyday setup; the twin
        // source-less-charger case is rare. We favour the common case, so the
        // divert fires on chargerSourceCount == 1. This pins that accepted
        // behaviour: it is a documented trade-off, not an oversight. (See the
        // comment on the Brick ID branch in ChargerWattageSource.resolve.)
        let wattage = ChargerWattageSource.resolve(
            portSources: [lowMagSafeBrickID()],
            activePortCount: 2,     // a second port is active...
            chargerSourceCount: 1,  // ...but it exposes no power source of its own
            adapter: AdapterInfo(watts: 96, isCharging: nil, source: "AC")
        )
        #expect(wattage == .systemAdapterFallback(watts: 96))
    }

    @Test("Source-less dock beside a second active port does not borrow the reading")
    func sourcelessDockWithSecondPortBlocked() {
        // Two active ports, the dock has no source node. We can't attribute the
        // adapter reading to either, so no fallback fires (#46 protection via
        // the plain active-port count).
        let wattage = ChargerWattageSource.resolve(
            portSources: [],
            activePortCount: 2,
            chargerSourceCount: 0,
            adapter: AdapterInfo(watts: 96, isCharging: nil, source: "AC")
        )
        #expect(wattage == .unknown)
    }

    // MARK: - Standby charger (issue #264)

    /// A USB-PD charger that is connected and advertising, but has no
    /// winning (negotiated) PDO because the Mac is drawing from elsewhere.
    private func usbPDNoContract(maxW: Int) -> PowerSource {
        PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [PowerOption(voltageMV: 20_000, maxCurrentMA: maxW * 50, maxPowerMW: maxW * 1000)],
            winning: nil
        )
    }

    @Test("Second charger reads as standby, not stuck negotiating")
    func secondChargerReadsAsStandby() {
        // Two chargers attached: this 60W one has no contract because the
        // Mac chose the other port. With the cross-port flag set it must
        // read as standby (calm, no warning), not "negotiation incomplete".
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPDNoContract(maxW: 60)],
            identities: [],
            anotherPortActivelyCharging: true
        )
        guard case .standbyCharger(let w) = diag?.bottleneck else {
            Issue.record("expected .standbyCharger, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(w == 60)
        #expect(diag!.isWarning == false)
        #expect(diag!.summary == "Charger on standby")
    }

    @Test("Single charger with no contract still reads as negotiating")
    func singleChargerNoContractStillNegotiating() {
        // Same inputs, but no other port is charging. This is the genuine
        // "negotiation hasn't completed" case and must be preserved.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPDNoContract(maxW: 60)],
            identities: [],
            anotherPortActivelyCharging: false
        )
        guard case .chargerLimit(let w) = diag?.bottleneck else {
            Issue.record("expected .chargerLimit, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(w == 60)
        // "Negotiation hasn't completed yet" is a transient state, not a
        // fault, so it is informational rather than a warning.
        #expect(diag!.isWarning == false)
        #expect(diag!.detail == "Negotiation hasn't completed yet.")
    }

    @Test("hasLiveChargingContract reflects a winning PDO")
    func hasLiveChargingContractReflectsWinningPDO() {
        #expect(PowerSource.hasLiveChargingContract(in: [usbPD(maxW: 96, winningW: 96)]))
        #expect(PowerSource.hasLiveChargingContract(in: [usbPDNoContract(maxW: 60)]) == false)
        #expect(PowerSource.hasLiveChargingContract(in: []) == false)
    }

    // MARK: - Charge hold (issue #319)

    @Test("Charge hold: batteryIsCharging=false shows on-hold summary, not a warning")
    func chargeHoldIsNotAWarning() {
        // batteryIsCharging=false with a live contract is the charge-hold state:
        // macOS has a charge limit or OBC active. The bottleneck stays .fine,
        // so it must NOT be flagged as a warning.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)],
            adapter: AdapterInfo(watts: 96, isCharging: nil, source: "AC"),
            batteryIsCharging: false
        )
        #expect(diag != nil)
        #expect(diag!.isWarning == false)
        #expect(diag!.summary == "Plugged in, charging on hold")
    }

    @Test("Charge hold: batteryFullyCharged=true takes precedence over batteryIsCharging=false")
    func batteryFullyChargedTakesPrecedenceOverChargeHold() {
        // When the battery is fully charged, that message wins even if IsCharging is also false.
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)],
            adapter: AdapterInfo(watts: 96, isCharging: nil, source: "AC"),
            batteryFullyCharged: true,
            batteryIsCharging: false
        )
        #expect(diag != nil)
        #expect(diag!.summary == "Battery full, not charging")
    }

    @Test("Charge hold: batteryIsCharging=nil keeps existing charging-well behaviour")
    func chargeHoldNilKeepsChargingWell() {
        // When batteryIsCharging is nil (desktop or unknown), summary stays "Charging well".
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            identities: [cableIdentity(watts: 100)],
            batteryIsCharging: nil
        )
        #expect(diag != nil)
        #expect(diag!.summary.contains("Charging well"))
    }

    @Test("Stale PDO: no diagnostic when the system has no adapter")
    func stalePDOWithNoSystemAdapterReturnsNil() {
        let diag = ChargingDiagnostic(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            identities: [],
            adapter: nil,
            batteryFullyCharged: false,
            batteryIsCharging: false
        )
        #expect(diag == nil)
    }
}
