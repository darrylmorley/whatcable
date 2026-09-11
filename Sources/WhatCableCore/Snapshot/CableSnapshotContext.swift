import Foundation

/// One immutable, pre-joined view of a CableSnapshot: the per-port filtering,
/// charger-source resolution, cross-port charging state, and device
/// attribution that every renderer needs before it can construct
/// PortSummary / ChargingDiagnostic / DataLinkDiagnostic correctly.
///
/// JSONFormatter, TextFormatter and DashboardCommand all consume this
/// builder. It is the only per-port assembly in the codebase;
/// do not reintroduce a private copy in a renderer.
///
/// Guarantees:
/// - `portContexts` preserves `snapshot.ports` order, one entry per port.
/// - Every filtered array preserves the input array's order.
/// - `portCIO` is the FIRST canonical match (mirrors all three copies).
/// - `attributedDevices` is the ID-deduplicated union of `matchedDevices`
///   then `structurallyScopedTunnelledDevices`, first occurrence wins, which
///   is exactly `TunnelledDeviceGrouping.attributedDevices(for:in:thunderboltSwitches:)`.
///
/// Deliberately NOT here (formatter concerns, or policy settled by the follow-up migration):
/// showRaw, switch index maps, dashboard sort order, DTOs, unmatched-USB
/// grouping (`TunnelledDeviceGrouping.group`). E-marker selection IS here
/// now, as `cableEmarker`; `portIdentities` is still exposed unfiltered
/// for consumers that need the whole set.
///
/// Not Sendable: CableSnapshot itself is not Sendable yet. No @MainActor.
public struct CableSnapshotContext {
    public struct PortContext {
        public let port: AppleHPMInterface
        /// Power sources canonically matched to this port, input order kept.
        public let portSources: [PowerSource]
        /// PD identities (SOP / SOP' / SOP'') canonically matched to this
        /// port. No endpoint selection policy is applied here.
        public let portIdentities: [USBPDSOP]
        /// The cable e-marker for this port: prefer a SOP' / SOP'' identity
        /// that actually carries VDOs, falling back to the first SOP' /
        /// SOP'' when none does.
        ///
        /// This is the ONE selection policy for the three renderer surfaces
        /// that read this field: JSONFormatter's `cable` / `device` / trust
        /// output, TextFormatter's display verdict and trust block, and
        /// DashboardCommand's `cableIdentity`. It does NOT reach every
        /// consumer. `ChargingDiagnostic` (`ChargingDiagnostic.swift:89-91`
        /// and `:129-131`) and `DataLinkDiagnostic`
        /// (`DataLinkDiagnostic.swift:259-260`) are still built from
        /// `portIdentities` below and each runs its own first-match
        /// selection internally, so a bare SOP' ahead of a populated SOP''
        /// can still produce a charging or data-link verdict that
        /// disagrees with the cable data shown elsewhere on the same card.
        /// That is pre-existing on `main`, unchanged by this migration, and
        /// out of scope here. `PortSummary` also keeps its own private
        /// `cableEmarker` copy on purpose; its internals are out of scope
        /// too.
        ///
        /// The old first-match code COULD be shadowed by a bare SOP'
        /// arriving ahead of a populated SOP'', but no machine in the
        /// customer-probe corpus (1394 machines, 22830 raw probe files) has
        /// ever presented that shape: every port carrying a cable identity
        /// has exactly one, always a SOP'. The new policy is the safer one
        /// regardless of that absence of evidence. It is also incomplete:
        /// when BOTH a SOP' and a SOP'' carry VDOs, selection still falls
        /// back to array order between them, so the order-independence
        /// guarantee holds only for the one-populated case.
        public let cableEmarker: USBPDSOP?
        /// The port partner's own identity (SOP), first canonical match.
        public let partnerIdentity: USBPDSOP?
        public let portUSB3: [USB3Transport]
        public let portTRM: [TRMTransport]
        /// First canonical CIO match, mirroring the formatters.
        public let portCIO: CIOCableCapability?
        /// First canonical Apple accessory identity match for this port.
        /// Nil covers two different things: no Apple accessory attached, and
        /// an Apple accessory whose UVDM node publishes no identity fields
        /// (8 nodes in the probe corpus). Never render nil as an absence.
        public let portAccessory: AppleAccessoryIdentity?
        public let portDisplayPorts: [IOPortTransportStateDisplayPort]
        /// Native-bus matches (`AppleHPMInterface.matchingDevices`). Feeds
        /// PortSummary / DataLinkDiagnostic, whose speed corroboration is
        /// native-bus-local by design.
        public let matchedDevices: [USBDevice]
        /// Tunnelled devices structurally scoped to this port by apciecN
        /// root name.
        public let structurallyScopedTunnelledDevices: [USBDevice]
        /// ID-deduplicated union, matched-first ordering. Feeds device lists.
        public let attributedDevices: [USBDevice]
        public let chargerWattageSource: ChargerWattageSource
        /// True when a DIFFERENT port holds a live charging contract (#264).
        public let anotherPortActivelyCharging: Bool
    }

