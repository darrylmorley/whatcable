import Foundation

/// The format a DP-to-HDMI (or DVI) converter emits towards the panel for one
/// colour mode: the node's `DownstreamFormat` sub-dictionary, its
/// `PixelEncoding` and `Depth`. Present on 333 tree-rendered corpus colour
/// modes across 31 nodes, every one encoding 1 (YCbCr 4:2:0) and every paired
/// one behind a converter; the DisplayPort link itself never carries 4:2:0
/// (research/displays/display-node-keys.md, section 1).
public struct DisplayDownstreamFormat: Codable, Hashable, Sendable {
    public let encoding: DisplayPixelEncoding
    public let depth: Int

    public init(encoding: DisplayPixelEncoding, depth: Int) {
        self.encoding = encoding
        self.depth = depth
    }
}

/// One entry of a timing's `ColorModes`, as the display node publishes it.
public struct DisplayColourMode: Codable, Hashable, Sendable {
    public let id: Int
    /// The format on the DisplayPort link.
    public let encoding: DisplayPixelEncoding
    public let depth: Int
    /// The raw `SupportsDSC` byte: 0, 1 or 3. Bit 0: the sink's DSC capability
    /// covers this depth and encoding; bit 1: a branch device's pass-through
    /// capability does (dump A3). A mode with 0 is never in the DSC-required
    /// list (0 of 39871 pairs, section 5).
    public let supportsDSC: Int
    /// Synthetic HDR entries macOS adds beside the panel's own; never a depth
    /// the link runs at.
    public let isVirtual: Bool
    /// The converter's output format for this mode, when the node records one.
    public let downstreamFormat: DisplayDownstreamFormat?

    public var isDSCCapable: Bool { supportsDSC != 0 }

    public init(id: Int, encoding: DisplayPixelEncoding, depth: Int, supportsDSC: Int, isVirtual: Bool, downstreamFormat: DisplayDownstreamFormat?) {
        self.id = id
        self.encoding = encoding
        self.depth = depth
        self.supportsDSC = supportsDSC
        self.isVirtual = isVirtual
        self.downstreamFormat = downstreamFormat
    }
}

