import Foundation

/// Builds a `PowerSource` from `AppleSmartBattery`'s `PortControllerInfo` array
/// when macOS never creates the per-port `IOPortFeaturePowerSource` node that
/// `PowerSourceWatcher` normally reads.
///
/// Background (issue #401): on M1 Pro / M1 Max / M1 Ultra, macOS does not
/// publish that node for USB-C ports at all (corpus-verified: 0 of 61
/// machines, including about 10 caught actively charging over USB-C). The
/// same negotiated-contract data macOS would otherwise expose there still
/// exists inside `AppleSmartBattery`'s `PortControllerInfo` array (the PDO
/// list plus the negotiated max wattage). This enum recovers it so the rest
/// of the app, which only ever reads `PowerSource` values, lights up without
/// having to special-case these machines anywhere else.
///
/// This is pure `WhatCableCore`: no IOKit reads happen here. The Darwin
/// backend (`PowerSourceWatcher`) does the IOKit reads, converts them into
/// the inputs below, and only calls this when the cheap gates in
/// `refresh()` already suggest synthesis might be needed.
///
/// Every gate below fails closed (returns `nil`) rather than guessing,
/// because attributing a charging contract to the wrong port is worse than
/// showing nothing.
public enum PowerSourceSynthesis {

    /// One `PortControllerInfo` array entry, pre-parsed by the Darwin backend
    /// from the raw `AppleSmartBattery` property dictionary.
    public struct ContractEntry {
        /// Position of this entry in the `PortControllerInfo` array. Used
        /// only for the positional attribution rung and to build the
        /// synthesized source's stable id.
        public let index: Int
        /// `PortControllerPortPDO`, already trimmed to `PortControllerNPDOs`
        /// entries (no trailing zero padding). Order matches the order the
        /// port controller transmitted the PDOs in, which is what the RDO's
        /// PDO-position field indexes into.
        public let rawPDOs: [UInt32]
        /// `PortControllerActiveContractRdo`. Corpus-verified to read 0 on
        /// M1 Pro/Max/Ultra even while genuinely charging, so this is not a
        /// reliable "is this entry live" signal on these machines; that
        /// signal is `maxPowerMW > 0` instead.
        public let activeRdo: UInt32
        /// `PortControllerMaxPower`, in milliwatts. The live-contract signal
        /// on these machines: exactly one entry has a positive value while a
        /// charger is negotiated.
        public let maxPowerMW: Int

        public init(index: Int, rawPDOs: [UInt32], activeRdo: UInt32, maxPowerMW: Int) {
            self.index = index
            self.rawPDOs = rawPDOs
            self.activeRdo = activeRdo
            self.maxPowerMW = maxPowerMW
        }
    }

    /// Sentinel high bits for synthesized source ids, so they can never
    /// collide with a real `IORegistryEntryID` (those are dense small
    /// integers in practice) and stay stable across refreshes for the same
    /// `PortControllerInfo` index, which keeps the equality guard in
    /// `PowerSourceWatcher.refresh()` from flapping (see issue #227).
    private static let idSentinel: UInt64 = 0xFFFF_FFFF_0000_0000

