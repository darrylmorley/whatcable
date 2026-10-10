import Foundation
import Testing
@testable import WhatCableDarwinBackend

/// Corpus-replay tests for `DisplayPortTransportWatcher.makeUpdate`.
///
/// These tests sweep every customer probe under `research/customer-probes/` and
/// call the `internal nonisolated static` parse function (`makeUpdate`) directly.
/// No IOKit required: the function accepts a `(String) -> Any?` closure, so we
/// build that closure from the text in the probe files.
///
/// Two probe sources are used:
///
/// - **Probe 17** (`17_deep_property_dump.json`): flat `--- IOPortTransportStateDisplayPort[N] ---`
///   blocks, `KEY: VALUE` colon format, 2-space indent. Covers 312 folders / 494 blocks
///   (as of 2026-07; see corpus.jsonl for the current corpus size) across all chip
///   generations, including inactive ports and HDMI-tunnelled displays. Best breadth.
///
/// - **Probe 33** (`33_displayport_capability.json`): dedicated DisplayPort probe,
///   `=== DisplayPort node [N] ===` blocks, `KEY = VALUE` equals format, 2-space indent.
///   204 folders / 322 blocks, 160 with an active display (as of 2026-07). Has
///   `Metadata.KEY` flat sub-keys so `ProductName` and `ManufacturerName` are accessible
///   without a nested dict. Best fidelity for monitor identity fields.
///
/// Fresh clones without the corpus trivially pass: probe 17 and 33 are gitignored raw
/// data (only `01_walk_pd_tree.json` is committed), so the missing-file guards return
/// empty collections and the guarded minimum-count assertions are skipped.
@Suite("DisplayPortTransportWatcher -- customer probe sweep")
struct DisplayPortTransportWatcherSweepTests {

    // MARK: - Corpus root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // MARK: - Folder enumeration

    private static func allProbeFolders() -> [String] {
        guard let entries = try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path) else { return [] }
        return entries.filter { entry in
            var isDir: ObjCBool = false
            let path = probeRoot.appendingPathComponent(entry).path
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted()
    }

    /// True when at least one folder has probe 17 or probe 33 files.
    /// In a fresh clone only `01_walk_pd_tree.json` is committed; the raw probes
    /// are gitignored and must be fetched from KV. Tests use this flag to skip
    /// minimum-count assertions rather than failing on a machine with no corpus.
    private static func hasDPProbeFiles() -> Bool {
        let folders = allProbeFolders()
        for folder in folders.prefix(10) {
            for probe in ["17_deep_property_dump", "33_displayport_capability"] {
                let url = probeRoot
                    .appendingPathComponent(folder)
                    .appendingPathComponent("\(probe).json")
                if FileManager.default.fileExists(atPath: url.path) { return true }
            }
        }
        return false
    }

    // MARK: - JSON probe loader

    private static func loadProbeText(folder: String, probe: String) -> String? {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("\(probe).json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Probe 17 block parser (KEY: VALUE colon format, 2-space indent)

    /// Parse `--- IOPortTransportStateDisplayPort[N] ---` blocks from probe 17.
    /// Properties use `KEY: VALUE` colon format at 2-space indent. Returns one
    /// dict per block; the dict is passed directly as the `read` closure to the
    /// watcher's parse function.
    private static func parseDashDPBlocks(text: String) -> [[String: Any]] {
        guard let regex = try? NSRegularExpression(
            pattern: "--- IOPortTransportStateDisplayPort\\[\\d+\\] ---")
        else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var blocks: [[String: Any]] = []
        for (i, match) in matches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < matches.count
                ? matches[i + 1].range.lowerBound
                : nsText.length
            var body = nsText.substring(with: NSRange(location: bodyStart,
                                                       length: bodyEnd - bodyStart))
            // Cut at the next section boundary (--- or ===)
            for sep in ["\n---", "\n==="] {
                if let r = body.range(of: sep) { body = String(body[..<r.lowerBound]) }
            }
            blocks.append(parseColonProps(body: body, indent: "  "))
        }
        return blocks
    }

    // MARK: - Probe 33 block parser (KEY = VALUE equals format, 2-space indent)

    /// Parse `=== DisplayPort node [N] ===` blocks from probe 33.
    /// Properties use `KEY = VALUE` equals format at 2-space indent.
    /// Metadata sub-fields appear as flat `Metadata.KEY = VALUE` lines at the
    /// same indent; they are folded into a `[String: Any]` dict stored under
    /// the key `"Metadata"` so the watcher's `read("Metadata") as? [String: Any]`
    /// lookup works normally.
    private static func parseDPNode33Blocks(text: String) -> [[String: Any]] {
        guard let regex = try? NSRegularExpression(
            pattern: "=== DisplayPort node \\[\\d+\\] ===")
        else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var blocks: [[String: Any]] = []
        for (i, match) in matches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < matches.count
                ? matches[i + 1].range.lowerBound
                : nsText.length
            let body = nsText.substring(with: NSRange(location: bodyStart,
                                                      length: bodyEnd - bodyStart))
            blocks.append(parseEqualsProps(body: body))
        }
        return blocks
    }

