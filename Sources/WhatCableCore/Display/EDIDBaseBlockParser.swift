import Foundation

/// `A` or `B`, used where a decode can land on either a mode (`EDIDMode`) or a bare fact with
/// no formula behind it (`EDIDInfo.StandardTimingID`). Not `Result`: neither side is an error.
enum Either<A, B> {
    case left(A)
    case right(B)
}

/// Decodes the 128-byte EDID base block into every mode it declares: Established Timings I, II
/// and III, the 8 Standard Timing slots (plus the 6 more a 0xFA descriptor can add), the up to 4
/// Detailed Timing Descriptors, and the CVT 3-byte codes a 0xF8 descriptor can carry. Also reads
/// the 0xFD Display Range Limits descriptor in full and the 0xFC monitor name.
///
/// Byte layouts and formula thresholds are ported from edid-decode (v4l-utils,
/// utils/edid-decode/parse-base-block.cpp, commit f341ed8e3742118a86619e5f499017db2de30d94),
/// SPDX-License-Identifier: MIT, Copyright 2006-2012 Red Hat, Inc., Copyright 2018-2020 Cisco
/// Systems, Inc. The MIT notice is reproduced in THIRD_PARTY_NOTICES.md at the repo root.
///
/// `detailedTiming(_:at:block:index:)` and `standardTiming(byte1:byte2:index:edidMinor:rangeLimits:)`
/// are shared with the CTA-861 and DisplayID VTB-EXT parsers (Tasks 6 to 8): the descriptor layout
/// a standard timing or a detailed timing is built from does not change with the block it appears
/// in, only the coordinates used to label the result.
public enum EDIDBaseBlockParser {
    public struct Result {
        public var modes: [EDIDMode] = []
        public var undecoded: [EDIDInfo.StandardTimingID] = []
        public var rangeLimits: EDIDInfo.RangeLimits?
        public var monitorName: String?
        public var continuousFrequency: Bool?
        public var preferred: EDIDMode?
    }

    /// `bytes` is the whole EDID; the base block is bytes 0..<128.
    public static func parse(_ bytes: [UInt8]) -> Result {
        var result = Result()
        guard bytes.count >= 128 else { return result }

        let edidMajor = Int(bytes[18])
        let edidMinor = Int(bytes[19])
        let isEDID14 = edidMajor == 1 && edidMinor >= 4
        result.continuousFrequency = isEDID14 ? (bytes[24] & 0x01 != 0) : nil

        // Established Timings I & II: bytes 35, 36, 37 bit 7, bit order 7...0.
        for legacy in EDIDEstablishedTimings.legacy {
            guard (bytes[legacy.byte] & (1 << legacy.bit)) != 0 else { continue }
            result.modes.append(EDIDMode(
                width: legacy.width, height: legacy.height,
                hTotal: legacy.hTotal, vTotal: legacy.vTotal,
                pixelClockHz: legacy.pixelClockKHz * 1_000, interlaced: legacy.interlaced,
                source: .establishedTiming(byte: legacy.byte, bit: legacy.bit, dmtID: legacy.dmtID)))
        }

        // Display Range Limits (0xFD) must be found before Standard Timings are decoded below,
        // since the derivation for a non-DMT standard timing depends on it. 0xFC (monitor name)
        // has no such dependency but is found in the same pass since it is just as cheap to.
        let descriptorOffsets = [54, 72, 90, 108]
        for off in descriptorOffsets {
            guard bytes[off] == 0, bytes[off + 1] == 0, bytes[off + 2] == 0 else { continue }
            switch bytes[off + 3] {
            case 0xFD:
                result.rangeLimits = Self.rangeLimits(bytes, at: off, isEDID14: isEDID14)
            case 0xFC:
                result.monitorName = Self.decodeDescriptorString(Array(bytes[(off + 5)..<(off + 18)]))
            default:
                break
            }
        }

        // Detailed Timing Descriptors and the other display descriptors (0xF7, 0xF8, 0xFA),
        // in slot order. `dtdIndex` only advances on a real DTD, matching how `.detailedTiming`
        // indexes within a block.
        var dtdIndex = 0
        for off in descriptorOffsets {
            let isDisplayDescriptor = bytes[off] == 0 && bytes[off + 1] == 0 && bytes[off + 2] == 0
            if isDisplayDescriptor {
                switch bytes[off + 3] {
                case 0xF7:
                    result.modes.append(contentsOf: Self.establishedIIIModes(bytes, at: off))
                case 0xF8:
                    result.modes.append(contentsOf: Self.cvtDescriptorModes(bytes, at: off))
                case 0xFA:
                    Self.appendStandardTimings(
                        bytes, at: off + 5, count: 6, startIndex: 8, edidMinor: edidMinor,
                        rangeLimits: result.rangeLimits, into: &result)
                default:
                    break
                }
                continue
            }
            guard let mode = Self.detailedTiming(bytes, at: off, block: 0, index: dtdIndex) else { continue }
            result.modes.append(mode)
            if result.preferred == nil { result.preferred = mode }
            dtdIndex += 1
        }

        // Standard Timings, bytes 38-53, slots 0-7.
        Self.appendStandardTimings(
            bytes, at: 38, count: 8, startIndex: 0, edidMinor: edidMinor,
            rangeLimits: result.rangeLimits, into: &result)

        return result
    }

