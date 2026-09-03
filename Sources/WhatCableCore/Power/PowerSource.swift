import Foundation

/// One PDO (Power Data Object) advertised by the connected source.
public struct PowerOption: Hashable {
    /// Which kind of PDO this option came from.
    ///
    /// The charging-path resistance regression can only be attributed under a
    /// contract whose voltage does not move, so it needs to know whether the
    /// source is holding a fixed PDO or steering its own output (PPS / AVS).
    ///
    /// Three states, not two, and the distinction is load-bearing. `nonFixed`
    /// means a supply type WAS reported and it is not fixed, which is positive
    /// evidence to reject on. `unknown` means nothing reported one at all,
    /// which is the SMC contract route (`SMCContractSynthesis` reads volts,
    /// amps and watts from the SMC and there is no supply type in those keys).
    /// Collapsing the two would let an unrecognised class string fall through
    /// to the weaker `unknown` handling, which is the exact hole this exists
    /// to close.
    ///
    /// No finer detail than "not fixed" is recorded, because the corpus has
    /// only ever shown one non-fixed SELECTION to name it from, and that one
    /// supports less than it looks like it does. Measured 2026-09-03 by
    /// decoding the RDO-selected PDO out of probe 32's raw integer arrays,
    /// reading no class string at all: every selection that decodes is fixed
    /// EXCEPT one, on `m1_macos26.5.2_af`, where `PortControllerActiveContractRdo`
    /// of `0x230390e4` picks object position 2, and position 2 of that port's
    /// PDO list is `0x9a45b4fe`, a Variable PDO (bits 31:30 = 10). No
    /// augmented (PPS / AVS) PDO has ever been selected anywhere in the
    /// corpus.
    ///
    /// READ THAT AS "A VARIABLE PDO HAS BEEN SELECTED SOMEWHERE", NOT AS "A
    /// MAC CHARGED FROM A VARIABLE CONTRACT". Two things say so, and PR #599's
    /// gate is right that the earlier wording let the stronger reading stand.
    /// Both are read straight out of that machine's probe 32:
    ///
    /// - the Variable selection sits on the port that LOST the election
    ///   (`PortControllerLoserReason` 1, `PortControllerMaxPower` 0,
    ///   `PortControllerElectionFailReason` 4). The port that WON that
    ///   machine's 52 W supply (`LoserReason` 0, `MaxPower` 52000, matching
    ///   the adapter's own 20 V / 2.6 A / 52 W keys) reports an
    ///   `ActiveContractRdo` of ZERO.
    /// - that register behaves like a latch rather than a live view, so a
    ///   non-zero word on an idle port is not evidence that contract is
    ///   running now. Two signatures, both re-derived by two parsers sharing
    ///   no code, over the 926 untruncated probe-32 dumps that publish
    ///   `PortControllerInfo` (3065 port entries, 946 of them carrying a
    ///   non-zero RDO): 6 of those 946 select a PDO slot that holds a padding
    ///   zero, `m1max_macos26.6_f` among them, where two ports both report
    ///   `0x538759d6` (object position 5) against a list whose
    ///   `PortControllerNPDOs` is 1; and 66 of the 926 folders carry one
    ///   identical non-zero RDO word on two ports at once.
    ///
    /// It is still the only non-fixed selection ever seen, so it stays named:
    /// it is the one piece of evidence that these registers can carry a
    /// non-fixed PDO at all. It is not evidence that a Mac will hold a
    /// Variable contract, and it is not a mapping from a class string to a
    /// supply type. That mapping would still be invented rather than observed.
    ///
    /// Deliberately NO precise total here, and that is a considered omission
    /// rather than laziness. The figure this comment used to carry ("2321
    /// active contracts across 786 machines, all fixed") was wrong twice over:
    /// the regex behind it could not match a leading minus, so it skipped
    /// every PDO with bit 31 set, and the replacement figure double-counted,
    /// because probe 32 prints its whole battery node a SECOND time under
    /// `=== AppleACAdapter / ChargerData ===`. Two parsers written
    /// independently both made the second mistake and agreed with each other,
    /// which is why agreement was not enough. The claim above is the part that
    /// survives re-derivation. Re-derive rather than quoting a total, and
    /// dedupe the sections when you do.
    ///
    /// That measurement is about what was NEGOTIATED. It says nothing about
    /// what chargers ADVERTISE, and it must not be read as "PPS is absent from
    /// the corpus", because it is not: well over a third of the machines that
    /// report a PDO list are plugged into a source offering PPS. Both facts are
    /// true at once, and why they are consistent (a Mac asks a PPS-capable
    /// charger for a fixed PDO) is set out in full at
    /// `ChargingInputResolver.contractIsEligible`. Read that before acting on
    /// any of this; it is deliberately not repeated here.
    ///
    /// Probes 19 and 32 AGREE that PPS is commonly advertised. An earlier draft
    /// of this comment recorded an "unexplained discrepancy" between them, with
    /// probe 32 decoding zero augmented PDOs against probe 19's 537. That
    /// discrepancy does not exist and the caveat has been removed rather than
    /// softened, because a false caveat is worse than none: it tells the next
    /// reader there is a mystery to go and solve.
    ///
    /// PROBE 19'S FIGURES ARE QUOTED HERE AND PROBE 32'S DELIBERATELY ARE NOT.
    /// Probe 19 advertises 7001 fixed, 537 augmented across 384 folders, and 8
    /// variable (measured 2026-09-03, truncated dumps excluded). Three parsers
    /// written independently during the PR #599 gate reproduced those exactly,
    /// which is why they are the numbers to rely on. No probe-32 TOTAL is
    /// quoted, because probe 32 prints the same port data twice and three
    /// careful parsers that cut the duplicate differently produced three
    /// different totals. Where you make that cut is a judgement call with no
    /// obviously right answer, and no code here depends on the total anyway.
    /// What every one of those parsers agreed on is the part that matters:
    /// probe 32's arrays DO advertise augmented PDOs, on hundreds of machines.
    ///
    /// The structural comparison survives where the totals do not, because it
    /// compares lists instead of counting them. On the 1135 folders where both
    /// probes are readable, 1134 carry an identical PDO multiset, and augmented
    /// PDOs appear under BOTH probes on exactly the same 297 folders, with none
    /// where only one sees them. That doubles as a check on the de-duplication
    /// itself: probe 19 lists each PDO once, so a reader that failed to collapse
    /// probe 32's duplicate would hand over a list twice as long and the
    /// multisets would disagree on nearly every folder.
    ///
    /// They could hardly disagree, which is the part worth remembering: both
    /// read the same IOKit key, `AppleSmartBattery.PortControllerInfo`, and
    /// probe 19 simply prints a decode of the array probe 32 prints raw. What
    /// produced the phantom is the trap to avoid: probe 32 stores the
    /// augmented PDOs AFTER the `PortControllerNPDOs` count, so a reader that
    /// treats that count as the array length drops every augmented PDO and
    /// reports a clean zero. Probe 19's own output shows this plainly, listing
    /// `PDO[5] = ... -> SPR PPS` on a port it labels `nPDOs=5`.
    public enum SupplyKind: String, Sendable, Hashable {
        /// A fixed-voltage PDO.
        case fixed
        /// A supply type was reported and it is not fixed: battery, variable,
        /// PPS or AVS augmented, or a class string we do not recognise.
        case nonFixed
        /// Nothing reported this option's supply type.
        case unknown
    }

