import Foundation

/// One value of the display node's `ColorModes[].PixelEncoding`: the kernel's
/// `IOAVVideoPixelEncoding` enum, 0 to 14, read from the `IOAVFamily` name
/// table and the DCP firmware's identical switch
/// (research/displays/dumps/display-node-keys-kernel-decode-2026-09-18.md,
/// Finding 4). A struct over a raw `Int` rather than a Swift `enum`, so a
/// value outside the table is carried as itself and never dropped or coerced:
/// the corpus has one flat-rendering occurrence each of 5, 8 and 9 and nothing
/// above 14 (research/displays/display-node-keys.md, section 1), and the type
/// does not get to decide that.
///
/// It is not the `kIOPixelEncoding*` bitmask in `IOGraphicsTypes.h`: that is a
/// different type for `IODisplayTimingRangeV1`, where 0 means "not supported".
/// Here 0 is RGB 4:4:4, which the corpus confirms on 401 of 401 paired nodes.
public struct DisplayPixelEncoding: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let rgb444 = DisplayPixelEncoding(rawValue: 0)
    public static let ycbcr420 = DisplayPixelEncoding(rawValue: 1)
    public static let ycbcr422 = DisplayPixelEncoding(rawValue: 2)
    public static let ycbcr444 = DisplayPixelEncoding(rawValue: 3)
    public static let dolbyVisionNative = DisplayPixelEncoding(rawValue: 4)
    public static let dolbyVisionHDMITunneling = DisplayPixelEncoding(rawValue: 5)
    public static let ycbcr422DPTunneling = DisplayPixelEncoding(rawValue: 6)
    public static let ycbcr422HDMITunneling = DisplayPixelEncoding(rawValue: 7)
    public static let dolbyVisionLLYCbCr422 = DisplayPixelEncoding(rawValue: 8)
    public static let dolbyVisionLLYCbCr422DPTunneling = DisplayPixelEncoding(rawValue: 9)
    public static let dolbyVisionLLYCbCr422HDMITunneling = DisplayPixelEncoding(rawValue: 10)
    public static let dolbyVisionLLYCbCr444 = DisplayPixelEncoding(rawValue: 11)
    public static let dolbyVisionLLRGB444 = DisplayPixelEncoding(rawValue: 12)
    public static let grgbTunneledEvenLineBlue = DisplayPixelEncoding(rawValue: 13)
    public static let grgbTunneledEvenLineRed = DisplayPixelEncoding(rawValue: 14)

    /// The kernel's own name for the value, from the 15-pointer table
    /// `_IOAVVideoPixelEncodingString` indexes (dump Finding 4). nil outside
    /// 0 to 14, which the kernel prints as "Unknown"; nil rather than that
    /// word so a caller never mistakes the kernel's placeholder for a name.
    public var name: String? {
        switch rawValue {
        case 0: return "RGB 4:4:4"
        case 1: return "YCbCr 4:2:0"
        case 2: return "YCbCr 4:2:2"
        case 3: return "YCbCr 4:4:4"
        case 4: return "DolbyVision (native)"
        case 5: return "DolbyVision (HDMI tunneling)"
        case 6: return "YCbCr 4:2:2 (DP tunneling)"
        case 7: return "YCbCr 4:2:2 (HDMI tunneling)"
        case 8: return "DolbyVision LL YCbCr 4:2:2"
        case 9: return "DolbyVision LL YCbCr 4:2:2 (DP tunneling)"
        case 10: return "DolbyVision LL YCbCr 4:2:2 (HDMI tunneling)"
        case 11: return "DolbyVision LL YCbCr 4:4:4"
        case 12: return "DolbyVision LL RGB 4:4:4"
        case 13: return "GRGB Tunneled as YCbCr422 (Even line blue)"
        case 14: return "GRGB Tunneled as YCbCr422 (Even line red)"
        default: return nil
        }
    }

    /// Apple's bits per pixel for this encoding at `depth` bits per component:
    /// the DCP firmware's `bitsPerPixel(depth, encoding)` at `DCP.bin` 0xe8738
    /// (dump A2), the figure its DSC rule and its HDMI character-rate rule
    /// both cost a mode with. 3 x depth for RGB and every 4:4:4 (0, 3, 11,
    /// 12); 2 x depth for plain 4:2:2 and the two GRGB tunnels (2, 13, 14);
    /// 1.5 x depth for 4:2:0 (1); a flat 24 whatever the depth for DolbyVision
    /// native and every HDMI or DP tunnelled encoding (4 to 10); nil for a
    /// value the firmware calls "invalid pixel encoding" (15 and above, and
    /// negatives) and for a depth at or below zero. Nothing here estimates: a
    /// value the table does not name costs nothing.
    public func bitsPerPixel(depth: Int) -> Double? {
        guard depth > 0 else { return nil }
        switch rawValue {
        case 0, 3, 11, 12: return 3 * Double(depth)
        case 2, 13, 14: return 2 * Double(depth)
        case 1: return 1.5 * Double(depth)
        case 4, 5, 6, 7, 8, 9, 10: return 24
        default: return nil
        }
    }
}
