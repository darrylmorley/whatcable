import Foundation

public struct DisplayPortLink: Codable, Sendable, Equatable {
    public let active: Bool
    public let laneCount: Int
    public let maxLaneCount: Int
    public let linkRate: Int
    public let linkRateDescription: String?
    public let tunneled: Bool
    public let hpdState: Int
    public let hpdStateDescription: String?

    public init(
        active: Bool,
        laneCount: Int,
        maxLaneCount: Int,
        linkRate: Int,
        linkRateDescription: String? = nil,
        tunneled: Bool,
        hpdState: Int,
        hpdStateDescription: String? = nil
    ) {
        self.active = active
        self.laneCount = laneCount
        self.maxLaneCount = maxLaneCount
        self.linkRate = linkRate
        self.linkRateDescription = linkRateDescription
        self.tunneled = tunneled
        self.hpdState = hpdState
        self.hpdStateDescription = hpdStateDescription
    }
}

public struct MonitorInfo: Codable, Sendable, Equatable {
    public let manufacturerName: String?
    public let productName: String?
    public let productId: Int?
    public let serialNumber: Int?
    public let yearOfManufacture: Int?
    public let weekOfManufacture: Int?
    public let edid: Data?

    public init(
        manufacturerName: String?,
        productName: String?,
        productId: Int?,
        serialNumber: Int? = nil,
        yearOfManufacture: Int?,
        weekOfManufacture: Int? = nil,
        edid: Data?
    ) {
        self.manufacturerName = manufacturerName
        self.productName = productName
        self.productId = productId
        self.serialNumber = serialNumber
        self.yearOfManufacture = yearOfManufacture
        self.weekOfManufacture = weekOfManufacture
        self.edid = edid
    }
}

extension MonitorInfo {
    /// Whether the panel is one of Apple's own displays: EDID bytes 8-9, the
    /// big-endian PNP manufacturer id, equal to 0x0610 (PNP `APP`); when the
    /// blob cannot hold byte 9, `manufacturerName == "APP"` stands in. The
    /// same key the display-node pairs used (research/displays/display-node-keys.md,
    /// "Apple's own displays carry a full DSC list on every timing").
    ///
    /// Gates only the wording of a DSC-on verdict (no link blame on an Apple
    /// display: 45 of 46 Apple-display nodes list DSC on every timing whatever
    /// the link). It is a statement about the producer's measured behaviour,
    /// not a vendor heuristic: on a node that does not match, the general rule
    /// gives the same "DSC on" reading and only the no-link-blame clause is lost.
    public var isAppleDisplay: Bool {
        if let edid, edid.count >= 10 {
            let bytes = [UInt8](edid.prefix(10))
            return bytes[8] == 0x06 && bytes[9] == 0x10
        }
        return manufacturerName == "APP"
    }
}

public struct IOPortTransportStateDisplayPort: Codable, Sendable, Equatable {
    public let link: DisplayPortLink
    public let monitor: MonitorInfo?
    public let dfpType: String?
    public let branchDeviceId: String?
    public let branchDeviceOUI: Data?
    public let sinkCount: Int
    public let role: Int
    public let roleDescription: String?
    public let driverStatus: Int
    public let driverStatusDescription: String?
    public let transportType: Int
    public let transportTypeDescription: String?
    public let transportDescription: String?
    public let authorizationRequired: Bool
    public let authorizationStatus: Int
    public let authorizationStatusDescription: String?
    public let authenticationRequired: Bool
    public let authenticationStatus: Int
    public let authenticationStatusDescription: String?
    public let hashStatus: Int
    public let hashStatusDescription: String?
    public let trmTransportSupervised: Bool
    public let parentPortType: Int
    public let parentPortTypeDescription: String?
    public let parentPortNumber: Int
    public let parentPortBuiltIn: Bool
    public let parentBuiltInPortType: Int
    public let parentBuiltInPortTypeDescription: String?
    public let parentBuiltInPortNumber: Int
    public let edidChanged: Bool
    public let nominalSignalingFrequenciesHz: [Int]
    public let index: Int
    /// The live on-screen mode from CoreGraphics, attached by the Darwin
    /// backend when it can match this node to exactly one display. nil in
    /// tests, and whenever the match is missing or ambiguous, so every
    /// consumer treats its absence as "no extra data".
    public let currentMode: DisplayCurrentMode?
    /// The display's native top mode as macOS reports it (from
    /// `CGDisplayCopyAllDisplayModes`): highest resolution, at its best refresh.
    /// The authoritative top mode that does not depend on parsing the EDID, so
    /// it is correct even for 5K/6K displays whose EDID can't describe their
    /// native mode. Same nil contract as `currentMode`.
    public let maxMode: DisplayCurrentMode?
    /// What macOS's display node states about this display: the driven
    /// timing's lists (colour modes, the DSC-required and unsafe lists, the
    /// valid encodings) and every non-virtual timing the node lists, attached
    /// by `DisplayTimingReader.match` when exactly one node matched this
    /// display; nil in tests and whenever the match is missing. Set together
    /// with `currentMode` and never without it.
    public let drivenTiming: DisplayTimingStatement?
    /// HPM controller UUID captured by walking the IOKit parent chain from the
    /// `IOPortTransportStateDisplayPort` node up to `AppleHPMDeviceHALType3`.
    /// Internal join key only. Never serialised to JSON or text output.
    /// Excluded from `CodingKeys` so it never appears in encoded output.
    public let hpmControllerUUID: String?

