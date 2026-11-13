#!/usr/bin/env swift

// Build the bundled SQLite database from vendor and cable sources.
//
// Reads:
//   - Sources/WhatCableCore/Resources/usbif-vendors.tsv (USB-IF vendor list)
//   - https://usb-ids.gowdy.us/usb.ids (community vendor list, fetched live)
//
// Writes:
//   - Sources/WhatCableCore/Resources/whatcable.db (bundled in the app)
//   - docs/whatcable.db (served on the website)
//
// Run from the repo root:
//   swift scripts/build-cable-db.swift
//
// Flags:
//   --refresh-certs   refetch every USB-IF per-XID record instead of reusing
//                     the .cert-cache (picks up cables that changed, e.g.
//                     Pass -> Obsolete, or gained listings).
//   --test-parser     run the parser self-tests (manual vendors, contact-email
//                     stripping, known cables, cert-xids.tsv, the seeded
//                     cert-date fallback, per-XID response validation and
//                     the cert-date carry-forward) and exit.
// Env:
//   ALLOW_EMPTY_CERTS=1   permit a build with zero certifications (otherwise a
//                         collapsed cert table fails the build; see below).
//                         Also overrides a failed per-XID certification fetch
//                         (exit 6): with this set, a failed fetch is a
//                         warning, not a build failure.
//   WC_PREVIOUS_CERT_DB   path to a db to carry dropped certification dates
//                         forward from, instead of the committed
//                         Sources/WhatCableCore/Resources/whatcable.db (git
//                         HEAD). For restoring dates an earlier build lost.
//   WC_FAIL_CERT_FETCH    test hook: comma-separated XIDs, decimal or hex
//                         with a 0x prefix (e.g. 7238 or 0x1C46). Forces
//                         fetchPerXIDListings to fail (return nil) for those
//                         XIDs, before it checks the cache, no network
//                         involved. Lets the exit(6) failed-build path be
//                         exercised in a real build. Does nothing when unset
//                         or empty. A token it cannot parse is reported on
//                         stderr and ignored; empty tokens are ignored.
//
// Requires: macOS (uses system SQLite3 via libsqlite3).

import Foundation
import SQLite3

// MARK: - Paths

let repoRoot = FileManager.default.currentDirectoryPath
let vendorTSV = "\(repoRoot)/Sources/WhatCableCore/Resources/usbif-vendors.tsv"
let manualVendorTSV = "\(repoRoot)/data/manual-vendors.tsv"
let certXIDsTSV = "\(repoRoot)/data/cert-xids.tsv"
let dbOutput = "\(repoRoot)/Sources/WhatCableCore/Resources/whatcable.db"
let dbWebCopy = "\(repoRoot)/docs/whatcable.db"
let cablesJSON = "\(repoRoot)/docs/cables.json"
let manualCablesMD = "\(repoRoot)/data/known-cables.md"
// The "Last updated" date the /cables page shows. Written here and committed,
// rather than worked out at site-build time, because the only two signals
// available then are both wrong on the public side: a git checkout resets file
// mtimes to checkout time, and the public Pages workflow clones at depth 1 so
// `git log` has no per-file history to read. Baking it in at generation time
// means the date travels with the data it describes.
let cablesUpdatedJSON = "\(repoRoot)/src/_data/cablesmeta.json"

// Per-XID USB-IF responses are cached here so a rebuild only fetches XIDs
// it hasn't seen before. Gitignored: the compiled cable_certs table in
// whatcable.db is what ships, not this cache.
let certCacheDir = "\(repoRoot)/.cert-cache"

// `--refresh-certs` bypasses the per-XID cache and refetches every XID, so a
// cable that has since changed (e.g. Pass -> Obsolete, or gained listings)
// is picked up. Without it, cached responses (including cached empties) are
// reused indefinitely. A successful refetch overwrites its cache entry.
let refreshCerts = CommandLine.arguments.contains("--refresh-certs")

// Test hook (see WC_FAIL_CERT_FETCH in the header comment): forces
// fetchPerXIDListings to fail for these XIDs, so the exit(6) failed-build
// path can be watched firing in a real build without a network fetch and
// without waiting for a cold per-XID crawl. Empty when unset, which does
// nothing.
// Tokens may be decimal or 0x-prefixed hex, because XIDs are written in hex
// everywhere else and a silently dropped `0x1C46` would make the guard look
// broken. A token that parses as neither gets a stderr warning.
let forcedCertFetchFailures: Set<Int> = {
    var out: Set<Int> = []
    let raw = ProcessInfo.processInfo.environment["WC_FAIL_CERT_FETCH"] ?? ""
    for piece in raw.split(separator: ",") {
        let token = piece.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { continue }
        let value: Int?
        if token.hasPrefix("0x") || token.hasPrefix("0X") {
            value = Int(token.dropFirst(2), radix: 16)
        } else {
            value = Int(token)
        }
        if let value {
            out.insert(value)
        } else {
            fputs("warn: WC_FAIL_CERT_FETCH: cannot parse XID token '\(token)', ignoring it\n", stderr)
        }
    }
    return out
}()

// MARK: - SQLite helpers

/// Exit after openDB() has deleted the bundled db: by then both dbs may be
/// missing or partial, so say how to put them back before a re-run.
func failBuild(_ code: Int32) -> Never {
    fputs("""
        Both bundled databases may now be missing or partial. Restore them
        before re-running:
          git checkout -- Sources/WhatCableCore/Resources/whatcable.db docs/whatcable.db

        """, stderr)
    exit(code)
}

var db: OpaquePointer?

func openDB() {
    // Remove existing DB so we always start fresh.
    try? FileManager.default.removeItem(atPath: dbOutput)

    let rc = sqlite3_open(dbOutput, &db)
    guard rc == SQLITE_OK else {
        fputs("error: sqlite3_open failed: \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        failBuild(1)
    }
    // WAL mode and synchronous=OFF for build-time speed (we're writing
    // once and the file is read-only at runtime).
    runSQL("PRAGMA journal_mode = WAL")
    runSQL("PRAGMA synchronous = OFF")
}

func runSQL(_ sql: String) {
    var err: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &err)
    if rc != SQLITE_OK {
        let msg = err.map { String(cString: $0) } ?? "unknown"
        sqlite3_free(err)
        fputs("error: SQL failed: \(msg)\n  statement: \(sql)\n", stderr)
        failBuild(2)
    }
}

func closeDB() {
    // Switch out of WAL mode before shipping. The bundled .db is read-only
    // at runtime; WAL mode requires creating -shm/-wal sidecars, which
    // fails in read-only bundle directories.
    runSQL("PRAGMA journal_mode = DELETE")
    sqlite3_close(db)
    db = nil
    try? FileManager.default.removeItem(atPath: dbOutput + "-shm")
    try? FileManager.default.removeItem(atPath: dbOutput + "-wal")
}

// MARK: - Schema

func createSchema() {
    runSQL("""
        CREATE TABLE vendors (
            vid    INTEGER PRIMARY KEY,
            name   TEXT NOT NULL,
            source TEXT NOT NULL CHECK(source IN ('usbif', 'usbids', 'manual'))
        )
        """)

    runSQL("""
        CREATE TABLE cables (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            vid       INTEGER NOT NULL,
            pid       INTEGER NOT NULL,
            cable_vdo INTEGER NOT NULL DEFAULT 0,
            brand     TEXT NOT NULL,
            speed     TEXT NOT NULL DEFAULT '',
            power     TEXT NOT NULL DEFAULT '',
            type      TEXT NOT NULL DEFAULT 'passive',
            xid       TEXT NOT NULL DEFAULT 'none',
            issue_url TEXT NOT NULL DEFAULT ''
        )
        """)

    runSQL("CREATE INDEX idx_cables_fingerprint ON cables(vid, pid, cable_vdo)")

    // One (VID, PID) can legitimately cover several rows: the same OEM
    // silicon sold under different retail brands (#505, ACON 0x0522/0x0A33
    // as both Anker Prime and UGREEN), and one PID covering several
    // capability tiers told apart only by Cable VDO (#239, e.g. Chant
    // Sincere 0x0C62/0xC8F1's 3A and 5A variants). So identity is no longer
    // (VID, PID) alone; every parsed markdown row becomes a DB row.
    //
    // What's never legitimate is an EXACT duplicate: the same brand curated
    // twice for the same (VID, PID, Cable VDO). That is a data-entry error
    // (a row pasted twice, or two issues for the same cable never merged),
    // so the full key stays unique and a violation fails the build. See
    // `findExactDuplicateRow` below, which reports this with a clear message
    // before the DB insert can hit the constraint.
    runSQL("CREATE UNIQUE INDEX idx_cables_identity ON cables(vid, pid, cable_vdo, brand)")

    // USB-IF certification listings, keyed by the cable's Cert Stat XID.
    // One row per listing: a single XID can carry several (rebrands and
    // related models share it). This is neutral provenance, never a fraud
    // signal (see research/usb-if-registry.md): vendor_id is a mild
    // confirming match at most, absence is normal, and product_id is
    // deliberately NOT stored because USB-IF's is an internal row counter,
    // not a USB PID.
    runSQL("""
        CREATE TABLE cable_certs (
            xid       INTEGER NOT NULL,
            vendor_id INTEGER,
            company   TEXT NOT NULL DEFAULT '',
            model     TEXT NOT NULL DEFAULT '',
            status    TEXT NOT NULL DEFAULT '',
            cert_date TEXT NOT NULL DEFAULT '',
            source    TEXT NOT NULL DEFAULT 'per_xid' CHECK(source IN ('per_xid', 'bulk'))
        )
        """)
    runSQL("CREATE INDEX idx_cable_certs_xid ON cable_certs(xid)")
}

// MARK: - USB-IF vendor import

func importUSBIFVendors() -> Int {
    guard let text = try? String(contentsOfFile: vendorTSV, encoding: .utf8) else {
        fputs("error: could not read \(vendorTSV)\n", stderr)
        failBuild(3)
    }

    let insertSQL = "INSERT INTO vendors (vid, name, source) VALUES (?, ?, 'usbif')"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("error: prepare failed for vendor insert\n", stderr)
        failBuild(4)
    }

    runSQL("BEGIN TRANSACTION")
    var count = 0

    for line in text.components(separatedBy: "\n") {
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 2, let vid = Int(parts[0]) else { continue }
        var name = parts[1].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { continue }
        // Strip the " ‐ OBSOLETE" suffix from obsolete vendor entries so
        // users see clean names. The raw suffix is preserved in the TSV.
        let obsoleteSuffix = " \u{2010} OBSOLETE"
        if name.hasSuffix(obsoleteSuffix) {
            name = String(name.dropLast(obsoleteSuffix.count))
        }
        name = strippingContactEmail(from: name)

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(vid))
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            fputs("warn: failed to insert VID \(vid): \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        }
        count += 1
    }

    runSQL("COMMIT")
    sqlite3_finalize(stmt)
    return count
}

// MARK: - usb.ids community vendor import

// Mirrors of the same file, maintained by Stephen J. Gowdy. Tried in order.
// gowdy.us is the canonical primary; linux-usb.org serves an identical copy
// over plain HTTP. If both Gowdy-hosted mirrors are unreachable (cert expiry,
// DNS, etc.) we fall back to the Red Hat hwdata copy on GitHub, which lags
// upstream by a few months but is stable.
let usbidsMirrors: [URL] = [
    URL(string: "https://usb-ids.gowdy.us/usb.ids")!,
    URL(string: "http://www.linux-usb.org/usb.ids")!,
    URL(string: "https://raw.githubusercontent.com/vcrhonek/hwdata/master/usb.ids")!,
]

func fetchUSBIDs() -> String? {
    for url in usbidsMirrors {
        do {
            let data = try Data(contentsOf: url)
            // The file is mostly UTF-8 but contains a few invalid bytes.
            // Fall back to Latin-1 (which always succeeds) if strict UTF-8 fails.
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
            if text != nil {
                fputs("usb.ids: fetched from \(url.host ?? url.absoluteString)\n", stderr)
                return text
            }
        } catch {
            fputs("warn: usb.ids fetch failed from \(url.host ?? url.absoluteString): \(error)\n", stderr)
        }
    }
    return nil
}

func importUSBIDsVendors() -> (inserted: Int, skipped: Int) {
    guard let text = fetchUSBIDs() else {
        fputs("warn: skipping usb.ids (fetch failed)\n", stderr)
        return (0, 0)
    }

    // INSERT OR IGNORE: USB-IF entries take priority (already loaded).
    let insertSQL = "INSERT OR IGNORE INTO vendors (vid, name, source) VALUES (?, ?, 'usbids')"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("warn: prepare failed for usb.ids insert\n", stderr)
        return (0, 0)
    }

    runSQL("BEGIN TRANSACTION")
    var inserted = 0
    var skipped = 0

    // Format: lines starting with 4 hex digits + 2 spaces + name are
    // vendor entries. Lines with leading tabs are device/interface
    // entries (ignored). The vendor section ends at "C xx  class_name".
    let re = try! NSRegularExpression(pattern: "^([0-9a-fA-F]{4})  (.+)$")

    for line in text.components(separatedBy: "\n") {
        // Stop at the device class section.
        if line.hasPrefix("C ") { break }
        if line.hasPrefix("#") || line.hasPrefix("\t") || line.isEmpty { continue }

        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range),
              m.numberOfRanges >= 3,
              let vidRange = Range(m.range(at: 1), in: line),
              let nameRange = Range(m.range(at: 2), in: line) else { continue }

        guard let vid = Int(String(line[vidRange]), radix: 16) else { continue }
        let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { continue }

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(vid))
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            // sqlite3_changes returns 0 for INSERT OR IGNORE when the
            // row already existed.
            if sqlite3_changes(db) > 0 {
                inserted += 1
            } else {
                skipped += 1
            }
        } else {
            skipped += 1
        }
    }

    runSQL("COMMIT")
    sqlite3_finalize(stmt)
    return (inserted, skipped)
}

