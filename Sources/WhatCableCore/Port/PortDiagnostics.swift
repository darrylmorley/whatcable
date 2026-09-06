import Foundation

public enum PDO: Codable, Sendable, Equatable {
    case fixed(voltage: Int, maxCurrent: Int)
    // Battery: min and max voltage (50mV units), max power (250mW units) - Table 6.11
    case battery(minVoltage: Int, maxVoltage: Int, maxPower: Int)
    // Variable: min and max voltage (50mV units), max current (10mA units) - Table 6.12
    case variable(minVoltage: Int, maxVoltage: Int, maxCurrent: Int)
    // Programmable Power Supply APDO (PPS, bits 29:28 = 00) - Table 6.13
    case pps(minVoltage: Int, maxVoltage: Int, maxCurrent: Int)
    // Extended Power Range Adjustable Voltage Supply APDO (bits 29:28 = 01) - Table 6.16
    case eprAvs(minVoltage: Int, maxVoltage: Int, pdp: Int)
    // Standard Power Range Adjustable Voltage Supply APDO (bits 29:28 = 10) - Table 6.15
    case sprAvs(maxCurrent15V: Int, maxCurrent20V: Int)

    public static func decode(rawValue: UInt32) -> PDO {
        switch (rawValue >> 30) & 0x3 {
        case 0:
            // Fixed supply: bits 19..10 = voltage (50mV), bits 9..0 = max current (10mA)
            let voltage = Int((rawValue >> 10) & 0x3FF) * 50
            let maxCurrent = Int(rawValue & 0x3FF) * 10
            return .fixed(voltage: voltage, maxCurrent: maxCurrent)
        case 1:
            // Battery: bits 29..20 = max voltage (50mV), bits 19..10 = min voltage (50mV), bits 9..0 = max power (250mW)
            let maxVoltage = Int((rawValue >> 20) & 0x3FF) * 50
            let minVoltage = Int((rawValue >> 10) & 0x3FF) * 50
            let maxPower = Int(rawValue & 0x3FF) * 250
            return .battery(minVoltage: minVoltage, maxVoltage: maxVoltage, maxPower: maxPower)
        case 2:
            // Variable: bits 29..20 = max voltage (50mV), bits 19..10 = min voltage (50mV), bits 9..0 = max current (10mA)
            let maxVoltage = Int((rawValue >> 20) & 0x3FF) * 50
            let minVoltage = Int((rawValue >> 10) & 0x3FF) * 50
            let maxCurrent = Int(rawValue & 0x3FF) * 10
            return .variable(minVoltage: minVoltage, maxVoltage: maxVoltage, maxCurrent: maxCurrent)
        default:
            // APDO: subtype in bits 29..28 determines layout
            switch (rawValue >> 28) & 0x3 {
            case 0:
                // PPS (Table 6.13): bits 24..17 = max voltage (100mV), bits 15..8 = min voltage (100mV), bits 6..0 = max current (50mA)
                let maxVoltage = Int((rawValue >> 17) & 0xFF) * 100
                let minVoltage = Int((rawValue >> 8) & 0xFF) * 100
                let maxCurrent = Int(rawValue & 0x7F) * 50
                return .pps(minVoltage: minVoltage, maxVoltage: maxVoltage, maxCurrent: maxCurrent)
            case 1:
                // EPR AVS (Table 6.16): bits 25..17 = max voltage (100mV), bits 15..8 = min voltage (100mV), bits 7..0 = PDP (1W)
                let maxVoltage = Int((rawValue >> 17) & 0x1FF) * 100
                let minVoltage = Int((rawValue >> 8) & 0xFF) * 100
                let pdp = Int(rawValue & 0xFF) * 1000
                return .eprAvs(minVoltage: minVoltage, maxVoltage: maxVoltage, pdp: pdp)
            case 2:
                // SPR AVS (Table 6.15): bits 19..10 = max current at 15V (10mA), bits 9..0 = max current at 20V (10mA)
                let maxCurrent15V = Int((rawValue >> 10) & 0x3FF) * 10
                let maxCurrent20V = Int(rawValue & 0x3FF) * 10
                return .sprAvs(maxCurrent15V: maxCurrent15V, maxCurrent20V: maxCurrent20V)
            default:
                // Subtype 11 is invalid per spec; fall back to PPS layout so we still show something
                let maxVoltage = Int((rawValue >> 17) & 0xFF) * 100
                let minVoltage = Int((rawValue >> 8) & 0xFF) * 100
                let maxCurrent = Int(rawValue & 0x7F) * 50
                return .pps(minVoltage: minVoltage, maxVoltage: maxVoltage, maxCurrent: maxCurrent)
            }
        }
    }
}