    public let voltageMV: Int
    public let maxCurrentMA: Int
    public let maxPowerMW: Int
    public let supplyKind: SupplyKind

    /// `supplyKind` is defaulted and trailing on purpose: 93 call sites across
    /// the sources and tests construct a `PowerOption`, and none of them needs
    /// to change. A caller that genuinely has no supply-type information gets
    /// the honest answer by saying nothing.
    public init(voltageMV: Int, maxCurrentMA: Int, maxPowerMW: Int, supplyKind: SupplyKind = .unknown) {
        self.voltageMV = voltageMV
        self.maxCurrentMA = maxCurrentMA
        self.maxPowerMW = maxPowerMW
        self.supplyKind = supplyKind
    }

    public var voltsLabel: String {
        String(format: "%.0fV", locale: .current, Double(voltageMV) / 1000)
    }
    public var ampsLabel: String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        let amps = Double(maxCurrentMA) / 1000
        return (formatter.string(from: NSNumber(value: amps)) ?? String(amps)) + "A"
    }
    public var wattsLabel: String {
        String(format: "%.0fW", locale: .current, Double(maxPowerMW) / 1000)
    }
}

/// A power source advertised on a USB-C / MagSafe port (parsed from
/// `IOPortFeaturePowerSource`). One port may have multiple sources
/// (e.g. "USB-PD" + "Brick ID").
public struct PowerSource: Identifiable, Hashable {
    public let id: UInt64
    public let name: String                // "USB-PD", "Brick ID"
    public let parentPortType: Int         // 0x2 = USB-C, 0x11 = MagSafe 3
    public let parentPortNumber: Int
    public let options: [PowerOption]
    public let winning: PowerOption?
    /// HPM controller UUID for this port, captured by walking the IOKit
    /// parent chain from the `IOPortFeaturePowerSource` node up through the
    /// HPM interface to the HPM device (`AppleHPMDevice` / `AppleHPMDeviceHALType3`).
    /// Internal join key only. Never serialised to JSON or text output.
    public let hpmControllerUUID: String?
    /// True when this source was built by `PowerSourceSynthesis` from
    /// `AppleSmartBattery`'s `PortControllerInfo` rather than read from a
    /// real `IOPortFeaturePowerSource` node (issue #401: macOS never
    /// creates that node for USB-C on M1 Pro/Max/Ultra). Defaults to false
    /// so every existing call site and fixture keeps working unchanged.
    public let isSynthesized: Bool

