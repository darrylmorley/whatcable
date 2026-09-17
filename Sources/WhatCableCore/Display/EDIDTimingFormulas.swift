// Ported from edid-decode (v4l-utils, utils/edid-decode/calc-gtf-cvt.cpp,
// commit f341ed8e3742118a86619e5f499017db2de30d94), SPDX-License-Identifier: MIT,
// Copyright 2006-2012 Red Hat, Inc., Copyright 2018-2021 Cisco Systems, Inc.
// The MIT notice is reproduced in THIRD_PARTY_NOTICES.md at the repo root.
// Formulas: VESA Generalized Timing Formula 1.1 and VESA Coordinated Video Timings 1.2 / 2.0.
//
// The port keeps edid-decode's constants, its choice of round / floor / ceil at
// each step, and its integer-vs-floating arithmetic, so the numbers it produces
// are the numbers `edid-decode --gtf` and `edid-decode --cvt` print. Only the
// vertical-refresh input form is ported (edid-decode's gtf_ip_vert_freq); the
// horizontal-frequency and pixel-clock input forms are CLI-only conveniences
// that no EDID field feeds.

public enum EDIDTimingFormulas {
    /// Totals for one computed mode. `vTotal` is the frame total: for interlaced
    /// modes that is twice the field total including the half line each field
    /// carries, so 1080i comes out at 1125 the way VIC 5 does.
    public struct Timing: Hashable, Sendable {
        public let hTotal: Int
        public let vTotal: Int
        public let pixelClockKHz: Int

        public init(hTotal: Int, vTotal: Int, pixelClockKHz: Int) {
            self.hTotal = hTotal
            self.vTotal = vTotal
            self.pixelClockKHz = pixelClockKHz
        }
    }

    /// Which CVT blanking variant to compute (edid-decode's `rb` argument plus its modifiers).
    public enum CVTBlanking: Hashable, Sendable {
        /// CVT standard blanking (rb = RB_NONE).
        case standard
        /// CVT reduced blanking version 1 (rb = RB_CVT_V1).
        case reducedV1
        /// CVT reduced blanking version 2 (rb = RB_CVT_V2); `videoOptimised` is
        /// edid-decode's `alt` for v2: the 1000/1001 rate.
        case reducedV2(videoOptimised: Bool)
        /// CVT reduced blanking version 3 (rb = RB_CVT_V3). `hBlank` is edid-decode's
        /// `rb_h_blank` (0 means not given, so `alternate` picks 160 over 80);
        /// `vBlankMin` is `rb_v_blank` in microseconds; `earlyVSync` is `early_vsync_rqd`;
        /// `alternate` is `alt` for v3: a 160 pixel horizontal blank.
        case reducedV3(hBlank: Int, vBlankMin: Int, earlyVSync: Bool, alternate: Bool)
    }

    /// The Secondary GTF curve from an EDID Display Range Limits descriptor
    /// (0xFD, byte 10 = 0x02). `c`, `j` are percentages already halved from the
    /// byte (`x[13] / 2.0`, `x[17] / 2.0`); `m` is the 16-bit gradient; `k` the
    /// scaling byte; `startFrequencyKHz` is `x[12] * 2`.
    public struct GTFSecondaryCurve: Hashable, Sendable {
        public let c: Double
        public let m: Double
        public let k: Double
        public let j: Double
        public let startFrequencyKHz: Int

        public init(c: Double, m: Double, k: Double, j: Double, startFrequencyKHz: Int) {
            self.c = c
            self.m = m
            self.k = k
            self.j = j
            self.startFrequencyKHz = startFrequencyKHz
        }
    }

    // MARK: - GTF

    private static let cellGran = 8.0
    private static let marginPerc = 1.8
    private static let gtfMinPorch = 1.0
    private static let gtfVSyncRqd = 3.0
    private static let gtfHSyncPerc = 8.0
    private static let gtfMinVSyncBP = 550.0

