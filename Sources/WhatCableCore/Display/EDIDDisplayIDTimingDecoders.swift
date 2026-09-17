import Foundation

/// Decoders for the ten DisplayID timing record layouts. Each takes one record's own bytes
/// (`x[x.startIndex]` is byte 0 of the record) and returns the mode it declares, or nil when
/// the slice is too short or the record is invalid. No walking happens here: the DisplayID
/// section walker and the CTA-861 embedded-DisplayID walker both call these.
///
/// Byte layouts follow edid-decode (v4l-utils, utils/edid-decode/parse-displayid-block.cpp,
/// commit f341ed8e3742118a86619e5f499017db2de30d94, MIT), function by function; each decoder
/// names the one it mirrors. Only the fields that reach `EDIDMode` are read: aspect codes,
/// stereo bits, sync polarities, the preferred flag and the Type VI image size are declared
/// facts the model has no slot for, so nothing is made of them here.
///
/// Interlaced records (Types I, II, VI carry a flag) keep `height` as the frame's active lines
/// and `vTotal` as `vact + vblank`, both straight off the record; `EDIDMode.refreshHz` doubles
/// the frame rate to give the field rate edid-decode prints. edid-decode itself halves the
/// three vertical porches with integer division and adds the half line back, which lands on
/// the same field rate whenever the porches are even; the record's own vblank is the fact.
public enum EDIDDisplayIDTimingDecoders {
    /// Type I (tag 0x03, DisplayID 1.x, 10 kHz clock units) and Type VII (tag 0x22, DisplayID 2.x,
    /// 1 kHz units). 20 bytes, plus 0 to 7 extra bytes for Type VII revision 2 records (block
    /// revision nibble bits 6-4) which are not read. `parse_displayid_type_1_7_timing`.
    ///
    /// Byte 3 bit 4 is the interlaced flag. A pixel clock above 16,777,216 kHz is the value
    /// edid-decode records as exceeding the format's maximum; no mode is carried for it.
    public static func typeIorVII(
        _ x: ArraySlice<UInt8>, clockUnitHz: Int, block: Int, index: Int, embeddedInCTA: Bool
    ) -> EDIDMode? {
        guard x.count >= 20 else { return nil }
        let type: EDIDMode.DisplayIDTimingType
        switch clockUnitHz {
        case 10_000: type = .typeI
        case 1_000: type = .typeVII
        default: return nil
        }
        let b = Array(x.prefix(20))
        let clockUnits = 1 + (Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16)
        let pixelClockKHz = clockUnits * clockUnitHz / 1000
        guard pixelClockKHz <= 16_777_216 else { return nil }
        let hact = 1 + (Int(b[4]) | Int(b[5]) << 8)
        let hblank = 1 + (Int(b[6]) | Int(b[7]) << 8)
        let vact = 1 + (Int(b[12]) | Int(b[13]) << 8)
        let vblank = 1 + (Int(b[14]) | Int(b[15]) << 8)
        let interlaced = b[3] & 0x10 != 0
        return EDIDMode(
            width: hact, height: vact, hTotal: hact + hblank, vTotal: vact + vblank,
            pixelClockHz: clockUnits * clockUnitHz, interlaced: interlaced,
            source: .displayID(block: block, type: type, index: index, embeddedInCTA: embeddedInCTA)
        )
    }

    /// Whether a Type I / Type VII record declares itself the preferred timing: byte 3 bit 7,
    /// read only when the data block's revision is below 2. In revision 2 the same bit means
    /// YCbCr 4:2:0 instead, so edid-decode's `parse_displayid_type_1_7_timing` guards it with
    /// `if (block_rev < 2 && (x[3] & 0x80))`. `revisionByte` is the data block's whole byte 1;
    /// the revision is its low three bits (`parse_displayid_data_block`: `block_rev = x[1] &
    /// 0x07`), bits 3 to 6 are per-block flags (a Type VII block's DSC pass-through bit and its
    /// extra-bytes count), so a revision byte of 0x09 is revision 1 and still flags. A
    /// CTA-embedded Type VII (`cta_displayid_type_7`) is always decoded as revision 2 there, so
    /// it never declares a preference. Separate from `typeIorVII` so its signature and every
    /// existing caller stay as they are.
    public static func typeIorVIIPreferredFlag(_ x: ArraySlice<UInt8>, revisionByte: UInt8) -> Bool {
        guard x.count >= 4, revisionByte & 0x07 < 2 else { return false }
        return x[x.startIndex + 3] & 0x80 != 0
    }

