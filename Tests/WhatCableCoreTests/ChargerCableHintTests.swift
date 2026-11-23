import Foundation
import Testing
@testable import WhatCableCore

/// Unit tests for the #672 hedged cable hint: `ChargerCableHint` and the
/// `.possibleCableLimit` arm of `ChargingDiagnostic`. Corpus replay lives in
/// `ChargerCableHintCorpusTests`.
@Suite("Charger cable hint (#672)")
struct ChargerCableHintTests {

    // MARK: - Fixtures

    private func port(magSafe: Bool = false) -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: magSafe ? "Port-MagSafe 3@1" : "Port-USB-C@1",
            className: magSafe ? "AppleHPMInterfaceType11" : "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: magSafe ? "MagSafe 3" : "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": magSafe ? "17" : "2"]
        )
    }

    private func offer(_ volts: Int, _ milliamps: Int) -> PowerOption {
        PowerOption(voltageMV: volts * 1000, maxCurrentMA: milliamps,
                    maxPowerMW: volts * milliamps, supplyKind: .fixed)
    }

    /// The reporter's original capture on #672: 5/9/15/20 V, all at 3 A.
    private var cappedAt3A: [PowerOption] {
        [offer(20, 3000), offer(15, 3000), offer(9, 3000), offer(5, 3000)]
    }

    /// The same charger after the cable swap on #672: 20 V at 4.7 A.
    private var normal96W: [PowerOption] {
        [offer(20, 4700), offer(15, 3000), offer(9, 3000), offer(5, 3000)]
    }

    private func usbPD(_ options: [PowerOption], winning: PowerOption?, magSafe: Bool = false) -> PowerSource {
        PowerSource(id: 1, name: "USB-PD", parentPortType: magSafe ? 0x11 : 2, parentPortNumber: 1,
                    options: options, winning: winning)
    }

    private func uvdm(_ userString: String?) -> AppleAccessoryIdentity {
        AppleAccessoryIdentity(
            id: 9, portKey: "2/1", manufacturer: "Apple Inc.", vendor: nil, product: "0",
            userString: userString, model: "0x7002", serialNumber: "SERIAL", hardwareVersion: "1.0",
            vendorID: 0x05AC, productID: 0x7002)
    }

    private func adapter(name: String?, manufacturer: String? = "Apple Inc.", watts: Int = 60) -> AdapterInfo {
        AdapterInfo(watts: watts, isCharging: true, source: "AC", manufacturer: manufacturer, name: name)
    }

    /// 3 A passive cable e-marker (60 W), same encoding as ChargingDiagnosticTests.
    private var cable60W: USBPDSOP {
        let cableVDO: UInt32 = 0b000 | (1 << 5) | (1 << 13)
        return USBPDSOP(id: 2, endpoint: .sopPrime, parentPortType: 2, parentPortNumber: 1,
                        vendorID: 0, productID: 0, bcdDevice: 0,
                        vdos: [0x1800_0000, 0, 0, cableVDO], specRevision: 0)
    }

    // MARK: - ratedWatts(appleChargerName:)

    @Test("Apple USB-C charger names give their rating; trailing space is trimmed")
    func ratedWattsFromAppleNames() {
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "96W USB-C Power Adapter") == 96)
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "140W USB-C Power Adapter") == 140)
        // Corpus: the 70 W and 35 W names carry a trailing space.
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "70W USB-C Power Adapter ") == 70)
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "61W USB-C Power Adapter") == 61)
    }

    @Test("Names that are not an Apple USB-C charger give no rating")
    func ratedWattsRejectsOtherNames() {
        #expect(ChargerCableHint.ratedWatts(appleChargerName: nil) == nil)
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "") == nil)
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "pd charger") == nil)
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "Studio Display") == nil)
        // iMac power supply: no USB-C offer menu at all.
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "143W Power Adapter") == nil)
        // 0x701E holds two wattages; not a "USB-C Power Adapter" name.
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "40W Pwr Adapter 60W Max") == nil)
        // Wattage not leading the name.
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "USB-C Power Adapter 96W") == nil)
        // An absurd figure must not overflow or pass.
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "99999999999999999999999W USB-C Power Adapter") == nil)
    }

    // MARK: - chargerName(...)

    @Test("The port's own UVDM name wins over AdapterDetails")
    func chargerNamePrefersUVDM() {
        let name = ChargerCableHint.chargerName(
            accessory: uvdm("96W USB-C Power Adapter"),
            adapter: adapter(name: "140W USB-C Power Adapter"),
            portHasLiveContract: true, anotherPortActivelyCharging: false)
        #expect(name == "96W USB-C Power Adapter")
    }

    @Test("AdapterDetails names the charger only when this is the one live charging port")
    func chargerNameAdapterFallbackNeedsOneLivePort() {
        let ad = adapter(name: "96W USB-C Power Adapter")
        #expect(ChargerCableHint.chargerName(
            accessory: nil, adapter: ad, portHasLiveContract: true, anotherPortActivelyCharging: false)
            == "96W USB-C Power Adapter")
        // Another port also holds a contract: AdapterDetails is system-wide, so
        // it cannot be pinned to this port.
        #expect(ChargerCableHint.chargerName(
            accessory: nil, adapter: ad, portHasLiveContract: true, anotherPortActivelyCharging: true) == nil)
        // This port holds no contract.
        #expect(ChargerCableHint.chargerName(
            accessory: nil, adapter: ad, portHasLiveContract: false, anotherPortActivelyCharging: false) == nil)
    }

    @Test("A non-Apple manufacturer on AdapterDetails is never rated; a missing one is allowed")
    func chargerNameAdapterManufacturer() {
        #expect(ChargerCableHint.chargerName(
            accessory: nil, adapter: adapter(name: "96W USB-C Power Adapter", manufacturer: "SMP"),
            portHasLiveContract: true, anotherPortActivelyCharging: false) == nil)
        // Corpus: 20 Apple-named AdapterDetails captures carry no Manufacturer.
        #expect(ChargerCableHint.chargerName(
            accessory: nil, adapter: adapter(name: "96W USB-C Power Adapter", manufacturer: nil),
            portHasLiveContract: true, anotherPortActivelyCharging: false) == "96W USB-C Power Adapter")
    }

    @Test("A UVDM node with no usable name falls back to AdapterDetails")
    func chargerNameEmptyUVDMFallsBack() {
        #expect(ChargerCableHint.chargerName(
            accessory: uvdm(nil), adapter: adapter(name: "70W USB-C Power Adapter "),
            portHasLiveContract: true, anotherPortActivelyCharging: false) == "70W USB-C Power Adapter ")
    }

    // MARK: - evaluate(chargerName:source:)

    /// A real (not synthesised) USB-PD source carrying `offers`, contract = top offer.
    private func hint(_ name: String?, _ offers: [PowerOption]) -> ChargerCableHint? {
        ChargerCableHint.evaluate(
            chargerName: name,
            source: PowerSource(id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
                                options: offers, winning: offers.max { $0.maxPowerMW < $1.maxPowerMW }))
    }

    @Test("96W charger offering 20V x 3A: hint with 96 and 60")
    func evaluateIssue672Shape() {
        let hint = hint("96W USB-C Power Adapter", cappedAt3A)
        #expect(hint == ChargerCableHint(chargerRatedW: 96, offeredW: 60))
    }

    @Test("The same charger offering 4.7A after the cable swap: no hint")
    func evaluateNormal96W() {
        #expect(hint("96W USB-C Power Adapter", normal96W) == nil)
    }

    @Test("Any offer above 3A means a 5A cable was found: no hint")
    func evaluateOneOfferAbove3A() {
        // One milliamp over the ceiling is enough.
        let offers = [offer(20, 3001), offer(5, 3000)]
        #expect(hint("140W USB-C Power Adapter", offers) == nil)
        // An EPR offer counts even when the SPR list is all 3A.
        let epr = cappedAt3A + [offer(28, 5000)]
        #expect(hint("140W USB-C Power Adapter", epr) == nil)
    }

    @Test("Rating floor is 65W: 64W never fires, 65W does")
    func evaluateRatingFloor() {
        let lowOffers = [offer(15, 3000), offer(5, 3000)]   // top 45 W
        #expect(hint("64W USB-C Power Adapter", lowOffers) == nil)
        #expect(hint("65W USB-C Power Adapter", lowOffers)
                == ChargerCableHint(chargerRatedW: 65, offeredW: 45))
        // 61 W Apple charger at its normal 20 V x 3 A: never a candidate.
        #expect(hint("61W USB-C Power Adapter", cappedAt3A) == nil)
    }

    @Test("The rating must beat the top offer by MORE than 5W")
    func evaluateMarginBoundary() {
        // Top offer 60 W. 65 W is exactly 5 W over: silent. 66 W is 6 W over: fires.
        #expect(hint("65W USB-C Power Adapter", cappedAt3A) == nil)
        #expect(hint("66W USB-C Power Adapter", cappedAt3A)
                == ChargerCableHint(chargerRatedW: 66, offeredW: 60))
        // Measured in milliwatts, not rounded watts: 65 W against 59.9 W is
        // 5.1 W over and fires.
        let just = [PowerOption(voltageMV: 20_000, maxCurrentMA: 2995, maxPowerMW: 59_900, supplyKind: .fixed)]
        #expect(hint("65W USB-C Power Adapter", just)
                == ChargerCableHint(chargerRatedW: 65, offeredW: 60))
    }

    @Test("No offers, or no Apple name: no hint")
    func evaluateNeedsOffersAndName() {
        #expect(hint("96W USB-C Power Adapter", []) == nil)
        #expect(hint(nil, cappedAt3A) == nil)
        #expect(hint("pd charger", cappedAt3A) == nil)
    }

    // MARK: - ChargingDiagnostic integration

    @Test("Issue #672 shape: unread e-marker, 96W Apple charger at 20V x 3A -> possibleCableLimit")
    func diagnosticFiresOnIssueShape() {
        let diag = ChargingDiagnostic(
            port: port(),
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [],
            adapter: adapter(name: nil),
            accessoryIdentity: uvdm("96W USB-C Power Adapter"))
        guard case .possibleCableLimit(let offeredW, let ratedW, let negotiatedW) = diag?.bottleneck else {
            Issue.record("expected .possibleCableLimit, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(offeredW == 60)
        #expect(ratedW == 96)
        #expect(negotiatedW == 60)
        #expect(diag?.isWarning == true)
        // The charger's own ceiling is its rating, so breakdown tables read
        // "Charger 96 W" beside "This 96W charger".
        #expect(diag?.chargerW == 96)
        #expect(diag?.cableW == nil)
        #expect(diag?.summary == "Cable may be limiting charging speed")
        #expect(diag?.detail == "This 96W charger is only offering up to 60W. Chargers do that when they can't confirm the cable is rated for 5A. Try a cable rated for 5A, 100W or more.")
    }

    @Test("AdapterDetails names the charger when no UVDM name is read")
    func diagnosticFiresFromAdapterName() {
        let diag = ChargingDiagnostic(
            port: port(),
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [],
            adapter: adapter(name: "67W USB-C Power Adapter"))
        #expect(diag?.bottleneck == .possibleCableLimit(offeredW: 60, chargerRatedW: 67, negotiatedW: 60))
    }

    @Test("A cable rating that was read keeps today's check: no hint")
    func diagnosticSilentWhenEmarkerRead() {
        let diag = ChargingDiagnostic(
            port: port(),
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [cable60W],
            adapter: adapter(name: "96W USB-C Power Adapter"))
        if case .possibleCableLimit = diag?.bottleneck {
            Issue.record("hint must not fire when the e-marker rating was read")
        }
        #expect(diag?.cableW == 60)
    }

    @Test("After the cable swap (4.7A offer) the diagnostic is today's .fine")
    func diagnosticSilentOnNormalOffer() {
        let diag = ChargingDiagnostic(
            port: port(),
            sources: [usbPD(normal96W, winning: offer(20, 4700))],
            identities: [],
            adapter: adapter(name: nil),
            accessoryIdentity: uvdm("96W USB-C Power Adapter"))
        #expect(diag?.bottleneck == .fine(negotiatedW: 94))
    }

    @Test("MagSafe never gets the hint: there is no USB-C cable to swap")
    func diagnosticSilentOnMagSafe() {
        let diag = ChargingDiagnostic(
            port: port(magSafe: true),
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000), magSafe: true)],
            identities: [],
            adapter: adapter(name: "96W USB-C Power Adapter"))
        if case .possibleCableLimit = diag?.bottleneck {
            Issue.record("hint must not fire on MagSafe")
        }
    }

    @Test("Another port charging: AdapterDetails cannot be pinned here, no hint")
    func diagnosticSilentWhenAnotherPortCharges() {
        let diag = ChargingDiagnostic(
            port: port(),
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [],
            adapter: adapter(name: "96W USB-C Power Adapter"),
            anotherPortActivelyCharging: true)
        if case .possibleCableLimit = diag?.bottleneck {
            Issue.record("hint must not use AdapterDetails when another port holds a contract")
        }
    }

    @Test("A per-port UVDM name still fires when another port is also charging")
    func diagnosticUVDMFiresWithAnotherPortCharging() {
        let diag = ChargingDiagnostic(
            port: port(),
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [],
            adapter: adapter(name: nil),
            anotherPortActivelyCharging: true,
            accessoryIdentity: uvdm("96W USB-C Power Adapter"))
        #expect(diag?.bottleneck == .possibleCableLimit(offeredW: 60, chargerRatedW: 96, negotiatedW: 60))
    }

    @Test("On battery: the diagnostic stays nil, as today")
    func diagnosticNilOnBattery() {
        let diag = ChargingDiagnostic(
            port: port(),
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [],
            adapter: nil,
            batteryIsCharging: false,
            accessoryIdentity: uvdm("96W USB-C Power Adapter"))
        #expect(diag == nil)
    }

    // MARK: - Renderer wiring (the UVDM name must reach the diagnostic)

    @Test("JSON output carries possibleCableLimit when only the UVDM node names the charger")
    func jsonWiresUVDMName() throws {
        let out = try JSONFormatter.render(
            ports: [port()],
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [], showRaw: false,
            adapter: adapter(name: nil),
            accessoryIdentities: [uvdm("96W USB-C Power Adapter")])
        let root = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let ports = try #require(root["ports"] as? [[String: Any]])
        let charging = try #require(ports.first?["charging"] as? [String: Any])
        #expect(charging["bottleneck"] as? String == "possibleCableLimit")
        #expect(charging["isWarning"] as? Bool == true)
    }

    @Test("CLI text carries the hint when only the UVDM node names the charger")
    func textWiresUVDMName() {
        let out = TextFormatter.render(
            ports: [port()],
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [], showRaw: false,
            adapter: adapter(name: nil),
            accessoryIdentities: [uvdm("96W USB-C Power Adapter")])
        #expect(out.contains("Cable may be limiting charging speed"))
    }

    // MARK: - Tightened gates (review round 2)

    @Test("Only a USB-PD source qualifies: a TypeC or Brick ID contract is a PD failure, not a cable matter")
    func onlyUSBPDSourceQualifies() {
        for name in ["TypeC", "Brick ID"] {
            let source = PowerSource(id: 3, name: name, parentPortType: 2, parentPortNumber: 1,
                                     options: cappedAt3A, winning: offer(20, 3000))
            #expect(ChargerCableHint.evaluate(chargerName: "96W USB-C Power Adapter", source: source) == nil,
                    "\(name) must not qualify")
            let diag = ChargingDiagnostic(
                port: port(), sources: [source], identities: [],
                adapter: adapter(name: "96W USB-C Power Adapter"))
            if case .possibleCableLimit = diag?.bottleneck {
                Issue.record("\(name)-only winning source fired the hint")
            }
        }
    }

    @Test("A UVDM name that is not a charger blocks the AdapterDetails fallback for that port")
    func nonChargerUVDMNameBlocksFallback() {
        let ad = adapter(name: "96W USB-C Power Adapter")
        #expect(ChargerCableHint.chargerName(
            accessory: uvdm("Studio Display"), adapter: ad,
            portHasLiveContract: true, anotherPortActivelyCharging: false) == nil)
        let diag = ChargingDiagnostic(
            port: port(), sources: [usbPD(cappedAt3A, winning: offer(20, 3000))], identities: [],
            adapter: ad, accessoryIdentity: uvdm("Studio Display"))
        if case .possibleCableLimit = diag?.bottleneck {
            Issue.record("a Studio Display on this port borrowed the system charger's name")
        }
    }

    @Test("An offer with unknown (0 mA) current does not pass the 3A test")
    func zeroCurrentOfferDoesNotQualify() {
        let zero = PowerOption(voltageMV: 20_000, maxCurrentMA: 0, maxPowerMW: 0, supplyKind: .unknown)
        #expect(hint("96W USB-C Power Adapter", cappedAt3A + [zero]) == nil)
    }

    @Test("Only the exact Apple name shape rates: trailing text after the name does not")
    func exactNameShapeOnly() {
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "96W USB-C Power Adapter (Anker)") == nil)
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "Generic 96W USB-C Power Adapter") == nil)
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "96W USB-C Power Adapter Pro") == nil)
        // Surrounding whitespace is still trimmed (corpus 70 W / 35 W names).
        #expect(ChargerCableHint.ratedWatts(appleChargerName: " 70W USB-C Power Adapter ") == 70)
    }

    @Test("An SMC-synthesised source carrying only the contract does not fire; a real offer list does")
    func synthesisedContractOnlyDoesNotFire() {
        let contract = offer(20, 3000)
        let smcOnly = PowerSource(id: 7, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
                                  options: [contract], winning: contract, isSynthesized: true)
        #expect(ChargerCableHint.evaluate(chargerName: "96W USB-C Power Adapter", source: smcOnly) == nil)
        // PortControllerInfo synthesis (M1 Pro/Max) carries the full PDO list: still fires.
        let fullList = PowerSource(id: 8, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
                                   options: cappedAt3A, winning: contract, isSynthesized: true)
        #expect(ChargerCableHint.evaluate(chargerName: "96W USB-C Power Adapter", source: fullList)
                == ChargerCableHint(chargerRatedW: 96, offeredW: 60))
    }

    @Test("JSON carries typed rated and offered watts on possibleCableLimit, and omits them elsewhere")
    func jsonCarriesTypedWatts() throws {
        func charging(_ sources: [PowerSource]) throws -> [String: Any] {
            let out = try JSONFormatter.render(
                ports: [port()], sources: sources, identities: [], showRaw: false,
                adapter: adapter(name: "96W USB-C Power Adapter"))
            let root = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
            let ports = try #require(root["ports"] as? [[String: Any]])
            return try #require(ports.first?["charging"] as? [String: Any])
        }
        let hinted = try charging([usbPD(cappedAt3A, winning: offer(20, 3000))])
        #expect(hinted["bottleneck"] as? String == "possibleCableLimit")
        #expect(hinted["chargerRatedW"] as? Int == 96)
        #expect(hinted["offeredW"] as? Int == 60)
        let normal = try charging([usbPD(normal96W, winning: offer(20, 4700))])
        #expect(normal["bottleneck"] as? String == "fine")
        #expect(normal["chargerRatedW"] == nil)
        #expect(normal["offeredW"] == nil)
    }

    @Test("The hint outranks the battery-full summary, as the read-cable check does")
    func diagnosticHintBeatsBatteryFull() {
        let diag = ChargingDiagnostic(
            port: port(),
            sources: [usbPD(cappedAt3A, winning: offer(20, 3000))],
            identities: [],
            adapter: adapter(name: "96W USB-C Power Adapter"),
            batteryFullyCharged: true)
        #expect(diag?.bottleneck == .possibleCableLimit(offeredW: 60, chargerRatedW: 96, negotiatedW: 60))
    }
}
