import Foundation
import Testing
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

// MARK: - Python oracle crosscheck suite
//
// Every other corpus-sweep test in this repo checks the Swift parsers against
// themselves (does the parser produce a sane-looking value). This suite is
// different: it checks the PRODUCTION Swift parsers against `corpus.jsonl`,
// which is produced by `inspect-probe.py`, a completely independent
// Python implementation that reads the same raw probe text. Two independent
// implementations agreeing on the same raw bytes is real evidence; one
// implementation agreeing with itself is not.
//
// Six checks are implemented, each described in the MARK header for its
// suite below: cable e-marker identity, device identity, zeroed-VID trust,
// TRM restriction count, CIO block count, and advanced-PD kinds. A seventh
// area, cumulative hard-reset counts, is explicitly NOT covered: probe 19's
// `hardResets=` / `attach=` line has no production Swift parser today, only
// `inspect-probe.py`'s `parse_hard_resets` reads it. There is nothing
// to cross-check it against, so no test is written for it. If a Swift
// consumer of that line is ever added, this file is the place to add the
// crosscheck.
//
// Known Python-side scope mismatches found while building this suite (see
// the per-check comments below for detail and folder counts):
//   - Zeroed-VID trust detection: Python's zeroed-cable definition (blank
//     VID + a nonzero 4th VDO) does not distinguish the case where the SOP
//     partner (the connector) identifies the same cable as a registered
//     vendor. Swift's `CableTrustReport` does distinguish that case
//     (`.eMarkerVIDBlankRegisteredPartner` instead of `.zeroVendorID`, a
//     `.note` not a `.warning`). Check 3 treats either flag as satisfying
//     the Python-side "zeroed" condition and documents this rather than
//     forcing an exact single-case match.
//
// One PREVIOUSLY known scope mismatch has since been FIXED at the source,
// not worked around here: `advanced_pd` in corpus.jsonl used to contain the
// bare kind "EPR" purely because a plain Fixed Supply PDO sets its
// "EPR-Capable" flag bit; that text substring-matched "EPR" even though the
// PDO was not an EPR AVS APDO and Swift's `PDO.decode` never produces
// `.eprAvs` for it (226 of 410 folders were affected between the "EPR" and
// "PPS" bare-substring cases combined). `inspect-probe.py`'s
// `parse_pdo` was corrected (2026-07) to match the actual decoded-PDO label
// the probe prints ("SPR PPS ..." / "EPR AVS ..." / "SPR AVS ...") instead
// of a bare substring anywhere in the dump, and the corpus was regenerated.
// Check 6 below now asserts full agreement with no carve-out.
//
// Duplication note: this file cannot import the private test-file-scoped
// helpers in `WatcherCorpusSweepTests.swift` or `TransportWatcherSweepTests.swift`
// (Swift's `private` is file-scoped, and several relevant helpers there are
// members of a `struct` and additionally `private static`), so the small
// amount of probe-parsing scaffolding needed here is duplicated rather than
// shared, matching the existing convention in this test target (those two
// files already duplicate a lot of the same parsing logic from each other).
// Each duplicated helper below says which file it mirrors.

// MARK: - Corpus root and folder enumeration (mirrors WatcherCorpusSweepTests.swift)

private let oracleProbeRoot: URL = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // WhatCableDarwinTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("research/customer-probes")
}()

private func oracleAllProbeFolders() -> [String] {
    (try? FileManager.default
        .contentsOfDirectory(atPath: oracleProbeRoot.path)
        .filter { entry in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(
                atPath: oracleProbeRoot.appendingPathComponent(entry).path,
                isDirectory: &isDir
            )
            return isDir.boolValue
        }
        .sorted()
    ) ?? []
}

/// Load the `"output"` text from a numbered probe JSON file. Returns nil when
/// the file is absent (fresh clone, raw probes not fetched from KV) OR when
/// the JSON fails to parse (one folder in the corpus, m2pro_macos26.5.1_h,
/// has a malformed `17_deep_property_dump.json`; `inspect-probe.py`'s
/// `out_of()` treats that the same way, returning None, so mirroring that
/// here keeps both sides skipping the same folder for the same reason).
private func oracleLoadProbeText(folder: String, probe: String) -> String? {
    let url = oracleProbeRoot
        .appendingPathComponent(folder)
        .appendingPathComponent("\(probe).json")
    guard FileManager.default.fileExists(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let text = root["output"] as? String
    else { return nil }
    return text
}

// MARK: - corpus.jsonl loader
//
// `corpus.jsonl` is git-tracked (one JSON object per line, produced by
// `inspect-probe.py`), so it is always present, even on a fresh
// clone that hasn't fetched raw probes from KV. The per-check floor
// assertions below are gated on the raw probe files (via
// `oracleLoadProbeText` returning non-nil), not on this loader, so a fresh
// clone still skips the floor assertions trivially.

private func oracleLoadCorpusRecords() -> [String: [String: Any]] {
    let url = oracleProbeRoot.appendingPathComponent("corpus.jsonl")
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8)
    else { return [:] }

    var records: [String: [String: Any]] = [:]
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let lineData = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let folder = obj["folder"] as? String
        else { continue }
        records[folder] = obj
    }
    return records
}

/// True when `probe` appears in this record's `truncated` list (a pipe-buffer
/// bug in the test-kit runner cuts probe output at exactly 65536 bytes; the
/// data up to that point is real, but a probe on this list may be missing a
/// property that would otherwise have appeared past the cut). Per the task
/// brief, checks skip folders where the specific probe they depend on was
/// truncated, rather than risk a mismatch caused by a mid-property cut.
private func oracleProbeTruncated(_ record: [String: Any], _ probe: String) -> Bool {
    ((record["truncated"] as? [String]) ?? []).contains(probe)
}

// MARK: - Probe-01 SOP/SOP'/SOP'' block parser + per-port identity aggregation
//
// The block-splitting approach (split on "=== ", keep CCUSBPDSOP* blocks,
// parse top-level "KEY = VALUE" lines plus a nested Metadata sub-dict) mirrors
// `WatcherCorpusSweepTests.loadSOPBlocks`, duplicated per the file-header note
// above. Extended with `bodyText` (the raw block substring) so the
// identity-less skip gate below can substring-match exactly the way
// `inspect-probe.py`'s regexes do, independent of the resolved Int values
// `USBPDSOPWatcher.parseIdentity` returns (a real zeroed VID, 0x0000, is
// otherwise indistinguishable from "the property was never printed").

private struct OracleSOPBlock {
    let className: String
    /// Physical port number, parsed the same way `inspect-probe.py`'s
    /// `parse_pd_tree` does: `Description = "Port-USB-C@(\d+)`, no "/CC"
    /// suffix requirement (confirmed to match on all 821 SOP/SOP' blocks in
    /// the corpus; see the file-header verification notes).
    let portKey: Int
    let bodyText: String
    let read: (String) -> Any?
}

