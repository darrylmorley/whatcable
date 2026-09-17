import Foundation

/// Walks one CTA-861 extension block (EDID extension tag 0x02) through every data block that
/// can name a mode, plus the Video Format Preference block and the trailing DTDs. The same data
/// block walk also runs over a DisplayID "CTA-861 DisplayID Data Block" payload (DisplayID tag
/// 0x81), which is a bare run of CTA data blocks with no 4-byte CTA block header; that reuse is
/// `dataBlocks(_:range:block:into:)`, called directly by `EDIDDisplayIDParser`'s 0x81 case.
///
/// Byte layout: `cta_block` / `parse_cta_block` (CTA-861-H section 7.5, edid-decode from
/// v4l-utils, utils/edid-decode/parse-cta-block.cpp, commit
/// f341ed8e3742118a86619e5f499017db2de30d94, MIT; `parse_cta_block` at line 3160, `cta_block` at
/// line 2796). Block header: byte 1 revision, byte 2 `d` (offset of the first DTD from the block
/// start; a value below 4 means no data blocks and no DTDs, 0 included), byte 3 flags. Data
/// blocks run from byte 4 to `d - 1`, only when the block's own revision is 3 or higher
/// (`parse_cta_block` gates the `cta_block` walk on `version >= 3`; revision 1 and 2 blocks carry
/// DTDs only, per the same function). Each data block's header byte is `tag = b >> 5`,
/// `length = b & 0x1F`; tag 7 is extended, and when `length > 0` the next byte is the extended tag,
/// counted in `length`. DTDs run from byte `d` in 18-byte steps until an all-zero slot or byte
/// 127 (the block's own checksum, never walked into); a display descriptor in a slot (bytes 0-1
/// zero, the rest not) is skipped, not a stop.
public enum EDIDCTAParser {
    public struct Result {
        public var modes: [EDIDMode] = []
        /// VFPDB (extended tag 0x0D) entries that name a VIC, in order. A preference, never a
        /// mode source: `cta_print_svr` (line 842) prints these but never adds them as a mode.
        public var preferredVICs: [Int] = []
        /// VFPDB entries 129...144, converted to DTD index 1...16 (counting the base block's DTD
        /// then every CTA DTD in declaration order).
        public var preferredDTDIndices: [Int] = []
        /// Both the block's own checksum (byte 127 sums the 128 bytes to 0 mod 256).
        public var checksumValid: Bool = false

        public init() {}
    }

    /// `base` is the offset of the 0x02 tag byte.
    public static func parse(_ bytes: [UInt8], base: Int, block: Int) -> Result {
        var result = Result()
        guard base + 4 <= bytes.count else { return result }

        let revision = bytes[base + 1]
        let d = Int(bytes[base + 2])
        // Byte 127 is the block's own checksum; data blocks and DTDs never read into it. A
        // truncated buffer (byte 126 under-declaring the extension count, see EDIDInfo) is
        // walked only as far as what is actually present.
        let blockEnd = min(base + 127, bytes.count)

        if d >= 4, d <= 127 {
            // `parse_cta_block` line ~3186: `if (version >= 3) { for (i = 4; i < offset; ...) cta_block(...); }`.
            // Revision 1 and 2 blocks skip the data block walk entirely and go straight to DTDs.
            if revision >= 3 {
                let dataBlocksEnd = min(base + d, blockEnd)
                if base + 4 <= dataBlocksEnd {
                    dataBlocks(bytes, range: (base + 4)..<dataBlocksEnd, block: block, into: &result)
                }
            }

            // `parse_cta_block` (parse-cta-block.cpp, the "Detailed Timing Descriptors" loop):
            // the walk stops only on an all-zero 18-byte slot (`if (memchk(detailed, 18))
            // break;`). A slot whose bytes 0-1 are zero but is not all zero is a display
            // descriptor (edid-decode hands it to `detailed_block`, which prints it as a
            // descriptor); it yields no mode and the walk continues past it, so a DTD declared
            // after one is still reached. `detailedTiming` returns nil for such a slot.
            var off = base + d
            var ctaIndex = 0
            while off + 18 <= blockEnd {
                if bytes[off..<(off + 18)].allSatisfy({ $0 == 0 }) { break } // padding marks the end
                if let mode = EDIDBaseBlockParser.detailedTiming(bytes, at: off, block: block, index: ctaIndex) {
                    result.modes.append(mode)
                    ctaIndex += 1
                }
                off += 18
            }
        }

        if base + 128 <= bytes.count {
            let sum = bytes[base..<(base + 128)].reduce(UInt8(0)) { $0 &+ $1 }
            result.checksumValid = sum == 0
        }

        return result
    }

