import Foundation
import Testing
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

/// `DisplayTimingReader` without IOKit: the parse and the match are pure
/// functions over the property dictionaries the display node publishes.
/// Shapes and values are the corpus's (`m3_macos26.6.2`, the 27C1U-L behind a
/// DisplayPort 1.2 adapter, timing 45), transcribed by hand.
@Suite("DisplayTimingReader")
struct DisplayTimingReaderTests {

    // MARK: - Fixtures

    /// The first 24 bytes of the 27C1U-L's EDID: header, "IOC" (0x25E3),
    /// product 0xFFFF, serial 0, week 34 of 2023 (0x22, 0x21), EDID 1.3,
    /// 0x80 digital, 60 x 34 cm, gamma 0x78.
    private static let edid27C1UL = Data([
        0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00,
        0x25, 0xe3, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
        0x22, 0x21, 0x01, 0x03, 0x80, 0x3c, 0x22, 0x78,
    ])

    /// A Dell with a real serial in bytes 12-15 (corpus `m1_macos15.7.7_e`,
    /// EDID UUID `10AC6540-0000-0000-1E14-0104B5402878`): macOS zeroes the
    /// serial in the UUID, so the key must too.
    private static let edidDellWithSerial = Data([
        0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00,
        0x10, 0xac, 0x65, 0x40, 0x4c, 0x34, 0x38, 0x30,
        0x1e, 0x14, 0x01, 0x04, 0xb5, 0x40, 0x28, 0x78,
    ])

    private static func colourMode(id: Int, encoding: Int, depth: Int, virtual: Bool = false, supportsDSC: Int = 0, downstream: [String: Any]? = nil) -> [String: Any] {
        var entry: [String: Any] = ["ID": NSNumber(value: id), "PixelEncoding": NSNumber(value: encoding),
                                    "Depth": NSNumber(value: depth), "IsVirtual": NSNumber(value: virtual),
                                    "SupportsDSC": NSNumber(value: supportsDSC)]
        if let downstream { entry["DownstreamFormat"] = downstream }
        return entry
    }

    /// Timing 45 as the node publishes it: 3840x2160 in 3910x2250 totals,
    /// PreciseSyncRate 3932160 = 60.0 Hz in 16.16, 8-bit RGB and 4:4:4 (plus
    /// two virtual 12-bit HDR entries), no mode DSC-capable, the DSC list
    /// empty, all six IDs unsafe (a DP 1.2 HDMI converter), ValidPixelEncodings 0x1b4d.
    private static func timing45(colourModes: [[String: Any]]? = nil) -> [String: Any] {
        ["ID": NSNumber(value: 45), "IsInterlaced": NSNumber(value: false), "IsVirtual": NSNumber(value: false),
         "HorizontalAttributes": ["Total": NSNumber(value: 3910), "Active": NSNumber(value: 3840)] as [String: Any],
         "VerticalAttributes": ["Total": NSNumber(value: 2250), "Active": NSNumber(value: 2160),
                                "PreciseSyncRate": NSNumber(value: 3932160)] as [String: Any],
         "ColorModes": colourModes ?? [
            colourMode(id: 90, encoding: 0, depth: 8), colourMode(id: 89, encoding: 0, depth: 8),
            colourMode(id: 91, encoding: 3, depth: 8), colourMode(id: 92, encoding: 3, depth: 8),
            colourMode(id: 10, encoding: 2, depth: 12, virtual: true), colourMode(id: 11, encoding: 6, depth: 12, virtual: true),
         ],
         "DSCRequiredColorElementIDs": [] as [Any],
         "UnsafeColorElementIDs": [90, 89, 91, 92, 10, 11].map { NSNumber(value: $0) },
         "ValidPixelEncodings": NSNumber(value: 6989)]
    }

    /// A 720p60 entry with 8 and 10 bit RGB colour modes, ID 15, both DSC-capable and both listed.
    private static let timing15: [String: Any] = [
        "ID": NSNumber(value: 15), "IsInterlaced": NSNumber(value: false), "IsVirtual": NSNumber(value: false),
        "HorizontalAttributes": ["Total": NSNumber(value: 1650), "Active": NSNumber(value: 1280)] as [String: Any],
        "VerticalAttributes": ["Total": NSNumber(value: 750), "Active": NSNumber(value: 720),
                               "PreciseSyncRate": NSNumber(value: 3932160)] as [String: Any],
        "ColorModes": [colourMode(id: 90, encoding: 0, depth: 8, supportsDSC: 1), colourMode(id: 93, encoding: 0, depth: 10, supportsDSC: 1)],
        "DSCRequiredColorElementIDs": [90, 93].map { NSNumber(value: $0) },
        "UnsafeColorElementIDs": [] as [Any],
        "ValidPixelEncodings": NSNumber(value: 6989),
    ]

    /// m1_macos26.5_o (MSI MP273 behind an HDMI converter, flat rendering,
    /// node-level ColorElements entry [10]): a 4:4:4 8-bit mode, ID 5, whose
    /// DownstreamFormat is YCbCr 4:2:0 at 8 bits, ID 4. The flat rendering
    /// prints IsVirtual as `<type 21>`; the tree-rendered twins of this entry
    /// (m2pro_macos26.6.1 timing 57, IDs 85 and 87) are non-virtual, so the
    /// fixture takes false.
    private static let downstreamMode5: [String: Any] = colourMode(
        id: 5, encoding: 3, depth: 8, supportsDSC: 0,
        downstream: ["ElementType": NSNumber(value: 1), "Depth": NSNumber(value: 8), "PixelEncoding": NSNumber(value: 1),
                     "EOTF": NSNumber(value: 0), "Colorimetry": NSNumber(value: 1), "StandardType": NSNumber(value: 2),
                     "SupportsDSC": NSNumber(value: 0), "DynamicRange": NSNumber(value: 1), "ID": NSNumber(value: 4),
                     "IsVirtual": NSNumber(value: false)] as [String: Any])

