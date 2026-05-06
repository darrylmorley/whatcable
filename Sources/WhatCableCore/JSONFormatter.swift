import Foundation

public enum JSONFormatter {
    public static func render(
        ports: [USBCPort],
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo? = nil
    ) throws -> String {
        let output = Output(
            version: AppInfo.version,
            ports: ports.map { port in
                PortDTO(
                    port: port,
                    sources: sources.filter { $0.portKey == port.portKey },
                    identities: identities.filter { $0.portKey == port.portKey },
                    showRaw: showRaw,
                    adapter: adapter
                )
            }
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
}

private struct PortDTO: Codable {
    let name: String
    let type: String?
    let className: String
    let connectionActive: Bool
    let status: String
    let headline: String
    let subtitle: String
    let bullets: [String]
    let transports: TransportsDTO
    let powerSources: [PowerSourceDTO]
    let cable: CableDTO?
    let device: DeviceDTO?
    let charging: ChargingDTO?
    let rawProperties: [String: String]?

    init(port: USBCPort, sources: [PowerSource], identities: [PDIdentity], showRaw: Bool, adapter: AdapterInfo?) {
        self.name = port.portDescription ?? port.serviceName
        self.type = port.portTypeDescription
        self.className = port.className
        self.connectionActive = port.connectionActive ?? false

        let summary = PortSummary(port: port, sources: sources, identities: identities)
        self.status = String(describing: summary.status)
        self.headline = summary.headline
        self.subtitle = summary.subtitle
        self.bullets = summary.bullets

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

        let report = CableTrustReport(identity: identity)
        self.trustFlags = report.isEmpty ? nil : report.flags.map(TrustFlagDTO.init)
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
