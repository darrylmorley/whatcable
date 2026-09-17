import Foundation

/// One mode a display has declared, from any of the formats an EDID can
/// carry it in: a base-block detailed timing, a CTA-861 short video
/// descriptor, a DisplayID timing block, an established or standard timing
/// slot, or a CVT/GTF code. `source` says which, and carries enough to
/// rebuild a human label (`sourceDescription`) or trace the mode back to its
/// bytes.
///
/// This is a declared fact, not a decision: nothing here picks a "best"
/// mode. `EDIDInfo.topMode` and `EDIDInfo.preferredMode` do that.
public struct EDIDMode: Hashable, Sendable, Codable {
    /// How a standard-timing or established-timing slot's implied refresh
    /// was derived, when the source names a formula rather than a fixed
    /// table entry.
    public enum Derivation: String, Hashable, Sendable, Codable {
        case dmt, cvt, cvtReducedBlanking, gtf, gtfSecondary
    }

    /// Which DisplayID timing-block format a `.displayID` source came from.
    public enum DisplayIDTimingType: String, Hashable, Sendable, Codable {
        case typeI, typeII, typeIII, typeIV, typeV, typeVI, typeVII, typeVIII, typeIX, typeX
        case vesaDMTBitmap   // tag 0x07
        case ctaVICBitmap    // tag 0x08

        var label: String {
            switch self {
            case .typeI: return "Type I"
            case .typeII: return "Type II"
            case .typeIII: return "Type III"
            case .typeIV: return "Type IV"
            case .typeV: return "Type V"
            case .typeVI: return "Type VI"
            case .typeVII: return "Type VII"
            case .typeVIII: return "Type VIII"
            case .typeIX: return "Type IX"
            case .typeX: return "Type X"
            case .vesaDMTBitmap: return "VESA DMT bitmap"
            case .ctaVICBitmap: return "CTA VIC bitmap"
            }
        }
    }

    /// Where a mode was declared: which EDID structure, and enough of its
    /// coordinates to trace it back to bytes.
    public enum Source: Hashable, Sendable, Codable {
        /// Base block bytes 35-37 (`byte` is the absolute base-block offset, `bit` 7...0),
        /// or the 0xF7 descriptor (`byte` 6...11 within the descriptor, offset by 1000 so
        /// the two never collide: 1006...1011).
        case establishedTiming(byte: Int, bit: Int, dmtID: Int?)
        /// Base slots 0...7, the 0xFA descriptor's six as 8...13, VTB-EXT as 100+.
        case standardTiming(index: Int, derivation: Derivation, dmtID: Int?)
        /// 18-byte descriptor. `block` 0 is the base block; `index` counts DTDs within that block from 0.
        case detailedTiming(block: Int, index: Int)
        /// 0xF8 descriptor (block 0) or VTB-EXT; one entry per supported refresh in the 3-byte code.
        case cvtCode(block: Int, index: Int, refreshHz: Int, reducedBlanking: Bool)
        /// CTA-861 Short Video Descriptor. `ycbcr420Only` for entries from the Y420VDB.
        case ctaVIC(block: Int, vic: Int, native: Bool, ycbcr420Only: Bool)
        /// DisplayID data block; `embeddedInCTA` when it came via CTA extended tags 0x22/0x23/0x2A.
        case displayID(block: Int, type: DisplayIDTimingType, index: Int, embeddedInCTA: Bool)
        /// A multi-tile panel's composite: the tile's mode times the topology. Not a declared timing;
        /// derived from two declared facts.
        case tiledComposite(tiles: Int, from: DisplayIDTimingType?)
    }

    public let width: Int          // active pixels per line
    public let height: Int         // active lines per FRAME (interlaced: both fields)
    public let hTotal: Int
    public let vTotal: Int         // frame total
    public let pixelClockHz: Int
    public let interlaced: Bool
    public let source: Source

    public init(
        width: Int, height: Int, hTotal: Int, vTotal: Int,
        pixelClockHz: Int, interlaced: Bool, source: Source
    ) {
        self.width = width
        self.height = height
        self.hTotal = hTotal
        self.vTotal = vTotal
        self.pixelClockHz = pixelClockHz
        self.interlaced = interlaced
        self.source = source
    }

    /// Field rate for interlaced, frame rate otherwise. This is the number people
    /// call "refresh" and the number edid-decode prints.
    public var refreshHz: Double {
        guard hTotal > 0, vTotal > 0 else { return 0 }
        let frame = Double(pixelClockHz) / Double(hTotal * vTotal)
        return interlaced ? frame * 2 : frame
    }

    /// Active pixels per second, the domain CoreGraphics reports in.
    public var activePixelRate: Double { Double(width) * Double(height) * refreshHz / (interlaced ? 2 : 1) }

    /// The entry's own label, e.g. "DisplayID Type I (block 3)". See
    /// `Source.description`.
    public var sourceDescription: String { source.description }
}

extension EDIDMode.Source: CustomStringConvertible {
    /// Where the mode was declared, as a human label with enough coordinates
    /// to trace it back to bytes: "detailed timing 1 (block 0)", "CTA VIC 97
    /// (block 1)", "DisplayID Type I (block 3)", "tiled composite of 2 tiles".
    public var description: String {
        switch self {
        case .establishedTiming(_, _, let dmt):
            return dmt.map { "established timing (DMT 0x\(String($0, radix: 16, uppercase: true)))" } ?? "established timing (legacy)"
        case .standardTiming(let i, let d, let dmt):
            let how = dmt.map { "DMT 0x\(String($0, radix: 16, uppercase: true))" } ?? d.rawValue.uppercased()
            return "standard timing \(i + 1) (\(how))"
        case .detailedTiming(let b, let i):
            return "detailed timing \(i + 1) (block \(b))"
        case .cvtCode(let b, let i, let r, let rb):
            return "CVT code \(i + 1) at \(r) Hz\(rb ? " RB" : "") (block \(b))"
        case .ctaVIC(let b, let v, _, let y):
            return "CTA VIC \(v)\(y ? " 4:2:0" : "") (block \(b))"
        case .displayID(let b, let t, _, let cta):
            return "DisplayID \(t.label)\(cta ? " in CTA" : "") (block \(b))"
        case .tiledComposite(let n, _):
            return "tiled composite of \(n) tiles"
        }
    }
}
