import Foundation
import Testing
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

// MARK: - DisplayTimingReaderProbeSweepTests
//
// Replays every external display node in the probe-26 corpus
// (`26_displayport_altmode.json`, "Connected display capability (tree)")
// through `DisplayTimingReader.parseNode`, pairs each to its DisplayPort node
// from probe 33 through `DisplayTimingReader.match`, and asks whether the
// timing macOS drives is one the EDID declares: same picture, refresh to
// 0.001 Hz (the node's refresh is a 16.16 fixed-point sync rate), pixel clock
// to 1 kHz (which pins the totals: one pixel of blanking moves the clock by
// tens of kHz).
//
// Probe 26 caps every array at 12 entries (`cap = 12`, marked "(sampled)"),
// so a node whose DPTimingModeId sits outside the captured entries has no
// timing to compare; some dumps are also cut at the 64 KB pipe cap before
// the timing lists. Both read as "current timing not captured" and are
// named, never silently skipped. A live node has whole arrays.
//
// CTA-861 defines every VIC at its nominal rate and at rate/1.001, and the
// EDID's one SVD covers both, so a driven timing at exactly refresh/1.001 of
// a declared VIC counts as declared. Those nodes are named and counted apart.
//
// A node can also publish a declared timing at its nominal rate. The Dell
// U3224KB on `m3ultra_macos27.2` (2026-11-12) declares 6144x3456 in a DisplayID
// Type I block at 1378.80 MHz over 6464 x 3555 totals, which is 60.00125 Hz;
// its node carries the same totals and porches with a vertical PreciseSyncRate
// of exactly 0x3c0000 (60.000 Hz), so totals times refresh is 28.8 kHz short of
// the declared clock. When the claimed node's totals equal a declared mode's
// and the refreshes differ by under 0.01 Hz, it is the declared mode with the
// rate rounded, not an undeclared one. Those are named and counted apart too.
//
// The parser and the probe-33 pairing are shared with DisplayDiagnosticProbeSweepTests through CorpusDisplayProbes.swift.

@Suite("DisplayTimingReader -- probe-26 corpus sweep")
struct DisplayTimingReaderProbeSweepTests {

    // MARK: - The sweep

