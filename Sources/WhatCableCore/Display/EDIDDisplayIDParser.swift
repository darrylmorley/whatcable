import Foundation

/// Walks one DisplayID extension block (EDID extension tag 0x70) through every data block that
/// can name a mode, plus the video-timing-range, dynamic-range and tiled-topology blocks the
/// model exposes. One call per 0x70 block; `EDIDInfo.init?(Data)` calls this once for each
/// DisplayID block an EDID carries and combines the results (all modes kept; `tiledTopology`,
/// `rangeLimits` and `dynamicRangeLimits` from the first block that carries each).
///
/// Byte layout: `displayid_block` / `parse_displayid_block` in edid-decode (v4l-utils,
/// utils/edid-decode/parse-displayid-block.cpp, commit f341ed8e3742118a86619e5f499017db2de30d94,
/// MIT). Section header at block bytes 1-4 (version, length, product type, extension count);
/// data blocks (tag, revision, payload length, payload) start at block byte 5 and run until
/// `5 + length` or a zero tag / zero length terminator. Section length counts data-block bytes
/// only, never the checksum at byte 127; a data block whose header plus payload would run past
/// the section is corrupt and stops the whole section, rather than being skipped alone.
///
/// Tag vs section version: a data block decodes by its OWN tag, whatever the section version
/// says. edid-decode's `tag_version` check treats a mismatch as a spec violation and warns, but
/// still decodes by tag. Whether any corpus EDID carries a 2.0 tag (0x20-0x2e) in a 1.x section
/// or a 1.x tag (0x00-0x13) in a 2.0 section is measured in
/// `research/findings/edid-mode-sources.md`; the rule is the spec's, not a corpus fit.
public enum EDIDDisplayIDParser {
    public struct Result {
        public var modes: [EDIDMode] = []
        public var tiledTopology: EDIDInfo.TiledTopology?
        public var rangeLimits: EDIDInfo.RangeLimits?
        public var dynamicRangeLimits: EDIDInfo.DynamicRangeLimits?
        public var discreteFrequency: Bool = false
        public var version: UInt8 = 0
        public var checksumValid: Bool = false
        /// CTA Video Format Preference VICs, from a 0x81 CTA-861 DisplayID Data Block, if any.
        public var ctaPreferredVICs: [Int] = []
        /// The first Type I / Type VII record in this section that sets the preferred flag
        /// (byte 3 bit 7, data block revision (byte 1 & 0x07) below 2:
        /// `EDIDDisplayIDTimingDecoders.typeIorVIIPreferredFlag`). Nil when no record does.
        public var preferred: EDIDMode?

        public init() {}
    }

    /// `base` is the offset of the 0x70 tag byte within `bytes`; `block` labels sources.
    public static func parse(_ bytes: [UInt8], base: Int, block: Int) -> Result {
        var result = Result()
        guard base + 5 <= bytes.count else { return result }

        let version = bytes[base + 1]
        result.version = version
        let declaredLength = Int(bytes[base + 2])
        // edid-decode's `parse_displayid_block` caps the section length at 121 ("DisplayID
        // length %d is greater than 121", parse-displayid-block.cpp:2743): 5 header bytes, up
        // to 121 data-block bytes and the section checksum fill bytes 0 to 126, and byte 127 is
        // the block's own EDID-extension checksum. The capped length bounds both the walk and
        // the section checksum below, so a corrupt length can never read a neighbouring block.
        let sectionLength = min(declaredLength, 121)
        let sectionEnd = base + 5 + sectionLength

        var off = base + 5
        while off + 3 <= sectionEnd, off + 3 <= bytes.count {
            let tag = bytes[off]
            let revision = bytes[off + 1]
            let payloadLength = Int(bytes[off + 2])
            if tag == 0 && payloadLength == 0 { break } // section end marker

            let payloadStart = off + 3
            let payloadEnd = payloadStart + payloadLength
            // A data block whose header plus payload does not fit inside the section is
            // corrupt or truncated: reject it whole and stop walking the section, rather than
            // reading into the checksum byte or a neighbouring block.
            guard payloadEnd <= sectionEnd, payloadEnd <= bytes.count else { break }

            decodeDataBlock(
                bytes, tag: tag, revision: revision,
                payloadStart: payloadStart, payloadEnd: payloadEnd,
                block: block, into: &result
            )
            off = payloadEnd
        }

        // Both checksums must hold: the section checksum (byte `5 + length`, sum of bytes 1
        // through it is 0 mod 256, edid-decode's `do_checksum(x + 1, saved_length + 5, ...)`)
        // and the EDID-extension checksum (byte 127, the whole 128-byte block sums to 0 mod
        // 256). A declared length above 121 puts its checksum byte at or past byte 127, outside
        // the section, so there is no section checksum to hold and the block reads invalid;
        // the capped range is never summed in its place, because a sum that lands on zero
        // from another block's bytes would be a checksum nothing declared. Corpus EDIDs are
        // serial-redacted, which can break the base block's checksum, but never touches an
        // extension block, so this is safe to report honestly rather than special-cased.
        let sectionChecksumOffset = base + 5 + sectionLength
        if declaredLength <= 121, sectionChecksumOffset < base + 127, base + 128 <= bytes.count {
            let sectionSum = bytes[(base + 1)...sectionChecksumOffset].reduce(UInt8(0)) { $0 &+ $1 }
            let blockSum = bytes[base..<(base + 128)].reduce(UInt8(0)) { $0 &+ $1 }
            result.checksumValid = sectionSum == 0 && blockSum == 0
        }

        return result
    }

