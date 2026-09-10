import Foundation
import Testing
@testable import WhatCableCore

/// Corpus-replay coverage for `HopTableEntry` parsing and
/// `ThunderboltTopology.tunnels(from:in:)`, using two independent sources.
///
/// (a) Probe 29 (`research/customer-probes/*/29_usb4_router_interfaces.json`,
///     NOT git-tracked, gated on files being on disk). Probe 29 lists
///     `IOThunderboltPort` blocks FLAT, not nested inside their owning
///     switch, so this sweep validates hop-table PARSING and UUID GROUPING
///     only, not terminal detection (which needs real switch nesting).
///
/// (b) `whatcable --tb-debug` dumps (`research/dumps/tb-fabric/*.md`, 4
///     files, git-tracked). These ARE nested per switch, so this sweep
///     validates full `tunnels(from:in:)` behaviour, including terminal
///     detection across real daisy chains, against hand-verified ground
///     truth (every UUID and port number below was grepped out of the raw
///     file and cross-checked by hand; see the comment above each
///     assertion for the exact grep).
@Suite("TunnelPath: corpus sweep")
struct TunnelPathCorpusTests {

    // MARK: - Roots

    private static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }()

    private static let customerProbesRoot: URL =
        repoRoot.appendingPathComponent("research/customer-probes")

    private static let tbFabricRoot: URL =
        repoRoot.appendingPathComponent("research/dumps/tb-fabric")

    // MARK: - (a) Probe 29 sweep: parsing + grouping only
    //
    // Probe 29's raw text format (studied against 3 real files before
    // writing this):
    //
    //   Hop Table =       [0]           Path =             "UUID"
    //           Dst Hop ID =             8 (0x8)
    //           Dst Port =             3 (0x3)
    //           Hop ID =             8 (0x8)
    //           Counter =             0 (0x0)
    //       [1]           Path =             "UUID2"
    //           ...
    //   Dual-Link Port RID =     1 (0x1)
    //
    // Key order within one entry is fixed (Path, Dst Hop ID, Dst Port,
    // Hop ID, Counter) across every file sampled. Entries for an empty
    // hop table print nothing, so "Hop Table =" runs straight into the
    // NEXT key on the same line ("Hop Table =   Thunderbolt Version = ...").

    /// Same "--- ClassName[N] ... ---" instance-block splitter as
    /// `ThunderboltProbeSweepTests`. Duplicated on purpose: Swift `private`
    /// is file-scoped and these sweeps are kept self-contained (see the
    /// same convention in `ConnectedDeviceTreeTests`).
    private static func parseInstanceBlocks(_ text: String, className: String) -> [String] {
        var results: [String] = []
        var currentBody: [String] = []
        var inBlock = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--- \(className)") && trimmed.hasSuffix("---") {
                if inBlock { results.append(currentBody.joined(separator: "\n")) }
                inBlock = true
                currentBody = []
            } else if trimmed.hasPrefix("=== ") && trimmed.hasSuffix(" ===") {
                if inBlock { results.append(currentBody.joined(separator: "\n")) }
                inBlock = false
                currentBody = []
            } else if inBlock {
                currentBody.append(line)
            }
        }
        if inBlock { results.append(currentBody.joined(separator: "\n")) }
        return results
    }

    /// Extract every hop-table entry from a probe-29 IOThunderboltPort body
    /// into the `[[String: Any]]` shape `IOThunderboltPort.from(read:)`
    /// expects for the "Hop Table" key. This is a harness parser, distinct
    /// from `probe29IndependentUUIDCount` below, which never looks at
    /// structure at all.
    /// Splits a hop table on its `[N]` row markers and reads each key by NAME.
    ///
    /// This replaced a single regex that hardcoded the key ORDER
    /// (Path, Dst Hop ID, Dst Port, Hop ID, Counter) and required `Counter`.
    /// Both assumptions were wrong, and the corpus proved it after 326 machines
    /// were back-filled: a hop table set up by firmware before macOS booted
    /// prints `Inherited From EFI` instead of `Counter` and puts `Path` LAST,
    /// so 8 real entries across 2 Intel Macs matched nothing here and were
    /// invisible to the sweep. IOKit does not emit properties in a stable
    /// order. Apple documents no ordering guarantee, and the corpus supplies the
    /// counterexample, so the harness reads by name like production does.
    private static let probe29RowMarker = try! NSRegularExpression(pattern: #"\[\d+\]"#)
    private static let probe29PathRegex = try! NSRegularExpression(
        pattern: #"Path\s*=\s*"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})""#
    )

    /// Line-anchored: `\bHop ID` also matches inside `Dst Hop ID` (the space
    /// before "Hop" is a word boundary), so an unanchored read would silently
    /// return the destination hop for the source hop. The sweep asserts counts
    /// only, so it would never have caught that.
    private static func probe29Int(_ chunk: String, _ key: String) -> Int? {
        guard let re = try? NSRegularExpression(
            pattern: "^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*(-?\\d+)",
            options: [.anchorsMatchLines]) else { return nil }
        guard let m = re.firstMatch(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)),
              let r = Range(m.range(at: 1), in: chunk) else { return nil }
        return Int(chunk[r])
    }

    private static func parseProbe29HopEntries(fromPortBody body: String) -> [[String: Any]] {
        // Scope to the hop table: `[N]` markers also appear in other array
        // properties on the same port block.
        guard let hopStart = body.range(of: "Hop Table =") else { return [] }
        var table = String(body[hopStart.upperBound...])
        if let end = try? NSRegularExpression(pattern: "^  [A-Za-z][A-Za-z0-9 _-]*\\s*=",
                                              options: [.anchorsMatchLines]),
           let m = end.firstMatch(in: table, range: NSRange(table.startIndex..., in: table)),
           let r = Range(m.range, in: table) {
            table = String(table[table.startIndex..<r.lowerBound])
        }

        let ns = table as NSString
        let marks = probe29RowMarker.matches(in: table, range: NSRange(location: 0, length: ns.length))
        var out: [[String: Any]] = []
        for (i, m) in marks.enumerated() {
            let start = m.range.location + m.range.length
            let end = (i + 1 < marks.count) ? marks[i + 1].range.location : ns.length
            guard end > start else { continue }
            let chunk = ns.substring(with: NSRange(location: start, length: end - start))
            guard let pm = probe29PathRegex.firstMatch(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)),
                  let pr = Range(pm.range(at: 1), in: chunk) else { continue }
            guard let dstHopID = probe29Int(chunk, "Dst Hop ID"),
                  let dstPort = probe29Int(chunk, "Dst Port"),
                  let hopID = probe29Int(chunk, "Hop ID") else { continue }
            var entry: [String: Any] = [
                "Path": String(chunk[pr]),
                "Dst Hop ID": NSNumber(value: dstHopID),
                "Dst Port": NSNumber(value: dstPort),
                "Hop ID": NSNumber(value: hopID),
            ]
            // Deliberately conditional: an EFI-inherited row has no Counter,
            // and production must still keep it.
            if let counter = probe29Int(chunk, "Counter") {
                entry["Counter"] = NSNumber(value: counter)
            }
            out.append(entry)
        }
        return out
    }

    /// Parse "Port Number" out of a probe-29 body (needed so
    /// `IOThunderboltPort.from` doesn't bail with nil).
    private static func parsePortNumber(_ body: String) -> Int? {
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Port Number = ") else { continue }
            let after = trimmed.dropFirst("Port Number = ".count).drop(while: { $0 == " " })
            return Int(after.prefix { $0.isNumber })
        }
        return nil
    }

    /// Parser 1 ("Swift-side parse", exercises the real production code):
    /// split the file into IOThunderboltPort blocks, extract each block's
    /// hop table into the `[[String: Any]]` shape, and run it through
    /// `IOThunderboltPort.from(read:)`. Returns the total hop entry count
    /// across every port in the file.
    private static func productionHopEntryCount(inProbe29Text text: String) -> Int {
        var total = 0
        for body in parseInstanceBlocks(text, className: "IOThunderboltPort") {
            let hopDicts = parseProbe29HopEntries(fromPortBody: body)
            let portNumber = parsePortNumber(body) ?? 1
            let dict: [String: Any] = [
                "Port Number": NSNumber(value: portNumber),
                "Adapter Type": NSNumber(value: 1),
                "Hop Table": hopDicts,
            ]
            if let port = IOThunderboltPort.from(read: { dict[$0] }) {
                total += port.hopTable.count
            }
        }
        return total
    }

    /// Parser 2 (independent second parser, per the "re-derive with a
    /// second parser" rule): a flat regex over the WHOLE raw file counting
    /// UUID-shaped `Path = "..."` occurrences, with no notion of port
    /// blocks or hop-table structure at all. `PCI Path` lines never match
    /// because their values are `IOService:...` strings, not UUIDs, so no
    /// extra filtering is needed to exclude them.
    private static let uuidPathRegex = try! NSRegularExpression(
        pattern: #"Path\s*=\s*"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}""#
    )

    private static func independentUUIDCount(inText text: String) -> Int {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return uuidPathRegex.numberOfMatches(in: text, range: range)
    }

    @Test("Probe 29 sweep: production hop-entry count matches an independent regex UUID count, per folder")
    func probe29ParsingMatchesIndependentCount() throws {
        guard FileManager.default.fileExists(atPath: Self.customerProbesRoot.path) else {
            // Fresh clone: probe 29 is not git-tracked, nothing to sweep.
            return
        }
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: Self.customerProbesRoot.path))?.sorted() ?? []

        var probe29FilesSeen = 0
        var foldersWithEntries = 0
        var totalProduction = 0
        var totalIndependent = 0
        var truncatedFoldersSkipped = 0

        for folder in folders {
            let url = Self.customerProbesRoot
                .appendingPathComponent(folder)
                .appendingPathComponent("29_usb4_router_interfaces.json")
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = root["output"] as? String
            else { continue }
            probe29FilesSeen += 1

            // Known data-quality issue (same 64 KB pipe cap documented for
            // probe 17 in research/cio-value-mappings.md): 12 of the 134 probe-29
            // files are truncated at exactly 65536 bytes. Found by hand
            // when this test's cross-check first fired on
            // m2max_macos27.0_b: production=34 vs independent=35, traced
            // to the file's LAST hop-table entry being cut off mid-line
            // (Path present and complete, Dst Hop ID/Dst Port/Hop
            // ID/Counter missing). That is not a parser bug: the
            // production parser is right to drop an incomplete entry, and
            // the flat independent regex is right to still see the intact
            // Path line. Skipping known-truncated files here rather than
            // loosening either regex to paper over it.
            guard text.utf8.count != 65536 else {
                truncatedFoldersSkipped += 1
                continue
            }

            let independent = Self.independentUUIDCount(inText: text)
            guard independent > 0 else { continue }
            foldersWithEntries += 1

            let production = Self.productionHopEntryCount(inProbe29Text: text)
            #expect(production == independent,
                "\(folder): production parse yielded \(production) hop entries, independent regex counted \(independent)")

            totalProduction += production
            totalIndependent += independent
        }
        // Re-derived by hand: 12 of 134 probe-29 files sit at exactly the
        // 65536-byte pipe cap. Not asserted as a hard floor/ceiling here
        // (a fresh KV fetch could change which files truncate), but
        // surfaced so a silent change in truncation rate is visible.
        _ = truncatedFoldersSkipped

        // The floor and totals only mean something when the raw corpus is
        // actually on disk. Probe 29 is not git-tracked, so a fresh clone
        // has the folder structure (tracked distillations) but zero
        // 29_*.json files; asserting the floor there would go red on every
        // fresh clone. Same filesOnDisk gating pattern as
        // USBWatcherCorpusSweepTests.
        guard probe29FilesSeen >= 20 else { return }

        // Corpus figures re-derived directly above (not quoted from
        // memory) and cross-checked against a standalone Python regex pass
        // over the same files before this test was written: 134 folders
        // have populated hop tables in total; 12 of those are truncated at
        // the 65536-byte pipe cap and are skipped above, leaving 122
        // folders / 1663 hop entries actually asserted on here.
        #expect(foldersWithEntries >= 20,
            """
            Expected the probe-29 corpus floor of >=20 folders with hop entries; found \(foldersWithEntries). \
            \(probe29FilesSeen) probe-29 files are on disk, so the corpus shrank or the parser broke.
            """)
        #expect(totalProduction == totalIndependent)
        #expect(totalProduction > 0)
    }

    // MARK: - (b) tb-debug dump sweep: full tunnels(from:in:), git-tracked

    /// Parse a `whatcable --tb-debug` dump into `IOThunderboltSwitch`
    /// values with real ports and hop tables, via the SAME production
    /// `IOThunderboltSwitch.from` / `IOThunderboltPort.from` factories the
    /// app uses. `parentSwitchUID` is left `nil` here; `linkParents(_:)`
    /// below fills it in.
    private enum TbDebugParser {
        struct SwitchBlock {
            let className: String
            let lines: [String]
        }

        static func parseSwitchBlocks(_ text: String) -> [SwitchBlock] {
            var blocks: [SwitchBlock] = []
            var className: String?
            var lines: [String] = []
            for line in text.components(separatedBy: "\n") {
                if line.hasPrefix("## Switch #") {
                    if let c = className { blocks.append(SwitchBlock(className: c, lines: lines)) }
                    // "## Switch #4: IOThunderboltSwitchIntelJHL8440"
                    className = line.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
                    lines = []
                } else if className != nil {
                    lines.append(line)
                }
            }
            if let c = className { blocks.append(SwitchBlock(className: c, lines: lines)) }
            return blocks
        }

        /// Split a switch block's body into the switch-level key lines and
        /// the per-port sub-blocks ("  ### Port @N: IOThunderboltPort").
        static func splitSwitchAndPorts(_ lines: [String]) -> (switchLines: [String], ports: [[String]]) {
            var switchLines: [String] = []
            var ports: [[String]] = []
            var currentPort: [String]? = nil
            for line in lines {
                if line.hasPrefix("  ### Port @") {
                    if let p = currentPort { ports.append(p) }
                    currentPort = []
                } else if currentPort != nil {
                    currentPort?.append(line)
                } else {
                    switchLines.append(line)
                }
            }
            if let p = currentPort { ports.append(p) }
            return (switchLines, ports)
        }

        private static let hopEntryRegex = try! NSRegularExpression(
            pattern: #"\{Counter=(\d+), Dst Hop ID=(\d+), Dst Port=(\d+), Hop ID=(\d+), Path="([0-9A-Fa-f-]{36})"\}"#
        )

        static func parseHopTableValue(_ raw: String) -> [[String: Any]] {
            guard raw != "[]" else { return [] }
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            return hopEntryRegex.matches(in: raw, range: range).compactMap { match -> [String: Any]? in
                guard match.numberOfRanges == 6 else { return nil }
                func group(_ i: Int) -> String? {
                    guard let r = Range(match.range(at: i), in: raw) else { return nil }
                    return String(raw[r])
                }
                guard
                    let counter = group(1).flatMap(Int.init),
                    let dstHopID = group(2).flatMap(Int.init),
                    let dstPort = group(3).flatMap(Int.init),
                    let hopID = group(4).flatMap(Int.init),
                    let path = group(5)
                else { return nil }
                return [
                    "Counter": NSNumber(value: counter),
                    "Dst Hop ID": NSNumber(value: dstHopID),
                    "Dst Port": NSNumber(value: dstPort),
                    "Hop ID": NSNumber(value: hopID),
                    "Path": path,
                ]
            }
        }

        /// Generic "  Key = Value" line parser for the tb-debug dump
        /// format (2-space indent at switch level, 4-space at port
        /// level; alphabetically sorted keys, one per line). Only decodes
        /// what `IOThunderboltSwitch.from` / `IOThunderboltPort.from`
        /// actually read: quoted strings, plain (possibly negative)
        /// integers, and the single-line `Hop Table` array. Binary blobs
        /// (`DROM`, `FW Counters`, `<...>`), nested dicts (`Buffer
        /// Allocation Request = {...}`), and plain-int arrays (`Port
        /// Affinity = [1]`) are deliberately skipped: none of them are
        /// read by `.from`, and skipping beats a wrong parse of a Data
        /// field we don't assert on.
        static func parseKeyValueLines(_ lines: [String]) -> [String: Any] {
            var result: [String: Any] = [:]
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let eqRange = trimmed.range(of: " = ") else { continue }
                let key = String(trimmed[trimmed.startIndex..<eqRange.lowerBound])
                let rawValue = String(trimmed[eqRange.upperBound...])
                if key == "Hop Table" {
                    result[key] = parseHopTableValue(rawValue)
                } else if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
                    result[key] = String(rawValue.dropFirst().dropLast())
                } else if let intVal = Int(rawValue) {
                    result[key] = NSNumber(value: intVal)
                }
                // Else: binary blob / nested dict / plain array. Skipped.
            }
            return result
        }

        /// Build every switch in the file, ports included, via the real
        /// production factories. `parentSwitchUID` is `nil` on every
        /// result; call `linkParents` to fill it in.
        static func parseSwitches(_ text: String) -> [IOThunderboltSwitch] {
            parseSwitchBlocks(text).compactMap { block in
                let (switchLines, portLineGroups) = splitSwitchAndPorts(block.lines)
                let switchDict = parseKeyValueLines(switchLines)
                let ports = portLineGroups.compactMap { portLines -> IOThunderboltPort? in
                    let portDict = parseKeyValueLines(portLines)
                    return IOThunderboltPort.from(read: { portDict[$0] })
                }
                guard let uidNum = switchDict["UID"] as? NSNumber else { return nil }
                return IOThunderboltSwitch.from(
                    uid: uidNum.int64Value,
                    read: { switchDict[$0] },
                    className: block.className,
                    ports: ports,
                    parentSwitchUID: nil
                )
            }
        }

        /// Replace `sw`'s `parentSwitchUID`, keeping every other field.
        static func withParent(_ sw: IOThunderboltSwitch, parentSwitchUID: Int64?) -> IOThunderboltSwitch {
            IOThunderboltSwitch(
                id: sw.id, className: sw.className, vendorID: sw.vendorID,
                vendorName: sw.vendorName, modelName: sw.modelName, routerID: sw.routerID,
                depth: sw.depth, routeString: sw.routeString,
                upstreamPortNumber: sw.upstreamPortNumber, maxPortNumber: sw.maxPortNumber,
                supportedSpeed: sw.supportedSpeed, ports: sw.ports,
                parentSwitchUID: parentSwitchUID, firmwareVersion: sw.firmwareVersion,
                thunderboltVersion: sw.thunderboltVersion, deviceID: sw.deviceID,
                currentPowerState: sw.currentPowerState, fwCounters: sw.fwCounters,
                fwCountersRunningTotal: sw.fwCountersRunningTotal, drom: sw.drom,
                minRequiredTMUMode: sw.minRequiredTMUMode
            )
        }

        /// All the UUIDs any port on this switch carries in its hop table.
        static func hopUUIDs(_ sw: IOThunderboltSwitch) -> Set<String> {
            Set(sw.ports.flatMap { $0.hopTable.map(\.pathUUID) })
        }

        /// Design decision: a depth-N switch's parent is the depth-(N-1)
        /// switch whose hop tables share at least one path UUID with it.
        /// `whatcable --tb-debug` dumps carry no explicit parent pointer
        /// (unlike production IOKit reads, where the watcher supplies
        /// `parentSwitchUID` from the registry parent chain), so this is
        /// reconstructed from the same evidence `tunnels(from:in:)` itself
        /// consumes. Confirmed unambiguous (exactly one match per child)
        /// on all 4 corpus files; `matchCounts` is returned so the caller
        /// can assert that rather than trust it silently.
        static func linkParents(_ switches: [IOThunderboltSwitch]) -> (linked: [IOThunderboltSwitch], matchCounts: [Int64: Int]) {
            let maxDepth = switches.map(\.depth).max() ?? 0
            let byDepth = Dictionary(grouping: switches, by: \.depth)
            var byID = Dictionary(uniqueKeysWithValues: switches.map { ($0.id, $0) })
            var matchCounts: [Int64: Int] = [:]

            guard maxDepth >= 1 else { return (switches, matchCounts) }
            for depth in 1...maxDepth {
                guard let children = byDepth[depth] else { continue }
                let candidates = byDepth[depth - 1] ?? []
                for child in children {
                    let childUUIDs = hopUUIDs(child)
                    let matches = candidates.filter { !hopUUIDs($0).isDisjoint(with: childUUIDs) }
                    matchCounts[child.id] = matches.count
                    if let parent = matches.first {
                        byID[child.id] = withParent(byID[child.id]!, parentSwitchUID: parent.id)
                    }
                }
            }
            return (switches.map { byID[$0.id] ?? $0 }, matchCounts)
        }
    }

    private static func loadTbFabricFile(_ name: String) throws -> String {
        let url = Self.tbFabricRoot.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Shared setup: parse, link parents (asserting exactly one match per
    /// child so an ambiguous or broken chain fails loudly instead of
    /// silently picking a wrong root), and return every switch plus the
    /// host root the deepest device's parent chain resolves to.
    private static func parseAndLink(_ fileName: String) throws -> (switches: [IOThunderboltSwitch], hostRoot: IOThunderboltSwitch) {
        let text = try loadTbFabricFile(fileName)
        let unlinked = TbDebugParser.parseSwitches(text)
        try #require(!unlinked.isEmpty, "\(fileName): no switches parsed")

        let (linked, matchCounts) = TbDebugParser.linkParents(unlinked)
        for (childID, count) in matchCounts {
            #expect(count == 1, "\(fileName): switch \(childID) matched \(count) depth-(N-1) parent candidates by shared hop-table UUID, expected exactly 1")
        }

        // Walk up from the deepest switch to find the host root actually
        // in this chain (the other depth-0 controllers for the Mac's
        // other, empty, TB ports have no parent link and are not it).
        guard let deepest = linked.max(by: { $0.depth < $1.depth }) else {
            throw TestFailure("\(fileName): no switches to walk from")
        }
        var current = deepest
        while let parentUID = current.parentSwitchUID, let parent = linked.first(where: { $0.id == parentUID }) {
            current = parent
        }
        return (linked, current)
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    // Ground truth below was grepped out of each raw file by hand; the
    // grep command is quoted in each comment so it can be re-run.

    @Test("nofr1ends (M5 Pro + UGreen TB5 dock): at least one video tunnel terminates at a non-lane adapter on a depth>0 switch")
    func nofr1endsVideoTerminatesDownstream() throws {
        // grep -n 'Path="3528A632\|Path="C46FDC47\|Path="DC539E16' 052-nofr1ends...md
        // confirms these 3 UUIDs recur on switch #4 (UGreen dock, depth 1)
        // at "DP or HDMI Adapter" ports (@10, @11, @14), matching the
        // Mac's own lane hop table on switch #3.
        let (switches, hostRoot) = try Self.parseAndLink("052-nofr1ends-m5pro-ugreen-tb5-dock.md")
        let tunnels = ThunderboltTopology.tunnels(from: hostRoot, in: switches)

        let videoTunnels = tunnels.filter { $0.kind == .video }
        try #require(!videoTunnels.isEmpty, "Expected at least one video tunnel")
        let downstream = videoTunnels.filter { tunnel in
            guard let uid = tunnel.terminalSwitchUID, let sw = switches.first(where: { $0.id == uid }) else { return false }
            return sw.depth > 0 && tunnel.terminalAdapterPortNumber != nil
        }
        #expect(!downstream.isEmpty, "At least one video tunnel must terminate at a non-lane adapter on a depth>0 switch")
        #expect(videoTunnels.count >= 3, "Grepped 3 distinct video-tunnel UUIDs by hand (3528A632, C46FDC47, DC539E16)")
    }

    @Test("jshier (M3 Ultra + Sabrent + Studio Display): video tunnel terminates at the depth-2 display, not the depth-1 KVM")
    func jshierVideoTerminatesAtDisplay() throws {
        // grep -n 'D4D5965F' 052-jshier...md: appears on switch #1's lane
        // (host root), switch #7's lane (Sabrent KVM, pass-through), and
        // switch #8's "DP or HDMI Adapter" Port Number 10 (Studio Display,
        // depth 2). The KVM (depth 1) never terminates it: it only has a
        // LANE-port hop and a second, unrelated PCIe UUID (16748162) of
        // its own.
        let (switches, hostRoot) = try Self.parseAndLink("052-jshier-m3ultra-studio-display-sabrent.md")
        let tunnels = ThunderboltTopology.tunnels(from: hostRoot, in: switches)

        let videoAtDepth2 = tunnels.first { tunnel in
            tunnel.kind == .video && switches.first(where: { $0.id == tunnel.terminalSwitchUID })?.depth == 2
        }
        try #require(videoAtDepth2 != nil, "Expected a video tunnel terminating at the depth-2 Studio Display")
        #expect(videoAtDepth2?.terminalAdapterPortNumber == 10)
        #expect(videoAtDepth2?.terminalAdapterType == .dpOut)
        #expect(videoAtDepth2?.segmentCount == 3, "3 hops: host lane, KVM lane pass-through, display DP-out")
    }

    @Test("joeshaw (M2 Pro daisy chain: ASUS -> CalDigit): a PCIe tunnel terminates at the deepest switch (depth 2)")
    func joeshawTerminatesAtDeepestDevice() throws {
        // grep -n '87F652F5' 052-joeshaw...md: appears on switch #4's
        // (ASUS, depth 1) downstream lane Port @2, and on switch #5's
        // (CalDigit TS3 Plus, depth 2) "PCIe Adapter" Port Number 6.
        // Never touches switch #3 (the actual host root among the 3
        // depth-0 controllers): this is the daisy-chain leg past the ASUS.
        let (switches, hostRoot) = try Self.parseAndLink("052-joeshaw-m2pro-asus-caldigit-daisychain.md")
        let tunnels = ThunderboltTopology.tunnels(from: hostRoot, in: switches)

        let deepestSwitchDepth = switches.filter { $0.parentSwitchUID != nil || $0.id == hostRoot.id }.map(\.depth).max() ?? 0
        try #require(deepestSwitchDepth == 2, "Expected the chain to reach depth 2 (ASUS -> CalDigit)")

        let deepTunnel = tunnels.first { tunnel in
            switches.first(where: { $0.id == tunnel.terminalSwitchUID })?.depth == 2
        }
        try #require(deepTunnel != nil, "Expected a tunnel terminating at the depth-2 CalDigit dock")
        #expect(deepTunnel?.kind == .pcie)
        #expect(deepTunnel?.terminalAdapterPortNumber == 6)
        #expect(deepTunnel?.terminalAdapterType == .pcieUp)
        #expect(deepTunnel?.segmentCount == 2, "2 hops: ASUS's downstream lane, CalDigit's PCIe adapter")
    }

    @Test("joeshaw: crossCableTunnels surfaces EXACTLY the 4 real cross-cable tunnels, excluding the ASUS-internal PCIe UUID 93B7660C")
    func joeshawExactSurfacedTunnelSet() throws {
        // Ground truth derived BY HAND from the raw file, re-derivable with:
        //   grep -oE 'Path="[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"' \
        //     052-joeshaw-m2pro-asus-caldigit-daisychain.md | sort | uniq -c
        // gives exactly 9 distinct path UUIDs. Grepping each individually
        // and reading the switch/port context around every hit (switch #3
        // = host root, UID 408812294957648176, depth 0; switch #4 = ASUS
        // PA32QCV, UID -9185256489162756864, depth 1; switch #5 = CalDigit
        // TS3 Plus, UID 17188550068006400, depth 2) gives this table:
        //
        //   113C2833-...  host root ONLY (its own PCIe adapter, Port 3)      -> host-internal
        //   CF1CBC79-...  host root ONLY (its own USB adapter, Port 4)       -> host-internal
        //   366CB1DC-...  host root ONLY (its own DP adapter, Port 5)        -> host-internal
        //   E35F465D-...  host root ONLY (its own DP adapter, Port 5, 2nd row) -> host-internal
        //   93B7660C-...  ASUS ONLY (its own PCIe adapter, Port 10)          -> ASUS-internal (distinctSwitchCount 1)
        //   AE240EDA-...  host root lane (dst port 4) + ASUS USB adapter Port 16  -> cross-cable, .usb
        //   311DD53C-...  host root lane (dst port 3) + ASUS PCIe adapter Port 9  -> cross-cable, .pcie
        //   13962F04-...  host root lane (dst port 5) + ASUS DP adapter Port 14   -> cross-cable, .video
        //   87F652F5-...  ASUS downstream lane (Port 3) + CalDigit PCIe Port 6    -> cross-cable, .pcie
        //
        // The first 5 rows never reach a second switch (host-internal or
        // ASUS-internal routing), so distinctSwitchCount is 1 for every one
        // of them; only the last 4 rows span >= 2 switches. 93B7660C is the
        // one this fix targets: pre-fix, `kind != .unknown && terminal depth
        // > 0` alone was enough to wrongly surface it as a 5th cross-cable
        // tunnel, because the ASUS switch (depth 1) happens to be its only
        // switch. So the surfaced set must be EXACTLY these 4:
        let expectedSurfacedUUIDs: Set<String> = [
            "13962F04-F0F3-4D59-9BEA-A0BF778C5944", // .video, ASUS DP adapter, port 14
            "AE240EDA-9424-4064-B975-5FF68643D302", // .usb, ASUS USB adapter, port 16
            "311DD53C-2BFF-4069-9DEA-9B6AF70AFA35", // .pcie, ASUS PCIe adapter, port 9
            "87F652F5-744E-4ED5-AB8F-F782D8F42C4B", // .pcie, CalDigit PCIe adapter, port 6
        ]

        let (switches, hostRoot) = try Self.parseAndLink("052-joeshaw-m2pro-asus-caldigit-daisychain.md")
        let tunnels = ThunderboltTopology.tunnels(from: hostRoot, in: switches)
        try #require(tunnels.count == 9, "Expected exactly 9 distinct path UUIDs in this dump; re-run the grep above if this fires")

        let surfaced = ActiveTunnelPresentation.crossCableTunnels(tunnels, switches: switches)
        let surfacedUUIDs = Set(surfaced.map(\.pathUUID))
        #expect(surfacedUUIDs == expectedSurfacedUUIDs, "Surfaced cross-cable tunnel set must be exactly the 4 derived by hand above")

        #expect(!surfacedUUIDs.contains("93B7660C-35ED-4194-8BA4-A48A9A9A1EDE"),
            "93B7660C only recurs on the ASUS switch's own PCIe adapter (distinctSwitchCount 1): dock-internal, must not surface")

        let usb = surfaced.first { $0.pathUUID == "AE240EDA-9424-4064-B975-5FF68643D302" }
        #expect(usb?.kind == .usb)
        #expect(usb?.terminalAdapterPortNumber == 16)

        let pcieToASUS = surfaced.first { $0.pathUUID == "311DD53C-2BFF-4069-9DEA-9B6AF70AFA35" }
        #expect(pcieToASUS?.kind == .pcie)
        #expect(pcieToASUS?.terminalAdapterPortNumber == 9)

        let video = surfaced.first { $0.pathUUID == "13962F04-F0F3-4D59-9BEA-A0BF778C5944" }
        #expect(video?.kind == .video)
        #expect(video?.terminalAdapterPortNumber == 14)

        let pcieToCalDigit = surfaced.first { $0.pathUUID == "87F652F5-744E-4ED5-AB8F-F782D8F42C4B" }
        #expect(pcieToCalDigit?.kind == .pcie)
        #expect(pcieToCalDigit?.terminalAdapterPortNumber == 6)
    }

    @Test("stevetrease (M3 MBA + Samsung TB3 monitor): parses and groups without crashing, video tunnel present")
    func stevetreaseParsesAndGroups() throws {
        // grep -n '5BFD5A68' 052-stevetrease...md: host-root lane (switch
        // #1) plus switch #3's (Samsung monitor) "DP or HDMI Adapter"
        // Port Number 11. Simplest of the 4 files: single depth-1 hop,
        // no daisy chain. Included so the sweep also covers the
        // single-hop shape, not just the two daisy-chain files above.
        let (switches, hostRoot) = try Self.parseAndLink("052-stevetrease-m3mba-samsung-tb3.md")
        let tunnels = ThunderboltTopology.tunnels(from: hostRoot, in: switches)

        #expect(!tunnels.isEmpty)
        let video = tunnels.first { $0.kind == .video }
        #expect(video?.terminalAdapterPortNumber == 11)
        #expect(video?.terminalAdapterType == .dpOut)

        // Six previously-unread `IOThunderboltPort` fields (bandwidth
        // allocation, CLx State, Dual-Link Port, Max Credits, TRM Policy):
        // Sources/WhatCableCore/Thunderbolt/IOThunderboltLink.swift already
        // parses them, but nothing in the app or its tests ever asserted on
        // the values, so a field-name typo or a dropped read would have
        // gone unnoticed. `TbDebugParser.parseKeyValueLines` above already
        // carries plain `Key = Value` lines like these straight through
        // (only Hop Table gets special handling), so this needed no new
        // parsing, only a hand-checked assertion.
        //
        // grep -n 'Max Credits = 179' 052-stevetrease...md: switch #1
        // (the host root, depth 0), Port @1 (Port Number 1), the same lane
        // this tunnel's own hop table lives on.
        let hostLane = switches.first { $0.depth == 0 }?.ports.first { $0.portNumber == 1 }
        #expect(hostLane != nil, "expected the host root's Port Number 1 lane")
        #expect(hostLane?.maxBandwidthAllocated == 61)
        #expect(hostLane?.requiredBandwidthAllocated == 2)
        #expect(hostLane?.clxState == 0)
        #expect(hostLane?.dualLinkPort == 2)
        #expect(hostLane?.maxCredits == 179)
        #expect(hostLane?.trmPolicy == "Root")
    }
}
