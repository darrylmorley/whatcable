import Foundation

/// The one place that enumerates every 128-byte block an EDID buffer carries and assembles the
/// result into what `EDIDInfo.init?(Data)` needs: every declared mode, a fact about each block
/// (its kind and whether its own checksum holds), and the handful of "first block that carries
/// it wins" fields (tiled topology, DisplayID range limits, dynamic range limits, CTA preferred
/// VICs).
///
/// Block count: `(bytes.count - 128) / 128` complete extension blocks. Byte 126 of the base
/// block is the EDID's own declared extension count, but it is never used to bound the walk:
/// real EDIDs under-declare it, hiding a further real block past what byte 126 admits
/// (`EDIDInfo.declaredExtensionCount` still records the byte itself, as a fact, never as a
/// limit). How often, and whether any over-declares, is measured in
/// `research/findings/edid-mode-sources.md`; walking only what is actually present in the
/// buffer is correct either way.
public enum EDIDBlockWalker {
    public struct Result {
        public var base: EDIDBaseBlockParser.Result
        /// Base modes first, then per block in order, then the tiled composite (if any) last.
        public var modes: [EDIDMode] = []
        public var blocks: [EDIDInfo.BlockInfo] = []
        public var tiledTopology: EDIDInfo.TiledTopology?
        public var displayIDRangeLimits: EDIDInfo.RangeLimits?
        public var dynamicRangeLimits: EDIDInfo.DynamicRangeLimits?
        public var ctaPreferredVICs: [Int] = []
        /// The first DisplayID Type I / VII record, across the blocks in order, that sets the
        /// preferred flag (`EDIDDisplayIDParser.Result.preferred`). Nil when none does.
        public var displayIDPreferred: EDIDMode?

        public init(base: EDIDBaseBlockParser.Result) {
            self.base = base
        }
    }

