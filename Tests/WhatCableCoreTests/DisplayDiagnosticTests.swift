import Foundation
import Testing
@testable import WhatCableCore

@Suite("Display Diagnostic")
struct DisplayDiagnosticTests {

    // MARK: - Fixtures

    /// The G34w-10 as parsed by EDIDInfo: preferred 3440x1440@60, with a real
    /// 3440x1440@100 top timing at 600 MHz. 600e6 x 24bpp = 14.4 Gbps usable
    /// needed. Its 0xFD envelope happens to sit at the same figures; the
    /// `topMode` is what the diagnostic reads, and without it this
    /// fixture would quietly fall to its 60 Hz preferred mode and stop testing
    /// the top-mode comparison at all.
    private let g34w = EDIDInfo.fixture(
        name: "LEN G34w-10",
        version: (1, 3),
        preferred: EDIDInfo.mode(3440, 1440, hTotal: 3702, vTotal: 1440, pixelClockHz: 319_890_000),
        modes: [EDIDInfo.mode(3440, 1440, hTotal: 4167, vTotal: 1440, pixelClockHz: 600_000_000,
                               source: .detailedTiming(block: 1, index: 0))],
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 100, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 600_000_000, timingSupport: .rangeLimitsOnly)
    )

    private func makeDP(
        active: Bool = true,
        lanes: Int = 4,
        maxLanes: Int = 4,
        rateDesc: String? = "5.4 Gbps (HBR2)",
        tunneled: Bool = false,
        dfpType: String? = nil,
        branchDeviceId: String? = nil,
        edidData: Data? = nil,
        manufacturerName: String? = nil,
        currentMode: DisplayCurrentMode? = nil,
        maxMode: DisplayCurrentMode? = nil,
        drivenTiming: DisplayTimingStatement? = nil
    ) -> IOPortTransportStateDisplayPort {
        let monitor: MonitorInfo? = (edidData == nil && manufacturerName == nil) ? nil : MonitorInfo(
            manufacturerName: manufacturerName, productName: nil, productId: nil,
            yearOfManufacture: nil, edid: edidData
        )
        return IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: active,
                laneCount: lanes,
                maxLaneCount: maxLanes,
                linkRate: 3,
                linkRateDescription: rateDesc,
                tunneled: tunneled,
                hpdState: 1
            ),
            monitor: monitor,
            dfpType: dfpType,
            branchDeviceId: branchDeviceId,
            currentMode: currentMode,
            maxMode: maxMode,
            drivenTiming: drivenTiming
        )
    }

    /// A cable e-marker (SOP') whose ID header product type marks it active
    /// (4) or passive (3). The cable VDO value itself is irrelevant here; the
    /// active/passive flag comes from the header.
    private func cable(active: Bool) -> USBPDSOP {
        let header: UInt32 = (active ? 4 : 3) << 27
        return USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [header, 0, 0, 0],
            specRevision: 0
        )
    }

    // MARK: - Statement fixtures (issue #664), corpus timings transcribed by hand

    private static func colour(_ id: Int, _ encoding: DisplayPixelEncoding, _ depth: Int, dsc: Int, virtual: Bool = false, downstream: DisplayDownstreamFormat? = nil) -> DisplayColourMode {
        DisplayColourMode(id: id, encoding: encoding, depth: depth, supportsDSC: dsc, isVirtual: virtual, downstreamFormat: downstream)
    }

    /// One 8-bit RGB mode, not DSC-capable, DSC list empty: "uncompressed" lists.
    private static func plainLists(id: Int = 1) -> DisplayTimingLists {
        DisplayTimingLists(colourModes: [colour(id, .rgb444, 8, dsc: 0)], dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1ffd, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    }

    /// One 8-bit RGB mode, DSC-capable and listed: "with DSC" lists.
    private static func dscLists(id: Int = 1) -> DisplayTimingLists {
        DisplayTimingLists(colourModes: [colour(id, .rgb444, 8, dsc: 1)], dscRequiredList: [id], unsafeList: [], validPixelEncodings: 0x1ffd, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    }

    /// A timing the node lists with no colour mode validated: a listing, not an offer.
    private static let emptyLists = DisplayTimingLists(colourModes: [], dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1ffd, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)

    /// One node timing: picture, refresh, clock and its lists.
    private static func listing(_ w: Int, _ h: Int, _ hz: Double, _ clock: Int?, _ lists: DisplayTimingLists = plainLists(), id: Int = 100) -> DisplayNodeTiming {
        DisplayNodeTiming(id: id, width: w, height: h, refreshHz: hz, pixelClockHz: clock, lists: lists)
    }

    /// A statement whose driven timing is plain 8-bit RGB uncompressed and whose node lists `timings`.
    private static func offering(_ timings: [DisplayNodeTiming], driven: DisplayTimingLists = plainLists()) -> DisplayTimingStatement {
        DisplayTimingStatement(driven: driven, allTimings: timings)
    }

    /// The G34w-10 at 60 Hz, as the node lists it (319.89 MHz DTD) and as CoreGraphics reports it (8-bit RGB).
    private static let g34wAt60 = listing(3440, 1440, 60.0, 319_890_000, id: 11)
    /// The G34w-10's 100 Hz top (600 MHz), uncompressed, and the same with DSC listed.
    /// 600 MHz over 4167 x 1440 totals is 99.992 Hz; the listing carries that figure so the exact step (0.001 Hz) matches it.
    private static let g34wAt100 = listing(3440, 1440, 99.992, 600_000_000, id: 12)
    private static let g34wAt100DSC = listing(3440, 1440, 99.992, 600_000_000, dscLists(id: 2), id: 12)
    private static let liveG34w60 = DisplayCurrentMode(width: 3440, height: 1440, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 319_890_000, pixelEncoding: .rgb444)
    private static let liveG34w100 = DisplayCurrentMode(width: 3440, height: 1440, refreshHz: 100, bitsPerComponent: 8, pixelClockHz: 600_000_000, pixelEncoding: .rgb444)

    /// m3_macos26.6.2, 27C1U-L, timing 45: no mode DSC-capable, DSC list empty, all six unsafe (behind a DP 1.2 HDMI converter).
    private static let lists27C1UL = DisplayTimingLists(
        colourModes: [colour(90, .rgb444, 8, dsc: 0), colour(89, .rgb444, 8, dsc: 0), colour(91, .ycbcr444, 8, dsc: 0), colour(92, .ycbcr444, 8, dsc: 0),
                      colour(10, .ycbcr422, 12, dsc: 0, virtual: true), colour(11, .ycbcr422DPTunneling, 12, dsc: 0, virtual: true)],
        dscRequiredList: [], unsafeList: [90, 89, 91, 92, 10, 11], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    private static let statement27C1UL = DisplayTimingStatement(driven: lists27C1UL, allTimings: [listing(3840, 2160, 60.0, 527_850_000, lists27C1UL, id: 45)])
    private static let live27C1UL = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 527_850_000)

    /// m5_macos26.6.1_e, Studio Display, timing 43: 5120x2880 at 60 Hz, 936 MHz; three RGB modes, all DSC-capable, all listed.
    private static let listsStudio = DisplayTimingLists(
        colourModes: [colour(1, .rgb444, 8, dsc: 1, virtual: true), colour(46, .rgb444, 8, dsc: 1), colour(48, .rgb444, 10, dsc: 1)],
        dscRequiredList: [1, 46, 48], unsafeList: [], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    private static let statementStudio = DisplayTimingStatement(driven: listsStudio, allTimings: [listing(5120, 2880, 60.0, 936_000_000, listsStudio, id: 43)])
    private static let liveStudio = DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60, bitsPerComponent: 10, pixelClockHz: 936_000_000, pixelEncoding: .rgb444)

    /// m4pro_macos26.6.1_b, DELL U3225QE, timing 76, the twelve printed modes: 4K120, 1188 MHz, RGB and 4:4:4 at 8 and 10 bit, all DSC-capable and listed.
    private static let listsU3225QE = DisplayTimingLists(
        colourModes: [colour(2, .rgb444, 8, dsc: 1, virtual: true), colour(122, .rgb444, 8, dsc: 1), colour(121, .rgb444, 8, dsc: 1), colour(1, .rgb444, 8, dsc: 1, virtual: true),
                      colour(108, .rgb444, 8, dsc: 1), colour(109, .rgb444, 8, dsc: 1), colour(112, .ycbcr444, 8, dsc: 1), colour(113, .ycbcr444, 8, dsc: 1),
                      colour(116, .rgb444, 10, dsc: 1), colour(115, .rgb444, 10, dsc: 1), colour(114, .rgb444, 10, dsc: 1), colour(117, .rgb444, 10, dsc: 1)],
        dscRequiredList: [2, 122, 121, 1, 108, 109, 112, 113, 116, 115, 114, 117], unsafeList: [], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    private static let statementU3225QE = DisplayTimingStatement(driven: listsU3225QE, allTimings: [listing(3840, 2160, 120.0, 1_188_000_000, listsU3225QE, id: 76)])
    private static let liveU3225QE = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120, pixelClockHz: 1_188_000_000)

    /// m1max_macos26.5.2_p, timing 64 (4K144, 1328.25 MHz): RGB and 4:4:4 DSC-capable and listed, 4:2:2 neither.
    private static let listsMixed = DisplayTimingLists(
        colourModes: [colour(68, .rgb444, 8, dsc: 1), colour(1, .rgb444, 8, dsc: 1, virtual: true), colour(71, .ycbcr422, 8, dsc: 0), colour(70, .ycbcr422, 8, dsc: 0),
                      colour(72, .ycbcr444, 8, dsc: 1), colour(73, .ycbcr444, 8, dsc: 1),
                      colour(75, .rgb444, 10, dsc: 1), colour(74, .rgb444, 10, dsc: 1), colour(81, .rgb444, 10, dsc: 1), colour(82, .rgb444, 10, dsc: 1)],
        dscRequiredList: [68, 1, 72, 73, 75, 74, 81, 82], unsafeList: [], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    private static let statementMixed = DisplayTimingStatement(driven: listsMixed, allTimings: [listing(3840, 2160, 143.9993, 1_328_249_948, listsMixed, id: 64)])
    private static let liveMixed = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 143.999, pixelClockHz: 1_328_249_948)

    /// m2pro_macos26.6.1, DELL S2721QS behind cHDMIb, timing 57: 4K60 at 594 MHz; three 4:4:4 modes carry a 4:2:0 downstream format; the plain RGB and 4:4:4 modes are unsafe.
    private static let listsS2721QS = DisplayTimingLists(
        colourModes: [colour(77, .rgb444, 8, dsc: 0), colour(76, .rgb444, 8, dsc: 0), colour(78, .ycbcr444, 8, dsc: 0), colour(79, .ycbcr444, 8, dsc: 0),
                      colour(5, .ycbcr444, 8, dsc: 0, virtual: true, downstream: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8)),
                      colour(87, .ycbcr444, 8, dsc: 0, downstream: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8)),
                      colour(85, .ycbcr444, 8, dsc: 0, downstream: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8)),
                      colour(10, .ycbcr422, 12, dsc: 0, virtual: true), colour(11, .ycbcr422DPTunneling, 12, dsc: 0, virtual: true)],
        dscRequiredList: [], unsafeList: [77, 76, 78, 79, 10, 11], validPixelEncodings: 0x1b4f, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    private static let statementS2721QS = DisplayTimingStatement(driven: listsS2721QS, allTimings: [listing(3840, 2160, 60.0, 594_000_000, listsS2721QS, id: 57)])
    private static let liveS2721QS = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 594_000_000)

    /// A Studio Display EDID with its real 5120x2880 top (the tiled composite the parser reads, 964.8 MHz), so `meetsTopMode` has the true top to meet and the node's 936 MHz timing matches it at the same refresh.
    private let studio5K = EDIDInfo.fixture(
        name: "StudioDisplay",
        version: (1, 4),
        preferred: EDIDInfo.mode(5120, 2880, hTotal: 5360, vTotal: 3000, pixelClockHz: 964_800_000)
    )

    // MARK: - Widget display path

    @Test("Widget path: dp current mode surfaces as a short label")
    func widgetPathSurfacesCurrentMode() throws {
        // The widget builds DisplayDiagnostic(dp:cable:) and reads
        // facts.currentMode?.shortLabel. This pins that path: a 5K 60Hz
        // current mode flows through to the badge label, cable-independent.
        let dp = makeDP(currentMode: DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60))
        let diag = try #require(DisplayDiagnostic(dp: dp, cable: nil))
        #expect(diag.facts.currentMode?.shortLabel == "5K 60Hz")
    }

    // MARK: - Core verdicts

    @Test("4-lane HBR2, the node lists the G34w-10's 100Hz top: belowMonitorMax, the statement clears the cable")
    func fourLaneOffersTheTopMode() throws {
        // Driven at 60 Hz; the node lists the 100 Hz top uncompressed, so the
        // selected mode or this Mac is what holds the picture below it.
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60, Self.g34wAt100])), edid: g34w))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.isWarning == true)
        #expect(diag.summary == "Monitor can do more than it is set to")
        #expect(diag.detail.contains("as available on this link, uncompressed"), "\(diag.detail)")
        #expect(diag.detail.contains("is running uncompressed."), "\(diag.detail)")
        #expect(diag.cableAssessment == .unlikelyTheCable, "the statement's reason")
        #expect(diag.facts.statementOffersTopMode == true)
        #expect(diag.facts.topModeAvailability == .offeredUncompressed)
        #expect(diag.facts.topModeMatch == .exact)
        #expect(diag.facts.topModeTiming?.id == 12)
        #expect(diag.facts.deliveredGbps.map { $0 > 17 } == true)
    }

    @Test("2-lane HBR2, the node lists the picture at 60Hz only: belowMonitorMax, top not offered")
    func twoLaneTopModeNotOffered() throws {
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.isWarning == true)
        #expect(diag.summary == "Monitor can do more than the link is carrying")
        #expect(diag.detail.contains("macOS does not offer your LEN G34w-10's top mode (up to 100Hz) on this link as it is now."), "\(diag.detail)")
        #expect(diag.facts.topModeAvailability == .notOffered)
        #expect(diag.facts.topModeMatch == .pictureOnly)
        #expect(diag.facts.lanes == 2)
        #expect(diag.facts.maxLanes == 4)
        // 2 of 4 lanes, not tunneled: we can't exonerate the cable.
        #expect(diag.cableAssessment == .inconclusive)
        // Non-accusatory: never names the cable as the definite culprit.
        #expect(!diag.detail.lowercased().contains("the cable is the limit"))
    }

    // MARK: - Cable attribution

    @Test("Tunneled shortfall exonerates the cable")
    func tunneledExonerates() throws {
        // DP tunneled over TB/USB4: the cable carries far more than DP needs.
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2, tunneled: true, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w)
        )
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.cableAssessment == .unlikelyTheCable)
        #expect(diag.detail.lowercased().contains("tunnel"))
        #expect(diag.detail.lowercased().contains("unlikely to be the cable"))
    }

    @Test("All host lanes in use on a passive cable exonerates it")
    func allLanesExonerates() throws {
        // 4 of 4 lanes but a low rate (RBR), and the node lists the picture
        // at 60 Hz only. The cable carries every lane, so it isn't lane-limiting.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "1.62 Gbps (RBR)", currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w, cable: cable(active: false)))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.cableAssessment == .unlikelyTheCable)
        #expect(diag.detail.lowercased().contains("every displayport lane"))
    }

    @Test("Active cable is NOT exonerated on the lane signal (issue #111)")
    func activeCableNotExonerated() throws {
        // Same all-lanes shortfall, but the cable is active. Active cables can
        // misreport, so the lane signal alone must not exonerate them.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "1.62 Gbps (RBR)", currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w, cable: cable(active: true)))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.cableAssessment == .inconclusive)
    }

    @Test("Unidentified cable (no e-marker) at all lanes stays inconclusive")
    func noEmarkerNotExonerated() throws {
        // All host lanes in use but no e-marker: we can't vouch for an
        // unidentified cable (it could be a cheap passive cable rate-limiting
        // the link), so the lane signal alone must not exonerate it.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "1.62 Gbps (RBR)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w, cable: nil))
        #expect(diag.bottleneck == .unknownMode, "no statement, live mode absent: nothing to judge the top mode with")
        #expect(diag.cableAssessment == .inconclusive)
    }

    @Test("Tunneled exonerates even an active cable")
    func tunneledBeatsActive() throws {
        // The tunnel itself proves capability, independent of the e-marker.
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2, tunneled: true), edid: g34w, cable: cable(active: true))
        )
        #expect(diag.cableAssessment == .unlikelyTheCable)
    }

    @Test("Top mode not offered behind an HDMI adapter: adapterLimit, not cable blame")
    func adapterShortfall() throws {
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2, dfpType: "HDMI", currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w)
        )
        #expect(diag.bottleneck == .adapterLimit)
        #expect(diag.facts.sinkType == "HDMI")
        #expect(diag.summary.contains("HDMI"))
    }

    @Test("An HDMI adapter through which the node offers the top mode is not blamed")
    func adapterWithTheTopModeOfferedIsNotBlamed() throws {
        // Offered: the adapter is not the limit, so the verdict names the
        // selected mode rather than the adapter.
        let below = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 4, dfpType: "HDMI", currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60, Self.g34wAt100])), edid: g34w)
        )
        #expect(below.bottleneck == .belowMonitorMax)
        #expect(below.facts.sinkType == "HDMI")
        // And at the top mode it is fine.
        let atTop = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 4, dfpType: "HDMI", currentMode: Self.liveG34w100, drivenTiming: Self.offering([Self.g34wAt60, Self.g34wAt100])), edid: g34w)
        )
        #expect(atTop.bottleneck == .fine)
    }

    @Test("Live link with no readable EDID: unknownMode, blames nothing")
    func noEDID() throws {
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2), edid: nil))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.isWarning == false)
    }

    @Test("No active DisplayPort link returns nil (port stays silent)")
    func inactiveLinkIsNil() {
        #expect(DisplayDiagnostic(dp: makeDP(active: false), edid: g34w) == nil)
    }

    @Test("Unparseable link rate degrades to unknownMode, no false alarm")
    func unparseableRate() throws {
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2, rateDesc: "No Link"), edid: g34w)
        )
        #expect(diag.bottleneck == .unknownMode)
    }

    // MARK: - Production path (parses EDID from the node's monitor blob)

    @Test("init(dp:) parses the embedded EDID end to end")
    func parsesEmbeddedEDID() throws {
        // Base block PLUS the CTA-861 extension. The G34w's 100 Hz mode is
        // declared only in the extension; the base block alone carries a 60 Hz
        // preferred timing and a 100 Hz 0xFD scan ceiling, and the ceiling is
        // not a mode (issue #596). Feeding the base block alone would make this
        // test assert 100 Hz from a number the panel never offered as a mode.
        let edidData = Data(EDIDInfoTests.g34wBaseBlock
            + EDIDInfoTests.hexBytes(EDIDInfoTests.g34wExtensionHex))
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, edidData: edidData)))
        // The verdict is unknown without the node; this test is about the EDID parse.
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.facts.monitorName == "LEN G34w-10")
        // 100 Hz now comes from the real 3440x1440@100 detailed timing.
        #expect(diag.facts.maxRefreshHz == 100)
    }

    // MARK: - Helpers

    @Test("portKey joins the DP node to its owning port (probe 17 values)")
    func portKeyCorrelation() {
        // Probe 17's active display reports ParentPortType 2 (USB-C) and
        // ParentPortNumber 4, which must join to a port whose portKey is
        // "2/4" (the PowerSource / AppleHPMInterface scheme).
        let dp = IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: true, laneCount: 4, maxLaneCount: 4, linkRate: 3,
                linkRateDescription: "5.4 Gbps (HBR2)", tunneled: false, hpdState: 1
            ),
            monitor: nil,
            parentPortType: 2,
            parentPortNumber: 4
        )
        #expect(dp.portKey == "2/4")
    }

    // MARK: - Branch device

    @Test("Names the adapter's reported DisplayPort version in the verdict")
    func adapterNamesBranchDevice() throws {
        // The real G34w case: HDMI adapter reporting "Dp1.2", 2 of 4 lanes.
        let dp = makeDP(lanes: 2, dfpType: "HDMI", branchDeviceId: "Dp1.2", currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w))
        #expect(diag.bottleneck == .adapterLimit)
        #expect(diag.facts.branchDevice == "DisplayPort 1.2")
        #expect(diag.detail.contains("DisplayPort 1.2"))
    }

    @Test("Adapter with no branch device keeps the plain wording")
    func adapterNoBranchDevice() throws {
        let dp = makeDP(lanes: 2, dfpType: "HDMI", branchDeviceId: nil, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w))
        #expect(diag.bottleneck == .adapterLimit)
        #expect(diag.facts.branchDevice == nil)
        #expect(!diag.detail.contains("reports as"))
    }

    @Test("branchDeviceLabel normalises the Dp version and falls back safely")
    func branchDeviceLabelParse() {
        #expect(DisplayDiagnostic.branchDeviceLabel("Dp1.2") == "DisplayPort 1.2")
        #expect(DisplayDiagnostic.branchDeviceLabel("DP2.1") == "DisplayPort 2.1")
        #expect(DisplayDiagnostic.branchDeviceLabel("  Dp 1.4 ") == "DisplayPort 1.4")
        #expect(DisplayDiagnostic.branchDeviceLabel("CustomHub") == "CustomHub")
        #expect(DisplayDiagnostic.branchDeviceLabel("dp") == "dp")
        #expect(DisplayDiagnostic.branchDeviceLabel("") == nil)
        #expect(DisplayDiagnostic.branchDeviceLabel(nil) == nil)
    }

    @Test("Parses per-lane Gbps from the macOS rate description")
    func parsesRate() {
        #expect(DisplayDiagnostic.perLaneGbps(fromDescription: "5.4 Gbps (HBR2)") == 5.4)
        #expect(DisplayDiagnostic.perLaneGbps(fromDescription: "8.1 Gbps (HBR3)") == 8.1)
        #expect(DisplayDiagnostic.perLaneGbps(fromDescription: "20 Gbps (UHBR20)") == 20)
        #expect(DisplayDiagnostic.perLaneGbps(fromDescription: "No Link") == nil)
        #expect(DisplayDiagnostic.perLaneGbps(fromDescription: nil) == nil)
    }

    // MARK: - Live sample: LG UltraFine 4K over a tunnelled DP link

    @Test("Live LG UltraFine 4K on tunnelled 4-lane HBR2: probe 33 alone reads unknown, cable exonerated")
    func liveLGUltraFineTunnelled() throws {
        // Real capture (M3 Max, Test Kit probe 33, 2026-05-30): a native-DP LG
        // UltraFine 4K reached over a Thunderbolt/USB4 tunnel at 4 lanes HBR2.
        // Probe 33 alone carries no display-node statement, so the top mode's
        // availability cannot be read (issue #664); the tunnel still exercises
        // the cable-exoneration path that only synthetic tests hit before.
        let edid = Data(EDIDInfoTests.hexBytes(EDIDInfoTests.lgUltraFineHex))
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 4, tunneled: true, edidData: edid))
        )
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.cableAssessment == .unlikelyTheCable)
        #expect(diag.facts.monitorName == "LG UltraFine")
        #expect(diag.facts.lanes == 4)
        #expect(diag.detail.contains("could not be matched"))
    }

    // MARK: - DSC / compression at the DisplayPort ceiling (issue #246)

    /// AORUS FO32U2P: 4K240, ~56 Gbps uncompressed (2.34 GHz pixel clock x
    /// 24bpp). EDID ceiling 240Hz. Needs DSC over any Mac DisplayPort link.
    private let fo32 = EDIDInfo.fixture(
        name: "AORUS FO32U2P",
        version: (1, 4),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 4514, vTotal: 2160, pixelClockHz: 2_340_000_000),
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 240, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 2_340_000_000, timingSupport: .rangeLimitsOnly)
    )

    @Test("4K240 at the DP ceiling (4-lane HBR3) without a statement reads unknown, not a warning")
    func ceilingWithoutStatementIsUnknown() throws {
        // 56.16 Gbps uncompressed needed, 4 x 8.1 x 0.8 = 25.92 delivered. The
        // figure decides nothing (issue #664): without the display node the
        // top mode's availability cannot be read, and the verdict says so.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.isWarning == false)
        #expect(diag.summary == "Display connected")
        #expect(diag.detail.contains("could not be matched to your AORUS FO32U2P"), "\(diag.detail)")
        // No "monitor can do more" headline, no "change your resolution" advice.
        #expect(!diag.summary.lowercased().contains("can do more"))
    }

    @Test("At the ceiling, even a mode DSC can't fully cover reads unknown without a statement")
    func ceilingTriggersRegardlessOfDSCHeadroom() throws {
        // ~100 Gbps uncompressed need over 25.92 delivered: the figure is a
        // receipt and nothing branches on it, so this is unknown like any
        // other no-statement shortfall.
        let huge = EDIDInfo.fixture(
            name: "8K panel",
            version: (1, 4),
            preferred: EDIDInfo.mode(7680, 4320, hTotal: 16088, vTotal: 4320, pixelClockHz: 4_170_000_000),
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 0, maxVerticalHz: 60, minHorizontalKHz: 0, maxHorizontalKHz: 0,
                maxPixelClockHz: 4_170_000_000, timingSupport: .rangeLimitsOnly)
        )
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: huge))
        #expect(diag.bottleneck == .unknownMode)
    }

    @Test("HBR3 but not all lanes, the node lists the picture at 60Hz only: belowMonitorMax")
    func hbr3PartialLanesStillWarns() throws {
        // 2 of 4 lanes at HBR3, driven at 4K60 with the node listing 4K60
        // only: the 240 Hz top is not listed at that picture (pictureOnly),
        // so the ordinary shortfall verdict stands and still warns.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_250_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: Self.offering([Self.listing(3840, 2160, 60.0, 533_250_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.isWarning == true)
    }

    @Test("All lanes but a low rate, the node lists the picture at 60Hz only: belowMonitorMax")
    func allLanesLowRateStillWarns() throws {
        // 4 of 4 lanes at HBR2, the same live mode and statement: the 240 Hz
        // top is pictureOnly, so the ordinary verdict.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_250_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", currentMode: live, drivenTiming: Self.offering([Self.listing(3840, 2160, 60.0, 533_250_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .belowMonitorMax)
    }

    @Test("Tunneled DP at the ceiling without a statement reads unknown, cable still exonerated")
    func tunneledAtCeilingWithoutStatementIsUnknown() throws {
        // A tunnelled DP link (TB/USB4 dock) at 4/4 HBR3 with the FO32 and no
        // statement. The tunnel still exonerates the cable in the structured
        // verdict; the verdict itself is unknown without the node.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.isWarning == false)
        #expect(diag.cableAssessment == .unlikelyTheCable)
    }

    // MARK: - CoreGraphics current-mode upgrade (issue #246 Option B / #249)

    @Test("Live mode at the panel's top mode upgrades compression to confirmed fine")
    func liveModeAtTopUpgradesToFine() throws {
        // FO32 at 4K240 over 4-lane HBR3 would be compressionPlausible, but a
        // matched live mode confirms it IS at 4K240, so we upgrade to .fine.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .fine)
        #expect(diag.isWarning == false)
        #expect(diag.detail.contains("3840 x 2160 @ 240Hz"))
    }

    @Test("Live mode below the top mode with no statement is unknown")
    func liveModeBelowTopDoesNotUpgrade() throws {
        // The display is actually running 4K60, short of its 240Hz top mode,
        // and there is no statement to say whether the top is offered.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .unknownMode)
    }

    @Test("No live mode and no statement is unknown")
    func noLiveModeNoStatementIsUnknown() throws {
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.facts.currentMode == nil)
        #expect(diag.facts.dscReading == nil)
        #expect(diag.facts.topModeAvailability == nil)
    }

    @Test("A 5K live mode surfaces in the facts even when the EDID under-reads it (issue #249)")
    func fiveKLiveModeInFacts() throws {
        // A Studio Display whose EDID can only describe a 4K-or-smaller mode.
        // The link is a TB tunnel, so the verdict is already .fine; the bug is
        // purely the label, which the live mode fixes.
        let studioEdid = EDIDInfo.fixture(
            name: "Studio Display",
            version: (1, 4),
            preferred: EDIDInfo.mode(4096, 2304, hTotal: 4340, vTotal: 2304, pixelClockHz: 600_000_000),
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 0, maxVerticalHz: 60, minHorizontalKHz: 0, maxHorizontalKHz: 0,
                maxPixelClockHz: 600_000_000, timingSupport: .rangeLimitsOnly)
        )
        let live = DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: studioEdid))
        #expect(diag.facts.currentMode?.width == 5120)
        #expect(diag.facts.currentMode?.height == 2880)
        #expect(diag.facts.currentMode?.label == "5120 x 2880 @ 60Hz")
    }

    // MARK: - Real corpus EDID (AORUS FO32U2P, customer probe m2pro_macos26.6)

    /// The actual 384-byte EDID the Test Kit captured from @buliwyf42's AORUS
    /// FO32U2P (probe 33, serial bytes redacted at source). Baked in as a
    /// fixture so the parse + verdict are tested against real hardware data
    /// without needing the corpus on disk.
    private static let fo32RealEDID = decodeHex(
        "00ffffffffffff001c5415320000000009220104b5452778fb0ad5af4e3eb5240e5054bf" +
        "ef80714f81c08100814081809500a9c0b3004dd000a0f0703e8030203500bb8b2100001a" +
        "000000fd0c30f0ffffea010a202020202020000000fc00414f52555320464f3332553250" +
        "000000ff0000000000000000000000000000020d02033c704f6175765e5f603f4003040f" +
        "10131f292309570783010000741a0000030330f000a067024f02f0000000000000e305c3" +
        "01e6060d01674f026fc200a0a0a0555030203500bb8b2100001a565e00a0a0a029503020" +
        "3500bb8b2100001a00000000000000000000000000000000000000000000000000000000" +
        "0000005e7012790300030164e9ec00047f079f002f801f003704860002000400ca9c0104" +
        "ff099f002f801f009f05b20002000400bb5a0204ff0e9f002f801f006f08b10002000400" +
        "5be70204ff0e9f002f801f006f08da0002000400f77e0304ff0edf002f801f006f08bc00" +
        "02000400000000000000000000000000000000000000f090"
    )

    private static func decodeHex(_ s: String) -> Data {
        var data = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            data.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return data
    }

    @Test("Real FO32U2P EDID from the corpus parses to its 4K240 top mode")
    func corpusEDIDParses() throws {
        // Fixture guard: the real corpus bytes, not a mistyped/truncated copy.
        #expect(Self.fo32RealEDID.count == 384)
        let edid = try #require(EDIDInfo(Self.fo32RealEDID))
        #expect(edid.monitorName == "AORUS FO32U2P")
        #expect(edid.preferredWidth == 3840)
        #expect(edid.preferredHeight == 2160)
        #expect(edid.rangeLimits?.maxVerticalHz == 240)
        // The 240 Hz mode lives in the DisplayID extension block.
        #expect(edid.topMode?.pixelClockHz == 2_291_120_000)
        #expect(edid.topMode.map { Int($0.refreshHz.rounded()) } == 240)
        // Product id (EDID bytes 10-11) is 0x3215 = 12821, the corpus value.
        #expect(Self.fo32RealEDID[10] == 0x15 && Self.fo32RealEDID[11] == 0x32)
    }

    @Test("Real corpus EDID at the DP ceiling without a statement is unknown")
    func corpusEDIDWithoutStatementIsUnknown() throws {
        // CoreGraphics supplies the 4K240 top mode, exactly as it does on the
        // live app path. Without the display node's statement the top mode's
        // availability cannot be read.
        let top = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)",
                        edidData: Self.fo32RealEDID, maxMode: top)
        let diag = try #require(DisplayDiagnostic(dp: dp))
        #expect(diag.bottleneck == .unknownMode)
    }

    @Test("Real corpus EDID with no CoreGraphics data reads its parsed timings; the verdict is unknown without a statement")
    func corpusEDIDWithoutCoreGraphicsReadsItsParsedTimings() throws {
        // The FO32U2P's 240 Hz modes live in a DisplayID extension block,
        // now parsed, so its highest detailed timing is the real 3840x2160
        // @240 at 2291.12 MHz rather than an understated 4K60. The figure is
        // still computed as a receipt; the verdict is unknown without the
        // display node (issue #664).
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", edidData: Self.fo32RealEDID)
        let diag = try #require(DisplayDiagnostic(dp: dp))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.isWarning == false)
        let edid = try #require(EDIDInfo(Data(Self.fo32RealEDID)))
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: edid))
        #expect(top.pixelClockHz == 2_291_120_000, "expected the 2291.12 MHz 4K240 DisplayID timing, got \(String(describing: top.pixelClockHz))")
        let needed = try #require(diag.facts.neededGbps)
        #expect(needed > 25.92)
        #expect(diag.facts.maxRefreshHz == 240)
    }

    @Test("Real corpus EDID plus a matched 4K240 live mode confirms full quality")
    func corpusEDIDUpgradesWithLiveMode() throws {
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)",
                        edidData: Self.fo32RealEDID, currentMode: live, maxMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp))
        #expect(diag.bottleneck == .fine)
        #expect(diag.detail.contains("3840 x 2160 @ 240Hz"))
    }

    // MARK: - CoreGraphics max mode against the declared list

    /// An EDID that understates a 240Hz panel: its highest declared entry is
    /// 4K120, so the declared list tops out there and only CoreGraphics knows
    /// the panel really reaches 240. The 1.3 GHz top timing also keeps the link
    /// short of the uncompressed top, so the compression branch (where the
    /// at-top-mode check runs) is reached rather than short-circuiting on
    /// `.fine`. Its range-limits refresh is absent on purpose, proving the
    /// diagnostic never needs it.
    private let understatedEdid = EDIDInfo.fixture(
        name: "Understated 4K",
        version: (1, 4),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 4113, vTotal: 2160, pixelClockHz: 533_000_000),
        modes: [EDIDInfo.mode(3840, 2160, hTotal: 5015, vTotal: 2160, pixelClockHz: 1_300_000_000,
                               source: .detailedTiming(block: 1, index: 0))],
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 0, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 2_340_000_000, timingSupport: .rangeLimitsOnly)
    )

    @Test("With no CG max mode, an understated EDID top falsely confirms a 120Hz mode")
    func understatedEdidWithoutMaxModeOverconfirms() throws {
        // The declared list tops out at 4K120, so a 120Hz live mode is at
        // that top and reads as full quality: right against the list, wrong
        // against the panel, and the list is all there is without CoreGraphics.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: understatedEdid))
        #expect(diag.bottleneck == .fine)
    }

    @Test("A CG max mode above every declared entry is macOS only; the live mode at it is fine, below it unknown")
    func cgMaxModeAboveDeclaredListIsMacOSOnly() throws {
        // Same understated EDID, and CoreGraphics names 4K240 as the top mode.
        // No declared entry is 4K240 and no tiled composite explains it, so
        // its pixel clock is nowhere we can read and the receipt is nil. With
        // no statement, a live mode below it (a) is unknown; a live mode at
        // macOS's own top (b) is the picture at the top mode (ruling 18: the
        // guard that said unknown here is gone; nothing branches on the figure).
        let top = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let below = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let a = try #require(DisplayDiagnostic(
            dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: below, maxMode: top),
            edid: understatedEdid))
        #expect(a.bottleneck == .unknownMode, "got \(a.bottleneck)")
        #expect(a.facts.topModeSource == "macOS only")
        #expect(a.facts.neededGbps == nil)
        #expect(a.detail.contains("could not be matched"))
        let b = try #require(DisplayDiagnostic(
            dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: top, maxMode: top),
            edid: understatedEdid))
        #expect(b.bottleneck == .fine, "got \(b.bottleneck)")
        #expect(b.facts.maxRefreshHz == 240)
        #expect(b.detail.contains("at its top mode (3840 x 2160 @ 240Hz)"), "got \(b.detail)")
    }

    @Test("The CG max mode is carried in the facts for the capability label")
    func maxModeSurfacesInFacts() throws {
        let top = DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, currentMode: top, maxMode: top)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.facts.maxMode?.width == 5120)
        #expect(diag.facts.maxMode?.height == 2880)
    }

    @Test("No Billboard note when the link is at the ceiling and the verdict is unknown")
    func noBillboardNoteAtCeilingUnknown() throws {
        // Without a statement we can't say the link is below the monitor's
        // best mode, so the corroborating signal the Billboard diagnosis needs
        // is absent and the note must stay silent, even with a Billboard
        // device present.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32, billboardPresent: true))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.billboardNote == nil)
    }

    // MARK: - DSC provably active (Jimmy's group feedback)

    /// DELL U2725QE: 4K 27-inch, DisplayPort 1.4, needs DSC for 4K120. This
    /// is the case Jimmy's group saw misdiagnosed as a refresh-rate / cable
    /// issue. EDID claims a 4K120 top mode at 4K60-ish pixel clock (the EDID
    /// can describe DSC modes with a lower clock); the live mode is the proof.
    private let dellU2725QE = EDIDInfo.fixture(
        name: "DELL U2725QE",
        version: (1, 4),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 4113, vTotal: 2160, pixelClockHz: 533_000_000),
        modes: [EDIDInfo.mode(3840, 2160, hTotal: 4244, vTotal: 2160, pixelClockHz: 1_100_000_000,
                               source: .detailedTiming(block: 1, index: 0))],
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 120, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 1_100_000_000, timingSupport: .rangeLimitsOnly)
    )

    @Test("4K120 over a 2-lane HBR3 link at the top mode without a statement reads fine, hedged")
    func liveModeAtTopWithoutStatementIsFineHedged() throws {
        // Link: 2 of 4 lanes at HBR3. Live mode: 4K120, the panel's top. With
        // no statement the picture at the top mode is the answer, hedged (S18):
        // nothing here says whether DSC carries it.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .fine)
        #expect(diag.isWarning == false)
        #expect(diag.detail.contains("3840 x 2160 @ 120Hz"))
        #expect(diag.detail.contains("link rate alone can't show it"))
        // The old "monitor can do more / change your resolution" wording must
        // not appear here: that's the whole point of the fix.
        #expect(!diag.summary.lowercased().contains("can do more"))
    }

    @Test("Live mode below the top with the node listing the picture at 60Hz only: belowMonitorMax, uncompressed")
    func liveModeWithinLinkDoesNotClaimDSC() throws {
        // Same DELL panel, driven at 4K60 over a 2-lane HBR3 link, the node
        // listing 4K60 only: the 4K120 top is pictureOnly, and the driven
        // lists say uncompressed.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_000_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: Self.offering([Self.listing(3840, 2160, 60.0, 533_000_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.facts.dscReading == .uncompressed)
    }

    @Test("No current mode and no statement below the top is unknown")
    func noCurrentModeNoStatementIsUnknown() throws {
        // A 2-lane HBR3 link with the DELL's top mode above it, no live mode
        // and no statement: nothing to judge the top mode with.
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .unknownMode)
    }

    @Test("compressionActive is not a warning and silences the Billboard note")
    func compressionActiveSilencesBillboardNote() throws {
        // Billboard-note gate is `isWarning`. DSC on, as macOS states it, is
        // the link doing its job, not a degraded link, so the note stays silent.
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: Self.liveU3225QE, drivenTiming: Self.statementU3225QE)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE, billboardPresent: true))
        #expect(diag.bottleneck == .compressionActive)
        #expect(diag.billboardNote == nil)
    }

    @Test("A live mode at the top mode beats the adapter verdict (ruling 17)")
    func liveModeAtTopBeatsTheAdapterVerdict() throws {
        // An HDMI adapter in the chain, no statement, the live mode at the
        // panel's top: the picture at the top mode is the answer.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .fine)
        #expect(diag.detail.contains("at its top mode"))
    }

    // MARK: - Billboard-device note (gated on a degraded link)

    @Test("Billboard note fires only with a below-best-mode link present")
    func billboardNoteOnShortfall() throws {
        // 2-lane HBR2, the node lists the G34w's picture at 60Hz only (top not
        // offered) -> belowMonitorMax, and a Billboard device is on the port:
        // the note should appear.
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w, billboardPresent: true)
        )
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.billboardNote != nil)
    }

    @Test("Billboard note fires behind a degraded adapter link too")
    func billboardNoteOnAdapterShortfall() throws {
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2, dfpType: "HDMI", currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w, billboardPresent: true)
        )
        #expect(diag.bottleneck == .adapterLimit)
        #expect(diag.billboardNote != nil)
    }

    @Test("No Billboard note when the link already carries the top mode")
    func noBillboardNoteWhenFine() throws {
        // 4-lane HBR2 driven at the 100Hz top, stated uncompressed -> .fine.
        // Even with a Billboard device present, the diagnosis must not fire: a
        // Billboard device on a healthy link is benign.
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 4, currentMode: Self.liveG34w100, drivenTiming: Self.offering([Self.g34wAt60, Self.g34wAt100])), edid: g34w, billboardPresent: true)
        )
        #expect(diag.bottleneck == .fine)
        #expect(diag.billboardNote == nil)
    }

    @Test("No Billboard note when the mode can't be compared")
    func noBillboardNoteWhenUnknown() throws {
        // No readable EDID -> .unknownMode: we can't claim "below best mode",
        // so the corroborating signal is absent and the note stays silent.
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2), edid: nil, billboardPresent: true)
        )
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.billboardNote == nil)
    }

    @Test("No Billboard note when no Billboard device is present")
    func noBillboardNoteWhenAbsent() throws {
        // Degraded link, but billboardPresent defaults to false: no note. This
        // is also the inline path's behaviour (it never passes the flag).
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.billboardNote == nil)
    }

    // MARK: - Native HDMI port (issue #352)

    /// Make a DP node sitting on a built-in HDMI port (M3 Pro/Max/M4/M5 MBP,
    /// Mac mini Pro, Mac Studio). Mirrors the corpus value shape:
    /// `ParentPortTypeDescription = "HDMI"`, `ParentPortType = 6`,
    /// `Tunneled = false`. Issue #352.
    private func makeHDMIPortDP(
        lanes: Int = 4,
        maxLanes: Int = 4,
        rateDesc: String? = "8.1 Gbps (HBR3)",
        dfpType: String? = "HDMI",
        edidData: Data? = nil,
        currentMode: DisplayCurrentMode? = nil,
        maxMode: DisplayCurrentMode? = nil,
        drivenTiming: DisplayTimingStatement? = nil
    ) -> IOPortTransportStateDisplayPort {
        // Matches the corpus shape for an M-series MBP / Mac mini / Studio
        // native HDMI port: `ParentPortType = 6`, `ParentPortTypeDescription
        // = "HDMI"`. `ParentPortBuiltIn` is intentionally left at its default
        // `false` because real IOKit DP nodes don't emit it for HDMI ports
        // (0 of 79 corpus blocks). Issue #352.
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: true,
                laneCount: lanes,
                maxLaneCount: maxLanes,
                linkRate: 4,
                linkRateDescription: rateDesc,
                tunneled: false,
                hpdState: 1
            ),
            monitor: edidData.map {
                MonitorInfo(
                    manufacturerName: nil, productName: nil, productId: nil,
                    yearOfManufacture: nil, edid: $0
                )
            },
            dfpType: dfpType,
            parentPortType: 6,
            parentPortTypeDescription: "HDMI",
            parentPortNumber: 1,
            currentMode: currentMode,
            maxMode: maxMode,
            drivenTiming: drivenTiming
        )
    }

    @Test("Native HDMI port at HBR3 4/4 lanes: never the 'USB-C to HDMI adapter' verdict")
    func nativeHDMIPortSkipsAdapterVerdict() throws {
        // The reporter's case (M3 Max MBP -> native HDMI -> ASUS PG42UQ): 4K120
        // panel that needs ~31 Gbps uncompressed, link is 4/4 lanes at HBR3
        // carrying ~25.9 Gbps. Pre-fix this fired the adapter-blame branch even
        // though there is no adapter on the path. Post-fix sinkType is gated
        // to nil for native HDMI ports, so we never reach .adapterLimit and
        // either land on .fine (current matches max) or on the DSC carve-out.
        let panel = EDIDInfo.fixture(
            name: "PG42UQ",
            version: (1, 4),
            preferred: EDIDInfo.mode(3840, 2160, hTotal: 5015, vTotal: 2160, pixelClockHz: 1_300_000_000),
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 0, maxVerticalHz: 120, minHorizontalKHz: 0, maxHorizontalKHz: 0,
                maxPixelClockHz: 1_300_000_000, timingSupport: .rangeLimitsOnly)
        )
        let dp = makeHDMIPortDP()
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel))
        #expect(diag.bottleneck != .adapterLimit)
        #expect(!diag.detail.contains("USB-C"))
        #expect(!diag.summary.contains("HDMI adapter"))
    }

    @Test("Native HDMI port at HBR3 4/4 lanes without a statement: unknown, not adapter blame")
    func nativeHDMIPortWithoutStatementIsUnknown() throws {
        // Same shape as the reporter's case: native HDMI port, HBR3 4/4 lanes,
        // no live mode and no statement. sinkType is nil (the SoC drives HDMI
        // directly), so the adapter verdict cannot fire; with nothing to
        // judge the top mode against the verdict is unknown.
        let panel = EDIDInfo.fixture(
            name: "PG42UQ",
            version: (1, 4),
            preferred: EDIDInfo.mode(3840, 2160, hTotal: 5015, vTotal: 2160, pixelClockHz: 1_300_000_000),
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 0, maxVerticalHz: 120, minHorizontalKHz: 0, maxHorizontalKHz: 0,
                maxPixelClockHz: 1_300_000_000, timingSupport: .rangeLimitsOnly)
        )
        let dp = makeHDMIPortDP()
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.facts.sinkType == nil)
    }

    @Test("USB-C-to-HDMI dongle keeps the adapter verdict")
    func usbCToHDMIDongleStillFlagsAdapter() throws {
        // The opposite shape: same dfpType ("HDMI") but the parent port is
        // USB-C, so there really is an adapter in the chain. Adapter blame
        // must still fire for this case; the fix is gated on parent port
        // type, not on dfpType.
        let dp = IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: true, laneCount: 2, maxLaneCount: 4, linkRate: 3,
                linkRateDescription: "5.4 Gbps (HBR2)", tunneled: false, hpdState: 1
            ),
            monitor: nil,
            dfpType: "HDMI",
            parentPortType: 2,
            parentPortTypeDescription: "USB-C",
            parentPortNumber: 1,
            currentMode: Self.liveG34w60,
            drivenTiming: Self.offering([Self.g34wAt60])
        )
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w))
        #expect(diag.bottleneck == .adapterLimit)
    }

    // MARK: - Cable classification (port controller)

    private func hpmPort(activeCable: Bool?) -> USBCPort {
        USBCPort(
            id: 1, serviceName: "Port-USB-C@1", className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C",
            portNumber: 1, connectionActive: true, activeCable: activeCable, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "DisplayPort"], transportsActive: ["DisplayPort"],
            transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
    }

    @Test("A port-promoted cable is no longer exonerated on the lane signal")
    func portPromotedCableIsNotExonerated() throws {
        // Same all-lanes shortfall as `allLanesExonerates`. The e-marker says
        // passive, but the port controller says the cable is active, and we
        // never exonerate a cable that could be active (issue #111).
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "1.62 Gbps (RBR)")
        let diag = try #require(
            DisplayDiagnostic(dp: dp, edid: g34w, cable: cable(active: false), port: hpmPort(activeCable: true))
        )
        #expect(diag.cableAssessment == .inconclusive)
    }

    @Test("With no port the passive exoneration is unchanged")
    func noPortLeavesExonerationUnchanged() throws {
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "1.62 Gbps (RBR)")
        let diag = try #require(
            DisplayDiagnostic(dp: dp, edid: g34w, cable: cable(active: false), port: nil)
        )
        #expect(diag.cableAssessment == .unlikelyTheCable)
    }

    @Test("A layout-contradiction cable loses its exoneration even with no port")
    func layoutContradictionCableIsNotExoneratedWithoutAPort() throws {
        // The CalDigit 2M Thunderbolt 4 cable from issue #111: VDO[3] is
        // decoded under the passive layout on purpose, so the old
        // self-report read it as passive and exonerated it. The classifier
        // resolves it active from the layout contradiction alone, with no
        // port involved, so the exoneration goes away on this path too.
        let identity = USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0x97,
            vdos: [0x1C002B1D, 0x00000000, 0x19010097, 0x3208485A],
            specRevision: 3
        )
        #expect(identity.cableVDO?.cableType == .passive, "fixture guard: the self-report still reads passive")
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "1.62 Gbps (RBR)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w, cable: identity, port: nil))
        #expect(diag.cableAssessment == .inconclusive)
    }

    // MARK: - Issue #596: the 0xFD envelope is a range, not a mode

    /// AOC U24P10R, the panel in issue #596. A 4K60 monitor whose 0xFD
    /// range-limits descriptor declares a 75 Hz / 600 MHz envelope it has no
    /// mode for. Its only real top mode is the 4K60 detailed timing at
    /// 533.25 MHz.
    private let aocU24P10R = EDIDInfo.fixture(
        name: "AOC U24P10R",
        version: (1, 4),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000),
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 75, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 600_000_000, timingSupport: .rangeLimitsOnly)
    )

    @Test("Issue #596: a 4K60 panel is never told it can run the 75Hz its 0xFD envelope declares")
    func envelopeRefreshIsNotClaimedAsAMode() throws {
        // 2 of 4 lanes at HBR3, driven at the panel's real 4K60 timing with
        // the node listing it: the live mode meets the top, so the correct
        // verdict is the all-clear (K1). The 75 Hz envelope is never a mode.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_250_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: Self.offering([Self.listing(3840, 2160, 59.99, 533_250_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: aocU24P10R))
        #expect(diag.bottleneck == .fine)
        #expect(diag.isWarning == false)
        #expect(diag.facts.maxRefreshHz == 60)
        #expect(!diag.detail.contains("75"), "the 75Hz scan ceiling must never reach the user as a mode")
        #expect(!diag.summary.contains("75"))
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 12.798) < 0.01)
    }

    /// ASUS PG27AQDP, from customer probe `m1pro_macos26.5_y`: the corpus's
    /// worst envelope overstatement. Its 0xFD descriptor declares a 2.52 GHz /
    /// 225 Hz envelope while its highest real detailed timing is 2560x1440@60
    /// at 248.87 MHz, a 10x gap in pixel clock.
    private let pg27AQDP = EDIDInfo.fixture(
        name: "PG27AQDP",
        version: (1, 4),
        preferred: EDIDInfo.mode(2560, 1440, hTotal: 2795, vTotal: 1440, pixelClockHz: 241_500_000),
        modes: [EDIDInfo.mode(2560, 1440, hTotal: 2880, vTotal: 1440, pixelClockHz: 248_870_000,
                               source: .detailedTiming(block: 1, index: 0))],
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 225, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 2_520_000_000, timingSupport: .rangeLimitsOnly)
    )

    @Test("The corpus's worst envelope overstatement stops claiming 60 Gbps")
    func worstEnvelopeOverstatementReadsItsRealTopMode() throws {
        // Envelope route: 2.52 GHz x 24bpp = 60.48 Gbps, a figure no
        // DisplayPort link on any Mac could ever carry. Declared top entry:
        // 248.87 MHz x 24bpp = 5.97 Gbps, and that is the figure, because the
        // declared list is the only place a pixel clock is read from. (The
        // real PG27AQDP declares its 480 Hz modes in blocks this fixture
        // leaves out; a fixture that omits them is a panel that lacks them.)
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: pg27AQDP))
        let clock = try #require(top.pixelClockHz)
        let needed = Double(clock) * Double(DisplayDiagnostic.topModeBitsPerPixel) / 1_000_000_000
        #expect(abs(needed - 5.973) < 0.05, "expected ~6.0 Gbps, got \(needed)")
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: pg27AQDP))
        #expect(diag.bottleneck == .unknownMode, "the figure is a receipt: `neededGbps` still reads 5.97; no statement, so the verdict is unknown, got \(diag.bottleneck)")
        #expect(diag.facts.neededGbps.map { abs($0 - 5.973) < 0.05 } == true,
                "got \(String(describing: diag.facts.neededGbps))")
        #expect(diag.facts.topModeSource == "detailed timing 1 (block 1)")
        #expect(!diag.detail.contains("225"), "the 225Hz scan ceiling must never reach the user as a mode")
    }

    @Test("No max mode: the declared top stands")
    func noMaxModeTheDeclaredTopStands() throws {
        // No CoreGraphics data at all. The highest-clock declared entry is
        // the top mode, and the 0xFD envelope is ignored even though it sits
        // well above it. (The issue #596 regression fixture, expectation
        // unchanged.)
        let panel = EDIDInfo.fixture(
            name: "Declared-top panel",
            version: (1, 4),
            preferred: EDIDInfo.mode(2560, 1440, hTotal: 2795, vTotal: 1440, pixelClockHz: 241_500_000),
            modes: [EDIDInfo.mode(2560, 1440, hTotal: 2880, vTotal: 1440, pixelClockHz: 497_750_000,
                                   source: .detailedTiming(block: 1, index: 0))],
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 0, maxVerticalHz: 144, minHorizontalKHz: 0, maxHorizontalKHz: 0,
                maxPixelClockHz: 1_200_000_000, timingSupport: .rangeLimitsOnly)
        )
        // Driven at 1440p60 with the node listing that picture at 60 Hz only:
        // the 120 Hz top is pictureOnly, so the shortfall verdict stands.
        let live = DisplayCurrentMode(width: 2560, height: 1440, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 241_500_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", currentMode: live, drivenTiming: Self.offering([Self.listing(2560, 1440, 60.0, 241_500_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel))
        #expect(diag.facts.maxMode == nil, "fixture guard: this path has no CoreGraphics data")
        #expect(diag.facts.maxRefreshHz == 120)
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 11.946) < 0.01, "expected the 497.75 MHz timing, got \(needed) Gbps")
        #expect(diag.facts.topModeSource == "detailed timing 1 (block 1)",
                "got \(String(describing: diag.facts.topModeSource))")
        #expect(diag.facts.declaredModeCount == 2)
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.detail.contains("120Hz"))
        // "144Hz", not "144": the live mode's label "2560 x 1440 @ 60Hz" (K2)
        // contains "144" as part of "1440", and the guard is about the
        // envelope's refresh reaching the user as a mode.
        #expect(!diag.detail.contains("144Hz"), "the 144Hz envelope must never reach the user")
    }

    // MARK: - Issue #596: the envelope is never consulted

    /// The reporter's own panel in issue #596, at his exact figures: a 600 MHz
    /// envelope against a 533.16 MHz declared timing. The envelope is a range
    /// of signals the panel accepts, not a mode it has, and nothing reads it.
    private let reporterU24P10R = EDIDInfo.fixture(
        name: "U24P10R",
        version: (1, 4),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 4114, vTotal: 2160, pixelClockHz: 533_160_000),
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 75, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 600_000_000, timingSupport: .rangeLimitsOnly)
    )

    @Test("Issue #596's own reporter keeps the all-clear: the envelope is never consulted")
    func reporterEnvelopeIsNeverConsulted() throws {
        // 4 of 4 lanes at HBR3, driven at the panel's real 4K60 mode at 533.16
        // MHz with the node listing it. The fix for his bug must leave him with
        // the all-clear (K1), not trade one wrong answer for another.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_160_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: Self.offering([Self.listing(3840, 2160, 60.0, 533_160_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: reporterU24P10R))
        #expect(diag.facts.maxMode == nil, "fixture guard: this path has no CoreGraphics data")
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck)")
        #expect(diag.facts.maxRefreshHz == 60)
        #expect(!diag.detail.contains("75"), "the 75Hz scan ceiling must never reach the user as a mode")
        #expect(!diag.summary.contains("75"))
    }

    @Test("Envelope absent or huge: the declared list alone drives the verdict")
    func envelopeAbsentOrHugeChangesNothing() throws {
        // (a) No 0xFD envelope at all. The declared 4K60 timing is the top
        // mode and the verdict is fine.
        let noEnvelope = EDIDInfo.fixture(
            name: "No envelope",
            version: (1, 4),
            preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000)
        )
        let live4K = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_250_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live4K, drivenTiming: Self.offering([Self.listing(3840, 2160, 60.0, 533_250_000)]))
        let a = try #require(DisplayDiagnostic(dp: dp, edid: noEnvelope))
        #expect(a.facts.maxMode == nil, "fixture guard: this path has no CoreGraphics data")
        #expect(a.bottleneck == .fine, "got \(a.bottleneck)")

        // (b) A 2.34 GHz / 240 Hz envelope on a panel that declares one
        // 1080p60 mode. The envelope is never read, so the single declared
        // mode is the top mode, the live 1080p60 meets it, and the verdict is
        // the same fine, with no 240 anywhere in it.
        let oneMode = EDIDInfo.fixture(
            name: "One declared mode",
            version: (1, 4),
            preferred: EDIDInfo.mode(1920, 1080, hTotal: 2292, vTotal: 1080, pixelClockHz: 148_500_000),
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 0, maxVerticalHz: 240, minHorizontalKHz: 0, maxHorizontalKHz: 0,
                maxPixelClockHz: 2_340_000_000, timingSupport: .rangeLimitsOnly)
        )
        let live1080 = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 148_500_000, pixelEncoding: .rgb444)
        let dp1080 = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live1080, drivenTiming: Self.offering([Self.listing(1920, 1080, 60.0, 148_500_000)]))
        let b = try #require(DisplayDiagnostic(dp: dp1080, edid: oneMode))
        #expect(b.facts.maxMode == nil, "fixture guard: this path has no CoreGraphics data")
        #expect(b.bottleneck == .fine, "got \(b.bottleneck)")
        #expect(b.facts.maxRefreshHz == 60)
        #expect(b.facts.declaredModeCount == 1)
        #expect(!b.detail.contains("240"), "the 240Hz envelope must never reach the user")
    }

    // MARK: - The top mode's refresh is shown with the top mode's own resolution

    /// Samsung Odyssey G60SD's shape, from customer probe `m5_macos27.0_p`:
    /// preferred 2560x1440@60, and a fastest timing of 1920x1080@240 that
    /// wins `topMode` on pixel clock. There is no 2560x1440@240
    /// mode, so a heading reading "2560 x 1440 · up to 240Hz" names a mode
    /// the panel does not have. Ten corpus panels share the shape.
    private let odysseyG60SD = EDIDInfo.fixture(
        name: "Odyssey G60SD",
        version: (1, 4),
        preferred: EDIDInfo.mode(2560, 1440, hTotal: 2795, vTotal: 1440, pixelClockHz: 241_500_000),
        modes: [EDIDInfo.mode(1920, 1080, hTotal: 2249, vTotal: 1080, pixelClockHz: 583_000_000,
                               source: .detailedTiming(block: 1, index: 0))],
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 240, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 600_000_000, timingSupport: .rangeLimitsOnly)
    )

    @Test("A top timing at a lower resolution than preferred carries its own resolution next to its refresh")
    func topModeRefreshIsPairedWithItsOwnResolution() throws {
        // No CoreGraphics data, so the 1920x1080@240 entry is the declared
        // top, and the facts the Pro heading is built from must say 1920 x
        // 1080 with 240, never 2560 x 1440 with 240.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: odysseyG60SD))
        #expect(diag.facts.maxMode == nil, "fixture guard: this path has no CoreGraphics data")
        #expect(diag.facts.maxRefreshHz == 240)
        #expect(diag.facts.topModeWidth == 1920,
                "the 240 Hz mode is 1920 wide, got \(String(describing: diag.facts.topModeWidth))")
        #expect(diag.facts.topModeHeight == 1080,
                "the 240 Hz mode is 1080 high, got \(String(describing: diag.facts.topModeHeight))")
        // The preferred mode is still reported as itself.
        #expect(diag.facts.preferredWidth == 2560)
        #expect(diag.facts.preferredHeight == 1440)
    }

    // Apple Pro Display XDR tile 1 (`edid-decode-data/apple-xdr-6k-tile1`, bytes in
    // `EDIDInfoTests.appleXDR6KTile1Hex`): no base-block DTD, eleven DisplayID Type I entries,
    // none flagged preferred. The diagnostic must read the EDID and resolve its declared top;
    // "capabilities aren't readable" is false for a panel that declares every mode it has.
    @Test("A display whose EDID has no base DTD still gets a resolved top mode and no preferred mode")
    func noBaseDTDEDIDResolvesATopMode() throws {
        let bytes = Data(EDIDInfoTests.hexBytes(EDIDInfoTests.appleXDR6KTile1Hex))
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", edidData: bytes)
        let diag = try #require(DisplayDiagnostic(dp: dp))
        #expect(diag.edid != nil)
        let top = try #require(diag.topMode)
        #expect(top.pixelClockHz != nil)
        #expect(diag.facts.topModeWidth == top.width && diag.facts.topModeHeight == top.height)
        #expect(diag.facts.preferredWidth == nil)
        #expect(diag.facts.preferredHeight == nil)
        #expect(diag.facts.preferredRefreshHz == nil)
        #expect(diag.facts.declaredModeCount == diag.edid?.modes.count)
    }

    // VIC 4 (1280x720p60, 74.25 MHz) and VIC 5 (1920x1080i60, 74.25 MHz), per the bundled
    // CTA-861 table. Same clock, so the larger picture wins the tie: the top mode is the
    // interlaced VIC 5. `EDIDMode.activePixelRate` halves for an interlaced entry (its
    // `refreshHz` is the field rate, and each field carries half the lines); the resolved
    // `TopMode` must carry the same figure, or step 4's macOS-only threshold judges
    // against double the panel's real pixel rate.
    @Test("An interlaced top mode's active pixel rate equals the entry it was built from")
    func interlacedTopModeActivePixelRateMatchesTheEntry() throws {
        let vic4 = EDIDInfo.mode(1280, 720, hTotal: 1650, vTotal: 750, pixelClockHz: 74_250_000,
                                 source: .ctaVIC(block: 1, vic: 4, native: false, ycbcr420Only: false))
        let vic5 = EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 74_250_000,
                                 interlaced: true, source: .ctaVIC(block: 1, vic: 5, native: false, ycbcr420Only: false))
        let edid = EDIDInfo.fixture(preferred: vic4, modes: [vic4, vic5])
        #expect(edid.topMode == vic5) // fixture guard
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: edid))
        #expect(top.interlaced == true)
        #expect(top.activePixelRate == vic5.activePixelRate)
        #expect(vic5.activePixelRate == 62_208_000)
        // A progressive 1920x1080 at 30 Hz carries the same active pixels as
        // 1080i60, and until PR #665's gate that was enough to "meet" it.
        // `meetsTopMode` is a picture-and-refresh identity now (Codex 1: the
        // throughput test called 1080p240 the same mode as 4K60), and 30 Hz
        // is not the entry's 60 Hz field rate, so it does not meet it. The
        // active-pixel figure above still matters to step 4.
        let live = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 30)
        #expect(DisplayDiagnostic.meetsTopMode(live, top: top) == false)
    }

    @Test("The top mode's resolution follows the entry that resolved it")
    func topModeResolutionFollowsTheResolvingEntry() throws {
        // CoreGraphics names a 5K mode no declared entry matches, so the top
        // mode is macOS only and its resolution is CoreGraphics' 5120 x 2880,
        // not the EDID's 4096 x 2304.
        let studio = EDIDInfo.fixture(
            name: "Studio Display",
            version: (1, 4),
            preferred: EDIDInfo.mode(4096, 2304, hTotal: 4340, vTotal: 2304, pixelClockHz: 600_000_000),
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 0, maxVerticalHz: 60, minHorizontalKHz: 0, maxHorizontalKHz: 0,
                maxPixelClockHz: 600_000_000, timingSupport: .rangeLimitsOnly)
        )
        let top = DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, maxMode: top)
        let cg = try #require(DisplayDiagnostic(dp: dp, edid: studio))
        #expect(cg.facts.topModeWidth == 5120, "got \(String(describing: cg.facts.topModeWidth))")
        #expect(cg.facts.topModeHeight == 2880, "got \(String(describing: cg.facts.topModeHeight))")
        #expect(cg.facts.topModeSource == "macOS only")
        #expect(cg.facts.maxRefreshHz == 60)

        // One declared mode and no CoreGraphics data: the preferred mode is
        // the top mode and carries its own resolution.
        let oneMode = EDIDInfo.fixture(
            name: "One declared mode",
            version: (1, 4),
            preferred: EDIDInfo.mode(1920, 1080, hTotal: 2292, vTotal: 1080, pixelClockHz: 148_500_000)
        )
        let plain = try #require(DisplayDiagnostic(dp: makeDP(), edid: oneMode))
        #expect(plain.facts.topModeWidth == 1920)
        #expect(plain.facts.topModeHeight == 1080)
        #expect(plain.facts.maxRefreshHz == 60)
        #expect(plain.facts.topModeSource == "detailed timing 1 (block 0)")
    }

    // MARK: - A CoreGraphics max mode may raise the top mode, never lower it

    /// A 4K60 panel as its EDID declares it: one real 4K60 detailed timing at
    /// 533.25 MHz. The `maxMode` in the tests below is what CoreGraphics may
    /// report for it on a 2-lane link that cannot carry 4K60: the mode list is
    /// the one System Settings shows, and it shrinks with the link.
    private let fourK60Panel = EDIDInfo.fixture(
        name: "4K60 panel",
        version: (1, 4),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000),
        rangeLimits: EDIDInfo.RangeLimits(
            minVerticalHz: 0, maxVerticalHz: 75, minHorizontalKHz: 0, maxHorizontalKHz: 0,
            maxPixelClockHz: 600_000_000, timingSupport: .rangeLimitsOnly)
    )

    @Test("A CG max mode below the EDID's top timing is link-limited and must not read as fine")
    func linkLimitedMaxModeDoesNotReadAsFine() throws {
        // 2 of 4 lanes at HBR2 carries 8.64 Gbps. The panel's real 4K60 mode
        // needs 12.80 Gbps, so this is the textbook shortfall the diagnostic
        // exists to report. CoreGraphics names 4K30 as the top mode because
        // 4K30 is all this link can carry: that describes the link, not the
        // panel. Taking it as the top mode would clear the link against a
        // 6.4 Gbps figure and reassure the user about the exact cap they came
        // to ask about.
        let linkLimited = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30)
        // Driven at 4K30 with the node listing 4K30 only: the 60 Hz top is pictureOnly.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30, bitsPerComponent: 8, pixelClockHz: 266_625_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", currentMode: live, maxMode: linkLimited, drivenTiming: Self.offering([Self.listing(3840, 2160, 30.0, 266_625_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fourK60Panel))
        #expect(diag.bottleneck != .fine,
                "a 4K60 panel on a link that carries 4K30 is not at full quality, got \(diag.bottleneck)")
        #expect(diag.bottleneck == .belowMonitorMax, "got \(diag.bottleneck)")
        #expect(diag.facts.maxRefreshHz == 60,
                "the top mode is the panel's 60 Hz, not the link's 30, got \(String(describing: diag.facts.maxRefreshHz))")
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 12.798) < 0.01, "expected the 4K60 timing's 12.8 Gbps, got \(needed)")
    }

    @Test("A CG max mode matching the EDID's top timing is labelled from that entry")
    func matchingMaxModeIsLabelledFromItsEntry() throws {
        // Same panel, and CoreGraphics agrees with the EDID that 4K60 is top.
        // 4 of 4 lanes at HBR3 carries 25.92 Gbps, so the all-clear stands,
        // with the timing's own pixel clock behind the figure.
        let cg60 = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_250_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, maxMode: cg60, drivenTiming: Self.offering([Self.listing(3840, 2160, 60.0, 533_250_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fourK60Panel))
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck)")
        #expect(diag.facts.maxRefreshHz == 60)
        #expect(diag.facts.topModeSource == "detailed timing 1 (block 0)")
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 12.798) < 0.01, "expected the 4K60 timing's 12.8 Gbps, got \(needed)")
    }

    @Test("meetsTopMode: a live 4K30 against a link-limited 4K30 max mode is not the panel's top")
    func meetsTopModeIsAnIdentityTestAgainstTheResolvedTop() throws {
        // CoreGraphics says the top is 4K30 and the live mode is 4K30, so on a
        // CG-only reading the display is "at its top mode". The EDID declares
        // a 4K60 timing, a mode the panel really has, so the resolved top is
        // that entry and 4K30 falls short of it.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30)
        let linkLimited = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30)
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: linkLimited, edid: fourK60Panel))
        #expect(DisplayDiagnostic.meetsTopMode(live, top: top) == false,
                "4K30 is not the top mode of a panel with a 4K60 timing")
        // And with CoreGraphics agreeing on 4K60, a live 4K60 does meet it.
        let cg60 = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let top60 = try #require(DisplayDiagnostic.resolveTopMode(maxMode: cg60, edid: fourK60Panel))
        #expect(DisplayDiagnostic.meetsTopMode(cg60, top: top60) == true)
    }

    @Test("meetsTopMode is a picture-and-refresh identity: 1080p240 does not meet a 4K60 top, whatever the pixel throughput (PR #665 gate, Codex 1)")
    func meetsTopModeNeedsTheSamePicture() throws {
        // 1920 x 1080 x 240 and 3840 x 2160 x 60 are the same 497.7 Mpx/s; the
        // user is getting a quarter of the pixels. Identity is the picture and
        // the refresh (within CoreGraphics' rounding or the CTA alternate),
        // never a throughput figure.
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: fourK60Panel))
        let quarter = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 240, bitsPerComponent: 8, pixelClockHz: 594_000_000, pixelEncoding: .rgb444)
        #expect(DisplayDiagnostic.meetsTopMode(quarter, top: top) == false)
        // Through the verdict: driven at 1080p240 uncompressed with the node
        // listing that timing only, the 4K60 top is not listed (K26), never
        // "running at full quality".
        let statement = Self.offering([Self.listing(1920, 1080, 240.0, 594_000_000)])
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: quarter, drivenTiming: statement), edid: fourK60Panel))
        #expect(diag.bottleneck != .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.facts.topModeMatch == .notListed)
        // Same picture, refresh within CoreGraphics' whole-hertz rounding
        // (0.5 Hz of the DTD's 59.99): at the top. A whole hertz off is
        // another mode.
        #expect(DisplayDiagnostic.meetsTopMode(DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 59.94005994), top: top) == true)
        #expect(DisplayDiagnostic.meetsTopMode(DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60.4), top: top) == true)
        #expect(DisplayDiagnostic.meetsTopMode(DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 61), top: top) == false)
        // The CTA alternate (top / 1.001) counts as the same mode even where
        // it falls outside the rounding window, which needs a top above 500 Hz.
        let fast = DisplayDiagnostic.TopMode(width: 1920, height: 1080, refreshHz: 1000, pixelClockHz: nil, interlaced: false, source: .reportedByMacOSOnly)
        #expect(DisplayDiagnostic.meetsTopMode(DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 1000 / 1.001), top: fast) == true)
        #expect(DisplayDiagnostic.meetsTopMode(DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 998), top: fast) == false)
    }

    // MARK: - The diagnostic reads the declared list and derives nothing

    /// A 4K panel that declares its 60 Hz mode as the base-block preferred
    /// DTD (533.25 MHz) and its 144 Hz mode as a DisplayID Type I timing in
    /// block 2 (1306.21 MHz, the shape of the corpus's "Beyond TV").
    private let fourK144Panel = EDIDInfo.fixture(
        name: "4K144 panel",
        version: (1, 4),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000),
        modes: [EDIDInfo.mode(3840, 2160, hTotal: 4082, vTotal: 2222, pixelClockHz: 1_306_210_000,
                               source: .displayID(block: 2, type: .typeI, index: 0, embeddedInCTA: false))]
    )

    @Test("A max mode that matches a declared entry takes that entry's pixel clock")
    func maxModeMatchingADeclaredEntryTakesItsClock() throws {
        // CoreGraphics names 4K144 and the EDID declares that very mode, so
        // the top mode is labelled from the entry and its clock, read from
        // the EDID, is the bandwidth figure: 1306.21 MHz x 24bpp = 31.35 Gbps.
        let cg144 = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 144)
        let matched = try #require(DisplayDiagnostic.declaredMode(matching: cg144, in: fourK144Panel))
        #expect(matched.pixelClockHz == 1_306_210_000)
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: cg144, edid: fourK144Panel))
        #expect(top.source == .declared(.displayID(block: 2, type: .typeI, index: 0, embeddedInCTA: false)),
                "got \(top.source)")
        #expect(top.pixelClockHz == 1_306_210_000, "got \(String(describing: top.pixelClockHz))")
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", maxMode: cg144)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fourK144Panel))
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 31.349) < 0.001, "expected 1306.21 MHz x 24bpp, got \(needed)")
        #expect(diag.facts.topModeSource == "DisplayID Type I (block 2)",
                "got \(String(describing: diag.facts.topModeSource))")
        #expect(diag.facts.maxRefreshHz == 144)
        #expect(diag.facts.declaredModeCount == 2)
    }

    @Test("A max mode below the declared top does not lower it")
    func maxModeBelowTheDeclaredTopDoesNotLowerIt() throws {
        // CoreGraphics names 4K30: the mode list it builds is what the trained
        // link can carry, so a max mode below the panel's own top describes
        // the link, not the panel. No declared entry is 4K30 and it sits below
        // the declared top, so the 4K144 entry stands.
        let cg30 = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30)
        #expect(DisplayDiagnostic.declaredMode(matching: cg30, in: fourK144Panel) == nil)
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: cg30, edid: fourK144Panel))
        #expect(top.source == .declared(.displayID(block: 2, type: .typeI, index: 0, embeddedInCTA: false)),
                "got \(top.source)")
        #expect(top.refreshHz.rounded() == 144)
        // Driven at 4K30 with the node listing 4K30 only: the 144 Hz top is pictureOnly.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30, bitsPerComponent: 8, pixelClockHz: 266_625_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", currentMode: live, maxMode: cg30, drivenTiming: Self.offering([Self.listing(3840, 2160, 30.0, 266_625_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fourK144Panel))
        #expect(diag.facts.maxRefreshHz == 144,
                "the top mode is the panel's 144 Hz, not the link's 30, got \(String(describing: diag.facts.maxRefreshHz))")
        #expect(diag.facts.topModeSource == "DisplayID Type I (block 2)")
        #expect(diag.bottleneck == .belowMonitorMax, "got \(diag.bottleneck)")
    }

    @Test("A max mode above every declared entry and no tiled composite is reported by macOS only")
    func maxModeAboveEveryDeclaredEntryIsMacOSOnly() throws {
        // The EDID declares one 4K60 DTD; CoreGraphics names 5120x2880@60. No
        // entry matches, no tiled composite explains it, so its pixel clock is
        // nowhere we can read. The verdict names the mode and computes
        // nothing: no bandwidth figure, no all-clear, no warning.
        let fourK60Only = EDIDInfo.fixture(
            name: "Studio Display",
            version: (1, 4),
            preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000)
        )
        let cg5K = DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60)
        #expect(DisplayDiagnostic.declaredMode(matching: cg5K, in: fourK60Only) == nil)
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: cg5K, edid: fourK60Only))
        #expect(top.source == .reportedByMacOSOnly, "got \(top.source)")
        #expect(top.pixelClockHz == nil)
        #expect(top.width == 5120 && top.height == 2880)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, maxMode: cg5K)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fourK60Only))
        #expect(diag.bottleneck == .unknownMode, "got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        #expect(diag.facts.neededGbps == nil, "got \(String(describing: diag.facts.neededGbps))")
        #expect(diag.facts.topModeSource == "macOS only", "got \(String(describing: diag.facts.topModeSource))")
        #expect(diag.facts.topModeWidth == 5120)
        #expect(diag.facts.maxRefreshHz == 60)
        // No statement: the node is named as unmatched (K27) and the top mode
        // is named through `canDo`; the macOS-only guard sentence is retired.
        #expect(diag.detail.contains("could not be matched"), "got \(diag.detail)")
        #expect(diag.detail.contains("top mode (up to 60Hz)"), "got \(diag.detail)")
        #expect(diag.detail.contains("Studio Display"), "got \(diag.detail)")
        #expect(diag.detail.contains("25.9 Gbps"), "the link sentence still reports the link, got \(diag.detail)")

        // Same shape on a continuous-frequency panel with a 1.2 GHz envelope:
        // the envelope is a range the panel accepts, not a mode, and it is
        // never consulted to fill the gap. Same verdict, same nil figure.
        let continuous = EDIDInfo.fixture(
            name: "Studio Display",
            version: (1, 4),
            preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000),
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 24, maxVerticalHz: 60, minHorizontalKHz: 30, maxHorizontalKHz: 180,
                maxPixelClockHz: 1_200_000_000, timingSupport: .rangeLimitsOnly),
            continuousFrequency: true
        )
        let c = try #require(DisplayDiagnostic(dp: dp, edid: continuous))
        #expect(c.bottleneck == .unknownMode, "got \(c.bottleneck)")
        #expect(c.facts.neededGbps == nil, "the envelope must not supply a clock, got \(String(describing: c.facts.neededGbps))")
        #expect(c.facts.topModeSource == "macOS only")
    }

    @Test("A tiled composite explains a max mode the tile EDID cannot")
    func tiledCompositeExplainsTheMaxMode() throws {
        // A two-tile 5K panel (the Studio Display's shape): the EDID declares
        // the tile's own 2560x2880@60 at 482.4 MHz, and the walker derives the
        // 5120x2880 composite at twice the clock from the tiled topology.
        // CoreGraphics names 5120x2880@60. The composite is a declared fact,
        // so the max mode is labelled from it and its clock is the figure:
        // 964.8 MHz x 24bpp = 23.16 Gbps.
        let tile = EDIDInfo.mode(2560, 2880, hTotal: 2680, vTotal: 3000, pixelClockHz: 482_400_000)
        let composite = EDIDInfo.mode(5120, 2880, hTotal: 5360, vTotal: 3000, pixelClockHz: 964_800_000,
                                      source: .tiledComposite(tiles: 2, from: nil))
        let tiled = EDIDInfo.fixture(
            name: "StudioDisplay",
            version: (1, 4),
            preferred: tile,
            modes: [tile, composite],
            tiledTopology: EDIDInfo.TiledTopology(
                hTiles: 2, vTiles: 1, tileWidth: 2560, tileHeight: 2880, hLocation: 0, vLocation: 0)
        )
        let cg5K = DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60)
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: cg5K, edid: tiled))
        #expect(top.source == .declared(.tiledComposite(tiles: 2, from: nil)), "got \(top.source)")
        #expect(top.pixelClockHz == 964_800_000, "got \(String(describing: top.pixelClockHz))")
        // The panel driven at 4K60 on the tunnelled HBR2 link, its node
        // listing no 5120x2880 picture (neither the composite's nor the
        // tile's), so step 1b keeps the declared top and it is genuinely not
        // listed (K26).
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_250_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", tunneled: true, currentMode: live, maxMode: cg5K,
                        drivenTiming: Self.offering([Self.listing(3840, 2160, 60.0, 533_250_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: tiled))
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 23.155) < 0.001, "expected 964.8 MHz x 24bpp, got \(needed)")
        #expect(diag.facts.topModeSource == "tiled composite of 2 tiles",
                "got \(String(describing: diag.facts.topModeSource))")
        #expect(diag.facts.topModeWidth == 5120)
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.facts.topModeMatch == .notListed)
        #expect(diag.facts.topModeListedByNode == false)
        #expect(diag.cableAssessment == .unlikelyTheCable)
    }

    // MARK: - YCbCr 4:2:0-only entries are declared facts, never the comparison mode

    /// The 27C1U-L behind a "DisplayPort 1.2" USB-C to HDMI adapter (corpus
    /// m3_macos26.6.2): the base block's DTD is 3840x2160 at 60 Hz, 527.85
    /// MHz, and the CTA block adds VIC 97 (3840x2160 at 60 Hz, 594 MHz) from
    /// the YCbCr 4:2:0 Video Data Block, a mode the panel supports at 4:2:0
    /// only. `EDIDInfo.topMode` is that VIC on pixel clock.
    private let panel27C1UL = EDIDInfo.fixture(
        name: "27C1U-L",
        version: (1, 3),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 3910, vTotal: 2250, pixelClockHz: 527_850_000),
        modes: [EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 594_000_000,
                               source: .ctaVIC(block: 1, vic: 97, native: false, ycbcr420Only: true))]
    )

    /// The UGREEN behind a "176GB0" USB-C to HDMI adapter (corpus
    /// m4_macos26.5.1_m, second display): a 1080p60 DTD, VIC 95 (3840x2160 at
    /// 30 Hz, 297 MHz) in full colour, and VICs 96 and 97 (4K50 and 4K60,
    /// 594 MHz) at 4:2:0 only.
    private let panelUGREEN = EDIDInfo.fixture(
        name: "UGREEN",
        version: (1, 3),
        preferred: EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 148_500_000),
        modes: [
            EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 297_000_000,
                          source: .ctaVIC(block: 1, vic: 95, native: false, ycbcr420Only: false)),
            EDIDInfo.mode(3840, 2160, hTotal: 5280, vTotal: 2250, pixelClockHz: 594_000_000,
                          source: .ctaVIC(block: 1, vic: 96, native: false, ycbcr420Only: true)),
            EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 594_000_000,
                          source: .ctaVIC(block: 1, vic: 97, native: false, ycbcr420Only: true)),
        ]
    )

    @Test("A 4:2:0-only top entry above a full-colour DTD: the link is judged against the DTD (2-lane HBR3 behind an HDMI adapter)")
    func ycbcr420OnlyTopIsSkippedOnHBR3Adapter() throws {
        // Fixture guard: on pixel clock alone the 4:2:0 VIC is the EDID's top.
        let edidTop = try #require(panel27C1UL.topMode)
        #expect(edidTop.sourceDescription == "CTA VIC 97 4:2:0 (block 1)")
        // 2 of 2 lanes at HBR3, driven at the DTD (timing 45, stated
        // uncompressed). The receipt is the DTD's 527.85e6 x 24 = 12.668
        // Gbps; the 4:2:0 VIC would have read 14.256.
        let dp = makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", branchDeviceId: "Dp1.2",
                        currentMode: Self.live27C1UL, drivenTiming: Self.statement27C1UL)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel27C1UL))
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.isWarning == false)
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 12.6684) < 0.001, "needed \(needed) Gbps, expected the DTD's 527.85 MHz x 24")
        #expect(diag.facts.topModeSource == "detailed timing 1 (block 0)")
        #expect(diag.facts.maxRefreshHz == 60)
        #expect(diag.facts.declaredModeCount == 2, "the 4:2:0 entry stays a declared fact")
        #expect(diag.facts.declared420OnlyModes == 1)
        // Int interpolation in `String(localized:)` groups digits by locale
        // ("3,840" in en_US), as the Pro heading's own "\(w) × \(h)" key does.
        #expect(diag.detail.contains("Its EDID also lists \(3840.formatted()) × \(2160.formatted()) at 60Hz in 4:2:0 only, a mode macOS does not send over the DisplayPort link."), "detail: \(diag.detail)")
        #expect(!diag.detail.contains("14.3"), "the 4:2:0 entry's bandwidth must never reach the user")
    }

    @Test("A 4:2:0-only 4K60 above a full-colour 4K30: the link is judged against 4K30 (2-lane HBR2 behind an HDMI adapter)")
    func ycbcr420OnlyTopIsSkippedOnHBR2Adapter() throws {
        let edidTop = try #require(panelUGREEN.topMode)
        #expect(edidTop.sourceDescription == "CTA VIC 97 4:2:0 (block 1)")
        // 2 of 2 lanes at HBR2, driven at VIC 95 (4K30, 297 MHz) with the node
        // listing it. The receipt is 297e6 x 24 = 7.128 Gbps.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30, bitsPerComponent: 8, pixelClockHz: 297_000_000, pixelEncoding: .rgb444)
        let dp = makeDP(lanes: 2, maxLanes: 2, rateDesc: "5.4 Gbps (HBR2)", dfpType: "HDMI", branchDeviceId: "176GB0",
                        currentMode: live, drivenTiming: Self.offering([Self.listing(3840, 2160, 30.0, 297_000_000)]))
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panelUGREEN))
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 7.128) < 0.001)
        #expect(diag.facts.topModeSource == "CTA VIC 95 (block 1)")
        #expect(diag.facts.topModeWidth == 3840)
        #expect(diag.facts.maxRefreshHz == 30)
        #expect(diag.facts.declaredModeCount == 4)
        #expect(diag.facts.declared420OnlyModes == 2)
        // The named entry is the highest 4:2:0-only one: 4K60 over 4K50
        // (same clock and area, higher refresh).
        #expect(diag.detail.contains("Its EDID also lists \(3840.formatted()) × \(2160.formatted()) at 60Hz in 4:2:0 only, a mode macOS does not send over the DisplayPort link."), "detail: \(diag.detail)")
    }

    @Test("A CoreGraphics max mode that matches only a 4:2:0-only entry is macOS's fact alone, never costed at 24 bpp")
    func maxModeMatchingOnlyA420EntryIsReportedByMacOSOnly() throws {
        // 4K60 is declared, but only from the Y420VDB. Step 3 must not label
        // the top from that entry; step 4 sees a max mode above the 4K30
        // full-colour top and reports it as macOS only, with no clock.
        let cg = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: cg, edid: panelUGREEN))
        #expect(top.source == .reportedByMacOSOnly, "got \(top.source)")
        #expect(top.pixelClockHz == nil)
        let dp = makeDP(lanes: 2, maxLanes: 2, rateDesc: "5.4 Gbps (HBR2)", dfpType: "HDMI", maxMode: cg)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panelUGREEN))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.facts.neededGbps == nil)
        #expect(diag.facts.declared420OnlyModes == 2)
        // The 4:2:0 sentence would contradict "a mode the EDID doesn't
        // describe", so it is left off on this path.
        #expect(!diag.detail.contains("4:2:0"), "detail: \(diag.detail)")
    }

    @Test("A max mode that matches a full-colour entry is labelled from it even when a higher-clock 4:2:0 twin exists")
    func maxModeMatchingAFullColourEntryIgnoresIts420Twin() throws {
        // The 27C1U-L declares 4K60 twice: the 527.85 MHz DTD and the 594 MHz
        // 4:2:0 VIC. CoreGraphics naming 4K60 lands on the DTD, the
        // highest-clock FULL-COLOUR match, not the higher-clock 4:2:0 one.
        let cg = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: cg, edid: panel27C1UL))
        #expect(top.source == .declared(.detailedTiming(block: 0, index: 0)), "got \(top.source)")
        #expect(top.pixelClockHz == 527_850_000)
    }

    @Test("No 4:2:0-only entries: the resolved top is EDIDInfo.topMode and no sentence is added")
    func noYcbcr420EntriesKeepsTodaysTop() throws {
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4), edid: g34w))
        #expect(diag.facts.declared420OnlyModes == 0)
        #expect(!diag.detail.contains("4:2:0"))
        let top = try #require(diag.topMode)
        let edidTop = try #require(g34w.topMode)
        #expect(top == DisplayDiagnostic.TopMode(declared: edidTop))
    }

    // MARK: - The driven timing's own clock

    @Test("A driven 4K60 at the DTD's clock over a 2-lane HBR3 link reads as fine without a statement (hedged)")
    func drivenTimingAtTheTopClockIsFine() throws {
        // The 27C1U-L over 2 of 2 lanes at HBR3 with the live mode at the
        // DTD: 3840x2160 at 60.0 Hz, 527.85 MHz, 8 bit. The live mode meets
        // the top, so fine (S18); with no statement there is no cross-check.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 527_850_000)
        let dp = makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", branchDeviceId: "Dp1.2", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel27C1UL))
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.facts.currentMode?.pixelClockHz == 527_850_000)
        #expect(diag.facts.liveNeededGbps == nil, "no statement, no cross-check")
    }

    @Test("meetsTopMode never compares the clock: a lower-clock timing of the top picture and refresh still meets it")
    func meetsTopModeIgnoresBlankingOnBothSides() throws {
        // A panel that declares 4K60 twice, VIC 97 at 594 MHz on top and a
        // reduced-blanking 533.25 MHz DTD below it. macOS drives the DTD (17
        // corpus nodes do exactly this). The display IS at its top picture
        // and refresh, so it meets the top even though its clock is 10% lower
        // (ruling 36: the driven timing's clock is not compared).
        let panel = EDIDInfo.fixture(
            name: "4K60 twice",
            version: (1, 4),
            preferred: EDIDInfo.mode(3840, 2160, hTotal: 4000, vTotal: 2222, pixelClockHz: 533_250_000),
            modes: [EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 594_000_000,
                                   source: .ctaVIC(block: 1, vic: 97, native: false, ycbcr420Only: false))]
        )
        let top = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: panel))
        #expect(top.pixelClockHz == 594_000_000, "fixture guard: the 594 MHz VIC is the top")
        let driven = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 59.996625, bitsPerComponent: 8, pixelClockHz: 533_250_000)
        #expect(DisplayDiagnostic.meetsTopMode(driven, top: top) == true)
        let below = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30, bitsPerComponent: 8, pixelClockHz: 297_000_000)
        #expect(DisplayDiagnostic.meetsTopMode(below, top: top) == false)
    }

    // MARK: - Verdicts from macOS's statement (issue #664, Design 3 and ruling 37)

    @Test("(b) Empty DSC list, live mode at the top: fine, named uncompressed, unsafe list a fact (27C1U-L, m3_macos26.6.2)")
    func emptyListAtTopIsFineUncompressed() throws {
        let dp = makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", branchDeviceId: "Dp1.2",
                        currentMode: Self.live27C1UL, drivenTiming: Self.statement27C1UL)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel27C1UL))
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.isWarning == false)
        #expect(diag.facts.dscReading == .uncompressed)
        #expect(diag.facts.isAppleDisplay == false)
        #expect(diag.facts.drivenTiming?.unsafeIDs == [89, 90, 91, 92], "a fact, never a verdict (ruling 1)")
        #expect(diag.detail.contains("states it is running uncompressed"), "\(diag.detail)")
        #expect(diag.detail.contains("a mode macOS does not send over the DisplayPort link"), "no 4:2:0 downstream format: sentence K17")
        #expect(diag.facts.topModeMatch == .exact)
        #expect(diag.facts.topModeAvailability == .offeredUncompressed)
        #expect(diag.facts.statementOffersTopMode == true)
        #expect(diag.facts.topModeListedByNode == true)
        #expect(diag.cableAssessment == .unlikelyTheCable, "the statement lists the top mode on this link")
        let need = try #require(diag.facts.liveNeededGbps)
        #expect(abs(need - 12.6684) < 0.001, "527.85 MHz x 24 (RGB and 4:4:4 at 8 bits both cost 24)")
        let usable = try #require(diag.facts.usableGbpsRange)
        #expect(abs(usable.upperBound - 12.96) < 1e-9)
        #expect(abs(usable.lowerBound - 12.96 * 0.9765625) < 1e-9)
        #expect(diag.facts.statementContradiction == false, "12.668 is inside 12.656...12.96")
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 12.6684) < 0.001, "the top-mode figure keeps its 8-bit RGB basis, as a receipt")
    }

    @Test("(b) Live below the top, top offered uncompressed: belowMonitorMax, the selected mode named, the cable exonerated by the statement")
    func topOfferedUncompressedBelowTop() throws {
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60, Self.g34wAt100])), edid: g34w))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.isWarning == true)
        #expect(diag.summary == "Monitor can do more than it is set to")
        #expect(diag.detail.contains("macOS lists your LEN G34w-10's top mode (up to 100Hz) as available on this link, uncompressed."), "\(diag.detail)")
        #expect(diag.detail.contains("macOS states the current mode, 3440 x 1440 @ 60Hz, is running uncompressed."), "\(diag.detail)")
        #expect(diag.detail.contains("The link is carrying about"), "S3 follows")
        #expect(diag.cableAssessment == .unlikelyTheCable, "2 of 4 lanes on no known cable, but macOS lists the top mode on this link")
        #expect(diag.facts.statementOffersTopMode == true)
        #expect(diag.facts.topModeAvailability == .offeredUncompressed)
        #expect(diag.facts.topModeTiming?.id == 12)
        #expect(diag.billboardNote == nil, "ruling 39: no re-plug advice when the link already carries the top mode")
    }

    @Test("(b) Top offered with DSC, and top offered with compression not named")
    func topOfferedWithDSCAndUnresolved() throws {
        let dsc = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60, Self.g34wAt100DSC])), edid: g34w))
        #expect(dsc.bottleneck == .belowMonitorMax)
        #expect(dsc.detail.contains("as available on this link with compression (DSC)."), "\(dsc.detail)")
        #expect(dsc.facts.topModeAvailability == .offeredWithDSC)
        let mixedTop = Self.listing(3440, 1440, 99.992, 600_000_000, Self.listsMixed, id: 12)
        let unresolved = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60, mixedTop])), edid: g34w))
        #expect(unresolved.bottleneck == .belowMonitorMax)
        #expect(unresolved.detail.contains("as available on this link. The mode selected"), "\(unresolved.detail)")
        #expect(!unresolved.detail.contains("with compression (DSC)"))
        #expect(unresolved.facts.topModeAvailability == .offeredUnresolved)
    }

    @Test("(b) Top not offered: picture at a lower refresh only, and a listing with no colour modes")
    func topNotOffered() throws {
        let lowerRefresh = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w))
        #expect(lowerRefresh.bottleneck == .belowMonitorMax)
        #expect(lowerRefresh.summary == "Monitor can do more than the link is carrying")
        #expect(lowerRefresh.detail.contains("macOS does not offer your LEN G34w-10's top mode (up to 100Hz) on this link as it is now."), "\(lowerRefresh.detail)")
        #expect(lowerRefresh.detail.contains("selecting it would retrain the link and show whether it is offered"), "K23: the otherwise wording")
        #expect(lowerRefresh.facts.topModeMatch == .pictureOnly)
        #expect(lowerRefresh.facts.topModeAvailability == .notOffered)
        #expect(lowerRefresh.cableAssessment == .inconclusive)
        #expect(!lowerRefresh.detail.contains("needs about"), "the arithmetic figure is a receipt, never the reason (the link line describes the link, that is all)")
        let emptyTop = Self.listing(3440, 1440, 99.992, 600_000_000, Self.emptyLists, id: 12)
        let noColour = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60, emptyTop])), edid: g34w))
        #expect(noColour.bottleneck == .belowMonitorMax)
        #expect(noColour.facts.topModeMatch == .exact)
        #expect(noColour.facts.topModeAvailability == .notOffered, "listed with no colour mode validated is not an offer")
        #expect(noColour.facts.topModeTiming?.id == 12)
    }

    @Test("(b) Top not offered behind a converter: adapterLimit, with and without a branch device")
    func topNotOfferedBehindAdapter() throws {
        let branch = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, dfpType: "HDMI", branchDeviceId: "Dp1.2", currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w))
        #expect(branch.bottleneck == .adapterLimit)
        #expect(branch.summary == "Video is going through a HDMI adapter")
        #expect(branch.detail.contains("that reports as DisplayPort 1.2, and macOS does not offer the monitor's top mode (up to 100Hz) on this link as it is now."), "\(branch.detail)")
        let plain = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, dfpType: "HDMI", currentMode: Self.liveG34w60, drivenTiming: Self.offering([Self.g34wAt60])), edid: g34w))
        #expect(plain.bottleneck == .adapterLimit)
        #expect(plain.detail.contains("adapter, and macOS does not offer the monitor's top mode (up to 100Hz) on this link as it is now."), "\(plain.detail)")
        #expect(!plain.detail.contains("reports as"))
    }

    @Test("Ruling 41: a scaler entry the node never lists is skipped and the listed entry below it is the top (the 1600x1200 DMT on a 1080p Dell)")
    func scalerTopIsSkippedForTheEntryTheNodeLists() throws {
        // A 1080p panel whose EDID's highest-clock entry is a 1600x1200 standard timing; the node lists 1080p only.
        let panel = EDIDInfo.fixture(name: "DELL P2219H", version: (1, 4),
                                     preferred: EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 148_500_000),
                                     modes: [EDIDInfo.mode(1600, 1200, hTotal: 2160, vTotal: 1250, pixelClockHz: 162_000_000, source: .detailedTiming(block: 0, index: 1))])
        // (On the real panel the 1600x1200 is a standard timing; the source plays no part in the resolver, which reads the clock.)
        let live = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 148_500_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(1920, 1080, 60.0, 148_500_000)])
        // Without the statement the resolver still picks the 162 MHz entry (as today).
        let declaredOnly = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: panel))
        #expect(declaredOnly.width == 1600, "fixture guard: the declared top is the scaler entry")
        // With it, step 1b walks past the entry the node never lists.
        let resolved = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: panel, statement: statement))
        #expect(resolved.width == 1920 && resolved.height == 1080)
        #expect(resolved.pixelClockHz == 148_500_000)
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: statement), edid: panel))
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.facts.topModeWidth == 1920)
        #expect(diag.facts.topModeSource == "detailed timing 1 (block 0)")
        #expect(diag.facts.topModeMatch == .exact)
        #expect(diag.facts.topModeListedByNode == true)
        #expect(diag.detail.contains("at its top mode (1920 x 1080 @ 60Hz)"), "K1 names the resolved top, not the scaler entry: \(diag.detail)")
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 3.564) < 0.001, "148.5 MHz x 24, the receipt follows the resolved top")
    }

    @Test("Ruling 41: no declared entry listed at all is the genuine not-listed case: unknownMode, K26")
    func nothingListedIsUnknown() throws {
        // The node lists a picture the EDID does not declare at all (nothing pairs), so every candidate is skipped and the declared top stands.
        let statement = Self.offering([Self.listing(800, 600, 60.0, 40_000_000)])
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, currentMode: Self.liveG34w60, drivenTiming: statement), edid: g34w))
        #expect(diag.facts.topModeWidth == 3440 && diag.facts.maxRefreshHz == 100, "the declared top stands")
        #expect(diag.bottleneck == .unknownMode, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.isWarning == false)
        #expect(diag.summary == "Display connected")
        #expect(diag.detail.contains("has no entry matching its top mode (up to 100Hz)"), "\(diag.detail)")
        #expect(diag.facts.topModeMatch == .notListed)
        #expect(diag.facts.topModeAvailability == .notListed)
        #expect(diag.facts.topModeListedByNode == false)
        #expect(diag.facts.statementOffersTopMode == false)
    }

    @Test("Ruling 41: a native picture listed only at lower refreshes stays the top, so the link's limit still shows (the LG 4K144 at 4K60)")
    func nativePictureAtLowerRefreshStaysTheTop() throws {
        // The panel's preferred picture is 3840x2160; its top is 4K120 at 1188 MHz; the node lists 3840x2160 at 60 Hz only.
        let panel = EDIDInfo.fixture(name: "LG 4K144", version: (1, 4),
                                     preferred: EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 594_000_000),
                                     modes: [EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 1_188_000_000, source: .detailedTiming(block: 1, index: 0))])
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 594_000_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(3840, 2160, 60.0, 594_000_000)])
        let resolved = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: panel, statement: statement))
        #expect(resolved.pixelClockHz == 1_188_000_000, "the 120 Hz entry is kept: its picture is the preferred one, so the missing refresh is the link's fact")
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: statement), edid: panel))
        #expect(diag.bottleneck == .belowMonitorMax, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.facts.topModeMatch == .pictureOnly)
        #expect(diag.facts.topModeAvailability == .notOffered)
        #expect(diag.facts.topModeListedByNode == true, "the node lists the picture, at other refreshes")
        #expect(diag.detail.contains("macOS does not offer your LG 4K144's top mode (up to 120Hz) on this link as it is now."), "\(diag.detail)")
    }

    @Test("Ruling 41: a non-preferred picture listed only at lower refreshes is a scaler entry and is skipped (the 5120x1440 panel with a 4K120 VIC)")
    func nonPreferredPictureAtLowerRefreshIsSkipped() throws {
        // Preferred (native) 5120x1440 at 120 Hz; the EDID also carries 4K120 (1188 MHz, outranking the native on clock) and 4K60 VICs; the node lists the native and 4K60.
        let native = EDIDInfo.mode(5120, 1440, hTotal: 5280, vTotal: 1480, pixelClockHz: 937_728_000)
        let panel = EDIDInfo.fixture(name: "Odyssey G9", version: (1, 4),
                                     preferred: native,
                                     modes: [EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 1_188_000_000,
                                                           source: .ctaVIC(block: 1, vic: 118, native: false, ycbcr420Only: false)),
                                             EDIDInfo.mode(3840, 2160, hTotal: 4400, vTotal: 2250, pixelClockHz: 594_000_000,
                                                           source: .ctaVIC(block: 1, vic: 97, native: false, ycbcr420Only: false))])
        let live = DisplayCurrentMode(width: 5120, height: 1440, refreshHz: 120, bitsPerComponent: 8, pixelClockHz: 937_728_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(5120, 1440, 120.0, 937_728_000), Self.listing(3840, 2160, 60.0, 594_000_000, id: 101)])
        let declaredOnly = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: panel))
        #expect(declaredOnly.width == 3840 && declaredOnly.pixelClockHz == 1_188_000_000, "fixture guard: the 4K120 VIC outranks the native on clock")
        let resolved = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: panel, statement: statement))
        #expect(resolved.width == 5120 && resolved.height == 1440, "4K120 is a non-preferred picture the node lists only at 60 Hz: skipped; the native is listed exactly")
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: statement), edid: panel))
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.facts.topModeWidth == 5120)
        #expect(diag.facts.topModeListedByNode == true)
        // Without the statement nothing changes from today: the 4K120 VIC is the top.
        let plain = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live), edid: panel))
        #expect(plain.facts.topModeWidth == 3840)
        #expect(plain.facts.topModeListedByNode == nil)
    }

    // MARK: - PR #665 gate rerun, Claude F1: a link-limited native picture above the preferred DTD

    /// The Studio Display as the parser reads it: the base DTD is a 4K60 compatibility mode,
    /// the native 5120x2880 is the tiled composite (964.8 MHz). A link that cannot carry the
    /// native mode lists it at 30 Hz only beside 4K60.
    private let studioLinkLimited = EDIDInfo.fixture(
        name: "StudioDisplay", version: (1, 4),
        preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000),
        modes: [EDIDInfo.mode(5120, 2880, hTotal: 5360, vTotal: 3000, pixelClockHz: 964_800_000, source: .tiledComposite(tiles: 2, from: nil))])

    @Test("F1: a Studio Display whose node lists its native 5K only at 30 Hz keeps 5K60 as the top and reads not offered, never 'not the cable'")
    func linkLimitedStudioDisplayKeepsItsNativeTop() throws {
        let live = DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 30, bitsPerComponent: 8, pixelClockHz: 468_000_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(3840, 2160, 60.0, 533_250_000, id: 37), Self.listing(5120, 2880, 30.0, 468_000_000, id: 43)])
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", manufacturerName: "APP", currentMode: live, drivenTiming: statement), edid: studioLinkLimited))
        #expect(diag.facts.topModeWidth == 5120 && diag.facts.maxRefreshHz == 60, "the native picture stays the top: got \(String(describing: diag.facts.topModeWidth)) @ \(String(describing: diag.facts.maxRefreshHz))")
        #expect(diag.facts.topModeMatch == .pictureOnly)
        #expect(diag.facts.topModeAvailability == .notOffered)
        #expect(diag.bottleneck == .belowMonitorMax, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.summary == "Monitor can do more than the link is carrying")
        #expect(diag.detail.contains("macOS does not offer your StudioDisplay's top mode (up to 60Hz) on this link as it is now."), "\(diag.detail)")
        #expect(!diag.detail.contains("not the cable or adapter"))
        #expect(diag.cableAssessment == .inconclusive)
    }

    @Test("F1: a Pro Display XDR (DisplayID-native 6K) whose node lists 6K only at 30 Hz keeps 6K60 as the top and reads not offered")
    func linkLimitedProDisplayXDRKeepsItsNativeTop() throws {
        let xdr = EDIDInfo.fixture(
            name: "ProDisplayXDR", version: (1, 4),
            preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000),
            modes: [EDIDInfo.mode(6016, 3384, hTotal: 6176, vTotal: 3472, pixelClockHz: 1_286_000_000,
                                  source: .displayID(block: 1, type: .typeI, index: 0, embeddedInCTA: false))])
        let live = DisplayCurrentMode(width: 6016, height: 3384, refreshHz: 30, bitsPerComponent: 8, pixelClockHz: 643_000_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(3840, 2160, 60.0, 533_250_000, id: 37), Self.listing(6016, 3384, 30.0, 643_000_000, id: 44)])
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", tunneled: true, manufacturerName: "APP", currentMode: live, drivenTiming: statement), edid: xdr))
        #expect(diag.facts.topModeWidth == 6016 && diag.facts.maxRefreshHz == 60, "got \(String(describing: diag.facts.topModeWidth)) @ \(String(describing: diag.facts.maxRefreshHz))")
        #expect(diag.facts.topModeAvailability == .notOffered)
        #expect(diag.bottleneck == .belowMonitorMax, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.detail.contains("macOS does not offer your ProDisplayXDR's top mode (up to 60Hz) on this link as it is now. The video is tunneled"), "K21: \(diag.detail)")
    }

    @Test("F1: a PA32QCV (6K panel that also declares 6K at 30) held to 30 Hz keeps 6K60 as the top and reads not offered, never full quality")
    func linkLimitedPA32QCVKeepsItsNativeTop() throws {
        let pa32 = EDIDInfo.fixture(
            name: "PA32QCV", version: (1, 4),
            preferred: EDIDInfo.mode(3008, 1692, hTotal: 3168, vTotal: 1750, pixelClockHz: 332_640_000),
            modes: [EDIDInfo.mode(6016, 3384, hTotal: 6176, vTotal: 3472, pixelClockHz: 1_286_000_000,
                                  source: .displayID(block: 1, type: .typeI, index: 0, embeddedInCTA: false)),
                    EDIDInfo.mode(6016, 3384, hTotal: 6176, vTotal: 3472, pixelClockHz: 643_000_000,
                                  source: .displayID(block: 1, type: .typeI, index: 1, embeddedInCTA: false))])
        let live = DisplayCurrentMode(width: 6016, height: 3384, refreshHz: 30, bitsPerComponent: 8, pixelClockHz: 643_000_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(3008, 1692, 60.0, 332_640_000, id: 37), Self.listing(6016, 3384, 30.0, 643_000_000, id: 44)])
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", currentMode: live, drivenTiming: statement), edid: pa32))
        #expect(diag.facts.topModeWidth == 6016 && diag.facts.maxRefreshHz == 60, "got \(String(describing: diag.facts.topModeWidth)) @ \(String(describing: diag.facts.maxRefreshHz))")
        #expect(diag.facts.topModeAvailability == .notOffered)
        #expect(diag.bottleneck == .belowMonitorMax, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.detail.contains("macOS does not offer your PA32QCV's top mode (up to 60Hz) on this link as it is now. The cable is already carrying every DisplayPort lane") == false, "4 of 4 lanes on no known passive cable: K23, not K22")
        #expect(diag.detail.contains("macOS does not offer your PA32QCV's top mode (up to 60Hz) on this link as it is now. If you've selected the higher mode"), "K23: \(diag.detail)")
    }

    @Test("DisplayID Type IV and Type VIII entries are code lists, like the two bitmap tags: a picture-only one is skipped, not kept as a link-limited native mode (PR #665 gate fix round 4, item 1)")
    func displayIDCodeListTypesAreNotNativeDeclarations() throws {
        // A 1080p panel whose EDID carries a 1600x1200@60 entry through a DisplayID code list; the node
        // lists 1600x1200 at 30 Hz only beside the native 1080p60. A Type I entry of that shape is the
        // ruling's accepted cost (it stays, not offered); the four code-list types must be skipped and
        // the top must stay the listed 1080p60.
        let live = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 148_500_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(1920, 1080, 60.0, 148_500_000), Self.listing(1600, 1200, 30.0, 81_000_000, id: 101)])
        for type in [EDIDMode.DisplayIDTimingType.typeIV, .typeVIII, .vesaDMTBitmap, .ctaVICBitmap] {
            let panel = EDIDInfo.fixture(name: "DELL P2219H", version: (1, 4),
                                         preferred: EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 148_500_000),
                                         modes: [EDIDInfo.mode(1600, 1200, hTotal: 2160, vTotal: 1250, pixelClockHz: 162_000_000,
                                                               source: .displayID(block: 1, type: type, index: 0, embeddedInCTA: false))])
            let codeList = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: panel, statement: statement))
            #expect(codeList.width == 1920 && codeList.height == 1080, "\(type): a code-list entry listed at 30 only is a scaler entry, got \(codeList.width)x\(codeList.height)")
            let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: statement), edid: panel))
            #expect(diag.bottleneck == .fine, "\(type): got \(diag.bottleneck): \(diag.detail)")
        }
        // The same entry as a Type I timing stays the top and reads not offered (the ruling's accepted cost).
        let typeI = EDIDInfo.fixture(name: "DELL P2219H", version: (1, 4),
                                     preferred: EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 148_500_000),
                                     modes: [EDIDInfo.mode(1600, 1200, hTotal: 2160, vTotal: 1250, pixelClockHz: 162_000_000,
                                                           source: .displayID(block: 1, type: .typeI, index: 0, embeddedInCTA: false))])
        #expect(try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: typeI, statement: statement)).width == 1600)
    }

    @Test("A native declaration the node lists nowhere stays the top and reads not listed (K26), never a compatibility mode at full quality (PR #665 gate fix round 4, item 2)")
    func unlistedNativeDeclarationStaysTheTop() throws {
        // The rerun's case (b): a Studio Display whose node lists no 5K entry at all, driven 4K60.
        // The composite is the panel's native mode; a scaler entry never carries that source, so an
        // unlisted one is the link's fact to report as not listed, not a reason to judge the 4K DTD.
        let live4K = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 533_250_000, pixelEncoding: .rgb444)
        let fourKOnly = Self.offering([Self.listing(3840, 2160, 60.0, 533_250_000, id: 37)])
        let studio = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", tunneled: true, manufacturerName: "APP", currentMode: live4K, drivenTiming: fourKOnly), edid: studioLinkLimited))
        #expect(studio.facts.topModeWidth == 5120 && studio.facts.maxRefreshHz == 60, "got \(String(describing: studio.facts.topModeWidth)) @ \(String(describing: studio.facts.maxRefreshHz))")
        #expect(studio.facts.topModeMatch == .notListed)
        #expect(studio.facts.topModeAvailability == .notListed)
        #expect(studio.facts.topModeListedByNode == false)
        #expect(studio.bottleneck == .unknownMode, "got \(studio.bottleneck): \(studio.detail)")
        #expect(studio.detail.contains("macOS's list of modes for your StudioDisplay has no entry matching its top mode (up to 60Hz)"), "K26: \(studio.detail)")
        #expect(!studio.detail.contains("full quality"))
        // The same for a DisplayID-native 6K (the Pro Display XDR shape) with no 6K entry listed.
        let xdr = EDIDInfo.fixture(
            name: "ProDisplayXDR", version: (1, 4),
            preferred: EDIDInfo.mode(3840, 2160, hTotal: 4115, vTotal: 2160, pixelClockHz: 533_250_000),
            modes: [EDIDInfo.mode(6016, 3384, hTotal: 6176, vTotal: 3472, pixelClockHz: 1_286_000_000,
                                  source: .displayID(block: 1, type: .typeI, index: 0, embeddedInCTA: false))])
        let unlistedXDR = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", tunneled: true, manufacturerName: "APP", currentMode: live4K, drivenTiming: fourKOnly), edid: xdr))
        #expect(unlistedXDR.facts.topModeWidth == 6016)
        #expect(unlistedXDR.facts.topModeMatch == .notListed && unlistedXDR.bottleneck == .unknownMode, "got \(unlistedXDR.bottleneck): \(unlistedXDR.detail)")
        // An unlisted DMT standard timing is still a scaler entry: it falls through to the next
        // listed candidate, so the 1080p Dell resolves to 1080p60 and reads fine.
        let dell = EDIDInfo.fixture(name: "DELL P2219H", version: (1, 4),
                                    preferred: EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 148_500_000),
                                    modes: [EDIDInfo.mode(1600, 1200, hTotal: 2160, vTotal: 1250, pixelClockHz: 162_000_000,
                                                          source: .standardTiming(index: 2, derivation: .dmt, dmtID: 0x33))])
        let live1080 = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 148_500_000, pixelEncoding: .rgb444)
        let only1080 = Self.offering([Self.listing(1920, 1080, 60.0, 148_500_000)])
        let resolved = try #require(DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: dell, statement: only1080))
        #expect(resolved.width == 1920 && resolved.height == 1080)
        let dellDiag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live1080, drivenTiming: only1080), edid: dell))
        #expect(dellDiag.bottleneck == .fine, "got \(dellDiag.bottleneck): \(dellDiag.detail)")
        // The EDID's preferred picture is a native declaration too (round-4 re-review, LOW): a
        // 1080p panel whose preferred 1080p60 DTD the node lists nowhere, beside a 720p VIC the node
        // does list, driven 720p. Without the preferred clause the 720p VIC becomes the top and the
        // panel reads full quality at 720p; with it the top stays 1080p60, not listed, unknown.
        let panel1080 = EDIDInfo.fixture(name: "1080p panel", version: (1, 4),
                                         preferred: EDIDInfo.mode(1920, 1080, hTotal: 2200, vTotal: 1125, pixelClockHz: 148_500_000),
                                         modes: [EDIDInfo.mode(1280, 720, hTotal: 1650, vTotal: 750, pixelClockHz: 74_250_000,
                                                               source: .ctaVIC(block: 1, vic: 4, native: false, ycbcr420Only: false))])
        let live720 = DisplayCurrentMode(width: 1280, height: 720, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 74_250_000, pixelEncoding: .rgb444)
        let only720 = Self.offering([Self.listing(1280, 720, 60.0, 74_250_000)])
        let preferredUnlisted = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live720, drivenTiming: only720), edid: panel1080))
        #expect(preferredUnlisted.facts.topModeWidth == 1920 && preferredUnlisted.facts.topModeHeight == 1080, "got \(String(describing: preferredUnlisted.facts.topModeWidth))x\(String(describing: preferredUnlisted.facts.topModeHeight))")
        #expect(preferredUnlisted.facts.topModeMatch == .notListed)
        #expect(preferredUnlisted.bottleneck == .unknownMode, "got \(preferredUnlisted.bottleneck): \(preferredUnlisted.detail)")
        #expect(!preferredUnlisted.detail.contains("full quality"))
    }

    @Test("(b) Same picture and refresh at another blanking counts as offered (the Studio Display's 936 MHz against the 964.8 MHz composite)")
    func sameRefreshMatchIsOffered() throws {
        // Driven below the top on purpose: the Studio Display at 4K60 with its 5K timing listed uncompressed.
        let studioAt4K = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 529_190_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(3840, 2160, 59.999, 529_190_000), Self.listing(5120, 2880, 60.0, 936_000_000, id: 43)])
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, manufacturerName: "APP", currentMode: studioAt4K, drivenTiming: statement), edid: studio5K))
        #expect(diag.facts.topModeMatch == .sameRefresh, "964.8 MHz declared against 936 MHz listed: same picture and refresh, another blanking")
        #expect(diag.facts.topModeAvailability == .offeredUncompressed)
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.summary == "Monitor can do more than it is set to")
    }

    @Test("(c) Every non-virtual mode listed: compressionActive from the statement, no arithmetic (DELL U3225QE, m4pro_macos26.6.1_b)")
    func fullListIsCompressionActive() throws {
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", tunneled: true, currentMode: Self.liveU3225QE, drivenTiming: Self.statementU3225QE)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .compressionActive, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.isWarning == false)
        #expect(diag.summary == "Display running compressed (DSC) to fit through the link")
        #expect(diag.detail.contains("states that this link needs compression (DSC) to carry it"), "\(diag.detail)")
        #expect(!diag.detail.contains("Apple"))
        #expect(diag.facts.dscReading == .dscOn)
        #expect(diag.facts.liveNeededGbps == nil, "8 and 10 bit on one timing and no live depth: no cross-check figure")
        #expect(diag.facts.statementContradiction == false)
        #expect(diag.facts.topModeAvailability == .offeredWithDSC, "reported beside the verdict, deciding nothing here")
    }

    @Test("(c) On an Apple display the DSC-on verdict blames no link (Studio Display, m5_macos26.6.1_e)")
    func fullListOnAppleDisplayHasNoLinkBlame() throws {
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, manufacturerName: "APP",
                        currentMode: Self.liveStudio, drivenTiming: Self.statementStudio)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: studio5K))
        #expect(diag.bottleneck == .compressionActive, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.facts.isAppleDisplay == true)
        #expect(diag.summary == "Display running compressed (DSC)")
        #expect(diag.detail.contains("Apple displays run compressed whenever the link supports it"), "\(diag.detail)")
        #expect(!diag.detail.contains("needs compression"), "no link blame")
        #expect(!diag.summary.contains("to fit through the link"))
        #expect(diag.cableAssessment == .unlikelyTheCable)
        // The cross-check is reported beside the statement and decides nothing:
        // 936 MHz x 30 bpp (the live 10-bit depth, RGB) = 28.08 Gbps against a
        // usable 25.31 to 25.92, which agrees with DSC on.
        let need = try #require(diag.facts.liveNeededGbps)
        #expect(abs(need - 28.08) < 0.001, "936 MHz x 30 bpp at the live 10-bit depth")
        #expect(diag.facts.statementContradiction == false, "28.08 is above the bottom of the usable range, so DSC on is not contradicted")
        #expect(diag.facts.topModeMatch == .sameRefresh)
    }

    @Test("(c) The Apple gate reads EDID bytes 8-9 when the node carries the blob")
    func appleGateReadsEDIDBytes() throws {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[8] = 0x06; bytes[9] = 0x10
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, edidData: Data(bytes),
                        currentMode: Self.liveStudio, drivenTiming: Self.statementStudio)
        // The injected EDID is the parsed fixture; the raw blob on the monitor only feeds the gate.
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: studio5K))
        #expect(diag.facts.isAppleDisplay == true)
        #expect(diag.summary == "Display running compressed (DSC)")
    }

    @Test("(d) A proper subset reads unknownMode: the node does not name the live colour mode")
    func properSubsetIsUnknownMode() throws {
        let subset = DisplayTimingStatement(driven: DisplayTimingLists(colourModes: Self.listsStudio.colourModes, dscRequiredList: [46], unsafeList: [], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true),
                                            allTimings: Self.statementStudio.allTimings)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, currentMode: Self.liveStudio, drivenTiming: subset)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: studio5K))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.isWarning == false)
        #expect(diag.summary == "Display connected")
        #expect(diag.detail.contains("does not name the colour format in use"), "\(diag.detail)")
        #expect(diag.detail.contains("The link is carrying about"), "the link is still described")
        #expect(diag.facts.dscReading == .unresolved)
    }

    @Test("(d) A timing listing DSC-capable and non-capable modes together is unknown until the live depth resolves it")
    func mixedTimingResolvesOnlyThroughTheLiveMode() throws {
        // 4K144 at 1328 MHz over 4 lanes HBR3. The EDID top is the same mode, so only the statement decides.
        let panel = EDIDInfo.fixture(name: "LG 4K144", version: (1, 4),
                                     preferred: EDIDInfo.mode(3840, 2160, hTotal: 4000, vTotal: 2306, pixelClockHz: 1_328_250_000))
        let unresolved = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: Self.liveMixed, drivenTiming: Self.statementMixed), edid: panel))
        #expect(unresolved.bottleneck == .unknownMode, "no live depth: RGB (capable) or 4:2:2 (not)")
        #expect(unresolved.facts.dscReading == .unresolved)
        #expect(unresolved.facts.liveNeededGbps == nil)
        let tenBit = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 143.999, bitsPerComponent: 10, pixelClockHz: 1_328_249_948)
        let resolved = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: tenBit, drivenTiming: Self.statementMixed), edid: panel))
        #expect(resolved.bottleneck == .compressionActive, "every 10-bit mode is RGB, capable and listed")
        let need = try #require(resolved.facts.liveNeededGbps)
        #expect(abs(need - 39.847) < 0.01, "1328.25 MHz x 30")
        let plain = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 143.999, bitsPerComponent: 8, pixelClockHz: 1_328_249_948, pixelEncoding: .ycbcr422)
        let uncompressed = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: plain, drivenTiming: Self.statementMixed), edid: panel))
        #expect(uncompressed.facts.dscReading == .uncompressed, "a SupportsDSC = 0 mode is never in the list")
        #expect(uncompressed.bottleneck == .fine, "the live mode meets the top: (b)")
        #expect(uncompressed.facts.statementContradiction == false, "1328.25 MHz x 16 = 21.25 Gbps fits 25.92")
    }

    @Test("(d) Unreadable lists read unknownMode, whatever the arithmetic says")
    func incompleteListsAreUnknown() throws {
        let incomplete = DisplayTimingStatement(driven: DisplayTimingLists(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: nil,
                                                                           colourModesComplete: true, dscListComplete: false, unsafeListComplete: true),
                                                allTimings: Self.statement27C1UL.allTimings)
        let dp = makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", currentMode: Self.live27C1UL, drivenTiming: incomplete)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel27C1UL))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.facts.dscReading == .unresolved)
        // Claude F2 (gate rerun): an incomplete colour table gives no cross-check figure and no K13
        // line beside "Not named"; the entry that failed to parse may be the live one.
        let tableIncomplete = DisplayTimingStatement(driven: DisplayTimingLists(colourModes: [Self.colour(90, .rgb444, 8, dsc: 0)], dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1b4d,
                                                                                colourModesComplete: false, dscListComplete: true, unsafeListComplete: true),
                                                     allTimings: Self.statement27C1UL.allTimings)
        let noFigure = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", currentMode: Self.live27C1UL, drivenTiming: tableIncomplete), edid: panel27C1UL))
        #expect(noFigure.facts.dscReading == .unresolved)
        #expect(noFigure.facts.liveNeededGbps == nil, "got \(String(describing: noFigure.facts.liveNeededGbps))")
        #expect(!noFigure.statementReceipts().contains { $0.contains("Live mode needs about") }, "\(noFigure.statementReceipts())")
        #expect(noFigure.statementReceipts().contains { $0.contains("Not named") })
        // Ruling 42: an unreadable unsafe list alone leaves the DSC statement, and the verdict, untouched.
        let unsafeOnly = DisplayTimingStatement(driven: DisplayTimingLists(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1b4d,
                                                                           colourModesComplete: true, dscListComplete: true, unsafeListComplete: false),
                                                allTimings: Self.statement27C1UL.allTimings)
        let stillFine = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", currentMode: Self.live27C1UL, drivenTiming: unsafeOnly), edid: panel27C1UL))
        #expect(stillFine.bottleneck == .fine, "got \(stillFine.bottleneck): \(stillFine.detail)")
        #expect(stillFine.facts.dscReading == .uncompressed)
        #expect(stillFine.facts.drivenTiming?.unsafeListComplete == false, "the receipt (Task 8, K38) says so; the verdict does not")
    }

    @Test("A statement without a live mode is treated as no statement for the verdict (ruling 21)")
    func statementWithoutCurrentModeIsIgnored() throws {
        let with = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", drivenTiming: Self.statementStudio), edid: fo32))
        let without = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)"), edid: fo32))
        #expect(with.bottleneck == without.bottleneck)
        #expect(with.bottleneck == .unknownMode)
        #expect(with.facts.dscReading == .dscOn, "the reading is still reported as a fact")
        #expect(with.facts.topModeAvailability == .notListed, "the match still runs as a fact: the Studio Display node lists no 4K240, and step 1b finds no declared entry it does list, so the declared top stands")
        #expect(with.facts.topModeListedByNode == false)
    }

    @Test("Design 6 and ruling 44: behind a converter recording 4:2:0 output, the 4:2:0-only entry is not 'a mode macOS does not use'; some modes converting says so without naming the live one, all converting names the picture")
    func converterWith420DownstreamNarrowsTheSentence() throws {
        // The 27C1U-L EDID (its VIC 97 is 4:2:0-only) with the S2721QS statement's shape: a 4K60 driven timing on which 3 of 6 non-virtual modes carry a 4:2:0 downstream format.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", tunneled: true, dfpType: "HDMI", branchDeviceId: "cHDMIb",
                        currentMode: Self.liveS2721QS, drivenTiming: Self.statementS2721QS)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel27C1UL))
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.facts.downstream420 == .someModes)
        #expect(diag.detail.contains("The current timing includes a colour mode the adapter sends to the display as 4:2:0; macOS does not name which of the timing's modes is in use."), "\(diag.detail)")
        #expect(!diag.detail.contains("converting the picture"), "K8 claims the live picture is converted; the node does not name the live mode (finding 4)")
        #expect(!diag.detail.contains("does not use"))
        #expect(!diag.detail.contains("does not send over the DisplayPort link"))
        #expect(diag.facts.drivenTiming?.unsafeIDs == [76, 77, 78, 79])
        #expect(diag.facts.declared420OnlyModes == 1)
        #expect(diag.facts.currentMode?.downstreamFormat == nil, "ruling 15: not every non-virtual mode carries one")
        // Every non-virtual mode converting (the m1_macos26.5_o entry alone): K8, and the current mode carries the format (ruling 15 and ruling 44 agree by construction).
        let allLists = DisplayTimingLists(colourModes: [Self.colour(5, .ycbcr444, 8, dsc: 0, downstream: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8))],
                                          dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1b4f, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        let allStatement = DisplayTimingStatement(driven: allLists, allTimings: [Self.listing(3840, 2160, 60.0, 594_000_000, allLists)])
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 594_000_000,
                                      pixelEncoding: .ycbcr444, downstreamFormat: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8))
        let all = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", tunneled: true, dfpType: "HDMI", branchDeviceId: "cHDMIb",
                                                             currentMode: live, drivenTiming: allStatement), edid: panel27C1UL))
        #expect(all.facts.downstream420 == .everyMode)
        #expect(all.detail.contains("macOS records the adapter converting the picture to 4:2:0 on its way to the display."), "\(all.detail)")
        #expect(!all.detail.contains("does not name which"))
    }

    @Test("Spec Design 3: the list decides on an Apple display too; the Apple clause only changes attribution when the list reads DSC on")
    func appleDisplayReadsTheListLikeAnyOther() throws {
        // The general rule on an Apple panel: DSC-capable modes, empty list. The vendor never overrides the
        // producer's statement, so at the top this is fine, K1, no Apple sentence.
        let emptyOnCapable = DisplayTimingLists(colourModes: Self.listsStudio.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1b4d,
                                                colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        let plain = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, manufacturerName: "APP",
                                                               currentMode: Self.liveStudio, drivenTiming: DisplayTimingStatement(driven: emptyOnCapable, allTimings: [Self.listing(5120, 2880, 60.0, 936_000_000, emptyOnCapable)])), edid: studio5K))
        #expect(plain.facts.isAppleDisplay == true)
        #expect(plain.facts.dscReading == .uncompressed)
        #expect(plain.bottleneck == .fine, "got \(plain.bottleneck): \(plain.detail)")
        #expect(plain.detail.contains("states it is running uncompressed"), "\(plain.detail)")
        #expect(!plain.detail.contains("Apple") && !plain.summary.contains("compressed"), "the Apple clause changes attribution only, and only when the list reads DSC on")
        // A proper subset on an Apple panel: unknown, K6, no Apple sentence.
        let subset = DisplayTimingLists(colourModes: Self.listsStudio.colourModes, dscRequiredList: [46], unsafeList: [], validPixelEncodings: 0x1b4d,
                                        colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        let unknown = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, manufacturerName: "APP",
                                                                 currentMode: Self.liveStudio, drivenTiming: DisplayTimingStatement(driven: subset, allTimings: Self.statementStudio.allTimings)), edid: studio5K))
        #expect(unknown.facts.isAppleDisplay == true)
        #expect(unknown.bottleneck == .unknownMode)
        #expect(unknown.detail.contains("does not name the colour format in use"), "\(unknown.detail)")
        #expect(!unknown.detail.contains("Apple"))
        // The Thunderbolt Display shape (06102792-): no mode DSC-capable, empty list: uncompressed by the general rule.
        let thunderbolt = DisplayTimingLists(colourModes: [Self.colour(46, .rgb444, 8, dsc: 0), Self.colour(48, .rgb444, 10, dsc: 0)], dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1b4d,
                                             colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        let tb = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, manufacturerName: "APP",
                                                            currentMode: Self.liveStudio, drivenTiming: DisplayTimingStatement(driven: thunderbolt, allTimings: [Self.listing(5120, 2880, 60.0, 936_000_000, thunderbolt)])), edid: studio5K))
        #expect(tb.facts.dscReading == .uncompressed)
        #expect(tb.bottleneck == .fine)
        #expect(!tb.detail.contains("Apple"))
    }

    @Test("The cross-check flags a contradiction and decides nothing")
    func contradictionIsFlaggedButDecidesNothing() throws {
        // Statement says uncompressed; the live 4K120 at 8-bit RGB needs 28.5 Gbps against 12.96: contradiction, verdict still follows the statement.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120, bitsPerComponent: 8, pixelClockHz: 1_188_000_000, pixelEncoding: .rgb444)
        let says = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, drivenTiming: Self.offering([Self.listing(3840, 2160, 120.0, 1_188_000_000)])), edid: dellU2725QE))
        #expect(says.facts.statementContradiction == true)
        #expect(says.facts.dscReading == .uncompressed)
        #expect(says.bottleneck == .fine, "the live mode meets the top; the statement stands")
        // Statement says DSC on; a 1080p60 at 8-bit RGB needs 3.56 Gbps, below the bottom of 25.31...25.92: contradiction, verdict still .compressionActive.
        let small = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 148_500_000, pixelEncoding: .rgb444)
        let listed = DisplayTimingStatement(driven: Self.dscLists(), allTimings: [Self.listing(1920, 1080, 60.0, 148_500_000, Self.dscLists())])
        let on = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: small, drivenTiming: listed), edid: g34w))
        #expect(on.facts.statementContradiction == true)
        #expect(on.bottleneck == .compressionActive)
        #expect(on.statementReceipts().contains { $0.contains("disagrees with macOS's statement") }, "the K14 receipt follows the flag")
    }

    @Test("On an Apple display reading DSC on, a live need under the usable floor is not a contradiction (PR #665 gate fix round 2, L2)")
    func appleDSCOnBelowTheFloorIsNotAContradiction() throws {
        // The live check on a Studio Display (M5, macOS 26.6, 4 lanes HBR3, run at 65a6a5fa) printed
        // K14 under the 25.3 Gbps floor with DSC on. The node lists DSC on every timing whatever the
        // link (the Apple clause: the list is not a link statement), so that is the expected state and
        // the line was noise. At HEAD a two-depth Apple timing yields no figure at all, so this
        // single-depth fixture is the shape the exemption decides. Same statement and live mode on a
        // non-Apple EDID: informative, stays.
        let small = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 148_500_000, pixelEncoding: .rgb444)
        let listed = DisplayTimingStatement(driven: Self.dscLists(), allTimings: [Self.listing(1920, 1080, 60.0, 148_500_000, Self.dscLists())])
        let apple = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", manufacturerName: "APP", currentMode: small, drivenTiming: listed), edid: g34w))
        #expect(apple.facts.isAppleDisplay == true)
        #expect(apple.facts.dscReading == .dscOn)
        let need = try #require(apple.facts.liveNeededGbps)
        let usable = try #require(apple.facts.usableGbpsRange)
        #expect(need < usable.lowerBound, "fixture guard: 3.56 Gbps is under the 25.3 Gbps floor")
        #expect(apple.facts.statementContradiction == false)
        #expect(apple.bottleneck == .compressionActive && apple.summary == "Display running compressed (DSC)")
        #expect(!apple.statementReceipts().contains { $0.contains("disagrees with macOS's statement") }, "the receipt follows the flag")
        let nonApple = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: small, drivenTiming: listed), edid: g34w))
        #expect(nonApple.facts.statementContradiction == true, "unchanged on a non-Apple display")
        // The helper itself: Apple exempts DSC on under the floor and nothing else.
        let range = 25.3125...25.92
        #expect(DisplayDiagnostic.statementContradiction(reading: .dscOn, liveNeededGbps: 3.564, usable: range, isAppleDisplay: true) == false)
        #expect(DisplayDiagnostic.statementContradiction(reading: .dscOn, liveNeededGbps: 3.564, usable: range, isAppleDisplay: false) == true)
        #expect(DisplayDiagnostic.statementContradiction(reading: .uncompressed, liveNeededGbps: 30, usable: range, isAppleDisplay: true) == true, "uncompressed above the ceiling on an Apple display still contradicts")
        #expect(DisplayDiagnostic.statementContradiction(reading: .unresolved, liveNeededGbps: 3.564, usable: range, isAppleDisplay: true) == false)
    }

    @Test("Facts carry the statement on every path, the no-EDID path included")
    func factsCarryTheStatementWithoutAnEDID() throws {
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", currentMode: Self.live27C1UL, drivenTiming: Self.statement27C1UL), edid: nil))
        #expect(diag.bottleneck == .unknownMode)
        #expect(diag.facts.dscReading == .uncompressed)
        #expect(diag.facts.drivenTiming == Self.statement27C1UL)
        #expect(diag.facts.liveNeededGbps != nil)
        #expect(diag.facts.usableGbpsRange != nil)
        #expect(diag.facts.topModeAvailability == nil, "no EDID, no top mode to match")
        #expect(diag.facts.statementOffersTopMode == false)
        #expect(diag.facts.topModeListedByNode == nil)
        #expect(diag.facts.downstream420 == .noMode, "the reading is never nil with a statement; no mode converts")
    }

    @Test("(e) No statement, live mode below the top: unknownMode with the node named as unmatched, never an arithmetic verdict")
    func noStatementBelowTopIsUnknown() throws {
        // FO32 top 4K240; live 4K120 on 2 of 4 lanes HBR3. Today this was .compressionActive by arithmetic; 4 of 4 lanes was .compressionPlausible.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        for lanes in [2, 4] {
            let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: lanes, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live), edid: fo32))
            #expect(diag.bottleneck == .unknownMode, "\(lanes) lanes: got \(diag.bottleneck)")
            #expect(diag.isWarning == false)
            #expect(diag.detail.contains("macOS's display node could not be matched to your AORUS FO32U2P"), "\(diag.detail)")
            #expect(diag.detail.contains("top mode (up to 240Hz)"))
            #expect(diag.facts.dscReading == nil)
            #expect(!diag.detail.lowercased().contains("compressed (dsc)"), "no DSC claim without the statement")
        }
    }

    @Test("A macOS-only top mode matches the node by picture and refresh; nothing branches on the figure")
    func macOSOnlyTopMatchesWithoutAClock() throws {
        // The UGREEN's 4K60 is declared only from the Y420VDB, so CoreGraphics naming 4K60 is macOS's fact alone (no declared clock).
        let cg = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 30, bitsPerComponent: 8, pixelClockHz: 297_000_000, pixelEncoding: .rgb444)
        let statement = Self.offering([Self.listing(3840, 2160, 30.0, 297_000_000), Self.listing(3840, 2160, 60.0, 594_000_000, id: 97)])
        let dp = makeDP(lanes: 2, maxLanes: 2, rateDesc: "5.4 Gbps (HBR2)", dfpType: "HDMI", currentMode: live, maxMode: cg, drivenTiming: statement)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panelUGREEN))
        #expect(diag.topMode?.source == .reportedByMacOSOnly, "fixture guard")
        #expect(diag.facts.neededGbps == nil, "no declared clock: the receipt is empty, and nothing needed it")
        #expect(diag.facts.topModeMatch == .sameRefresh, "the exact step needs a clock; the same-refresh step matched the node's 594 MHz 4K60")
        #expect(diag.facts.topModeAvailability == .offeredUncompressed)
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(!diag.detail.contains("4:2:0"), "the 4:2:0 sentence stays off when the top is macOS's own report")
    }

    @Test("The top-mode figure is the declared clock at 8-bit RGB, a receipt, whatever the live mode's depth")
    func topModeFigureKeepsEightBitRGB() throws {
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, manufacturerName: "APP", currentMode: Self.liveStudio, drivenTiming: Self.statementStudio), edid: studio5K))
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 964.8e6 * 24 / 1e9) < 1e-9)
        #expect(DisplayDiagnostic.topModeBitsPerPixel == 24)
    }

    @Test("Receipts: the converter's unsafe line names the count when the list read, and says so when it did not (rulings 1 and 42)")
    func receiptsNameTheUnsafeListState() throws {
        let dp = makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", branchDeviceId: "Dp1.2", currentMode: Self.live27C1UL, drivenTiming: Self.statement27C1UL)
        let read = try #require(DisplayDiagnostic(dp: dp, edid: panel27C1UL))
        #expect(read.statementReceipts().contains("macOS rates 4 of 4 colour modes on this timing as above the HDMI adapter's TMDS rate limit."), "\(read.statementReceipts())")
        let unsafeUnread = DisplayTimingStatement(driven: DisplayTimingLists(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1b4d,
                                                                             colourModesComplete: true, dscListComplete: true, unsafeListComplete: false),
                                                  allTimings: Self.statement27C1UL.allTimings)
        let unread = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", branchDeviceId: "Dp1.2", currentMode: Self.live27C1UL, drivenTiming: unsafeUnread), edid: panel27C1UL))
        #expect(unread.statementReceipts().contains("macOS's list of colour modes above the HDMI adapter's TMDS rate limit could not be read for this timing."), "\(unread.statementReceipts())")
        #expect(!unread.statementReceipts().contains { $0.hasPrefix("macOS rates") })
        #expect(unread.statementReceipts().first == "macOS states: Uncompressed", "the DSC statement is untouched by the unsafe list")
        #expect(unread.bottleneck == .fine)
        // Native DisplayPort never shows either line, read or not.
        let native = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", currentMode: Self.live27C1UL, drivenTiming: unsafeUnread), edid: panel27C1UL))
        #expect(!native.statementReceipts().contains { $0.contains("TMDS") })
    }

    @Test("Receipts: on the Mac's own HDMI port the unsafe line names the port, not an adapter (PR #665 gate rerun, note 4 ruled)")
    func nativeHDMIPortPrintsThePortTMDSReceipt() throws {
        // Dump A1: the SoC's HDMI transport is itself the DP-to-HDMI stage, so the unsafe list is
        // meaningful on a native HDMI port; sinkType is nil there by design (issue #352), so K15's
        // "adapter" wording cannot be used. K39 names the port. 23 of 38 native-HDMI corpus nodes
        // carry unsafe members on the driven timing and printed nothing.
        let dp = makeHDMIPortDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: Self.live27C1UL, drivenTiming: Self.statement27C1UL)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: panel27C1UL))
        #expect(diag.facts.sinkType == nil, "fixture guard: a native HDMI port is not an adapter")
        #expect(diag.facts.isNativeHDMIPort == true)
        #expect(diag.statementReceipts().contains("macOS rates 4 of 4 colour modes on this timing as above the HDMI port's TMDS rate limit."), "\(diag.statementReceipts())")
        #expect(!diag.statementReceipts().contains { $0.contains("adapter") })
        #expect(diag.bottleneck == .fine, "the receipt is a fact, never a verdict (ruling 1)")
        // The unreadable list on a native port: K40, the port wording of K38.
        let unsafeUnread = DisplayTimingStatement(driven: DisplayTimingLists(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1b4d,
                                                                             colourModesComplete: true, dscListComplete: true, unsafeListComplete: false),
                                                  allTimings: Self.statement27C1UL.allTimings)
        let unread = try #require(DisplayDiagnostic(dp: makeHDMIPortDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: Self.live27C1UL, drivenTiming: unsafeUnread), edid: panel27C1UL))
        #expect(unread.statementReceipts().contains("macOS's list of colour modes above the HDMI port's TMDS rate limit could not be read for this timing."), "\(unread.statementReceipts())")
        #expect(!unread.statementReceipts().contains { $0.contains("adapter") })
        // An empty unsafe list on a native port prints nothing, as on a converter.
        let none = try #require(DisplayDiagnostic(dp: makeHDMIPortDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: Self.liveU3225QE, drivenTiming: Self.statementU3225QE), edid: dellU2725QE))
        #expect(!none.statementReceipts().contains { $0.contains("TMDS") })
        // A converter still prints K15 (the m3 anchor's line), and native DisplayPort nothing.
        let converter = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2, maxLanes: 2, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", branchDeviceId: "Dp1.2", currentMode: Self.live27C1UL, drivenTiming: Self.statement27C1UL), edid: panel27C1UL))
        #expect(converter.facts.isNativeHDMIPort == false)
        #expect(converter.statementReceipts().contains("macOS rates 4 of 4 colour modes on this timing as above the HDMI adapter's TMDS rate limit."))
    }
}