    /// m2pro_macos26.6.1, DELL S2721QS behind a cHDMIb converter, timing 57:
    /// 3840x2160 in 4400x2250 at 60.0 Hz (594 MHz), nine colour modes, three
    /// of them (5 virtual, 87, 85) carrying a 4:2:0 downstream format at 8
    /// bits, DSC list empty, unsafe [77, 76, 78, 79, 10, 11], ValidPixelEncodings 0x1b4f.
    private static let timing57: [String: Any] = [
        "ID": NSNumber(value: 57), "IsInterlaced": NSNumber(value: false), "IsVirtual": NSNumber(value: false),
        "HorizontalAttributes": ["Total": NSNumber(value: 4400), "Active": NSNumber(value: 3840)] as [String: Any],
        "VerticalAttributes": ["Total": NSNumber(value: 2250), "Active": NSNumber(value: 2160),
                               "PreciseSyncRate": NSNumber(value: 3932160)] as [String: Any],
        "ColorModes": [
            colourMode(id: 77, encoding: 0, depth: 8), colourMode(id: 76, encoding: 0, depth: 8),
            colourMode(id: 78, encoding: 3, depth: 8), colourMode(id: 79, encoding: 3, depth: 8),
            colourMode(id: 5, encoding: 3, depth: 8, virtual: true, downstream: ["PixelEncoding": NSNumber(value: 1), "Depth": NSNumber(value: 8), "ID": NSNumber(value: 4)] as [String: Any]),
            colourMode(id: 87, encoding: 3, depth: 8, downstream: ["PixelEncoding": NSNumber(value: 1), "Depth": NSNumber(value: 8), "ID": NSNumber(value: 86)] as [String: Any]),
            colourMode(id: 85, encoding: 3, depth: 8, downstream: ["PixelEncoding": NSNumber(value: 1), "Depth": NSNumber(value: 8), "ID": NSNumber(value: 84)] as [String: Any]),
            colourMode(id: 10, encoding: 2, depth: 12, virtual: true), colourMode(id: 11, encoding: 6, depth: 12, virtual: true),
        ],
        "DSCRequiredColorElementIDs": [] as [Any],
        "UnsafeColorElementIDs": [77, 76, 78, 79, 10, 11].map { NSNumber(value: $0) },
        "ValidPixelEncodings": NSNumber(value: 6991),
    ]

    /// A virtual HDR twin of timing 45 as the node's TimingElements carry
    /// them (IsVirtual true, ValidPixelEncodings 0xffffffff), ID 23: kept
    /// by parseNode, left out of the statement's allTimings.
    private static let virtualTiming23: [String: Any] = {
        var t = timing45()
        t["ID"] = NSNumber(value: 23)
        t["IsVirtual"] = NSNumber(value: true)
        t["ValidPixelEncodings"] = NSNumber(value: 4_294_967_295)
        return t
    }()

    private static func node(props: [String: Any]) -> DisplayTimingReader.Node? {
        DisplayTimingReader.parseNode { props[$0] }
    }

    /// The 27C1U-L node with `timing` as its only entry, still driven at
    /// ID 45, for the malformed-timing cases: the node parses, the timing
    /// must not.
    private static func nodeWithOnlyTiming(_ timing: [String: Any]) -> [String: Any] {
        var props = externalNode27C1UL
        props["TimingElements"] = [] as [Any]
        props["PreferredTimingElements"] = [timing]
        return props
    }