private func oracleLoadSOPBlocks(folder: String) -> [OracleSOPBlock] {
    guard let text = oracleLoadProbeText(folder: folder, probe: "01_walk_pd_tree") else { return [] }

    let blocks = text.components(separatedBy: "=== ").dropFirst()
    var results: [OracleSOPBlock] = []

    for block in blocks {
        guard block.contains("CCUSBPDSOP") else { continue }

        let firstLine = String(block.prefix(while: { $0 != "\n" }))
        let className = firstLine.replacingOccurrences(
            of: #"\[\d+\].*$"#, with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
        guard className.hasPrefix("IOPortTransportComponentCCUSBPDSOP") else { continue }

        var portKey = 0
        if let re = try? NSRegularExpression(pattern: #"Description = "Port-USB-C@(\d+)"#),
           let m = re.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
           let r = Range(m.range(at: 1), in: block),
           let n = Int(block[r]) {
            portKey = n
        }

        var dict: [String: Any] = [:]
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("Metadata =") || t.hasPrefix("Metadata:") {
                let bodyLines = Array(lines[(i + 1)...])
                var metaDict: [String: Any] = [:]
                var j = 0
                var vdos: [Data] = []
                var inVDOs = false
                while j < bodyLines.count {
                    let ml = bodyLines[j].trimmingCharacters(in: .whitespaces)
                    if ml == "}" { break }
                    if ml.hasPrefix("VDOs") { inVDOs = true; j += 1; continue }
                    if inVDOs {
                        if ml == "]" { inVDOs = false; j += 1; continue }
                        if let re = try? NSRegularExpression(pattern: #"<data 4 bytes: ([0-9a-fA-F ]+)>"#),
                           let m = re.firstMatch(in: ml, range: NSRange(ml.startIndex..., in: ml)),
                           let r = Range(m.range(at: 1), in: ml) {
                            let parts = String(ml[r]).split(separator: " ").compactMap { UInt8($0, radix: 16) }
                            if parts.count == 4 { vdos.append(Data(parts)) }
                        }
                        j += 1; continue
                    }
                    if let sep = ml.range(of: " = ") {
                        let key = String(ml[..<sep.lowerBound])
                        let val = String(ml[sep.upperBound...])
                        if val == "true" { metaDict[key] = NSNumber(value: true) }
                        else if val == "false" { metaDict[key] = NSNumber(value: false) }
                        else if val.hasPrefix("\""), val.hasSuffix("\""), val.count >= 2 {
                            metaDict[key] = String(val.dropFirst().dropLast())
                        } else {
                            let digits = val.prefix { $0.isNumber }
                            if !digits.isEmpty, let num = Int(digits) { metaDict[key] = NSNumber(value: num) }
                        }
                    }
                    j += 1
                }
                if !vdos.isEmpty { metaDict["VDOs"] = vdos as [Any] }
                dict["Metadata"] = metaDict as Any
                i += 1
                continue
            }

            if line.hasPrefix("    "), let sep = t.range(of: " = ") {
                let key = String(t[..<sep.lowerBound])
                let val = String(t[sep.upperBound...])
                if val == "true" { dict[key] = NSNumber(value: true) }
                else if val == "false" { dict[key] = NSNumber(value: false) }
                else if val.hasPrefix("\""), val.hasSuffix("\""), val.count >= 2 {
                    dict[key] = String(val.dropFirst().dropLast())
                } else {
                    let digits = val.prefix { $0.isNumber }
                    if !digits.isEmpty, let num = Int(digits) { dict[key] = NSNumber(value: num) }
                }
            }
            i += 1
        }

        let readFn: (String) -> Any? = { dict[$0] }
        results.append(OracleSOPBlock(className: className, portKey: portKey, bodyText: String(block), read: readFn))
    }
    return results
}

private struct OraclePortIdentities {
    var cable: USBPDSOP?
    var device: USBPDSOP?
}

/// Groups every SOP/SOP' identity in a folder by physical port, mirroring
/// `inspect-probe.py`'s `parse_pd_tree` exactly:
///   - a block with no "Vendor ID = " text, no 4th VDO (cable_vdo), and no
///     "Product Type Description = " text is "not read on this connection"
///     and is dropped entirely (not recorded as a zeroed identity);
///   - the FIRST cable-kind (SOP'/SOP'') block per port wins (Python's
///     `ports[port].setdefault('cable', e)`);
///   - the LAST device-kind (SOP) block per port wins (Python's
///     `ports[port]['device'] = e`, an unconditional overwrite).
/// The corpus has no SOP'' blocks as of 2026-07 (confirmed in
/// `VDMIdentitySweepTests`), so the setdefault-vs-overwrite asymmetry above
/// rarely has more than one candidate to choose between in practice, but is
/// implemented to match Python precisely regardless.
private func oracleBuildPortIdentities(folder: String) -> [Int: OraclePortIdentities] {
    var ports: [Int: OraclePortIdentities] = [:]

    for (idx, block) in oracleLoadSOPBlocks(folder: folder).enumerated() {
        let isCable = block.className.hasSuffix("SOPp") || block.className.hasSuffix("SOPpp")
        let isDevice = !isCable && block.className.hasSuffix("SOP")
        guard isCable || isDevice else { continue }

        guard let identity = USBPDSOPWatcher.parseIdentity(
            entryID: UInt64(idx + 1),
            read: block.read,
            className: block.className,
            hpmControllerUUID: nil
        ) else { continue }

        let hasVendorIDText = block.bodyText.contains("Vendor ID = ")
        let hasPTDText = block.bodyText.contains("Product Type Description = \"")
        if !hasVendorIDText && identity.vdos.count < 4 && !hasPTDText { continue }

        if isCable {
            if ports[block.portKey, default: OraclePortIdentities()].cable == nil {
                ports[block.portKey, default: OraclePortIdentities()].cable = identity
            }
        } else {
            ports[block.portKey, default: OraclePortIdentities()].device = identity
        }
    }
    return ports
}

/// (vid, pid, cable_vdo) triple matching the shape of a `cables` / `devices`
/// entry in corpus.jsonl. `cableVDO` is nil when the identity has fewer than
/// 4 VDOs (no 4th VDO to read), matching Python's `cable_vdo: None`.
private struct OracleTriple: Hashable {
    let vid: Int
    let pid: Int
    let cableVDO: UInt32?
}

private func oracleTriple(from identity: USBPDSOP) -> OracleTriple {
    OracleTriple(
        vid: identity.vendorID,
        pid: identity.productID,
        cableVDO: identity.vdos.count > 3 ? identity.vdos[3] : nil
    )
}

/// Parses one corpus.jsonl `cables`/`devices` entry (vid/pid/cable_vdo as
/// "0xHEX" strings or JSON null) into an `OracleTriple`. Comparing as
/// integers (not strings) sidesteps case/leading-zero formatting mismatches
/// between the two implementations' hex formatting.
private func oracleTripleFromJSON(_ entry: [String: Any]) -> OracleTriple {
    func hex(_ key: String) -> Int? {
        guard let s = entry[key] as? String, s.hasPrefix("0x") || s.hasPrefix("0X") else { return nil }
        return Int(s.dropFirst(2), radix: 16)
    }
    let cableVDO: UInt32? = hex("cable_vdo").map { UInt32($0) }
    return OracleTriple(vid: hex("vid") ?? 0, pid: hex("pid") ?? 0, cableVDO: cableVDO)
}

/// Multiset equality: true only when every distinct value appears the same
/// NUMBER OF TIMES on both sides, not just when the two collections contain
/// the same distinct values.
///
/// Checks 1 and 2 used to compare `Set<OracleTriple>` on both sides, which
/// silently masks a per-port miss whenever the same cable or device sits on
/// 2+ ports: dropping one port's copy of a duplicate still leaves the same
/// *set* of distinct triples, so a `Set` comparison can't tell the
/// difference between "both sides agree on every port" and "one side is
/// missing a port". Confirmed this is a real gap, not a hypothetical one:
/// folder m5_macos26.5.1_b has the same zeroed cable
/// (0x0000:0x0000:0x000A2644) on 2 ports, both in Python's `cables` array
/// (`inspect-probe.py`'s `'cables': [p['cable'] for p in ports.values() if
/// ...]` is a per-port list comprehension with no dedup) and, before this
/// fix, in Swift's port-identity map; deliberately dropping port 1's entry
/// from the Swift side still passed the old `Set`-based assertion. As of
/// 2026-07 the corpus has 12 folders with a duplicate cable triple and 13
/// with a duplicate device triple (both counted directly from
/// `corpus.jsonl`, e.g. m1pro_macos26.5.1_d has USB hub 0x2109:0x0103 as a
/// device on 2 ports).
///
/// Python's own array is already per-port (not deduped), so multiset
/// comparison is the granularity both sides genuinely share; this isn't an
/// arbitrary tightening, it's matching what `inspect-probe.py` already
/// computes.
private func oracleMultisetsMatch<T: Hashable>(_ a: [T], _ b: [T]) -> Bool {
    var countsA: [T: Int] = [:]
    for x in a { countsA[x, default: 0] += 1 }
    var countsB: [T: Int] = [:]
    for x in b { countsB[x, default: 0] += 1 }
    return countsA == countsB
}

// MARK: - Check 1: Cable e-marker identity
//
// Byte-order sanity check performed by hand before writing this assertion
// (folder m1_macos15.6.1, SOP' block, VDO[3] raw bytes "50 60 08 00"):
// Python reverses the 4 printed byte pairs and concatenates them
// ('00086050'), giving cable_vdo = "0x00086050". Swift's
// `PDVDO.vdoFromData` treats byte[0] as the LSB (`d[0] | d[1]<<8 | d[2]<<16
// | d[3]<<24`), giving the same UInt32 value 0x00086050. The two are the
// same numeric value expressed two different ways (Python's is a
// byte-reversed hex string, Swift's is a native UInt32), not a coincidence:
// reversing 4 printed hex byte-pairs and reading the result big-endian is
// arithmetically identical to reading the original 4 bytes little-endian.
// Confirmed against the corpus record for that folder (cable_vdo:
// "0x00086050") before trusting this corpus-wide.
@Suite("Python oracle crosscheck - cable e-marker identity")
struct CableIdentityOracleCrosscheckTests {

    @Test("Swift-parsed SOP'/SOP'' cable identities match corpus.jsonl's cables array")
    func cableIdentityMatchesPythonOracle() throws {
        let corpus = oracleLoadCorpusRecords()
        var applicable = 0
        var matched = 0
        var mismatches: [String] = []

        for folder in oracleAllProbeFolders() {
            guard let record = corpus[folder] else { continue }
            guard !oracleProbeTruncated(record, "01_walk_pd_tree") else { continue }
            guard oracleLoadProbeText(folder: folder, probe: "01_walk_pd_tree") != nil else { continue }

            applicable += 1

            let ports = oracleBuildPortIdentities(folder: folder)
            let swiftCables = ports.values.compactMap { $0.cable }.map(oracleTriple)

            let pythonCables = ((record["cables"] as? [[String: Any]]) ?? []).map(oracleTripleFromJSON)

            // Multiset, not Set: see `oracleMultisetsMatch`'s doc comment
            // for why a per-port duplicate would otherwise go unchecked.
            if oracleMultisetsMatch(swiftCables, pythonCables) {
                matched += 1
            } else {
                mismatches.append("\(folder): swift=\(swiftCables) python=\(pythonCables)")
            }
        }

        for m in mismatches.prefix(20) { Issue.record("Cable identity mismatch: \(m)") }

        // Gate: probe 01 is git-tracked, so the full 410-folder corpus is
        // always present, even on a fresh clone. Skip only if something is
        // badly wrong (e.g. running from a stripped-down fixture checkout).
        if applicable >= 50 {
            // Actual as of 2026-07: 409 applicable (410 folders total, minus
            // m5max_macos26.5_b, whose 01_walk_pd_tree.json is absent from
            // disk despite having a corpus.jsonl record -- a pre-existing
            // data oddity in that one folder, not a truncation), 409/409
            // (100%) agree with the Python oracle at MULTISET granularity
            // (see `oracleMultisetsMatch`'s doc comment): confirmed the
            // multiset tightening surfaces zero new mismatches, including
            // across the 12 folders with a genuine duplicate cable on 2+
            // ports. Floor set at 85% of applicable (0.85 * 409 = 347.65,
            // floor 347), not the actual 100%, so a genuine future
            // regression fails the suite without the suite being brittle
            // against a single new corpus folder that happens to disagree
            // for a legitimate reason.
            let floor = Int(Double(applicable) * 0.85)
            #expect(
                matched >= floor,
                "Cable identity: only \(matched)/\(applicable) folders agree with the Python oracle (floor \(floor)); see recorded mismatches"
            )
        }
    }
}

// MARK: - Check 2: Device (partner) identity
@Suite("Python oracle crosscheck - device identity")
struct DeviceIdentityOracleCrosscheckTests {

    @Test("Swift-parsed SOP partner identities match corpus.jsonl's devices array")
    func deviceIdentityMatchesPythonOracle() throws {
        let corpus = oracleLoadCorpusRecords()
        var applicable = 0
        var matched = 0
        var mismatches: [String] = []

        for folder in oracleAllProbeFolders() {
            guard let record = corpus[folder] else { continue }
            guard !oracleProbeTruncated(record, "01_walk_pd_tree") else { continue }
            guard oracleLoadProbeText(folder: folder, probe: "01_walk_pd_tree") != nil else { continue }

            applicable += 1

            let ports = oracleBuildPortIdentities(folder: folder)
            let swiftDevices = ports.values.compactMap { $0.device }.map(oracleTriple)

            let pythonDevices = ((record["devices"] as? [[String: Any]]) ?? []).map(oracleTripleFromJSON)

            // Multiset, not Set: see `oracleMultisetsMatch`'s doc comment
            // for why a per-port duplicate would otherwise go unchecked.
            if oracleMultisetsMatch(swiftDevices, pythonDevices) {
                matched += 1
            } else {
                mismatches.append("\(folder): swift=\(swiftDevices) python=\(pythonDevices)")
            }
        }

        for m in mismatches.prefix(20) { Issue.record("Device identity mismatch: \(m)") }

        if applicable >= 50 {
            // Actual as of 2026-07: 409 applicable (same one folder
            // excluded as check 1), 409/409 (100%) agree at MULTISET
            // granularity (see check 1's comment and
            // `oracleMultisetsMatch`'s doc comment): confirmed zero new
            // mismatches from the multiset tightening, including across
            // the 13 folders with a genuine duplicate device on 2+ ports.
            // Floor at 85% of applicable (0.85 * 409 = 347.65, floor 347),
            // same rationale as check 1.
            let floor = Int(Double(applicable) * 0.85)
            #expect(
                matched >= floor,
                "Device identity: only \(matched)/\(applicable) folders agree with the Python oracle (floor \(floor)); see recorded mismatches"
            )
        }
    }
}

