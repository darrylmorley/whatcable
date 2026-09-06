import Foundation
import Testing
@testable import WhatCableCore

/// Corpus-replay sweep for `CableDB.vendorName(vid:)`, `CableDB.isUSBIFRegistered(_:)`,
/// and `CableDB.curatedCables(vid:pid:cableVDO:)` (`Sources/WhatCableCore/Database/CableDB.swift`),
/// the bundled-SQLite-backed lookup no existing test drives against real
/// corpus identities.
///
/// Reads `research/customer-probes/corpus.jsonl`, the committed distillation
/// (not gitignored raw probes), so this sweep runs on a fresh clone with no
/// re-fetch needed. Each record's `devices` and `cables` arrays carry
/// `{"vid": "0x...", "pid": "0x..."}` pairs seen on real hardware: `devices`
/// are connected-peripheral SOP identities, `cables` are cable e-marker
/// (SOP'/SOP'') identities.
@Suite("CableDB: corpus lookup sweep")
struct CableDBCorpusLookupTests {

    private static let corpusRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private struct Identity: Hashable {
        let vid: Int
        let pid: Int
    }

    /// Every (VID, PID) pair seen anywhere in `corpus.jsonl`'s `devices` or
    /// `cables` arrays, across every folder. `vid`/`pid` are hex strings like
    /// `"0x05AC"`; entries missing either field, or equal to `"0x0000"`, are
    /// skipped (mirrors `CableDB.curatedCables`'s own zero-VID/PID guard --
    /// there is nothing to look up for an unidentified accessory).
    private static let identities: Set<Identity> = {
        let url = corpusRoot.appendingPathComponent("corpus.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var result: Set<Identity> = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let arrays = [obj["devices"] as? [[String: Any]] ?? [], obj["cables"] as? [[String: Any]] ?? []]
            for array in arrays {
                for entry in array {
                    guard let vidStr = entry["vid"] as? String, vidStr.hasPrefix("0x"),
                          let pidStr = entry["pid"] as? String, pidStr.hasPrefix("0x"),
                          let vid = Int(vidStr.dropFirst(2), radix: 16),
                          let pid = Int(pidStr.dropFirst(2), radix: 16),
                          vid != 0, pid != 0
                    else { continue }
                    result.insert(Identity(vid: vid, pid: pid))
                }
            }
        }
        return result
    }()

    /// The 5 corpus-identified cables added to `data/known-cables.md` /
    /// `whatcable.db` from test-kit evidence (commit c45018418, "Add 5
    /// corpus-identified cables to the known-cables database"). Each must
    /// resolve to a curated row: this is the same database the app bundles,
    /// so a lookup miss here means the running app can't identify these
    /// cables either. `cableVDO` is the exact value the curated row was
    /// entered against, since `curatedCables` now discriminates on it.
    private static let recentlyAddedCables: [(vid: Int, pid: Int, cableVDO: UInt32, brandContains: String)] = [
        (0x05AC, 0x7203, 0x4368F8DB, "Thunderbolt 4 Pro Cable (3 m)"),
        (0x20C2, 0x080F, 0x45082043, "Sumitomo"),
        (0x20C2, 0x0714, 0x460A2643, "Sumitomo"),
        (0x0C62, 0xC8F1, 0x00082042, "Chant Sincere"),
    ]

    /// Fingerprints seen in the corpus that we deliberately refuse to name.
    ///
    /// 0x05AC:0x7209 was once curated as "likely Studio Display captive cable
    /// (test-kit corpus, seen alongside a Studio Display device on 3 of 8
    /// machines)". That is a guess about provenance, not an identification,
    /// and the app prints the brand column verbatim as "Cable identified as
    /// <brand>", so it was reading working notes out to users as the cable's
    /// name. It is now `(needs review)`, which `build-cable-db.swift` skips.
    private static let deliberatelyUnnamed: [(vid: Int, pid: Int)] = [
        (0x05AC, 0x7209),
    ]

