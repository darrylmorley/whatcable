import Foundation

// MARK: - Generation / width / adapter enums
//
// These decode the raw IOKit field values into Swift cases. Encoding is
// anchored against Linux's `drivers/thunderbolt/tb_regs.h`, which describes
// the same USB4 lane-adapter registers Apple's IOThunderbolt fields appear
// to mirror. See planning/thunderbolt-fabric.md for the field-by-field
// reasoning and the contributor samples that confirmed the mapping for
// TB3 and TB4 / USB4. TB5 (raw speed code 0x2) is supported in the model
// but the renderer should not produce a TB5 label until we have a real
// sample — the `LinkGeneration.unknown(rawSpeedCode:)` escape hatch
// exists for exactly that.

/// Negotiated lane-rate generation for a Thunderbolt link.
/// Decoded from `Current Link Speed` on a TB-protocol port (Adapter Type = 1).
public enum LinkGeneration: Hashable {
    /// Speed code `0x8`. 10 Gb/s per lane.
    case tb3
    /// Speed code `0x4`. 20 Gb/s per lane. Used by both USB4 v1 and TB4.
    /// IOKit doesn't (as far as we've seen) distinguish the two; the
    /// renderer treats them as one bucket.
    case usb4Tb4
    /// Speed code `0x2`. 40 Gb/s per lane. USB4 v2 / TB5.
    /// Inferred from Linux register definitions; not yet verified against
    /// an Apple Silicon TB5 hardware sample.
    case tb5
    /// Speed code we don't have a mapping for. Forward-compat: future
    /// generations or unexpected encodings won't break the model.
    case unknown(rawSpeedCode: UInt8)

    /// Per-lane Gb/s for the known cases. `nil` for `.unknown`.
    public var perLaneGbps: Int? {
        switch self {
        case .tb3: return 10
        case .usb4Tb4: return 20
        case .tb5: return 40
        case .unknown: return nil
        }
    }

    /// Build from a raw `Current Link Speed` register value.
    /// `0` (idle) returns `nil`; the caller treats that as "no link".
    public static func from(rawSpeedCode: UInt8) -> LinkGeneration? {
        switch rawSpeedCode {
        case 0x0: return nil
        case 0x8: return .tb3
        case 0x4: return .usb4Tb4
        case 0x2: return .tb5
        default: return .unknown(rawSpeedCode: rawSpeedCode)
        }
    }
}

/// Bitmask decoding of `Current Link Speed` (a single value) for use as
/// a bitmask on `Supported Link Speed`. Each bit set indicates the
/// controller can negotiate that generation. We keep this as a raw struct
/// so future generations are representable without a model change.
public struct SupportedSpeedMask: Hashable {
    public let supportsTb3: Bool      // bit 0x8
    public let supportsUsb4Tb4: Bool  // bit 0x4
    public let supportsTb5: Bool      // bit 0x2
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
        self.supportsTb3 = (rawValue & 0x8) != 0
        self.supportsUsb4Tb4 = (rawValue & 0x4) != 0
        self.supportsTb5 = (rawValue & 0x2) != 0
    }
}

/// Decode of `Current Link Width`. This is a bitmask in the Linux model
/// (`enum tb_link_width`); preserve it as separate flags so a future TB5
/// asymmetric link is representable without refactoring.
public struct LinkWidth: Hashable {
    public let single: Bool        // bit 0x1
    public let dual: Bool          // bit 0x2
    public let asymmetricTx: Bool  // bit 0x4 (3 TX / 1 RX)
    public let asymmetricRx: Bool  // bit 0x8 (1 TX / 3 RX)
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
        self.single = (rawValue & 0x1) != 0
        self.dual = (rawValue & 0x2) != 0
        self.asymmetricTx = (rawValue & 0x4) != 0
        self.asymmetricRx = (rawValue & 0x8) != 0
    }

    /// Number of active TX lanes.
    /// `1` for single, `2` for dual, `3` for asymmetric TX, `1` for asymmetric RX.
    public var txLanes: Int {
        if asymmetricTx { return 3 }
        if asymmetricRx { return 1 }
        if dual { return 2 }
        if single { return 1 }
        return 0
    }

    /// Number of active RX lanes.
    public var rxLanes: Int {
        if asymmetricRx { return 3 }
        if asymmetricTx { return 1 }
        if dual { return 2 }
        if single { return 1 }
        return 0
    }

    /// Whether any lane is active.
    public var isActive: Bool { rawValue != 0 }
}

/// Decode of `Target Link Width`. Different encoding to Current Link Width:
/// Linux defines `LANE_ADP_CS_1_TARGET_WIDTH_SINGLE = 0x1` and
/// `LANE_ADP_CS_1_TARGET_WIDTH_DUAL = 0x3`. So `0x3` here means "negotiated
/// dual lane", NOT "asymmetric". This was a footgun in the planning phase.
public enum TargetLinkWidth: Hashable {
    case single
    case dual
    case unknown(rawValue: UInt8)

    public static func from(rawValue: UInt8) -> TargetLinkWidth? {
        switch rawValue {
        case 0: return nil
        case 0x1: return .single
        case 0x3: return .dual
        default: return .unknown(rawValue: rawValue)
        }
    }
}