    /// Decode `count` standard-timing pairs starting at byte offset `start`, appending each
    /// result to `result.modes` or `result.undecoded`. Shared by the base 8 slots (bytes 38-53)
    /// and the 6 more a 0xFA descriptor carries (descriptor bytes 5-16).
    private static func appendStandardTimings(
        _ bytes: [UInt8], at start: Int, count: Int, startIndex: Int, edidMinor: Int,
        rangeLimits: EDIDInfo.RangeLimits?, into result: inout Result
    ) {
        for i in 0..<count {
            let off = start + i * 2
            guard let decoded = Self.standardTiming(
                byte1: bytes[off], byte2: bytes[off + 1], index: startIndex + i,
                edidMinor: edidMinor, rangeLimits: rangeLimits)
            else { continue }
            switch decoded {
            case .left(let mode): result.modes.append(mode)
            case .right(let undecodedID): result.undecoded.append(undecodedID)
            }
        }
    }

    // MARK: - Detailed timing (shared with the CTA and VTB parsers)

    /// Decode the 18-byte detailed timing descriptor at `off`. Returns nil when the slot is a
    /// display descriptor instead (bytes 0-1 zero) or the pixel clock is below 10 MHz, which
    /// edid-decode treats as invalid data (`detailed_timings`, parse-base-block.cpp:988) rather
    /// than a real (if oddly slow) mode.
    ///
    /// `hTotal = hact + hblank` and `vTotal = vact + vblank` directly off the raw bytes, with no
    /// border term: edid-decode's own blanking figure already has the border subtracted out
    /// before its front/back porch split (`hbl = raw_hblank - hborder*2`), and border pixels are
    /// still inside the raw blanking word, so by the time the two are added back together in
    /// `print_timings`' total the border term cancels. Reading `hact + hblank` straight off the
    /// bytes gets the same total without the subtract/re-add round trip.
    public static func detailedTiming(_ bytes: [UInt8], at off: Int, block: Int, index: Int) -> EDIDMode? {
        guard off + 17 < bytes.count else { return nil }
        let pixelClock10kHz = Int(bytes[off]) | (Int(bytes[off + 1]) << 8)
        let pixelClockKHz = pixelClock10kHz * 10
        guard pixelClockKHz >= 10_000 else { return nil } // below 10 MHz (including 0): invalid data
        let hActive = Int(bytes[off + 2]) | ((Int(bytes[off + 4]) & 0xF0) << 4)
        let hBlank = Int(bytes[off + 3]) | ((Int(bytes[off + 4]) & 0x0F) << 8)
        let vActiveField = Int(bytes[off + 5]) | ((Int(bytes[off + 7]) & 0xF0) << 4)
        let vBlankField = Int(bytes[off + 6]) | ((Int(bytes[off + 7]) & 0x0F) << 8)
        let interlaced = (bytes[off + 17] & 0x80) != 0

        let height: Int
        let vTotal: Int
        if interlaced {
            // Per-field values from the bytes; the frame is two fields plus the half line
            // each field carries (edid-decode's `t.vact *= 2` plus its own field-blanking
            // math folds to this once totalled: VIC 5 checks, 2 * (540 + 22) + 1 = 1125).
            height = 2 * vActiveField
            vTotal = 2 * (vActiveField + vBlankField) + 1
        } else {
            height = vActiveField
            vTotal = vActiveField + vBlankField
        }

        return EDIDMode(
            width: hActive, height: height, hTotal: hActive + hBlank, vTotal: vTotal,
            pixelClockHz: pixelClockKHz * 1_000, interlaced: interlaced,
            source: .detailedTiming(block: block, index: index))
    }