    public let adapter: AdapterInfo?
    public let batteryFullyCharged: Bool?
    public let batteryIsCharging: Bool?
    public let federatedIdentities: [FederatedIdentity]
    public let thunderboltSwitches: [IOThunderboltSwitch]
    public let isDesktopMac: Bool
    /// One entry per `snapshot.ports` element, same order.
    public let portContexts: [PortContext]

    public init(snapshot: CableSnapshot) {
        let ports = snapshot.ports
        let sources = snapshot.powerSources
        // Machine-wide intermediates. Kept private on purpose: consumers get
        // the resolved per-port answers, not the raw counts.
        let activePortCount = ports.filter { $0.connectionActive == true }.count
        let chargerSourceCount = ChargerWattageSource.chargerSourceCount(
            ports: ports, sources: sources)
        // Port keys with a live negotiated contract (#264). Deliberately
        // ungated on adapter/battery: this only feeds
        // anotherPortActivelyCharging, and ChargingDiagnostic applies the
        // system-power gate before acting on it.
        let chargingPortKeys = Set(ports.compactMap { port -> String? in
            let portSources = sources.filter { $0.canonicallyMatches(port: port) }
            return PowerSource.hasLiveChargingContract(in: portSources) ? port.portKey : nil
        })
        self.portContexts = ports.map { port in
            let portSources = sources.filter { $0.canonicallyMatches(port: port) }
            let matched = port.matchingDevices(from: snapshot.usbDevices)
            let scoped = TunnelledDeviceGrouping.structurallyScopedTunnelledDevices(
                for: port, in: snapshot.usbDevices,
                thunderboltSwitches: snapshot.thunderboltSwitches)
            var seen = Set<UInt64>()
            var union: [USBDevice] = []
            for device in matched + scoped where seen.insert(device.id).inserted {
                union.append(device)
            }
            let portIdentities = snapshot.identities.filter { $0.canonicallyMatches(port: port) }
            let cableEmarker = portIdentities.first {
                ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime) && !$0.vdos.isEmpty
            } ?? portIdentities.first {
                $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
            }
            return PortContext(
                port: port,
                portSources: portSources,
                portIdentities: portIdentities,
                cableEmarker: cableEmarker,
                partnerIdentity: portIdentities.first { $0.endpoint == .sop },
                portUSB3: snapshot.usb3Transports.filter { $0.canonicallyMatches(port: port) },
                portTRM: snapshot.trmTransports.filter { $0.canonicallyMatches(port: port) },
                portCIO: snapshot.cioCapabilities.first { $0.canonicallyMatches(port: port) },
                portAccessory: snapshot.accessoryIdentities.first { $0.canonicallyMatches(port: port) },
                portDisplayPorts: snapshot.displayPorts.filter { $0.canonicallyMatches(port: port) },
                matchedDevices: matched,
                structurallyScopedTunnelledDevices: scoped,
                attributedDevices: union,
                chargerWattageSource: ChargerWattageSource.resolve(
                    portSources: portSources,
                    portIsActive: port.connectionActive == true,
                    activePortCount: activePortCount,
                    chargerSourceCount: chargerSourceCount,
                    adapter: snapshot.adapter),
                anotherPortActivelyCharging: port.portKey.map { key in
                    chargingPortKeys.contains { $0 != key }
                } ?? false
            )
        }
        self.adapter = snapshot.adapter
        self.batteryFullyCharged = snapshot.batteryFullyCharged
        self.batteryIsCharging = snapshot.batteryIsCharging
        self.federatedIdentities = snapshot.federatedIdentities
        self.thunderboltSwitches = snapshot.thunderboltSwitches
        self.isDesktopMac = snapshot.isDesktopMac
    }
}
