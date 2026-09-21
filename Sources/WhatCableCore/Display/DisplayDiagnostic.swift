import Foundation

/// The display sibling of `ChargingDiagnostic` (power) and
/// `DataLinkDiagnostic` (data speed): it answers "is my monitor getting the
/// bandwidth for its best picture, and if not, where is the limit?"
///
/// **Where the answer comes from.** macOS's own display node, read by
/// `DisplayTimingReader` and carried here as
/// `IOPortTransportStateDisplayPort.drivenTiming` (a `DisplayTimingStatement`):
/// - the driven timing's lists say whether the live mode is compressed
///   (`DSCRequiredColorElementIDs` against that timing's DSC-capable modes)
///   and which modes a converter rates over its TMDS cap
///   (`UnsafeColorElementIDs`, a receipt, never a verdict);
/// - the node's own timing for the panel's declared top mode says whether the
///   top mode is offered over this link at all, uncompressed or with DSC
///   (issue #664, ruling 37; research/displays/display-node-keys.md: a colour
///   mode macOS lists on a timing is one the link carries, P3 H1, zero
///   non-members above the link in every cell).
/// The EDID's declared top mode, costed at 8-bit RGB (`topModeBitsPerPixel`),
/// is a labelled receipt (`Facts.neededGbps`) and decides nothing. Before #664
/// it decided everything, and a fifth arithmetic branch was queued.
///
/// **Honest altitude.** The only "delivered" number is the current link state
/// (`laneCount x rate`), read as a snapshot. Whether a DisplayPort link trains
/// itself down to the selected mode is unmeasured: nothing in the research
/// library records a link retraining with a mode change, and measuring it is
/// a live experiment filed as its own question. So a top mode the node does
/// not offer might mean "the cable or adapter can't do more" OR "the user
/// hasn't selected the higher mode", and the wording keeps both.
///
/// Therefore:
/// - `.fine` is the confident verdict: macOS reports the live mode at the top
///   mode (with a statement, uncompressed).
/// - `.compressionActive` is macOS's statement that the live mode is carried
///   with DSC, never an inference from bandwidth. On an Apple display the
///   wording blames no link: Apple's displays list DSC on every timing
///   whatever the rate (45 of 46 corpus nodes).
/// - `.belowMonitorMax` is **informational, not accusatory**. When the node
///   offers the top mode it names the selected mode or this Mac and clears
///   the cable; when the node does not offer it, it states both explanations.
/// - `.adapterLimit` flags that a USB-C -> HDMI/DVI/VGA converter is in the
///   chain and the node does not offer the top mode through it.
/// - `.unknownMode` when there is nothing solid to say: no readable EDID or
///   link rate, a statement that does not name the live colour mode, a node
///   with no entry for the panel's top mode, or no statement at all. Report
///   what the link is doing, blame nothing.
///
/// The bandwidth arithmetic on the live mode survives as a labelled cross-check
/// (`Facts.liveNeededGbps`, `usableGbpsRange`, `statementContradiction`),
/// reported beside the statement and deciding nothing.
public struct DisplayDiagnostic {
    public enum Bottleneck: Hashable, Sendable {
        /// The current link already carries the monitor's top mode. No limit.
        case fine
        /// The live mode is below the panel's top mode. Two shapes: the node
        /// offers the top mode on this link (the selected mode or this Mac is
        /// holding the picture back; the cable is cleared), or it does not (a
        /// cable or adapter cap and an unselected mode cannot be told apart;
        /// the wording stays non-accusatory).
        case belowMonitorMax
        /// A USB-C -> HDMI / DVI / VGA adapter sits in the chain and the node
        /// does not offer the top mode through it, so the shortfall cannot be
        /// attributed to the cable.
        case adapterLimit
        /// Live link, but nothing trustworthy to compare it against: no
        /// readable EDID; no readable link rate; a statement whose list does
        /// not name the live colour mode (a proper subset, or a timing listing
        /// DSC-capable and non-capable modes together with the live depth and
        /// encoding unable to split them); a node with no entry for the
        /// panel's top mode; or no statement at all (the display node did not
        /// match). Report the mode and the link, assert nothing.
        case unknownMode
        /// macOS states DSC is on for the driven timing:
        /// `DSCRequiredColorElementIDs` covers the live colour mode (or every
        /// non-virtual mode). Read, never inferred (issue #664 replaced the
        /// "live mode needs more than the link carries" arithmetic, which is
        /// now the cross-check). Positive, never a warning.
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
        /// Refresh of the display's TOP MODE, as `resolveTopMode` resolved
        /// it: the highest-clock entry in the EDID's declared list, or the
        /// mode macOS reports when no declared entry matches it. **Not** the
        /// 0xFD scan-range ceiling, which is the range of signals the panel
        /// accepts rather than a mode it has (issue #596). The name is kept
        /// because the Pro Display screen and the tests read it. nil only
        /// when there is no readable EDID.
        public let maxRefreshHz: Int?
        /// Resolution of that same top mode, so a label never pairs one
        /// mode's refresh with another mode's resolution. `EDIDInfo.topMode`
        /// is max-by-pixel-clock, and a panel whose fastest timing is
        /// 1920x1080@240 while its preferred mode is 2560x1440 (Samsung
        /// Odyssey G60SD) has no 2560x1440@240 mode to label. nil exactly when
        /// `maxRefreshHz` is nil.
        public let topModeWidth: Int?
        public let topModeHeight: Int?
        /// Where that top mode came from, for the Pro receipts:
        /// `EDIDMode.sourceDescription` for a declared entry (for example
        /// "DisplayID Type I (block 3)" or "tiled composite of 2 tiles"), or
        /// "macOS only" when CoreGraphics reports a mode the EDID does not
        /// describe. nil only when there is no readable EDID.
        public let topModeSource: String?
        /// How many modes the EDID declares (`EDIDInfo.modes.count`), every
        /// format counted. nil only when there is no readable EDID.
        public let declaredModeCount: Int?
        /// How many of those declared entries the panel supports only at
        /// YCbCr 4:2:0 (CTA VICs from the Y420VDB, `ycbcr420Only`). They stay
        /// in `declaredModeCount`, the JSON and the bench report, and never
        /// become the comparison mode: a 4:2:0 mode carries half the data of
        /// the same mode in full colour, so 24 bits per pixel is not its
        /// cost; the DisplayPort link never carries 4:2:0, though a converter
        /// behind it can (`DisplayTimingLists.downstream420`). 0 when there
        /// is no readable EDID.
        public let declared420OnlyModes: Int
        /// Bandwidth the monitor's top mode would need at 8-bit RGB, usable
        /// Gbps: its declared pixel clock times `topModeBitsPerPixel`. A
        /// labelled receipt (the Pro cell K16, the text line K28): no verdict
        /// branches on it (ruling 36). nil when there is no readable EDID and
        /// when the top mode is reported by macOS only.
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
        /// mode). nil when there's no live data (tests, or no match).
        public let currentMode: DisplayCurrentMode?
        /// The display's native top mode as macOS reports it (CoreGraphics):
        /// highest resolution at its best refresh, EDID-free. The authoritative
        /// "top mode" for the capability label and the at-top-mode check. Same
        /// nil contract as `currentMode`.
        public let maxMode: DisplayCurrentMode?
        /// macOS's statement about the display, when the display node matched
        /// (`IOPortTransportStateDisplayPort.drivenTiming`): the driven
        /// timing's lists and every non-virtual timing the node lists. nil in
        /// tests and when the node did not match; then `dscReading`,
        /// `topModeMatch` and `topModeAvailability` are nil too.
        public let drivenTiming: DisplayTimingStatement?
        /// What the driven timing's lists say about the live mode, resolved
        /// against `currentMode`'s depth and encoding. nil without a statement.
        public let dscReading: DisplayTimingStatement.DSCReading?
        /// How much of the driven timing the converter sends on as 4:2:0
        /// (ruling 44): all, some or none of its non-virtual colour modes. nil
        /// without a statement. Picks between K8, K37 and K17.
        public let downstream420: DisplayTimingStatement.Downstream420Reading?
        /// `MonitorInfo.isAppleDisplay`: EDID manufacturer 0x0610, else the
        /// PNP name `APP`. Chooses the no-link-blame wording of a DSC-on verdict
        /// and nothing else: an Apple display whose driven timing lists no DSC
        /// reads by the general rule (spec Design 3 as corrected 2026-09-21).
        public let isAppleDisplay: Bool
        /// The cross-check: the live mode's pixel clock times Apple's bits per
        /// pixel at its encoding and depth, usable Gbps. nil when there is no
        /// statement, no clock, or the statement's candidate modes do not agree
        /// on one bits-per-pixel figure. Decides nothing.
        public let liveNeededGbps: Double?
        /// The usable link with and without forward error correction:
        /// `deliveredGbps x 0.9765625 ... deliveredGbps`. FEC state is not
        /// published, so it is a range. nil when the rate is unreadable.
        public let usableGbpsRange: ClosedRange<Double>?
        /// True when the statement says uncompressed and `liveNeededGbps`
        /// exceeds the top of `usableGbpsRange`, or says DSC on and it is below
        /// the bottom, except on an Apple display, whose list reads DSC on
        /// whatever the link (fix round 2, L2). Reported; the statement stands
        /// either way.
        public let statementContradiction: Bool
        /// How the panel's declared top mode sits in the node's list (ruling
        /// 37): exact, same refresh at another blanking, picture only, or not
        /// listed. nil without a statement or without a resolved top mode.
        public let topModeMatch: DisplayTimingStatement.TopModeMatchKind?
        /// The node timing the top mode matched (`exact` or `sameRefresh`),
        /// with its own lists. nil otherwise.
        public let topModeTiming: DisplayNodeTiming?
        /// What that timing says: offered (uncompressed, with DSC, or with
        /// compression not named), not offered (listed only at lower
        /// refreshes, or with no colour mode validated), or not listed. nil
        /// without a statement or a resolved top mode.
        public let topModeAvailability: TopModeAvailability?
        /// True when `topModeAvailability` is one of the offered cases: the
        /// third reason `cableAssessment` reads `.unlikelyTheCable`, and the
        /// gate that keeps `billboardNote` silent (ruling 39).
        public let statementOffersTopMode: Bool
        /// Whether the resolved top is an entry the node lists (ruling 41's
        /// step 1b chose it, or kept it for its preferred picture): true for
        /// `exact`, `sameRefresh` and `pictureOnly`, false for `notListed`
        /// (the top is a native declaration the node lists nowhere, or no
        /// declared entry qualified and the declared top stands). nil
        /// without a statement or a resolved top mode.
        public let topModeListedByNode: Bool?
        /// True when the DisplayPort node sits on the Mac's own HDMI port
        /// (`ParentPortTypeDescription == "HDMI"`, issue #352), where
        /// `sinkType` is nil by design: the SoC's HDMI transport is itself the
        /// DP-to-HDMI stage (dump A1), so the converter's unsafe list is
        /// meaningful and its receipt names the port (K39, K40) rather than
        /// an adapter (PR #665 gate rerun, note 4 ruled).
        public let isNativeHDMIPort: Bool
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