    // MARK: - Coverage floor
    //
    // Measured directly against the committed corpus.jsonl at the time this
    // sweep was written, by a Python script mirroring this file's own filter
    // exactly (vid/pid must be "0x"-prefixed strings that parse as hex and
    // are both non-zero): 231 distinct (VID, PID) pairs across every folder's
    // `devices` + `cables` arrays. Floor = 85% of 231, rounded down:
    // 231 * 0.85 = 196.35 -> 196.
    //
    // An earlier scoping pass (used only to gauge scale before this file was
    // written, not the filter that shipped) had counted 268 by checking the
    // vid/pid strings were merely non-empty rather than non-zero, so it
    // counted zero-VID/zero-PID entries (e.g. `"0x0000"`/`"0x0000"`) as a
    // valid pair. This file's actual filter excludes those (mirroring
    // `CableDB.curatedCables`'s own zero-VID/PID guard, see the doc comment
    // above), so 268 never matched what the shipped code counts; 231 is the
    // correct figure for the filter actually in this file.
    //
    // corpus.jsonl is committed (unlike the gitignored raw probes the other
    // sweeps depend on), so this floor never skips on a fresh clone.
    private static let coverageFloor = 196

    // MARK: - Tests

    @Test("Coverage: the corpus has enough distinct (VID, PID) identities to exercise CableDB")
    func coverageFloorHolds() {
        #expect(Self.identities.count >= Self.coverageFloor,
            "Expected at least \(Self.coverageFloor) distinct (VID, PID) identities (85% of the 231 counted when this sweep was written); found \(Self.identities.count).")
    }

    @Test("No crash: every corpus (VID, PID) identity survives a CableDB round trip")
    func noCrashAcrossCorpus() {
        for id in Self.identities {
            _ = CableDB.vendorName(vid: id.vid)
            _ = CableDB.isUSBIFRegistered(id.vid)
            _ = CableDB.curatedCables(vid: id.vid, pid: id.pid, cableVDO: 0)
        }
        #expect(Bool(true))
    }

    @Test("Invariant: a vendor name is never empty when CableDB resolves one")
    func vendorNameNeverEmptyWhenResolved() {
        var examined = 0
        var violations: [String] = []
        for id in Self.identities {
            guard let name = CableDB.vendorName(vid: id.vid) else { continue }
            examined += 1
            if name.isEmpty {
                violations.append("VID 0x\(String(format: "%04X", id.vid)) resolved to an empty vendor name")
            }
        }
        if examined == 0 {
            Issue.record("No corpus VID resolved a vendor name at all; this invariant is untested by this sweep")
        }
        #expect(violations.isEmpty, "\(violations.joined(separator: "\n"))")
    }

    @Test("Invariant: isUSBIFRegistered implies vendorName is also resolvable")
    func usbifRegisteredImpliesVendorNameResolves() {
        // Source: `isUSBIFRegistered` checks `store.vendors[vid]?.source == "usbif"`,
        // which can only be true if `store.vendors[vid]` exists at all --
        // the same dictionary `vendorName(vid:)` reads. A VID that is
        // USB-IF-registered but resolves no name at all would mean the two
        // methods are reading inconsistent state.
        var examined = 0
        for id in Self.identities {
            guard CableDB.isUSBIFRegistered(id.vid) else { continue }
            examined += 1
            #expect(CableDB.vendorName(vid: id.vid) != nil,
                "VID 0x\(String(format: "%04X", id.vid)) is USB-IF registered but vendorName(vid:) returned nil")
        }
        if examined == 0 {
            Issue.record("No corpus VID was USB-IF registered; this invariant is untested by this sweep")
        }
    }

    @Test("A fingerprint we can't name resolves nothing, rather than a guess", arguments: Self.deliberatelyUnnamed)
    func unnamedCablesResolveNothing(_ fixture: (vid: Int, pid: Int)) {
        let matches = CableDB.curatedCables(vid: fixture.vid, pid: fixture.pid, cableVDO: 0)
        #expect(matches.isEmpty,
            "0x\(String(format: "%04X", fixture.vid)):0x\(String(format: "%04X", fixture.pid)) resolved \(matches.map(\.brand)); it is meant to stay unnamed until someone confirms what the cable is")
    }

    @Test("The recently-added corpus-identified cables resolve to their curated rows", arguments: Self.recentlyAddedCables)
    func recentlyAddedCablesResolve(_ fixture: (vid: Int, pid: Int, cableVDO: UInt32, brandContains: String)) {
        let matches = CableDB.curatedCables(vid: fixture.vid, pid: fixture.pid, cableVDO: fixture.cableVDO)
        #expect(!matches.isEmpty,
            "0x\(String(format: "%04X", fixture.vid)):0x\(String(format: "%04X", fixture.pid)) resolved no curated cable row")
        #expect(matches.contains { $0.brand.localizedCaseInsensitiveContains(fixture.brandContains) },
            "0x\(String(format: "%04X", fixture.vid)):0x\(String(format: "%04X", fixture.pid)) resolved \(matches.map(\.brand)), none containing '\(fixture.brandContains)'")
    }
}