// MARK: - Check 3: Zeroed-VID trust flag
//
// Python flags a cable as "zeroed" when its e-marker VID is 0x0000 AND its
// 4th VDO (cable_vdo) is present and non-zero (`inspect-probe.py`'s
// `zeroed_cables` list comprehension). Swift's `CableTrustReport` raises
// `.zeroVendorID` for a blank VID, UNLESS the SOP partner (the connector)
// identifies the same cable as a USB-IF-registered vendor, in which case it
// raises the softer `.eMarkerVIDBlankRegisteredPartner` note instead
// (DAR-140 / issue #250). Python's definition does not distinguish this
// case at all: it is purely a text-level "vid == 0x0000" check with no
// notion of the partner's identity. So this check treats either Swift flag
// as satisfying Python's "zeroed" condition, and documents the split rather
// than asserting a single exact case name. This is a genuine, if narrow,
// definition mismatch between the two implementations, not a bug in
// either: the corpus has no case (as of 2026-07) where a zeroed-VID cable's
// partner is a registered cable, so it has never actually been exercised,
// but the test is written to tolerate it if one shows up.
@Suite("Python oracle crosscheck - zeroed-VID trust flag")
struct ZeroedVIDTrustOracleCrosscheckTests {

    @Test("CableTrustReport raises a blank-VID flag for exactly the cables Python marks as zeroed")
    func zeroedVIDTrustMatchesPythonOracle() throws {
        let corpus = oracleLoadCorpusRecords()
        var applicableCables = 0
        var matchedCables = 0
        var mismatches: [String] = []

        for folder in oracleAllProbeFolders() {
            guard let record = corpus[folder] else { continue }
            guard !oracleProbeTruncated(record, "01_walk_pd_tree") else { continue }
            guard oracleLoadProbeText(folder: folder, probe: "01_walk_pd_tree") != nil else { continue }

            let pythonZeroed = Set((((record["trust"] as? [String: Any])?["zeroed_vid_cables"]) as? [String]) ?? [])

            let ports = oracleBuildPortIdentities(folder: folder)
            for (_, identities) in ports {
                // Scoped to cables where the 4th VDO (cable_vdo) is defined,
                // matching Python's own precondition for computing a
                // zeroed-cable candidate at all: Python's `cable_vdo` is
                // None (and so the cable can never appear in
                // `zeroed_vid_cables`) whenever there are fewer than 4
                // VDOs. Swift's `CableTrustReport.zeroVendorID` guard is
                // broader (it only requires `!vdos.isEmpty`, not
                // `vdos.count >= 4`), so without this scoping Swift would
                // fire on a population Python's signal was never computed
                // over at all -- a different definition, not a
                // disagreement. Restricting to the shared population keeps
                // the comparison honest.
                guard let cable = identities.cable, cable.vdos.count > 3 else { continue }
                applicableCables += 1

                let vidHex = String(format: "0x%04X", cable.vendorID)
                let cableVDOHex = String(format: "0x%08X", cable.vdos[3])
                let key = "\(vidHex):\(cableVDOHex)"

                let pythonSaysZeroed = cable.vendorID == 0 && cable.vdos[3] != 0
                // Sanity precondition: Swift's own resolved values (already
                // established equal to Python's by check 1) reproduce
                // Python's exact "zeroed" definition for this cable.
                #expect(
                    pythonSaysZeroed == pythonZeroed.contains(key),
                    "\(folder): zeroed-candidate key \(key) disagrees with corpus.jsonl trust.zeroed_vid_cables"
                )

                let report = CableTrustReport(identity: cable, partner: identities.device)
                let firesBlankVIDFlag = report.flags.contains {
                    if case .zeroVendorID = $0 { return true }
                    if case .eMarkerVIDBlankRegisteredPartner = $0 { return true }
                    return false
                }

                if pythonSaysZeroed == firesBlankVIDFlag {
                    matchedCables += 1
                } else {
                    mismatches.append("\(folder) cable \(key): pythonZeroed=\(pythonSaysZeroed) swiftFlagFired=\(firesBlankVIDFlag)")
                }
            }
        }

