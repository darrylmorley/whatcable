import Foundation

/// USB Power Delivery 3.0 / 3.1 VDO decoders. We only parse the fields we
/// surface — refer to the USB-PD spec (Universal Serial Bus Power Delivery
/// Specification, Revision 3.1) for the full layout.
public enum PDVDO {

    // MARK: ID Header VDO (always VDO[0])

    public enum ProductType: Int {
        case undefined = 0
        case pdusbHub = 1
        case pdusbPeripheral = 2
        case passiveCable = 3
        case activeCable = 4
        case ama = 5            // Alternate Mode Adapter
        case vpd = 6            // VCONN-Powered Device
        case other = 7

        public var label: String {
            switch self {
            case .undefined: return String(localized: "Unspecified", bundle: .module)
            case .pdusbHub: return String(localized: "USB Hub", bundle: .module)
            case .pdusbPeripheral: return String(localized: "USB Peripheral", bundle: .module)
            case .passiveCable: return String(localized: "Passive cable", bundle: .module)
            case .activeCable: return String(localized: "Active cable", bundle: .module)
            case .ama: return String(localized: "Alternate Mode Adapter", bundle: .module)
            case .vpd: return String(localized: "VCONN-powered device", bundle: .module)
            case .other: return String(localized: "Other", bundle: .module)
            }
        }
    }

    public struct IDHeader: Hashable {
        public let usbCommHost: Bool
        public let usbCommDevice: Bool
        public let modalOperation: Bool
        /// UFP product type (set on cables / peripherals)
        public let ufpProductType: ProductType
        /// DFP product type (set on hosts / hubs)
        public let dfpProductType: ProductType
        public let vendorID: Int
    }

    public static func decodeIDHeader(_ vdo: UInt32) -> IDHeader {
        IDHeader(
            usbCommHost: (vdo >> 31) & 1 == 1,
            usbCommDevice: (vdo >> 30) & 1 == 1,
            modalOperation: (vdo >> 26) & 1 == 1,
            ufpProductType: ProductType(rawValue: Int((vdo >> 27) & 0b111)) ?? .undefined,
            dfpProductType: ProductType(rawValue: Int((vdo >> 23) & 0b111)) ?? .undefined,
            vendorID: Int(vdo & 0xFFFF)
        )
    }

    // MARK: Cable VDO (passive or active, VDO[3] in PD 3.0+)

    public enum CableSpeed: Int {
        case usb20 = 0
        case usb32Gen1 = 1   // 5 Gbps
        case usb32Gen2 = 2   // 10 Gbps
        case usb4Gen3 = 3    // 20 Gbps (PD 3.0) / 40 Gbps (PD 3.1)
        case usb4Gen4 = 4    // 80 Gbps

        public var label: String {
            switch self {
            case .usb20: return String(localized: "USB 2.0 (480 Mbps)", bundle: .module)
            case .usb32Gen1: return String(localized: "USB 3.2 Gen 1 (5 Gbps)", bundle: .module)
            case .usb32Gen2: return String(localized: "USB 3.2 Gen 2 (10 Gbps)", bundle: .module)
            case .usb4Gen3: return String(localized: "USB4 Gen 3 (20 / 40 Gbps)", bundle: .module)
            case .usb4Gen4: return String(localized: "USB4 Gen 4 (80 Gbps)", bundle: .module)
            }
        }

        public var maxGbps: Double {
            switch self {
            case .usb20: return 0.48
            case .usb32Gen1: return 5
            case .usb32Gen2: return 10
            case .usb4Gen3: return 40
            case .usb4Gen4: return 80
            }
        }
    }

    public enum CableCurrent: Int {
        case usbDefault = 0   // 900 mA / 1.5 A typical USB
        case threeAmp = 1
        case fiveAmp = 2