    /// Attempt to synthesize a `PowerSource` for the one port that has a live
    /// charging contract in `PortControllerInfo` but no real
    /// `IOPortFeaturePowerSource` node covering it.
    ///
    /// - Parameters:
    ///   - realSources: The power sources macOS actually published this tick.
    ///     If any of these already carry a live contract, synthesis is a
    ///     no-op: MagSafe (which does publish the node on these machines)
    ///     stays authoritative.
    ///   - ports: Every physical port this session knows about.
    ///   - identities: SOP/SOP'/SOP'' identities, used only for the
    ///     partner-kind attribution rung.
    ///   - entries: Parsed `PortControllerInfo` entries.
    ///   - positionalPortKeys: Port keys in the same HPM traversal order
    ///     Apple uses to build `PortControllerInfo`. Same assumption
    ///     `PortDiagnosticsWatcher.portKeyMap` already ships with.
    ///   - externalConnected: `AppleSmartBattery`'s `ExternalConnected`. No
    ///     charger, nothing to synthesize.
    /// - Returns: One synthesized `PowerSource`, or `nil` when any gate
    ///   fails or attribution can't resolve to exactly one valid port.
    public static func synthesizedSource(
        realSources: [PowerSource],
        ports: [AppleHPMInterface],
        identities: [USBPDSOP],
        entries: [ContractEntry],
        positionalPortKeys: [String],
        externalConnected: Bool
    ) -> PowerSource? {
        // Gate 1: nothing to charge from.
        guard externalConnected else { return nil }

        // Gate 2: a real source already has a live contract (e.g. MagSafe,
        // which does publish the node on these machines). Never override it.
        //
        // Deliberately NOT `PowerSource.hasLiveChargingContract(in:)`: that
        // helper calls `preferredChargingSource`, which returns the FIRST
        // source named "USB-PD" in the array and checks only that one. Every
        // existing caller of it passes an array already filtered to one
        // port, so "first" is unambiguous there. Here `realSources` spans
        // every port on the machine, and a corpus replay (m2_macos26.2,
        // m2_macos27.0) showed the literal machine-wide check missing a live
        // MagSafe contract because an unrelated, idle USB-C port's "USB-PD"
        // source (no winning contract) happened to sort first. Checking
        // every source directly is what "no real source ANYWHERE has a live
        // contract" actually requires.
        let anyRealSourceHasLiveContract = realSources.contains { source in
            guard let winning = source.winning else { return false }
            return winning.maxPowerMW > 0
        }
        guard !anyRealSourceHasLiveContract else { return nil }

        // Gate 2b: a real source parented to a USB-C port exists anywhere on
        // the machine, even without a winning contract yet. That is direct
        // evidence macOS's node publication works for USB-C here, so a
        // missing winning means mid-negotiation or idle, not the #401
        // phenomenon (which is macOS never creating the node at all).
        // Synthesis is only for machines that publish NO USB-C node
        // whatsoever. Without this gate, a port that's genuinely charging
        // but hasn't finished negotiating (real node, no winning yet) gets
        // rejected by the positional rung for being "covered," and a later
        // rung can then misattribute its own PortControllerInfo contract to
        // a different active, uncovered port (e.g. a dock). MagSafe-parented
        // real sources deliberately do NOT trip this gate: M1 Pro/Max
        // publish MagSafe nodes while the USB-C side stays bare, and a live
        // MagSafe contract is already caught by gate 2 above.
        guard !realSources.contains(where: { $0.parentPortType == 2 }) else { return nil }

        // Gate 3: exactly one entry with a live contract. macOS charges from
        // one port at a time, so zero means nothing to attribute and two or
        // more means the data can't be trusted.
        let liveEntries = entries.filter { $0.maxPowerMW > 0 }
        guard liveEntries.count == 1, let liveEntry = liveEntries.first else { return nil }

        // Gate 4: the live entry needs an actual PDO list to build options
        // and a winning contract from.
        guard !liveEntry.rawPDOs.isEmpty else { return nil }

        // Decode every raw PDO in its original transmitted order. This order
        // must be preserved (not sorted) because the RDO's PDO-position field
        // (bits 30..28) indexes into it.
        let decodedInOrder = liveEntry.rawPDOs.map(PDO.decode(rawValue:))
        let positionalOptions = decodedInOrder.map(option(for:))
        let options = positionalOptions.compactMap { $0 }
            .sorted { $0.maxPowerMW > $1.maxPowerMW }
        guard !options.isEmpty else { return nil }

        // Gate 5 (folded into the attribution ladder): resolve to exactly
        // one valid target port.
        guard let targetPort = attributeTarget(
            entry: liveEntry,
            entriesCount: entries.count,
            ports: ports,
            identities: identities,
            realSources: realSources,
            positionalPortKeys: positionalPortKeys
        ), let portKey = targetPort.portKey else { return nil }

        let keyParts = portKey.split(separator: "/")
        guard keyParts.count == 2,
              let parentPortType = Int(keyParts[0]),
              let parentPortNumber = Int(keyParts[1]) else { return nil }

        let winning = winningOption(
            entry: liveEntry,
            positionalOptions: positionalOptions,
            sortedOptions: options
        )

        return PowerSource(
            id: idSentinel | UInt64(liveEntry.index),
            name: "USB-PD",
            parentPortType: parentPortType,
            parentPortNumber: parentPortNumber,
            options: options,
            winning: winning,
            hpmControllerUUID: targetPort.hpmControllerUUID,
            isSynthesized: true
        )
    }

    // MARK: - Attribution ladder

    /// A port is a valid synthesis target when it is explicitly a USB-C
    /// port, currently connected, and not already covered by a real power
    /// source. USB-C is checked positively (`portKey` prefix "2/", the raw
    /// `PortType` value) rather than by excluding MagSafe: A18 Pro
    /// ("MacBook Neo") corpus machines have `Port-Inductive` ports, and
    /// other non-USB-C, non-MagSafe port types may exist that we haven't
    /// seen yet. A "not MagSafe" check would wrongly let synthesis land on
    /// any of those. The coverage check is what stops synthesis from ever
    /// shadowing or duplicating a real reading.
    private static func isValidTarget(_ port: AppleHPMInterface, realSources: [PowerSource]) -> Bool {
        guard port.portKey?.hasPrefix("2/") == true else { return false }
        guard port.connectionActive == true else { return false }
        return realSources.filter { $0.canonicallyMatches(port: port) }.isEmpty
    }

