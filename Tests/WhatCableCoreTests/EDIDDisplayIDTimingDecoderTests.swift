import Foundation
import Testing
@testable import WhatCableCore

// Every expected value below was read from edid-decode built from v4l-utils commit
// f341ed8e3742118a86619e5f499017db2de30d94, run as
//   edid-decode-bin --skip-hex-dump --skip-sha --long-timings <hexfile>
// on the same bytes the test feeds the decoder. The output lines sit above each test.
// hTotal = hact + Hfront + Hsync + Hback; vTotal = vact + Vfront + Vsync + Vback for
// progressive modes. For interlaced modes edid-decode prints the halved field porches;
// the model keeps the frame: vTotal = vact + the record's vblank, refreshHz is the field
// rate. The synthetic records live in two DisplayID blocks built by
// `EDIDTestBuilder.displayIDBlock`, and the first test in each group pins the built
// block to the exact hex edid-decode read, so the oracle and the decoder saw one set of bytes.
@Suite("EDID DisplayID timing decoders")
struct EDIDDisplayIDTimingDecoderTests {

    // MARK: - Helpers

    /// One line per mode so a failure prints computed against expected side by side.
    static func shape(_ m: EDIDMode?) -> String {
        guard let m else { return "nil" }
        return "\(m.width)x\(m.height)\(m.interlaced ? "i" : "") hTotal \(m.hTotal) vTotal \(m.vTotal) \(m.pixelClockHz / 1000) kHz"
    }

    static func expected(_ w: Int, _ h: Int, hTotal: Int, vTotal: Int, kHz: Int, interlaced: Bool = false) -> String {
        "\(w)x\(h)\(interlaced ? "i" : "") hTotal \(hTotal) vTotal \(vTotal) \(kHz) kHz"
    }

    static func slice(_ bytes: [UInt8]) -> ArraySlice<UInt8> { bytes[...] }

    // MARK: - Synthetic DisplayID 1.2 block (Types I, II, III, V, VI)

    /// 1920x1080i, 74.25 MHz, aspect 16:9 (x3 = 0x14: aspect 4, bit 4 interlaced).
    static let typeIInterlaced = EDIDInfoTests.hexBytes("001d00147f07170157002b0037042c0003000900")
    /// 1920x1080, 148.5 MHz: hact 8+8*239, hblank 8+8*34, hfp 8+8*10, hsync 8+8*4, vact 1+1079, vblank 1+44, vfp 1+3, vsync 1+4.
    static let typeII = EDIDInfoTests.hexBytes("013a0000ef44a437042c34")
    /// 16:9, CVT RBv1 (x0 bits 6-4 = 1), hact 8+8*239 = 1920, refresh 1+59.
    static let typeIIIReduced = EDIDInfoTests.hexBytes("14ef3b")
    /// 16:10, CVT standard, hact 8+8*209 = 1680, refresh 1+59.
    static let typeIIIStandard = EDIDInfoTests.hexBytes("05d13b")
    /// 2560x1440 at 1+59 Hz, RBv2.
    static let typeV = EDIDInfoTests.hexBytes("0000ff099f053b")
    /// 14-byte Type VI: 148.5 MHz (1 kHz units), 1920x1080, hblank 280, hfp 88, hsync 44, vblank 45, vfp 4, vsync 5.
    static let typeVI14 = EDIDInfoTests.hexBytes("1344027f0737041757012b2c0304")
    /// 17-byte Type VI (x2 bit 6 set): 241.5 MHz, 2560x1440, hblank 160, hfp 48, hsync 32, vblank 41, vfp 3, vsync 5, plus size bytes.
    static let typeVI17 = EDIDInfoTests.hexBytes("5baf43ff099f059f2f001f280204aa5f01")

    static let v1Block = EDIDTestBuilder.displayIDBlock(version: 0x12, dataBlocks: [
        (tag: 0x03, revision: 0x00, payload: typeIInterlaced),
        (tag: 0x04, revision: 0x00, payload: typeII),
        (tag: 0x05, revision: 0x00, payload: typeIIIReduced + typeIIIStandard),
        (tag: 0x11, revision: 0x00, payload: typeV),
        (tag: 0x13, revision: 0x00, payload: typeVI14 + typeVI17),
    ])

