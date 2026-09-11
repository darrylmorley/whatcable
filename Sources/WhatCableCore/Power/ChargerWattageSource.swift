import Foundation

/// Where the "charger wattage" number came from for a given port.
///
/// Most ports get their wattage from the per-port USB-PD negotiation
/// (`portNegotiated`). Some setups (e.g. Thunderbolt docks that deliver
/// power without registering a USB-PD source) only expose a system-wide
/// adapter reading. Under strict conditions we fall back to that value.
public enum ChargerWattageSource: Hashable {
    case portNegotiated(watts: Int)
    case systemAdapterFallback(watts: Int)
    case unknown

    public var watts: Int? {
        switch self {
        case .portNegotiated(let w): return w
        case .systemAdapterFallback(let w): return w
        case .unknown: return nil
        }
    }

    /// Apple's analog charger-identity node. Its options are placeholder
    /// values (often ~2.5W, which rounds to a misleading "3W"), never a real
    /// PD menu, and it never carries a winning contract. The one shared
    /// definition of the name, so the surfaces that have to recognise it stop
    /// each keeping their own literal.
    public static let brickIDSourceName = "Brick ID"

    /// True when `resolved` is a wattage that came out of a Brick ID node's
    /// junk options, so no surface should print it as a number.
    ///
    /// `resolve` diverts a Brick ID port to the system adapter reading
    /// (issue #154), but only when there IS an adapter reading and it is
    /// higher than the brick's own figure. When the divert declines, resolve
    /// falls through to its general per-port branch and hands back that junk
    /// figure as `.portNegotiated`. This is the predicate for that case.
    ///
    /// Deliberately a separate query rather than a new `resolve` case: every
    /// other consumer (`PortSummary`, the formatters, the widget, the app's
    /// port cards) keeps the exact values it has today, JSON output included.
    public static func isUnquantifiedBrickID(
        portSources: [PowerSource],
        resolved: ChargerWattageSource
    ) -> Bool {
        guard case .portNegotiated = resolved else { return false }
        return PowerSource.preferredChargingSource(in: portSources)?.name == brickIDSourceName
    }

    /// Number of active ports that expose a power-source node of their own,
    /// i.e. a port through which the Mac is actually pulling a charging
    /// contract (Brick ID, USB-PD, Type-C, or a synthesized source on M1
    /// Pro/Max).
    ///
    /// This is the count that gates the **Brick ID divert** below (issue #154:
    /// a MagSafe third-party brick shows a junk ~3W Brick ID and the real
    /// wattage is in the system adapter reading). Counting every
    /// `connectionActive` port there let a plain USB-C display cable, or any
    /// data-only device, pose as a second charger and block the divert, so the
    /// port stayed frozen at 3W while the Mac charged at full wattage (issue
    /// #443). A display or data port has no power-source node, so it no longer
    /// counts. Two real chargers each expose a source node, so both still
    /// count and the #46 multi-charger protection holds.
    ///
    /// Deliberately does NOT special-case MagSafe: a MagSafe port that is
    /// actually charging already has a Brick ID / USB-PD source node and is
    /// counted through `hasSourceNode`. A MagSafe cable plugged in but not
    /// into a charger has no source node and correctly does not count (it is
    /// not a competing charger). The source-less legacy fallback for docks
    /// that deliver power without any node (issue #141) is gated on the plain
    /// active-port count instead, not this one.
    ///
    /// - Parameters:
    ///   - ports: Every port on the machine.
    ///   - sources: Every power source on the machine (matched to ports by
    ///     `PowerSource.canonicallyMatches(port:)`).
    public static func chargerSourceCount(
        ports: [AppleHPMInterface],
        sources: [PowerSource]
    ) -> Int {
        ports.filter { port in
            guard port.connectionActive == true else { return false }
            return sources.contains { $0.canonicallyMatches(port: port) }
        }.count
    }

    /// Resolve the charger wattage for a single port.
    ///
    /// - Parameters:
    ///   - portSources: Power sources belonging to this port only.
    ///   - portIsActive: This port's own `connectionActive` state. Every
    ///     branch that returns the system adapter reading is gated on
    ///     machine-wide COUNTS, which carry no port identity, so a sole active
    ///     charger port and some other disconnected port being summarised
    ///     alongside it look identical to them. This is the identity those
    ///     counts lack, and a `.systemAdapterFallback` becomes `.unknown`
    ///     without it (issue #542).
    ///   - activePortCount: Number of ports with `connectionActive == true`
    ///     across the whole machine. Gates the source-less adapter fallback
    ///     (issue #141: a dock delivers power with no per-port source node, so
    ///     the only signal that this port is the charger is that it is the sole
    ///     active port). Kept as the plain active count so that fallback, and
    ///     the #46 protection built on it, are unchanged.
    ///   - chargerSourceCount: Number of active ports that expose a power-
    ///     source node (see `chargerSourceCount(ports:sources:)`). Gates the
    ///     Brick ID divert only. A data/display port no longer inflates it
    ///     (issue #443).
    ///   - adapter: System-wide adapter info from `IOPSCopyExternalPowerAdapterDetails`.
    public static func resolve(
        portSources: [PowerSource],
        portIsActive: Bool,
        activePortCount: Int,
        chargerSourceCount: Int,
        adapter: AdapterInfo?
    ) -> ChargerWattageSource {
        let resolved = resolveIgnoringPortIdentity(
            portSources: portSources,
            activePortCount: activePortCount,
            chargerSourceCount: chargerSourceCount,
            adapter: adapter
        )

        // The system adapter reading is machine-wide. Both branches that
        // return it are gated on counts alone, which carry no port identity,
        // so either can hand it to a port that is not itself connected
        // (issue #542: 67W printed beside an accessory that draws nothing).
        // Guarding the VALUE rather than one branch's condition covers both,
        // and leaves the branches' own conditions untouched. Measured on the
        // customer-probe corpus: 22 ports publish a Brick ID node while
        // reporting `connectionActive == false`, so the node's presence is
        // not evidence a charger is attached to that port.
        if case .systemAdapterFallback = resolved, !portIsActive {
            return .unknown
        }
        return resolved
    }