    // MARK: - Data block walk

    /// Walk a run of CTA data blocks (the block body from byte 4 to `d - 1`, or a DisplayID
    /// 0x81 payload, which is the same bare run with no leading 4-byte CTA block header).
    /// `cta_block`, line 2796: `length = x[0] & 0x1f`, `tag = x[0] >> 5`; when `tag == 0x07`
    /// (extended) and `length > 0`, the next byte is the extended tag and `length` counts it, so
    /// the walk's own step (`off + 1 + originalLength`) is identical whether or not the block is
    /// extended.
    public static func dataBlocks(_ bytes: [UInt8], range: Range<Int>, block: Int, into result: inout Result) {
        var off = range.lowerBound
        while off < range.upperBound, off < bytes.count {
            let header = bytes[off]
            let baseTag = (header & 0xE0) >> 5
            let originalLength = Int(header & 0x1F)

            var payloadStart = off + 1
            var extendedTag: UInt8? = nil
            if baseTag == 0x07 && originalLength > 0 {
                guard payloadStart < bytes.count else { break }
                extendedTag = bytes[payloadStart]
                payloadStart += 1
            }

            let nextOff = off + 1 + originalLength
            guard nextOff <= range.upperBound, nextOff <= bytes.count, payloadStart <= nextOff else { break }
            let p = bytes[payloadStart..<nextOff]

            if let ext = extendedTag {
                switch ext {
                case 0x0D: // Video Format Preference Data Block. `cta_vfpdb`, line 906.
                    vfpdb(p, into: &result)
                case 0x0E: // YCbCr 4:2:0 Video Data Block. `cta_svd(x, length, true)`.
                    svd(p, block: block, ycbcr420Only: true, into: &result)
                case 0x22: // DisplayID Type VII VTDB. `cta_displayid_type_7`, line 2643.
                    decodeType7VTDB(p, block: block, into: &result)
                case 0x23: // DisplayID Type VIII VTDB. `cta_displayid_type_8`, line 2654.
                    decodeType8VTDB(p, block: block, into: &result)
                case 0x2A: // DisplayID Type X VTDB. `cta_displayid_type_10`, line 2684.
                    decodeType10VTDB(p, block: block, into: &result)
                default:
                    // Every other extended tag (audio, vendor, colorimetry, HDR, HDMI forum,
                    // native video resolution, the 4:2:0 capability map, ...) carries no mode
                    // this model has a slot for, and is skipped by length alone.
                    break
                }
            } else if baseTag == 0x02 { // Video Data Block. `cta_svd(x, length, false)`.
                svd(p, block: block, ycbcr420Only: false, into: &result)
            }
            // Every other plain tag (audio, vendor-specific, speaker allocation, VESA transfer
            // characteristics, video format) carries no mode and is skipped by length alone.

            off = nextOff
        }
    }

    // MARK: - Video Data Block / YCbCr 4:2:0 Video Data Block

    /// `cta_svd`, line 578. Each byte is a Short Video Descriptor. `(svd & 0x7f) == 0` (byte 0 or
    /// 0x80) is a skipped filler entry. When `(svd - 1) & 0x40 != 0` (svd in 65...127 or
    /// 193...255) the whole byte is the VIC with no native bit; otherwise `vic = svd & 0x7f`,
    /// `native = svd & 0x80`. VICs 128...192 are forbidden SVD values (never reached: they fall
    /// under the `(svd & 0x7f) == 0` skip only for svd == 128 itself; 129...192 decode through
    /// the "otherwise" branch like any other low VIC, per the reference code as written). An SVD
    /// naming a VIC absent from `EDIDTimingTables.vic` decodes to nothing.
    private static func svd(_ p: ArraySlice<UInt8>, block: Int, ycbcr420Only: Bool, into result: inout Result) {
        for byte in p {
            guard byte & 0x7F != 0 else { continue }
            let vic: Int
            let native: Bool
            if (Int(byte) - 1) & 0x40 != 0 {
                vic = Int(byte)
                native = false
            } else {
                vic = Int(byte & 0x7F)
                native = byte & 0x80 != 0
            }
            guard let t = EDIDTimingTables.vic[vic] else { continue }
            result.modes.append(EDIDMode(
                width: t.width, height: t.height, hTotal: t.hTotal, vTotal: t.vTotal,
                pixelClockHz: t.pixelClockKHz * 1000, interlaced: t.interlaced,
                source: .ctaVIC(block: block, vic: vic, native: native, ycbcr420Only: ycbcr420Only)
            ))
        }
    }

    // MARK: - Video Format Preference Data Block

