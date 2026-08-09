import Foundation
import Testing
@testable import WhatCableCore

@Suite("EDID Info")
struct EDIDInfoTests {

    /// The 128-byte EDID base block of a Lenovo G34w-10, captured verbatim
    /// from a real Mac in `probes/17_deep_property_dump_output.txt`. This is
    /// the golden sample: a 3440x1440 ultrawide whose preferred mode is 60 Hz
    /// but whose range-limits descriptor advertises a 100 Hz / 600 MHz
    /// ceiling. It is the exact case the feature exists to catch.
    /// Shared with `DisplayDiagnosticTests` for its end-to-end parse test.
    static let g34wBaseBlock: [UInt8] = [
        0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x30, 0xae, 0xa1, 0x66, 0x00, 0x00, 0x00, 0x00,
        0x34, 0x1d, 0x01, 0x03, 0x80, 0x50, 0x21, 0x78, 0xb6, 0xee, 0x95, 0xa3, 0x54, 0x4c, 0x99, 0x26,
        0x0f, 0x50, 0x54, 0xaf, 0xef, 0x00, 0x81, 0xc0, 0x81, 0x80, 0x95, 0x00, 0xa9, 0xc0, 0xb3, 0x00,
        0xd1, 0xc0, 0x71, 0x4f, 0x81, 0x8a, 0xf5, 0x7c, 0x70, 0xa0, 0xd0, 0xa0, 0x29, 0x50, 0x30, 0x20,
        0x35, 0x00, 0x1d, 0x4e, 0x31, 0x00, 0x00, 0x1a, 0x00, 0x00, 0x00, 0xff, 0x00, 0x55, 0x47, 0x57,
        0x30, 0x30, 0x32, 0x30, 0x35, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0xfd, 0x00, 0x30,
        0x64, 0x17, 0xa0, 0x3c, 0x00, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0xfc,
        0x00, 0x4c, 0x45, 0x4e, 0x20, 0x47, 0x33, 0x34, 0x77, 0x2d, 0x31, 0x30, 0x0a, 0x20, 0x01, 0x49,
    ]

    /// The CTA-861 extension block (128 bytes) of the same G34w-10, captured
    /// live. Starts with the CTA tag 0x02; its detailed timings are all lower
    /// than the base block's modes. Appended to `g34wBaseBlock` to form the
    /// full 256-byte EDID without re-transcribing the proven base bytes.
    static let g34wExtensionHex =
        "020331f34b0102030405901213141f4e230907078301000067030c001000384267" +
        "d85dc401788000681a000001013064ed44d070a0d0a02950584045001d4e3100001e" +
        "662156aa51001e30468f33001d4e3100001e6a5e00a0a0a02950302035001d4e3100" +
        "001e226870a0d0a02950302035001d4e3100001a00000000000081"

    /// Full 384-byte EDID (base block + two CTA-861 extensions) of an LG
    /// UltraFine 4K (manufacturer GSM = LG, sink "22MD4K"), captured live from
    /// an Apple M3 Max over a *tunnelled* DisplayPort link via Test Kit probe
    /// 33 on 2026-05-30. Native DisplayPort, no adapter. The second real
    /// monitor golden sample alongside the G34w, and the first from a 4K panel.
    /// Verbatim from `research/dumps/displayport/2026-05-30_m3max_lg-ultrafine.md`.
    static let lgUltraFineHex =
        "00ffffffffffff001e6d7b5b00000000041d0104b5351e78803e31ae5047ac270c50542000000101010101010101010101010101010150d000a0f0703e803020630c0d272100001a000000ff0000000000000000000000000000000000fd00303c1e873c010a202020202020000000fc004c4720556c74726146696e650a027a701279000001000c8e126e0a0010000950784e772900106c370bdf4a3f44a19fc3f816f25e900d03003cbb9c00041f0d4f0007801f006107350000000700a25b0004ff094f0007801f009f05280000000700133400047f074f0007801f0037041e0000000700000000000000000000000000000000000000000000000000c390701279000003003c4fd00084ff0e9f002f801f006f083d003500020093ad0004ff0e9f002f801f006f083d003500020025680004ff0e9f002f801f006f083d0035000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008f90"

    static func hexBytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    @Test("Parses the real G34w-10 base block: preferred mode")
    func parsesPreferredMode() throws {
        let edid = try #require(EDIDInfo(Data(Self.g34wBaseBlock)))
        #expect(edid.preferredWidth == 3440)
        #expect(edid.preferredHeight == 1440)
        #expect(edid.preferredRefreshHz == 60)
        #expect(edid.preferredPixelClockHz == 319_890_000)
    }

