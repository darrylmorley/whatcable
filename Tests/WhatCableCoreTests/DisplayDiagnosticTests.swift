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
        currentMode: DisplayCurrentMode? = nil,
        maxMode: DisplayCurrentMode? = nil
    ) -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: active,
                laneCount: lanes,
                maxLaneCount: maxLanes,
                linkRate: 3,
                linkRateDescription: rateDesc,
                tunneled: tunneled,
                hpdState: 1
            ),
            monitor: edidData.map {
                MonitorInfo(
                    manufacturerName: nil, productName: nil, productId: nil,
                    yearOfManufacture: nil, edid: $0
                )
            },
            dfpType: dfpType,
            branchDeviceId: branchDeviceId,
            currentMode: currentMode,
            maxMode: maxMode
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

    @Test("4-lane HBR2 carries the G34w-10's 100Hz mode: fine")
    func fourLaneFits() throws {
        // delivered = 4 x 5.4 x 0.8 = 17.28 Gbps usable >= 14.4 needed.
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4), edid: g34w))
        #expect(diag.bottleneck == .fine)
        #expect(diag.isWarning == false)
        #expect(diag.facts.deliveredGbps.map { $0 > 17 } == true)
    }

    @Test("2-lane HBR2 falls short of the 100Hz mode: belowMonitorMax")
    func twoLaneShortfall() throws {
        // delivered = 2 x 5.4 x 0.8 = 8.64 Gbps usable < 14.4 needed.
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2), edid: g34w))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.isWarning == true)
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
            DisplayDiagnostic(dp: makeDP(lanes: 2, tunneled: true), edid: g34w)
        )
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.cableAssessment == .unlikelyTheCable)
        #expect(diag.detail.lowercased().contains("tunnel"))
        #expect(diag.detail.lowercased().contains("unlikely to be the cable"))
    }

    @Test("All host lanes in use on a passive cable exonerates it")
    func allLanesExonerates() throws {
        // 4 of 4 lanes but a low rate (RBR) leaves the 100Hz mode short.
        // The cable carries every lane, so it isn't lane-limiting.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "1.62 Gbps (RBR)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w, cable: cable(active: false)))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.cableAssessment == .unlikelyTheCable)
        #expect(diag.detail.lowercased().contains("every displayport lane"))
    }

    @Test("Active cable is NOT exonerated on the lane signal (issue #111)")
    func activeCableNotExonerated() throws {
        // Same all-lanes shortfall, but the cable is active. Active cables can
        // misreport, so the lane signal alone must not exonerate them.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "1.62 Gbps (RBR)")
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

    @Test("Shortfall behind an HDMI adapter: adapterLimit, not cable blame")
    func adapterShortfall() throws {
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2, dfpType: "HDMI"), edid: g34w)
        )
        #expect(diag.bottleneck == .adapterLimit)
        #expect(diag.facts.sinkType == "HDMI")
        #expect(diag.summary.contains("HDMI"))
    }

    @Test("An HDMI adapter that still fits is fine, no adapter blame")
    func adapterButFits() throws {
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 4, dfpType: "HDMI"), edid: g34w)
        )
        #expect(diag.bottleneck == .fine)
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
        #expect(diag.bottleneck == .fine)
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
        let dp = makeDP(lanes: 2, dfpType: "HDMI", branchDeviceId: "Dp1.2")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: g34w))
        #expect(diag.bottleneck == .adapterLimit)
        #expect(diag.facts.branchDevice == "DisplayPort 1.2")
        #expect(diag.detail.contains("DisplayPort 1.2"))
    }

    @Test("Adapter with no branch device keeps the plain wording")
    func adapterNoBranchDevice() throws {
        let dp = makeDP(lanes: 2, dfpType: "HDMI", branchDeviceId: nil)
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

    @Test("Live LG UltraFine 4K on tunnelled 4-lane HBR2: fine, cable exonerated")
    func liveLGUltraFineTunnelled() throws {
        // Real capture (M3 Max, Test Kit probe 33, 2026-05-30): a native-DP LG
        // UltraFine 4K reached over a Thunderbolt/USB4 tunnel at 4 lanes HBR2.
        // End to end from the real EDID bytes: 600 MHz x 24bpp = 14.4 Gbps
        // needed, 4 x 5.4 x 0.8 = 17.3 delivered, so the link carries the top
        // mode. The first live tunnelled sample, so it also exercises the
        // tunnelled cable-exoneration path that only synthetic tests hit before.
        let edid = Data(EDIDInfoTests.hexBytes(EDIDInfoTests.lgUltraFineHex))
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 4, tunneled: true, edidData: edid))
        )
        #expect(diag.bottleneck == .fine)
        #expect(diag.cableAssessment == .unlikelyTheCable)
        #expect(diag.facts.monitorName == "LG UltraFine")
        #expect(diag.facts.lanes == 4)
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

    @Test("4K240 at the DP ceiling (4-lane HBR3) reads as compression, not a warning")
    func ceilingCompressionPlausible() throws {
        // 56.16 Gbps uncompressed needed, 4 x 8.1 x 0.8 = 25.92 delivered. The
        // link is at every lane and HBR3, so the gap is most likely covered by
        // DSC, not a link the user can widen. (Issue #246.)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .compressionPlausible)
        #expect(diag.isWarning == false)
        // No "monitor can do more" headline, no "change your resolution" advice.
        #expect(!diag.summary.lowercased().contains("can do more"))
        #expect(diag.detail.lowercased().contains("compression"))
    }

    @Test("At the ceiling, even a mode DSC can't fully cover stays compressionPlausible")
    func ceilingTriggersRegardlessOfDSCHeadroom() throws {
        // ~100 Gbps uncompressed need over 25.92 delivered is more than a 3:1
        // DSC ratio could carry, but the trigger is the link being at the
        // ceiling, not DSC feasibility: there is still no wider link to select.
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
        #expect(diag.bottleneck == .compressionPlausible)
    }

    @Test("HBR3 but not all lanes stays belowMonitorMax (ceiling needs every lane)")
    func hbr3PartialLanesStillWarns() throws {
        // 2 of 4 lanes at HBR3 = 12.96 delivered, short of the FO32's 56 Gbps.
        // The link isn't at the ceiling (lanes < maxLanes), so the ordinary
        // shortfall verdict stands and still warns.
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.isWarning == true)
    }

    @Test("All lanes but a low rate stays belowMonitorMax (ceiling needs HBR3+)")
    func allLanesLowRateStillWarns() throws {
        // 4 of 4 lanes but HBR2 (5.4 < 8.0): not the ceiling. A display needing
        // more than the 17.28 delivered still gets the ordinary verdict.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .belowMonitorMax)
    }

    @Test("Tunneled DP at the ceiling also reads as compression, cable still exonerated")
    func tunneledAtCeilingCompressionPlausible() throws {
        // A tunnelled DP link (TB/USB4 dock) at 4/4 HBR3 short of the FO32's top
        // mode. The adapter branch only returns for HDMI/DVI/VGA, so tunnels
        // reach the ceiling guard: at 4 lanes HBR3 the DP link is maxed whether
        // tunnelled or not, so "change your resolution" is the wrong advice here
        // too. The tunnel still exonerates the cable in the structured verdict.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .compressionPlausible)
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

    @Test("Live mode below the top mode keeps today's compressionPlausible verdict")
    func liveModeBelowTopDoesNotUpgrade() throws {
        // The display is actually running 4K60, short of its 240Hz top mode, so
        // there is no certainty to upgrade with: stays compressionPlausible.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .compressionPlausible)
    }

    @Test("No live mode is the regression guard: behaviour is exactly today's verdict")
    func noLiveModeKeepsShippedVerdict() throws {
        // The shipped Option A path must never change when currentMode is nil.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .compressionPlausible)
        #expect(diag.facts.currentMode == nil)
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

    @Test("Real corpus EDID at the DP ceiling without a live mode stays compressionPlausible")
    func corpusEDIDCompressionPlausible() throws {
        // CoreGraphics supplies the 4K240 top mode, exactly as it does on the
        // live app path. The EDID cannot: see
        // `corpusEDIDWithoutCoreGraphicsReadsItsParsedTimings` below.
        let top = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)",
                        edidData: Self.fo32RealEDID, maxMode: top)
        let diag = try #require(DisplayDiagnostic(dp: dp))
        #expect(diag.bottleneck == .compressionPlausible)
    }

    @Test("Real corpus EDID with no CoreGraphics data still reaches the DisplayPort ceiling verdict")
    func corpusEDIDWithoutCoreGraphicsReadsItsParsedTimings() throws {
        // The FO32U2P's 240 Hz modes live in a DisplayID extension block,
        // now parsed, so its highest detailed timing is the real 3840x2160
        // @240 at 2291.12 MHz rather than an understated 4K60. With every
        // lane at HBR3 and no CoreGraphics live mode to confirm it, the
        // DisplayPort-ceiling branch gives `.compressionPlausible`.
        // `corpusEDIDCompressionPlausible` above is the same EDID WITH the
        // CoreGraphics top mode, which is the live app's usual path.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", edidData: Self.fo32RealEDID)
        let diag = try #require(DisplayDiagnostic(dp: dp))
        #expect(diag.bottleneck == .compressionPlausible)
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

    @Test("A CG max mode above every declared entry is macOS only, whatever the live mode says")
    func cgMaxModeAboveDeclaredListIsMacOSOnly() throws {
        // Same understated EDID, and CoreGraphics names 4K240 as the top mode.
        // No declared entry is 4K240 and no tiled composite explains it, so
        // its pixel clock is nowhere we can read: the diagnostic names the
        // mode and computes nothing, whether the live mode is below it (a) or
        // at it (b). Reassuring on (b) would need a bandwidth figure the EDID
        // never gave us.
        let top = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let below = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let a = try #require(DisplayDiagnostic(
            dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: below, maxMode: top),
            edid: understatedEdid))
        #expect(a.bottleneck == .unknownMode, "got \(a.bottleneck)")
        #expect(a.facts.topModeSource == "macOS only")
        #expect(a.facts.neededGbps == nil)
        let b = try #require(DisplayDiagnostic(
            dp: makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: top, maxMode: top),
            edid: understatedEdid))
        #expect(b.bottleneck == .unknownMode, "got \(b.bottleneck)")
        #expect(b.facts.maxRefreshHz == 240)
        #expect(b.detail.contains("\(3840.formatted()) × \(2160.formatted()) mode at 240Hz"), "got \(b.detail)")
    }

    @Test("The CG max mode is carried in the facts for the capability label")
    func maxModeSurfacesInFacts() throws {
        let top = DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", tunneled: true, currentMode: top, maxMode: top)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.facts.maxMode?.width == 5120)
        #expect(diag.facts.maxMode?.height == 2880)
    }

    @Test("No Billboard note when the link is at the ceiling (can't claim below best mode)")
    func noBillboardNoteWhenCompressionPlausible() throws {
        // At the ceiling we can't say the link is below the monitor's best mode
        // (it may be at it via DSC), so the corroborating signal the Billboard
        // diagnosis needs is absent and the note must stay silent, even with a
        // Billboard device present.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32, billboardPresent: true))
        #expect(diag.bottleneck == .compressionPlausible)
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

    @Test("4K120 over a 2-lane HBR3 link with DSC active reads as compressionActive, not a shortfall")
    func liveModeNeedsDSCIsCompressionActive() throws {
        // Link: 2 of 4 lanes at HBR3 = 12.96 Gbps usable. Live mode: 4K120 =
        // ~19.91 Gbps uncompressed (3840 x 2160 x 120 x 24 / 1e9). Picture is on
        // the screen, so DSC has to be carrying it. Not at the DP ceiling
        // (lanes < maxLanes), so the existing .compressionPlausible block does
        // not fire; the new branch catches this.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .compressionActive)
        #expect(diag.isWarning == false)
        #expect(diag.detail.lowercased().contains("compression"))
        #expect(diag.detail.contains("3840 x 2160 @ 120Hz"))
        // The old "monitor can do more / change your resolution" wording must
        // not appear here: that's the whole point of the fix.
        #expect(!diag.summary.lowercased().contains("can do more"))
    }

    @Test("Live mode within the link's capacity falls through to belowMonitorMax (no false DSC claim)")
    func liveModeWithinLinkDoesNotClaimDSC() throws {
        // Same DELL panel, but the user is actually at 4K60 (= ~5.97 Gbps
        // uncompressed) over a 2-lane HBR3 link (12.96 Gbps delivered). The
        // live mode fits comfortably, so DSC is NOT proven active and the
        // verdict stays as today's shortfall verdict.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .belowMonitorMax)
    }

    @Test("No current mode keeps today's belowMonitorMax behaviour (regression guard)")
    func noCurrentModeKeepsShippedBehaviour() throws {
        // A 2-lane HBR3 link short of the DELL's top mode without a live mode:
        // the new branch must not fire (no evidence), so the verdict stays as
        // it was on main before this change.
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .belowMonitorMax)
    }

    @Test("compressionActive is not a warning and silences the Billboard note")
    func compressionActiveSilencesBillboardNote() throws {
        // Billboard-note gate is `isWarning`. Provably-active DSC is the link
        // doing its job, not a degraded link, so the note must stay silent.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE, billboardPresent: true))
        #expect(diag.bottleneck == .compressionActive)
        #expect(diag.billboardNote == nil)
    }

    @Test("At-ceiling shortfall still prefers compressionPlausible/fine (no regression)")
    func compressionPlausibleStillWinsAtCeiling() throws {
        // 4-lane HBR3 with the FO32U2P: the at-ceiling block (above the new
        // branch) must still claim this first. A matching live mode upgrades
        // to .fine; no live mode keeps .compressionPlausible. .compressionActive
        // must not appear here.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: fo32))
        #expect(diag.bottleneck == .compressionPlausible)
    }

    @Test("Adapter limit still wins over compressionActive (HDMI/DVI/VGA branch first)")
    func adapterStillWins() throws {
        // Even when the live mode would otherwise satisfy compressionActive's
        // condition, an HDMI/DVI/VGA adapter in the chain reroutes to
        // .adapterLimit above the new branch. DSC reasoning doesn't carry
        // through a converter, so this ordering matters.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", dfpType: "HDMI", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: dellU2725QE))
        #expect(diag.bottleneck == .adapterLimit)
    }

    @Test("Helper: a zero-refresh live mode is rejected (never a positive claim)")
    func liveModeNeedsCompressionRejectsZeroRefresh() {
        let zeroHz = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 0)
        #expect(DisplayDiagnostic.liveModeNeedsCompression(zeroHz, deliveredGbps: 1.0) == false)
    }

    @Test("10bpc catches the DSC case 24bpp would miss (Codex review false-negative)")
    func tenBpcCatchesUnderestimatedDSC() {
        // 4K60 over a 12 Gbps link. With the old 24bpp assumption the need is
        // 3840 x 2160 x 60 x 24 / 1e9 = 11.94 Gbps, under the 12 x 1.15 = 13.8
        // threshold, so the helper would NOT call DSC. But the live mode is
        // 10bpc HDR, which truly needs 3840 x 2160 x 60 x 30 / 1e9 = 14.93
        // Gbps, comfortably over the threshold: DSC IS on, and the bpc plumbing
        // catches what the bare 24bpp path misses. Codex flagged this as the
        // false-negative case worth covering.
        let live8bpc = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8)
        let live10bpc = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 10)
        #expect(DisplayDiagnostic.liveModeNeedsCompression(live8bpc, deliveredGbps: 12.0) == false)
        #expect(DisplayDiagnostic.liveModeNeedsCompression(live10bpc, deliveredGbps: 12.0) == true)
    }

    @Test("10bpc adds bandwidth budget when delivered headroom is large (no false trigger)")
    func tenBpcDoesNotFalseTriggerWithHeadroom() {
        // 4K60 at 10bpc (14.93 Gbps) over a 25 Gbps tunnel: comfortably within
        // capacity, DSC should not be claimed. Sanity check that lifting bpc
        // doesn't push every HDR mode into the .compressionActive bucket.
        let live10bpc = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 10)
        #expect(DisplayDiagnostic.liveModeNeedsCompression(live10bpc, deliveredGbps: 25.0) == false)
    }

    @Test("nil bpc falls back to the 24bpp default (backwards compatible)")
    func nilBpcFallsBackTo24bpp() {
        // Pre-bpc-plumbing path. Same numbers as the original .compressionActive
        // case must still fire so older snapshots without bpc behave identically.
        let liveNoBpc = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        #expect(liveNoBpc.bitsPerComponent == nil)
        #expect(DisplayDiagnostic.liveModeNeedsCompression(liveNoBpc, deliveredGbps: 12.96) == true)
    }

    @Test("5% noise margin: a mode just over the link does not yet claim DSC")
    func toleranceAbsorbsEstimationNoise() {
        // 5% is an estimation-noise margin, not a blanking adjustment: when the
        // active estimate is within 5% of delivered, treat it as "could go
        // either way" rather than calling DSC. The mode here is 3440 x 1440 at
        // 110Hz x 24bpp = 13.07 Gbps active, ~0.9% over the 12.96 Gbps link but
        // within the 5% threshold (13.61 Gbps). Must NOT call this DSC; the
        // active estimate is too close to the link to draw a confident
        // conclusion either way.
        let near = DisplayCurrentMode(width: 3440, height: 1440, refreshHz: 110, bitsPerComponent: 8)
        #expect(DisplayDiagnostic.liveModeNeedsCompression(near, deliveredGbps: 12.96) == false)
    }

    @Test("Past the 5% margin but within the old 15% band trips compressionActive")
    func toleranceGuardsAgainstFalseNegative() {
        // The earlier code widened the margin to 15%, creating a real false-
        // negative band: 13.58 Gbps to 14.87 Gbps over a 12.93 Gbps link sat
        // inside the old 15% margin and was being silently read as fine. Pin
        // the recovery with a mode that lands squarely in that band: 3440 x
        // 1440 at 95Hz x 30bpp (10bpc) = 14.12 Gbps. Over 12.93 x 1.05 = 13.58
        // (so the corrected 5% margin trips it), but under 12.93 x 1.15 = 14.87
        // (so the old 15% margin missed it). MUST fire on .compressionActive
        // with the corrected tolerance.
        let live = DisplayCurrentMode(width: 3440, height: 1440, refreshHz: 95, bitsPerComponent: 10)
        #expect(DisplayDiagnostic.liveModeNeedsCompression(live, deliveredGbps: 12.93) == true)
    }

    // MARK: - Billboard-device note (gated on a degraded link)

    @Test("Billboard note fires only with a below-best-mode link present")
    func billboardNoteOnShortfall() throws {
        // 2-lane HBR2 falls short of the G34w's 100Hz mode -> belowMonitorMax,
        // and a Billboard device is on the port: the note should appear.
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2), edid: g34w, billboardPresent: true)
        )
        #expect(diag.bottleneck == .belowMonitorMax)
        #expect(diag.billboardNote != nil)
    }

    @Test("Billboard note fires behind a degraded adapter link too")
    func billboardNoteOnAdapterShortfall() throws {
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 2, dfpType: "HDMI"), edid: g34w, billboardPresent: true)
        )
        #expect(diag.bottleneck == .adapterLimit)
        #expect(diag.billboardNote != nil)
    }

    @Test("No Billboard note when the link already carries the top mode")
    func noBillboardNoteWhenFine() throws {
        // 4-lane HBR2 carries the full 100Hz mode -> .fine. Even with a
        // Billboard device present, the diagnosis must not fire: a Billboard
        // device on a healthy link is benign.
        let diag = try #require(
            DisplayDiagnostic(dp: makeDP(lanes: 4), edid: g34w, billboardPresent: true)
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
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 2), edid: g34w))
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
        maxMode: DisplayCurrentMode? = nil
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
            maxMode: maxMode
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

    @Test("Native HDMI port at HBR3 4/4 lanes below uncompressed top: DSC carve-out, not adapter blame")
    func nativeHDMIPortReachesDSCCarveOut() throws {
        // Same shape as the reporter's case: native HDMI port, HBR3 4/4 lanes,
        // delivered ~25.9 Gbps, panel needs ~31 Gbps uncompressed. Pre-fix the
        // adapter branch swallowed this case before the DSC plausibility logic
        // could run. Post-fix sinkType is nil so the link falls through to the
        // ceiling check; HBR3 + max lanes hits the compressionPlausible verdict
        // when no live mode is supplied.
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
        // delivered = 4 * 8.1 * 0.8 = 25.9 Gbps, needed ~31 Gbps. Without an
        // adapter heuristic and at the link ceiling, DSC carve-out fires.
        #expect(diag.bottleneck == .compressionPlausible)
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
            parentPortNumber: 1
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
        // 2 of 4 lanes at HBR3: delivered = 2 x 8.1 x 0.8 = 12.96 Gbps. The
        // envelope route asks for 600 MHz x 24bpp = 14.4 Gbps and warns. The
        // panel's real 4K60 timing asks for 533.25 MHz x 24bpp = 12.80 Gbps,
        // which this link carries, so the correct verdict is silence.
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
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
        let needed = Double(clock) * Double(DisplayDiagnostic.assumedBitsPerPixel) / 1_000_000_000
        #expect(abs(needed - 5.973) < 0.05, "expected ~6.0 Gbps, got \(needed)")
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: pg27AQDP))
        #expect(diag.bottleneck == .fine, "25.92 Gbps carries the 5.97 Gbps declared top, got \(diag.bottleneck)")
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
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)")
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
        #expect(!diag.detail.contains("144"), "the 144Hz envelope must never reach the user")
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
        // 4 of 4 lanes at HBR3 carries 25.92 Gbps; the panel's real 4K60 mode
        // needs 533.16 MHz x 24bpp = 12.80 Gbps. The fix for his bug must leave
        // him with the all-clear, not trade one wrong answer for another.
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
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
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)")
        let a = try #require(DisplayDiagnostic(dp: dp, edid: noEnvelope))
        #expect(a.facts.maxMode == nil, "fixture guard: this path has no CoreGraphics data")
        #expect(a.bottleneck == .fine, "got \(a.bottleneck)")

        // (b) A 2.34 GHz / 240 Hz envelope on a panel that declares one
        // 1080p60 mode. The envelope is never read, so the single declared
        // mode is the top mode (148.5 MHz x 24bpp = 3.56 Gbps, carried) and
        // the verdict is the same fine, with no 240 anywhere in it.
        let oneMode = EDIDInfo.fixture(
            name: "One declared mode",
            version: (1, 4),
            preferred: EDIDInfo.mode(1920, 1080, hTotal: 2292, vTotal: 1080, pixelClockHz: 148_500_000),
            rangeLimits: EDIDInfo.RangeLimits(
                minVerticalHz: 0, maxVerticalHz: 240, minHorizontalKHz: 0, maxHorizontalKHz: 0,
                maxPixelClockHz: 2_340_000_000, timingSupport: .rangeLimitsOnly)
        )
        let b = try #require(DisplayDiagnostic(dp: dp, edid: oneMode))
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
        #expect(diag.bottleneck != .unknownMode)
    }

    // VIC 4 (1280x720p60, 74.25 MHz) and VIC 5 (1920x1080i60, 74.25 MHz), per the bundled
    // CTA-861 table. Same clock, so the larger picture wins the tie: the top mode is the
    // interlaced VIC 5. `EDIDMode.activePixelRate` halves for an interlaced entry (its
    // `refreshHz` is the field rate, and each field carries half the lines); the resolved
    // `TopMode` must carry the same figure, or step 4's macOS-only threshold and
    // `meetsTopMode` judge against double the panel's real pixel rate.
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
        // A progressive 1920x1080 at 30 Hz carries the same active pixels as 1080i60.
        let live = DisplayCurrentMode(width: 1920, height: 1080, refreshHz: 30)
        #expect(DisplayDiagnostic.meetsTopMode(live, top: top) == true)
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
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", maxMode: linkLimited)
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
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", maxMode: cg60)
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
        let dp = makeDP(lanes: 2, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", maxMode: cg30)
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
        #expect(diag.detail.contains("doesn't describe"), "got \(diag.detail)")
        // Int interpolation in `String(localized:)` groups digits by locale
        // ("5,120" in en_US), as the Pro heading's own "\(w) × \(h)" key does.
        #expect(diag.detail.contains("\(5120.formatted()) × \(2880.formatted()) mode at 60Hz"), "got \(diag.detail)")
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
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "5.4 Gbps (HBR2)", tunneled: true, maxMode: cg5K)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: tiled))
        let needed = try #require(diag.facts.neededGbps)
        #expect(abs(needed - 23.155) < 0.001, "expected 964.8 MHz x 24bpp, got \(needed)")
        #expect(diag.facts.topModeSource == "tiled composite of 2 tiles",
                "got \(String(describing: diag.facts.topModeSource))")
        #expect(diag.facts.topModeWidth == 5120)
        #expect(diag.bottleneck == .belowMonitorMax, "23.16 Gbps needed over 17.28 carried, got \(diag.bottleneck)")
        #expect(diag.cableAssessment == .unlikelyTheCable)
    }
}
