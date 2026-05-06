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
            case .undefined: return "Unspecified"
            case .pdusbHub: return "USB Hub"
            case .pdusbPeripheral: return "USB Peripheral"
            case .passiveCable: return "Passive cable"
            case .activeCable: return "Active cable"
            case .ama: return "Alternate Mode Adapter"
            case .vpd: return "VCONN-powered device"
            case .other: return "Other"
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
            case .usb20: return "USB 2.0 (480 Mbps)"
            case .usb32Gen1: return "USB 3.2 Gen 1 (5 Gbps)"
            case .usb32Gen2: return "USB 3.2 Gen 2 (10 Gbps)"
            case .usb4Gen3: return "USB4 Gen 3 (20 / 40 Gbps)"
            case .usb4Gen4: return "USB4 Gen 4 (80 Gbps)"
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
            case .usbDefault: return "USB default"
            case .threeAmp: return "3 A"
            case .fiveAmp: return "5 A"
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
            decodeWarnings: warnings
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
