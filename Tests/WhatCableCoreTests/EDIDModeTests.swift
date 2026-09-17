import Foundation
import Testing
@testable import WhatCableCore

@Suite("EDID mode model")
struct EDIDModeTests {
    @Test("refreshHz is the field rate for interlaced modes")
    func interlacedRefresh() {
        let m = EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 74_250_000, interlaced: true)
        #expect(abs(m.refreshHz - 60.0) < 0.001)
    }
    @Test("topMode is the highest pixel clock, then the larger picture, then the higher refresh")
    func topModeOrder() {
        let a = EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 594_000_000)
        let b = EDIDInfo.mode(2560, 1440, hTotal: 2720, vTotal: 1525, pixelClockHz: 746_640_000, source: .displayID(block: 2, type: .typeI, index: 0, embeddedInCTA: false))
        let c = EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 148_500_000, source: .ctaVIC(block: 1, vic: 16, native: true, ycbcr420Only: false))
        let e = EDIDInfo.fixture(preferred: a, modes: [a, c, b])
        #expect(e.topMode == b)
        #expect(e.modes.count == 3)
        #expect(e.preferredWidth == 3840)
    }
    // Base block: one 1080p60 DTD (`02 3a 80 18 71 38 2d 40 58 2c 45 00 00 00 00 00 00 1e`).
    // CTA block (revision 3, d = 4, no data blocks) with one DTD `60 ea 80 00 ...`: pixel
    // clock 0xea60 * 10 kHz = 600 MHz, 128 active pixels, no blanking, 0 lines.
    // `edid-decode-bin --skip-hex-dump --skip-sha <synth-r3-2.hex>`:
    //   DTD 1:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz
    //   DTD 2:   128x0            inf Hz   1:0   4687.500 kHz    600.000000 MHz (analog composite, sync-on-green)
    // DTD 2 is a declared fact and stays in `modes` (the oracle sweep's rule 7 matches it), but
    // a mode with no picture and no vertical total is not a mode the panel can run, so the
    // top is the 148.5 MHz DTD, not the 600 MHz one.
    @Test("topMode skips an entry with a zero dimension or total, which stays in modes")
    func topModeSkipsZeroDimensionEntries() throws {
        let dtd = EDIDInfoTests.hexBytes("023a801871382d40582c450000000000001e")
        var base = EDIDTestBuilder.baseBlock(version: (1, 4), descriptors: [dtd])
        base[126] = 1
        base = EDIDTestBuilder.withChecksum(base)
        var cta = [UInt8](repeating: 0, count: 128)
        cta[0] = 0x02; cta[1] = 0x03; cta[2] = 0x04
        let zeroLines = EDIDInfoTests.hexBytes("60ea8000" + String(repeating: "00", count: 14))
        for (i, b) in zeroLines.enumerated() { cta[4 + i] = b }
        cta = EDIDTestBuilder.withChecksum(cta)

        let edid = try #require(EDIDInfo(Data(base + cta)))
        #expect(edid.modes.contains { $0.pixelClockHz == 600_000_000 && $0.width == 128 && $0.height == 0 })
        let top = try #require(edid.topMode)
        #expect(top.pixelClockHz == 148_500_000 && top.width == 1920 && top.height == 1080)
    }
    @Test("sourceDescription names the block and format")
    func sourceDescription() {
        let m = EDIDInfo.mode(2560, 1440, hTotal: 2720, vTotal: 1525, pixelClockHz: 746_640_000, source: .displayID(block: 2, type: .typeI, index: 0, embeddedInCTA: false))
        #expect(m.sourceDescription == "DisplayID Type I (block 2)")
        let v = EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 1_188_000_000, source: .ctaVIC(block: 1, vic: 118, native: false, ycbcr420Only: false))
        #expect(v.sourceDescription == "CTA VIC 118 (block 1)")
    }
}