    // MARK: - Standard timing (shared with the 0xFA descriptor and VTB-EXT)

    /// Decode one 2-byte standard timing. Returns nil for the unused code (edid-decode's
    /// `print_standard_timing` only accepts `0x01 0x01` as the sanctioned form, but treats any
    /// `byte1 <= 0x01` the same way). `edidMinor` and `rangeLimits` pick the derivation:
    /// a DMT match always wins; otherwise EDID 1.4 uses the range-limits descriptor's declared
    /// formula (CVT, default GTF, or the secondary GTF curve when its start frequency licenses
    /// it), 1.4 with only a range-limits-only descriptor or none at all has no formula the EDID
    /// licenses; EDID 1.2/1.3 always assumes GTF (edid-decode's comment: "An EDID 1.3 source
    /// will assume GTF"); below 1.2 there is no formula either.
    ///
    /// `gtfOnly` mirrors `print_standard_timing`'s `gtf_only` argument (`parse-vtb-ext-block.cpp`
    /// passes `true`): a VTB-EXT standard timing always derives by the default GTF formula,
    /// never CVT or the secondary GTF curve, whatever `rangeLimits` or `edidMinor` say, and the
    /// aspect-bits-0 case always reads 16:10 (never 1:1) too, matching
    /// `if (gtf_only || show_both || base.edid_minor >= 3)`. Default `false` keeps every existing
    /// (base-block, 0xFA descriptor) caller unchanged.
    ///
    /// A formula that has no finite answer for the timing (`EDIDTimingFormulas.gtf` / `cvt`
    /// return nil) leaves the standard timing as an undecoded fact, the same as a formula the
    /// EDID does not license: the id is real, the timing is not computable.
    static func standardTiming(
        byte1: UInt8, byte2: UInt8, index: Int, edidMinor: Int, rangeLimits: EDIDInfo.RangeLimits?,
        gtfOnly: Bool = false
    ) -> Either<EDIDMode, EDIDInfo.StandardTimingID>? {
        guard byte1 > 0x01 else { return nil }

        let standardCode = (UInt16(byte1) << 8) | UInt16(byte2)
        if let dmt = EDIDTimingTables.dmt(standardCode: standardCode) {
            return .left(EDIDMode(
                width: dmt.width, height: dmt.height, hTotal: dmt.hTotal, vTotal: dmt.vTotal,
                pixelClockHz: dmt.pixelClockKHz * 1_000, interlaced: dmt.interlaced,
                source: .standardTiming(index: index, derivation: .dmt, dmtID: dmt.id)))
        }

        let hact = (Int(byte1) + 31) * 8
        let aspectBits = (byte2 >> 6) & 0x03
        let hratio: Int
        let vratio: Int
        switch aspectBits {
        case 0x00: (hratio, vratio) = (gtfOnly || edidMinor >= 3) ? (16, 10) : (1, 1)
        case 0x01: (hratio, vratio) = (4, 3)
        case 0x02: (hratio, vratio) = (5, 4)
        default: (hratio, vratio) = (16, 9) // 0x03
        }
        let vact = (hact * vratio) / hratio
        let refresh = Int(byte2 & 0x3F) + 60

        func undecoded() -> Either<EDIDMode, EDIDInfo.StandardTimingID> {
            .right(EDIDInfo.StandardTimingID(width: hact, height: vact, refreshHz: refresh, sourceIndex: index))
        }

        func mode(_ timing: EDIDTimingFormulas.Timing, _ derivation: EDIDMode.Derivation) -> Either<EDIDMode, EDIDInfo.StandardTimingID> {
            .left(EDIDMode(
                width: hact, height: vact, hTotal: timing.hTotal, vTotal: timing.vTotal,
                pixelClockHz: timing.pixelClockKHz * 1_000, interlaced: false,
                source: .standardTiming(index: index, derivation: derivation, dmtID: nil)))
        }

        if gtfOnly {
            guard let timing = EDIDTimingFormulas.gtf(width: hact, height: vact, refreshHz: Double(refresh)) else { return undecoded() }
            return mode(timing, .gtf)
        }

        if edidMinor >= 4 {
            switch rangeLimits?.timingSupport {
            case .cvt:
                guard let timing = EDIDTimingFormulas.cvt(width: hact, height: vact, refreshHz: Double(refresh), blanking: .standard) else { return undecoded() }
                return mode(timing, .cvt)
            case .defaultGTF:
                guard let timing = EDIDTimingFormulas.gtf(width: hact, height: vact, refreshHz: Double(refresh)) else { return undecoded() }
                return mode(timing, .gtf)
            case .secondaryGTF(let startFrequencyKHz, let c, let m, let k, let j):
                let curve = EDIDTimingFormulas.GTFSecondaryCurve(c: c, m: Double(m), k: Double(k), j: j, startFrequencyKHz: startFrequencyKHz)
                guard let (timing, derivation) = Self.gtfApplyingSecondary(width: hact, height: vact, refreshHz: Double(refresh), curve: curve) else { return undecoded() }
                return mode(timing, derivation)
            case .rangeLimitsOnly, .unknown, nil:
                return undecoded()
            }
        } else if edidMinor == 2 || edidMinor == 3 {
            if case .secondaryGTF(let startFrequencyKHz, let c, let m, let k, let j) = rangeLimits?.timingSupport {
                let curve = EDIDTimingFormulas.GTFSecondaryCurve(c: c, m: Double(m), k: Double(k), j: j, startFrequencyKHz: startFrequencyKHz)
                guard let (timing, derivation) = Self.gtfApplyingSecondary(width: hact, height: vact, refreshHz: Double(refresh), curve: curve) else { return undecoded() }
                return mode(timing, derivation)
            }
            guard let timing = EDIDTimingFormulas.gtf(width: hact, height: vact, refreshHz: Double(refresh)) else { return undecoded() }
            return mode(timing, .gtf)
        } else {
            return undecoded()
        }
    }