    /// Type II (tag 0x04), 11 bytes, 10 kHz clock units. Horizontal values are in 8-pixel
    /// steps with an 8 offset; vertical values are 1-based. `parse_displayid_type_2_timing`.
    public static func typeII(_ x: ArraySlice<UInt8>, block: Int, index: Int) -> EDIDMode? {
        guard x.count >= 11 else { return nil }
        let b = Array(x.prefix(11))
        let clockUnits = 1 + (Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16)
        let hact = 8 + 8 * (Int(b[4]) | (Int(b[5]) & 0x01) << 8)
        let hblank = 8 + 8 * ((Int(b[5]) & 0xFE) >> 1)
        let vact = 1 + (Int(b[7]) | (Int(b[8]) & 0x0F) << 8)
        let vblank = 1 + Int(b[9])
        let interlaced = b[3] & 0x10 != 0
        return EDIDMode(
            width: hact, height: vact, hTotal: hact + hblank, vTotal: vact + vblank,
            pixelClockHz: clockUnits * 10_000, interlaced: interlaced,
            source: .displayID(block: block, type: .typeII, index: index, embeddedInCTA: false)
        )
    }

    /// Type III (tag 0x05), 3 bytes, CVT formula. Byte 0 bits 3-0 are the aspect code the
    /// height is derived from, bits 6-4 equal to 1 select CVT reduced blanking v1 (anything
    /// else is standard blanking); byte 1 is the width in 8-pixel steps with an 8 offset; byte 2
    /// bits 6-0 are the refresh minus 1. `parse_displayid_type_3_timing`.
    public static func typeIII(_ x: ArraySlice<UInt8>, block: Int, index: Int) -> EDIDMode? {
        guard x.count >= 3 else { return nil }
        let b = Array(x.prefix(3))
        let (hratio, vratio) = aspectRatio(code: b[0] & 0x0F)
        let blanking: EDIDTimingFormulas.CVTBlanking = ((b[0] & 0x70) >> 4) == 1 ? .reducedV1 : .standard
        let hact = 8 + 8 * Int(b[1])
        let vact = hact * vratio / hratio
        let refresh = 1 + Int(b[2] & 0x7F)
        return cvtMode(
            width: hact, height: vact, refreshHz: refresh, blanking: blanking,
            source: .displayID(block: block, type: .typeIII, index: index, embeddedInCTA: false)
        )
    }

    /// Type IV (tag 0x06) and Type VIII (tag 0x23): a DMT id, a VIC or an HDMI VIC
    /// (`codeType` 0, 1, 2). `parse_displayid_type_4_8_timing`. HDMI VICs (code type 2) have
    /// no bundled table, so no mode is carried for them; an id missing from the DMT or VIC
    /// table likewise yields nothing.
    public static func typeIVorVIII(
        codeType: UInt8, id: Int, type: EDIDMode.DisplayIDTimingType, block: Int, index: Int, embeddedInCTA: Bool
    ) -> EDIDMode? {
        let source = EDIDMode.Source.displayID(block: block, type: type, index: index, embeddedInCTA: embeddedInCTA)
        switch codeType {
        case 0:
            guard let dmt = EDIDTimingTables.dmt[id] else { return nil }
            return EDIDMode(
                width: dmt.width, height: dmt.height, hTotal: dmt.hTotal, vTotal: dmt.vTotal,
                pixelClockHz: dmt.pixelClockKHz * 1000, interlaced: dmt.interlaced, source: source
            )
        case 1:
            guard let vic = EDIDTimingTables.vic[id] else { return nil }
            return EDIDMode(
                width: vic.width, height: vic.height, hTotal: vic.hTotal, vTotal: vic.vTotal,
                pixelClockHz: vic.pixelClockKHz * 1000, interlaced: vic.interlaced, source: source
            )
        default:
            return nil
        }
    }

