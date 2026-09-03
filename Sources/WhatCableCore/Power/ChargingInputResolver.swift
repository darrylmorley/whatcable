import Foundation

/// Decides whether this tick's power state is eligible for the charging-path
/// resistance regression, and if so, which port and contract the estimate
/// belongs to (charging-path resistance rework, 2026-08).
///
/// The regression measures the DC-in slope (SMC `VD0R` vs `ID0R`), which is a
/// machine-wide reading, so it is only attributable when exactly one charging
/// input is resolved and stable. Every gate here is an owner-set acceptance
/// criterion; loosening one is a spec change, not a cleanup:
///
/// - laptops only (a desktop's DC-in is its internal PSU, not a cable);
/// - charger attached and externally connected;
/// - exactly one port holding a winning contract (two chargers split the
///   DC-in reading between cables, so neither slope means anything);
/// - USB-C or MagSafe charge-in only (phase 2 lifted the phase-1 MagSafe
///   rejection; see `chargeInPortTypes`);
/// - a fixed-voltage contract, at any voltage. PPS / AVS sources move their
///   own output voltage, which the single-ended slope cannot distinguish
///   from cable drop. The supply type comes from the PDO kind IOKit
///   publishes, not from the voltage. Where no supply type is available at
///   all, the phase-1 voltage-tier proxy still applies, at exactly its old
///   strength: see `contractIsEligible`.
///
/// Pure logic, no platform imports: unit-tested directly in Core tests.
public enum ChargingInputResolver {

    /// Identity of the charging path a regression sample belongs to. Any
    /// change (port, connection, renegotiated contract) invalidates every
    /// previously collected sample, so the accumulator resets when this
    /// value changes.
    public struct Fingerprint: Equatable, Sendable {
        /// Canonical join key of the charging port (HPM controller UUID when
        /// present, else "type/number"). Internal only, never serialised.
        public let portJoinKey: String
        /// Display key ("type/number") for attribution in the UI and JSON.
        public let portKey: String
        /// IOKit registry entry ID of the representative power-source node.
        /// This is the CONNECTION identity: a replug (which is how a cable
        /// swap happens physically) tears the node down and recreates it with
        /// a new ID, so two cables negotiating the identical contract on the
        /// same port still get distinct fingerprints. Review finding on the
        /// first cut, which carried port + contract only and would have
        /// spliced them.
        public let sourceID: UInt64
        public let contractVoltageMV: Int
        public let contractCurrentMA: Int

        public init(
            portJoinKey: String,
            portKey: String,
            sourceID: UInt64,
            contractVoltageMV: Int,
            contractCurrentMA: Int
        ) {
            self.portJoinKey = portJoinKey
            self.portKey = portKey
            self.sourceID = sourceID
            self.contractVoltageMV = contractVoltageMV
            self.contractCurrentMA = contractCurrentMA
        }
    }

    /// The parent port types a charging input may arrive on.
    ///
    /// USB-C (0x2) and MagSafe 3 (0x11). MagSafe was rejected in phase 1 by
    /// owner call, pending the channel-resolution question; phase 2 settled it.
    /// The regression reads the machine-wide SMC DC-in rail (VD0R / ID0R), not
    /// a per-port SMC channel, so there is no channel to resolve and no
    /// per-port join for a MagSafe reading to fail: the per-port SMC channels
    /// only ever carry power flowing OUT of a port. What a MagSafe reading
    /// measures is the MagSafe cable's own path, which is exactly as valid as
    /// the USB-C case, and the port attribution comes from the IOKit node the
    /// same way it does for USB-C.
    ///
    /// Corpus, re-derived 2026-09-03 (the 2026-09-02 figures here read 1027
    /// blocks / 636 / 377 / 14 and did not reproduce; they were low). All
    /// 1122 winning-option blocks in untruncated probe-17 captures, which is
    /// the same total the corpus sweep pins: 712 USB-C, 394 MagSafe, 16 on a
    /// port type the capture does not name. The type code and the separate
    /// `ParentPortTypeDescription` string agree on every one of them. Every
    /// one is a fixed PDO. Narrowed to M1 Pro/Max/Ultra the split is 58
    /// MagSafe, ZERO USB-C and one unnamed, which is issue 401 seen from the
    /// other side: MagSafe is the only route to an estimate on that silicon
    /// when it charges the way those machines usually charge.
    ///
    /// Matched positively, never as "not MagSafe" or "not USB-C": A18 Pro
    /// corpus machines publish `Port-Inductive` ports, and other port types we
    /// have not seen may exist.
    static let chargeInPortTypes: Set<Int> = [
        PortIdentity.usbCTypeCode,
        PortIdentity.magSafeTypeCode,
    ]