    @Test("Parses the 0xFD range-limits descriptor: the max ceiling")
    func parsesMaxCapability() throws {
        let edid = try #require(EDIDInfo(Data(Self.g34wBaseBlock)))
        // This is the load-bearing assertion: the monitor's ceiling is 100 Hz
        // / 600 MHz, far above its 60 Hz preferred mode. The diagnostic must
        // compare the link against this, not the preferred mode.
        #expect(edid.maxRefreshHz == 100)
        #expect(edid.maxPixelClockHz == 600_000_000)
    }

    // MARK: - CTA-861 extension

    @Test("Parses the full 256-byte EDID with CTA extension: ceiling unchanged")
    func parsesFullBlockWithExtension() throws {
        let bytes = Self.g34wBaseBlock + Self.hexBytes(Self.g34wExtensionHex)
        #expect(bytes.count == 256)
        let edid = try #require(EDIDInfo(Data(bytes)))
        // The extension's detailed timings are all below the base block's, so
        // the preferred mode and the ceiling are identical to the base parse.
        #expect(edid.preferredWidth == 3440)
        #expect(edid.maxPixelClockHz == 600_000_000)
    }

    @Test("Detailed-timing scan reads both base and extension descriptors")
    func scansAllDetailedTimings() {
        let bytes = Self.g34wBaseBlock + Self.hexBytes(Self.g34wExtensionHex)
        // The G34w declares its top mode (3440x1440 at ~100 Hz, 533.16 MHz) as
        // a detailed timing in the CTA extension, above the base block's 60 Hz
        // preferred (319.89 MHz). The scan must find it. The 0xFD ceiling
        // (600 MHz) still covers it, so the diagnostic's max is unchanged, but
        // this proves the extension scan reads a real higher mode that the base
        // block alone misses.
        #expect(EDIDInfo.highestDTDPixelClockHz(bytes) == 533_160_000)
    }