/// One timing's lists, resolved against that timing's non-virtual colour
/// modes: the per-timing part of macOS's statement, shared by the driven
/// timing and by the node timing the panel's top mode matches.
///
/// The three sets (`dscCapableIDs`, `dscRequiredIDs`, `unsafeIDs`) are the
/// node's two ID lists and its `SupportsDSC` bytes, each **resolved against
/// the non-virtual colour modes**: an ID the node lists for a virtual entry
/// (the Studio Display's `DSCRequiredColorElementIDs` prints (1, 46, 48) and
/// mode 1 is virtual, so the resolved set is {46, 48}) is dropped from the
/// set and stays visible in `colourModes` and in the raw lists
/// (`dscRequiredIDsRaw`, `unsafeIDsRaw`), which carry the two ID lists
/// exactly as the node printed them. An ID no colour mode carries at all
/// clears the list's completeness flag (PR #665 gate, Codex 2). Membership in
/// `DSCRequiredColorElementIDs` is what the producer means by "requires DSC"
/// (dump Finding 5 and A1); the corpus has seen the list either empty or
/// exactly the DSC-capable set, never a proper subset (P3 `dsc-shape`,
/// 2026-09-18, 1408 folders).
public struct DisplayTimingLists: Codable, Hashable, Sendable {
    /// Every `ColorModes` entry that parsed, virtual ones included.
    public let colourModes: [DisplayColourMode]
    /// Non-virtual modes with `SupportsDSC` not zero.
    public let dscCapableIDs: Set<Int>
    /// `DSCRequiredColorElementIDs`, resolved against the non-virtual modes.
    public let dscRequiredIDs: Set<Int>
    /// `UnsafeColorElementIDs`, resolved against the non-virtual modes. Empty
    /// on native DisplayPort (0 of 35535 pairs); behind an HDMI, DVI or VGA
    /// converter it is the converter's TMDS cap as macOS rates it, a fact and
    /// never a verdict.
    public let unsafeIDs: Set<Int>
    /// `DSCRequiredColorElementIDs` as the node printed it, in the node's
    /// order, virtual and unknown IDs included: what a reader of the JSON
    /// sees beside the resolved set (PR #665 gate fix round 2, L1).
    public let dscRequiredIDsRaw: [Int]
    /// `UnsafeColorElementIDs` on the same terms.
    public let unsafeIDsRaw: [Int]
    /// The timing's `ValidPixelEncodings` bitmask (`1 << encoding` per allowed
    /// encoding; 0xffffffff on a virtual timing). nil when unreadable.
    public let validPixelEncodings: UInt32?
    /// Whether each list was complete (spec Design 2; ruling 42). A live read
    /// is never sampled, so a clear flag is the malformed-node case.
    /// `ColorModes` present, an array, and every entry parsed (a
    /// `DownstreamFormat` that is present but unreadable included) with a
    /// `SupportsDSC` inside the two-bit field the dump names (0 to 3; PR #665
    /// gate, Codex 2); an absent key or any other type clears it (ruling
    /// 43). With it clear the table cannot say what the live mode is, and
    /// `dscReading` is `.unresolved`.
    public let colourModesComplete: Bool
    /// `DSCRequiredColorElementIDs` present, an array, every entry a number,
    /// and every ID one of the colour modes (virtual ones included): an ID
    /// the table does not carry is a shape the firmware never publishes (0 of
    /// 4101 unsampled corpus timings), and intersecting it away would let
    /// `[46, 999]` read as the capable set and `[999]` as empty (PR #665
    /// gate, Codex 2). With it clear `dscReading` is `.unresolved`: an
    /// unreadable list is not an empty one.
    public let dscListComplete: Bool
    /// `UnsafeColorElementIDs`, same contract. A converter receipt (Design 5):
    /// with it clear the receipt reads "could not be read" (K38) and nothing
    /// else changes; it never touches the DSC reading.
    public let unsafeListComplete: Bool

    public init(colourModes: [DisplayColourMode], dscRequiredList: [Int], unsafeList: [Int], validPixelEncodings: UInt32?,
                colourModesComplete: Bool, dscListComplete: Bool, unsafeListComplete: Bool) {
        self.colourModes = colourModes
        let known = Set(colourModes.map(\.id))
        let nonVirtual = Set(colourModes.filter { !$0.isVirtual }.map(\.id))
        self.dscCapableIDs = Set(colourModes.filter { !$0.isVirtual && $0.isDSCCapable }.map(\.id))
        self.dscRequiredIDs = Set(dscRequiredList).intersection(nonVirtual)
        self.unsafeIDs = Set(unsafeList).intersection(nonVirtual)
        self.dscRequiredIDsRaw = dscRequiredList
        self.unsafeIDsRaw = unsafeList
        self.validPixelEncodings = validPixelEncodings
        // The caller's flags can only be cleared here, never raised: a list naming an ID
        // no colour mode carries, or an entry whose SupportsDSC is outside 0...3, is
        // malformed whatever the reader said (PR #665 gate, Codex 2).
        self.colourModesComplete = colourModesComplete && colourModes.allSatisfy { (0...3).contains($0.supportsDSC) }
        self.dscListComplete = dscListComplete && Set(dscRequiredList).isSubset(of: known)
        self.unsafeListComplete = unsafeListComplete && Set(unsafeList).isSubset(of: known)
    }

    /// The IDs of the non-virtual colour modes.
    public var nonVirtualIDs: Set<Int> { Set(colourModes.filter { !$0.isVirtual }.map(\.id)) }

    /// True when at least one non-virtual colour mode is listed: macOS
    /// validated a format for this timing on this link. Many panels list a
    /// DTD twice, once with no colour modes at all (32 paired corpus nodes);
    /// that entry is a listing, not an offer.
    public var hasNonVirtualColourMode: Bool { colourModes.contains { !$0.isVirtual } }