    /// Try each attribution rung in order. The first rung that resolves to
    /// exactly one valid port wins; a rung that resolves to an invalid port
    /// (wrong port type, inactive, already covered by a real source) falls
    /// through to the next rung rather than failing outright.
    private static func attributeTarget(
        entry: ContractEntry,
        entriesCount: Int,
        ports: [AppleHPMInterface],
        identities: [USBPDSOP],
        realSources: [PowerSource],
        positionalPortKeys: [String]
    ) -> AppleHPMInterface? {
        // Rung a: positional. Same traversal-order assumption
        // PortDiagnosticsWatcher.portKeyMap already relies on, but only
        // attempted when entries.count == positionalPortKeys.count.
        // hpmPortKeys() filters to USB-C + MagSafe only, so a machine with a
        // filtered-out port type in the mix (e.g. A18 Pro's Port-Inductive:
        // corpus-real, PortControllerInfo has 1 entry while the machine has
        // 2 USB-C + 1 Inductive port) can have PortControllerInfo slots that
        // don't line up 1:1 with positionalPortKeys. A count mismatch means
        // the key list and the controller array don't describe the same
        // slots, so index alignment can't be trusted; matching cardinality
        // is the cheap consistency signal available without changing
        // hpmPortKeys() itself (shared with shipped Pro diagnostics).
        if entriesCount == positionalPortKeys.count,
           entry.index >= 0, entry.index < positionalPortKeys.count {
            let key = positionalPortKeys[entry.index]
            if let port = ports.first(where: { $0.portKey == key }),
               isValidTarget(port, realSources: realSources) {
                return port
            }
        }

        let validPorts = ports.filter { isValidTarget($0, realSources: realSources) }

        // Rung b: partner-kind anchor. Exactly one active, uncovered USB-C
        // port whose SOP partner identifies itself as a power brick (the
        // DFP-field "Power Brick" product type, not the UFP cable-type
        // field).
        let brickPartnerPorts = validPorts.filter { port in
            identities.contains { identity in
                identity.endpoint == .sop
                    && identity.canonicallyMatches(port: port)
                    && identity.idHeader?.dfpProductType == .powerBrick
            }
        }
        if brickPartnerPorts.count == 1 { return brickPartnerPorts[0] }

        // Rung c: sole-active anchor. Exactly one active, uncovered USB-C
        // port machine-wide, no partner-identity evidence needed.
        if validPorts.count == 1 { return validPorts[0] }

        return nil
    }

    // MARK: - PDO -> PowerOption

    /// Convert one decoded PDO into a `PowerOption`. Fixed and Variable
    /// supplies, and PPS augmented supplies, all expose both a usable
    /// voltage and a max current, so they convert directly. Battery supplies
    /// (max power, no max current) and EPR AVS (PDP, no max current) can't
    /// be expressed as a voltage/current pair, and SPR AVS has no voltage
    /// field at all (only currents at two fixed voltages); those are
    /// skipped rather than guessed.
    private static func option(for pdo: PDO) -> PowerOption? {
        switch pdo {
        case .fixed(let voltage, let maxCurrent):
            guard voltage > 0 else { return nil }
            return PowerOption(
                voltageMV: voltage, maxCurrentMA: maxCurrent, maxPowerMW: voltage * maxCurrent / 1000,
                supplyKind: .fixed
            )
        case .variable(_, let maxVoltage, let maxCurrent):
            guard maxVoltage > 0 else { return nil }
            return PowerOption(
                voltageMV: maxVoltage, maxCurrentMA: maxCurrent, maxPowerMW: maxVoltage * maxCurrent / 1000,
                supplyKind: .nonFixed
            )
        case .pps(_, let maxVoltage, let maxCurrent):
            guard maxVoltage > 0 else { return nil }
            // A PPS option converted at its MAXIMUM voltage is exactly the
            // case the phase-1 tier proxy could not see: a 20 V-max PPS
            // supply produced a 20 000 mV option and sailed through. The kind
            // is what closes that.
            return PowerOption(
                voltageMV: maxVoltage, maxCurrentMA: maxCurrent, maxPowerMW: maxVoltage * maxCurrent / 1000,
                supplyKind: .nonFixed
            )
        case .battery, .eprAvs, .sprAvs:
            return nil
        }
    }

    // MARK: - Winning option derivation

    /// Pick the option that represents the currently negotiated contract.
    ///
    /// When the RDO is non-zero, it names its PDO by position (bits 30..28,
    /// 1-based) into the PDO list as transmitted, so that lookup must use
    /// `positionalOptions` (original order), never the wattage-sorted
    /// `sortedOptions` used for display.
    ///
    /// When the RDO is zero (the normal case on M1 Pro/Max/Ultra, where
    /// `PortControllerActiveContractRdo` reads 0 even while charging),
    /// `maxPowerMW > 0` is itself the live-contract signal, so the winning
    /// option is whichever option's wattage matches it, or failing an exact
    /// match, the largest option that doesn't exceed it.
    private static func winningOption(
        entry: ContractEntry,
        positionalOptions: [PowerOption?],
        sortedOptions: [PowerOption]
    ) -> PowerOption? {
        if entry.activeRdo != 0 {
            let position = Int((entry.activeRdo >> 28) & 0x7)
            let idx = position - 1
            guard idx >= 0, idx < positionalOptions.count else { return nil }
            return positionalOptions[idx]
        }
        if let exact = sortedOptions.first(where: { $0.maxPowerMW == entry.maxPowerMW }) {
            return exact
        }
        return sortedOptions
            .filter { $0.maxPowerMW <= entry.maxPowerMW }
            .max(by: { $0.maxPowerMW < $1.maxPowerMW })
    }
}