    /// GTF (VESA Generalized Timing Formula 1.1) timing for the given active size and
    /// refresh. `refreshHz` is what edid-decode's parse path hands `calc_gtf_mode`:
    /// the frame rate. For interlaced modes the field rate is twice that (edid-decode's
    /// `--gtf` CLI halves the `fps` it is given before calling the formula).
    ///
    /// With `secondary` set, the default curve is computed first; if its horizontal
    /// frequency (`pixelClockKHz / hTotal`) is at or above `startFrequencyKHz` the mode
    /// is recomputed with the secondary parameters. That is the rule edid-decode's
    /// `--gtf ...,secondary <edid>` applies (edid-decode.cpp, the `options[OptGTF]`
    /// block after `preparse_base_block`), and VESA GTF 1.1 section 4.3's.
    ///
    /// Returns nil when the formula has no finite answer for the inputs: a non-finite
    /// intermediate, a horizontal blanking or total that is not above zero, or a figure
    /// outside `Int`. A curve with K = 0 and J = 100% (C' = 100, duty cycle 100%) is one such
    /// input. Nil is "no timing", never a substitute; the caller records the fact it holds
    /// (a standard timing id, a CVT code) as undecoded.
    public static func gtf(
        width: Int, height: Int, refreshHz: Double, interlaced: Bool = false,
        secondary: GTFSecondaryCurve? = nil
    ) -> Timing? {
        guard let primary = calcGTFMode(
            hPixels: width, vLines: height, ipFreqRqd: refreshHz, intRqd: interlaced,
            c: 40, m: 600, k: 128, j: 20
        ) else { return nil }
        guard let secondary else { return primary }
        let horFreqKHz = Double(primary.pixelClockKHz) / Double(primary.hTotal)
        guard horFreqKHz >= Double(secondary.startFrequencyKHz) else { return primary }
        return calcGTFMode(
            hPixels: width, vLines: height, ipFreqRqd: refreshHz, intRqd: interlaced,
            c: secondary.c, m: secondary.m, k: secondary.k, j: secondary.j
        )
    }

    /// `calc_gtf_mode` for `ip_parm == gtf_ip_vert_freq`, `margins_rqd == false`. Nil where
    /// edid-decode's C would carry an inf / NaN through to its integer conversions (see `gtf`).
    private static func calcGTFMode(
        hPixels: Int, vLines: Int, ipFreqRqd: Double, intRqd: Bool,
        c: Double, m: Double, k: Double, j: Double
    ) -> Timing? {
        /* C' and M' are part of the Blanking Duty Cycle computation */
        let cPrime = ((c - j) * k / 256.0) + j
        let mPrime = k / 256.0 * m

        let hPixelsRnd = (Double(hPixels) / cellGran).rounded() * cellGran
        let vLinesRnd = intRqd ? (Double(vLines) / 2.0).rounded() : Double(vLines)
        let horMargin = 0.0
        let vertMargin = 0.0
        let interlace = intRqd ? 0.5 : 0.0
        let totalActivePixels = hPixelsRnd + horMargin * 2

        // vertical frame frequency (Hz)
        let vFieldRateRqd = intRqd ? ipFreqRqd * 2 : ipFreqRqd
        let hPeriodEst = ((1.0 / vFieldRateRqd) - gtfMinVSyncBP / 1_000_000.0)
            / (vLinesRnd + vertMargin * 2 + gtfMinPorch + interlace) * 1_000_000.0
        let vSyncBP = (gtfMinVSyncBP / hPeriodEst).rounded()
        let totalVLines = vLinesRnd + vertMargin * 2 + vSyncBP + interlace + gtfMinPorch
        let vFieldRateEst = 1.0 / hPeriodEst / totalVLines * 1_000_000.0
        let hPeriod = hPeriodEst / (vFieldRateRqd / vFieldRateEst)
        let idealDutyCycle = cPrime - (mPrime * hPeriod / 1000.0)
        let hBlankPixels = (totalActivePixels * idealDutyCycle / (100.0 - idealDutyCycle) / (2 * cellGran)).rounded()
            * 2 * cellGran
        let totalPixels = totalActivePixels + hBlankPixels
        let pixelFreq = totalPixels / hPeriod

        let vBackPorch = vSyncBP - gtfVSyncRqd

        guard hBlankPixels > 0, totalPixels > 0, hPeriod > 0,
              let vbp = exactInt(vBackPorch),
              let pixclkKHz = exactInt((1000.0 * pixelFreq).rounded()),
              let hsync = exactInt((gtfHSyncPerc / 100.0 * totalPixels / cellGran).rounded() * cellGran),
              let halfBlank = exactInt(hBlankPixels / 2.0),
              let hact = exactInt(hPixelsRnd), let vactField = exactInt(vLinesRnd)
        else { return nil }
        let vsync = Int(gtfVSyncRqd)
        let vfp = Int(gtfMinPorch)
        let hfp = halfBlank - hsync
        let hbp = hfp + hsync
        let hborder = Int(horMargin)
        let vborder = Int(vertMargin)

        return timing(
            hact: hact, vactField: vactField, interlaced: intRqd,
            hfp: hfp, hsync: hsync, hbp: hbp, hborder: hborder,
            vfp: vfp, vsync: vsync, vbp: vbp, vborder: vborder,
            pixclkKHz: pixclkKHz
        )
    }