    /// How much of this timing the converter sends on as YCbCr 4:2:0
    /// (ruling 44). Which mode is live is not on the node (dump Finding 3), so
    /// only `.all` supports "the picture is being converted"; `.some` supports
    /// "a mode on this timing is". 139 such modes on 21 driven corpus timings
    /// (P1 `pe-downstream-420`), every one of them `.someModes` (at 8 bits, 2 of 6
    /// modes convert on each; replica 2026-09-21).
    /// Case names avoid `some` and `none` on purpose: `Facts.downstream420`
    /// is optional, and `.some` / `.none` on an optional resolve to
    /// `Optional`'s cases. The raw values are the JSON and bench vocabulary.
    public enum Downstream420Reading: String, Codable, Hashable, Sendable {
        /// Every non-virtual colour mode carries a 4:2:0 `DownstreamFormat`:
        /// ruling 15's condition for `DisplayCurrentMode.downstreamFormat`,
        /// so the field and this reading always agree.
        case everyMode = "all"
        /// At least one does, not all.
        case someModes = "some"
        /// None does, or there are no non-virtual modes.
        case noMode = "none"
    }

    public var downstream420: Downstream420Reading {
        let nonVirtual = colourModes.filter { !$0.isVirtual }
        let converting = nonVirtual.filter { $0.downstreamFormat?.encoding == .ycbcr420 }
        guard !converting.isEmpty else { return .noMode }
        return converting.count == nonVirtual.count ? .everyMode : .someModes
    }

    /// What the lists say about a mode's compression.
    public enum DSCReading: String, Codable, Hashable, Sendable {
        /// No colour mode on the timing needs DSC on this link (the list is
        /// empty), or the mode resolves to a non-capable one.
        case uncompressed
        /// Every DSC-capable mode is DSC-required and the mode resolves to one
        /// of them, or every non-virtual mode is listed.
        case dscOn
        /// The lists were unreadable, the list is a proper subset of the
        /// capable set, or the mode cannot be resolved between a capable and
        /// a non-capable entry: the node does not name it (dump Finding 3).
        case unresolved
    }

    /// The non-virtual colour modes the live mode could be: filtered by the
    /// live depth when known (`bitsPerComponent`) and the live encoding when
    /// known (`pixelEncoding`). All of them when neither is known, which is
    /// also how a timing that is not being driven is read.
    public func candidateModes(for mode: DisplayCurrentMode?) -> [DisplayColourMode] {
        colourModes.filter { colour in
            guard !colour.isVirtual else { return false }
            if let depth = mode?.bitsPerComponent, colour.depth != depth { return false }
            if let encoding = mode?.pixelEncoding, colour.encoding != encoding { return false }
            return true
        }
    }

    /// The reading, in ruling 7's order: an unreadable colour table or DSC
    /// list says nothing (the unsafe list is not consulted, ruling 42); no
    /// candidate mode says nothing either, an empty list included (ruling 43:
    /// "nothing here needs DSC" is a statement about modes, and there are
    /// none); an empty list over at least one candidate means uncompressed;
    /// a list that is not the capable set is a shape the corpus has never
    /// seen and reads unresolved; otherwise the candidate modes decide: all
    /// capable, DSC on; none capable, uncompressed (a mode with
    /// `SupportsDSC = 0` is never in the list, so the link carries it plain);
    /// a mix, unresolved.
    public func dscReading(for mode: DisplayCurrentMode?) -> DSCReading {
        guard colourModesComplete, dscListComplete else { return .unresolved }
        let candidates = candidateModes(for: mode)
        guard !candidates.isEmpty else { return .unresolved }
        if dscRequiredIDs.isEmpty { return .uncompressed }
        guard dscRequiredIDs == dscCapableIDs else { return .unresolved }
        if candidates.allSatisfy(\.isDSCCapable) { return .dscOn }
        if !candidates.contains(where: \.isDSCCapable) { return .uncompressed }
        return .unresolved
    }

