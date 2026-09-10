import Foundation
import Testing
@testable import WhatCableCore

/// Corpus-replay sweep for `PowerSourceSynthesis` (issue #401).
///
/// For every corpus folder that has both probe 17 (`IOPortFeaturePowerSource`
/// nodes) and probe 32 (`AppleSmartBattery`'s `PortControllerInfo`) on disk,
/// this sweep:
///
/// 1. Parses probe 17 for real per-port power sources, so machines that
///    already have the node (everything except M1 Pro/Max/Ultra) can prove
///    synthesis stays a no-op on them.
/// 2. Parses probe 32's *first* `PortControllerInfo` dump (the probe prints
///    it more than once; see the comment on `firstPortControllerEntries`)
///    into `PowerSourceSynthesis.ContractEntry` fixtures.
/// 3. Parses probe 01 for port name/type/connectionActive, the same way
///    `DataLinkDiagnosticProbeSweepTests` does.
/// 4. Runs `PowerSourceSynthesis.synthesizedSource` with empty identities
///    (the partner-kind rung never fires; positional and sole-active carry
///    the sweep) and checks the invariants below.
///
/// Probe 17 and 32 are gitignored raw data; only `01_walk_pd_tree.json` is
/// committed. A fresh clone or worktree without the raw corpus fetched in
/// skips gracefully (see `hasBothProbes()`), matching the pattern
/// `TransportWatcherSweepTests` already uses.
@Suite("PowerSourceSynthesis -- customer probe sweep (issue #401)")
struct PowerSourceSynthesisProbeSweepTests {

    private typealias ContractEntry = PowerSourceSynthesis.ContractEntry

    // MARK: - Folder enumeration / skip gate

    private static func allFolders() -> [String] {
        ProbeCorpus.allFolders()
    }

