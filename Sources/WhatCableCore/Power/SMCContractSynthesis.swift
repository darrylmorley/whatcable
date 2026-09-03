import Foundation

/// Builds a per-port charging contract from the SMC, for the machines where
/// macOS publishes one nowhere else.
///
/// THE PROBLEM. M1 Pro, M1 Max and M1 Ultra never publish a USB-C
/// `IOPortFeaturePowerSource` node. That node is where a port's negotiated
/// charging contract normally comes from, so on those machines the Power
/// Monitor's per-port card had nothing to show and spun "waiting for power
/// telemetry" forever while the Mac charged at 100 W (public issue 491). The
/// existing fallback, `PowerSourceSynthesis`, rebuilds the contract from
/// `AppleSmartBattery`'s `PortControllerInfo`, and that needs a PDO list which
/// macOS 14.8.x and 15.7.x do not publish: they ship a reduced 19-key form of
/// that array carrying only interrupt counters and a max-power figure. So on
/// the reporter's exact configuration both routes fail closed.
///
/// THE DATA. The contract is in the SMC all along, on the same `D1..D4`
/// channels the power-out figures use: `DxMP` / `DxMV` / `DxMI`, joined to a
/// physical port by the `DxUI` controller UUID. On the reporter's machine
/// channel D2 reads 100000 mW / 20000 mV / 5000 mA, matching the 100 W / 20 V /
/// 5 A in his own pasted output.
///
/// WHY IT IS TRUSTED. Measured across the customer-probe corpus:
///
/// - the `DxUI` join lands on a known HPM controller on 464 of 464 machines
///   carrying both probes, including 190 M1 and M2 machines, which is exactly
///   the silicon that needs it
/// - `DxMV x DxMI = DxMP` on 455 of 455 checks
/// - `DxMP` equals a live `PortControllerMaxPower` on 418 of 419 machines
/// - against the node, where both exist: 185 shared USB-C ports, 182 identical
///   on watts, volts and amps
///
/// WHERE IT RANKS. Below a real node, above `PowerSourceSynthesis`. The node is
/// macOS's own answer and is never overridden. Synthesis sits underneath
/// because on M1 Pro/Max/Ultra the SMC answers on 23 machines where synthesis
/// cannot, and where both answer they agree on the port every time (19 of 19),
/// with the SMC correct in all 3 value disagreements. Synthesis stays rather
/// than being replaced: it still answers on 4 machines where the SMC does not.
///
/// WHAT IT CANNOT DO. It never reports MagSafe: 105 MagSafe contracts come from
/// the node and 0 from the SMC. And desktops publish none of these keys at all,
/// on all 83 desktops in the corpus with the relevant probe.
public enum SMCContractSynthesis {

    /// A single switch. Turning this off returns every affected port to the
    /// no-data state it had before this existed.
    ///
    /// This is the one part of the power-slice work that can turn a
    /// fail-closed bug into a fail-open one: everything else either showed a
    /// spinner or showed nothing, whereas this puts a number on a card. If a
    /// machine in the wild disagrees with it, the recovery is flipping this,
    /// not unpicking a merge.
    ///
    /// Mutable global state, which is a hazard, so `synthesizedSource` takes it
    /// as a parameter defaulting to this rather than reading it directly. That
    /// is not theoretical tidiness: the first version read the global, and the
    /// test that flips it off raced every other test in its own suite, because
    /// swift-testing runs them in parallel. The failure looked like a logic bug
    /// in gate 5 and was not.
    public static var isEnabled = true

    /// The label the SMC uses for a channel that is SOURCING power to a
    /// peripheral rather than receiving it. A contract on such a channel is
    /// the Mac's own output and must never be shown as an incoming charge.
    private static let outgoingLabel = "usb host"

    /// Stable id prefix, so a synthesized source is recognisable and can never
    /// collide with a real IOKit registry entry id.
    private static let idSentinel: UInt64 = 0xFFFE_FFFF_0000_0000

