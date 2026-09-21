import Foundation
import Testing
@testable import WhatCableCore

/// The statement as a pure value: one timing's lists resolved against its
/// non-virtual colour modes, what that says about the live mode, and the
/// match from a declared top mode to the node's own timing for it. Fixtures
/// are corpus timings transcribed by hand (folder, node key, timing ID named
/// on each).
@Suite("DisplayTimingStatement")
struct DisplayTimingStatementTests {

    private static func colour(_ id: Int, _ encoding: DisplayPixelEncoding, _ depth: Int, dsc: Int, virtual: Bool = false, downstream: DisplayDownstreamFormat? = nil) -> DisplayColourMode {
        DisplayColourMode(id: id, encoding: encoding, depth: depth, supportsDSC: dsc, isVirtual: virtual, downstreamFormat: downstream)
    }

    /// One 8-bit RGB mode, not DSC-capable, list empty: the plain "offered, uncompressed" lists.
    private static func plainLists(id: Int = 1) -> DisplayTimingLists {
        DisplayTimingLists(colourModes: [colour(id, .rgb444, 8, dsc: 0)], dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1ffd, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    }

    /// One 8-bit RGB mode, DSC-capable and listed: "offered, with DSC".
    private static func dscLists(id: Int = 1) -> DisplayTimingLists {
        DisplayTimingLists(colourModes: [colour(id, .rgb444, 8, dsc: 1)], dscRequiredList: [id], unsafeList: [], validPixelEncodings: 0x1ffd, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    }

    /// No colour modes at all: the node lists the timing but validated no format on this link.
    private static let emptyLists = DisplayTimingLists(colourModes: [], dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1ffd, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)

    private static func node(_ id: Int, _ w: Int, _ h: Int, _ hz: Double, _ clock: Int?, _ lists: DisplayTimingLists) -> DisplayNodeTiming {
        DisplayNodeTiming(id: id, width: w, height: h, refreshHz: hz, pixelClockHz: clock, lists: lists)
    }

    /// m3_macos26.6.2, 27C1U-L, node 25E3FFFF-..., timing 45: no mode DSC-capable, DSC list empty, all six unsafe.
    static let lists27C1UL = DisplayTimingLists(
        colourModes: [colour(90, .rgb444, 8, dsc: 0), colour(89, .rgb444, 8, dsc: 0),
                      colour(91, .ycbcr444, 8, dsc: 0), colour(92, .ycbcr444, 8, dsc: 0),
                      colour(10, .ycbcr422, 12, dsc: 0, virtual: true), colour(11, .ycbcr422DPTunneling, 12, dsc: 0, virtual: true)],
        dscRequiredList: [], unsafeList: [90, 89, 91, 92, 10, 11], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    static let statement27C1UL = DisplayTimingStatement(driven: lists27C1UL, allTimings: [node(45, 3840, 2160, 60.0, 527_850_000, lists27C1UL)])

    /// m5_macos26.6.1_e, Studio Display, node 061046AE-..., timing 43: three RGB modes, all DSC-capable, all listed.
    static let listsStudio = DisplayTimingLists(
        colourModes: [colour(1, .rgb444, 8, dsc: 1, virtual: true), colour(46, .rgb444, 8, dsc: 1), colour(48, .rgb444, 10, dsc: 1)],
        dscRequiredList: [1, 46, 48], unsafeList: [], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    static let statementStudio = DisplayTimingStatement(driven: listsStudio, allTimings: [node(43, 5120, 2880, 60.0, 936_000_000, listsStudio)])

    /// m1max_macos26.5.2_p, node 1E6DBF5B-..., timing 64 (4K144): RGB and 4:4:4 DSC-capable and listed, 4:2:2 neither.
    static let listsMixed = DisplayTimingLists(
        colourModes: [colour(68, .rgb444, 8, dsc: 1), colour(1, .rgb444, 8, dsc: 1, virtual: true),
                      colour(71, .ycbcr422, 8, dsc: 0), colour(70, .ycbcr422, 8, dsc: 0),
                      colour(72, .ycbcr444, 8, dsc: 1), colour(73, .ycbcr444, 8, dsc: 1),
                      colour(75, .rgb444, 10, dsc: 1), colour(74, .rgb444, 10, dsc: 1), colour(81, .rgb444, 10, dsc: 1), colour(82, .rgb444, 10, dsc: 1)],
        dscRequiredList: [68, 1, 72, 73, 75, 74, 81, 82], unsafeList: [], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    static let statementMixed = DisplayTimingStatement(driven: listsMixed, allTimings: [node(64, 3840, 2160, 143.9993, 1_328_249_948, listsMixed)])

    /// m2pro_macos26.6.1, DELL S2721QS behind cHDMIb, node 10AC96A1-...-0C22-..., timing 57: three 4:4:4 modes carry a 4:2:0 downstream format; the link-side RGB and 4:4:4 modes without one are unsafe.
    static let listsS2721QS = DisplayTimingLists(
        colourModes: [colour(77, .rgb444, 8, dsc: 0), colour(76, .rgb444, 8, dsc: 0), colour(78, .ycbcr444, 8, dsc: 0), colour(79, .ycbcr444, 8, dsc: 0),
                      colour(5, .ycbcr444, 8, dsc: 0, virtual: true, downstream: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8)),
                      colour(87, .ycbcr444, 8, dsc: 0, downstream: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8)),
                      colour(85, .ycbcr444, 8, dsc: 0, downstream: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8)),
                      colour(10, .ycbcr422, 12, dsc: 0, virtual: true), colour(11, .ycbcr422DPTunneling, 12, dsc: 0, virtual: true)],
        dscRequiredList: [], unsafeList: [77, 76, 78, 79, 10, 11], validPixelEncodings: 0x1b4f, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
    static let statementS2721QS = DisplayTimingStatement(driven: listsS2721QS, allTimings: [node(57, 3840, 2160, 60.0, 594_000_000, listsS2721QS)])

    @Test("The sets are resolved against the non-virtual colour modes")
    func setsAreResolvedAgainstNonVirtualModes() {
        let s = Self.statement27C1UL
        #expect(s.nonVirtualIDs == [89, 90, 91, 92])
        #expect(s.dscCapableIDs.isEmpty)
        #expect(s.dscRequiredIDs.isEmpty)
        #expect(s.unsafeIDs == [89, 90, 91, 92], "the two virtual IDs (10, 11) are dropped from the resolved set")
        #expect(s.colourModes.count == 6, "the virtual entries stay in colourModes as facts")
        #expect(s.validPixelEncodings == 0x1b4d)
        #expect(s.driven == Self.lists27C1UL, "the forwarders read the driven lists")
        #expect(Self.statementStudio.dscRequiredIDs == [46, 48], "the virtual mode 1 is listed by the node but resolved out")
        #expect(Self.statementStudio.dscCapableIDs == [46, 48])
        // An ID the node lists that no colour mode carries never enters a set.
        let stray = DisplayTimingLists(colourModes: Self.listsStudio.colourModes, dscRequiredList: [46, 48, 999], unsafeList: [999], validPixelEncodings: nil, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(stray.dscRequiredIDs == [46, 48])
        #expect(stray.unsafeIDs.isEmpty)
        // The convenience init builds the driven lists from their parts.
        let convenience = DisplayTimingStatement(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [90, 89, 91, 92, 10, 11], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(convenience.driven == Self.lists27C1UL)
        #expect(convenience.allTimings.isEmpty)
    }

    @Test("Empty list reads uncompressed whatever the live mode")
    func emptyListIsUncompressed() {
        #expect(Self.statement27C1UL.dscReading(for: nil) == .uncompressed)
        #expect(Self.statement27C1UL.dscReading(for: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8)) == .uncompressed)
        #expect(Self.statementS2721QS.dscReading(for: nil) == .uncompressed)
    }

    @Test("Every non-virtual mode listed reads DSC on, with or without a live mode")
    func fullListIsDSCOn() {
        #expect(Self.statementStudio.dscReading(for: nil) == .dscOn)
        #expect(Self.statementStudio.dscReading(for: DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60, bitsPerComponent: 10)) == .dscOn)
    }

    @Test("A timing listing DSC-capable and non-capable modes together resolves only through the live depth and encoding")
    func mixedTimingResolvesThroughTheLiveMode() {
        let s = Self.statementMixed
        #expect(s.dscRequiredIDs == s.dscCapableIDs, "fixture guard: the list equals the capable set")
        #expect(s.dscReading(for: nil) == .unresolved, "no depth, no encoding: the live mode could be RGB (capable) or 4:2:2 (not)")
        #expect(s.dscReading(for: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 144, bitsPerComponent: 8)) == .unresolved, "8-bit RGB is capable, 8-bit 4:2:2 is not")
        #expect(s.dscReading(for: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 144, bitsPerComponent: 10)) == .dscOn, "every 10-bit mode is RGB and capable")
        #expect(s.dscReading(for: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 144, bitsPerComponent: 8, pixelEncoding: .ycbcr422)) == .uncompressed, "SupportsDSC = 0 is never a member: the link carries it uncompressed")
        #expect(s.dscReading(for: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 144, bitsPerComponent: 8, pixelEncoding: .rgb444)) == .dscOn)
        #expect(s.candidateModes(for: DisplayCurrentMode(width: 1, height: 1, refreshHz: 1, bitsPerComponent: 12)).isEmpty)
        #expect(s.dscReading(for: DisplayCurrentMode(width: 1, height: 1, refreshHz: 1, bitsPerComponent: 12)) == .unresolved, "a depth no mode has leaves nothing to read")
    }

    @Test("A proper subset, or an incomplete list, reads unresolved")
    func subsetOrIncompleteIsUnresolved() {
        let subset = DisplayTimingLists(colourModes: Self.listsStudio.colourModes, dscRequiredList: [46], unsafeList: [], validPixelEncodings: nil, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(subset.dscReading(for: nil) == .unresolved)
        let incomplete = DisplayTimingLists(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: nil,
                                            colourModesComplete: true, dscListComplete: false, unsafeListComplete: true)
        #expect(incomplete.dscReading(for: nil) == .unresolved, "an unreadable DSC list says nothing, even an empty one")
        let tableIncomplete = DisplayTimingLists(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: nil,
                                                 colourModesComplete: false, dscListComplete: true, unsafeListComplete: true)
        #expect(tableIncomplete.dscReading(for: nil) == .unresolved, "a table missing an entry cannot say what the live mode is")
        // Ruling 42: the unsafe list is a converter receipt (Design 5). Damage to it alone never touches the DSC reading.
        let unsafeIncomplete = DisplayTimingLists(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: nil,
                                                  colourModesComplete: true, dscListComplete: true, unsafeListComplete: false)
        #expect(unsafeIncomplete.dscReading(for: nil) == .uncompressed, "an unreadable unsafe list does not suppress a complete DSC statement")
        #expect(unsafeIncomplete.unsafeIDs.isEmpty)
        let unsafeIncompleteDSC = DisplayTimingLists(colourModes: Self.listsStudio.colourModes, dscRequiredList: [1, 46, 48], unsafeList: [], validPixelEncodings: nil,
                                                     colourModesComplete: true, dscListComplete: true, unsafeListComplete: false)
        #expect(unsafeIncompleteDSC.dscReading(for: nil) == .dscOn)
    }

    @Test("An ID no colour mode carries makes its list incomplete; a SupportsDSC outside 0...3 makes the table incomplete (PR #665 gate, Codex 2)")
    func unknownIDsAndOutOfRangeSupportsDSCFailClosed() {
        // One DSC-capable non-virtual mode, 46. A list of [46, 999]: intersected with the
        // colour modes it would equal the capable set and read DSC on; the 999 is a shape
        // the firmware never publishes (0 of 4101 unsampled corpus timings), so the list is
        // unreadable and the reading unresolved.
        let modes = [Self.colour(46, .rgb444, 8, dsc: 1), Self.colour(1, .rgb444, 8, dsc: 1, virtual: true)]
        let extra = DisplayTimingLists(colourModes: modes, dscRequiredList: [46, 999], unsafeList: [], validPixelEncodings: 0x1b4d,
                                       colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(extra.dscListComplete == false)
        #expect(extra.dscReading(for: nil) == .unresolved, "not dscOn: 999 belongs to no colour mode")
        #expect(extra.dscRequiredIDs == [46], "the resolved set still names what did match")
        // [999] alone: intersected it would be empty and read uncompressed.
        let only = DisplayTimingLists(colourModes: modes, dscRequiredList: [999], unsafeList: [], validPixelEncodings: 0x1b4d,
                                      colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(only.dscListComplete == false)
        #expect(only.dscReading(for: nil) == .unresolved, "not uncompressed: the list named a mode the table does not have")
        // An ID that belongs to a virtual mode is a known mode: the list stays complete (the Studio Display's [1, 46, 48]).
        #expect(Self.listsStudio.dscListComplete == true)
        #expect(Self.listsStudio.dscReading(for: nil) == .dscOn)
        // The unsafe list on the same terms: a receipt fact (ruling 42), the DSC reading untouched.
        let unsafe = DisplayTimingLists(colourModes: modes, dscRequiredList: [], unsafeList: [46, 999], validPixelEncodings: 0x1b4d,
                                        colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(unsafe.unsafeListComplete == false)
        #expect(unsafe.dscListComplete == true)
        #expect(unsafe.dscReading(for: nil) == .uncompressed)
        // SupportsDSC is the two-bit field the dump names (0 to 3); 7 is a malformed entry.
        let seven = DisplayTimingLists(colourModes: [Self.colour(46, .rgb444, 8, dsc: 7)], dscRequiredList: [46], unsafeList: [], validPixelEncodings: 0x1b4d,
                                       colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(seven.colourModesComplete == false)
        #expect(seven.dscReading(for: nil) == .unresolved)
        let passthrough = DisplayTimingLists(colourModes: [Self.colour(46, .rgb444, 8, dsc: 3)], dscRequiredList: [46], unsafeList: [], validPixelEncodings: 0x1b4d,
                                             colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(passthrough.colourModesComplete == true && passthrough.dscReading(for: nil) == .dscOn, "3 (sink and branch) is in range")
        // A caller's clear flag is never raised back to true by a clean list.
        let cleared = DisplayTimingLists(colourModes: modes, dscRequiredList: [46], unsafeList: [], validPixelEncodings: 0x1b4d,
                                         colourModesComplete: true, dscListComplete: false, unsafeListComplete: true)
        #expect(cleared.dscListComplete == false)
    }

    @Test("Ruling 43: an empty DSC list over no colour modes is not a statement; it reads unresolved")
    func emptyListOverNoModesIsUnresolved() {
        #expect(Self.emptyLists.dscReading(for: nil) == .unresolved, "no candidate mode: nothing says the link carries the mode plain")
        #expect(Self.emptyLists.hasNonVirtualColourMode == false)
        // Virtual entries alone are no candidates either.
        let virtualOnly = DisplayTimingLists(colourModes: [Self.colour(10, .ycbcr422, 12, dsc: 0, virtual: true)], dscRequiredList: [], unsafeList: [],
                                             validPixelEncodings: 0xffffffff, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(virtualOnly.dscReading(for: nil) == .unresolved)
        // One non-virtual candidate is enough.
        #expect(Self.plainLists().dscReading(for: nil) == .uncompressed)
        // A live depth that empties the candidate set reads unresolved, not uncompressed, on an empty list too.
        #expect(Self.plainLists().dscReading(for: DisplayCurrentMode(width: 1, height: 1, refreshHz: 1, bitsPerComponent: 12)) == .unresolved)
    }

    @Test("Live bits per pixel are determined when the candidate modes agree on Apple's figure")
    func liveBitsPerPixelWhenCandidatesAgree() {
        #expect(Self.statement27C1UL.liveBitsPerPixel(for: nil) == 24, "RGB and 4:4:4 at 8 bits both cost 24")
        #expect(Self.statementStudio.liveBitsPerPixel(for: nil) == nil, "8 and 10 bit RGB: 24 or 30")
        #expect(Self.statementStudio.liveBitsPerPixel(for: DisplayCurrentMode(width: 5120, height: 2880, refreshHz: 60, bitsPerComponent: 10)) == 30)
        #expect(Self.statementMixed.liveBitsPerPixel(for: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 144, bitsPerComponent: 8)) == nil, "RGB 24 beside 4:2:2 16")
        #expect(Self.statementMixed.liveBitsPerPixel(for: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 144, bitsPerComponent: 10)) == 30)
        // An incomplete table names no cost: the entry that failed to parse may be the one that
        // is live (PR #665 gate rerun, Claude F2), the same guard bitsPerComponent has.
        let incomplete = DisplayTimingLists(colourModes: Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: 0x1b4d,
                                            colourModesComplete: false, dscListComplete: true, unsafeListComplete: true)
        #expect(incomplete.liveBitsPerPixel(for: nil) == nil)
        #expect(incomplete.liveBitsPerPixel(for: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8)) == nil)
    }

    @Test("The 4:2:0 downstream reading is every mode, some modes or no mode over the non-virtual modes (ruling 44)")
    func downstream420IsExposed() {
        #expect(Self.statementS2721QS.downstream420 == .someModes, "3 of 6 non-virtual modes convert: the live one is not named")
        #expect(Self.statement27C1UL.downstream420 == .noMode)
        let virtualOnly = DisplayTimingLists(colourModes: [Self.listsS2721QS.colourModes[4]] + Self.lists27C1UL.colourModes, dscRequiredList: [], unsafeList: [], validPixelEncodings: nil, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(virtualOnly.downstream420 == .noMode, "a virtual entry's downstream format does not count")
        // Every non-virtual mode converting: the m1_macos26.5_o entry alone (mode 5, 4:4:4 at 8 bits, downstream 4:2:0 at 8 bits).
        let allConverting = DisplayTimingLists(colourModes: [Self.colour(5, .ycbcr444, 8, dsc: 0, downstream: DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8)), Self.listsS2721QS.colourModes[7]],
                                               dscRequiredList: [], unsafeList: [], validPixelEncodings: nil, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        #expect(allConverting.downstream420 == .everyMode, "the one non-virtual mode converts; the virtual 4:2:2 entry does not count")
        #expect(Self.emptyLists.downstream420 == .noMode)
        #expect(Self.statementS2721QS.unsafeIDs == [76, 77, 78, 79], "the three 4:2:0-downstream modes are not rated unsafe")
        #expect(Self.emptyLists.hasNonVirtualColourMode == false)
        #expect(Self.lists27C1UL.hasNonVirtualColourMode == true)
    }

    // MARK: - The top-mode match (ruling 37)

    /// A G34w-10-shaped node: 3440x1440 at 60 Hz (319.89 MHz) and at 100 Hz
    /// (600 MHz), 1080p60, with the 60 Hz entry listed twice, once with no
    /// colour modes (the shape 32 paired corpus nodes show).
    private static let g34wNode = DisplayTimingStatement(driven: plainLists(id: 1), allTimings: [
        node(10, 3440, 1440, 60.0, 319_890_000, emptyLists),
        node(11, 3440, 1440, 60.0, 319_890_000, plainLists(id: 1)),
        node(12, 3440, 1440, 99.99, 600_000_000, dscLists(id: 2)),
        node(13, 1920, 1080, 60.0, 148_500_000, plainLists(id: 3)),
    ])

    @Test("Exact match: picture, refresh within 0.001 Hz, clock within 1 percent; the entry with colour modes wins a tie")
    func exactMatchPrefersColourModes() throws {
        let match = Self.g34wNode.topModeMatch(width: 3440, height: 1440, refreshHz: 60.0, pixelClockHz: 319_890_000)
        #expect(match.kind == .exact)
        let timing = try #require(match.timing)
        #expect(timing.id == 11, "the twin with colour modes, not the empty one")
        let top = Self.g34wNode.topModeMatch(width: 3440, height: 1440, refreshHz: 99.99, pixelClockHz: 600_000_000)
        #expect(top.kind == .exact)
        #expect(top.timing?.id == 12)
        #expect(top.timing?.lists.dscReading(for: nil) == .dscOn)
        // Clock off by more than 1 percent at the same refresh is the same-refresh step, not exact.
        let offClock = Self.g34wNode.topModeMatch(width: 3440, height: 1440, refreshHz: 60.0, pixelClockHz: 340_000_000)
        #expect(offClock.kind == .sameRefresh)
        #expect(offClock.timing?.id == 11)
    }

    @Test("The CTA alternate rate counts as exact: a 60 Hz entry against a 59.94 Hz node timing")
    func ctaAlternateIsExact() {
        let cta = DisplayTimingStatement(driven: Self.plainLists(), allTimings: [Self.node(20, 3840, 2160, 59.94005994, 593_406_593, Self.plainLists())])
        let match = cta.topModeMatch(width: 3840, height: 2160, refreshHz: 60.0, pixelClockHz: 594_000_000)
        #expect(match.kind == .exact)
    }

    @Test("Same picture and refresh at another blanking is a same-refresh match (the Studio Display's 936 MHz against the 964.8 MHz composite)")
    func sameRefreshAtAnotherBlanking() throws {
        let match = Self.statementStudio.topModeMatch(width: 5120, height: 2880, refreshHz: 60.0, pixelClockHz: 964_800_000)
        #expect(match.kind == .sameRefresh)
        #expect(try #require(match.timing).id == 43)
        // With no declared clock (a macOS-only top) the exact step is skipped and the same-refresh step runs.
        let noClock = Self.statementStudio.topModeMatch(width: 5120, height: 2880, refreshHz: 60.0, pixelClockHz: nil)
        #expect(noClock.kind == .sameRefresh)
    }

    @Test("An entry with a colour mode wins across the exact and same-refresh pools: an empty exact listing does not hide a usable same-refresh one (PR #665 gate, Codex 3 and Claude F3)")
    func usableSameRefreshEntryBeatsAnEmptyExactOne() throws {
        // The node lists the EDID's 4K144 at its exact refresh and clock with no colour modes,
        // and the same picture and refresh (143.9 Hz: inside 0.5 Hz, outside 0.001 Hz and not
        // the /1.001 alternate) at the node's own blanking, more than 1% apart in clock, with a
        // colour mode validated. macOS offers the picture at that refresh; the empty listing
        // must not read it as not offered.
        let emptyExact = Self.node(30, 3840, 2160, 144.0, 1_328_250_000, Self.emptyLists)
        let usableSameRefresh = Self.node(31, 3840, 2160, 143.9, 1_306_000_000, Self.plainLists(id: 5))
        let statement = DisplayTimingStatement(driven: Self.plainLists(), allTimings: [emptyExact, usableSameRefresh])
        let match = statement.topModeMatch(width: 3840, height: 2160, refreshHz: 144.0, pixelClockHz: 1_328_250_000)
        #expect(match.kind == .sameRefresh, "got \(match.kind)")
        #expect(match.timing?.id == 31, "the usable entry, not the empty exact one")
        #expect(DisplayDiagnostic.topModeAvailability(match) == .offeredUncompressed)
        // With DSC listed on the usable entry the offer carries that.
        let usableDSC = Self.node(31, 3840, 2160, 143.9, 1_306_000_000, Self.dscLists(id: 5))
        let dsc = DisplayTimingStatement(driven: Self.plainLists(), allTimings: [emptyExact, usableDSC])
        #expect(DisplayDiagnostic.topModeAvailability(dsc.topModeMatch(width: 3840, height: 2160, refreshHz: 144.0, pixelClockHz: 1_328_250_000)) == .offeredWithDSC)
        // Among equally usable entries exact still beats same-refresh, whatever the clocks.
        let usableExact = Self.node(30, 3840, 2160, 144.0, 1_328_250_000, Self.plainLists(id: 4))
        let both = DisplayTimingStatement(driven: Self.plainLists(), allTimings: [usableSameRefresh, usableExact])
        let bothMatch = both.topModeMatch(width: 3840, height: 2160, refreshHz: 144.0, pixelClockHz: 1_328_250_000)
        #expect(bothMatch.kind == .exact)
        #expect(bothMatch.timing?.id == 30)
        // Two empty listings: exact still wins, and the match still reads not offered downstream.
        let emptySameRefresh = Self.node(31, 3840, 2160, 143.9, 1_306_000_000, Self.emptyLists)
        let bothEmpty = DisplayTimingStatement(driven: Self.plainLists(), allTimings: [emptySameRefresh, emptyExact])
        let emptyMatch = bothEmpty.topModeMatch(width: 3840, height: 2160, refreshHz: 144.0, pixelClockHz: 1_328_250_000)
        #expect(emptyMatch.kind == .exact && emptyMatch.timing?.id == 30)
        #expect(DisplayDiagnostic.topModeAvailability(emptyMatch) == .notOffered)
    }

    @Test("Picture only at other refreshes, and picture not listed, are told apart")
    func pictureOnlyAndNotListed() {
        #expect(Self.g34wNode.topModeMatch(width: 3440, height: 1440, refreshHz: 144.0, pixelClockHz: 900_000_000).kind == .pictureOnly)
        #expect(Self.g34wNode.topModeMatch(width: 1600, height: 1200, refreshHz: 60.0, pixelClockHz: 162_000_000).kind == .notListed)
        #expect(Self.g34wNode.topModeMatch(width: 1600, height: 1200, refreshHz: 60.0, pixelClockHz: 162_000_000).timing == nil)
        let empty = DisplayTimingStatement(driven: Self.plainLists(), allTimings: [])
        #expect(empty.topModeMatch(width: 3440, height: 1440, refreshHz: 60.0, pixelClockHz: 319_890_000).kind == .notListed)
    }

    @Test("Interlace is part of the picture's identity: a 1080i60 node timing never matches a progressive 1080p60 candidate (PR #665 gate rerun, Codex R1)")
    func interlaceIsPartOfTheIdentity() throws {
        // The reader leaves an interlaced timing's clock nil; the node lists 1080i60 with a colour mode.
        let interlaced = DisplayNodeTiming(id: 5, width: 1920, height: 1080, refreshHz: 60.0, pixelClockHz: nil, lists: Self.plainLists(id: 9), interlaced: true)
        let statement = DisplayTimingStatement(driven: Self.plainLists(), allTimings: [interlaced])
        // A progressive 1080p60 EDID candidate: not listed at all, so never offered and never the cable cleared.
        let progressive = statement.topModeMatch(width: 1920, height: 1080, refreshHz: 60.0, pixelClockHz: 148_500_000, interlaced: false)
        #expect(progressive.kind == .notListed, "got \(progressive.kind)")
        #expect(DisplayDiagnostic.topModeAvailability(progressive) == .notListed)
        // A matching interlaced pair still matches (no clock on the node side, so same-refresh).
        let pair = statement.topModeMatch(width: 1920, height: 1080, refreshHz: 60.0, pixelClockHz: 74_250_000, interlaced: true)
        #expect(pair.kind == .sameRefresh)
        #expect(pair.timing?.id == 5)
        #expect(DisplayDiagnostic.topModeAvailability(pair) == .offeredUncompressed)
        // A progressive node timing never matches an interlaced candidate either.
        let progressiveNode = DisplayTimingStatement(driven: Self.plainLists(), allTimings: [Self.node(6, 1920, 1080, 60.0, 148_500_000, Self.plainLists(id: 9))])
        #expect(progressiveNode.topModeMatch(width: 1920, height: 1080, refreshHz: 60.0, pixelClockHz: 74_250_000, interlaced: true).kind == .notListed)
        // The default is progressive, so every existing call reads as before.
        #expect(progressiveNode.topModeMatch(width: 1920, height: 1080, refreshHz: 60.0, pixelClockHz: 148_500_000).kind == .exact)
        // Codable carries the flag; an encoding from before it reads progressive.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = try #require(String(data: try encoder.encode(interlaced), encoding: .utf8))
        #expect(text.contains("\"interlaced\":true"), "\(text)")
        #expect(try JSONDecoder().decode(DisplayNodeTiming.self, from: try encoder.encode(interlaced)) == interlaced)
        let legacy = try JSONDecoder().decode(DisplayNodeTiming.self, from: Data("""
        {"id":6,"width":1920,"height":1080,"refreshHz":60,"pixelClockHz":148500000,"lists":{"colourModes":[],"dscCapableIDs":[],"dscRequiredIDs":[],"unsafeIDs":[],"colourModesComplete":true,"dscListComplete":true,"unsafeListComplete":true}}
        """.utf8))
        #expect(legacy.interlaced == false)
    }

    @Test("The raw lists are carried as the node printed them, beside the sets resolved against the non-virtual modes (PR #665 gate fix round 2, L1)")
    func rawListsKeepWhatTheResolvedSetsDrop() throws {
        // The Studio Display's node prints DSCRequiredColorElementIDs (1, 46, 48); mode 1 is virtual,
        // so the resolved set is {46, 48}. The raw list keeps the 1, in the node's order.
        #expect(Self.listsStudio.dscRequiredIDsRaw == [1, 46, 48])
        #expect(Self.listsStudio.dscRequiredIDs == [46, 48])
        #expect(Self.statementStudio.dscRequiredIDsRaw == [1, 46, 48], "forwarded from the driven lists")
        // The 27C1U-L's unsafe list as printed, (90, 89, 91, 92, 10, 11), against the resolved {89, 90, 91, 92}.
        #expect(Self.lists27C1UL.unsafeIDsRaw == [90, 89, 91, 92, 10, 11])
        #expect(Self.lists27C1UL.unsafeIDs == [89, 90, 91, 92])
        #expect(Self.statement27C1UL.unsafeIDsRaw == [90, 89, 91, 92, 10, 11])
        // Codable carries both raw lists; an encoding from before the fields existed decodes with empty ones.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = try #require(String(data: try encoder.encode(Self.statementStudio), encoding: .utf8))
        #expect(text.contains("\"dscRequiredIDsRaw\":[1,46,48]"), "\(text)")
        #expect(text.contains("\"unsafeIDsRaw\":[]"))
        let back = try JSONDecoder().decode(DisplayTimingStatement.self, from: try encoder.encode(Self.statement27C1UL))
        #expect(back.unsafeIDsRaw == [90, 89, 91, 92, 10, 11])
        #expect(back == Self.statement27C1UL)
        let legacy = """
        {"colourModes":[],"dscCapableIDs":[],"dscRequiredIDs":[],"unsafeIDs":[],"colourModesComplete":true,"dscListComplete":true,"unsafeListComplete":true}
        """
        let decoded = try JSONDecoder().decode(DisplayTimingLists.self, from: Data(legacy.utf8))
        #expect(decoded.dscRequiredIDsRaw.isEmpty && decoded.unsafeIDsRaw.isEmpty)
    }

    @Test("Codable round trip, with the sets encoded as sorted arrays, and allTimings carried")
    func codableRoundTripIsStable() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Self.statementMixed)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"dscRequiredIDs\":[68,72,73,74,75,81,82]"), "\(text)")
        #expect(text.contains("\"dscCapableIDs\":[68,72,73,74,75,81,82]"))
        #expect(text.contains("\"unsafeIDs\":[]"))
        #expect(text.contains("\"validPixelEncodings\":6989"))
        #expect(text.contains("\"colourModesComplete\":true") && text.contains("\"dscListComplete\":true") && text.contains("\"unsafeListComplete\":true"))
        #expect(!text.contains("listsComplete\""), "the single flag is gone (ruling 42)")
        #expect(text.contains("\"allTimings\":[{"))
        let back = try JSONDecoder().decode(DisplayTimingStatement.self, from: data)
        #expect(back == Self.statementMixed)
        let downstream = try JSONDecoder().decode(DisplayTimingStatement.self, from: try encoder.encode(Self.statementS2721QS))
        #expect(downstream == Self.statementS2721QS)
        let g34w = try JSONDecoder().decode(DisplayTimingStatement.self, from: try encoder.encode(Self.g34wNode))
        #expect(g34w == Self.g34wNode)
        #expect(g34w.allTimings.count == 4)
    }

    @Test("The DisplayPort node carries the statement through Codable")
    func displayPortNodeCarriesTheStatement() throws {
        let mode = DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 527_850_000, pixelEncoding: nil, downstreamFormat: nil)
        let port = IOPortTransportStateDisplayPort(
            link: DisplayPortLink(active: true, laneCount: 2, maxLaneCount: 2, linkRate: 4, linkRateDescription: "8.1 Gbps (HBR3)", tunneled: false, hpdState: 1),
            monitor: nil, currentMode: mode, drivenTiming: Self.statement27C1UL, hpmControllerUUID: "ignored-by-codable")
        let data = try JSONEncoder().encode(port)
        let back = try JSONDecoder().decode(IOPortTransportStateDisplayPort.self, from: data)
        #expect(back.drivenTiming == Self.statement27C1UL)
        #expect(back.currentMode == mode)
        #expect(back.hpmControllerUUID == nil, "the join key stays out of the encoded form, as before")
        // A node encoded before this field existed decodes with no statement.
        let legacy = try JSONDecoder().decode(IOPortTransportStateDisplayPort.self, from: try JSONEncoder().encode(
            IOPortTransportStateDisplayPort(link: port.link, monitor: nil)))
        #expect(legacy.drivenTiming == nil)
    }
}