    /// The fixed SPR PDO voltage tiers (USB-PD r3.x table 6-9).
    ///
    /// This is no longer the contract gate. It is only the fallback proxy used
    /// when a source reports no supply type at all: see `contractIsEligible`.
    static let fixedSPRVoltagesMV: Set<Int> = [5000, 9000, 12000, 15000, 20000]

    /// Whether this winning contract holds a voltage the regression can be
    /// attributed under.
    ///
    /// The regression fits DC-in volts against DC-in amps, so it can only
    /// separate cable drop from source behaviour while the source is holding
    /// one voltage. A PPS or AVS source steers its own output, which the
    /// single-ended slope cannot tell apart from cable drop.
    ///
    /// THIS GATE IS NOT WHAT PROTECTS THE REGRESSION. Read that before
    /// changing anything here, because the rest of this comment reads like it
    /// is and it is not. The supply-kind check is a cheap first filter: it
    /// costs one enum comparison and it throws out the obvious case early. If
    /// it were deleted tomorrow the estimate would still not be corrupted by
    /// a moving source, because two gates downstream in
    /// `RegressionAccumulator.estimate()` do that job:
    ///
    /// - the positive-slope rejection. Voltage rising with current is
    ///   physically impossible for a resistive path, and the accumulator's own
    ///   comment already names the usual cause: "a source moving its
    ///   setpoint". A source stepping its output up mid-measurement produces
    ///   exactly that signature and is thrown out as `unreliable`.
    /// - the R-squared floor of 0.7. A source moving independently of load
    ///   scatters the fit, and a scattered fit cannot reach `stable`.
    ///
    /// Be exact about what that second one covers, because "the floor protects
    /// the output" overstates it. `RegressionAccumulator.estimate()` applies
    /// the floor on the LAST rung of its ladder only: a buffer holding fewer
    /// than `minSamplesForStable` distinct samples returns `converging`
    /// BEFORE the floor is consulted, and that estimate carries a real
    /// computed milliohm value rather than a zero. The floor gates the
    /// `stable` STATUS, not every value the model can carry.
    ///
    /// What keeps a converging value off the screen is the display layer, one
    /// surface at a time, and there is one surface where it is NOT kept off.
    /// An earlier version of this comment said "nothing user-facing shows a
    /// converging milliohm figure today". That is false, and PR #599's gate
    /// caught it. Every surface below was read, and the JSON one was run
    /// (2026-09-03):
    ///
    /// - `--monitor` (`formatResistance` in `MonitorCommand`) and
    ///   `--dashboard` (`dashboardResistanceLine` in `DashboardApp`) both
    ///   render `converging` as "measuring (N samples)". No number.
    /// - the Power Monitor window renders it as a progress spinner, a
    ///   "Measuring while your Mac charges" line and a sample count. No
    ///   number.
    /// - `CableResistanceEstimate.tier(ratedFiveA:)` returns nil unless the
    ///   status is `stable`, so a converging estimate contributes no tier to
    ///   the session monitor or Cable History.
    /// - `--monitor-json` DOES emit the number. `runJSONMonitor` encodes the
    ///   whole `PowerMonitorSnapshot` with a plain `JSONEncoder` and filters
    ///   nothing, so a converging tick goes out with `"status":"converging"`
    ///   and a real `"milliohms"` in the same object. Confirmed by running it:
    ///   15 samples (over `minSamplesForValue`, under `minSamplesForStable`)
    ///   down a synthetic 142.7 mOhm path, through the real accumulator and
    ///   the real encoder, produced
    ///   `"status":"converging"` beside `"milliohms":142.69999999999783`.
    ///
    /// So the claim that holds is the narrower one: no HUMAN-READABLE surface
    /// shows a converging milliohm figure, and the documented machine schema
    /// does. That is the schema working as intended (a consumer is handed the
    /// raw snapshot and the status word to gate on) and this PR does not move
    /// it. Anything NEW that reads `estimate.milliohms` has to check the
    /// status for itself; the number is not gated, only the status is.
    ///
    /// Neither gate is touched by this PR. Both are load-bearing. Do not
    /// loosen the slope check or drop the R-squared floor on the reasoning
    /// that the kind gate upstream already excludes PPS: it does not, it only
    /// excludes the ones that announce themselves, and the two gates below are
    /// the only thing standing behind the `.unknown` branch, which accepts a
    /// source whose kind we never learned at all.
    ///
    /// Equally, do not TIGHTEN this gate believing it is what keeps the
    /// feature honest. Tightening it buys nothing the accumulator is not
    /// already doing, and it costs real estimates on real machines: the
    /// `.unknown` branch below is the only route to an estimate on M1
    /// Pro / Max / Ultra.
    ///
    /// What the corpus actually shows, measured 2026-09-03, and it is not
    /// what an earlier draft of this comment said:
    ///
    /// - `.nonFixed` has never fired on a corpus machine. Every negotiated
    ///   contract is fixed: 1122 of 1122 `WinningPowerSourceOption` blocks in
    ///   probe 17 carry the same single `Class` string, counted three times
    ///   with parsers sharing no code.
    /// - PPS chargers are NOT rare, and this is the correction. Probe 19
    ///   decodes the raw source-capability list, which is what the charger
    ///   ADVERTISES rather than what the Mac negotiated. Across 982 folders it
    ///   yields 7546 PDOs: 7001 fixed, 8 variable, and 537 SPR PPS / EPR AVS
    ///   spread over 384 folders. An earlier draft quoted the 7001 as though
    ///   it were the total and concluded every advertised PDO was fixed. It is
    ///   the fixed subset. Well over a third of the machines that report a PDO
    ///   list are plugged into something that offers PPS.
    /// - Those two facts are consistent, and the gap between them is the
    ///   whole point: a Mac faced with a PPS-capable charger still asks for a
    ///   fixed PDO. What has never been observed is a PPS or AVS contract
    ///   WINNING, not a PPS charger being present. Anyone reasoning "PPS is
    ///   exotic, so this cannot happen" has the wrong picture.
    ///
    /// And a PPS source is not automatically a problem even when one does
    /// win. PPS steers its output only when asked to; a PPS source holding a
    /// STEADY setpoint behaves exactly as a fixed supply does, and the slope
    /// measured under it is the real path resistance, not an artefact. Phase 1
    /// already defines the measured path as including the charger's own output
    /// impedance and load regulation (see `planning/cable-resistance-live-smc.md`
    /// and `RegressionAccumulator`'s header: cable VBUS+GND loop + connectors +
    /// charger output impedance + Mac board path). A steady PPS source
    /// contributes to that path the same way a fixed one does. The case the
    /// slope and R-squared gates exist for is a source that MOVES while we
    /// measure, which is a behaviour, not a supply type. That is why the
    /// behaviour gates are the protection and the type gate is only a filter.
    ///
    /// For any future work on this question, probe 19's raw PDO decode is the
    /// authoritative source, NOT the `Class` string. The PDO list is the
    /// actual USB-PD source-capability message; `Class` is a derived flag
    /// several layers above it, and it describes only the option that won.
    /// The 537 augmented PDOs are invisible from `Class` entirely, which is
    /// precisely how the earlier draft got this wrong.
    ///
    /// Probe 32's own advertised PDO arrays agree with that, and an earlier
    /// draft of this comment said otherwise. It recorded probe 32 decoding
    /// zero augmented entries against probe 19's 537, and called the
    /// disagreement unexplained. There is no disagreement: the two probes read
    /// the same IOKit key and, on the 1135 folders where both are readable,
    /// 1134 carry an identical PDO multiset with augmented PDOs in exactly the
    /// same 297 folders. The zero came from a reader that treated
    /// `PortControllerNPDOs` as the array length, and probe 32 stores the
    /// augmented PDOs after that count. Full derivation at
    /// `PowerOption.SupplyKind`.
    ///
    /// - `.fixed`: accepted at any voltage. Phase 1 also required membership
    ///   of the fixed SPR tier set, as a proxy for "fixed", and that proxy
    ///   was wrong in both directions. It refused 91 winning contracts in the
    ///   corpus that sit off a standard tier: 84 at 28 V (Apple's 140 W EPR
    ///   brick), 4 at 19.5 V (a 63 W charger), 2 at 10 V (30 W) and 1 at
    ///   21 V. The 19.5 V and 10 V cases were confirmed genuinely fixed by
    ///   decoding the raw PDO list on those same machines, where the charger
    ///   advertises a fixed PDO at exactly that voltage. The 28 V case is
    ///   Apple's EPR fixed tier and was NOT confirmed the same way, because
    ///   EPR PDOs are carried outside the SPR list this decode reads. Owner
    ///   amended acceptance criterion 4 on 2026-09-02.
    /// - `.nonFixed`: rejected outright, whatever the voltage. This is the
    ///   hole phase 1 documented: a PPS source parked on exactly 5/9/12/15/20 V
    ///   passed the tier set.
    /// - `.unknown`: falls back to the tier set, which is EXACTLY the phase-1
    ///   proxy and no stronger. It is not a supply-type gate and must not be
    ///   read as one: a PPS source held at 20 V would still pass it. It is
    ///   here because the SMC contract route (`SMCContractSynthesis`) has no
    ///   supply-type data at all, and that route is the only thing standing
    ///   between an M1 Pro / Max / Ultra charging over USB-C and no estimate
    ///   whatsoever. Owner ruling 2026-09-02: keep the machine working at
    ///   today's strength rather than lose it, and say plainly that is what
    ///   this branch is.
    static func contractIsEligible(_ winning: PowerOption) -> Bool {
        switch winning.supplyKind {
        case .fixed: return true
        case .nonFixed: return false
        case .unknown: return fixedSPRVoltagesMV.contains(winning.voltageMV)
        }
    }

