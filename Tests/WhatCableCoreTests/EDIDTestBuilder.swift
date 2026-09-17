import Foundation

/// Fabricates minimal, byte-correct EDID structures for parser tests, so a test only spells out
/// the bytes it actually cares about. Every builder here targets the 128-byte base block; Tasks 5
/// to 8 add `displayIDSection`, `ctaBlock`, `vtbBlock` alongside these as the DisplayID, CTA-861
/// and VTB-EXT parsers land.
enum EDIDTestBuilder {
    /// Build a 128-byte EDID base block. `version` is (major, minor), written to bytes 18-19.
    /// `establishedBytes` are bytes 35-37 (the Established Timings I/II bitmap), zero by default.
    /// `standardTimings` fill bytes 38-53 in order (up to 8 pairs); any slot beyond what's given
    /// is padded with the unused code `0x01 0x01`. `descriptors` fill the four 18-byte descriptor
    /// slots at offsets 54, 72, 90, 108 in order (see `descriptor(tag:payload:)`); any slot beyond
    /// what's given is left as an all-zero "Empty Descriptor" (a valid, inert display descriptor).
    /// Byte 126 (extension count) is left 0; append extension blocks and set it yourself if a test
    /// needs one. The checksum (byte 127) is NOT set; pipe the result through `withChecksum(_:)`.
    static func baseBlock(
        version: (major: UInt8, minor: UInt8) = (1, 4),
        establishedBytes: (UInt8, UInt8, UInt8) = (0, 0, 0),
        standardTimings: [(UInt8, UInt8)] = [],
        descriptors: [[UInt8]] = []
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 128)
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        for (i, b) in header.enumerated() { bytes[i] = b }
        bytes[18] = version.major
        bytes[19] = version.minor
        bytes[35] = establishedBytes.0
        bytes[36] = establishedBytes.1
        bytes[37] = establishedBytes.2
        for i in 0..<8 {
            let off = 38 + i * 2
            if i < standardTimings.count {
                bytes[off] = standardTimings[i].0
                bytes[off + 1] = standardTimings[i].1
            } else {
                bytes[off] = 0x01
                bytes[off + 1] = 0x01
            }
        }
        let descriptorOffsets = [54, 72, 90, 108]
        for (i, off) in descriptorOffsets.enumerated() {
            guard i < descriptors.count else { continue }
            let d = descriptors[i]
            precondition(d.count == 18, "descriptor must be exactly 18 bytes, got \(d.count)")
            for (j, b) in d.enumerated() { bytes[off + j] = b }
        }
        return bytes
    }

    /// Build one 18-byte display descriptor: offsets 0-2 are the zero marker that says "this slot
    /// is a display descriptor, not a detailed timing"; `tag` goes at offset 3; `payload` fills
    /// offsets 4-17 (14 bytes), zero-padded if shorter and truncated if longer.
    static func descriptor(tag: UInt8, payload: [UInt8]) -> [UInt8] {
        var d = [UInt8](repeating: 0, count: 18)
        d[3] = tag
        for (i, b) in payload.prefix(14).enumerated() { d[4 + i] = b }
        return d
    }

    /// Build a 128-byte DisplayID extension block (EDID extension tag 0x70). Byte 0 is the tag,
    /// byte 1 the DisplayID structure version (0x12 = 1.2, 0x20 = 2.0), byte 2 the section length
    /// (data-block bytes only), byte 3 the product type, byte 4 the extension count (0). Data
    /// blocks (tag, revision, payload length, payload) start at byte 5, followed by the section
    /// checksum (bytes 1 through the last data block sum to 0 mod 256, the rule edid-decode's
    /// `parse_displayid_block` checks), zero fill, and the extension-block checksum at byte 127.
    ///
    /// `productType` defaults to 0x01 (test structure) because edid-decode records a failure for
    /// a base-section product type of 0 and, for the display product types (2, 3, 4, 6 in 1.x and
    /// 2 to 8 in 2.x), demands Display Parameters and Type I/VII data blocks a timing-only
    /// fixture does not carry (`check_displayid_blocks`). Product type 1 needs neither.
    static func displayIDBlock(
        version: UInt8,
        productType: UInt8 = 0x01,
        dataBlocks: [(tag: UInt8, revision: UInt8, payload: [UInt8])]
    ) -> [UInt8] {
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x70
        block[1] = version
        block[3] = productType
        block[4] = 0
        var off = 5
        for dataBlock in dataBlocks {
            precondition(off + 3 + dataBlock.payload.count <= 126, "DisplayID section overflows the block")
            block[off] = dataBlock.tag
            block[off + 1] = dataBlock.revision
            block[off + 2] = UInt8(dataBlock.payload.count)
            for (i, b) in dataBlock.payload.enumerated() { block[off + 3 + i] = b }
            off += 3 + dataBlock.payload.count
        }
        block[2] = UInt8(off - 5)
        let sectionSum = block[1..<off].reduce(UInt8(0)) { $0 &+ $1 }
        block[off] = UInt8((256 - Int(sectionSum)) % 256)
        return withChecksum(block)
    }

    /// Set the last byte of `bytes` so the whole array sums to 0 mod 256, the EDID base-block
    /// (and extension-block) checksum rule. Works on any 128-byte-multiple block, not just the
    /// base block, since every EDID block is checksummed the same way.
    static func withChecksum(_ bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return bytes }
        var out = bytes
        let last = out.count - 1
        out[last] = 0
        let sum = out.reduce(UInt8(0)) { $0 &+ $1 }
        out[last] = UInt8((256 - Int(sum)) % 256)
        return out
    }

    /// Build a 128-byte VTB-EXT extension block (EDID extension tag 0x10). Byte 0 is the tag,
    /// byte 1 the structure version (1), bytes 2-4 the DTD / CVT-code / standard-timing counts,
    /// then the DTDs (18 bytes each, from `descriptor`-shaped raw bytes, not display
    /// descriptors), the CVT codes (3 bytes each) and the standard timings (2 bytes each) back
    /// to back starting at byte 5. Checksum at byte 127 via `withChecksum(_:)`.
    static func vtbBlock(
        dtds: [[UInt8]] = [],
        cvtCodes: [(UInt8, UInt8, UInt8)] = [],
        standardTimings: [(UInt8, UInt8)] = []
    ) -> [UInt8] {
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x10
        block[1] = 1 // version
        block[2] = UInt8(dtds.count)
        block[3] = UInt8(cvtCodes.count)
        block[4] = UInt8(standardTimings.count)
        var off = 5
        for dtd in dtds {
            precondition(dtd.count == 18, "VTB-EXT DTD must be exactly 18 bytes, got \(dtd.count)")
            precondition(off + 18 <= 127, "VTB-EXT block overflows the block")
            for (i, b) in dtd.enumerated() { block[off + i] = b }
            off += 18
        }
        for code in cvtCodes {
            precondition(off + 3 <= 127, "VTB-EXT block overflows the block")
            block[off] = code.0
            block[off + 1] = code.1
            block[off + 2] = code.2
            off += 3
        }
        for timing in standardTimings {
            precondition(off + 2 <= 127, "VTB-EXT block overflows the block")
            block[off] = timing.0
            block[off + 1] = timing.1
            off += 2
        }
        return withChecksum(block)
    }

    /// Write `bytes` as a whitespace-separated hex text file, the input format
    /// `edid-decode-bin --skip-hex-dump --skip-sha <file>` reads. Returns the file's URL; the
    /// caller is responsible for nothing further (it lands in a temporary directory).
    static func hexFile(_ bytes: [UInt8]) -> URL {
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("edid-\(UUID().uuidString).hex")
        try? hex.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
