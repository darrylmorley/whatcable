import Testing
@testable import WhatCableCore

// Charging-path resistance rework (2026-08): eligibility gates for the charging-path resistance regression.
// Each test names the owner acceptance criterion it pins.

private func source(
    id: UInt64 = 1,
    name: String = "USB-PD",
    portType: Int = 0x2,
    portNumber: Int = 4,
    winningVoltageMV: Int? = 20_000,
    winningCurrentMA: Int = 4_700,
    uuid: String? = "0123456789abcdef0123456789abcdef"
) -> PowerSource {
    let winning = winningVoltageMV.map {
        PowerOption(voltageMV: $0, maxCurrentMA: winningCurrentMA, maxPowerMW: $0 * winningCurrentMA / 1000)
    }
    return PowerSource(
        id: id, name: name, parentPortType: portType, parentPortNumber: portNumber,
        options: winning.map { [$0] } ?? [], winning: winning, hpmControllerUUID: uuid
    )
}

private func resolve(
    _ sources: [PowerSource],
    batteryInstalled: Bool = true,
    externalConnected: Bool = true,
    chargerAttached: Bool = true
) -> ChargingInputResolver.Fingerprint? {
    ChargingInputResolver.fingerprint(
        sources: sources,
        batteryInstalled: batteryInstalled,
        externalConnected: externalConnected,
        chargerAttached: chargerAttached
    )
}

private func kindedSource(
    id: UInt64 = 1,
    portType: Int = 0x2,
    portNumber: Int = 4,
    winningVoltageMV: Int = 20_000,
    winningCurrentMA: Int = 4_700,
    supplyKind: PowerOption.SupplyKind,
    uuid: String? = "0123456789abcdef0123456789abcdef"
) -> PowerSource {
    let winning = PowerOption(
        voltageMV: winningVoltageMV,
        maxCurrentMA: winningCurrentMA,
        maxPowerMW: winningVoltageMV * winningCurrentMA / 1000,
        supplyKind: supplyKind
    )
    return PowerSource(
        id: id, name: "USB-PD", parentPortType: portType, parentPortNumber: portNumber,
        options: [winning], winning: winning, hpmControllerUUID: uuid
    )
}

@Suite("ChargingInputResolver")
struct ChargingInputResolverTests {

    @Test("One USB-C fixed-SPR charging input resolves with port and contract identity")
    func happyPath() {
        let fp = resolve([source()])
        #expect(fp != nil)
        #expect(fp?.portKey == "2/4")
        #expect(fp?.contractVoltageMV == 20_000)
        #expect(fp?.contractCurrentMA == 4_700)
        // Canonical join key is the normalised controller UUID when present.
        #expect(fp?.portJoinKey == "0123456789abcdef0123456789abcdef")
    }

    @Test("Laptops only: no battery, no fingerprint")
    func laptopsOnly() {
        #expect(resolve([source()], batteryInstalled: false) == nil)
    }

    @Test("Requires external power on this tick")
    func requiresExternalPower() {
        #expect(resolve([source()], externalConnected: false) == nil)
        #expect(resolve([source()], chargerAttached: false) == nil)
    }