    /// Compute the default GTF curve, then recompute with the secondary curve when its start
    /// frequency licenses it (the default curve's horizontal frequency is at or above
    /// `curve.startFrequencyKHz`). Mirrors the check `EDIDTimingFormulas.gtf(secondary:)` makes
    /// internally; done here too so the caller knows which curve was actually used, for the
    /// `.gtf` / `.gtfSecondary` label. Nil when the curve the EDID licenses has no finite
    /// timing for the inputs; the default curve is not substituted for it.
    private static func gtfApplyingSecondary(
        width: Int, height: Int, refreshHz: Double, curve: EDIDTimingFormulas.GTFSecondaryCurve
    ) -> (EDIDTimingFormulas.Timing, EDIDMode.Derivation)? {
        guard let primary = EDIDTimingFormulas.gtf(width: width, height: height, refreshHz: refreshHz) else { return nil }
        let horFreqKHz = Double(primary.pixelClockKHz) / Double(primary.hTotal)
        guard horFreqKHz >= Double(curve.startFrequencyKHz) else { return (primary, .gtf) }
        guard let secondary = EDIDTimingFormulas.gtf(width: width, height: height, refreshHz: refreshHz, secondary: curve) else { return nil }
        return (secondary, .gtfSecondary)
    }

    // MARK: - CVT 3-byte codes (shared with VTB-EXT)

