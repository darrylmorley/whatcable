import CryptoKit
import Foundation
import Testing
@testable import WhatCableCore

// MARK: - EDIDOracleSweepTests
//
// The acceptance gate for the EDID parser: every timing the reference decoder
// (edid-decode from v4l-utils, pinned commit recorded in the TSV's first line)
// prints for every unique EDID in the customer-probe corpus must appear in
// `EDIDInfo.modes`, and every entry in `EDIDInfo.modes` must be a timing
// edid-decode printed. The oracle rows live in
// `research/corpus-baselines/edid-decode-timings.tsv`, written by
// `scripts/edid-oracle.py` in the research repo; that script's docstring is the
// TSV's schema and `kind` vocabulary.
//
// Extraction of the EDID bytes is the same as the neighbouring sweeps
// (`DisplayDiagnosticProbeSweepTests`): the `Metadata.EDID = <N bytes ...> HEX`
// line inside every `=== DisplayPort node [N] ===` block of every probe-33
// file. Every block is read, active or not, so the set matches the oracle's.
// Dedupe is by the sha256 of the bytes, which is the TSV's join key.
//
// The two sides differ by design in a handful of named ways. Each rule below
// is a measured fact about edid-decode's output, cited to the function that
// prints it, and the sweep counts every row it excludes so a rule that starts
// swallowing more than it should is visible in the printout.
//
//   1. `HDMIVIC` rows are excluded. No HDMI VIC table is bundled (owner ruling
//      9); edid-decode prints them from `edid_hdmi_mode_map` in
//      `cta_hdmi_block` (parse-cta-block.cpp).
//   2. Standard timings. edid-decode's `print_standard_timing`
//      (parse-base-block.cpp) prints exactly one `GTF` line for a non-DMT
//      standard timing on every EDID in this corpus, whatever the 0xFD
//      descriptor's byte 10 says, because `supports_cvt` is never set on a
//      fresh parse (its preparse runs before `edid_minor` is read). Our side has
//      one entry (the formula the EDID licenses) or none (an undecoded
//      `StandardTimingID`). So a `GTF`/`CVT` row under "Standard Timings" is
//      satisfied by an entry with the same picture, refresh and pixel clock,
//      or by `undecodedStandardTimings` naming that picture and refresh. An
//      entry with the same picture and rounded refresh but a different clock
//      is a formula difference, counted, and tolerated only when byte 10 is
//      0x04 (CVT), which this corpus does not contain.
//   3. VIC rows under the "YCbCr 4:2:0 Capability Map Data Block" and the HDMI
//      VSDB's "3D VIC indices" sections are re-prints of the Video Data
//      Block's own SVDs (`cta_y420cmdb` and `cta_hdmi_block` call
//      `print_vic_index`, which prints `cta.preparsed_svds[0][idx]`), not new
//      declarations. The oracle script measured that every one has an
//      identical VDB row in the same EDID. They are excluded and counted.
//   4. `TILED` rows are not timings. edid-decode prints the topology
//      (`parse_displayid_tiled_display_topology`) and synthesises no composite
//      mode. Each `.tiledComposite` entry on our side must instead correspond
//      to a `TILED` row whose tile resolution times its tile count equals the
//      composite's picture, and is counted.
//   5. Interlaced refresh is compared as the field rate on both sides
//      (`EDIDMode.refreshHz` doubles the frame rate; `print_timings` divides
//      the frame by a half-line-corrected field total).
//   6. Refresh is compared to 0.001 Hz and pixel clock to 1 kHz, the spec's
//      acceptance criteria.
//   7. A descriptor with a zero vertical total prints an `inf` refresh
//      (`print_timings` divides the clock by `htotal * vtotal`); our
//      `EDIDMode.refreshHz` returns 0 for a zero total. Such a row matches on
//      picture and pixel clock alone, and is counted. Measured once in the
//      corpus: a CTA-block DTD of 128x0.
//
// Everything else must match exactly, in both directions, and the sweep prints
// every mismatch before failing.

@Suite("EDID oracle sweep: every corpus EDID's declared mode list matches edid-decode")
struct EDIDOracleSweepTests {

    // MARK: - Paths