    /// The CoreGraphics mode already on the port before the timing read. Its
    /// 10-bit depth differs from timing 45's 8, so a timing that wrongly
    /// attaches never equals it by accident.
    private static let cgMode = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 10)

    /// The port's current mode after `match` against a node built from
    /// `props`, with `cgMode` already on the port.
    private static func modeAfterMatch(props: [String: Any]) -> DisplayCurrentMode? {
        let nodes = [node(props: props)].compactMap { $0 }
        return DisplayTimingReader.match(ports: [port(edid: edid27C1UL, currentMode: cgMode)], nodes: nodes)[0].currentMode
    }

    private static let externalNode27C1UL: [String: Any] = [
        "external": NSNumber(value: true),
        "DPTimingModeId": NSNumber(value: 45),
        "EDID UUID": "25E3FFFF-0000-0000-2221-0103803C2278",
        "IOMFBUUID": "25E3FFFF-0000-0000-2221-0103803C2278",
        "TimingElements": [timing15, virtualTiming23],
        "PreferredTimingElements": [timing45()],
        "DisplayAttributes": ["ProductAttributes": ["SerialNumber": NSNumber(value: 0), "ProductName": "27C1U-L"] as [String: Any]] as [String: Any],
    ]

    private static func port(edid: Data?, serial: Int? = nil, currentMode: DisplayCurrentMode? = nil, maxMode: DisplayCurrentMode? = nil, hpmControllerUUID: String? = nil) -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(active: true, laneCount: 2, maxLaneCount: 2, linkRate: 4,
                                  linkRateDescription: "8.1 Gbps (HBR3)", tunneled: false, hpdState: 1),
            monitor: MonitorInfo(manufacturerName: "IOC", productName: "27C1U-L", productId: 65535,
                                 serialNumber: serial, yearOfManufacture: 2023, edid: edid),
            currentMode: currentMode,
            maxMode: maxMode,
            hpmControllerUUID: hpmControllerUUID
        )
    }

    // MARK: - The key

    @Test("edidKey is EDID bytes 8-23 as macOS formats them, with the serial bytes zeroed")
    func edidKeyMatchesMacOSFormat() {
        #expect(DisplayTimingReader.edidKey(from: Self.edid27C1UL) == "25E3FFFF-0000-0000-2221-0103803C2278")
        #expect(DisplayTimingReader.edidKey(from: Self.edidDellWithSerial) == "10AC6540-0000-0000-1E14-0104B5402878")
        #expect(DisplayTimingReader.edidKey(from: Data(repeating: 0, count: 23)) == nil, "too short to hold bytes 8-23")
    }

    // MARK: - The parse

    @Test("parseNode reads the current timing by DPTimingModeId from either list")
    func parseNodeReadsTheCurrentTiming() throws {
        let node = try #require(Self.node(props: Self.externalNode27C1UL))
        #expect(node.edidKey == "25E3FFFF-0000-0000-2221-0103803C2278")
        #expect(node.currentTimingID == 45)
        #expect(node.serialNumber == 0)
        #expect(node.capturedTimingIDs == [15, 23, 45])
        #expect(node.timings.map(\.id) == [15, 23, 45], "every parsed timing is kept, in the node's order")
        let timing = try #require(node.currentTiming)
        #expect(timing.width == 3840)
        #expect(timing.height == 2160)
        #expect(timing.hTotal == 3910)
        #expect(timing.vTotal == 2250)
        #expect(timing.refreshHz == 60.0)
        #expect(timing.interlaced == false)
        #expect(timing.pixelClockHz == 527_850_000)
        #expect(timing.bitsPerComponent == 8, "every non-virtual colour mode is 8 bit")
        #expect(timing.colourModes.count == 6, "the virtual entries are carried, not dropped")
        #expect(timing.colourModes.filter { !$0.isVirtual }.map(\.encoding.rawValue) == [0, 0, 3, 3])
    }

    @Test("A DPTimingModeId or UUID that changes while the arrays are read is a torn node: no current timing, nothing attaches (PR #665 gate, Codex 4)")
    func tornReadYieldsNoCurrentTiming() throws {
        // Per-key reads can straddle a mode change or a hot-plug. The ID is read before and
        // after the arrays; 45 and 15 both exist in the lists, which is the case where an
        // unbracketed read attaches the wrong timing with a confident verdict.
        var idReads = 0
        let tornID = try #require(DisplayTimingReader.parseNode { key in
            if key == "DPTimingModeId" { idReads += 1; return NSNumber(value: idReads == 1 ? 45 : 15) }
            return Self.externalNode27C1UL[key]
        })
        #expect(idReads == 2, "the ID is read before and after the arrays")
        #expect(tornID.currentTiming == nil)
        #expect(tornID.currentTimingID == nil)
        #expect(tornID.edidKey == "25E3FFFF-0000-0000-2221-0103803C2278")
        #expect(tornID.timings.isEmpty, "since the table bracket (gate rerun, Codex R2) any tear empties the timings too: they belong to no one snapshot")
        let cg = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let out = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, currentMode: cg)], nodes: [tornID])
        #expect(out[0].currentMode == cg && out[0].drivenTiming == nil, "a torn node attaches nothing")
        // The UUID pair on the same terms: a node replaced under the read is not this node.
        var uuidReads = 0
        let tornUUID = try #require(DisplayTimingReader.parseNode { key in
            if key == "EDID UUID" { uuidReads += 1; return uuidReads == 1 ? "25E3FFFF-0000-0000-2221-0103803C2278" : "10AC6540-0000-0000-1E14-0104B5402878" }
            return Self.externalNode27C1UL[key]
        })
        #expect(uuidReads == 2)
        #expect(tornUUID.currentTiming == nil && tornUUID.currentTimingID == nil)
        // A stable pair reads exactly as before.
        let stable = try #require(Self.node(props: Self.externalNode27C1UL))
        #expect(stable.currentTimingID == 45 && stable.currentTiming?.id == 45)
    }

    @Test("A timing table that changes between the two array reads is a torn node even with a stable UUID and ID: no current timing, no timings (PR #665 gate rerun, Codex R2)")
    func tornTableYieldsNoCurrentTiming() throws {
        // A same-panel link retrain between the TimingElements read and the PreferredTimingElements
        // read changes an entry's totals while the UUID and DPTimingModeId stay the same. The
        // arrays are read twice inside the bracket and attach only when both parses agree.
        var altered = Self.timing45()
        altered["HorizontalAttributes"] = ["Total": NSNumber(value: 4000), "Active": NSNumber(value: 3840)] as [String: Any]
        var preferredReads = 0
        let torn = try #require(DisplayTimingReader.parseNode { key in
            if key == "PreferredTimingElements" { preferredReads += 1; return preferredReads == 1 ? [Self.timing45()] : [altered] }
            return Self.externalNode27C1UL[key]
        })
        #expect(preferredReads == 2, "each array is read before and after")
        #expect(torn.currentTiming == nil && torn.currentTimingID == nil)
        #expect(torn.timings.isEmpty, "a torn table carries no timings: nothing for a top-mode match either")
        #expect(torn.edidKey == "25E3FFFF-0000-0000-2221-0103803C2278")
        let cg = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let out = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, currentMode: cg)], nodes: [torn])
        #expect(out[0].currentMode == cg && out[0].drivenTiming == nil, "a torn node attaches nothing")
        // TimingElements torn the same way.
        var timingReads = 0
        let tornFirst = try #require(DisplayTimingReader.parseNode { key in
            if key == "TimingElements" { timingReads += 1; return timingReads == 1 ? [Self.timing15, Self.virtualTiming23] : [Self.timing15] }
            return Self.externalNode27C1UL[key]
        })
        #expect(timingReads == 2)
        #expect(tornFirst.currentTiming == nil && tornFirst.timings.isEmpty)
        // A stable read attaches exactly as before, timings and all.
        let stable = try #require(Self.node(props: Self.externalNode27C1UL))
        #expect(stable.currentTiming?.id == 45 && stable.timings.map(\.id) == [15, 23, 45])
    }

    @Test("A timing offering more than one non-virtual depth has no bitsPerComponent")
    func ambiguousDepthIsNil() throws {
        var props = Self.externalNode27C1UL
        props["DPTimingModeId"] = NSNumber(value: 15)
        let node = try #require(Self.node(props: props))
        let timing = try #require(node.currentTiming)
        #expect(timing.id == 15)
        #expect(timing.bitsPerComponent == nil)
        #expect(timing.pixelClockHz == 1650 * 750 * 60)
    }

    @Test("A current timing outside both lists is reported as absent, with the IDs that were seen")
    func currentTimingNotCaptured() throws {
        var props = Self.externalNode27C1UL
        props["DPTimingModeId"] = NSNumber(value: 68)
        let node = try #require(Self.node(props: props))
        #expect(node.currentTimingID == 68)
        #expect(node.currentTiming == nil)
        #expect(node.capturedTimingIDs == [15, 23, 45])
    }

    @Test("An interlaced timing parses with no pixel clock, and never attaches")
    func interlacedTimingDoesNotAttach() throws {
        var t = Self.timing45()
        t["IsInterlaced"] = NSNumber(value: true)
        let timing = try #require(DisplayTimingReader.parseTiming(t))
        #expect(timing.interlaced == true)
        #expect(timing.pixelClockHz == nil)
        #expect(timing.nodeTiming.interlaced == true, "the flag reaches the statement's timing (PR #665 gate rerun, Codex R1)")
        #expect(timing.nodeTiming.pixelClockHz == nil)
        #expect(Self.modeAfterMatch(props: Self.nodeWithOnlyTiming(t)) == Self.cgMode, "a timing without a clock leaves the CoreGraphics mode in place")
    }

    @Test("Empty external slots, internal panels and nodes without a key parse to nil")
    func nonDisplayNodesAreNil() {
        #expect(Self.node(props: ["external": NSNumber(value: true), "IONameMatched": "dispext1,t604x"]) == nil)
        var internalPanel = Self.externalNode27C1UL
        internalPanel["external"] = nil
        #expect(Self.node(props: internalPanel) == nil)
        var noKey = Self.externalNode27C1UL
        noKey["EDID UUID"] = nil
        noKey["IOMFBUUID"] = nil
        #expect(Self.node(props: noKey) == nil)
    }

    @Test("IOMFBUUID stands in when EDID UUID is absent")
    func iomfbUUIDFallsBack() throws {
        var props = Self.externalNode27C1UL
        props["EDID UUID"] = nil
        let node = try #require(Self.node(props: props))
        #expect(node.edidKey == "25E3FFFF-0000-0000-2221-0103803C2278")
    }

    @Test("A timing missing a total or the precise sync rate is not a timing")
    func incompleteTimingIsNil() {
        var t = Self.timing45()
        t["VerticalAttributes"] = ["Total": NSNumber(value: 2250), "Active": NSNumber(value: 2160)] as [String: Any]
        #expect(DisplayTimingReader.parseTiming(t) == nil)
    }

    @Test("A zero active dimension is not a timing, and leaves the CoreGraphics mode in place")
    func zeroActiveTimingIsNotATiming() {
        var t = Self.timing45()
        t["HorizontalAttributes"] = ["Total": NSNumber(value: 3910), "Active": NSNumber(value: 0)] as [String: Any]
        #expect(DisplayTimingReader.parseTiming(t) == nil)
        #expect(Self.modeAfterMatch(props: Self.nodeWithOnlyTiming(t)) == Self.cgMode)
    }

    @Test("A zero precise sync rate is not a timing, and leaves the CoreGraphics mode in place")
    func zeroSyncRateTimingIsNotATiming() {
        var t = Self.timing45()
        t["VerticalAttributes"] = ["Total": NSNumber(value: 2250), "Active": NSNumber(value: 2160),
                                   "PreciseSyncRate": NSNumber(value: 0)] as [String: Any]
        #expect(DisplayTimingReader.parseTiming(t) == nil)
        #expect(Self.modeAfterMatch(props: Self.nodeWithOnlyTiming(t)) == Self.cgMode)
    }

    @Test("A total below its active dimension is not a timing")
    func totalsBelowActivesIsNotATiming() {
        var t = Self.timing45()
        t["HorizontalAttributes"] = ["Total": NSNumber(value: 3000), "Active": NSNumber(value: 3840)] as [String: Any]
        #expect(DisplayTimingReader.parseTiming(t) == nil)
    }

    @Test("A string where a number belongs is not a number: no timing, no current ID, port untouched")
    func nonNumericValuesAreNotNumbers() throws {
        var t = Self.timing45()
        t["ID"] = "45"
        #expect(DisplayTimingReader.parseTiming(t) == nil)
        var props = Self.externalNode27C1UL
        props["DPTimingModeId"] = "45"
        let node = try #require(Self.node(props: props))
        #expect(node.currentTimingID == nil)
        #expect(node.currentTiming == nil)
        #expect(Self.modeAfterMatch(props: props) == Self.cgMode)
    }

    @Test("A timing without a readable IsInterlaced is not a timing")
    func missingIsInterlacedIsNotATiming() {
        var t = Self.timing45()
        t["IsInterlaced"] = nil
        #expect(DisplayTimingReader.parseTiming(t) == nil)
    }

    @Test("A boolean where a number belongs is not a number")
    func booleanIsNotANumber() throws {
        var t = Self.timing45()
        t["ID"] = NSNumber(value: true)
        #expect(DisplayTimingReader.parseTiming(t) == nil)
        var props = Self.externalNode27C1UL
        props["DPTimingModeId"] = NSNumber(value: true)
        let node = try #require(Self.node(props: props))
        #expect(node.currentTimingID == nil)
    }

    @Test("A fractional value where an integer belongs is not a number")
    func fractionalValueIsNotANumber() {
        var active = Self.timing45()
        active["HorizontalAttributes"] = ["Total": NSNumber(value: 3910), "Active": NSNumber(value: 3840.9)] as [String: Any]
        #expect(DisplayTimingReader.parseTiming(active) == nil)
        var rate = Self.timing45()
        rate["VerticalAttributes"] = ["Total": NSNumber(value: 2250), "Active": NSNumber(value: 2160),
                                      "PreciseSyncRate": NSNumber(value: 3932160.5)] as [String: Any]
        #expect(DisplayTimingReader.parseTiming(rate) == nil)
    }

    @Test("An integer is not IsInterlaced; only a genuine boolean is")
    func integerIsNotAFlag() {
        var one = Self.timing45()
        one["IsInterlaced"] = NSNumber(value: 1)
        #expect(DisplayTimingReader.parseTiming(one) == nil)
        var zero = Self.timing45()
        zero["IsInterlaced"] = NSNumber(value: 0)
        #expect(DisplayTimingReader.parseTiming(zero) == nil)
        var genuine = Self.timing45()
        genuine["IsInterlaced"] = NSNumber(value: false)
        #expect(DisplayTimingReader.parseTiming(genuine) != nil)
    }

    @Test("Totals whose product does not fit an Int give no clock, and never trap")
    func hugeTotalsNeverTrap() throws {
        var t = Self.timing45()
        t["HorizontalAttributes"] = ["Total": NSNumber(value: Int.max / 2), "Active": NSNumber(value: 3840)] as [String: Any]
        t["VerticalAttributes"] = ["Total": NSNumber(value: Int.max / 2), "Active": NSNumber(value: 2160),
                                   "PreciseSyncRate": NSNumber(value: 3932160)] as [String: Any]
        let timing = try #require(DisplayTimingReader.parseTiming(t), "the guards pass: every value is a positive integer above its active")
        #expect(timing.pixelClockHz == nil)
        #expect(Self.modeAfterMatch(props: Self.nodeWithOnlyTiming(t)) == Self.cgMode)
    }

    @Test("A colour table with a malformed depth names no depth, but keeps its clock")
    func malformedDepthHidesTheWholeTable() throws {
        let t = Self.timing45(colourModes: [
            Self.colourMode(id: 90, encoding: 0, depth: 8),
            ["ID": NSNumber(value: 93), "PixelEncoding": NSNumber(value: 0),
             "Depth": NSNumber(value: 10.5), "IsVirtual": NSNumber(value: false)],
        ])
        let timing = try #require(DisplayTimingReader.parseTiming(t))
        #expect(timing.pixelClockHz == 527_850_000)
        #expect(timing.colourModesComplete == false)
        #expect(timing.bitsPerComponent == nil, "one surviving 8-bit entry must not pass for the whole table")
        #expect(timing.colourModes.count == 1, "the entry that parsed is still a fact")
        let mode = try #require(Self.modeAfterMatch(props: Self.nodeWithOnlyTiming(t)))
        #expect(mode.bitsPerComponent == nil, "no depth from an incomplete table, and none from the port (PR #665 gate, Claude F1)")
        #expect(mode.pixelClockHz == 527_850_000)
    }

    @Test("An IsVirtual that is not a genuine boolean, or is absent, makes the entry malformed")
    func nonBooleanIsVirtualIsMalformed() throws {
        let numeric = Self.timing45(colourModes: [
            Self.colourMode(id: 90, encoding: 0, depth: 8),
            ["ID": NSNumber(value: 10), "PixelEncoding": NSNumber(value: 2),
             "Depth": NSNumber(value: 12), "IsVirtual": NSNumber(value: 1)],
        ])
        let withNumeric = try #require(DisplayTimingReader.parseTiming(numeric))
        #expect(withNumeric.colourModesComplete == false)
        #expect(withNumeric.bitsPerComponent == nil)
        let absent = Self.timing45(colourModes: [
            Self.colourMode(id: 90, encoding: 0, depth: 8),
            ["ID": NSNumber(value: 10), "PixelEncoding": NSNumber(value: 2), "Depth": NSNumber(value: 12)],
        ])
        let withAbsent = try #require(DisplayTimingReader.parseTiming(absent))
        #expect(withAbsent.colourModesComplete == false)
        #expect(withAbsent.bitsPerComponent == nil)
    }

    @Test("A table where every entry parsed still names its single depth")
    func completeTableStillNamesItsDepth() throws {
        let timing = try #require(DisplayTimingReader.parseTiming(Self.timing45()))
        #expect(timing.colourModesComplete == true)
        #expect(timing.bitsPerComponent == 8)
    }

    @Test("A non-finite sync rate is not a number")
    func nonFiniteRateIsNotANumber() {
        var infinite = Self.timing45()
        infinite["VerticalAttributes"] = ["Total": NSNumber(value: 2250), "Active": NSNumber(value: 2160),
                                          "PreciseSyncRate": NSNumber(value: Double.infinity)] as [String: Any]
        #expect(DisplayTimingReader.parseTiming(infinite) == nil)
        var nan = Self.timing45()
        nan["VerticalAttributes"] = ["Total": NSNumber(value: 2250), "Active": NSNumber(value: 2160),
                                     "PreciseSyncRate": NSNumber(value: Double.nan)] as [String: Any]
        #expect(DisplayTimingReader.parseTiming(nan) == nil)
    }

    // MARK: - The statement fields (issue #664)

    @Test("parseTiming reads SupportsDSC, the two ID lists and ValidPixelEncodings into the statement")
    func parseTimingReadsTheStatementFields() throws {
        let timing = try #require(DisplayTimingReader.parseTiming(Self.timing45()))
        #expect(timing.dscRequiredList == [])
        #expect(timing.unsafeList == [90, 89, 91, 92, 10, 11])
        #expect(timing.validPixelEncodings == 0x1b4d)
        #expect(timing.colourModes.map(\.supportsDSC) == [0, 0, 0, 0, 0, 0])
        #expect(timing.colourModes.allSatisfy { $0.downstreamFormat == nil })
        let lists = timing.lists
        #expect(lists.colourModesComplete && lists.dscListComplete && lists.unsafeListComplete)
        #expect(lists.unsafeIDs == [89, 90, 91, 92])
        #expect(lists.dscReading(for: nil) == .uncompressed)
        #expect(timing.isVirtual == false)
        #expect(timing.nodeTiming == DisplayNodeTiming(id: 45, width: 3840, height: 2160, refreshHz: 60.0, pixelClockHz: 527_850_000, lists: lists))
        #expect(timing.pixelEncoding == nil)
        #expect(timing.downstreamFormat == nil)
        let listed = try #require(DisplayTimingReader.parseTiming(Self.timing15))
        #expect(listed.lists.dscRequiredIDs == [90, 93])
        #expect(listed.lists.dscCapableIDs == [90, 93])
        #expect(listed.pixelEncoding == .rgb444, "every non-virtual mode is RGB")
        #expect(listed.bitsPerComponent == nil, "8 and 10 bit: no single depth, as before")
    }

    @Test("A DownstreamFormat is read per colour mode (m2pro_macos26.6.1 timing 57 and the m1_macos26.5_o entry)")
    func downstreamFormatIsRead() throws {
        let timing = try #require(DisplayTimingReader.parseTiming(Self.timing57))
        #expect(timing.pixelClockHz == 594_000_000)
        let withDownstream = timing.colourModes.filter { $0.downstreamFormat != nil }
        #expect(withDownstream.map(\.id) == [5, 87, 85])
        #expect(withDownstream.allSatisfy { $0.downstreamFormat == DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8) })
        #expect(timing.lists.downstream420 == .someModes, "3 of 6 non-virtual modes convert (ruling 44)")
        #expect(timing.lists.unsafeIDs == [76, 77, 78, 79], "the modes converted to 4:2:0 are not rated unsafe, and the virtual ones are resolved out")
        #expect(timing.lists.dscReading(for: nil) == .uncompressed)
        #expect(timing.downstreamFormat == nil, "only three of six non-virtual modes carry one")
        let single = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [Self.downstreamMode5])))
        #expect(single.colourModes.first?.downstreamFormat == DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8))
        #expect(single.downstreamFormat == DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8), "every non-virtual mode (the one) carries it")
        #expect(single.pixelEncoding == .ycbcr444)
    }

    @Test("A malformed DownstreamFormat fails closed: the entry is dropped, the table is incomplete, the statement reads unresolved")
    func malformedDownstreamFormatFailsClosed() throws {
        var badDepth = Self.downstreamMode5
        badDepth["DownstreamFormat"] = ["PixelEncoding": NSNumber(value: 1), "Depth": "8"] as [String: Any]
        let timing = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [Self.colourMode(id: 90, encoding: 0, depth: 8), badDepth])))
        #expect(timing.colourModes.count == 1)
        #expect(timing.colourModesComplete == false)
        #expect(timing.bitsPerComponent == nil)
        #expect(timing.lists.colourModesComplete == false)
        // The empty DSC list parsed and names nothing the table lacks, so it is complete;
        // the unsafe list names the dropped entry's twins (89, 91, 92, 10, 11), modes the
        // table cannot vouch for, so it is incomplete and its receipt reads K38 (PR #665
        // gate, Codex 2: an ID no colour mode carries is never intersected away).
        #expect(timing.lists.dscListComplete == true)
        #expect(timing.lists.unsafeListComplete == false)
        #expect(timing.lists.dscReading(for: nil) == .unresolved)
        var scalar = Self.downstreamMode5
        scalar["DownstreamFormat"] = NSNumber(value: 1)
        let scalarTiming = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [scalar])))
        #expect(scalarTiming.colourModes.isEmpty && scalarTiming.colourModesComplete == false)
        var noEncoding = Self.downstreamMode5
        noEncoding["DownstreamFormat"] = ["Depth": NSNumber(value: 8)] as [String: Any]
        #expect(try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [noEncoding]))).colourModesComplete == false)
        #expect(Self.modeAfterMatch(props: Self.nodeWithOnlyTiming(Self.timing45(colourModes: [badDepth])))?.bitsPerComponent == nil, "an incomplete table names no depth, and the port's NSScreen value never stands in (PR #665 gate, Claude F1)")
    }

    @Test("A colour mode without a numeric SupportsDSC is malformed")
    func missingSupportsDSCIsMalformed() throws {
        var entry = Self.colourMode(id: 90, encoding: 0, depth: 8)
        entry["SupportsDSC"] = nil
        let absent = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [entry, Self.colourMode(id: 91, encoding: 3, depth: 8)])))
        #expect(absent.colourModes.map(\.id) == [91])
        #expect(absent.colourModesComplete == false)
        entry["SupportsDSC"] = "1"
        let string = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [entry])))
        #expect(string.colourModes.isEmpty && string.colourModesComplete == false)
        entry["SupportsDSC"] = NSNumber(value: 3)
        let three = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [entry])))
        #expect(three.colourModes.first?.supportsDSC == 3)
        #expect(three.colourModes.first?.isDSCCapable == true)
    }

    @Test("A SupportsDSC outside the two-bit field, or a list naming an ID no colour mode carries, reads unresolved through the statement (PR #665 gate, Codex 2)")
    func outOfDomainSupportsDSCAndUnknownListIDsFailClosed() throws {
        // SupportsDSC 7: not the bit field the dump names (0 to 3), so the entry is malformed
        // and the table incomplete, exactly like a non-numeric one.
        var entry = Self.colourMode(id: 90, encoding: 0, depth: 8, supportsDSC: 7)
        let seven = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [entry, Self.colourMode(id: 91, encoding: 3, depth: 8)])))
        #expect(seven.colourModes.map(\.id) == [91])
        #expect(seven.colourModesComplete == false)
        #expect(seven.lists.colourModesComplete == false)
        #expect(seven.lists.dscReading(for: nil) == .unresolved)
        entry["SupportsDSC"] = NSNumber(value: -1)
        let negative = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [entry])))
        #expect(negative.colourModes.isEmpty && negative.colourModesComplete == false)
        // A DSC list naming 999 beside the capable 90: the reader reads the list as published
        // (a fact), and the statement's list is incomplete, so the reading is unresolved and
        // never the DSC on that the intersection alone would have given.
        var timing = Self.timing45(colourModes: [Self.colourMode(id: 90, encoding: 0, depth: 8, supportsDSC: 1)])
        timing["DSCRequiredColorElementIDs"] = [90, 999].map { NSNumber(value: $0) }
        let unknown = try #require(DisplayTimingReader.parseTiming(timing))
        #expect(unknown.dscRequiredList == [90, 999], "read as published")
        #expect(unknown.lists.dscListComplete == false)
        #expect(unknown.lists.dscRequiredIDs == [90])
        #expect(unknown.lists.dscReading(for: nil) == .unresolved)
        // The same for the unsafe list: its receipt reads unreadable (K38), the DSC reading stands.
        var unsafe = Self.timing45()
        unsafe["UnsafeColorElementIDs"] = [90, 999].map { NSNumber(value: $0) }
        let unsafeUnknown = try #require(DisplayTimingReader.parseTiming(unsafe))
        #expect(unsafeUnknown.lists.unsafeListComplete == false)
        #expect(unsafeUnknown.lists.dscReading(for: nil) == .uncompressed)
        // Timing 45 as published (the virtual IDs 10 and 11 in its unsafe list are known modes): complete.
        let published = try #require(DisplayTimingReader.parseTiming(Self.timing45()))
        #expect(published.lists.unsafeListComplete == true && published.lists.dscListComplete == true && published.lists.colourModesComplete == true)
    }

    @Test("An ID list with a non-numeric entry, or an absent list key, makes the statement incomplete")
    func unreadableListsFailClosed() throws {
        var t = Self.timing45()
        t["DSCRequiredColorElementIDs"] = [NSNumber(value: 90), "91"] as [Any]
        let bad = try #require(DisplayTimingReader.parseTiming(t))
        #expect(bad.dscRequiredList == nil)
        #expect(bad.lists.dscListComplete == false)
        #expect(bad.lists.colourModesComplete && bad.lists.unsafeListComplete)
        #expect(bad.lists.dscReading(for: nil) == .unresolved, "an empty-looking list that did not fully parse says nothing")
        #expect(bad.pixelClockHz == 527_850_000, "the clock is unaffected")
        var absent = Self.timing45()
        absent["UnsafeColorElementIDs"] = nil
        let noKey = try #require(DisplayTimingReader.parseTiming(absent))
        #expect(noKey.unsafeList == nil)
        #expect(noKey.lists.unsafeListComplete == false)
        #expect(noKey.lists.colourModesComplete && noKey.lists.dscListComplete)
        #expect(noKey.lists.dscReading(for: nil) == .uncompressed, "ruling 42: the unsafe list is a receipt; its damage never suppresses the DSC statement")
        #expect(noKey.lists.unsafeIDs.isEmpty)
        var scalar = Self.timing45()
        scalar["DSCRequiredColorElementIDs"] = NSNumber(value: 0)
        #expect(try #require(DisplayTimingReader.parseTiming(scalar)).dscRequiredList == nil, "a scalar where a list belongs is not an empty list")
        var vpe = Self.timing45()
        vpe["ValidPixelEncodings"] = NSNumber(value: -1)
        #expect(try #require(DisplayTimingReader.parseTiming(vpe)).validPixelEncodings == nil)
        vpe["ValidPixelEncodings"] = NSNumber(value: 4_294_967_295)
        #expect(try #require(DisplayTimingReader.parseTiming(vpe)).validPixelEncodings == 0xffffffff)
        var noVPE = Self.timing45()
        noVPE["ValidPixelEncodings"] = nil
        let lists = try #require(DisplayTimingReader.parseTiming(noVPE)).lists
        #expect(lists.validPixelEncodings == nil && lists.colourModesComplete && lists.dscListComplete && lists.unsafeListComplete, "ValidPixelEncodings gates nothing")
        var noVirtualFlag = Self.timing45()
        noVirtualFlag["IsVirtual"] = nil
        let unflagged = try #require(DisplayTimingReader.parseTiming(noVirtualFlag))
        #expect(unflagged.isVirtual == nil, "a timing without a readable IsVirtual still parses (the driven lookup does not need it)")
        noVirtualFlag["IsVirtual"] = NSNumber(value: 1)
        #expect(try #require(DisplayTimingReader.parseTiming(noVirtualFlag)).isVirtual == nil, "an integer is not IsVirtual")
    }

    @Test("Ruling 43: an absent or non-array ColorModes is an incomplete table; a genuine empty array is complete and says nothing")
    func absentColourModesIsIncomplete() throws {
        var absent = Self.timing45()
        absent["ColorModes"] = nil
        let noKey = try #require(DisplayTimingReader.parseTiming(absent))
        #expect(noKey.colourModes.isEmpty)
        #expect(noKey.colourModesComplete == false, "no key is not an empty table")
        #expect(noKey.dscRequiredList == [] && noKey.unsafeList == [90, 89, 91, 92, 10, 11], "the two lists still parsed")
        // Over an absent table the empty DSC list is complete (it names nothing) and the unsafe
        // list, naming six modes no table carries, is not (PR #665 gate, Codex 2).
        #expect(noKey.lists.dscListComplete == true && noKey.lists.unsafeListComplete == false)
        #expect(noKey.lists.dscReading(for: nil) == .unresolved, "an empty DSC list over an absent table is no statement")
        #expect(noKey.bitsPerComponent == nil && noKey.pixelEncoding == nil && noKey.downstreamFormat == nil)
        var scalar = Self.timing45()
        scalar["ColorModes"] = NSNumber(value: 0)
        let notArray = try #require(DisplayTimingReader.parseTiming(scalar))
        #expect(notArray.colourModes.isEmpty && notArray.colourModesComplete == false)
        // The corpus's twin listing: `ColorModes = [0]`, a genuine empty array (255 of 6729 external timings, replica 2026-09-21).
        let empty = try #require(DisplayTimingReader.parseTiming(Self.timing45(colourModes: [])))
        #expect(empty.colourModes.isEmpty)
        #expect(empty.colourModesComplete == true, "an empty array is a complete table with nothing in it")
        #expect(empty.lists.hasNonVirtualColourMode == false)
        #expect(empty.lists.dscReading(for: nil) == .unresolved, "ruling 43: no candidate mode, so an empty list is not 'uncompressed'")
        #expect(empty.nodeTiming.lists.colourModesComplete == true)
    }

    @Test("match attaches the statement beside the mode, with every non-virtual node timing, and only there")
    func matchAttachesTheStatement() throws {
        var props = Self.externalNode27C1UL
        props["DPTimingModeId"] = NSNumber(value: 15)
        let node = try #require(Self.node(props: props))
        let cg = DisplayCurrentMode(width: 1280, height: 720, refreshHz: 60, bitsPerComponent: 10)
        let out = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, currentMode: cg)], nodes: [node])
        let statement = try #require(out[0].drivenTiming)
        #expect(statement.dscRequiredIDs == [90, 93])
        #expect(out[0].currentMode?.pixelEncoding == .rgb444)
        #expect(out[0].currentMode?.bitsPerComponent == nil, "the timing offers two depths and the port's NSScreen 10 never stands in (PR #665 gate, Claude F1)")
        #expect(statement.dscReading(for: out[0].currentMode) == .dscOn, "both modes are DSC-capable and listed, so the reading needs no depth")
        #expect(statement.allTimings.map(\.id) == [15, 45], "both non-virtual timings, in the node's order; the virtual twin 23 is left out")
        #expect(statement.allTimings[1].pixelClockHz == 527_850_000)
        #expect(statement.allTimings[1].lists.unsafeIDs == [89, 90, 91, 92])
        // The top-mode match runs over what the reader carried (Core decides; the reader never sees the EDID's top).
        #expect(statement.topModeMatch(width: 3840, height: 2160, refreshHz: 60.0, pixelClockHz: 527_850_000).kind == .exact)
        // A port the match leaves alone keeps no statement.
        #expect(DisplayTimingReader.match(ports: [Self.port(edid: Self.edidDellWithSerial, currentMode: cg)], nodes: [node])[0].drivenTiming == nil)
    }

    // MARK: - The match

    @Test("A single key match attaches the driven timing as the current mode, keeping the max mode")
    func cleanMatchAttaches() throws {
        let node = try #require(Self.node(props: Self.externalNode27C1UL))
        let cg = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 10)
        let maxMode = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let port = Self.port(edid: Self.edid27C1UL, currentMode: cg, maxMode: maxMode, hpmControllerUUID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        let out = DisplayTimingReader.match(ports: [port], nodes: [node])
        let mode = try #require(out[0].currentMode)
        #expect(mode.width == 3840 && mode.height == 2160)
        #expect(mode.refreshHz == 60.0)
        #expect(mode.pixelClockHz == 527_850_000)
        #expect(mode.bitsPerComponent == 8, "the timing's single depth wins over the NSScreen value")
        #expect(out[0].maxMode == maxMode)
        #expect(out[0].hpmControllerUUID == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        let statement = try #require(out[0].drivenTiming)
        #expect(statement.unsafeIDs == [89, 90, 91, 92])
        #expect(statement.dscRequiredIDs.isEmpty && statement.dscCapableIDs.isEmpty)
        #expect(statement.colourModesComplete && statement.dscListComplete && statement.unsafeListComplete)
        #expect(mode.pixelEncoding == nil, "RGB and 4:4:4 on one timing: no single link encoding")
        #expect(mode.downstreamFormat == nil)
    }

    @Test("An ambiguous depth stays nil: NSScreen's depth on the port never reaches the driven mode (PR #665 gate, Claude F1)")
    func ambiguousDepthIsNotFilledFromThePort() throws {
        // Until PR #665's gate the port's NSScreen depth stood in when the timing listed
        // several depths, and `candidateModes` then narrowed the DSC reading by it: a
        // value the node never published deciding the verdict. The node does not carry
        // the live depth and the spec forbids guessing it, so the driven mode carries the
        // timing's single depth or nothing.
        var props = Self.externalNode27C1UL
        props["DPTimingModeId"] = NSNumber(value: 15)
        let node = try #require(Self.node(props: props))
        let cg = DisplayCurrentMode(width: 1280, height: 720, refreshHz: 60, bitsPerComponent: 10)
        let out = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, currentMode: cg)], nodes: [node])
        #expect(out[0].currentMode?.bitsPerComponent == nil)
        #expect(out[0].currentMode?.pixelClockHz == 1650 * 750 * 60)
    }

    @Test("A timing listing an 8-bit non-capable and a 10-bit capable mode reads the same at NSScreen 8, 10 and none: unresolved (PR #665 gate, Claude F1)")
    func nsScreenDepthDoesNotNarrowTheReading() throws {
        // The reviewer's constructed shape: 8-bit RGB SupportsDSC 0, 10-bit RGB SupportsDSC 1,
        // DSC list [the 10-bit]. With NSScreen 8 the old reader read uncompressed, with 10 DSC
        // on: two confident verdicts from one statement. The node does not name the live
        // depth, so the reading is unresolved whatever the port carried.
        var mixed = Self.timing15
        mixed["ColorModes"] = [Self.colourMode(id: 90, encoding: 0, depth: 8, supportsDSC: 0), Self.colourMode(id: 93, encoding: 0, depth: 10, supportsDSC: 1)]
        mixed["DSCRequiredColorElementIDs"] = [NSNumber(value: 93)]
        var props = Self.externalNode27C1UL
        props["TimingElements"] = [mixed]
        props["DPTimingModeId"] = NSNumber(value: 15)
        let node = try #require(Self.node(props: props))
        var readings: [DisplayTimingStatement.DSCReading] = []
        for cg in [nil, DisplayCurrentMode(width: 1280, height: 720, refreshHz: 60, bitsPerComponent: 8), DisplayCurrentMode(width: 1280, height: 720, refreshHz: 60, bitsPerComponent: 10)] {
            let out = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, currentMode: cg)], nodes: [node])[0]
            let statement = try #require(out.drivenTiming)
            #expect(out.currentMode?.bitsPerComponent == nil, "NSScreen \(String(describing: cg?.bitsPerComponent)) must not reach the driven mode")
            readings.append(statement.dscReading(for: out.currentMode))
        }
        #expect(readings == [.unresolved, .unresolved, .unresolved], "got \(readings)")
        // A timing with one depth still names it, from the timing itself.
        let single = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, currentMode: Self.cgMode)], nodes: [try #require(Self.node(props: Self.externalNode27C1UL))])[0]
        #expect(single.currentMode?.bitsPerComponent == 8, "timing 45's own single depth, not the port's 10")
    }

    @Test("No EDID, no key match, or no current timing: the port is returned untouched")
    func failClosed() throws {
        let node = try #require(Self.node(props: Self.externalNode27C1UL))
        let cg = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        #expect(DisplayTimingReader.match(ports: [Self.port(edid: nil, currentMode: cg)], nodes: [node])[0].currentMode == cg)
        #expect(DisplayTimingReader.match(ports: [Self.port(edid: Self.edidDellWithSerial, currentMode: cg)], nodes: [node])[0].currentMode == cg)
        var absent = Self.externalNode27C1UL
        absent["DPTimingModeId"] = NSNumber(value: 68)
        let noTiming = try #require(Self.node(props: absent))
        #expect(DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, currentMode: cg)], nodes: [noTiming])[0].currentMode == cg)
        #expect(DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL)], nodes: [])[0].currentMode == nil)
    }

    @Test("Two identical panels: the serial breaks the tie, and equal or missing serials attach nothing")
    func identicalPanelsBreakTiesOnSerial() throws {
        func nodeWithSerial(_ serial: Int, timingID: Int) -> DisplayTimingReader.Node {
            var props = Self.externalNode27C1UL
            props["DPTimingModeId"] = NSNumber(value: timingID)
            props["DisplayAttributes"] = ["ProductAttributes": ["SerialNumber": NSNumber(value: serial)] as [String: Any]] as [String: Any]
            return Self.node(props: props)!
        }
        let a = nodeWithSerial(391_073, timingID: 45)
        let b = nodeWithSerial(391_074, timingID: 15)
        let portA = Self.port(edid: Self.edid27C1UL, serial: 391_073)
        let portB = Self.port(edid: Self.edid27C1UL, serial: 391_074)
        let out = DisplayTimingReader.match(ports: [portA, portB], nodes: [a, b])
        #expect(out[0].currentMode?.pixelClockHz == 527_850_000)
        #expect(out[1].currentMode?.pixelClockHz == 1650 * 750 * 60)
        // Same placeholder serial on both (the corpus's 16843009 case): nothing attaches.
        let c = nodeWithSerial(16_843_009, timingID: 45)
        let d = nodeWithSerial(16_843_009, timingID: 15)
        let same = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, serial: 16_843_009)], nodes: [c, d])
        #expect(same[0].currentMode == nil)
        // No serial on the port at all: nothing attaches either.
        let noSerial = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL)], nodes: [a, b])
        #expect(noSerial[0].currentMode == nil)
        // One candidate whose real serial is not the port's: the other panel's node.
        let other = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, serial: 391_074)], nodes: [a])
        #expect(other[0].currentMode == nil)
    }

    @Test("Two ports with the same EDID identity cannot be told apart: neither attaches, even to a single node")
    func duplicatePortIdentityAttachesNothing() throws {
        let node = try #require(Self.node(props: Self.externalNode27C1UL))
        let twins = [Self.port(edid: Self.edid27C1UL), Self.port(edid: Self.edid27C1UL)]
        let out = DisplayTimingReader.match(ports: twins, nodes: [node])
        #expect(out[0].currentMode == nil)
        #expect(out[1].currentMode == nil)
        // A real serial on the port and none on the node (0) does not
        // contradict: a port alone on its identity still attaches.
        let single = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, serial: 7)], nodes: [node])
        #expect(single[0].currentMode?.pixelClockHz == 527_850_000)
    }

    @Test("One node never attaches to two ports: two real port serials against a single zero-serial node attach nothing")
    func oneNodeNeverAttachesToTwoPorts() throws {
        let node = try #require(Self.node(props: Self.externalNode27C1UL))
        #expect(node.serialNumber == 0)
        let ports = [Self.port(edid: Self.edid27C1UL, serial: 391_073), Self.port(edid: Self.edid27C1UL, serial: 391_074)]
        let out = DisplayTimingReader.match(ports: ports, nodes: [node])
        #expect(out[0].currentMode == nil)
        #expect(out[1].currentMode == nil)
        // The guard is about two ports choosing one node, not about the zero
        // serial: a port alone on its identity still attaches to that node.
        let single = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, serial: 7)], nodes: [node])
        #expect(single[0].currentMode?.pixelClockHz == 527_850_000)
    }
}
