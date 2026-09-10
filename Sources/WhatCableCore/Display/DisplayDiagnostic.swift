import Foundation

/// The display sibling of `ChargingDiagnostic` (power) and
/// `DataLinkDiagnostic` (data speed): it answers "is my monitor getting the
/// bandwidth for its best picture, and if not, where is the limit?"
///
/// **Honest altitude.** This dimension is genuinely weaker as an automatic
/// bottleneck-namer than power was, and the type is shaped to say so. Power
/// had three independently measured numbers (charger / cable / negotiated).
/// Here the only "delivered" number we get is the *current* link state
/// (`laneCount x rate`), and a DisplayPort link trains itself down to satisfy
/// whatever mode is on screen right now, to save power. So a link carrying
/// less than the monitor's top mode might mean "the cable/adapter can't do
/// more" OR "the user simply hasn't selected the higher mode, so the GPU
/// trained a lazy link." From passive current-state IOKit data we cannot tell
/// those apart.
///
/// Therefore:
/// - `.fine` is the one confident, unambiguous verdict. If the current link
///   already carries the monitor's top mode, there is definitively no link
///   bottleneck. Lead with this.
/// - `.belowMonitorMax` is **informational, not accusatory**. It states both
///   explanations and never declares the cable guilty.
/// - `.adapterLimit` flags that a USB-C -> HDMI/DVI/VGA converter is in the
///   chain, so a shortfall can't be pinned on the cable.
/// - `.unknownMode` when the link is live but the monitor's EDID is
///   unreadable: report what the link is doing, blame nothing.
///
/// Phase wording is deliberately plain (not `String(localized:)`) while the
/// copy is under review; it moves to the localised bundle once approved,
/// matching how `DataLinkDiagnostic` was handled.
public struct DisplayDiagnostic {
    public enum Bottleneck: Hashable, Sendable {
        /// The current link already carries the monitor's top mode. No limit.
        case fine
        /// The link, as currently trained, carries less than the monitor's
        /// top mode. Ambiguous by nature (cable/adapter cap vs unselected
        /// mode), so the wording stays non-accusatory.
        case belowMonitorMax
        /// A USB-C -> HDMI / DVI / VGA adapter sits in the chain, so a
        /// shortfall cannot be attributed to the cable.
        case adapterLimit
        /// Live link but no readable EDID: nothing to compare against.
        case unknownMode
        /// The link is at the DisplayPort ceiling (every lane, HBR3 or faster)
        /// yet short of the monitor's *uncompressed* top mode. DSC (~3:1
        /// compression) may be carrying the top mode through the link, and
        /// there is no wider link to select, so we can't claim the display is
        /// under-driven. Informational, never a warning. (Issue #246.)
        case compressionPlausible
        /// DSC is **provably active right now**: the live on-screen mode needs
        /// more uncompressed bandwidth than the link is carrying, yet the
        /// picture is reaching the display. That can only happen with
        /// compression on. Stronger than `.compressionPlausible` (a reasoned
        /// inference from the link being at the DP ceiling): this one is
        /// grounded in the empirical gap between `currentMode` and
        /// `deliveredGbps`. Positive, never a warning. (Jimmy's group feedback:
        /// users on DSC-needing modes like 4K120 over DP 1.4 were reading the
        /// old "monitor can do more" shortfall message as a fault.)
        case compressionActive
    }

