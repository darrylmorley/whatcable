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

    @Test("Parses the monitor name and EDID version")
    func parsesNameAndVersion() throws {
        let edid = try #require(EDIDInfo(Data(Self.g34wBaseBlock)))
        #expect(edid.monitorName == "LEN G34w-10")
        #expect(edid.versionMajor == 1)
        #expect(edid.versionMinor == 3)
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
}
