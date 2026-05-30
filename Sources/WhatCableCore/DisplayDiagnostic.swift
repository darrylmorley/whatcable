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

    /// True for the cases worth a glance in the inline verdict. `.fine` is the
    /// all-clear and `.unknownMode` is a non-event, so neither warns. Note the
    /// wording stays non-accusatory even when this is true: a warning here
    /// means "worth looking at", not "the cable is broken".
    public var isWarning: Bool {
        switch bottleneck {
        case .fine, .unknownMode: return false
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

    /// Production entry point. Parses the EDID from the DisplayPort node's own
    /// monitor blob, then defers to the injectable initialiser below.
    public init?(dp: IOPortTransportStateDisplayPort, cable: USBPDSOP? = nil) {
        let edid = dp.monitor?.edid.flatMap { EDIDInfo($0) }
        self.init(dp: dp, edid: edid, cable: cable)
    }

    /// Test seam: the parsed EDID is injected rather than read from `dp`.
    /// Returns `nil` when there is no live DisplayPort link on this node, so
    /// ports with nothing plugged in stay silent.
    ///
    /// `cable` is the port's USB-PD e-marker (SOP' / SOP''), used only to tell
    /// whether the cable is active (issue #111: active cables misreport, so we
    /// never exonerate one on its e-marker).
    public init?(dp: IOPortTransportStateDisplayPort, edid: EDIDInfo?, cable: USBPDSOP? = nil) {
        guard dp.link.active else { return nil }

        let lanes = dp.link.laneCount
        let maxLanes = dp.link.maxLaneCount
        let rate = dp.link.linkRateDescription
        let perLane = Self.perLaneGbps(fromDescription: rate)
        let delivered = perLane.map {
            Double(lanes) * $0 * Self.codingEfficiency(perLaneGbps: $0)
        }
        let sinkType = Self.adapterSinkType(dp.dfpType)

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
        let cableKnownPassive = cable?.cableVDO?.cableType == .passive
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
                rateDescription: rate, sinkType: sinkType
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
            rateDescription: rate, sinkType: sinkType
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
        let dscCaveat = " " + String(localized: "This estimate assumes standard colour; a display using compression (DSC) may reach more.", bundle: _coreLocalizedBundle)

        if let sinkType {
            self.facts = baseFacts
            self.bottleneck = .adapterLimit
            self.summary = String(localized: "Video is going through a \(sinkType) adapter", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "Your \(name) is reached through a USB-C to \(sinkType) adapter, and the link isn't currently carrying the monitor's top mode (\(canDo), about \(needLabel)); it's carrying about \(haveLabel) (\(laneLabel)). With an adapter in the chain, the adapter's own limit may be the cap rather than the cable. Trying the monitor over native DisplayPort, or a higher-spec adapter, would tell you which.", bundle: _coreLocalizedBundle) + dscCaveat
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
        String(format: "%.1f Gbps", value)
    }
}