/// Type of adapter on a Thunderbolt port. Each switch has lane adapters
/// (the actual TB ports) plus protocol adapters that tunnel DP, PCIe, and
/// USB3 over the fabric. Encoding 1:1 with Linux `tb_regs.h` adapter types.
///
/// The `down` / `up` distinction is the adapter's role relative to its
/// **local** router, not a global host-side / device-side label. In a
/// daisy-chain, a middle switch has both.
public enum AdapterType: Hashable {
    case inactive       // 0x000000
    case lane           // 0x000001 — physical TB port
    case nhi            // 0x000002 — host interface (only on root switches)
    case dpIn           // 0x0e0101
    case dpOut          // 0x0e0102
    case pcieDown       // 0x100101
    case pcieUp         // 0x100102
    case usb3Down       // 0x200101
    case usb3Up         // 0x200102
    case other(UInt32)

    public static func from(rawValue: UInt32) -> AdapterType {
        switch rawValue {
        case 0x000000: return .inactive
        case 0x000001: return .lane
        case 0x000002: return .nhi
        case 0x0e0101: return .dpIn
        case 0x0e0102: return .dpOut
        case 0x100101: return .pcieDown
        case 0x100102: return .pcieUp
        case 0x200101: return .usb3Down
        case 0x200102: return .usb3Up
        default: return .other(rawValue)
        }
    }

    /// True for the lane (physical TB) adapter. Used to select ports that
    /// actually carry a Thunderbolt link, as opposed to the protocol
    /// tunnels above.
    public var isLane: Bool {
        if case .lane = self { return true }
        return false
    }
}

// MARK: - Switch and port models

/// One Thunderbolt switch in the fabric. Could be a host root (Depth=0)
/// or a downstream device's internal switch (Depth>0).
public struct ThunderboltSwitch: Identifiable, Hashable {
    public let id: Int64                    // UID (signed Int64; can be negative)
    public let className: String            // raw IOKit class
    public let vendorID: Int
    public let vendorName: String
    public let modelName: String
    public let routerID: Int                // 0 on the first host root
    public let depth: Int                   // hops from host (0 = root)
    public let routeString: Int64           // path encoding (one byte per hop)
    public let upstreamPortNumber: Int
    public let maxPortNumber: Int
    public let supportedSpeed: SupportedSpeedMask
    public let ports: [ThunderboltPort]
    /// Parent switch UID, populated by the watcher via the IOKit parent
    /// chain. `nil` on host roots. Phase 3 (rendering) uses this to walk
    /// the topology without re-parsing Route String / Hop Table.
    public let parentSwitchUID: Int64?

    public init(
        id: Int64,
        className: String,
        vendorID: Int,
        vendorName: String,
        modelName: String,
        routerID: Int,
        depth: Int,
        routeString: Int64,
        upstreamPortNumber: Int,
        maxPortNumber: Int,
        supportedSpeed: SupportedSpeedMask,
        ports: [ThunderboltPort],
        parentSwitchUID: Int64?
    ) {
        self.id = id
        self.className = className
        self.vendorID = vendorID
        self.vendorName = vendorName
        self.modelName = modelName
        self.routerID = routerID
        self.depth = depth
        self.routeString = routeString
        self.upstreamPortNumber = upstreamPortNumber
        self.maxPortNumber = maxPortNumber
        self.supportedSpeed = supportedSpeed
        self.ports = ports
        self.parentSwitchUID = parentSwitchUID
    }

    /// Build a `ThunderboltSwitch` from a raw IOKit property dictionary
    /// plus a list of already-parsed child ports. Returns `nil` if the
    /// dictionary is missing the minimum identifying fields (UID + Vendor ID).
    /// Lives here in `WhatCableCore` so it can be exercised against fixture
    /// data without IOKit, mirroring the `USBCPort.from(...)` pattern.
    public static func from(
        properties: [String: Any],
        className: String,
        ports: [ThunderboltPort],
        parentSwitchUID: Int64? = nil
    ) -> ThunderboltSwitch? {
        guard let uidNum = properties["UID"] as? NSNumber else { return nil }
        guard let vendorIDNum = properties["Vendor ID"] as? NSNumber else { return nil }

        let speedMaskRaw = (properties["Supported Link Speed"] as? NSNumber)?.uint8Value ?? 0
        return ThunderboltSwitch(
            id: uidNum.int64Value,
            className: className,
            vendorID: vendorIDNum.intValue,
            vendorName: (properties["Device Vendor Name"] as? String) ?? "",
            modelName: (properties["Device Model Name"] as? String) ?? "",
            routerID: (properties["Router ID"] as? NSNumber)?.intValue ?? 0,
            depth: (properties["Depth"] as? NSNumber)?.intValue ?? 0,
            routeString: (properties["Route String"] as? NSNumber)?.int64Value ?? 0,
            upstreamPortNumber: (properties["Upstream Port Number"] as? NSNumber)?.intValue ?? 0,
            maxPortNumber: (properties["Max Port Number"] as? NSNumber)?.intValue ?? 0,
            supportedSpeed: SupportedSpeedMask(rawValue: speedMaskRaw),
            ports: ports,
            parentSwitchUID: parentSwitchUID
        )
    }

