import Foundation
import Testing
@testable import WhatCableDarwinBackend

/// Corpus-replay tests for the transport and power-source watcher parse functions.
///
/// These tests sweep every customer probe under `research/customer-probes/` and
/// call the `internal nonisolated static` parse functions (makeTRMTransport,
/// makeCIOCapability, makeTransport, makeSource) directly. No IOKit required:
/// the parse functions accept a `(String) -> Any?` closure, so we build
/// that closure from the text in the probe files.
///
/// Fresh clones without the corpus (probe 17 and 19 files are gitignored;
/// only probe 01 is committed) will trivially pass because missing-file guards
/// return empty collections and the minimum-count assertions are skipped when
/// the corpus root is empty.
@Suite("Transport and power-source watcher -- customer probe sweep (DAR-77)")
struct TransportWatcherSweepTests {

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

    /// Returns true when at least one folder in the corpus has probe 17 or probe 19.
    /// In a fresh clone, only `01_walk_pd_tree.json` is committed; probe 17 and 19
    /// are gitignored raw data. Tests use this to skip minimum-count assertions
    /// rather than failing on a machine that hasn't fetched the corpus from KV.
    private static func hasTransportProbeFiles() -> Bool {
        let folders = allProbeFolders()
        for folder in folders.prefix(10) {
            for probe in ["17_deep_property_dump", "19_pdo_decode_and_usb3_watch"] {
                let url = probeRoot
                    .appendingPathComponent(folder)
                    .appendingPathComponent("\(probe).json")
                if FileManager.default.fileExists(atPath: url.path) { return true }
            }
        }
        return false
    }

    // MARK: - JSON probe loader

    /// Load the "output" text from a numbered probe JSON inside a folder.
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

    // MARK: - Text block parsers

