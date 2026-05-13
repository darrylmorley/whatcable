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
// Requires: macOS (uses system SQLite3 via libsqlite3).

import Foundation
import SQLite3

// MARK: - Paths

let repoRoot = FileManager.default.currentDirectoryPath
let vendorTSV = "\(repoRoot)/Sources/WhatCableCore/Resources/usbif-vendors.tsv"
let dbOutput = "\(repoRoot)/Sources/WhatCableCore/Resources/whatcable.db"
let dbWebCopy = "\(repoRoot)/docs/whatcable.db"

// MARK: - SQLite helpers

var db: OpaquePointer?

func openDB() {
    // Remove existing DB so we always start fresh.
    try? FileManager.default.removeItem(atPath: dbOutput)

    let rc = sqlite3_open(dbOutput, &db)
    guard rc == SQLITE_OK else {
        fputs("error: sqlite3_open failed: \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        exit(1)
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
        exit(2)
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
            vid       INTEGER NOT NULL,
            pid       INTEGER NOT NULL,
            cable_vdo INTEGER NOT NULL DEFAULT 0,
            brand     TEXT NOT NULL,
            speed     TEXT NOT NULL DEFAULT '',
            power     TEXT NOT NULL DEFAULT '',
            type      TEXT NOT NULL DEFAULT 'passive',
            xid       TEXT NOT NULL DEFAULT 'none',
            issue_url TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (vid, pid, cable_vdo)
        )
        """)
}

// MARK: - USB-IF vendor import

func importUSBIFVendors() -> Int {
    guard let text = try? String(contentsOfFile: vendorTSV, encoding: .utf8) else {
        fputs("error: could not read \(vendorTSV)\n", stderr)
        exit(3)
    }

    let insertSQL = "INSERT INTO vendors (vid, name, source) VALUES (?, ?, 'usbif')"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("error: prepare failed for vendor insert\n", stderr)
        exit(4)
    }

    runSQL("BEGIN TRANSACTION")
    var count = 0

    for line in text.components(separatedBy: "\n") {
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 2, let vid = Int(parts[0]) else { continue }
        let name = parts[1].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { continue }

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

let usbidsURL = URL(string: "https://usb-ids.gowdy.us/usb.ids")!

func fetchUSBIDs() -> String? {
    do {
        let data = try Data(contentsOf: usbidsURL)
        // The file is mostly UTF-8 but contains a few invalid bytes.
        // Fall back to Latin-1 (which always succeeds) if strict UTF-8 fails.
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    } catch {
        fputs("warn: usb.ids fetch failed: \(error)\n", stderr)
        return nil
    }
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

// MARK: - Known cables import (from data/known-cables.md)

let knownCablesMD = "\(repoRoot)/data/known-cables.md"

func importKnownCables() -> Int {
    guard let text = try? String(contentsOfFile: knownCablesMD, encoding: .utf8) else {
        fputs("warn: could not read \(knownCablesMD), skipping cables\n", stderr)
        return 0
    }

    let insertSQL = """
        INSERT OR REPLACE INTO cables (vid, pid, cable_vdo, brand, speed, power, type, xid, issue_url)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("warn: prepare failed for cable insert\n", stderr)
        return 0
    }

    runSQL("BEGIN TRANSACTION")
    var count = 0

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

        let brand = parts[0]
        // Skip "(needs review)" rows
        if brand == "(needs review)" { continue }

        guard let vid = parseHex(parts[1]),
              let pid = parseHex(parts[2]) else { continue }
        let cableVDO = parseHex(parts[3]) ?? 0
        let xid = parts[5]
        let speed = parts[6]
        let power = parts[7]
        let type = parts[8]
        // Source cell is "[#NN](url)"; extract the URL.
        let issueURL: String
        if let urlStart = parts[9].range(of: "("),
           let urlEnd = parts[9].range(of: ")") {
            issueURL = String(parts[9][urlStart.upperBound..<urlEnd.lowerBound])
        } else {
            issueURL = ""
        }

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(vid))
        sqlite3_bind_int(stmt, 2, Int32(pid))
        sqlite3_bind_int(stmt, 3, Int32(bitPattern: UInt32(cableVDO)))
        sqlite3_bind_text(stmt, 4, (brand as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (speed as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (power as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (type as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (xid as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, (issueURL as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            fputs("warn: failed to insert cable VID=\(vid) PID=\(pid): \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        } else {
            count += 1
        }
    }

    runSQL("COMMIT")
    sqlite3_finalize(stmt)
    return count
}

/// Parse "`0xABCD`" or "`0x01234567`" into an integer.
func parseHex(_ s: String) -> Int? {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "`", with: "")
    guard trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") else { return nil }
    return Int(trimmed.dropFirst(2), radix: 16)
}

// MARK: - Main

openDB()
createSchema()

let vendorCount = importUSBIFVendors()
print("Imported \(vendorCount) USB-IF vendors")

let usbids = importUSBIDsVendors()
print("usb.ids: \(usbids.inserted) new vendors added, \(usbids.skipped) already in USB-IF list")

let cableCount = importKnownCables()
print("Imported \(cableCount) known cables")

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
