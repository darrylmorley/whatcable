import Foundation

/// Physical layer state for one USB-C port. One instance per physical port
/// on the machine (4 on M4 Pro). Read from `AppleT8132TypeCPhy` IOKit
/// services. Provides per-lane transport mode, the only way to determine
/// whether a port is using CIO (Thunderbolt), DisplayPort alt-mode, or both.
public struct AppleTypeCPhy: Identifiable, Hashable, Equatable, Sendable {
    /// AppleTypeCPhyID (port index 0-3).
    public let id: Int
    /// Per-lane state. Typically 2 lanes (Lane 0 and Lane 1).
    public let lanes: [PhyLane]
    /// USB 2.0 transport state on this port.
    public let usb2: PhyUSB2?
    /// DisplayPort pixel clock info when DP is active.
    public let displayPortPclk: PhyDisplayPortPclk?
    /// DP tunnel state string.
    public let displayPortTunnel: String?

    public init(
        id: Int,
        lanes: [PhyLane],
        usb2: PhyUSB2? = nil,
        displayPortPclk: PhyDisplayPortPclk? = nil,
        displayPortTunnel: String? = nil
    ) {
        self.id = id
        self.lanes = lanes
        self.usb2 = usb2
        self.displayPortPclk = displayPortPclk
        self.displayPortTunnel = displayPortTunnel
    }

    /// True when at least one lane carries CIO (Thunderbolt/USB4).
    public var hasCIO: Bool {
        lanes.contains { $0.transport == "CIO" }
    }

    /// True when at least one lane carries DisplayPort.
    public var hasDisplayPort: Bool {
        lanes.contains { $0.transport == "DisplayPort" }
    }

    /// True when all lanes are idle (no transport assigned).
    public var isIdle: Bool {
        lanes.allSatisfy { $0.transport.isEmpty || $0.powerLevel != "on" }
    }

    /// Number of lanes actively carrying CIO.
    public var cioLaneCount: Int {
        lanes.filter { $0.transport == "CIO" && $0.powerLevel == "on" }.count
    }

    /// Number of lanes actively carrying DisplayPort.
    public var dpLaneCount: Int {
        lanes.filter { $0.transport == "DisplayPort" && $0.powerLevel == "on" }.count
    }
}

/// State of a single physical lane on the USB-C PHY.
public struct PhyLane: Hashable, Sendable {
    /// Lane index (0 or 1).
    public let index: Int
    /// Transport protocol: "CIO", "DisplayPort", "USB3", or empty string for idle.
    public let transport: String
    /// Power state: "on" or empty string for off.
    public let powerLevel: String
    /// Driver client name (e.g. "AppleThunderboltNHIType7").
    public let client: String

    public init(index: Int, transport: String, powerLevel: String, client: String) {
        self.index = index
        self.transport = transport
        self.powerLevel = powerLevel
        self.client = client
    }
}

/// USB 2.0 transport state on the PHY.
public struct PhyUSB2: Hashable, Sendable {
    public let transport: String
    public let client: String

    public init(transport: String, client: String) {
        self.transport = transport
        self.client = client
    }

    public var isActive: Bool { !transport.isEmpty }
}

/// DisplayPort pixel clock information from the PHY.
public struct PhyDisplayPortPclk: Hashable, Sendable {
    /// Link rate string, e.g. "5.40Gbps/lane (HBR2)".
    public let linkRate: String

    public init(linkRate: String) {
        self.linkRate = linkRate
    }
}

@available(*, deprecated, renamed: "AppleTypeCPhy")
public typealias TypeCPhy = AppleTypeCPhy