public struct PDContract: Codable, Sendable, Equatable {
    public let activeRdo: UInt32
    public let pdoList: [PDO]
    public let pdoCount: Int
    public let maxPower: Int
    public let capMismatch: Bool
    public let srcTypes: Int

    public init(
        activeRdo: UInt32,
        pdoList: [PDO],
        pdoCount: Int,
        maxPower: Int,
        capMismatch: Bool,
        srcTypes: Int
    ) {
        self.activeRdo = activeRdo
        self.pdoList = pdoList
        self.pdoCount = pdoCount
        self.maxPower = maxPower
        self.capMismatch = capMismatch
        self.srcTypes = srcTypes
    }
}

public struct PortHealthCounters: Codable, Sendable, Equatable {
    public let attachCount: Int
    public let detachCount: Int
    public let hardResetCount: Int
    public let shortDetectCount: Int
    public let i2cErrCount: Int
    public let dataRoleSwapCount: Int
    public let dataRoleSwapFailCount: Int
    public let pwrRoleSwapCount: Int
    public let pwrRoleSwapFailCount: Int
    public let vdoFailCount: Int
    public let fetEnableFailCount: Int
    public let fetStatus: UInt8
    public let pdState: UInt8
    public let dnState: UInt8

    public init(
        attachCount: Int,
        detachCount: Int,
        hardResetCount: Int,
        shortDetectCount: Int,
        i2cErrCount: Int,
        dataRoleSwapCount: Int,
        dataRoleSwapFailCount: Int,
        pwrRoleSwapCount: Int,
        pwrRoleSwapFailCount: Int,
        vdoFailCount: Int,
        fetEnableFailCount: Int,
        fetStatus: UInt8,
        pdState: UInt8,
        dnState: UInt8
    ) {
        self.attachCount = attachCount
        self.detachCount = detachCount
        self.hardResetCount = hardResetCount
        self.shortDetectCount = shortDetectCount
        self.i2cErrCount = i2cErrCount
        self.dataRoleSwapCount = dataRoleSwapCount
        self.dataRoleSwapFailCount = dataRoleSwapFailCount
        self.pwrRoleSwapCount = pwrRoleSwapCount
        self.pwrRoleSwapFailCount = pwrRoleSwapFailCount
        self.vdoFailCount = vdoFailCount
        self.fetEnableFailCount = fetEnableFailCount
        self.fetStatus = fetStatus
        self.pdState = pdState
        self.dnState = dnState
    }
}

/// Event codes seen in the AppleSmartBattery `PortControllerEvtBuffer` ring.
///
/// These are Apple HPM firmware event codes, verified against the deltas of the
/// `PortController*` counters across seven before/after captures (2026-09-05).
/// They are NOT the TI TPS6598x IntEvent bit table, which the earlier decode in
/// this file assumed: only 0x03 lines up between the two.
public enum PDEvent: Codable, Sendable, Equatable {
    /// 0x03, plug attached (arg 0x01) or detached (arg 0x02).
    case plugEvent
    /// 0x30, Source_Capabilities received; the argument is the PDO count.
    case sourceCapsReceived
    /// 0xf0, Request (RDO) sent. Always follows a 0x30.
    case requestSent
    /// 0xf1, source ready result: arg 0x01 accepted, arg 0x81 rejected.
    case sourceReady
    /// 0x48, Discover Identity response received on SOP.
    case identityReceived
    /// 0x5e, unstructured VDM enumeration.
    case uvdmEnum
    /// 0x5f, unstructured VDM status update.
    case uvdmStatusUpdate
    /// 0x37, the Mac became the power source on this port.
    case becameSource
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0x03: self = .plugEvent
        case 0x30: self = .sourceCapsReceived
        case 0xf0: self = .requestSent
        case 0xf1: self = .sourceReady
        case 0x48: self = .identityReceived
        case 0x5e: self = .uvdmEnum
        case 0x5f: self = .uvdmStatusUpdate
        case 0x37: self = .becameSource
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .plugEvent: return 0x03
        case .sourceCapsReceived: return 0x30
        case .requestSent: return 0xf0
        case .sourceReady: return 0xf1
        case .identityReceived: return 0x48
        case .uvdmEnum: return 0x5e
        case .uvdmStatusUpdate: return 0x5f
        case .becameSource: return 0x37
        case .unknown(let value): return value
        }
    }
}