    @Test("Sweep: macOS's driven timing is a mode the EDID declares, on every node the corpus lets us pair")
    func drivenTimingIsADeclaredMode() throws {
        guard let folders = try? FileManager.default.contentsOfDirectory(atPath: CorpusDisplayProbes.probeRoot.path) else {
            return // corpus absent: the private CI's corpus-presence check owns that failure
        }

        var foldersWithProbe26 = 0
        var nodesWithTables = 0
        var byClass: [String: Int] = [:]
        var notCaptured: [String] = []
        var unpaired: [String] = []
        var attachedPorts = 0
        var claimedNodes = 0
        var comparedExact = 0
        var alternateRate: [String] = []
        var nominalRate: [String] = []
        var mismatches: [String] = []
        var singleDepth = 0
        var nodesWithTiming = 0

        for folder in folders.sorted() {
            guard let text = CorpusDisplayProbes.loadOutput(folder: folder, file: "26_displayport_altmode.json") else { continue }
            foldersWithProbe26 += 1
            var nodes: [DisplayTimingReader.Node] = []
            for parsed in CorpusDisplayProbes.parseNodes(text: text) {
                guard (parsed.props["external"] as? NSNumber)?.boolValue == true,
                      parsed.props["TimingElements"] != nil else { continue }
                nodesWithTables += 1
                byClass[parsed.className, default: 0] += 1
                guard let node = DisplayTimingReader.parseNode(read: { parsed.props[$0] }) else {
                    Issue.record("\(folder): an external node with tables did not parse (no UUID key?)")
                    continue
                }
                guard let timing = node.currentTiming else {
                    notCaptured.append("\(folder) \(node.edidKey): timing \(node.currentTimingID.map(String.init) ?? "nil") not among \(node.capturedTimingIDs)")
                    continue
                }
                nodesWithTiming += 1
                if timing.bitsPerComponent != nil { singleDepth += 1 }
                nodes.append(node)
            }
            guard !nodes.isEmpty else { continue }

            let ports = CorpusDisplayProbes.activePorts(folder: folder)
            let matched = DisplayTimingReader.match(ports: ports.map(\.port), nodes: nodes)
            // Nodes not yet claimed by an attached port. A port claims the
            // first unclaimed node with its key and the attached clock whose
            // serial does not contradict the port's, so two identical panels
            // at the same timing claim two nodes, and a node attached twice
            // (a match defect) is recorded rather than counted.
            var pool = nodes
            for (entry, port) in zip(ports, matched) {
                var claimedTiming: DisplayTimingReader.Timing?
                guard let mode = port.currentMode, let clock = mode.pixelClockHz else { continue }
                attachedPorts += 1
                let key = DisplayTimingReader.edidKey(from: entry.port.monitor?.edid ?? Data())
                let portSerial = entry.port.monitor?.serialNumber ?? 0
                if let index = pool.firstIndex(where: {
                    $0.edidKey == key && $0.currentTiming?.pixelClockHz == clock
                        && (portSerial == 0 || ($0.serialNumber ?? 0) == 0 || $0.serialNumber == portSerial)
                }) {
                    claimedTiming = pool.remove(at: index).currentTiming
                    claimedNodes += 1
                } else {
                    Issue.record("\(folder) block \(entry.block): attached a timing no unclaimed node explains (a node attached twice?)")
                }
                let tag = "\(folder) block \(entry.block): driven \(mode.width)x\(mode.height) @ \(mode.refreshHz) Hz, clock \(clock)"
                let exact = entry.edid.modes.contains {
                    $0.width == mode.width && $0.height == mode.height
                        && abs($0.refreshHz - mode.refreshHz) <= 0.001
                        && abs($0.pixelClockHz - clock) <= 1000
                }
                if exact { comparedExact += 1; continue }
                let alternate = entry.edid.modes.contains {
                    $0.width == mode.width && $0.height == mode.height
                        && abs($0.refreshHz / 1.001 - mode.refreshHz) <= 0.001
                        && abs(Double($0.pixelClockHz) / 1.001 - Double(clock)) <= 1000
                }
                if alternate { alternateRate.append(tag + " (declared at x1.001)"); continue }
                if let timing = claimedTiming, entry.edid.modes.contains(where: {
                    $0.width == mode.width && $0.height == mode.height
                        && $0.hTotal == timing.hTotal && $0.vTotal == timing.vTotal
                        && abs($0.refreshHz - mode.refreshHz) < 0.01
                }) {
                    nominalRate.append(tag + " (declared totals, rate rounded)")
                    continue
                }
                mismatches.append(tag + " is not among the EDID's \(entry.edid.modes.count) declared modes")
            }
            for node in pool {
                unpaired.append("\(folder) \(node.edidKey) serial \(node.serialNumber ?? 0): no single probe-33 block with that EDID identity")
            }
        }

        print("DisplayTimingReaderProbeSweep: \(foldersWithProbe26) folders with probe 26; \(nodesWithTables) external nodes with tables \(byClass); \(nodesWithTiming) with the current timing captured, \(notCaptured.count) not captured; \(attachedPorts) ports attached (\(claimedNodes) nodes claimed), \(unpaired.count) nodes unpaired; compared: \(comparedExact) exact, \(alternateRate.count) at the CTA alternate rate, \(nominalRate.count) at a rounded rate, \(mismatches.count) mismatches; \(singleDepth) timings with a single depth")
        for line in notCaptured { print("  NOT CAPTURED \(line)") }
        for line in unpaired { print("  UNPAIRED \(line)") }
        for line in alternateRate { print("  ALTERNATE RATE \(line)") }
        for line in nominalRate { print("  ROUNDED RATE \(line)") }
        for line in mismatches { print("  MISMATCH \(line)") }

        // Non-vacuity: a corpus that exists but yields no node must not pass quietly. The run
        // prints every total (re-derivable by the research repo's scripts/display-timing-sweep.py);
        // the assertions below hold the per-node rule and the accounting, never the totals.
        #expect(nodesWithTables > 0, "no external node with tables: checked at least one")
        #expect(mismatches.isEmpty, "\(mismatches.count) driven timings the EDID does not declare:\n\(mismatches.joined(separator: "\n"))")
        #expect(attachedPorts == claimedNodes, "a port attached a timing no node explains: \(attachedPorts) ports for \(claimedNodes) nodes")
        #expect(comparedExact + alternateRate.count + nominalRate.count + mismatches.count == attachedPorts, "every attached port is compared")
        #expect(claimedNodes + unpaired.count == nodesWithTiming, "every captured node is attached or named unpaired")
        #expect(nodesWithTiming + notCaptured.count == nodesWithTables, "every node is accounted for")
    }

    // MARK: - The statement fields against the pair figures (issue #664)