    // MARK: - CVT

    private static let cvtMinVSyncBP = 550.0
    private static let cvtMinVPorch = 3.0
    /* Minimum vertical backporch for CVT and CVT RBv1 */
    private static let cvtMinVBPorch = 7.0
    /* Fixed vertical backporch for CVT RBv2 and RBv3 */
    private static let cvtFixedVBPorch = 6.0
    private static let cvtCPrime = 30.0
    private static let cvtMPrime = 300.0
    private static let cvtRBMinVBlank = 460.0
    private static let cvtRBAltMinVBlank = 300.0

    private enum RB: Int, Comparable {
        case none = 0, cvtV1 = 1, cvtV2 = 2, cvtV3 = 3
        static func < (lhs: RB, rhs: RB) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// CVT (VESA Coordinated Video Timings 1.2 / 2.0) timing for the given active size,
    /// refresh and blanking variant. `refreshHz` is what edid-decode's parse path hands
    /// `calc_cvt_mode`: the frame rate. For interlaced modes the field rate is twice that
    /// (edid-decode's `--cvt` CLI halves the `fps` it is given before calling the formula).
    ///
    /// Nil on the same terms as `gtf`: a non-finite intermediate, a horizontal blanking or
    /// total that is not above zero, or a figure outside `Int`. Nil is "no timing"; the CVT
    /// code or DisplayID record it came from yields no mode.
    public static func cvt(
        width: Int, height: Int, refreshHz: Double, blanking: CVTBlanking, interlaced: Bool = false
    ) -> Timing? {
        switch blanking {
        case .standard:
            return calcCVTMode(
                hPixels: width, vLines: height, ipFreqRqd: refreshHz, rb: .none, intRqd: interlaced,
                alt: false, rbHBlank: 0, rbVBlank: 460, earlyVSyncRqd: false
            )
        case .reducedV1:
            return calcCVTMode(
                hPixels: width, vLines: height, ipFreqRqd: refreshHz, rb: .cvtV1, intRqd: interlaced,
                alt: false, rbHBlank: 0, rbVBlank: 460, earlyVSyncRqd: false
            )
        case .reducedV2(let videoOptimised):
            return calcCVTMode(
                hPixels: width, vLines: height, ipFreqRqd: refreshHz, rb: .cvtV2, intRqd: interlaced,
                alt: videoOptimised, rbHBlank: 0, rbVBlank: 460, earlyVSyncRqd: false
            )
        case .reducedV3(let hBlank, let vBlankMin, let earlyVSync, let alternate):
            return calcCVTMode(
                hPixels: width, vLines: height, ipFreqRqd: refreshHz, rb: .cvtV3, intRqd: interlaced,
                alt: alternate, rbHBlank: hBlank, rbVBlank: vBlankMin, earlyVSyncRqd: earlyVSync
            )
        }
    }