    /// Decode one 3-byte CVT code into up to 5 modes, one per supported refresh bit in `code.2`.
    /// Ported from edid-decode's `detailed_cvt_descriptor` (parse-base-block.cpp:418). A refresh
    /// bit whose CVT timing has no finite answer yields no mode.
    public static func cvtCodeModes(_ code: (UInt8, UInt8, UInt8), block: Int, index: Int) -> [EDIDMode] {
        let (b0, b1, b2) = code
        let vact = ((Int(b0) | (Int(b1 & 0xF0) << 4)) + 1) * 2
        let hratio: Int
        let vratio: Int
        switch b1 & 0x0C {
        case 0x00: (hratio, vratio) = (4, 3)
        case 0x04: (hratio, vratio) = (16, 9)
        case 0x08: (hratio, vratio) = (16, 10)
        default: (hratio, vratio) = (15, 9) // 0x0C
        }
        let hact = 8 * (((vact * hratio) / vratio) / 8)

        // (bit in byte 2, refresh Hz, reduced blanking v1)
        let rates: [(bit: UInt8, refreshHz: Int, reducedBlanking: Bool)] = [
            (0x10, 50, false), (0x08, 60, false), (0x04, 75, false), (0x02, 85, false), (0x01, 60, true),
        ]
        var modes: [EDIDMode] = []
        for rate in rates {
            guard (b2 & rate.bit) != 0 else { continue }
            let blanking: EDIDTimingFormulas.CVTBlanking = rate.reducedBlanking ? .reducedV1 : .standard
            guard let timing = EDIDTimingFormulas.cvt(width: hact, height: vact, refreshHz: Double(rate.refreshHz), blanking: blanking) else { continue }
            modes.append(EDIDMode(
                width: hact, height: vact, hTotal: timing.hTotal, vTotal: timing.vTotal,
                pixelClockHz: timing.pixelClockKHz * 1_000, interlaced: false,
                source: .cvtCode(block: block, index: index, refreshHz: rate.refreshHz, reducedBlanking: rate.reducedBlanking)))
        }
        return modes
    }

    // MARK: - Descriptor decoders (base block only: 0xF7, 0xF8, 0xFD)

    /// 0xF7 Established Timings III: descriptor byte 5 is the version (edid-decode fails if it
    /// isn't 1, but still decodes the bitmap regardless), bytes 6-11 are a 48-bit map read bit 7
    /// first. `EDIDEstablishedTimings.iiiDMTIDs` is indexed the same way.
    private static func establishedIIIModes(_ bytes: [UInt8], at off: Int) -> [EDIDMode] {
        var modes: [EDIDMode] = []
        for (i, dmtID) in EDIDEstablishedTimings.iiiDMTIDs.enumerated() {
            let descriptorByte = 6 + i / 8
            let bit = 7 - i % 8
            guard (bytes[off + descriptorByte] & (1 << bit)) != 0 else { continue }
            guard let dmt = EDIDTimingTables.dmt[dmtID] else { continue }
            modes.append(EDIDMode(
                width: dmt.width, height: dmt.height, hTotal: dmt.hTotal, vTotal: dmt.vTotal,
                pixelClockHz: dmt.pixelClockKHz * 1_000, interlaced: dmt.interlaced,
                // Offset by 1000 so this never collides with a bytes-35-37 established-timing
                // byte number: 1006...1011.
                source: .establishedTiming(byte: 1000 + descriptorByte, bit: bit, dmtID: dmtID)))
        }
        return modes
    }

    /// 0xF8 CVT 3-byte Timing Codes: descriptor byte 5 must be version 1 (else edid-decode skips
    /// the whole descriptor), then four 3-byte codes at descriptor bytes 6, 9, 12, 15. An
    /// all-zero code after the first is absent (edid-decode's `!first && !memcmp(x, empty, 3)`).
    private static func cvtDescriptorModes(_ bytes: [UInt8], at off: Int) -> [EDIDMode] {
        guard bytes[off + 5] == 1 else { return [] }
        var modes: [EDIDMode] = []
        for i in 0..<4 {
            let codeOff = off + 6 + i * 3
            let code = (bytes[codeOff], bytes[codeOff + 1], bytes[codeOff + 2])
            if i > 0, code == (0, 0, 0) { continue }
            modes.append(contentsOf: Self.cvtCodeModes(code, block: 0, index: i))
        }
        return modes
    }