    /// Replays every external node with tables through the production parser
    /// and asserts what research/displays/display-node-keys.md measured with
    /// its six parser pairs. This sweep reads the tree and redacted renderings
    /// only, and every external node with tables rather than only the paired
    /// nodes, so its denominators are its own and are printed, not asserted;
    /// the invariants (never a proper subset, never a SupportsDSC = 0 member,
    /// never a non-4:2:0 downstream format, virtual timings alone at
    /// 0xffffffff, native DP never unsafe) are asserted as zeros.
    ///
    /// Sampled lists (corpus-parser-traps entry 13): a `[N] (sampled)` header
    /// means the printed items are the first twelve of N. Membership over a
    /// sampled list is unknown, so a timing whose DSC list or ColorModes list
    /// is sampled is excluded from the shape and membership tests and counted
    /// as a skip; the printed count never exceeds the header count.
    @Test("Sweep: the DSC-required, unsafe, SupportsDSC, DownstreamFormat and ValidPixelEncodings fields replay to the pair figures")
    func statementFieldsMatchThePairFigures() throws {
        guard let folders = try? FileManager.default.contentsOfDirectory(atPath: CorpusDisplayProbes.probeRoot.path) else {
            return // corpus absent: the private CI's corpus-presence check owns that failure
        }

        var nodesWithTables = 0
        var timingsSeen = 0
        var timingsParsed = 0
        var unparsed: [String] = []
        var unparsedNotCut: [String] = []
        var shapeSampledSkipped = 0
        var incomplete: [String] = []
        var shapeTested = 0, shapeEmpty = 0, shapeEqual = 0
        var shapeOther: [String] = []
        var shapePartial: [String] = []
        var idsOutside: [String] = []
        var colourModesSampled = 0, dscListSampled = 0, unsafeListSampled = 0
        var headerBelowPrinted: [String] = []
        var dsc0Pairs = 0
        var dsc0Members: [String] = []
        var downstreamModes = 0, downstreamNot420: [String] = []
        var downstreamNodes = Set<String>()
        var drivenDownstreamNodes = Set<String>(), drivenDownstreamModes = 0
        var virtualAtFFFF = 0, virtualElsewhere: [String] = [], realAtFFFF: [String] = [], realElsewhere = 0
        var dpUnsafePairs = 0
        var dpUnsafeMembers: [String] = []
        var drivenCaptured = 0

        for folder in folders.sorted() {
            guard let records = CorpusDisplayProbes.externalNodes(folder: folder) else { continue }
            nodesWithTables += records.count
            for record in records {
                let nodeTag = "\(folder) \(record.node.edidKey)"
                let drivenID = record.node.currentTimingID
                if record.node.currentTiming != nil { drivenCaptured += 1 }
                for (entryIndex, dict) in CorpusDisplayProbes.timingDictionaries(record).enumerated() {
                    timingsSeen += 1
                    guard let timing = DisplayTimingReader.parseTiming(dict) else {
                        // Ruling 45's identity: every raw entry is parsed or named. The named ones are the
                        // entries the 64 KB cut truncates (no ID or no totals).
                        let entryTag = "\(nodeTag) entry \(entryIndex) ID \((dict["ID"] as? NSNumber)?.intValue.description ?? "absent") keys \(dict.keys.sorted().prefix(6))"
                        unparsed.append(entryTag)
                        // The cut-entry signature: the 64 KB cut leaves an entry with no ID or without
                        // its totals. An entry that carries its ID and both totals and still fails to
                        // parse is a parser gap, never a cut.
                        let hasTotals = (dict["HorizontalAttributes"] as? [String: Any])?["Total"] != nil
                            && (dict["VerticalAttributes"] as? [String: Any])?["Total"] != nil
                        if dict["ID"] != nil && hasTotals { unparsedNotCut.append(entryTag) }
                        continue
                    }
                    timingsParsed += 1
                    let tag = "\(nodeTag) timing \(timing.id)"
                    let isDriven = drivenID == timing.id

                    // Sampled headers: count them, and check the header never undercounts.
                    let cmSampled = CorpusDisplayProbes.listSampled(dict, "ColorModes")
                    let dscSampled = CorpusDisplayProbes.listSampled(dict, "DSCRequiredColorElementIDs")
                    let unsafeSampled = CorpusDisplayProbes.listSampled(dict, "UnsafeColorElementIDs")
                    if cmSampled { colourModesSampled += 1 }
                    if dscSampled { dscListSampled += 1 }
                    if unsafeSampled { unsafeListSampled += 1 }
                    for key in ["ColorModes", "DSCRequiredColorElementIDs", "UnsafeColorElementIDs"] {
                        if let count = CorpusDisplayProbes.listCount(dict, key),
                           let printed = (dict[key] as? [Any])?.count, count < printed {
                            headerBelowPrinted.append("\(tag) \(key): header \(count) below printed \(printed)")
                        }
                    }

                    // ValidPixelEncodings: 0xffffffff exactly when the timing is virtual.
                    if let virtualFlag = (dict["IsVirtual"] as? NSNumber), CFGetTypeID(virtualFlag) == CFBooleanGetTypeID(),
                       let vpe = timing.validPixelEncodings {
                        switch (virtualFlag.boolValue, vpe == 0xffffffff) {
                        case (true, true): virtualAtFFFF += 1
                        case (true, false): virtualElsewhere.append("\(tag) virtual at \(String(vpe, radix: 16))")
                        case (false, true): realAtFFFF.append("\(tag) real at 0xffffffff")
                        case (false, false): realElsewhere += 1
                        }
                    }

                    // DownstreamFormat, every parsed colour mode.
                    for colour in timing.colourModes where colour.downstreamFormat != nil {
                        downstreamModes += 1
                        downstreamNodes.insert(nodeTag)
                        if colour.downstreamFormat?.encoding != .ycbcr420 {
                            downstreamNot420.append("\(tag) mode \(colour.id) downstream encoding \(colour.downstreamFormat!.encoding.rawValue)")
                        }
                        if isDriven { drivenDownstreamModes += 1; drivenDownstreamNodes.insert(nodeTag) }
                    }

                    // The shape rule and the SupportsDSC = 0 rule: unsampled DSC list, complete unsampled ColorModes.
                    // Every parsed timing lands in exactly one of: sampled skip, incomplete (named), tested.
                    guard !dscSampled, !cmSampled else { shapeSampledSkipped += 1; continue }
                    guard timing.colourModesComplete, let rawList = timing.dscRequiredList else {
                        incomplete.append("\(tag): ColorModes complete \(timing.colourModesComplete), DSC list \(timing.dscRequiredList == nil ? "unreadable" : "read"), unsafe list \(timing.unsafeList == nil ? "unreadable" : "read")")
                        continue
                    }
                    shapeTested += 1
                    let listed = Set(rawList)
                    let allIDs = Set(timing.colourModes.map(\.id))
                    let capableAll = Set(timing.colourModes.filter(\.isDSCCapable).map(\.id))
                    if !listed.isSubset(of: allIDs) { idsOutside.append("\(tag): listed \(listed.subtracting(allIDs).sorted()) not among the colour modes") }
                    if listed.isEmpty {
                        shapeEmpty += 1
                    } else if listed == capableAll {
                        shapeEqual += 1
                    } else if listed.isSubset(of: capableAll) {
                        // A PARTIAL list: some DSC-capable modes need compression on this
                        // link and others do not. Legitimate, and a shape the rule once missed.
                        // The named case: m2ultra_macos27.0_c timing 91, list [102] against
                        // capable [1, 96, 100, 101, 102]. Mode 102 is the node's only 10-bit
                        // mode; 1, 96, 100 and 101 are all 8-bit. 10-bit costs about 25% more
                        // bandwidth, so the 8-bit modes fit this link uncompressed and the
                        // 10-bit one does not. Naming just that mode is correct.
                        shapePartial.append("\(tag): list \(listed.sorted()) against capable \(capableAll.sorted())")
                    } else {
                        shapeOther.append("\(tag): list \(listed.sorted()) against capable \(capableAll.sorted())")
                    }
                    for colour in timing.colourModes where !colour.isDSCCapable {
                        dsc0Pairs += 1
                        if listed.contains(colour.id) { dsc0Members.append("\(tag) mode \(colour.id)") }
                    }
                }
            }

            // Native DisplayPort is never unsafe: over the paired nodes whose port carries no HDMI/DVI/VGA sink.
            for pairing in CorpusDisplayProbes.pairings(folder: folder) {
                let sink = pairing.entry.port.dfpType?.uppercased() ?? ""
                guard !(sink.contains("HDMI") || sink.contains("DVI") || sink.contains("VGA")) else { continue }
                for dict in CorpusDisplayProbes.timingDictionaries(pairing.record) {
                    guard !CorpusDisplayProbes.listSampled(dict, "UnsafeColorElementIDs"),
                          let timing = DisplayTimingReader.parseTiming(dict), let unsafe = timing.unsafeList else { continue }
                    dpUnsafePairs += timing.colourModes.count
                    if !unsafe.isEmpty { dpUnsafeMembers.append("\(folder) \(pairing.record.node.edidKey) timing \(timing.id): \(unsafe)") }
                }
            }
        }

        print("DisplayTimingReaderProbeSweep/statement: \(nodesWithTables) nodes with tables; \(timingsSeen) timings seen, \(timingsParsed) parsed, \(unparsed.count) unparsed (named), \(drivenCaptured) driven captured; shape tested \(shapeTested) (sampled skips \(shapeSampledSkipped), incomplete \(incomplete.count)): empty \(shapeEmpty), equal \(shapeEqual), partial \(shapePartial.count), other \(shapeOther.count), IDs outside \(idsOutside.count); SKIP sampled: ColorModes \(colourModesSampled), DSC list \(dscListSampled), unsafe list \(unsafeListSampled); SupportsDSC=0 pairs \(dsc0Pairs), members \(dsc0Members.count); DownstreamFormat modes \(downstreamModes) on \(downstreamNodes.count) nodes (\(downstreamNot420.count) not 4:2:0), on driven timings \(drivenDownstreamModes) modes on \(drivenDownstreamNodes.count) nodes; ValidPixelEncodings virtual@ffffffff \(virtualAtFFFF), virtual elsewhere \(virtualElsewhere.count), real@ffffffff \(realAtFFFF.count), real elsewhere \(realElsewhere); native-DP unsafe pairs \(dpUnsafePairs), members \(dpUnsafeMembers.count)")
        for line in shapePartial { print("  PARTIAL \(line)") }
        for line in shapeOther { print("  SHAPE \(line)") }
        for line in idsOutside { print("  OUTSIDE \(line)") }
        for line in dsc0Members { print("  DSC0 MEMBER \(line)") }
        for line in downstreamNot420 { print("  DOWNSTREAM \(line)") }
        for line in virtualElsewhere + realAtFFFF { print("  VPE \(line)") }
        for line in dpUnsafeMembers { print("  DP UNSAFE \(line)") }
        for line in headerBelowPrinted { print("  HEADER \(line)") }
        for line in unparsed { print("  UNPARSED \(line)") }
        for line in incomplete { print("  INCOMPLETE \(line)") }

        // Pair references: research/displays/display-node-keys.md. The run prints every total;
        // the assertions below hold the per-item rules and the accounting, never the totals,
        // which move with the corpus. Re-derive figures from a run, never copy them.
        #expect(timingsParsed > 0, "no timing parsed: checked at least one")
        // A list may be empty, the whole DSC-capable set, or a subset of it. What it may
        // never be is a list naming a mode that is not DSC-capable: that would contradict
        // SupportsDSC, which `dsc0Members` below asserts separately over every pair.
        #expect(shapeOther.isEmpty, "\(shapeOther.count) timings with a list naming a mode outside the DSC-capable set:\n\(shapeOther.joined(separator: "\n"))")
        // A partial list is a legitimate shape (see where it is collected), so the corpus may
        // hold any number of them. What must not happen is the named case vanishing by
        // regression: if the reader stopped marking modes 1, 96, 100 and 101 DSC-capable,
        // timing 91's list would equal the capable set and reclassify as shapeEqual. So the
        // named case (one fixture folder) must stay partial.
        #expect(shapePartial.contains { $0.contains("m2ultra_macos27.0_c") && $0.contains("timing 91") }, "the known partial list, m2ultra_macos27.0_c timing 91 (its only 10-bit mode, where the other DSC-capable modes are 8-bit), is no longer partial; got \(shapePartial)")
        #expect(idsOutside.isEmpty, "\(idsOutside.count) lists naming an ID no colour mode carries")
        #expect(dsc0Members.isEmpty, "\(dsc0Members.count) SupportsDSC=0 modes in a DSC list, over \(dsc0Pairs) pairs")
        #expect(downstreamNot420.isEmpty, "\(downstreamModes) downstream formats, \(downstreamNot420.count) not 4:2:0")
        #expect(virtualElsewhere.isEmpty, "virtual timings off 0xffffffff: \(virtualElsewhere.count)")
        #expect(realAtFFFF.isEmpty, "real timings at 0xffffffff: \(realAtFFFF.count)")
        #expect(dpUnsafeMembers.isEmpty, "native DP unsafe members: \(dpUnsafeMembers.count) over \(dpUnsafePairs) pairs")
        #expect(headerBelowPrinted.isEmpty, "a sampled header undercounting its printed items:\n\(headerBelowPrinted.joined(separator: "\n"))")
        #expect(shapeEmpty + shapeEqual + shapePartial.count + shapeOther.count == shapeTested, "every tested timing is classified")
        // Ruling 45's identities for a whole-corpus sweep: the raw totals come from the loader, not from
        // production; what guards the parse is the accounting.
        #expect(unparsed.count == timingsSeen - timingsParsed, "every raw entry is parsed or named")
        // Every rejected entry must be a cut entry (no ID or no totals), never an entry the parser could
        // have read. How many cut entries the corpus holds is not a property of the parser.
        #expect(unparsedNotCut.isEmpty, "\(unparsedNotCut.count) rejected raw entries that carry an ID and both totals, so they are not cut entries:\n\(unparsedNotCut.joined(separator: "\n"))")
        #expect(incomplete.isEmpty, "\(incomplete.count) parsed timings with an unreadable table or list (ruling 20):\n\(incomplete.joined(separator: "\n"))")
        #expect(shapeTested + shapeSampledSkipped + incomplete.count == timingsParsed, "every parsed timing is tested, a sampled skip, or named incomplete")
    }