// MARK: - Manual vendor import (editorial additions)

struct ManualVendorEntry: Equatable {
    let vid: Int
    let name: String
}

/// Pure parser for manual-vendors.tsv. Returns parsed entries plus any
/// warnings the build script should print. Kept side-effect free so the
/// `--test-parser` mode can exercise it directly.
///
/// Validation rules:
/// - Comment lines (starting with `#`) and blank lines are ignored.
/// - Each data line must have exactly 2 tab-separated fields. Lines with
///   the wrong number of fields are warned and skipped.
/// - VID must be hex (with or without `0x`/`0X` prefix), within 0...0xFFFF.
/// - Name must be non-empty after trimming.
/// - Duplicate VIDs are warned and skipped (first occurrence wins).
func parseManualVendorsText(_ text: String) -> (entries: [ManualVendorEntry], warnings: [String]) {
    var entries: [ManualVendorEntry] = []
    var warnings: [String] = []
    var seen: Set<Int> = []

    for (zeroBasedIndex, rawLine) in text.components(separatedBy: "\n").enumerated() {
        let lineNum = zeroBasedIndex + 1
        // Trim only newlines and carriage returns at the line level so a
        // trailing tab (which is a real field separator) is not silently
        // collapsed into a single-field line. Per-field trimming below
        // still uses full whitespace.
        let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        let visible = line.trimmingCharacters(in: .whitespaces)
        if visible.isEmpty || visible.hasPrefix("#") { continue }

        let parts = line.components(separatedBy: "\t")
        guard parts.count == 2 else {
            warnings.append("manual-vendors.tsv line \(lineNum): expected exactly 2 tab-separated fields, got \(parts.count); skipping")
            continue
        }

        let vidToken = parts[0].trimmingCharacters(in: .whitespaces)
        let name = parts[1].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            warnings.append("manual-vendors.tsv line \(lineNum): empty vendor name; skipping")
            continue
        }

        let hexPart: String
        if vidToken.hasPrefix("0x") || vidToken.hasPrefix("0X") {
            hexPart = String(vidToken.dropFirst(2))
        } else {
            hexPart = vidToken
        }
        guard !hexPart.isEmpty, let vid = Int(hexPart, radix: 16) else {
            warnings.append("manual-vendors.tsv line \(lineNum): cannot parse VID '\(vidToken)' as hex; skipping")
            continue
        }
        guard (0...0xFFFF).contains(vid) else {
            warnings.append("manual-vendors.tsv line \(lineNum): VID '\(vidToken)' out of range (0...0xFFFF); skipping")
            continue
        }

        if !seen.insert(vid).inserted {
            warnings.append(String(format: "manual-vendors.tsv line %d: duplicate VID 0x%04X; keeping first occurrence", lineNum, vid))
            continue
        }

        entries.append(ManualVendorEntry(vid: vid, name: name))
    }

    return (entries, warnings)
}

func importManualVendors() -> (inserted: Int, skipped: Int) {
    guard let text = try? String(contentsOfFile: manualVendorTSV, encoding: .utf8) else {
        // The file is optional; an empty manual list is a valid state.
        return (0, 0)
    }

    let parsed = parseManualVendorsText(text)
    for warning in parsed.warnings {
        fputs("warn: \(warning)\n", stderr)
    }

    // INSERT OR IGNORE: USB-IF and usb.ids entries take priority, so a
    // manual row never silently overwrites either authoritative source.
    let insertSQL = "INSERT OR IGNORE INTO vendors (vid, name, source) VALUES (?, ?, 'manual')"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("warn: prepare failed for manual vendor insert\n", stderr)
        return (0, 0)
    }

    runSQL("BEGIN TRANSACTION")
    var inserted = 0
    var skipped = 0

    for entry in parsed.entries {
        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(entry.vid))
        sqlite3_bind_text(stmt, 2, (entry.name as NSString).utf8String, -1, nil)

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            if sqlite3_changes(db) > 0 {
                inserted += 1
            } else {
                skipped += 1
            }
        } else {
            skipped += 1
        }
    }

    runSQL("COMMIT")
    sqlite3_finalize(stmt)
    return (inserted, skipped)
}

// MARK: - Manual certification-ID seed (data/cert-xids.tsv)

struct ManualCertXID: Equatable {
    let xid: Int
    /// Certification date for this XID, in the same format the cable_certs
    /// column holds ("2019-01-25T00:00:00"), or "" when USB-IF never
    /// published one. Seeded here because the per-XID endpoint does not
    /// return a date and these XIDs are no longer in the bulk catalogue.
    let certDate: String
    let note: String
}

/// Pure parser for cert-xids.tsv. Returns parsed entries plus any warnings
/// the build script should print. Side-effect free so `--test-parser` can
/// exercise it directly.
///
/// Validation rules, deliberately the same shape as the manual-vendors
/// parser:
/// - Comment lines (starting with `#`) and blank lines are ignored.
/// - Each data line must have exactly 3 tab-separated fields:
///   XID, certification date, note.
/// - XID must be hex (with or without `0x`/`0X` prefix) and non-zero. Zero
///   is the "no certification" sentinel, never a real ID.
/// - The certification date may be empty: USB-IF genuinely publishes no date
///   for some listings, and an invented one would be worse than none.
/// - The note must be non-empty; it is for humans and the build ignores it.
/// - Duplicate XIDs are warned and skipped (first occurrence wins).
func parseCertXIDsText(_ text: String) -> (entries: [ManualCertXID], warnings: [String]) {
    var entries: [ManualCertXID] = []
    var warnings: [String] = []
    var seen: Set<Int> = []

    for (zeroBasedIndex, rawLine) in text.components(separatedBy: "\n").enumerated() {
        let lineNum = zeroBasedIndex + 1
        let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        let visible = line.trimmingCharacters(in: .whitespaces)
        if visible.isEmpty || visible.hasPrefix("#") { continue }

        let parts = line.components(separatedBy: "\t")
        guard parts.count == 3 else {
            warnings.append("cert-xids.tsv line \(lineNum): expected exactly 3 tab-separated fields, got \(parts.count); skipping")
            continue
        }

        let xidToken = parts[0].trimmingCharacters(in: .whitespaces)
        let certDate = parts[1].trimmingCharacters(in: .whitespaces)
        let note = parts[2].trimmingCharacters(in: .whitespaces)
        guard !note.isEmpty else {
            warnings.append("cert-xids.tsv line \(lineNum): empty note; skipping")
            continue
        }

        let hexPart: String
        if xidToken.hasPrefix("0x") || xidToken.hasPrefix("0X") {
            hexPart = String(xidToken.dropFirst(2))
        } else {
            hexPart = xidToken
        }
        guard !hexPart.isEmpty, let xid = Int(hexPart, radix: 16) else {
            warnings.append("cert-xids.tsv line \(lineNum): cannot parse XID '\(xidToken)' as hex; skipping")
            continue
        }
        guard xid > 0, xid <= 0xFFFF_FFFF else {
            warnings.append("cert-xids.tsv line \(lineNum): XID '\(xidToken)' out of range (1...0xFFFFFFFF); skipping")
            continue
        }
        guard !seen.contains(xid) else {
            warnings.append("cert-xids.tsv line \(lineNum): duplicate XID '\(xidToken)'; skipping")
            continue
        }
        seen.insert(xid)
        entries.append(ManualCertXID(xid: xid, certDate: certDate, note: note))
    }

    return (entries, warnings)
}

/// Certification IDs named in data/cert-xids.tsv, each with its seeded
/// certification date ("" when USB-IF publishes none).
///
/// Third seed alongside `curatedXIDs()` and `corpusXIDs()`, for IDs none of
/// the automated sources lists today.
///
/// A missing file is not an error: the seed list is optional and an absent
/// one just means no extra IDs. A file that EXISTS but cannot be read is a
/// different thing entirely, and silently returning an empty set there would
/// reproduce the very bug this file was added to stop (one stray non-UTF-8
/// byte is enough). Same shape as `importKnownCables()`: warn loudly to
/// stderr, then carry on.
func manualCertXIDs(path: String = certXIDsTSV) -> [Int: String] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        if FileManager.default.fileExists(atPath: path) {
            fputs("warn: \(path) exists but could not be read as UTF-8; " +
                  "no seeded certification IDs this build\n", stderr)
        }
        return [:]
    }
    let (entries, warnings) = parseCertXIDsText(text)
    for warning in warnings { fputs("warn: \(warning)\n", stderr) }
    return Dictionary(uniqueKeysWithValues: entries.map { ($0.xid, $0.certDate) })
}

// MARK: - Self-test mode (--test-parser)

/// Returns a tuple (failures, output). Failures is the number of failed
/// assertions; output is the formatted test report.
func runManualVendorParserSelfTests() -> (failures: Int, output: String) {
    struct Case {
        let label: String
        let input: String
        let expectedEntries: [ManualVendorEntry]
        let expectedWarningSubstrings: [String]
    }

    let cases: [Case] = [
        Case(
            label: "happy path: single entry with 0x prefix",
            input: "0x01B6\tCalDigit, Inc.\n",
            expectedEntries: [ManualVendorEntry(vid: 0x01B6, name: "CalDigit, Inc.")],
            expectedWarningSubstrings: []
        ),
        Case(
            label: "happy path: hex without prefix, lowercase, uppercase",
            input: "01b6\tlower\n0X02A2\tupper-prefix\nFFFF\tmax\n",
            expectedEntries: [
                ManualVendorEntry(vid: 0x01B6, name: "lower"),
                ManualVendorEntry(vid: 0x02A2, name: "upper-prefix"),
                ManualVendorEntry(vid: 0xFFFF, name: "max"),
            ],
            expectedWarningSubstrings: []
        ),
        Case(
            label: "comments and blank lines are ignored",
            input: "# header comment\n\n# another\n0x01B6\tCalDigit, Inc.\n\n",
            expectedEntries: [ManualVendorEntry(vid: 0x01B6, name: "CalDigit, Inc.")],
            expectedWarningSubstrings: []
        ),
        Case(
            label: "extra fields are rejected",
            input: "0x01B6\tCalDigit, Inc.\textra\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["expected exactly 2 tab-separated fields"]
        ),
        Case(
            label: "single field is rejected",
            input: "0x01B6\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["expected exactly 2 tab-separated fields"]
        ),
        Case(
            label: "empty name is rejected",
            input: "0x01B6\t   \n",
            expectedEntries: [],
            expectedWarningSubstrings: ["empty vendor name"]
        ),
        Case(
            label: "non-hex VID is rejected",
            input: "0xZZZZ\tBogus\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["cannot parse VID"]
        ),
        Case(
            label: "VID out of 16-bit range is rejected",
            input: "0x10000\tToo big\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["out of range"]
        ),
        Case(
            label: "duplicate VID: first wins, second warned",
            input: "0x01B6\tFirst\n0x01B6\tSecond\n",
            expectedEntries: [ManualVendorEntry(vid: 0x01B6, name: "First")],
            expectedWarningSubstrings: ["duplicate VID 0x01B6"]
        ),
        Case(
            label: "VID 0 is allowed (lower bound)",
            input: "0x0000\tBoundary low\n",
            expectedEntries: [ManualVendorEntry(vid: 0, name: "Boundary low")],
            expectedWarningSubstrings: []
        ),
    ]

    var output = "Manual vendor parser self-tests\n"
    output += "================================\n"
    var failures = 0

    for c in cases {
        let result = parseManualVendorsText(c.input)
        var caseFailed = false
        var detail = ""

        if result.entries != c.expectedEntries {
            caseFailed = true
            detail += "  entries: expected \(c.expectedEntries), got \(result.entries)\n"
        }
        for substring in c.expectedWarningSubstrings {
            if !result.warnings.contains(where: { $0.contains(substring) }) {
                caseFailed = true
                detail += "  warnings missing '\(substring)'; got \(result.warnings)\n"
            }
        }
        if c.expectedWarningSubstrings.isEmpty && !result.warnings.isEmpty {
            caseFailed = true
            detail += "  unexpected warnings: \(result.warnings)\n"
        }

        if caseFailed {
            failures += 1
            output += "FAIL  \(c.label)\n"
            output += detail
        } else {
            output += "ok    \(c.label)\n"
        }
    }

    output += "\n\(cases.count - failures)/\(cases.count) passed"
    if failures > 0 {
        output += ", \(failures) FAILED"
    }
    output += "\n"
    return (failures, output)
}