    public init(
        link: DisplayPortLink,
        monitor: MonitorInfo?,
        dfpType: String? = nil,
        branchDeviceId: String? = nil,
        branchDeviceOUI: Data? = nil,
        sinkCount: Int = 0,
        role: Int = 0,
        roleDescription: String? = nil,
        driverStatus: Int = 0,
        driverStatusDescription: String? = nil,
        transportType: Int = 0,
        transportTypeDescription: String? = nil,
        transportDescription: String? = nil,
        authorizationRequired: Bool = false,
        authorizationStatus: Int = 0,
        authorizationStatusDescription: String? = nil,
        authenticationRequired: Bool = false,
        authenticationStatus: Int = 0,
        authenticationStatusDescription: String? = nil,
        hashStatus: Int = 0,
        hashStatusDescription: String? = nil,
        trmTransportSupervised: Bool = false,
        parentPortType: Int = 0,
        parentPortTypeDescription: String? = nil,
        parentPortNumber: Int = 0,
        parentPortBuiltIn: Bool = false,
        parentBuiltInPortType: Int = 0,
        parentBuiltInPortTypeDescription: String? = nil,
        parentBuiltInPortNumber: Int = 0,
        edidChanged: Bool = false,
        nominalSignalingFrequenciesHz: [Int] = [],
        index: Int = 0,
        currentMode: DisplayCurrentMode? = nil,
        maxMode: DisplayCurrentMode? = nil,
        drivenTiming: DisplayTimingStatement? = nil,
        hpmControllerUUID: String? = nil
    ) {
        self.link = link
        self.monitor = monitor
        self.dfpType = dfpType
        self.branchDeviceId = branchDeviceId
        self.branchDeviceOUI = branchDeviceOUI
        self.sinkCount = sinkCount
        self.role = role
        self.roleDescription = roleDescription
        self.driverStatus = driverStatus
        self.driverStatusDescription = driverStatusDescription
        self.transportType = transportType
        self.transportTypeDescription = transportTypeDescription
        self.transportDescription = transportDescription
        self.authorizationRequired = authorizationRequired
        self.authorizationStatus = authorizationStatus
        self.authorizationStatusDescription = authorizationStatusDescription
        self.authenticationRequired = authenticationRequired
        self.authenticationStatus = authenticationStatus
        self.authenticationStatusDescription = authenticationStatusDescription
        self.hashStatus = hashStatus
        self.hashStatusDescription = hashStatusDescription
        self.trmTransportSupervised = trmTransportSupervised
        self.parentPortType = parentPortType
        self.parentPortTypeDescription = parentPortTypeDescription
        self.parentPortNumber = parentPortNumber
        self.parentPortBuiltIn = parentPortBuiltIn
        self.parentBuiltInPortType = parentBuiltInPortType
        self.parentBuiltInPortTypeDescription = parentBuiltInPortTypeDescription
        self.parentBuiltInPortNumber = parentBuiltInPortNumber
        self.edidChanged = edidChanged
        self.nominalSignalingFrequenciesHz = nominalSignalingFrequenciesHz
        self.index = index
        self.currentMode = currentMode
        self.maxMode = maxMode
        self.drivenTiming = drivenTiming
        self.hpmControllerUUID = hpmControllerUUID
    }

    /// `CodingKeys` lists only the serialisable fields. `hpmControllerUUID` is
    /// intentionally omitted: it is an internal join key and must never appear
    /// in JSON, text output, or any encoded representation.
    private enum CodingKeys: String, CodingKey {
        case link, monitor, dfpType, branchDeviceId, branchDeviceOUI
        case sinkCount, role, roleDescription
        case driverStatus, driverStatusDescription
        case transportType, transportTypeDescription, transportDescription
        case authorizationRequired, authorizationStatus, authorizationStatusDescription
        case authenticationRequired, authenticationStatus, authenticationStatusDescription
        case hashStatus, hashStatusDescription
        case trmTransportSupervised
        case parentPortType, parentPortTypeDescription, parentPortNumber
        case parentPortBuiltIn, parentBuiltInPortType, parentBuiltInPortTypeDescription, parentBuiltInPortNumber
        case edidChanged, nominalSignalingFrequenciesHz, index
        case currentMode, maxMode, drivenTiming
        // hpmControllerUUID is deliberately absent from this enum.
    }