    /// Apple's bits per pixel for the live mode when every candidate mode
    /// costs the same (RGB beside YCbCr 4:4:4 both cost 3 x depth); nil when
    /// the candidates disagree (RGB beside 4:2:2), there are none, or the
    /// colour table is incomplete (the entry that failed to parse may be the
    /// live one; the same guard the reader's depth and encoding have; PR #665
    /// gate rerun, Claude F2). Feeds the cross-check and nothing else.
    public func liveBitsPerPixel(for mode: DisplayCurrentMode?) -> Double? {
        guard colourModesComplete else { return nil }
        let values = Set(candidateModes(for: mode).compactMap { $0.encoding.bitsPerPixel(depth: $0.depth) })
        return values.count == 1 ? values.first : nil
    }

    // MARK: Codable: the sets encode as sorted arrays so encoded output is stable across runs.

    private enum CodingKeys: String, CodingKey {
        case colourModes, dscCapableIDs, dscRequiredIDs, unsafeIDs, validPixelEncodings
        case colourModesComplete, dscListComplete, unsafeListComplete
        case dscRequiredIDsRaw, unsafeIDsRaw
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colourModes = try c.decode([DisplayColourMode].self, forKey: .colourModes)
        dscCapableIDs = Set(try c.decode([Int].self, forKey: .dscCapableIDs))
        dscRequiredIDs = Set(try c.decode([Int].self, forKey: .dscRequiredIDs))
        unsafeIDs = Set(try c.decode([Int].self, forKey: .unsafeIDs))
        validPixelEncodings = try c.decodeIfPresent(UInt32.self, forKey: .validPixelEncodings)
        colourModesComplete = try c.decode(Bool.self, forKey: .colourModesComplete)
        dscListComplete = try c.decode(Bool.self, forKey: .dscListComplete)
        unsafeListComplete = try c.decode(Bool.self, forKey: .unsafeListComplete)
        // Absent in an encoding from before the raw lists existed: read as empty.
        dscRequiredIDsRaw = try c.decodeIfPresent([Int].self, forKey: .dscRequiredIDsRaw) ?? []
        unsafeIDsRaw = try c.decodeIfPresent([Int].self, forKey: .unsafeIDsRaw) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(colourModes, forKey: .colourModes)
        try c.encode(dscCapableIDs.sorted(), forKey: .dscCapableIDs)
        try c.encode(dscRequiredIDs.sorted(), forKey: .dscRequiredIDs)
        try c.encode(unsafeIDs.sorted(), forKey: .unsafeIDs)
        try c.encodeIfPresent(validPixelEncodings, forKey: .validPixelEncodings)
        try c.encode(colourModesComplete, forKey: .colourModesComplete)
        try c.encode(dscListComplete, forKey: .dscListComplete)
        try c.encode(unsafeListComplete, forKey: .unsafeListComplete)
        try c.encode(dscRequiredIDsRaw, forKey: .dscRequiredIDsRaw)
        try c.encode(unsafeIDsRaw, forKey: .unsafeIDsRaw)
    }
}

/// One non-virtual timing the node lists, with its lists: what the panel's
/// declared top mode is matched against (ruling 37). `pixelClockHz` is totals
/// times refresh, nil for an interlaced timing.
public struct DisplayNodeTiming: Codable, Hashable, Sendable {
    public let id: Int
    public let width: Int
    public let height: Int
    public let refreshHz: Double
    public let pixelClockHz: Int?
    public let lists: DisplayTimingLists
    /// The timing's own `IsInterlaced`. Part of the picture's identity in
    /// `topModeMatch`: a 1080i60 listing is not the panel's 1080p60 mode
    /// (PR #665 gate rerun, Codex R1). Additive; an encoding from before the
    /// field reads progressive. An interlaced timing carries no clock.
    public let interlaced: Bool

    public init(id: Int, width: Int, height: Int, refreshHz: Double, pixelClockHz: Int?, lists: DisplayTimingLists, interlaced: Bool = false) {
        self.id = id
        self.width = width
        self.height = height
        self.refreshHz = refreshHz
        self.pixelClockHz = pixelClockHz
        self.lists = lists
        self.interlaced = interlaced
    }