    /// The exact 128 bytes edid-decode read for the 1.2 fixture (appended to `EDIDTestBuilder.baseBlock()`
    /// with byte 126 = 1 and checksummed).
    static let v1BlockHex =
        "70125a0100030014001d00147f07170157002b0037042c000300090004000b013a0000ef44a437042c3405000614ef3b05d13b1100070000ff099f053b13001f1344027f0737041757012b2c03045baf43ff099f059f2f001f280204aa5f016c0000000000000000000000000000000000000000000000000000000000000090"

    @Test("The synthetic DisplayID 1.2 block is byte-identical to what edid-decode read")
    func v1BlockMatchesOracleBytes() {
        #expect(Self.v1Block == EDIDInfoTests.hexBytes(Self.v1BlockHex))
        #expect(Self.v1Block.count == 128)
    }

    // MARK: - Synthetic DisplayID 2.0 block (Types IX, X, VIII)

    /// RBv2 2560x1440 at 1+59; RBv1 3840x2160 at 1+59; standard 1920x1200 at 1+59.
    static let typeIX = EDIDInfoTests.hexBytes("02ff099f053b" + "01ff0e6f083b" + "007f07af043b")
    /// Xiaomi Mi Monitor (corpus `m4_macos27.0_h`), the tag 0x2A payload as captured: five 6-byte records.
    static let typeXXiaomi = EDIDInfoTests.hexBytes("01ff0e6f088f" + "01ff099f059f" + "01ff099f058f" + "007f0737049f" + "007f0737048f")
    /// Four 8-byte records (block revision 0x20 = two extra bytes):
    /// RBv3 + hblank 160 + early vsync, 3840x2160, 1+0xEF = 240 Hz, delta hblank 2, add vblank 3, alt min vblank;
    /// RBv3, 2560x1440, 1+0x67+(1<<8) = 360 Hz, delta hblank 7, add vblank 1;
    /// RBv2 video optimised, 1920x1080, 60 Hz;
    /// RBv3 + hblank 160, 1920x1080, 120 Hz, delta hblank 6.
    static let typeXReducedV3 = EDIDInfoTests.hexBytes("1bff0e6f08ef6801" + "03ff099f05673d00" + "127f0737043b0000" + "137f073704771800")

    static let v2Block = EDIDTestBuilder.displayIDBlock(version: 0x20, dataBlocks: [
        (tag: 0x24, revision: 0x00, payload: typeIX),
        (tag: 0x2A, revision: 0x00, payload: typeXXiaomi),
        (tag: 0x2A, revision: 0x20, payload: typeXReducedV3),
        (tag: 0x23, revision: 0x00, payload: [0x52]),   // Type VIII code type 0: DMT 0x52
        (tag: 0x23, revision: 0x40, payload: [97]),     // Type VIII code type 1: VIC 97
        (tag: 0x23, revision: 0x80, payload: [1]),      // Type VIII code type 2: HDMI VIC 1
    ])

    static let v2BlockHex =
        "702065010024001202ff099f053b01ff0e6f083b007f07af043b2a001e01ff0e6f088f01ff099f059f01ff099f058f007f0737049f007f0737048f2a20201bff0e6f08ef680103ff099f05673d00127f0737043b0000137f0737047718002300015223400161238001018e000000000000000000000000000000000000000090"

    @Test("The synthetic DisplayID 2.0 block is byte-identical to what edid-decode read")
    func v2BlockMatchesOracleBytes() {
        #expect(Self.v2Block == EDIDInfoTests.hexBytes(Self.v2BlockHex))
        #expect(Self.v2Block.count == 128)
    }