    /// Parse `--- ClassName[N] ---` style blocks (2-space-indented properties).
    /// Used by the flat "All IOPortTransportState* services" and
    /// "All IOPortFeature* services" sections in probe 17, and by
    /// "Current IOPortTransportStateUSB3" in probe 19.
    private static func parseDashBlocks(text: String, classPrefix: String) -> [[String: Any]] {
        // Match headers like: --- IOPortTransportStateUSB3[0] ---
        let escapedPrefix = NSRegularExpression.escapedPattern(for: classPrefix)
        guard let regex = try? NSRegularExpression(
            pattern: "--- \(escapedPrefix)\\[\\d+\\] ---")
        else { return [] }

        let nsText = text as NSString
        let headerMatches = regex.matches(
            in: text, range: NSRange(text.startIndex..., in: text))

        var blocks: [[String: Any]] = []
        for (i, match) in headerMatches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < headerMatches.count
                ? headerMatches[i + 1].range.lowerBound
                : nsText.length
            var body = nsText.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
            // Cut at next section boundary
            for sep in ["\n---", "\n==="] {
                if let r = body.range(of: sep) { body = String(body[..<r.lowerBound]) }
            }
            blocks.append(parseProperties(body: body, indent: "  "))
        }
        return blocks
    }

    /// Parse `=== ClassName ===` style blocks (4-space-indented properties).
    /// Used inside the HPM deep-dive and per-port sections in probe 17
    /// (IOPortTransportStateCIO and IOPortTransportStateUSB3 appear here).
    private static func parseEqualsBlocks(text: String, className: String) -> [[String: Any]] {
        let header = "=== \(className) ==="
        var blocks: [[String: Any]] = []
        var searchFrom = text.startIndex
        while let range = text.range(of: header, range: searchFrom..<text.endIndex) {
            let bodyStart = range.upperBound
            var body: String
            // Find the next === or --- section boundary
            let rest = String(text[bodyStart...])
            if let nextSection = rest.range(of: "\n=== ") ?? rest.range(of: "\n--- ") {
                body = String(rest[..<nextSection.lowerBound])
            } else {
                body = String(rest.prefix(2000))
            }
            blocks.append(parseProperties(body: body, indent: "    "))
            searchFrom = range.upperBound
        }
        return blocks
    }

    /// Convert a block body (text after the section header) into a `[String: Any]` dict
    /// by parsing `KEY: VALUE` lines at the given indentation level.
    ///
    /// Value forms supported:
    /// - `N (0xHEX)` -> Int
    /// - `"quoted string"` -> String
    /// - `true` / `false` -> Bool
    /// - anything else -> left as String (rare, skipped by the watchers)
    private static func parseProperties(body: String, indent: String) -> [String: Any] {
        var props: [String: Any] = [:]
        let deeper = indent + " "   // exclude more-deeply-nested lines (sub-dicts)
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
            } else if let m = matchInt(valStr) {
                props[key] = NSNumber(value: m)
            }
            // else: complex types (<CFType 17>, multi-line dicts) -- ignored
        }
        return props
    }

    /// Parse `N (0xHEX)` or plain integer strings, returning the integer.
    private static func matchInt(_ s: String) -> Int? {
        // Form: "N (0xHEX)" -- take the decimal N
        if let spaceIdx = s.firstIndex(of: " ") {
            if let v = Int(s[..<spaceIdx]) { return v }
        }
        return Int(s)
    }

    /// Parse the `WinningPowerSourceOption: { ... }` sub-dict from a
    /// PowerSource block body. Returns nil if absent.
    private static func parseWinningOption(body: String) -> [String: Any]? {
        let marker = "WinningPowerSourceOption: {"
        guard let start = body.range(of: marker) else { return nil }
        let afterBrace = body[start.upperBound...]
        guard let endBrace = afterBrace.range(of: "\n  }") else { return nil }
        let inner = String(afterBrace[..<endBrace.lowerBound])
        // Keys inside the dict are indented 4 spaces
        return parseProperties(body: inner, indent: "    ")
    }

    // MARK: - Tests

    // MARK: TRM transport

    @Test("TRM transport: gate on TRM_State, no silent drops (probe 17 sweep)")
    func trmTransportGateAndNoSilentDrops() {
        let folders = Self.allProbeFolders()
        var blocksWithState = 0
        var modelsProduced = 0
        var blocksWithoutState = 0
        var nilsForMissingState = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            // Gather blocks from both text styles in probe 17
            var allBlocks: [[String: Any]] = []
            for cls in TRMTransportWatcher.watchedClasses {
                // The flat "All services" section uses --- style (2-space indent)
                allBlocks += Self.parseDashBlocks(text: text, classPrefix: cls)
                // The HPM deep-dive section uses === style (4-space indent)
                allBlocks += Self.parseEqualsBlocks(text: text, className: cls)
            }

            for (i, props) in allBlocks.enumerated() {
                let read: (String) -> Any? = { props[$0] }
                let transportType = (props["TransportTypeDescription"] as? String) ?? "USB2"

                let hasTRMState = props["TRM_State"] != nil
                let model = TRMTransportWatcher.makeTRMTransport(
                    entryID: UInt64(i),
                    read: read,
                    transportType: transportType,
                    hpmControllerUUID: nil
                )

                if hasTRMState {
                    blocksWithState += 1
                    if model != nil { modelsProduced += 1 }
                } else {
                    blocksWithoutState += 1
                    if model == nil { nilsForMissingState += 1 }
                }
            }
        }

        // Every block with TRM_State must produce a model (no silent drops)
        #expect(modelsProduced == blocksWithState,
            "Expected \(blocksWithState) models for blocks with TRM_State; got \(modelsProduced)")

        // Every block without TRM_State must return nil (gate holds)
        #expect(nilsForMissingState == blocksWithoutState,
            "Expected nil for all \(blocksWithoutState) blocks missing TRM_State; got \(nilsForMissingState) nils")

        // Actual 821 TRM_State blocks across 225 of 410 folders, as of 2026-07.
        // Floor set to ~85% of actual (700). This assertion is skipped on a
        // fresh clone (no probe 17 files).
        if Self.hasTransportProbeFiles() {
            #expect(blocksWithState >= 700,
                "Expected at least 700 blocks with TRM_State across the corpus; got \(blocksWithState) -- did probe files get deleted?")
        }
    }

    @Test("TRM transport: field-level spot checks (stateDescription, portKey)")
    func trmTransportFieldSpotChecks() {
        let folders = Self.allProbeFolders()
        var verified = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            for cls in TRMTransportWatcher.watchedClasses {
                for (i, props) in Self.parseDashBlocks(text: text, classPrefix: cls).enumerated() {
                    guard props["TRM_State"] != nil else { continue }
                    let read: (String) -> Any? = { props[$0] }
                    guard let model = TRMTransportWatcher.makeTRMTransport(
                        entryID: UInt64(i),
                        read: read,
                        transportType: TRMTransportWatcher.transportType(from: cls),
                        hpmControllerUUID: nil
                    ) else { continue }

                    // stateDescription round-trips
                    if let desc = props["TRM_StateDescription"] as? String {
                        #expect(model.stateDescription == desc,
                            "Probe \(folder): TRM_StateDescription mismatch: got \(model.stateDescription ?? "nil"), expected \(desc)")
                    }

                    // portKey is non-empty and contains "/"
                    #expect(model.portKey.contains("/"),
                        "Probe \(folder): portKey \(model.portKey) should contain '/'")

                    // transportType matches the class suffix
                    let expectedType = TRMTransportWatcher.transportType(from: cls)
                    #expect(model.transportType == expectedType,
                        "Probe \(folder): transportType mismatch: got \(model.transportType), expected \(expectedType)")

                    verified += 1
                }
            }
        }

        // Actual 485 verifications as of 2026-07. Floor set to ~87% of actual.
        if Self.hasTransportProbeFiles() {
            #expect(verified >= 420,
                "Expected at least 420 TRM field verifications across the corpus; got \(verified)")
        }
    }

    // MARK: CIO capability

    @Test("CIO capability: always produces a model for CIO blocks, fields round-trip (probe 17 sweep)")
    func cioCapabilityFields() {
        let folders = Self.allProbeFolders()
        var cioBlocks = 0
        var modelsProduced = 0
        var inactiveBlocks = 0
        var cableGenVerified = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            // CIO appears as '=== IOPortTransportStateCIO ===' in probe 17
            for (i, props) in Self.parseEqualsBlocks(text: text, className: "IOPortTransportStateCIO").enumerated() {
                cioBlocks += 1
                let read: (String) -> Any? = { props[$0] }
                let model = TRMTransportWatcher.makeCIOCapability(
                    entryID: UInt64(1000 + i),
                    read: read,
                    hpmControllerUUID: nil
                )
                // CIO has no gate key, except an explicit Active=false row
                // (the CIO leg is not currently up), which is dropped: every
                // other CIO block must produce a model.
                if (props["Active"] as? NSNumber)?.boolValue == false {
                    #expect(model == nil,
                        "Probe \(folder): CIO block with Active=false should be dropped")
                    inactiveBlocks += 1
                    continue
                }
                #expect(model != nil,
                    "Probe \(folder): CIO block should always produce a capability model")
                guard let model else { continue }
                modelsProduced += 1

                // cableGeneration round-trips when present
                if let gen = (props["CableGeneration"] as? NSNumber)?.intValue {
                    #expect(model.cableGeneration == gen,
                        "Probe \(folder): cableGeneration mismatch: got \(model.cableGeneration ?? -1), expected \(gen)")
                    cableGenVerified += 1
                }

                // cableSpeed round-trips when present
                if let speed = (props["CableSpeed"] as? NSNumber)?.intValue {
                    #expect(model.negotiatedLinkSpeed == speed,
                        "Probe \(folder): cableSpeed mismatch: got \(model.negotiatedLinkSpeed ?? -1), expected \(speed)")
                }

                // portKey is non-empty
                #expect(model.portKey.contains("/"),
                    "Probe \(folder): CIO portKey \(model.portKey) should contain '/'")
            }
        }

        // Actual 101 CIO blocks across 75 folders, as of 2026-07. Floor set to
        // ~89% of actual.
        if Self.hasTransportProbeFiles() && cioBlocks > 0 {
            #expect(cioBlocks >= 90,
                "Expected at least 90 CIO blocks in the corpus; got \(cioBlocks)")
            #expect(modelsProduced == cioBlocks - inactiveBlocks,
                "Every CIO block except an Active=false row should produce a model: expected \(cioBlocks - inactiveBlocks), got \(modelsProduced)")
        }
    }

    // MARK: USB3 transport

    @Test("USB3 transport: models produced for all blocks in probe 17 and 19")
    func usb3TransportNoSilentDrops() {
        let folders = Self.allProbeFolders()
        var blocks17 = 0
        var models17 = 0
        var blocks19 = 0
        var models19 = 0

        for folder in folders {
            // Probe 17: flat --- style blocks
            if let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump") {
                for (i, props) in Self.parseDashBlocks(text: text, classPrefix: "IOPortTransportStateUSB3").enumerated() {
                    blocks17 += 1
                    let read: (String) -> Any? = { props[$0] }
                    if USB3TransportWatcher.makeTransport(
                        entryID: UInt64(i),
                        read: read,
                        hpmControllerUUID: nil
                    ) != nil {
                        models17 += 1
                    }
                }
            }

            // Probe 19: "Current IOPortTransportStateUSB3" section, --- style
            if let text = Self.loadProbeText(folder: folder, probe: "19_pdo_decode_and_usb3_watch") {
                for (i, props) in Self.parseDashBlocks(text: text, classPrefix: "IOPortTransportStateUSB3").enumerated() {
                    blocks19 += 1
                    let read: (String) -> Any? = { props[$0] }
                    if USB3TransportWatcher.makeTransport(
                        entryID: UInt64(2000 + i),
                        read: read,
                        hpmControllerUUID: nil
                    ) != nil {
                        models19 += 1
                    }
                }
            }
        }

        // USB3Transport has no gate key: every block must produce a model
        #expect(models17 == blocks17,
            "Probe 17: expected \(blocks17) USB3 models (no gate); got \(models17)")
        #expect(models19 == blocks19,
            "Probe 19: expected \(blocks19) USB3 models (no gate); got \(models19)")

        // Actual as of 2026-07: 465 blocks in probe 17, 494 in probe 19.
        // Floors set to ~86% (400) and ~85% (420) of actual respectively.
        if Self.hasTransportProbeFiles() {
            if blocks17 > 0 {
                #expect(blocks17 >= 400,
                    "Expected at least 400 USB3 blocks in probe 17; got \(blocks17)")
            }
            if blocks19 > 0 {
                #expect(blocks19 >= 420,
                    "Expected at least 420 USB3 blocks in probe 19; got \(blocks19)")
            }
        }
    }

    @Test("USB3 transport: field-level spot checks (signalingDescription, portKey)")
    func usb3TransportFieldSpotChecks() {
        let folders = Self.allProbeFolders()
        var verified = 0

        for folder in folders {
            for probe in ["17_deep_property_dump", "19_pdo_decode_and_usb3_watch"] {
                guard let text = Self.loadProbeText(folder: folder, probe: probe)
                else { continue }
                for (i, props) in Self.parseDashBlocks(text: text, classPrefix: "IOPortTransportStateUSB3").enumerated() {
                    let read: (String) -> Any? = { props[$0] }
                    guard let model = USB3TransportWatcher.makeTransport(
                        entryID: UInt64(i),
                        read: read,
                        hpmControllerUUID: nil
                    ) else { continue }

                    // signalingDescription round-trips
                    if let desc = props["SuperSpeedSignalingDescription"] as? String {
                        #expect(model.signalingDescription == desc,
                            "Probe \(folder)/\(probe): signalingDescription mismatch")
                    }

                    // signaling value round-trips
                    if let sig = (props["SuperSpeedSignaling"] as? NSNumber)?.intValue {
                        #expect(model.signaling == sig,
                            "Probe \(folder)/\(probe): signaling integer mismatch")
                    }

                    // portKey is well-formed
                    #expect(model.portKey.contains("/"),
                        "Probe \(folder)/\(probe): portKey should contain '/'")

                    verified += 1
                }
            }
        }

        // Actual 959 verifications as of 2026-07. Floor set to ~85% of actual.
        if Self.hasTransportProbeFiles() {
            #expect(verified >= 820,
                "Expected at least 820 USB3 field verifications; got \(verified)")
        }
    }

    // MARK: PowerSource

    @Test("PowerSource: models produced for all blocks, WinningOption parsed (probe 17 sweep)")
    func powerSourceNoSilentDrops() {
        let folders = Self.allProbeFolders()
        var totalBlocks = 0
        var totalModels = 0
        var blocksWithWinning = 0
        var winnersProduced = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            for (i, props) in Self.parseDashBlocks(text: text, classPrefix: "IOPortFeaturePowerSource").enumerated() {
                totalBlocks += 1
                let read: (String) -> Any? = { props[$0] }

                // Build the WinningPowerSourceOption value the way the watcher would see it:
                // in IOKit it is a CF dict, here we reconstruct it from the parsed sub-dict.
                var augmented = props
                // The raw block body for the sub-dict parse -- we re-extract from text
                // by finding the block's body range and parsing WinningPowerSourceOption.
                // Since we've already parsed flat props, we need to locate the raw body.
                // Strategy: search for the block's description key to pinpoint the block.
                // Simpler: re-derive body from the dash-block extractor index.
                // Because parseDashBlocks returns bodies (not raw text), and we need the
                // sub-dict, we stored props only. Re-parse via a separate search:
                let winningOpt = extractWinningOption(text: text, blockIndex: i, classPrefix: "IOPortFeaturePowerSource")
                if let winOpt = winningOpt {
                    blocksWithWinning += 1
                    // Pass as NSDictionary (matching what IOKit delivers)
                    augmented["WinningPowerSourceOption"] = winOpt as NSDictionary
                }

                let augRead: (String) -> Any? = { augmented[$0] }
                let model = PowerSourceWatcher.makeSource(
                    entryID: UInt64(3000 + i),
                    read: augRead,
                    hpmControllerUUID: nil
                )

                // PowerSource has no gate key: every block must produce a model
                #expect(model != nil,
                    "Probe \(folder): PowerSource block \(i) should always produce a model")
                guard let model else { continue }
                totalModels += 1

                if winningOpt != nil {
                    if model.winning != nil { winnersProduced += 1 }
                }

                // portKey is well-formed
                let portKey = "\(model.parentPortType)/\(model.parentPortNumber)"
                #expect(portKey.contains("/"),
                    "Probe \(folder): portKey should contain '/'")

                // Port number is non-negative
                #expect(model.parentPortNumber >= 0,
                    "Probe \(folder): parentPortNumber \(model.parentPortNumber) should be >= 0")
            }
        }

        #expect(totalModels == totalBlocks,
            "Every PowerSource block should produce a model: expected \(totalBlocks), got \(totalModels)")

        // Actual as of 2026-07: 604 blocks, 204 with WinningOption. Floor set
        // to ~86% of the block total.
        if Self.hasTransportProbeFiles() && totalBlocks > 0 {
            #expect(totalBlocks >= 520,
                "Expected at least 520 PowerSource blocks in the corpus; got \(totalBlocks)")
        }
    }

    @Test("PowerSource: WinningOption voltage and current round-trip (probe 17 spot checks)")
    func powerSourceWinningOptionFields() {
        let folders = Self.allProbeFolders()
        var verified = 0

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            let blocks = Self.parseDashBlocks(text: text, classPrefix: "IOPortFeaturePowerSource")
            for (i, props) in blocks.enumerated() {
                guard let winRaw = extractWinningOption(text: text, blockIndex: i, classPrefix: "IOPortFeaturePowerSource"),
                      let voltage = winRaw["Voltage (mV)"] as? Int,
                      voltage > 0
                else { continue }

                var augmented = props
                augmented["WinningPowerSourceOption"] = winRaw as NSDictionary
                let augRead: (String) -> Any? = { augmented[$0] }

                guard let model = PowerSourceWatcher.makeSource(
                    entryID: UInt64(i),
                    read: augRead,
                    hpmControllerUUID: nil
                ), let winning = model.winning else { continue }

                let expectedCurrent = winRaw["Max Current (mA)"] ?? 0
                let expectedPower = winRaw["Max Power (mW)"] ?? 0

                #expect(winning.voltageMV == voltage,
                    "Probe \(folder): WinningOption voltageMV mismatch: got \(winning.voltageMV), expected \(voltage)")
                #expect(winning.maxCurrentMA == expectedCurrent,
                    "Probe \(folder): WinningOption maxCurrentMA mismatch: got \(winning.maxCurrentMA), expected \(expectedCurrent)")

                // Max power must be >= voltage * current / 1000 (may be larger if stored explicitly)
                let derivedPower = voltage * expectedCurrent / 1000
                #expect(winning.maxPowerMW >= derivedPower,
                    "Probe \(folder): maxPowerMW \(winning.maxPowerMW) should be >= derived \(derivedPower)")

                if expectedPower > 0 {
                    #expect(winning.maxPowerMW == expectedPower,
                        "Probe \(folder): WinningOption maxPowerMW mismatch: got \(winning.maxPowerMW), expected \(expectedPower)")
                }

                verified += 1
            }
        }

        // Actual 204 verifications as of 2026-07. Floor set to ~88% of actual.
        if Self.hasTransportProbeFiles() {
            #expect(verified >= 180,
                "Expected at least 180 WinningOption verifications; got \(verified)")
        }
    }

    // MARK: - Sweep summary assertion

    @Test("Sweep minimum: corpus contributes at least 50 machine folders with parsed services")
    func sweepMinimumFolderContribution() {
        let folders = Self.allProbeFolders()
        // Trivially pass on a fresh clone where probe 17/19 files haven't been fetched from KV.
        guard Self.hasTransportProbeFiles() else { return }

        var foldersWithAnyService = 0

        for folder in folders {
            var found = false

            if let text = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump") {
                for cls in TRMTransportWatcher.watchedClasses {
                    if !Self.parseDashBlocks(text: text, classPrefix: cls).isEmpty { found = true; break }
                    if !Self.parseEqualsBlocks(text: text, className: cls).isEmpty { found = true; break }
                }
                if !Self.parseDashBlocks(text: text, classPrefix: "IOPortFeaturePowerSource").isEmpty { found = true }
            }

            if !found,
               let text = Self.loadProbeText(folder: folder, probe: "19_pdo_decode_and_usb3_watch") {
                if !Self.parseDashBlocks(text: text, classPrefix: "IOPortTransportStateUSB3").isEmpty { found = true }
            }

            if found { foldersWithAnyService += 1 }
        }

        // Actual as of 2026-07: 390 of 410 folders have at least one of these
        // service types present in probe 17 or probe 19. Floor set to ~87% of
        // actual (340), not the stale 50 (13% of actual).
        #expect(foldersWithAnyService >= 340,
            "Expected at least 340 machine folders to contribute parsed services; got \(foldersWithAnyService) out of \(folders.count)")
    }

    // MARK: - Helpers

    /// Re-extract the WinningPowerSourceOption sub-dict from the raw probe text
    /// for the Nth `--- IOPortFeaturePowerSource[N] ---` block.
    private func extractWinningOption(text: String, blockIndex: Int, classPrefix: String) -> [String: Int]? {
        // Re-locate the raw body for this block index
        let pattern = "--- \(classPrefix)[\(blockIndex)] ---"
        guard let headerRange = text.range(of: pattern) else { return nil }
        let bodyStart = headerRange.upperBound
        var body = String(text[bodyStart...])
        // Cut at next section boundary
        for sep in ["\n---", "\n==="] {
            if let r = body.range(of: sep) { body = String(body[..<r.lowerBound]) }
        }
        // Parse WinningPowerSourceOption: { ... }
        let marker = "WinningPowerSourceOption: {"
        guard let start = body.range(of: marker) else { return nil }
        let afterBrace = body[start.upperBound...]
        guard let endBrace = afterBrace.range(of: "\n  }") else { return nil }
        let inner = String(afterBrace[..<endBrace.lowerBound])

        var result: [String: Int] = [:]
        for line in inner.split(separator: "\n") {
            let s = String(line)
            guard s.hasPrefix("    "), !s.hasPrefix("     ") else { continue }
            let stripped = String(s.dropFirst(4))
            guard let colonRange = stripped.range(of: ": ") else { continue }
            let key = String(stripped[..<colonRange.lowerBound])
            let valStr = String(stripped[colonRange.upperBound...])
            if let v = Self.matchInt(valStr) { result[key] = v }
        }
        return result.isEmpty ? nil : result
    }
}
