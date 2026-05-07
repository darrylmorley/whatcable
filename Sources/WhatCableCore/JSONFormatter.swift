import Foundation

public enum JSONFormatter {
    public static func render(
        ports: [USBCPort],
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo? = nil,
        thunderboltSwitches: [ThunderboltSwitch] = []
    ) throws -> String {
        let output = Output(
            version: AppInfo.version,
            ports: ports.map { port in
                PortDTO(
                    port: port,
                    sources: sources.filter { $0.portKey == port.portKey },
                    identities: identities.filter { $0.portKey == port.portKey },
                    thunderboltSwitches: thunderboltSwitches,
                    showRaw: showRaw,
                    adapter: adapter
                )
            },
            thunderboltSwitches: thunderboltSwitches.map { ThunderboltSwitchDTO(sw: $0) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct Output: Codable {
    let version: String
    let ports: [PortDTO]
    /// Top-level Thunderbolt fabric. Always present (empty array on
    /// machines without a TB controller, or before the watcher has data).
    /// Per-port `thunderboltSwitchUID` references this graph by UID rather
    /// than nesting the whole switch under each port.
    let thunderboltSwitches: [ThunderboltSwitchDTO]
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
    /// UID of the host root Thunderbolt switch this port maps to, if any.
    /// Resolved via the `Socket ID` <-> `@N` join key. Encoded as Int64
    /// (signed, matching IOKit's representation; some vendors use the
    /// sign bit). nil for ports that aren't TB-protocol or for which the
    /// watcher hasn't found a match.
    let thunderboltSwitchUID: Int64?
    let rawProperties: [String: String]?

    init(
        port: USBCPort,
        sources: [PowerSource],
        identities: [PDIdentity],
        thunderboltSwitches: [ThunderboltSwitch],
        showRaw: Bool,
        adapter: AdapterInfo?
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
            thunderboltSwitches: thunderboltSwitches
        )
        self.status = String(describing: summary.status)
        self.headline = summary.headline
        self.subtitle = summary.subtitle
        self.bullets = summary.bullets

        // Resolve the host-root switch UID via Socket ID matching.
        if let socketID = ThunderboltTopology.socketID(fromServiceName: port.serviceName),
           let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches) {
            self.thunderboltSwitchUID = root.id
        } else {
            self.thunderboltSwitchUID = nil
        }

        self.transports = TransportsDTO(
            supported: port.transportsSupported,
            active: port.transportsActive,
            provisioned: port.transportsProvisioned
        )

        self.powerSources = sources.map { PowerSourceDTO(source: $0) }

        let cableEmarker = identities.first {
            $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
        }
        self.cable = cableEmarker.map { CableDTO(identity: $0) }

        let partner = identities.first { $0.endpoint == .sop }
        self.device = partner.map { DeviceDTO(identity: $0) }

        self.charging = ChargingDiagnostic(port: port, sources: sources, identities: identities, adapter: adapter)
            .map { ChargingDTO(diagnostic: $0) }

        self.rawProperties = showRaw ? port.rawProperties : nil
    }
}

private struct TransportsDTO: Codable {
    let supported: [String]
    let active: [String]
    let provisioned: [String]
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
    let speed: String?
    let currentRating: String?
    let maxVolts: Int?
    let maxWatts: Int?
    let type: String?
    let active: ActiveCableDTO?
    let trustFlags: [TrustFlagDTO]?

    init(identity: PDIdentity) {
        self.endpoint = identity.endpoint.rawValue
        self.vendorID = identity.vendorID
        self.vendorName = VendorDB.name(for: identity.vendorID)
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

    init(identity: PDIdentity) {
        let header = identity.idHeader
        self.kind = header.map {
            $0.ufpProductType != .undefined ? $0.ufpProductType.label : $0.dfpProductType.label
        }
        self.vendorID = identity.vendorID
        self.vendorName = VendorDB.name(for: identity.vendorID)
        self.productID = identity.productID
    }
}

// MARK: - Thunderbolt fabric DTOs

/// One Thunderbolt switch in JSON form. Encoded once at the top level of
/// the snapshot; per-port references use `thunderboltSwitchUID`. Avoids
/// duplicating the whole graph under every port.
private struct ThunderboltSwitchDTO: Codable {
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
    let ports: [ThunderboltPortDTO]

    init(sw: ThunderboltSwitch) {
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
        self.ports = sw.ports.map { ThunderboltPortDTO(port: $0) }
    }
}

private struct ThunderboltPortDTO: Codable {
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

    init(port: ThunderboltPort) {
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
        // TB5 stays hedged in JSON for the same reason as the text
        // renderer: the 0x2 -> TB5 mapping is inferred from Linux
        // register definitions but not yet verified against an Apple
        // Silicon TB5 paste-back. Machine consumers that want the raw
        // code can read `rawSpeedCode` directly. The label flips to
        // `"tb5"` once verified.
        case .tb5: return "unknown(0x2_inferredTb5)"
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