    // MARK: - Type I / VII

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings mag274q.hex   (EDIDInfoTests.mag274qHex)
    //   Video Timing Modes Type 1 - Detailed Timings Data Block:
    //     DTD:  2560x1440  180.000000 Hz  16:9    274.500 kHz    746.640000 MHz (aspect 16:9, no 3D stereo)
    //                Hfront   48 Hsync  32 Hback   80 Hpol N
    //                Vfront    3 Vsync   5 Vback   77 Vpol N
    @Test("Type I: the MAG274Q's fourth record, 10 kHz units")
    func typeIMAG274Q() {
        let record = EDIDInfoTests.hexBytes("a7230104ff099f002f001f009f05540002000400")
        let mode = EDIDDisplayIDTimingDecoders.typeIorVII(Self.slice(record), clockUnitHz: 10_000, block: 2, index: 3, embeddedInCTA: false)
        #expect(Self.shape(mode) == Self.expected(2560, 1440, hTotal: 2720, vTotal: 1525, kHz: 746_640))
        #expect(mode?.source == .displayID(block: 2, type: .typeI, index: 3, embeddedInCTA: false))
        #expect(mode.map { Int($0.refreshHz.rounded()) } == 180)
    }

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings hg573t42.hex   (EDIDInfoTests.hg573t42Hex)
    //   Video Timing Modes Type 7 - Detailed Timings Data Block:
    //     DTD:  3840x2160  120.000000 Hz  16:9    266.640 kHz   1066.560000 MHz (aspect 16:9, no 3D stereo, preferred)
    //                Hfront   48 Hsync  32 Hback   80 Hpol P
    //                Vfront    3 Vsync   5 Vback   54 Vpol N
    @Test("Type VII: the HG573T42's first record, 1 kHz units")
    func typeVIIHG573T42() {
        let record = EDIDInfoTests.hexBytes("3f461084ff0e9f002f801f006f083d0002000400")
        let mode = EDIDDisplayIDTimingDecoders.typeIorVII(Self.slice(record), clockUnitHz: 1_000, block: 2, index: 0, embeddedInCTA: false)
        #expect(Self.shape(mode) == Self.expected(3840, 2160, hTotal: 4000, vTotal: 2222, kHz: 1_066_560))
        #expect(mode?.source == .displayID(block: 2, type: .typeVII, index: 0, embeddedInCTA: false))
    }

    @Test("Type VII: a revision 2 record with extra bytes decodes the same as its first 20")
    func typeVIIExtraBytesIgnored() {
        let record = EDIDInfoTests.hexBytes("3f461084ff0e9f002f801f006f083d0002000400") + [0xAB, 0xCD]
        let mode = EDIDDisplayIDTimingDecoders.typeIorVII(Self.slice(record), clockUnitHz: 1_000, block: 1, index: 0, embeddedInCTA: true)
        #expect(Self.shape(mode) == Self.expected(3840, 2160, hTotal: 4000, vTotal: 2222, kHz: 1_066_560))
        #expect(mode?.source == .displayID(block: 1, type: .typeVII, index: 0, embeddedInCTA: true))
    }

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings synth-v1.hex
    //   Video Timing Modes Type 1 - Detailed Timings Data Block:
    //     DTD:  1920x1080i  60.000000 Hz  16:9     33.750 kHz     74.250000 MHz (aspect 16:9, no 3D stereo)
    //                Hfront   88 Hsync  44 Hback  148 Hpol N
    //                Vfront    2 Vsync   5 Vback   15 Vpol N Vfront +0.5 Odd Field
    //                Vfront    2 Vsync   5 Vback   15 Vpol N Vback  +0.5 Even Field
    // The record's vblank is 45 (bytes 14-15 = 0x002C, plus 1); the frame total is 1080 + 45.
    @Test("Type I: an interlaced record keeps the frame height and frame total, field rate 60 Hz")
    func typeIInterlaced() {
        let mode = EDIDDisplayIDTimingDecoders.typeIorVII(Self.slice(Self.typeIInterlaced), clockUnitHz: 10_000, block: 1, index: 0, embeddedInCTA: false)
        #expect(Self.shape(mode) == Self.expected(1920, 1080, hTotal: 2200, vTotal: 1125, kHz: 74_250, interlaced: true))
        #expect(mode.map { Int($0.refreshHz.rounded()) } == 60)
    }

    // edid-decode's parse_displayid_type_1_7_timing: "Pixel Clock (%.3f MP/s) exceeds maximum (16,777.216 MP/s)."
    // Bytes 0-2 = 0xFFFFFF in 10 kHz units is 167,772,160 kHz: no mode is carried for it.
    @Test("Type I: a pixel clock above 16,777,216 kHz is rejected")
    func typeIPixelClockCap() {
        var record = Self.typeIInterlaced
        record[0] = 0xFF; record[1] = 0xFF; record[2] = 0xFF
        #expect(EDIDDisplayIDTimingDecoders.typeIorVII(Self.slice(record), clockUnitHz: 10_000, block: 1, index: 0, embeddedInCTA: false) == nil)
    }

