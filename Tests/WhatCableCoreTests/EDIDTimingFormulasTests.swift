import Testing
@testable import WhatCableCore

// Every expected value below was produced by edid-decode built from v4l-utils commit
// f341ed8e3742118a86619e5f499017db2de30d94 on this machine. The command and the
// output lines it printed sit above each test. hTotal = hact + Hfront + Hsync + Hback;
// vTotal = vact + Vfront + Vsync + Vback for progressive modes, and for interlaced
// modes the frame total 2 * (vact / 2 + Vfront + Vsync + Vback) + 1, the same
// convention the DMT and VIC tables use (VIC 5 is 1125 lines).
@Suite("EDID timing formulas")
struct EDIDTimingFormulasTests {

    // edid-decode --cvt w=2560,h=1440,fps=60
    // CVT:  2560x1440   59.960627 Hz  16:9     89.521 kHz    312.250000 MHz
    //            Hfront  192 Hsync 272 Hback  464 Hpol N
    //            Vfront    3 Vsync   5 Vback   45 Vpol P
    @Test("CVT standard blanking 2560x1440@60")
    func cvtStandard() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 2560, height: 1440, refreshHz: 60, blanking: .standard))
        #expect(t.pixelClockKHz == 312_250 && t.hTotal == 3488 && t.vTotal == 1493)
    }

    // edid-decode --cvt w=2560,h=1440,fps=60,rb=1
    // CVT:  2560x1440   59.950550 Hz  16:9     88.787 kHz    241.500000 MHz (RB)
    //            Hfront   48 Hsync  32 Hback   80 Hpol P
    //            Vfront    3 Vsync   5 Vback   33 Vpol N
    @Test("CVT reduced blanking v1 2560x1440@60")
    func cvtRB1() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 2560, height: 1440, refreshHz: 60, blanking: .reducedV1))
        #expect(t.pixelClockKHz == 241_500 && t.hTotal == 2720 && t.vTotal == 1481)
    }

    // edid-decode --cvt w=2560,h=1440,fps=60,rb=2
    // CVT:  2560x1440   59.999898 Hz  16:9     88.860 kHz    234.590000 MHz (RBv2)
    //            Hfront    8 Hsync  32 Hback   40 Hpol P
    //            Vfront   27 Vsync   8 Vback    6 Vpol N
    @Test("CVT reduced blanking v2 2560x1440@60")
    func cvtRB2() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 2560, height: 1440, refreshHz: 60, blanking: .reducedV2(videoOptimised: false)))
        #expect(t.pixelClockKHz == 234_590 && t.hTotal == 2640 && t.vTotal == 1481)
    }

    // edid-decode --cvt w=3840,h=2160,fps=120,rb=3
    // CVT:  3840x2160  120.000022 Hz  16:9    274.440 kHz   1075.805000 MHz (RBv3)
    //            Hfront    8 Hsync  32 Hback   40 Hpol P
    //            Vfront  113 Vsync   8 Vback    6 Vpol N
    @Test("CVT reduced blanking v3 3840x2160@120")
    func cvtRB3() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 3840, height: 2160, refreshHz: 120, blanking: .reducedV3(hBlank: 80, vBlankMin: 460, earlyVSync: false, alternate: false)))
        #expect(t.pixelClockKHz == 1_075_805 && t.hTotal == 3920 && t.vTotal == 2287)
    }

    // edid-decode --gtf w=1280,h=1024,fps=85
    // GTF:  1280x1024   85.000000 Hz   5:4     91.375 kHz    159.358000 MHz
    //            Hfront   96 Hsync 136 Hback  232 Hpol N
    //            Vfront    1 Vsync   3 Vback   47 Vpol P
    @Test("GTF 1280x1024@85")
    func gtf() throws {
        let t = try #require(EDIDTimingFormulas.gtf(width: 1280, height: 1024, refreshHz: 85))
        #expect(t.pixelClockKHz == 159_358 && t.hTotal == 1744 && t.vTotal == 1075)
    }

    // edid-decode --gtf w=1600,h=1200,fps=60
    // GTF:  1600x1200   59.999925 Hz   4:3     74.520 kHz    160.963000 MHz
    //            Hfront  104 Hsync 176 Hback  280 Hpol N
    //            Vfront    1 Vsync   3 Vback   38 Vpol P
    @Test("GTF 1600x1200@60")
    func gtf2() throws {
        let t = try #require(EDIDTimingFormulas.gtf(width: 1600, height: 1200, refreshHz: 60))
        #expect(t.pixelClockKHz == 160_963 && t.hTotal == 2160 && t.vTotal == 1242)
    }

    // The secondary curve comes from edid-decode's test/vesa-edid-1.3.test, whose
    // Display Range Limits descriptor decodes as:
    //   GTF Secondary Curve Block: Start frequency: 80 kHz, C: 40.0%, M: 3600%/kHz, K: 128, J: 35.0%
    // 1800x1440@75 is a standard timing in that EDID. Its default-curve horizontal
    // frequency is 112.725 kHz, above the 80 kHz start, so the secondary curve applies:
    // edid-decode --gtf w=1800,h=1440,fps=75,secondary edid-decode-test/vesa-edid-1.3.test
    // GTF:  1800x1440   75.000116 Hz   5:4    112.725 kHz    258.817000 MHz (RB)
    //            Hfront   64 Hsync 184 Hback  248 Hpol P
    //            Vfront    1 Vsync   3 Vback   59 Vpol N
    @Test("GTF secondary curve applies at or above the start frequency")
    func gtfSecondaryAboveStart() throws {
        let curve = EDIDTimingFormulas.GTFSecondaryCurve(c: 40, m: 3600, k: 128, j: 35, startFrequencyKHz: 80)
        let t = try #require(EDIDTimingFormulas.gtf(width: 1800, height: 1440, refreshHz: 75, secondary: curve))
        #expect(t.pixelClockKHz == 258_817 && t.hTotal == 2296 && t.vTotal == 1503)
    }

    // Same EDID, same curve. 1152x864@85 is also a standard timing there; its
    // default-curve horizontal frequency is 77.095 kHz, below the 80 kHz start,
    // so the default curve stands:
    // edid-decode --gtf w=1152,h=864,fps=85,secondary edid-decode-test/vesa-edid-1.3.test
    // GTF:  1152x864    84.999687 Hz   4:3     77.095 kHz    119.651000 MHz
    //            Hfront   72 Hsync 128 Hback  200 Hpol N
    //            Vfront    1 Vsync   3 Vback   39 Vpol P
    @Test("GTF secondary curve is ignored below the start frequency")
    func gtfSecondaryBelowStart() throws {
        let curve = EDIDTimingFormulas.GTFSecondaryCurve(c: 40, m: 3600, k: 128, j: 35, startFrequencyKHz: 80)
        let t = try #require(EDIDTimingFormulas.gtf(width: 1152, height: 864, refreshHz: 85, secondary: curve))
        #expect(t.pixelClockKHz == 119_651 && t.hTotal == 1552 && t.vTotal == 907)
    }

    // edid-decode's --gtf takes fps as the field rate and halves it before calling
    // calc_gtf_mode, so refreshHz here is 30 (the frame rate), as the parse path passes it.
    // edid-decode --gtf w=1920,h=1080,fps=60,interlaced
    // GTF:  1920x1080i  59.999824 Hz  16:9     33.570 kHz     81.642000 MHz
    //            Hfront   64 Hsync 192 Hback  256 Hpol N
    //            Vfront    1 Vsync   3 Vback   15 Vpol P Vfront +0.5 Odd Field
    //            Vfront    1 Vsync   3 Vback   15 Vpol P Vback  +0.5 Even Field
    // Frame total: 2 * (540 + 1 + 3 + 15) + 1 = 1119.
    @Test("GTF interlaced 1920x1080i reports the frame total")
    func gtfInterlaced() throws {
        let t = try #require(EDIDTimingFormulas.gtf(width: 1920, height: 1080, refreshHz: 30, interlaced: true))
        #expect(t.pixelClockKHz == 81_642 && t.hTotal == 2432 && t.vTotal == 1119)
    }

    // edid-decode --cvt w=1920,h=1080,fps=60,interlaced=1
    // (the bare `interlaced` word sets the flag to 0 in this build; the `=1` form is needed)
    // CVT:  1920x1080i  59.941520 Hz  16:9     33.717 kHz     82.000000 MHz
    //            Hfront   64 Hsync 192 Hback  256 Hpol N
    //            Vfront    3 Vsync   5 Vback   14 Vpol P Vfront +0.5 Odd Field
    //            Vfront    3 Vsync   5 Vback   14 Vpol P Vback  +0.5 Even Field
    // Frame total: 2 * (540 + 3 + 5 + 14) + 1 = 1125.
    @Test("CVT interlaced 1920x1080i reports the frame total")
    func cvtInterlaced() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 1920, height: 1080, refreshHz: 30, blanking: .standard, interlaced: true))
        #expect(t.pixelClockKHz == 82_000 && t.hTotal == 2432 && t.vTotal == 1125)
    }

    // The remaining vectors cover the branches of the port the six above do not reach:
    // RBv2 video-optimised, RBv3 with its 160 pixel alternate blank, an explicit
    // hblank, early vsync, a vblank above the 460 us minimum, a width that is not a
    // multiple of 8 (CVT keeps 1366, GTF rounds to 1368), the "custom" aspect ratio
    // vsync of 10, and the RBv1 5:4 aspect vsync of 7.

    // edid-decode --cvt w=1920,h=1080,fps=60,rb=2,alt=1
    // (a bare `alt` sets the flag to 0 in this build, like `interlaced`; `alt=1` is needed)
    // CVT:  1920x1080   59.939694 Hz  16:9     66.593 kHz    133.186000 MHz (RBv2,video-optimized)
    //            Hfront    8 Hsync  32 Hback   40 Hpol P
    //            Vfront   17 Vsync   8 Vback    6 Vpol N
    @Test("CVT reduced blanking v2 video-optimised 1920x1080@60")
    func cvtRB2VideoOptimised() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 1920, height: 1080, refreshHz: 60, blanking: .reducedV2(videoOptimised: true)))
        #expect(t.pixelClockKHz == 133_186 && t.hTotal == 2000 && t.vTotal == 1111)
    }

    // edid-decode --cvt w=3840,h=2160,fps=60,rb=3,alt=1
    // CVT:  3840x2160   60.000000 Hz  16:9    133.320 kHz    533.280000 MHz (RBv3,h-blank-160)
    //            Hfront    8 Hsync  32 Hback  120 Hpol P
    //            Vfront   48 Vsync   8 Vback    6 Vpol N
    // hBlank 0 means "not given", so `alternate` picks the 160 pixel blank.
    @Test("CVT reduced blanking v3 alternate 3840x2160@60")
    func cvtRB3Alternate() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 3840, height: 2160, refreshHz: 60, blanking: .reducedV3(hBlank: 0, vBlankMin: 460, earlyVSync: false, alternate: true)))
        #expect(t.pixelClockKHz == 533_280 && t.hTotal == 4000 && t.vTotal == 2222)
    }

    // edid-decode --cvt w=3840,h=2160,fps=60,rb=3,hblank=120
    // CVT:  3840x2160   60.000091 Hz  16:9    133.320 kHz    527.948000 MHz (RBv3)
    //            Hfront    8 Hsync  32 Hback   80 Hpol P
    //            Vfront   48 Vsync   8 Vback    6 Vpol N
    @Test("CVT reduced blanking v3 explicit hblank 3840x2160@60")
    func cvtRB3HBlank() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 3840, height: 2160, refreshHz: 60, blanking: .reducedV3(hBlank: 120, vBlankMin: 460, earlyVSync: false, alternate: false)))
        #expect(t.pixelClockKHz == 527_948 && t.hTotal == 3960 && t.vTotal == 2222)
    }

    // edid-decode --cvt w=3840,h=2160,fps=144,rb=3,early-vsync
    // CVT:  3840x2160  144.000031 Hz  16:9    333.216 kHz   1306.207000 MHz (RBv3)
    //            Hfront    8 Hsync  32 Hback   40 Hpol P
    //            Vfront   69 Vsync   8 Vback   77 Vpol N
    // Early vsync moves the sync inside the same blank (without it: Vfront 140, Vback 6),
    // so the totals this API exposes are unchanged; the vector proves the branch runs
    // without disturbing them.
    @Test("CVT reduced blanking v3 early vsync 3840x2160@144")
    func cvtRB3EarlyVSync() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 3840, height: 2160, refreshHz: 144, blanking: .reducedV3(hBlank: 0, vBlankMin: 460, earlyVSync: true, alternate: false)))
        #expect(t.pixelClockKHz == 1_306_207 && t.hTotal == 3920 && t.vTotal == 2314)
    }

    // edid-decode --cvt w=3840,h=2160,fps=60,rb=3,vblank=600
    // CVT:  3840x2160   60.000091 Hz  16:9    134.460 kHz    527.084000 MHz (RBv3)
    //            Hfront    8 Hsync  32 Hback   40 Hpol P
    //            Vfront   67 Vsync   8 Vback    6 Vpol N
    @Test("CVT reduced blanking v3 vblank 600us 3840x2160@60")
    func cvtRB3VBlank() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 3840, height: 2160, refreshHz: 60, blanking: .reducedV3(hBlank: 0, vBlankMin: 600, earlyVSync: false, alternate: false)))
        #expect(t.pixelClockKHz == 527_084 && t.hTotal == 3920 && t.vTotal == 2241)
    }

    // edid-decode --cvt w=1366,h=768,fps=60
    // CVT:  1366x768    59.597647 Hz 683:384   47.559 kHz     84.750000 MHz
    //            Hfront   72 Hsync 136 Hback  208 Hpol N
    //            Vfront    3 Vsync  10 Vback   17 Vpol P
    @Test("CVT standard blanking 1366x768@60 keeps the unrounded width")
    func cvtStandard1366() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 1366, height: 768, refreshHz: 60, blanking: .standard))
        #expect(t.pixelClockKHz == 84_750 && t.hTotal == 1782 && t.vTotal == 798)
    }

    // edid-decode --cvt w=1366,h=768,fps=60,rb=2
    // CVT:  1366x768    59.999650 Hz 683:384   47.400 kHz     68.540000 MHz (RBv2)
    //            Hfront    8 Hsync  32 Hback   40 Hpol P
    //            Vfront    8 Vsync   8 Vback    6 Vpol N
    @Test("CVT reduced blanking v2 1366x768@60")
    func cvtRB21366() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 1366, height: 768, refreshHz: 60, blanking: .reducedV2(videoOptimised: false)))
        #expect(t.pixelClockKHz == 68_540 && t.hTotal == 1446 && t.vTotal == 790)
    }

    // edid-decode --gtf w=1366,h=768,fps=60
    // GTF:  1368x768    60.000000 Hz  57:32    47.700 kHz     85.860000 MHz
    //            Hfront   72 Hsync 144 Hback  216 Hpol N
    //            Vfront    1 Vsync   3 Vback   23 Vpol P
    @Test("GTF 1366x768@60 rounds the width to 1368")
    func gtf1366() throws {
        let t = try #require(EDIDTimingFormulas.gtf(width: 1366, height: 768, refreshHz: 60))
        #expect(t.pixelClockKHz == 85_860 && t.hTotal == 1800 && t.vTotal == 795)
    }

    // edid-decode --cvt w=1280,h=1024,fps=75,rb=1
    // CVT:  1280x1024   74.942402 Hz   5:4     79.514 kHz    114.500000 MHz (RB)
    //            Hfront   48 Hsync  32 Hback   80 Hpol P
    //            Vfront    3 Vsync   7 Vback   27 Vpol N
    @Test("CVT reduced blanking v1 1280x1024@75 uses the 5:4 vsync width")
    func cvtRB1FiveFour() throws {
        let t = try #require(EDIDTimingFormulas.cvt(width: 1280, height: 1024, refreshHz: 75, blanking: .reducedV1))
        #expect(t.pixelClockKHz == 114_500 && t.hTotal == 1440 && t.vTotal == 1061)
    }
}