    /// Custom `Decodable` implementation required because `hpmControllerUUID` is
    /// excluded from `CodingKeys`. It always decodes as `nil`; the watcher sets
    /// it at construction time via the public `init`, never via decoding.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        link = try c.decode(DisplayPortLink.self, forKey: .link)
        monitor = try c.decodeIfPresent(MonitorInfo.self, forKey: .monitor)
        dfpType = try c.decodeIfPresent(String.self, forKey: .dfpType)
        branchDeviceId = try c.decodeIfPresent(String.self, forKey: .branchDeviceId)
        branchDeviceOUI = try c.decodeIfPresent(Data.self, forKey: .branchDeviceOUI)
        sinkCount = try c.decode(Int.self, forKey: .sinkCount)
        role = try c.decode(Int.self, forKey: .role)
        roleDescription = try c.decodeIfPresent(String.self, forKey: .roleDescription)
        driverStatus = try c.decode(Int.self, forKey: .driverStatus)
        driverStatusDescription = try c.decodeIfPresent(String.self, forKey: .driverStatusDescription)
        transportType = try c.decode(Int.self, forKey: .transportType)
        transportTypeDescription = try c.decodeIfPresent(String.self, forKey: .transportTypeDescription)
        transportDescription = try c.decodeIfPresent(String.self, forKey: .transportDescription)
        authorizationRequired = try c.decode(Bool.self, forKey: .authorizationRequired)
        authorizationStatus = try c.decode(Int.self, forKey: .authorizationStatus)
        authorizationStatusDescription = try c.decodeIfPresent(String.self, forKey: .authorizationStatusDescription)
        authenticationRequired = try c.decode(Bool.self, forKey: .authenticationRequired)
        authenticationStatus = try c.decode(Int.self, forKey: .authenticationStatus)
        authenticationStatusDescription = try c.decodeIfPresent(String.self, forKey: .authenticationStatusDescription)
        hashStatus = try c.decode(Int.self, forKey: .hashStatus)
        hashStatusDescription = try c.decodeIfPresent(String.self, forKey: .hashStatusDescription)
        trmTransportSupervised = try c.decode(Bool.self, forKey: .trmTransportSupervised)
        parentPortType = try c.decode(Int.self, forKey: .parentPortType)
        parentPortTypeDescription = try c.decodeIfPresent(String.self, forKey: .parentPortTypeDescription)
        parentPortNumber = try c.decode(Int.self, forKey: .parentPortNumber)
        parentPortBuiltIn = try c.decode(Bool.self, forKey: .parentPortBuiltIn)
        parentBuiltInPortType = try c.decode(Int.self, forKey: .parentBuiltInPortType)
        parentBuiltInPortTypeDescription = try c.decodeIfPresent(String.self, forKey: .parentBuiltInPortTypeDescription)
        parentBuiltInPortNumber = try c.decode(Int.self, forKey: .parentBuiltInPortNumber)
        edidChanged = try c.decode(Bool.self, forKey: .edidChanged)
        nominalSignalingFrequenciesHz = try c.decode([Int].self, forKey: .nominalSignalingFrequenciesHz)
        index = try c.decode(Int.self, forKey: .index)
        currentMode = try c.decodeIfPresent(DisplayCurrentMode.self, forKey: .currentMode)
        maxMode = try c.decodeIfPresent(DisplayCurrentMode.self, forKey: .maxMode)
        drivenTiming = try c.decodeIfPresent(DisplayTimingStatement.self, forKey: .drivenTiming)
        // hpmControllerUUID is internal only; always nil when decoded from persisted data.
        hpmControllerUUID = nil
    }
}

extension IOPortTransportStateDisplayPort {
    /// Join key to the owning USB-C / MagSafe port. The DisplayPort node
    /// reports its parent as `ParentPortType` (2 = USB-C, 0x11 = MagSafe) and
    /// `ParentPortNumber`, the same scheme `PowerSource.portKey` and
    /// `AppleHPMInterface.portKey` use, so `"\(type)/\(number)"` matches a
    /// port directly. Confirmed against probe 17 (ParentPortType 2 /
    /// ParentPortNumber 4 for the active "Port-USB-C" display).
    public var portKey: String { "\(parentPortType)/\(parentPortNumber)" }

    /// Canonical in-session join key: normalised UUID when captured, else portKey.
    /// Internal only; never expose in JSON or text output.
    public var canonicalJoinKey: String {
        if let uuid = hpmControllerUUID {
            let n = uuid.replacingOccurrences(of: "-", with: "").lowercased()
            if n.count == 32 { return n }
        }
        return portKey
    }

    /// True when this DisplayPort node belongs to the same physical port as `port`.
    /// UUID-keyed when both sides have a UUID, portKey fallback otherwise.
    public func canonicallyMatches(port: AppleHPMInterface) -> Bool {
        guard let portKey = port.portKey else { return false }
        if let srcUUID = hpmControllerUUID, let portUUID = port.hpmControllerUUID {
            let sn = srcUUID.replacingOccurrences(of: "-", with: "").lowercased()
            let pn = portUUID.replacingOccurrences(of: "-", with: "").lowercased()
            if sn.count == 32 && pn.count == 32 { return sn == pn }
        }
        return self.portKey == portKey
    }
}

@available(*, deprecated, renamed: "IOPortTransportStateDisplayPort")
public typealias DisplayPortStatus = IOPortTransportStateDisplayPort
