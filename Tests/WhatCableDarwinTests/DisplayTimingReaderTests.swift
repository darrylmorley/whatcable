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

    private static func colourMode(id: Int, encoding: Int, depth: Int, virtual: Bool = false) -> [String: Any] {
        ["ID": NSNumber(value: id), "PixelEncoding": NSNumber(value: encoding),
         "Depth": NSNumber(value: depth), "IsVirtual": NSNumber(value: virtual)]
    }

    /// Timing 45 as the node publishes it: 3840x2160 in 3910x2250 totals,
    /// PreciseSyncRate 3932160 = 60.0 Hz in 16.16, 8-bit RGB and 4:4:4 only
    /// (plus two virtual 12-bit HDR entries the reader ignores).
    private static func timing45(colourModes: [[String: Any]]? = nil) -> [String: Any] {
        ["ID": NSNumber(value: 45), "IsInterlaced": NSNumber(value: false),
         "HorizontalAttributes": ["Total": NSNumber(value: 3910), "Active": NSNumber(value: 3840)] as [String: Any],
         "VerticalAttributes": ["Total": NSNumber(value: 2250), "Active": NSNumber(value: 2160),
                                "PreciseSyncRate": NSNumber(value: 3932160)] as [String: Any],
         "ColorModes": colourModes ?? [
            colourMode(id: 90, encoding: 0, depth: 8), colourMode(id: 89, encoding: 0, depth: 8),
            colourMode(id: 91, encoding: 3, depth: 8), colourMode(id: 92, encoding: 3, depth: 8),
            colourMode(id: 10, encoding: 2, depth: 12, virtual: true), colourMode(id: 11, encoding: 6, depth: 12, virtual: true),
         ]]
    }

    /// A 720p60 entry with 8 and 10 bit colour modes, ID 15.
    private static let timing15: [String: Any] = [
        "ID": NSNumber(value: 15), "IsInterlaced": NSNumber(value: false),
        "HorizontalAttributes": ["Total": NSNumber(value: 1650), "Active": NSNumber(value: 1280)] as [String: Any],
        "VerticalAttributes": ["Total": NSNumber(value: 750), "Active": NSNumber(value: 720),
                               "PreciseSyncRate": NSNumber(value: 3932160)] as [String: Any],
        "ColorModes": [colourMode(id: 90, encoding: 0, depth: 8), colourMode(id: 93, encoding: 0, depth: 10)],
    ]

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
        "TimingElements": [timing15],
        "PreferredTimingElements": [timing45()],
        "DisplayAttributes": ["ProductAttributes": ["SerialNumber": NSNumber(value: 0), "ProductName": "27C1U-L"] as [String: Any]] as [String: Any],
    ]

    private static func port(edid: Data?, serial: Int? = nil, currentMode: DisplayCurrentMode? = nil, maxMode: DisplayCurrentMode? = nil) -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(active: true, laneCount: 2, maxLaneCount: 2, linkRate: 4,
                                  linkRateDescription: "8.1 Gbps (HBR3)", tunneled: false, hpdState: 1),
            monitor: MonitorInfo(manufacturerName: "IOC", productName: "27C1U-L", productId: 65535,
                                 serialNumber: serial, yearOfManufacture: 2023, edid: edid),
            currentMode: currentMode,
            maxMode: maxMode
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
        #expect(node.capturedTimingIDs == [15, 45])
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
        #expect(timing.colourModes.filter { !$0.isVirtual }.map(\.encoding) == [0, 0, 3, 3])
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
        #expect(node.capturedTimingIDs == [15, 45])
    }

    @Test("An interlaced timing parses with no pixel clock, and never attaches")
    func interlacedTimingDoesNotAttach() throws {
        var t = Self.timing45()
        t["IsInterlaced"] = NSNumber(value: true)
        let timing = try #require(DisplayTimingReader.parseTiming(t))
        #expect(timing.interlaced == true)
        #expect(timing.pixelClockHz == nil)
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
        #expect(mode.bitsPerComponent == 10, "the NSScreen depth stays")
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

    // MARK: - The match

    @Test("A single key match attaches the driven timing as the current mode, keeping the max mode")
    func cleanMatchAttaches() throws {
        let node = try #require(Self.node(props: Self.externalNode27C1UL))
        let cg = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 10)
        let maxMode = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let port = Self.port(edid: Self.edid27C1UL, currentMode: cg, maxMode: maxMode)
        let out = DisplayTimingReader.match(ports: [port], nodes: [node])
        let mode = try #require(out[0].currentMode)
        #expect(mode.width == 3840 && mode.height == 2160)
        #expect(mode.refreshHz == 60.0)
        #expect(mode.pixelClockHz == 527_850_000)
        #expect(mode.bitsPerComponent == 8, "the timing's single depth wins over the NSScreen value")
        #expect(out[0].maxMode == maxMode)
    }

    @Test("An ambiguous depth keeps the bits per component already on the port")
    func ambiguousDepthKeepsThePortsValue() throws {
        var props = Self.externalNode27C1UL
        props["DPTimingModeId"] = NSNumber(value: 15)
        let node = try #require(Self.node(props: props))
        let cg = DisplayCurrentMode(width: 1280, height: 720, refreshHz: 60, bitsPerComponent: 10)
        let out = DisplayTimingReader.match(ports: [Self.port(edid: Self.edid27C1UL, currentMode: cg)], nodes: [node])
        #expect(out[0].currentMode?.bitsPerComponent == 10)
        #expect(out[0].currentMode?.pixelClockHz == 1650 * 750 * 60)
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