        for m in mismatches.prefix(20) { Issue.record("Zeroed-VID trust mismatch: \(m)") }

        if applicableCables >= 20 {
            // Actual as of 2026-07: 303 cables have a defined cable_vdo
            // (the shared population this check and Python's own
            // precondition both restrict to; 70 folders have a nonempty
            // trust.zeroed_vid_cables list within that population), and
            // 303/303 (100%) agree, including the sanity precondition
            // above. Floor set at 85% of applicable (0.85 * 303 = 257.55,
            // floor 257), not the actual 100%, for the same margin-not-
            // brittleness reason as checks 1 and 2.
            let floor = Int(Double(applicableCables) * 0.85)
            #expect(
                matchedCables >= floor,
                "Zeroed-VID trust: only \(matchedCables)/\(applicableCables) cables agree with the Python oracle (floor \(floor)); see recorded mismatches"
            )
        }
    }
}

// MARK: - Probe-17 dual-form block parser (TRM restriction + CIO block count)
//
// CRITICAL scope note discovered while building this suite: a single
// physically-restricted transport can appear TWICE in probe 17's raw text --
// once in the flat "All IOPortTransportState* services" listing (a
// `--- ClassName[N] ---` header, 2-space-indented properties) and once
// nested in the HPM deep-dive section (a `=== ClassName ===` header,
// 4-space-indented properties). Verified directly: folder
// a18pro_macos26.5.1's probe 17 has "TRM_TransportRestricted: true" exactly
// twice for what is one restricted USB3 transport (once under each header
// style). Python's `trm_restricted` is a raw whole-text substring count
// (`o.count('TRM_TransportRestricted: true')`), so it counts both
// occurrences. To agree with it, this suite must also gather both header
// forms per watched class, exactly like
// `TransportWatcherSweepTests.trmTransportGateAndNoSilentDrops` already
// does (duplicated here for the same file-scoping reason described in the
// file header; see that test for the same dual-form gather).
//
// CIO transport blocks, by contrast, were verified to appear ONLY in the
// `=== ClassName ===` form across the whole corpus (0 folders have a
// `--- IOPortTransportStateCIO[` dash header), so double-counting is not
// currently possible for check 5. Both forms are still gathered
// uniformly for all four watched classes rather than special-casing CIO,
// matching the existing convention and staying correct if that ever
// changes.