    /// The resolved numbers behind the verdict, for the Pro "receipts" view.
    /// Kept separate from the `Bottleneck` enum (which is just the verdict
    /// kind) so the screen has structured data and the tests stay simple.
    public struct Facts: Hashable, Sendable {
        public let monitorName: String?
        public let preferredWidth: Int?
        public let preferredHeight: Int?
        public let preferredRefreshHz: Int?
        public let maxRefreshHz: Int?
        /// Bandwidth the monitor's top mode needs, usable Gbps (estimated).
        public let neededGbps: Double?
        /// Bandwidth the current link carries, usable Gbps (estimated).
        public let deliveredGbps: Double?
        public let lanes: Int
        public let maxLanes: Int
        public let rateDescription: String?
        /// "HDMI" / "DVI" / "VGA" when an adapter is in the chain, else nil.
        public let sinkType: String?
        /// The adapter / branch device's reported DisplayPort version, e.g.
        /// "DisplayPort 1.2", from the DP node's `BranchDeviceID`. nil for a
        /// direct connection or when the field is absent. Descriptive only:
        /// it is what the device reports about itself, paired with the
        /// demonstrated lane usage to explain a cap.
        public let branchDevice: String?
        /// The live on-screen mode from CoreGraphics, when the backend could
        /// match this display to its port. Drives the true resolution label
        /// (issue #249: 5K displays whose EDID can't describe their native
        /// mode). nil when there's no live data (a non-Darwin backend, tests,
        /// or no match).
        public let currentMode: DisplayCurrentMode?
        /// The display's native top mode as macOS reports it (CoreGraphics):
        /// highest resolution at its best refresh, EDID-free. The authoritative
        /// "top mode" for the capability label and the at-top-mode check. Same
        /// nil contract as `currentMode`.
        public let maxMode: DisplayCurrentMode?
    }

    /// Whether the cable can be implicated in a shortfall. Deliberately has
    /// no "the cable is the problem" value: from passive current-state data we
    /// can only ever *exonerate* the cable with confidence, never convict it
    /// (the same limit that keeps `.belowMonitorMax` non-accusatory). So the
    /// only confident verdict is "unlikely the cable", backed by demonstrated
    /// evidence, not by the e-marker's claimed rating (issue #111: active
    /// cables misreport their own e-marker, so a rating can't exonerate them).
    public enum CableAssessment: Hashable, Sendable {
        /// Demonstrated, not rated: the DP is tunneled over a Thunderbolt /
        /// USB4 link (so the cable carries far more than any DP mode needs),
        /// or the link is already using every DisplayPort lane the host
        /// exposes on a non-active cable (so the cable isn't lane-limiting).
        case unlikelyTheCable
        /// Can't tell from current-state data. The honest default.
        case inconclusive
    }

    public let bottleneck: Bottleneck
    public let summary: String
    public let detail: String
    public let facts: Facts
    /// Cable attribution, orthogonal to `bottleneck`. Only changes the wording
    /// in the `.belowMonitorMax` case; informational elsewhere.
    public let cableAssessment: CableAssessment
    /// Whether a USB Billboard device is enumerated on this port. Set only by
    /// the Pro Display screen (the inline surfaces never pass it, which keeps
    /// the Billboard *diagnosis* out of the port card by construction). Drives
    /// `billboardNote`.
    public let billboardPresent: Bool

    /// The Billboard-device diagnosis, or `nil` when it should not be shown.
    /// Fires only when a Billboard device is present **and** the link is below
    /// the monitor's best mode (`isWarning`, the same `needed <= delivered`
    /// comparison that drives the verdict, so there is one definition of
    /// "degraded"). A Billboard device on its own is often benign (docks park
    /// them there normally), so naming it is safe everywhere but this pointed
    /// inference is gated on the corroborating degraded link.
    public var billboardNote: String? {
        guard billboardPresent, isWarning else { return nil }
        return String(localized: "A Billboard device is present on this port. That usually appears when an Alt Mode like DisplayPort was set up but didn't fully come up. Your display is below its best mode, so a re-plug, a different cable, or a different adapter may bring it up. Some docks show a Billboard device normally, so this isn't always a fault.", bundle: _coreLocalizedBundle)
    }

    /// True for the cases worth a glance in the inline verdict. `.fine` is the
    /// all-clear and `.unknownMode` is a non-event, so neither warns. Note the
    /// wording stays non-accusatory even when this is true: a warning here
    /// means "worth looking at", not "the cable is broken".
    public var isWarning: Bool {
        switch bottleneck {
        case .fine, .unknownMode, .compressionPlausible, .compressionActive: return false
        case .belowMonitorMax, .adapterLimit: return true
        }
    }
}

