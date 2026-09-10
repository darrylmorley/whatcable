import Foundation
import Testing
@testable import WhatCableCore

@Suite("Display Diagnostic")
struct DisplayDiagnosticTests {

    // MARK: - Fixtures

    /// The G34w-10 as parsed by EDIDInfo: preferred 3440x1440@60, ceiling
    /// 100Hz / 600 MHz. 600e6 x 24bpp = 14.4 Gbps usable needed.
    private let g34w = EDIDInfo(
        monitorName: "LEN G34w-10",
        versionMajor: 1, versionMinor: 3,
        preferredWidth: 3440, preferredHeight: 1440, preferredRefreshHz: 60,
        preferredPixelClockHz: 319_890_000,
        maxRefreshHz: 100, maxPixelClockHz: 600_000_000
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
        let edidData = Data(EDIDInfoTests.g34wBaseBlock)
        let diag = try #require(DisplayDiagnostic(dp: makeDP(lanes: 4, edidData: edidData)))
        #expect(diag.bottleneck == .fine)
        #expect(diag.facts.monitorName == "LEN G34w-10")
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
    private let fo32 = EDIDInfo(
        monitorName: "AORUS FO32U2P",
        versionMajor: 1, versionMinor: 4,
        preferredWidth: 3840, preferredHeight: 2160, preferredRefreshHz: 240,
        preferredPixelClockHz: 2_340_000_000,
        maxRefreshHz: 240, maxPixelClockHz: 2_340_000_000
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
        let huge = EDIDInfo(
            monitorName: "8K panel",
            versionMajor: 1, versionMinor: 4,
            preferredWidth: 7680, preferredHeight: 4320, preferredRefreshHz: 60,
            preferredPixelClockHz: 4_170_000_000,
            maxRefreshHz: 60, maxPixelClockHz: 4_170_000_000
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
        let studioEdid = EDIDInfo(
            monitorName: "Studio Display",
            versionMajor: 1, versionMinor: 4,
            preferredWidth: 4096, preferredHeight: 2304, preferredRefreshHz: 60,
            preferredPixelClockHz: 600_000_000,
            maxRefreshHz: 60, maxPixelClockHz: 600_000_000
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
        "00ffffffffffff001c5415320000000009220104b5452778fb0ad5af4e3eb5240e5054" +
        "bfef80714f81c08100814081809500a9c0b3004dd000a0f0703e8030203500bb8b2100" +
        "001a000000fd0c30f0ffffea010a202020202020000000fc00414f52555320464f3332" +
        "553250000000ff0000000000000000000000000000020d02033c704f6175765e5f603f" +
        "4003040f10131f292309570783010000741a0000030330f000a067024f02f000000000" +
        "0000e305c301e6060d01674f026fc200a0a0a0555030203500bb8b2100001a565e00a0a" +
        "0a0295030203500bb8b2100001a0000000000000000000000000000000000000000000" +
        "0000000000000000000005e7012790300030164e9ec00047f079f002f801f003704860" +
        "002000400ca9c0104ff099f002f801f009f05b20002000400bb5a0204ff0e9f002f801" +
        "f006f08b100020004005be70204ff0e9f002f801f006f08da0002000400f77e0304ff0" +
        "edf002f801f006f08bc0002000400000000000000000000000000000000000000f090"
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
        let edid = try #require(EDIDInfo(Self.fo32RealEDID))
        #expect(edid.monitorName == "AORUS FO32U2P")
        #expect(edid.preferredWidth == 3840)
        #expect(edid.preferredHeight == 2160)
        #expect(edid.maxRefreshHz == 240)
        // Product id (EDID bytes 10-11) is 0x3215 = 12821, the corpus value.
        #expect(Self.fo32RealEDID[10] == 0x15 && Self.fo32RealEDID[11] == 0x32)
    }

    @Test("Real corpus EDID at the DP ceiling without a live mode stays compressionPlausible")
    func corpusEDIDCompressionPlausible() throws {
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", edidData: Self.fo32RealEDID)
        let diag = try #require(DisplayDiagnostic(dp: dp))
        #expect(diag.bottleneck == .compressionPlausible)
    }

    @Test("Real corpus EDID plus a matched 4K240 live mode confirms full quality")
    func corpusEDIDUpgradesWithLiveMode() throws {
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", edidData: Self.fo32RealEDID, currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp))
        #expect(diag.bottleneck == .fine)
        #expect(diag.detail.contains("3840 x 2160 @ 240Hz"))
    }

    // MARK: - CoreGraphics max mode as the authoritative top-mode reference

    /// An EDID whose range-limits descriptor is absent, so its only idea of the
    /// "top mode" is the 60Hz preferred mode, understating a 240Hz panel. The
    /// high max pixel clock forces the link short of the uncompressed top so the
    /// compression branch (where the at-top-mode check runs) is reached.
    private let understatedEdid = EDIDInfo(
        monitorName: "Understated 4K",
        versionMajor: 1, versionMinor: 4,
        preferredWidth: 3840, preferredHeight: 2160, preferredRefreshHz: 60,
        preferredPixelClockHz: 533_000_000,
        maxRefreshHz: nil, maxPixelClockHz: 2_340_000_000
    )

    @Test("With no CG max mode, an understated EDID top falsely confirms a 120Hz mode")
    func understatedEdidWithoutMaxModeOverconfirms() throws {
        // The EDID thinks the top mode is 60Hz, so a 120Hz live mode clears it
        // and (wrongly, but this is the EDID-only fallback) reads as full quality.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: understatedEdid))
        #expect(diag.bottleneck == .fine)
    }

    @Test("The CG max mode corrects it: 120Hz below a true 240Hz top stays compressionPlausible")
    func cgMaxModeTightensTopReference() throws {
        // Same understated EDID and same 120Hz live mode, but now CoreGraphics
        // supplies the real 240Hz top. 120 < 240, so it is genuinely not at the
        // top mode and we must not confirm full quality.
        let live = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120)
        let top = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: live, maxMode: top)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: understatedEdid))
        #expect(diag.bottleneck == .compressionPlausible)
    }

    @Test("At the CG max mode, the verdict confirms full quality")
    func atCgMaxModeConfirmsFine() throws {
        let top = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240)
        let dp = makeDP(lanes: 4, maxLanes: 4, rateDesc: "8.1 Gbps (HBR3)", currentMode: top, maxMode: top)
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: understatedEdid))
        #expect(diag.bottleneck == .fine)
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
    private let dellU2725QE = EDIDInfo(
        monitorName: "DELL U2725QE",
        versionMajor: 1, versionMinor: 4,
        preferredWidth: 3840, preferredHeight: 2160, preferredRefreshHz: 60,
        preferredPixelClockHz: 533_000_000,
        maxRefreshHz: 120, maxPixelClockHz: 1_100_000_000
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
        let panel = EDIDInfo(
            monitorName: "PG42UQ",
            versionMajor: 1, versionMinor: 4,
            preferredWidth: 3840, preferredHeight: 2160, preferredRefreshHz: 120,
            preferredPixelClockHz: 1_300_000_000,
            maxRefreshHz: 120, maxPixelClockHz: 1_300_000_000
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
        let panel = EDIDInfo(
            monitorName: "PG42UQ",
            versionMajor: 1, versionMinor: 4,
            preferredWidth: 3840, preferredHeight: 2160, preferredRefreshHz: 120,
            preferredPixelClockHz: 1_300_000_000,
            maxRefreshHz: 120, maxPixelClockHz: 1_300_000_000
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
}