/// One event from the ring: the opcode plus its argument byte, where it has one.
public struct PDEventRecord: Codable, Sendable, Equatable {
    public let event: PDEvent
    public let argument: UInt8?
    /// This record sits at the ring seam and its reading is a guess; never show
    /// it. It covers both halves of the problem: a leftover byte whose opcode
    /// fell off the front of the buffer, and the first record parsed after it,
    /// which is only as trustworthy as the alignment that produced it.
    public let isSeamAffected: Bool

    public init(event: PDEvent, argument: UInt8?, isSeamAffected: Bool = false) {
        self.event = event
        self.argument = argument
        self.isSeamAffected = isSeamAffected
    }

    /// What a 0xf1 source ready record actually reported. Nil for every other
    /// opcode. A record with no argument, or an argument we have not seen,
    /// is `unknown`: it is not evidence the source came up.
    public enum SourceReadyOutcome: Codable, Sendable, Equatable {
        case accepted
        case rejected
        case unknown
    }

    public var sourceReadyOutcome: SourceReadyOutcome? {
        guard event == .sourceReady else { return nil }
        switch argument {
        case 0x01: return .accepted
        case 0x81: return .rejected
        default: return .unknown
        }
    }

    /// 0x03 with argument 0x01: a cable was plugged in.
    public var isAttach: Bool { event == .plugEvent && argument == 0x01 }

    /// 0x03 with argument 0x02: a cable was unplugged.
    public var isDetach: Bool { event == .plugEvent && argument == 0x02 }

    /// 0xf1 with argument 0x81: the source did not become ready.
    public var isSourceReadyRejected: Bool { event == .sourceReady && argument == 0x81 }

    /// How many PDOs the source advertised, when this record is a 0x30.
    public var pdoCount: Int? {
        guard event == .sourceCapsReceived, let argument else { return nil }
        return Int(argument)
    }
}

public struct PDEventTrace: Codable, Sendable, Equatable {
    /// The buffer exactly as read from the registry, nothing stripped.
    public let rawBuffer: Data
    public let events: [PDEventRecord]

    public init(rawBuffer: Data, events: [PDEventRecord]) {
        self.rawBuffer = rawBuffer
        self.events = events
    }

    /// Opcodes that consume the byte after them as an argument. Everything
    /// else in the buffer stands alone, including 0x48 and 0x5f, which are
    /// real events with no argument.
    private static let opcodesWithArgument: Set<UInt8> = [
        0x03, 0x1a, 0x30, 0x31, 0x37, 0x3f, 0x40, 0x5e, 0xf0, 0xf1, 0xf2, 0xf3, 0xf8,
    ]

    /// Opcodes that stand alone but are still real events, as opposed to bytes
    /// we simply do not recognise.
    private static let opcodesWithoutArgument: Set<UInt8> = [0x48, 0x5f]

    private static func isKnownOpcode(_ byte: UInt8) -> Bool {
        opcodesWithArgument.contains(byte) || opcodesWithoutArgument.contains(byte)
    }

    /// Decides the L == 0 case: is the first byte a leftover argument (true) or
    /// a record of its own (false)? This picks the alignment only. Either way
    /// the first record that comes out of it is flagged, because a reading that
    /// fits is not a reading that is known. See `parse`'s doc comment.
    private static func seamLeftoverLeads(_ bytes: [UInt8]) -> Bool {
        guard let first = bytes.first else { return false }
        // Not an opcode at all: it can only be a leftover.
        guard isKnownOpcode(first) else { return true }
        // Where the buffer would continue if this really is a record.
        let afterRecord = opcodesWithArgument.contains(first) ? min(2, bytes.count) : 1
        if afterRecord >= bytes.count { return false }
        if isKnownOpcode(bytes[afterRecord]) { return false }
        // That reading falls out of step. Does dropping the byte fix it?
        if bytes.count > 1, isKnownOpcode(bytes[1]) { return true }
        // Neither reading lines up, so change nothing.
        return false
    }