    private enum CodingKeys: String, CodingKey {
        case id, width, height, refreshHz, pixelClockHz, lists, interlaced
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        refreshHz = try c.decode(Double.self, forKey: .refreshHz)
        pixelClockHz = try c.decodeIfPresent(Int.self, forKey: .pixelClockHz)
        lists = try c.decode(DisplayTimingLists.self, forKey: .lists)
        interlaced = try c.decodeIfPresent(Bool.self, forKey: .interlaced) ?? false
    }
}

/// What macOS states about a display: the driven timing's lists (the entry
/// of `TimingElements` / `PreferredTimingElements` whose `ID` is
/// `DPTimingModeId`) and every non-virtual timing the node lists. Built by
/// `DisplayTimingReader.match` in the Darwin backend and attached to
/// `IOPortTransportStateDisplayPort.drivenTiming`; nothing else sets it. The
/// reader never sees the EDID's top mode: which node timing is the top mode
/// is decided here, in Core, by `topModeMatch` (ruling 37).
public struct DisplayTimingStatement: Codable, Hashable, Sendable {
    /// The driven timing's lists.
    public let driven: DisplayTimingLists
    /// Every non-virtual timing the node lists, both lists, in the node's
    /// order. On external panels these are almost all the
    /// `PreferredTimingElements` (1 to 7 per node in the corpus, mean 3);
    /// `TimingElements` holds the virtual HDR twins.
    public let allTimings: [DisplayNodeTiming]

    public init(driven: DisplayTimingLists, allTimings: [DisplayNodeTiming]) {
        self.driven = driven
        self.allTimings = allTimings
    }

    /// The driven lists from their parts. Tests and fixtures use it.
    public init(colourModes: [DisplayColourMode], dscRequiredList: [Int], unsafeList: [Int], validPixelEncodings: UInt32?,
                colourModesComplete: Bool, dscListComplete: Bool, unsafeListComplete: Bool, allTimings: [DisplayNodeTiming] = []) {
        self.init(driven: DisplayTimingLists(colourModes: colourModes, dscRequiredList: dscRequiredList, unsafeList: unsafeList,
                                             validPixelEncodings: validPixelEncodings, colourModesComplete: colourModesComplete,
                                             dscListComplete: dscListComplete, unsafeListComplete: unsafeListComplete),
                  allTimings: allTimings)
    }

    public typealias DSCReading = DisplayTimingLists.DSCReading
    public typealias Downstream420Reading = DisplayTimingLists.Downstream420Reading

    // The driven timing's facts, read as before the lists were factored out.
    public var colourModes: [DisplayColourMode] { driven.colourModes }
    public var dscCapableIDs: Set<Int> { driven.dscCapableIDs }
    public var dscRequiredIDs: Set<Int> { driven.dscRequiredIDs }
    public var unsafeIDs: Set<Int> { driven.unsafeIDs }
    public var dscRequiredIDsRaw: [Int] { driven.dscRequiredIDsRaw }
    public var unsafeIDsRaw: [Int] { driven.unsafeIDsRaw }
    public var validPixelEncodings: UInt32? { driven.validPixelEncodings }
    public var colourModesComplete: Bool { driven.colourModesComplete }
    public var dscListComplete: Bool { driven.dscListComplete }
    public var unsafeListComplete: Bool { driven.unsafeListComplete }
    public var nonVirtualIDs: Set<Int> { driven.nonVirtualIDs }
    public var hasNonVirtualColourMode: Bool { driven.hasNonVirtualColourMode }
    public var downstream420: Downstream420Reading { driven.downstream420 }
    public func candidateModes(for mode: DisplayCurrentMode?) -> [DisplayColourMode] { driven.candidateModes(for: mode) }
    public func dscReading(for mode: DisplayCurrentMode?) -> DSCReading { driven.dscReading(for: mode) }
    public func liveBitsPerPixel(for mode: DisplayCurrentMode?) -> Double? { driven.liveBitsPerPixel(for: mode) }