    /// The panel's top mode against the node's non-virtual timings, on every
    /// paired node, twice: the declared top (the resolver without the
    /// statement, today's behaviour) and the resolved top (ruling 41's step
    /// 1b, the resolver with the statement). Outcomes: exact (the #661 rule),
    /// same refresh at another blanking, picture at other refreshes only, not
    /// listed. Every node whose top changed between the two is printed with
    /// both tops, so the 20 nodes ruling 38 measured (a scaler entry above
    /// the panel's native picture) are named and their new outcome read off
    /// the line. PR #665 gate fix round 3, Claude F1: `nodeLists` now also
    /// keeps a picture-only candidate whose source is the tiled composite or
    /// a DisplayID timing (the native declarations of 5K, 6K and 5120x1440
    /// panels). Measured at 272bc49f: every count and every CHANGED line
    /// identical before and after, 0 tops moved, because the source clause
    /// then applied to picture-only candidates alone. Fix round 4 (item 2)
    /// extended it to a native declaration the node lists nowhere, and that
    /// moved exactly one node, the Odyssey G85SB's 2560x1440 @ 175 Hz
    /// DisplayID entry on `m1pro_macos26.5.2_x` block 1, named at the
    /// expectations below with the sampling caveat. The withdrawn "largest
    /// picture by area" rule moved the LS49AG95 (`m4_macos26.5.2_b`) to a
    /// not-offered 4K120 top; see `nodeLists`. Sampling: the probe samples every external node's
    /// `TimingElements` (231 of 231 paired nodes on 2026-09-21), but
    /// on external panels the non-virtual timings sit in the unsampled
    /// `PreferredTimingElements` (1 to 7 per node); the sweep prints how many
    /// nodes carry a non-virtual timing among the printed `TimingElements`
    /// (6), because on those a negative outcome could in principle hide in
    /// the unprinted entries.
    ///
    /// The invariant: a node driven at the resolved top (picture and refresh
    /// within 0.5 Hz) must match `exact` or `sameRefresh`, never picture-only
    /// or not listed. Below-top nodes are counted by outcome and named.
    @Test("Sweep: the top mode against the node's own timings, by outcome, before and after ruling 41, on every eligible node")
    func topModeMatchesTheNodeByOutcome() throws {
        guard let corpus = CorpusDisplayProbes.accountCorpus() else {
            return // corpus absent: the private CI's corpus-presence check owns that failure
        }
        var paired = 0
        var atTop = 0, atTopExact = 0, atTopSameRefresh = 0
        var atTopViolations: [String] = []
        var belowTop = 0, belowExact = 0, belowSameRefresh = 0
        var belowPictureOnly: [String] = [], belowNotListed: [String] = []
        var changedTop: [String] = []
        var beforeNotListed = 0
        var declaredListed = 0
        var listedButMoved: [String] = []
        var unlistedNotNative: [String] = []
        var noDeclaredTop = 0
        var nonVirtualInTimingElements = 0
        var nonVirtualCounts: [Int] = []

        func label(_ top: DisplayDiagnostic.TopMode) -> String {
            "\(top.width)x\(top.height) @ \((top.refreshHz * 1000).rounded() / 1000) Hz (\(top.sourceDescription))"
        }

        for pairing in corpus.attached {
            let folder = pairing.folder
            guard let statement = pairing.matched.drivenTiming, let current = pairing.matched.currentMode else { continue }
            paired += 1
            nonVirtualCounts.append(statement.allTimings.count)
            let timingElementIDs = Set((pairing.record.props["TimingElements"] as? [[String: Any]] ?? []).compactMap { ($0["ID"] as? NSNumber)?.intValue })
            if statement.allTimings.contains(where: { timingElementIDs.contains($0.id) }) { nonVirtualInTimingElements += 1 }
            guard let declared = DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: pairing.entry.edid),
                  let top = DisplayDiagnostic.resolveTopMode(maxMode: nil, edid: pairing.entry.edid, statement: statement)
            else { noDeclaredTop += 1; continue }
            let declaredMatch = statement.topModeMatch(width: declared.width, height: declared.height, refreshHz: declared.refreshHz, pixelClockHz: declared.pixelClockHz, interlaced: declared.interlaced)
            if declaredMatch.kind == .notListed { beforeNotListed += 1 }
            let match = statement.topModeMatch(width: top.width, height: top.height, refreshHz: top.refreshHz, pixelClockHz: top.pixelClockHz, interlaced: top.interlaced)
            let nodeList = statement.allTimings.map { "\($0.width)x\($0.height)@\(($0.refreshHz * 1000).rounded() / 1000)" }
            let tag = "\(folder) block \(pairing.entry.block) \(pairing.record.node.edidKey): top \(label(top)), node lists \(nodeList)"
            // Ruling 41, per node. (a) A declared top the node lists at its own refresh is
            // vouched for, so step 1b keeps it: the top moves only off a declared top the node
            // lists at other refreshes only, or nowhere. (b) Only a native declaration (the EDID's
            // preferred picture, the tiled composite, a DisplayID timing) may stay the top while
            // the node lists it nowhere; anything else unlisted must give way to a listed entry.
            switch declaredMatch {
            case .exact, .sameRefresh:
                declaredListed += 1
                if declared != top { listedButMoved.append("\(tag): declared \(label(declared)) is listed [\(declaredMatch.kind)] yet the top moved") }
            case .pictureOnly, .notListed:
                break
            }
            if match.kind == .notListed {
                let preferred = pairing.entry.edid.preferredMode
                let isPreferredPicture = preferred.map { $0.width == top.width && $0.height == top.height } ?? false
                let isNative = pairing.entry.edid.modes.contains { DisplayDiagnostic.TopMode(declared: $0) == top && DisplayDiagnostic.isNativeDeclaration($0) }
                if !(isPreferredPicture || isNative) { unlistedNotNative.append("\(tag): the node lists the top nowhere and it is not a native declaration") }
            }
            if declared != top {
                changedTop.append("\(folder) block \(pairing.entry.block) \(pairing.record.node.edidKey): declared \(label(declared)) [\(declaredMatch.kind)] -> resolved \(label(top)) [\(match.kind)], driven \(current.label), node lists \(nodeList)")
            }
            let drivenAtTop = current.width == top.width && current.height == top.height && abs(current.refreshHz - top.refreshHz) <= 0.5
            if drivenAtTop {
                atTop += 1
                switch match {
                case .exact: atTopExact += 1
                case .sameRefresh: atTopSameRefresh += 1
                case .pictureOnly, .notListed: atTopViolations.append("\(tag): driven at the top yet \(match.kind)")
                }
            } else {
                belowTop += 1
                switch match {
                case .exact: belowExact += 1
                case .sameRefresh: belowSameRefresh += 1
                case .pictureOnly: belowPictureOnly.append(tag)
                case .notListed: belowNotListed.append(tag)
                }
            }
        }

