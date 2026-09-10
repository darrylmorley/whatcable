import Foundation
import Testing
@testable import WhatCableDarwinBackend
import WhatCableCore

// MARK: - PortDiagnosticsWatcherCorpusSweepTests
//
// First corpus coverage for `PortDiagnosticsWatcher` (Watchers/PortDiagnosticsWatcher.swift).
//
// SEAM NOTE: `PortDiagnosticsWatcher.refresh()` reads live IOKit
// (`AppleSmartBatteryReader.properties()` and
// `PowerSourceWatcher.readAllPowerSources()`), so it is unreachable from a
// test. Two of its three per-entry builders, `healthCounters(from:)` and
// `eventTrace(from:)`, are `private static func`, so they cannot be called
// directly even via `@testable import` (Swift's `private` stays file-scoped
// regardless of the import). The third, `contract(from:)`, was opened to
// internal so the PDO slot sweep below drives production rather
// than a copy of it. Also fully reachable, and where the port-attribution
// logic actually lives, is
// `portKeyMap(entries:portKeys:sources:)`: a `nonisolated static func` with no
// IOKit dependency at all, taking plain `[String: Any]` / `[PowerSource]`
// values. This is the function the task brief is really about: it is the
// piece that decides which physical port an unlabelled `PortControllerInfo`
// array entry belongs to (issue class: idle-port entries have no port
// identifier at all, so `PowerControllerPortJoin`'s watts-based match is the
// load-bearing logic, with positional fallback only for entries with no
// watts signal). This file sweeps it against real probe-32 /
// probe-17 data.
//
// `PDO.decode` itself already has dedicated corpus coverage in
// `Tests/WhatCableCoreTests/PDODecodeCorpusSweepTests.swift`; this file does
// not duplicate that. Nothing here re-assembles a copy of a production
// builder any more: the PDO sweep below calls `contract(from:)` and
// `PowerSourceWatcher.contractEntries(from:)` themselves, on the same probe
// dicts, so a bug in either is caught rather than faithfully reproduced.
// `healthCounters(from:)` and `eventTrace(from:)` stay private and stay
// uncovered here; that residual gap is real.
@Suite("PortDiagnosticsWatcher corpus sweep - portKeyMap (probes 17 + 32)")
struct PortDiagnosticsWatcherCorpusSweepTests {