    /// Whether macOS offers the panel's declared top mode over this link, read
    /// from the node's own timing for it (ruling 37).
    public enum TopModeAvailability: String, Codable, Hashable, Sendable {
        /// Listed with a non-virtual colour mode and an empty DSC list.
        case offeredUncompressed
        /// Listed with a non-virtual colour mode and a DSC list equal to its
        /// DSC-capable set, every non-virtual mode included.
        case offeredWithDSC
        /// Listed with a non-virtual colour mode, but its lists do not say
        /// whether DSC would be used (a proper subset, or capable and
        /// non-capable modes side by side).
        case offeredUnresolved
        /// The picture is listed only at lower refreshes, or the matched
        /// timing has no colour mode validated: macOS does not offer the top
        /// mode on this link as it is now.
        case notOffered
        /// No timing has the top mode's picture.
        case notListed

        public var isOffered: Bool {
            switch self {
            case .offeredUncompressed, .offeredWithDSC, .offeredUnresolved: return true
            case .notOffered, .notListed: return false
            }
        }
    }

    public let bottleneck: Bottleneck
    public let summary: String
    public let detail: String
    public let facts: Facts
    /// The parsed EDID this diagnostic was built from, retained so the
    /// output layers (JSON, bench report) can expose the full declared mode
    /// list without re-parsing the raw bytes. nil exactly when `facts`'
    /// EDID-derived fields are nil (no readable EDID).
    public let edid: EDIDInfo?
    /// The display's top mode as `resolveTopMode` resolved it. Same value
    /// `facts.topModeWidth/Height/maxRefreshHz/topModeSource` were built
    /// from, kept whole here (with its pixel clock) for the output layers.
    /// nil exactly when `edid` is nil.
    public let topMode: TopMode?
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
    /// the monitor's best mode (`isWarning`, the same verdict that drives the
    /// inline surfaces, so there is one definition of "degraded"). A Billboard
    /// device on its own is often benign (docks park them there normally), so
    /// naming it is safe everywhere but this pointed inference is gated on the
    /// corroborating degraded link. Silent when the statement offers the top
    /// mode: a re-plug or another cable cannot improve a link macOS says
    /// already carries it (ruling 39).
    public var billboardNote: String? {
        guard billboardPresent, isWarning, !facts.statementOffersTopMode else { return nil }
        return String(localized: "A Billboard device is present on this port. That usually appears when an Alt Mode like DisplayPort was set up but didn't fully come up. Your display is below its best mode, so a re-plug, a different cable, or a different adapter may bring it up. Some docks show a Billboard device normally, so this isn't always a fault.", bundle: _coreLocalizedBundle)
    }

    /// True for the cases worth a glance in the inline verdict. `.fine` is the
    /// all-clear and `.unknownMode` is a non-event, so neither warns. Note the
    /// wording stays non-accusatory even when this is true: a warning here
    /// means "worth looking at", not "the cable is broken".
    public var isWarning: Bool {
        switch bottleneck {
        case .fine, .unknownMode, .compressionActive: return false
        case .belowMonitorMax, .adapterLimit: return true
        }
    }
}

extension DisplayDiagnostic {
    /// Bits per pixel the TOP MODE figure (`Facts.neededGbps`) is costed at:
    /// 8-bit RGB, 24. A stated basis, labelled as such wherever the figure is
    /// shown ("at 8-bit RGB"), and a receipt only: no verdict branches on it
    /// (ruling 36). The live mode is costed from macOS's own statement of its
    /// encoding and depth (`Facts.liveNeededGbps`), also a receipt; DSC and
    /// the top mode's availability are read from the node. A mode the panel
    /// supports only at 4:2:0 never reaches this constant: `resolveTopMode`
    /// skips it.
    static let topModeBitsPerPixel = 24
    /// Matching window for `resolveTopMode`'s step 4 (a CoreGraphics max
    /// mode above every declared entry): an identity test between modes, not
    /// a bandwidth comparison. `meetsTopMode` no longer uses it (PR #665 gate,
    /// Codex 1): it matches picture and refresh through `refreshMatchHz`.
    static let tolerance = 0.05
    /// Forward error correction takes 64000/65536 of the payload (the DCP
    /// firmware's `usableLinkBandwidth`, research/displays/dumps/
    /// display-node-keys-kernel-decode-2026-09-18.md A2). FEC state is not
    /// published, so the usable link is a range with and without it.
    static let fecFactor = 0.9765625

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
        // dongle in the chain. With sinkType nil here we skip the adapter
        // verdict below. Signal source: `ParentPortTypeDescription` on the DP
        // transport node, populated for every native HDMI display across
        // M1 Pro through M5 Pro in the corpus.
        let nativeHDMI = dp.parentPortTypeDescription?.uppercased() == "HDMI"
        let sinkType: String?
        if nativeHDMI {
            sinkType = nil
        } else {
            sinkType = Self.adapterSinkType(dp.dfpType)
        }
        let branchDevice = Self.branchDeviceLabel(dp.branchDeviceId)

