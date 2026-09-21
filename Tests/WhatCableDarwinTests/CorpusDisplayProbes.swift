import Foundation
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

// MARK: - Shared corpus probe readers for the display slice (probes 26 and 33)
//
// `DisplayTimingReaderProbeSweepTests` and `DisplayDiagnosticProbeSweepTests`
// pair the same population (every external display node with tables, to its
// DisplayPort node by EDID key) and must count it the same way, so the parser
// and the pairing live here, the `CorpusPowerProbes.swift` precedent.
//
// BEFORE CHANGING THE PARSER, read `research/corpus-parser-traps.md`, entry
// 13 in particular: probe 26 prints a long array as `Key = [N] (sampled)` and
// then only its first twelve entries. The header count is the truth and the
// printed lines are a subset. This parser keeps both beside the items:
//   dict[key]              the printed items ([[String: Any]] for `{ ... }`
//                          items, [NSNumber] / [String] for scalar items)
//   dict[key + "#count"]   NSNumber, the header's N
//   dict[key + "#sampled"] NSNumber(Bool), true when the header says (sampled)
// Production readers ask for none of the sidecar keys. A sweep that tests
// membership excludes sampled lists and prints how many it excluded.
//
// Rendering: `--- <class> "<name>" (entryID=...) ---` opens a node; its body
// is `KEY = VALUE` lines at any indent, `{` opening a nested dictionary closed
// by a bare `}`, and `[N]` or `[N] (sampled)` opening a list whose `{ ... }`
// items become dictionaries and whose scalar lines (`90 (0x5a)`, `"disp0"`)
// become NSNumber / String. The flat rendering (no `--- ` headers, booleans
// as `<type 21>`) is not readable here and those folders count as absent.

enum CorpusDisplayProbes {

    // MARK: Corpus root

