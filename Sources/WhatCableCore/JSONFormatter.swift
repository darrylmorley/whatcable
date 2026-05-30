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
        federatedIdentities: [FederatedIdentity] = [],
        usb3Transports: [USB3Transport] = [],
        trmTransports: [TRMTransport] = [],
        cioCapabilities: [CIOCableCapability] = [],
        usbDevices: [USBDevice] = [],
        displayPorts: [IOPortTransportStateDisplayPort] = []
    ) throws -> String {
        let activePortCount = ports.filter { $0.connectionActive == true }.count
        let output = Output(
            version: AppInfo.version,
            isDesktopMac: isDesktopMac,
            adapter: adapter.map { AdapterDTO(adapter: $0) },
            ports: ports.map { port in
                let portSources = sources.filter { $0.portKey == port.portKey }
                let wattageSource = ChargerWattageSource.resolve(
                    portSources: portSources,
                    activePortCount: activePortCount,
                    adapter: adapter
                )
                return PortDTO(
                    port: port,
                    sources: portSources,
                    identities: identities.filter { $0.portKey == port.portKey },
                    thunderboltSwitches: thunderboltSwitches,
                    showRaw: showRaw,
                    adapter: adapter,
                    federatedIdentities: federatedIdentities,
                    usb3Transports: usb3Transports.filter { $0.portKey == port.portKey },
                    trmTransports: trmTransports.filter { $0.portKey == port.portKey },
                    cioCapability: cioCapabilities.first { $0.portKey == port.portKey },
                    chargerWattageSource: wattageSource,
                    batteryFullyCharged: batteryFullyCharged,
                    usbDevices: port.matchingDevices(from: usbDevices),
                    displayPort: displayPorts.first { $0.portKey == port.portKey }
                )
            },
            thunderboltSwitches: thunderboltSwitches.map { IOThunderboltSwitchDTO(sw: $0) }
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
    /// Per-port `thunderboltSwitchUID` references this graph by UID rather
    /// than nesting the whole switch under each port.
    let thunderboltSwitches: [IOThunderboltSwitchDTO]
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
    let bullets: [String]
    let transports: TransportsDTO
    let powerSources: [PowerSourceDTO]
    let cable: CableDTO?
    let device: DeviceDTO?
    let charging: ChargingDTO?
    /// Data-speed "weakest link" verdict: which of cable / Mac port /
    /// device limits the negotiated data rate. Nil when there's no data
    /// link to judge on this port.
    let dataLink: DataLinkDTO?
    /// Display "weakest link" verdict: whether the current DisplayPort link
    /// carries the monitor's top mode. Nil when there's no active display
    /// link on this port.
    let display: DisplayDTO?
    /// UID of the host root Thunderbolt switch this port maps to, if any.
    /// Resolved via the `Socket ID` <-> `@N` join key. Encoded as Int64
    /// (signed, matching IOKit's representation; some vendors use the
    /// sign bit). nil for ports that aren't TB-protocol or for which the
    /// watcher hasn't found a match.
    let thunderboltSwitchUID: Int64?
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
        showRaw: Bool,
        adapter: AdapterInfo?,
        federatedIdentities: [FederatedIdentity] = [],
        usb3Transports: [USB3Transport] = [],
        trmTransports: [TRMTransport] = [],
        cioCapability: CIOCableCapability? = nil,
        chargerWattageSource: ChargerWattageSource = .unknown,
        batteryFullyCharged: Bool? = nil,
        usbDevices: [USBDevice] = [],
        displayPort: IOPortTransportStateDisplayPort? = nil
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
            cioCapability: cioCapability,
            chargerWattageSource: chargerWattageSource,
            batteryFullyCharged: batteryFullyCharged,
            adapter: adapter
        )
        self.status = String(describing: summary.status)
        self.headline = summary.headline
        self.subtitle = summary.subtitle
        self.bullets = summary.bullets

        // Resolve the host-root switch UID via Socket ID matching.
        if let socketID = ThunderboltTopology.socketID(for: port),
           let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches) {
            self.thunderboltSwitchUID = root.id
        } else {
            self.thunderboltSwitchUID = nil
        }

        // `TransportsActive` is the sole authority for "USB3 is live"
        // (issue #187). The HPM controller can leave a stale
        // `IOPortTransportStateUSB3` service registered, assert
        // `IOAccessoryUSBSuperSpeedActive=1`, and even keep matched
        // `USBDevice` entries reporting SuperSpeed when the negotiated
        // link is only USB 2.0. Gate the whole `usb3Speed` resolution on
        // TransportsActive, not just the transport-derived fallback.
        let usb3Speed: String?
        if port.transportsActive.contains("USB3") {
            // Selection order mirrors PortSummary: root device first,
            // then HPM transport, then controller-port-name fallback for
            // Apple Silicon front USB-C ports whose internal virtual root
            // hides the actual root device.
            let rootDeviceSpeed = USBDevice.rootSuperSpeed(in: usbDevices)?.usb3SpeedLabel
            let portMatchedSpeed = USBDevice.portMatchedSuperSpeed(in: usbDevices)?.usb3SpeedLabel
            usb3Speed = rootDeviceSpeed ?? usb3Transports.first?.speedLabel ?? portMatchedSpeed
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

        let cableEmarker = identities.first {
            $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
        }
        self.cable = cableEmarker.map { CableDTO(identity: $0) }

        let partner = identities.first { $0.endpoint == .sop }
        self.device = partner.map { DeviceDTO(identity: $0) }

        self.charging = ChargingDiagnostic(port: port, sources: sources, identities: identities, adapter: adapter, wattageSource: chargerWattageSource, batteryFullyCharged: batteryFullyCharged)
            .map { ChargingDTO(diagnostic: $0) }

        self.dataLink = DataLinkDiagnostic(
            port: port,
            identities: identities,
            devices: usbDevices,
            usb3Transports: usb3Transports,
            cio: cioCapability,
            thunderboltSwitches: thunderboltSwitches
        ).map { DataLinkDTO(diagnostic: $0) }

        self.display = displayPort
            .flatMap { DisplayDiagnostic(dp: $0, cable: cableEmarker) }
            .map { DisplayDTO(diagnostic: $0) }

        self.trm = trmTransports.isEmpty ? nil : trmTransports.map { TRMTransportDTO(transport: $0) }
        self.cio = cioCapability.map { CIOCableCapabilityDTO(capability: $0) }

        let tree = USBDeviceNode.buildTree(from: usbDevices)
        self.devices = tree.isEmpty ? nil : tree.map { USBDeviceDTO(node: $0) }

        self.rawProperties = showRaw ? port.rawProperties : nil
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

    init(source: PowerSource) {
        self.name = source.name
        self.maxPowerW = Int((Double(source.maxPowerMW) / 1000).rounded())
        self.options = source.options.map { OptionDTO(option: $0) }
        self.negotiated = source.winning.map { OptionDTO(option: $0) }
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
    let trustFlags: [TrustFlagDTO]?

    init(identity: USBPDSOP) {
        self.endpoint = identity.endpoint.rawValue
        self.vendorID = identity.vendorID
        self.vendorName = VendorDB.name(for: identity.vendorID)
        let vdo = identity.vdos.count > 3 ? identity.vdos[3] : 0
        let curated = CableDB.curatedCables(
            vid: identity.vendorID, pid: identity.productID, cableVDO: vdo
        )
        var seen = Set<String>()
        let unique = curated.map(\.brand).filter { seen.insert($0).inserted }
        self.curatedBrands = unique.isEmpty ? nil : unique
        if let cv = identity.cableVDO {
            self.speed = cv.speed.label
            self.currentRating = cv.current.label
            self.maxVolts = cv.maxVolts
            self.maxWatts = cv.maxWatts
            self.type = cv.cableType == .active ? "active" : "passive"
        } else {
            self.speed = nil
            self.currentRating = nil
            self.maxVolts = nil
            self.maxWatts = nil
            self.type = nil
        }

        self.active = identity.activeCableVDO2.map(ActiveCableDTO.init)

        let report = CableTrustReport(identity: identity)
        self.trustFlags = report.isEmpty ? nil : report.flags.map(TrustFlagDTO.init)
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

    init(_ flag: TrustFlag) {
        self.code = flag.code
        self.title = flag.title
        self.detail = flag.detail
    }
}

private struct DeviceDTO: Codable {
    let kind: String?
    let vendorID: Int
    let vendorName: String?
    let productID: Int
    let pdRevision: String?

    init(identity: USBPDSOP) {
        let header = identity.idHeader
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
/// the snapshot; per-port references use `thunderboltSwitchUID`. Avoids
/// duplicating the whole graph under every port.
private struct IOThunderboltSwitchDTO: Codable {
    let uid: Int64
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
    let parentSwitchUID: Int64?
    let ports: [IOThunderboltPortDTO]

    init(sw: IOThunderboltSwitch) {
        self.uid = sw.id
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
        self.parentSwitchUID = sw.parentSwitchUID
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
    let cableSpeed: Int?
    let generation: Int?
    let asymmetricModeSupported: Bool?
    let legacyAdapter: Bool?
    let linkTrainingMode: Int?

    init(capability: CIOCableCapability) {
        self.cableGeneration = capability.cableGeneration
        self.cableSpeed = capability.cableSpeed
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
    /// Cable attribution: "unlikelyTheCable" or "inconclusive". Never blames
    /// the cable (only ever exonerates it on demonstrated evidence).
    let cableAssessment: String

    init(diagnostic: DisplayDiagnostic) {
        self.summary = diagnostic.summary
        self.detail = diagnostic.detail
        self.isWarning = diagnostic.isWarning
        switch diagnostic.bottleneck {
        case .fine: self.bottleneck = "fine"
        case .belowMonitorMax: self.bottleneck = "belowMonitorMax"
        case .adapterLimit: self.bottleneck = "adapterLimit"
        case .unknownMode: self.bottleneck = "unknownMode"
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
    let speed: String
    let locationID: String
    let children: [USBDeviceDTO]?

    init(node: USBDeviceNode) {
        self.name = node.device.productName
        self.vendorID = Int(node.device.vendorID)
        self.productID = Int(node.device.productID)
        self.vendorName = node.device.vendorName
        self.speed = node.device.speedLabel
        self.locationID = String(format: "0x%08x", node.device.locationID)
        self.children = node.children.isEmpty ? nil : node.children.map { USBDeviceDTO(node: $0) }
    }
}