        public var maxAmps: Double {
            switch self {
            case .usbDefault: return 3.0   // be charitable; Type-C default current is 3A on cables
            case .threeAmp: return 3.0
            case .fiveAmp: return 5.0
            }
        }

        public var label: String {
            switch self {
            case .usbDefault: return String(localized: "USB default", bundle: .module)
            case .threeAmp: return String(localized: "3 A", bundle: .module)
            case .fiveAmp: return String(localized: "5 A", bundle: .module)
            }
        }
    }

    public enum CableType: Int {
        case passive = 0
        case active = 1
        case other = 2
    }

    public enum DecodeWarning: Hashable {
        case reservedSpeedEncoding(Int)
        case reservedCurrentEncoding(Int)
        /// Cable latency field uses a reserved value. Bounds depend on
        /// cable type: passive cables treat 0000 and 1001..1111 as
        /// invalid; active cables treat 0000 and 1011..1111 as invalid
        /// (1001 and 1010 carry valid optical-cable latencies).
        case reservedCableLatencyEncoding(Int)
        /// Cable VDO Version field (bits 23..21) uses a value the spec
        /// marks as Invalid for this cable type. Passive cables: only
        /// `000` (v1.0) is valid. Active cables: `000` (deprecated v1.0),
        /// `010` (deprecated v1.2), and `011` (v1.3) are accepted.
        case invalidVDOVersion(Int)
        /// Cable Termination field (bits 12..11) uses a value the spec
        /// marks as Invalid for this cable type. Passive cables: `00`
        /// and `01` valid. Active cables: `10` and `11` valid.
        case invalidCableTermination(Int)
        /// Passive cable's e-marker advertises EPR Capable but reports
        /// only 20V Max VBUS. EPR requires 48V or 50V VBUS, so this
        /// pair of fields is internally contradictory.
        case eprClaimedWithLowMaxVoltage
    }

    public struct CableVDO: Hashable {
        public let speed: CableSpeed
        public let current: CableCurrent
        /// Approx max wattage at the highest negotiated voltage (20V) the cable can carry.
        public let maxWatts: Int
        public let cableType: CableType
        public let vbusThroughCable: Bool
        /// Encoded "Maximum VBUS Voltage" field. 0=20V, 1=30V, 2=40V, 3=50V.
        public let maxVoltageEncoded: Int
        /// Raw 4-bit "Cable Latency" field (bits 16..13). 0000 and reserved
        /// values per cable type are flagged via `decodeWarnings`. Use
        /// `latencyNanoseconds` for a typed interpretation.
        public let cableLatencyEncoded: Int
        /// Raw 3-bit "VDO Version" field (bits 23..21). Validity depends
        /// on cable type and is reported via `decodeWarnings`.
        public let vdoVersionEncoded: Int
        /// Raw 2-bit "Cable Termination" field (bits 12..11). Validity
        /// depends on cable type and is reported via `decodeWarnings`.
        public let cableTerminationEncoded: Int
        /// Bit 17, "EPR Capable." When true, the cable claims to be safe
        /// for Extended Power Range operation (48V / 50V).
        public let eprCapable: Bool
        public let decodeWarnings: [DecodeWarning]

        public var maxVolts: Int {
            switch maxVoltageEncoded {
            case 0: return 20
            case 1: return 30
            case 2: return 40
            case 3: return 50
            default: return 20
            }
        }

        /// Approximate one-way cable latency in nanoseconds, decoded from
        /// `cableLatencyEncoded`. Returns `nil` for the reserved values
        /// flagged in `decodeWarnings`. The 0001..1000 range maps roughly
        /// 10 ns per cable metre. Active cables additionally carry 1001
        /// (~1000 ns) and 1010 (~2000 ns) for optical lengths.
        public var latencyNanoseconds: Int? {
            switch cableLatencyEncoded {
            case 0b0001: return 10
            case 0b0010: return 20
            case 0b0011: return 30
            case 0b0100: return 40
            case 0b0101: return 50
            case 0b0110: return 60
            case 0b0111: return 70
            case 0b1000: return 80    // ">70 ns" per spec; treat as 80 for display purposes
            case 0b1001 where cableType == .active: return 1000
            case 0b1010 where cableType == .active: return 2000
            default: return nil
            }
        }
    }