    /// Tokenises a `PortControllerEvtBuffer` into records.
    ///
    /// 0x00 is a legitimate argument value (0x40 0x00, 0xf8 0x00, 0x5e 0x00), so
    /// zeros are never stripped from the middle of the buffer. Because it is a
    /// ring the last record can be cut short, so an opcode at the very end that
    /// wants an argument gets a nil one.
    ///
    /// The ring cuts the FIRST record in half too, and the buffer is presented
    /// oldest first, so index 0 is the only place that can happen. Every
    /// argument-taking opcode consumes exactly one byte, so a cut record leaves
    /// at most ONE leftover byte behind. What sits at the front is decided by
    /// the length of the leading zero run, L:
    ///
    /// - **L >= 3: the ring has not wrapped yet.** Those zeros are unwritten
    ///   space, not data, so there is no seam at all. Strip them and parse the
    ///   rest as ordinary records, including the first one even if its opcode
    ///   is unknown to us. Nothing is flagged.
    /// - **L is 1 or 2: the first zero is the leftover.** Too few to be an
    ///   unfilled ring, so index 0 is the argument byte of a record whose
    ///   opcode fell off the front. It is flagged. Only ONE byte can be
    ///   leftover, so with L == 2 the second zero is a real record of its own
    ///   (an unknown 0x00) and is not flagged. Either way the alignment from
    ///   index 1 on is known, so nothing after it is flagged either.
    /// - **L == 0: the alignment at index 0 is a guess.** Two readings of the
    ///   first byte B: H1 says B is a record, H2 says B is a leftover argument.
    ///   B that is not an opcode at all can only be H2. Otherwise take H1 when
    ///   H1's record ends on a known opcode or on the end of the buffer,
    ///   because that is the reading that stays in step; failing that take H2
    ///   when the byte after B is a known opcode, for the same reason; failing
    ///   both, keep H1 and change nothing.
    ///
    /// That last branch only settles which bytes to READ, never whether the
    /// reading is right. So under L == 0 both readings are tokenised in full
    /// and compared. From the first offset past index 0 where H1 and H2 both
    /// start a record, the two readings are byte-for-byte the same (the same
    /// bytes follow, and tokenising is deterministic), so records from there on
    /// are known. Every record of the chosen reading that starts BEFORE that
    /// offset is a product of the guess and is flagged, and the view shows
    /// none of them. `3f f1 03 01` is the case that needs this: H1 reads
    /// `3f(f1), 03(01)` and is chosen because 3f(f1) lands on the 0x03 opcode,
    /// but H2 reads a leftover 3f, `f1(03)`, `unknown(01)`, which has no plug
    /// event in it, and the two only meet again at the end of the buffer. The
    /// plug event exists only under one guess, so both H1 records are flagged.
    /// If the readings never meet before the buffer ends, everything is
    /// flagged. Where they meet at once, as with `81 30 04 5f` (H1 reads 81
    /// standalone, H2 reads it as a leftover, both continue at index 1), only
    /// the byte at the seam is flagged.
    ///
    public static func parse(_ buffer: Data) -> PDEventTrace {
        let bytes = [UInt8](buffer)

        var leadingZeros = 0
        while leadingZeros < bytes.count, bytes[leadingZeros] == 0x00 {
            leadingZeros += 1
        }

        if leadingZeros == 0 {
            return PDEventTrace(rawBuffer: buffer, events: parseAtGuessedSeam(bytes))
        }

        var events: [PDEventRecord] = []
        var index = leadingZeros
        if leadingZeros < 3 {
            // Exactly one byte can be left over, so only the first zero is one.
            // With L == 2 the second is a real record and tokenising from index
            // 1 reads it.
            events.append(PDEventRecord(event: .unknown(0x00), argument: nil, isSeamAffected: true))
            index = 1
        }
        // leadingZeros >= 3: unfilled ring, zeros already skipped, no seam.
        events.append(contentsOf: tokenise(bytes, from: index).map(\.record))
        return PDEventTrace(rawBuffer: buffer, events: events)
    }

    /// One record and the index of the byte it starts on.
    private struct PositionedRecord {
        let start: Int
        let record: PDEventRecord
    }