    /// The branch logic, unchanged since before issue #542. Split out so the
    /// port-identity guard applies to every `.systemAdapterFallback` return
    /// in one place. Callers use `resolve`.
    private static func resolveIgnoringPortIdentity(
        portSources: [PowerSource],
        activePortCount: Int,
        chargerSourceCount: Int,
        adapter: AdapterInfo?
    ) -> ChargerWattageSource {
        let source = PowerSource.preferredChargingSource(in: portSources)

        // "Brick ID" is a low-fidelity analog identifier, not a USB-PD
        // contract. On MagSafe with a third-party PD brick the port only
        // exposes Brick ID (often ~3W) while the real negotiated wattage
        // sits in the system adapter reading. Same situation as the
        // TB-dock case in #141, extended to a Brick ID that does carry a
        // tiny wattage (so the check below would otherwise accept it as
        // authoritative). When Brick ID is the only source, one charger is
        // in play (this port is the sole port with a power-source node), and
        // the system adapter reports a higher wattage, trust the adapter. The
        // single-source guard preserves the #46 multi-charger protection. See
        // issue #154.
        //
        // Accepted trade-off (issue #443 vs #46): a second active port that
        // has no power-source node does NOT block this divert. From the port
        // data alone, a source-less display cable (the everyday #443 case) is
        // indistinguishable from a source-less dock that is itself delivering
        // power (the rare #141-shape twin-charger case). We favour the common
        // case: the divert fires on chargerSourceCount == 1 even when another
        // source-less port is active. The narrow residual (Brick ID MagSafe +
        // a simultaneously-charging source-less dock) can misattribute the
        // adapter reading to MagSafe; it is pinned by a regression test so a
        // future change here is a conscious one.
        //
        // This branch's `.systemAdapterFallback` return is subject to the
        // port-identity guard in `resolve`, the same as the source-less
        // branch below. A Brick ID node persists on a disconnected port, so
        // its presence is not evidence a charger is attached here.
        if let source, source.name == "Brick ID",
           chargerSourceCount == 1,
           let adapterW = adapter?.watts, adapterW > 0 {
            let brickW = Int((Double(source.maxPowerMW) / 1000).rounded())
            if adapterW > brickW {
                return .systemAdapterFallback(watts: adapterW)
            }
        }

        if let source, source.maxPowerMW > 0 {
            let watts = Int((Double(source.maxPowerMW) / 1000).rounded())
            return .portNegotiated(watts: watts)
        }

        // If a USB-PD source exists on this port (even with 0W), PD
        // negotiation owns the wattage. Don't substitute the system
        // adapter, because on a multi-charger Mac the adapter value
        // might belong to a different port. See issue #46.
        let hasUSBPD = portSources.contains { $0.name == "USB-PD" }
        if hasUSBPD { return .unknown }

        // No usable per-port source (either none at all, or a Brick ID at 0W).
        // The charger is delivering power through a path that bypasses per-port
        // PD negotiation (e.g. a Thunderbolt dock, see issue #141). Fall back to
        // the system adapter under two conditions:
        //
        // (a) Only one port is active on the whole machine. A source-less
        //     charger leaves no per-port evidence, so the sole-active-port test
        //     is the only signal that this port is the one the adapter reading
        //     belongs to. This deliberately stays the plain active-port count,
        //     NOT chargerSourceCount: a dock has no source node, so a source
        //     count would be 0 here and the fallback would never fire. If two
        //     ports are active we can't attribute the reading, which also
        //     guards against two docks delivering power on separate chains (#46).
        //
        // (b) The system adapter reports a positive wattage.
        //
        // `resolve` applies a third condition to the value this returns: the
        // port must be active. See the guard there.
        if activePortCount == 1,
           let adapterW = adapter?.watts,
           adapterW > 0 {
            return .systemAdapterFallback(watts: adapterW)
        }

        return .unknown
    }
}