    /// Resolve this tick's charging input, or nil when any gate fails.
    ///
    /// - Parameters:
    ///   - sources: every power source read this tick (real and synthesized).
    ///   - batteryInstalled: laptop check.
    ///   - externalConnected: `AppleSmartBattery.ExternalConnected`.
    ///   - chargerAttached: live system adapter presence.
    public static func fingerprint(
        sources: [PowerSource],
        batteryInstalled: Bool,
        externalConnected: Bool,
        chargerAttached: Bool
    ) -> Fingerprint? {
        guard batteryInstalled, externalConnected, chargerAttached else { return nil }

        // Ports holding a winning (negotiated) contract, grouped by port so a
        // port publishing several source nodes ("USB-PD" + "Brick ID") counts
        // once. Grouped by `portKey` (type/number), NOT `canonicalJoinKey`:
        // sibling nodes on one physical port each walk the registry for their
        // own HPM UUID, and if one walk fails while the other succeeds their
        // canonical keys differ, which would split one real charging input
        // into two groups and wrongly fail the exactly-one gate (review
        // finding, reproduced in `ChargingInputResolverTests`). `portKey` is
        // identical for siblings by construction.
        let byPort = Dictionary(grouping: sources.filter { ($0.winning?.maxPowerMW ?? 0) > 0 }) {
            $0.portKey
        }
        // Exactly one resolved charging input. Zero means nothing to
        // attribute; two or more means the DC-in rail blends both cables.
        guard byPort.count == 1,
              let portSources = byPort.values.first,
              let source = PowerSource.preferredChargingSource(in: portSources),
              let winning = source.winning else { return nil }

        // USB-C or MagSafe. See `chargeInPortTypes`.
        guard chargeInPortTypes.contains(source.parentPortType) else { return nil }

        // A contract the slope can be attributed under. See `contractIsEligible`.
        guard contractIsEligible(winning) else { return nil }

        // Prefer a UUID-bearing sibling's join key: the representative node
        // may be the one whose UUID walk failed while a sibling's succeeded.
        let joinKey = portSources.first { $0.hpmControllerUUID != nil }?.canonicalJoinKey
            ?? source.canonicalJoinKey
        return Fingerprint(
            portJoinKey: joinKey,
            portKey: source.portKey,
            sourceID: source.id,
            contractVoltageMV: winning.voltageMV,
            contractCurrentMA: winning.maxCurrentMA
        )
    }
}
