import Foundation

// MARK: - Generation / width / adapter enums
//
// These decode the raw IOKit field values into Swift cases. Encoding is
// anchored against Linux's `drivers/thunderbolt/tb_regs.h`, which describes
// the same USB4 lane-adapter registers Apple's IOThunderbolt fields appear
// to mirror. See planning/thunderbolt-fabric.md for the field-by-field
// reasoning and the contributor samples that confirmed the mapping for
// TB3, TB4 / USB4, and TB5. TB5 (raw speed code 0x2) was confirmed against
// an M5 Pro + UGreen JHL9580 dock paste-back on issue #52.

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
    /// Confirmed via M5 Pro + UGreen JHL9580 dock paste-back on issue #52
    /// (system_profiler reports "Mode: USB4 v2, Speed: 120 Gb/s" for the
    /// same active link).
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

    /// Headline symmetric dual-lane Gb/s for the known cases: TB3 = 20,
    /// TB4 / USB4 v1 = 40, TB5 / USB4 v2 = 80. `nil` for `.unknown`. The
    /// link rate is per-lane Gbps times lane count, corpus-confirmed
    /// against `Link Bandwidth` without exception (see `activeGbps` on
    /// `IOThunderboltPort` for the width-aware figure); this property
    /// assumes the generation's own dual-lane case. Asymmetric mode
    /// (TB5 120/40) and trained-down lane widths are deliberately not
    /// modelled here.
    public var totalGbps: Double? {
        switch self {
        case .tb3: return 20
        case .usb4Tb4: return 40
        case .tb5: return 80
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

    /// Per-lane Gb/s of the highest supported generation: TB5 / USB4 v2 = 40,
    /// TB4 / USB4 v1 = 20, TB3 = 10. Nil if the mask is empty or has only
    /// unrecognised bits. A mask carrying only the Gen 2 (TB3) bit is Gen 2
    /// silicon, not a 40 Gbps TB3 host: every 40 Gbps TB3 host also sets the
    /// Gen 3 (TB4/USB4) bit, so it is caught by `supportsUsb4Tb4` above that
    /// check.
    public var maxPerLaneGbps: Int? {
        if supportsTb5 { return 40 }
        if supportsUsb4Tb4 { return 20 }
        if supportsTb3 { return 10 }
        return nil
    }

    /// `maxPerLaneGbps` times a trained lane count. Nil when the mask is
    /// unrecognised or `lanes` is not positive. Callers that know the width
    /// (`LinkWidth.txLanes` / `rxLanes`) use this rather than the dual-lane
    /// headline.
    public func maxTotalGbps(lanes: Int) -> Double? {
        guard let perLane = maxPerLaneGbps, lanes > 0 else { return nil }
        return Double(perLane) * Double(lanes)
    }

    /// Symmetric dual-lane headline Gbps for the highest supported
    /// generation: TB3 = 20, TB4 / USB4 v1 = 40, TB5 / USB4 v2 = 80. Nil if
    /// the mask is empty or has only unrecognised bits. This is NOT a ceiling
    /// on a live TB5 link: asymmetric mode trains 3 TX lanes at 40 Gb/s per
    /// lane, so this reads 80 on a link carrying 120 out of the Mac
    /// (research/customer-probes/m5max_macos26.5.1 host Socket 1 port 1:
    /// Current Link Width 4, Supported Link Width 2, Link Bandwidth 400).
    /// `Supported Link Width` reads 2 (dual) on both ends of that link, so
    /// nothing in the registers advertises the 3-lane mode; callers that know
    /// the trained width use `maxTotalGbps(lanes:)`.
    public var maxTotalGbps: Double? {
        maxTotalGbps(lanes: 2)
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

/// Decode of `Target Link Width`. Different encoding to Current Link Width,
/// as a simplification rather than a strict rule: Linux defines
/// `LANE_ADP_CS_1_TARGET_WIDTH_SINGLE = 0x1` and
/// `LANE_ADP_CS_1_TARGET_WIDTH_DUAL = 0x3`, so `0x3` here means "negotiated
/// dual lane", NOT "asymmetric" (this was a footgun in the planning phase).
/// But corpus-measured over 9313 lane adapters, value 5 is also observed
/// twice (m5pro_macos26.5_b port 1 on a live symmetric Gen 4 link, and
/// m5max_macos26.5.1 port 1 on an asymmetricTx one), plus one port in
/// research/dumps/tb-fabric/052-nofr1ends-m5pro-ugreen-tb5-dock.md. It
/// reads as `single | asymmetricTx` under the Current Link Width bitmask,
/// and the same capture's asymmetricRx port reads 9, fitting the same
/// reading. `from` already returns `.unknown(5)` and `.unknown(9)` for
/// these, unchanged here.
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
    /// TB5-era USB tunneling adapter, distinct from the USB3 adapter
    /// types above. Confirmed on an M5 Pro + Ugreen TB5 dock (issue
    /// #52 paste-back, `research/dumps/tb-fabric/052-nofr1ends-m5pro-
    /// ugreen-tb5-dock.md` lines 215-217): `Adapter Type = 2162945`,
    /// `Description = "USB Gen T Adapter"`.
    case usbGenTDown     // 0x210101
    case usbGenTUp       // 0x210102
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
        case 0x210101: return .usbGenTDown
        case 0x210102: return .usbGenTUp
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
public struct IOThunderboltSwitch: Identifiable, Hashable {
    /// Hardware UID (signed Int64; can be negative). A stable per-device
    /// identifier: internal join key ONLY. Never serialise it into JSON,
    /// --raw, or any user-facing output; use a per-snapshot array index
    /// instead (see `IOThunderboltSwitchDTO`).
    public let id: Int64
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
    public let ports: [IOThunderboltPort]
    /// Parent switch UID, populated by the watcher via the IOKit parent
    /// chain. `nil` on host roots. Phase 3 (rendering) uses this to walk
    /// the topology without re-parsing Route String / Hop Table.
    public let parentSwitchUID: Int64?
    /// CIO firmware version string with build date and chip ID.
    public let firmwareVersion: String?
    /// Controller-class constant, not a per-link value: Apple Type5 = 32
    /// (TB4-class), Apple Type7 = 64 (TB5-capable), Type3 = 16. Do not use
    /// for link-generation labels. See `research/thunderbolt-fabric.md`.
    public let thunderboltVersion: Int?
    /// Controller chip device ID.
    public let deviceID: Int?
    /// Current power state (0 = sleeping, 2 = active).
    public let currentPowerState: Int?
    /// Firmware event counters (binary blob, 348 bytes).
    public let fwCounters: Data?
    /// Lifetime firmware event totals (binary blob, 348 bytes).
    public let fwCountersRunningTotal: Data?
    /// Device ROM topology descriptor.
    public let drom: Data?
    /// Time Management Unit mode requirement.
    public let minRequiredTMUMode: Int?
    /// The DROM's own numeric `Device Vendor ID`, e.g. `0x174c` for OWC.
    /// NOT the same field as `vendorID` above (that one reads the registry's
    /// plain `Vendor ID` key, the PCIe/controller chip vendor, which for a
    /// dock's downstream switch is often the SILICON vendor rather than the
    /// dock's own brand). This is the accessory identity number used for the
    /// #493 numeric-first join: a native USB endpoint's `idVendor` matching
    /// this exactly is strong evidence the endpoint IS this chain device.
    /// `nil` whenever the raw registry value is not a plausible USB
    /// vendor/product id: non-positive, or above `UInt16.max` (a real ID is
    /// always a 16-bit number; a raw 0 or a negative/oversized value is a
    /// missing or garbage read, never a real accessory identity). Normalised
    /// at parse time in `from(...)` below, not left for every caller to
    /// re-check, because a 0 here matched against a similarly-zeroed USB
    /// `idVendor`/`idProduct` (both defaulted on a failed descriptor read)
    /// would otherwise look like a real exact match. See issue #493 round 5.
    public let dromVendorID: Int?
    /// The DROM's own numeric `Device Model ID`, e.g. `0x2465` for the OWC
    /// Express 1M2. Paired with `dromVendorID` for the exact-identity check;
    /// see that property's doc for why it is a distinct field from
    /// `deviceID` above, and for the same non-positive/out-of-range-is-nil
    /// normalisation.
    public let dromModelID: Int?
    /// The `acioN` Thunderbolt HAL root name (e.g. `"acio2"`) this HOST ROOT
    /// switch sits under, captured by walking the IOService plane past the
    /// point where no further Thunderbolt-switch ancestor exists. `nil` for
    /// every downstream (non-host-root) switch, whose ancestor walk always
    /// stops at its parent switch first, and `nil` for a host root when the
    /// walk's bound was exceeded before reaching `acioN` (should not happen
    /// in practice: the corpus never needed more than a few hops).
    ///
    /// This is the port-scoping half of the apciec<->acio join
    /// (`research/usb-chain-attribution-identifiers.md`): Apple Silicon
    /// exposes each Thunderbolt port as two sibling roots sharing one index N,
    /// `apciecN` (the PCIe tunnel, captured on `USBDevice.tunnelRootName`) and
    /// `acioN` (the Thunderbolt HAL, captured here). `ThunderboltTopology
    /// .apciecRootName(fromAcioRootName:)` converts one to the other so a
    /// tunnelled device's own `tunnelRootName` can be checked against the
    /// port whose host root this is. Verified end to end on
    /// `research/customer-probes/m3pro_macos27.0_l`: the host root under
    /// `acio2` (UID `0x5acfe0e539a3992`) is the one whose downstream chain
    /// carries the LaCie 1big and Studio Display, both reporting
    /// `tunnelRootName == "apciec2"`.
    public let acioRootName: String?
    /// Raw `USB Port Map` property: triplets of
    /// `(USB4 port, ?, 0x80 | USB3 adapter number)` that pair a switch's
    /// downstream USB4 ports with its own USB3 adapter numbers. Kept as raw
    /// `Data` here and parsed in `USBPortMapEntry.parse(_:)` in Core, so a
    /// probe-text replay can hand it straight in without any IOKit type.
    /// `nil` when the switch does not publish the property (older captures)
    /// or the read failed. See `USBPortMapEntry` for the triplet format and
    /// `ChainDeviceAttribution`'s TB5 tunnel-hub pass for how it is used.
    public let usbPortMap: Data?

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
        ports: [IOThunderboltPort],
        parentSwitchUID: Int64?,
        firmwareVersion: String? = nil,
        thunderboltVersion: Int? = nil,
        deviceID: Int? = nil,
        currentPowerState: Int? = nil,
        fwCounters: Data? = nil,
        fwCountersRunningTotal: Data? = nil,
        drom: Data? = nil,
        minRequiredTMUMode: Int? = nil,
        dromVendorID: Int? = nil,
        dromModelID: Int? = nil,
        acioRootName: String? = nil,
        usbPortMap: Data? = nil
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
        self.firmwareVersion = firmwareVersion
        self.thunderboltVersion = thunderboltVersion
        self.deviceID = deviceID
        self.currentPowerState = currentPowerState
        self.fwCounters = fwCounters
        self.fwCountersRunningTotal = fwCountersRunningTotal
        self.drom = drom
        self.minRequiredTMUMode = minRequiredTMUMode
        self.dromVendorID = dromVendorID
        self.dromModelID = dromModelID
        self.acioRootName = acioRootName
        self.usbPortMap = usbPortMap
    }

    /// Build a `IOThunderboltSwitch` from a raw IOKit property dictionary
    /// plus a list of already-parsed child ports. Returns `nil` if the
    /// dictionary is missing the minimum identifying fields (UID + Vendor ID).
    /// Lives here in `WhatCableCore` so it can be exercised against fixture
    /// data without IOKit, mirroring the `AppleHPMInterface.from(...)` pattern.
    /// Build from a parsed IOKit property dictionary.
    /// `uid` is passed explicitly by the caller (who already read it to build
    /// the UID lookup table) so the factory does not make a second IOKit
    /// round-trip for the same key.
    public static func from(
        uid: Int64,
        read: (String) -> Any?,
        className: String,
        ports: [IOThunderboltPort],
        parentSwitchUID: Int64? = nil,
        acioRootName: String? = nil
    ) -> IOThunderboltSwitch? {
        guard let vendorIDNum = read("Vendor ID") as? NSNumber else { return nil }

        // `Supported Link Speed` is per-port on the IOKit side (Apple
        // Silicon, M3-M5+ confirmed). The switch object itself does not
        // carry the property. Try the switch first for compatibility with
        // any platform that did expose it there; if zero, OR together every
        // lane port's mask. Lane ports on a given switch all advertise the
        // same capability, but ORing is harmless and forward-safe.
        let switchLevelMask = (read("Supported Link Speed") as? NSNumber)?.uint8Value ?? 0
        let speedMaskRaw: UInt8 = {
            if switchLevelMask != 0 { return switchLevelMask }
            var agg: UInt8 = 0
            for p in ports where p.adapterType.isLane {
                agg |= p.supportedSpeed?.rawValue ?? 0
            }
            return agg
        }()

        let powerState: Int?
        if let pmDict = read("IOPowerManagement") as? [String: Any] {
            powerState = (pmDict["CurrentPowerState"] as? NSNumber)?.intValue
        } else {
            powerState = nil
        }

        // A real USB vendor/product id is always in 1...UInt16.max. Zero
        // (the default USBWatcher falls back to on a failed descriptor read,
        // see Sources/WhatCableDarwinBackend/Watchers/USBWatcher.swift) or a
        // negative/oversized registry value is not a real accessory
        // identity, so it is normalised to nil right here rather than left
        // for every caller of `dromVendorID`/`dromModelID` to re-check.
        func validDROMNumber(_ key: String) -> Int? {
            guard let value = (read(key) as? NSNumber)?.intValue,
                  value > 0, value <= Int(UInt16.max)
            else { return nil }
            return value
        }

        return IOThunderboltSwitch(
            id: uid,
            className: className,
            vendorID: vendorIDNum.intValue,
            vendorName: (read("Device Vendor Name") as? String) ?? "",
            modelName: (read("Device Model Name") as? String) ?? "",
            routerID: (read("Router ID") as? NSNumber)?.intValue ?? 0,
            depth: (read("Depth") as? NSNumber)?.intValue ?? 0,
            routeString: (read("Route String") as? NSNumber)?.int64Value ?? 0,
            upstreamPortNumber: (read("Upstream Port Number") as? NSNumber)?.intValue ?? 0,
            maxPortNumber: (read("Max Port Number") as? NSNumber)?.intValue ?? 0,
            supportedSpeed: SupportedSpeedMask(rawValue: speedMaskRaw),
            ports: ports,
            parentSwitchUID: parentSwitchUID,
            firmwareVersion: read("Firmware Version") as? String,
            thunderboltVersion: (read("Thunderbolt Version") as? NSNumber)?.intValue,
            deviceID: (read("Device ID") as? NSNumber)?.intValue,
            currentPowerState: powerState,
            fwCounters: read("FW Counters") as? Data,
            fwCountersRunningTotal: read("FW Counters Running Total") as? Data,
            drom: read("DROM") as? Data,
            minRequiredTMUMode: (read("Min Required TMU Mode") as? NSNumber)?.intValue,
            // Registry key names verified against
            // research/customer-probes/m3pro_macos27.0_l/29_usb4_router_interfaces.json:
            // the OWC Express 1M2 switch block carries
            // `Device Vendor ID = 5964 (0x174c)` and
            // `Device Model ID = 9317 (0x2465)`, exactly matching that same
            // machine's USB endpoint `idVendor`/`idProduct`.
            dromVendorID: validDROMNumber("Device Vendor ID"),
            dromModelID: validDROMNumber("Device Model ID"),
            acioRootName: acioRootName,
            usbPortMap: read("USB Port Map") as? Data
        )
    }

    /// True for switches the host owns directly (Depth=0).
    public var isHostRoot: Bool { depth == 0 }

    /// True when the controller is in an active power state.
    public var isAwake: Bool { currentPowerState == 2 }

    /// TB1/TB2-era device IDs whose `Current Link Speed` code `0x8` does
    /// NOT mean a real link at the code's headline rate (issue #515). Intel
    /// Falcon Ridge, the TB2 controller. `Thunderbolt Version == 2` is not
    /// used for this: it mixes real TB2 devices with TB3 controllers
    /// (Alpine Ridge etc), so the cap is keyed on Device ID here instead.
    /// Device ID alone is not a safe key across vendors (the same 16-bit
    /// number can be reused outside Intel's own device space), so the
    /// match also requires `Vendor ID == 0x8086` (Intel, decimal 32902,
    /// confirmed in the corpus). Verified against the pci.ids database
    /// (https://pci-ids.ucw.cz/read/PC/8086, checked 2026-09-10): 0x156c is
    /// "DSL5520 Thunderbolt 2 NHI [Falcon Ridge 4C 2013]" and 0x156d is
    /// "DSL5520 Thunderbolt 2 Bridge [Falcon Ridge 4C 2013]".
    private static let falconRidgeTB2DeviceIDs: Set<Int> = [0x156c, 0x156d]
    private static let intelVendorID = 0x8086

    /// Capability ceiling for TB1/TB2-era devices, in Gbps, or `nil` when
    /// no cap applies (TB3-class silicon and newer).
    ///
    /// Speed code `0x8` is 10 Gb/s per lane (corpus-measured: `Link
    /// Bandwidth` = per-lane Gbps x lanes x 10 without exception across
    /// 6548 records). A real 40 Gbps TB3 link trains at code `0x4`, the
    /// same code TB4 uses; code `0x8` on a dual-lane link is a 20 Gbps
    /// link, and on TB1/TB2-era silicon it can mean a single-lane 10 Gb/s
    /// link that width-aware `activeGbps` already reads correctly. This
    /// property exists for callers that only have the generation, not the
    /// width: it flags devices where even the per-lane figure needs a
    /// further cap (issue #515: a LaCie Rugged THB, genuine TB1 silicon,
    /// reported a rate its own hardware cannot reach).
    ///
    /// `thunderboltVersion == 1` is corpus-verified as ONLY genuine TB1
    /// silicon (Light Ridge / Port Ridge device IDs), zero contamination
    /// across 48 rows, so it's safe as a direct 10 Gbps cap.
    /// `thunderboltVersion == 2` is a TRAP (mixes real TB2 devices with TB3
    /// controllers) and must never be used here; the TB2 case is instead
    /// keyed on the Falcon Ridge device IDs above, capped at 20 Gbps (TB2's
    /// real per-link maximum).
    public var deviceGenerationCapGbps: Double? {
        if thunderboltVersion == 1 { return 10 }
        if vendorID == Self.intelVendorID,
           let deviceID, Self.falconRidgeTB2DeviceIDs.contains(deviceID) {
            return 20
        }
        return nil
    }
}

/// One row of an adapter's `Hop Table`. A Thunderbolt link multiplexes
/// several tunnels (DisplayPort video, USB3, PCIe) over the same physical
/// lane; each row describes how this adapter forwards one tunnel to the
/// next hop in the fabric. `pathUUID` is the join key: the same UUID
/// recurs on every adapter a tunnel crosses, across switches, so matching
/// it against another adapter's hop table pins where a tunnel enters and
/// exits the fabric. Verified live: a host-root lane port's hop table
/// listed 3 paths; one of them also appeared on a downstream dock's DP
/// adapter, pinning the monitor's video exit point. See
/// `ThunderboltTopology.tunnels(from:in:)` in `TunnelPath.swift` for the
/// grouping logic that consumes this.
public struct HopTableEntry: Hashable {
    /// Sequence number of this row within the adapter's hop table.
    public let counter: Int
    /// This adapter's hop ID for the tunnel (the inbound leg).
    public let hopID: Int
    /// The hop ID this row forwards to on the next adapter.
    public let dstHopID: Int
    /// The port number this row forwards to.
    public let dstPort: Int
    /// The tunnel's join key. Recurs on every adapter the tunnel crosses.
    public let pathUUID: String

    public init(counter: Int, hopID: Int, dstHopID: Int, dstPort: Int, pathUUID: String) {
        self.counter = counter
        self.hopID = hopID
        self.dstHopID = dstHopID
        self.dstPort = dstPort
        self.pathUUID = pathUUID
    }
}

/// One adapter on a Thunderbolt switch. Could be a physical TB lane port
/// (with link-state fields) or a protocol-tunnel adapter (DP, PCIe, USB3).
public struct IOThunderboltPort: Hashable {
    public let portNumber: Int
    /// String form of `Socket ID`, present on TB-protocol ports.
    /// Matches the `@N` suffix on a root host's USB-C port for the
    /// host-port-to-switch correlation key.
    public let socketID: String?
    public let adapterType: AdapterType
    /// Human-readable adapter description from IOKit (e.g. "Thunderbolt Port", "DP or HDMI Adapter").
    public let adapterDescription: String?
    /// Decoded `Current Link Speed`. `nil` on idle ports or non-lane adapters.
    public let currentSpeed: LinkGeneration?
    /// Decoded `Current Link Width`. `nil` on non-lane adapters. An idle lane
    /// port does NOT read zero on most silicon: Type2 to Type5 hosts idle at
    /// Current Link Speed 8 and Current Link Width 1, so `LinkWidth.isActive`
    /// is true there with nothing plugged in. Type7, which the corpus shows on
    /// M4 Pro, M4 Max and every M5 class Mac, mostly idles at 0, 0 instead
    /// (1232 of its 1344 idle-machine lanes).
    public let currentWidth: LinkWidth?
    public let targetWidth: TargetLinkWidth?
    /// Hardware-supported maximum link width.
    public let supportedWidth: LinkWidth?
    /// Per-lane Gb/s if we have a known generation, else `nil`. Convenience
    /// derived from `currentSpeed` so renderers don't need to switch on it.
    public let perLaneGbps: Int?
    public let txLanes: Int?
    public let rxLanes: Int?
    /// Raw `Target Link Speed`. Corpus-measured: it IS a bitmask over the
    /// same codes as `Supported Link Speed`, not the single named value
    /// Linux defines (`LANE_ADP_CS_1_TARGET_SPEED_GEN3 = 0xc`). It takes
    /// three values across the corpus (8, 12, 14), equals `Supported Link
    /// Speed` on 9013 of 9018 lane adapters, and every port linked at Gen 4
    /// reports 14, never 12. Still stored raw; nothing decodes it.
    public let rawTargetSpeed: UInt8?
    /// Raw `Link Bandwidth`. Unitless aggregate that scales with active
    /// lanes; useful for diagnostics, not for user-facing labels.
    public let linkBandwidthRaw: Int?
    /// Maximum bandwidth currently allocated to this adapter.
    public let maxBandwidthAllocated: Int?
    /// Minimum bandwidth required by connected devices.
    public let requiredBandwidthAllocated: Int?
    /// Buffer credits reserved per protocol tunnel.
    public let bufferAllocation: BufferAllocation?
    /// Total available buffer credits on this adapter.
    public let maxCredits: Int?
    /// Partner port number for dual-lane operation.
    public let dualLinkPort: Int?
    /// Lane number this adapter uses.
    public let lane: Int?
    /// Power management link state (0 = CL0 active, higher = deeper sleep).
    public let clxState: Int?
    /// Controller-class constant, not a per-link value: Apple Type5 = 32
    /// (TB4-class), Apple Type7 = 64 (TB5-capable), Type3 = 16. Do not use
    /// for link-generation labels. See `research/thunderbolt-fabric.md`.
    public let thunderboltVersion: Int?
    /// Hardware-supported maximum link speed as a bitmask.
    public let supportedSpeed: SupportedSpeedMask?
    /// TRM policy string (e.g. "Root" for the host switch).
    public let trmPolicy: String?
    /// Controller vendor ID (1452 = Apple).
    public let vendorID: Int?
    /// Controller device ID.
    public let deviceID: Int?
    /// Tunnel routing rows for this adapter. Empty when the property is
    /// absent or the adapter carries no active tunnel. See
    /// `HopTableEntry` for the join-key semantics.
    public let hopTable: [HopTableEntry]
    /// Registry path (IOService plane) of where this adapter's PCIe tunnel
    /// lands in the host tree, read from `PCI Path`. Present only on PCIe
    /// up/down adapters; nil elsewhere. Internal join key for Stage B's
    /// PCI-Path-prefix attribution (see planning/pcie-tunnelled-usb-attribution.md).
    /// Never user-facing: registry paths stay internal, like switch UIDs.
    public let pciPath: String?
    /// Registry entry ID of the `pciPath` landing node, read from
    /// `PCI Entry ID`. Registry entry IDs are unique per boot and never
    /// reused, so this is the instance-identity half of the Stage B join
    /// (a path string alone is a reusable topology address). Internal only.
    public let pciEntryID: UInt64?

    public struct BufferAllocation: Hashable {
        public let maxUSB3: Int
        public let maxPCIe: Int
        public let maxHI: Int
        public let minDPAux: Int

        public init(maxUSB3: Int, maxPCIe: Int, maxHI: Int, minDPAux: Int) {
            self.maxUSB3 = maxUSB3
            self.maxPCIe = maxPCIe
            self.maxHI = maxHI
            self.minDPAux = minDPAux
        }
    }

    public init(
        portNumber: Int,
        socketID: String?,
        adapterType: AdapterType,
        adapterDescription: String? = nil,
        currentSpeed: LinkGeneration?,
        currentWidth: LinkWidth?,
        targetWidth: TargetLinkWidth?,
        supportedWidth: LinkWidth? = nil,
        rawTargetSpeed: UInt8?,
        linkBandwidthRaw: Int?,
        maxBandwidthAllocated: Int? = nil,
        requiredBandwidthAllocated: Int? = nil,
        bufferAllocation: BufferAllocation? = nil,
        maxCredits: Int? = nil,
        dualLinkPort: Int? = nil,
        lane: Int? = nil,
        clxState: Int? = nil,
        supportedSpeed: SupportedSpeedMask? = nil,
        trmPolicy: String? = nil,
        thunderboltVersion: Int? = nil,
        vendorID: Int? = nil,
        deviceID: Int? = nil,
        hopTable: [HopTableEntry] = [],
        pciPath: String? = nil,
        pciEntryID: UInt64? = nil
    ) {
        self.portNumber = portNumber
        self.socketID = socketID
        self.adapterType = adapterType
        self.adapterDescription = adapterDescription
        self.currentSpeed = currentSpeed
        self.currentWidth = currentWidth
        self.targetWidth = targetWidth
        self.supportedWidth = supportedWidth
        self.perLaneGbps = currentSpeed?.perLaneGbps
        self.txLanes = currentWidth?.txLanes
        self.rxLanes = currentWidth?.rxLanes
        self.rawTargetSpeed = rawTargetSpeed
        self.linkBandwidthRaw = linkBandwidthRaw
        self.maxBandwidthAllocated = maxBandwidthAllocated
        self.requiredBandwidthAllocated = requiredBandwidthAllocated
        self.bufferAllocation = bufferAllocation
        self.maxCredits = maxCredits
        self.dualLinkPort = dualLinkPort
        self.lane = lane
        self.clxState = clxState
        self.supportedSpeed = supportedSpeed
        self.trmPolicy = trmPolicy
        self.thunderboltVersion = thunderboltVersion
        self.vendorID = vendorID
        self.deviceID = deviceID
        self.hopTable = hopTable
        self.pciPath = pciPath
        self.pciEntryID = pciEntryID
    }

    /// Build a port from a raw IOKit property dictionary.
    public static func from(read: (String) -> Any?) -> IOThunderboltPort? {
        guard let portNumNum = read("Port Number") as? NSNumber else { return nil }
        let adapterRaw = (read("Adapter Type") as? NSNumber)?.uint32Value ?? 0
        let adapter = AdapterType.from(rawValue: adapterRaw)

        let socketID = read("Socket ID") as? String
        let description = read("Description") as? String

        let speedRaw = (read("Current Link Speed") as? NSNumber)?.uint8Value ?? 0
        let widthRaw = (read("Current Link Width") as? NSNumber)?.uint8Value ?? 0
        let supportedWidthRaw = (read("Supported Link Width") as? NSNumber)?.uint8Value ?? 0
        let targetWidthRaw = (read("Target Link Width") as? NSNumber)?.uint8Value ?? 0
        let targetSpeedRaw = (read("Target Link Speed") as? NSNumber)?.uint8Value

        let currentSpeed: LinkGeneration?
        let currentWidth: LinkWidth?
        let targetWidth: TargetLinkWidth?
        let supportedWidth: LinkWidth?
        if adapter.isLane {
            currentSpeed = LinkGeneration.from(rawSpeedCode: speedRaw)
            currentWidth = LinkWidth(rawValue: widthRaw)
            targetWidth = TargetLinkWidth.from(rawValue: targetWidthRaw)
            supportedWidth = supportedWidthRaw != 0 ? LinkWidth(rawValue: supportedWidthRaw) : nil
        } else {
            currentSpeed = nil
            currentWidth = nil
            targetWidth = nil
            supportedWidth = nil
        }

        let bufferAlloc: BufferAllocation?
        if let bufDict = read("Buffer Allocation Request") as? [String: Any] {
            bufferAlloc = BufferAllocation(
                maxUSB3: (bufDict["Max USB3"] as? NSNumber)?.intValue ?? 0,
                maxPCIe: (bufDict["Max PCIe"] as? NSNumber)?.intValue ?? 0,
                maxHI: (bufDict["Max HI"] as? NSNumber)?.intValue ?? 0,
                minDPAux: (bufDict["Min DP Aux"] as? NSNumber)?.intValue ?? 0
            )
        } else {
            bufferAlloc = nil
        }

        // "Hop Table" is an array of dictionaries when populated; absent
        // or empty on idle adapters. Read it as `[Any]` first and cast each
        // element individually, rather than `[[String: Any]]` for the whole
        // array: a single non-dict element (e.g. IOKit bridging a row that
        // failed to fully stringify) would otherwise make the whole-array
        // cast fail and silently drop every entry, good rows included.
        // Skip any entry missing a required key, or whose Path isn't
        // exactly 36 characters (a well-formed UUID string), rather than
        // crashing or grouping on a malformed row. The 36-char check keeps
        // production consistent with the corpus sweep's independent
        // UUID-shaped regex (`TunnelPathCorpusTests.uuidPathRegex`).
        let hopTable: [HopTableEntry] = {
            guard let raw = read("Hop Table") as? [Any] else { return [] }
            return raw.enumerated().compactMap { index, element -> HopTableEntry? in
                guard let entry = element as? [String: Any] else { return nil }
                guard
                    let hopID = (entry["Hop ID"] as? NSNumber)?.intValue,
                    let dstHopID = (entry["Dst Hop ID"] as? NSNumber)?.intValue,
                    let dstPort = (entry["Dst Port"] as? NSNumber)?.intValue,
                    let path = entry["Path"] as? String,
                    path.count == 36
                else { return nil }
                // `Counter` is NOT required. A tunnel set up by firmware before
                // macOS booted carries `Inherited From EFI` in place of it, and
                // requiring Counter dropped the whole entry, so those tunnels
                // silently never reached the Active tunnels list. Found by the
                // probe-29 corpus sweep after back-filling 326 machines: 8 hop
                // entries across 2 Intel Macs were being discarded.
                //
                // Falling back to the row's position preserves the field's
                // meaning ("sequence number of this row within the adapter's
                // hop table") and nothing downstream groups on it: tunnel
                // reconstruction keys on pathUUID alone.
                let counter = (entry["Counter"] as? NSNumber)?.intValue ?? index
                return HopTableEntry(counter: counter, hopID: hopID, dstHopID: dstHopID, dstPort: dstPort, pathUUID: path)
            }
        }()

        return IOThunderboltPort(
            portNumber: portNumNum.intValue,
            socketID: socketID,
            adapterType: adapter,
            adapterDescription: description,
            currentSpeed: currentSpeed,
            currentWidth: currentWidth,
            targetWidth: targetWidth,
            supportedWidth: supportedWidth,
            rawTargetSpeed: targetSpeedRaw,
            linkBandwidthRaw: (read("Link Bandwidth") as? NSNumber)?.intValue,
            maxBandwidthAllocated: (read("Maximum Bandwidth Allocated") as? NSNumber)?.intValue,
            requiredBandwidthAllocated: (read("Required Bandwidth Allocated") as? NSNumber)?.intValue,
            bufferAllocation: bufferAlloc,
            maxCredits: (read("Max Credits") as? NSNumber)?.intValue,
            dualLinkPort: (read("Dual-Link Port") as? NSNumber)?.intValue,
            lane: (read("Lane") as? NSNumber)?.intValue,
            clxState: (read("CLx State") as? NSNumber)?.intValue,
            supportedSpeed: {
                let raw = (read("Supported Link Speed") as? NSNumber)?.uint8Value ?? 0
                return raw != 0 ? SupportedSpeedMask(rawValue: raw) : nil
            }(),
            trmPolicy: read("TRM Policy") as? String,
            thunderboltVersion: (read("Thunderbolt Version") as? NSNumber)?.intValue,
            vendorID: (read("Vendor ID") as? NSNumber)?.intValue,
            deviceID: (read("Device ID") as? NSNumber)?.intValue,
            hopTable: hopTable,
            pciPath: read("PCI Path") as? String,
            pciEntryID: (read("PCI Entry ID") as? NSNumber)?.uint64Value
        )
    }

    /// Active link rate in Gb/s: `perLaneGbps` times the TX lane count, the
    /// same identity the corpus confirms for `Link Bandwidth` (per-lane
    /// Gbps x lanes x 10). `nil` when `currentSpeed`, its `perLaneGbps`, or
    /// `currentWidth` is nil, and also when no lane is trained: six corpus
    /// records carry a real speed code with `Current Link Width` 0, and a
    /// 0.0 there would read as a measured zero-rate link rather than as
    /// "no link". Uses TX lanes, so an asymmetric TX link reads as the 3
    /// lane figure (120 on Gen 4/TB5); on the two asymmetric corpus
    /// records, `Link Bandwidth` tracks the RX side instead, so the two do
    /// not agree there. Always equal to `txGbps`.
    public var activeGbps: Double? {
        txGbps
    }

    /// Rate out of this port in Gb/s: `perLaneGbps` times the TX lane count.
    /// Same nil rules as `activeGbps`. On a symmetric link this equals
    /// `rxGbps`; on a TB5 asymmetric TX link (3 TX / 1 RX) it reads 120
    /// against an `rxGbps` of 40.
    public var txGbps: Double? {
        gbps(lanes: currentWidth?.txLanes)
    }

    /// Rate into this port in Gb/s: `perLaneGbps` times the RX lane count.
    /// Same nil rules as `activeGbps`.
    public var rxGbps: Double? {
        gbps(lanes: currentWidth?.rxLanes)
    }

    /// Shared arithmetic for the three rate properties, so the nil guards
    /// cannot drift apart. `lanes` is nil when `currentWidth` is.
    private func gbps(lanes: Int?) -> Double? {
        guard let currentSpeed, let perLane = currentSpeed.perLaneGbps, let lanes else {
            return nil
        }
        guard lanes > 0 else { return nil }
        return Double(perLane) * Double(lanes)
    }

    /// The raw `Current Link Speed` / `Current Link Width` register read for a
    /// TB lane port: true when the lane reports a trained width and a decoded
    /// speed. It is NOT "something is plugged in". An empty socket reports
    /// trained lanes on most silicon, on a Mac's host root and on a dock
    /// alike. Measured over the corpus lanes on machines with nothing
    /// attached: every Type2, Type3 and Type4 lane reads speed code 8 width 1
    /// (496 of 496), Type5 does on 3315 of 3634, and Type7 is the exception,
    /// idling at 0, 0 on 1232 of 1344. Callers asking "is a device actually
    /// connected on this lane" want
    /// `ThunderboltTopology.isLinked(port:on:in:)`, which pairs the lane
    /// against the switch graph.
    public var hasTrainedLanes: Bool {
        guard adapterType.isLane else { return false }
        guard let currentWidth, currentWidth.isActive else { return false }
        return currentSpeed != nil
    }

    /// True when the cable is limiting the link below what hardware supports.
    public var isBandwidthLimited: Bool {
        guard let supported = supportedWidth, let current = currentWidth else { return false }
        return supported.dual && current.single
    }
}