extension DisplayDiagnostic {
    /// Assume standard 8-bit RGB (24 bits/pixel) for the bandwidth estimate.
    /// Real links may use 10-bit (30 bpp), chroma subsampling, or DSC
    /// compression, all of which change the maths, so the verdict wording
    /// hedges accordingly.
    static let assumedBitsPerPixel = 24
    /// Don't declare a shortfall on estimation noise alone.
    static let tolerance = 0.05
    /// Margin for `.compressionActive`'s "live mode needs more than the link
    /// carries" check. Kept at 5%, same as the noise margin used elsewhere.
    ///
    /// Why no blanking adjustment: `liveModeNeedsCompression` compares an
    /// active-pixel estimate against the delivered link, while the link
    /// actually carries the EDID pixel clock (active + blanking, 10-20%
    /// higher). So if the active estimate already exceeds delivered, the real
    /// wire is even further over and DSC must be on. The math is conservative
    /// in our favour, not against it; widening this margin to "absorb blanking"
    /// would only create a false-negative band where genuine DSC modes get read
    /// as fine.
    static let compressionActiveTolerance = 0.05
    /// Per-lane rate (Gbps) at or above which the link is running at a high
    /// rate. HBR3 (8.1 Gbps/lane) is the ceiling over USB-C DisplayPort Alt
    /// Mode; UHBR is higher still. At all lanes and this rate, a shortfall
    /// against the *uncompressed* top mode is most likely covered by DSC, not
    /// a link the user can widen (issue #246).
    static let highRatePerLaneGbps = 8.0

    /// Production entry point. Parses the EDID from the DisplayPort node's own
    /// monitor blob, then defers to the injectable initialiser below.
    public init?(dp: IOPortTransportStateDisplayPort, cable: USBPDSOP? = nil, billboardPresent: Bool = false, port: AppleHPMInterface? = nil) {
        let edid = dp.monitor?.edid.flatMap { EDIDInfo($0) }
        self.init(dp: dp, edid: edid, cable: cable, billboardPresent: billboardPresent, port: port)
    }