    /// Parse `KEY = VALUE` lines at 2-space indent. Folds `Metadata.KEY = VALUE`
    /// lines into a nested `[String: Any]` dict under `"Metadata"`.
    private static func parseEqualsProps(body: String) -> [String: Any] {
        var props: [String: Any] = [:]
        var metadata: [String: Any] = [:]

        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            // Only top-level 2-space indent, skip deeper (Metadata section header etc.)
            guard s.hasPrefix("  "), !s.hasPrefix("   ") else { continue }
            let stripped = String(s.dropFirst(2))

            // Flat metadata field: "Metadata.KEY = VALUE"
            if stripped.hasPrefix("Metadata.") {
                let rest = String(stripped.dropFirst("Metadata.".count))
                if let (key, val) = parseEqualsLine(rest) {
                    metadata[key] = val
                }
                continue
            }
            // Skip "--- Metadata ---" section header
            if stripped.hasPrefix("---") { continue }

            if let (key, val) = parseEqualsLine(stripped) {
                props[key] = val
            }
        }

        if !metadata.isEmpty { props["Metadata"] = metadata }
        return props
    }

    /// Parse a single `KEY = VALUE` line. Returns nil for `(absent)`, `(redacted)`,
    /// opaque types, and lines without `= `.
    private static func parseEqualsLine(_ stripped: String) -> (String, Any)? {
        guard let eqRange = stripped.range(of: " = ") else { return nil }
        let key = String(stripped[..<eqRange.lowerBound])
        let valStr = String(stripped[eqRange.upperBound...])

        // Skip sentinel values that indicate the field was not present
        if valStr == "(absent)" || valStr == "(redacted)" { return nil }
        // Skip opaque binary values we can't parse
        if valStr.hasPrefix("<") { return nil }
        // Skip complex collection types that aren't simple scalars
        if valStr.hasPrefix("{") { return nil }

        if valStr == "true" {
            return (key, NSNumber(value: true))
        } else if valStr == "false" {
            return (key, NSNumber(value: false))
        } else if valStr.hasPrefix("\""), valStr.hasSuffix("\""), valStr.count >= 2 {
            return (key, String(valStr.dropFirst().dropLast()))
        } else if let n = matchInt(valStr) {
            return (key, NSNumber(value: n))
        }
        return nil
    }

    // MARK: - Shared colon-property parser

    /// Parse `KEY: VALUE` lines at the given indent level. Skips sub-dict bodies
    /// (more deeply indented than `indent`) and complex types (`<...>`, `{...}`).
    private static func parseColonProps(body: String, indent: String) -> [String: Any] {
        var props: [String: Any] = [:]
        let deeper = indent + " "
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.hasPrefix(indent), !s.hasPrefix(deeper) else { continue }
            let stripped = String(s.dropFirst(indent.count))
            guard let colonRange = stripped.range(of: ": ") else { continue }
            let key = String(stripped[..<colonRange.lowerBound])
            let valStr = String(stripped[colonRange.upperBound...])

            if valStr == "true" {
                props[key] = NSNumber(value: true)
            } else if valStr == "false" {
                props[key] = NSNumber(value: false)
            } else if valStr.hasPrefix("\""), valStr.hasSuffix("\""), valStr.count >= 2 {
                props[key] = String(valStr.dropFirst().dropLast())
            } else if let n = matchInt(valStr) {
                props[key] = NSNumber(value: n)
            }
            // Skip complex types (<data ...>, <CFType 17>, multi-line dicts, etc.)
        }
        return props
    }

    // MARK: - Integer matcher

    /// Parse `N (0xHEX)` or plain integer strings. Returns the decimal value.
    private static func matchInt(_ s: String) -> Int? {
        if let spaceIdx = s.firstIndex(of: " ") {
            if let v = Int(s[..<spaceIdx]) { return v }
        }
        return Int(s)
    }

    // MARK: - Shared update builder

    /// Call `DisplayPortTransportWatcher.makeUpdate` from a props dict. Supplies
    /// a fixed entryID and nil portType/portIndex/uuid (no IOKit in tests).
    private func makeUpdate(props: [String: Any], id: UInt64) -> DisplayPortTransportWatcher.DisplayPortUpdate? {
        let read: (String) -> Any? = { props[$0] }
        return DisplayPortTransportWatcher.makeUpdate(
            entryID: id,
            read: read,
            portIndex: 0,
            portType: "USB-C",
            hpmControllerUUID: nil
        )
    }

    // MARK: - Tests

    // MARK: Probe 17: no silent drops

    @Test("DP watcher: every probe-17 block produces an update, no silent drops")
    func probe17NoSilentDrops() {
        let folders = Self.allProbeFolders()
        var blocksTotal = 0
        var modelsTotal = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            let blocks = Self.parseDashDPBlocks(text: text)
            for (i, props) in blocks.enumerated() {
                blocksTotal += 1
                if makeUpdate(props: props, id: UInt64(i)) != nil {
                    modelsTotal += 1
                }
            }
        }

        // DisplayPortTransportWatcher.makeUpdate has no gate key: every valid block
        // must produce an update.
        #expect(modelsTotal == blocksTotal,
            "Expected \(blocksTotal) DisplayPortUpdate models (no gate); got \(modelsTotal)")

        // Actual 494 blocks across 312 folders, as of 2026-07. Floor set to
        // ~85% of actual (420), not the stale 200 (40% of actual).
        // Guard skipped on a fresh clone that hasn't fetched raw probes from KV.
        if Self.hasDPProbeFiles() && blocksTotal > 0 {
            #expect(blocksTotal >= 420,
                "Expected at least 420 DP blocks in probe 17; got \(blocksTotal) -- were raw probes deleted?")
        }
    }

    // MARK: Probe 17: field round-trips

    @Test("DP watcher: probe-17 field round-trips (active, laneCount, linkRate, tunneled, HPD, parentPort)")
    func probe17FieldRoundTrips() {
        let folders = Self.allProbeFolders()
        var verified = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            let blocks = Self.parseDashDPBlocks(text: text)
            for (i, props) in blocks.enumerated() {
                let read: (String) -> Any? = { props[$0] }
                guard let update = DisplayPortTransportWatcher.makeUpdate(
                    entryID: UInt64(i),
                    read: read,
                    portIndex: 0,
                    portType: "USB-C",
                    hpmControllerUUID: nil
                ) else { continue }

                let link = update.status.link
                let st = update.status

                // active flag round-trips
                if let rawActive = (props["Active"] as? NSNumber)?.boolValue {
                    #expect(link.active == rawActive,
                        "Probe \(folder)/17 block \(i): active mismatch: got \(link.active), expected \(rawActive)")
                }

                // laneCount round-trips
                if let rawLane = (props["LaneCount"] as? NSNumber)?.intValue {
                    #expect(link.laneCount == rawLane,
                        "Probe \(folder)/17 block \(i): laneCount mismatch")
                    // Lane counts must be in the set {0, 1, 2, 4}
                    #expect([0, 1, 2, 4].contains(link.laneCount),
                        "Probe \(folder)/17 block \(i): laneCount \(link.laneCount) not in {0,1,2,4}")
                }

                // maxLaneCount round-trips
                if let rawMax = (props["MaxLaneCount"] as? NSNumber)?.intValue {
                    #expect(link.maxLaneCount == rawMax,
                        "Probe \(folder)/17 block \(i): maxLaneCount mismatch")
                    #expect([0, 1, 2, 4].contains(link.maxLaneCount),
                        "Probe \(folder)/17 block \(i): maxLaneCount \(link.maxLaneCount) not in {0,1,2,4}")
                }

                // linkRate is non-negative
                #expect(link.linkRate >= 0,
                    "Probe \(folder)/17 block \(i): linkRate \(link.linkRate) should be >= 0")

                // linkRateDescription non-empty when key is present
                if let desc = props["LinkRateDescription"] as? String {
                    #expect(link.linkRateDescription == desc,
                        "Probe \(folder)/17 block \(i): linkRateDescription mismatch")
                    #expect(!desc.isEmpty,
                        "Probe \(folder)/17 block \(i): linkRateDescription should not be empty")
                }

                // tunneled round-trips
                if let rawTunneled = (props["Tunneled"] as? NSNumber)?.boolValue {
                    #expect(link.tunneled == rawTunneled,
                        "Probe \(folder)/17 block \(i): tunneled mismatch")
                }

                // HPD_State round-trips
                if let rawHPD = (props["HPD_State"] as? NSNumber)?.intValue {
                    #expect(link.hpdState == rawHPD,
                        "Probe \(folder)/17 block \(i): hpdState mismatch")
                }

                // HPD_StateDescription round-trips
                if let desc = props["HPD_StateDescription"] as? String {
                    #expect(link.hpdStateDescription == desc,
                        "Probe \(folder)/17 block \(i): hpdStateDescription mismatch")
                }

                // parent port identity: portKey contains "/"
                #expect(st.portKey.contains("/"),
                    "Probe \(folder)/17 block \(i): portKey \(st.portKey) should contain '/'")

                // parentPortNumber is non-negative
                #expect(st.parentPortNumber >= 0,
                    "Probe \(folder)/17 block \(i): parentPortNumber \(st.parentPortNumber) should be >= 0")

                // transportTypeDescription round-trips when present
                if let desc = props["TransportTypeDescription"] as? String {
                    #expect(st.transportTypeDescription == desc,
                        "Probe \(folder)/17 block \(i): transportTypeDescription mismatch")
                    #expect(!desc.isEmpty,
                        "Probe \(folder)/17 block \(i): transportTypeDescription should not be empty")
                }

                verified += 1
            }
        }

        // Actual 494 verifications as of 2026-07. Floor set to ~85% of actual.
        if Self.hasDPProbeFiles() {
            #expect(verified >= 420,
                "Expected at least 420 probe-17 field verifications; got \(verified)")
        }
    }

    // MARK: Probe 17: monitor info when active

    @Test("DP watcher: probe-17 monitor fields round-trip for active blocks")
    func probe17MonitorFieldsForActiveBlocks() {
        let folders = Self.allProbeFolders()
        var activeBlocks = 0
        var withMonitor = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            let blocks = Self.parseDashDPBlocks(text: text)
            for (i, props) in blocks.enumerated() {
                guard (props["Active"] as? NSNumber)?.boolValue == true else { continue }
                activeBlocks += 1

                let read: (String) -> Any? = { props[$0] }
                guard let update = DisplayPortTransportWatcher.makeUpdate(
                    entryID: UInt64(i),
                    read: read,
                    portIndex: 0,
                    portType: "USB-C",
                    hpmControllerUUID: nil
                ) else { continue }

                let st = update.status
                guard let monitor = st.monitor else { continue }
                withMonitor += 1

                // ProductName round-trips (may come from top-level or Metadata).
                // An EMPTY value is normalised to nil by the watcher: three
                // corpus machines publish `ProductName: ""` on a real display,
                // and an empty string is not a name. The old assertion here was
                // `!name.isEmpty`, which encoded the assumption that a present
                // key always carries a usable value; the corpus disproved it.
                if let name = props["ProductName"] as? String {
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        #expect(monitor.productName == nil,
                            "Probe \(folder)/17 block \(i): an empty ProductName must become nil, not \"\"")
                    } else {
                        #expect(monitor.productName == name,
                            "Probe \(folder)/17 block \(i): monitor.productName mismatch")
                    }
                }

                // ManufacturerName round-trips (same empty-to-nil contract)
                if let mfr = props["ManufacturerName"] as? String,
                   !mfr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    #expect(monitor.manufacturerName == mfr,
                        "Probe \(folder)/17 block \(i): monitor.manufacturerName mismatch")
                }

                // ProductID round-trips
                if let pid = (props["ProductID"] as? NSNumber)?.intValue {
                    #expect(monitor.productId == pid,
                        "Probe \(folder)/17 block \(i): monitor.productId mismatch")
                }
            }
        }

        // Actual 239 active blocks in probe 17, all 239 with monitor info, as of
        // 2026-07. Floor set to ~88% of actual (210), not the stale 100 (42%).
        if Self.hasDPProbeFiles() && activeBlocks > 0 {
            #expect(activeBlocks >= 210,
                "Expected at least 210 active DP blocks in probe 17; got \(activeBlocks)")
            // Allow some fraction without monitor info (inactive ports, HDMI-only)
            #expect(withMonitor > activeBlocks / 3,
                "At least a third of active blocks should have monitor info; got \(withMonitor)/\(activeBlocks)")
        }
    }

    // MARK: Probe 33: no silent drops

    @Test("DP watcher: every probe-33 block produces an update, no silent drops")
    func probe33NoSilentDrops() {
        let folders = Self.allProbeFolders()
        var blocksTotal = 0
        var modelsTotal = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "33_displayport_capability")
            else { continue }

            let blocks = Self.parseDPNode33Blocks(text: text)
            for (i, props) in blocks.enumerated() {
                blocksTotal += 1
                if makeUpdate(props: props, id: UInt64(1000 + i)) != nil {
                    modelsTotal += 1
                }
            }
        }

        #expect(modelsTotal == blocksTotal,
            "Expected \(blocksTotal) DisplayPortUpdate models from probe 33 (no gate); got \(modelsTotal)")

        // Actual 322 blocks across 204 folders, as of 2026-07. Floor set to
        // ~87% of actual (280), not the stale 60 (19% of actual).
        if Self.hasDPProbeFiles() && blocksTotal > 0 {
            #expect(blocksTotal >= 280,
                "Expected at least 280 DP blocks in probe 33; got \(blocksTotal) -- were raw probes deleted?")
        }
    }

    // MARK: Probe 33: field round-trips

    @Test("DP watcher: probe-33 field round-trips (active, lanes, link rate, HPD, parent port, monitor name)")
    func probe33FieldRoundTrips() {
        let folders = Self.allProbeFolders()
        var verified = 0
        var activeVerified = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "33_displayport_capability")
            else { continue }

            let blocks = Self.parseDPNode33Blocks(text: text)
            for (i, props) in blocks.enumerated() {
                let read: (String) -> Any? = { props[$0] }
                guard let update = DisplayPortTransportWatcher.makeUpdate(
                    entryID: UInt64(1000 + i),
                    read: read,
                    portIndex: 0,
                    portType: "USB-C",
                    hpmControllerUUID: nil
                ) else { continue }

                let link = update.status.link
                let st = update.status

                // active flag round-trips
                if let rawActive = (props["Active"] as? NSNumber)?.boolValue {
                    #expect(link.active == rawActive,
                        "Probe \(folder)/33 block \(i): active mismatch: got \(link.active), expected \(rawActive)")
                }

                // laneCount round-trips and is in valid set
                if let rawLane = (props["LaneCount"] as? NSNumber)?.intValue {
                    #expect(link.laneCount == rawLane,
                        "Probe \(folder)/33 block \(i): laneCount mismatch")
                    #expect([0, 1, 2, 4].contains(link.laneCount),
                        "Probe \(folder)/33 block \(i): laneCount \(link.laneCount) not in {0,1,2,4}")
                }

                // maxLaneCount round-trips and is in valid set
                if let rawMax = (props["MaxLaneCount"] as? NSNumber)?.intValue {
                    #expect(link.maxLaneCount == rawMax,
                        "Probe \(folder)/33 block \(i): maxLaneCount mismatch")
                    #expect([0, 1, 2, 4].contains(link.maxLaneCount),
                        "Probe \(folder)/33 block \(i): maxLaneCount \(link.maxLaneCount) not in {0,1,2,4}")
                }

                // linkRate is non-negative
                #expect(link.linkRate >= 0,
                    "Probe \(folder)/33 block \(i): linkRate \(link.linkRate) should be >= 0")

                // linkRateDescription round-trips and is non-empty when present
                if let desc = props["LinkRateDescription"] as? String {
                    #expect(link.linkRateDescription == desc,
                        "Probe \(folder)/33 block \(i): linkRateDescription mismatch")
                    #expect(!desc.isEmpty,
                        "Probe \(folder)/33 block \(i): linkRateDescription should not be empty")
                }

                // HPD_State round-trips
                if let rawHPD = (props["HPD_State"] as? NSNumber)?.intValue {
                    #expect(link.hpdState == rawHPD,
                        "Probe \(folder)/33 block \(i): hpdState mismatch")
                }

                // tunneled round-trips
                if let rawTunneled = (props["Tunneled"] as? NSNumber)?.boolValue {
                    #expect(link.tunneled == rawTunneled,
                        "Probe \(folder)/33 block \(i): tunneled mismatch")
                }

                // portKey is well-formed
                #expect(st.portKey.contains("/"),
                    "Probe \(folder)/33 block \(i): portKey \(st.portKey) should contain '/'")

                // parentPortNumber is non-negative
                #expect(st.parentPortNumber >= 0,
                    "Probe \(folder)/33 block \(i): parentPortNumber \(st.parentPortNumber) should be >= 0")

                // For active blocks: monitor identity fields come from Metadata.*
                if link.active {
                    activeVerified += 1
                    // ProductName arrives via Metadata dict. Empty values are
                    // normalised to nil by the watcher (see the probe-17 sweep
                    // above), so only non-empty names round-trip.
                    if let metadata = props["Metadata"] as? [String: Any],
                       let name = metadata["ProductName"] as? String,
                       !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        #expect(update.status.monitor?.productName == name,
                            "Probe \(folder)/33 block \(i): monitor.productName mismatch: got \(update.status.monitor?.productName ?? "nil"), expected \(name)")
                    }
                    // ManufacturerName arrives via Metadata dict
                    if let metadata = props["Metadata"] as? [String: Any],
                       let mfr = metadata["ManufacturerName"] as? String,
                       !mfr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        #expect(update.status.monitor?.manufacturerName == mfr,
                            "Probe \(folder)/33 block \(i): monitor.manufacturerName mismatch")
                    }
                }

                verified += 1
            }
        }

        // Actual as of 2026-07: 322 verifications, 160 active-block verifications.
        // Floors set to ~87% (280) and ~87.5% (140) of actual respectively.
        if Self.hasDPProbeFiles() {
            #expect(verified >= 280,
                "Expected at least 280 probe-33 field verifications; got \(verified)")
            #expect(activeVerified >= 140,
                "Expected at least 140 active-block verifications in probe 33; got \(activeVerified)")
        }
    }

    // MARK: Sanity invariants

    @Test("DP watcher: sanity invariants across both probes (lane counts, link rates)")
    func sanityInvariantsBothProbes() {
        let folders = Self.allProbeFolders()

        for folder in folders {
            for (probe, blocks) in [
                ("17", Self.parseDashDPBlocks(
                    text: Self.loadProbeText(folder: folder, probe: "17_deep_property_dump") ?? "")),
                ("33", Self.parseDPNode33Blocks(
                    text: Self.loadProbeText(folder: folder, probe: "33_displayport_capability") ?? "")),
            ] {
                for (i, props) in blocks.enumerated() {
                    let read: (String) -> Any? = { props[$0] }
                    guard let update = DisplayPortTransportWatcher.makeUpdate(
                        entryID: UInt64(i),
                        read: read,
                        portIndex: 0,
                        portType: "USB-C",
                        hpmControllerUUID: nil
                    ) else { continue }

                    let link = update.status.link

                    // Lane counts must be in the known valid set {0, 1, 2, 4}
                    #expect([0, 1, 2, 4].contains(link.laneCount),
                        "Probe \(folder)/\(probe) block \(i): laneCount \(link.laneCount) not in {0,1,2,4}")
                    #expect([0, 1, 2, 4].contains(link.maxLaneCount),
                        "Probe \(folder)/\(probe) block \(i): maxLaneCount \(link.maxLaneCount) not in {0,1,2,4}")

                    // linkRate is non-negative
                    #expect(link.linkRate >= 0,
                        "Probe \(folder)/\(probe) block \(i): linkRate \(link.linkRate) is negative")

                    // linkRateDescription is non-empty when present
                    if let desc = link.linkRateDescription {
                        #expect(!desc.isEmpty,
                            "Probe \(folder)/\(probe) block \(i): linkRateDescription is empty string")
                    }
                }
            }
        }
    }

    // MARK: Cross-probe count assertion (m4max_macos26.5.1_b)

    @Test("DP watcher: m4max_macos26.5.1_b (Dell U4320Q on native HDMI port) has active display in probe 33")
    func m4maxActiveDisplayProbe33() {
        // This machine has a Dell U4320Q connected to the M4 Max MBP's native
        // HDMI port (probe 33 confirms ParentPortType=6,
        // ParentPortTypeDescription="HDMI", Tunneled=false). An earlier
        // comment guessed a CalDigit TS4 dock path; that was wrong (issue #352).
        // We assert Active is true and the monitor name round-trips through
        // the watcher's parse path.
        let folder = "m4max_macos26.5.1_b"
        guard let text = Self.loadProbeText(folder: folder, probe: "33_displayport_capability")
        else { return }

        let blocks = Self.parseDPNode33Blocks(text: text)
        guard !blocks.isEmpty else { return }

        var foundActive = false
        for (i, props) in blocks.enumerated() {
            let read: (String) -> Any? = { props[$0] }
            guard let update = DisplayPortTransportWatcher.makeUpdate(
                entryID: UInt64(i),
                read: read,
                portIndex: 0,
                portType: "USB-C",
                hpmControllerUUID: nil
            ) else { continue }

            if update.status.link.active {
                foundActive = true
                // ProductName for the Dell U4320Q
                if let monitor = update.status.monitor, let name = monitor.productName {
                    #expect(name.contains("U4320") || name.contains("DELL") || !name.isEmpty,
                        "m4max active display: expected a monitor name, got '\(name)'")
                }
                // laneCount must be 2 or 4 for an active HBR3 display
                #expect([2, 4].contains(update.status.link.laneCount),
                    "m4max active display: expected laneCount 2 or 4, got \(update.status.link.laneCount)")
                // linkRate 4 = HBR3 (8.1 Gbps)
                #expect(update.status.link.linkRate > 0,
                    "m4max active display: linkRate should be > 0 when active")
            }
        }

        #expect(foundActive,
            "m4max_macos26.5.1_b probe 33 should have at least one active DisplayPort node")
    }

    // MARK: Sweep summary

    @Test("DP watcher sweep: at least 280 folders contribute DP blocks across both probes")
    func sweepMinimumFolderCount() {
        guard Self.hasDPProbeFiles() else { return }

        let folders = Self.allProbeFolders()
        var foldersWithDP = 0

        for folder in folders {
            var found = false

            if let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump") {
                if !Self.parseDashDPBlocks(text: text).isEmpty { found = true }
            }
            if !found,
               let text = Self.loadProbeText(folder: folder, probe: "33_displayport_capability") {
                if !Self.parseDPNode33Blocks(text: text).isEmpty { found = true }
            }

            if found { foldersWithDP += 1 }
        }

        // Actual as of 2026-07: 312 folders have probe-17 DP blocks, 204 have
        // probe-33 DP blocks, 323 folders have at least one of the two (out of
        // 410 total). Floor set to ~87% of actual (280), not the stale 30 (9%).
        #expect(foldersWithDP >= 280,
            "Expected at least 280 machine folders to contribute DP blocks; got \(foldersWithDP) out of \(folders.count)")
    }

    // MARK: - Empty identity strings (deterministic, no corpus required)
    //
    // These exist because the corpus sweeps CANNOT guard this fix where it
    // matters. The three machines that publish `ProductName: ""` on a real
    // display (m4pro_macos26.5.1_d, _i, m4pro_macos26.5.2_aa) are not in the
    // git-tracked fixture set, so on a fresh clone or in CI the sweeps skip
    // them entirely. A reviewer reverted the production fix in that exact
    // environment and every sweep still passed: the test certified the bug
    // rather than catching it.
    //
    // Built from a plain dictionary so they always run, clone or not, and so
    // they fail the moment `nonEmpty` is removed.

    @Test("DP identity: an empty top-level name does not suppress the Metadata fallback")
    func emptyTopLevelNameFallsBackToMetadata() throws {
        let update = try #require(makeUpdate(props: [
            "Active": true,
            "ProductName": "",
            "ManufacturerName": "",
            "Metadata": [
                "ProductName": "Studio Display",
                "ManufacturerName": "Apple Inc."
            ] as [String: Any]
        ], id: 0x1001))
        // The whole point of the fix: "" must not win over a real fallback.
        #expect(update.status.monitor?.productName == "Studio Display")
        #expect(update.status.monitor?.manufacturerName == "Apple Inc.")
    }

    @Test("DP identity: a whitespace-only name is treated as absent")
    func whitespaceOnlyNameFallsBackToMetadata() throws {
        let update = try #require(makeUpdate(props: [
            "Active": true,
            "ProductName": "   ",
            "ManufacturerName": "\t\n",
            "Metadata": [
                "ProductName": "LG HDR 4K",
                "ManufacturerName": "LG Electronics"
            ] as [String: Any]
        ], id: 0x1002))
        #expect(update.status.monitor?.productName == "LG HDR 4K")
        #expect(update.status.monitor?.manufacturerName == "LG Electronics")
    }

    @Test("DP identity: empty on both sources becomes nil, never an empty string")
    func emptyEverywhereBecomesNil() throws {
        let update = try #require(makeUpdate(props: [
            "Active": true,
            "ProductName": "",
            "ManufacturerName": "",
            "Metadata": ["ProductName": "", "ManufacturerName": ""] as [String: Any]
        ], id: 0x1003))
        #expect(update.status.monitor?.productName == nil)
        #expect(update.status.monitor?.manufacturerName == nil)
    }

    @Test("DP identity: a real name is preserved verbatim and still wins over Metadata")
    func realTopLevelNameWins() throws {
        let update = try #require(makeUpdate(props: [
            "Active": true,
            "ProductName": "DELL U2720Q",
            "Metadata": ["ProductName": "should not be used"] as [String: Any]
        ], id: 0x1004))
        // Guards the opposite direction: the fix must not make every name nil,
        // which is how a "normalise to nil" change passes vacuously.
        #expect(update.status.monitor?.productName == "DELL U2720Q")
    }

    @Test("DP identity: dfpType and branchDeviceId get the same treatment")
    func dfpTypeAndBranchDeviceIdFallBack() throws {
        let update = try #require(makeUpdate(props: [
            "Active": true,
            "DFP Type Description": "",
            "BranchDeviceID": "",
            "Metadata": [
                "DFP Type Description": "DisplayPort",
                "BranchDeviceID": "BRANCH-1"
            ] as [String: Any]
        ], id: 0x1005))
        #expect(update.status.dfpType == "DisplayPort")
        #expect(update.status.branchDeviceId == "BRANCH-1")
    }
}