    /// Type V (tag 0x11), 7 bytes, always CVT reduced blanking v2 (edid-decode computes RBv2
    /// whatever byte 0 bits 1-0 say, noting the other values as unexpected or invalid).
    /// `parse_displayid_type_5_timing`.
    public static func typeV(_ x: ArraySlice<UInt8>, block: Int, index: Int) -> EDIDMode? {
        guard x.count >= 7 else { return nil }
        let b = Array(x.prefix(7))
        let hact = 1 + (Int(b[2]) | Int(b[3]) << 8)
        let vact = 1 + (Int(b[4]) | Int(b[5]) << 8)
        let refresh = 1 + Int(b[6])
        return cvtMode(
            width: hact, height: vact, refreshHz: refresh, blanking: .reducedV2(videoOptimised: false),
            source: .displayID(block: block, type: .typeV, index: index, embeddedInCTA: false)
        )
    }

    /// Type VI (tag 0x13), 14 bytes, or 17 when byte 2 bit 6 says the image-size bytes follow;
    /// only the first 14 carry timing. 1 kHz clock units. `parse_displayid_type_6_timing`.
    public static func typeVI(_ x: ArraySlice<UInt8>, block: Int, index: Int) -> EDIDMode? {
        guard x.count >= 14 else { return nil }
        let b = Array(x.prefix(14))
        let pixelClockKHz = 1 + (Int(b[0]) | Int(b[1]) << 8 | (Int(b[2]) & 0x3F) << 16)
        let hact = 1 + (Int(b[3]) | (Int(b[4]) & 0x3F) << 8)
        let vact = 1 + (Int(b[5]) | (Int(b[6]) & 0x3F) << 8)
        let hblank = 1 + (Int(b[7]) | (Int(b[9]) & 0x0F) << 8)
        let vblank = 1 + Int(b[11])
        let interlaced = b[13] & 0x80 != 0
        return EDIDMode(
            width: hact, height: vact, hTotal: hact + hblank, vTotal: vact + vblank,
            pixelClockHz: pixelClockKHz * 1000, interlaced: interlaced,
            source: .displayID(block: block, type: .typeVI, index: index, embeddedInCTA: false)
        )
    }

    /// Type IX (tag 0x24), 6 bytes, CVT. Byte 0 bits 2-0: 1 is reduced blanking v1, 2 is v2,
    /// anything else standard blanking. `parse_displayid_type_9_timing`.
    public static func typeIX(_ x: ArraySlice<UInt8>, block: Int, index: Int) -> EDIDMode? {
        guard x.count >= 6 else { return nil }
        let b = Array(x.prefix(6))
        let hact = 1 + (Int(b[1]) | Int(b[2]) << 8)
        let vact = 1 + (Int(b[3]) | Int(b[4]) << 8)
        let refresh = 1 + Int(b[5])
        let blanking: EDIDTimingFormulas.CVTBlanking
        switch b[0] & 0x07 {
        case 1: blanking = .reducedV1
        case 2: blanking = .reducedV2(videoOptimised: false)
        default: blanking = .standard
        }
        return cvtMode(
            width: hact, height: vact, refreshHz: refresh, blanking: blanking,
            source: .displayID(block: block, type: .typeIX, index: index, embeddedInCTA: false)
        )
    }