        // Cable attribution, part one: demonstrated evidence that does not
        // need the EDID. A Thunderbolt / USB4 tunnel (the cable carries far
        // more than any DP mode needs), or every host DisplayPort lane already
        // in use on a cable we've positively identified as passive (so the
        // cable isn't lane-limiting). We require a *known* passive e-marker,
        // not merely a non-active one: an absent e-marker means an
        // unidentified cable we can't vouch for (often a cheap passive cable
        // that could itself be rate-limiting), and an active cable can
        // misreport its own e-marker (issue #111). The e-marker's claimed
        // rating is never used to exonerate. Read through the classifier, not
        // the e-marker's self-report. Part two, the statement offering the
        // top mode, needs the EDID and joins below.
        let cableKnownPassive = cable.flatMap {
            CableClassification.resolve(identity: $0, port: port)
        }?.type == .passive
        let cableUnlikelyByLink = dp.link.tunneled
            || (lanes > 0 && lanes == maxLanes && cableKnownPassive)

        // macOS's statement about the display, and the arithmetic cross-check
        // beside it. Computed once, before any verdict, so every Facts carries
        // them, the no-EDID path included. The verdict branch below also
        // needs a live mode (the reader sets both together, and every
        // statement sentence names the live mode); the facts do not.
        let statement = dp.drivenTiming
        let reading = statement?.dscReading(for: dp.currentMode)
        let downstream420 = statement?.downstream420
        let isApple = dp.monitor?.isAppleDisplay ?? false
        let liveNeeded = Self.liveNeededGbps(mode: dp.currentMode, statement: statement)
        let usable = Self.usableGbpsRange(deliveredGbps: delivered)
        let contradiction = Self.statementContradiction(reading: reading, liveNeededGbps: liveNeeded, usable: usable, isAppleDisplay: isApple)