/// Self-tests for `strippingContactEmail`. A vendor name legitimately
/// containing an `@` must survive untouched; only an actual address goes.
func runContactEmailSelfTests() -> (failures: Int, output: String) {
    let cases: [(label: String, input: String, expected: String)] = [
        // Fabricated addresses on purpose. An earlier version of these tests
        // used the real row from the registry, which would have written the
        // very address being stripped from the database into this file, which
        // ships publicly and keeps it in git history forever. Exactly the leak
        // the function exists to prevent, one layer up.
        ("a contact address is removed, company kept",
         "Example Instruments Inc. , firstname@example.com", "Example Instruments Inc."),
        ("an @ inside a company name survives",
         "M@inNet Communication", "M@inNet Communication"),
        ("a company name that IS an @-domain survives",
         "@pos.com", "@pos.com"),
        ("a plain name is untouched",
         "CalDigit, Inc.", "CalDigit, Inc."),
        ("an address with no comma is still removed",
         "Acme Ltd info@example.co.uk", "Acme Ltd"),
        ("a name that is only an address is kept rather than emptied",
         "firstname@example.com", "firstname@example.com"),
    ]
    var failures = 0
    var output = ""
    for c in cases {
        let got = strippingContactEmail(from: c.input)
        if got == c.expected {
            output += "ok    \(c.label)\n"
        } else {
            failures += 1
            output += "FAIL  \(c.label)\n        input:    \(c.input)\n"
            output += "        expected: \(c.expected)\n        got:      \(got)\n"
        }
    }
    output += "\n\(cases.count - failures)/\(cases.count) passed"
    if failures > 0 { output += ", \(failures) FAILED" }
    output += "\n"
    return (failures, output)
}

// --test-parser runs all self-test suites (manual-vendors, contact-email
// stripping, and the known-cables row parser below) and exits; see the
// bottom of the "Known cables import" section for the actual invocation,
// after `runKnownCablesParserSelfTests` is defined.

// MARK: - Known cables import (from data/known-cables.md)

let knownCablesMD = "\(repoRoot)/data/known-cables.md"

/// Parsed cable row from the markdown table, before DB insert.
private struct CableRow: Equatable {
    let vid: Int
    let pid: Int
    let cableVDO: Int
    let brand: String
    let speed: String
    let power: String
    let type: String
    let xid: String
    let issueURL: String
}

/// Parse "`0xABCD`" or "`0x01234567`" into an integer.
func parseHex(_ s: String) -> Int? {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "`", with: "")
    guard trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") else { return nil }
    return Int(trimmed.dropFirst(2), radix: 16)
}

/// Pure parser for the known-cables markdown table: turns the "## Table"
/// block into flat `CableRow`s, applying the same skip rules the build uses.
/// No I/O beyond the text passed in, no sqlite, no `exit()`, so `--test-parser`
/// can exercise it directly and prove each rule actually does something.
///
/// Skip rules:
/// - `(needs review)` brand: no usable brand context yet.
/// - all-zero fingerprint (vid == 0 && pid == 0 && cableVDO == 0): carries no
///   identifying bits; `CableDB.curatedCables` refuses it at lookup time too.
private func parseCableRowsText(_ text: String) -> (
    rows: [CableRow], totalDataRows: Int, skippedNeedsReview: Int, skippedAllZero: Int
) {
    var parsed: [CableRow] = []
    var totalDataRows = 0
    var skippedNeedsReview = 0
    var skippedAllZero = 0
    var inTable = false

    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("## Table") { inTable = true; continue }
        if inTable, line.hasPrefix("## ") { break }
        guard inTable, line.hasPrefix("|"), !line.contains("---") else { continue }

        let parts = line.dropFirst().dropLast()
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // 10 columns: Brand, VID, PID, Cable VDO, Vendor, XID, Speed, Power, Type, Source
        guard parts.count == 10 else { continue }
        // Skip header row
        guard parts[1].hasPrefix("`0x") else { continue }

        totalDataRows += 1
        let brand = parts[0]
        // Skip "(needs review)" rows - they have no usable brand context yet.
        if brand == "(needs review)" {
            skippedNeedsReview += 1
            continue
        }

        guard let vid = parseHex(parts[1]),
              let pid = parseHex(parts[2]) else { continue }
        let cableVDO = parseHex(parts[3]) ?? 0

        // All-zero fingerprint carries no identifying bits; CableDB.curatedCable
        // refuses it at lookup time, so there's no point storing it.
        if vid == 0 && pid == 0 && cableVDO == 0 {
            skippedAllZero += 1
            continue
        }

        let xid = parts[5].replacingOccurrences(of: "`", with: "")
        let speed = parts[6]
        let power = parts[7]
        let type = parts[8]
        // Source cell holds a markdown link "[#NN](url)", possibly with prose
        // around it. Anchor on "](" rather than the first "(" in the cell: a
        // source note like "Test-kit corpus (7 machines), see [#478](url)"
        // would otherwise yield "7 machines" as the link target.
        let issueURL: String
        if let linkStart = parts[9].range(of: "]("),
           let urlEnd = parts[9].range(of: ")", range: linkStart.upperBound..<parts[9].endIndex) {
            issueURL = String(parts[9][linkStart.upperBound..<urlEnd.lowerBound])
        } else {
            issueURL = ""
        }

        parsed.append(CableRow(
            vid: vid, pid: pid, cableVDO: cableVDO,
            brand: brand, speed: speed, power: power, type: type,
            xid: xid, issueURL: issueURL
        ))
    }

    return (parsed, totalDataRows, skippedNeedsReview, skippedAllZero)
}

/// Hex-formatted (VID, PID, Cable VDO) triple, for error messages.
private func fingerprintLabel(vid: Int, pid: Int, cableVDO: Int) -> String {
    String(format: "0x%04X:0x%04X:0x%08X", vid, pid, UInt32(bitPattern: Int32(cableVDO)))
}

/// Finds rows that share a real (VID, PID, Cable VDO) fingerprint but
/// disagree on Speed, Power, or Type, and returns a description of the
/// first one found (or nil if every shared fingerprint agrees).
///
/// "Real" excludes vid == 0 or pid == 0: a zeroed identity is not a product
/// identity (many unrelated cables legitimately share it), so consistency
/// isn't meaningful there. Two rows with different brands but the same real
/// fingerprint (the #505 case: the same OEM cable sold as Anker and UGREEN)
/// are expected to agree on capability even though the brand differs, because
/// they are the same physical cable; if they don't agree, that's a
/// data-entry mistake in one of the rows, not two different cables.
private func findFingerprintInconsistency(_ rows: [CableRow]) -> String? {
    var seenByKey: [String: CableRow] = [:]
    for row in rows {
        guard row.vid != 0, row.pid != 0 else { continue }
        let key = "\(row.vid):\(row.pid):\(row.cableVDO)"
        guard let existing = seenByKey[key] else {
            seenByKey[key] = row
            continue
        }
        if existing.speed != row.speed || existing.power != row.power || existing.type != row.type {
            let fp = fingerprintLabel(vid: row.vid, pid: row.pid, cableVDO: row.cableVDO)
            return """
                data/known-cables.md has inconsistent Speed/Power/Type for the same \
                (VID, PID, Cable VDO) fingerprint \(fp):
                  '\(existing.brand)': speed='\(existing.speed)' power='\(existing.power)' type='\(existing.type)'
                  '\(row.brand)': speed='\(row.speed)' power='\(row.power)' type='\(row.type)'
                Fix the markdown row(s) before rebuilding.
                """
        }
    }
    return nil
}

/// Finds an exact duplicate row (same VID, PID, Cable VDO, AND brand) and
/// returns a description of the first one found, or nil if every row's full
/// key is unique. Mirrors the `UNIQUE(vid, pid, cable_vdo, brand)` index the
/// build enforces in sqlite; checking it here first gives a clearer message
/// than a raw sqlite constraint error.
private func findExactDuplicateRow(_ rows: [CableRow]) -> String? {
    var seen: Set<String> = []
    for row in rows {
        let key = "\(row.vid):\(row.pid):\(row.cableVDO):\(row.brand)"
        if !seen.insert(key).inserted {
            let fp = fingerprintLabel(vid: row.vid, pid: row.pid, cableVDO: row.cableVDO)
            return """
                data/known-cables.md has an exact duplicate row for \(fp) '\(row.brand)'. \
                Merge the two rows (keep every issue link in the Source cell) rather than \
                curating the same product twice.
                """
        }
    }
    return nil
}

/// Drops a contact email address from a USB-IF vendor name, keeping the
/// organisation.
///
/// The upstream registry occasionally carries a person's work email in the
/// company field, in the shape `Some Company Inc. , firstname@example.com`. We
/// redistribute that list inside `whatcable.db`, so it ships in the app and on
/// the website. The company name is the useful part and the only part the app
/// displays; the individual's address is not ours to publish.
///
/// Deliberately narrow. It removes an email-shaped token and any comma left
/// stranded in front of it, and nothing else. Vendor names that legitimately
/// contain an `@` are common (`M@inNet Communication`, `@pos.com` are both real
/// entries) and must survive untouched, so this only fires on a token that
/// actually looks like `local@domain.tld`.
func strippingContactEmail(from name: String) -> String {
    guard name.contains("@") else { return name }
    let pattern = #"\s*,?\s*\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return name }
    let range = NSRange(name.startIndex..., in: name)
    let stripped = re.stringByReplacingMatches(in: name, range: range, withTemplate: "")
    let cleaned = stripped
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        .trimmingCharacters(in: .whitespaces)
    // Never return an empty name: if the whole field was an address, the
    // original is more useful than nothing and the caller's guard expects
    // non-empty.
    return cleaned.isEmpty ? name : cleaned
}

/// Validates `data/known-cables.md` and fails the build loudly on a data
/// error, before `openDB()` touches anything.
///
/// Three checks, all fatal:
/// - **Brand column provenance text.** The app prints this column verbatim
///   as "Cable identified as `<brand>`", so provenance prose here is read
///   out to users as the cable's name. Two rows once carried corpus
///   working-notes and a beta tester was told his Apple cable was "seen with
///   CalDigit devices (test-kit corpus)". A cable we cannot name is
///   `(needs review)`, not a description of where we found it. Provenance
///   belongs in the Source column.
/// - **Fingerprint inconsistency** (`findFingerprintInconsistency`): two rows
///   sharing a real (VID, PID, Cable VDO) fingerprint must agree on
///   Speed/Power/Type.
/// - **Exact duplicate row** (`findExactDuplicateRow`): the same brand
///   curated twice for the same fingerprint.
///
/// `openDB()` deletes the bundled database before writing a fresh one, so
/// all three checks run here, on the raw markdown text, before that happens.
/// A rejected row stops the build while every generated artifact (the
/// bundled db, the docs copy, the website JSON) is still untouched. This
/// used to be true only of the first check; the other two ran inside
/// `importKnownCables()`, after `openDB()` had already truncated the
/// bundled db to a vendors-only shell, so a failure there left a corrupt
/// `whatcable.db` in the tree. Moved here so a failure anywhere in this
/// function never touches the db at all.
func validateKnownCablesMarkdown() {
    guard let text = try? String(contentsOfFile: knownCablesMD, encoding: .utf8) else { return }

    var inTable = false
    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("## Table") { inTable = true; continue }
        if inTable, line.hasPrefix("## ") { break }
        guard inTable, line.hasPrefix("|"), !line.contains("---") else { continue }

        let parts = line.dropFirst().dropLast()
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 10, parts[1].hasPrefix("`0x") else { continue }

        let brand = parts[0]
        if brand == "(needs review)" { continue }

        for phrase in ["corpus", "seen with", "seen alongside"] where brand.lowercased().contains(phrase) {
            fputs("""
            error: brand column contains provenance text ("\(phrase)"), not a product name:
              \(brand)
              Move it to the Source column, or use (needs review) if the cable can't be named.

            """, stderr)
            exit(1)
        }
    }

    // Same pure parse importKnownCables() uses later, run here purely to
    // feed the two invariant checks before any db write happens. The parsed
    // rows aren't reused for the actual import: importKnownCables() re-reads
    // and re-parses the file itself, same as this function already re-reads
    // it separately from the brand-column check above.
    let parsed = parseCableRowsText(text).rows
    if let message = findFingerprintInconsistency(parsed) {
        fputs("error: \(message)\n", stderr)
        exit(9)
    }
    if let message = findExactDuplicateRow(parsed) {
        fputs("error: \(message)\n", stderr)
        exit(10)
    }
}

/// Self-tests for the known-cables row parser and the two build-time
/// invariants (`findFingerprintInconsistency`, `findExactDuplicateRow`).
/// Each "should fail" case proves the check actually catches the bad
/// fixture, not just that it stays quiet on good data.
private func tableFixture(_ rows: String) -> String {
    """
    ## Table

    | Brand / model context | VID | PID | Cable VDO | Vendor | XID | Speed | Power | Type | Source |
    |---|---|---|---|---|---|---|---|---|---|
    \(rows)

    ## Next section
    """
}