    @Test("Type I / VII: a short slice returns nil")
    func typeIShort() {
        let record = Array(Self.typeIInterlaced.prefix(19))
        #expect(EDIDDisplayIDTimingDecoders.typeIorVII(Self.slice(record), clockUnitHz: 10_000, block: 1, index: 0, embeddedInCTA: false) == nil)
        #expect(EDIDDisplayIDTimingDecoders.typeIorVII(Self.slice(record), clockUnitHz: 1_000, block: 1, index: 0, embeddedInCTA: false) == nil)
    }

    // MARK: - Type II

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings synth-v1.hex
    //   Video Timing Modes Type 2 - Detailed Timings Data Block:
    //     DTD:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz (aspect 16:9, no 3D stereo)
    //                Hfront   88 Hsync  40 Hback  152 Hpol N
    //                Vfront    4 Vsync   5 Vback   36 Vpol P
    @Test("Type II: 11-byte record, 1920x1080 at 148.5 MHz")
    func typeII() {
        let mode = EDIDDisplayIDTimingDecoders.typeII(Self.slice(Self.typeII), block: 1, index: 0)
        #expect(Self.shape(mode) == Self.expected(1920, 1080, hTotal: 2200, vTotal: 1125, kHz: 148_500))
        #expect(mode?.source == .displayID(block: 1, type: .typeII, index: 0, embeddedInCTA: false))
    }

    @Test("Type II: a short slice returns nil")
    func typeIIShort() {
        #expect(EDIDDisplayIDTimingDecoders.typeII(Self.slice(Array(Self.typeII.prefix(10))), block: 1, index: 0) == nil)
    }

    // MARK: - Type III

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings synth-v1.hex
    //   Video Timing Modes Type 3 - Short Timings Data Block:
    //     CVT:  1920x1080   59.933878 Hz  16:9     66.587 kHz    138.500000 MHz (RB, aspect 16:9)
    //                Hfront   48 Hsync  32 Hback   80 Hpol P
    //                Vfront    3 Vsync   5 Vback   23 Vpol N
    @Test("Type III: 16:9 CVT reduced blanking v1, 1920 wide at 60 Hz")
    func typeIIIReducedBlanking() {
        let mode = EDIDDisplayIDTimingDecoders.typeIII(Self.slice(Self.typeIIIReduced), block: 1, index: 0)
        #expect(Self.shape(mode) == Self.expected(1920, 1080, hTotal: 2080, vTotal: 1111, kHz: 138_500))
        #expect(mode?.source == .displayID(block: 1, type: .typeIII, index: 0, embeddedInCTA: false))
    }

    //     CVT:  1680x1050   59.954250 Hz  16:10    65.290 kHz    146.250000 MHz (aspect 16:10)
    //                Hfront  104 Hsync 176 Hback  280 Hpol N
    //                Vfront    3 Vsync   6 Vback   30 Vpol P
    @Test("Type III: 16:10 CVT standard blanking, 1680 wide at 60 Hz")
    func typeIIIStandardBlanking() {
        let mode = EDIDDisplayIDTimingDecoders.typeIII(Self.slice(Self.typeIIIStandard), block: 1, index: 1)
        #expect(Self.shape(mode) == Self.expected(1680, 1050, hTotal: 2240, vTotal: 1089, kHz: 146_250))
        #expect(mode?.source == .displayID(block: 1, type: .typeIII, index: 1, embeddedInCTA: false))
    }

    @Test("Type III: a short slice returns nil")
    func typeIIIShort() {
        #expect(EDIDDisplayIDTimingDecoders.typeIII(Self.slice([0x14, 0xEF]), block: 1, index: 0) == nil)
    }