        let meanNonVirtual = nonVirtualCounts.isEmpty ? 0 : Double(nonVirtualCounts.reduce(0, +)) / Double(nonVirtualCounts.count)
        print("DisplayTimingReaderProbeSweep/top-mode \(corpus.summary)")
        for failure in corpus.failures { print("  FAILURE \(failure)") }
        print("DisplayTimingReaderProbeSweep/top-mode: \(paired) paired nodes with a statement; non-virtual timings per node \(nonVirtualCounts.min() ?? 0) to \(nonVirtualCounts.max() ?? 0), mean \(String(format: "%.2f", meanNonVirtual)); \(nonVirtualInTimingElements) nodes with a non-virtual timing among the printed TimingElements; no declared top \(noDeclaredTop); declared top listed at its refresh on \(declaredListed) (moved \(listedButMoved.count)); unlisted tops that are not native \(unlistedNotNative.count); before ruling 41 the declared top was not listed on \(beforeNotListed) nodes; the resolved top differs from the declared top on \(changedTop.count); at the top \(atTop): exact \(atTopExact), same refresh \(atTopSameRefresh), violations \(atTopViolations.count); below the top \(belowTop): exact \(belowExact), same refresh \(belowSameRefresh), picture only \(belowPictureOnly.count), not listed \(belowNotListed.count)")
        for line in changedTop { print("  CHANGED \(line)") }
        for line in atTopViolations { print("  VIOLATION \(line)") }
        for line in belowPictureOnly { print("  PICTURE ONLY \(line)") }
        for line in belowNotListed { print("  NOT LISTED \(line)") }

