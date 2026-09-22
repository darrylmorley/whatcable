import Testing
@testable import WhatCableCore

@Suite("EDID timing tables")
struct EDIDTimingTablesTests {
    @Test("VIC 97 is 3840x2160 at 60 Hz, 4400x2250 total, 594 MHz (CTA-861-H Table 1)")
    func vic97() throws {
        let t = try #require(EDIDTimingTables.vic[97])
        #expect(t.width == 3840 && t.height == 2160)
        #expect(t.hTotal == 4400 && t.vTotal == 2250)
        #expect(t.pixelClockKHz == 594_000)
        #expect(t.interlaced == false)
    }
    @Test("VIC 5 is 1920x1080 interlaced, 2200x1125 total, 74.25 MHz")
    func vic5() throws {
        let t = try #require(EDIDTimingTables.vic[5])
        #expect(t.interlaced == true)
        #expect(t.hTotal == 2200 && t.vTotal == 1125 && t.pixelClockKHz == 74_250)
    }
    @Test("VIC 219 is 4096x2160 at 120 Hz, 1188 MHz; the table has 154 entries (VIC 1-127, 193-219; 128-192 reserved)")
    func vic219() throws {
        let t = try #require(EDIDTimingTables.vic[219])
        #expect(t.width == 4096 && t.pixelClockKHz == 1_188_000)
        // CTA-861-H Table 1 defines no Video Format Timing for VIC 0 or
        // 128-192 (128-192 are "Forbidden" as SVD values); 219 is the
        // highest VIC, not the row count. 127 + (219-193+1) = 154, verified
        // three ways: the PDF text itself, edid-decode's edid_cta_modes1[]
        // (127 entries) + edid_cta_modes2[] (27 entries), and the Linux
        // kernel's edid_cea_modes_1[] + edid_cea_modes_193[] (same 127 + 27).
        #expect(EDIDTimingTables.vic.count == 154)
    }
    @Test("DMT 0x10 is 1024x768 at 60 Hz, 1344x806 total, 65 MHz, standard code 0x6140")
    func dmt10() throws {
        let t = try #require(EDIDTimingTables.dmt[0x10])
        #expect(t.width == 1024 && t.height == 768)
        #expect(t.hTotal == 1344 && t.vTotal == 806 && t.pixelClockKHz == 65_000)
        #expect(t.standardCode == 0x6140)
        #expect(EDIDTimingTables.dmt(standardCode: 0x6140)?.id == 0x10)
    }
    @Test("DMT 0x52 is 1920x1080 at 60 Hz, 2200x1125, 148.5 MHz, standard code 0xD1C0")
    func dmt52() throws {
        let t = try #require(EDIDTimingTables.dmt[0x52])
        #expect(t.hTotal == 2200 && t.vTotal == 1125 && t.pixelClockKHz == 148_500)
        #expect(EDIDTimingTables.dmt(standardCode: 0xD1C0)?.id == 0x52)
        #expect(EDIDTimingTables.dmt(width: 1920, height: 1080, refreshHz: 60, reducedBlanking: false)?.id == 0x52)
    }
    @Test("DMT 0x58 is 4096x2160 at 59.94 Hz RB, 556.188 MHz; the table has 88 entries")
    func dmt58() throws {
        let t = try #require(EDIDTimingTables.dmt[0x58])
        #expect(t.reducedBlanking && t.pixelClockKHz == 556_188)
        #expect(EDIDTimingTables.dmt.count == 88)
    }
}