    /// Build a contract for one port, or nil when no gate passes.
    ///
    /// - Parameters:
    ///   - contracts: this tick's SMC contract channels.
    ///   - uuidMap: controller UUID to port key, the same map the per-port
    ///     power path uses.
    ///   - ports: the live HPM port enumeration.
    ///   - realSources: every `IOPortFeaturePowerSource` macOS published,
    ///     synthesized entries excluded by the caller.
    ///   - externalConnected: whether the Mac reports external power.
    public static func synthesizedSource(
        contracts: [SMCPortContract],
        uuidMap: [String: String],
        ports: [AppleHPMInterface],
        realSources: [PowerSource],
        externalConnected: Bool,
        enabled: Bool = isEnabled
    ) -> PowerSource? {
        guard enabled else { return nil }

        // GATE 1: nothing is charging, so there is no contract to describe.
        guard externalConnected else { return nil }

        // GATE 5, applied early because it is the cheapest and the most
        // important. If ANY port already holds a winning contract, macOS has
        // answered and this must stay quiet.
        //
        // Cross-port on purpose, and deliberately not
        // `PowerSource.hasLiveChargingContract(in:)`, which inspects only the
        // first source named "USB-PD" in the array. That is right for its
        // callers, which pass an already-per-port-filtered list, and wrong
        // here, where `realSources` spans every port.
        //
        // Without this, an M1 Pro charging on MagSafe with a dock attached
        // would show the dock's contract as though the Mac were charging from
        // it. With it, that port keeps its current no-data state, which is no
        // worse than today.
        let anyRealContract = realSources.contains { ($0.winning?.maxPowerMW ?? 0) > 0 }
        guard !anyRealContract else { return nil }

        let candidates = contracts.compactMap { contract -> (contract: SMCPortContract, port: AppleHPMInterface)? in
            // GATE 2: the channel must resolve to a physical port through the
            // UUID join. No guessing by channel index: D2 is not port 2.
            guard let portKey = uuidMap[contract.uuid] else { return nil }

            // GATE 3: a plausible charging contract. Power must be positive and
            // the voltage at least the 5 V floor every USB-C contract starts
            // at, which rejects a partially-populated channel.
            guard contract.powerMW > 0, contract.voltageMV >= 5_000 else { return nil }

            // GATE 4: not the Mac's own output. The label is empty on plenty of
            // genuine chargers so its absence proves nothing, but when it does
            // say "usb host" it is describing power going the other way.
            guard !contract.label.lowercased().contains(outgoingLabel) else { return nil }

            // The port must exist, be USB-C, and be connected. MagSafe is
            // excluded outright: the SMC has never reported a MagSafe contract
            // in the corpus, so a MagSafe match here would be a join error
            // rather than a discovery.
            guard let port = ports.first(where: { $0.portKey == portKey }),
                  let identity = port.identity,
                  identity.typeCode == PortIdentity.usbCTypeCode,
                  port.connectionActive == true
            else { return nil }

            // And the port must not already have a real source of its own, even
            // one without a winning contract: macOS is describing that port and
            // we are not going to talk over it.
            guard !realSources.contains(where: { $0.canonicallyMatches(port: port) }) else { return nil }

            return (contract, port)
        }

        // Exactly one, or stay silent. Two candidates means the join is
        // ambiguous, and naming the wrong port is worse than naming none: that
        // is the misattribution class this whole slice exists to close.
        guard candidates.count == 1, let winner = candidates.first else { return nil }

        // No supply kind. The SMC channel keys (DxMV / DxMI / DxMP) carry
        // volts, amps and watts and nothing about the PDO the contract came
        // from, so `.unknown` is the honest answer and the default. Stated
        // explicitly rather than left to the default so the next reader knows
        // it was considered: downstream, `.unknown` gets the weaker phase-1
        // voltage-tier proxy instead of a real supply-type gate.
        let option = PowerOption(
            voltageMV: winner.contract.voltageMV,
            maxCurrentMA: winner.contract.currentMA,
            maxPowerMW: winner.contract.powerMW,
            supplyKind: .unknown
        )
        return PowerSource(
            id: idSentinel | UInt64(winner.contract.channel),
            name: "USB-PD",
            parentPortType: winner.port.identity?.typeCode ?? PortIdentity.usbCTypeCode,
            parentPortNumber: winner.port.portNumber ?? 0,
            options: [option],
            winning: option,
            hpmControllerUUID: winner.port.hpmControllerUUID,
            isSynthesized: true
        )
    }
}