private func oracleParseDashBlocks(text: String, classPrefix: String) -> [[String: Any]] {
    let escapedPrefix = NSRegularExpression.escapedPattern(for: classPrefix)
    guard let regex = try? NSRegularExpression(pattern: "--- \(escapedPrefix)\\[\\d+\\] ---")
    else { return [] }

    let nsText = text as NSString
    let headerMatches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

    var blocks: [[String: Any]] = []
    for (i, match) in headerMatches.enumerated() {
        let bodyStart = match.range.upperBound
        let sameClassBodyEnd = i + 1 < headerMatches.count ? headerMatches[i + 1].range.lowerBound : nsText.length
        var body = nsText.substring(with: NSRange(location: bodyStart, length: sameClassBodyEnd - bodyStart))
        if let cutIndex = oracleNextSectionHeaderIndex(in: body) {
            body = String(body[..<cutIndex])
        }
        blocks.append(oracleParseProperties(body: body, indent: "  "))
    }
    return blocks
}

private func oracleParseEqualsBlocks(text: String, className: String) -> [[String: Any]] {
    let header = "=== \(className) ==="
    var blocks: [[String: Any]] = []
    var searchFrom = text.startIndex
    while let range = text.range(of: header, range: searchFrom..<text.endIndex) {
        let bodyStart = range.upperBound
        var body = String(text[bodyStart...])
        if let cutIndex = oracleNextSectionHeaderIndex(in: body) {
            body = String(body[..<cutIndex])
        } else {
            body = String(body.prefix(2000))
        }
        blocks.append(oracleParseProperties(body: body, indent: "    "))
        searchFrom = range.upperBound
    }
    return blocks
}

/// Finds the `String.Index` of the next section-header line ("=== ClassName
/// ===" or "--- ClassName[N] ---") in `body`, or nil if there is none.
///
/// This has to tolerate leading whitespace before the marker: nested
/// `=== ClassName ===` sub-blocks are sometimes indented a couple of spaces
/// deeper than their siblings depending on how deep they sit in the HPM
/// deep-dive tree (confirmed directly: folder a18pro_macos26.5.1 has
/// `  === IOPortTransportStateUSB2 ===`, 2 leading spaces, right after the
/// USB3 block this function is meant to bound). A bare `"\n==="` /
/// `"\n---"` substring search misses that indented header, so the body
/// keeps going past the true end of its own section and pulls in the next
/// block's properties. Both blocks are then parsed into ONE dict by
/// `oracleParseProperties` (both use 4-space-indented lines), and the next
/// block's same-named key (also `TRM_TransportRestricted`, just a
/// different value) silently overwrites the current block's value because
/// dict assignment is last-write-wins in line order. That is exactly the
/// class of bug this whole suite exists to catch, so getting the boundary
/// right here matters more than it would in an ordinary sweep test.
///
/// Uses `NSRegularExpression` (UTF-16 offsets) and converts the match back
/// to a `String.Index` via `Range(_:in:)` rather than counting Characters
/// with `prefix(_:)`, which would misalign on any non-ASCII byte in the
/// probe text.
private func oracleNextSectionHeaderIndex(in body: String) -> String.Index? {
    guard let re = try? NSRegularExpression(pattern: #"\n[ \t]*(?:===|---) "#) else { return nil }
    let ns = body as NSString
    guard let m = re.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return Range(m.range, in: body)?.lowerBound
}

private func oracleParseProperties(body: String, indent: String) -> [String: Any] {
    var props: [String: Any] = [:]
    let deeper = indent + " "
    for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
        let s = String(line)
        guard s.hasPrefix(indent), !s.hasPrefix(deeper) else { continue }
        let stripped = String(s.dropFirst(indent.count))
        guard let colonRange = stripped.range(of: ": ") else { continue }
        let key = String(stripped[..<colonRange.lowerBound])
        let valStr = String(stripped[colonRange.upperBound...])

        if valStr == "true" { props[key] = NSNumber(value: true) }
        else if valStr == "false" { props[key] = NSNumber(value: false) }
        else if valStr.hasPrefix("\""), valStr.hasSuffix("\""), valStr.count >= 2 {
            props[key] = String(valStr.dropFirst().dropLast())
        } else {
            let digits = valStr.prefix { $0.isNumber }
            if !digits.isEmpty, let n = Int(digits) { props[key] = NSNumber(value: n) }
        }
    }
    return props
}

private func oracleAllTransportBlocks(folder: String, className: String) -> [[String: Any]] {
    guard let text = oracleLoadProbeText(folder: folder, probe: "17_deep_property_dump") else { return [] }
    return oracleParseDashBlocks(text: text, classPrefix: className)
        + oracleParseEqualsBlocks(text: text, className: className)
}

/// The two probes that carry CIO transports, in the order the Python oracle
/// (`inspect-probe.py`) reads them.
///
/// Probe 17 alone is not enough: it is truncated at the 64 KB pipe cap on 41
/// corpus folders and absent on others, so reading it alone undercounts
/// machines-with-a-connected-Thunderbolt-device by 36 (87 vs the true 123).
/// Probe 19 is never truncated in the corpus and its CIO port set is a superset
/// of probe 17's. Both probes can describe the same port, so callers must
/// de-duplicate by `TransportDescription` rather than summing block counts.
private let oracleCIOProbes = ["17_deep_property_dump", "19_pdo_decode_and_usb3_watch"]

private func oracleCIOBlocksByPort(folder: String) -> [String: [String: Any]] {
    var byPort: [String: [String: Any]] = [:]
    for probe in oracleCIOProbes {
        guard let text = oracleLoadProbeText(folder: folder, probe: probe) else { continue }
        let blocks = oracleParseDashBlocks(text: text, classPrefix: "IOPortTransportStateCIO")
            + oracleParseEqualsBlocks(text: text, className: "IOPortTransportStateCIO")
        for props in blocks {
            // A bare `Port-USB-C@N/CIO` transport carrying a real CableSpeed is
            // the only thing that means a Thunderbolt device is actually linked.
            // Probe 19 publishes a structural CIO node on every USB-C port even
            // when nothing is plugged in (335 of 468 folders), and tunnels like
            // `.../CIO/USB3@0` are children of the transport, not separate links.
            guard let port = props["TransportDescription"] as? String,
                  port.hasSuffix("/CIO"),
                  props["CableSpeed"] != nil
            else { continue }
            if byPort[port] == nil { byPort[port] = props }
        }
    }
    return byPort
}

