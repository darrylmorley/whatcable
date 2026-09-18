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
// All helpers are file-private copies; there is no shared corpus support file.

@Suite("DisplayTimingReader -- probe-26 corpus sweep")
struct DisplayTimingReaderProbeSweepTests {

    // MARK: - Corpus root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private static func loadOutput(folder: String, file: String) -> String? {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Probe 26 tree parser
    //
    // `--- <class> "<name>" (entryID=... parentEntryID=...) ---` opens a node;
    // its body is `KEY = VALUE` lines at any indent, `{` opening a nested
    // dictionary closed by a bare `}`, and `[N]` or `[N] (sampled)` opening a
    // list whose `{ ... }` items become dictionaries. Scalar list items
    // (`90 (0x5a)`, `"disp0,t8122"`) do not match the key pattern and are
    // skipped, exactly as the Python reference parser skips them. Numbers
    // become NSNumber, `true`/`false` NSNumber(Bool), `"text"` String,
    // anything else (`Data[32]: ...`, `set[2]`) the raw text.

    private struct ParsedNode {
        let className: String
        let props: [String: Any]
    }

    private static let keyValue = try! NSRegularExpression(pattern: "^([A-Za-z0-9_ .-]+?) = (.*)$")
    private static let listHeader = try! NSRegularExpression(pattern: "^\\[(\\d+)\\]( \\(sampled\\))?$")

    private static func parseNodes(text: String) -> [ParsedNode] {
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
            if listHeader.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
                i += 1
                var items: [[String: Any]] = []
                while i < end, lines[i].trimmingCharacters(in: .whitespaces) == "{" {
                    i += 1
                    items.append(parseBlock(lines, &i, end: end))
                    if i < end, ["}", "},"].contains(lines[i].trimmingCharacters(in: .whitespaces)) { i += 1 }
                }
                dict[key] = items
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

    // MARK: - Probe 33 side (file-private copies of the DisplayDiagnostic sweep's helpers)

    private static func parseDPNode33Blocks(text: String) -> [[String: Any]] {
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

    private static func hexFromString(_ s: String) -> Data? {
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

    private struct ActivePort {
        let block: Int
        let port: IOPortTransportStateDisplayPort
        let edid: EDIDInfo
    }

    /// Every active probe-33 block of a folder as the production model, EDID
    /// bytes attached, so `MonitorInfo.edid` carries what the match keys on.
    private static func activePorts(folder: String) -> [ActivePort] {
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

    // MARK: - The sweep

    @Test("Sweep: macOS's driven timing is a mode the EDID declares, on every node the corpus lets us pair")
    func drivenTimingIsADeclaredMode() throws {
        guard let folders = try? FileManager.default.contentsOfDirectory(atPath: Self.probeRoot.path) else {
            return // corpus absent: scripts/ci.sh's presence check owns that failure
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
        var mismatches: [String] = []
        var singleDepth = 0
        var nodesWithTiming = 0

        for folder in folders.sorted() {
            guard let text = Self.loadOutput(folder: folder, file: "26_displayport_altmode.json") else { continue }
            foldersWithProbe26 += 1
            var nodes: [DisplayTimingReader.Node] = []
            for parsed in Self.parseNodes(text: text) {
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

            let ports = Self.activePorts(folder: folder)
            let matched = DisplayTimingReader.match(ports: ports.map(\.port), nodes: nodes)
            // Nodes not yet claimed by an attached port. A port claims the
            // first unclaimed node with its key and the attached clock whose
            // serial does not contradict the port's, so two identical panels
            // at the same timing claim two nodes, and a node attached twice
            // (a match defect) is recorded rather than counted.
            var pool = nodes
            for (entry, port) in zip(ports, matched) {
                guard let mode = port.currentMode, let clock = mode.pixelClockHz else { continue }
                attachedPorts += 1
                let key = DisplayTimingReader.edidKey(from: entry.port.monitor?.edid ?? Data())
                let portSerial = entry.port.monitor?.serialNumber ?? 0
                if let index = pool.firstIndex(where: {
                    $0.edidKey == key && $0.currentTiming?.pixelClockHz == clock
                        && (portSerial == 0 || ($0.serialNumber ?? 0) == 0 || $0.serialNumber == portSerial)
                }) {
                    pool.remove(at: index)
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
                mismatches.append(tag + " is not among the EDID's \(entry.edid.modes.count) declared modes")
            }
            for node in pool {
                unpaired.append("\(folder) \(node.edidKey) serial \(node.serialNumber ?? 0): no single probe-33 block with that EDID identity")
            }
        }

        print("DisplayTimingReaderProbeSweep: \(foldersWithProbe26) folders with probe 26; \(nodesWithTables) external nodes with tables \(byClass); \(nodesWithTiming) with the current timing captured, \(notCaptured.count) not captured; \(attachedPorts) ports attached (\(claimedNodes) nodes claimed), \(unpaired.count) nodes unpaired; compared: \(comparedExact) exact, \(alternateRate.count) at the CTA alternate rate, \(mismatches.count) mismatches; \(singleDepth) timings with a single depth")
        for line in notCaptured { print("  NOT CAPTURED \(line)") }
        for line in unpaired { print("  UNPAIRED \(line)") }
        for line in alternateRate { print("  ALTERNATE RATE \(line)") }
        for line in mismatches { print("  MISMATCH \(line)") }

        // Coverage floors: a corpus that exists but yields little must not
        // pass quietly. Figures at the time of writing, re-derived by the
        // second parser (the research repo's scripts/display-timing-sweep.py):
        // 1352 folders with probe 26, 453 nodes (AppleCLCD2 143,
        // IOMobileFramebufferShim 310), 260 captured, 193 not, 238
        // attached, 22 unpaired, 235 exact, 3 alternate rate, 0 mismatches,
        // 104 single-depth timings.
        #expect(nodesWithTables >= 440, "only \(nodesWithTables) external nodes with tables; the corpus or the parser is near-empty")
        #expect((byClass["AppleCLCD2"] ?? 0) >= 100 && (byClass["IOMobileFramebufferShim"] ?? 0) >= 100,
            "both node classes must be in the corpus: \(byClass)")
        #expect(comparedExact >= 230, "only \(comparedExact) exact comparisons; expected at least 230")
        #expect(singleDepth >= 100, "only \(singleDepth) timings with a single depth")
        #expect(mismatches.isEmpty, "\(mismatches.count) driven timings the EDID does not declare:\n\(mismatches.joined(separator: "\n"))")
        #expect(attachedPorts == claimedNodes, "a port attached a timing no node explains: \(attachedPorts) ports for \(claimedNodes) nodes")
        #expect(comparedExact + alternateRate.count + mismatches.count == attachedPorts, "every attached port is compared")
        #expect(claimedNodes + unpaired.count == nodesWithTiming, "every captured node is attached or named unpaired")
        #expect(nodesWithTiming + notCaptured.count == nodesWithTables, "every node is accounted for")
    }
}