    /// `cta_vfpdb` (line 906) walking each byte through `cta_print_svr` (line 842). Only the two
    /// SVR ranges this model has a slot for are recorded: 1...127 and 193...253 name a VIC
    /// (`preferredVICs`), 129...144 name a DTD by index 1...16 (`preferredDTDIndices`).
    /// 145...160 (VTDB reference), 161...175 (RID) and 254 (T8VTDB) are read by edid-decode but
    /// create no mode and have no slot here, so they are read and discarded.
    private static func vfpdb(_ p: ArraySlice<UInt8>, into result: inout Result) {
        for svr in p {
            if (svr > 0 && svr < 128) || (svr > 192 && svr < 254) {
                result.preferredVICs.append(Int(svr))
            } else if svr >= 129 && svr <= 144 {
                result.preferredDTDIndices.append(Int(svr) - 128)
            }
        }
    }

    // MARK: - Embedded DisplayID VTDBs

    /// `cta_displayid_type_7`, line 2643: payload byte 0 is the revision, the record (`x + 1`)
    /// is decoded by `parse_displayid_type_1_7_timing`, the same layout `typeIorVII` already
    /// implements for the DisplayID-native Type VII data block. Exactly one record, unlike the
    /// DisplayID-native block which loops. The record is `20 + ((revision & 0x70) >> 4)` bytes
    /// (the revision byte's bits 6-4 count the extra bytes), and edid-decode records "Empty
    /// Data Block" and decodes nothing when the payload is shorter than the revision byte
    /// plus that (`if (length < 21U + ((x[0] & 0x70) >> 4))`). Reading a shorter payload as
    /// a 20-byte record would make a mode out of a block that declares none.
    private static func decodeType7VTDB(_ p: ArraySlice<UInt8>, block: Int, into result: inout Result) {
        guard p.startIndex + 1 <= p.endIndex else { return }
        let revision = p[p.startIndex]
        guard p.count >= 21 + Int((revision & 0x70) >> 4) else { return }
        let record = p[(p.startIndex + 1)...]
        if let mode = EDIDDisplayIDTimingDecoders.typeIorVII(
            record, clockUnitHz: 1_000, block: block, index: 0, embeddedInCTA: true
        ) {
            result.modes.append(mode)
        }
    }

    /// `cta_displayid_type_8`, line 2654: payload byte 0 is the revision; bit 3 selects 2-byte
    /// ids, bits 7-6 are the code type. Unlike the DisplayID-native Type VIII block (which
    /// decodes DMT, VIC and HDMI-VIC code types alike), edid-decode only decodes this
    /// CTA-embedded variant for code type 0 (DMT): `if (type) { fail(...); return; }`. A non-zero
    /// code type here yields nothing, for the whole block, not per id.
    private static func decodeType8VTDB(_ p: ArraySlice<UInt8>, block: Int, into result: inout Result) {
        guard let revision = p.first else { return }
        let codeType = (revision & 0xC0) >> 6
        guard codeType == 0 else { return }
        let twoByteIDs = revision & 0x08 != 0
        let ids = p[(p.startIndex + 1)...]

        var index = 0
        if twoByteIDs {
            var i = ids.startIndex
            while i + 1 < ids.endIndex {
                let id = Int(ids[i]) | (Int(ids[i + 1]) << 8)
                if let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(
                    codeType: 0, id: id, type: .typeVIII, block: block, index: index, embeddedInCTA: true
                ) {
                    result.modes.append(mode)
                }
                i += 2; index += 1
            }
        } else {
            for i in ids.indices {
                let id = Int(ids[i])
                if let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(
                    codeType: 0, id: id, type: .typeVIII, block: block, index: index, embeddedInCTA: true
                ) {
                    result.modes.append(mode)
                }
                index += 1
            }
        }
    }

    /// `cta_displayid_type_10`, line 2684: payload byte 0 is the revision, record size
    /// `6 + ((rev & 0x70) >> 4)`, then records back to back.
    private static func decodeType10VTDB(_ p: ArraySlice<UInt8>, block: Int, into result: inout Result) {
        guard let revision = p.first else { return }
        let recordSize = 6 + Int((revision & 0x70) >> 4)
        guard (6...8).contains(recordSize) else { return }

        var i = p.startIndex + 1
        var index = 0
        while i + recordSize <= p.endIndex {
            if let mode = EDIDDisplayIDTimingDecoders.typeX(
                p[i..<(i + recordSize)], recordSize: recordSize, block: block, index: index, embeddedInCTA: true
            ) {
                result.modes.append(mode)
            }
            i += recordSize; index += 1
        }
    }
}