    /// `calc_cvt_mode` with `margins_rqd == false`.
    // If rb == RB_CVT_V2, then alt means video-optimized (i.e. 59.94 instead of 60 Hz, etc.).
    // If rb == RB_CVT_V3, then alt means that rb_h_blank is 160 instead of 80.
    private static func calcCVTMode(
        hPixels: Int, vLines: Int, ipFreqRqd: Double, rb: RB, intRqd: Bool,
        alt: Bool, rbHBlank: Int, rbVBlank rbVBlankIn: Int, earlyVSyncRqd: Bool
    ) -> Timing? {
        let hact = hPixels
        let vact = vLines

        var rbVBlank = rbVBlankIn
        if rb == .cvtV3 {
            if Double(rbVBlank) < cvtRBAltMinVBlank {
                rbVBlank = Int(cvtRBAltMinVBlank)
            } else if Double(rbVBlank) > cvtRBAltMinVBlank + 140,
                      Double(rbVBlank) < cvtRBMinVBlank {
                rbVBlank = Int(cvtRBMinVBlank)
            } else if Double(rbVBlank) > cvtRBMinVBlank + 460 {
                rbVBlank = Int(cvtRBMinVBlank + 460)
            }
        }

        let cellGran = rb == .cvtV2 ? 1.0 : Self.cellGran
        let hPixelsRnd = (Double(hPixels) / cellGran).rounded(.down) * cellGran
        let vLinesRnd = intRqd ? (Double(vLines) / 2.0).rounded(.down) : Double(vLines)
        let horMargin = 0.0
        let vertMargin = 0.0
        let interlace = intRqd ? 0.5 : 0.0
        let totalActivePixels = hPixelsRnd + horMargin * 2
        let vFieldRateRqd = intRqd ? ipFreqRqd * 2 : ipFreqRqd
        let clockStep = rb >= .cvtV2 ? 0.001 : 0.25
        var hBlank = (rb == .cvtV1 || (rb == .cvtV3 && alt)) ? 160.0 : 80.0
        let rbVFPorch = rb == .cvtV1 ? 3.0 : 1.0
        let refreshMultiplier = (rb == .cvtV2 && alt) ? 1000.0 / 1001.0 : 1.0
        let rbMinVBlank = rb == .cvtV3 ? Double(rbVBlank) : cvtRBMinVBlank
        var hSync = 32.0

        var vSync: Double
        var pixelFreq: Double
        var vBlank: Double
        var vSyncBP: Double

        if rb == .cvtV3 && rbHBlank != 0 {
            hBlank = Double(rbHBlank & ~7)
            if hBlank < 80 {
                hBlank = 80
            } else if hBlank > 200 {
                hBlank = 200
            }
        }

        /* Determine VSync Width from aspect ratio */
        if (vact * 4 / 3) == hact {
            vSync = 4
        } else if (vact * 16 / 9) == hact {
            vSync = 5
        } else if (vact * 16 / 10) == hact {
            vSync = 6
        } else if (vact % 4) == 0 && ((vact * 5 / 4) == hact) {
            vSync = 7
        } else if (vact * 15 / 9) == hact {
            vSync = 7
        } else {                        /* Custom */
            vSync = 10
        }

        if rb >= .cvtV2 {
            vSync = 8
        }

        if rb == .none {
            let hPeriodEst = ((1.0 / vFieldRateRqd) - cvtMinVSyncBP / 1_000_000.0)
                / (vLinesRnd + vertMargin * 2 + cvtMinVPorch + interlace) * 1_000_000.0
            vSyncBP = (cvtMinVSyncBP / hPeriodEst).rounded(.down) + 1
            if vSyncBP < vSync + cvtMinVBPorch {
                vSyncBP = vSync + cvtMinVBPorch
            }
            vBlank = vSyncBP + cvtMinVPorch
            var idealDutyCycle = cvtCPrime - (cvtMPrime * hPeriodEst / 1000.0)
            if idealDutyCycle < 20 {
                idealDutyCycle = 20
            }
            hBlank = (totalActivePixels * idealDutyCycle / (100.0 - idealDutyCycle) / (2 * Self.cellGran)).rounded(.down)
                * 2 * Self.cellGran
            let totalPixels = totalActivePixels + hBlank
            hSync = (totalPixels * 0.08 / Self.cellGran).rounded(.down) * Self.cellGran
            pixelFreq = ((totalPixels / hPeriodEst) / clockStep).rounded(.down) * clockStep
        } else {
            let hPeriodEst = ((1_000_000.0 / vFieldRateRqd) - rbMinVBlank) / (vLinesRnd + vertMargin * 2)
            let vbiLines = (rbMinVBlank / hPeriodEst).rounded(.down) + 1
            var rbVBPorch = (rb == .cvtV1 ? cvtMinVBPorch : cvtFixedVBPorch)
            let rbMinVBI = rbVFPorch + vSync + rbVBPorch
            vBlank = vbiLines < rbMinVBI ? rbMinVBI : vbiLines
            let totalVLines = vBlank + vLinesRnd + vertMargin * 2 + interlace
            if rb == .cvtV3 && earlyVSyncRqd {
                rbVBPorch = (vbiLines / 2.0).rounded(.down)
                if vBlank - rbVBPorch - vSync < rbVFPorch {
                    rbVBPorch = vBlank - vSync - rbVFPorch
                }
            }
            if rb == .cvtV1 {
                vSyncBP = vBlank - rbVFPorch
            } else {
                vSyncBP = vSync + rbVBPorch
            }
            let totalPixels = hBlank + totalActivePixels
            let freq = vFieldRateRqd * totalVLines * totalPixels * refreshMultiplier
            if rb == .cvtV3 {
                pixelFreq = ((freq / 1_000_000.0) / clockStep).rounded(.up) * clockStep
            } else {
                pixelFreq = ((freq / 1_000_000.0) / clockStep).rounded(.down) * clockStep
            }
        }

        guard hBlank > 0, hBlank + totalActivePixels > 0,
              let vbp = exactInt(vSyncBP - vSync),
              let vsync = exactInt(vSync),
              let vBlankLines = exactInt(vBlank),
              let pixclkKHz = exactInt((1000.0 * pixelFreq).rounded()),
              let hsync = exactInt(hSync),
              let hBlankPixels = exactInt(hBlank),
              let halfBlank = exactInt(hBlank / 2.0),
              let vactField = exactInt(vLinesRnd)
        else { return nil }
        let vfp = vBlankLines - vbp - vsync
        let hfp: Int
        if rb >= .cvtV2 {
            hfp = 8
        } else {
            hfp = halfBlank - hsync
        }
        let hbp = hBlankPixels - hfp - hsync
        let hborder = Int(horMargin)
        let vborder = Int(vertMargin)

        return timing(
            hact: hact, vactField: vactField, interlaced: intRqd,
            hfp: hfp, hsync: hsync, hbp: hbp, hborder: hborder,
            vfp: vfp, vsync: vsync, vbp: vbp, vborder: vborder,
            pixclkKHz: pixclkKHz
        )
    }