    public init(
        id: UInt64,
        name: String,
        parentPortType: Int,
        parentPortNumber: Int,
        options: [PowerOption],
        winning: PowerOption?,
        hpmControllerUUID: String? = nil,
        isSynthesized: Bool = false
    ) {
        self.id = id
        self.name = name
        self.parentPortType = parentPortType
        self.parentPortNumber = parentPortNumber
        self.options = options
        self.winning = winning
        self.hpmControllerUUID = hpmControllerUUID
        self.isSynthesized = isSynthesized
    }

    public var maxPowerMW: Int {
        if let max = options.map(\.maxPowerMW).max(), max > 0 {
            return max
        }
        return winning?.maxPowerMW ?? 0
    }

    /// Match key joining a power source to its port.
    public var portKey: String { "\(parentPortType)/\(parentPortNumber)" }

    /// Canonical in-session join key: normalised UUID (32 lowercase hex chars)
    /// when one was captured, else `portKey`. Mirrors `AppleHPMInterface.canonicalJoinKey`.
    /// Internal only; never expose in JSON or text output.
    public var canonicalJoinKey: String {
        if let uuid = hpmControllerUUID {
            let normalised = uuid.replacingOccurrences(of: "-", with: "").lowercased()
            if normalised.count == 32 { return normalised }
        }
        return portKey
    }
}

extension PowerSource {
    /// True when this source belongs to the same physical port as `port`.
    ///
    /// Matching is UUID-based when both sides resolved a UUID (M3+, guaranteed
    /// correct: distinct HPM controller dies have distinct UUIDs). Falls back to
    /// `portKey` comparison when either side is missing a UUID (M1/M2, or a
    /// defensive nil from an unusual registry layout). The fallback preserves
    /// existing behaviour on hardware that predates the UUID probe.
    ///
    /// A source that fails to resolve a UUID while the port has one is NOT
    /// silently dropped: `canonicalJoinKey` falls back to `portKey` on the
    /// source side, so it still matches the port's `portKey` fallback, and
    /// the match still fires as long as `ParentPortType/Number` agrees.
    public func canonicallyMatches(port: AppleHPMInterface) -> Bool {
        guard let portKey = port.portKey else { return false }
        // When both sides have a UUID, compare them directly. This is the
        // collision-proof path on M3+.
        if let sourceUUID = hpmControllerUUID,
           let portUUID = port.hpmControllerUUID {
            let sn = sourceUUID.replacingOccurrences(of: "-", with: "").lowercased()
            let pn = portUUID.replacingOccurrences(of: "-", with: "").lowercased()
            if sn.count == 32 && pn.count == 32 { return sn == pn }
        }
        // Fallback: compare portKey strings. Works correctly on M1/M2 where
        // MagSafe and USB-C portKeys already differ by type prefix (17/ vs 2/).
        return self.portKey == portKey
    }