    public static func decodeCableVDO(_ vdo: UInt32, isActive: Bool) -> CableVDO {
        let speedBits = Int(vdo & 0b111)
        let decodedSpeed = CableSpeed(rawValue: speedBits)
        let speed = decodedSpeed ?? .usb20
        let vbusThrough = (vdo >> 4) & 1 == 1
        let currentBits = Int((vdo >> 5) & 0b11)
        let decodedCurrent = CableCurrent(rawValue: currentBits)
        let current = decodedCurrent ?? .usbDefault
        let maxV = Int((vdo >> 9) & 0b11)
        let latencyBits = Int((vdo >> 13) & 0b1111)
        let cableType: CableType = isActive ? .active : .passive
        let cableTerminationBits = Int((vdo >> 11) & 0b11)
        let vdoVersionBits = Int((vdo >> 21) & 0b111)
        let eprCapable = (vdo >> 17) & 1 == 1
        var warnings: [DecodeWarning] = []
        if decodedSpeed == nil {
            warnings.append(.reservedSpeedEncoding(speedBits))
        }
        if decodedCurrent == nil {
            warnings.append(.reservedCurrentEncoding(currentBits))
        }
        // The PD spec also flags `00` as Invalid for VBUS Current
        // Handling (treat as 3 A), but real-world cables — including
        // basic USB 2.0 charging cables — emit `00` as a "default"
        // routinely. We intentionally don't warn on `00` because the
        // false-positive rate would be high, and we lack calibration
        // data showing it correlating with counterfeits. Revisit if
        // future cable reports show otherwise.
        // Cable Latency field. 0000 is "Invalid" for both cable types.
        // Passive cables also treat 1001..1111 as Invalid. Active cables
        // accept 1001 (~1000 ns optical) and 1010 (~2000 ns optical),
        // and treat 1011..1111 as Invalid.
        let latencyInvalid: Bool
        if latencyBits == 0 {
            latencyInvalid = true
        } else if isActive {
            latencyInvalid = latencyBits >= 0b1011
        } else {
            latencyInvalid = latencyBits >= 0b1001
        }
        if latencyInvalid {
            warnings.append(.reservedCableLatencyEncoding(latencyBits))
        }

        // VDO Version (bits 23..21).
        // Passive: only 000 (v1.0) is valid; everything else Invalid.
        // Active: 000 (deprecated v1.0), 010 (deprecated v1.2), 011 (v1.3)
        // are accepted. 001 and 100..111 are Invalid per Table 6.43.
        let vdoVersionInvalid: Bool
        if isActive {
            vdoVersionInvalid = !(vdoVersionBits == 0 || vdoVersionBits == 0b010 || vdoVersionBits == 0b011)
        } else {
            vdoVersionInvalid = vdoVersionBits != 0
        }
        if vdoVersionInvalid {
            warnings.append(.invalidVDOVersion(vdoVersionBits))
        }

        // Cable Termination (bits 12..11).
        // Passive: 00 (VCONN not required) and 01 (VCONN required) are
        // valid; 10 and 11 are Invalid.
        // Active: 00 and 01 are Invalid; 10 (one end active) and 11
        // (both ends active) are valid.
        let cableTerminationInvalid: Bool
        if isActive {
            cableTerminationInvalid = cableTerminationBits < 0b10
        } else {
            cableTerminationInvalid = cableTerminationBits >= 0b10
        }
        if cableTerminationInvalid {
            warnings.append(.invalidCableTermination(cableTerminationBits))
        }

        // H9a: Passive cable claims EPR Capable but reports 20V Max VBUS.
        // EPR requires 48V or 50V; only encoding 11 (50V) is consistent
        // with an EPR claim. We flag the 20V case (encoding 0) explicitly,
        // matching what the planning doc calls out. Active cables aren't
        // flagged here: their EPR semantics need the Active VDO2 decoder.
        if !isActive && eprCapable && maxV == 0 {
            warnings.append(.eprClaimedWithLowMaxVoltage)
        }

        let volts: Double
        switch maxV {
        case 1: volts = 30
        case 2: volts = 40
        case 3: volts = 50
        default: volts = 20
        }
        let amps = current.maxAmps
        let watts = Int((volts * amps).rounded())

        return CableVDO(
            speed: speed,
            current: current,
            maxWatts: watts,
            cableType: cableType,
            vbusThroughCable: vbusThrough,
            maxVoltageEncoded: maxV,
            cableLatencyEncoded: latencyBits,
            vdoVersionEncoded: vdoVersionBits,
            cableTerminationEncoded: cableTerminationBits,
            eprCapable: eprCapable,
            decodeWarnings: warnings
        )
    }