// MARK: - Check 4: TRM restriction count
@Suite("Python oracle crosscheck - TRM restriction count")
struct TRMRestrictionOracleCrosscheckTests {

    @Test("TRMTransportWatcher's restricted-transport count matches corpus.jsonl's signals.trm_restricted")
    func trmRestrictedCountMatchesPythonOracle() throws {
        let corpus = oracleLoadCorpusRecords()
        var applicable = 0
        var matched = 0
        var mismatches: [String] = []

        for folder in oracleAllProbeFolders() {
            guard let record = corpus[folder] else { continue }
            guard !oracleProbeTruncated(record, "17_deep_property_dump") else { continue }
            guard oracleLoadProbeText(folder: folder, probe: "17_deep_property_dump") != nil else { continue }
            // Python's trm_restricted is None (not 0) when probe 17 is
            // present but fails to parse as JSON (one folder in the corpus,
            // see oracleLoadProbeText's doc comment); that folder has
            // already been filtered out by the guard above, so this should
            // always succeed here, but the explicit unwrap keeps the two
            // "no data" cases (missing vs unparseable file) handled the
            // same way on both sides rather than assumed to coincide.
            guard let pythonRestricted = (record["signals"] as? [String: Any])?["trm_restricted"] as? Int
            else { continue }

            applicable += 1

            // Count DISTINCT restricted transports, keyed on TransportDescription
            // (e.g. "Port-USB-C@1/USB2"), not blocks.
            //
            // `oracleAllTransportBlocks` is dash blocks PLUS equals blocks, and
            // probe 17 on M3 and newer prints every transport under BOTH header
            // styles, so counting blocks double-counts those machines: 97 of 576
            // M3+ folders reported exactly twice their real figure. M1/M2 emit
            // only the flat style and were unaffected, which is why this survived
            // unnoticed. The Python side deduplicates the same way, so the two
            // sides now compare the same quantity rather than agreeing by luck
            // on the generations that happen to print once.
            var restrictedTransports = Set<String>()
            for cls in TRMTransportWatcher.watchedClasses {
                let blocks = oracleAllTransportBlocks(folder: folder, className: cls)
                for (idx, props) in blocks.enumerated() {
                    let read: (String) -> Any? = { props[$0] }
                    guard let t = TRMTransportWatcher.makeTRMTransport(
                        entryID: UInt64(idx + 1),
                        read: read,
                        transportType: TRMTransportWatcher.transportType(from: cls),
                        hpmControllerUUID: nil
                    ), t.transportRestricted == true else { continue }
                    // Fall back to a block-unique key if a capture ever lacks a
                    // description, so an undescribed transport is still counted
                    // rather than silently collapsing into another one.
                    let key = (props["TransportDescription"] as? String)
                        ?? "\(cls)#\(idx)"
                    // Python counts USB-C transports only: the SD card slot
                    // reports the same flag on a locked card and is not a USB-C
                    // data link.
                    if key.hasPrefix("Port-USB-C") || !key.hasPrefix("Port-") {
                        restrictedTransports.insert(key)
                    }
                }
            }
            let swiftRestricted = restrictedTransports.count

            if swiftRestricted == pythonRestricted {
                matched += 1
            } else {
                mismatches.append("\(folder): swift=\(swiftRestricted) python=\(pythonRestricted)")
            }
        }

        for m in mismatches.prefix(20) { Issue.record("TRM restriction count mismatch: \(m)") }

        // Gate: probe 17 is gitignored (only fetched from KV on demand), so
        // a fresh clone has none and this skips trivially.
        if applicable >= 50 {
            // Actual as of 2026-07: 410 folders total, minus 40 truncated on
            // probe 17, minus a further 10 where probe 17 doesn't yield
            // usable text (not truncated; confirmed by direct
            // file-existence/parse check for all 10): 9 are simply absent
            // from disk (the contributor's run never produced that file),
            // and 1 (m2pro_macos26.5.1_h) is present on disk but fails to
            // parse as JSON, the same malformed file documented on
            // `oracleLoadProbeText`'s doc comment. Both cases fall through
            // `oracleLoadProbeText` returning nil the same way, so they are
            // filtered out by the same guard above. That leaves 360
            // applicable. 360/360 (100%)
            // agree with the Python oracle after fixing the boundary bug
            // documented on oracleNextSectionHeaderIndex (see that comment
            // for detail: without the fix, ~20 folders mismatched because a
            // restricted transport's own body ran on into the next
            // service's block and got its value overwritten). Floor set at
            // 85% of applicable (0.85 * 360 = 306), not the actual 100%,
            // for the same margin-not-brittleness reason as checks 1-3.
            let floor = Int(Double(applicable) * 0.85)
            #expect(
                matched >= floor,
                "TRM restriction count: only \(matched)/\(applicable) folders agree with the Python oracle (floor \(floor)); see recorded mismatches"
            )
        }
    }
}

// MARK: - Check 5: CIO block count
@Suite("Python oracle crosscheck - CIO block count")
struct CIOBlockCountOracleCrosscheckTests {