    // MARK: - Probe root (duplicated across sweep files by house convention)

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private static func allProbeFolders() -> [String] {
        (try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path)
            .filter { entry in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(
                    atPath: probeRoot.appendingPathComponent(entry).path,
                    isDirectory: &isDir
                )
                return isDir.boolValue
            }
            .sorted()
        ) ?? []
    }

    private static func loadProbeText(folder: String, fileName: String) -> String? {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Probe-32 PortControllerInfo extraction
    //
    // Duplicated (with light renaming) from
    // `PowerTelemetryParsingTests.extractPortControllerInfoItems` /
    // `findArraySection` / `parseFirstInt`, per the house rule of copying
    // shared parsing helpers into each new sweep file rather than editing an
    // existing one. See that file's doc comment for the full probe-32 format
    // notes; only the pieces this file needs are reproduced here.

    private static func parseFirstInt(from s: String) -> Int? {
        let trimmed = s.drop(while: { $0 == " " })
        let digits = trimmed.prefix { c in c.isNumber || c == "-" }
        return Int(digits)
    }

    private static func findArraySection(_ text: String, key: String) -> String? {
        let prefix = "  \(key) = "
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(prefix) {
                let rest = line.dropFirst(prefix.count).drop(while: { $0 == " " })
                if rest.hasPrefix("Array[") {
                    if let range = text.range(of: line) {
                        let afterLine = text[range.upperBound...]
                        if afterLine.hasPrefix("\n") { return String(afterLine.dropFirst()) }
                        return String(afterLine)
                    }
                }
            }
        }
        return nil
    }

    /// Parses one `PortControllerInfo` item into the same `[String: Any]`
    /// shape IOKit hands the production code, INCLUDING the
    /// `PortControllerPortPDO` array, which this parser previously did not
    /// read at all.
    ///
    /// TRAP: probe 32 prints each PDO word as a SIGNED decimal followed by a
    /// sign-extended 64-bit hex, e.g. `-2138272628 (0xffffffff808c8c8c)`. A
    /// PDO's type is bits 31:30 and every non-Fixed class sets bit 31, so
    /// every PPS, AVS, Variable and Battery word prints negative. A parser
    /// that accepts only digits reads zero non-Fixed PDOs and looks like a
    /// clean pass. `parseFirstInt` takes the sign, and `wcUInt32` in
    /// production truncates it back to the real 32-bit word.
    private static func extractPortControllerInfoItems(_ text: String) -> [[String: Any]] {
        guard let after = findArraySection(text, key: "PortControllerInfo") else { return [] }
        var items: [[String: Any]] = []
        var current: [String: Any] = [:]
        var pdoSlots: [NSNumber] = []
        var inItem = false
        var inPDOArray = false

        func finishItem() {
            current["PortControllerPortPDO"] = pdoSlots as NSArray
            items.append(current)
        }

        for line in after.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.contains("Dict[") {
                if inItem { finishItem() }
                current = [:]
                pdoSlots = []
                inPDOArray = false
                inItem = true
            } else if inItem && trimmed.hasPrefix("PortController") {
                // Any other PortController key ends the PDO array.
                inPDOArray = trimmed.hasPrefix("PortControllerPortPDO")
                if let eqRange = trimmed.range(of: " = ") {
                    let key = String(trimmed[..<eqRange.lowerBound])
                    let valStr = String(trimmed[eqRange.upperBound...]).drop(while: { $0 == " " })
                    if let n = parseFirstInt(from: String(valStr)) {
                        current[key] = NSNumber(value: n)
                    }
                }
            } else if inItem, inPDOArray, trimmed.hasPrefix("["),
                      let closeBracket = trimmed.firstIndex(of: "]") {
                // `[7]                 574451 (0x8c3f3)`: slot index, then the
                // word. Kept positionally, zeros included, because the raw
                // array is a fixed 13-slot layout and slot position is what
                // the RDO's object position indexes into.
                let rest = String(trimmed[trimmed.index(after: closeBracket)...])
                if let n = parseFirstInt(from: rest) {
                    pdoSlots.append(NSNumber(value: n))
                }
            } else if inItem && !trimmed.hasPrefix(" ") && !trimmed.isEmpty && !trimmed.hasPrefix("[") {
                break
            }
        }
        if inItem { finishItem() }
        return items
    }

    // MARK: - Probe-17 self-keyed PowerSource extraction
    //
    // Duplicated (with light renaming) from
    // `TransportWatcherSweepTests.parseDashBlocks` / `parseProperties` /
    // `extractWinningOption`, per the same house rule.

    private static func parseProperties(body: String, indent: String) -> [String: Any] {
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
            } else if let m = matchInt(valStr) {
                props[key] = NSNumber(value: m)
            }
        }
        return props
    }

    private static func matchInt(_ s: String) -> Int? {
        if let spaceIdx = s.firstIndex(of: " ") {
            if let v = Int(s[..<spaceIdx]) { return v }
        }
        return Int(s)
    }

    private static func parseDashBlocks(text: String, classPrefix: String) -> [[String: Any]] {
        let escapedPrefix = NSRegularExpression.escapedPattern(for: classPrefix)
        guard let regex = try? NSRegularExpression(pattern: "--- \(escapedPrefix)\\[\\d+\\] ---") else { return [] }
        let nsText = text as NSString
        let headerMatches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var blocks: [[String: Any]] = []
        for (i, match) in headerMatches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < headerMatches.count ? headerMatches[i + 1].range.lowerBound : nsText.length
            var body = nsText.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
            for sep in ["\n---", "\n==="] {
                if let r = body.range(of: sep) { body = String(body[..<r.lowerBound]) }
            }
            blocks.append(parseProperties(body: body, indent: "  "))
        }
        return blocks
    }

    private static func extractWinningOption(text: String, blockIndex: Int, classPrefix: String) -> [String: Int]? {
        let pattern = "--- \(classPrefix)[\(blockIndex)] ---"
        guard let headerRange = text.range(of: pattern) else { return nil }
        let bodyStart = headerRange.upperBound
        var body = String(text[bodyStart...])
        for sep in ["\n---", "\n==="] {
            if let r = body.range(of: sep) { body = String(body[..<r.lowerBound]) }
        }
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
            if let v = matchInt(valStr) { result[key] = v }
        }
        return result.isEmpty ? nil : result
    }

    /// Self-keyed `PowerSource` list from probe 17's flat `IOPortFeaturePowerSource`
    /// section, same construction TransportWatcherSweepTests / ChargingDiagnosticProbeSweepTests use.
    private static func parsePowerSources(text: String) -> [PowerSource] {
        let blocks = parseDashBlocks(text: text, classPrefix: "IOPortFeaturePowerSource")
        var result: [PowerSource] = []
        for (i, props) in blocks.enumerated() {
            let name = (props["PowerSourceName"] as? String) ?? "Unknown"
            let parentType = (props["ParentPortType"] as? NSNumber)?.intValue
                ?? (props["ParentBuiltInPortType"] as? NSNumber)?.intValue ?? 0
            let parentNum = (props["ParentBuiltInPortNumber"] as? NSNumber)?.intValue
                ?? (props["ParentPortNumber"] as? NSNumber)?.intValue ?? 0
            let winRaw = extractWinningOption(text: text, blockIndex: i, classPrefix: "IOPortFeaturePowerSource")
            let winning: PowerOption? = winRaw.flatMap { w in
                guard let v = w["Voltage (mV)"], v > 0 else { return nil }
                let c = w["Max Current (mA)"] ?? 0
                let p = w["Max Power (mW)"] ?? (v * c / 1000)
                return PowerOption(voltageMV: v, maxCurrentMA: c, maxPowerMW: p)
            }
            result.append(PowerSource(
                id: UInt64(1000 + i), name: name, parentPortType: parentType,
                parentPortNumber: parentNum, options: [], winning: winning
            ))
        }
        return result
    }

    // MARK: - Corpus sweep: portKeyMap

    @Test("Probe 17+32 sweep: portKeyMap resolves a key for every entry, watts-matched entries land on the matching source's own port")
    func portKeyMapSweep() {
        var foldersScanned = 0
        var entriesTotal = 0
        var wattsMatchedTotal = 0
        var positionalFallbackTotal = 0
        var outOfRangeFallbackTotal = 0

        for folder in Self.allProbeFolders() {
            guard let probe32 = Self.loadProbeText(folder: folder, fileName: "32_smart_battery_full_keys.json") else { continue }
            let entries = Self.extractPortControllerInfoItems(probe32)
            guard !entries.isEmpty else { continue }
            foldersScanned += 1
            entriesTotal += entries.count

            let sources: [PowerSource]
            if let probe17 = Self.loadProbeText(folder: folder, fileName: "17_deep_property_dump.json") {
                sources = Self.parsePowerSources(text: probe17)
            } else {
                sources = []
            }

            // portKeys: the HPM positional-traversal fallback list. We don't
            // have live IOKit's hpmPortKeys() here, so approximate it with a
            // plausible "2/1".."2/N" list sized to the entry count -- exactly
            // the shape portKeyMap expects for its positional-fallback branch,
            // without claiming it is the true HPM traversal order (which this
            // sweep cannot observe without IOKit).
            let portKeys = (1...max(entries.count, 1)).map { "2/\($0)" }

            let keyMap = PortDiagnosticsWatcher.portKeyMap(entries: entries, portKeys: portKeys, sources: sources)

            // Invariant 1: no two entries share a port key.
            //
            // This used to assert `keyMap.count == entries.count` ("every entry
            // resolves to SOME key"). That was the wrong invariant: it was
            // satisfied by handing two entries the same key, and the caller
            // writes `counters[key]` in offset order, so the second silently
            // overwrote the first. Issue #460 traded that for the honest
            // failure: when the watts join and the positional order contradict
            // each other about a port, the contradicting entry is dropped
            // rather than written onto some other port's key. Uniqueness is the
            // property that actually protects the display.
            #expect(Set(keyMap.values).count == keyMap.count,
                "\(folder): portKeyMap gave \(keyMap.count) entries only \(Set(keyMap.values).count) distinct keys")

            let sourcePortKeys = Set(sources.map(\.portKey))
            let maxPowers = entries.map { ($0["PortControllerMaxPower"] as? NSNumber)?.intValue ?? 0 }
            let wattsMap = PowerControllerPortJoin.portKeysByContent(controllerMaxPowerMW: maxPowers, sources: sources)

            // Watts keys that more than one entry claims. `portKeysByContent`
            // answers "does exactly one PORT draw this wattage?" per entry, so
            // two entries at the same wattage both name the same port. That is
            // a tie, not a match, and since issue #460 portKeyMap sends those
            // entries to the positional pass instead. Classify them the same
            // way here or the invariants below test the old behaviour.
            let contestedWattsKeys = Set(
                Dictionary(grouping: wattsMap, by: \.value)
                    .filter { $0.value.count > 1 }
                    .keys
            )

            for (offset, _) in entries.enumerated() {
                guard let resolvedKey = keyMap[offset] else { continue }
                if let wattsKey = wattsMap[offset], !contestedWattsKeys.contains(wattsKey) {
                    wattsMatchedTotal += 1
                    // Invariant 2: when the watts-based join resolves unambiguously,
                    // portKeyMap must use that key verbatim, never override it with
                    // the positional fallback. This is the actual `PowerControllerPortJoin`
                    // production logic under test, not a re-derivation of it.
                    #expect(resolvedKey == wattsKey,
                        "\(folder) entry[\(offset)]: watts-matched key \(wattsKey) but portKeyMap returned \(resolvedKey)")
                    #expect(sourcePortKeys.contains(resolvedKey),
                        "\(folder) entry[\(offset)]: watts-matched key \(resolvedKey) is not among the self-keyed source portKeys")
                } else if offset < portKeys.count {
                    positionalFallbackTotal += 1
                    #expect(resolvedKey == portKeys[offset],
                        "\(folder) entry[\(offset)]: expected positional fallback \(portKeys[offset]), got \(resolvedKey)")
                } else {
                    outOfRangeFallbackTotal += 1
                    #expect(resolvedKey == "2/\(offset + 1)",
                        "\(folder) entry[\(offset)]: expected out-of-range fallback 2/\(offset + 1), got \(resolvedKey)")
                }
            }
        }

        print("[PortDiagnosticsWatcherSweep] \(foldersScanned) folders, \(entriesTotal) entries, "
            + "\(wattsMatchedTotal) watts-matched, \(positionalFallbackTotal) positional-fallback, "
            + "\(outOfRangeFallbackTotal) out-of-range-fallback")

        // Coverage floor: actual counts measured directly from the on-disk
        // corpus during this pass (see printed sweep summary above for the
        // exact run's numbers). Floor set to ~85% of the measured folder
        // count so the assertion is falsifiable rather than a rubber stamp.
        //
        // Two-tier reality: only 12 probe-32 files are git-tracked (the
        // entries here are sourced from probe 32); the other ~375 are
        // on-disk-only. Gate on a raw-corpus-presence threshold well above
        // the 12-file fresh-clone case, so a fresh clone SKIPS these counts
        // instead of failing them, while the per-entry correctness checks
        // above (watts-match/positional/out-of-range resolution) keep
        // running unconditionally regardless of corpus size.
        if foldersScanned >= 50 {
            #expect(foldersScanned >= 240,
                "Expected at least 240 folders with probe-32 PortControllerInfo entries; got \(foldersScanned)")
            #expect(entriesTotal >= 240,
                "Expected at least 240 PortControllerInfo entries across the corpus; got \(entriesTotal)")
            // At least some watts-matched joins must occur, or the
            // PowerControllerPortJoin integration inside portKeyMap regressed
            // silently (this is the load-bearing path the whole function
            // exists for).
            #expect(wattsMatchedTotal >= 1,
                "Expected at least one watts-matched portKeyMap resolution across the corpus")
        }
    }

    // MARK: - Corpus sweep: the PDO slot array
    //
    // macOS lays `PortControllerPortPDO` out as a fixed 13-slot array, 7 SPR
    // slots then 6 EPR slots. `PortControllerNPDOs` counts only the SPR
    // offers, so every PPS, AVS and EPR offer sits AFTER that count. Trimming
    // the array to `NPDOs` therefore threw away 536 of the corpus's 540
    // non-Fixed offers, and left the RDO's object position 8 indexing past
    // the end of the list. These assertions drive the production factory,
    // `PortDiagnosticsWatcher.contract(from:)`, not a copy of it.

    private static func isNonFixed(_ pdo: PDO) -> Bool {
        if case .fixed = pdo { return false }
        return true
    }

    @Test("Probe 32 sweep: contract(from:) keeps the PPS/AVS/EPR offers that sit past PortControllerNPDOs, and no RDO reads object position 0")
    func pdoSlotSweep() {
        var foldersScanned = 0
        var entriesTotal = 0
        var contractsWithNonFixed = 0
        var nonFixedPDOs = 0
        var nonZeroRDOs = 0
        var zeroPositionRDOs = 0

        for folder in Self.allProbeFolders() {
            guard let probe32 = Self.loadProbeText(folder: folder, fileName: "32_smart_battery_full_keys.json") else { continue }
            let items = Self.extractPortControllerInfoItems(probe32)
            guard !items.isEmpty else { continue }
            foldersScanned += 1

            // Both producers, driven together on the same dicts. They must
            // agree that the slot array is passed through whole: the RDO's
            // object position names a slot number in it, so one of them
            // trimming and the other not means the two disagree about which
            // PDO the Mac is actually drawing from.
            let readerEntries = AppleSmartBatteryReader.parsePortControllerInfo(items)
            let synthesisEntries = PowerSourceWatcher.contractEntries(from: readerEntries)

            // Asserted before the loop so the per-entry checks below can index
            // unconditionally. A count check guarded by the count it is
            // checking goes dark instead of failing: dropping an entry removes
            // a whole physical port from power synthesis, with its offers and
            // its RDO, and a conditional index would simply stop running for
            // the missing tail.
            #expect(readerEntries.count == items.count,
                "\(folder): the reader returned \(readerEntries.count) entries for \(items.count) PortControllerInfo items")
            #expect(synthesisEntries.count == items.count,
                "\(folder): contractEntries returned \(synthesisEntries.count) entries for \(items.count) PortControllerInfo items")
            guard synthesisEntries.count == items.count else { continue }

            for (offset, dict) in items.enumerated() {
                entriesTotal += 1
                let rawSlotCount = wcArray(dict["PortControllerPortPDO"]).count
                let contract = PortDiagnosticsWatcher.contract(from: dict)

                // Exact, not a floor. A floor is a lower bound and a lower
                // bound cannot see a PARTIAL re-trim: cutting to NPDOs+4
                // still leaves 520 contracts carrying a non-Fixed PDO and
                // sails through the 500 floor below. This kills every trim,
                // partial or whole, on both producers.
                #expect(contract.pdoSlots.count == rawSlotCount,
                    "\(folder) entry[\(offset)]: contract(from:) kept \(contract.pdoSlots.count) of \(rawSlotCount) raw PDO slots")
                #expect(synthesisEntries[offset].rawPDOs.count == rawSlotCount,
                    "\(folder) entry[\(offset)]: PowerSourceWatcher.contractEntries kept \(synthesisEntries[offset].rawPDOs.count) of \(rawSlotCount) raw PDO slots")
                let nonFixed = contract.pdoList.filter(Self.isNonFixed)
                nonFixedPDOs += nonFixed.count
                if !nonFixed.isEmpty { contractsWithNonFixed += 1 }

                if contract.activeRdo != 0 {
                    nonZeroRDOs += 1
                    let position = PDContract.objectPosition(of: contract.activeRdo)
                    if position == 0 { zeroPositionRDOs += 1 }
                }
            }
        }

        print("[PortDiagnosticsWatcherSweep/PDO] \(foldersScanned) folders, \(entriesTotal) entries, "
            + "\(contractsWithNonFixed) contracts carrying a non-Fixed PDO, \(nonFixedPDOs) non-Fixed PDOs, "
            + "\(nonZeroRDOs) non-zero RDOs, \(zeroPositionRDOs) of them at object position 0")

        // Structural ceiling, not a floor. Rule 5 of
        // `research/corpus-parser-traps.md`: a floor is blind to double
        // counting, so bound the other side too. Every probe-32 file that
        // carries the key prints `PortControllerInfo` TWICE, and only the
        // 2-space top-level form is matched, which is why the entry count is
        // right today; loosen that prefix and both the 500 floor below and
        // the 240 entry floor in the sweep above still pass at 7784 entries.
        // Max entries per folder is 4, measured across the whole corpus (665
        // folders at 4, 294 at 3, 175 at 2), so even an all-4-port corpus
        // reaches only 4 per folder and 5 leaves a port's worth of headroom.
        //
        // 5 rather than 8 because 8 does not do the job: watched against a
        // simulated whole-corpus duplication, 7784 entries over 1134 folders
        // is 6.9 each and passes an 8. At 5 the same duplication fails, which
        // is the case this ceiling exists for.
        #expect(entriesTotal <= foldersScanned * 5,
            "\(entriesTotal) entries across \(foldersScanned) folders is more than 5 per folder; PortControllerInfo is probably being counted twice")

        // Object position is bits 31:28, four bits since PD 3.1. A 3-bit read
        // masks position 8 down to 0, which is the "no contract" value, so a
        // live EPR contract reads as no contract at all. Measured on this
        // corpus: 45 entries did that under the old 3-bit mask, 0 do now.
        // Unconditional: it is a property of every entry, not a corpus floor.
        #expect(zeroPositionRDOs == 0,
            "\(zeroPositionRDOs) of \(nonZeroRDOs) non-zero RDOs decoded to object position 0")

        // Corpus floor, gated the same skip-not-fail way as the sweep above:
        // a fresh clone without the raw corpus hard-linked in skips rather
        // than fails. Measured untrimmed: 534 contracts carry a non-Fixed
        // PDO, 529 once the implausible filler words are dropped (five words,
        // not four: the four `0x808c8c8c` fillers and `0xc00c30f5` on
        // m4_macos26.6_i). The trimmed reading found 4.
        //
        // What this floor guards, precisely: a FULL re-trim to NPDOs, which
        // drops it to 4. It does not catch a partial one. Measured
        // sensitivity: trimming to NPDOs+1, +2 or +3 still leaves 520
        // contracts and sails through, and NPDOs+5 leaves 530. The assertion
        // that closes NPDOs+1 to NPDOs+3 is `replayM5MaxEPRSelection`, where
        // NPDOs is 4 and slot 8 has to survive. Only a contrived NPDOs+4 trim
        // gets past the whole suite.
        if foldersScanned >= 50 {
            #expect(contractsWithNonFixed >= 500,
                "Expected at least 500 contracts carrying a non-Fixed PDO; got \(contractsWithNonFixed). A count near 4 means the PDO array is being trimmed to PortControllerNPDOs again.")
        }
    }

    @Test("Replay m1pro_macos26.5_y: entry 3 offers an SPR PPS supply at slot 6, past its NPDOs of 5")
    func replayM1ProPPSOffer() {
        guard let probe32 = Self.loadProbeText(folder: "m1pro_macos26.5_y", fileName: "32_smart_battery_full_keys.json") else { return }
        let items = Self.extractPortControllerInfoItems(probe32)
        guard items.count > 3 else {
            Issue.record("m1pro_macos26.5_y: expected at least 4 PortControllerInfo entries, got \(items.count)")
            return
        }
        let contract = PortDiagnosticsWatcher.contract(from: items[3])
        let hasPPS = contract.pdoList.contains { pdo in
            if case .pps = pdo { return true }
            return false
        }
        #expect(hasPPS, "expected a PPS offer in entry 3's PDO list, got \(contract.pdoList)")
    }

    @Test("Replay m5max_macos26.5.2_f: entry 3's RDO selects the 28 V EPR Fixed PDO at slot 8")
    func replayM5MaxEPRSelection() {
        guard let probe32 = Self.loadProbeText(folder: "m5max_macos26.5.2_f", fileName: "32_smart_battery_full_keys.json") else { return }
        let items = Self.extractPortControllerInfoItems(probe32)
        guard items.count > 3 else {
            Issue.record("m5max_macos26.5.2_f: expected at least 4 PortControllerInfo entries, got \(items.count)")
            return
        }
        let contract = PortDiagnosticsWatcher.contract(from: items[3])
        #expect(contract.activeRdo == 0x81c759d6)
        let position = PDContract.objectPosition(of: contract.activeRdo)
        let selected = contract.selectedPDO(for: contract.activeRdo)
        #expect(selected == .fixed(voltage: 28_000, maxCurrent: 4_990),
            "expected the 28 V / 4.99 A EPR Fixed PDO at object position \(position), got \(String(describing: selected))")
        // 28 000 mV * 4990 mA = 139 720 mW, which is what the controller
        // reports as the negotiated maximum.
        #expect(contract.maxPower == 139_720)
    }

    // MARK: - Fixture: idle-port positional fallback vs watts-matched entry
    //
    // The real corpus mostly has one or two entries per machine, so the
    // "idle entry falls back positionally while a live entry watts-matches"
    // scenario is easy to miss in a pure corpus sweep depending on which
    // machines happen to have both shapes at once. Restated here as an
    // explicit fixture so the two-tier fallback itself always has direct
    // coverage regardless of what today's corpus snapshot contains.
    @Test("Fixture: watts-matched entry takes its source's key; idle entry falls back positionally")
    func fixtureMixedWattsAndPositionalFallback() {
        let sources = [
            PowerSource(id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1, options: [],
                        winning: PowerOption(voltageMV: 20_000, maxCurrentMA: 3_250, maxPowerMW: 65_000)),
        ]
        let entries: [[String: Any]] = [
            ["PortControllerMaxPower": NSNumber(value: 65_000)],  // matches source above
            ["PortControllerMaxPower": NSNumber(value: 0)],       // idle: no watts signal
        ]
        let portKeys = ["2/1", "2/2"]
        let keyMap = PortDiagnosticsWatcher.portKeyMap(entries: entries, portKeys: portKeys, sources: sources)

        #expect(keyMap[0] == "2/1", "watts-matched entry should take the source's own portKey")
        #expect(keyMap[1] == "2/2", "idle entry with no watts signal should fall back to the positional HPM order")
    }

    @Test("Fixture: entry index beyond known HPM ports falls back to a best-effort 1-based key")
    func fixtureOutOfRangeFallback() {
        // Two entries but only one known port: the extra entry still surfaces
        // under a best-effort 1-based key rather than vanishing.
        let entries: [[String: Any]] = [
            ["PortControllerMaxPower": NSNumber(value: 0)],
            ["PortControllerMaxPower": NSNumber(value: 0)],
        ]
        let keyMap = PortDiagnosticsWatcher.portKeyMap(entries: entries, portKeys: ["2/1"], sources: [])
        #expect(keyMap[0] == "2/1")
        #expect(keyMap[1] == "2/2")
    }

    @Test("Fixture: an empty port-key list invents nothing")
    func fixtureNoPortOrderInventsNothing() {
        // This used to assert the entry got "2/1". Since issue #460 an empty
        // list is `hpmPortKeysRIDOrdered()` saying it could not establish the
        // order Apple built PortControllerInfo in, so index-based placement is
        // off the table entirely. Fabricating a port name for a real counter is
        // the failure this whole change exists to stop.
        let entries: [[String: Any]] = [["PortControllerMaxPower": NSNumber(value: 0)]]
        let keyMap = PortDiagnosticsWatcher.portKeyMap(entries: entries, portKeys: [], sources: [])
        #expect(keyMap.isEmpty)
    }
}