    /// Test seam: the parsed EDID is injected rather than read from `dp`.
    /// Returns `nil` when there is no live DisplayPort link on this node, so
    /// ports with nothing plugged in stay silent.
    ///
    /// `cable` is the port's USB-PD e-marker (SOP' / SOP''), used only to tell
    /// whether the cable is active (issue #111: active cables misreport, so we
    /// never exonerate one on its e-marker).
    ///
    /// `port` must be the port that `cable` belongs to, so the classifier can
    /// read its `ActiveCable` flag. See `CableClassification.resolve`.
    public init?(dp: IOPortTransportStateDisplayPort, edid: EDIDInfo?, cable: USBPDSOP? = nil, billboardPresent: Bool = false, port: AppleHPMInterface? = nil) {
        guard dp.link.active else { return nil }
        self.billboardPresent = billboardPresent

        let lanes = dp.link.laneCount
        let maxLanes = dp.link.maxLaneCount
        let rate = dp.link.linkRateDescription
        let perLane = Self.perLaneGbps(fromDescription: rate)
        let delivered = perLane.map {
            Double(lanes) * $0 * Self.codingEfficiency(perLaneGbps: $0)
        }
        // Don't treat the built-in HDMI port on an Apple Silicon MacBook Pro /
        // Mac mini as if the display were behind a USB-C-to-HDMI adapter. The
        // SoC drives HDMI directly, so the HDMI sink is the port itself, not a
        // dongle in the chain. With sinkType nil here we skip the adapter-blame
        // branch below AND fall through to the HBR3 + max-lanes DSC carve-out
        // when the link is at its ceiling, which is the right verdict for a
        // native HDMI 2.1 panel running 4K120 via compression. Signal source:
        // `ParentPortTypeDescription` on the DP transport node, populated for
        // every native HDMI display across M1 Pro through M5 Pro in the corpus.
        let sinkType: String?
        if dp.parentPortTypeDescription?.uppercased() == "HDMI" {
            sinkType = nil
        } else {
            sinkType = Self.adapterSinkType(dp.dfpType)
        }
        let branchDevice = Self.branchDeviceLabel(dp.branchDeviceId)

        // Cable attribution. Exonerate only on demonstrated evidence: a
        // Thunderbolt / USB4 tunnel (the cable carries far more than any DP
        // mode needs), or every host DisplayPort lane already in use on a
        // cable we've positively identified as passive (so the cable isn't
        // lane-limiting). We require a *known* passive e-marker, not merely a
        // non-active one: an absent e-marker means an unidentified cable we
        // can't vouch for (often a cheap passive cable that could itself be
        // rate-limiting), and an active cable can misreport its own e-marker
        // (issue #111). The e-marker's claimed rating is never used to
        // exonerate. Assigned once here so it holds on every return path.
        // Read through the classifier, not the e-marker's self-report. Two
        // cables lose their exoneration by that change, both in the direction
        // the paragraph above asks for, so `cableAssessment` moves from
        // `.unlikelyTheCable` to `.inconclusive` for each:
        //
        //   1. a cable on a port whose controller reports an active cable;
        //   2. a cable carrying the issue #111 layout contradiction, with or
        //      without a port. Its VDO[3] is decoded under the passive layout
        //      on purpose, so the raw self-report used to read passive.
        let cableKnownPassive = cable.flatMap {
            CableClassification.resolve(identity: $0, port: port)
        }?.type == .passive
        let cableUnlikely = dp.link.tunneled
            || (lanes > 0 && lanes == maxLanes && cableKnownPassive)
        self.cableAssessment = cableUnlikely ? .unlikelyTheCable : .inconclusive

        // No readable EDID: we can describe the link but have nothing to judge
        // it against. Report, blame nothing.
        guard let edid else {
            self.facts = Facts(
                monitorName: nil,
                preferredWidth: nil, preferredHeight: nil, preferredRefreshHz: nil,
                maxRefreshHz: nil,
                neededGbps: nil, deliveredGbps: delivered,
                lanes: lanes, maxLanes: maxLanes,
                rateDescription: rate, sinkType: sinkType,
                branchDevice: branchDevice,
                currentMode: dp.currentMode, maxMode: dp.maxMode
            )
            self.bottleneck = .unknownMode
            self.summary = String(localized: "Display connected", bundle: _coreLocalizedBundle)
            let base = String(localized: "A display is connected but its capabilities aren't readable, so there's nothing to compare the link against.", bundle: _coreLocalizedBundle)
            if let delivered {
                self.detail = base + " " + String(localized: "The link is carrying about \(Self.gbps(delivered)) (\(lanes) of \(maxLanes) lanes).", bundle: _coreLocalizedBundle)
            } else {
                self.detail = base
            }
            return
        }

        let name = edid.monitorName ?? String(localized: "display", bundle: _coreLocalizedBundle)
        // The monitor's top mode drives the comparison: max pixel clock if the
        // range-limits descriptor gave us one, else the preferred mode.
        let topPixelClockHz = edid.maxPixelClockHz ?? edid.preferredPixelClockHz
        let needed = Double(topPixelClockHz) * Double(Self.assumedBitsPerPixel) / 1_000_000_000

        let baseFacts = Facts(
            monitorName: edid.monitorName,
            preferredWidth: edid.preferredWidth,
            preferredHeight: edid.preferredHeight,
            preferredRefreshHz: edid.preferredRefreshHz,
            maxRefreshHz: edid.maxRefreshHz,
            neededGbps: needed,
            deliveredGbps: delivered,
            lanes: lanes, maxLanes: maxLanes,
            rateDescription: rate, sinkType: sinkType,
            branchDevice: branchDevice,
            currentMode: dp.currentMode, maxMode: dp.maxMode
        )

        // Without a delivered figure (unparseable rate string) we can't
        // compare. Report the monitor, blame nothing.
        guard let delivered else {
            self.facts = baseFacts
            self.bottleneck = .unknownMode
            self.summary = String(localized: "Display connected", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "Your \(name) is connected, but the link rate isn't readable, so there's nothing to compare its capability against.", bundle: _coreLocalizedBundle)
            return
        }

        // Does the current link already carry the monitor's top mode?
        if needed <= delivered * (1 + Self.tolerance) {
            self.facts = baseFacts
            self.bottleneck = .fine
            self.summary = String(localized: "Display running at full quality", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "Your \(name) is connected and the link has the bandwidth for its top mode. Nothing is holding the picture back.", bundle: _coreLocalizedBundle)
            return
        }

        // Shortfall. The current link carries less than the monitor's top
        // mode. Stay non-accusatory: we can't tell a cable/adapter cap from an
        // unselected mode.
        let needLabel = Self.gbps(needed)
        let haveLabel = Self.gbps(delivered)
        let laneLabel: String
        if let rate {
            laneLabel = String(localized: "\(lanes) of \(maxLanes) lanes at \(rate)", bundle: _coreLocalizedBundle)
        } else {
            laneLabel = String(localized: "\(lanes) of \(maxLanes) lanes", bundle: _coreLocalizedBundle)
        }
        let canDo = edid.maxRefreshHz
            .map { String(localized: "up to \($0)Hz", bundle: _coreLocalizedBundle) }
            ?? String(localized: "a higher mode than the link is carrying", bundle: _coreLocalizedBundle)
        let dscCaveat = " " + String(localized: "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.", bundle: _coreLocalizedBundle)

        if let sinkType {
            self.facts = baseFacts
            self.bottleneck = .adapterLimit
            self.summary = String(localized: "Video is going through a \(sinkType) adapter", bundle: _coreLocalizedBundle)
            if let branchDevice {
                self.detail = String(localized: "Your \(name) is reached through a USB-C to \(sinkType) adapter that reports as \(branchDevice), currently carrying about \(haveLabel) (\(laneLabel)), short of the monitor's top mode (\(canDo), about \(needLabel)). With an adapter in the chain, the adapter's own limit may be the cap rather than the cable. A native DisplayPort connection, or a higher-spec adapter, would tell you which.", bundle: _coreLocalizedBundle) + dscCaveat
            } else {
                self.detail = String(localized: "Your \(name) is reached through a USB-C to \(sinkType) adapter, and the link isn't currently carrying the monitor's top mode (\(canDo), about \(needLabel)); it's carrying about \(haveLabel) (\(laneLabel)). With an adapter in the chain, the adapter's own limit may be the cap rather than the cable. Trying the monitor over native DisplayPort, or a higher-spec adapter, would tell you which.", bundle: _coreLocalizedBundle) + dscCaveat
            }
            return
        }

        // The link is at the DisplayPort ceiling (every lane, HBR3 or faster)
        // but still short of the monitor's *uncompressed* top mode. High-
        // resolution displays use DSC (~3:1 compression) to fit a higher mode
        // through a link like this, so the link rate alone can't tell whether
        // the display is already at its best mode, and there is no wider link
        // to select. Drop the "monitor can do more / change your resolution"
        // verdict here: it is the wrong advice when the link is maxed and the
        // picture may already be at full quality via compression. (Issue #246:
        // a 4K240 monitor running 240Hz over HBR3 + DSC was wrongly flagged as
        // under-driven.) Native DisplayPort only: the adapter path returned
        // above, and DSC reasoning doesn't carry through an HDMI/DVI/VGA
        // converter.
        if lanes > 0, lanes == maxLanes, let perLane, perLane >= Self.highRatePerLaneGbps {
            // Certainty upgrade (issue #246): if CoreGraphics confirms the
            // display is actually at its top mode, replace the hedged "may be
            // using compression" with a definitive "running at full quality".
            // Strict and fail-closed: only when we have a matched live mode and
            // it meets the panel's top mode by active-pixel throughput.
            // Anything short, or no live mode at all, keeps today's verdict.
            if let current = dp.currentMode, Self.meetsTopMode(current, maxMode: dp.maxMode, edid: edid) {
                self.facts = baseFacts
                self.bottleneck = .fine
                self.summary = String(localized: "Display running at full quality", bundle: _coreLocalizedBundle)
                self.detail = String(localized: "macOS reports your \(name) at its top mode (\(current.label)), and the link is carrying it. Many high-resolution displays use compression (DSC) to fit a mode like this through the link, so the link rate alone can't show it; your display is at full quality.", bundle: _coreLocalizedBundle)
                return
            }
            self.facts = baseFacts
            self.bottleneck = .compressionPlausible
            self.summary = String(localized: "Display may be using compression to reach its top mode", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "Your \(name) can run \(canDo), which uncompressed would need about \(needLabel). This link is already running every lane at a high rate, carrying about \(haveLabel) (\(laneLabel)). Many high-resolution displays use compression (DSC) to fit their top mode through a link like this, so the link rate alone can't tell whether you're already at your best mode. If the picture looks right, it most likely is.", bundle: _coreLocalizedBundle)
            return
        }

        // DSC provably active. The live on-screen mode needs more uncompressed
        // bandwidth than the link is carrying, yet the picture is reaching the
        // display. The only way that holds is compression on: this is the link
        // doing what it's designed to do, not a fault. Stronger than the
        // ceiling-based `.compressionPlausible` inference above because the
        // evidence is grounded in CoreGraphics' live mode, not just the link
        // being at HBR3. This catches the case Jimmy's group flagged: 4K120
        // DSC-mode displays (DELL U2725QE etc.) over sub-ceiling links being
        // wrongly read as a shortfall.
        if let current = dp.currentMode,
           Self.liveModeNeedsCompression(current, deliveredGbps: delivered) {
            self.facts = baseFacts
            self.bottleneck = .compressionActive
            self.summary = String(localized: "Display running compressed (DSC) to fit through the link", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "macOS reports your \(name)'s current mode as \(current.label), which would need more bandwidth than this link carries uncompressed. High-resolution displays use compression (DSC) to fit a mode like this through a link like this. The picture is reaching the display, so this is working as intended.", bundle: _coreLocalizedBundle)
            return
        }

        self.facts = baseFacts
        self.bottleneck = .belowMonitorMax
        self.summary = String(localized: "Monitor can do more than the link is carrying", bundle: _coreLocalizedBundle)
        if cableUnlikely {
            // The cable is exonerated on demonstrated evidence, so point the
            // user at the likely real cause (the selected mode / the Mac)
            // instead of leaving the cable under suspicion.
            if dp.link.tunneled {
                self.detail = String(localized: "Your \(name) can run \(canDo), which needs about \(needLabel), but the link is currently carrying about \(haveLabel) (\(laneLabel)). The video is tunneled over Thunderbolt or USB4, so the cable carries far more than the display needs: this is unlikely to be the cable. It's most likely the resolution or refresh rate selected in Display settings, or this Mac's limit for this display.", bundle: _coreLocalizedBundle) + dscCaveat
            } else {
                self.detail = String(localized: "Your \(name) can run \(canDo), which needs about \(needLabel), but the link is currently carrying about \(haveLabel) (\(laneLabel)). The cable is already carrying every DisplayPort lane this Mac provides, so this is unlikely to be the cable. It's most likely the resolution or refresh rate selected in Display settings.", bundle: _coreLocalizedBundle) + dscCaveat
            }
        } else {
            self.detail = String(localized: "Your \(name) can run \(canDo), which needs about \(needLabel), but the link is currently carrying about \(haveLabel) (\(laneLabel)). If you've selected the higher mode and aren't getting it, the cable or adapter is the likely limit; if you haven't tried it, selecting it may retrain the link to a higher rate.", bundle: _coreLocalizedBundle) + dscCaveat
        }
    }

