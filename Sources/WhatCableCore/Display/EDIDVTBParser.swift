import Foundation

/// Decodes one VTB-EXT extension block (EDID extension tag 0x10): the "Video Timing Block
/// Extension", a compact alternative to CTA-861 or DisplayID that carries nothing but the three
/// descriptor shapes the base block already knows how to read: Detailed Timing Descriptors,
/// CVT 3-byte codes, and Standard Timings.
///
/// Byte layout: `parse_vtb_ext_block` (edid-decode, v4l-utils,
/// utils/edid-decode/parse-vtb-ext-block.cpp, commit f341ed8e3742118a86619e5f499017db2de30d94,
/// MIT). Byte 1 is the structure version (edid-decode flags anything but 1 as a failure but
/// still decodes the rest the same way; there is no second layout to fall back to, so this
/// decodes regardless of the version byte's value). Byte 2 is the DTD count, byte 3 the CVT-code
/// count, byte 4 the standard-timing count. DTDs (18 bytes each) start at byte 5, immediately
/// followed by the CVT codes (3 bytes each), then the standard timings (2 bytes each).
///
/// Every group is bounded by byte 127 (`y = x + 0x7f` in the reference, the block's own
/// checksum, never read into): if a group's next entry would read into or past it, edid-decode
/// `fail()`s and `return`s from the WHOLE function, not just that loop, so a truncated DTD count
/// means the CVT codes and standard timings after it are never read either, even when their own
/// bytes are present and well-formed. Mirrored here with a `stopped` flag rather than three
/// separate early returns, to the same effect.
///
/// Standard timings use `gtf_only` semantics: `print_standard_timing("    ", x[0], x[1], true)`
/// passes `gtf_only = true`, so every VTB-EXT standard timing derives by the default GTF formula
/// regardless of what the base block's range-limits descriptor says (`EDIDBaseBlockParser
/// .standardTiming`'s `gtfOnly` parameter). Source indices for VTB standard timings are `100 + i`
/// (`EDIDMode.Source.standardTiming`'s doc comment already reserves this range).
public enum EDIDVTBParser {
    /// `base` is the offset of the 0x10 tag byte; `block` labels sources the same way the CTA and
    /// DisplayID parsers do (1 for the first extension block, and so on).
    public static func parse(
        _ bytes: [UInt8], base: Int, block: Int, edidMinor: Int, rangeLimits: EDIDInfo.RangeLimits?
    ) -> (modes: [EDIDMode], undecoded: [EDIDInfo.StandardTimingID], checksumValid: Bool) {
        var modes: [EDIDMode] = []
        var undecoded: [EDIDInfo.StandardTimingID] = []
        let checksumValid = EDIDBlockWalker.checksumValid(bytes, block: base / 128)
        guard base + 5 <= bytes.count else { return (modes, undecoded, checksumValid) }

        let numDTD = Int(bytes[base + 2])
        let numCVT = Int(bytes[base + 3])
        let numST = Int(bytes[base + 4])
        // Byte 127: the block's own checksum. A group's next entry may never read into or past
        // it (`y = x + 0x7f` in the reference).
        let checksumOffset = base + 0x7F

        var off = base + 5
        var stopped = false

        if !stopped {
            for i in 0..<numDTD {
                guard off + 18 <= checksumOffset else { stopped = true; break }
                if let mode = EDIDBaseBlockParser.detailedTiming(bytes, at: off, block: block, index: i) {
                    modes.append(mode)
                }
                off += 18
            }
        }
        if !stopped {
            for i in 0..<numCVT {
                guard off + 3 <= checksumOffset else { stopped = true; break }
                let code = (bytes[off], bytes[off + 1], bytes[off + 2])
                modes.append(contentsOf: EDIDBaseBlockParser.cvtCodeModes(code, block: block, index: i))
                off += 3
            }
        }
        if !stopped {
            for i in 0..<numST {
                guard off + 2 <= checksumOffset else { stopped = true; break }
                if let decoded = EDIDBaseBlockParser.standardTiming(
                    byte1: bytes[off], byte2: bytes[off + 1], index: 100 + i,
                    edidMinor: edidMinor, rangeLimits: rangeLimits, gtfOnly: true
                ) {
                    switch decoded {
                    case .left(let mode): modes.append(mode)
                    case .right(let id): undecoded.append(id)
                    }
                }
                off += 2
            }
        }

        return (modes, undecoded, checksumValid)
    }
}