    // MARK: Active Cable VDO 2 (active cables only, VDO[4] in PD 3.0+)

    /// Physical medium the cable uses to carry data.
    public enum PhysicalConnection: Int {
        case copper = 0
        case optical = 1

        public var label: String {
            switch self {
            case .copper: return String(localized: "Copper", bundle: .module)
            case .optical: return String(localized: "Optical", bundle: .module)
            }
        }
    }

    /// What the active silicon inside the cable's connector does to the
    /// signal. A re-driver boosts the signal in place; a re-timer fully
    /// decodes and re-emits it. Re-timers are more capable and usually
    /// found in higher-end cables.
    public enum ActiveElement: Int {
        case redriver = 0
        case retimer = 1

        public var label: String {
            switch self {
            case .redriver: return String(localized: "Re-driver", bundle: .module)
            case .retimer: return String(localized: "Re-timer", bundle: .module)
            }
        }
    }

    /// Idle-state power consumption of the active chip while the cable
    /// is in U3 / CLd. Matters for thermal and battery-life accounting on
    /// portable hosts. Bits 14..12.
    public enum U3CLdPower: Int {
        case greaterThan10mW = 0      // > 10 mW
        case fiveTo10mW = 1           // 5-10 mW
        case oneTo5mW = 2             // 1-5 mW
        case halfTo1mW = 3            // 0.5-1 mW
        case fifthToHalfmW = 4        // 0.2-0.5 mW
        case fiftyTo200uW = 5         // 50-200 µW
        case lessThan50uW = 6         // < 50 µW
        case reserved = 7

        public var label: String {
            switch self {
            case .greaterThan10mW: return String(localized: "> 10 mW", bundle: .module)
            case .fiveTo10mW: return String(localized: "5-10 mW", bundle: .module)
            case .oneTo5mW: return String(localized: "1-5 mW", bundle: .module)
            case .halfTo1mW: return String(localized: "0.5-1 mW", bundle: .module)
            case .fifthToHalfmW: return String(localized: "0.2-0.5 mW", bundle: .module)
            case .fiftyTo200uW: return String(localized: "50-200 µW", bundle: .module)
            case .lessThan50uW: return String(localized: "< 50 µW", bundle: .module)
            case .reserved: return String(localized: "Reserved", bundle: .module)
            }
        }
    }