    // MARK: - Type IV / VIII

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings synth-v2.hex
    //   Video Timing Modes Type 8 - Enumerated Timing Codes Data Block:
    //     DMT 0x52:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz
    //                     Hfront   88 Hsync  44 Hback  148 Hpol P
    //                     Vfront    4 Vsync   5 Vback   36 Vpol P
    @Test("Type VIII: code type 0 resolves DMT 0x52 from the table")
    func typeVIIIDMT() {
        let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(codeType: 0, id: 0x52, type: .typeVIII, block: 1, index: 0, embeddedInCTA: false)
        #expect(Self.shape(mode) == Self.expected(1920, 1080, hTotal: 2200, vTotal: 1125, kHz: 148_500))
        #expect(mode?.source == .displayID(block: 1, type: .typeVIII, index: 0, embeddedInCTA: false))
    }

    //   Video Timing Modes Type 8 - Enumerated Timing Codes Data Block:
    //     VIC  97:  3840x2160   60.000000 Hz  16:9    135.000 kHz    594.000000 MHz
    //                    Hfront  176 Hsync  88 Hback  296 Hpol P
    //                    Vfront    8 Vsync  10 Vback   72 Vpol P
    @Test("Type IV: code type 1 resolves VIC 97 from the table")
    func typeIVVIC() {
        let mode = EDIDDisplayIDTimingDecoders.typeIVorVIII(codeType: 1, id: 97, type: .typeIV, block: 1, index: 2, embeddedInCTA: true)
        #expect(Self.shape(mode) == Self.expected(3840, 2160, hTotal: 4400, vTotal: 2250, kHz: 594_000))
        #expect(mode?.source == .displayID(block: 1, type: .typeIV, index: 2, embeddedInCTA: true))
    }

    //   Video Timing Modes Type 8 - Enumerated Timing Codes Data Block:
    //     HDMI VIC 1:  3840x2160   30.000000 Hz  16:9     67.500 kHz    297.000000 MHz
    // No HDMI VIC table is bundled and no mode is fabricated for it (plan ruling 9).
    @Test("Type VIII: code type 2 (HDMI VIC 1) yields no mode")
    func typeVIIIHDMIVIC() {
        #expect(EDIDDisplayIDTimingDecoders.typeIVorVIII(codeType: 2, id: 1, type: .typeVIII, block: 1, index: 0, embeddedInCTA: false) == nil)
    }

    @Test("Type IV / VIII: an id missing from the table yields no mode")
    func typeIVUnknownID() {
        #expect(EDIDDisplayIDTimingDecoders.typeIVorVIII(codeType: 0, id: 0, type: .typeIV, block: 1, index: 0, embeddedInCTA: false) == nil)
        #expect(EDIDDisplayIDTimingDecoders.typeIVorVIII(codeType: 1, id: 0, type: .typeIV, block: 1, index: 0, embeddedInCTA: false) == nil)
        #expect(EDIDDisplayIDTimingDecoders.typeIVorVIII(codeType: 3, id: 0x52, type: .typeIV, block: 1, index: 0, embeddedInCTA: false) == nil)
    }

    // MARK: - Type V

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings synth-v1.hex
    //   Video Timing Modes Type 5 - Short Timings Data Block:
    //     CVT:  2560x1440   59.999898 Hz  16:9     88.860 kHz    234.590000 MHz (RBv2, aspect 16:9, no 3D stereo)
    //                Hfront    8 Hsync  32 Hback   40 Hpol P
    //                Vfront   27 Vsync   8 Vback    6 Vpol N
    @Test("Type V: 2560x1440 at 60 Hz, CVT reduced blanking v2")
    func typeV() {
        let mode = EDIDDisplayIDTimingDecoders.typeV(Self.slice(Self.typeV), block: 1, index: 0)
        #expect(Self.shape(mode) == Self.expected(2560, 1440, hTotal: 2640, vTotal: 1481, kHz: 234_590))
        #expect(mode?.source == .displayID(block: 1, type: .typeV, index: 0, embeddedInCTA: false))
    }

    @Test("Type V: a short slice returns nil")
    func typeVShort() {
        #expect(EDIDDisplayIDTimingDecoders.typeV(Self.slice(Array(Self.typeV.prefix(6))), block: 1, index: 0) == nil)
    }