        // No readable EDID: we can describe the link but have nothing to judge
        // it against. Report, blame nothing. An `EDIDInfo` whose `topMode` is
        // nil (an empty declared list, or every declared entry with a zero
        // dimension) has no top mode to resolve and is treated the same way.
        guard let edid, let top = Self.resolveTopMode(maxMode: dp.maxMode, edid: edid, statement: statement) else {
            self.edid = edid
            self.topMode = nil
            self.cableAssessment = cableUnlikelyByLink ? .unlikelyTheCable : .inconclusive
            self.facts = Facts(
                monitorName: nil,
                preferredWidth: nil, preferredHeight: nil, preferredRefreshHz: nil,
                maxRefreshHz: nil, topModeWidth: nil, topModeHeight: nil,
                topModeSource: nil, declaredModeCount: nil,
                declared420OnlyModes: 0,
                neededGbps: nil, deliveredGbps: delivered,
                lanes: lanes, maxLanes: maxLanes,
                rateDescription: rate, sinkType: sinkType,
                branchDevice: branchDevice,
                currentMode: dp.currentMode, maxMode: dp.maxMode,
                drivenTiming: statement, dscReading: reading, downstream420: downstream420, isAppleDisplay: isApple,
                liveNeededGbps: liveNeeded, usableGbpsRange: usable, statementContradiction: contradiction,
                topModeMatch: nil, topModeTiming: nil, topModeAvailability: nil, statementOffersTopMode: false,
                topModeListedByNode: nil,
                isNativeHDMIPort: nativeHDMI
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

        // The node's own timing for the panel's top mode (ruling 37): Core
        // decides which of the timings the reader carried is the top mode.
        // `resolveTopMode` already walked the declared list with the statement
        // (ruling 41, step 1b), so this match names how the chosen top sits in
        // the node's list and never reads `notListed` unless no declared entry
        // qualified. A top mode only CoreGraphics reports has no declared
        // clock; the match runs on picture and refresh alone then.
        let topMatch = statement?.topModeMatch(width: top.width, height: top.height, refreshHz: top.refreshHz, pixelClockHz: top.pixelClockHz, interlaced: top.interlaced)
        let availability = topMatch.map(Self.topModeAvailability)
        let statementOffersTop = availability?.isOffered == true
        // Cable attribution, part two: a link macOS lists the top mode on is
        // not a link the cable is limiting. Assigned once here so it holds on
        // every return path below.
        let cableUnlikely = cableUnlikelyByLink || statementOffersTop
        self.cableAssessment = cableUnlikely ? .unlikelyTheCable : .inconclusive

        let name = edid.monitorName ?? String(localized: "display", bundle: _coreLocalizedBundle)
        // Entries the panel supports at YCbCr 4:2:0 only. Declared facts, so
        // they stay in `edid.modes`, but never the comparison mode (see
        // `resolveTopMode`). The highest is named in the verdict so a 4K60
        // that only ever appears in the Y420VDB is not silently missing. Left
        // off when the top is macOS's own report: "a mode the EDID doesn't
        // describe" and "its EDID also lists" would contradict each other.
        // The DisplayPort link never carries 4:2:0 (research/displays/
        // display-node-keys.md, section 1), which is what the first sentence
        // claims and nothing more; behind a converter whose driven timing
        // records 4:2:0 output (`DownstreamFormat`), the second sentence says
        // what the node records and does not claim the 4:2:0-only entry is
        // the one driven (Design 6; that step is INFERRED in the findings).
        // Ruling 44: "converting the picture" (K8) only when every non-virtual
        // mode of the driven timing converts, which is also when
        // `currentMode.downstreamFormat` is set (ruling 15); when only some
        // do (every driven corpus timing with one), K37 says the timing
        // includes such a mode and that macOS does not name the live one.
        let declared420 = edid.modes.filter(Self.isYCbCr420Only)
        let note420: String
        if case .declared = top.source, let named = Self.highestPriority(declared420) {
            let namedWidth = named.width
            let namedHeight = named.height
            let namedRefresh = Int(named.refreshHz.rounded())
            switch downstream420 {
            case .everyMode?:
                note420 = " " + String(localized: "Its EDID also lists \(namedWidth) × \(namedHeight) at \(namedRefresh)Hz in 4:2:0 only. On the current timing, macOS records the adapter converting the picture to 4:2:0 on its way to the display.", bundle: _coreLocalizedBundle)
            case .someModes?:
                note420 = " " + String(localized: "Its EDID also lists \(namedWidth) × \(namedHeight) at \(namedRefresh)Hz in 4:2:0 only. The current timing includes a colour mode the adapter sends to the display as 4:2:0; macOS does not name which of the timing's modes is in use.", bundle: _coreLocalizedBundle)
            case .noMode?, nil:
                note420 = " " + String(localized: "Its EDID also lists \(namedWidth) × \(namedHeight) at \(namedRefresh)Hz in 4:2:0 only, a mode macOS does not send over the DisplayPort link.", bundle: _coreLocalizedBundle)
            }
        } else {
            note420 = ""
        }
        // The monitor's top MODE is what the node is asked about, never the
        // 0xFD range-limits envelope (issue #596). See `resolveTopMode`,
        // resolved in the guard above.
        self.edid = edid
        self.topMode = top
        // The declared pixel clock times 24 (8-bit RGB): a labelled receipt
        // (`Facts.neededGbps`, ruling 36). Nothing below branches on it. nil
        // for a top mode only macOS reports, which has no declared clock.
        let needed = top.pixelClockHz.map { Double($0) * Double(Self.topModeBitsPerPixel) / 1_000_000_000 }
        let topRefresh = Int(top.refreshHz.rounded())

        self.facts = Facts(
            monitorName: edid.monitorName,
            preferredWidth: edid.preferredWidth,
            preferredHeight: edid.preferredHeight,
            preferredRefreshHz: edid.preferredRefreshHz,
            maxRefreshHz: topRefresh,
            topModeWidth: top.width, topModeHeight: top.height,
            topModeSource: top.sourceDescription,
            declaredModeCount: edid.modes.count,
            declared420OnlyModes: declared420.count,
            neededGbps: needed,
            deliveredGbps: delivered,
            lanes: lanes, maxLanes: maxLanes,
            rateDescription: rate, sinkType: sinkType,
            branchDevice: branchDevice,
            currentMode: dp.currentMode, maxMode: dp.maxMode,
            drivenTiming: statement, dscReading: reading, downstream420: downstream420, isAppleDisplay: isApple,
            liveNeededGbps: liveNeeded, usableGbpsRange: usable, statementContradiction: contradiction,
            topModeMatch: topMatch?.kind, topModeTiming: topMatch?.timing,
            topModeAvailability: availability, statementOffersTopMode: statementOffersTop,
            topModeListedByNode: topMatch.map { $0.kind != .notListed },
            isNativeHDMIPort: nativeHDMI
        )

        // Without a delivered figure (unparseable rate string) we can't
        // describe the link. Report the monitor, blame nothing.
        guard let delivered else {
            self.bottleneck = .unknownMode
            self.summary = String(localized: "Display connected", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "Your \(name) is connected, but the link rate isn't readable, so there's nothing to compare its capability against.", bundle: _coreLocalizedBundle) + note420
            return
        }

        // Shared labels. `canDo` names the top mode in every sentence below.
        let canDo = topRefresh > 0
            ? String(localized: "up to \(topRefresh)Hz", bundle: _coreLocalizedBundle)
            : String(localized: "a higher mode than the link is carrying", bundle: _coreLocalizedBundle)
        let linkLine = String(localized: "The link is carrying about \(Self.gbps(delivered)) (\(lanes) of \(maxLanes) lanes).", bundle: _coreLocalizedBundle)

        // The node does not offer the top mode behind a converter.
        func adapterNotOffered(_ sinkType: String, extra: String) -> (String, String) {
            let summary = String(localized: "Video is going through a \(sinkType) adapter", bundle: _coreLocalizedBundle)
            let detail: String
            if let branchDevice {
                detail = String(localized: "Your \(name) is reached through a USB-C to \(sinkType) adapter that reports as \(branchDevice), and macOS does not offer the monitor's top mode (\(canDo)) on this link as it is now. With an adapter in the chain, the adapter's own limit may be the cap rather than the cable. A native DisplayPort connection, or a higher-spec adapter, would tell you which.", bundle: _coreLocalizedBundle)
            } else {
                detail = String(localized: "Your \(name) is reached through a USB-C to \(sinkType) adapter, and macOS does not offer the monitor's top mode (\(canDo)) on this link as it is now. With an adapter in the chain, the adapter's own limit may be the cap rather than the cable. Trying the monitor over native DisplayPort, or a higher-spec adapter, would tell you which.", bundle: _coreLocalizedBundle)
            }
            return (summary, detail + extra + " " + linkLine + note420)
        }

        // The node does not offer the top mode, no converter: the cable
        // attribution wording. Non-accusatory: a cable or adapter cap and an
        // unselected mode cannot be told apart from a snapshot.
        func belowMaxNotOffered(extra: String) -> (String, String) {
            let summary = String(localized: "Monitor can do more than the link is carrying", bundle: _coreLocalizedBundle)
            let detail: String
            if cableUnlikelyByLink {
                if dp.link.tunneled {
                    detail = String(localized: "macOS does not offer your \(name)'s top mode (\(canDo)) on this link as it is now. The video is tunneled over Thunderbolt or USB4, so the cable carries far more than the display needs: this is unlikely to be the cable. It's most likely the resolution or refresh rate selected in Display settings, or this Mac's limit for this display; selecting the higher mode would retrain the link and show whether it is offered.", bundle: _coreLocalizedBundle)
                } else {
                    detail = String(localized: "macOS does not offer your \(name)'s top mode (\(canDo)) on this link as it is now. The cable is already carrying every DisplayPort lane this Mac provides, so this is unlikely to be the cable. Selecting the higher mode in Display settings would retrain the link and show whether it is offered.", bundle: _coreLocalizedBundle)
                }
            } else {
                detail = String(localized: "macOS does not offer your \(name)'s top mode (\(canDo)) on this link as it is now. If you've selected the higher mode and aren't getting it, the cable or adapter is the likely limit; if you haven't tried it, selecting it would retrain the link and show whether it is offered.", bundle: _coreLocalizedBundle)
            }
            return (summary, detail + extra + " " + linkLine + note420)
        }

        // The node offers the top mode: the selected mode or this Mac is what
        // holds the picture below it, and the cable is cleared (ruling 37).
        func belowMaxOffered(_ availability: TopModeAvailability, extra: String) -> (String, String) {
            let summary = String(localized: "Monitor can do more than it is set to", bundle: _coreLocalizedBundle)
            let detail: String
            switch availability {
            case .offeredUncompressed:
                detail = String(localized: "macOS lists your \(name)'s top mode (\(canDo)) as available on this link, uncompressed. The mode selected in Display settings, or this Mac's choice for this display, is what is holding the picture below it, not the cable or adapter.", bundle: _coreLocalizedBundle)
            case .offeredWithDSC:
                detail = String(localized: "macOS lists your \(name)'s top mode (\(canDo)) as available on this link with compression (DSC). The mode selected in Display settings, or this Mac's choice for this display, is what is holding the picture below it, not the cable or adapter.", bundle: _coreLocalizedBundle)
            case .offeredUnresolved, .notOffered, .notListed:
                detail = String(localized: "macOS lists your \(name)'s top mode (\(canDo)) as available on this link. The mode selected in Display settings, or this Mac's choice for this display, is what is holding the picture below it, not the cable or adapter.", bundle: _coreLocalizedBundle)
            }
            return (summary, detail + extra + " " + linkLine + note420)
        }

        // (b), (c), (d): macOS's statement decides. The driven timing's lists
        // decide the live mode; the top mode's own node timing decides the
        // top mode. Nothing here reads `needed`.
        // `reading` and `availability` are both nil exactly when there is no
        // statement, so binding them binds the statement's presence.
        if let reading, let availability, let current = dp.currentMode {
            switch reading {
            case .dscOn:
                // (c) macOS lists DSC for the live colour mode. Read, not
                // inferred. An Apple display lists DSC on every timing whatever
                // the link (45 of 46 corpus nodes), so on one the list says
                // "DSC on" and never "the link forced it": no link blame.
                self.bottleneck = .compressionActive
                if isApple {
                    self.summary = String(localized: "Display running compressed (DSC)", bundle: _coreLocalizedBundle)
                    self.detail = String(localized: "macOS reports your \(name)'s current mode as \(current.label) with compression (DSC) on. Apple displays run compressed whenever the link supports it, so this says nothing about the link's capacity. The picture is reaching the display, so this is working as intended.", bundle: _coreLocalizedBundle) + note420
                } else {
                    self.summary = String(localized: "Display running compressed (DSC) to fit through the link", bundle: _coreLocalizedBundle)
                    self.detail = String(localized: "macOS reports your \(name)'s current mode as \(current.label) and states that this link needs compression (DSC) to carry it. High-resolution displays use DSC to fit a mode like this through a link like this. The picture is reaching the display, so this is working as intended.", bundle: _coreLocalizedBundle) + note420
                }
                return
            case .unresolved:
                // (d) The list is a shape the corpus has never seen, the lists
                // were unreadable, or the timing lists DSC-capable and
                // non-capable modes together and nothing names the live one.
                self.bottleneck = .unknownMode
                self.summary = String(localized: "Display connected", bundle: _coreLocalizedBundle)
                self.detail = String(localized: "macOS reports your \(name)'s current mode as \(current.label) but does not name the colour format in use, so whether the link is compressing it can't be read from here.", bundle: _coreLocalizedBundle)
                    + " " + linkLine + note420
                return
            case .uncompressed:
                // (b) No mode on the driven timing needs DSC on this link, or
                // the live mode resolves to one that cannot use it: the link
                // carries the live mode uncompressed. At the top mode that is
                // the whole answer; below it, the node's own timing for the
                // top mode says whether the top is offered (ruling 37).
                let uncompressedNote = " " + String(localized: "macOS states the current mode, \(current.label), is running uncompressed.", bundle: _coreLocalizedBundle)
                if Self.meetsTopMode(current, top: top) {
                    self.bottleneck = .fine
                    self.summary = String(localized: "Display running at full quality", bundle: _coreLocalizedBundle)
                    self.detail = String(localized: "macOS reports your \(name) at its top mode (\(current.label)) and states it is running uncompressed. The link is carrying it in full; nothing is holding the picture back.", bundle: _coreLocalizedBundle) + note420
                    return
                }
                switch availability {
                case .offeredUncompressed, .offeredWithDSC, .offeredUnresolved:
                    self.bottleneck = .belowMonitorMax
                    let verdict = belowMaxOffered(availability, extra: uncompressedNote)
                    self.summary = verdict.0
                    self.detail = verdict.1
                    return
                case .notOffered:
                    if let sinkType {
                        self.bottleneck = .adapterLimit
                        let verdict = adapterNotOffered(sinkType, extra: uncompressedNote)
                        self.summary = verdict.0
                        self.detail = verdict.1
                        return
                    }
                    self.bottleneck = .belowMonitorMax
                    let verdict = belowMaxNotOffered(extra: uncompressedNote)
                    self.summary = verdict.0
                    self.detail = verdict.1
                    return
                case .notListed:
                    self.bottleneck = .unknownMode
                    self.summary = String(localized: "Display connected", bundle: _coreLocalizedBundle)
                    self.detail = String(localized: "macOS's list of modes for your \(name) has no entry matching its top mode (\(canDo)), so whether this link could carry it can't be read from here.", bundle: _coreLocalizedBundle)
                        + uncompressedNote + " " + linkLine + note420
                    return
                }
            }
        }

        // (e) No statement: the display node did not match this display, or
        // there is no live mode. A live mode CoreGraphics reports at the top
        // mode is the picture on screen at the top mode, whatever the link
        // rate says; hedged, because without the statement nothing can say
        // whether DSC carries it. Anything else is unknown: the top mode's
        // availability is the node's to state, and the node is not here.
        if let current = dp.currentMode, Self.meetsTopMode(current, top: top) {
            self.bottleneck = .fine
            self.summary = String(localized: "Display running at full quality", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "macOS reports your \(name) at its top mode (\(current.label)), and the link is carrying it. Many high-resolution displays use compression (DSC) to fit a mode like this through the link, so the link rate alone can't show it; your display is at full quality.", bundle: _coreLocalizedBundle) + note420
            return
        }
        self.bottleneck = .unknownMode
        self.summary = String(localized: "Display connected", bundle: _coreLocalizedBundle)
        self.detail = String(localized: "macOS's display node could not be matched to your \(name), so whether this link could carry its top mode (\(canDo)) can't be read from here. If the picture looks right, it most likely is.", bundle: _coreLocalizedBundle)
            + " " + linkLine + note420
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

    /// The cross-check's "needed": the live mode's pixel clock (the driven
    /// timing's, blanking included) times Apple's bits per pixel for its
    /// encoding and depth, as the statement's candidate modes determine it.
    /// nil without a statement, without a clock, or when the candidates do
    /// not agree on one figure (RGB beside 4:2:2). Reported, never decisive.
    static func liveNeededGbps(mode: DisplayCurrentMode?, statement: DisplayTimingStatement?) -> Double? {
        guard let mode, let clock = mode.pixelClockHz, let statement,
              let bitsPerPixel = statement.liveBitsPerPixel(for: mode) else { return nil }
        return Double(clock) * bitsPerPixel / 1_000_000_000
    }

    /// The usable link as a range: the delivered figure (lanes x rate x line
    /// coding) with forward error correction (x 0.9765625) at the bottom and
    /// without it at the top. FEC state is not published.
    static func usableGbpsRange(deliveredGbps: Double?) -> ClosedRange<Double>? {
        guard let deliveredGbps, deliveredGbps > 0 else { return nil }
        return (deliveredGbps * Self.fecFactor)...deliveredGbps
    }

    /// True when the arithmetic disagrees with the statement: uncompressed
    /// but the live mode needs more than the link can carry even without FEC,
    /// or DSC on but the live mode fits even with FEC. Reported beside the
    /// statement; the statement is what decides.
    ///
    /// On an Apple display reading DSC on, a live need under the floor is
    /// the expected state and not a contradiction: Apple's displays list DSC
    /// on every timing whatever the link (the Apple clause: the list is not
    /// a link statement), so the arithmetic has nothing to disagree with
    /// (PR #665 gate fix round 2, L2). The K14 line that prompted it was seen
    /// on a Studio Display (M5, macOS 26.6, 4 lanes HBR3) in the live check
    /// run at 65a6a5fa, a build whose NSScreen fallback narrowed the two-depth
    /// timing to 8 bits; at HEAD that timing yields no cross-check figure at
    /// all, so on every corpus Apple shape the exemption has nothing to fire
    /// on and it decides only the single-depth Apple case. Unchanged
    /// everywhere else: on a non-Apple display DSC on under the floor is
    /// informative and stays.
    static func statementContradiction(reading: DisplayTimingStatement.DSCReading?, liveNeededGbps: Double?, usable: ClosedRange<Double>?, isAppleDisplay: Bool) -> Bool {
        guard let reading, let liveNeededGbps, let usable else { return false }
        switch reading {
        case .uncompressed: return liveNeededGbps > usable.upperBound
        case .dscOn: return !isAppleDisplay && liveNeededGbps < usable.lowerBound
        case .unresolved: return false
        }
    }

    /// What the node's timing for the top mode says (ruling 37). A matched
    /// timing with no non-virtual colour mode is a listing macOS validated no
    /// format for: not an offer. The matched timing's own lists, read with no
    /// live mode (every non-virtual mode a candidate), say whether the top
    /// mode would run uncompressed or with DSC.
    static func topModeAvailability(_ match: DisplayTimingStatement.TopModeMatch) -> TopModeAvailability {
        switch match {
        case .exact(let timing), .sameRefresh(let timing):
            guard timing.lists.hasNonVirtualColourMode else { return .notOffered }
            switch timing.lists.dscReading(for: nil) {
            case .uncompressed: return .offeredUncompressed
            case .dscOn: return .offeredWithDSC
            case .unresolved: return .offeredUnresolved
            }
        case .pictureOnly: return .notOffered
        case .notListed: return .notListed
        }
    }

    // MARK: - Top mode

    /// True for an entry the panel supports only at YCbCr 4:2:0: a CTA VIC
    /// from the Y420VDB. A declared fact about the panel, never the
    /// comparison mode: a 4:2:0 mode carries half the data of the same mode
    /// in full colour, so 24 bits per pixel is not its cost, and the
    /// DisplayPort link never carries 4:2:0 (a converter behind it can:
    /// `DisplayTimingLists.downstream420`).
    static func isYCbCr420Only(_ mode: EDIDMode) -> Bool {
        if case .ctaVIC(_, _, _, true) = mode.source { return true }
        return false
    }

    /// The highest-priority entry of `modes` by `EDIDInfo`'s own tie-break
    /// chain (pixel clock, area, refresh, then list order), admitting the
    /// same candidates `EDIDInfo.topMode` admits: every dimension above zero.
    /// nil when nothing qualifies.
    static func highestPriority(_ modes: [EDIDMode]) -> EDIDMode? {
        var best: EDIDMode? = nil
        for candidate in modes {
            guard candidate.width > 0, candidate.height > 0, candidate.hTotal > 0, candidate.vTotal > 0 else { continue }
            guard let current = best else { best = candidate; continue }
            if EDIDInfo.isHigherPriority(candidate, than: current) { best = candidate }
        }
        return best
    }

    /// Where the display's top mode came from.
    public enum TopModeSource: Hashable, Sendable {
        /// The mode is in the EDID's declared list; carries which entry.
        case declared(EDIDMode.Source)
        /// macOS reports a mode (its max mode) that no declared entry matches and no tiled composite explains.
        case reportedByMacOSOnly
    }

    /// The display's top mode as the diagnostic resolved it: the mode the
    /// link is judged against. Built by `resolveTopMode` and nowhere else.
    public struct TopMode: Hashable, Sendable {
        public let width: Int
        public let height: Int
        public let refreshHz: Double
        /// nil exactly when `source == .reportedByMacOSOnly`: the mode exists (macOS lists it) but its
        /// pixel clock is not in the EDID, so nothing here can name the bandwidth it needs.
        public let pixelClockHz: Int?
        /// Carried from the declared entry. For an interlaced entry
        /// `refreshHz` is the field rate and each field carries half the
        /// lines, so `activePixelRate` halves, the same as
        /// `EDIDMode.activePixelRate`. Always false for `.reportedByMacOSOnly`:
        /// CoreGraphics modes carry no interlace flag.
        public let interlaced: Bool
        public let source: TopModeSource
        /// Active pixels per second, the domain CoreGraphics reports in:
        /// `width * height * refreshHz`, halved when interlaced.
        public var activePixelRate: Double { Double(width) * Double(height) * refreshHz / (interlaced ? 2 : 1) }

        public init(width: Int, height: Int, refreshHz: Double, pixelClockHz: Int?, interlaced: Bool, source: TopModeSource) {
            self.width = width
            self.height = height
            self.refreshHz = refreshHz
            self.pixelClockHz = pixelClockHz
            self.interlaced = interlaced
            self.source = source
        }

        /// A declared entry carried whole: its own width, height, refresh,
        /// pixel clock and interlace flag, so `activePixelRate` equals
        /// `mode.activePixelRate` by construction.
        init(declared mode: EDIDMode) {
            self.init(
                width: mode.width, height: mode.height, refreshHz: mode.refreshHz,
                pixelClockHz: mode.pixelClockHz, interlaced: mode.interlaced, source: .declared(mode.source)
            )
        }

        /// `Facts.topModeSource`: the declared entry's own label, or
        /// "macOS only".
        public var sourceDescription: String {
            switch source {
            case .declared(let entry): return entry.description
            case .reportedByMacOSOnly: return "macOS only"
            }
        }
    }

    /// CoreGraphics rounds a mode's refresh to a whole number of hertz; the
    /// EDID does not (59.94, 143.98). A declared entry within this much of the
    /// reported refresh, at the same resolution, is the same mode. A matching
    /// window, not a derivation: nothing is computed from it.
    static let refreshMatchHz = 0.5

    /// The display's top mode: the mode the link is judged against. Nil when
    /// no full-colour entry has every dimension above zero: an empty declared
    /// list, a parsed EDID whose every entry has a zero dimension, or one
    /// whose only usable entries are 4:2:0-only. Then there is nothing to
    /// judge against, and the diagnostic's init treats it like no EDID.
    ///
    /// Five steps, in order, and no other branch:
    /// 1. The declared full-colour candidates, ranked by `EDIDInfo.topMode`'s
    ///    own chain (pixel clock, area, refresh, list order) over the same
    ///    list minus the `ycbcr420Only` entries (`isYCbCr420Only`).
    ///    `preferredMode` plays no part in the ranking: it is the EDID's
    ///    stated default, not its top, and may be absent.
    /// 1b. With a statement (the display node matched, ruling 41): the top
    ///    is the highest-ranked candidate that `nodeLists` vouches for, which
    ///    is one the node lists at its refresh, or one the node lists only
    ///    at other refreshes or nowhere at all when it is the panel's own
    ///    native declaration (its picture is the EDID's preferred picture,
    ///    or its source is the tiled composite or a DisplayID timing other
    ///    than the four code-list types), or, listed at other refreshes, when
    ///    the EDID names no preferred mode. Anything else the node does not
    ///    list at its refresh is a scaler-accepted entry macOS has already
    ///    declined (a 1600x1200 DMT on a 1080p panel, a 4K VIC on a 1440p or
    ///    5120x1440 one) and is skipped, so an unlisted native picture reads
    ///    as not listed rather than falling through to a compatibility mode;
    ///    when no candidate qualifies the declared top stands and reads the
    ///    same way, and without a statement this step does nothing.
    /// 2. No max mode from CoreGraphics, or one with no readable refresh:
    ///    that candidate.
    /// 3. The max mode matches a declared entry (`declaredMode(matching:in:)`):
    ///    that entry when its pixel clock is at least the candidate's, so a
    ///    max mode that IS a declared entry is labelled from that entry;
    ///    otherwise the candidate. A max mode may only raise the top, never
    ///    lower it: CoreGraphics builds its mode list from what the trained
    ///    link can carry (`planning/display-current-mode-coregraphics.md`),
    ///    so a lower max mode describes the link, not the panel.
    /// 4. No declared entry matches: when the max mode's active-pixel rate
    ///    sits above the candidate's by more than `tolerance`, macOS is
    ///    reporting a mode the EDID does not describe, returned as
    ///    `.reportedByMacOSOnly` with no pixel clock; otherwise the candidate.
    ///
    /// Nothing here derives a pixel clock: every clock returned is an
    /// `EDIDMode.pixelClockHz` read from the EDID, or nil. The 0xFD
    /// range-limits envelope is never consulted, on a continuous-frequency
    /// panel or any other: it is the range of signals the panel accepts, not
    /// a mode it has (issue #596).
    static func resolveTopMode(maxMode: DisplayCurrentMode?, edid: EDIDInfo, statement: DisplayTimingStatement? = nil) -> TopMode? {
        // 1. The declared full-colour candidates. Nil when none qualifies (see
        //    above). A 4:2:0-only entry is skipped here and in step 3 both:
        //    it is a fact about the panel, not a mode macOS drives.
        var candidates = edid.modes.filter { !Self.isYCbCr420Only($0) }
        guard let declaredTop = Self.highestPriority(candidates) else { return nil }
        // 1b. With the node's list, the highest-ranked candidate it lists.
        var panelTop = declaredTop
        if let statement {
            let preferredPicture = edid.preferredMode.map { (width: $0.width, height: $0.height) }
            while let best = Self.highestPriority(candidates) {
                if Self.nodeLists(best, in: statement, preferredPicture: preferredPicture) {
                    panelTop = best
                    break
                }
                candidates.removeAll { $0 == best }
            }
        }
        // 2. Nothing from CoreGraphics to weigh against the list.
        guard let maxMode, maxMode.refreshHz > 0 else { return TopMode(declared: panelTop) }
        // 3. The max mode is a declared entry: label it from that entry, but
        //    never let it lower the top.
        if let matched = Self.declaredMode(matching: maxMode, in: edid) {
            if matched.pixelClockHz >= panelTop.pixelClockHz { return TopMode(declared: matched) }
            return TopMode(declared: panelTop)
        }
        // 4. Not declared anywhere: above the list it is macOS's fact alone,
        //    with no clock to read; at or below it the declared top stands.
        //    `panelTop.activePixelRate` halves for an interlaced entry, the
        //    same figure `TopMode(declared:)` would carry.
        if maxMode.pixelThroughput > panelTop.activePixelRate * (1 + Self.tolerance) {
            return TopMode(
                width: maxMode.width, height: maxMode.height, refreshHz: maxMode.refreshHz,
                pixelClockHz: nil, interlaced: false, source: .reportedByMacOSOnly
            )
        }
        return TopMode(declared: panelTop)
    }

    /// Ruling 41's predicate as implemented: whether the node's list vouches
    /// for a declared candidate as a mode this panel can be driven at on this
    /// Mac. Listed at its refresh (`exact`, `sameRefresh`): yes, whether or
    /// not the listing carries a colour mode. Listed only at other refreshes:
    /// yes when the candidate is the panel's own native declaration and the
    /// link is limiting it, which is any of: its picture is the EDID's
    /// preferred picture (a base-block-DTD-native panel), or its source is
    /// the tiled composite (the Studio Display's 5K, derived from the tile
    /// and the topology), or a DisplayID timing (Type I to X less the
    /// code-list types, in a DisplayID block or embedded in CTA: how the Pro
    /// Display XDR, the PA32QCV and every 5K, 6K and 5120x1440 panel declare
    /// a native mode an EDID 1.4 base-block DTD cannot hold), or the EDID
    /// names no preferred mode; no otherwise (a scaler-accepted DMT or VIC).
    /// Listed nowhere at all: yes for those same native declarations (the
    /// preferred picture, the tiled composite, a DisplayID timing), because a
    /// scaler entry never carries those sources and an unlisted native
    /// picture must not fall through to a compatibility mode reading "full
    /// quality"; the diagnostic then reads the top as not listed (K26,
    /// unknown). No for anything else, listed nowhere and not a native
    /// declaration: a scaler-accepted entry. The four DisplayID code-list
    /// types (Type IV, tag 0x06, and Type VIII, tag 0x23, DMT and enumerated
    /// code lists; the 0x07 DMT and 0x08 VIC bitmaps), all decoded by the
    /// same code-list decoder, are lists of codes the panel accepts, not
    /// timings it declares, so they never count as native (0 corpus
    /// candidates of any of the four; PR #665 gate fix round 4, item 1).
    /// (PR #665 gate rerun, Claude F1: the preferred-picture clause alone
    /// keyed on a lower compatibility DTD on 38 of 231 corpus nodes, so a
    /// link-limited Studio Display read "not the cable" and a link-limited
    /// PA32QCV read full quality at 30 Hz.) A "largest picture by area the
    /// node lists" rule was tried and withdrawn: on every 32:9 panel a 4K
    /// scaler VIC out-areas the 5120x1440 native picture, and it moved the
    /// LS49AG95 (`m4_macos26.5.2_b`, driven at its native mode) to a
    /// "not offered" 4K120 top.
    ///
    /// Ruling 41's recorded text says "exact or sameRefresh with a colour
    /// mode". The implemented predicate deliberately counts a listing with no
    /// colour mode as listed (a planner's deviation, recorded in the task
    /// ledger and confirmed at the PR #665 gate, Claude F2): the resolver's
    /// job is to skip entries macOS never lists at all (scaler-accepted DMTs
    /// and VICs); a listing with no format validated is the node saying it
    /// knows the mode and offers no format for it on this link, which reads
    /// not offered downstream (`topModeAvailability`), the link's fact and not
    /// the resolver's to hide by moving the top to a lower entry. Measured on
    /// the corpus (plan, figures table, 2026-09-21): the coordinator's simpler
    /// criterion, exact or same-refresh with colour modes only, made every
    /// link-limited "not offered" verdict vanish (228 of 231 paired nodes at
    /// the top), which is why the preferred-picture clause is here; 0 of 231
    /// nodes list a declared top with no colour mode and no colour twin.
    static func nodeLists(_ candidate: EDIDMode, in statement: DisplayTimingStatement, preferredPicture: (width: Int, height: Int)?) -> Bool {
        switch statement.topModeMatch(width: candidate.width, height: candidate.height, refreshHz: candidate.refreshHz, pixelClockHz: candidate.pixelClockHz, interlaced: candidate.interlaced) {
        case .exact, .sameRefresh:
            return true
        case .pictureOnly:
            if Self.isNativeDeclaration(candidate) { return true }
            guard let preferredPicture else { return true }
            return preferredPicture.width == candidate.width && preferredPicture.height == candidate.height
        case .notListed:
            // A native declaration the node lists nowhere is still the top:
            // the diagnostic reads it as not listed (K26) rather than judging
            // a compatibility mode as full quality (fix round 4, item 2).
            if Self.isNativeDeclaration(candidate) { return true }
            guard let preferredPicture else { return false }
            return preferredPicture.width == candidate.width && preferredPicture.height == candidate.height
        }
    }

    /// Whether a declared entry is the panel's own statement of a native
    /// mode rather than a code it accepts: the tiled composite, or a DisplayID
    /// timing of any type but the four code-list types (see `nodeLists`).
    static func isNativeDeclaration(_ mode: EDIDMode) -> Bool {
        switch mode.source {
        case .tiledComposite:
            return true
        case .displayID(_, let type, _, _):
            switch type {
            case .vesaDMTBitmap, .ctaVICBitmap, .typeIV, .typeVIII: return false
            default: return true
            }
        default:
            return false
        }
    }

    /// The declared entry a CoreGraphics mode is: same width and height,
    /// refresh within `refreshMatchHz`, and the highest pixel clock among the
    /// entries that match. nil when no entry matches. Interlace is not part
    /// of the match: a CoreGraphics `DisplayCurrentMode` carries no interlace
    /// flag, so there is nothing on that side to compare it with. A
    /// 4:2:0-only entry never matches: a max mode that only the Y420VDB
    /// describes falls through to step 4 and is reported as macOS's fact,
    /// with no clock to cost it.
    static func declaredMode(matching mode: DisplayCurrentMode, in edid: EDIDInfo) -> EDIDMode? {
        var best: EDIDMode? = nil
        for entry in edid.modes {
            guard !Self.isYCbCr420Only(entry),
                  entry.width == mode.width, entry.height == mode.height,
                  abs(entry.refreshHz - mode.refreshHz) <= Self.refreshMatchHz
            else { continue }
            if let current = best, current.pixelClockHz >= entry.pixelClockHz { continue }
            best = entry
        }
        return best
    }

    /// Whether the live mode is the top mode: the same picture (width and
    /// height), and the same refresh within `refreshMatchHz` (CoreGraphics
    /// rounds to whole hertz) or at the CTA alternate rate (top / 1.001
    /// within `DisplayTimingStatement.exactRefreshHz`, the node's own rule).
    /// An identity test, not a throughput one: 1920x1080 at 240 Hz carries
    /// the same active pixels per second as 3840x2160 at 60 Hz and is a
    /// quarter of the picture (PR #665 gate, Codex 1). A top mode with no
    /// readable refresh meets nothing.
    ///
    /// The driven timing's `pixelClockHz`, when present, is deliberately not
    /// compared here: 17 corpus panels driven at their top picture and
    /// refresh sit on a lower-clock declared timing of the same mode (the
    /// 533.25 MHz 4K60 DTD where the top entry is VIC 97 at 594 MHz), and a
    /// clock identity test would call them short of the top. Bandwidth
    /// questions use the clock in `liveNeededGbps` (a receipt); this is an
    /// identity question (ruling 36).
    static func meetsTopMode(_ current: DisplayCurrentMode, top: TopMode) -> Bool {
        guard top.refreshHz > 0, current.width == top.width, current.height == top.height else { return false }
        return abs(current.refreshHz - top.refreshHz) <= Self.refreshMatchHz
            || abs(current.refreshHz - top.refreshHz / 1.001) <= DisplayTimingStatement.exactRefreshHz
    }

    // MARK: - Link-rate labelling (shared by every Pro UI surface)

    /// Confirmed numeric `linkRate` fallback, used only when macOS's own
    /// `linkRateDescription` string isn't available. Sourced from a sweep of
    /// the probe-33 (`displayport_capability`) customer submissions. As of the
    /// 2026-07-22 batch the only codes ever observed are 0 ("No Link"),
    /// 1 ("1.62 Gbps (RBR)"), 2 ("2.7 Gbps (HBR)"), 3 ("5.4 Gbps (HBR2)"), and
    /// 4 ("8.1 Gbps (HBR3)"). Code 1 (RBR) is now corpus-confirmed: it first
    /// appeared in that batch on an M2 Max driving an HP E271i over USB-C,
    /// which macOS itself labelled "1.62 Gbps (RBR)". The kernel's own table
    /// (IODisplayPortFamily transport state, build 25G83, read 2026-09-16)
    /// continues 5 "10 Gbps (UHBR10)", 6 "13.5 Gbps (UHBR13.5)",
    /// 7 "20 Gbps (UHBR20)"; none has appeared in the corpus, so they are
    /// left out here until one does. See
    /// research/classes/_meaning/IOPortTransportStateDisplayPort.md.
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

extension DisplayDiagnostic {
    /// Localised receipt lines for macOS's statement and the arithmetic
    /// beside it, shared by the CLI text output and the Pro Display screen so
    /// both say the same words. Empty when the display node did not match (no
    /// statement). Order: what macOS states about the live mode (K9), the
    /// cross-check (K13, K14), the top-mode figure at 8-bit RGB (K28, the
    /// receipt ruling 36 keeps; the Pro screen shows it as cells and passes
    /// `includeTopModeFigure: false`), the node's answer for the top mode
    /// (K29), the cable cleared by the statement (K35), and the converter's
    /// unsafe rating (K15: ruling 1's fact, never a verdict; it names the
    /// count of non-virtual modes rated unsafe over the non-virtual total,
    /// the same resolution as `DisplayTimingLists.unsafeIDs`, not the modes
    /// or their downstream format, which are in the JSON `drivenTiming`
    /// block beside the raw lists, because which mode is live is not on the
    /// node). No receipt line names IDs.
    public func statementReceipts(includeTopModeFigure: Bool = true) -> [String] {
        guard let reading = facts.dscReading else { return [] }
        var lines: [String] = []
        lines.append(String(localized: "macOS states: \(Self.readingLabel(reading))", bundle: _coreLocalizedBundle))
        if let need = facts.liveNeededGbps, let usable = facts.usableGbpsRange {
            lines.append(String(localized: "Live mode needs about \(Self.gbps(need)); the link's usable rate is \(Self.gbps(usable.lowerBound)) to \(Self.gbps(usable.upperBound)).", bundle: _coreLocalizedBundle))
        }
        if facts.statementContradiction {
            lines.append(String(localized: "The bandwidth arithmetic disagrees with macOS's statement for this mode. The statement is what is shown.", bundle: _coreLocalizedBundle))
        }
        if includeTopModeFigure, let needed = facts.neededGbps, let delivered = facts.deliveredGbps {
            lines.append(String(localized: "Top mode needs about \(Self.gbps(needed)) at 8-bit RGB; the link carries about \(Self.gbps(delivered)).", bundle: _coreLocalizedBundle))
        }
        if let availability = facts.topModeAvailability {
            lines.append(String(localized: "Top mode on this link: \(Self.availabilityLabel(availability))", bundle: _coreLocalizedBundle))
        }
        if facts.statementOffersTopMode {
            lines.append(String(localized: "The cable is not the limit: macOS lists the top mode on this link.", bundle: _coreLocalizedBundle))
        }
        // The converter's unsafe rating (Design 5): the count when the list
        // read, K38 when it did not (ruling 42). On the Mac's own HDMI port
        // the SoC's transport is the DP-to-HDMI stage (dump A1), so the same
        // two lines name the port instead of an adapter (K39, K40; PR #665
        // gate rerun, note 4 ruled). Never on native DisplayPort, and never
        // a verdict.
        if let statement = facts.drivenTiming {
            if let sinkType = facts.sinkType {
                if !statement.unsafeListComplete {
                    lines.append(String(localized: "macOS's list of colour modes above the \(sinkType) adapter's TMDS rate limit could not be read for this timing.", bundle: _coreLocalizedBundle))
                } else if !statement.unsafeIDs.isEmpty {
                    let flagged = statement.unsafeIDs.count
                    let total = statement.nonVirtualIDs.count
                    lines.append(String(localized: "macOS rates \(flagged) of \(total) colour modes on this timing as above the \(sinkType) adapter's TMDS rate limit.", bundle: _coreLocalizedBundle))
                }
            } else if facts.isNativeHDMIPort {
                if !statement.unsafeListComplete {
                    lines.append(String(localized: "macOS's list of colour modes above the HDMI port's TMDS rate limit could not be read for this timing.", bundle: _coreLocalizedBundle))
                } else if !statement.unsafeIDs.isEmpty {
                    let flagged = statement.unsafeIDs.count
                    let total = statement.nonVirtualIDs.count
                    lines.append(String(localized: "macOS rates \(flagged) of \(total) colour modes on this timing as above the HDMI port's TMDS rate limit.", bundle: _coreLocalizedBundle))
                }
            }
        }
        return lines
    }

    /// The statement's reading as a receipt value.
    static func readingLabel(_ reading: DisplayTimingStatement.DSCReading) -> String {
        switch reading {
        case .dscOn: return String(localized: "DSC on", bundle: _coreLocalizedBundle)
        case .uncompressed: return String(localized: "Uncompressed", bundle: _coreLocalizedBundle)
        case .unresolved: return String(localized: "Not named", bundle: _coreLocalizedBundle)
        }
    }

    /// The node's answer for the top mode as a receipt value.
    static func availabilityLabel(_ availability: TopModeAvailability) -> String {
        switch availability {
        case .offeredUncompressed: return String(localized: "available, uncompressed", bundle: _coreLocalizedBundle)
        case .offeredWithDSC: return String(localized: "available, with DSC", bundle: _coreLocalizedBundle)
        case .offeredUnresolved: return String(localized: "available", bundle: _coreLocalizedBundle)
        case .notOffered: return String(localized: "not offered", bundle: _coreLocalizedBundle)
        case .notListed: return String(localized: "no matching entry", bundle: _coreLocalizedBundle)
        }
    }
}
