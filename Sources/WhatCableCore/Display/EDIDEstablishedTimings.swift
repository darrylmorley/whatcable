// Established Timings I, II and III: the two small fixed-bitmap tables the
// EDID base block declares support for, distinct from every other mode
// format because the bit position alone names the mode: no byte payload to
// decode, just "is this DMT (or legacy pre-DMT) timing supported, yes/no".
//
// Ported from edid-decode (v4l-utils, utils/edid-decode/parse-base-block.cpp,
// commit f341ed8e3742118a86619e5f499017db2de30d94), SPDX-License-Identifier: MIT,
// Copyright 2006-2012 Red Hat, Inc., Copyright 2018-2020 Cisco Systems, Inc.
// The MIT notice is reproduced in THIRD_PARTY_NOTICES.md at the repo root.
// The four non-DMT ("legacy") rows are themselves copied in edid-decode from
// the Linux kernel's drm_edid.c (the 1152x870 Apple row instead from the
// kernel's macmodes.c, since drm_edid.c's version is a different, 1152x864,
// format) -- numeric cross-check only, no table or code taken from the kernel.

public enum EDIDEstablishedTimings {
    /// One Established Timings I/II bit: byte 35, 36 or 37 of the base block, bit 7 down to 0.
    /// `dmtID` is set when the bit names a DMT timing (look it up in `EDIDTimingTables.dmt`);
    /// the four bits with `dmtID == nil` are pre-DMT IBM/Apple modes edid-decode carries its own
    /// totals for, reproduced here (`hTotal`/`vTotal`/`pixelClockKHz`) since no DMT entry holds them.
    /// `interlaced` comes from the DMT entry (DMT 0x0F, byte 36 bit 4, is 1024x768i at 87 Hz);
    /// the four legacy rows are progressive.
    public struct Legacy {
        public let byte: Int
        public let bit: Int
        public let dmtID: Int?
        public let width: Int
        public let height: Int
        public let hTotal: Int
        public let vTotal: Int
        public let pixelClockKHz: Int
        public let interlaced: Bool

        public init(byte: Int, bit: Int, dmtID: Int?, width: Int, height: Int, hTotal: Int, vTotal: Int, pixelClockKHz: Int, interlaced: Bool) {
            self.byte = byte
            self.bit = bit
            self.dmtID = dmtID
            self.width = width
            self.height = height
            self.hTotal = hTotal
            self.vTotal = vTotal
            self.pixelClockKHz = pixelClockKHz
            self.interlaced = interlaced
        }
    }

    /// The 17 Established Timings I/II bits, byte 35 bit 7 down to byte 37 bit 7 (byte 37's
    /// remaining bits 6...0 are manufacturer-reserved and carry no entry here). DMT-numbered
    /// rows borrow their totals from `EDIDTimingTables.dmt` so the two tables cannot drift;
    /// the four legacy rows carry edid-decode's own totals (hTotal = hact + hfp + hsync + hbp,
    /// vTotal = vact + vfp + vsync + vbp, from parse-base-block.cpp's `established_timings12[]`).
    public static let legacy: [Legacy] = [
        // Byte 35, bit 7...0.
        Legacy(byte: 35, bit: 7, dmtID: nil, width: 720, height: 400, hTotal: 900, vTotal: 449, pixelClockKHz: 28_320, interlaced: false), // IBM 720x400@70
        Legacy(byte: 35, bit: 6, dmtID: nil, width: 720, height: 400, hTotal: 900, vTotal: 449, pixelClockKHz: 35_500, interlaced: false), // IBM 720x400@88
        Self.dmtLegacy(byte: 35, bit: 5, dmtID: 0x04),
        Legacy(byte: 35, bit: 4, dmtID: nil, width: 640, height: 480, hTotal: 864, vTotal: 525, pixelClockKHz: 30_240, interlaced: false), // Apple 640x480@67
        Self.dmtLegacy(byte: 35, bit: 3, dmtID: 0x05),
        Self.dmtLegacy(byte: 35, bit: 2, dmtID: 0x06),
        Self.dmtLegacy(byte: 35, bit: 1, dmtID: 0x08),
        Self.dmtLegacy(byte: 35, bit: 0, dmtID: 0x09),
        // Byte 36, bit 7...0.
        Self.dmtLegacy(byte: 36, bit: 7, dmtID: 0x0A),
        Self.dmtLegacy(byte: 36, bit: 6, dmtID: 0x0B),
        Legacy(byte: 36, bit: 5, dmtID: nil, width: 832, height: 624, hTotal: 1152, vTotal: 667, pixelClockKHz: 57_284, interlaced: false), // Apple 832x624@75
        Self.dmtLegacy(byte: 36, bit: 4, dmtID: 0x0F),
        Self.dmtLegacy(byte: 36, bit: 3, dmtID: 0x10),
        Self.dmtLegacy(byte: 36, bit: 2, dmtID: 0x11),
        Self.dmtLegacy(byte: 36, bit: 1, dmtID: 0x12),
        Self.dmtLegacy(byte: 36, bit: 0, dmtID: 0x24),
        // Byte 37, bit 7 only; bits 6...0 are manufacturer-reserved.
        Legacy(byte: 37, bit: 7, dmtID: nil, width: 1152, height: 870, hTotal: 1456, vTotal: 915, pixelClockKHz: 100_000, interlaced: false), // Apple 1152x870@75
    ]

    /// Build a `Legacy` row from a DMT table entry so its totals can never drift from
    /// `EDIDTimingTables.dmt`. Crashes at process start (a `static let` runs once) if the id
    /// is missing from the table, which would mean the table and this list have gone out of sync.
    private static func dmtLegacy(byte: Int, bit: Int, dmtID: Int) -> Legacy {
        guard let dmt = EDIDTimingTables.dmt[dmtID] else {
            preconditionFailure("EDIDEstablishedTimings.legacy names DMT 0x\(String(dmtID, radix: 16)), which is not in EDIDTimingTables.dmt")
        }
        return Legacy(
            byte: byte, bit: bit, dmtID: dmtID,
            width: dmt.width, height: dmt.height,
            hTotal: dmt.hTotal, vTotal: dmt.vTotal, pixelClockKHz: dmt.pixelClockKHz,
            interlaced: dmt.interlaced)
    }

    /// Established Timings III (EDID 1.4, descriptor tag 0xF7): 44 DMT ids, one per bit of
    /// descriptor bytes 6...11, bit 7 first (`established_timings3_dmt_ids[]`,
    /// parse-base-block.cpp). Bits 44...47 (the low 4 bits of descriptor byte 11) are reserved
    /// and have no entry here.
    public static let iiiDMTIDs: [Int] = [
        // Descriptor byte 6, bit 7...0.
        0x01, 0x02, 0x03, 0x07, 0x0E, 0x0C, 0x13, 0x15,
        // Descriptor byte 7, bit 7...0.
        0x16, 0x17, 0x18, 0x19, 0x20, 0x21, 0x23, 0x25,
        // Descriptor byte 8, bit 7...0.
        0x27, 0x2E, 0x2F, 0x30, 0x31, 0x29, 0x2A, 0x2B,
        // Descriptor byte 9, bit 7...0.
        0x2C, 0x39, 0x3A, 0x3B, 0x3C, 0x33, 0x34, 0x35,
        // Descriptor byte 10, bit 7...0.
        0x36, 0x37, 0x3E, 0x3F, 0x41, 0x42, 0x44, 0x45,
        // Descriptor byte 11, bit 7...4.
        0x46, 0x47, 0x49, 0x4A,
    ]
}