    // MARK: - Type VI

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings synth-v1.hex
    //   Video Timing Modes Type 6 - Detailed Timings Data Block:
    //     DTD:  1920x1080   60.000000 Hz  16:9     67.500 kHz    148.500000 MHz (aspect 16:9, no 3D stereo)
    //                Hfront   88 Hsync  44 Hback  148 Hpol N
    //                Vfront    4 Vsync   5 Vback   36 Vpol N
    @Test("Type VI: 14-byte record, 1920x1080 at 148.5 MHz in 1 kHz units")
    func typeVI14Bytes() {
        let mode = EDIDDisplayIDTimingDecoders.typeVI(Self.slice(Self.typeVI14), block: 1, index: 0)
        #expect(Self.shape(mode) == Self.expected(1920, 1080, hTotal: 2200, vTotal: 1125, kHz: 148_500))
        #expect(mode?.source == .displayID(block: 1, type: .typeVI, index: 0, embeddedInCTA: false))
    }

    //     DTD:  2560x1440   59.950550 Hz  16:9     88.787 kHz    241.500000 MHz (aspect 16:9, no 3D stereo, 701 mm x 352 mm)
    //                Hfront   48 Hsync  32 Hback   80 Hpol N
    //                Vfront    3 Vsync   5 Vback   33 Vpol N
    @Test("Type VI: 17-byte record (x2 bit 6 set), 2560x1440 at 241.5 MHz")
    func typeVI17Bytes() {
        let mode = EDIDDisplayIDTimingDecoders.typeVI(Self.slice(Self.typeVI17), block: 1, index: 1)
        #expect(Self.shape(mode) == Self.expected(2560, 1440, hTotal: 2720, vTotal: 1481, kHz: 241_500))
        #expect(mode?.source == .displayID(block: 1, type: .typeVI, index: 1, embeddedInCTA: false))
    }

    @Test("Type VI: a short slice returns nil")
    func typeVIShort() {
        #expect(EDIDDisplayIDTimingDecoders.typeVI(Self.slice(Array(Self.typeVI14.prefix(13))), block: 1, index: 0) == nil)
    }

    // MARK: - Type IX

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings synth-v2.hex
    //   Video Timing Modes Type 9 - Formula-based Timings Data Block:
    //     CVT:  2560x1440   59.999898 Hz  16:9     88.860 kHz    234.590000 MHz (RBv2, aspect 16:9, no 3D stereo)
    //                Hfront    8 Hsync  32 Hback   40 Hpol P
    //                Vfront   27 Vsync   8 Vback    6 Vpol N
    @Test("Type IX: formula 2 is CVT reduced blanking v2")
    func typeIXReducedV2() {
        let record = Array(Self.typeIX[0..<6])
        let mode = EDIDDisplayIDTimingDecoders.typeIX(Self.slice(record), block: 1, index: 0)
        #expect(Self.shape(mode) == Self.expected(2560, 1440, hTotal: 2640, vTotal: 1481, kHz: 234_590))
        #expect(mode?.source == .displayID(block: 1, type: .typeIX, index: 0, embeddedInCTA: false))
    }

    //     CVT:  3840x2160   59.996625 Hz  16:9    133.312 kHz    533.250000 MHz (RB, aspect 16:9, no 3D stereo)
    //                Hfront   48 Hsync  32 Hback   80 Hpol P
    //                Vfront    3 Vsync   5 Vback   54 Vpol N
    @Test("Type IX: formula 1 is CVT reduced blanking v1")
    func typeIXReducedV1() {
        let record = Array(Self.typeIX[6..<12])
        let mode = EDIDDisplayIDTimingDecoders.typeIX(Self.slice(record), block: 1, index: 1)
        #expect(Self.shape(mode) == Self.expected(3840, 2160, hTotal: 4000, vTotal: 2222, kHz: 533_250))
    }

    //     CVT:  1920x1200   59.884600 Hz  16:10    74.556 kHz    193.250000 MHz (aspect 16:10, no 3D stereo)
    //                Hfront  136 Hsync 200 Hback  336 Hpol N
    //                Vfront    3 Vsync   6 Vback   36 Vpol P
    @Test("Type IX: formula 0 is CVT standard blanking")
    func typeIXStandard() {
        let record = Array(Self.typeIX[12..<18])
        let mode = EDIDDisplayIDTimingDecoders.typeIX(Self.slice(record), block: 1, index: 2)
        #expect(Self.shape(mode) == Self.expected(1920, 1200, hTotal: 2592, vTotal: 1245, kHz: 193_250))
    }