    // MARK: - Helpers

    /// Pull the per-lane Gbps figure out of macOS's own rate description, e.g.
    /// "5.4 Gbps (HBR2)" -> 5.4. Using the string sidesteps the unconfirmed
    /// numeric `linkRate` enum (only code 3 / HBR2 is confirmed on real
    /// hardware). Returns nil for "No Link" or anything unparseable.
    static func perLaneGbps(fromDescription desc: String?) -> Double? {
        guard let desc, let gbpsRange = desc.range(of: "Gbps") else { return nil }
        let prefix = desc[desc.startIndex..<gbpsRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        return Double(prefix)
    }

    /// Line-coding efficiency: 8b/10b (0.8) for RBR/HBR/HBR2/HBR3
    /// (<= 8.1 Gbps/lane), 128b/132b (~0.97) for UHBR (>= 10 Gbps/lane).
    static func codingEfficiency(perLaneGbps: Double) -> Double {
        perLaneGbps >= 10 ? 0.9697 : 0.8
    }

    /// Friendly label for the DP node's `BranchDeviceID`, the version the
    /// adapter / branch device reports for itself. Observed format is "Dp1.2"
    /// (a USB-C to HDMI adapter reporting DisplayPort 1.2). Normalised to
    /// "DisplayPort 1.2"; anything that doesn't match the "Dp<version>" shape
    /// is surfaced as-is so we never hide or mangle an unfamiliar value.
    /// Returns nil for a direct connection or an empty field.
    static func branchDeviceLabel(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("dp") {
            let version = raw.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !version.isEmpty, version.first?.isNumber == true {
                return "DisplayPort \(version)"
            }
        }
        return raw
    }

    /// Map a downstream-facing-port type to an adapter sink type, or nil when
    /// the sink is native DisplayPort (no adapter in the chain).
    static func adapterSinkType(_ dfpType: String?) -> String? {
        guard let t = dfpType?.uppercased() else { return nil }
        if t.contains("HDMI") { return "HDMI" }
        if t.contains("DVI") { return "DVI" }
        if t.contains("VGA") { return "VGA" }
        return nil
    }

    /// Human-readable bandwidth, one decimal place, e.g. "14.4 Gbps".
    static func gbps(_ value: Double) -> String {
        String(format: "%.1f Gbps", locale: .current, value)
    }

    /// Whether the live on-screen mode demands more bandwidth than the link
    /// can carry uncompressed: the empirical proof that DSC is active right
    /// now. Bits per pixel come from `current.bitsPerComponent` when
    /// CoreGraphics reported it (8bpc -> 24bpp standard, 10bpc -> 30bpp for
    /// HDR / 10-bit colour), so a HDR mode that legitimately needs more raw
    /// bandwidth is not misread as DSC. With nil bpc we fall back to the
    /// 24bpp assumption, which keeps today's behaviour on backends that don't
    /// plumb bpc.
    ///
    /// The 5% tolerance is an estimation-noise margin, not a blanking
    /// adjustment. The active-pixel figure on the needed side already
    /// understates the real wire draw (which adds blanking), so "needed >
    /// delivered" already implies "wire > delivered" by a comfortable margin.
    /// Widening the tolerance further would only create a false-negative band
    /// where real DSC modes get read as fine.
    static func liveModeNeedsCompression(_ current: DisplayCurrentMode, deliveredGbps: Double) -> Bool {
        guard current.refreshHz > 0 else { return false }
        let bitsPerPixel = current.bitsPerComponent.map { $0 * 3 } ?? Self.assumedBitsPerPixel
        let neededGbps = current.pixelThroughput * Double(bitsPerPixel) / 1_000_000_000
        return neededGbps > deliveredGbps * (1 + Self.compressionActiveTolerance)
    }

    /// Whether the live mode meets the monitor's top mode. Compared in one
    /// domain on purpose: active-pixel throughput on both sides. Never the EDID
    /// pixel clock, which includes blanking and would run ~10-20% higher than
    /// CoreGraphics' active-pixel figure at the very same mode, making this
    /// comparison fail when it shouldn't. The tolerance absorbs blanking and
    /// refresh rounding.
    ///
    /// The top-mode reference is the CoreGraphics max mode when we have it (the
    /// authoritative, EDID-free top mode), falling back to the EDID's preferred
    /// resolution x max refresh. The CG max also handles 5K for free, where the
    /// EDID under-reports the native mode.
    static func meetsTopMode(_ current: DisplayCurrentMode, maxMode: DisplayCurrentMode?, edid: EDIDInfo) -> Bool {
        let topThroughput: Double
        if let maxMode {
            topThroughput = maxMode.pixelThroughput
        } else {
            let topRefresh = Double(edid.maxRefreshHz ?? edid.preferredRefreshHz)
            topThroughput = Double(edid.preferredWidth) * Double(edid.preferredHeight) * topRefresh
        }
        guard topThroughput > 0 else { return false }
        return current.pixelThroughput >= topThroughput * (1 - Self.tolerance)
    }

    // MARK: - Link-rate labelling (shared by every Pro UI surface)

    /// Confirmed numeric `linkRate` fallback, used only when macOS's own
    /// `linkRateDescription` string isn't available. Sourced from a sweep of
    /// the probe-33 (`displayport_capability`) customer submissions. As of the
    /// 2026-07-22 batch the only codes ever observed are 0 ("No Link"),
    /// 1 ("1.62 Gbps (RBR)"), 2 ("2.7 Gbps (HBR)"), 3 ("5.4 Gbps (HBR2)"), and
    /// 4 ("8.1 Gbps (HBR3)"). Code 1 (RBR) is now corpus-confirmed: it first
    /// appeared in that batch on an M2 Max driving an HP E271i over USB-C,
    /// which macOS itself labelled "1.62 Gbps (RBR)". macOS's other documented
    /// codes (6/10/20/30/40) still never appeared once, so they are
    /// deliberately left out here rather than guessed at.
    public static let confirmedLinkRateDescriptions: [Int: String] = [
        0: "No Link",
        1: "1.62 Gbps (RBR)",
        2: "2.7 Gbps (HBR)",
        3: "5.4 Gbps (HBR2)",
        4: "8.1 Gbps (HBR3)",
    ]

    /// Best available link-rate description: macOS's own string when present
    /// and non-blank (always preferred, since it's what the OS itself
    /// reports), else the confirmed numeric fallback above, else nil.
    /// Callers render nil with their own "Rate N" / "Unknown" wording, since
    /// that's a presentation choice, not data this helper owns.
    /// Whitespace-only strings count as absent so a blank IOKit value can't
    /// render as an empty-looking row.
    public static func linkRateDescription(rate: Int, description: String?) -> String? {
        if let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            return trimmed
        }
        return confirmedLinkRateDescriptions[rate]
    }

    /// Short mode name parsed out of a link-rate description's parenthesised
    /// token, e.g. "5.4 Gbps (HBR2)" -> "HBR2". Follows the same
    /// description-first / confirmed-numeric order as `linkRateDescription`.
    /// When the description has no clean parenthesised token (a bare
    /// "UHBR20", nested parens, malformed pairs), the whole description is
    /// returned rather than a guessed fragment: a real OS string beats the
    /// caller's "Rate N" fallback. "No Link" returns nil so inactive links
    /// keep their own wording.
    public static func linkRateShortName(rate: Int, description: String?) -> String? {
        guard let resolved = linkRateDescription(rate: rate, description: description) else {
            return nil
        }
        if resolved == "No Link" { return nil }
        // Token between the first "(" and the last ")". A token that still
        // contains "(" means nested or malformed parens; fall back to the
        // full description instead of a garbled fragment.
        if let open = resolved.firstIndex(of: "("),
           let close = resolved.lastIndex(of: ")"),
           open < close {
            let token = resolved[resolved.index(after: open)..<close]
            if !token.isEmpty, !token.contains("(") { return String(token) }
        }
        return resolved
    }
}