    /// True for switches the host owns directly (Depth=0).
    public var isHostRoot: Bool { depth == 0 }
}

/// One adapter on a Thunderbolt switch. Could be a physical TB lane port
/// (with link-state fields) or a protocol-tunnel adapter (DP, PCIe, USB3).
public struct ThunderboltPort: Hashable {
    public let portNumber: Int
    /// String form of `Socket ID`, present on TB-protocol ports.
    /// Matches the `@N` suffix on a root host's USB-C port for the
    /// host-port-to-switch correlation key.
    public let socketID: String?
    public let adapterType: AdapterType
    /// Decoded `Current Link Speed`. `nil` on idle ports or non-lane adapters.
    public let currentSpeed: LinkGeneration?
    /// Decoded `Current Link Width`. `nil` on non-lane adapters; on idle
    /// lane ports, `LinkWidth.isActive` will be false.
    public let currentWidth: LinkWidth?
    public let targetWidth: TargetLinkWidth?
    /// Per-lane Gb/s if we have a known generation, else `nil`. Convenience
    /// derived from `currentSpeed` so renderers don't need to switch on it.
    public let perLaneGbps: Int?
    public let txLanes: Int?
    public let rxLanes: Int?
    /// Raw `Target Link Speed`. Don't interpret this as a bitmask in the
    /// renderer; Linux defines it as a single named value
    /// (e.g. `LANE_ADP_CS_1_TARGET_SPEED_GEN3 = 0xc`). Kept raw for
    /// diagnostics.
    public let rawTargetSpeed: UInt8?
    /// Raw `Link Bandwidth`. Unitless aggregate that scales with active
    /// lanes; useful for diagnostics, not for user-facing labels.
    public let linkBandwidthRaw: Int?

    public init(
        portNumber: Int,
        socketID: String?,
        adapterType: AdapterType,
        currentSpeed: LinkGeneration?,
        currentWidth: LinkWidth?,
        targetWidth: TargetLinkWidth?,
        rawTargetSpeed: UInt8?,
        linkBandwidthRaw: Int?
    ) {
        self.portNumber = portNumber
        self.socketID = socketID
        self.adapterType = adapterType
        self.currentSpeed = currentSpeed
        self.currentWidth = currentWidth
        self.targetWidth = targetWidth
        self.perLaneGbps = currentSpeed?.perLaneGbps
        self.txLanes = currentWidth?.txLanes
        self.rxLanes = currentWidth?.rxLanes
        self.rawTargetSpeed = rawTargetSpeed
        self.linkBandwidthRaw = linkBandwidthRaw
    }

    /// Build a port from a raw IOKit property dictionary.
    public static func from(properties: [String: Any]) -> ThunderboltPort? {
        guard let portNumNum = properties["Port Number"] as? NSNumber else { return nil }
        let adapterRaw = (properties["Adapter Type"] as? NSNumber)?.uint32Value ?? 0
        let adapter = AdapterType.from(rawValue: adapterRaw)

        // Socket ID is stored as a string in IOKit (e.g. "1", "2"). It
        // appears on TB-protocol ports only.
        let socketID = properties["Socket ID"] as? String

        let speedRaw = (properties["Current Link Speed"] as? NSNumber)?.uint8Value ?? 0
        let widthRaw = (properties["Current Link Width"] as? NSNumber)?.uint8Value ?? 0
        let targetWidthRaw = (properties["Target Link Width"] as? NSNumber)?.uint8Value ?? 0
        let targetSpeedRaw = (properties["Target Link Speed"] as? NSNumber)?.uint8Value

        // Only populate link state on actual lane ports. Protocol
        // adapters (DP, PCIe, USB3) don't carry link generation; their
        // tunnel state is exposed via Hop Table, which we ignore in v1.
        let currentSpeed: LinkGeneration?
        let currentWidth: LinkWidth?
        let targetWidth: TargetLinkWidth?
        if adapter.isLane {
            currentSpeed = LinkGeneration.from(rawSpeedCode: speedRaw)
            currentWidth = LinkWidth(rawValue: widthRaw)
            targetWidth = TargetLinkWidth.from(rawValue: targetWidthRaw)
        } else {
            currentSpeed = nil
            currentWidth = nil
            targetWidth = nil
        }

        return ThunderboltPort(
            portNumber: portNumNum.intValue,
            socketID: socketID,
            adapterType: adapter,
            currentSpeed: currentSpeed,
            currentWidth: currentWidth,
            targetWidth: targetWidth,
            rawTargetSpeed: targetSpeedRaw,
            linkBandwidthRaw: (properties["Link Bandwidth"] as? NSNumber)?.intValue
        )
    }

    /// True for a TB lane port that has actually negotiated a link.
    /// Useful for the renderer when picking which port to label.
    public var hasActiveLink: Bool {
        guard adapterType.isLane else { return false }
        guard let currentWidth, currentWidth.isActive else { return false }
        return currentSpeed != nil
    }
}