    /// True when at least one folder has both probe 17 and probe 32 on disk.
    /// Lets every test below skip cleanly (rather than fail) on a fresh
    /// clone or a worktree that hasn't hard-linked the raw corpus in.
    private static func hasBothProbes() -> Bool {
        for folder in allFolders() {
            if ProbeCorpus.loadText(folder: folder, probe: "17_deep_property_dump") != nil,
               ProbeCorpus.loadText(folder: folder, probe: "32_smart_battery_full_keys") != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Probe 17: real per-port power sources

    /// Header for either probe-17 format: the flat "All services" dash style
    /// (`--- IOPortFeaturePowerSource[N] ---`) and the HPM deep-dive equals
    /// style (`=== IOPortFeaturePowerSource ===`, possibly indented under a
    /// nested `IOPortFeaturePowerIn` block). Matching the bare substring
    /// (no line anchor) picks up both regardless of indentation, mirroring
    /// the detection method documented in
    /// `research/magsafe-power-source-by-silicon.md`.
    private static let powerSourceHeaderRegex = try! NSRegularExpression(
        pattern: "(===|---) IOPortFeaturePowerSource(\\[\\d+\\])? (===|---)"
    )

    /// One real `IOPortFeaturePowerSource` block, reduced to what the
    /// synthesis gates need: which port it covers, and (best-effort) its
    /// winning contract so `PowerSource.hasLiveChargingContract` reads
    /// correctly for genuinely-charging real sources (MagSafe).
    private static func realPowerSources(text17: String) -> [PowerSource] {
        let ns = text17 as NSString
        let matches = powerSourceHeaderRegex.matches(in: text17, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }

        var result: [PowerSource] = []
        for (i, match) in matches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < matches.count ? matches[i + 1].range.location : min(bodyStart + 1500, ns.length)
            guard bodyEnd > bodyStart else { continue }
            let body = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))

            let parentType = intField(body, key: "ParentPortType") ?? intField(body, key: "ParentBuiltInPortType") ?? 0
            let parentNumber = intField(body, key: "ParentBuiltInPortNumber") ?? intField(body, key: "ParentPortNumber") ?? 0
            let name = stringField(body, key: "PowerSourceName") ?? "Unknown"
            let winning = winningOption(in: body)

            result.append(PowerSource(
                id: UInt64(9000 + i),
                name: name,
                parentPortType: parentType,
                parentPortNumber: parentNumber,
                options: [],
                winning: winning
            ))
        }
        return result
    }

    /// Scoped scan for `WinningPowerSourceOption`'s Voltage/Current/Power
    /// fields. Scoped to the substring between the marker and its own first
    /// `}` so it can't accidentally pick up a value from the sibling
    /// `PowerSourceOptions` set (which has its own "Voltage (mV)" fields per
    /// option).
    private static func winningOption(in body: String) -> PowerOption? {
        guard let start = body.range(of: "WinningPowerSourceOption: {") else { return nil }
        let after = body[start.upperBound...]
        guard let end = after.firstIndex(of: "}") else { return nil }
        let inner = String(after[..<end])
        guard let v = intField(inner, key: "Voltage (mV)"), v > 0 else { return nil }
        let c = intField(inner, key: "Max Current (mA)") ?? 0
        let p = intField(inner, key: "Max Power (mW)") ?? (v * c / 1000)
        return PowerOption(voltageMV: v, maxCurrentMA: c, maxPowerMW: p)
    }

    private static func intField(_ body: String, key: String) -> Int? {
        guard let range = body.range(of: "\(key):") else { return nil }
        let after = body[range.upperBound...].drop(while: { $0 == " " })
        let digits = after.prefix { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    private static func stringField(_ body: String, key: String) -> String? {
        guard let range = body.range(of: "\(key):") else { return nil }
        let after = body[range.upperBound...]
        guard let q1 = after.firstIndex(of: "\"") else { return nil }
        let afterQ1 = after[after.index(after: q1)...]
        guard let q2 = afterQ1.firstIndex(of: "\"") else { return nil }
        return String(afterQ1[..<q2])
    }

    // MARK: - Probe 32: first PortControllerInfo dump

    /// Probe 32 prints `PortControllerInfo` more than once (once in the flat
    /// top-level dump, again nested inside a duplicate section). Both copies
    /// carry the same data, but only the *first* is parsed, per the brief:
    /// take the first complete set. Indentation is variable across machines
    /// (2-space top-level dump vs deeper nested dumps) but internally
    /// consistent: array items sit 4 spaces deeper than the
    /// `PortControllerInfo =` marker line, and each item's own properties sit
    /// 4 spaces deeper again. Detecting the marker's own indent and working
    /// relative to it handles both depths without hardcoding either.
    /// One parsed entry: the `ContractEntry` production consumes, plus the
    /// raw `PortControllerPDst` beside it. Port state 5 is "explicit contract
    /// in place", which is what makes an entry a LIVE contract, and it is not
    /// part of `ContractEntry` because synthesis does not gate on it.
    private struct ParsedEntry {
        let entry: ContractEntry
        let pdState: Int
    }

    private static func firstPortControllerEntries(text32: String) -> [ParsedEntry] {
        let lines = text32.components(separatedBy: "\n")
        guard let markerIdx = lines.firstIndex(where: { $0.contains("PortControllerInfo =") }) else { return [] }
        let markerIndent = lines[markerIdx].prefix { $0 == " " }.count
        let itemIndent = markerIndent + 4
        let propIndent = itemIndent + 4
        let propPrefix = String(repeating: " ", count: propIndent)
        let pdoInnerPrefix = String(repeating: " ", count: propIndent + 4)

        // Item header lines look like "<itemIndent>[N] ... Dict[M]:". Collect
        // their line indices; stop at the first line that dedents below
        // itemIndent (the array has ended).
        var itemStarts: [Int] = []
        var i = markerIdx + 1
        while i < lines.count {
            let line = lines[i]
            let indent = line.prefix { $0 == " " }.count
            if indent < itemIndent {
                break
            }
            if indent == itemIndent, line.dropFirst(itemIndent).hasPrefix("[") {
                itemStarts.append(i)
            }
            i += 1
        }
        guard !itemStarts.isEmpty else { return [] }

        var entries: [ParsedEntry] = []
        for (idx, start) in itemStarts.enumerated() {
            let end = idx + 1 < itemStarts.count ? itemStarts[idx + 1] : lines.count
            var maxPower = 0
            var activeRdo: UInt32 = 0
            var npdos = 0
            var pdState = 0
            var rawPDOs: [UInt32] = []
            var j = start + 1
            while j < end {
                let line = lines[j]
                if line.hasPrefix(propPrefix), !line.hasPrefix(propPrefix + " "),
                   let eq = line.range(of: " = ") {
                    let key = String(line[line.index(line.startIndex, offsetBy: propIndent)..<eq.lowerBound])
                    // Values are padded with extra spaces after "= " (e.g.
                    // "PortControllerMaxPower =             100000 (0x186a0)"),
                    // and ProbeCorpus.matchInt requires no leading whitespace.
                    let valStr = String(line[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "PortControllerMaxPower":
                        maxPower = ProbeCorpus.matchInt(valStr) ?? 0
                    case "PortControllerActiveContractRdo":
                        if let v = ProbeCorpus.matchInt(valStr) { activeRdo = UInt32(truncatingIfNeeded: v) }
                    case "PortControllerNPDOs":
                        npdos = ProbeCorpus.matchInt(valStr) ?? 0
                    case "PortControllerPDst":
                        pdState = ProbeCorpus.matchInt(valStr) ?? 0
                    case "PortControllerPortPDO":
                        var k = j + 1
                        while k < end {
                            let sub = lines[k]
                            guard sub.hasPrefix(pdoInnerPrefix), !sub.hasPrefix(pdoInnerPrefix + " ") else { break }
                            let subStripped = sub.dropFirst(pdoInnerPrefix.count)
                            guard subStripped.hasPrefix("["), let closeBr = subStripped.firstIndex(of: "]") else { break }
                            let valuePart = subStripped[subStripped.index(after: closeBr)...]
                                .trimmingCharacters(in: .whitespaces)
                            if let v = ProbeCorpus.matchInt(valuePart) {
                                rawPDOs.append(UInt32(truncatingIfNeeded: v))
                            }
                            k += 1
                        }
                    default:
                        break
                    }
                }
                j += 1
            }
            // Untrimmed on purpose. `PortControllerNPDOs` counts only the SPR
            // offers, so cutting the array to it hides every PPS, AVS and EPR
            // offer and leaves the RDO's object position 8 indexing past the
            // end. `npdos` is parsed only so this comment can point at it.
            _ = npdos
            entries.append(ParsedEntry(
                entry: ContractEntry(index: idx, rawPDOs: rawPDOs, activeRdo: activeRdo, maxPowerMW: maxPower),
                pdState: pdState
            ))
        }
        return entries
    }

    // MARK: - Probe 01: ports

    private struct ProbePort {
        let portTypeDescription: String?
        let portNumber: Int
        let connectionActive: Bool

        /// Maps probe 01's `PortTypeDescription` to the raw `PortType` value
        /// `PowerSourceSynthesis.isValidTarget` gates on (USB-C = "2").
        /// Mapping every non-MagSafe type to "2" would let a filtered port
        /// type pose as a USB-C synthesis target: A18 Pro ("MacBook Neo")
        /// corpus machines have `Port-Inductive` ports (raw PortType 18),
        /// which must NOT satisfy the USB-C gate. Only "USB-C" maps to "2";
        /// "Inductive" maps to its own real raw value; anything else falls
        /// back to "0" (a value that is neither USB-C nor MagSafe), so an
        /// unrecognised future port type still can't game the gate.
        fileprivate static func rawPortType(for portTypeDescription: String?) -> String {
            switch portTypeDescription {
            case "USB-C": return "2"
            case let d? where d.hasPrefix("MagSafe"): return "17"
            case "Inductive": return "18"
            default: return "0"
            }
        }

        var asAppleHPMInterface: AppleHPMInterface {
            let rawType = Self.rawPortType(for: portTypeDescription)
            return AppleHPMInterface(
                id: UInt64(portNumber),
                serviceName: "Port-\(portTypeDescription ?? "USB-C")@\(portNumber)",
                className: "AppleHPMInterfaceType10",
                portDescription: nil,
                portTypeDescription: portTypeDescription,
                portNumber: portNumber,
                connectionActive: connectionActive,
                activeCable: nil,
                opticalCable: nil,
                usbActive: nil,
                superSpeedActive: nil,
                usbModeType: nil,
                usbConnectString: nil,
                transportsSupported: [],
                transportsActive: [],
                transportsProvisioned: [],
                plugOrientation: nil,
                plugEventCount: nil,
                connectionCount: nil,
                overcurrentCount: nil,
                pinConfiguration: [:],
                powerCurrentLimits: [],
                firmwareVersion: nil,
                bootFlagsHex: nil,
                rawProperties: ["PortType": rawType]
            )
        }
    }

    /// Parse `01_walk_pd_tree.json` the same way `DataLinkDiagnosticProbeSweepTests`
    /// does: split on the `=== IOAccessoryManager[` block header.
    private static func loadPorts(folder: String) -> [ProbePort] {
        guard let text = ProbeCorpus.loadText(folder: folder, probe: "01_walk_pd_tree") else { return [] }
        let rawChunks = text.components(separatedBy: "=== IOAccessoryManager[")
        guard rawChunks.count > 1 else { return [] }
        let parts: [String] = rawChunks.dropFirst().compactMap { chunk in
            guard let endOfHeader = chunk.range(of: "===\n") else { return nil }
            return String(chunk[endOfHeader.upperBound...])
        }

        var ports: [ProbePort] = []
        for raw in parts {
            let body: String
            if let endRange = raw.range(of: "\n=== ") {
                body = String(raw[..<endRange.lowerBound])
            } else {
                body = raw
            }
            guard body.contains("PortTypeDescription") else { continue }
            let portType = quotedField(body, key: "PortTypeDescription")
            let portNumber = numberField(body, key: "PortNumber") ?? 0
            let conn = body.contains("ConnectionActive = true")
            ports.append(ProbePort(portTypeDescription: portType, portNumber: portNumber, connectionActive: conn))
        }
        return ports
    }

    private static func quotedField(_ block: String, key: String) -> String? {
        let prefix = "    \(key) = \""
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) {
                let after = line.dropFirst(prefix.count)
                guard let closing = after.firstIndex(of: "\"") else { return nil }
                return String(after[..<closing])
            }
        }
        return nil
    }

    private static func numberField(_ block: String, key: String) -> Int? {
        let prefix = "    \(key) = "
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) {
                let after = line.dropFirst(prefix.count)
                let digits = after.prefix { $0.isNumber }
                return Int(digits)
            }
        }
        return nil
    }

    // MARK: - Sweep

    @Test("Sweep: real-node machines never synthesize; synthesized machines attribute to a real, active, non-MagSafe port; at least 5 machines synthesize")
    func sweep() {
        guard Self.hasBothProbes() else {
            // Fresh clone / worktree without the raw corpus fetched in.
            // Nothing to check; pass trivially.
            return
        }

        var machinesChecked = 0
        var machinesWithRealSources = 0
        var machinesSynthesized = 0
        var outcomeLines: [String] = []

        for folder in Self.allFolders() {
            guard let text17 = ProbeCorpus.loadText(folder: folder, probe: "17_deep_property_dump"),
                  let text32 = ProbeCorpus.loadText(folder: folder, probe: "32_smart_battery_full_keys")
            else { continue }

            machinesChecked += 1

            let realSources = Self.realPowerSources(text17: text17)
            let entries = Self.firstPortControllerEntries(text32: text32).map(\.entry)
            let probePorts = Self.loadPorts(folder: folder)
            let ports = probePorts.map { $0.asAppleHPMInterface }
            // Positional keys: the same HPM traversal order assumption
            // PortDiagnosticsWatcher.portKeyMap and PowerSourceSynthesis's
            // rung (a) both rely on. Probe 01 doesn't preserve that exact
            // traversal, so we approximate with each port's own key in the
            // order probe 01 listed them -- good enough for the sweep, since
            // rung (a) failing just falls through to rung (c) here (no
            // identities are fed, so rung (b) never fires either way).
            let positionalPortKeys = ports.compactMap { $0.portKey }

            if !realSources.isEmpty {
                machinesWithRealSources += 1
                // Invariant (a): a machine with real per-port sources never
                // gets a synthesized one on top.
                let result = PowerSourceSynthesis.synthesizedSource(
                    realSources: realSources,
                    ports: ports,
                    identities: [],
                    entries: entries,
                    positionalPortKeys: positionalPortKeys,
                    externalConnected: true
                )
                #expect(result == nil, "\(folder): expected nil (real node already present), got a synthesized source")
                outcomeLines.append("\(folder): real node present, \(realSources.count) source(s), synthesis correctly skipped")
                continue
            }

            // No real per-port sources at all: the candidate case (M1 Pro/Max/Ultra).
            let result = PowerSourceSynthesis.synthesizedSource(
                realSources: [],
                ports: ports,
                identities: [],
                entries: entries,
                positionalPortKeys: positionalPortKeys,
                externalConnected: true
            )

            if let result {
                machinesSynthesized += 1
                // Invariant (b): attributed to a port that was active in
                // probe 01 and is explicitly USB-C (raw PortType "2"), not
                // just "not MagSafe" (which an Inductive port would also
                // satisfy).
                let matchingPort = probePorts.first { port in
                    let rawType = ProbePort.rawPortType(for: port.portTypeDescription)
                    return Int(rawType) == result.parentPortType && port.portNumber == result.parentPortNumber
                }
                #expect(matchingPort != nil, "\(folder): synthesized source \(result.portKey) doesn't match any parsed probe-01 port")
                #expect(matchingPort?.connectionActive == true, "\(folder): synthesized source's port wasn't active in probe 01")
                #expect(matchingPort?.portTypeDescription == "USB-C", "\(folder): synthesized source landed on a non-USB-C port (\(matchingPort?.portTypeDescription ?? "nil"))")
                outcomeLines.append("\(folder): synthesized -> \(result.portKey), winning=\(result.winning?.maxPowerMW ?? -1)mW, options=\(result.options.count)")
            } else {
                outcomeLines.append("\(folder): no real sources, no synthesis (no live/attributable entry)")
            }
        }

        // Invariant (c): the function's return type is a single Optional, so
        // "at most one synthesized source per machine" holds by construction;
        // nothing further to assert there.

        print("PowerSourceSynthesis corpus sweep: \(machinesChecked) machines checked, "
            + "\(machinesWithRealSources) with a real node, \(machinesSynthesized) synthesized")
        // Synthesized machines are the interesting minority: always print all
        // of them, and cap only the routine skip/no-synthesis lines.
        for line in outcomeLines where line.contains("synthesized ->") {
            print("  \(line)")
        }
        let routine = outcomeLines.filter { !$0.contains("synthesized ->") }
        for line in routine.prefix(40) {
            print("  \(line)")
        }
        if routine.count > 40 {
            print("  ... (\(routine.count - 40) more routine lines)")
        }

        // `hasBothProbes()` above only gates on at least ONE folder having
        // both probes on disk, so it lets the sweep run against a partial
        // corpus too (e.g. a worktree mid hard-link, or a stray couple of
        // folders). The coverage floors below make a claim about the FULL
        // corpus, not "whatever happens to be present", so they need their
        // own stronger gate: skip (not fail) when machinesChecked doesn't
        // clear the same bar the floor asserts, matching the skip-not-fail
        // convention in PDODecodeCorpusSweepTests.hasFullRawCorpus(). Raw
        // probes 17 and 32 live on disk in the primary repo only (neither is
        // a tracked fixture -- see the file-header comment), so a fresh
        // clone or worktree without them hard-linked in would otherwise fail
        // here for a reason that has nothing to do with the code under test.
        guard machinesChecked > 20 else { return }
        #expect(machinesSynthesized >= 5,
            "Expected at least 5 machines to synthesize (the known M1 Pro/Max/Ultra USB-C-charging cases); got \(machinesSynthesized). A count of 0 would mean this sweep isn't exercising the synthesis path at all.")
    }
    // MARK: - Live contracts: the winning option must be the negotiated one

    /// For every corpus entry that is a LIVE contract (`PortControllerPDst`
    /// 5, RDO valid bit set), the option the RDO names must be the wattage
    /// the controller reports in `PortControllerMaxPower`. All 32 such
    /// entries in the corpus select object position 8, which is the first EPR
    /// slot, and every one of them sits past `PortControllerNPDOs`.
    ///
    /// This cannot go through `synthesizedSource`: gate 1 there returns nil
    /// for any machine that already publishes a real
    /// `IOPortFeaturePowerSource` node, and 31 of the 32 folders do. So the
    /// test drives the option and winning-option path directly. No production
    /// gate is weakened to make it pass.
    @Test("Sweep: every live PD contract's winning option carries PortControllerMaxPower")
    func liveContractsWinAtTheirReportedWattage() {
        guard Self.hasBothProbes() else { return }

        var foldersScanned = 0
        var liveContracts = 0

        for folder in Self.allFolders() {
            guard let text32 = ProbeCorpus.loadText(folder: folder, probe: "32_smart_battery_full_keys") else { continue }
            let parsed = Self.firstPortControllerEntries(text32: text32)
            guard !parsed.isEmpty else { continue }
            foldersScanned += 1

            for item in parsed {
                // Port state 5 plus the RDO's valid bit: an explicit contract
                // is in place and the RDO is meaningful.
                guard item.pdState == 5, item.entry.activeRdo & 0x8000_0000 != 0 else { continue }
                liveContracts += 1

                let positionalOptions = item.entry.rawPDOs
                    .map(PDO.decode(rawValue:))
                    .map(PowerSourceSynthesis.option(for:))
                let sortedOptions = positionalOptions.compactMap { $0 }
                    .sorted { $0.maxPowerMW > $1.maxPowerMW }
                let winning = PowerSourceSynthesis.winningOption(
                    entry: item.entry,
                    positionalOptions: positionalOptions,
                    sortedOptions: sortedOptions
                )

                let position = PDContract.objectPosition(of: item.entry.activeRdo)
                #expect(winning != nil,
                    "\(folder) entry[\(item.entry.index)]: live contract, RDO object position \(position), but no winning option was derived from \(item.entry.rawPDOs.count) PDO slots")
                #expect(winning?.maxPowerMW == item.entry.maxPowerMW,
                    "\(folder) entry[\(item.entry.index)]: winning option is \(winning?.maxPowerMW ?? -1) mW, PortControllerMaxPower is \(item.entry.maxPowerMW) mW")
            }
        }

        print("PowerSourceSynthesis live-contract sweep: \(foldersScanned) folders, \(liveContracts) live contracts")

        // Same skip-not-fail gate the sweep above uses: a partial corpus
        // skips the floor rather than failing it.
        guard foldersScanned > 20 else { return }
        #expect(liveContracts >= 30,
            "Expected at least 30 live PD contracts across the corpus (32 measured); got \(liveContracts)")
    }
}