    // MARK: - One data block

    /// Decode one data block's payload by tag. `p[i]` is the data block's own `x[i + 3]`
    /// (edid-decode indexes every field off the tag byte at `x[0]`; the payload starts at
    /// `x[3]`), which is how every byte offset below lines up with the plan's citations.
    private static func decodeDataBlock(
        _ bytes: [UInt8], tag: UInt8, revision: UInt8,
        payloadStart: Int, payloadEnd: Int, block: Int, into result: inout Result
    ) {
        let payloadLength = payloadEnd - payloadStart
        let p = Array(bytes[payloadStart..<payloadEnd])

        switch tag {
        case 0x03: // Type I (DisplayID 1.x), 20-byte records
            var i = 0, index = 0
            while i + 20 <= payloadLength {
                let record = bytes[(payloadStart + i)..<(payloadStart + i + 20)]
                if let mode = EDIDDisplayIDTimingDecoders.typeIorVII(
                    record, clockUnitHz: 10_000, block: block, index: index, embeddedInCTA: false
                ) {
                    result.modes.append(mode)
                    if result.preferred == nil,
                       EDIDDisplayIDTimingDecoders.typeIorVIIPreferredFlag(record, revisionByte: revision) {
                        result.preferred = mode
                    }
                }
                i += 20; index += 1
            }

        case 0x22: // Type VII (DisplayID 2.0), 20 bytes plus the revision-nibble extra bytes
            let recordSize = 20 + Int((revision & 0x70) >> 4)
            var i = 0, index = 0
            while i + recordSize <= payloadLength {
                let record = bytes[(payloadStart + i)..<(payloadStart + i + recordSize)]
                if let mode = EDIDDisplayIDTimingDecoders.typeIorVII(
                    record, clockUnitHz: 1_000, block: block, index: index, embeddedInCTA: false
                ) {
                    result.modes.append(mode)
                    if result.preferred == nil,
                       EDIDDisplayIDTimingDecoders.typeIorVIIPreferredFlag(record, revisionByte: revision) {
                        result.preferred = mode
                    }
                }
                i += recordSize; index += 1
            }

        case 0x04: // Type II, 11-byte records
            var i = 0, index = 0
            while i + 11 <= payloadLength {
                if let mode = EDIDDisplayIDTimingDecoders.typeII(
                    bytes[(payloadStart + i)..<(payloadStart + i + 11)], block: block, index: index
                ) {
                    result.modes.append(mode)
                }
                i += 11; index += 1
            }

        case 0x05: // Type III, 3-byte records
            var i = 0, index = 0
            while i + 3 <= payloadLength {
                if let mode = EDIDDisplayIDTimingDecoders.typeIII(
                    bytes[(payloadStart + i)..<(payloadStart + i + 3)], block: block, index: index
                ) {
                    result.modes.append(mode)
                }
                i += 3; index += 1
            }

        case 0x06: // Type IV, 1 id byte each; code type from revision bits 7-6
            let codeType = (revision & 0xC0) >> 6
            for i in 0..<payloadLength {
                if let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(
                    codeType: codeType, id: Int(p[i]), type: .typeIV, block: block, index: i, embeddedInCTA: false
                ) {
                    result.modes.append(mode)
                }
            }

        case 0x23: // Type VIII, 1- or 2-byte ids (revision bit 3); code type from revision bits 7-6
            let codeType = (revision & 0xC0) >> 6
            if revision & 0x08 != 0 {
                var i = 0, index = 0
                while i + 2 <= payloadLength {
                    let id = Int(p[i]) | (Int(p[i + 1]) << 8)
                    if let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(
                        codeType: codeType, id: id, type: .typeVIII, block: block, index: index, embeddedInCTA: false
                    ) {
                        result.modes.append(mode)
                    }
                    i += 2; index += 1
                }
            } else {
                for i in 0..<payloadLength {
                    if let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(
                        codeType: codeType, id: Int(p[i]), type: .typeVIII, block: block, index: i, embeddedInCTA: false
                    ) {
                        result.modes.append(mode)
                    }
                }
            }

        case 0x07: // VESA DMT bitmap: up to 10 bytes, bit i of byte i/8 (LSB first) means DMT id i+1
            let bitCount = min(payloadLength, 10) * 8
            for i in 0..<bitCount where p[i / 8] & (1 << (i % 8)) != 0 {
                if let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(
                    codeType: 0, id: i + 1, type: .vesaDMTBitmap, block: block, index: i, embeddedInCTA: false
                ) {
                    result.modes.append(mode)
                }
            }

        case 0x08: // CTA VIC bitmap: up to 8 bytes, bit i means VIC i+1
            let bitCount = min(payloadLength, 8) * 8
            for i in 0..<bitCount where p[i / 8] & (1 << (i % 8)) != 0 {
                if let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(
                    codeType: 1, id: i + 1, type: .ctaVICBitmap, block: block, index: i, embeddedInCTA: false
                ) {
                    result.modes.append(mode)
                }
            }

        case 0x09: // video timing range limits, 15-byte record: x3...x17
            guard payloadLength >= 15, result.rangeLimits == nil else { break }
            let pixelClockMaxUnits = (Int(p[3]) | Int(p[4]) << 8 | Int(p[5]) << 16) + 1 // 10 kHz units
            let minHorizontalKHz = Int(p[6])
            let maxHorizontalKHz = Int(p[7])
            let minVerticalHz = Int(p[10])
            let maxVerticalHz = Int(p[11])
            let flags = p[14] // x17
            let cvtSupported = flags & 0x40 != 0
            let cvtReducedBlanking = flags & 0x20 != 0
            result.discreteFrequency = flags & 0x10 != 0
            let timingSupport: EDIDInfo.RangeLimits.TimingSupport = cvtSupported
                ? .cvt(version: "", maxActivePixelsPerLine: nil, standardBlanking: cvtSupported,
                       reducedBlanking: cvtReducedBlanking, preferredRefreshHz: nil, realMaxPixelClockHz: nil)
                : .rangeLimitsOnly
            result.rangeLimits = EDIDInfo.RangeLimits(
                minVerticalHz: minVerticalHz, maxVerticalHz: maxVerticalHz,
                minHorizontalKHz: minHorizontalKHz, maxHorizontalKHz: maxHorizontalKHz,
                maxPixelClockHz: pixelClockMaxUnits * 10_000, timingSupport: timingSupport
            )

        case 0x11: // Type V, 7-byte records
            var i = 0, index = 0
            while i + 7 <= payloadLength {
                if let mode = EDIDDisplayIDTimingDecoders.typeV(
                    bytes[(payloadStart + i)..<(payloadStart + i + 7)], block: block, index: index
                ) {
                    result.modes.append(mode)
                }
                i += 7; index += 1
            }

        case 0x12, 0x28: // tiled display topology, 22-byte record: x3...x24
            guard payloadLength >= 22, result.tiledTopology == nil else { break }
            let hTiles = 1 + (Int(p[1] >> 4) | ((Int(p[3]) >> 2) & 0x30))       // x4, x6
            let vTiles = 1 + (Int(p[1] & 0x0F) | (Int(p[3]) & 0x30))            // x4, x6
            let hLocation = Int(p[2] >> 4) | (((Int(p[3]) >> 2) & 0x3) << 4)    // x5, x6
            let vLocation = Int(p[2] & 0x0F) | ((Int(p[3]) & 0x3) << 4)         // x5, x6
            let tileWidth = 1 + (Int(p[4]) | (Int(p[5]) << 8))                  // x7, x8
            let tileHeight = 1 + (Int(p[6]) | (Int(p[7]) << 8))                 // x9, x10
            result.tiledTopology = EDIDInfo.TiledTopology(
                hTiles: hTiles, vTiles: vTiles, tileWidth: tileWidth, tileHeight: tileHeight,
                hLocation: hLocation, vLocation: vLocation
            )

        case 0x13: // Type VI, 14 bytes, or 17 when the record's own byte 2 bit 6 is set
            var i = 0, index = 0
            while i + 14 <= payloadLength {
                let recordSize = (p[i + 2] & 0x40 != 0) ? 17 : 14
                guard i + recordSize <= payloadLength else { break }
                if let mode = EDIDDisplayIDTimingDecoders.typeVI(
                    bytes[(payloadStart + i)..<(payloadStart + i + recordSize)], block: block, index: index
                ) {
                    result.modes.append(mode)
                }
                i += recordSize; index += 1
            }

        case 0x24: // Type IX, 6-byte records
            var i = 0, index = 0
            while i + 6 <= payloadLength {
                if let mode = EDIDDisplayIDTimingDecoders.typeIX(
                    bytes[(payloadStart + i)..<(payloadStart + i + 6)], block: block, index: index
                ) {
                    result.modes.append(mode)
                }
                i += 6; index += 1
            }

        case 0x25: // dynamic video timing range limits, 9-byte record: x3...x11
            guard payloadLength >= 9, result.dynamicRangeLimits == nil else { break }
            let minPixelClockKHz = (Int(p[0]) | Int(p[1]) << 8 | Int(p[2]) << 16) + 1
            let maxPixelClockKHz = (Int(p[3]) | Int(p[4]) << 8 | Int(p[5]) << 16) + 1
            let minRefreshHz = Int(p[6]) // x9
            let blockRevision = revision & 0x07
            let maxRefreshHz = blockRevision != 0
                ? Int(p[7]) + ((Int(p[8]) & 0x03) << 8) // x10 + (x11 bits 1-0) << 8
                : Int(p[7])
            result.dynamicRangeLimits = EDIDInfo.DynamicRangeLimits(
                minPixelClockKHz: minPixelClockKHz, maxPixelClockKHz: maxPixelClockKHz,
                minRefreshHz: minRefreshHz, maxRefreshHz: maxRefreshHz
            )

        case 0x2A: // Type X, 6 to 8 bytes (6 + the revision nibble bits 6-4)
            let recordSize = 6 + Int((revision & 0x70) >> 4)
            guard (6...8).contains(recordSize) else { break }
            var i = 0, index = 0
            while i + recordSize <= payloadLength {
                if let mode = EDIDDisplayIDTimingDecoders.typeX(
                    bytes[(payloadStart + i)..<(payloadStart + i + recordSize)],
                    recordSize: recordSize, block: block, index: index, embeddedInCTA: false
                ) {
                    result.modes.append(mode)
                }
                i += recordSize; index += 1
            }

        case 0x81: // CTA-861 DisplayID Data Block: a bare run of CTA data blocks, no CTA block
            // header. `parse_displayid_cta_data_block`, tag 0x81: `len = x[2]` (the payload
            // length already computed above as `payloadLength`), then `for (i = 0; i < len; ...)
            // cta_block(x + i, ...)`, the exact same data block walk `EDIDCTAParser.dataBlocks`
            // implements for a CTA-861 extension block's own body.
            var ctaResult = EDIDCTAParser.Result()
            EDIDCTAParser.dataBlocks(bytes, range: payloadStart..<payloadEnd, block: block, into: &ctaResult)
            result.modes.append(contentsOf: ctaResult.modes)
            result.ctaPreferredVICs.append(contentsOf: ctaResult.preferredVICs)

        default:
            // Every other tag (0x00-0x02, 0x0A-0x10, 0x21, 0x26-0x27, 0x29, 0x2B-0x2E, and the
            // 0x7E/0x7F vendor-specific blocks including the Apple 0x7F block on the Studio
            // Display sample) carries no mode, range or topology this model has a slot for, and
            // is skipped by payload length alone: `off = payloadEnd` in the caller already moves
            // past it. Recorded here by tag only, in this doc comment, not in `Result`.
            break
        }
    }
}