        // Ruling 45: the population first. The loader computed it from the raw probes; production
        // match attached it; every eligible node is attached or named.
        #expect(paired > 0, "no paired node: checked at least one. \(corpus.summary)")
        #expect(corpus.unnamedFailures.isEmpty, "eligible nodes production match did not attach and knownExceptions does not name:\n\(corpus.unnamedFailures.map(\.description).joined(separator: "\n"))")
        #expect(corpus.attached.count == corpus.eligible - CorpusDisplayProbes.knownExceptions.count, "attached \(corpus.attached.count) is not eligible \(corpus.eligible) minus the \(CorpusDisplayProbes.knownExceptions.count) known exceptions")
        #expect(paired == corpus.attached.count, "every attached node carries a statement and a live mode")
        // No pair figure: a new question. The run prints every outcome count and names every
        // CHANGED, PICTURE ONLY and NOT LISTED node; the assertions below hold the per-node rules
        // and the bucket identities, never the totals, which move with the corpus.
        // PR #665 gate fix round 4, item 2 (measured at 2404c8f4): a native declaration the node lists
        // nowhere now stays the top and reads not listed, and exactly one node moves, the Odyssey
        // G85SB on `m1pro_macos26.5.2_x` block 1: its declared top, a DisplayID Type I 2560x1440 @
        // 174.967 Hz above the native 3440x1440, is listed nowhere in the capture (node lists
        // 3440x1440@59.959, 1920x1080@59.94, 1920x1080@60.0, 3440x1440@119.961), so it is now the
        // resolved top (notListed) instead of the listed 3440x1440 @ 119.961 Hz (exact). Its verdict
        // is unknownMode before and after (its colour reading is unresolved, so the (d) sentence
        // prints, not K26); the top, the match and the facts are what moved. Sampling caveat: the
        // probe caps every array at 12 entries, and this node's TimingElements (28 of its 40 timings
        // outside the capture) and its driven ColorModes table are sampled, so "listed nowhere" here
        // may be the capture's truncation rather than the node's statement; a live read is never
        // sampled.
        #expect(noDeclaredTop == 0, "\(noDeclaredTop) attached nodes with no declared top")
        // The before/after relationship, per node (see the switch in the loop): a declared top the
        // node lists at its refresh never moves, and only a native declaration stays the top while the
        // node lists it nowhere.
        #expect(listedButMoved.isEmpty, "\(listedButMoved.count) nodes whose declared top the node lists at its refresh, yet ruling 41 moved the top:\n\(listedButMoved.joined(separator: "\n"))")
        #expect(unlistedNotNative.isEmpty, "\(unlistedNotNative.count) nodes whose resolved top the node lists nowhere and which is not a native declaration:\n\(unlistedNotNative.joined(separator: "\n"))")
        #expect(changedTop.count + belowNotListed.count >= beforeNotListed, "every node whose declared top the node never listed must resolve elsewhere or be named not listed: \(beforeNotListed) were not listed, \(changedTop.count) changed, \(belowNotListed.count) kept as not listed")
        #expect(atTopViolations.isEmpty, "\(atTopViolations.count) nodes driven at the top whose top the node does not list:\n\(atTopViolations.joined(separator: "\n"))")
        // Every node lands in exactly one outcome bucket on its side of the top.
        #expect(atTopExact + atTopSameRefresh + atTopViolations.count == atTop, "at the top \(atTop) is not exact \(atTopExact) + same refresh \(atTopSameRefresh) + violations \(atTopViolations.count)")
        #expect(belowExact + belowSameRefresh + belowPictureOnly.count + belowNotListed.count == belowTop, "below the top \(belowTop) is not exact \(belowExact) + same refresh \(belowSameRefresh) + picture only \(belowPictureOnly.count) + not listed \(belowNotListed.count)")
        #expect(atTop + belowTop + noDeclaredTop == paired, "every paired node is classified")
    }
}
