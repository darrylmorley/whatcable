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

    // MARK: - Detailed-timing border bytes and the preferred refresh rate

    /// Build a minimal valid 128-byte EDID 1.4 base block whose first
    /// descriptor slot (offset 54) carries a detailed timing with the given
    /// fields. Only the bytes `EDIDInfo` reads are populated: the 8-byte
    /// header, the 1.4 version bytes, the 18-byte detailed timing at offset
    /// 54, and a zero extension count (byte 126). The other three descriptor
    /// slots stay zero, so they are inert — a zero pixel clock is not a
    /// detailed timing, and a zero descriptor tag is not a monitor descriptor.
    /// Used to exercise the preferred-mode parse in isolation, in particular
    /// the refresh-rate formula's handling of the horizontal/vertical border
    /// bytes (detailed-timing offsets +15 / +16 per the EDID 1.4 spec).
    static func syntheticDetailedTimingBaseBlock(
        hActive: Int, hBlank: Int,
        vActive: Int, vBlank: Int,
        hBorder: Int, vBorder: Int,
        pixelClock10kHz: Int
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 128)
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        for (i, b) in header.enumerated() { bytes[i] = b }
        bytes[18] = 1   // EDID 1.4
        bytes[19] = 4
        bytes[126] = 0  // no extension blocks

        let off = 54 // first descriptor slot == preferred timing
        // Pixel clock in 10 kHz units, little-endian word.
        bytes[off]     = UInt8(truncatingIfNeeded: pixelClock10kHz)
        bytes[off + 1] = UInt8(truncatingIfNeeded: pixelClock10kHz >> 8)
        // Active / blanking are split across a low byte and a high nibble.
        bytes[off + 2] = UInt8(truncatingIfNeeded: hActive)
        bytes[off + 3] = UInt8(truncatingIfNeeded: hBlank)
        bytes[off + 4] = UInt8(truncatingIfNeeded: (((hActive >> 8) << 4) | ((hBlank >> 8) & 0x0F)))
        bytes[off + 5] = UInt8(truncatingIfNeeded: vActive)
        bytes[off + 6] = UInt8(truncatingIfNeeded: vBlank)
        bytes[off + 7] = UInt8(truncatingIfNeeded: (((vActive >> 8) << 4) | ((vBlank >> 8) & 0x0F)))
        bytes[off + 15] = UInt8(truncatingIfNeeded: hBorder) // horizontal border, each side
        bytes[off + 16] = UInt8(truncatingIfNeeded: vBorder) // vertical border, each side
        return bytes
    }

    @Test("Preferred refresh accounts for non-zero h/v borders (lowers the rate)")
    func preferredRefreshHzAccountsForBorders() throws {
        // 1920x1080 active, 148.5 MHz pixel clock, with a 16-pixel horizontal
        // border and an 8-line vertical border on each side. Hand-computed
        // period (borders counted twice — one per side):
        //   hTotal = 1920 + 280 + 2×16 = 2232
        //   vTotal = 1080 +  45 + 2×8  = 1141
        //   rate   = round(148_500_000 / (2232 × 1141)) = round(58.31) = 58
        // Without borders the period would be 2200 × 1125 and the rate 60 —
        // the too-high value this test guards against.
        let bytes = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 16, vBorder: 8,
            pixelClock10kHz: 14850
        )
        let edid = try #require(EDIDInfo(Data(bytes)))
        // Borders are timing overhead, not addressable pixels: the reported
        // resolution stays the active (addressable) area.
        #expect(edid.preferredWidth == 1920)
        #expect(edid.preferredHeight == 1080)
        #expect(edid.preferredRefreshHz == 58)
    }

    @Test("Zero borders leave the preferred refresh rate unchanged (control)")
    func preferredRefreshHzZeroBordersControl() throws {
        // Same timing as the bordered case but with zero borders: the rate is
        // the plain 148_500_000 / (2200 × 1125) = 60. This must hold both
        // before and after the border fix, proving borders are only ever added.
        let bytes = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 0, vBorder: 0,
            pixelClock10kHz: 14850
        )
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.preferredRefreshHz == 60)
    }

    @Test("Each border axis widens the period independently and on both sides")
    func preferredRefreshHzAppliesEachBorderAxis() throws {
        // Horizontal border only (16 px each side): hTotal = 2232, vTotal = 1125.
        //   rate = round(148_500_000 / (2232 × 1125)) = round(59.10) = 59
        let hOnly = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 16, vBorder: 0,
            pixelClock10kHz: 14850
        )
        #expect(try #require(EDIDInfo(Data(hOnly))).preferredRefreshHz == 59)

        // Vertical border only (8 lines each side): hTotal = 2200, vTotal = 1141.
        //   rate = round(148_500_000 / (2200 × 1141)) = round(59.16) = 59
        let vOnly = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 0, vBorder: 8,
            pixelClock10kHz: 14850
        )
        #expect(try #require(EDIDInfo(Data(vOnly))).preferredRefreshHz == 59)
    }
}