    /// The charging source to represent this port by. Name priority is
    /// USB-PD, then Apple's brick identity ("Brick ID"), then plain Type-C
    /// current ("TypeC", the basic 5V/1.5A-3A a charger delivers over the CC
    /// resistor without PD negotiation, up to ~15W).
    ///
    /// A source that actually holds a winning (negotiated) contract is
    /// preferred over one that does not, even if the latter ranks higher by
    /// name. Otherwise a bare "Brick ID" identity node with no contract would
    /// shadow a winning "TypeC" on the same port (a real non-PD charger),
    /// and the port would read as "no live source" and spin forever. Only
    /// when no source has a contract do we fall back to name priority alone
    /// (a charger still negotiating, or advertised capability).
    public static func preferredChargingSource(in sources: [PowerSource]) -> PowerSource? {
        let priority = ["USB-PD", "Brick ID", "TypeC"]
        // First: a source that holds a winning contract, by name priority.
        for name in priority {
            if let s = sources.first(where: { $0.name == name && ($0.winning?.maxPowerMW ?? 0) > 0 }) {
                return s
            }
        }
        // Then: any source by name priority (no contract yet / advertised only).
        for name in priority {
            if let s = sources.first(where: { $0.name == name }) {
                return s
            }
        }
        return nil
    }

    /// True when these sources expose a negotiated contract: a `winning` PDO
    /// with positive wattage.
    ///
    /// This is a raw negotiation signal. It does NOT prove the system accepted
    /// external power: a controller can retain a winning PDO after the Mac has
    /// stopped drawing (the stale-PDO case). Most callers use it only to build
    /// a `chargingPortKeys` set that feeds `anotherPortActivelyCharging`, which
    /// is consumed solely by `ChargingDiagnostic` (it applies the system-power
    /// gate downstream, so a stale PDO never surfaces a charging claim). One
    /// caller (`PowerMonitorWindow`) uses it directly, but only for cross-port
    /// attribution (does *this* port hold the contract), not to make a charging
    /// claim. Any NEW caller that turns this into a user-visible charging claim
    /// must apply the system-power gate itself (`SystemPowerState.onBattery`);
    /// this call alone is not sufficient evidence.
    public static func hasLiveChargingContract(in sources: [PowerSource]) -> Bool {
        guard let source = preferredChargingSource(in: sources),
              let winning = source.winning else { return false }
        return winning.maxPowerMW > 0
    }
}

extension AppleHPMInterface {
    /// This port's identity, or nil when the port has no number (so nothing can
    /// be keyed to it at all).
    public var identity: PortIdentity? {
        guard let n = portNumber else { return nil }
        return PortIdentity.from(
            typeDescription: portTypeDescription,
            reportedTypeCode: rawProperties["PortType"].flatMap { Int($0) },
            number: n
        )
    }

    public var portKey: String? { identity?.key }

    /// The canonical in-session join key for this port.
    ///
    /// When `hpmControllerUUID` is present, this is the UUID with dashes
    /// stripped and lowercased (32 hex chars) -- the same normalised form
    /// `HPMPortUUIDMap` uses. When absent (M1/M2 or defensive nil), it falls
    /// back to `portKey` so every port still has a key.
    ///
    /// **Internal only.** This value must never appear in JSON, text output,
    /// or the UI. Use `portKey` for all user-visible output.
    ///
    /// Two ports that share the same `@N` suffix but belong to different
    /// physical connectors (MagSafe@1 and USB-C@1, both wired to separate
    /// HPM controller dies) carry distinct UUIDs. Their canonical join keys
    /// are therefore distinct even when their `portKey` values would agree.
    public var canonicalJoinKey: String? {
        if let uuid = hpmControllerUUID {
            let normalised = uuid.replacingOccurrences(of: "-", with: "").lowercased()
            if normalised.count == 32 { return normalised }
        }
        return portKey
    }
}
