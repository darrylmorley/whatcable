import Foundation
import Testing
@testable import WhatCableCore

/// Unit tests for `PowerSourceSynthesis` (issue #401: M1 Pro/Max/Ultra never
/// publish a real `IOPortFeaturePowerSource` node for USB-C, so we recover
/// the same contract data from `AppleSmartBattery`'s `PortControllerInfo`).
@Suite("PowerSourceSynthesis")
struct PowerSourceSynthesisTests {

    // MARK: - Fixture builders

    /// - Parameter rawType: The raw `PortType` value (e.g. "2" for USB-C,
    ///   "17" for MagSafe, "18" for the A18 Pro "Inductive" port type). When
    ///   nil, inferred from `typeDescription` the way the two shipped types
    ///   always have been (MagSafe -> 17, else USB-C -> 2). Pass explicitly
    ///   for any other port type.
    private func port(
        number: Int,
        typeDescription: String = "USB-C",
        rawType explicitRawType: String? = nil,
        active: Bool
    ) -> AppleHPMInterface {
        let rawType = explicitRawType ?? (typeDescription.hasPrefix("MagSafe") ? "17" : "2")
        return AppleHPMInterface(
            id: UInt64(number),
            serviceName: "Port-\(typeDescription)@\(number)",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-\(typeDescription)@\(number)",
            portTypeDescription: typeDescription,
            portNumber: number,
            connectionActive: active,
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
            rawProperties: ["PortType": rawType]
        )
    }

    /// Raw Fixed Supply PDO (Table 6.9): bits 19..10 = voltage (50 mV units),
    /// bits 9..0 = max current (10 mA units). Bits 31..30 = 00 (fixed) are
    /// left unset, which is what `PDO.decode(rawValue:)` expects for a fixed
    /// supply.
    private func fixedPDORaw(voltsMV: Int, currentMA: Int) -> UInt32 {
        (UInt32(voltsMV / 50) << 10) | UInt32(currentMA / 10)
    }

    /// A raw ID Header VDO with the DFP product-type field (bits 25..23) set
    /// to `dfpValue`. `3` = Power Brick, `2` = Host.
    private func idHeaderVDO(dfpValue: UInt32) -> UInt32 {
        dfpValue << 23
    }

    private func sopIdentity(portNumber: Int, dfpValue: UInt32, id: UInt64 = 1) -> USBPDSOP {
        USBPDSOP(
            id: id,
            endpoint: .sop,
            parentPortType: 2,
            parentPortNumber: portNumber,
            vendorID: 0,
            productID: 0,
            bcdDevice: 0,
            vdos: [idHeaderVDO(dfpValue: dfpValue)],
            specRevision: 3
        )
    }

    private typealias ContractEntry = PowerSourceSynthesis.ContractEntry

    // MARK: - 1. Reporter scenario (issue #401)