    // MARK: The top-mode match (ruling 37)

    public enum TopModeMatchKind: String, Codable, Hashable, Sendable {
        case exact, sameRefresh, pictureOnly, notListed
    }

    /// How the panel's declared top mode sits in the node's list.
    public enum TopModeMatch: Hashable, Sendable {
        /// Same picture, refresh within 0.001 Hz of the entry or of its CTA
        /// alternate (entry / 1.001), totals x refresh within 1% of the
        /// entry's clock: the #661 sweep's rule.
        case exact(DisplayNodeTiming)
        /// Same picture and refresh (within 0.5 Hz, or the alternate) at
        /// another blanking: the node lists the mode with its own totals, as
        /// it does with its 936 MHz 5K timing against the EDID's 964.8 MHz
        /// tiled composite on every Studio Display.
        case sameRefresh(DisplayNodeTiming)
        /// The picture is listed only at other refreshes.
        case pictureOnly
        /// No timing has the picture.
        case notListed

        public var kind: TopModeMatchKind {
            switch self {
            case .exact: return .exact
            case .sameRefresh: return .sameRefresh
            case .pictureOnly: return .pictureOnly
            case .notListed: return .notListed
            }
        }

        public var timing: DisplayNodeTiming? {
            switch self {
            case .exact(let t), .sameRefresh(let t): return t
            case .pictureOnly, .notListed: return nil
            }
        }
    }

    static let exactRefreshHz = 0.001
    static let sameRefreshHz = 0.5
    static let clockTolerance = 0.01

    /// The node timing for a declared top mode. `pixelClockHz` nil (a top mode
    /// only CoreGraphics reports) skips the exact test. The picture is width,
    /// height and interlace together: an interlaced node timing is never the
    /// progressive candidate's mode, nor the reverse (PR #665 gate rerun,
    /// Codex R1); `interlaced` defaults to progressive, which every EDID
    /// entry but a CTA interlaced VIC is. The exact and
    /// same-refresh candidates are ranked together: a timing with a
    /// non-virtual colour mode wins over one with none (a listing macOS
    /// validated no format for must not hide a usable entry for the same
    /// mode at the node's own blanking; PR #665 gate, Codex 3 and Claude F3),
    /// exact beats same-refresh only among equally usable entries, then the
    /// highest clock.
    public func topModeMatch(width: Int, height: Int, refreshHz: Double, pixelClockHz: Int?, interlaced: Bool = false) -> TopModeMatch {
        let picture = allTimings.filter { $0.width == width && $0.height == height && $0.interlaced == interlaced }
        guard !picture.isEmpty else { return .notListed }
        func refreshMatches(_ timing: DisplayNodeTiming, within window: Double) -> Bool {
            abs(timing.refreshHz - refreshHz) <= window || abs(timing.refreshHz - refreshHz / 1.001) <= window
        }
        func isExact(_ timing: DisplayNodeTiming) -> Bool {
            guard let clock = pixelClockHz, let nodeClock = timing.pixelClockHz, refreshMatches(timing, within: Self.exactRefreshHz) else { return false }
            return abs(Double(nodeClock - clock)) <= Double(clock) * Self.clockTolerance
        }
        // Every exact entry is also a same-refresh one (0.001 Hz sits inside 0.5 Hz), so
        // the same-refresh pool is the whole candidate set and the exact test is a rank.
        let candidates = picture.filter { refreshMatches($0, within: Self.sameRefreshHz) }
        let winner = candidates.max { a, b in
            if a.lists.hasNonVirtualColourMode != b.lists.hasNonVirtualColourMode { return !a.lists.hasNonVirtualColourMode }
            if isExact(a) != isExact(b) { return !isExact(a) }
            return (a.pixelClockHz ?? 0) < (b.pixelClockHz ?? 0)
        }
        guard let winner else { return .pictureOnly }
        return isExact(winner) ? .exact(winner) : .sameRefresh(winner)
    }
}