    @Test("Exactly one resolved charging input: two contracted ports resolve to nil")
    func twoChargersRejected() {
        let a = source(id: 1, portNumber: 1, uuid: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        let b = source(id: 2, portNumber: 2, uuid: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(resolve([a, b]) == nil)
    }

    @Test("Two source nodes on the SAME port (USB-PD + Brick ID) still resolve")
    func multipleNodesOnePort() {
        let pd = source(id: 1, name: "USB-PD")
        let brick = source(id: 2, name: "Brick ID")
        let fp = resolve([pd, brick])
        #expect(fp != nil)
        #expect(fp?.contractVoltageMV == 20_000, "USB-PD is the preferred representative node")
        #expect(fp?.sourceID == 1, "the representative node's registry ID is the connection identity")
    }

    @Test("Sibling nodes with mixed UUID resolution are one input, not two")
    func mixedUUIDSiblingsAreOneInput() {
        // Same physical port, but only one node's HPM UUID walk succeeded (a
        // registry teardown race can do this). Grouping by canonical key
        // would split them into two groups and wrongly fail the exactly-one
        // gate; grouping by portKey must not.
        let pd = source(id: 1, name: "USB-PD", uuid: "0123456789abcdef0123456789abcdef")
        let brick = source(id: 2, name: "Brick ID", uuid: nil)
        let fp = resolve([pd, brick])
        #expect(fp != nil)
        // And the join key still prefers the UUID-bearing sibling.
        #expect(fp?.portJoinKey == "0123456789abcdef0123456789abcdef")
    }

    @Test("The representative node's UUID walk failing still yields the sibling's UUID join key")
    func joinKeyPrefersUUIDBearingSibling() {
        let pd = source(id: 1, name: "USB-PD", uuid: nil)
        let brick = source(id: 2, name: "Brick ID", uuid: "0123456789abcdef0123456789abcdef")
        let fp = resolve([pd, brick])
        #expect(fp != nil)
        #expect(fp?.sourceID == 1, "USB-PD stays the representative")
        #expect(fp?.portJoinKey == "0123456789abcdef0123456789abcdef")
    }

    @Test("No winning contract anywhere resolves to nil")
    func noContract() {
        #expect(resolve([source(winningVoltageMV: nil)]) == nil)
        #expect(resolve([]) == nil)
    }

    @Test("Fixed SPR tiers only: a PPS-style 17.4 V contract is rejected")
    func nonFixedVoltageRejected() {
        #expect(resolve([source(winningVoltageMV: 17_400)]) == nil)
        // EPR fixed 28 V is also out in phase 1 (owner: SPR only).
        #expect(resolve([source(winningVoltageMV: 28_000)]) == nil)
        // Every standard SPR tier passes.
        for tier in [5_000, 9_000, 12_000, 15_000, 20_000] {
            #expect(resolve([source(winningVoltageMV: tier)]) != nil, "\(tier) mV must resolve")
        }
    }

    // Phase 2, item 1. MagSafe was rejected in phase 1 by owner call. The
    // reading measures the MagSafe cable, which is a real removable cable, and
    // the regression reads the machine-wide DC-in rail rather than a per-port
    // SMC channel, so nothing about the port type changes what is measured.
    // Corpus, 2026-09-02: 377 MagSafe winning contracts in probe 17, every
    // one a fixed PDO, and on M1 Pro/Max/Ultra MagSafe is the ONLY port type
    // that publishes a winning contract at all (56 MagSafe, 0 USB-C).
    @Test("MagSafe charging input resolves, with MagSafe port attribution")
    func magSafeResolves() {
        let fp = resolve([source(portType: 0x11, portNumber: 1)])
        #expect(fp != nil)
        #expect(fp?.portKey == "17/1")
        #expect(fp?.contractVoltageMV == 20_000)
    }

    @Test("A port type that is neither USB-C nor MagSafe is still rejected")
    func otherPortTypesRejected() {
        // A18 Pro corpus machines publish Port-Inductive ports. Positive
        // matching on the two known charge-in types, never "not USB-C".
        #expect(resolve([source(portType: 0x30, portNumber: 1)]) == nil)
    }

    @Test("MagSafe charging plus a second port holding a contract is still rejected")
    func magSafePlusDockRejected() {
        // The exactly-one-input gate is what makes the DC-in slope
        // attributable, and it does not care which port types are involved.
        let fp = resolve([
            source(id: 1, portType: 0x11, portNumber: 1),
            source(id: 2, portType: 0x2, portNumber: 3, uuid: "fedcba9876543210fedcba9876543210"),
        ])
        #expect(fp == nil)
    }

    @Test("MagSafe with no winning contract resolves nothing")
    func magSafeWithoutContract() {
        #expect(resolve([source(portType: 0x11, portNumber: 1, winningVoltageMV: nil)]) == nil)
    }

    // Phase 2, item 2. Phase 1 had no supply type at all and used membership of
    // the fixed SPR tier set as a proxy, which is wrong in both directions:
    // a PPS source parked on a standard tier passed, and a genuine fixed PDO
    // at a non-standard voltage was refused. IOKit publishes the type all
    // along, as a `Class` string on the winning option.

    @Test("A PPS contract held at exactly 20 V is rejected")
    func ppsAtTwentyVoltsRejected() {
        #expect(resolve([kindedSource(supplyKind: .nonFixed)]) == nil)
    }

    @Test("An AVS contract at a standard voltage is rejected")
    func avsAtStandardVoltageRejected() {
        // AVS and PPS both reach the resolver as `.nonFixed`: the distinction
        // does not change the verdict, and the parse never invents one.
        #expect(resolve([kindedSource(winningVoltageMV: 15_000, supplyKind: .nonFixed)]) == nil)
    }

    @Test("A fixed contract at a non-standard voltage is accepted")
    func fixedAtNonStandardVoltageAccepted() {
        // Real chargers in the corpus. 19.5 V / 3.25 A (63 W) and 10 V / 3 A
        // (30 W) were confirmed genuinely fixed by decoding the raw PDO list
        // on those same machines; 28 V is Apple's 140 W EPR tier, 84 blocks,
        // not confirmed the same way because EPR PDOs sit outside the SPR
        // list that decode reads. Phase 1 refused all three on the tier
        // proxy. Owner amended acceptance criterion 4 on 2026-09-02 to accept
        // any fixed contract.
        #expect(resolve([kindedSource(winningVoltageMV: 19_500, winningCurrentMA: 3_250, supplyKind: .fixed)]) != nil)
        #expect(resolve([kindedSource(winningVoltageMV: 10_000, winningCurrentMA: 3_000, supplyKind: .fixed)]) != nil)
        #expect(resolve([kindedSource(winningVoltageMV: 28_000, winningCurrentMA: 5_000, supplyKind: .fixed)]) != nil)
    }

    @Test("Unknown kind falls back to the phase-1 tier proxy, and only that")
    func unknownKindUsesTierProxy() {
        // The SMC contract route carries no supply type at all, which is how
        // an M1 Pro charging over USB-C reaches here. Owner ruling
        // 2026-09-02: accept it at exactly phase-1 strength, no wider.
        #expect(resolve([kindedSource(supplyKind: .unknown)]) != nil)
        #expect(resolve([kindedSource(winningVoltageMV: 19_500, winningCurrentMA: 3_250, supplyKind: .unknown)]) == nil)
    }

    @Test("Every fixed SPR tier still resolves under the fixed kind")
    func fixedTiersStillResolve() {
        for v in [5_000, 9_000, 12_000, 15_000, 20_000] {
            #expect(resolve([kindedSource(winningVoltageMV: v, supplyKind: .fixed)]) != nil)
        }
    }
}