    @Test("Reporter scenario: 3-port machine, attributes via the positional rung and picks the 20V/60W winning option")
    func reporterScenario() throws {
        // 5V/3A = 15W, 12V/3A = 36W, 20V/3A = 60W. 20000mV * 3000mA / 1000 =
        // 60000mW, exactly entry.maxPowerMW, so the exact-match rung fires.
        let pdos = [
            fixedPDORaw(voltsMV: 5000, currentMA: 3000),
            fixedPDORaw(voltsMV: 12000, currentMA: 3000),
            fixedPDORaw(voltsMV: 20000, currentMA: 3000),
        ]
        let ports = [
            port(number: 1, active: true),
            port(number: 2, active: false),
            port(number: 3, active: true),
        ]
        // entry.index 0 and entries.count == positionalPortKeys.count below,
        // so rung a (positional) resolves this to port @1 directly; these
        // identities never get consulted. They're here as realistic set
        // dressing (a real machine would have SOP partners too), not because
        // rung b (partner-kind) does the work here. Rung b's own coverage
        // lives in `positionalFallsThroughToPartnerKind` below, where the
        // positional target is deliberately inactive so rung b has to fire.
        let identities = [
            sopIdentity(portNumber: 1, dfpValue: 3, id: 1),  // Power Brick
            sopIdentity(portNumber: 3, dfpValue: 2, id: 2),  // Host (dock)
        ]
        let entries = [
            ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000),
            ContractEntry(index: 1, rawPDOs: [], activeRdo: 0, maxPowerMW: 0),
            ContractEntry(index: 2, rawPDOs: [], activeRdo: 0, maxPowerMW: 0),
        ]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: identities,
            entries: entries,
            positionalPortKeys: ["2/1", "2/2", "2/3"],
            externalConnected: true
        )

        let source = try #require(result)
        #expect(source.portKey == "2/1")
        #expect(source.name == "USB-PD")
        #expect(source.isSynthesized == true)
        #expect(source.options.count == 3)
        #expect(source.winning?.maxPowerMW == 60000)
        #expect(source.winning?.voltageMV == 20000)
    }

    // MARK: - 2. Corpus scenario (m1pro_macos26.5.1_b)

    @Test("Corpus scenario m1pro_macos26.5.1_b: live entry at index 1 attributes to 2/2 via positional rung")
    func corpusScenarioPositional() {
        let pdos = [
            fixedPDORaw(voltsMV: 5000, currentMA: 3000),   // 15W
            fixedPDORaw(voltsMV: 9000, currentMA: 3000),   // 27W
            fixedPDORaw(voltsMV: 15000, currentMA: 3000),  // 45W
            fixedPDORaw(voltsMV: 20000, currentMA: 5000),  // 100W
        ]
        let ports = [
            port(number: 1, active: false),
            port(number: 2, active: true),
            port(number: 3, active: false),
        ]
        let entries = [
            ContractEntry(index: 0, rawPDOs: [], activeRdo: 0, maxPowerMW: 0),
            ContractEntry(index: 1, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 100000),
            ContractEntry(index: 2, rawPDOs: [], activeRdo: 0, maxPowerMW: 0),
        ]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1", "2/2", "2/3"],
            externalConnected: true
        )

        #expect(result?.portKey == "2/2")
        #expect(result?.winning?.maxPowerMW == 100000)
    }

    // MARK: - 3. Decline: real live contract already exists (MagSafe)

    @Test("Decline: a real source already has a live contract (MagSafe) -> nil")
    func declineWhenRealSourceHasLiveContract() {
        let magSafeWinning = PowerOption(voltageMV: 20000, maxCurrentMA: 7000, maxPowerMW: 140000)
        let realSources = [
            PowerSource(
                id: 555,
                name: "USB-PD",
                parentPortType: 0x11,
                parentPortNumber: 1,
                options: [magSafeWinning],
                winning: magSafeWinning
            ),
        ]
        let ports = [port(number: 1, active: true)]
        let entries = [
            ContractEntry(
                index: 0,
                rawPDOs: [fixedPDORaw(voltsMV: 20000, currentMA: 3000)],
                activeRdo: 0,
                maxPowerMW: 60000
            ),
        ]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: realSources,
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1"],
            externalConnected: true
        )
        #expect(result == nil)
    }

    // MARK: - 4. Decline: two live entries

    @Test("Decline: two entries with maxPowerMW > 0 -> nil")
    func declineWhenTwoLiveEntries() {
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [port(number: 1, active: true), port(number: 2, active: true)]
        let entries = [
            ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 50000),
            ContractEntry(index: 1, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000),
        ]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1", "2/2"],
            externalConnected: true
        )
        #expect(result == nil)
    }

    // MARK: - 5. Decline: no external power

    @Test("Decline: externalConnected == false -> nil")
    func declineWhenNoExternalPower() {
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [port(number: 1, active: true)]
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1"],
            externalConnected: false
        )
        #expect(result == nil)
    }

    // MARK: - 6. Decline: target port already covered by a real source

    @Test("Decline: the only candidate port is already covered by a real source (even 0W) -> nil overall")
    func declineWhenTargetPortAlreadyCovered() {
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [port(number: 1, active: true)]
        // A 0W Brick ID source with no winning contract: doesn't trip gate 2
        // (hasLiveChargingContract requires a non-nil winning), but it does
        // cover the port for the attribution ladder.
        let realSources = [
            PowerSource(id: 9, name: "Brick ID", parentPortType: 2, parentPortNumber: 1, options: [], winning: nil),
        ]
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: realSources,
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1"],
            externalConnected: true
        )
        #expect(result == nil)
    }

    // MARK: - 7. Decline: ambiguous attribution on every rung

    @Test("Decline: positional target inactive, partner-kind ambiguous (2 brick ports), multiple active ports -> nil")
    func declineWhenEveryRungAmbiguous() {
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [
            port(number: 1, active: false),  // positional target, but inactive
            port(number: 2, active: true),
            port(number: 3, active: true),
        ]
        let identities = [
            sopIdentity(portNumber: 2, dfpValue: 3, id: 1),  // Power Brick
            sopIdentity(portNumber: 3, dfpValue: 3, id: 2),  // Power Brick (ambiguous)
        ]
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: identities,
            entries: entries,
            positionalPortKeys: ["2/1", "2/2", "2/3"],
            externalConnected: true
        )
        #expect(result == nil)
    }

    // MARK: - 8. Positional target inactive, falls through to partner-kind rung

    @Test("Positional target inactive, but exactly one active brick-partner port -> falls through to rung b")
    func positionalFallsThroughToPartnerKind() {
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [
            port(number: 1, active: false),  // positional target
            port(number: 2, active: true),   // brick partner, the real target
            port(number: 3, active: true),   // dock, not a brick
        ]
        let identities = [
            sopIdentity(portNumber: 2, dfpValue: 3, id: 1),  // Power Brick
            sopIdentity(portNumber: 3, dfpValue: 2, id: 2),  // Host
        ]
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: identities,
            entries: entries,
            positionalPortKeys: ["2/1", "2/2", "2/3"],
            externalConnected: true
        )
        #expect(result?.portKey == "2/2")
    }

    /// Issue #573 part 2 (Codex design review, "another identities consumer
    /// omitted from the audit"): a MagSafe cable identity (endpoint
    /// `.sopPrime`, `parentPortType == 17`) is a structural no-op here,
    /// pinned end-to-end (with vs. without) rather than assumed. Two
    /// INDEPENDENT guards both have to hold for that to be true: rung b only
    /// ever consults `identity.endpoint == .sop` (a device/power-brick
    /// PARTNER identity, never a cable identity), and separately
    /// `isValidTarget` restricts candidate ports to a `"2/"` (USB-C)
    /// `portKey` prefix, so a MagSafe port could never become a synthesis
    /// target either. This test pins the OBSERVABLE outcome (identical
    /// result with or without the identity present); the next test below
    /// isolates the endpoint guard specifically, since a realistic
    /// MagSafe-typed identity can never exercise it alone (the port-type
    /// guard already excludes it first).
    @Test("A MagSafe SOP' cable identity is a no-op for synthesis, even carrying a power-brick-shaped VDO")
    func magSafeSOPPrimeIdentityIsANoOp() {
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [
            port(number: 1, active: false),                    // positional target, inactive
            port(number: 2, active: true),                     // the only active USB-C port
        ]
        let magSafeCableIdentity = USBPDSOP(
            id: 1, endpoint: .sopPrime, parentPortType: 17, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x7800, bcdDevice: 0,
            vdos: [idHeaderVDO(dfpValue: 3)], specRevision: 0)   // "Power Brick" shaped, but .sopPrime not .sop
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000)]

        let withMagSafeIdentity = PowerSourceSynthesis.synthesizedSource(
            realSources: [], ports: ports, identities: [magSafeCableIdentity],
            entries: entries, positionalPortKeys: ["2/1"], externalConnected: true)
        let withoutAnyIdentity = PowerSourceSynthesis.synthesizedSource(
            realSources: [], ports: ports, identities: [],
            entries: entries, positionalPortKeys: ["2/1"], externalConnected: true)

        #expect(withMagSafeIdentity?.portKey == withoutAnyIdentity?.portKey)
        #expect(withMagSafeIdentity?.portKey == "2/2")
    }

    /// Isolates rung b's `identity.endpoint == .sop` guard specifically
    /// (the guard MagSafe's cable identity, `endpoint == .sopPrime`, relies
    /// on). A real MagSafe identity can't exercise this guard in isolation,
    /// because its `parentPortType == 17` already fails `isValidTarget`'s
    /// USB-C-only port-key check before the endpoint is ever consulted; this
    /// fixture uses a `.sopPrime` identity on a valid USB-C port instead
    /// (the shape a genuine USB-C cable e-marker identity has), so the ONLY
    /// thing standing between it and winning rung b is the endpoint check.
    @Test("A SOP' (cable, not partner) identity never satisfies rung b, even sharing a valid target port's key")
    func cableIdentityNeverSatisfiesRungBEvenOnAMatchingPort() {
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        // THREE ports, deliberately: with only one active port, rung c
        // (sole-active-port) would resolve to the same answer regardless of
        // whether rung b's endpoint guard holds, making the test outcome-
        // insensitive to the very mechanism it claims to isolate. With two
        // ACTIVE ports, rung c is ambiguous (validPorts.count == 2) and
        // therefore fails too, so the correct result is nil; a broken
        // endpoint guard would instead let the cable identity's brick-shaped
        // VDO wrongly resolve rung b to port 2.
        let ports = [
            port(number: 1, active: false),   // positional target, inactive
            port(number: 2, active: true),    // ambiguous candidate A
            port(number: 3, active: true),    // ambiguous candidate B
        ]
        // A cable identity (not a device/power-brick partner) sitting on
        // port 2, carrying the exact VDO shape that would win rung b if it
        // were a real .sop partner.
        let cableIdentityOnSamePort = USBPDSOP(
            id: 1, endpoint: .sopPrime, parentPortType: 2, parentPortNumber: 2,
            vendorID: 0x05AC, productID: 0x7800, bcdDevice: 0,
            vdos: [idHeaderVDO(dfpValue: 3)], specRevision: 0)
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [], ports: ports, identities: [cableIdentityOnSamePort],
            entries: entries, positionalPortKeys: ["2/1"], externalConnected: true)

        // No rung resolves: rung a fails (inactive positional target), rung
        // b fails (the cable identity is never consulted), rung c fails
        // (two ambiguous active ports).
        #expect(result == nil)
    }

    // MARK: - 9. Winning derivation from maxPowerMW between two options

    @Test("Winning is the largest option <= maxPowerMW when there's no exact match")
    func winningPicksLargestBelowMaxPower() {
        let pdos = [
            fixedPDORaw(voltsMV: 9000, currentMA: 3000),   // 27W
            fixedPDORaw(voltsMV: 20000, currentMA: 3000),  // 60W
        ]
        let ports = [port(number: 1, active: true)]
        // 45W sits between 27W and 60W: 27W is the largest option <= 45W.
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 45000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1"],
            externalConnected: true
        )
        #expect(result?.options.count == 2)
        #expect(result?.winning?.maxPowerMW == 27000)
    }

    @Test("Winning is nil when no option is <= maxPowerMW, but the source still synthesizes with its options")
    func winningNilWhenNoOptionFitsButSourceStillBuilds() {
        let pdos = [
            fixedPDORaw(voltsMV: 9000, currentMA: 3000),   // 27W
            fixedPDORaw(voltsMV: 20000, currentMA: 3000),  // 60W
        ]
        let ports = [port(number: 1, active: true)]
        // 10W is below every option's wattage.
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 10000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1"],
            externalConnected: true
        )
        #expect(result != nil)
        #expect(result?.options.count == 2)
        #expect(result?.winning == nil)
    }

    // MARK: - 10. RDO path uses PDO transmission order, not the sorted display order

    @Test("RDO PDO-position selects by original transmission order, not the wattage-sorted display order")
    func rdoUsesOriginalOrderNotSortedOrder() {
        // Original order: 60W, 15W, 36W. Sorted-for-display order would be
        // 60W, 36W, 15W. RDO position 3 (1-based) must select the THIRD PDO
        // as transmitted (36W), not the third item in the sorted list (15W).
        let pdos = [
            fixedPDORaw(voltsMV: 20000, currentMA: 3000),  // 60W, position 1
            fixedPDORaw(voltsMV: 5000, currentMA: 3000),   // 15W, position 2
            fixedPDORaw(voltsMV: 12000, currentMA: 3000),  // 36W, position 3
        ]
        let ports = [port(number: 1, active: true)]
        // Bits 31:28 = 3 (position 3, 1-based).
        let rdo: UInt32 = 3 << 28
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: rdo, maxPowerMW: 36000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1"],
            externalConnected: true
        )
        #expect(result?.winning?.maxPowerMW == 36000)
        #expect(result?.winning?.voltageMV == 12000)
    }

    // MARK: - 11. Non-USB-C target exclusion (MagSafe)

    @Test("Non-USB-C target exclusion (MagSafe): positional rung lands on MagSafe, no other anchor -> nil")
    func magSafeTargetExcluded() {
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [port(number: 1, typeDescription: "MagSafe 3", active: true)]
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["17/1"],
            externalConnected: true
        )
        #expect(result == nil)
    }

    // MARK: - 12. Non-USB-C target exclusion (other port types, e.g. Inductive)

    @Test("Non-USB-C target exclusion (Inductive): positional rung lands on a non-USB-C, non-MagSafe port, no other anchor -> nil")
    func nonUSBCPortTypeExcluded() {
        // A18 Pro ("MacBook Neo") corpus machines have Port-Inductive ports
        // (raw PortType 18). isValidTarget must require USB-C positively
        // (portKey prefix "2/"), not just exclude MagSafe by name, or a port
        // type like this one would wrongly qualify as a synthesis target.
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [port(number: 1, typeDescription: "Inductive", rawType: "18", active: true)]
        let entries = [ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000)]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["18/1"],
            externalConnected: true
        )
        #expect(result == nil)
    }

    // MARK: - 13. Gate 2b: a real USB-C-parented source anywhere blocks synthesis

    @Test("Gate 2b: a real, winning-less USB-C-parented source on the positional target blocks synthesis entirely, not just that port")
    func realUSBCSourceWithoutWinningBlocksSynthesis() {
        // Port A is genuinely charging and macOS HAS published a real node
        // for it, but negotiation hasn't produced a positive winning yet.
        // Port B is a second active, uncovered port (e.g. a dock). Before
        // gate 2b existed: gate 2 passed (no real source has a live
        // winning), the positional rung rejected A (covered by the real
        // source), and rung c then attributed A's own live entry to B,
        // which is wrong: A's negotiation is just slow, not synthesis's
        // problem to solve. Gate 2b declines the whole machine instead,
        // because a real USB-C-parented node existing anywhere is direct
        // evidence macOS's node publication works for USB-C here.
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [
            port(number: 1, active: true),  // Port A: real node, no winning yet
            port(number: 2, active: true),  // Port B: active, uncovered
        ]
        let realSources = [
            PowerSource(id: 77, name: "USB-PD", parentPortType: 2, parentPortNumber: 1, options: [], winning: nil),
        ]
        let entries = [
            ContractEntry(index: 0, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000),  // A's own live entry
            ContractEntry(index: 1, rawPDOs: [], activeRdo: 0, maxPowerMW: 0),
        ]

        let result = PowerSourceSynthesis.synthesizedSource(
            realSources: realSources,
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1", "2/2"],
            externalConnected: true
        )
        #expect(result == nil)
    }

    // MARK: - 14. Rung a requires entries.count == positionalPortKeys.count

    @Test("Rung a is skipped on a count mismatch, falling to rung c; the same fixture with matching counts lets rung a win")
    func positionalRungRequiresMatchingCardinality() {
        // hpmPortKeys() filters to USB-C + MagSafe only, so a machine with a
        // filtered-out port type in the mix (A18 Pro's Port-Inductive) can
        // have a PortControllerInfo whose slot count doesn't match
        // positionalPortKeys.count. Both ports below are active, uncovered,
        // and valid; the live entry sits at index 1 either way.
        let pdos = [fixedPDORaw(voltsMV: 20000, currentMA: 3000)]
        let ports = [
            port(number: 1, active: true),
            port(number: 2, active: true),
        ]
        let entries = [
            ContractEntry(index: 0, rawPDOs: [], activeRdo: 0, maxPowerMW: 0),
            ContractEntry(index: 1, rawPDOs: pdos, activeRdo: 0, maxPowerMW: 60000),
        ]

        // Mismatch: entries.count (2) != positionalPortKeys.count (3).
        // Rung a is skipped entirely (not attempted with an out-of-range or
        // stale index), so attribution falls to rung b (no identities, does
        // nothing) then rung c. Two valid, active, uncovered ports exist
        // machine-wide, so rung c is ambiguous and declines: nil.
        let mismatched = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1", "2/2", "2/3"],
            externalConnected: true
        )
        #expect(mismatched == nil, "Expected rung c to decline (2 valid ports, ambiguous), got \(String(describing: mismatched))")

        // Companion: same ports and entries, but positionalPortKeys.count
        // now matches entries.count (2). Rung a is attempted and succeeds
        // immediately: entry.index 1 -> positionalPortKeys[1] "2/2" -> port
        // @2, which is active and uncovered. This proves the mismatch case
        // above is genuinely a different code path (rung c declining),
        // not just a fixture that always resolves to nil.
        let matched = PowerSourceSynthesis.synthesizedSource(
            realSources: [],
            ports: ports,
            identities: [],
            entries: entries,
            positionalPortKeys: ["2/1", "2/2"],
            externalConnected: true
        )
        #expect(matched?.portKey == "2/2")
    }
}