    public struct ActiveCableVDO2: Hashable {
        /// Bits 31..24, in degrees C. 0 means "not specified."
        public let maxOperatingTempC: Int
        /// Bits 23..16, in degrees C. 0 means "not specified."
        public let shutdownTempC: Int
        /// Bits 14..12.
        public let u3CLdPower: U3CLdPower
        /// Bit 11. `true` = transition through U3S (saves power but slower
        /// to wake), `false` = direct.
        public let u3ToU0TransitionThroughU3S: Bool
        /// Bit 10.
        public let physicalConnection: PhysicalConnection
        /// Bit 9.
        public let activeElement: ActiveElement
        /// Bit 8.
        public let usb4Supported: Bool
        /// Bits 7..6. Number of USB 2.0 hub hops the cable consumes from
        /// the topology budget.
        public let usb2HubHopsConsumed: Int
        /// Bit 5.
        public let usb2Supported: Bool
        /// Bit 4. Set when USB 3.2 signalling is supported.
        public let usb32Supported: Bool
        /// Bit 3. `true` = two USB lanes supported, `false` = one lane.
        public let twoLanesSupported: Bool
        /// Bit 2. Optical cables that carry their signal on glass fiber
        /// are physically isolated by construction; cables that bring
        /// power or ground continuity through copper alongside the fiber
        /// will set this to `false`.
        public let opticallyIsolated: Bool
        /// Bit 1.
        public let usb4AsymmetricMode: Bool
        /// Bit 0. `true` = Gen2 or higher, `false` = Gen1.
        public let usbGen2OrHigher: Bool
    }

    public static func decodeActiveCableVDO2(_ vdo: UInt32) -> ActiveCableVDO2 {
        let maxTemp = Int((vdo >> 24) & 0xFF)
        let shutdownTemp = Int((vdo >> 16) & 0xFF)
        let powerBits = Int((vdo >> 12) & 0b111)
        let power = U3CLdPower(rawValue: powerBits) ?? .reserved
        let physBits = Int((vdo >> 10) & 1)
        let phys = PhysicalConnection(rawValue: physBits) ?? .copper
        let elemBits = Int((vdo >> 9) & 1)
        let elem = ActiveElement(rawValue: elemBits) ?? .redriver

        // The protocol-supported bits (USB4, USB 3.2, USB 2.0) are
        // *inverted* in the spec: a 0 bit means "supported," a 1 means
        // "not supported." The other Bool fields use the conventional
        // 1 = yes encoding. Keep the API ergonomic (`usb4Supported = true`
        // when the cable actually supports USB4) by inverting here.
        return ActiveCableVDO2(
            maxOperatingTempC: maxTemp,
            shutdownTempC: shutdownTemp,
            u3CLdPower: power,
            u3ToU0TransitionThroughU3S: (vdo >> 11) & 1 == 1,
            physicalConnection: phys,
            activeElement: elem,
            usb4Supported: (vdo >> 8) & 1 == 0,
            usb2HubHopsConsumed: Int((vdo >> 6) & 0b11),
            usb2Supported: (vdo >> 5) & 1 == 0,
            usb32Supported: (vdo >> 4) & 1 == 0,
            twoLanesSupported: (vdo >> 3) & 1 == 1,
            opticallyIsolated: (vdo >> 2) & 1 == 1,
            usb4AsymmetricMode: (vdo >> 1) & 1 == 1,
            usbGen2OrHigher: vdo & 1 == 1
        )
    }

    // MARK: Cert Stat VDO (always VDO[1])

    /// USB-IF certification identity. Issued before product certification;
    /// `0` means the e-marker carries no certification ID. Common on
    /// reputable but uncertified cables, so we surface it as a neutral
    /// fact rather than a trust flag.
    public struct CertStat: Hashable {
        public let xid: UInt32

        public var isPresent: Bool { xid != 0 }
    }

    public static func decodeCertStat(_ vdo: UInt32) -> CertStat {
        // Spec table 6.38: bits 31..0 carry the XID.
        return CertStat(xid: vdo)
    }

    // MARK: Helpers

    /// IOKit stores VDOs as 4-byte little-endian Data blobs. Decode to UInt32.
    public static func vdoFromData(_ data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        return data.withUnsafeBytes { buf in
            buf.loadUnaligned(as: UInt32.self).littleEndian
        }
    }
}