    /// Type X (tag 0x2A), 6 to 8 bytes (`recordSize` = 6 + the block revision nibble bits 6-4),
    /// CVT. `parse_displayid_type_10_timing`, whose argument mapping is mirrored exactly:
    ///
    /// - byte 0 bits 2-0: 1 RBv1, 2 RBv2, 3 RBv3, else standard blanking;
    /// - byte 0 bit 4: with RBv2 the video-optimised (1000/1001) rate, with RBv3 a 160 pixel
    ///   horizontal blank in place of 80;
    /// - byte 0 bit 3: with RBv3, early vsync;
    /// - refresh is 1 + byte 5, plus byte 6 bits 1-0 as bits 9-8 when the record is longer than 6;
    /// - byte 7 bit 0 (8-byte records only): the 300 us minimum vertical blank instead of 460 us;
    /// - with RBv3 and a record longer than 6: byte 6 bits 4-2 are the horizontal blank delta
    ///   (`80 + 8 * delta` from an 80 base; `160 + 8 * delta` for delta 0 to 5 and
    ///   `160 - 8 * (delta - 5)` above that from a 160 base), and byte 6 bits 7-5 add
    ///   `20 us` (300 us base) or `35 us` (460 us base) each to the minimum vertical blank.
    public static func typeX(
        _ x: ArraySlice<UInt8>, recordSize: Int, block: Int, index: Int, embeddedInCTA: Bool
    ) -> EDIDMode? {
        guard (6...8).contains(recordSize), x.count >= recordSize else { return nil }
        let b = Array(x.prefix(recordSize))
        let hact = 1 + (Int(b[1]) | Int(b[2]) << 8)
        let vact = 1 + (Int(b[3]) | Int(b[4]) << 8)
        let formula = b[0] & 0x07
        let alternate = b[0] & 0x10 != 0
        let earlyVSync = b[0] & 0x08 != 0
        let refresh = 1 + Int(b[5]) + (recordSize == 6 ? 0 : (Int(b[6]) & 0x03) << 8)

        let blanking: EDIDTimingFormulas.CVTBlanking
        switch formula {
        case 1:
            blanking = .reducedV1
        case 2:
            blanking = .reducedV2(videoOptimised: alternate)
        case 3:
            var hBlank = alternate ? 160 : 80
            let altMinVBlank = recordSize >= 8 && b[7] & 0x01 != 0
            var vBlankMin = altMinVBlank ? 300 : 460
            if recordSize > 6 {
                let deltaHBlank = (Int(b[6]) >> 2) & 0x07
                if hBlank == 80 {
                    hBlank = 80 + 8 * deltaHBlank
                } else if deltaHBlank <= 5 {
                    hBlank = 160 + 8 * deltaHBlank
                } else {
                    hBlank = 160 - (deltaHBlank - 5) * 8
                }
                vBlankMin += ((Int(b[6]) >> 5) & 0x07) * (altMinVBlank ? 20 : 35)
            }
            blanking = .reducedV3(hBlank: hBlank, vBlankMin: vBlankMin, earlyVSync: earlyVSync, alternate: alternate)
        default:
            blanking = .standard
        }
        return cvtMode(
            width: hact, height: vact, refreshHz: refresh, blanking: blanking,
            source: .displayID(block: block, type: .typeX, index: index, embeddedInCTA: embeddedInCTA)
        )
    }

    // MARK: - Shared

    /// The DisplayID aspect-ratio code table shared by Types I, VII and III
    /// (`parse_displayid_type_1_7_timing` and `parse_displayid_type_3_timing`). Code 8 is
    /// "undefined" and codes 9 to 15 are reserved; edid-decode's Type III derives the height
    /// from 1:1 for both, and that is what a Type III record with such a code yields here.
    private static func aspectRatio(code: UInt8) -> (h: Int, v: Int) {
        switch code {
        case 1: return (5, 4)
        case 2: return (4, 3)
        case 3: return (15, 9)
        case 4: return (16, 9)
        case 5: return (16, 10)
        case 6: return (64, 27)
        case 7: return (256, 135)
        default: return (1, 1)
        }
    }

    /// Nil when the CVT formula has no finite timing for the record's figures: the record
    /// yields no mode, and nothing is put in its place.
    private static func cvtMode(
        width: Int, height: Int, refreshHz: Int, blanking: EDIDTimingFormulas.CVTBlanking, source: EDIDMode.Source
    ) -> EDIDMode? {
        guard let t = EDIDTimingFormulas.cvt(width: width, height: height, refreshHz: Double(refreshHz), blanking: blanking) else { return nil }
        return EDIDMode(
            width: width, height: height, hTotal: t.hTotal, vTotal: t.vTotal,
            pixelClockHz: t.pixelClockKHz * 1000, interlaced: false, source: source
        )
    }
}