    private static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }()

    private static let probeRoot = repoRoot.appendingPathComponent("research/customer-probes")
    private static let oracleTSV = repoRoot.appendingPathComponent("research/corpus-baselines/edid-decode-timings.tsv")

    // MARK: - Oracle rows

    struct OracleRow {
        let sha: String
        let folder: String
        let block: Int
        let monitor: String
        let kind: String
        let width: Int
        let height: Int
        let interlaced: Bool
        let refreshHz: Double
        let pixelClockKHz: Int
        let detail: String
        let section: String

        var isStandardTimingFormula: Bool {
            (kind == "GTF" || kind == "CVT") && section == "Standard Timings"
        }

        /// Rule 3: a VIC printed under a section that re-lists the VDB's SVDs.
        var isReprintedVIC: Bool {
            kind == "VIC" && section != "Video Data Block" && !section.hasPrefix("YCbCr 4:2:0 Video Data Block")
        }

        var label: String {
            "\(kind) \(width)x\(height)\(interlaced ? "i" : "") \(refreshHz) Hz \(pixelClockKHz) kHz [\(section)]\(detail.isEmpty ? "" : " " + detail)"
        }
    }

    private static func loadOracle() -> [String: [OracleRow]]? {
        guard let text = try? String(contentsOf: oracleTSV, encoding: .utf8) else { return nil }
        var rows: [String: [OracleRow]] = [:]
        var sawHeader = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("#") { continue }
            if !sawHeader { sawHeader = true; continue }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 12,
                  let block = Int(f[2]), let width = Int(f[5]), let height = Int(f[6]),
                  let interlaced = Int(f[7]), let refresh = Double(f[8]), let clock = Int(f[9])
            else { continue }
            let row = OracleRow(sha: f[0], folder: f[1], block: block, monitor: f[3], kind: f[4],
                                width: width, height: height, interlaced: interlaced == 1,
                                refreshHz: refresh, pixelClockKHz: clock, detail: f[10], section: f[11])
            rows[row.sha, default: []].append(row)
        }
        return rows
    }

    // MARK: - Corpus EDIDs

    struct CorpusEDID {
        let sha: String
        let folder: String
        let block: Int
        let data: Data
    }

    /// Every unique EDID in the corpus, keyed by sha256, first folder and block wins.
    private static func loadCorpusEDIDs() -> [CorpusEDID] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: probeRoot.path) else { return [] }
        var seen: Set<String> = []
        var result: [CorpusEDID] = []
        for folder in folders.sorted() {
            let url = probeRoot.appendingPathComponent(folder).appendingPathComponent("33_displayport_capability.json")
            guard let raw = try? Data(contentsOf: url),
                  let root = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
                  let text = root["output"] as? String
            else { continue }
            let parts = text.components(separatedBy: "=== DisplayPort node [")
            for part in parts.dropFirst() {
                guard let close = part.firstIndex(of: "]"), let block = Int(part[part.startIndex..<close]) else { continue }
                guard let range = part.range(of: "Metadata.EDID = "),
                      let lineEnd = part[range.upperBound...].firstIndex(of: "\n")
                else { continue }
                let rest = String(part[range.upperBound..<lineEnd])
                guard let angleEnd = rest.range(of: "> ") else { continue }
                let hex = String(rest[angleEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard let data = hexToData(hex) else { continue }
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard !seen.contains(sha) else { continue }
                seen.insert(sha)
                result.append(CorpusEDID(sha: sha, folder: folder, block: block, data: data))
            }
        }
        return result
    }

    private static func hexToData(_ s: String) -> Data? {
        let hex = s.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let byte = UInt8(hex[i..<j], radix: 16) else { return nil }
            data.append(byte)
            i = j
        }
        return data.isEmpty ? nil : data
    }

    // MARK: - Our side

    /// One declared entry, in the oracle's units.
    struct OurEntry {
        let mode: EDIDMode
        var width: Int { mode.width }
        var height: Int { mode.height }
        var interlaced: Bool { mode.interlaced }
        var refreshHz: Double { mode.refreshHz }
        var pixelClockKHz: Int { Int((Double(mode.pixelClockHz) / 1000).rounded()) }

        var label: String {
            "\(width)x\(height)\(interlaced ? "i" : "") \(refreshHz) Hz \(pixelClockKHz) kHz (\(mode.sourceDescription))"
        }

        func matches(_ row: OracleRow) -> Bool {
            width == row.width && height == row.height && interlaced == row.interlaced
                && abs(refreshHz - row.refreshHz) <= 0.001
                && abs(pixelClockKHz - row.pixelClockKHz) <= 1
        }

        /// Rule 7: the oracle printed a non-finite refresh (zero vertical total).
        func matchesIgnoringRefresh(_ row: OracleRow) -> Bool {
            width == row.width && height == row.height && interlaced == row.interlaced
                && abs(pixelClockKHz - row.pixelClockKHz) <= 1
        }

        /// Rule 2's looser identity: same picture and the same refresh once rounded to the
        /// integer the standard timing byte encodes.
        func samePictureAndRoundedRefresh(_ row: OracleRow) -> Bool {
            width == row.width && height == row.height && !interlaced && !row.interlaced
                && Int(refreshHz.rounded()) == Int(row.refreshHz.rounded())
        }
    }

    /// A coarse label per `EDIDMode.Source` case, for the per-source counts.
    static func sourceKind(_ source: EDIDMode.Source) -> String {
        switch source {
        case .establishedTiming(_, _, let dmt): return dmt == nil ? "established timing (legacy)" : "established timing (DMT)"
        case .standardTiming(_, let derivation, let dmt): return "standard timing (\(dmt == nil ? derivation.rawValue.uppercased() : "DMT"))"
        case .detailedTiming(let block, _): return block == 0 ? "detailed timing (base block)" : "detailed timing (CTA block)"
        case .cvtCode: return "CVT code"
        case .ctaVIC(_, _, _, let y420): return y420 ? "CTA VIC (4:2:0 only)" : "CTA VIC"
        case .displayID(_, let type, _, let cta): return "DisplayID \(type.label)\(cta ? " in CTA" : "")"
        case .tiledComposite: return "tiled composite"
        }
    }

    static func blockKindLabel(_ kind: EDIDInfo.BlockInfo.Kind) -> String {
        switch kind {
        case .base: return "base"
        case .cta861: return "cta861"
        case .displayID(let v): return "displayID\(v >> 4).\(v & 0xF)"
        case .vtb: return "vtb"
        case .blockMap: return "blockMap"
        case .padding: return "padding"
        case .unknown(let tag): return "unknown0x" + String(format: "%02x", tag)
        }
    }

    // MARK: - The sweep

    @Test("Every corpus EDID's declared mode list matches edid-decode's timings")
    func oracleAgreesOnEveryCorpusEDID() throws {
        // SKIP only when the corpus itself is absent, the same guard the neighbouring sweeps
        // use. A corpus with no oracle TSV beside it is a FAILURE, not a skip: the sweep is the
        // acceptance gate for the parser, and a green run that compared nothing is the exact
        // shape a missing TSV would otherwise produce on any checkout whose research tree lacks
        // the baseline.
        guard FileManager.default.fileExists(atPath: Self.probeRoot.path) else {
            print("EDIDOracleSweep: SKIPPED: no corpus at \(Self.probeRoot.path). "
                + "Run scripts/link-research.sh in this checkout to sweep for real.")
            return
        }
        guard let oracle = Self.loadOracle() else {
            let message = "EDIDOracleSweep: the raw corpus is present at \(Self.probeRoot.path) but the oracle TSV is "
                + "missing at \(Self.oracleTSV.path). Remedy: link a research tree that carries the "
                + "baseline (scripts/link-research.sh), or regenerate it there with scripts/edid-oracle.py."
            Issue.record(Comment(rawValue: message))
            return
        }
        let corpus = Self.loadCorpusEDIDs()

        var comparedEDIDs = 0
        var ourModes = 0
        var oracleRows = 0
        var oracleTimingRows = 0
        var mismatches: [String] = []

        // Exclusions by rule.
        var hdmiVICRows = 0
        var reprintedVICRows = 0
        var tiledRows = 0
        var tiledComposites = 0
        var tiledTopologiesWithoutComposite = 0
        var undecodedSatisfiedRows = 0
        var standardTimingFormulaDiffers = 0
        var zeroTotalRows = 0

        // Per-source counts and the corpus facts the findings doc quotes.
        var modesBySource: [String: Int] = [:]
        var topModeBySource: [String: Int] = [:]
        var continuousFrequency = 0
        var checksumValid: [String: (valid: Int, invalid: Int)] = [:]
        var undecodedStandardTimings = 0
        var edidsWithUndecoded = 0
        var tiledPanels = 0
        var byte126UnderDeclares = 0
        var rangeLimitsAboveTop: [String: Int] = [:]
        var noRangeLimitClock = 0
        var noOracleRows = 0
        var tiledCompositeFrom: [String: Int] = [:]
        var tiledWithCompositeDeclared = 0
        var dynamicRangeLimits = 0

        for edid in corpus {
            guard let rows = oracle[edid.sha] else {
                noOracleRows += 1
                mismatches.append("\(edid.sha.prefix(12)) \(edid.folder) block \(edid.block): no oracle rows for this EDID")
                continue
            }
            guard let info = EDIDInfo(edid.data) else {
                mismatches.append("\(edid.sha.prefix(12)) \(edid.folder) block \(edid.block): EDIDInfo returned nil; edid-decode printed \(rows.count) rows")
                continue
            }
            comparedEDIDs += 1
            let monitor = rows.first?.monitor ?? ""
            let tag = "\(edid.sha.prefix(12)) \(edid.folder) block \(edid.block) '\(monitor)'"

            // Facts.
            ourModes += info.modes.count
            oracleRows += rows.count
            for mode in info.modes { modesBySource[Self.sourceKind(mode.source), default: 0] += 1 }
            if let top = info.topMode { topModeBySource[Self.sourceKind(top.source), default: 0] += 1 }
            if info.continuousFrequency == true { continuousFrequency += 1 }
            for block in info.blocks {
                let k = Self.blockKindLabel(block.kind)
                var c = checksumValid[k] ?? (0, 0)
                if block.checksumValid { c.valid += 1 } else { c.invalid += 1 }
                checksumValid[k] = c
            }
            undecodedStandardTimings += info.undecodedStandardTimings.count
            if !info.undecodedStandardTimings.isEmpty { edidsWithUndecoded += 1 }
            if let t = info.tiledTopology, t.hTiles * t.vTiles > 1 {
                tiledPanels += 1
                let compositeWidth = t.tileWidth * t.hTiles
                let compositeHeight = t.tileHeight * t.vTiles
                if info.modes.contains(where: { mode in
                    if case .tiledComposite = mode.source { return false }
                    return mode.width == compositeWidth && mode.height == compositeHeight
                }) { tiledWithCompositeDeclared += 1 }
                for mode in info.modes {
                    if case .tiledComposite(_, let from) = mode.source {
                        tiledCompositeFrom[from.map { "DisplayID " + $0.label } ?? "base or CTA descriptor", default: 0] += 1
                    }
                }
            }
            if info.dynamicRangeLimits != nil { dynamicRangeLimits += 1 }
            if info.declaredExtensionCount < info.blocks.count - 1 { byte126UnderDeclares += 1 }
            if let top = info.topMode {
                if let maxClock = info.rangeLimits?.maxPixelClockHz {
                    let ratio = Double(maxClock) / Double(top.pixelClockHz)
                    let bucket = String(format: "%.1f", (ratio * 10).rounded(.down) / 10)
                    rangeLimitsAboveTop[bucket, default: 0] += 1
                } else {
                    noRangeLimitClock += 1
                }
            }

            // Our multiset.
            var ours = info.modes.map { OurEntry(mode: $0) }
            var consumed = [Bool](repeating: false, count: ours.count)
            func take(where predicate: (OurEntry) -> Bool) -> Int? {
                for (i, entry) in ours.enumerated() where !consumed[i] && predicate(entry) {
                    consumed[i] = true
                    return i
                }
                return nil
            }

            var tiledRowsForThisEDID: [OracleRow] = []

            for row in rows {
                if row.kind == "TILED" {
                    tiledRows += 1
                    tiledRowsForThisEDID.append(row)
                    continue
                }
                oracleTimingRows += 1
                if row.kind == "HDMIVIC" {              // rule 1
                    hdmiVICRows += 1
                    continue
                }
                if row.isReprintedVIC {                 // rule 3
                    reprintedVICRows += 1
                    continue
                }
                if take(where: { $0.matches(row) }) != nil { continue }

                if !row.refreshHz.isFinite,             // rule 7
                   take(where: { $0.matchesIgnoringRefresh(row) && $0.refreshHz == 0 }) != nil {
                    zeroTotalRows += 1
                    continue
                }

                if row.isStandardTimingFormula {        // rule 2
                    let refreshInt = Int(row.refreshHz.rounded())
                    if info.undecodedStandardTimings.contains(where: {
                        $0.width == row.width && $0.height == row.height && $0.refreshHz == refreshInt
                    }) {
                        undecodedSatisfiedRows += 1
                        continue
                    }
                    if let i = take(where: { $0.samePictureAndRoundedRefresh(row) }) {
                        standardTimingFormulaDiffers += 1
                        var byte10IsCVT = false
                        if case .cvt = info.rangeLimits?.timingSupport { byte10IsCVT = true }
                        if !byte10IsCVT {
                            mismatches.append("\(tag): standard timing formula differs and byte 10 is not 0x04: oracle \(row.label) vs ours \(ours[i].label)")
                        }
                        continue
                    }
                }
                mismatches.append("\(tag): oracle row has no entry on our side: \(row.label)")
            }

            // Every entry of ours must have been consumed, except tiled composites (rule 4).
            for (i, entry) in ours.enumerated() where !consumed[i] {
                if case .tiledComposite(let tiles, _) = entry.mode.source {
                    let topologyMatches = tiledRowsForThisEDID.contains { row in
                        let parts = row.detail.split(separator: "x").compactMap { Int($0) }
                        guard parts.count == 2 else { return false }
                        return parts[0] * parts[1] == tiles
                            && row.width * parts[0] == entry.width
                            && row.height * parts[1] == entry.height
                    }
                    if topologyMatches {
                        tiledComposites += 1
                    } else {
                        mismatches.append("\(tag): tiled composite \(entry.label) has no matching TILED row (\(tiledRowsForThisEDID.map(\.label)))")
                    }
                    continue
                }
                mismatches.append("\(tag): our entry has no oracle row: \(entry.label)")
            }
            if let t = info.tiledTopology, t.hTiles * t.vTiles > 1,
               !info.modes.contains(where: { if case .tiledComposite = $0.source { return true } else { return false } }) {
                tiledTopologiesWithoutComposite += 1
            }
            ours.removeAll()
        }

        // Printout.
        print("EDIDOracleSweep summary")
        print("  oracle TSV header: \((try? String(contentsOf: Self.oracleTSV, encoding: .utf8))?.split(separator: "\n").first.map(String.init) ?? "")")
        print("  corpus unique EDIDs: \(corpus.count)  comparedEDIDs: \(comparedEDIDs)  EDIDs with no oracle rows: \(noOracleRows)")
        print("  ourModes: \(ourModes)  oracleRows: \(oracleRows) (timing rows \(oracleTimingRows), TILED rows \(tiledRows))")
        print("  exclusions by rule:")
        print("    rule 1 HDMI VIC rows: \(hdmiVICRows)")
        print("    rule 2 undecoded-satisfied standard timing rows: \(undecodedSatisfiedRows)")
        print("    rule 2 standard timing formula differs: \(standardTimingFormulaDiffers)")
        print("    rule 3 re-printed VIC rows (Y420CMDB, HDMI VSDB 3D): \(reprintedVICRows)")
        print("    rule 4 tiled composites matched to a TILED row: \(tiledComposites)  topologies with no composite: \(tiledTopologiesWithoutComposite)")
        print("    rule 7 zero-vertical-total rows (oracle refresh inf, ours 0): \(zeroTotalRows)")
        print("  modes by source:")
        for (k, v) in modesBySource.sorted(by: { $0.key < $1.key }) { print("    \(v)\t\(k)") }
        print("  top mode by source:")
        for (k, v) in topModeBySource.sorted(by: { $0.key < $1.key }) { print("    \(v)\t\(k)") }
        print("  continuous frequency (EDID 1.4 byte 24 bit 0): \(continuousFrequency)")
        print("  checksum-valid per block kind:")
        for (k, v) in checksumValid.sorted(by: { $0.key < $1.key }) { print("    \(k): \(v.valid) valid / \(v.invalid) invalid") }
        print("  undecoded standard timings: \(undecodedStandardTimings) across \(edidsWithUndecoded) EDIDs")
        print("  tiled panels (topology with more than one tile): \(tiledPanels); of them, composite resolution also declared as a mode: \(tiledWithCompositeDeclared)")
        print("  tiled composite built from:")
        for (k, v) in tiledCompositeFrom.sorted(by: { $0.key < $1.key }) { print("    \(v)\t\(k)") }
        print("  DisplayID dynamic range limits (tag 0x25) present: \(dynamicRangeLimits)")
        print("  byte 126 under-declares the block count: \(byte126UnderDeclares)")
        print("  0xFD max pixel clock / top mode pixel clock, 0.1 buckets (EDIDs with no 0xFD clock: \(noRangeLimitClock)):")
        for (k, v) in rangeLimitsAboveTop.sorted(by: { (Double($0.key) ?? 0) < (Double($1.key) ?? 0) }) { print("    \(k): \(v)") }
        print("  mismatches: \(mismatches.count)")
        for m in mismatches { print("    MISMATCH \(m)") }

        #expect(comparedEDIDs >= 550,
            "Only \(comparedEDIDs) EDIDs compared; expected at least 550 -- the corpus or the oracle TSV is near-empty")
        #expect(mismatches.isEmpty,
            "\(mismatches.count) mismatches between EDIDInfo.modes and edid-decode across \(comparedEDIDs) EDIDs; see the MISMATCH lines above")
    }
}