    /// Reads records from `start` to the end of the buffer, none flagged.
    private static func tokenise(_ bytes: [UInt8], from start: Int) -> [PositionedRecord] {
        var records: [PositionedRecord] = []
        var index = start
        while index < bytes.count {
            let recordStart = index
            let opcode = bytes[index]
            index += 1
            var argument: UInt8?
            if opcodesWithArgument.contains(opcode), index < bytes.count {
                argument = bytes[index]
                index += 1
            }
            records.append(PositionedRecord(
                start: recordStart,
                record: PDEventRecord(event: PDEvent(rawValue: opcode), argument: argument)
            ))
        }
        return records
    }

    /// The L == 0 case: tokenises both readings of the first byte, emits the
    /// one `seamLeftoverLeads` picks, and flags every record of it that starts
    /// before the two readings first agree on a record boundary.
    private static func parseAtGuessedSeam(_ bytes: [UInt8]) -> [PDEventRecord] {
        guard let first = bytes.first else { return [] }

        // H1: index 0 is a record. H2: index 0 is a leftover argument byte,
        // recorded on its own and always flagged, then records from index 1.
        let h1 = tokenise(bytes, from: 0)
        let h2 = [PositionedRecord(
            start: 0,
            record: PDEventRecord(event: PDEvent(rawValue: first), argument: nil, isSeamAffected: true)
        )] + tokenise(bytes, from: 1)

        // The first offset past the seam byte that starts a record under both
        // readings. The end of the buffer is a boundary under both, so a pair
        // that never meets before it flags every record.
        let h1Starts = Set(h1.map(\.start))
        let reconvergence = h2.map(\.start).first { $0 > 0 && h1Starts.contains($0) } ?? bytes.count

        let chosen = seamLeftoverLeads(bytes) ? h2 : h1
        return chosen.map { positioned in
            guard positioned.start < reconvergence else { return positioned.record }
            return PDEventRecord(
                event: positioned.record.event,
                argument: positioned.record.argument,
                isSeamAffected: true
            )
        }
    }
}

public struct VDMIdentity: Codable, Sendable, Equatable {
    public let vendorId: Int
    public let productId: Int
    public let bcdDevice: Int
    public let specRevision: Int
    public let vdos: [Data]
    public let productType: Int?
    public let productTypeDescription: String?

    public init(
        vendorId: Int,
        productId: Int,
        bcdDevice: Int,
        specRevision: Int,
        vdos: [Data],
        productType: Int?,
        productTypeDescription: String?
    ) {
        self.vendorId = vendorId
        self.productId = productId
        self.bcdDevice = bcdDevice
        self.specRevision = specRevision
        self.vdos = vdos
        self.productType = productType
        self.productTypeDescription = productTypeDescription
    }

    /// Reads `vdos[3]` as a little-endian UInt32 and returns its value,
    /// or nil when VDO[3] is absent or malformed. Used by the diagnostic
    /// view to check the SOP'' Controller Present bit without depending on
    /// the USBPDSOP / PDVDO decode path.
    public var cableVDO3Value: UInt32? {
        guard vdos.count > 3, vdos[3].count == 4 else { return nil }
        let b = vdos[3]
        return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
    }

    /// Reads `vdos[1]`, the Cert Stat VDO, as a little-endian UInt32. That is
    /// the USB-IF-issued XID, or 0 for a cable that never went through
    /// certification (the majority). Nil when VDO[1] is absent or malformed.
    /// Mirrors `USBPDSOP.certStatVDO` for the Pro diagnostic view, which works
    /// from `VDMIdentity` rather than `USBPDSOP`.
    public var certStatXID: UInt32? {
        guard vdos.count > 1, vdos[1].count == 4 else { return nil }
        let b = vdos[1]
        return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
    }

    /// True when the cable's ID Header self-reports as passive (Product Type = 3)
    /// but VDO[3] bit 3 is set. Mirrors `USBPDSOP.hasActiveLayoutContradiction`.
    /// Used in the Pro diagnostic view which works from `VDMIdentity` rather
    /// than `USBPDSOP`.
    public var hasActiveLayoutContradiction: Bool {
        guard productType == 3, let vdo3 = cableVDO3Value else { return false }
        return (vdo3 >> 3) & 1 == 1
    }
}