    @Test("Type IX: a short slice returns nil")
    func typeIXShort() {
        #expect(EDIDDisplayIDTimingDecoders.typeIX(Self.slice(Array(Self.typeIX.prefix(5))), block: 1, index: 0) == nil)
    }

    // MARK: - Type X

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings xiaomi.hex
    // (research/customer-probes/m4_macos27.0_h/33_displayport_capability.json, Metadata.EDID, 384 bytes;
    // the same five records sit in synth-v2.hex and print identically there)
    //   Video Timing Modes Type 10 - Formula-based Timings Data Block:
    //     CVT:  3840x2160  143.987684 Hz  16:9    333.188 kHz   1332.750000 MHz (RB, aspect 16:9, no 3D stereo)
    //                Hfront   48 Hsync  32 Hback   80 Hpol P
    //                Vfront    3 Vsync   5 Vback  146 Vpol N
    //     CVT:  2560x1440  159.944203 Hz  16:9    248.713 kHz    676.500000 MHz (RB, aspect 16:9, no 3D stereo)
    //                Hfront   48 Hsync  32 Hback   80 Hpol P
    //                Vfront    3 Vsync   5 Vback  107 Vpol N
    //     CVT:  2560x1440  143.973257 Hz  16:9    222.151 kHz    604.250000 MHz (RB, aspect 16:9, no 3D stereo)
    //                Hfront   48 Hsync  32 Hback   80 Hpol P
    //                Vfront    3 Vsync   5 Vback   95 Vpol N
    //     CVT:  1920x1080  159.875955 Hz  16:9    189.933 kHz    507.500000 MHz (aspect 16:9, no 3D stereo)
    //                Hfront  168 Hsync 208 Hback  376 Hpol N
    //                Vfront    3 Vsync   5 Vback  100 Vpol P
    //     CVT:  1920x1080  143.881735 Hz  16:9    169.349 kHz    452.500000 MHz (aspect 16:9, no 3D stereo)
    //                Hfront  168 Hsync 208 Hback  376 Hpol N
    //                Vfront    3 Vsync   5 Vback   89 Vpol P
    @Test("Type X: the Xiaomi Mi Monitor's five 6-byte records (RBv1 and standard CVT)")
    func typeXXiaomi() {
        let expected = [
            Self.expected(3840, 2160, hTotal: 4000, vTotal: 2314, kHz: 1_332_750),
            Self.expected(2560, 1440, hTotal: 2720, vTotal: 1555, kHz: 676_500),
            Self.expected(2560, 1440, hTotal: 2720, vTotal: 1543, kHz: 604_250),
            Self.expected(1920, 1080, hTotal: 2672, vTotal: 1188, kHz: 507_500),
            Self.expected(1920, 1080, hTotal: 2672, vTotal: 1177, kHz: 452_500),
        ]
        for i in 0..<5 {
            let record = Array(Self.typeXXiaomi[(i * 6)..<(i * 6 + 6)])
            let mode = EDIDDisplayIDTimingDecoders.typeX(Self.slice(record), recordSize: 6, block: 2, index: i, embeddedInCTA: false)
            #expect(Self.shape(mode) == expected[i], "record \(i)")
            #expect(mode?.source == .displayID(block: 2, type: .typeX, index: i, embeddedInCTA: false), "record \(i)")
        }
    }