    // MARK: - Totals

    /// `Int(d)` without the trap: nil when `d` is not finite or its magnitude is 2^53 or
    /// more. `Int(Double)` aborts the process on inf, NaN and out-of-range input, and an EDID
    /// can steer the formulas there (a secondary GTF curve with K = 0 and J = 100% gives an
    /// infinite horizontal blanking), so every conversion goes through here. The 2^53 bound is
    /// the last integer a `Double` represents exactly, and keeps the handful of additions
    /// `timing(...)` performs on the results inside `Int` with room to spare.
    private static func exactInt(_ d: Double) -> Int? {
        guard d.isFinite, d.magnitude < 9_007_199_254_740_992.0 else { return nil }
        return Int(d)
    }

    /// Folds edid-decode's per-field porches into the totals the model carries.
    /// `hTotal` is `hact + hfp + hsync + hbp + 2 * hborder`, as edid-decode's
    /// `print_timings` computes it. For progressive modes `vTotal` is
    /// `vact + vfp + vsync + vbp + 2 * vborder`. For interlaced modes edid-decode's
    /// field total is `vact / 2 + vblank + 0.5` (the half line each field carries);
    /// the frame is two fields, so `vTotal = 2 * (vactField + vblank) + 1`.
    private static func timing(
        hact: Int, vactField: Int, interlaced: Bool,
        hfp: Int, hsync: Int, hbp: Int, hborder: Int,
        vfp: Int, vsync: Int, vbp: Int, vborder: Int,
        pixclkKHz: Int
    ) -> Timing {
        let hTotal = hact + hfp + hsync + hbp + 2 * hborder
        let vBlank = vfp + vsync + vbp + 2 * vborder
        let vTotal = interlaced ? 2 * (vactField + vBlank) + 1 : vactField + vBlank
        return Timing(hTotal: hTotal, vTotal: vTotal, pixelClockKHz: pixclkKHz)
    }
}
