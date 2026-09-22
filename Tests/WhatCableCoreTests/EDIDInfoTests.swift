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
    /// Verbatim from `research/displays/dumps/2026-05-30_m3max_lg-ultrafine.md`.
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
        #expect(edid.rangeLimits?.maxVerticalHz == 100)
        #expect(edid.rangeLimits?.maxPixelClockHz == 600_000_000)
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
        #expect(edid.rangeLimits?.maxPixelClockHz == 600_000_000)
    }

    @Test("Detailed-timing scan reads both base and extension descriptors")
    func scansAllDetailedTimings() throws {
        let bytes = Self.g34wBaseBlock + Self.hexBytes(Self.g34wExtensionHex)
        // The G34w declares its top mode (3440x1440 at ~100 Hz, 533.16 MHz) as
        // a detailed timing in the CTA extension, above the base block's 60 Hz
        // preferred (319.89 MHz). The scan must find it. The 0xFD ceiling
        // (600 MHz) still covers it, so the diagnostic's max is unchanged, but
        // this proves the extension scan reads a real higher mode that the base
        // block alone misses.
        let top = try #require(EDIDInfo(Data(bytes))).topMode
        #expect(top?.pixelClockHz == 533_160_000)
        #expect(top?.width == 3440)
        #expect(top?.height == 1440)
    }

    @Test("The 0xFD ceiling sits above every real timing, and reads as its own figure")
    func ceilingIsNotAMode() throws {
        // The #596 shape: the envelope is higher than any mode the panel has.
        // The G34w declares a 600 MHz pixel-clock ceiling in its 0xFD
        // descriptor while its top real timing is 533.16 MHz. The two must not
        // be conflated: one is what the panel will accept, the other is what it
        // can actually show.
        let bytes = Self.g34wBaseBlock + Self.hexBytes(Self.g34wExtensionHex)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.rangeLimits?.maxPixelClockHz == 600_000_000)
        #expect(edid.topMode?.pixelClockHz == 533_160_000)
        #expect(edid.rangeLimits?.maxPixelClockHz != edid.topMode?.pixelClockHz)
    }

    @Test("A mode declared only in the CTA extension becomes the top detailed timing")
    func extensionModeBecomesTopTiming() throws {
        // Base block (0xFD ceiling = 600 MHz) plus a synthetic CTA extension
        // whose detailed timing is 640 MHz, above the base ceiling. This is the
        // case that needs the extension scan: a real monitor where the top mode
        // lives only in the extension. The top timing must follow it, while the
        // 0xFD envelope stays exactly what the descriptor said.
        var bytes = Self.g34wBaseBlock
        var ext = [UInt8](repeating: 0, count: 128)
        ext[0] = 0x02 // CTA-861 tag
        ext[1] = 0x03 // revision
        ext[2] = 0x04 // detailed timings start right after the 4-byte header
        // Detailed timing at extension offset 4: pixel clock 640 MHz = 64000
        // (0xFA00) in 10 kHz units, little-endian.
        ext[4] = 0x00
        ext[5] = 0xFA
        // A small but whole picture (128x64, 16 + 8 blanking): `topMode` only considers
        // entries with a non-zero picture and totals, so a clock alone is not enough to top
        // the list.
        ext[6] = 0x80 // h-active 128
        ext[7] = 0x10 // h-blank 16
        ext[9] = 0x40 // v-active 64
        ext[10] = 0x08 // v-blank 8
        bytes.append(contentsOf: ext)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.topMode?.pixelClockHz == 640_000_000)
        // And the envelope is byte 9 of the 0xFD descriptor, nothing else:
        // a higher detailed timing never raises it.
        #expect(edid.rangeLimits?.maxPixelClockHz == 600_000_000)
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
        #expect(edid.rangeLimits?.maxVerticalHz == 60)
        #expect(edid.rangeLimits?.maxPixelClockHz == 600_000_000)
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

    @Test("Non-zero h/v borders do not affect the preferred refresh rate")
    func preferredRefreshHzAccountsForBorders() throws {
        // 1920x1080 active, 148.5 MHz pixel clock, with a 16-pixel horizontal border and an
        // 8-line vertical border on each side. edid-decode's own comment at
        // parse-base-block.cpp:1010 (`detailed_timings`) rules that
        // hTotal = hact + hblank and vTotal = vact + vblank, straight off the bytes, with NO
        // border term: edid-decode's blanking figure already has the border subtracted out of
        // it before its front/back-porch split, and that same border amount is added back in
        // when the porches are summed into a total, so the two cancel and the raw hblank/vblank
        // bytes already are the right blanking to add. So:
        //   hTotal = 1920 + 280 = 2200, vTotal = 1080 + 45 = 1125
        //   rate   = round(148_500_000 / (2200 × 1125)) = round(60.0) = 60
        // This used to read 58 (borders double-counted into the total): that was the bug this
        // task's border-arithmetic ruling fixes, per the plan's explicit instruction to rewrite
        // this test to the new totals.
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
        #expect(edid.preferredRefreshHz == 60)
    }

    @Test("Zero borders leave the preferred refresh rate unchanged (control)")
    func preferredRefreshHzZeroBordersControl() throws {
        // Same timing as the bordered case but with zero borders: the rate is
        // the plain 148_500_000 / (2200 × 1125) = 60. Border bytes never move the total
        // now (see the test above), so this is identical to that one; kept as its own test
        // because it is the simplest possible case and the one every reader checks first.
        let bytes = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 0, vBorder: 0,
            pixelClock10kHz: 14850
        )
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.preferredRefreshHz == 60)
    }

    @Test("A border on only one axis still does not affect the preferred refresh rate")
    func preferredRefreshHzAppliesEachBorderAxis() throws {
        // Horizontal border only (16 px each side): hTotal = 1920 + 280 = 2200 (border excluded),
        // vTotal = 1080 + 45 = 1125. rate = round(148_500_000 / (2200 × 1125)) = 60.
        let hOnly = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 16, vBorder: 0,
            pixelClock10kHz: 14850
        )
        #expect(try #require(EDIDInfo(Data(hOnly))).preferredRefreshHz == 60)

        // Vertical border only (8 lines each side): hTotal = 2200, vTotal = 1080 + 45 = 1125
        // (border excluded). rate = round(148_500_000 / (2200 × 1125)) = 60.
        let vOnly = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1920, hBlank: 280,
            vActive: 1080, vBlank: 45,
            hBorder: 0, vBorder: 8,
            pixelClock10kHz: 14850
        )
        #expect(try #require(EDIDInfo(Data(vOnly))).preferredRefreshHz == 60)
    }

    // MARK: - DisplayID extension
    //
    // DisplayID is a second, newer extension format (EDID extension tag
    // 0x70) that some panels use to declare their real top mode instead of,
    // or in addition to, a base-block or CTA-861 detailed timing. Layout:
    // a 128-byte block starting 0x70, structure version (0x12 = 1.2,
    // 0x13 = 1.3, 0x20 = 2.0), section length, product type, extension
    // count, then data blocks (tag, revision, payload length, payload)
    // starting at block byte 5. Type I timings (tag 0x03, DisplayID 1.x)
    // give the pixel clock in 10 kHz units, same as a base/CTA detailed
    // timing; Type VII timings (tag 0x22, DisplayID 2.0) use 1 kHz units
    // instead, same 20-byte payload shape otherwise.

    /// MSI MAG274Q QD E2, 384 bytes, captured live from a real Mac
    /// (`research/customer-probes/m1pro_macos26.5.2_z`). Base block + CTA-861
    /// extension (tag 0x02) + DisplayID 1.2 extension (tag 0x70, version
    /// 0x12). The DisplayID block holds one Type I data block (tag 0x03,
    /// four 20-byte timings); the fourth is the panel's real top mode,
    /// above anything the base or CTA blocks carry.
    static let mag274qHex =
        "00ffffffffffff003669c2ac000000000f220104b53c2178f957a5af4f3db727085054bfcf0081809500b300d1c0714fa9c0b33cd1fc386100a0a0a055503020350055502100001a000000fd0c30b4ffff48010a202020202020000000fc004d414732373451205144204532000000ff004343324848333437303135343802bd020333f123090707830100004a0103049011131f203f12e2007fe305c000e6060701665f006d1a0000020130b4000473217321023a801871382d40582c450055502100001e6fc200a0a0a055503020350055502100001aa08380a070382d403020350055502100001a00000000000000000000000000000000000000000000b8701279030003015034e30004ff099f002f001f009f052c0002000400fb310004ff049f002f001f009f052800020004004f110104ff099f002f001f009f05760002000400a7230104ff099f002f001f009f0554000200040000000000000000000000000000000000000000000000000000000000000000000000000000000a90"

    /// HG573T42, 384 bytes, captured live from a real Mac
    /// (`research/customer-probes/m4pro_macos26.6.2_e`). Base block + CTA-861
    /// extension (tag 0x02) + DisplayID 2.0 extension (tag 0x70, version
    /// 0x20). Four separate Type VII data blocks (tag 0x22), one 20-byte
    /// timing each, pixel clock in 1 kHz units rather than Type I's 10 kHz.
    static let hg573t42Hex =
        "00ffffffffffff004a8b42730000000015230104a5000078fe6435a5544f9e27125054210800d1c0a9c081c00101010101010101010150d000a0f0703e803020350061632100001a50d000a0f0703e803020350061632100001a000000fc0048473537335434320a20202020000000fd0028781e8780010a2020202020200299020334f149104c5d5e5f60613f7623097f078301000067030c002000b8ff67d85dc401ff8043e200eae3056000e606050169694f023a801871382d40582c450061632100001e565e00a0a0a029503020350061632100001e0000000000000000000000000000000000000000000000000000000000000000000000000000008970207900002200143f461084ff0e9f002f801f006f083d0002000400220014df8f0d04ff0e9f002f801f006f083d0002000400220014af340c04ff0e9f002f801f006f083d0002000400220014e72b0a04ff0e9f002f801f006f083d000200040000000000000000000000000000000000000000000000000000000000001490"

    /// DELL S2725QC, 384 bytes, captured live from a real Mac
    /// (`research/customer-probes/m4_macos26.5.2_j`). Base block byte 126
    /// declares 1 extension, but the buffer carries two: a CTA-861 block
    /// (tag 0x02) and, beyond what byte 126 admits, a DisplayID 1.2 block
    /// (tag 0x70) whose Type I timings include the panel's real 4K120 mode.
    static let s2725qcHex =
        "00ffffffffffff0010ac73a2000000001b230103803c2278eae1b5ac524d9d230e5054a54b00714f8180a9c0a940d1c0e1000101010108e80030f2705a80b0588a0055502100001e000000ff0000000000000000000000000000000000fc0044454c4c20533237323551430a000000fd0030781bff77000a20202020202001a9020364f1e278025361010302040510121113141f20213f5d5e5f7623090707830100006d030c00100038442000600302016ad85dc40178886b023078e40f010004e305c301e6060501626227741a000003013078e6000000000078000000008000e200ea565e00a0a0a029503020350055502100001a0000000000000000006270123f030003013c856f00047f079f002f801f0037043f00020004006ec20004ff099f002f801f009f055400020004000fd00104ff0e2f02af8057006f08590007800900520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090"

    @Test("MAG274Q: a Type I timing in a DisplayID 1.2 block becomes the top detailed timing")
    func mag274qDisplayIDTypeITopTiming() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.mag274qHex))))
        #expect(edid.topMode?.width == 2560)
        #expect(edid.topMode?.height == 1440)
        #expect(edid.topMode.map { Int($0.refreshHz.rounded()) } == 180)
        #expect(edid.topMode?.pixelClockHz == 746_640_000)
        // The 0xFD envelope is a separate signal from the real top mode and
        // must not move when the top mode changes.
        #expect(edid.rangeLimits?.maxPixelClockHz == 720_000_000)
        #expect(edid.monitorName == "MAG274Q QD E2")
    }

    @Test("MAG274Q: the full parse reads the DisplayID block directly")
    func mag274qHighestDetailedTimingReadsDisplayIDDirectly() throws {
        let bytes = Self.hexBytes(Self.mag274qHex)
        #expect(try #require(EDIDInfo(Data(bytes))).topMode?.pixelClockHz == 746_640_000)
    }

    // This test originally asserted the top mode came from the DisplayID Type VII block, back
    // when the CTA-861 extension only contributed its trailing DTDs. `EDIDCTAParser` also
    // decodes the Video Data Block now, and this real monitor declares VIC 118 there
    // (`edid-decode-bin --skip-hex-dump --skip-sha` on `hg573t42Hex`:
    // "VIC 118: 3840x2160 120.000000 Hz 16:9 270.000 kHz 1188.000000 MHz"), a higher pixel clock
    // than every DisplayID timing. Ruling: VIC 118 is a real fact this monitor declares and
    // must win `topMode`; the test now asserts that, and separately confirms the Type VII record
    // it used to check (a real DisplayID timing, at the same 3840x2160 120 Hz but a different,
    // lower pixel clock: `edid-decode-bin`: "DTD: 3840x2160 120.000000 Hz 16:9 266.640 kHz
    // 1066.560000 MHz") still decodes with 1 kHz clock units, not Type I's 10 kHz.
    @Test("HG573T42: CTA's VIC 118 outranks the DisplayID Type VII timing as the top mode; Type VII still uses 1 kHz units")
    func hg573t42DisplayIDTypeVIIUsesOneKHzUnits() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.hg573t42Hex))))
        #expect(edid.topMode?.width == 3840)
        #expect(edid.topMode?.height == 2160)
        #expect(edid.topMode.map { Int($0.refreshHz.rounded()) } == 120)
        #expect(edid.topMode?.pixelClockHz == 1_188_000_000)
        if case .ctaVIC(_, 118, false, false) = edid.topMode?.source {
            // expected: the real top mode is CTA VIC 118, not a DisplayID timing.
        } else {
            Issue.record("expected topMode.source to be .ctaVIC(_, 118, false, false), got \(String(describing: edid.topMode?.source))")
        }

        // The DisplayID Type VII record this test originally guarded still decodes correctly at
        // 1 kHz clock units. If it were misread as 10 kHz units (Type I's unit) this would come
        // out as 10_665_600_000 Hz: asserting the exact value means that unit mistake cannot pass.
        let typeVII = try #require(edid.modes.first {
            if case .displayID(_, .typeVII, 0, false) = $0.source { return true }
            return false
        })
        #expect(typeVII.width == 3840); #expect(typeVII.height == 2160)
        #expect(typeVII.pixelClockHz == 1_066_560_000)
        #expect(edid.rangeLimits?.maxPixelClockHz == 1_280_000_000)
    }

    // A data block decodes by its OWN tag, whatever the section version says: the tag byte
    // defines the record layout, the section version is metadata. edid-decode's own
    // `tag_version` check treats a tag/version mismatch as a spec violation it warns on, and
    // decodes the record anyway. Measured in the corpus: no 0x22 (Type VII) tag ever appears in
    // a 1.x section and no 0x03 (Type I) tag in a 2.0 section, so no real EDID changes hands
    // under this rule; it only reaches these two contrived, never-real mismatches, which is why
    // the previous opposite rule (decode only when tag and version agree) is reversed here.

    @Test("displayID: a Type VII tag inside a DisplayID 1.x section decodes by its own tag")
    func displayIDTypeVIITagInsideOnePointXSectionDecodesByTag() throws {
        var bytes = Self.g34wBaseBlock
        bytes[126] = 1 // one extension block
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x70 // DisplayID extension tag
        block[1] = 0x12 // section version: DisplayID 1.2
        block[2] = 0x17 // section length: 3-byte header + 20-byte payload
        block[3] = 0x03 // product type
        block[4] = 0x00 // extension count
        block[5] = 0x22 // data block tag: Type VII (a 2.0 record layout, inside a 1.2 section)
        block[6] = 0x00 // revision
        block[7] = 0x14 // payload length: 20 bytes
        // HG573T42's first Type VII record: 3840x2160 hTotal 4000 vTotal 2222 1066560000 Hz
        // (edid-decode evidence: `hg573t42.hex`).
        let record = Self.hexBytes("3f461084ff0e9f002f801f006f083d0002000400")
        for (i, b) in record.enumerated() { block[8 + i] = b }
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.topMode?.width == 3840)
        #expect(edid.topMode?.height == 2160)
        #expect(edid.topMode?.pixelClockHz == 1_066_560_000)
    }

    @Test("displayID: a Type I tag inside a DisplayID 2.0 section decodes by its own tag")
    func displayIDTypeITagInsideTwoPointOhSectionDecodesByTag() throws {
        var bytes = Self.g34wBaseBlock
        bytes[126] = 1 // one extension block
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x70
        block[1] = 0x20 // section version: DisplayID 2.0
        block[2] = 0x17
        block[3] = 0x03
        block[4] = 0x00
        block[5] = 0x03 // data block tag: Type I (a 1.x record layout, inside a 2.0 section)
        block[6] = 0x00
        block[7] = 0x14
        // MAG274Q's fourth Type I record: 2560x1440 hTotal 2720 vTotal 1525 746640000 Hz
        // (edid-decode evidence: `mag274q.hex`).
        let record = Self.hexBytes("a7230104ff099f002f001f009f05540002000400")
        for (i, b) in record.enumerated() { block[8 + i] = b }
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.topMode?.width == 2560)
        #expect(edid.topMode?.height == 1440)
        #expect(edid.topMode?.pixelClockHz == 746_640_000)
    }

    // This test used tag 0x04 (Type II) when the walker handled only tags 0x03 and 0x22.
    // The walker now decodes Type II data blocks for real (11-byte CVT-free
    // records; `EDIDDisplayIDTimingDecoders.typeII`), so 0x04 is no longer an example of a tag
    // the walker leaves alone: its own bytes here (`ff ff ff ...`) now decode to a real, if
    // absurd, Type II mode (clock units 0xFFFFFF, 167,772,160,000 Hz) rather than being skipped.
    // Ruling: the test's purpose (an unhandled tag's payload must never be misread as if it were
    // a fixed-format timing) is preserved by moving to a tag the walker genuinely leaves alone
    // (0x0A, Product Serial Number Data Block, `default: break` in `EDIDDisplayIDParser`).
    @Test("A DisplayID data block whose tag the walker does not decode is skipped")
    func nonTimingDisplayIDBlockSkipped() throws {
        var bytes = Self.g34wBaseBlock
        bytes[126] = 1 // one extension block
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x70 // DisplayID extension tag
        block[1] = 0x12 // DisplayID 1.2
        block[2] = 0x17 // section length: 3-byte data-block header + 20-byte payload
        block[3] = 0x03 // product type
        block[4] = 0x00 // extension count
        block[5] = 0x0A // data block tag: Product Serial Number, not a tag the walker decodes
        block[6] = 0x00 // revision
        block[7] = 0x14 // payload length: 20 bytes
        // Payload: if misread as a 20-byte timing, the first three bytes
        // decode to a huge pixel clock under either unit (167.77 GHz at
        // Type I's 10 kHz, 16.78 GHz at Type VII's 1 kHz), well above the
        // base block's real top mode. A correct tag check must skip this
        // block regardless of which unit it would have used.
        block[8] = 0xFF
        block[9] = 0xFF
        block[10] = 0xFF
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.topMode?.pixelClockHz == 319_890_000)
    }

    @Test("A DisplayID timing block whose length is not a multiple of 20 is skipped")
    func misalignedDisplayIDTimingBlockSkipped() throws {
        var bytes = Self.g34wBaseBlock
        bytes[126] = 1 // one extension block
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x70
        block[1] = 0x12
        block[2] = 0x21 // section length: 3-byte header + 30-byte payload
        block[3] = 0x03
        block[4] = 0x00
        block[5] = 0x03 // data block tag: Type I timing
        block[6] = 0x00 // revision
        block[7] = 0x1E // payload length: 30 bytes, not a multiple of 20
        // First 20 bytes decode to a huge pixel clock. Without the guard the
        // inner loop reads this as one valid 20-byte timing (the trailing 10
        // bytes going unread), well above the base block's real top mode.
        // With the guard the whole block is rejected. The remaining 10 bytes
        // of the 30-byte payload stay zero.
        block[8] = 0xFF
        block[9] = 0xFF
        block[10] = 0xFF
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.topMode?.pixelClockHz == 319_890_000)
    }

    @Test("A DisplayID section length past the block end never indexes out of range")
    func sectionLengthPastBlockEndClamped() throws {
        var bytes = Self.g34wBaseBlock
        bytes[126] = 1 // one extension block
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x70
        block[1] = 0x12
        block[2] = 0xFF // section length claims far more than the 128-byte block holds
        block[3] = 0x03
        block[4] = 0x00
        block[5] = 0x03 // data block tag: Type I timing
        block[6] = 0x00 // revision
        block[7] = 0x14 // payload length: 20 bytes
        let timing = Self.hexBytes("a7230104ff099f002f001f009f05540002000400") // MAG274Q's fourth timing
        for (i, b) in timing.enumerated() { block[8 + i] = b }
        // Non-zero past the timing, so the walk cannot stop early on the
        // zero-tag/zero-length end marker: only the sectionEnd clamp keeps
        // it from reading past the 128-byte block.
        for i in 28...126 { block[i] = 0x01 }
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))
        // The walk must clamp to the 128-byte block and still return the
        // timing it can read, rather than crashing.
        #expect(edid.topMode?.pixelClockHz == 746_640_000)
    }

    @Test("An extension count larger than the buffer is walked only as far as the bytes go")
    func extensionCountLargerThanBufferWalksOnlyPresentBytes() throws {
        var bytes = Self.g34wBaseBlock
        bytes[126] = 3 // claims three extension blocks; only one is appended
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x70
        block[1] = 0x12
        block[2] = 0x17 // sane section length: 3-byte header + 20-byte payload
        block[3] = 0x03
        block[4] = 0x00
        block[5] = 0x03
        block[6] = 0x00
        block[7] = 0x14
        let timing = Self.hexBytes("a7230104ff099f002f001f009f05540002000400") // MAG274Q's fourth timing
        for (i, b) in timing.enumerated() { block[8 + i] = b }
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.topMode?.pixelClockHz == 746_640_000)

        // Truncated to the base block plus a partial extension: must not
        // crash, and falls back to the base block's own real top mode.
        let truncated = Array(bytes.prefix(200))
        let truncatedEDID = try #require(EDIDInfo(Data(truncated)))
        #expect(truncatedEDID.topMode?.pixelClockHz == 319_890_000)
    }

    @Test("A DisplayID data block whose payload runs past the section end is rejected whole")
    func dataBlockPayloadOverrunsSectionEndRejected() throws {
        var bytes = Self.g34wBaseBlock
        bytes[126] = 1 // one extension block
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x70
        block[1] = 0x12
        block[2] = 0x17 // section length: one 3-byte header + 20 bytes, not 40
        block[3] = 0x03
        block[4] = 0x00
        block[5] = 0x03 // data block tag: Type I timing
        block[6] = 0x00 // revision
        block[7] = 0x28 // payload length: 40 bytes, twice what the section holds
        let timing = Self.hexBytes("a7230104ff099f002f001f009f05540002000400") // MAG274Q's fourth timing
        for (i, b) in timing.enumerated() { block[8 + i] = b }
        // A second, far higher pixel clock right after it: if the overrunning
        // block were read instead of rejected, this is what a correct decode
        // of the (wrong) 40-byte payload would surface as the top mode.
        var secondTiming = timing
        secondTiming[0] = 0xFF
        secondTiming[1] = 0xFF
        secondTiming[2] = 0x0F
        for (i, b) in secondTiming.enumerated() { block[28 + i] = b }
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))
        // The overrunning block is rejected whole, so neither timing counts;
        // the base block's own real top mode is what's left.
        #expect(edid.topMode?.pixelClockHz == 319_890_000)
    }

    @Test("S2725QC: a DisplayID block beyond the extension count in byte 126 is still walked")
    func s2725qcDisplayIDBlockBeyondExtensionCountByteWalked() throws {
        let bytes = Self.hexBytes(Self.s2725qcHex)
        // Fixture guards: byte 126 under-declares what the buffer actually holds.
        #expect(bytes[126] == 1)
        #expect(bytes.count == 384)

        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.monitorName == "DELL S2725QC")
        #expect(edid.topMode?.width == 3840)
        #expect(edid.topMode?.height == 2160)
        #expect(edid.topMode.map { Int($0.refreshHz.rounded()) } == 120)
        #expect(edid.topMode?.pixelClockHz == 1_188_000_000)
        // The 0xFD envelope is a separate signal from the real top mode and
        // must not move when the top mode changes.
        #expect(edid.rangeLimits?.maxPixelClockHz == 1_190_000_000)
        // Byte 126 is a fact, never a bound: it says 1, the walker still finds 3 real blocks
        // (base + CTA + the DisplayID block beyond what byte 126 admits).
        #expect(edid.declaredExtensionCount == 1)
        #expect(edid.blocks.count == 3)
    }

    // Same record in a Type VII data block (tag 0x22, DisplayID 2.0 section, 1 kHz clock units
    // so the clock reads 48.337 MHz) with revision byte 0x09: revision 1 in bits 0-2, plus bit
    // 3 (DSC pass-through), a per-block flag. edid-decode's `parse_displayid_data_block` reads
    // `block_rev = x[1] & 0x07` before the `block_rev < 2` preferred test, so bits 3 to 6 do
    // not disqualify the flag. `edid-decode-bin --skip-hex-dump --skip-sha <synth-n1.hex>`:
    //   Video Timing Modes Type 7 - Detailed Timings Data Block:
    //     These timings support DSC pass-through
    //     DTD:  2560x2880    5.999647 Hz   0:0     17.771 kHz     48.337000 MHz (aspect undefined, no 3D stereo, preferred)
    @Test("EDIDInfo: the DisplayID preferred flag reads the revision from the low three bits of the revision byte")
    func edidInfoPreferredFlagMasksRevisionByte() throws {
        let record = Self.hexBytes("d0bc0088ff099f0007801f003f0b510000000700")
        var base = EDIDTestBuilder.baseBlock(version: (1, 4))
        base[126] = 1
        base = EDIDTestBuilder.withChecksum(base)
        let bytes = base + EDIDTestBuilder.displayIDBlock(version: 0x20, dataBlocks: [(tag: 0x22, revision: 0x09, payload: record)])
        let edid = try #require(EDIDInfo(Data(bytes)))
        let want = EDIDMode(
            width: 2560, height: 2880, hTotal: 2720, vTotal: 2962, pixelClockHz: 48_337_000,
            interlaced: false, source: .displayID(block: 1, type: .typeVII, index: 0, embeddedInCTA: false))
        #expect(edid.modes == [want])
        #expect(edid.preferredMode == want)
    }

    // MARK: Elo 4600L: a CTA DTD declared after two display descriptors
    //
    // `edid-decode-data/elo-4600l-hdmi` (MIT), 256 bytes. Its CTA block's DTD area holds DTD 3,
    // then two Manufacturer-Specified Display Descriptors (bytes 0-1 zero, not all-zero), then
    // DTD 4. edid-decode's `parse_cta_block` stops the walk only on an all-zero 18-byte slot
    // (`if (memchk(detailed, 18)) break;`) and hands every other slot to `detailed_block`, so
    // DTD 4 is reached. `edid-decode-bin --skip-hex-dump --skip-sha elo-4600l-hdmi`:
    //   Detailed Timing Descriptors:
    //     DTD 3:   512x1680    9.562384 Hz  32:105   17.595 kHz     74.250000 MHz (digital composite, ...)
    //     Manufacturer-Specified Display Descriptor (0x00): 1a 00 00 00 f7 00 0a 00 ca e0 60 00 00 00 00 00
    //     Manufacturer-Specified Display Descriptor (0x00): 00 00 00 00 fc 00 45 4c 4f 20 45 54 34 36 30 30
    //     DTD 4:    32x0            inf Hz   1:0   2583.750 kHz     82.680000 MHz (analog composite, sync-on-green)
    //                  Hfront    0 Hsync   0 Hback    0 Hpol N
    //                  Vfront    0 Vsync   0 Vback    0 Vpol N
    // DTD 4 is garbage (32 wide, 0 high, refresh inf) and the test asserts it is present with its
    // declared clock, whatever the picture: the rule under test is the walk, not the mode.
    static let elo4600LHex =
        "00ffffffffffff00158f0046f07200001e170103806639782a609da154499b260f474a23080081c0814081809500b300" +
        "d1c08bc00101023a801871382d40582c4500fa3d3200001e662156aa51001e30468f3300fa3d3200001e000000fd0030" +
        "3e1f500f000a202020202020000000fe0031423243335030303435300a2001a102031b40471631041901031823090707" +
        "8301000066030c00200080011d007c2e90a0601a1e4030203600a20b3200001a000000f7000a00cae060000000000000" +
        "0000000000fc00454c4f204554343630304c202000000000000000000000000000000000000000000000000000000000" +
        "000000000000000000000000000000c1"

    @Test("cta: a DTD after a display descriptor in the CTA block is walked, per edid-decode's all-zero stop rule")
    func ctaEloDTDAfterDisplayDescriptorsIsWalked() throws {
        let bytes = Self.hexBytes(Self.elo4600LHex)
        #expect(bytes.count == 256) // fixture guard
        let edid = try #require(EDIDInfo(Data(bytes)))
        let ctaDTDs = edid.modes.filter {
            if case .detailedTiming(block: 1, _) = $0.source { return true }
            return false
        }
        #expect(ctaDTDs.count == 2, "expected DTD 3 and DTD 4, got \(ctaDTDs.map(\.sourceDescription))")
        let dtd3 = try #require(ctaDTDs.first { $0.pixelClockHz == 74_250_000 })
        #expect(dtd3.width == 512 && dtd3.height == 1680)
        let dtd4 = try #require(ctaDTDs.first { $0.pixelClockHz == 82_680_000 })
        #expect(dtd4.width == 32 && dtd4.height == 0 && dtd4.vTotal == 0)
        if case .detailedTiming(block: 1, index: 1) = dtd4.source {} else {
            Issue.record("expected DTD 4 as .detailedTiming(block: 1, index: 1), got \(dtd4.sourceDescription)")
        }
    }

    // MARK: - DisplayID section walker
    //
    // EDIDDisplayIDParser walks the whole 0x70 section: every data block that can name a mode
    // (Types I-X, the VESA DMT and CTA VIC bitmaps), plus the video-timing-range (0x09),
    // tiled-topology (0x12/0x28) and dynamic-range (0x25) blocks the model exposes. Every
    // expected value below is transcribed from a real `edid-decode-bin` run; the exact command
    // and output are in each test's comment.

    /// Apple Studio Display, 512 bytes, captured live from a real Mac
    /// (`research/customer-probes/m3max_macos26.5_f`). Base block + CTA-861 extension (tag 0x02)
    /// + two DisplayID 1.2 extensions (tag 0x70): the first carries a ContainerID block, a
    /// Display Parameters block, an Apple vendor block, the Tiled Display Topology block this
    /// test reads, a VESA vendor block and a second Apple vendor block, none of which name a
    /// mode; the second carries the panel's real 5120x2880 Type I preferred timing.
    static let studioDisplayHex =
        "00ffffffffffff0006103aae0000000007200104c53c2178000f91ae5243b0260f505400000001010101010101010101010101010101b7ce0050f0705a800820c800534f2100001ad05c0050a0a03c500820e808534f2100001abc34805070382d400820f804534f2100001a000000fc0053747564696f446973706c617903be02030f80e3050000e606010173730070bc0078a04078b00820a80800000000001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000127012790000290010e9ba8e0815a9426481fad04a261bc2e201000c4017140d0014400b10784ebb7f81070010fa0401000012001682100000ff093f0b00000000004150503bae4aacebeb7e00053a029281007e00100010fa0501010060c0d2ff550010001000000000000000000000000000000000000000000000000000219070127900000300149f6d0184ff134f0007801f003f0b77006900070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009590"

    /// Samsung Odyssey G95NC, 512 bytes, captured live from a real Mac
    /// (`research/customer-probes/m2max_macos27.0_b`). Base block + CTA-861 extension (tag 0x02)
    /// + two DisplayID 1.2 extensions (tag 0x70): the first carries five Type I timings plus the
    /// Dynamic Video Timing Range Limits block this test reads; the second carries five more
    /// Type I timings.
    static let g95ncHex =
        "00ffffffffffff004c2d7574000000001d230104b58c28783a4ed5ae4e45aa270e505425cf00714f81c0810081809500a9c0b300d1c01a6800a0f0381f4030203a0078905100001a000000fd081ef01effff000a202020202020000000fc004f647973736579204739354e43000000ff000000000000000000000000000003d0020333f047615f103f0403762309070783010000e305c0006d1a0000020f30f0e90000000000e60605018b7300e5018b849079565e00a0a0a029503020350078905100001a6fc200a0a0a055503020350078905100001a74d600a0f038404030203a0078905100001a00000000000000000000000000000000000000000000ce70127903000301640a650388ff1d2f02f7801f006f08590002000900bf750608ff1d9f002f801f006f085900020009001fa00304ff0e2f02f7801f006f0859000200040033e900047f07170111801f00370432000200040033980188ff1d9f002f801f006f083d0002000900250009a761007f994030f00000000000000011907012790000030164d0b40108ff0e17016b801f00370432000200090073fc0208ff133f017f801f009f053a000200090057790108ff139f002f801f009f05540002000900af940104ff093f017f801f009f053a000200040033b70008ff139f002f801f009f05280002000900000000000000000000000000000000000000d290"

    /// Planar IX2790, 384 bytes, from edid-decode's own `data/planar-ix2790` fixture (real
    /// panel, MIT-licensed test corpus). Base block + CTA-861 extension (tag 0x02) + a DisplayID
    /// 1.2 extension (tag 0x70) carrying one Type I timing plus the VESA DMT Timings bitmap
    /// (tag 0x07) this test reads.
    static let planarIX2790Hex =
        "00ffffffffffff00418e902701010101001b0104a53c21783ad7f5ad5143b1260d5054bfef80e1c0d100d1c0b300a940a9c0818081004dd000a0f0703e8030203500534f2100001a565e00a0a0a0295030203500534f2100001a000000fd00174c0fb461000a202020202020000000fc004958323739300a2020202020200226020320f353101f04140312021105140716061501615f5e5d23097f078301000004740030f2705a80b0588a00534f2100001e0474801871705a80582c8a00534f2100001e023a801871382d40582c4500534f2100001e011d007251d01e206e285500534f2100001ec5bc00a0a04052b030203a00534f2100001a0000000000597012240300030114bc790184ff13670117805f003f0b3d002f00070007000a088100080400040210000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090"

    /// Studio Display: `edid-decode-bin --skip-hex-dump --skip-sha --long-timings <hex>`:
    ///   Block 2, DisplayID Extension Block:
    ///     ...
    ///     Tiled Display Topology Data Block (0x12):
    ///       Num horizontal tiles: 2 Num vertical tiles: 1
    ///       Tile location: 0, 0
    ///       Tile resolution: 2560x2880
    @Test("displayID: Studio Display's tiled topology block reads as two 2560x2880 horizontal tiles")
    func displayIDTiledTopologyStudioDisplay() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.studioDisplayHex))))
        let topology = try #require(edid.tiledTopology)
        #expect(topology.hTiles == 2)
        #expect(topology.vTiles == 1)
        #expect(topology.tileWidth == 2560)
        #expect(topology.tileHeight == 2880)
        #expect(topology.hLocation == 0)
        #expect(topology.vLocation == 0)
        // The block also carries the panel's real 5120x2880 preferred timing in a second
        // DisplayID block (Type I), which must still surface as the top mode.
        #expect(edid.topMode?.width == 5120)
        #expect(edid.topMode?.height == 2880)
    }

    /// Odyssey G95NC: `edid-decode-bin --skip-hex-dump --skip-sha --long-timings <hex>`:
    ///   Block 2, DisplayID Extension Block:
    ///     ...
    ///     Dynamic Video Timing Range Limits Data Block:
    ///       Minimum Pixel Clock: 25000 kHz
    ///       Maximum Pixel Clock: 4233600 kHz
    ///       Minimum Vertical Refresh Rate: 48 Hz
    ///       Maximum Vertical Refresh Rate: 240 Hz
    @Test("displayID: Odyssey G95NC's dynamic range block reads all four numbers edid-decode prints")
    func displayIDDynamicRangeLimitsOdysseyG95NC() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.g95ncHex))))
        let dynamic = try #require(edid.dynamicRangeLimits)
        #expect(dynamic.minPixelClockKHz == 25_000)
        #expect(dynamic.maxPixelClockKHz == 4_233_600)
        #expect(dynamic.minRefreshHz == 48)
        #expect(dynamic.maxRefreshHz == 240)
    }

    /// planar-ix2790: `edid-decode-bin --skip-hex-dump --skip-sha --long-timings <hex>`:
    ///   Block 2, DisplayID Extension Block:
    ///     ...
    ///     Supported Timing Modes Type 1 - VESA DMT Timings Data Block:
    ///       DMT 0x04:   640x480    59.940476 Hz ...     25.175000 MHz
    ///       DMT 0x09:   800x600    60.316541 Hz ...     40.000000 MHz
    ///       DMT 0x10:  1024x768    60.003840 Hz ...     65.000000 MHz
    ///       DMT 0x1c:  1280x800    59.810326 Hz ...     83.500000 MHz
    ///       DMT 0x23:  1280x1024   60.019740 Hz ...    108.000000 MHz
    ///       DMT 0x33:  1600x1200   60.000000 Hz ...    162.000000 MHz
    ///       DMT 0x3a:  1680x1050   59.954250 Hz ...    146.250000 MHz
    ///       DMT 0x45:  1920x1200   59.884600 Hz ...    193.250000 MHz
    /// (payload bytes `08 81 00 08 04 00 04 02 10 00`: bit 3 of byte 0 is DMT id 4, bits 0 and 7
    /// of byte 1 are ids 9 and 16, bit 3 of byte 3 is id 28 (0x1c), bit 2 of byte 4 is id 35
    /// (0x23), bit 2 of byte 6 is id 51 (0x33), bit 1 of byte 7 is id 58 (0x3a), bit 4 of byte 8
    /// is id 69 (0x45): the eight ids edid-decode lists, in bitmap order.)
    @Test("displayID: planar-ix2790's VESA DMT bitmap resolves all eight declared ids from the table")
    func displayIDVesaDMTBitmapPlanarIX2790() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.planarIX2790Hex))))
        let bitmapModes = edid.modes.filter {
            if case .displayID(_, .vesaDMTBitmap, _, _) = $0.source { return true }
            return false
        }
        #expect(bitmapModes.count == 8)
        func mode(width: Int, height: Int, hTotal: Int, vTotal: Int, pixelClockHz: Int) -> Bool {
            bitmapModes.contains {
                $0.width == width && $0.height == height && $0.hTotal == hTotal
                    && $0.vTotal == vTotal && $0.pixelClockHz == pixelClockHz
            }
        }
        #expect(mode(width: 640, height: 480, hTotal: 800, vTotal: 525, pixelClockHz: 25_175_000))    // DMT 0x04
        #expect(mode(width: 1680, height: 1050, hTotal: 2240, vTotal: 1089, pixelClockHz: 146_250_000)) // DMT 0x3a
        #expect(mode(width: 1920, height: 1200, hTotal: 2592, vTotal: 1245, pixelClockHz: 193_250_000)) // DMT 0x45
    }

    /// Synthetic DisplayID 2.0 section: one Type VIII record block (2-byte ids, VIC 97 and 118)
    /// and one Type IX record (2560x1440@144, CVT reduced blanking v2), built with
    /// `EDIDTestBuilder.displayIDBlock` and cross-checked against edid-decode on the same bytes:
    ///
    ///   Video Timing Modes Type 8 - Enumerated Timing Codes Data Block:
    ///     VIC  97:  3840x2160   60.000000 Hz ...    594.000000 MHz
    ///     VIC 118:  3840x2160  120.000000 Hz ...   1188.000000 MHz
    ///   Video Timing Modes Type 9 - Formula-based Timings Data Block:
    ///     CVT:  2560x1440  143.999784 Hz ... (RBv2) 586.586000 MHz
    ///                Hfront    8 Hsync  32 Hback   40
    ///                Vfront   89 Vsync   8 Vback    6
    @Test("displayID: a synthetic DisplayID 2.0 section decodes Type VIII (2-byte ids) and Type IX")
    func displayIDTypeVIIIAndTypeIXSynthetic() throws {
        let block = EDIDTestBuilder.displayIDBlock(version: 0x20, dataBlocks: [
            (tag: 0x23, revision: 0x48, payload: [97, 0, 118, 0]), // 2-byte ids (0x08), code type 1 (VIC)
            (tag: 0x24, revision: 0x00, payload: [0x02, 0xFF, 0x09, 0x9F, 0x05, 0x8F]),
        ])
        // A real preferred DTD is required for EDIDInfo(Data:) to parse at all; 1920x1080@60 is
        // lower than every DisplayID mode below, so it never becomes the top mode itself.
        var bytes = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1920, hBlank: 280, vActive: 1080, vBlank: 45, hBorder: 0, vBorder: 0, pixelClock10kHz: 14850
        )
        bytes[126] = 1
        bytes = EDIDTestBuilder.withChecksum(bytes)
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))

        let vic97 = try #require(edid.modes.first { if case .displayID(_, .typeVIII, 0, false) = $0.source { return true }; return false })
        #expect(vic97.width == 3840); #expect(vic97.height == 2160); #expect(vic97.pixelClockHz == 594_000_000)

        let vic118 = try #require(edid.modes.first { if case .displayID(_, .typeVIII, 1, false) = $0.source { return true }; return false })
        #expect(vic118.width == 3840); #expect(vic118.height == 2160); #expect(vic118.pixelClockHz == 1_188_000_000)

        let typeIX = try #require(edid.modes.first { if case .displayID(_, .typeIX, _, _) = $0.source { return true }; return false })
        #expect(typeIX.width == 2560)
        #expect(typeIX.height == 1440)
        #expect(typeIX.hTotal == 2640)
        #expect(typeIX.vTotal == 1543)
        #expect(typeIX.pixelClockHz == 586_586_000)
    }

    /// Synthetic DisplayID 1.3 section: a 0x08 CTA VIC bitmap for VIC 16 (bit 15, byte 1) and
    /// VIC 64 (bit 63, the last bit of byte 7, the widest byte offset the tag's 8-byte cap
    /// allows). edid-decode on the same bytes:
    ///
    ///   Supported Timing Modes Type 2 - CTA-861 Timings Data Block:
    ///     VIC  16:  1920x1080   60.000000 Hz ...    148.500000 MHz
    ///     VIC  64:  1920x1080  100.000000 Hz ...    297.000000 MHz
    @Test("displayID: a synthetic DisplayID 1.3 section decodes a 0x08 CTA VIC bitmap")
    func displayIDCtaVICBitmapSynthetic() throws {
        var bitmap = [UInt8](repeating: 0, count: 8)
        bitmap[15 / 8] |= 1 << (15 % 8) // VIC 16
        bitmap[63 / 8] |= 1 << (63 % 8) // VIC 64
        let block = EDIDTestBuilder.displayIDBlock(version: 0x13, dataBlocks: [
            (tag: 0x08, revision: 0x00, payload: bitmap),
        ])
        var bytes = Self.syntheticDetailedTimingBaseBlock(
            hActive: 1280, hBlank: 370, vActive: 720, vBlank: 30, hBorder: 0, vBorder: 0, pixelClock10kHz: 7425
        )
        bytes[126] = 1
        bytes = EDIDTestBuilder.withChecksum(bytes)
        bytes.append(contentsOf: block)
        let edid = try #require(EDIDInfo(Data(bytes)))

        let bitmapModes = edid.modes.filter {
            if case .displayID(_, .ctaVICBitmap, _, _) = $0.source { return true }
            return false
        }
        #expect(bitmapModes.count == 2)
        #expect(bitmapModes.contains { $0.width == 1920 && $0.height == 1080 && $0.pixelClockHz == 148_500_000 })  // VIC 16
        #expect(bitmapModes.contains { $0.width == 1920 && $0.height == 1080 && $0.pixelClockHz == 297_000_000 })  // VIC 64
    }

    @Test("EDIDInfo on an empty buffer returns nil without crashing")
    func edidInfoOnEmptyBufferReturnsNil() {
        #expect(EDIDInfo(Data()) == nil)
    }

    // MARK: - base block
    //
    // EDIDBaseBlockParser makes the 128-byte base block yield every mode format it can carry:
    // Established Timings I/II (bytes 35-37) and III (0xF7), Standard Timings (bytes 38-53 and
    // the 6 more a 0xFA descriptor adds), Detailed Timing Descriptors, and CVT 3-byte codes
    // (0xF8). Every expected value below is transcribed from a real `edid-decode-bin` run; the
    // exact command is in each test's comment.

    // MARK: G34w Established Timings I & II
    //
    // `edid-decode-bin --skip-hex-dump --skip-sha <g34w.hex>` (bytes = Self.g34wBaseBlock):
    //   Established Timings I & II:
    //     IBM     :   720x400    70.081663 Hz   9:5     31.467 kHz     28.320000 MHz
    //     DMT 0x04:   640x480    59.940476 Hz   4:3     31.469 kHz     25.175000 MHz
    //     DMT 0x05:   640x480    72.808802 Hz   4:3     37.861 kHz     31.500000 MHz
    //     DMT 0x06:   640x480    75.000000 Hz   4:3     37.500 kHz     31.500000 MHz
    //     DMT 0x08:   800x600    56.250000 Hz   4:3     35.156 kHz     36.000000 MHz
    //     DMT 0x09:   800x600    60.316541 Hz   4:3     37.879 kHz     40.000000 MHz
    //     DMT 0x0a:   800x600    72.187572 Hz   4:3     48.077 kHz     50.000000 MHz
    //     DMT 0x0b:   800x600    75.000000 Hz   4:3     46.875 kHz     49.500000 MHz
    //     Apple   :   832x624    74.551266 Hz   4:3     49.726 kHz     57.284000 MHz
    //     DMT 0x10:  1024x768    60.003840 Hz   4:3     48.363 kHz     65.000000 MHz
    //     DMT 0x11:  1024x768    70.069359 Hz   4:3     56.476 kHz     75.000000 MHz
    //     DMT 0x12:  1024x768    75.028582 Hz   4:3     60.023 kHz     78.750000 MHz
    //     DMT 0x24:  1280x1024   75.024675 Hz   5:4     79.976 kHz    135.000000 MHz
    // (bytes 35-37 = af ef 00; the byte/bit each line comes from, and the hTotal/vTotal/
    // pixelClockKHz behind each DMT id, are `EDIDEstablishedTimings.legacy` itself, ported from
    // edid-decode's `established_timings12[]`, parse-base-block.cpp:252.)
    @Test("baseBlock: G34w Established Timings I & II decode to the DMT/legacy modes edid-decode lists")
    func baseBlockG34wEstablishedTimings() throws {
        let edid = try #require(EDIDInfo(Data(Self.g34wBaseBlock)))
        let established = edid.modes.filter {
            if case .establishedTiming = $0.source { return true }
            return false
        }
        #expect(established.count == 13)

        func mode(_ width: Int, _ height: Int, _ hTotal: Int, _ vTotal: Int, _ mhz: Int, byte: Int, bit: Int, dmtID: Int?) -> EDIDMode {
            EDIDMode(width: width, height: height, hTotal: hTotal, vTotal: vTotal, pixelClockHz: mhz * 1_000,
                      interlaced: false, source: .establishedTiming(byte: byte, bit: bit, dmtID: dmtID))
        }
        let expected: [EDIDMode] = [
            mode(720, 400, 900, 449, 28_320, byte: 35, bit: 7, dmtID: nil),     // IBM 720x400@70
            mode(640, 480, 800, 525, 25_175, byte: 35, bit: 5, dmtID: 0x04),
            mode(640, 480, 832, 520, 31_500, byte: 35, bit: 3, dmtID: 0x05),
            mode(640, 480, 840, 500, 31_500, byte: 35, bit: 2, dmtID: 0x06),
            mode(800, 600, 1024, 625, 36_000, byte: 35, bit: 1, dmtID: 0x08),
            mode(800, 600, 1056, 628, 40_000, byte: 35, bit: 0, dmtID: 0x09),
            mode(800, 600, 1040, 666, 50_000, byte: 36, bit: 7, dmtID: 0x0A),
            mode(800, 600, 1056, 625, 49_500, byte: 36, bit: 6, dmtID: 0x0B),
            mode(832, 624, 1152, 667, 57_284, byte: 36, bit: 5, dmtID: nil),     // Apple 832x624@75
            mode(1024, 768, 1344, 806, 65_000, byte: 36, bit: 3, dmtID: 0x10),
            mode(1024, 768, 1328, 806, 75_000, byte: 36, bit: 2, dmtID: 0x11),
            mode(1024, 768, 1312, 800, 78_750, byte: 36, bit: 1, dmtID: 0x12),
            mode(1280, 1024, 1688, 1066, 135_000, byte: 36, bit: 0, dmtID: 0x24),
        ]
        for want in expected {
            #expect(established.contains(want), "missing established timing \(want.sourceDescription)")
        }
    }

    // MARK: Established Timings I & II, byte 36 bit 4: DMT 0x0F is interlaced
    //
    // `edid-decode-bin --dmt 0x0f`:
    //   DMT 0x0f:  1024x768i   86.957532 Hz   4:3     35.522 kHz     44.900000 MHz
    // Thirteen of edid-decode's own EDIDs set this bit (sony-gdmf520-vga among them), and its
    // parse output lists `DMT 1024x768i 86.957532 Hz` for each. The refresh here is the field
    // rate `EDIDMode.refreshHz` reports for an interlaced entry.
    @Test("baseBlock: Established Timings byte 36 bit 4 is DMT 0x0F, interlaced at 86.96 Hz")
    func baseBlockEstablishedTimingDMT0x0FIsInterlaced() throws {
        let bytes = EDIDTestBuilder.withChecksum(EDIDTestBuilder.baseBlock(
            version: (1, 3), establishedBytes: (0x00, 0x10, 0x00)))
        let result = EDIDBaseBlockParser.parse(bytes)
        let mode = try #require(result.modes.first {
            if case .establishedTiming(byte: 36, bit: 4, dmtID: 0x0F) = $0.source { return true }
            return false
        })
        #expect(mode.width == 1024 && mode.height == 768)
        #expect(mode.interlaced == true)
        #expect(mode.hTotal == 1264 && mode.vTotal == 817 && mode.pixelClockHz == 44_900_000)
        #expect(abs(mode.refreshHz - 86.957532) < 0.01)
    }


    // MARK: - No base-block DTD (finding: EDIDInfo returned nil for real Apple and LG EDIDs)
    //
    // Fixtures are edid-decode's own `data/` EDIDs (MIT). Both base blocks carry four display
    // descriptors and no detailed timing; every mode lives in DisplayID Type I records.

    /// `edid-decode-data/apple-xdr-6k-tile1`, 640 bytes: base block (four display descriptors,
    /// no DTD) + CTA-861 + three DisplayID 1.2 blocks. `edid-decode-bin --skip-hex-dump
    /// --skip-sha apple-xdr-6k-tile1`:
    ///   Block 0: Detailed Timing Descriptors: Dummy, Dummy, Dummy, Display Product Name: 'ProDisplayXDR'
    ///   Block 2: Tile location: 1, 0; Tile resolution: 3008x3384
    ///     Video Timing Modes Type 1: DTD:  3008x3384   59.999726 Hz  648.910000 MHz
    ///   Block 3: Video Timing Modes Type 1:
    ///     DTD:  2560x2880   59.999451 Hz  481.270000 MHz
    ///     DTD:  2560x2880   59.939451 Hz  481.110000 MHz
    ///     DTD:  2560x2880   49.999584 Hz  481.190000 MHz
    ///     DTD:  2560x2880   47.999777 Hz  481.240000 MHz
    ///     DTD:  2560x2880   47.951349 Hz  481.140000 MHz
    ///   Block 4: Video Timing Modes Type 1:
    ///     DTD:  3008x3384   59.999726 Hz  648.910000 MHz
    ///     DTD:  3008x3384   59.939337 Hz  648.810000 MHz
    ///     DTD:  3008x3384   49.999830 Hz  648.880000 MHz
    ///     DTD:  3008x3384   47.999781 Hz  648.910000 MHz
    ///     DTD:  3008x3384   47.951701 Hz  648.850000 MHz
    /// The word "preferred" appears on none of those lines: no record sets byte 3 bit 7.
    static let appleXDR6KTile1Hex =
        "00ffffffffffff0006102eae020e0d25011d0104b5462778000f91ae5243b0260f505400000001010101010101010101" +
        "010101010101000000100000000000000000000000000000000000100000000000000000000000000000000000100000" +
        "000000000000000000000000000000fc0050726f446973706c6179584452047402030f80e3058000e6060701a06b0100" +
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "000000000000000000000000000000047012790000290010dfde542f1339444bad7d7071d131bff801000c521b5e0f80" +
        "17380d10784ebb7f8107fa10000401000012001680101000bf0b370d00000000004150502fae020e0d257e00053a0292" +
        "81000300147afd0008bf0b430007801f00370d830075000700000000000000000000000000000000000000000000bf90" +
        "7012790000030064febb0008ff09770007801f003f0b700062000700eebb0008ff09770007801f003f0b720064000700" +
        "f6bb0008ff09770007801f003f0bc602b8020700fbbb0008ff09770007801f003f0b5c034e030700f1bb0008ff097700" +
        "07801f003f0b5f0351030700000000000000000000000000000000000000939070127900000300647afd0008bf0b4300" +
        "07801f00370d83007500070070fd0008bf0b430007801f00370d86007800070077fd0008bf0b430007801f00370d4203" +
        "340307007afd0008bf0b430007801f00370df203e403070074fd0008bf0b430007801f00370df603e803070000000000" +
        "00000000000000000000000000007e90"

    /// `edid-decode-data/lg-ultrafine-5k-v2-thunderbolt-dp2-tile1`, 256 bytes: base block (two
    /// dummy descriptors, serial, name; no DTD) + one DisplayID 1.2 block. `edid-decode-bin`:
    ///   Block 1: Tile location: 1, 0; Tile resolution: 2560x2880; Num horizontal tiles: 2
    ///     Video Timing Modes Type 1: DTD:  2560x2880   59.996475 Hz  483.370000 MHz
    ///       Hfront    8 Hsync  32 Hback  120 (hTotal 2720); Vfront 1 Vsync 8 Vback 73 (vTotal 2962)
    /// No "preferred" on that line.
    static let lgUltraFine5KV2Tile1Hex =
        "00ffffffffffff001e6d745bc33b0500061d0104b53c2278800f91ae5243b0260f505400000001010101010101010101" +
        "010101010101000000100000000000000000000000000000000000100000000000000000000000000000000000ff0039" +
        "30364e54435a41323937390a000000fc004c4720556c74726146696e650a0193701279030001000c3e17160d0014400b" +
        "50784e99290010b4e35e8fdfa04360ba543a6dfeea02d512001680101000ff093f0b000000000047534d745b01010101" +
        "030014d0bc0008ff099f0007801f003f0b51000000070000000000000000000000000000000000000000000000000000" +
        "00000000000000000000000000001e90"

    @Test("EDIDInfo: Apple Pro Display XDR tile 1 (no base DTD) parses to its eleven DisplayID Type I modes")
    func edidInfoAppleXDRTile1ParsesWithoutBaseDTD() throws {
        let bytes = Self.hexBytes(Self.appleXDR6KTile1Hex)
        #expect(bytes.count == 640) // fixture guard
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.monitorName == "ProDisplayXDR")

        let typeI = edid.modes.compactMap { mode -> (Int, Int, Int, Int)? in
            if case .displayID(let block, .typeI, _, false) = mode.source { return (block, mode.width, mode.height, mode.pixelClockHz) }
            return nil
        }
        let expected: [(Int, Int, Int, Int)] = [
            (2, 3008, 3384, 648_910_000),
            (3, 2560, 2880, 481_270_000), (3, 2560, 2880, 481_110_000), (3, 2560, 2880, 481_190_000),
            (3, 2560, 2880, 481_240_000), (3, 2560, 2880, 481_140_000),
            (4, 3008, 3384, 648_910_000), (4, 3008, 3384, 648_810_000), (4, 3008, 3384, 648_880_000),
            (4, 3008, 3384, 648_910_000), (4, 3008, 3384, 648_850_000),
        ]
        #expect(typeI.count == expected.count)
        for (got, want) in zip(typeI, expected) {
            #expect(got == want, "expected \(want), got \(got)")
        }
        // Refresh to 0.001 Hz on the first and last line.
        let first = try #require(edid.modes.first { if case .displayID(2, .typeI, 0, false) = $0.source { return true }; return false })
        #expect(abs(first.refreshHz - 59.999726) < 0.001)
        let last = try #require(edid.modes.first { if case .displayID(4, .typeI, 4, false) = $0.source { return true }; return false })
        #expect(abs(last.refreshHz - 47.951701) < 0.001)

        // No base DTD and no record flagged preferred: the EDID declares no preferred mode.
        #expect(edid.preferredMode == nil)
        #expect(edid.preferredWidth == nil)
        #expect(edid.topMode != nil)
    }

    @Test("EDIDInfo: LG UltraFine 5K tile 1 (no base DTD) parses to its Type I entry and composite")
    func edidInfoLGUltraFineTile1ParsesWithoutBaseDTD() throws {
        let bytes = Self.hexBytes(Self.lgUltraFine5KV2Tile1Hex)
        #expect(bytes.count == 256) // fixture guard
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.monitorName == "LG UltraFine")
        #expect(edid.modes.contains(EDIDMode(
            width: 2560, height: 2880, hTotal: 2720, vTotal: 2962, pixelClockHz: 483_370_000,
            interlaced: false, source: .displayID(block: 1, type: .typeI, index: 0, embeddedInCTA: false))))
        #expect(edid.preferredMode == nil)
        let composite = try #require(edid.modes.first { if case .tiledComposite = $0.source { return true }; return false })
        #expect(composite.width == 5120 && composite.height == 2880 && composite.pixelClockHz == 966_740_000)
        #expect(edid.topMode == composite)
    }

    // Synthetic EDID 1.3 base block: Established Timings byte 35 bit 5 and standard timing
    // `d1 c0`, no DTD. `edid-decode-bin --skip-hex-dump --skip-sha <synth-c.hex>`:
    //   Established Timings I & II:
    //     DMT 0x04:   640x480    59.940476 Hz   4:3     31.469 kHz     25.175000 MHz
    //   Standard Timings:
    //     DMT 0x52:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz
    @Test("EDIDInfo: an EDID 1.3 base block with only established and standard timings parses, with no preferred mode")
    func edidInfoNoDTDEstablishedAndStandardOnly() throws {
        let bytes = EDIDTestBuilder.withChecksum(EDIDTestBuilder.baseBlock(
            version: (1, 3), establishedBytes: (0x20, 0x00, 0x00), standardTimings: [(0xD1, 0xC0)]))
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.preferredMode == nil)
        #expect(edid.modes.count == 2)
        let top = try #require(edid.topMode)
        #expect(top.width == 1920 && top.height == 1080 && top.pixelClockHz == 148_500_000)
        if case .standardTiming(index: 0, derivation: .dmt, dmtID: 0x52) = top.source {} else {
            Issue.record("expected the DMT 0x52 standard timing as the top mode, got \(top.sourceDescription)")
        }
    }

    // Synthetic EDID 1.4 base block with no DTD + a DisplayID 1.2 block carrying one Type I
    // record (the LG tile record above with byte 3 bit 7 set: `d0 bc 00 88 ...`).
    // `edid-decode-bin --skip-hex-dump --skip-sha <synth-d.hex>`, data block revision 0:
    //   DTD:  2560x2880   59.996475 Hz   0:0    177.710 kHz    483.370000 MHz (aspect undefined, no 3D stereo, preferred)
    // The same record under data block revision 2 (`<synth-d2.hex>`): the bit means YCbCr 4:2:0
    // there, and edid-decode prints no "preferred" (`parse_displayid_type_1_7_timing`:
    // `if (block_rev < 2 && (x[3] & 0x80))`):
    //   DTD:  2560x2880   59.996475 Hz   0:0    177.710 kHz    483.370000 MHz (aspect undefined, no 3D stereo, YCbCr 4:2:0)
    @Test("EDIDInfo: with no base DTD, a DisplayID Type I record flagged preferred (block revision < 2) is the preferred mode")
    func edidInfoPreferredModeFromDisplayIDTypeIFlag() throws {
        let record = Self.hexBytes("d0bc0088ff099f0007801f003f0b510000000700")
        var base = EDIDTestBuilder.baseBlock(version: (1, 4))
        base[126] = 1
        base = EDIDTestBuilder.withChecksum(base)
        let want = EDIDMode(
            width: 2560, height: 2880, hTotal: 2720, vTotal: 2962, pixelClockHz: 483_370_000,
            interlaced: false, source: .displayID(block: 1, type: .typeI, index: 0, embeddedInCTA: false))

        let flagged = base + EDIDTestBuilder.displayIDBlock(version: 0x12, dataBlocks: [(tag: 0x03, revision: 0x00, payload: record)])
        let edid = try #require(EDIDInfo(Data(flagged)))
        #expect(edid.modes == [want])
        #expect(edid.preferredMode == want)
        #expect(edid.preferredWidth == 2560 && edid.preferredHeight == 2880)

        let revision2 = base + EDIDTestBuilder.displayIDBlock(version: 0x12, dataBlocks: [(tag: 0x03, revision: 0x02, payload: record)])
        let edid2 = try #require(EDIDInfo(Data(revision2)))
        #expect(edid2.modes == [want])
        #expect(edid2.preferredMode == nil)
    }

    // MARK: G34w Standard Timings
    //
    // `edid-decode-bin --skip-hex-dump --skip-sha <g34w.hex>`:
    //   Standard Timings:
    //     DMT 0x55:  1280x720    60.000000 Hz  16:9     45.000 kHz     74.250000 MHz
    //     DMT 0x23:  1280x1024   60.019740 Hz   5:4     63.981 kHz    108.000000 MHz
    //     DMT 0x2f:  1440x900    59.887445 Hz  16:10    55.935 kHz    106.500000 MHz
    //     DMT 0x53:  1600x900    60.000000 Hz  16:9     60.000 kHz    108.000000 MHz (RB)
    //     DMT 0x3a:  1680x1050   59.954250 Hz  16:10    65.290 kHz    146.250000 MHz
    //     DMT 0x52:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz
    //     DMT 0x15:  1152x864    75.000000 Hz   4:3     67.500 kHz    108.000000 MHz
    //     GTF     :  1280x1024   69.999805 Hz   5:4     74.620 kHz    128.943000 MHz
    // The last one (bytes `81 8a`) is not a DMT match (edid-decode prints "GTF", not "DMT 0x..");
    // G34w is EDID 1.3 with a default-GTF 0xFD descriptor, so it decodes via GTF. Its totals are
    // from `edid-decode-bin --gtf w=1280,h=1024,fps=70`: Hfront 88 Hsync 136 Hback 224 (hTotal
    // 1728), Vfront 1 Vsync 3 Vback 38 (vTotal 1066), 128.943000 MHz. (The byte pair decodes to
    // aspect 5:4 / 1280x1024, not the 16:10 1280x800 the dispatch's plain-English gloss named:
    // byte2 = 0x8a's top 2 bits are 0b10, the 5:4 case, per both `--std 0x81,0x8a` and
    // `print_standard_timing`'s own switch. edid-decode's code is the byte-layout authority, and
    // its own numbers already checked out perfectly against the hand-decode, so its output is
    // trusted over the prose that introduced the discrepancy.)
    @Test("baseBlock: G34w Standard Timings decode to the DMT modes edid-decode lists, plus one GTF")
    func baseBlockG34wStandardTimings() throws {
        let edid = try #require(EDIDInfo(Data(Self.g34wBaseBlock)))

        func dmtMode(_ index: Int, _ width: Int, _ height: Int, _ hTotal: Int, _ vTotal: Int, _ khz: Int, dmtID: Int) -> EDIDMode {
            EDIDMode(width: width, height: height, hTotal: hTotal, vTotal: vTotal, pixelClockHz: khz * 1_000,
                      interlaced: false, source: .standardTiming(index: index, derivation: .dmt, dmtID: dmtID))
        }
        let expected: [EDIDMode] = [
            dmtMode(0, 1280, 720, 1650, 750, 74_250, dmtID: 0x55),
            dmtMode(1, 1280, 1024, 1688, 1066, 108_000, dmtID: 0x23),
            dmtMode(2, 1440, 900, 1904, 934, 106_500, dmtID: 0x2F),
            dmtMode(3, 1600, 900, 1800, 1000, 108_000, dmtID: 0x53),
            dmtMode(4, 1680, 1050, 2240, 1089, 146_250, dmtID: 0x3A),
            dmtMode(5, 1920, 1080, 2200, 1125, 148_500, dmtID: 0x52),
            dmtMode(6, 1152, 864, 1600, 900, 108_000, dmtID: 0x15),
            EDIDMode(width: 1280, height: 1024, hTotal: 1728, vTotal: 1066, pixelClockHz: 128_943_000,
                      interlaced: false, source: .standardTiming(index: 7, derivation: .gtf, dmtID: nil)),
        ]
        for want in expected {
            #expect(edid.modes.contains(want), "missing standard timing \(want.sourceDescription)")
        }
    }

    /// The base block of one of the two `m4max_macos26.5.1_e` panels whose 0xFD descriptor byte
    /// 10 is 0xFF, an unrecognised timing-support class. Captured live from
    /// `research/customer-probes/m4max_macos26.5.1_e/33_displayport_capability.json`
    /// (`Metadata.EDID`, serial-redacted, first active DisplayPort node). First 128 bytes only;
    /// the standard-timing slot (bytes 38-53) carries one DMT match (`d1 c0`) and seven unused
    /// (`01 01`) slots, so there is nothing non-DMT for `undecodedStandardTimings` to hold here.
    static let m4maxEBaseBlockHex =
        "00ffffffffffff00061434120000000020210104b5220a7802ef65a656529d280b5054210800d1c00101010101010101" +
        "0101010101019e3e80c870b03c40582c45002dbc1000001e000000ff0000000000000000000000000000000000fc004d" +
        "4e4e0a202020202020202020000000fd002f4b185413ff0a2020202020200114"

    // `edid-decode-bin --skip-hex-dump --skip-sha <m4max_e.hex>`:
    //   Display Range Limits:
    //     Monitor ranges (Unknown (0xff)): 47-75 Hz V, 24-84 kHz H, max dotclock 190 MHz
    //   Standard Timings:
    //     DMT 0x52:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz
    @Test("baseBlock: an unrecognised 0xFD timing-support byte (0xFF) parses as .unknown, corpus fixture")
    func baseBlockUnknownRangeLimitsFromCorpus() throws {
        let bytes = Self.hexBytes(Self.m4maxEBaseBlockHex)
        #expect(bytes.count == 128)
        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.rangeLimits?.timingSupport == .unknown(0xFF))
        #expect(edid.rangeLimits?.minVerticalHz == 47)
        #expect(edid.rangeLimits?.maxVerticalHz == 75)
        #expect(edid.rangeLimits?.minHorizontalKHz == 24)
        #expect(edid.rangeLimits?.maxHorizontalKHz == 84)
        #expect(edid.rangeLimits?.maxPixelClockHz == 190_000_000)
        // The only standard timing present (`d1 c0`) is DMT 0x52; nothing is left undecoded.
        #expect(edid.undecodedStandardTimings.isEmpty)
    }

    // MARK: Synthetic EDID 1.4: 0xF7 Established Timings III, 0xF8 CVT codes, 0xFA Standard Timings
    //
    // Built with EDIDTestBuilder: version 1.4, no DTD; read through EDIDBaseBlockParser.parse
    // directly, the layer under test here.
    // 0xF7 descriptor bytes 6-11 set the bits for DMT 0x16 (index 8 of
    // EDIDEstablishedTimings.iiiDMTIDs -> byte 7 bit 7), DMT 0x23 (index 14 -> byte 7 bit 1) and
    // DMT 0x44 (index 38 -> byte 10 bit 1): bytes = [0x00, 0x82, 0x00, 0x00, 0x02, 0x00].
    // 0xF8 descriptor carries one code (0x1B, 0x24, 0x1F) at bytes 6-8, the other three codes
    // all-zero (absent). 0xFA descriptor carries `d1 c0` (DMT 0x52) then five `01 01` (unused).
    //
    // `edid-decode-bin --skip-hex-dump --skip-sha <synth1.hex>`:
    //   Detailed Timing Descriptors:
    //     Established timings III:
    //       DMT 0x16:  1280x768    59.994726 Hz   5:3     47.396 kHz     68.250000 MHz (RB)
    //       DMT 0x23:  1280x1024   60.019740 Hz   5:4     63.981 kHz    108.000000 MHz
    //       DMT 0x44:  1920x1200   59.950171 Hz  16:10    74.038 kHz    154.000000 MHz (RB)
    //     CVT 3 Byte Timing Codes:
    //       CVT:  1920x1080   49.929146 Hz  16:9     55.621 kHz    141.500000 MHz (preferred vertical rate)
    //       CVT:  1920x1080   59.962844 Hz  16:9     67.158 kHz    173.000000 MHz
    //       CVT:  1920x1080   74.905668 Hz  16:9     84.643 kHz    220.750000 MHz
    //       CVT:  1920x1080   84.883867 Hz  16:9     96.513 kHz    253.250000 MHz
    //       CVT:  1920x1080   59.933878 Hz  16:9     66.587 kHz    138.500000 MHz (RB)
    //     Standard Timing Identifications:
    //       DMT 0x52:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz
    // Totals for the five CVT modes are each from the matching `edid-decode-bin --cvt
    // w=1920,h=1080,fps=<N>[,rb=1]` (Hfront/Hsync/Hback and Vfront/Vsync/Vback summed):
    //   50 Hz:  hTotal 1920+112+200+312=2544, vTotal 1080+3+5+26=1114, 141_500 kHz
    //   60 Hz:  hTotal 1920+128+200+328=2576, vTotal 1080+3+5+32=1120, 173_000 kHz
    //   75 Hz:  hTotal 1920+136+208+344=2608, vTotal 1080+3+5+42=1130, 220_750 kHz
    //   85 Hz:  hTotal 1920+144+208+352=2624, vTotal 1080+3+5+49=1137, 253_250 kHz
    //   60 Hz RB: hTotal 1920+48+32+80=2080, vTotal 1080+3+5+23=1111, 138_500 kHz
    @Test("baseBlock: synthetic 0xF7/0xF8/0xFA descriptors decode to the modes edid-decode lists")
    func baseBlockSyntheticEstablishedIIICVTAndFAStandardTimings() {
        let f7 = EDIDTestBuilder.descriptor(tag: 0xF7, payload: [0x00, 0x01, 0x00, 0x82, 0x00, 0x00, 0x02, 0x00, 0, 0, 0, 0, 0, 0])
        let f8 = EDIDTestBuilder.descriptor(tag: 0xF8, payload: [0x00, 0x01, 0x1B, 0x24, 0x1F, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let fa = EDIDTestBuilder.descriptor(tag: 0xFA, payload: [0x00, 0xD1, 0xC0, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00])
        let bytes = EDIDTestBuilder.withChecksum(EDIDTestBuilder.baseBlock(version: (1, 4), descriptors: [f7, f8, fa]))

        let result = EDIDBaseBlockParser.parse(bytes)

        // Established Timings III.
        func est3(_ width: Int, _ height: Int, _ hTotal: Int, _ vTotal: Int, _ khz: Int, dmtID: Int, descByte: Int, bit: Int) -> EDIDMode {
            EDIDMode(width: width, height: height, hTotal: hTotal, vTotal: vTotal, pixelClockHz: khz * 1_000,
                      interlaced: false, source: .establishedTiming(byte: 1000 + descByte, bit: bit, dmtID: dmtID))
        }
        #expect(result.modes.contains(est3(1280, 768, 1440, 790, 68_250, dmtID: 0x16, descByte: 7, bit: 7)))
        #expect(result.modes.contains(est3(1280, 1024, 1688, 1066, 108_000, dmtID: 0x23, descByte: 7, bit: 1)))
        #expect(result.modes.contains(est3(1920, 1200, 2080, 1235, 154_000, dmtID: 0x44, descByte: 10, bit: 1)))

        // CVT 3-byte codes: block 0, index 0 (the descriptor's first and only code).
        func cvt(_ hTotal: Int, _ vTotal: Int, _ khz: Int, refreshHz: Int, rb: Bool) -> EDIDMode {
            EDIDMode(width: 1920, height: 1080, hTotal: hTotal, vTotal: vTotal, pixelClockHz: khz * 1_000,
                      interlaced: false, source: .cvtCode(block: 0, index: 0, refreshHz: refreshHz, reducedBlanking: rb))
        }
        #expect(result.modes.contains(cvt(2544, 1114, 141_500, refreshHz: 50, rb: false)))
        #expect(result.modes.contains(cvt(2576, 1120, 173_000, refreshHz: 60, rb: false)))
        #expect(result.modes.contains(cvt(2608, 1130, 220_750, refreshHz: 75, rb: false)))
        #expect(result.modes.contains(cvt(2624, 1137, 253_250, refreshHz: 85, rb: false)))
        #expect(result.modes.contains(cvt(2080, 1111, 138_500, refreshHz: 60, rb: true)))

        // 0xFA Standard Timing Identifications: index 8 is the descriptor's first slot.
        #expect(result.modes.contains(EDIDMode(
            width: 1920, height: 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 148_500_000,
            interlaced: false, source: .standardTiming(index: 8, derivation: .dmt, dmtID: 0x52))))
    }

    // MARK: Synthetic EDID 1.4: CVT range-limits descriptor drives a non-DMT standard timing
    //
    // 0xFD descriptor: byte 10 = 0x04 (CVT), byte 11 = 0x11 (version "1.1"), byte 12 = 0x00 (no
    // pixel-clock adjustment, no max-active-pixels high bits), byte 13 = 0x00 (no max-active-pixels),
    // byte 15 = 0x18 (both standard and reduced blanking supported), byte 17 = 60 (preferred
    // refresh). Standard timing slot 0 = `81 0a`: not a DMT match (edid-decode prints "CVT"/"GTF",
    // not "DMT 0x.."); hact=(0x81+31)*8=1280, aspect 16:10 (byte2 top bits 00, EDID>=1.3),
    // vact=800, refresh=(0x0a&0x3f)+60=70.
    //
    // `edid-decode-bin --std 0x81,0x0a` (edid-minor-independent form; same numbers the full parse
    // would print for this block, since the standard-timing byte decode itself doesn't depend on
    // EDID minor beyond the aspect-ratio default, which is already >= 1.3 either way):
    //   CVT     :  1280x800    69.823734 Hz  16:10    58.373 kHz     99.000000 MHz
    //   GTF     :  1280x800    70.000170 Hz  16:10    58.310 kHz     98.894000 MHz
    // Our derivation rule (task4 dispatch, byte semantics item 2) always uses CVT for a minor>=4
    // EDID whose range-limits descriptor is .cvt, regardless of edid-decode's own full-EDID-parse
    // output for this exact block (which prints only the GTF line here: edid-decode's
    // `preparse_detailed_block` sets `base.supports_cvt` before `base.edid_minor` itself is set,
    // so on a from-scratch parse the CVT branch of `print_standard_timing` never fires for EDID
    // 1.4; this is edid-decode's own preparse-ordering quirk, not a byte-layout fact, so the
    // dispatch's rule -- "the pixel clock edid-decode prints on its CVT line" -- points at the
    // standalone `--std`/`--cvt` tool output, not the full-parse "Standard Timings" section).
    // Totals via `edid-decode-bin --cvt w=1280,h=800,fps=70`: Hfront 80 Hsync 128 Hback 208
    // (hTotal 1696), Vfront 3 Vsync 6 Vback 27 (vTotal 836), 99.000000 MHz.
    @Test("baseBlock: a CVT range-limits descriptor drives a non-DMT standard timing via CVT standard blanking")
    func baseBlockSyntheticCVTRangeLimitsStandardTiming() {
        let fd = EDIDTestBuilder.descriptor(tag: 0xFD, payload: [
            0x00,       // byte 4: offset flags (EDID 1.4, unused here)
            40, 90,     // bytes 5-6: min/max vertical Hz
            20, 100,    // bytes 7-8: min/max horizontal kHz
            20,         // byte 9: max pixel clock, 20 * 10 MHz = 200 MHz
            0x04,       // byte 10: CVT
            0x11,       // byte 11: version 1.1
            0x00, 0x00, // bytes 12-13: no pixel-clock adjustment, no max-active-pixels
            0x00,       // byte 14: aspect bits (not modelled)
            0x18,       // byte 15: standard + reduced blanking supported
            0x00,       // byte 16: no scaling
            60,         // byte 17: preferred refresh 60 Hz
        ])
        let bytes = EDIDTestBuilder.withChecksum(EDIDTestBuilder.baseBlock(
            version: (1, 4), standardTimings: [(0x81, 0x0A)], descriptors: [fd]))

        let result = EDIDBaseBlockParser.parse(bytes)
        #expect(result.rangeLimits?.timingSupport == .cvt(
            version: "1.1", maxActivePixelsPerLine: nil, standardBlanking: true, reducedBlanking: true,
            preferredRefreshHz: 60, realMaxPixelClockHz: nil))
        #expect(result.modes.contains(EDIDMode(
            width: 1280, height: 800, hTotal: 1696, vTotal: 836, pixelClockHz: 99_000_000,
            interlaced: false, source: .standardTiming(index: 0, derivation: .cvt, dmtID: nil))))
    }

    // MARK: Synthetic EDID 1.3: secondary-GTF range-limits descriptor
    //
    // 0xFD descriptor bytes copied verbatim from `edid-decode-test/vesa-edid-1.3.test` (offset
    // 108 there: `00 00 00 fd 00 30 a0 1e 79 1c 02 00 28 50 10 0e 80 46`), whose standard timing
    // `c2 8f` is 1800x1440@75 (hact=(0xc2+31)*8=1800, aspect 5:4 since byte2 top bits 10, vact=1440,
    // refresh=(0x8f&0x3f)+60=75), reused here as slot 0.
    //
    // `edid-decode-bin --skip-hex-dump --skip-sha <vesa-edid-1.3.test>`:
    //   Standard Timings:
    //     GTF     :  1800x1440   74.999946 Hz   5:4    112.725 kHz    278.656000 MHz
    //   Display Range Limits:
    //     Monitor ranges (Secondary GTF): 48-160 Hz V, 30-121 kHz H, max dotclock 280 MHz
    //     GTF Secondary Curve Block:
    //       Start frequency: 80 kHz
    //       C: 40.0%  M: 3600%/kHz  K: 128  J: 35.0%
    // The 278.656 MHz line above is edid-decode's own PARSE-mode output, which only ever
    // prints the default curve, measured against the binary directly; the orchestrator ruling
    // applies the secondary curve whenever a standard timing's
    // default-curve horizontal frequency is at or above the start frequency, which the 112.725 kHz
    // above already is (>= 80 kHz). The expected number instead comes from
    // `edid-decode-bin --gtf w=1800,h=1440,fps=75,secondary,C=40,M=3600,K=128,J=35`:
    //   GTF:  1800x1440   75.000116 Hz   5:4    112.725 kHz    258.817000 MHz (RB)
    //          Hfront   64 Hsync 184 Hback  248 (hTotal 2296)
    //          Vfront    1 Vsync   3 Vback   59 (vTotal 1503)
    @Test("baseBlock: a secondary-GTF descriptor is applied above its start frequency (.gtfSecondary)")
    func baseBlockSyntheticSecondaryGTFStandardTiming() {
        let fd = EDIDTestBuilder.descriptor(tag: 0xFD, payload: [
            0x00, 0x30, 0xA0, 0x1E, 0x79, 0x1C, 0x02, 0x00, 0x28, 0x50, 0x10, 0x0E, 0x80, 0x46,
        ])
        let bytes = EDIDTestBuilder.withChecksum(EDIDTestBuilder.baseBlock(
            version: (1, 3), standardTimings: [(0xC2, 0x8F)], descriptors: [fd]))

        let result = EDIDBaseBlockParser.parse(bytes)
        #expect(result.rangeLimits?.timingSupport == .secondaryGTF(startFrequencyKHz: 80, c: 40.0, m: 3600, k: 128, j: 35.0))
        #expect(result.modes.contains(EDIDMode(
            width: 1800, height: 1440, hTotal: 2296, vTotal: 1503, pixelClockHz: 258_817_000,
            interlaced: false, source: .standardTiming(index: 0, derivation: .gtfSecondary, dmtID: nil))))
    }

    // MARK: Synthetic secondary-GTF descriptor with a degenerate curve (K = 0, J = 100%)
    //
    // 0xFD with byte 10 = 0x02, start frequency 0 (byte 12), C = 40% (byte 13 = 80),
    // M = 600 (bytes 14-15), K = 0 (byte 16), J = 100% (byte 17 = 200). The curve is not
    // all-zero, so it is a declared curve; the arithmetic gives C' = 100 and an ideal duty
    // cycle of 100%, so the horizontal blanking is infinite. The standard timing `c2 8f`
    // (1800x1440@75, not in DMT) has no finite timing under that curve. edid-decode prints the
    // default curve on its parse path and never evaluates this one, so there is no oracle
    // line: the fact the EDID declares is a standard timing the licensed formula cannot
    // compute, which is `undecodedStandardTimings`. The DTD (VIC 5's bytes) keeps the block a
    // whole EDID.
    @Test("EDIDInfo: a secondary GTF curve that yields no finite timing leaves the standard timing undecoded")
    func edidInfoDegenerateSecondaryGTFCurveDoesNotTrap() throws {
        let fd = EDIDTestBuilder.descriptor(tag: 0xFD, payload: [
            0x00, 0x30, 0xA0, 0x1E, 0x79, 0x1C,
            0x02,       // byte 10: secondary GTF
            0x00,       // byte 11
            0x00,       // byte 12: start frequency 0 kHz
            80,         // byte 13: C = 40.0%
            0x58, 0x02, // bytes 14-15: M = 600
            0,          // byte 16: K = 0
            200,        // byte 17: J = 100.0%
        ])
        let dtd: [UInt8] = [0x01, 0x1D, 0x80, 0x18, 0x71, 0x1C, 0x16, 0x20, 0x58, 0x2C, 0x25, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9E]
        let bytes = EDIDTestBuilder.withChecksum(EDIDTestBuilder.baseBlock(
            version: (1, 3), standardTimings: [(0xC2, 0x8F)], descriptors: [dtd, fd]))

        let info = try #require(EDIDInfo(Data(bytes)))
        #expect(info.rangeLimits?.timingSupport == .secondaryGTF(startFrequencyKHz: 0, c: 40.0, m: 600, k: 0, j: 100.0))
        #expect(info.undecodedStandardTimings == [EDIDInfo.StandardTimingID(width: 1800, height: 1440, refreshHz: 75, sourceIndex: 0)])
        #expect(!info.modes.contains { $0.width == 1800 && $0.height == 1440 })
    }

    // MARK: Synthetic secondary-GTF descriptor whose curve block is all zero
    //
    // 0xFD with byte 10 = 0x02 and bytes 12-17 all zero. edid-decode's `preparse_detailed_block`
    // sets `supports_sec_gtf = !memchk(x + 12, 6)`, so an all-zero curve block is no curve at
    // all (its parse path prints "Zeroed Secondary Curve Block" as a failure) and the default
    // GTF curve is what the EDID licenses. Standard timing `d1 f0`: hact = (0xd1 + 31) * 8 =
    // 1920, aspect 16:9 (top bits 11) so vact = 1080, refresh = (0xf0 & 0x3f) + 60 = 108.
    // `edid-decode-bin --gtf w=1920,h=1080,fps=108`:
    //   GTF:  1920x1080  107.999885 Hz  16:9    124.092 kHz    329.588000 MHz
    //              Hfront  152 Hsync 216 Hback  368 (hTotal 2656)
    //              Vfront    1 Vsync   3 Vback   65 (vTotal 1149)
    @Test("baseBlock: an all-zero secondary GTF curve block is the default curve, not C = 0 / M = 0")
    func baseBlockSyntheticZeroedSecondaryGTFCurveUsesDefaultCurve() {
        let fd = EDIDTestBuilder.descriptor(tag: 0xFD, payload: [
            0x00, 0x30, 0xA0, 0x1E, 0x79, 0x1C, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ])
        let bytes = EDIDTestBuilder.withChecksum(EDIDTestBuilder.baseBlock(
            version: (1, 3), standardTimings: [(0xD1, 0xF0)], descriptors: [fd]))

        let result = EDIDBaseBlockParser.parse(bytes)
        #expect(result.rangeLimits?.timingSupport == .defaultGTF)
        #expect(result.modes.contains(EDIDMode(
            width: 1920, height: 1080, hTotal: 2656, vTotal: 1149, pixelClockHz: 329_588_000,
            interlaced: false, source: .standardTiming(index: 0, derivation: .gtf, dmtID: nil))))
    }

    // MARK: Synthetic interlaced DTD (VIC 5's numbers)
    //
    // DTD bytes built from VIC 5's own porches (`edid-decode-bin --vic 5`):
    //   VIC   5:  1920x1080i  60.000000 Hz  16:9     33.750 kHz     74.250000 MHz
    //                Hfront   88 Hsync  44 Hback  148 (hBlank 280, matching hact 1920 + hblank
    //                                                   280 = hTotal 2200)
    //                Vfront    2 Vsync   5 Vback   15 (vBlank/field 22), flags 0x80 (interlaced)
    //                                                  | 0x1E (digital separate, +hsync +vsync)
    // Placed as the sole DTD (descriptor slot 0) in a synthetic base block.
    // `edid-decode-bin --skip-hex-dump --skip-sha <synth3.hex>`:
    //   DTD 1:  1920x1080i  60.000000 Hz  16:9     33.750 kHz     74.250000 MHz
    @Test("baseBlock: an interlaced DTD reports the field rate, per VIC 5's own numbers")
    func baseBlockSyntheticInterlacedDTD() {
        let dtd: [UInt8] = [0x01, 0x1D, 0x80, 0x18, 0x71, 0x1C, 0x16, 0x20, 0x58, 0x2C, 0x25, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x9E]
        let bytes = EDIDTestBuilder.withChecksum(EDIDTestBuilder.baseBlock(version: (1, 4), descriptors: [dtd]))

        let mode = try? #require(EDIDBaseBlockParser.detailedTiming(bytes, at: 54, block: 0, index: 0))
        #expect(mode?.width == 1920)
        #expect(mode?.height == 1080)
        #expect(mode?.hTotal == 2200)
        #expect(mode?.vTotal == 1125)
        #expect(mode?.interlaced == true)
        #expect(mode?.pixelClockHz == 74_250_000)
        #expect(mode.flatMap { abs($0.refreshHz - 60.0) < 0.01 } ?? false)
    }

    // MARK: - CTA-861 extension: full parse
    //
    // EDIDCTAParser makes the CTA-861 extension block yield every VIC (Video Data Block and the
    // YCbCr 4:2:0 Video Data Block), the Video Format Preference block, the DisplayID VTDBs
    // CTA-861 can carry (Types VII, VIII, X), and the trailing DTDs. Every expected value below
    // is transcribed from a real `edid-decode-bin` run; the exact command is in each test's
    // comment. Tests call `EDIDCTAParser.parse` directly (the pattern the `baseBlock:`
    // tests already use for `EDIDBaseBlockParser.parse`) except where the point is the full
    // `EDIDInfo(Data:)` round trip through a real EDID.

    /// The G34w-10's own CTA-861 extension (`g34wExtensionHex`, above) is the one real,
    /// currently-committed fixture that actually carries a CTA-861 block (the "LG UltraFine"
    /// fixture's two extensions are both DisplayID, tag 0x70, not CTA; see report section 5).
    /// `edid-decode-bin --skip-hex-dump --skip-sha` on `g34wBaseBlock + g34wExtensionHex`:
    ///
    ///   Block 1, CTA-861 Extension Block:
    ///     Video Data Block:
    ///       VIC   1:   640x480    59.940476 Hz   4:3     31.469 kHz     25.175000 MHz
    ///       VIC   2:   720x480    59.940060 Hz   4:3     31.469 kHz     27.000000 MHz
    ///       VIC   3:   720x480    59.940060 Hz  16:9     31.469 kHz     27.000000 MHz
    ///       VIC   4:  1280x720    60.000000 Hz  16:9     45.000 kHz     74.250000 MHz
    ///       VIC   5:  1920x1080i  60.000000 Hz  16:9     33.750 kHz     74.250000 MHz
    ///       VIC  16:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz (native)
    ///       VIC  18:   720x576    50.000000 Hz  16:9     31.250 kHz     27.000000 MHz
    ///       VIC  19:  1280x720    50.000000 Hz  16:9     37.500 kHz     74.250000 MHz
    ///       VIC  20:  1920x1080i  50.000000 Hz  16:9     28.125 kHz     74.250000 MHz
    ///       VIC  31:  1920x1080   50.000000 Hz  16:9     56.250 kHz    148.500000 MHz
    ///       VIC  78:  1920x1080  120.000000 Hz  64:27   135.000 kHz    297.000000 MHz
    ///     Detailed Timing Descriptors:
    ///       DTD 2:  3440x1440  100.000000 Hz  43:18   148.100 kHz    533.160000 MHz
    ///       DTD 3:  1366x768    59.789541 Hz 683:384   47.712 kHz     85.500000 MHz
    ///       DTD 4:  2560x1440   60.000199 Hz  16:9     88.860 kHz    241.700000 MHz
    ///       DTD 5:  3440x1440   50.000000 Hz  43:18    74.050 kHz    266.580000 MHz
    @Test("cta: G34w-10's real CTA-861 block yields all eleven VICs (VIC 16 native) and its four DTDs")
    func ctaG34wVICsAndDTDs() throws {
        let bytes = Self.g34wBaseBlock + Self.hexBytes(Self.g34wExtensionHex)
        let edid = try #require(EDIDInfo(Data(bytes)))

        let vics = edid.modes.compactMap { mode -> (Int, Bool)? in
            if case .ctaVIC(let block, let vic, let native, false) = mode.source, block == 1 { return (vic, native) }
            return nil
        }
        #expect(vics.count == 11)
        #expect(Set(vics.map(\.0)) == Set([1, 2, 3, 4, 5, 16, 18, 19, 20, 31, 78]))
        #expect(vics.filter(\.1).map(\.0) == [16]) // VIC 16 is the only native entry

        let vic16 = try #require(edid.modes.first {
            if case .ctaVIC(1, 16, true, false) = $0.source { return true }
            return false
        })
        #expect(vic16.width == 1920); #expect(vic16.height == 1080); #expect(vic16.pixelClockHz == 148_500_000)

        func ctaDTD(_ index: Int) -> EDIDMode? {
            edid.modes.first {
                if case .detailedTiming(let block, let i) = $0.source { return block == 1 && i == index }
                return false
            }
        }
        #expect(ctaDTD(0)?.pixelClockHz == 533_160_000) // DTD 2
        #expect(ctaDTD(1)?.pixelClockHz == 85_500_000)  // DTD 3
        #expect(ctaDTD(2)?.pixelClockHz == 241_700_000) // DTD 4
        #expect(ctaDTD(3)?.pixelClockHz == 266_580_000) // DTD 5
    }

    /// edid-decode's own `test/cta-timings.test` (v4l-utils, MIT licence, same pinned commit as
    /// every other fixture in this file): base block, a Block Map extension, and two CTA-861
    /// extensions (edid-decode's "Block 2" and "Block 3", which land at extension index 1 and 2
    /// here, i.e. `block: 2` and `block: 3`). Block 2 carries a 17-entry Video Data Block, a
    /// YCbCr 4:2:0 Video Data Block, a Video Format Preference block, and one each of the
    /// DisplayID Type VII, VIII and X VTDBs. `edid-decode-bin --skip-hex-dump --skip-sha
    /// cta-timings.test`:
    ///
    ///   Block 2, CTA-861 Extension Block:
    ///     Video Data Block:
    ///       VIC  97:  3840x2160   60.000000 Hz  16:9    135.000 kHz    594.000000 MHz
    ///       (plus VIC 96, 95, 94, 93, 16, 31, 4, 19, 34, 33, 32, 5, 20, 2, 17, 1: 17 total, none native)
    ///     YCbCr 4:2:0 Video Data Block:
    ///       VIC 114:  3840x2160   48.000000 Hz  16:9    108.000 kHz    594.000000 MHz
    ///     Video Format Preference Data Block:
    ///       VIC  97, VIC 114, DTD 1, DTD 3, DMT 0x48 (T8VTDB), VTDB 1, VTDB 2, RID 7@60p
    ///     DisplayID Type VII Video Timing Data Block:
    ///       VTDB 1:  5120x2160   60.000000 Hz   1:1    133.320 kHz    693.264000 MHz
    ///     DisplayID Type VIII Video Timing Data Block:
    ///       DMT 0x48:  1920x1200  119.908612 Hz  16:10   152.404 kHz    317.000000 MHz (RB)
    ///     DisplayID Type X Video Timing Data Block:
    ///       VTDB 2:  5120x1440   50.000000 Hz  32:9     73.700 kHz    383.240000 MHz (RBv3)
    ///     Detailed Timing Descriptors:
    ///       DTD 2:  3840x2160   59.996625 Hz  16:9    133.312 kHz    533.250000 MHz
    ///   Block 3, CTA-861 Extension Block:
    ///     Detailed Timing Descriptors:
    ///       DTD 3:  1280x720    59.855126 Hz  16:9     44.772 kHz     74.500000 MHz
    ///
    /// The Video Format Preference block's raw bytes were independently re-derived by walking
    /// the CTA data block header format by hand (`e1 46` at block-relative offset 3: extended tag
    /// 0x0D, payload `91 61 72 81 83 fe 92 a6`), confirming SVR 0x61=97 and 0x72=114 as VICs and
    /// 0x81=129/0x83=131 as DTD indices 1 and 3, independent of edid-decode's own pretty-printed
    /// output.
    static let ctaTimingsTestHex =
        "00ffffffffffff0031d8341200000000221a0103806036780fee91a3544c99260f50542fcf0031594559818081409040" +
        "9500a940b30008e80030f2705a80b0588a00c01c3200001e000000fd001878189946000a202020202020000000fc0068" +
        "646d692d346b2d3630300a2000000010000000000000000000000000000003ebf0020200000000000000000000000000" +
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "0000000000000000000000000000000c02036df15161605f5e5d101f04132221200514021101230907076d030c001000" +
        "003c21006001020367d85dc401788008e200cae90d9161728183fe92a6e20f02e20e72f622020f940a00ff134f000780" +
        "1f006f083d002f000700e3230148e82a0003ff139f0531c20007e208914dd000a0f0703e8030203500c01c3200001e49" +
        "020304f11a1d008051d01c2040803500c01c320000000000000000000000000000000000000000000000000000000000" +
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "00000000000000000000000000000000000000000000000000000000000000ef"

    @Test("cta: cta-timings.test's Video Data Block yields all 17 VICs, none native")
    func ctaTimingsTestVideoDataBlockVICs() throws {
        let bytes = Self.hexBytes(Self.ctaTimingsTestHex)
        let result = EDIDCTAParser.parse(bytes, base: 256, block: 2)

        let vics = result.modes.compactMap { mode -> (Int, Bool)? in
            if case .ctaVIC(2, let vic, let native, false) = mode.source { return (vic, native) }
            return nil
        }
        #expect(vics.count == 17)
        #expect(Set(vics.map(\.0)) == Set([97, 96, 95, 94, 93, 16, 31, 4, 19, 34, 33, 32, 5, 20, 2, 17, 1]))
        #expect(vics.allSatisfy { !$0.1 })

        let vic97 = try #require(result.modes.first {
            if case .ctaVIC(2, 97, false, false) = $0.source { return true }
            return false
        })
        #expect(vic97.width == 3840); #expect(vic97.height == 2160); #expect(vic97.pixelClockHz == 594_000_000)
    }

    @Test("cta: cta-timings.test's YCbCr 4:2:0 Video Data Block yields VIC 114 as 4:2:0-only")
    func ctaTimingsTestY420VDB() throws {
        let bytes = Self.hexBytes(Self.ctaTimingsTestHex)
        let result = EDIDCTAParser.parse(bytes, base: 256, block: 2)

        let vic114 = try #require(result.modes.first {
            if case .ctaVIC(2, 114, false, true) = $0.source { return true }
            return false
        })
        #expect(vic114.width == 3840); #expect(vic114.height == 2160); #expect(vic114.pixelClockHz == 594_000_000)
        // The plain Video Data Block does not also carry VIC 114 (it is 4:2:0-only there).
        #expect(!result.modes.contains {
            if case .ctaVIC(2, 114, _, false) = $0.source { return true }
            return false
        })
    }

    @Test("cta: cta-timings.test's Video Format Preference block records VICs 97/114 and DTDs 1/3")
    func ctaTimingsTestVFPDB() throws {
        let bytes = Self.hexBytes(Self.ctaTimingsTestHex)
        let result = EDIDCTAParser.parse(bytes, base: 256, block: 2)
        #expect(result.preferredVICs == [97, 114])
        #expect(result.preferredDTDIndices == [1, 3])
    }

    @Test("cta: cta-timings.test's DisplayID Type VII, VIII and X VTDBs decode as embedded-in-CTA modes")
    func ctaTimingsTestEmbeddedDisplayIDVTDBs() throws {
        let bytes = Self.hexBytes(Self.ctaTimingsTestHex)
        let result = EDIDCTAParser.parse(bytes, base: 256, block: 2)

        let typeVII = try #require(result.modes.first {
            if case .displayID(2, .typeVII, 0, true) = $0.source { return true }
            return false
        })
        #expect(typeVII.width == 5120); #expect(typeVII.height == 2160); #expect(typeVII.pixelClockHz == 693_264_000)

        let typeVIII = try #require(result.modes.first {
            if case .displayID(2, .typeVIII, 0, true) = $0.source { return true }
            return false
        })
        #expect(typeVIII.width == 1920); #expect(typeVIII.height == 1200); #expect(typeVIII.pixelClockHz == 317_000_000)

        let typeX = try #require(result.modes.first {
            if case .displayID(2, .typeX, 0, true) = $0.source { return true }
            return false
        })
        #expect(typeX.width == 5120); #expect(typeX.height == 1440); #expect(typeX.pixelClockHz == 383_240_000)
    }

    // Synthetic CTA block (revision 3, d = 27) with one data block: header 0xF6 (tag 7,
    // length 22), extended tag 0x22, revision byte 0x70 (revision 0, seven extra bytes per
    // record), then 20 bytes of 0x11. edid-decode's `cta_displayid_type_7` needs
    // `21 + ((x[0] & 0x70) >> 4)` = 28 payload bytes and gets 21, records "Empty Data Block"
    // and returns. `edid-decode-bin --skip-hex-dump --skip-sha <synth-r3-3.hex>`:
    //   DisplayID Type VII Video Timing Data Block:
    // (no DTD line under it). Reading the first 20 bytes as a record anyway would invent a
    // mode from a block edid-decode says holds none.
    @Test("cta: a CTA-embedded Type VII VTDB shorter than its revision's record size yields no mode")
    func ctaEmbeddedTypeVIIShortBlockYieldsNoMode() throws {
        let dtd = Self.hexBytes("023a801871382d40582c450000000000001e")
        var base = EDIDTestBuilder.baseBlock(version: (1, 4), descriptors: [dtd])
        base[126] = 1
        base = EDIDTestBuilder.withChecksum(base)
        var cta = [UInt8](repeating: 0, count: 128)
        cta[0] = 0x02; cta[1] = 0x03
        let dataBlock: [UInt8] = [0xE0 | 22, 0x22, 0x70] + [UInt8](repeating: 0x11, count: 20)
        for (i, b) in dataBlock.enumerated() { cta[4 + i] = b }
        cta[2] = UInt8(4 + dataBlock.count)
        cta = EDIDTestBuilder.withChecksum(cta)

        let edid = try #require(EDIDInfo(Data(base + cta)))
        let embedded = edid.modes.filter {
            if case .displayID(_, .typeVII, _, true) = $0.source { return true }
            return false
        }
        #expect(embedded.isEmpty, "expected no mode, got \(embedded)")
        #expect(edid.modes.count == 1) // the base DTD alone
    }

    @Test("cta: cta-timings.test's own DTDs land in both CTA-861 extension blocks")
    func ctaTimingsTestDTDs() throws {
        let bytes = Self.hexBytes(Self.ctaTimingsTestHex)
        let block2 = EDIDCTAParser.parse(bytes, base: 256, block: 2)
        let block3 = EDIDCTAParser.parse(bytes, base: 384, block: 3)

        let dtd2 = try #require(block2.modes.first {
            if case .detailedTiming(2, 0) = $0.source { return true }
            return false
        })
        #expect(dtd2.width == 3840); #expect(dtd2.height == 2160); #expect(dtd2.pixelClockHz == 533_250_000)

        let dtd3 = try #require(block3.modes.first {
            if case .detailedTiming(3, 0) = $0.source { return true }
            return false
        })
        #expect(dtd3.width == 1280); #expect(dtd3.height == 720); #expect(dtd3.pixelClockHz == 74_500_000)
    }

    /// edid-decode's own `test/cta-vfpdb.test` (v4l-utils, MIT). `edid-decode-bin
    /// --skip-hex-dump --skip-sha cta-vfpdb.test`:
    ///
    ///   Block 1, CTA-861 Extension Block:
    ///     Video Data Block:
    ///       VIC  95:  3840x2160   30.000000 Hz  16:9     67.500 kHz    297.000000 MHz
    ///       (plus VIC 16, 34, 4, 62, 1: 6 total)
    ///     Video Format Preference Data Block:
    ///       DTD   2
    ///
    /// Independently re-derived by walking the raw bytes: block-relative offset 3 is `e1`
    /// (extended tag, length 1), the next byte `46` is the extended tag 0x0D (VFPDB), whose
    /// single-byte payload `82` = SVR 130 = DTD index 2. No VIC-range SVR appears.
    static let ctaVFPDBTestHex =
        "00ffffffffffff000d33010100000000031b0103803c22780eee91a3544c99260f5054210800d1c0a9c081c001010101" +
        "010101010101023a801871382d40582c450058542100001e000000fd001e3c16591e000a202020202020000000fc0043" +
        "532d434f444543504c552d32000000ff003132333435360a20202020202001e4020325e1465f1022043e012309070783" +
        "0100006b030c000000003c20002001e2004ae20d82011d007251d01e206e28550020c23100001e565e00a0a0a0295030" +
        "20350058542100001a000000000000000000000000000000000000000000000000000000000000000000000000000000" +
        "00000000000000000000000000000005"

    @Test("cta: cta-vfpdb.test's Video Format Preference block records DTD 2 and no VICs")
    func ctaVFPDBTestDTDOnly() throws {
        let bytes = Self.hexBytes(Self.ctaVFPDBTestHex)
        let result = EDIDCTAParser.parse(bytes, base: 128, block: 1)
        #expect(result.preferredVICs == [])
        #expect(result.preferredDTDIndices == [2])

        let vics = result.modes.compactMap { mode -> Int? in
            if case .ctaVIC(1, let vic, _, false) = mode.source { return vic }
            return nil
        }
        #expect(Set(vics) == Set([95, 16, 34, 4, 62, 1]))
    }

    /// Synthetic Video Data Block, one 5-byte data block (header `0x44`: tag 2, length 4) with
    /// four hand-picked SVDs exercising every branch of `cta_svd`'s native/whole-byte logic:
    /// `0x85` (VIC 5, native), `0xC1` (VIC 193, no native bit: `(0xC1-1)&0x40 == 0x40 != 0`),
    /// `0x80` (`svd & 0x7f == 0`: skipped, no mode), `0x90` (VIC 16, native).
    @Test("cta: synthetic SVD bytes decode natives, the whole-byte VIC case, and the zero-VIC skip")
    func ctaSyntheticSVDBytes() throws {
        var block = [UInt8](repeating: 0, count: 128)
        block[0] = 0x02 // CTA tag
        block[1] = 0x03 // revision 3 (data blocks are only walked at revision >= 3)
        block[2] = 9    // first DTD offset: right after the one 5-byte data block
        block[3] = 0x00
        block[4] = 0x44 // Video Data Block, tag 2, length 4
        block[5] = 0x85 // VIC 5, native
        block[6] = 0xC1 // VIC 193, no native bit
        block[7] = 0x80 // (svd & 0x7f) == 0: skipped
        block[8] = 0x90 // VIC 16, native
        let result = EDIDCTAParser.parse(block, base: 0, block: 9)

        #expect(result.modes.count == 3) // 0x80 names no mode

        func vic(_ target: Int) -> EDIDMode? {
            result.modes.first {
                if case .ctaVIC(9, let vv, _, false) = $0.source { return vv == target }
                return false
            }
        }
        let v5 = try #require(vic(5))
        #expect(v5.width == 1920); #expect(v5.height == 1080); #expect(v5.interlaced == true)
        #expect(v5.pixelClockHz == 74_250_000)
        if case .ctaVIC(_, _, let native, _) = v5.source { #expect(native == true) } else { Issue.record("expected .ctaVIC") }

        let v193 = try #require(vic(193))
        #expect(v193.width == 5120); #expect(v193.height == 2160); #expect(v193.pixelClockHz == 1_485_000_000)
        if case .ctaVIC(_, _, let native, _) = v193.source { #expect(native == false) } else { Issue.record("expected .ctaVIC") }

        let v16 = try #require(vic(16))
        #expect(v16.width == 1920); #expect(v16.height == 1080); #expect(v16.pixelClockHz == 148_500_000)
        if case .ctaVIC(_, _, let native, _) = v16.source { #expect(native == true) } else { Issue.record("expected .ctaVIC") }

        #expect(vic(0) == nil)
    }

    /// `research/customer-probes/m1max_macos26.5.2_b/33_displayport_capability.json`, EDID field
    /// (Samsung SyncMaster, real corpus EDID, serial-redacted). `edid-decode-bin
    /// --skip-hex-dump --skip-sha <hex>` (base block checksum reads as 0xe4 where 0x66 is
    /// expected, the serial-redaction signature; the CTA extension's own checksum is untouched
    /// and reads correctly at 0xd1):
    ///
    ///   Block 1, CTA-861 Extension Block:
    ///     YCbCr 4:2:0 Video Data Block:
    ///       VIC  96:  3840x2160   50.000000 Hz  16:9    112.500 kHz    594.000000 MHz
    ///       VIC  97:  3840x2160   60.000000 Hz  16:9    135.000 kHz    594.000000 MHz
    ///       VIC 101:  4096x2160   50.000000 Hz 256:135  112.500 kHz    594.000000 MHz
    ///       VIC 102:  4096x2160   60.000000 Hz 256:135  135.000 kHz    594.000000 MHz
    static let m1maxCorpusHex =
        "00ffffffffffff004c2d080e000000000e1b0103807944782a23ada4544d99260f474abdef80714f81c0810081809500" +
        "a9c0b300010104740030f2705a80b0588a00baa84200001e000000fd00184b0f511e000a202020202020000000fc0053" +
        "796e634d61737465720a2020000000ff000000000000000000000000000001e4020340f0535f101f041305142021225d" +
        "5e626364071603122309070783010000e2000fe30503016e030c001000b83c20008001020304e3060d01e50e60616566" +
        "011d80d0721c1620102c2580501d7400009e662156aa51001e30468f3300501d7400001e023a801871382d40582c4500" +
        "baa84200001e000000000000000000d1"

    @Test("cta: m1max_macos26.5.2_b's real corpus EDID yields its YCbCr 4:2:0 VICs")
    func ctaCorpusM1MaxY420VDB() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.m1maxCorpusHex))))
        let y420 = edid.modes.compactMap { mode -> Int? in
            if case .ctaVIC(1, let vic, _, true) = mode.source { return vic }
            return nil
        }
        #expect(Set(y420) == Set([96, 97, 101, 102]))

        let vic97 = try #require(edid.modes.first {
            if case .ctaVIC(1, 97, false, true) = $0.source { return true }
            return false
        })
        #expect(vic97.width == 3840); #expect(vic97.height == 2160); #expect(vic97.pixelClockHz == 594_000_000)
    }

    // MARK: - Block walker, VTB-EXT, block map, checksums, tiled composite
    //
    // EDIDBlockWalker is the one place that enumerates every 128-byte block and assembles
    // EDIDInfo; `init?(Data)` now calls it directly. These tests exercise the pieces the four
    // per-block parsers don't cover on their own: the block map tag (0xF0), an all-zero padding
    // block, per-block checksums, the VTB-EXT parser, and the tiled composite.

    /// LG ULTRAGEAR+, 512 bytes, captured live from a real Mac
    /// (`research/customer-probes/m3max_macos27.0_g/33_displayport_capability.json`). Base block
    /// declares "Extension blocks: 3"; the buffer holds all three: a Block Map extension (tag
    /// 0xF0) at block 1, a CTA-861 extension at block 2, a DisplayID 1.2 extension at block 3
    /// whose Type I data block carries the panel's real top mode.
    static let m3maxBlockMapHex =
        "00ffffffffffff001e6d839e3d4907000820010380693b78eac1f3ad5245af250c4849210900d1c0614001010101010101010101010108e80030f2705a80b0588a001a4e4200001e000000fd0828781e0f77000a202020202020000000fc004c4720554c545241474541522b000000ff003230384e545a4e45313530310a0304f00270000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009e02035671230f5707830100005061605f5e5d22201f1210040301133f766d030c001000b83c2000600102036ad85dc401788063002878e30f0380e2006ae305c000e6060501732e126d1a000002012878000473142e2904740030f2705a80b0588a001a4e4200001e6fc200a0a0a05550302035001a4e4200001a0000000000e6701279030001000c7017480d000f700890784ebb0f000a74210e0e0701220000000301286ea30184ff0e9f002f801f006f084c0002000400856f00047f079f002f801f0037043f000200040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008d90"

    @Test("walker: LG ULTRAGEAR+'s block map (0xF0) is recorded as .blockMap, and the DisplayID block after it is still walked")
    func walkerBlockMapRecordedAndBlockAfterItWalked() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.m3maxBlockMapHex))))
        #expect(edid.blocks.count == 4) // base, block map, CTA, DisplayID
        #expect(edid.blocks[1].kind == .blockMap)
        #expect(edid.blocks[2].kind == .cta861)
        if case .displayID(let version) = edid.blocks[3].kind {
            #expect(version == 0x12)
        } else {
            Issue.record("expected blocks[3].kind == .displayID, got \(edid.blocks[3].kind)")
        }
        // `edid-decode-bin --skip-hex-dump --skip-sha` on this fixture: Block 3's Type I data
        // block reads "DTD: 3840x2160 119.998882 Hz 16:9 268.438 kHz 1073.750000 MHz ...
        // preferred". The block-map block carries no timing of its own; this mode can only be
        // present if the walker keeps reading the blocks that follow it.
        let displayIDTop = edid.modes.first {
            if case .displayID(3, .typeI, 0, false) = $0.source { return true }
            return false
        }
        let displayIDTop2 = try #require(displayIDTop)
        #expect(displayIDTop2.width == 3840)
        #expect(displayIDTop2.height == 2160)
        #expect(displayIDTop2.pixelClockHz == 1_073_750_000)
    }

    /// Gigabyte MO27Q28G, 384 bytes, captured live from a real Mac
    /// (`research/customer-probes/m1_macos26.5.2_b/33_displayport_capability.json`). Base block
    /// declares "Extension blocks: 1", but the buffer holds two: a real CTA-861 block at block 1
    /// and, past what byte 126 admits, an entirely zero 128-byte block at block 2
    /// (`edid-decode-bin`: "Unknown EDID Extension Block 0x00", all 128 bytes zero).
    static let m1CorpusZeroBlockHex =
        "00ffffffffffff001c543c270101010131230103803b2178eeced5b04f3cb7260a5054bfef80714f81c08100814081809500a9c0b300565e00a0a0a02950302035004e4e2100001a000000fd0230191eff7e000a202020202020000000fc004d4f3237513238470a20202020000000ff003235343932463030313433380001ea020363f1e2780251767561605f5e5d3f4003040f10131f202923090607830100006d030c00200038442000600302016dd85dc401788033020000c3330c741a0000030030f0eca09e029e0218010000000000e305c301e20f0fe6060d019e5202e200ea6fc200a0a0a05550302035004e4e2100001a00000000000000000000170000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

    @Test("walker: MO27Q28G's under-declared trailing all-zero block is recorded as .padding")
    func walkerZeroBlockRecordedAsPadding() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.m1CorpusZeroBlockHex))))
        #expect(edid.declaredExtensionCount == 1) // byte 126 under-declares by one, as measured
        #expect(edid.blocks.count == 3) // base, CTA, the zero block byte 126 doesn't admit
        #expect(edid.blocks[1].kind == .cta861)
        #expect(edid.blocks[2].kind == .padding)
    }

    // MARK: Checksums

    // A DisplayID block whose section length byte claims 0xFF. edid-decode's
    // `parse_displayid_block` caps the length at 121 ("DisplayID length %d is greater than
    // 121", parse-displayid-block.cpp:2743) and sums the section checksum over bytes 1 through
    // 5 + length of THIS block only. Summing the declared 0xFF range instead runs 133 bytes
    // into the neighbouring blocks, and this fixture's third block carries one byte chosen so
    // that neighbour-crossing sum comes out to zero: a checksum that reads valid from another
    // block's bytes. The declared checksum byte (offset 5 + 255) sits past the section, so
    // there is no checksum to hold; the block's `checksumValid` is false.
    @Test("walker: a DisplayID section length past 121 never sums a neighbouring block into its checksum")
    func walkerDisplayIDSectionChecksumNeverCrossesTheBlock() throws {
        var base = Self.g34wBaseBlock
        base[126] = 3
        base = EDIDTestBuilder.withChecksum(base)
        var displayID = [UInt8](repeating: 0, count: 128)
        displayID[0] = 0x70
        displayID[1] = 0x12
        displayID[2] = 0xFF // section length: past the block
        displayID[3] = 0x01
        displayID = EDIDTestBuilder.withChecksum(displayID) // block sum 0, so only the section sum is in play
        let padding = [UInt8](repeating: 0, count: 128)
        var third = [UInt8](repeating: 0, count: 128)
        // The unclamped range is bytes 129...388 of the EDID: the DisplayID block from byte 1,
        // all of the padding block, and bytes 384...388 of this block. Byte 386 (offset 2 here)
        // is set so that range sums to 0 mod 256.
        let displayIDPartialSum = displayID[1...].reduce(UInt8(0)) { $0 &+ $1 }
        third[2] = UInt8((256 - Int(displayIDPartialSum)) % 256)
        third = EDIDTestBuilder.withChecksum(third)
        let bytes = base + displayID + padding + third
        #expect(bytes[129...388].reduce(UInt8(0)) { $0 &+ $1 } == 0) // fixture guard: the trap is armed

        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.blocks.count == 4)
        #expect(edid.blocks[1].kind == .displayID(version: 0x12))
        #expect(edid.blocks[1].checksumValid == false)
    }

    @Test("walker: the live-captured G34w-10 base block's own checksum holds")
    func walkerG34wBaseChecksumHolds() throws {
        // Sum of all 128 bytes mod 256 == 0, verified independently (Python `sum(bytes) % 256`)
        // against the same literal array `parsesPreferredMode` uses: this is a real, serial-intact
        // capture, unlike the corpus EDIDs below.
        let edid = try #require(EDIDInfo(Data(Self.g34wBaseBlock)))
        #expect(edid.blocks.count == 1)
        #expect(edid.blocks[0].kind == .base)
        #expect(edid.blocks[0].checksumValid == true)
    }

    @Test("walker: a serial-redacted corpus EDID's base checksum fails; its CTA extension checksum holds")
    func walkerCorpusSerialRedactionFailsBaseChecksumOnly() throws {
        // `m1maxCorpusHex` (used above for the YCbCr 4:2:0 test): edid-decode-bin reads the base
        // block checksum as 0xe4 where 0x66 is expected (the serial-redaction signature: the
        // serial bytes were zeroed after the checksum was computed), while the CTA extension's
        // own checksum is untouched and reads correctly at 0xd1.
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.m1maxCorpusHex))))
        #expect(edid.blocks.count == 2)
        #expect(edid.blocks[0].kind == .base)
        #expect(edid.blocks[0].checksumValid == false)
        #expect(edid.blocks[1].kind == .cta861)
        #expect(edid.blocks[1].checksumValid == true)
    }

    // MARK: VTB-EXT

    /// 800x600@60 DTD, a 1920x1080 CVT code, and an aspect-bits-0 standard timing, in a synthetic
    /// VTB-EXT block appended to a minimal EDID 1.4 base block (preferred 640x480@60). Expected
    /// values: `edid-decode-bin --skip-hex-dump --skip-sha` on these exact bytes:
    ///
    ///   Block 1, Video Timing Extension Block:
    ///     Version: 1
    ///     Detailed Timing Descriptors:
    ///       DTD:   800x600    60.316541 Hz   4:3     37.879 kHz     40.000000 MHz
    ///     Coordinated Video Timings:
    ///       CVT:  1920x1080   59.962844 Hz  16:9     67.158 kHz    173.000000 MHz
    ///     Standard Timings:
    ///       GTF     :   760x475    59.999915 Hz  16:10    29.520 kHz     28.103000 MHz
    ///
    /// The GTF standard timing's 16:10 aspect (rather than base-block EDID 1.4's own default of
    /// 16:10 too, since `edidMinor >= 3`) is confirmed separately below at `edidMinor == 2`,
    /// where the base-block rule alone would give 1:1.
    @Test("walker: a synthetic VTB-EXT block's DTD, CVT code and GTF-only standard timing all decode")
    func walkerVTBBlockDTDCVTAndStandardTiming() throws {
        // 640x480@60: pixel clock 25.20 MHz (pclk10k 2520), hBlank 160, vBlank 45.
        let preferredDTD: [UInt8] = [0xD8, 0x09, 0x80, 0xA0, 0x20, 0xE0, 0x2D, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        var bytes = EDIDTestBuilder.baseBlock(version: (1, 4), descriptors: [preferredDTD])
        bytes[126] = 1
        // 800x600@60: pixel clock 40.00 MHz (pclk10k 4000), hBlank 256, vBlank 28.
        let vtbDTD: [UInt8] = [0xA0, 0x0F, 0x20, 0x00, 0x31, 0x58, 0x1C, 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let vtb = EDIDTestBuilder.vtbBlock(
            dtds: [vtbDTD], cvtCodes: [(0x1B, 0x24, 0x08)], standardTimings: [(0x40, 0x00)])
        bytes.append(contentsOf: vtb)

        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.blocks.count == 2)
        #expect(edid.blocks[1].kind == .vtb)
        #expect(edid.blocks[1].checksumValid == true)

        let dtd = try #require(edid.modes.first {
            if case .detailedTiming(1, 0) = $0.source { return true }
            return false
        })
        #expect(dtd.width == 800); #expect(dtd.height == 600); #expect(dtd.pixelClockHz == 40_000_000)

        let cvt = try #require(edid.modes.first {
            if case .cvtCode(1, 0, 60, false) = $0.source { return true }
            return false
        })
        #expect(cvt.width == 1920); #expect(cvt.height == 1080); #expect(cvt.pixelClockHz == 173_000_000)

        let standard = try #require(edid.modes.first {
            if case .standardTiming(100, .gtf, nil) = $0.source { return true }
            return false
        })
        #expect(standard.width == 760); #expect(standard.height == 475); #expect(standard.pixelClockHz == 28_103_000)
    }

    /// The same standard-timing byte (aspect bits 0, `EDIDMode.Source.standardTiming` index 100)
    /// at `edidMinor == 2`, where a base-block standard timing would read 1:1, not 16:10
    /// (`EDIDBaseBlockParser.standardTiming`'s own aspect-0 rule is `edidMinor >= 3 ? (16,10) :
    /// (1,1)`). `edid-decode-bin --skip-hex-dump --skip-sha` on these exact bytes still reads
    /// "GTF     :   760x475    59.999915 Hz  16:10 ... 28.103000 MHz": `gtf_only` forces 16:10
    /// regardless of `edid_minor` (`print_standard_timing`'s `case 0x00: if (gtf_only || ...)`).
    @Test("walker: a VTB-EXT standard timing forces 16:10 at edidMinor 2, where the base-block rule alone would give 1:1")
    func walkerVTBStandardTimingForces16x10RegardlessOfEDIDMinor() throws {
        let preferredDTD: [UInt8] = [0xD8, 0x09, 0x80, 0xA0, 0x20, 0xE0, 0x2D, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        var bytes = EDIDTestBuilder.baseBlock(version: (1, 2), descriptors: [preferredDTD])
        bytes[126] = 1
        let vtb = EDIDTestBuilder.vtbBlock(standardTimings: [(0x40, 0x00)])
        bytes.append(contentsOf: vtb)

        let edid = try #require(EDIDInfo(Data(bytes)))
        let standard = try #require(edid.modes.first {
            if case .standardTiming(100, .gtf, nil) = $0.source { return true }
            return false
        })
        #expect(standard.width == 760); #expect(standard.height == 475); #expect(standard.pixelClockHz == 28_103_000)
    }

    // MARK: Tiled composite

    /// Dell UP2715K, 384 bytes, from edid-decode's own `data/dell-up2715k-dp1-tile1` (v4l-utils,
    /// MIT). Base block + CTA-861 extension + DisplayID 1.2 extension carrying the Tiled Display
    /// Topology block (0x12): 2 horizontal tiles, 1 vertical, tile resolution 2560x2880
    /// (`edid-decode-bin --skip-hex-dump --skip-sha`: "Num horizontal tiles: 2 Num vertical
    /// tiles: 1", "Tile resolution: 2560x2880").
    static let dellUP2715KTileHex =
        "00ffffffffffff0010acb6405339383012190104b53c22783a7225ac5033b7260b50542108008100b300d100a9408180d1c001010101565e00a0a0a029503020350055502100001a000000ff0046314a434d353455303839530a000000fc0044454c4c205550323731354b0a000000fd001d4b1fb436010a20202020202002ad02030cf123090707830100004dd000a0f0703e805020650c555021000018565e00a0a0a029503020350055502100001a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000034701279000012001682101000ff093f0b000000000044454cb6405339383003003c4cd00084ff0e9f002f801f006f083d0002000400105d0004ff099f002f801f003f0b280002000900c4bc0004ff099f002f801f003f0b51000200090007000a088100080400040210000000000000000000000000000000000000000000c990"

    @Test("walker: the real Dell UP2715K tile fixture derives its composite from the higher-clock DisplayID Type I entry, not base.preferred")
    func walkerDellTileDerivesCompositeFromDisplayIDEntry() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.dellUP2715KTileHex))))
        #expect(edid.tiledTopology?.hTiles == 2)
        #expect(edid.tiledTopology?.vTiles == 1)
        #expect(edid.tiledTopology?.tileWidth == 2560)
        #expect(edid.tiledTopology?.tileHeight == 2880)
        // `edid-decode-bin`: base block "DTD 1: 2560x1440 ... 241.500000 MHz" -- the panel's own
        // preferred mode does NOT match the tile's 2560x2880. The DisplayID block's own Type I
        // data block carries two 2560x2880 entries: "DTD: 2560x2880 29.986961 Hz ... 238.250000
        // MHz" and "DTD: 2560x2880 59.981580 Hz ... 483.250000 MHz". Rule 4 (revised) picks the
        // higher-pixel-clock declared entry matching the tile resolution, from any source: the
        // second one, at 483.25 MHz.
        #expect(edid.preferredWidth == 2560)
        #expect(edid.preferredHeight == 1440)

        let composite = try #require(edid.modes.first {
            if case .tiledComposite = $0.source { return true }
            return false
        })
        #expect(composite.width == 5120)
        #expect(composite.height == 2880)
        #expect(composite.hTotal == 5440) // 2720 (the 483.25 MHz entry's own hTotal) * 2 tiles
        #expect(composite.vTotal == 2962) // 2962 (the 483.25 MHz entry's own vTotal) * 1 tile
        #expect(composite.pixelClockHz == 966_500_000) // 483_250_000 * 2 tiles
        if case .tiledComposite(let tiles, let from) = composite.source {
            #expect(tiles == 2)
            #expect(from == .typeI)
        } else {
            Issue.record("expected .tiledComposite")
        }
    }

    /// LG UltraFine 5K, 384 bytes, captured live from a real Mac
    /// (`research/customer-probes/m1max_macos26.5.1_c/33_displayport_capability.json`, first
    /// active DisplayPort block). Base block + two DisplayID 1.2 extensions: the first carries
    /// the panel's 3840x2160 and 3200x1800 Type I timings (no tile-resolution match), the second
    /// carries the Tiled Display Topology block (2 horizontal tiles, 2560x2880) and a single
    /// Type I entry at that exact resolution. The panel's real 5120x2880 mode is declared
    /// NOWHERE in this EDID except as this tile: this is the shape the corpus measurement in
    /// `EDIDBlockWalker`'s doc comment names.
    static let lgUltraFine5KHex =
        "00ffffffffffff001e6d745b0000000003200104b53c2278800f91ae5243b0260f50542000000101010101010101010101010101010125cc0050f0703e800820180058542100001aa35b0050a0a029500820180058542100001a000000ff0000000000000000000000000000000000fc004c4720556c74726146696e650a0210701279030001000c3e17160d0014400b50784e992900100b817c6514dc402da5b8c79289b2478703002824cc0084ff0e4f0007801f006f083d00000007005e8e00047f0c4f0007801f00070733000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000990701279030012001682100000ff093f0b000000000047534d745b01010101030014d0bc0008ff099f0007801f003f0b510000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001290"

    @Test("walker: LG UltraFine 5K declares its tile mode only in DisplayID and its composite reads the real 5120x2880")
    func walkerLGUltraFine5KComposite() throws {
        let edid = try #require(EDIDInfo(Data(Self.hexBytes(Self.lgUltraFine5KHex))))
        #expect(edid.monitorName == "LG UltraFine") // fixture guard
        #expect(edid.tiledTopology?.hTiles == 2)
        #expect(edid.tiledTopology?.vTiles == 1)
        #expect(edid.tiledTopology?.tileWidth == 2560)
        #expect(edid.tiledTopology?.tileHeight == 2880)
        // No declared entry anywhere in this EDID is 5120x2880; the panel's real top mode is
        // reachable only as the tiled composite. `edid-decode-bin`, second DisplayID block:
        // "Video Timing Modes Type 1 ...: DTD: 2560x2880 ... 483.370000 MHz".
        // Fixture guard: no DECLARED entry (anything but the composite itself, which the code
        // under test is about to add) is 5120x2880.
        let hasDeclared5120 = edid.modes.contains {
            guard $0.width == 5120, $0.height == 2880 else { return false }
            if case .tiledComposite = $0.source { return false }
            return true
        }
        #expect(hasDeclared5120 == false, "fixture guard: no declared 5120x2880 entry, only the tile")

        let composite = try #require(edid.modes.first {
            if case .tiledComposite = $0.source { return true }
            return false
        })
        #expect(composite.width == 5120)
        #expect(composite.height == 2880)
        #expect(composite.hTotal == 5440) // 2720 * 2 tiles
        #expect(composite.vTotal == 2962) // 2962 * 1 tile
        #expect(composite.pixelClockHz == 966_740_000) // 483_370_000 * 2 tiles
        if case .tiledComposite(let tiles, let from) = composite.source {
            #expect(tiles == 2)
            #expect(from == .typeI)
        } else {
            Issue.record("expected .tiledComposite")
        }
    }

    @Test("walker: a synthetic tiled topology composites from the matching entry even when base.preferred is a different resolution")
    func walkerSyntheticTiledCompositeIgnoresNonMatchingPreferred() throws {
        // DTD 1 (preferred, base-block slot 0): 3840x2160, pixel clock 200 MHz -- does NOT match
        // the tile resolution below. `edid-decode-bin`: "DTD 1: 3840x2160 ... 200.000000 MHz".
        let preferredDTD: [UInt8] = [0x20, 0x4E, 0x00, 0x30, 0xF2, 0x70, 0xC8, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        // DTD 2 (base-block slot 1): 2560x1440, pixel clock 100 MHz -- matches the tile
        // resolution, and is not the preferred mode. `edid-decode-bin`: "DTD 2: 2560x1440 ...
        // 100.000000 MHz".
        let secondDTD: [UInt8] = [0x10, 0x27, 0x00, 0xA0, 0xA0, 0xA0, 0x28, 0x50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        var bytes = EDIDTestBuilder.baseBlock(version: (1, 4), descriptors: [preferredDTD, secondDTD])
        bytes[126] = 1

        // Tiled Display Topology data block (tag 0x12), 22-byte payload: hTiles = 1 + (p[1]>>4) =
        // 2, vTiles = 1 + (p[1]&0xF) = 1, tile resolution 2560x1440 (p[4..5] = 2560-1, p[6..7] =
        // 1440-1). `edid-decode-bin` on the same bytes: "Num horizontal tiles: 2 Num vertical
        // tiles: 1", "Tile resolution: 2560x1440".
        let tiledPayload: [UInt8] = [0x00, 0x10, 0x00, 0x00, 0xFF, 0x09, 0x9F, 0x05] + [UInt8](repeating: 0, count: 14)
        let displayID = EDIDTestBuilder.displayIDBlock(version: 0x12, dataBlocks: [(tag: 0x12, revision: 0, payload: tiledPayload)])
        bytes.append(contentsOf: displayID)

        let edid = try #require(EDIDInfo(Data(bytes)))
        // Fixture guard: the preferred mode really is the non-matching 3840x2160, not the tile.
        #expect(edid.preferredWidth == 3840)
        #expect(edid.preferredHeight == 2160)
        #expect(edid.tiledTopology?.hTiles == 2)
        #expect(edid.tiledTopology?.vTiles == 1)

        let composite = try #require(edid.modes.first {
            if case .tiledComposite = $0.source { return true }
            return false
        })
        // hTiles * vTiles = 2 independent streams, each carrying the matching (non-preferred)
        // entry's mode: width and hTotal double, height and vTotal (vTiles == 1) stay put, pixel
        // clock doubles.
        #expect(composite.width == 5120)
        #expect(composite.height == 1440)
        #expect(composite.hTotal == 5440)
        #expect(composite.vTotal == 1480)
        #expect(composite.pixelClockHz == 200_000_000)
        if case .tiledComposite(let tiles, let from) = composite.source {
            #expect(tiles == 2)
            #expect(from == nil) // the matching entry is a base-block DTD, not a DisplayID one
        } else {
            Issue.record("expected .tiledComposite")
        }
    }

    // MARK: Trailing partial block

    @Test("walker: a trailing partial block is walked as one extension; the remaining bytes are ignored")
    func walkerTrailingPartialBlockIgnored() throws {
        // Base block + one real CTA-861 extension (256 bytes) + 44 junk bytes: blocksPresent =
        // (300 - 128) / 128 = 1, so only the CTA extension is walked and the 44 trailing bytes
        // never form a third block.
        var bytes = Self.g34wBaseBlock + Self.hexBytes(Self.g34wExtensionHex)
        bytes.append(contentsOf: [UInt8](repeating: 0xAB, count: 44))
        #expect(bytes.count == 300)

        let edid = try #require(EDIDInfo(Data(bytes)))
        #expect(edid.blocks.count == 2)
        #expect(edid.blocks[0].kind == .base)
        #expect(edid.blocks[1].kind == .cta861)
    }
}