    public static func walk(_ bytes: [UInt8]) -> Result {
        let baseResult = EDIDBaseBlockParser.parse(bytes)
        var result = Result(base: baseResult)
        guard bytes.count >= 128 else { return result }

        result.modes = baseResult.modes
        result.blocks.append(EDIDInfo.BlockInfo(index: 0, kind: .base, checksumValid: checksumValid(bytes, block: 0)))

        let edidMinor = bytes.count > 19 ? Int(bytes[19]) : 0
        var continuousFrequency = baseResult.continuousFrequency
        var undecoded = baseResult.undecoded

        // `blocksPresent` walks every complete 128-byte block actually in the buffer, never byte
        // 126's declared count (see the type doc comment above).
        let blocksPresent = max(0, (bytes.count - 128) / 128)
        for extIndex in 0..<blocksPresent {
            let base = 128 + 128 * extIndex
            let blockNumber = extIndex + 1
            let tag = bytes[base]

            switch tag {
            case 0x02:
                // CTA-861. EDIDCTAParser walks every VIC (Video Data Block and the 4:2:0 Video
                // Data Block), the Video Format Preference block, the DisplayID VTDBs CTA-861
                // can carry (Types VII, VIII, X), and the trailing DTDs.
                let cta = EDIDCTAParser.parse(bytes, base: base, block: blockNumber)
                result.modes.append(contentsOf: cta.modes)
                if result.ctaPreferredVICs.isEmpty { result.ctaPreferredVICs = cta.preferredVICs }
                result.blocks.append(EDIDInfo.BlockInfo(index: blockNumber, kind: .cta861, checksumValid: cta.checksumValid))

            case 0x70:
                // DisplayID. EDIDDisplayIDParser walks the whole section: every data block that
                // can name a mode, plus the range, dynamic-range and tiled-topology blocks this
                // model has a slot for. Modes from every DisplayID block are kept; tiledTopology
                // / displayIDRangeLimits / dynamicRangeLimits come from the first block that
                // carries each.
                let displayID = EDIDDisplayIDParser.parse(bytes, base: base, block: blockNumber)
                result.modes.append(contentsOf: displayID.modes)
                if result.displayIDPreferred == nil { result.displayIDPreferred = displayID.preferred }
                if result.tiledTopology == nil { result.tiledTopology = displayID.tiledTopology }
                if result.displayIDRangeLimits == nil { result.displayIDRangeLimits = displayID.rangeLimits }
                if result.dynamicRangeLimits == nil { result.dynamicRangeLimits = displayID.dynamicRangeLimits }
                if continuousFrequency == nil && displayID.discreteFrequency { continuousFrequency = false }
                if result.ctaPreferredVICs.isEmpty { result.ctaPreferredVICs = displayID.ctaPreferredVICs }
                result.blocks.append(EDIDInfo.BlockInfo(
                    index: blockNumber, kind: .displayID(version: displayID.version), checksumValid: displayID.checksumValid))

            case 0x10:
                // VTB-EXT: Detailed Timing Descriptors, CVT codes and GTF-only standard timings,
                // nothing else.
                let vtb = EDIDVTBParser.parse(bytes, base: base, block: blockNumber, edidMinor: edidMinor, rangeLimits: baseResult.rangeLimits)
                result.modes.append(contentsOf: vtb.modes)
                undecoded.append(contentsOf: vtb.undecoded)
                result.blocks.append(EDIDInfo.BlockInfo(index: blockNumber, kind: .vtb, checksumValid: vtb.checksumValid))

            case 0xF0:
                // Block map: bytes 1...126 name the tags of the following blocks. The tags
                // themselves add nothing this model doesn't already get by reading each block's
                // own tag byte directly, and are not used to bound or reorder the walk; recorded
                // as a fact only.
                result.blocks.append(EDIDInfo.BlockInfo(index: blockNumber, kind: .blockMap, checksumValid: checksumValid(bytes, block: blockNumber)))

            default:
                // `0x40` (DI-EXT) and `0x50` (LS-EXT) carry no timings this model reads and fall
                // under `.unknown` deliberately, same as any other tag with no case above. An
                // all-zero 128-byte block (tag 0x00 included) is padding; a non-zero block under
                // an unhandled tag is `.unknown(tag:)`.
                let blockBytes = bytes[base..<(base + 128)]
                let kind: EDIDInfo.BlockInfo.Kind = blockBytes.allSatisfy { $0 == 0 } ? .padding : .unknown(tag: tag)
                result.blocks.append(EDIDInfo.BlockInfo(index: blockNumber, kind: kind, checksumValid: checksumValid(bytes, block: blockNumber)))
            }
        }

        result.base.continuousFrequency = continuousFrequency
        result.base.undecoded = undecoded

        // Tiled composite (rule 4, revised: matching against `base.preferred` alone missed a
        // real corpus shape. Some panels that declare a tiled topology declare their tile's own
        // mode only in a DisplayID block, at a resolution the base block's preferred mode never
        // matches, and declare the full composite resolution nowhere at all (how many, and which,
        // is in `research/findings/edid-mode-sources.md`); under the old rule those panels' real
        // top mode went unexplained, which is exactly the "mystery" the topology block exists to
        // remove. The composite is now built from the highest-pixel-clock declared,
        // non-interlaced entry, from any source, whose own resolution equals the tile's - not
        // from `base.preferred` specifically. Both the matched entry and the topology are
        // declared bytes, and the arithmetic (hTiles * vTiles independent streams, each carrying
        // the matched entry's mode) is still the definition of tiling, so this stays a fact, not
        // a guess. When no declared entry matches the tile's resolution, nothing is recorded (the
        // oracle sweep counts it).
        if let topology = result.tiledTopology, topology.hTiles * topology.vTiles > 1 {
            var tileEntry: EDIDMode? = nil
            for mode in result.modes {
                guard mode.width == topology.tileWidth, mode.height == topology.tileHeight, !mode.interlaced else { continue }
                if let current = tileEntry {
                    if mode.pixelClockHz > current.pixelClockHz { tileEntry = mode }
                } else {
                    tileEntry = mode
                }
            }
            if let tileEntry {
                let tiles = topology.hTiles * topology.vTiles
                let from: EDIDMode.DisplayIDTimingType?
                if case .displayID(_, let type, _, _) = tileEntry.source { from = type } else { from = nil }
                result.modes.append(EDIDMode(
                    width: topology.tileWidth * topology.hTiles,
                    height: topology.tileHeight * topology.vTiles,
                    hTotal: tileEntry.hTotal * topology.hTiles,
                    vTotal: tileEntry.vTotal * topology.vTiles,
                    pixelClockHz: tileEntry.pixelClockHz * tiles,
                    interlaced: false,
                    source: .tiledComposite(tiles: tiles, from: from)))
            }
        }

        return result
    }

    /// Sum of the block's own 128 bytes, mod 256: the EDID checksum rule, the same for the base
    /// block and every extension block. `block` is the block number (0 = base, 1 = the first
    /// extension, and so on), not a byte offset.
    public static func checksumValid(_ bytes: [UInt8], block: Int) -> Bool {
        guard block >= 0 else { return false }
        let base = block * 128
        guard base + 128 <= bytes.count else { return false }
        let sum = bytes[base..<(base + 128)].reduce(UInt8(0)) { $0 &+ $1 }
        return sum == 0
    }
}
