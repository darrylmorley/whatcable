import Foundation

public enum JSONFormatter {
    public static func render(
        ports: [AppleHPMInterface],
        sources: [PowerSource],
        identities: [USBPDSOP],
        showRaw: Bool,
        adapter: AdapterInfo? = nil,
        thunderboltSwitches: [IOThunderboltSwitch] = [],
        isDesktopMac: Bool = false,
        batteryFullyCharged: Bool? = nil,
        batteryIsCharging: Bool? = nil,
        federatedIdentities: [FederatedIdentity] = [],
        usb3Transports: [USB3Transport] = [],
        trmTransports: [TRMTransport] = [],
        cioCapabilities: [CIOCableCapability] = [],
        usbDevices: [USBDevice] = [],
        displayPorts: [IOPortTransportStateDisplayPort] = [],
        builtInDisplayPorts: [BuiltInDisplayPort] = []
    ) throws -> String {
        // One shared per-port assembly for every renderer. The
        // loose parameters above are this function's public signature; they
        // describe a CableSnapshot, so rebuild it and let the Core builder
        // do the canonical joins, the charger-wattage resolution, the
        // cross-port charging flag (#264) and the device attribution.
        let context = CableSnapshotContext(snapshot: CableSnapshot(
            ports: ports,
            powerSources: sources,
            identities: identities,
            usbDevices: usbDevices,
            adapter: adapter,
            thunderboltSwitches: thunderboltSwitches,
            isDesktopMac: isDesktopMac,
            federatedIdentities: federatedIdentities,
            usb3Transports: usb3Transports,
            trmTransports: trmTransports,
            cioCapabilities: cioCapabilities,
            displayPorts: displayPorts,
            batteryFullyCharged: batteryFullyCharged,
            batteryIsCharging: batteryIsCharging
        ))
        // Map each switch's hardware UID to its position in the encoded
        // array. The JSON exposes only these per-snapshot indices; the raw
        // UID is a stable hardware identifier and stays internal (it would
        // otherwise leak into output people paste publicly). Presentation,
        // so it stays here rather than in the builder.
        var switchIndexByUID: [Int64: Int] = [:]
        for (index, sw) in thunderboltSwitches.enumerated() where switchIndexByUID[sw.id] == nil {
            switchIndexByUID[sw.id] = index
        }
        // Devices structurally scoped to a port by apciecN root name join
        // that port's own device tree (via PortDTO's
        // structuralTunnelledDevices) and are subtracted from the flat
        // otherUSBDevices group. The builder already computed the per-port
        // sets; this only unions their ids for the subtraction.
        var structurallyScopedIDs: Set<UInt64> = []
        for portContext in context.portContexts {
            structurallyScopedIDs.formUnion(portContext.structurallyScopedTunnelledDevices.map(\.id))
        }
        // Group port-less USB devices once: those reached over a Thunderbolt
        // tunnel (#274) and those on built-in front-panel ports (#348). Shared
        // by the two closures below so the grouping runs a single time.
        // Grouping stays a formatter concern; the builder is deliberately
        // per-port only.
        let usbGrouping = TunnelledDeviceGrouping.group(
            devices: usbDevices,
            ports: ports,
            thunderboltSwitches: thunderboltSwitches,
            isDesktopMac: isDesktopMac,
            structurallyScoped: structurallyScopedIDs
        )
        let output = Output(
            version: AppInfo.version,
            isDesktopMac: context.isDesktopMac,
            adapter: context.adapter.map { AdapterDTO(adapter: $0) },
            ports: context.portContexts.map { portContext in
                PortDTO(
                    port: portContext.port,
                    sources: portContext.portSources,
                    identities: portContext.portIdentities,
                    thunderboltSwitches: context.thunderboltSwitches,
                    switchIndexByUID: switchIndexByUID,
                    showRaw: showRaw,
                    adapter: context.adapter,
                    federatedIdentities: context.federatedIdentities,
                    usb3Transports: portContext.portUSB3,
                    trmTransports: portContext.portTRM,
                    cioCapability: portContext.portCIO,
                    chargerWattageSource: portContext.chargerWattageSource,
                    batteryFullyCharged: context.batteryFullyCharged,
                    batteryIsCharging: context.batteryIsCharging,
                    usbDevices: portContext.matchedDevices,
                    structuralTunnelledDevices: portContext.structurallyScopedTunnelledDevices,
                    displayPorts: portContext.portDisplayPorts,
                    anotherPortActivelyCharging: portContext.anotherPortActivelyCharging,
                    cableEmarker: portContext.cableEmarker,
                    partnerIdentity: portContext.partnerIdentity
                )
            },
            thunderboltSwitches: thunderboltSwitches.enumerated().map { index, sw in
                IOThunderboltSwitchDTO(sw: sw, index: index, switchIndexByUID: switchIndexByUID)
            },
            builtInDisplayPorts: builtInDisplayPorts.isEmpty ? nil : builtInDisplayPorts.map { hdmiPort in
                BuiltInDisplayPortDTO(
                    name: hdmiPort.serviceName,
                    type: hdmiPort.portType,
                    portNumber: hdmiPort.portNumber,
                    displays: hdmiPort.displays.compactMap { dp in
                        guard let diag = DisplayDiagnostic(dp: dp, cable: nil) else { return nil }
                        return DisplayDTO(diagnostic: diag)
                    }
                )
            },
            otherUSBDevices: {
                guard !usbGrouping.devices.isEmpty else { return nil }
                let tree = USBDeviceNode.buildTree(from: usbGrouping.devices)
                return OtherUSBDevicesDTO(
                    behindPort: usbGrouping.hostPortServiceName,
                    devices: tree.map { USBDeviceDTO(node: $0) }
                )
            }(),
            builtInUSBDevices: {
                // internalHubDevices is already desktop-gated by group() above,
                // so it is empty on a laptop and this block is omitted there.
                guard !usbGrouping.internalHubDevices.isEmpty else { return nil }
                let tree = USBDeviceNode.buildTree(from: usbGrouping.internalHubDevices)
                return BuiltInUSBDevicesDTO(
                    devices: tree.map { USBDeviceDTO(node: $0) }
                )
            }()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct Output: Codable {
    let version: String
    let isDesktopMac: Bool
    /// System-wide charger info from `IOPSCopyExternalPowerAdapterDetails`.
    /// Nil when no adapter is connected (running on battery).
    let adapter: AdapterDTO?
    let ports: [PortDTO]
    /// Top-level Thunderbolt fabric. Always present (empty array on
    /// machines without a TB controller, or before the watcher has data).
    /// Per-port `thunderboltSwitchIndex` references this graph by array
    /// index rather than nesting the whole switch under each port.
    let thunderboltSwitches: [IOThunderboltSwitchDTO]
    /// Native video output sockets (today: the built-in HDMI port on
    /// Apple Silicon MacBook Pros, Mac mini Pro, Mac Studio). These aren't
    /// USB-C, have no PD / transports / e-marker / Thunderbolt fabric, and
    /// so don't appear in `ports`. Issue #352. Omitted when nothing is
    /// plugged into them.
    let builtInDisplayPorts: [BuiltInDisplayPortDTO]?
    /// USB devices reached over a Thunderbolt tunnel (behind a dock or display),
    /// which match no physical port (issue #274). Omitted when there are none.
    let otherUSBDevices: OtherUSBDevicesDTO?
    /// USB devices on built-in plain-USB ports behind the Mac's internal hub
    /// (front USB-C / USB-A ports on Mac mini, Studio, Pro). These have no
    /// port-controller silicon, so no cable / PD / Thunderbolt data is
    /// available for them (issue #348). Omitted when there are none.
    let builtInUSBDevices: BuiltInUSBDevicesDTO?
}

private struct BuiltInDisplayPortDTO: Codable {
    /// Synthesized service name, mirroring `Port-USB-C@N` / `Port-MagSafe 3@N`.
    let name: String
    /// "HDMI" today. Future-proofed as a string in case other native video
    /// sockets ship.
    let type: String
    /// 1-based socket index on the host, matching Apple's "HDMI port 1" labelling.
    let portNumber: Int
    /// Display verdict(s) for monitor(s) attached to this socket. Same DTO
    /// shape as `PortDTO.displays`, so existing JSON consumers can reuse
    /// their parsing.
    let displays: [DisplayDTO]
}

/// Devices behind a Thunderbolt dock or display. `behindPort` is the
/// `name` of the one Thunderbolt port they sit behind; it is a nil optional
/// (so the encoder omits the key entirely) when two or more Thunderbolt
/// devices are connected and the attribution is ambiguous. So: key present =
/// attributed to that port; key absent = flat/ambiguous.
private struct OtherUSBDevicesDTO: Codable {
    let behindPort: String?
    let devices: [USBDeviceDTO]
}

/// Devices plugged into the Mac's built-in plain-USB ports (front-panel
/// ports on desktops, hanging off the internal Apple USB hub). No
/// port-controller silicon backs these ports, so no cable, PD, or
/// Thunderbolt data is available; the section lists the devices themselves
/// only. Issue #348.
private struct BuiltInUSBDevicesDTO: Codable {
    let devices: [USBDeviceDTO]
}

/// One attributed section of a port card. `source` is the stable machine key
/// (`measured`, `emarker`, `charger`, `database`); `header` is the localised
/// human heading, so a script should key off `source`, never the header text.
private struct BulletGroupDTO: Codable {
    let source: String
    let header: String
    /// The group's state when it has nothing to list, e.g. the e-marker was
    /// present but not read on this connection.
    ///
    /// The key is OMITTED, not null, when the group simply carries its lines:
    /// Swift's synthesised Codable drops nil optionals. Consumers must treat
    /// absent as "no state to report".
    let state: String?
    let lines: [String]
}

private struct PortDTO: Codable {
    let name: String
    let type: String?
    let className: String
    let connectionActive: Bool
    let pdCapable: Bool
    let status: String
    let headline: String
    let subtitle: String
    /// Every group's lines, flattened. Kept for schema stability: scripts have
    /// consumed this key since long before the lines were attributed to a
    /// source. Prefer `bulletGroups`, which says where each line came from.
    let bullets: [String]
    /// The same lines, grouped by source, plus each group's read state.
    /// `bullets` cannot carry a subtitle, so a port whose e-marker was not
    /// read explains itself only here.
    let bulletGroups: [BulletGroupDTO]
    let transports: TransportsDTO
    let powerSources: [PowerSourceDTO]
    let cable: CableDTO?
    let device: DeviceDTO?
    /// Cable trust verdict: a single tier (green / amber / red) over the
    /// e-marker's consistency plus whether the live link confirmed the cable
    /// performs as claimed. Nil when there's no cable e-marker to assess.
    let trust: TrustDTO?
    let charging: ChargingDTO?
    /// Data-speed "weakest link" verdict: which of cable / Mac port /
    /// device limits the negotiated data rate. Nil when there's no data
    /// link to judge on this port.
    let dataLink: DataLinkDTO?
    /// Display "weakest link" verdicts: whether each DisplayPort link carries
    /// its monitor's top mode. One entry per active display on this port; a
    /// dock can drive several monitors through a single port (issue #271). Nil
    /// when there's no active display link on this port.
    let displays: [DisplayDTO]?
    /// Whether a USB Billboard device is enumerated on this port. Raw signal,
    /// no diagnosis attached (a Billboard device is often benign). Consumers
    /// pair it with `displays` to spot a probable failed Alt-Mode handshake.
    let billboardDevicePresent: Bool
    /// Index into the top-level `thunderboltSwitches` array of the host
    /// root switch this port maps to, if any. Resolved via the
    /// `Socket ID` <-> `@N` join key. A per-snapshot index, not the
    /// hardware UID: the UID is a stable machine identifier and is kept
    /// internal. nil for ports that aren't TB-protocol or for which the
    /// watcher hasn't found a match.
    let thunderboltSwitchIndex: Int?
    /// Per-transport TRM state for this port. Nil when no TRM data is
    /// available (nothing connected, or TRM not active on this port).
    let trm: [TRMTransportDTO]?
    /// CIO cable capability from the Thunderbolt transport controller.
    /// Independent of the USB-PD e-marker. Nil when no TB link is active.
    let cio: CIOCableCapabilityDTO?
    let devices: [USBDeviceDTO]?
    let rawProperties: [String: String]?

    init(
        port: AppleHPMInterface,
        sources: [PowerSource],
        identities: [USBPDSOP],
        thunderboltSwitches: [IOThunderboltSwitch],
        switchIndexByUID: [Int64: Int] = [:],
        showRaw: Bool,
        adapter: AdapterInfo?,
        federatedIdentities: [FederatedIdentity] = [],
        usb3Transports: [USB3Transport] = [],
        trmTransports: [TRMTransport] = [],
        cioCapability: CIOCableCapability? = nil,
        chargerWattageSource: ChargerWattageSource = .unknown,
        batteryFullyCharged: Bool? = nil,
        batteryIsCharging: Bool? = nil,
        usbDevices: [USBDevice] = [],
        // Tunnelled devices structurally scoped to this port by apciecN root
        // name. Joined into the per-port device tree below; kept OUT of the
        // summary/diagnostic/speed inputs, which are native-bus-local by
        // design (a device on a dock's own PCIe xHCI negotiates its speed
        // with that controller, not with this port's native link).
        structuralTunnelledDevices: [USBDevice] = [],
        displayPorts: [IOPortTransportStateDisplayPort] = [],
        anotherPortActivelyCharging: Bool = false,
        // The one shared e-marker selection. Previously computed
        // here; the builder owns the policy now so the text and dashboard
        // surfaces cannot drift from it again.
        cableEmarker: USBPDSOP?,
        partnerIdentity: USBPDSOP?
    ) {
        self.name = port.portDescription ?? port.serviceName
        self.type = port.portTypeDescription
        self.className = port.className
        self.connectionActive = port.connectionActive ?? false
        self.pdCapable = port.transportsSupported.contains("CC")

        let summary = PortSummary(
            port: port,
            sources: sources,
            identities: identities,
            devices: usbDevices,
            thunderboltSwitches: thunderboltSwitches,
            federatedIdentities: federatedIdentities,
            usb3Transports: usb3Transports,
            trmTransports: trmTransports,
            cioCapability: cioCapability,
            chargerWattageSource: chargerWattageSource,
            batteryFullyCharged: batteryFullyCharged,
            batteryIsCharging: batteryIsCharging,
            adapter: adapter
        )
        self.status = String(describing: summary.status)
        self.headline = summary.headline
        self.subtitle = summary.subtitle
        self.bullets = summary.bullets
        self.bulletGroups = summary.groups.map {
            BulletGroupDTO(source: $0.kind.rawValue, header: $0.header, state: $0.subtitle, lines: $0.lines)
        }

        // Resolve the host-root switch via Socket ID matching, then encode
        // its array index (never the raw hardware UID).
        if let socketID = ThunderboltTopology.socketID(for: port),
           let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches) {
            self.thunderboltSwitchIndex = switchIndexByUID[root.id]
        } else {
            self.thunderboltSwitchIndex = nil
        }

        // `TransportsActive` is the sole authority for "USB3 is live"
        // (issue #187). The HPM controller can leave a stale
        // `IOPortTransportStateUSB3` service registered, assert
        // `IOAccessoryUSBSuperSpeedActive=1`, and even keep matched
        // `USBDevice` entries reporting SuperSpeed when the negotiated
        // link is only USB 2.0. Gate the whole `usb3Speed` resolution on
        // TransportsActive, not just the transport-derived fallback.
        //
        // issue #181: also require corroboration (an enumerated
        // SuperSpeed device, or a TRM-restricted selected transport) before
        // emitting a speed. Without this, a `--json` snapshot taken mid
        // cable-orientation handshake on a charger-only cable prints a
        // usb3Speed that PD negotiation is about to withdraw. See
        // USB3SpeedCorroboration and planning/dar-50-usb3-speed-corroboration.md.
        let selectedUSB3Transport = USB3SpeedCorroboration.selectedTransport(for: port, in: usb3Transports)
        let usb3Speed: String?
        if port.transportsActive.contains("USB3"),
           USB3SpeedCorroboration.isCorroborated(selected: selectedUSB3Transport, devices: usbDevices) {
            // Selection order mirrors PortSummary: root device first,
            // then HPM transport, then controller-port-name fallback for
            // Apple Silicon front USB-C ports whose internal virtual root
            // hides the actual root device.
            let rootDeviceSpeed = USBDevice.rootSuperSpeed(in: usbDevices)?.usb3SpeedLabel
            let portMatchedSpeed = USBDevice.portMatchedSuperSpeed(in: usbDevices)?.usb3SpeedLabel
            usb3Speed = rootDeviceSpeed ?? selectedUSB3Transport?.speedLabel ?? portMatchedSpeed
        } else {
            usb3Speed = nil
        }
        self.transports = TransportsDTO(
            supported: port.transportsSupported,
            active: port.transportsActive,
            provisioned: port.transportsProvisioned,
            displayPortLanes: port.dpLaneConfig?.label,
            usb3Speed: usb3Speed
        )

        self.powerSources = port.connectionActive != false ? sources.map { PowerSourceDTO(source: $0) } : []

        self.cable = cableEmarker.map { CableDTO(identity: $0, partner: partnerIdentity, port: port) }

        self.device = partnerIdentity.map { DeviceDTO(identity: $0) }

        self.charging = ChargingDiagnostic(port: port, sources: sources, identities: identities, adapter: adapter, wattageSource: chargerWattageSource, batteryFullyCharged: batteryFullyCharged, batteryIsCharging: batteryIsCharging, anotherPortActivelyCharging: anotherPortActivelyCharging, federatedIdentities: federatedIdentities)
            .map { ChargingDTO(diagnostic: $0) }

        let dataLinkDiag = DataLinkDiagnostic(
            port: port,
            identities: identities,
            devices: usbDevices,
            usb3Transports: usb3Transports,
            cio: cioCapability,
            thunderboltSwitches: thunderboltSwitches
        )
        self.dataLink = dataLinkDiag.map { DataLinkDTO(diagnostic: $0) }

        // Cable trust tier: combine the static e-marker report with the
        // behavioural signals (the live data link and the negotiated PD
        // contract). Only when there's a cable e-marker to assess. The
        // negotiated wattage is the highest winning contract across sources,
        // matching how ChargingDiagnostic reads the live contract.
        let negotiatedWatts: Int? = sources
            .compactMap { $0.winning.map { Int((Double($0.maxPowerMW) / 1000).rounded()) } }
            .max()
        self.trust = cableEmarker.map { id in
            TrustDTO(trust: CableTrust(
                report: CableTrustReport(identity: id, partner: partnerIdentity),
                vendorRegistered: VendorDB.isRegistered(id.vendorID),
                dataLink: dataLinkDiag,
                negotiatedWatts: negotiatedWatts,
                ratedWatts: id.cableVDO?.maxWatts
            ))
        }

        let displayDTOs = displayPorts
            .compactMap { DisplayDiagnostic(dp: $0, cable: cableEmarker, port: port) }
            .map { DisplayDTO(diagnostic: $0) }
        self.displays = displayDTOs.isEmpty ? nil : displayDTOs

        self.billboardDevicePresent = port.hasBillboardDevice(among: usbDevices)

        self.trm = trmTransports.isEmpty ? nil : trmTransports.map { TRMTransportDTO(transport: $0) }
        self.cio = cioCapability.map { CIOCableCapabilityDTO(capability: $0) }

        // The per-port JSON device tree is the deduplicated union of native
        // matches and structurally scoped tunnelled devices: one array, so no
        // split-array duplication risk here (unlike ConnectedDeviceTree.rows).
        var seenDeviceIDs = Set<UInt64>()
        var treeDevices: [USBDevice] = []
        for device in usbDevices + structuralTunnelledDevices where seenDeviceIDs.insert(device.id).inserted {
            treeDevices.append(device)
        }
        let tree = USBDeviceNode.buildTree(from: treeDevices)
        self.devices = tree.isEmpty ? nil : tree.map { USBDeviceDTO(node: $0) }

        self.rawProperties = showRaw ? port.redactedRawProperties : nil
    }
}

private struct TransportsDTO: Codable {
    let supported: [String]
    let active: [String]
    let provisioned: [String]
    let displayPortLanes: String?
    /// Negotiated USB 3 speed label, e.g. "USB 3.2 Gen 1 (5 Gbps)".
    /// Nil when no USB 3 transport data is available for this port.
    let usb3Speed: String?
}

private struct PowerSourceDTO: Codable {
    let name: String
    let maxPowerW: Int
    let options: [OptionDTO]
    let negotiated: OptionDTO?
    /// True only when this source was synthesized from `PortControllerInfo`
    /// because macOS never published a real `IOPortFeaturePowerSource` node
    /// (issue #401, M1 Pro/Max/Ultra USB-C). Nil (omitted from JSON) for a
    /// real source, so existing output is unchanged.
    let synthesized: Bool?

    init(source: PowerSource) {
        self.name = source.name
        self.maxPowerW = Int((Double(source.maxPowerMW) / 1000).rounded())
        self.options = source.options.map { OptionDTO(option: $0) }
        self.negotiated = source.winning.map { OptionDTO(option: $0) }
        self.synthesized = source.isSynthesized ? true : nil
    }
}

private struct OptionDTO: Codable {
    let voltageV: Double
    let currentA: Double
    let powerW: Double

    init(option: PowerOption) {
        self.voltageV = Double(option.voltageMV) / 1000
        self.currentA = Double(option.maxCurrentMA) / 1000
        self.powerW = Double(option.maxPowerMW) / 1000
    }
}

private struct CableDTO: Codable {
    let endpoint: String
    let vendorID: Int
    let vendorName: String?
    let curatedBrands: [String]?
    let speed: String?
    let currentRating: String?
    let maxVolts: Int?
    let maxWatts: Int?
    let type: String?
    let active: ActiveCableDTO?
    /// True when the cable's ID Header self-reports as passive (Product Type 3)
    /// but VDO[3] bit 3 is set, which only exists in the active-cable layout.
    /// A genuine passive cable cannot have this bit set; its presence is a
    /// structural contradiction suggesting a mis-programmed e-marker. See
    /// `USBPDSOP.hasActiveLayoutContradiction` for the full spec rationale.
    let activeLayoutContradiction: Bool
    let trustFlags: [TrustFlagDTO]?
    /// USB-IF certification listings for this cable's Cert Stat XID, or nil
    /// when the XID is absent / unregistered (the common case). Additive:
    /// existing consumers are unaffected. Neutral provenance, not a verdict.
    let certification: CertificationDTO?
    /// The raw Cert Stat XID the e-marker reports, as hex ("0x5FC"), or nil
    /// when the cable carries no ID at all (VDO[1] == 0).
    ///
    /// Emitted whether or not the XID resolves to a listing, which is the
    /// whole point: without it, "this cable has no certification ID" and
    /// "this cable has one that USB-IF does not publish" are indistinguishable
    /// in every output the app produces. Measured on the probe corpus, ~15% of
    /// cable e-markers are the second case, Apple's own Thunderbolt cable
    /// included, so the difference is common enough to matter when diagnosing
    /// a "why is there no certified line?" report.
    ///
    /// The UI shows the raw ID under the cable's own claims ("Certification
    /// ID 0x...") and, when we can't resolve it, a neutral note under our
    /// records ("... isn't in our copy of the USB-IF registry"). Never as a
    /// fault: an unpublished ID says nothing bad about a cable, so
    /// a red/verdict treatment would read as doubt cast on good hardware. See
    /// planning/cable-trust-model.md for the same lesson learned the expensive
    /// way.
    let certID: String?
    /// Which reading settled `type`: "emarker", "portController" or
    /// "layoutContradiction". Emitted whenever `type` is, nil when it is not.
    /// Additive and machine-consumed, so the spellings are fixed.
    let typeSource: String?
    /// The cable's plug type from Cable VDO bits 19:18: "Type-A", "Type-B",
    /// "Type-C" or "captive". `reportLabel`, not `label`: --json must not vary
    /// with the UI language, same split as `speed` and `currentRating`.
    let plugType: String?

    init(identity: USBPDSOP, partner: USBPDSOP? = nil, port: AppleHPMInterface? = nil) {
        self.endpoint = identity.endpoint.rawValue
        self.vendorID = identity.vendorID
        self.vendorName = VendorDB.name(for: identity.vendorID)
        let cableVDORaw = identity.vdos.count > 3 ? identity.vdos[3] : 0
        let curated = CableDB.curatedCables(
            vid: identity.vendorID, pid: identity.productID, cableVDO: cableVDORaw
        )
        var seen = Set<String>()
        let unique = curated.map(\.brand).filter { seen.insert($0).inserted }
        self.curatedBrands = unique.isEmpty ? nil : unique

        // Resolved once and used for both `type`/`typeSource` and the
        // `active` block below. The two are edited apart, and them
        // disagreeing about the same read is exactly the defect this hoist
        // makes impossible.
        let resolution = CableClassification.resolve(identity: identity, port: port)

        if let cv = identity.cableVDO {
            // reportLabel, not label: --json is machine-consumed, and the
            // localized label varies with the UI language (same split as
            // currentRating below).
            self.speed = cv.speed.reportLabel
            self.currentRating = cv.current.reportLabel
            self.maxVolts = cv.maxVolts
            self.maxWatts = cv.maxWatts
            // The verdict is the classifier's, so a cable the port controller
            // promotes reports "active" here too. `typeSource` says which
            // reading settled it, so a consumer can tell the two apart.
            self.type = (resolution?.type ?? cv.cableType) == .active ? "active" : "passive"
            switch resolution?.source {
            case .emarker, nil: self.typeSource = "emarker"
            case .portController: self.typeSource = "portController"
            case .layoutContradiction: self.typeSource = "layoutContradiction"
            }
            self.plugType = cv.plugType.reportLabel
        } else {
            self.speed = nil
            self.currentRating = nil
            self.maxVolts = nil
            self.maxWatts = nil
            self.type = nil
            self.typeSource = nil
            self.plugType = nil
        }

        // Classifier-gated, matching the port card: a cable only the port
        // controller calls active still gets VDO[4] decoded, so `type` and
        // `active` cannot disagree about the same read.
        self.active = identity
            .activeCableVDO2(classifiedAs: resolution)
            .map(ActiveCableDTO.init)
        self.activeLayoutContradiction = identity.hasActiveLayoutContradiction

        let report = CableTrustReport(identity: identity, partner: partner)
        self.trustFlags = report.isEmpty ? nil : report.flags.map(TrustFlagDTO.init)

        if let xid = identity.certStatVDO?.xid {
            // Uppercase hex with a 0x prefix, matching how XIDs are written in
            // data/known-cables.md and shown by hardware e-marker readers.
            self.certID = xid == 0 ? nil : "0x" + String(xid, radix: 16, uppercase: true)
            let certs = CableDB.certifications(forXID: xid)
            self.certification = certs.isEmpty ? nil : CertificationDTO(
                listings: certs.map(CertListingDTO.init),
                // Confirming match only for a real (non-zero) VID; a mismatch
                // is never a signal. See research/usb-if-registry.md.
                vendorMatch: identity.vendorID != 0
                    && certs.contains { $0.vendorID == identity.vendorID }
            )
        } else {
            // No SOP' / SOP'' Cert Stat VDO to read at all (not a cable
            // e-marker, or fewer than two VDOs).
            self.certID = nil
            self.certification = nil
        }
    }
}

/// USB-IF certification for a cable, compiled offline. Neutral provenance.
private struct CertificationDTO: Codable {
    let listings: [CertListingDTO]
    /// True only when the cable's own e-marker VID matches a listing's vendor.
    /// A mild confirming signal. Never emitted as a "false = suspicious" flag;
    /// a mismatch is normal for ODM rebrands. See research/usb-if-registry.md.
    let vendorMatch: Bool
}

private struct CertListingDTO: Codable {
    let company: String
    let model: String
    let status: String
    let date: String
    let vendorId: Int?

    init(_ cert: CableCert) {
        self.company = cert.company
        self.model = cert.model
        self.status = cert.status
        self.date = cert.certDate
        self.vendorId = cert.vendorID
    }
}

private struct ActiveCableDTO: Codable {
    let physicalConnection: String
    let activeElement: String
    let opticallyIsolated: Bool
    let twoLanesSupported: Bool
    let usb4Supported: Bool
    let usb32Supported: Bool
    let usb2Supported: Bool
    let usbGen2OrHigher: Bool
    let maxOperatingTempC: Int
    let shutdownTempC: Int
    let u3CLdPower: String

    init(_ v2: PDVDO.ActiveCableVDO2) {
        self.physicalConnection = v2.physicalConnection.label
        self.activeElement = v2.activeElement.label
        self.opticallyIsolated = v2.opticallyIsolated
        self.twoLanesSupported = v2.twoLanesSupported
        self.usb4Supported = v2.usb4Supported
        self.usb32Supported = v2.usb32Supported
        self.usb2Supported = v2.usb2Supported
        self.usbGen2OrHigher = v2.usbGen2OrHigher
        self.maxOperatingTempC = v2.maxOperatingTempC
        self.shutdownTempC = v2.shutdownTempC
        self.u3CLdPower = v2.u3CLdPower.label
    }
}

private struct TrustFlagDTO: Codable {
    let code: String
    let title: String
    let detail: String
    /// "warning" for real trust signals, "note" for neutral context.
    let severity: String

    init(_ flag: TrustFlag) {
        self.code = flag.code
        self.title = flag.title
        self.detail = flag.detail
        self.severity = flag.severity == .warning ? "warning" : "note"
    }
}

private struct TrustDTO: Codable {
    /// "green", "amber", or "red".
    let tier: String
    /// Behavioural axes that confirmed the cable performs ("data" / "power").
    /// Nil for a static green and for amber/red. Sorted for stable output.
    let confirmedBy: [String]?
    /// The live link disagrees with the e-marker's claim; a pointer to the
    /// Negotiation breakdown, not part of the tier decision.
    let contradiction: Bool

    init(trust: CableTrust) {
        self.tier = trust.tier.rawValue
        let dims = trust.confirmedBy.map(\.rawValue).sorted()
        self.confirmedBy = dims.isEmpty ? nil : dims
        self.contradiction = trust.contradiction
    }
}

private struct DeviceDTO: Codable {
    let kind: String?
    let vendorID: Int
    let vendorName: String?
    let productID: Int
    let pdRevision: String?

    /// Builds the JSON view of a port partner from its USB-PD SOP identity,
    /// reporting the product type, vendor, product ID, and PD revision exactly
    /// as advertised on the wire.
    init(identity: USBPDSOP) {
        let header = identity.idHeader
        // `kind` is the partner's product type exactly as advertised in its PD
        // ID header. This is intentionally the raw value: the JSON feed is
        // faithful to the wire. The human-facing PortSummary applies a smarter
        // rule (a power source claiming to be a passive cable is shown as the
        // charger, see issue #268), so `device.kind` here can read "Passive
        // cable" for a port whose card/CLI bullet says "Charger identified as".
        self.kind = header.map {
            $0.ufpProductType != .undefined ? $0.ufpProductType.label : $0.dfpProductType.label
        }
        self.vendorID = identity.vendorID
        self.vendorName = VendorDB.name(for: identity.vendorID)
        self.productID = identity.productID
        self.pdRevision = identity.pdRevisionLabel
    }
}

// MARK: - Thunderbolt fabric DTOs

/// One Thunderbolt switch in JSON form. Encoded once at the top level of
/// the snapshot; per-port references use `thunderboltSwitchIndex`. Avoids
/// duplicating the whole graph under every port. The hardware UID is a
/// stable machine identifier and is deliberately not encoded; `index` and
/// `parentSwitchIndex` are per-snapshot positions in this array.
private struct IOThunderboltSwitchDTO: Codable {
    let index: Int
    let className: String
    let vendorID: Int
    let vendorName: String
    let modelName: String
    let depth: Int
    let routerID: Int
    let routeString: Int64
    let upstreamPortNumber: Int
    let maxPortNumber: Int
    let supportedSpeedMask: Int
    let parentSwitchIndex: Int?
    let ports: [IOThunderboltPortDTO]

    init(sw: IOThunderboltSwitch, index: Int, switchIndexByUID: [Int64: Int]) {
        self.index = index
        self.className = sw.className
        self.vendorID = sw.vendorID
        self.vendorName = sw.vendorName
        self.modelName = sw.modelName
        self.depth = sw.depth
        self.routerID = sw.routerID
        self.routeString = sw.routeString
        self.upstreamPortNumber = sw.upstreamPortNumber
        self.maxPortNumber = sw.maxPortNumber
        self.supportedSpeedMask = Int(sw.supportedSpeed.rawValue)
        self.parentSwitchIndex = sw.parentSwitchUID.flatMap { switchIndexByUID[$0] }
        self.ports = sw.ports.map { IOThunderboltPortDTO(port: $0) }
    }
}

private struct IOThunderboltPortDTO: Codable {
    let portNumber: Int
    let socketID: String?
    let adapterType: String
    let linkActive: Bool
    let linkLabel: String?
    let generation: String?
    let perLaneGbps: Int?
    let txLanes: Int?
    let rxLanes: Int?
    let rawSpeedCode: Int?
    let rawWidthCode: Int?
    let rawTargetSpeed: Int?
    let linkBandwidthRaw: Int?

    init(port: IOThunderboltPort) {
        self.portNumber = port.portNumber
        self.socketID = port.socketID
        self.adapterType = Self.adapterTypeLabel(port.adapterType)
        self.linkActive = port.hasActiveLink
        self.linkLabel = ThunderboltLabels.linkLabel(for: port)
        self.generation = port.currentSpeed.map { Self.generationLabel($0) }
        self.perLaneGbps = port.perLaneGbps
        self.txLanes = port.txLanes
        self.rxLanes = port.rxLanes
        self.rawSpeedCode = port.currentSpeed.map { Self.rawSpeedCode($0) }
        self.rawWidthCode = port.currentWidth.map { Int($0.rawValue) }
        self.rawTargetSpeed = port.rawTargetSpeed.map { Int($0) }
        self.linkBandwidthRaw = port.linkBandwidthRaw
    }

    private static func adapterTypeLabel(_ type: AdapterType) -> String {
        switch type {
        case .inactive: return "inactive"
        case .lane: return "lane"
        case .nhi: return "nhi"
        case .dpIn: return "dpIn"
        case .dpOut: return "dpOut"
        case .pcieDown: return "pcieDown"
        case .pcieUp: return "pcieUp"
        case .usb3Down: return "usb3Down"
        case .usb3Up: return "usb3Up"
        case .usbGenTDown: return "usbGenTDown"
        case .usbGenTUp: return "usbGenTUp"
        case .other(let raw): return "other(0x\(String(raw, radix: 16)))"
        }
    }

    private static func generationLabel(_ gen: LinkGeneration) -> String {
        switch gen {
        case .tb3: return "tb3"
        case .usb4Tb4: return "usb4Tb4"
        // TB5 (raw speed code 0x2) was confirmed against a real M5 Pro +
        // UGreen JHL9580 dock paste-back on issue #52, so the hedge has
        // been dropped. Machine consumers that want the raw code can
        // still read `rawSpeedCode` directly.
        case .tb5: return "tb5"
        case .unknown(let raw): return "unknown(0x\(String(raw, radix: 16)))"
        }
    }

    private static func rawSpeedCode(_ gen: LinkGeneration) -> Int {
        switch gen {
        case .tb3: return 0x8
        case .usb4Tb4: return 0x4
        case .tb5: return 0x2
        case .unknown(let raw): return Int(raw)
        }
    }
}

private struct TRMTransportDTO: Codable {
    let transportType: String
    let state: Int?
    let stateDescription: String?
    let transportRestricted: Bool?
    let transportSupervised: Bool?
    let identificationRestricted: Bool?
    let deviceLocked: Bool?
    let relaxedPeriod: Bool?
    let gracePeriodReason: Int?
    let gracePeriodReasonDescription: String?
    let profile: Int?
    let profileDescription: String?
    let cacheMiss: Bool?

    init(transport: TRMTransport) {
        self.transportType = transport.transportType
        self.state = transport.state
        self.stateDescription = transport.stateDescription
        self.transportRestricted = transport.transportRestricted
        self.transportSupervised = transport.transportSupervised
        self.identificationRestricted = transport.identificationRestricted
        self.deviceLocked = transport.deviceLocked
        self.relaxedPeriod = transport.relaxedPeriod
        self.gracePeriodReason = transport.gracePeriodReason
        self.gracePeriodReasonDescription = transport.gracePeriodReasonDescription
        self.profile = transport.profile
        self.profileDescription = transport.profileDescription
        self.cacheMiss = transport.cacheMiss
    }
}

private struct CIOCableCapabilityDTO: Codable {
    let cableGeneration: Int?
    // Wire name stays "cableSpeed" for JSON schema stability even though
    // the Swift-side property is `negotiatedLinkSpeed` (renamed, issue
    // #393, since "cableSpeed" reads as a cable capability and it is
    // actually the negotiated link rate, a floor not a cap). Changing a
    // public JSON key is a breaking change for anyone parsing `--json`
    // output, so only the internal name moves.
    let cableSpeed: Int?
    let generation: Int?
    let asymmetricModeSupported: Bool?
    let legacyAdapter: Bool?
    let linkTrainingMode: Int?

    init(capability: CIOCableCapability) {
        self.cableGeneration = capability.cableGeneration
        self.cableSpeed = capability.negotiatedLinkSpeed
        self.generation = capability.generation
        self.asymmetricModeSupported = capability.asymmetricModeSupported
        self.legacyAdapter = capability.legacyAdapter
        self.linkTrainingMode = capability.linkTrainingMode
    }
}

private struct ChargingDTO: Codable {
    let summary: String
    let detail: String
    let bottleneck: String
    let isWarning: Bool

    init(diagnostic: ChargingDiagnostic) {
        self.summary = diagnostic.summary
        self.detail = diagnostic.detail
        self.isWarning = diagnostic.isWarning
        switch diagnostic.bottleneck {
        case .noCharger: self.bottleneck = "noCharger"
        case .chargerLimit: self.bottleneck = "chargerLimit"
        case .cableLimit: self.bottleneck = "cableLimit"
        case .macLimit: self.bottleneck = "macLimit"
        case .fine: self.bottleneck = "fine"
        case .standbyCharger: self.bottleneck = "standbyCharger"
        }
    }
}

private struct DataLinkDTO: Codable {
    let summary: String
    let detail: String
    let bottleneck: String
    let isWarning: Bool
    /// True when the cable e-marker and the Thunderbolt controller
    /// disagree about the cable's speed (issue #111).
    let cableSignalConflict: Bool

    init(diagnostic: DataLinkDiagnostic) {
        self.summary = diagnostic.summary
        self.detail = diagnostic.detail
        self.isWarning = diagnostic.isWarning
        self.cableSignalConflict = diagnostic.cableSignalConflict
        switch diagnostic.bottleneck {
        case .fine: self.bottleneck = "fine"
        case .cableLimit: self.bottleneck = "cableLimit"
        case .hostLimit: self.bottleneck = "hostLimit"
        case .deviceLimit: self.bottleneck = "deviceLimit"
        case .degraded: self.bottleneck = "degraded"
        case .unknownCable: self.bottleneck = "unknownCable"
        case .cableContradictsActive: self.bottleneck = "cableContradictsActive"
        case .blockedBySecurity: self.bottleneck = "blockedBySecurity"
        }
    }
}

private struct DisplayDTO: Codable {
    let summary: String
    let detail: String
    let bottleneck: String
    let isWarning: Bool
    let monitorName: String?
    let neededGbps: Double?
    let deliveredGbps: Double?
    let lanes: Int
    let maxLanes: Int
    let rate: String?
    /// "HDMI" / "DVI" / "VGA" when an adapter is in the chain, else nil.
    let sinkType: String?
    /// The adapter / branch device's reported DisplayPort version, e.g.
    /// "DisplayPort 1.2". nil for a direct connection.
    let branchDevice: String?
    /// Cable attribution: "unlikelyTheCable" or "inconclusive". Never blames
    /// the cable (only ever exonerates it on demonstrated evidence).
    let cableAssessment: String
    /// The live on-screen mode from CoreGraphics, when matched. The true
    /// resolution even for 5K/6K displays whose EDID can't describe it.
    let currentMode: CurrentModeDTO?
    /// The display's highest mode from CoreGraphics, EDID-free.
    let maxMode: CurrentModeDTO?

    init(diagnostic: DisplayDiagnostic) {
        self.summary = diagnostic.summary
        self.detail = diagnostic.detail
        self.isWarning = diagnostic.isWarning
        switch diagnostic.bottleneck {
        case .fine: self.bottleneck = "fine"
        case .belowMonitorMax: self.bottleneck = "belowMonitorMax"
        case .adapterLimit: self.bottleneck = "adapterLimit"
        case .unknownMode: self.bottleneck = "unknownMode"
        case .compressionPlausible: self.bottleneck = "compressionPlausible"
        case .compressionActive: self.bottleneck = "compressionActive"
        }
        switch diagnostic.cableAssessment {
        case .unlikelyTheCable: self.cableAssessment = "unlikelyTheCable"
        case .inconclusive: self.cableAssessment = "inconclusive"
        }
        let facts = diagnostic.facts
        self.monitorName = facts.monitorName
        self.neededGbps = facts.neededGbps
        self.deliveredGbps = facts.deliveredGbps
        self.lanes = facts.lanes
        self.maxLanes = facts.maxLanes
        self.rate = facts.rateDescription
        self.sinkType = facts.sinkType
        self.branchDevice = facts.branchDevice
        self.currentMode = facts.currentMode.map(CurrentModeDTO.init)
        self.maxMode = facts.maxMode.map(CurrentModeDTO.init)
    }
}

private struct CurrentModeDTO: Codable {
    let width: Int
    let height: Int
    let refreshHz: Double
    /// Bits per channel macOS is driving the framebuffer at (8 / 10 when read,
    /// nil otherwise). Emitted so a `--json` consumer can see which bits-per-
    /// pixel value the display diagnostic used: a `.compressionActive` verdict
    /// reads as 8 -> 24bpp arithmetic, 10 -> 30bpp arithmetic, missing -> the
    /// 24bpp fallback.
    let bitsPerComponent: Int?

    init(_ mode: DisplayCurrentMode) {
        self.width = mode.width
        self.height = mode.height
        self.refreshHz = mode.refreshHz
        self.bitsPerComponent = mode.bitsPerComponent
    }
}

/// System-wide charger info from IOPSCopyExternalPowerAdapterDetails.
private struct AdapterDTO: Codable {
    let watts: Int?
    let source: String?
    let voltageMV: Int?
    let currentMA: Int?
    let description: String?
    let powerTier: Int?
    let isWireless: Bool?
    /// The charger's HVC menu: every voltage/current combo it supports.
    let hvcMenu: [AdapterHVCEntryDTO]?
    /// Charger brand from IOKit `AdapterDetails.Manufacturer`. Present
    /// mostly on Apple bricks. Omitted when nil or empty.
    let manufacturer: String?
    /// Product name from IOKit `AdapterDetails.Name`. Pairs with
    /// `manufacturer`. Omitted when nil or empty.
    let name: String?
    /// Apple-internal model code (e.g. "0x7019"). Omitted when absent.
    let model: String?

    init(adapter: AdapterInfo) {
        self.watts = adapter.watts
        self.source = adapter.source
        self.voltageMV = adapter.voltageMV
        self.currentMA = adapter.currentMA
        self.description = adapter.adapterDescription
        self.powerTier = adapter.powerTier
        self.isWireless = adapter.isWireless
        self.hvcMenu = adapter.hvcMenu.isEmpty ? nil : adapter.hvcMenu.map {
            AdapterHVCEntryDTO(voltageMV: $0.voltageMV, currentMA: $0.currentMA)
        }
        self.manufacturer = adapter.manufacturer
        self.name = adapter.name
        self.model = adapter.model
    }
}

private struct AdapterHVCEntryDTO: Codable {
    let voltageMV: Int
    let currentMA: Int
}

private struct USBDeviceDTO: Codable {
    let name: String?
    let vendorID: Int
    let productID: Int
    let vendorName: String?
    let serialNumber: String?
    let usbVersion: String?
    let speed: String
    let locationID: String
    let children: [USBDeviceDTO]?

    init(node: USBDeviceNode) {
        let device = node.device
        self.name = device.productName
        self.vendorID = Int(device.vendorID)
        self.productID = Int(device.productID)
        // Match the UI: device-reported name, else the VID database. Gate the
        // DB fallback on a real registration so the sentinel sentences
        // VendorDB.name(for:) returns for VID 0 / 0xFFFF ("No vendor reported",
        // "No vendor ID assigned …") never leak into this machine-readable
        // field — downstream consumers parse it, so it stays null when there is
        // no genuine vendor name (preserving the pre-fallback contract).
        if let reported = device.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reported.isEmpty {
            self.vendorName = reported
        } else if VendorDB.isRegistered(Int(device.vendorID)) {
            self.vendorName = VendorDB.name(for: Int(device.vendorID))
        } else {
            self.vendorName = nil
        }
        self.serialNumber = device.serialNumber
        self.usbVersion = device.usbVersion
        self.speed = device.speedLabel
        self.locationID = String(format: "0x%08x", device.locationID)
        self.children = node.children.isEmpty ? nil : node.children.map { USBDeviceDTO(node: $0) }
    }
}