    @Test("TRMTransportWatcher's CIO capability count matches corpus.jsonl's cio_blocks")
    func cioBlockCountMatchesPythonOracle() throws {
        let corpus = oracleLoadCorpusRecords()
        var applicable = 0
        var matched = 0
        // Folders where the oracle says a Thunderbolt device IS connected. If
        // this is zero the whole check is vacuous: comparing 0 == 0 on every
        // folder proves nothing about the counting logic.
        var positives = 0
        var mismatches: [String] = []

        for folder in oracleAllProbeFolders() {
            guard let record = corpus[folder] else { continue }
            // Raw-probe presence guard, same as the TRM check above: probes 17
            // and 19 are gitignored (only committed for folders that keep them
            // on disk locally), but `corpus.jsonl`'s `cio_blocks` is committed
            // regardless, computed back when the raw files existed on whichever
            // machine ran the regen. On a tracked-only clone (corpus.jsonl
            // present, raw probes absent), skipping this guard would compare
            // Swift's forced 0 (no raw text to parse) against Python's committed
            // nonzero value for every folder that has a real CIO block, which is
            // not "both sides degrade to 0 the same way" (they don't: only Swift
            // degrades), it is comparing live data against no data. Confirmed
            // this matters: without this guard, a tracked-only checkout produces
            // up to 38 false mismatches racing the floor gate below.
            //
            // No truncation guard here (unlike the TRM check): both sides now
            // read exactly the same two probe texts and apply the same rule, so
            // a truncated probe degrades Swift and Python identically rather
            // than pulling them apart. Probe 19, which carries the complete CIO
            // port set, is never truncated in the corpus anyway.
            guard oracleCIOProbes.contains(where: {
                oracleLoadProbeText(folder: folder, probe: $0) != nil
            }) else { continue }
            guard let pythonCIOBlocks = record["cio_blocks"] as? Int else { continue }

            applicable += 1
            if pythonCIOBlocks > 0 { positives += 1 }

            // Distinct CIO-linked ports across probes 17 and 19, matching the
            // Python oracle's union. Summing raw block counts would double-count
            // the 118 ports that both probes captured.
            let byPort = oracleCIOBlocksByPort(folder: folder)
            var swiftCIOBlocks = 0
            var knownInactiveDrops = 0
            for (idx, port) in byPort.keys.sorted().enumerated() {
                let props = byPort[port]!
                let read: (String) -> Any? = { props[$0] }
                // makeCIOCapability has no hard gate key (unlike TRM's
                // TRM_State), except an explicit Active=false row, which it
                // drops because the CIO leg is not currently up (a cable can
                // still be seated). The Python oracle counts raw blocks with
                // no Active filtering, so we
                // track those drops here and subtract them from its count
                // below rather than from Swift's. The count is therefore
                // really "did we find the right number of linked ports", not
                // "did the parser succeed" -- which is exactly what this
                // check is validating against the Python oracle.
                if (props["Active"] as? NSNumber)?.boolValue == false {
                    knownInactiveDrops += 1
                }
                if TRMTransportWatcher.makeCIOCapability(entryID: UInt64(idx + 1), read: read, hpmControllerUUID: nil) != nil {
                    swiftCIOBlocks += 1
                }
            }

            let expectedCIOBlocks = pythonCIOBlocks - knownInactiveDrops
            if swiftCIOBlocks == expectedCIOBlocks {
                matched += 1
            } else {
                mismatches.append("\(folder): swift=\(swiftCIOBlocks) python=\(pythonCIOBlocks) (adjusted expected \(expectedCIOBlocks))")
            }
        }

        for m in mismatches.prefix(20) { Issue.record("CIO block count mismatch: \(m)") }

        // Gate at 20, not 50, so this check still ASSERTS on a tracked-only
        // clone. Probe 17/19 are gitignored in general, but 27 probe-17 and 15
        // probe-19 files are committed as replay fixtures (DAR-138, #383), which
        // is enough to run a real comparison anywhere. At the old floor of 50 a
        // fresh clone fell short, the assertion never ran, and the check passed
        // vacuously -- and a silently-agreeable check is precisely what let the
        // probe-17-only `cio_blocks` undercount survive this long. Full local
        // corpus: 459 applicable, 123 with cio_blocks > 0. Tracked-only clone:
        // ~27 applicable, ~12 positive.
        #expect(positives > 0,
                "CIO crosscheck is vacuous: no folder with cio_blocks > 0 was comparable; expected the committed probe-17/19 replay fixtures to supply some")

        if applicable >= 20 {
            // 100% agree in practice (both locally and on the tracked-only
            // subset). Floor set at 85% of applicable for margin, not
            // brittleness, matching the other checks in this file.
            let floor = Int(Double(applicable) * 0.85)
            #expect(
                matched >= floor,
                "CIO block count: only \(matched)/\(applicable) folders agree with the Python oracle (floor \(floor)); see recorded mismatches"
            )
        }
    }
}

// MARK: - Check 6: Advanced PD kinds
//
// Python's `advanced_pd` signal used to be a substring match over probe 19's
// raw text for five literal strings: "SPR PPS", "EPR AVS", "SPR AVS", "EPR",
// "PPS". The last two were a real Python-side bug: "PPS" as a bare substring
// only ever matched inside the longer "SPR PPS" text (verified: 115/115
// folders with "PPS" also had "SPR PPS", so it added nothing), and "EPR" as
// a bare substring was a genuine over-match, since probe 19's C probe prints
// " EPR-Capable" as a flag suffix on ordinary Fixed Supply PDOs (bit 23 of
// the PDO word), which has nothing to do with an EPR AVS APDO (145 folders
// had the "EPR" substring, but only 4 of those also had "EPR AVS"; the other
// 141 would have failed any crosscheck against `.eprAvs`, not because Swift
// was wrong, but because Python's substring match answered a different
// question than the kind label implied).
//
// That bug is now FIXED at the source (2026-07): `inspect-probe.py`'s
// `parse_pdo` matches the actual decoded-PDO label the probe prints right
// after "PDO[n] = 0x........ -> " ("SPR PPS ...", "EPR AVS ...", "SPR AVS
// ..."), the same three APDO subtypes `PDO.decode` produces (`.pps`,
// `.eprAvs`, `.sprAvs`). The corpus was regenerated (226 of 410 folders'
// `advanced_pd` field changed, always by dropping a stray bare "EPR" and/or
// "PPS" entry, nothing else in corpus.jsonl or inspection.md changed;
// sample-checked and swept in full). "Advanced PD" is now defined the same
// way on both sides, so there is no carve-out here: every label the
// corrected Python emits is asserted against a matching decoded PDO, full
// stop. The defensive check below (`unexpectedKinds`) exists so that if
// Python's output ever again contains a label outside the three known APDO
// kinds, that shows up as a reported finding instead of silently not being
// checked.
//
// "SPR AVS" has zero samples in the current 410-folder corpus (no folder's
// probe 19 output contains it), so it is included in the loop below for
// completeness but never actually exercised; noted rather than silently
// dropped.
//
// This check used to be one-directional: for each label Python claimed
// present, it asked "does Swift also produce a matching PDO?" but never
// asked the reverse ("does Swift produce a kind Python didn't claim?"). A
// Swift-side over-match (e.g. a regex bug that decoded a stray hex word
// that isn't really a PDO line) would have nothing to fail against, since
// the loop only ever iterated Python-positive labels. Fixed by deriving
// `swiftAdvancedPD` as the full set of labels produced by decoding EVERY
// raw PDO word in the folder (not just checking presence for
// Python-claimed labels) and asserting Set equality against
// `pythonAdvancedPD`, so a mismatch in either direction fails. Verified
// this is still fully green after the tightening: 0 mismatches across the
// corpus, both directions.
@Suite("Python oracle crosscheck - advanced PD kinds")
struct AdvancedPDKindOracleCrosscheckTests {