    static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    static func loadOutput(folder: String, file: String) -> String? {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: Probe 26 tree parser

    struct ParsedNode {
        let className: String
        let props: [String: Any]
    }

    private static let keyValue = try! NSRegularExpression(pattern: "^([A-Za-z0-9_ .-]+?) = (.*)$")
    private static let listHeader = try! NSRegularExpression(pattern: "^\\[(\\d+)\\]( \\(sampled\\))?$")

    static func listCount(_ dict: [String: Any], _ key: String) -> Int? {
        (dict[key + "#count"] as? NSNumber)?.intValue
    }

    static func listSampled(_ dict: [String: Any], _ key: String) -> Bool {
        (dict[key + "#sampled"] as? NSNumber)?.boolValue == true
    }

    static func parseNodes(text: String) -> [ParsedNode] {
        let lines = text.components(separatedBy: "\n")
        let starts = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("--- ") }
        var nodes: [ParsedNode] = []
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : lines.count
            let header = lines[start].trimmingCharacters(in: .whitespaces)
            let className = header.dropFirst(4).split(separator: " ").first.map(String.init) ?? ""
            var i = start + 1
            let props = parseBlock(lines, &i, end: end)
            nodes.append(ParsedNode(className: className, props: props))
        }
        return nodes
    }

    private static func isKeyLine(_ s: String) -> Bool {
        keyValue.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func parseBlock(_ lines: [String], _ i: inout Int, end: Int) -> [String: Any] {
        var dict: [String: Any] = [:]
        while i < end {
            let s = lines[i].trimmingCharacters(in: .whitespaces)
            if s.isEmpty { i += 1; continue }
            if s == "}" || s == "}," { return dict }
            if s.hasPrefix("--- ") || s.hasPrefix("=== ") { return dict }
            guard let m = keyValue.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let keyRange = Range(m.range(at: 1), in: s),
                  let valueRange = Range(m.range(at: 2), in: s)
            else { i += 1; continue }
            let key = String(s[keyRange])
            let value = String(s[valueRange])
            if value == "{" {
                i += 1
                dict[key] = parseBlock(lines, &i, end: end)
                if i < end, ["}", "},"].contains(lines[i].trimmingCharacters(in: .whitespaces)) { i += 1 }
                continue
            }
            if let header = listHeader.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) {
                let countRange = Range(header.range(at: 1), in: value)!
                dict[key + "#count"] = NSNumber(value: Int(value[countRange]) ?? 0)
                dict[key + "#sampled"] = NSNumber(value: header.range(at: 2).location != NSNotFound)
                i += 1
                var dictionaryItems: [[String: Any]] = []
                var scalarItems: [Any] = []
                while i < end {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t == "{" {
                        i += 1
                        dictionaryItems.append(parseBlock(lines, &i, end: end))
                        if i < end, ["}", "},"].contains(lines[i].trimmingCharacters(in: .whitespaces)) { i += 1 }
                        continue
                    }
                    // The list ends at the next key line, a closing brace, a
                    // node header or a blank line; anything else is a scalar item.
                    if t.isEmpty || t == "}" || t == "}," || t.hasPrefix("--- ") || t.hasPrefix("=== ") || isKeyLine(t) { break }
                    scalarItems.append(scalar(t))
                    i += 1
                }
                dict[key] = dictionaryItems.isEmpty ? scalarItems : dictionaryItems
                continue
            }
            dict[key] = scalar(value)
            i += 1
        }
        return dict
    }

    private static func scalar(_ value: String) -> Any {
        if value == "true" { return NSNumber(value: true) }
        if value == "false" { return NSNumber(value: false) }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        let head = value.split(separator: " ", maxSplits: 1).first.map(String.init) ?? value
        if let n = Int(head) { return NSNumber(value: n) }
        return value
    }

    // MARK: Probe 33 blocks

    static func parseDPNode33Blocks(text: String) -> [[String: Any]] {
        guard let regex = try? NSRegularExpression(pattern: "=== DisplayPort node \\[\\d+\\] ===") else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var blocks: [[String: Any]] = []
        for (i, match) in matches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < matches.count ? matches[i + 1].range.lowerBound : nsText.length
            let body = nsText.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
            blocks.append(parseEqualsProps(body: body))
        }
        return blocks
    }

    private static func parseEqualsProps(body: String) -> [String: Any] {
        var props: [String: Any] = [:]
        var metadata: [String: Any] = [:]
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.hasPrefix("  "), !s.hasPrefix("   ") else { continue }
            let stripped = String(s.dropFirst(2))
            if stripped.hasPrefix("Metadata.EDID = ") {
                // `<N bytes serial-redacted> HEX` (the `serial-redacted` word is absent on older captures).
                let rest = String(stripped.dropFirst("Metadata.EDID = ".count))
                if let angle = rest.range(of: "> "), let data = hexFromString(String(rest[angle.upperBound...])) {
                    props["EDID"] = data
                }
                continue
            }
            if stripped.hasPrefix("Metadata.") {
                if let (key, val) = parseEqualsLine(String(stripped.dropFirst("Metadata.".count))) { metadata[key] = val }
                continue
            }
            if stripped.hasPrefix("---") { continue }
            if let (key, val) = parseEqualsLine(stripped) { props[key] = val }
        }
        if !metadata.isEmpty { props["Metadata"] = metadata }
        return props
    }

    private static func parseEqualsLine(_ stripped: String) -> (String, Any)? {
        guard let eqRange = stripped.range(of: " = ") else { return nil }
        let key = String(stripped[..<eqRange.lowerBound])
        let valStr = String(stripped[eqRange.upperBound...])
        if valStr == "(absent)" || valStr == "(redacted)" { return nil }
        if valStr.hasPrefix("<") || valStr.hasPrefix("{") { return nil }
        if valStr == "true" { return (key, NSNumber(value: true)) }
        if valStr == "false" { return (key, NSNumber(value: false)) }
        if valStr.hasPrefix("\""), valStr.hasSuffix("\""), valStr.count >= 2 {
            return (key, String(valStr.dropFirst().dropLast()))
        }
        if let spaceIdx = valStr.firstIndex(of: " "), let v = Int(valStr[..<spaceIdx]) { return (key, NSNumber(value: v)) }
        if let v = Int(valStr) { return (key, NSNumber(value: v)) }
        return nil
    }

    static func hexFromString(_ s: String) -> Data? {
        let hex = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0, !hex.isEmpty else { return nil }
        var data = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let byte = UInt8(hex[i..<j], radix: 16) else { return nil }
            data.append(byte)
            i = j
        }
        return data
    }

    struct ActivePort {
        let block: Int
        let port: IOPortTransportStateDisplayPort
        let edid: EDIDInfo
    }

    /// Every active probe-33 block of a folder as the production model, EDID
    /// bytes attached, so `MonitorInfo.edid` carries what the match keys on.
    static func activePorts(folder: String) -> [ActivePort] {
        guard let text = loadOutput(folder: folder, file: "33_displayport_capability.json") else { return [] }
        var out: [ActivePort] = []
        for (i, props) in parseDPNode33Blocks(text: text).enumerated() {
            guard (props["Active"] as? NSNumber)?.boolValue == true,
                  let data = props["EDID"] as? Data, let edid = EDIDInfo(data),
                  let update = DisplayPortTransportWatcher.makeUpdate(
                      entryID: UInt64(i), read: { props[$0] }, portIndex: 0, portType: "USB-C", hpmControllerUUID: nil)
            else { continue }
            out.append(ActivePort(block: i, port: update.status, edid: edid))
        }
        return out
    }

    // MARK: Probe 26 nodes and the pairing

    struct NodeRecord {
        let className: String
        let props: [String: Any]
        let node: DisplayTimingReader.Node
    }

    /// Every external node with a `TimingElements` list in a folder's probe 26,
    /// parsed by the production reader. nil when the file is absent; a node
    /// the reader rejects (no UUID key) is left out, which the caller counts
    /// against the raw `parseNodes` total if it needs to.
    static func externalNodes(folder: String) -> [NodeRecord]? {
        guard let text = loadOutput(folder: folder, file: "26_displayport_altmode.json") else { return nil }
        var records: [NodeRecord] = []
        for parsed in parseNodes(text: text) {
            guard (parsed.props["external"] as? NSNumber)?.boolValue == true,
                  parsed.props["TimingElements"] != nil,
                  let node = DisplayTimingReader.parseNode(read: { parsed.props[$0] })
            else { continue }
            records.append(NodeRecord(className: parsed.className, props: parsed.props, node: node))
        }
        return records
    }

    /// The raw timing dictionaries of a node, both lists, in the order the
    /// production reader reads them.
    static func timingDictionaries(_ record: NodeRecord) -> [[String: Any]] {
        let timings = (record.props["TimingElements"] as? [[String: Any]] ?? [])
            + (record.props["PreferredTimingElements"] as? [[String: Any]] ?? [])
        return timings
    }

    /// The raw dictionary of the driven timing, when the capture holds it.
    static func drivenTimingDictionary(_ record: NodeRecord) -> [String: Any]? {
        guard let id = record.node.currentTimingID else { return nil }
        return timingDictionaries(record).first { ($0["ID"] as? NSNumber)?.intValue == id }
    }

    struct Pairing {
        let folder: String
        let entry: ActivePort
        let matched: IOPortTransportStateDisplayPort
        let record: NodeRecord
    }

    // MARK: The population (ruling 45)

    /// The loader's own copy of the key rule: EDID bytes 8 to 24 with the
    /// four serial bytes zeroed, hex, dashed as the node's `EDID UUID`
    /// spells it. Deliberately not `DisplayTimingReader.edidKey`: the
    /// population must not move when production's rule does, and a
    /// disagreement between the two is a named failure below.
    static func edidKey(_ edid: Data) -> String? {
        let bytes = [UInt8](edid)
        guard bytes.count >= 24 else { return nil }
        var field = Array(bytes[8..<24])
        for i in 4..<8 { field[i] = 0 }
        let hex = field.map { String(format: "%02X", $0) }.joined()
        let h = Array(hex)
        return String(h[0..<8]) + "-" + String(h[8..<12]) + "-" + String(h[12..<16]) + "-" + String(h[16..<20]) + "-" + String(h[20..<32])
    }

    struct ActiveBlock {
        let block: Int
        let edid: Data
        let props: [String: Any]
    }

    /// Every probe-33 block with `Active = true` and an EDID, raw: before
    /// `makeUpdate` or `EDIDInfo` get a say. `block` is the index in the
    /// file, the same index `ActivePort.block` carries.
    static func activeBlocks(folder: String) -> [ActiveBlock] {
        guard let text = loadOutput(folder: folder, file: "33_displayport_capability.json") else { return [] }
        var out: [ActiveBlock] = []
        for (i, props) in parseDPNode33Blocks(text: text).enumerated() {
            guard (props["Active"] as? NSNumber)?.boolValue == true, let data = props["EDID"] as? Data else { continue }
            out.append(ActiveBlock(block: i, edid: data, props: props))
        }
        return out
    }

    struct Eligible {
        let record: NodeRecord
        let block: ActiveBlock
    }

    struct Population {
        /// External nodes with tables whose driven entry the probe captured
        /// and whose key exactly one active block carries.
        let eligible: [Eligible]
        /// Captured, but no active block carries the key (probe 33 absent,
        /// or the panel's block inactive).
        let noBlock: [NodeRecord]
        /// Captured, but two or more active blocks carry the key: the
        /// identical-panel pairs, told apart by nothing the loader keys on.
        let severalBlocks: [(record: NodeRecord, blocks: Int)]
        /// External nodes with tables the production parser rejected (no
        /// `EDID UUID` or `IOMFBUUID`): unkeyable, so never eligible.
        let noKey: Int
        var captured: Int { eligible.count + noBlock.count + severalBlocks.count }
    }

    /// Ruling 45: the eligible population, from the raw probes and the
    /// loader's key rule, with no production `match` involved. A node is
    /// eligible when it is external with tables, the raw timing dictionaries
    /// hold an entry whose `ID` is its `DPTimingModeId`, and exactly one
    /// active probe-33 block's EDID gives its key.
    static func population(folder: String) -> Population {
        guard let text = loadOutput(folder: folder, file: "26_displayport_altmode.json") else {
            return Population(eligible: [], noBlock: [], severalBlocks: [], noKey: 0)
        }
        let blocks = activeBlocks(folder: folder)
        var eligible: [Eligible] = [], noBlock: [NodeRecord] = [], several: [(record: NodeRecord, blocks: Int)] = []
        var noKey = 0
        for parsed in parseNodes(text: text) {
            guard (parsed.props["external"] as? NSNumber)?.boolValue == true, parsed.props["TimingElements"] != nil else { continue }
            guard let node = DisplayTimingReader.parseNode(read: { parsed.props[$0] }) else { noKey += 1; continue }
            let record = NodeRecord(className: parsed.className, props: parsed.props, node: node)
            guard let drivenID = (parsed.props["DPTimingModeId"] as? NSNumber)?.intValue,
                  timingDictionaries(record).contains(where: { ($0["ID"] as? NSNumber)?.intValue == drivenID })
            else { continue }
            let carrying = blocks.filter { edidKey($0.edid) == node.edidKey }
            switch carrying.count {
            case 0: noBlock.append(record)
            case 1: eligible.append(Eligible(record: record, block: carrying[0]))
            default: several.append((record: record, blocks: carrying.count))
            }
        }
        return Population(eligible: eligible, noBlock: noBlock, severalBlocks: several, noKey: noKey)
    }

    struct Failure: CustomStringConvertible {
        let folder: String
        let edidKey: String
        let block: Int
        let reason: String
        var description: String { "\(folder) block \(block) \(edidKey): \(reason)" }
    }

    struct Accounting {
        let population: Population
        let attached: [Pairing]
        let failures: [Failure]
    }

    /// Production `DisplayTimingReader.match` over the folder's active ports
    /// and nodes, then every eligible node accounted for: attached (the port
    /// whose block carries the node's key came back with that node's driven
    /// lists and clock) or a named failure. Nothing eligible is dropped
    /// silently, which is what lets the sweeps assert the population.
    static func account(folder: String) -> Accounting {
        let pop = population(folder: folder)
        guard !pop.eligible.isEmpty else { return Accounting(population: pop, attached: [], failures: []) }
        let ports = activePorts(folder: folder)
        let records = externalNodes(folder: folder) ?? []
        let matched = DisplayTimingReader.match(ports: ports.map(\.port), nodes: records.map(\.node))
        var attached: [Pairing] = []
        var failures: [Failure] = []
        for eligible in pop.eligible {
            let record = eligible.record
            guard let index = ports.firstIndex(where: { $0.block == eligible.block.block }) else {
                let why = EDIDInfo(eligible.block.edid) == nil ? "EDID unparsed by EDIDInfo" : "probe-33 block unreadable by makeUpdate"
                failures.append(Failure(folder: folder, edidKey: record.node.edidKey, block: eligible.block.block, reason: why))
                continue
            }
            let entry = ports[index]
            let port = matched[index]
            if let timing = record.node.currentTiming, let statement = port.drivenTiming,
               statement.driven == timing.lists, port.currentMode?.pixelClockHz == timing.pixelClockHz {
                attached.append(Pairing(folder: folder, entry: entry, matched: port, record: record))
                continue
            }
            failures.append(Failure(folder: folder, edidKey: record.node.edidKey, block: eligible.block.block,
                                    reason: reason(for: record, entry: entry, records: records)))
        }
        return Accounting(population: pop, attached: attached, failures: failures)
    }

    /// Why production `match` did not attach an eligible node, in the order
    /// `match` itself decides them.
    private static func reason(for record: NodeRecord, entry: ActivePort, records: [NodeRecord]) -> String {
        guard let timing = record.node.currentTiming else { return "driven timing unparseable by parseTiming" }
        guard timing.pixelClockHz != nil else { return "interlaced driven timing (no clock)" }
        if DisplayTimingReader.edidKey(from: entry.port.monitor?.edid ?? Data()) != record.node.edidKey {
            return "production's key differs from the loader's for this EDID"
        }
        let sharing = records.filter { $0.node.edidKey == record.node.edidKey && $0.node.currentTiming != nil }.count
        if sharing > 1 { return "key shared by \(sharing) nodes in the folder; port serial \(entry.port.monitor?.serialNumber ?? 0)" }
        if let portSerial = entry.port.monitor?.serialNumber, portSerial != 0,
           let nodeSerial = record.node.serialNumber, nodeSerial != 0, nodeSerial != portSerial {
            return "serial disagrees (port \(portSerial), node \(nodeSerial))"
        }
        return "match declined for a reason this loader does not name (read DisplayTimingReader.match)"
    }

    /// Eligible nodes production `match` is known not to attach, each with
    /// its reason, dated. A failure not on this list fails the sweep with
    /// the node named. Measured 2026-09-21 with a replica of `match` over the
    /// corpus: 231 eligible, 231 attached, none to list. Add a line here only
    /// with the reason read off the sweep's FAILURE print, never to make a
    /// run green.
    static let knownExceptions: [(folder: String, edidKey: String, reason: String)] = []

    struct CorpusAccounting {
        let folders: Int
        let captured: Int
        let eligible: Int
        let noBlock: Int
        let severalBlocks: Int
        let noKey: Int
        let attached: [Pairing]
        let failures: [Failure]
        /// Failures `knownExceptions` does not name.
        var unnamedFailures: [Failure] {
            failures.filter { f in !CorpusDisplayProbes.knownExceptions.contains { $0.folder == f.folder && $0.edidKey == f.edidKey } }
        }
        var summary: String {
            "population: \(folders) folders, \(captured) captured driven timings, \(eligible) eligible (\(noBlock) with no active block carrying the key, \(severalBlocks) with several, \(noKey) unkeyable nodes), attached \(attached.count), failures \(failures.count), known exceptions \(CorpusDisplayProbes.knownExceptions.count)"
        }
    }

    /// `account(folder:)` over the whole corpus. nil when the corpus is
    /// absent (scripts/ci.sh's presence check owns that failure).
    static func accountCorpus() -> CorpusAccounting? {
        guard let folders = try? FileManager.default.contentsOfDirectory(atPath: probeRoot.path) else { return nil }
        var captured = 0, eligible = 0, noBlock = 0, several = 0, noKey = 0
        var attached: [Pairing] = [], failures: [Failure] = []
        for folder in folders.sorted() {
            let accounting = account(folder: folder)
            captured += accounting.population.captured
            eligible += accounting.population.eligible.count
            noBlock += accounting.population.noBlock.count
            several += accounting.population.severalBlocks.count
            noKey += accounting.population.noKey
            attached += accounting.attached
            failures += accounting.failures
        }
        return CorpusAccounting(folders: folders.count, captured: captured, eligible: eligible, noBlock: noBlock,
                                severalBlocks: several, noKey: noKey, attached: attached, failures: failures)
    }

    /// The attached pairings of one folder.
    static func pairings(folder: String) -> [Pairing] { account(folder: folder).attached }
}
