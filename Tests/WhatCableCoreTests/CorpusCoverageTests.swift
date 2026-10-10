import Foundation
import Testing

/// Guards the customer-probe corpus's queryable index (`corpus.jsonl`) so the
/// audit fixtures cannot silently vanish. The post-redesign diagnostic audit
/// (and the work it spawned: TRM, advanced-PD, cable-trust
/// checks) leans on these signals being present in the corpus. A bad
/// regeneration or an accidental edit that drops records or strips a signal
/// would quietly remove the fixtures those tasks and their regression tests
/// depend on. This catches that.
///
/// Reads the git-tracked `corpus.jsonl` (not the gitignored raw probes), so it
/// runs identically on a fresh clone. Thresholds sit comfortably below the
/// current counts: they flag a collapse, not normal growth.
@Suite("Customer-probe corpus coverage")
struct CorpusCoverageTests {
    private static let corpusURL: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes/corpus.jsonl")
    }()

    struct MalformedCorpusLine: Error { let line: Int }

    private static func records() throws -> [[String: Any]] {
        let text = try String(contentsOf: corpusURL, encoding: .utf8)
        // Fail fast on a malformed line rather than silently dropping it: a
        // corrupt regeneration must surface as a test failure, not a quietly
        // lower record count that still clears the thresholds.
        return try text
            .split(separator: "\n")
            .enumerated()
            .map { index, line in
                guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                    throw MalformedCorpusLine(line: index + 1)
                }
                return obj
            }
    }

    private static func signals(_ r: [String: Any]) -> [String: Any] {
        (r["signals"] as? [String: Any]) ?? [:]
    }

    @Test("corpus has the expected total record count")
    func totalRecords() throws {
        let recs = try Self.records()
        // Actual 410 as of 2026-07. Floor set to ~85% of actual (350), not the
        // stale 200: 200 was loose enough to miss a corpus that shrank by
        // roughly half.
        #expect(recs.count >= 350,
            "corpus.jsonl should hold the full corpus (350+ folders); found \(recs.count). A drop means records were lost in regeneration.")
    }

    @Test("TRM-restriction fixtures present")
    func trmFixtures() throws {
        let n = try Self.records().filter { ((Self.signals($0)["trm_restricted"] as? Int) ?? 0) > 0 }.count
        // Actual 89 as of 2026-07. Floor set to ~90% of actual (80), not the
        // stale 30 (34% of actual, wide enough to hide a real regression).
        #expect(n >= 80, "expected 80+ TRM-restricted folders as fixtures; found \(n)")
    }

    @Test("CIO / connected-Thunderbolt fixtures present")
    func cioFixtures() throws {
        let n = try Self.records().filter { ((($0["cio_blocks"] as? Int)) ?? 0) > 0 }.count
        // Actual 75 as of 2026-07. Floor set to ~87% of actual (65), not the
        // stale 25 (33% of actual).
        #expect(n >= 65, "expected 65+ CIO folders (mine-cio + port-key fixtures); found \(n)")
    }

    @Test("advanced-PD fixtures present")
    func advancedPDFixtures() throws {
        let n = try Self.records().filter { ((Self.signals($0)["advanced_pd"] as? [Any]) ?? []).isEmpty == false }.count
        // Actual 226 (pre-fix) dropped to 117 (2026-07) after correcting a
        // Python-pipeline bug in `inspect-probe.py`'s advanced-PD
        // detection: it used to substring-match the bare text "EPR" anywhere
        // in probe 19's output, which also matched an ordinary Fixed Supply
        // PDO's "EPR-Capable" flag suffix (and, on machines with a TB dock,
        // the unrelated "EEPROM Version" property text) even when no PDO
        // actually decoded as an EPR AVS APDO. 109 folders flipped from
        // "has advanced PD" to "no advanced PD" once that false-positive
        // source was removed; the corrected 117 is real signal, matched
        // 1:1 by Swift's `PDO.decode` (see PythonOracleCrosscheckTests.swift's
        // check 6). The old floor of 200 was calibrated against the inflated
        // 226 and would now always fail, so it is re-derived from the
        // corrected actual: 0.85 * 117 = 99.45, floor set to 100 (85.5% of
        // actual), same margin-not-brittleness standard as the other rows
        // in this file.
        #expect(n >= 100, "expected 100+ advanced-PD folders as fixtures; found \(n)")
    }

    @Test("zeroed-VID cable-trust fixtures present")
    func zeroedVIDFixtures() throws {
        let n = try Self.records().filter {
            (($0["trust"] as? [String: Any])?["zeroed_vid_cables"] as? [Any] ?? []).isEmpty == false
        }.count
        // Actual 70 as of 2026-07. Floor set to ~86% of actual (60), not the
        // stale 20 (29% of actual).
        #expect(n >= 60, "expected 60+ zeroed-VID cable folders as fixtures; found \(n)")
    }

    @Test("Billboard fixtures present")
    func billboardFixtures() throws {
        let n = try Self.records().filter { ((Self.signals($0)["billboard"] as? Int) ?? 0) > 0 }.count
        // Actual 88 as of 2026-07. Floor set to ~85% of actual (75), not the
        // stale 30 (34% of actual).
        #expect(n >= 75, "expected 75+ Billboard (bDeviceClass 0x11) folders; found \(n)")
    }

    // MARK: - Canary for ChargingDiagnosticProbeSweepTests' named fixtures
    //
    // ChargingDiagnosticProbeSweepTests has 12 tests, each pinned to one named
    // machine folder, that skip gracefully (`guard ... else { return }`) when
    // that folder's probe-17 file is missing -- the same skip-not-fail
    // convention every other sweep suite uses for a corpus-less checkout. The
    // trade-off: if one of those 12 folders is ever renamed, deleted, or its
    // probe-17 fixture corrupted, the individual test would just skip forever
    // rather than fail, so a real fixture regression could go unnoticed. This
    // canary asserts each fixture actually loads, so that failure mode surfaces
    // loudly here instead.

    /// The 12 machine folders ChargingDiagnosticProbeSweepTests pins its named
    /// tests to. Keep in sync with the `folder:` argument of each `@Test` in
    /// that file (and the `fixtureMachines` array in its sweep test).
    private static let chargingFixtureFolders = [
        "m1pro_macos15.7.4",
        "m1pro_macos26.5_k",
        "m1pro_macos26.5_m",
        "m4_macos26.5_d",
        "m5pro_macos26.5_c",
        "m3pro_macos26.5_b",
        "m3pro_macos15.7.5",
        "m2_macos26.3.1",
        "m4pro_macos26.5_j",
        "m1_macos26.5_o",
        "m3_macos26.5_g",
        "m1_macos26.5_n",
    ]

    @Test("ChargingDiagnostic fixture probes load (skip-not-fail canary)")
    func chargingFixtureProbesLoad() throws {
        // Same corpus-present guard convention as the sweep suites: skip
        // entirely in a checkout with no raw probe corpus on disk at all
        // (these fixtures are git-tracked via `git add -f`, so in practice
        // they are present in every clone, but the guard keeps this test
        // consistent with -- and as harmless as -- the rest of the sweep).
        guard FileManager.default.fileExists(atPath: ProbeCorpus.root.path) else { return }

        for folder in Self.chargingFixtureFolders {
            let text = ProbeCorpus.loadText(folder: folder, probe: "17_deep_property_dump")
            #expect(text != nil,
                "ChargingDiagnosticProbeSweepTests fixture \(folder)/17_deep_property_dump.json failed to load. That named test would silently skip instead of asserting anything -- check the folder wasn't renamed, deleted, or its probe-17 fixture corrupted.")
        }
    }
}