    @Test("PDO.decode's full set of APDO kinds matches corpus.jsonl's advanced_pd exactly, both directions")
    func advancedPDKindsMatchPythonOracle() throws {
        let corpus = oracleLoadCorpusRecords()

        // These three are the entire "advanced PD" universe on both sides
        // now that inspect-probe.py's parse_pdo is fixed: Python only ever
        // emits one of these three labels, and each maps 1:1 to a PDO.decode
        // APDO case.
        let comparableKinds: [(label: String, matches: (PDO) -> Bool)] = [
            ("SPR PPS", { if case .pps = $0 { return true }; return false }),
            ("EPR AVS", { if case .eprAvs = $0 { return true }; return false }),
            ("SPR AVS", { if case .sprAvs = $0 { return true }; return false }),
        ]
        let knownLabels = Set(comparableKinds.map(\.label))

        var results: [String: (applicable: Int, matched: Int, mismatches: [String])] = [:]
        for (label, _) in comparableKinds { results[label] = (0, 0, []) }
        var unexpectedKinds: [String] = []

        var folderApplicable = 0
        var folderMatched = 0
        var folderMismatches: [String] = []

        for folder in oracleAllProbeFolders() {
            guard let record = corpus[folder] else { continue }
            guard !oracleProbeTruncated(record, "19_pdo_decode_and_usb3_watch") else { continue }
            guard let text = oracleLoadProbeText(folder: folder, probe: "19_pdo_decode_and_usb3_watch") else { continue }
            let advancedPD = Set((((record["signals"] as? [String: Any])?["advanced_pd"]) as? [String]) ?? [])

            // Anything outside the three known APDO kinds is a fresh finding
            // to surface, not something to quietly ignore: it would mean
            // either the Python fix regressed, or a genuinely new PDO shape
            // showed up that Swift's PDO.decode doesn't know about either.
            for stray in advancedPD.subtracting(knownLabels) {
                unexpectedKinds.append("\(folder): unexpected advanced_pd label \"\(stray)\"")
            }

            // Folder-scoped raw PDO word extraction, straight from the same
            // "PDO[n] = 0x........" text Python's own decodePDO printf
            // produces (probes/test-kit/19_pdo_decode_and_usb3_watch.c).
            // Not per-port: the task brief scopes this check at folder
            // level ("must produce at least one PDO of the matching kind"),
            // and corpus.jsonl's advanced_pd signal is itself folder-wide,
            // not per-port.
            var rawWords: [UInt32] = []
            if let re = try? NSRegularExpression(pattern: #"PDO\[\d+\] = 0x([0-9a-fA-F]{8})"#) {
                let ns = text as NSString
                for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let hex = ns.substring(with: m.range(at: 1))
                    if let v = UInt32(hex, radix: 16) { rawWords.append(v) }
                }
            }
            let decoded = rawWords.map(PDO.decode)

            // Full set of APDO kinds Swift's PDO.decode actually produces
            // for every raw PDO word in this folder, not just a presence
            // check for labels Python already claimed. This is the
            // bidirectional half of the fix: `swiftAdvancedPD == advancedPD`
            // below fails if either side has a label the other doesn't.
            let swiftAdvancedPD = Set(decoded.compactMap { pdo -> String? in
                for (label, matches) in comparableKinds where matches(pdo) { return label }
                return nil
            })

            folderApplicable += 1
            if swiftAdvancedPD == advancedPD {
                folderMatched += 1
            } else {
                folderMismatches.append("\(folder): swift=\(swiftAdvancedPD.sorted()) python=\(advancedPD.sorted())")
            }

            // Per-label breakdown, retained for detailed reporting (which
            // specific kind disagreed) even though the folder-level check
            // above is now the actual gate.
            for (label, _) in comparableKinds {
                guard advancedPD.contains(label) else { continue }
                var r = results[label]!
                r.applicable += 1
                if swiftAdvancedPD.contains(label) {
                    r.matched += 1
                } else {
                    r.mismatches.append(folder)
                }
                results[label] = r
            }
        }

        for u in unexpectedKinds { Issue.record("Advanced PD: \(u)") }
        #expect(unexpectedKinds.isEmpty, "corpus.jsonl's advanced_pd contains \(unexpectedKinds.count) label(s) outside the three known APDO kinds; see recorded findings")

        for f in folderMismatches.prefix(20) { Issue.record("Advanced PD set mismatch: \(f)") }

        // Actual as of 2026-07: 400 applicable folders (410 total, minus 10
        // where probe 19 is absent from disk -- a different 10 folders
        // than the probe-17 gaps used by checks 4/5, e.g. this list has
        // m2pro_macos26.5.1_i, not _h, and none of these 10 are
        // present-but-malformed, all 10 are simply absent), 400/400 (100%)
        // full-set agreement, both directions. Floor at 85% of applicable
        // (0.85 * 400 = 340), not the actual 100%, same margin-not-
        // brittleness rationale as the other checks.
        if folderApplicable >= 50 {
            let floor = Int(Double(folderApplicable) * 0.85)
            #expect(
                folderMatched >= floor,
                "Advanced PD (full set): only \(folderMatched)/\(folderApplicable) folders fully agree with the Python oracle, both directions (floor \(floor)); see recorded mismatches"
            )
        }

        for (label, r) in results {
            for f in r.mismatches.prefix(10) {
                Issue.record("Advanced PD kind mismatch (\(label)): \(f) has no matching decoded PDO")
            }
        }

        // "SPR PPS": actual as of 2026-07, 115 applicable folders, 115/115
        // (100%) produce a matching .pps PDO. Floor at 85% of applicable
        // (0.85 * 115 = 97.75, floor 97), not the actual 100%, for the
        // same margin-not-brittleness reason as the other checks.
        if let r = results["SPR PPS"], r.applicable >= 20 {
            let floor = Int(Double(r.applicable) * 0.85)
            #expect(
                r.matched >= floor,
                "SPR PPS: only \(r.matched)/\(r.applicable) folders produce a matching .pps PDO (floor \(floor))"
            )
        }

        // "EPR AVS": actual as of 2026-07, only 4 applicable folders (a
        // small sample, unlike the others), 4/4 (100%) produce a matching
        // .eprAvs PDO. 85% of 4 is 3.4, so the floor is set at 3 rather
        // than requiring a perfect 4/4, per the same "not just a round
        // number, walk the arithmetic" rule applied at small N.
        if let r = results["EPR AVS"], r.applicable >= 1 {
            let floor = max(1, Int(Double(r.applicable) * 0.85))
            #expect(
                r.matched >= floor,
                "EPR AVS: only \(r.matched)/\(r.applicable) folders produce a matching .eprAvs PDO (floor \(floor))"
            )
        }

        // "SPR AVS": zero samples in the corpus as of 2026-07. No floor is
        // asserted; this branch exists so a future corpus with a real
        // sample starts being checked automatically rather than silently.
        if let r = results["SPR AVS"], r.applicable > 0 {
            let floor = Int(Double(r.applicable) * 0.85)
            #expect(
                r.matched >= floor,
                "SPR AVS: only \(r.matched)/\(r.applicable) folders produce a matching .sprAvs PDO (floor \(floor))"
            )
        }
    }
}