    @Test("A higher mode in the CTA extension raises the max ceiling")
    func extensionModeRaisesCeiling() throws {
        // Base block (0xFD ceiling = 600 MHz) plus a synthetic CTA extension
        // whose detailed timing is 640 MHz, above the base ceiling. This is the
        // case that needs the extension scan: a real monitor where the top mode
        // lives only in the extension. The max must follow it.
        var bytes = Self.g34wBaseBlock
        var ext = [UInt8](repeating: 0, count: 128)
        ext[0] = 0x02 // CTA-861 tag
        ext[1] = 0x03 // revision
        ext[2] = 0x04 // detailed timings start right after the 4-byte header
        // Detailed timing at extension offset 4: pixel clock 640 MHz = 64000
        // (0xFA00) in 10 kHz units, little-endian.
        ext[4] = 0x00
        ext[5] = 0xFA
        ext[6] = 0x80 // arbitrary non-zero h-active, irrelevant to the scan
        bytes.append(contentsOf: ext)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.maxPixelClockHz == 640_000_000)
    }

    @Test("Parses the monitor name and EDID version")
    func parsesNameAndVersion() throws {
        let edid = try #require(EDIDInfo(Data(Self.g34wBaseBlock)))
        #expect(edid.monitorName == "LEN G34w-10")
        #expect(edid.versionMajor == 1)
        #expect(edid.versionMinor == 3)
    }

    // MARK: - Second real monitor: LG UltraFine 4K (live, tunnelled DP)

    @Test("Parses the live LG UltraFine 4K EDID (base block + CTA extensions)")
    func parsesLGUltraFine() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.lgUltraFineHex))))
        #expect(edid.monitorName == "LG UltraFine")
        #expect(edid.preferredWidth == 3840)
        #expect(edid.preferredHeight == 2160)
        // 0xFD range-limits ceiling: 60 Hz, 600 MHz max pixel clock. The CTA
        // extensions carry only lower modes, so the ceiling is unchanged.
        #expect(edid.maxRefreshHz == 60)
        #expect(edid.maxPixelClockHz == 600_000_000)
    }

    @Test("Rejects a blob with a bad header")
    func rejectsBadHeader() {
        var bad = Self.g34wBaseBlock
        bad[0] = 0x01 // header must start 00 FF FF...
        #expect(EDIDInfo(Data(bad)) == nil)
    }

    @Test("Rejects a blob that is too short")
    func rejectsShortBlob() {
        let short = Array(Self.g34wBaseBlock.prefix(64))
        #expect(EDIDInfo(Data(short)) == nil)
    }

    @Test("Monitor name stops at first non-ASCII byte, not garbled Latin-1")
    func monitorNameIgnoresHighBytes() throws {
        // Inject a Latin-1 byte (0xE9 = 'e with accent') into the 0xFC monitor
        // name descriptor of the G34w base block. The 0xFC block starts at
        // offset 108; the name payload is at offsets 113-125. Byte 113 is the
        // first name character ('L'). Replacing it with 0xE9 should cause the
        // decoder to stop immediately, yielding nil (no printable chars before
        // the bad byte).
        var bytes = Self.g34wBaseBlock
        // 0xFC descriptor starts at offset 108; name bytes start at 108+5 = 113.
        bytes[113] = 0xE9
        let edid = try #require(EDIDInfo(Data(bytes)))
        // The name is truncated to nothing before the bad byte, so it should be nil.
        #expect(edid.monitorName == nil)
    }

    // MARK: - Detailed-timing border bytes and the refresh rate

    /// Build a minimal 128-byte EDID 1.4 base block carrying a single
    /// detailed-timing descriptor in the first descriptor slot (offset 54, the
    /// preferred-timing slot) with the supplied active area, blanking, and
    /// per-side borders. Every other byte is zero apart from the fixed 8-byte
    /// header and a correct block checksum. It lets the border math be exercised
    /// on a hand-computed timing, in isolation from a real capture's confounding
    /// fields (sync, image size, range limits).
    static func syntheticEDID(
        clock10kHz: Int,
        hActive: Int, hBlank: Int,
        vActive: Int, vBlank: Int,
        hBorder: Int, vBorder: Int
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 128)
        // Fixed EDID header: 00 FF FF FF FF FF FF 00.
        bytes[0] = 0x00
        for i in 1...6 { bytes[i] = 0xFF }
        bytes[7] = 0x00
        bytes[18] = 1  // EDID structure version
        bytes[19] = 4  // revision 4 (EDID 1.4)

        let off = 54 // first detailed-timing descriptor = the preferred timing
        bytes[off]      = UInt8(truncatingIfNeeded: clock10kHz)
        bytes[off + 1]  = UInt8(truncatingIfNeeded: clock10kHz >> 8)
        bytes[off + 2]  = UInt8(truncatingIfNeeded: hActive)
        bytes[off + 3]  = UInt8(truncatingIfNeeded: hBlank)
        bytes[off + 4]  = UInt8(truncatingIfNeeded: ((hActive >> 8) << 4) | (hBlank >> 8))
        bytes[off + 5]  = UInt8(truncatingIfNeeded: vActive)
        bytes[off + 6]  = UInt8(truncatingIfNeeded: vBlank)
        bytes[off + 7]  = UInt8(truncatingIfNeeded: ((vActive >> 8) << 4) | (vBlank >> 8))
        // Per the EDID 1.4 detailed-timing layout, bytes +15/+16 are the
        // per-side horizontal/vertical borders. Each side of the image carries
        // that many pixels/lines, so a full frame includes 2x each.
        bytes[off + 15] = UInt8(truncatingIfNeeded: hBorder)
        bytes[off + 16] = UInt8(truncatingIfNeeded: vBorder)

        // EDID block checksum: byte 127 makes the 128-byte sum a multiple of 256.
        var sum = 0
        for b in bytes[0..<127] { sum += Int(b) }
        bytes[127] = UInt8(truncatingIfNeeded: 256 - sum)
        return bytes
    }

    @Test("Preferred refresh is 60 Hz for a borderless 1080p timing")
    func controlTimingWithoutBorders() throws {
        // 1920x1080 at a 148.5 MHz pixel clock: a 2200x1125 frame is exactly
        // 60.00 Hz. No borders, so this is the anchor the bordered case is
        // compared against.
        let edid = try #require(EDIDInfo(Data(Self.syntheticEDID(
            clock10kHz: 14850,
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 0, vBorder: 0))))
        #expect(edid.preferredWidth == 1920)
        #expect(edid.preferredHeight == 1080)
        #expect(edid.preferredRefreshHz == 60)
    }

    @Test("Preferred refresh drops when the detailed timing declares borders")
    func borderedTimingLowerRefresh() throws {
        // Same 1920x1080 active area and 148.5 MHz clock as the control, but
        // with a 20-pixel horizontal border on each side and a 5-line vertical
        // border on each side. Those border pixels/lines are part of every
        // frame, so the totals grow to 2240x1135 and the refresh falls:
        // 148,500,000 / (2240 * 1135) = 58.37 Hz -> 58 Hz. Before the border fix
        // the totals ignored the borders (2200x1125) and the mode read as 60 Hz,
        // i.e. too high — exactly the regression this test pins down.
        let edid = try #require(EDIDInfo(Data(Self.syntheticEDID(
            clock10kHz: 14850,
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 20, vBorder: 5))))
        // The addressable image (the resolution the monitor runs at) is
        // unchanged: borders are black bars around the image, not part of it.
        #expect(edid.preferredWidth == 1920)
        #expect(edid.preferredHeight == 1080)
        #expect(edid.preferredRefreshHz == 58)
    }
}