    // edid-decode-bin --skip-hex-dump --skip-sha --long-timings synth-v2.hex
    //   Video Timing Modes Type 10 - Formula-based Timings Data Block:
    //     CVT:  3840x2160  240.000042 Hz  16:9    567.600 kHz   2279.482000 MHz (RBv3,h-blank-160, aspect 16:9, no 3D stereo, hblank is 160 pixels, early-vsync, delta-hblank=2, add-vblank=60)
    //                Hfront    8 Hsync  32 Hback  136 Hpol P
    //                Vfront   95 Vsync   8 Vback  102 Vpol N
    @Test("Type X: 8-byte RBv3 record with hblank 160, early vsync, delta hblank 2, add vblank 3 and the 300 us minimum")
    func typeXReducedV3Alternate() {
        let record = Array(Self.typeXReducedV3[0..<8])
        let mode = EDIDDisplayIDTimingDecoders.typeX(Self.slice(record), recordSize: 8, block: 1, index: 0, embeddedInCTA: false)
        #expect(Self.shape(mode) == Self.expected(3840, 2160, hTotal: 4016, vTotal: 2365, kHz: 2_279_482))
        #expect(mode?.source == .displayID(block: 1, type: .typeX, index: 0, embeddedInCTA: false))
    }

    //     CVT:  2560x1440  360.000068 Hz  16:9    631.080 kHz   1701.392000 MHz (RBv3, aspect 16:9, no 3D stereo, delta-hblank=7, add-vblank=35)
    //                Hfront    8 Hsync  32 Hback   96 Hpol P
    //                Vfront  299 Vsync   8 Vback    6 Vpol N
    @Test("Type X: 8-byte RBv3 record with hblank 80, a 9-bit refresh (360 Hz), delta hblank 7, add vblank 1")
    func typeXReducedV3NineBitRefresh() {
        let record = Array(Self.typeXReducedV3[8..<16])
        let mode = EDIDDisplayIDTimingDecoders.typeX(Self.slice(record), recordSize: 8, block: 1, index: 1, embeddedInCTA: false)
        #expect(Self.shape(mode) == Self.expected(2560, 1440, hTotal: 2696, vTotal: 1753, kHz: 1_701_392))
    }

    //     CVT:  1920x1080   59.939694 Hz  16:9     66.593 kHz    133.186000 MHz (RBv2,video-optimized, aspect 16:9, no 3D stereo, refresh rate * (1000/1001) supported)
    //                Hfront    8 Hsync  32 Hback   40 Hpol P
    //                Vfront   17 Vsync   8 Vback    6 Vpol N
    @Test("Type X: RBv2 with bit 4 is video optimised (1000/1001)")
    func typeXReducedV2VideoOptimised() {
        let record = Array(Self.typeXReducedV3[16..<24])
        let mode = EDIDDisplayIDTimingDecoders.typeX(Self.slice(record), recordSize: 8, block: 1, index: 2, embeddedInCTA: false)
        #expect(Self.shape(mode) == Self.expected(1920, 1080, hTotal: 2000, vTotal: 1111, kHz: 133_186))
    }

    //     CVT:  1920x1080  120.000354 Hz  16:9    137.280 kHz    284.445000 MHz (RBv3,h-blank-160, aspect 16:9, no 3D stereo, hblank is 160 pixels, delta-hblank=6)
    //                Hfront    8 Hsync  32 Hback  112 Hpol P
    //                Vfront   50 Vsync   8 Vback    6 Vpol N
    @Test("Type X: RBv3 with hblank 160 and delta hblank 6 lands on 152 pixels")
    func typeXReducedV3DeltaAboveFive() {
        let record = Array(Self.typeXReducedV3[24..<32])
        let mode = EDIDDisplayIDTimingDecoders.typeX(Self.slice(record), recordSize: 8, block: 1, index: 3, embeddedInCTA: false)
        #expect(Self.shape(mode) == Self.expected(1920, 1080, hTotal: 2072, vTotal: 1144, kHz: 284_445))
    }

    @Test("Type X: a slice shorter than the record size, or a record size outside 6 to 8, returns nil")
    func typeXShort() {
        let record = Array(Self.typeXXiaomi[0..<6])
        #expect(EDIDDisplayIDTimingDecoders.typeX(Self.slice(Array(record.prefix(5))), recordSize: 6, block: 1, index: 0, embeddedInCTA: false) == nil)
        #expect(EDIDDisplayIDTimingDecoders.typeX(Self.slice(record), recordSize: 8, block: 1, index: 0, embeddedInCTA: false) == nil)
        #expect(EDIDDisplayIDTimingDecoders.typeX(Self.slice(record + [0, 0, 0]), recordSize: 9, block: 1, index: 0, embeddedInCTA: false) == nil)
    }
}