func runKnownCablesParserSelfTests() -> (failures: Int, output: String) {
    var output = "Known-cables row parser self-tests\n"
    output += "===================================\n"
    var failures = 0
    func check(_ condition: @autoclosure () -> Bool, _ label: String, _ detail: String = "") {
        if condition() {
            output += "ok    \(label)\n"
        } else {
            failures += 1
            output += "FAIL  \(label)\n"
            if !detail.isEmpty { output += "  \(detail)\n" }
        }
    }

    // Two brands sharing one (vid, pid, vdo), agreeing on capability: both
    // should parse and both should insert (no inconsistency, no duplicate).
    // This is the #505 shape (Anker Prime + UGREEN on the same ACON silicon).
    do {
        let md = tableFixture("""
            | Anker Prime | `0x0522` | `0x0A33` | `0x110A2644` | ACON | `0x943` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#418](url) |
            | UGREEN | `0x0522` | `0x0A33` | `0x110A2644` | ACON | `0x943` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#505](url) |
            """)
        let parsed = parseCableRowsText(md)
        check(parsed.rows.count == 2, "two brands sharing one fingerprint: both parsed",
            "got \(parsed.rows.count) rows")
        check(findFingerprintInconsistency(parsed.rows) == nil, "two brands sharing one fingerprint: no inconsistency flagged",
            findFingerprintInconsistency(parsed.rows) ?? "")
        check(findExactDuplicateRow(parsed.rows) == nil, "two brands sharing one fingerprint: no duplicate flagged",
            findExactDuplicateRow(parsed.rows) ?? "")
    }

    // Variant rows: same (vid, pid), different Cable VDO. Both should insert;
    // this is the Chant Sincere 3A/5A shape (#239).
    do {
        let md = tableFixture("""
            | Lenovo 3A | `0x0C62` | `0xC8F1` | `0x00082022` | Chant Sincere | `0x573` | USB 3.2 Gen 2 (10 Gbps) | 3 A / 20 V (60 W) | passive | [#402](url) |
            | Lenovo 5A | `0x0C62` | `0xC8F1` | `0x00082042` | Chant Sincere | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#403](url) |
            """)
        let parsed = parseCableRowsText(md)
        check(parsed.rows.count == 2, "variant rows, different VDO: both parsed",
            "got \(parsed.rows.count) rows")
        check(findFingerprintInconsistency(parsed.rows) == nil, "variant rows, different VDO: no inconsistency flagged (different fingerprints)",
            findFingerprintInconsistency(parsed.rows) ?? "")
        check(findExactDuplicateRow(parsed.rows) == nil, "variant rows, different VDO: no duplicate flagged",
            findExactDuplicateRow(parsed.rows) ?? "")
    }

    // Speed mismatch within the same (vid, pid, vdo): must fail. Proves the
    // check can actually fire, not just pass silently on good data.
    do {
        let md = tableFixture("""
            | Brand A | `0x1234` | `0x0001` | `0x00082042` | Vendor | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#1](url) |
            | Brand B | `0x1234` | `0x0001` | `0x00082042` | Vendor | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#2](url) |
            """)
        let parsed = parseCableRowsText(md)
        let result = findFingerprintInconsistency(parsed.rows)
        check(result != nil, "speed mismatch within one fingerprint: flagged as inconsistent")
        if let result {
            output += "  observed failure: \(result.split(separator: "\n").first ?? "")\n"
        }
    }

    // Exact full-key duplicate (same vid, pid, vdo, AND brand): must fail.
    do {
        let md = tableFixture("""
            | Same Brand | `0x1234` | `0x0002` | `0x00082042` | Vendor | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#3](url) |
            | Same Brand | `0x1234` | `0x0002` | `0x00082042` | Vendor | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#4](url) |
            """)
        let parsed = parseCableRowsText(md)
        let result = findExactDuplicateRow(parsed.rows)
        check(result != nil, "exact full-key duplicate: flagged")
        if let result {
            output += "  observed failure: \(result.split(separator: "\n").first ?? "")\n"
        }
    }

    // Row-count bookkeeping: (needs review) and all-zero rows are excluded
    // from `rows` but counted in totalDataRows/skipped*, so
    // totalDataRows - skippedNeedsReview - skippedAllZero == rows.count.
    do {
        let md = tableFixture("""
            | Real cable | `0x1234` | `0x0003` | `0x00082042` | Vendor | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#5](url) |
            | (needs review) | `0x1234` | `0x0004` | `0x00082042` | Vendor | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#6](url) |
            | All zero | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#7](url) |
            """)
        let parsed = parseCableRowsText(md)
        check(parsed.rows.count == 1, "row-count bookkeeping: only the real cable parses into rows",
            "got \(parsed.rows.count) rows")
        check(parsed.totalDataRows == 3, "row-count bookkeeping: totalDataRows counts every data row",
            "got \(parsed.totalDataRows)")
        check(parsed.skippedNeedsReview == 1 && parsed.skippedAllZero == 1,
            "row-count bookkeeping: skip counts match",
            "needsReview=\(parsed.skippedNeedsReview) allZero=\(parsed.skippedAllZero)")
        check(parsed.rows.count == parsed.totalDataRows - parsed.skippedNeedsReview - parsed.skippedAllZero,
            "row-count bookkeeping: rows.count == totalDataRows - skippedNeedsReview - skippedAllZero")
    }

    output += "\n\(failures == 0 ? "all passed" : "\(failures) FAILED")\n"
    return (failures, output)
}

func runCertXIDParserSelfTests() -> (failures: Int, output: String) {
    struct Case {
        let label: String
        let input: String
        let expectedEntries: [ManualCertXID]
        let expectedWarningSubstrings: [String]
    }

    let cases: [Case] = [
        Case(
            label: "happy path: 0x prefix, no prefix, mixed case",
            input: "0x3399\t2021-03-04T00:00:00\tStarTech.com Ltd.: CC3M20GUSB4CX\n"
                + "17bc\t2019-08-26T00:00:00\tON Semiconductor: FUSB380C\n"
                + "0X241205\t2024-02-08T00:00:00\tLuxshare-ICT: sample\n",
            expectedEntries: [
                ManualCertXID(xid: 0x3399, certDate: "2021-03-04T00:00:00",
                              note: "StarTech.com Ltd.: CC3M20GUSB4CX"),
                ManualCertXID(xid: 0x17BC, certDate: "2019-08-26T00:00:00",
                              note: "ON Semiconductor: FUSB380C"),
                ManualCertXID(xid: 0x241205, certDate: "2024-02-08T00:00:00",
                              note: "Luxshare-ICT: sample"),
            ],
            expectedWarningSubstrings: []
        ),
        Case(
            label: "comments and blank lines are ignored",
            input: "# header\n\n# another\n0x3399\t2021-03-04T00:00:00\tStarTech.com Ltd.\n\n",
            expectedEntries: [
                ManualCertXID(xid: 0x3399, certDate: "2021-03-04T00:00:00",
                              note: "StarTech.com Ltd."),
            ],
            expectedWarningSubstrings: []
        ),
        Case(
            label: "an empty date field is valid; USB-IF publishes none for some IDs",
            input: "0x1C53\t\tStarTech.com Ltd.: 50C-40G-USB4-CABLE\n",
            expectedEntries: [
                ManualCertXID(xid: 0x1C53, certDate: "",
                              note: "StarTech.com Ltd.: 50C-40G-USB4-CABLE"),
            ],
            expectedWarningSubstrings: []
        ),
        Case(
            label: "XID 0 is the no-certification sentinel and is rejected",
            input: "0x0\t2021-03-04T00:00:00\tnot a real listing\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["out of range"]
        ),
        Case(
            label: "XID above 32 bits is rejected (upper bound)",
            input: "0x100000000\t2021-03-04T00:00:00\tone bit past the top\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["out of range"]
        ),
        Case(
            label: "unparseable XID is warned and skipped",
            input: "notahex\t2021-03-04T00:00:00\tsomething\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["cannot parse XID"]
        ),
        Case(
            label: "too few fields is warned and skipped",
            input: "0x3399\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["expected exactly 3 tab-separated fields"]
        ),
        Case(
            label: "the old 2-field shape is warned and skipped, not read as a dateless entry",
            input: "0x3399\tStarTech.com Ltd.: CC3M20GUSB4CX\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["expected exactly 3 tab-separated fields"]
        ),
        Case(
            label: "too many fields is warned and skipped",
            input: "0x3399\t2021-03-04T00:00:00\tStarTech.com Ltd.\tstray fourth field\n",
            expectedEntries: [],
            expectedWarningSubstrings: ["expected exactly 3 tab-separated fields"]
        ),
        Case(
            label: "empty note is warned and skipped",
            input: "0x3399\t2021-03-04T00:00:00\t   \n",
            expectedEntries: [],
            expectedWarningSubstrings: ["empty note"]
        ),
        Case(
            label: "duplicate XID keeps the first and warns",
            input: "0x3399\t2021-03-04T00:00:00\tfirst\n0x3399\t2022-01-01T00:00:00\tsecond\n",
            expectedEntries: [
                ManualCertXID(xid: 0x3399, certDate: "2021-03-04T00:00:00", note: "first"),
            ],
            expectedWarningSubstrings: ["duplicate XID"]
        ),
        // The case the rest of this suite cannot make: a rejected line must
        // SKIP, not stop the parse. Every reject path is sandwiched between
        // two good lines, and both good lines are expected out the far side.
        // Turning any one `continue` in this parser into a `break` loses the
        // good lines below it, which is exactly the shape of the 2026-09-22
        // incident: the file is read, no error is raised, and most of the
        // seeded IDs quietly never reach the build.
        Case(
            label: "a rejected line is skipped, not fatal: good lines after every reject kind survive",
            input: "0x1111\t2020-01-01T00:00:00\tfirst good\n"
                + "0x2222\t2020-01-01T00:00:00\ttoo many\tfields\n"
                + "0x3333\t2020-01-01T00:00:00\t   \n"
                + "notahex\t2020-01-01T00:00:00\tbad xid\n"
                + "0x100000000\t2020-01-01T00:00:00\tout of range\n"
                + "0x1111\t2020-01-01T00:00:00\tduplicate of the first\n"
                + "0x9999\n"
                + "0x4444\t\tlast good, dateless\n",
            expectedEntries: [
                ManualCertXID(xid: 0x1111, certDate: "2020-01-01T00:00:00", note: "first good"),
                ManualCertXID(xid: 0x4444, certDate: "", note: "last good, dateless"),
            ],
            expectedWarningSubstrings: [
                "expected exactly 3 tab-separated fields",
                "empty note",
                "cannot parse XID",
                "out of range",
                "duplicate XID",
            ]
        ),
    ]

    var failures = 0
    var output = "cert-xids parser:\n"
    for testCase in cases {
        let (entries, warnings) = parseCertXIDsText(testCase.input)
        var problems: [String] = []
        if entries != testCase.expectedEntries {
            problems.append("entries \(entries) != expected \(testCase.expectedEntries)")
        }
        for expected in testCase.expectedWarningSubstrings
        where !warnings.contains(where: { $0.contains(expected) }) {
            problems.append("missing warning containing '\(expected)' (got \(warnings))")
        }
        if testCase.expectedWarningSubstrings.isEmpty && !warnings.isEmpty {
            problems.append("unexpected warnings \(warnings)")
        }
        if problems.isEmpty {
            output += "  ok: \(testCase.label)\n"
        } else {
            failures += 1
            output += "  FAIL: \(testCase.label)\n"
            for problem in problems { output += "    - \(problem)\n" }
        }
    }
    output += "\n\(failures == 0 ? "all passed" : "\(failures) FAILED")\n"
    return (failures, output)
}