    /// 0xFD Display Range Limits. `off` is the base-block offset of the descriptor's first byte
    /// (the zero that marks it a display descriptor, i.e. `x[0]` in edid-decode's
    /// `detailed_display_range_limits`, parse-base-block.cpp:681).
    private static func rangeLimits(_ bytes: [UInt8], at off: Int, isEDID14: Bool) -> EDIDInfo.RangeLimits {
        var vMaxOffset = 0, vMinOffset = 0, hMaxOffset = 0, hMinOffset = 0
        if isEDID14 {
            let flags = bytes[off + 4]
            if flags & 0x02 != 0 {
                vMaxOffset = 255
                if flags & 0x01 != 0 { vMinOffset = 255 }
            }
            if flags & 0x08 != 0 {
                hMaxOffset = 255
                if flags & 0x04 != 0 { hMinOffset = 255 }
            }
        }
        let minV = Int(bytes[off + 5]) + vMinOffset
        let maxV = Int(bytes[off + 6]) + vMaxOffset
        let minH = Int(bytes[off + 7]) + hMinOffset
        let maxH = Int(bytes[off + 8]) + hMaxOffset
        let pclk10MHz = Int(bytes[off + 9])
        let maxPixelClockHz = pclk10MHz != 0 ? pclk10MHz * 10_000_000 : nil

        let timingSupport: EDIDInfo.RangeLimits.TimingSupport
        switch bytes[off + 10] {
        case 0x00:
            timingSupport = .defaultGTF
        case 0x01:
            timingSupport = .rangeLimitsOnly
        case 0x02 where bytes[(off + 12)...(off + 17)].allSatisfy({ $0 == 0 }):
            // Byte 10 says 0x02 but the curve block (bytes 12 to 17) is empty. edid-decode's
            // `preparse_detailed_block` sets `supports_sec_gtf = !memchk(x + 12, 6)`, so an
            // all-zero block is no curve at all, and the default GTF curve is what the EDID
            // licenses. Applying zeros as C = 0 / M = 0 would give a mode with no horizontal
            // blanking, which no curve declared.
            timingSupport = .defaultGTF
        case 0x02:
            timingSupport = .secondaryGTF(
                startFrequencyKHz: Int(bytes[off + 12]) * 2,
                c: Double(bytes[off + 13]) / 2.0,
                m: (Int(bytes[off + 15]) << 8) | Int(bytes[off + 14]),
                k: Int(bytes[off + 16]),
                j: Double(bytes[off + 17]) / 2.0)
        case 0x04:
            let version = "\((bytes[off + 11] & 0xF0) >> 4).\(bytes[off + 11] & 0x0F)"
            let rawOffset = (bytes[off + 12] & 0xFC) >> 2
            let realMaxPixelClockHz: Int?
            if rawOffset != 0, pclk10MHz != 0 {
                realMaxPixelClockHz = Int((Double(pclk10MHz * 10) - Double(rawOffset) * 0.25) * 1_000_000)
            } else {
                realMaxPixelClockHz = nil
            }
            let maxActivePixels = ((Int(bytes[off + 12] & 0x03) << 8) | Int(bytes[off + 13])) * 8
            timingSupport = .cvt(
                version: version,
                maxActivePixelsPerLine: maxActivePixels != 0 ? maxActivePixels : nil,
                standardBlanking: bytes[off + 15] & 0x08 != 0,
                reducedBlanking: bytes[off + 15] & 0x10 != 0,
                preferredRefreshHz: bytes[off + 17] != 0 ? Int(bytes[off + 17]) : nil,
                realMaxPixelClockHz: realMaxPixelClockHz)
        default:
            timingSupport = .unknown(bytes[off + 10])
        }

        return EDIDInfo.RangeLimits(
            minVerticalHz: minV, maxVerticalHz: maxV,
            minHorizontalKHz: minH, maxHorizontalKHz: maxH,
            maxPixelClockHz: maxPixelClockHz, timingSupport: timingSupport)
    }

    /// Decode a 13-byte EDID text payload (monitor name / serial). Same rule as the code this
    /// replaces in `EDIDInfo`: ASCII only (0x20-0x7E), stopping at the first byte outside that
    /// range so a misbehaving monitor (a non-ASCII or Latin-1 byte) can't produce garbled output.
    private static func decodeDescriptorString(_ raw: [UInt8]) -> String? {
        var out = ""
        for b in raw {
            guard b >= 0x20, b <= 0x7E else { break }
            out.append(Character(UnicodeScalar(b)))
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