if CommandLine.arguments.contains("--test-parser") {
    let (vendorFailures, vendorReport) = runManualVendorParserSelfTests()
    let (emailFailures, emailReport) = runContactEmailSelfTests()
    let (cableFailures, cableReport) = runKnownCablesParserSelfTests()
    let (certXIDFailures, certXIDReport) = runCertXIDParserSelfTests()
    let (certDateFailures, certDateReport) = runCertDateFallbackSelfTests()
    let (perXIDFailures, perXIDReport) = runPerXIDResponseSelfTests()
    let (carryFailures, carryReport) = runCertDateCarrySelfTests()
    FileHandle.standardOutput.write(vendorReport.data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write("\ncontact-email stripping:\n".data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write(emailReport.data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write("\n".data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write(cableReport.data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write("\n".data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write(certXIDReport.data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write("\n".data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write(certDateReport.data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write("\n".data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write(perXIDReport.data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write("\n".data(using: .utf8) ?? Data())
    FileHandle.standardOutput.write(carryReport.data(using: .utf8) ?? Data())
    exit((vendorFailures + emailFailures + cableFailures
          + certXIDFailures + certDateFailures + perXIDFailures
          + carryFailures) == 0 ? 0 : 1)
}

func importKnownCables() -> Int {
    guard let text = try? String(contentsOfFile: knownCablesMD, encoding: .utf8) else {
        fputs("warn: could not read \(knownCablesMD), skipping cables\n", stderr)
        return 0
    }

    // Parse all valid markdown rows into a flat list. No merging: each row
    // from the markdown becomes one DB row. The fingerprint index
    // (idx_cables_fingerprint) lets CableDB look up all rows for a given
    // (vid, pid, cable_vdo).
    let (parsed, totalDataRows, skippedNeedsReview, skippedAllZero) = parseCableRowsText(text)

    if skippedNeedsReview > 0 {
        print("warn: skipped \(skippedNeedsReview) row(s) with '(needs review)' brand - hand-edit before next build")
    }
    if skippedAllZero > 0 {
        print("Skipped \(skippedAllZero) all-zero-fingerprint markdown row(s) (cannot identify a cable)")
    }

    // Count shared fingerprints for informational output only.
    var fingerprintCounts: [String: Int] = [:]
    for row in parsed {
        let key = "\(row.vid):\(row.pid):\(row.cableVDO)"
        fingerprintCounts[key, default: 0] += 1
    }
    let sharedCount = fingerprintCounts.values.filter { $0 > 1 }.count
    if sharedCount > 0 {
        print("note: \(sharedCount) fingerprint(s) shared by multiple rows (same OEM cable under different brands, or a capability variant told apart by Cable VDO)")
    }

    // Build-time invariants (fingerprint consistency, exact duplicates)
    // already ran in validateKnownCablesMarkdown(), on the same parse, before
    // openDB() touched anything. Not re-run here: this function runs after
    // the db has already been truncated, so a failure here can no longer
    // stop a bad row before some artifact gets written. Every parsed row is
    // inserted directly; the UNIQUE(vid, pid, cable_vdo, brand) index is a
    // belt-and-braces backstop in case a future code path bypasses the
    // pre-openDB check (see the SQLITE_CONSTRAINT branch below).
    let insertSQL = """
        INSERT INTO cables (vid, pid, cable_vdo, brand, speed, power, type, xid, issue_url)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("warn: prepare failed for cable insert\n", stderr)
        return 0
    }

    runSQL("BEGIN TRANSACTION")
    var count = 0

    for row in parsed {
        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(row.vid))
        sqlite3_bind_int(stmt, 2, Int32(row.pid))
        sqlite3_bind_int(stmt, 3, Int32(bitPattern: UInt32(row.cableVDO)))
        sqlite3_bind_text(stmt, 4, (row.brand as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (row.speed as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (row.power as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (row.type as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (row.xid as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, (row.issueURL as NSString).utf8String, -1, nil)

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_CONSTRAINT {
            // Should be unreachable: findExactDuplicateRow already checked
            // this. If it fires anyway, something upstream disagrees with
            // that check, which is itself a bug worth failing loudly for.
            fputs("error: sqlite rejected cable VID=\(row.vid) PID=\(row.pid) '\(row.brand)' as a duplicate of the UNIQUE(vid, pid, cable_vdo, brand) index, but findExactDuplicateRow did not catch it. This is a bug in the duplicate check.\n", stderr)
            failBuild(12)
        } else if rc != SQLITE_DONE {
            fputs("warn: failed to insert cable VID=\(row.vid) PID=\(row.pid): \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        } else {
            count += 1
        }
    }

    runSQL("COMMIT")
    sqlite3_finalize(stmt)

    // Row-count assertion: every parsed row must have inserted. totalDataRows
    // is every row the parser looked at, including the ones it skipped
    // ((needs review), all-zero), so this also proves the skip counts are
    // accurate.
    let expected = totalDataRows - skippedNeedsReview - skippedAllZero
    if count != expected {
        fputs("""
            error: cable row-count mismatch: inserted \(count) rows but expected \(expected) \
            (totalDataRows=\(totalDataRows) - skippedNeedsReview=\(skippedNeedsReview) - skippedAllZero=\(skippedAllZero)). \
            A row was silently dropped somewhere between parsing and insert.

            """, stderr)
        failBuild(13)
    }

    return count
}

// MARK: - JSON export for website search

func exportCablesJSON() -> Int {
    let query = """
        SELECT c.vid, c.pid, c.cable_vdo, c.brand, c.speed, c.power,
               c.type, c.xid, c.issue_url, COALESCE(v.name, '') as vendor_name,
               COALESCE(v.source, '') as vendor_source
        FROM cables c
        LEFT JOIN vendors v ON c.vid = v.vid
        ORDER BY c.vid, c.pid
        """
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
        fputs("warn: prepare failed for JSON export\n", stderr)
        return 0
    }
    defer { sqlite3_finalize(stmt) }

    var entries: [[String: Any]] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let vid = Int(sqlite3_column_int(stmt, 0))
        let pid = Int(sqlite3_column_int(stmt, 1))
        let cableVDO = UInt32(bitPattern: sqlite3_column_int(stmt, 2))
        let brand = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
        let speed = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
        let power = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
        let type = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
        let xid = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "none"
        let issueURL = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? ""
        let vendorName = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? ""
        let vendorSource = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? ""

        // 0x0000 and 0xFFFF are USB-PD "no vendor identity" sentinels,
        // not vendors. Both happen to sit in the USB-IF list (as "USB
        // Implementers Forum" and a stale "Taiwan OEM" respectively), so
        // a plain vendors-table join badges the most identity-less
        // cables in the catalogue as coming from a registered vendor.
        // VendorDB.name(for:) / .isRegistered already short-circuit both
        // in the app; mirror that here so the website agrees with it.
        let isSentinelVID = (vid == 0 || vid == 0xFFFF)

        let vendor: String
        if vid == 0 {
            vendor = "(zeroed)"
        } else if vid == 0xFFFF {
            vendor = "No vendor ID assigned (USB-PD spec sentinel)"
        } else if vendorName.isEmpty {
            vendor = "Unregistered"
        } else {
            vendor = vendorName
        }

        let vidHex = String(format: "0x%04X", vid)
        let pidHex = String(format: "0x%04X", pid)
        let vdoHex = cableVDO == 0 ? "" : String(format: "0x%08X", cableVDO)

        let issueNum: String
        if let hashIdx = issueURL.lastIndex(of: "/") {
            issueNum = "#" + issueURL[issueURL.index(after: hashIdx)...]
        } else {
            issueNum = ""
        }

        let entry: [String: Any] = [
            "brand": brand,
            "vid": vidHex,
            "pid": pidHex,
            "cableVDO": vdoHex,
            "vendor": vendor,
            "registered": !isSentinelVID && vendorSource == "usbif",
            "xid": xid,
            "speed": speed,
            "power": power,
            "type": type,
            "issueURL": issueURL,
            "issueNum": issueNum,
        ]
        entries.append(entry)
    }

    guard let data = try? JSONSerialization.data(
        withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
    ) else {
        fputs("warn: JSON serialization failed\n", stderr)
        return 0
    }

    let url = URL(fileURLWithPath: cablesJSON)
    do {
        try data.write(to: url)
    } catch {
        fputs("warn: could not write \(cablesJSON): \(error)\n", stderr)
        return 0
    }

    return entries.count
}

// MARK: - USB-IF certification import

// Two public, unauthenticated USB-IF endpoints (both undocumented Drupal
// routes, hence compiled offline, never called at runtime):
//   - bulk list: the whole certified-products catalogue in one GET. Carries
//     the cert date but NO vendor_id.
//   - per-XID:   one XID's listings, WITH vendor_id but no cert date.
// We union them by XID to get both. See research/usb-if-registry.md.
let usbifBulkURL = URL(string: "https://www.usb.org/vtm-products/v1/all")!
func usbifPerXIDURL(_ xid: Int) -> URL {
    // The XID goes in the path in DECIMAL, not hex.
    URL(string: "https://cms.usb.org/usb_device/get_status_by_xid/\(xid)")!
}

/// Synchronous HTTP GET with a real timeout. `Data(contentsOf:)` has no
/// timeout control, which matters across ~1,000 sequential per-XID calls.
func httpGet(_ url: URL, timeout: TimeInterval = 30) -> Data? {
    let sem = DispatchSemaphore(value: 0)
    // The completion handler runs on URLSession's delegate queue while the
    // caller waits on this thread, so all access to `result` is guarded by a
    // lock. On the (near-never) backstop timeout we cancel the task and read
    // whatever is there under the same lock, so there is no unsynchronised
    // read/write race.
    let lock = NSLock()
    var result: Data?
    var done = false
    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    let task = URLSession.shared.dataTask(with: request) { data, response, _ in
        lock.lock()
        if !done {
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            done = true
        }
        lock.unlock()
        sem.signal()
    }
    task.resume()
    if sem.wait(timeout: .now() + timeout + 5) == .timedOut {
        task.cancel()
    }
    lock.lock()
    let out = result
    lock.unlock()
    return out
}

/// Minimal HTML-entity unescape. The bulk list HTML-encodes a few
/// characters in text fields (company names with `&amp;`, categories with
/// `&gt;`). Per-XID text is clean JSON, so this only touches bulk fallbacks.
func htmlUnescape(_ s: String) -> String {
    s.replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&#039;", with: "'")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

struct BulkListing {
    let company: String
    let model: String
    let status: String
    let certDate: String
}

/// Best certification date for one listing.
///
/// Matched conservatively against the bulk rows for this XID: prefer an exact
/// company+model match, otherwise fall back to a company-only match ONLY when
/// exactly one bulk row carries that company. If several models share the
/// company we cannot tell which date belongs to this listing, so return empty
/// rather than guess (an XID with several unrelated companies must never
/// borrow another's date).
///
/// When the bulk catalogue has NO rows for this XID at all, fall back to the
/// date seeded in data/cert-xids.tsv. That is the whole point of the seed: the
/// per-XID endpoint answers for IDs the bulk feed has dropped, but it returns
/// no date, so without this the restored listings come back dateless.
///
/// The seed is a fallback, never an override. An XID the bulk catalogue does
/// list takes its date from there, even when that resolves to "" because the
/// company/model match was too weak to trust, and an XID outside the seed file
/// gets nothing from it.
///
/// Pure (no globals, no I/O) so `--test-parser` can exercise it directly.
func certDate(
    forXID xid: Int,
    company: String,
    model: String,
    bulk: [Int: [BulkListing]],
    seededDates: [Int: String]
) -> String {
    guard let rows = bulk[xid], !rows.isEmpty else {
        return seededDates[xid] ?? ""
    }
    if let exact = rows.first(where: {
        $0.company.caseInsensitiveCompare(company) == .orderedSame
            && $0.model.caseInsensitiveCompare(model) == .orderedSame
    }) { return exact.certDate }
    let sameCompany = rows.filter {
        $0.company.caseInsensitiveCompare(company) == .orderedSame
    }
    return sameCompany.count == 1 ? sameCompany[0].certDate : ""
}

/// Self-tests for the seeded-date fallback in `certDate(forXID:...)`.
///
/// The rule under test is narrow and easy to get wrong in either direction:
/// the seed fills a date in ONLY when the bulk catalogue has nothing at all
/// for that XID, it never overrides a bulk date, and it never reaches an XID
/// outside data/cert-xids.tsv.
func runCertDateFallbackSelfTests() -> (failures: Int, output: String) {
    // 0x1C46 and 0x1C53 are seeded and absent from bulk (the real case).
    // 0x219C and 0x2600 are seeded AND in bulk, purely to prove the seed
    // never overrides the catalogue.
    let seeded: [Int: String] = [
        0x1C46: "2017-11-28T00:00:00",   // StarTech, dropped from the bulk feed
        0x1C53: "",                      // seeded but genuinely dateless
        0x219C: "1999-09-09T00:00:00",   // deliberately wrong; bulk must win
        0x2600: "1999-09-09T00:00:00",   // deliberately wrong; bulk must win
    ]
    let bulk: [Int: [BulkListing]] = [
        0x219C: [BulkListing(company: "Anker", model: "A8756",
                             status: "Pass", certDate: "2022-06-01T00:00:00")],
        0x2600: [
            BulkListing(company: "Foo Ltd", model: "A", status: "Pass",
                        certDate: "2020-01-01T00:00:00"),
            BulkListing(company: "Bar Ltd", model: "B", status: "Pass",
                        certDate: "2021-01-01T00:00:00"),
        ],
    ]

    let cases: [(label: String, xid: Int, company: String, model: String, expected: String)] = [
        ("a seeded XID the bulk feed has dropped takes the seeded date",
         0x1C46, "StarTech.com Ltd.", "USB31CC1M", "2017-11-28T00:00:00"),
        ("a seeded XID with an empty seeded date stays empty",
         0x1C53, "StarTech.com Ltd.", "50C-40G-USB4-CABLE", ""),
        ("the seed never overrides a date the bulk catalogue does supply",
         0x219C, "Anker", "A8756", "2022-06-01T00:00:00"),
        ("bulk rows present but no company match: still empty, seed does not fill in",
         0x2600, "Baz Ltd", "C", ""),
        ("an XID outside the seed file gets nothing from it",
         0x4242, "Nobody Ltd", "X", ""),
    ]

    var failures = 0
    var output = "cert-date seed fallback:\n"
    for testCase in cases {
        let got = certDate(forXID: testCase.xid, company: testCase.company,
                           model: testCase.model, bulk: bulk, seededDates: seeded)
        if got == testCase.expected {
            output += "  ok: \(testCase.label)\n"
        } else {
            failures += 1
            output += "  FAIL: \(testCase.label)\n"
            output += "    - expected '\(testCase.expected)', got '\(got)'\n"
        }
    }
    output += "\n\(failures == 0 ? "all passed" : "\(failures) FAILED")\n"
    return (failures, output)
}

/// One certification listing as far as its date is concerned: the cert ID,
/// company and model that identify it, and the date it carries.
struct CertListing {
    let xid: Int
    let company: String
    let model: String
    let certDate: String
}

/// Result of `carryForwardCertDates`: one resolved date per new listing (same
/// order), plus which listings took a carried date and which could not
/// because the previous db had more than one date for them.
struct CertDateCarryResult {
    let dates: [String]
    let carried: [Int]
    let ambiguous: [Int]
}

/// Keep certification dates the USB-IF feed has dropped.
///
/// The bulk catalogue is the only source of dates, and it drops rows between
/// builds, so a listing USB-IF still shows can come back dateless. That is
/// flaky data, not a real change: when the new build has an EMPTY date for a
/// listing the previous db had dated, the previous date is carried forward.
///
/// A listing is the same one only when cert ID, company and model all match
/// (company and model case-insensitively, like `certDate(forXID:...)`). One
/// cert ID can carry several companies, so a date never crosses to a
/// different company or model. A date the new build does have is never
/// replaced. USB-IF does list some models twice under one cert ID, so a
/// date is carried only when every previous row for the listing had that
/// same date and the new build has no more rows for it than the previous
/// db. Otherwise (two dates, a dated row beside a dateless one, an extra
/// row) there is no telling which row the date belongs to, so nothing is
/// carried and the listing is reported as ambiguous.
///
/// Pure (no globals, no I/O) so `--test-parser` can exercise it directly.
func carryForwardCertDates(new: [CertListing], previous: [CertListing]) -> CertDateCarryResult {
    func key(_ l: CertListing) -> String {
        let fold: (String) -> String = { $0.folding(options: .caseInsensitive, locale: nil) }
        return "\(l.xid)\u{0}\(fold(l.company))\u{0}\(fold(l.model))"
    }
    var previousRows: [String: Int] = [:]
    var previousDateless: Set<String> = []
    var previousDates: [String: Set<String>] = [:]
    for p in previous {
        let k = key(p)
        previousRows[k, default: 0] += 1
        if p.certDate.isEmpty { previousDateless.insert(k) }
        else { previousDates[k, default: []].insert(p.certDate) }
    }
    var newRows: [String: Int] = [:]
    for n in new { newRows[key(n), default: 0] += 1 }

    var dates: [String] = []
    var carried: [Int] = []
    var ambiguous: [Int] = []
    for (i, listing) in new.enumerated() {
        let k = key(listing)
        guard listing.certDate.isEmpty, let candidates = previousDates[k] else {
            dates.append(listing.certDate)
            continue
        }
        // Carry only when every previous row for this listing had the same
        // date and the new build has no more rows for it than before.
        // Anything else (two dates, a dated row beside a dateless twin, an
        // extra row that may be a new listing) leaves no way to tell which
        // row the date belongs to.
        if candidates.count == 1, let only = candidates.first,
           !previousDateless.contains(k),
           newRows[k, default: 0] <= previousRows[k, default: 0] {
            dates.append(only)
            carried.append(i)
        } else {
            dates.append("")
            ambiguous.append(i)
        }
    }
    return CertDateCarryResult(dates: dates, carried: carried, ambiguous: ambiguous)
}

/// Self-tests for `carryForwardCertDates`.
func runCertDateCarrySelfTests() -> (failures: Int, output: String) {
    // 0xEE6 is the real case: Astron Connectivity lost its date while
    // Johnson Component, on the same cert ID, kept its own.
    let previous: [CertListing] = [
        CertListing(xid: 0xEE6, company: "Johnson Component & Equipments Co., Ltd.",
                    model: "USB3CC-6830-1m", certDate: "2016-08-17T00:00:00"),
        CertListing(xid: 0xEE6, company: "Astron Connectivity",
                    model: "T1M1M10XX6-R", certDate: "2020-05-06T00:00:00"),
        CertListing(xid: 0x100, company: "Foo Ltd", model: "A1",
                    certDate: "2021-01-01T00:00:00"),
        CertListing(xid: 0x101, company: "Foo Ltd", model: "B1",
                    certDate: "2021-02-02T00:00:00"),
        CertListing(xid: 0x102, company: "Bar Ltd", model: "C1",
                    certDate: "2021-03-03T00:00:00"),
        // Listed twice with different dates: ambiguous.
        CertListing(xid: 0x103, company: "Twice Ltd", model: "D1",
                    certDate: "2016-12-22T00:00:00"),
        CertListing(xid: 0x103, company: "Twice Ltd", model: "D1",
                    certDate: "2016-02-09T00:00:00"),
        // Listed twice with the same date: not ambiguous.
        CertListing(xid: 0x104, company: "Same Ltd", model: "E1",
                    certDate: "2022-07-12T00:00:00"),
        CertListing(xid: 0x104, company: "Same Ltd", model: "E1",
                    certDate: "2022-07-12T00:00:00"),
        // Previously dateless: nothing to carry.
        CertListing(xid: 0x105, company: "Blank Ltd", model: "F1", certDate: ""),
        // Listed twice, one dated and one dateless: which row the date
        // belongs to is unknowable, so it is ambiguous. This is what a
        // twice-listed model looks like one build after the feed dropped
        // one of its dates.
        CertListing(xid: 0x107, company: "Half Ltd", model: "H1",
                    certDate: "2016-12-22T00:00:00"),
        CertListing(xid: 0x107, company: "Half Ltd", model: "H1", certDate: ""),
        // Same, where the dateless twin is still dateless and the dated one
        // still dated: the twin must not borrow its sibling's date.
        CertListing(xid: 0x108, company: "Twin Ltd", model: "T1",
                    certDate: "2019-01-01T00:00:00"),
        CertListing(xid: 0x108, company: "Twin Ltd", model: "T1", certDate: ""),
        // Listed once before, twice now: the new row could be a new listing.
        CertListing(xid: 0x109, company: "Grow Ltd", model: "G2",
                    certDate: "2020-02-02T00:00:00"),
    ]
    let new: [CertListing] = [
        CertListing(xid: 0xEE6, company: "Johnson Component & Equipments Co., Ltd.",
                    model: "USB3CC-6830-1m", certDate: ""),
        CertListing(xid: 0xEE6, company: "Astron Connectivity",
                    model: "T1M1M10XX6-R", certDate: ""),
        CertListing(xid: 0x100, company: "Foo Ltd", model: "A1",
                    certDate: "2024-04-04T00:00:00"),
        CertListing(xid: 0x101, company: "FOO LTD", model: "b1", certDate: ""),
        CertListing(xid: 0x102, company: "Bar Ltd", model: "C2", certDate: ""),
        CertListing(xid: 0x102, company: "Other Ltd", model: "C1", certDate: ""),
        CertListing(xid: 0x103, company: "Twice Ltd", model: "D1", certDate: ""),
        CertListing(xid: 0x104, company: "Same Ltd", model: "E1", certDate: ""),
        CertListing(xid: 0x105, company: "Blank Ltd", model: "F1", certDate: ""),
        CertListing(xid: 0x106, company: "New Ltd", model: "G1", certDate: ""),
        CertListing(xid: 0x101, company: "Foo Ltd", model: "A1", certDate: ""),
        CertListing(xid: 0x107, company: "Half Ltd", model: "H1", certDate: ""),
        CertListing(xid: 0x108, company: "Twin Ltd", model: "T1",
                    certDate: "2019-01-01T00:00:00"),
        CertListing(xid: 0x108, company: "Twin Ltd", model: "T1", certDate: ""),
        CertListing(xid: 0x109, company: "Grow Ltd", model: "G2", certDate: ""),
        CertListing(xid: 0x109, company: "Grow Ltd", model: "G2", certDate: ""),
    ]
    let cases: [(label: String, index: Int, expected: String)] = [
        ("each listing on a shared cert ID gets back its own date (Johnson)",
         0, "2016-08-17T00:00:00"),
        ("each listing on a shared cert ID gets back its own date (Astron)",
         1, "2020-05-06T00:00:00"),
        ("a date the feed does give is never replaced", 2, "2024-04-04T00:00:00"),
        ("company and model match case-insensitively", 3, "2021-02-02T00:00:00"),
        ("a different model under the same company gets nothing", 4, ""),
        ("a different company with the same model gets nothing", 5, ""),
        ("two different previous dates for one listing: nothing carried", 6, ""),
        ("the same previous date listed twice is still carried", 7, "2022-07-12T00:00:00"),
        ("a listing that was dateless before stays dateless", 8, ""),
        ("a listing the previous db did not have gets nothing", 9, ""),
        ("a date never crosses to a different cert ID", 10, ""),
        ("previously listed twice, one dated and one dateless: nothing carried",
         11, ""),
        ("a dated twin keeps its date", 12, "2019-01-01T00:00:00"),
        ("a dateless twin never borrows its dated sibling's date", 13, ""),
        ("listed once before, twice now: first row not carried", 14, ""),
        ("listed once before, twice now: second row not carried", 15, ""),
    ]

    let result = carryForwardCertDates(new: new, previous: previous)
    var failures = 0
    var output = "cert-date carry-forward:\n"
    func record(_ ok: Bool, _ label: String, _ detail: String) {
        if ok {
            output += "  ok: \(label)\n"
        } else {
            failures += 1
            output += "  FAIL: \(label)\n    - \(detail)\n"
        }
    }
    for testCase in cases {
        let got = testCase.index < result.dates.count ? result.dates[testCase.index] : "<missing>"
        record(got == testCase.expected, testCase.label,
               "expected '\(testCase.expected)', got '\(got)'")
    }
    record(result.dates.count == new.count, "one resolved date per new listing",
           "expected \(new.count), got \(result.dates.count)")
    record(result.carried == [0, 1, 3, 7], "the carried listings are reported",
           "expected [0, 1, 3, 7], got \(result.carried)")
    record(result.ambiguous == [6, 11, 13, 14, 15], "the ambiguous listings are reported",
           "expected [6, 11, 13, 14, 15], got \(result.ambiguous)")
    output += "\n\(failures == 0 ? "all passed" : "\(failures) FAILED")\n"
    return (failures, output)
}

/// Fetch the bulk catalogue and index the XID-bearing rows by XID.
/// Returns nil on fetch/parse failure so the caller can skip cert import
/// without aborting the whole DB build.
func fetchBulkListings() -> [Int: [BulkListing]]? {
    guard let data = httpGet(usbifBulkURL, timeout: 120) else {
        fputs("warn: usb-if bulk list fetch failed\n", stderr)
        return nil
    }
    // The response is a JSON object keyed by stringified index ("0","1",...),
    // not an array.
    guard let obj = try? JSONSerialization.jsonObject(with: data),
          let dict = obj as? [String: Any] else {
        fputs("warn: usb-if bulk list did not parse as a JSON object\n", stderr)
        return nil
    }
    var byXID: [Int: [BulkListing]] = [:]
    for value in dict.values {
        guard let row = value as? [String: Any],
              let xidStr = (row["field_usb_xid"] as? String)?
                .trimmingCharacters(in: .whitespaces),
              let xid = Int(xidStr), xid != 0 else { continue }
        let listing = BulkListing(
            company: htmlUnescape((row["device_company_view_field"] as? String) ?? ""),
            model: htmlUnescape((row["name"] as? String)
                ?? (row["field_usb_model_part_number"] as? String) ?? ""),
            status: htmlUnescape((row["field_device_status"] as? String) ?? ""),
            certDate: (row["global_pass_date"] as? String) ?? ""
        )
        byXID[xid, default: []].append(listing)
    }
    // Guard against a 200 response that is an error object, an empty object,
    // or a changed schema: any of those parse as a dictionary but yield few or
    // no XID rows. Real data is ~1,086 distinct XIDs. Treat an implausibly
    // small result as a failed fetch so cert import is skipped loudly (0
    // listings in the summary) rather than silently compiling a truncated
    // table that could get committed.
    if byXID.count < 500 {
        fputs("warn: usb-if bulk list returned only \(byXID.count) XID rows; treating as a failed or changed response and skipping cert import\n", stderr)
        return nil
    }
    return byXID
}

/// Whether a parsed per-XID response can be trusted. Usable only if it is a
/// JSON array and EVERY row is an object with a non-empty (trimmed) string
/// `company`. An empty array is usable: it is the endpoint's "not
/// registered" answer.
///
/// All-or-nothing on purpose. A row without a company is what a schema change
/// at USB-IF looks like (e.g. `company` renamed), and the importer would skip
/// such rows as malformed. Accepting the response anyway would drop those
/// listings with the build still exiting 0, and caching it would repeat the
/// loss on every later build. Measured 2026-09-23: none of the 931 non-empty
/// cached responses has a row without a company, so this rejects nothing real.
///
/// Pure (no globals, no I/O) so `--test-parser` can exercise it directly.
func isUsablePerXIDResponse(_ json: Any) -> Bool {
    guard let rows = json as? [Any] else { return false }
    for row in rows {
        guard let object = row as? [String: Any],
              let company = object["company"] as? String,
              !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
    }
    return true
}

/// Self-tests for `isUsablePerXIDResponse`. The cases that matter most are
/// the mixed ones: a single bad row anywhere must make the whole response
/// unusable, not just the first row.
func runPerXIDResponseSelfTests() -> (failures: Int, output: String) {
    let good: [String: Any] = ["company": "StarTech.com Ltd.", "model_number": "USB31CC1M"]
    let good2: [String: Any] = ["company": "Johnson Component", "model_number": "X"]
    let cases: [(label: String, json: Any, expected: Bool)] = [
        ("an empty array is a usable 'not registered' answer", [Any](), true),
        ("one row with a company is usable", [good], true),
        ("several rows with companies are usable", [good, good2, good], true),
        ("a row with no company key is unusable",
         [["company_name": "StarTech.com Ltd."] as [String: Any]], false),
        ("a row with an empty company is unusable",
         [["company": ""] as [String: Any]], false),
        ("a row with a whitespace-only company is unusable",
         [["company": "  \t "] as [String: Any]], false),
        ("a row with a non-string company is unusable",
         [["company": 42] as [String: Any]], false),
        ("a good row then a bad row is unusable (every row is checked)",
         [good, ["company": ""] as [String: Any]], false),
        ("a bad row then a good row is unusable",
         [["model_number": "X"] as [String: Any], good], false),
        ("a JSON object is not an array, so unusable",
         ["company": "StarTech.com Ltd."] as [String: Any], false),
        ("a string is not an array, so unusable", "error", false),
        ("an array holding a non-object is unusable", [good, "oops"] as [Any], false),
    ]

    var failures = 0
    var output = "per-XID response validation:\n"
    for testCase in cases {
        let got = isUsablePerXIDResponse(testCase.json)
        if got == testCase.expected {
            output += "  ok: \(testCase.label)\n"
        } else {
            failures += 1
            output += "  FAIL: \(testCase.label)\n"
            output += "    - expected \(testCase.expected), got \(got)\n"
        }
    }
    output += "\n\(failures == 0 ? "all passed" : "\(failures) FAILED")\n"
    return (failures, output)
}

/// Fetch one XID's listings from the per-XID endpoint, caching the raw
/// response to disk. An empty array is a valid "not registered" result and
/// is cached too, so it is not re-fetched. Returns the parsed array (possibly
/// empty), or nil when the fetch failed or the response failed
/// `isUsablePerXIDResponse`.
///
/// Validation runs on the cache too. A cached response that fails it (written
/// by an older build that cached before validating, or damaged on disk) is
/// treated as a cache miss and refetched, so a poisoned entry cannot keep
/// losing listings. A fresh response that fails it is never cached.
func fetchPerXIDListings(_ xid: Int) -> [[String: Any]]? {
    if forcedCertFetchFailures.contains(xid) { return nil }
    let cachePath = "\(certCacheDir)/\(xid).json"
    let fm = FileManager.default
    if !refreshCerts, let cached = fm.contents(atPath: cachePath) {
        if let json = try? JSONSerialization.jsonObject(with: cached),
           isUsablePerXIDResponse(json),
           let arr = json as? [[String: Any]] {
            return arr
        }
        fputs("warn: cached per-XID response for \(String(format: "0x%X", xid)) " +
              "is malformed; ignoring the cache and refetching\n", stderr)
    }
    // Be polite to USB-IF's undocumented per-XID endpoint: throttle to ~2
    // requests a second, but only on an actual network fetch (a warm cache
    // does no network and does not sleep). Matches the rate the research doc
    // describes for the one-time full fetch.
    Thread.sleep(forTimeInterval: 0.5)
    guard let data = httpGet(usbifPerXIDURL(xid)) else { return nil }
    // Validate before caching. A non-array response is a transient error,
    // not a "not registered" answer, and an array with a company-less row
    // is a malformed or schema-changed one. Either is a failed fetch, and
    // neither is written to the cache.
    guard let json = try? JSONSerialization.jsonObject(with: data),
          isUsablePerXIDResponse(json),
          let arr = json as? [[String: Any]] else {
        fputs("warn: per-XID response for \(String(format: "0x%X", xid)) " +
              "is malformed; treating it as a failed fetch, not caching it\n", stderr)
        return nil
    }
    try? data.write(to: URL(fileURLWithPath: cachePath))
    return arr
}

/// Read the distinct XIDs already recorded on curated cables (hex strings
/// like "0x5F5" in the cables table). Seeding the universe with these catches
/// registered XIDs the bulk catalogue omits (verified: the bulk list misses
/// some, e.g. the Anker sample 0x219C).
func curatedXIDs() -> Set<Int> {
    var out: Set<Int> = []
    var stmt: OpaquePointer?
    let sql = "SELECT DISTINCT xid FROM cables WHERE xid NOT IN ('none', '')"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
    defer { sqlite3_finalize(stmt) }
    while sqlite3_step(stmt) == SQLITE_ROW {
        guard let c = sqlite3_column_text(stmt, 0) else { continue }
        var s = String(cString: c)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
        if let v = Int(s, radix: 16) { out.insert(v) }
    }
    return out
}

/// Read the distinct non-zero Cert Stat XIDs that real cables reported in the
/// probe corpus (`research/customer-probes/*/01_walk_pd_tree.json`).
///
/// Same motivation as `curatedXIDs()`, one step wider: the bulk catalogue is
/// NOT a superset of the per-XID endpoint. Measured on 2026-07-24, 41 distinct
/// corpus XIDs resolved to nothing in the compiled table, and 11 of them
/// returned real listings from the per-XID endpoint (Anker x4, Belkin,
/// Plugable, ZAGG, Richtek, Hynetek, Sunlike, SIP Simya). Those cables are
/// certified and were showing no certification line purely because the build
/// never asked about their XID.
///
/// Fails soft on purpose. `research/` is excluded from the public mirror while
/// this script is not, so a rebuild from the public repo finds no corpus
/// directory and simply gets the old (bulk + curated) universe.
func corpusXIDs() -> Set<Int> {
    let corpusRoot = "\(repoRoot)/research/customer-probes"
    guard let folders = try? FileManager.default.contentsOfDirectory(
        atPath: corpusRoot
    ) else {
        print("USB-IF certs: no probe corpus at research/customer-probes, " +
              "skipping corpus XID seeding")
        return []
    }

    var out: Set<Int> = []
    for folder in folders {
        let probe = "\(corpusRoot)/\(folder)/01_walk_pd_tree.json"
        guard let data = FileManager.default.contents(atPath: probe),
              let obj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let text = obj["output"] as? String else { continue }

        // Probe 01 prints one "=== ClassName[n] ===" block per registry node.
        // Keep the blocks whose own Description ends in "/SOP'" (the cable
        // plug's e-marker) and read VDO[1], the Cert Stat XID.
        for block in text.components(separatedBy: "=== ") {
            // Both cable-plug addresses, matching what the app itself reads:
            // `USBPDSOP.certStatVDO` accepts .sopPrime and .sopDoublePrime.
            // No SOP'' block exists in the corpus today, so this changes
            // nothing now; it stops the seeder drifting from the app the day
            // a dual-e-marker cable turns up.
            guard let desc = blockDescription(block),
                  desc.hasSuffix("/SOP'") || desc.hasSuffix("/SOP''"),
                  let xid = blockCertStatXID(block), xid != 0 else { continue }
            out.insert(xid)
        }
    }
    return out
}

/// The first `Description = "..."` value on its own line within a probe block.
/// Requires the closing quote rather than blindly dropping the last character,
/// so a truncated line can't have its final character eaten and turn into a
/// value that matches something (`.../SOP'X` becoming `.../SOP'`).
func blockDescription(_ block: String) -> String? {
    let prefix = "Description = \""
    for line in block.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(prefix), t.hasSuffix("\""), t.count > prefix.count else { continue }
        return String(t.dropFirst(prefix.count).dropLast())
    }
    return nil
}

/// VDO[1] as a little-endian UInt32, mirroring `PDVDO.vdoFromData`'s byte
/// order (the app decodes the same bytes the same way).
///
/// Every token must be valid hex. Dropping unparseable tokens instead would
/// let a corrupt line still yield four bytes from the survivors and decode to
/// a plausible but wrong XID, which we would then fetch and store.
func blockCertStatXID(_ block: String) -> Int? {
    guard let range = block.range(of: "[1] <data 4 bytes: ") else { return nil }
    let after = block[range.upperBound...]
    guard let end = after.firstIndex(of: ">") else { return nil }
    let tokens = after[..<end].split(separator: " ")
    guard tokens.count == 4 else { return nil }
    var value = 0
    for (i, token) in tokens.enumerated() {
        guard let byte = UInt8(token, radix: 16) else { return nil }
        value |= Int(byte) << (8 * i)
    }
    return value
}

func importCertifications() -> (xids: Int, listings: Int, failedXIDs: [Int]) {
    try? FileManager.default.createDirectory(
        atPath: certCacheDir, withIntermediateDirectories: true)

    guard let bulk = fetchBulkListings() else {
        fputs("warn: skipping certification import (bulk fetch failed)\n", stderr)
        return (0, 0, [])
    }

    // Universe = every XID the catalogue lists, plus every XID our curated
    // cables carry, plus every XID real hardware reported in the probe corpus.
    // Sorted so progress logging and cache order are stable.
    let curated = curatedXIDs()
    let corpus = corpusXIDs()
    let seeded = manualCertXIDs()
    let universe = Set(bulk.keys).union(curated).union(corpus).union(seeded.keys).sorted()
    print("USB-IF certs: \(universe.count) XIDs to resolve " +
          "(\(bulk.count) from bulk list, \(curated.count) from curated cables, " +
          "\(corpus.count) from the probe corpus, \(seeded.count) from data/cert-xids.tsv)")

    let insertSQL = """
        INSERT INTO cable_certs (xid, vendor_id, company, model, status, cert_date, source)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("warn: prepare failed for cable_certs insert\n", stderr)
        return (0, 0, [])
    }
    defer { sqlite3_finalize(stmt) }

    // SQLite keeps a pointer to bound text until the statement is stepped;
    // SQLITE_TRANSIENT tells it to copy immediately so our Swift strings can
    // go out of scope safely.
    let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    func bindText(_ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }

    var xidsCovered = 0
    var listingsInserted = 0
    var fetchFailures = 0
    var failedXIDs: [Int] = []

    for (i, xid) in universe.enumerated() {
        if i > 0 && i % 100 == 0 {
            print("  ...\(i)/\(universe.count) XIDs resolved")
        }
        let perXID = fetchPerXIDListings(xid)
        if perXID == nil {
            fetchFailures += 1
            failedXIDs.append(xid)
        }

        // Authoritative first: per-XID rows carry vendor_id. fetchPerXIDListings
        // only returns responses where every row has a non-empty company (an
        // empty company would render as a bogus "USB-IF certified.
        // Manufacturer:" line); anything else comes back nil and is recorded
        // in failedXIDs above. The company guard below is kept as defence in
        // depth. An empty (not registered) response falls THROUGH to the bulk
        // data via the single if/else chain below.
        var insertedFromPerXID = false
        if let listings = perXID {
            for row in listings {
                let company = ((row["company"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespaces)
                guard !company.isEmpty else { continue }
                let model = ((row["model_number"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespaces)
                let status = ((row["status"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespaces)
                let vid = (row["vendor_id"] as? String).flatMap { Int($0) }
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, sqlite3_int64(xid))
                // Int32(exactly:) so a malformed out-of-range vendor_id binds
                // NULL (vendor unknown) instead of trapping the whole build.
                if let vid, let v32 = Int32(exactly: vid) { sqlite3_bind_int(stmt, 2, v32) }
                else { sqlite3_bind_null(stmt, 2) }
                bindText(3, company)
                bindText(4, model)
                bindText(5, status)
                bindText(6, certDate(forXID: xid, company: company, model: model,
                                     bulk: bulk, seededDates: seeded))
                bindText(7, "per_xid")
                if sqlite3_step(stmt) == SQLITE_DONE {
                    listingsInserted += 1
                    insertedFromPerXID = true
                }
            }
        }

        if insertedFromPerXID {
            xidsCovered += 1
        } else if let bulkRows = bulk[xid] {
            // Fallback: per-XID gave nothing usable, or the catalogue lists
            // this XID only in the bulk source. No vendor_id here. Same
            // non-empty-company guard so no bogus row reaches the db.
            var any = false
            for b in bulkRows {
                guard !b.company.isEmpty else { continue }
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, sqlite3_int64(xid))
                sqlite3_bind_null(stmt, 2)
                bindText(3, b.company)
                bindText(4, b.model)
                bindText(5, b.status)
                bindText(6, b.certDate)
                bindText(7, "bulk")
                if sqlite3_step(stmt) == SQLITE_DONE { listingsInserted += 1; any = true }
            }
            if any { xidsCovered += 1 }
        }
        // else: a curated XID that resolves nowhere -> genuinely unregistered.
    }

    if fetchFailures > 0 {
        fputs("warn: \(fetchFailures) per-XID fetch(es) failed\n", stderr)
    }
    return (xidsCovered, listingsInserted, failedXIDs)
}

/// Certification listings of the previous db, the carry-forward source.
///
/// That is the COMMITTED db (`git show HEAD:...`), not the file on disk:
/// openDB() deletes the file, so after a failed build the on-disk copy can
/// be empty or partial, and a re-run reading it would silently lose every
/// date it should carry. WC_PREVIOUS_CERT_DB names another db file instead
/// (e.g. an older commit's, to restore dates already lost). Without git the
/// on-disk file is used, with a warning.
func loadPreviousCertListings() -> [CertListing] {
    let fm = FileManager.default
    var path = dbOutput
    var tempPath: String?
    if let override = ProcessInfo.processInfo.environment["WC_PREVIOUS_CERT_DB"],
       !override.isEmpty {
        path = override
        print("cert-date carry-forward: previous db from WC_PREVIOUS_CERT_DB=\(override)")
    } else {
        let temp = NSTemporaryDirectory() + "whatcable-previous-\(ProcessInfo.processInfo.processIdentifier).db"
        fm.createFile(atPath: temp, contents: nil)
        let out = FileHandle(forWritingAtPath: temp)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoRoot, "show",
                             "HEAD:Sources/WhatCableCore/Resources/whatcable.db"]
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        var ok = false
        if (try? process.run()) != nil {
            process.waitUntilExit()
            ok = process.terminationStatus == 0
        }
        try? out?.close()
        let size = (try? fm.attributesOfItem(atPath: temp)[.size] as? Int) ?? 0
        if ok, size > 0 {
            path = temp
            tempPath = temp
            print("cert-date carry-forward: previous db from git HEAD")
        } else {
            try? fm.removeItem(atPath: temp)
            fputs("warn: cert-date carry-forward: could not read the committed db from git; " +
                  "using the file on disk, which a failed earlier build may have emptied\n", stderr)
        }
    }
    defer { if let tempPath { try? fm.removeItem(atPath: tempPath) } }

    guard fm.fileExists(atPath: path) else {
        fputs("warn: cert-date carry-forward: no previous db at \(path), nothing to carry\n", stderr)
        return []
    }
    var prev: OpaquePointer?
    defer { sqlite3_close(prev) }
    guard sqlite3_open_v2(path, &prev, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        fputs("warn: cert-date carry-forward: could not open the previous db, nothing to carry\n", stderr)
        return []
    }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(prev, "SELECT xid, company, model, cert_date FROM cable_certs",
                             -1, &stmt, nil) == SQLITE_OK else {
        fputs("warn: cert-date carry-forward: previous db has no cable_certs table, nothing to carry\n", stderr)
        return []
    }
    defer { sqlite3_finalize(stmt) }
    func text(_ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }
    var out: [CertListing] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        out.append(CertListing(xid: Int(sqlite3_column_int64(stmt, 0)),
                               company: text(1), model: text(2), certDate: text(3)))
    }
    if out.isEmpty {
        fputs("warn: cert-date carry-forward: the previous db has 0 certification listings, nothing to carry\n", stderr)
    }
    print("cert-date carry-forward: \(out.count) listings in the previous db")
    return out
}

/// Fill in the dates the feed dropped, from the previous db, and print one
/// line per carried date so the carry stays visible in the build output.
func applyCertDateCarryForward(previous: [CertListing]) {
    var rowids: [Int64] = []
    var listings: [CertListing] = []
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT rowid, xid, company, model, cert_date FROM cable_certs ORDER BY rowid",
                             -1, &stmt, nil) == SQLITE_OK else {
        fputs("error: could not read cable_certs for the cert-date carry-forward\n", stderr)
        failBuild(2)
    }
    func text(_ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }
    while sqlite3_step(stmt) == SQLITE_ROW {
        rowids.append(sqlite3_column_int64(stmt, 0))
        listings.append(CertListing(xid: Int(sqlite3_column_int64(stmt, 1)),
                                    company: text(2), model: text(3), certDate: text(4)))
    }
    sqlite3_finalize(stmt)

    let result = carryForwardCertDates(new: listings, previous: previous)
    func describe(_ l: CertListing) -> String {
        "\(String(format: "0x%X", l.xid)) \(l.company) / \(l.model)"
    }

    var update: OpaquePointer?
    guard sqlite3_prepare_v2(db, "UPDATE cable_certs SET cert_date = ? WHERE rowid = ?",
                             -1, &update, nil) == SQLITE_OK else {
        fputs("error: could not prepare the cert-date carry-forward update\n", stderr)
        failBuild(2)
    }
    defer { sqlite3_finalize(update) }
    let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for i in result.carried {
        sqlite3_reset(update)
        sqlite3_bind_text(update, 1, result.dates[i], -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(update, 2, rowids[i])
        guard sqlite3_step(update) == SQLITE_DONE else {
            fputs("error: cert-date carry-forward update failed for \(describe(listings[i]))\n", stderr)
            failBuild(2)
        }
        print("  carried forward: \(describe(listings[i])) -> \(result.dates[i])")
    }
    for i in result.ambiguous {
        print("  not carried (ambiguous: listed more than once): \(describe(listings[i]))")
    }
    print("cert-date carry-forward: \(result.carried.count) date(s) carried, " +
          "\(result.ambiguous.count) ambiguous")
}

// MARK: - Main

// Validate the markdown before openDB() touches anything: openDB() deletes
// the bundled database, so a rejected row must fail the build while every
// generated artifact is still intact.
validateKnownCablesMarkdown()

// Read the certification listings of the committed db, so dates USB-IF's
// feed has dropped can be carried forward (see carryForwardCertDates).
let previousCertListings = loadPreviousCertListings()

openDB()
createSchema()

let vendorCount = importUSBIFVendors()
print("Imported \(vendorCount) USB-IF vendors")

let usbids = importUSBIDsVendors()
print("usb.ids: \(usbids.inserted) new vendors added, \(usbids.skipped) already in USB-IF list")

let manual = importManualVendors()
print("manual-vendors: \(manual.inserted) added, \(manual.skipped) skipped (already in USB-IF or usb.ids)")

let cableCount = importKnownCables()
print("Imported \(cableCount) known cables")

let certs = importCertifications()
print("USB-IF certs: \(certs.listings) listings across \(certs.xids) XIDs")
applyCertDateCarryForward(previous: previousCertListings)

// Guard against silently shipping a cert-less db. With the per-XID -> bulk
// fallback and the bulk floor, zero listings can only mean the bulk fetch
// itself failed (a network outage), not a partial per-XID failure. Fail the
// build loudly at the end (after the db is written, so the message about
// restoring it is accurate), unless a cert-less build was asked for.
// A deliberate cert-less build requires ALLOW_EMPTY_CERTS set to a NON-empty
// value; an unset or empty var does not count as the override.
let allowEmptyCerts = !(ProcessInfo.processInfo.environment["ALLOW_EMPTY_CERTS"] ?? "").isEmpty
let certsCollapsed = certs.listings == 0 && !allowEmptyCerts

// Guard against a quieter version of the same loss: a failed per-XID fetch.
// importCertifications() records every XID whose per-XID fetch returned nil
// (a network failure, a malformed or company-less response, or the
// WC_FAIL_CERT_FETCH hook) and the check at the end of this script fails the
// build with exit 6 if there are any, unless ALLOW_EMPTY_CERTS is set. The
// importer still falls back to bulk rows for such an XID, but that fallback
// only ever inserts the rows bulk happens to carry for that XID, which is why
// it cannot stand in for the fetch. Several XIDs are
// shared by more than one company (e.g. 0x2642, 0x2643, 0x264C, 0x264D carry
// both a Johnson Component row in bulk and a StarTech listing that only the
// per-XID endpoint returns), so a failed fetch on one of those silently
// drops the company bulk does not know about while still reporting the XID
// as covered. A bulk row can also exist with an empty company, inserting
// nothing. Any failed per-XID fetch is therefore treated as unresolved,
// regardless of what bulk carries for that XID.
let failedCertFetches = certs.failedXIDs

// Speed/Power/Type consistency and exact-duplicate checks already ran inside
// importKnownCables(), before any row was inserted (see
// findFingerprintInconsistency / findExactDuplicateRow): a violation exits
// the build there rather than reaching this point.

// Summary: total rows, unique fingerprints, shared fingerprints.
var totalRows = 0
var uniqueFingerprints = 0
var sharedFingerprints = 0
let summaryQuery = """
    SELECT COUNT(*) as total,
           COUNT(DISTINCT vid || ':' || pid || ':' || cable_vdo) as unique_fps
    FROM cables
    """
let sharedQuery = """
    SELECT COUNT(*) FROM (
        SELECT vid, pid, cable_vdo FROM cables
        GROUP BY vid, pid, cable_vdo
        HAVING COUNT(*) > 1
    )
    """
var sumStmt: OpaquePointer?
if sqlite3_prepare_v2(db, summaryQuery, -1, &sumStmt, nil) == SQLITE_OK {
    if sqlite3_step(sumStmt) == SQLITE_ROW {
        totalRows = Int(sqlite3_column_int(sumStmt, 0))
        uniqueFingerprints = Int(sqlite3_column_int(sumStmt, 1))
    }
    sqlite3_finalize(sumStmt)
}
var sharedStmt: OpaquePointer?
if sqlite3_prepare_v2(db, sharedQuery, -1, &sharedStmt, nil) == SQLITE_OK {
    if sqlite3_step(sharedStmt) == SQLITE_ROW {
        sharedFingerprints = Int(sqlite3_column_int(sharedStmt, 0))
    }
    sqlite3_finalize(sharedStmt)
}
print("Cable DB summary: \(totalRows) total rows, \(uniqueFingerprints) unique fingerprints, \(sharedFingerprints) shared fingerprints")

let jsonCount = exportCablesJSON()
print("Exported \(jsonCount) cables to \(cablesJSON)")

/// Runs a command and returns its trimmed stdout, or nil if it fails to launch
/// or exits non-zero.
func runCapturing(_ launchPath: String, _ args: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let out = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return out.isEmpty ? nil : out
}

/// When the curated cable list was last actually changed.
///
/// Uncommitted edits count as "now", because the export we just wrote includes
/// them. Otherwise it is the commit date of the last change to the markdown,
/// which is the honest answer and does not move when nothing changed. Falls
/// back to the file's mtime outside a git checkout.
func lastCableDataChange() -> String {
    let git = "/usr/bin/git"
    let dirty = runCapturing(git, ["status", "--porcelain", "--", manualCablesMD])
    if dirty == nil, let committed = runCapturing(git, ["log", "-1", "--format=%cI", "--", manualCablesMD]) {
        return committed
    }
    if dirty != nil {
        // Working-tree edits are in this export, so stamp it now.
        return ISO8601DateFormatter().string(from: Date())
    }
    let mtime = (try? FileManager.default.attributesOfItem(atPath: manualCablesMD)[.modificationDate]) as? Date
    return ISO8601DateFormatter().string(from: mtime ?? Date())
}

do {
    let updated = lastCableDataChange()
    let payload = ["updated": updated]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    try (String(decoding: data, as: UTF8.self) + "\n").write(toFile: cablesUpdatedJSON, atomically: true, encoding: .utf8)
    print("Cable data last changed \(updated) -> \(cablesUpdatedJSON)")
} catch {
    fputs("warn: could not write \(cablesUpdatedJSON): \(error)\n", stderr)
}

// Copy to docs/ for the website.
closeDB()

do {
    let fm = FileManager.default
    if fm.fileExists(atPath: dbWebCopy) {
        try fm.removeItem(atPath: dbWebCopy)
    }
    try fm.copyItem(atPath: dbOutput, toPath: dbWebCopy)
    print("Copied to \(dbWebCopy)")
} catch {
    fputs("warn: could not copy to docs/: \(error)\n", stderr)
}

print("Done: \(dbOutput)")

if certsCollapsed {
    fputs("""
        error: the certification table is EMPTY (0 listings). The USB-IF bulk
        endpoint was most likely unreachable or changed during this build, so
        both bundled databases now have NO cable certifications. Restore them
        and re-run when the network is available:
          git checkout -- Sources/WhatCableCore/Resources/whatcable.db docs/whatcable.db
        Or set ALLOW_EMPTY_CERTS=1 to build deliberately without certifications.

        """, stderr)
    exit(5)
}

if !failedCertFetches.isEmpty {
    let hexList = failedCertFetches.map { String(format: "0x%X", $0) }.joined(separator: ", ")
    if allowEmptyCerts {
        fputs("warn: \(failedCertFetches.count) certification fetch(es) failed " +
              "(ALLOW_EMPTY_CERTS override): \(hexList)\n", stderr)
    } else {
        fputs("""
            error: \(failedCertFetches.count) certification fetch(es) failed: \(hexList).
            Their listings may be missing or incomplete in both bundled
            databases. Restore them and re-run when the network is healthy:
              git checkout -- Sources/WhatCableCore/Resources/whatcable.db docs/whatcable.db
            The per-XID cache means a re-run only refetches what failed.
            Or set ALLOW_EMPTY_CERTS=1 to build deliberately without them.

            """, stderr)
        exit(6)
    }
}
