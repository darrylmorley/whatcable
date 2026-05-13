#!/usr/bin/env swift

// Sync data/known-cables.md from closed `cable-report` issues.
//
// Pulls every closed issue tagged `cable-report` via `gh`, parses the
// e-marker fingerprint table out of each body, looks up canonical USB-IF
// vendor names from the bundled TSV, and rewrites the table block in
// data/known-cables.md.
//
// Hand-edited "Brand / model context" cells are preserved by issue
// number. Newly-added rows get "(needs review)" as a placeholder so
// you know to fill them in by hand.
//
// Run from the repo root:
//   swift scripts/sync-cable-reports.swift
//
// Then re-run scripts/render-known-cables.swift to update docs/cables.html.
//
// Requires:
//   - `gh` CLI authenticated for the repo
//   - Sources/WhatCableCore/Resources/usbif-vendors.tsv

import Foundation

// MARK: - Paths

let repoRoot = FileManager.default.currentDirectoryPath
let mdURL = URL(fileURLWithPath: "\(repoRoot)/data/known-cables.md")
let vendorTSVURL = URL(fileURLWithPath: "\(repoRoot)/Sources/WhatCableCore/Resources/usbif-vendors.tsv")
let needsReview = "(needs review)"

// MARK: - Vendor TSV

func loadVendors() -> [Int: String] {
    guard let text = try? String(contentsOf: vendorTSVURL, encoding: .utf8) else {
        fputs("error: could not read \(vendorTSVURL.path)\n", stderr)
        exit(2)
    }
    var out: [Int: String] = [:]
    for line in text.components(separatedBy: "\n") {
        if line.hasPrefix("#") || line.isEmpty { continue }
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 2, let vid = Int(parts[0]) else { continue }
        out[vid] = parts[1].trimmingCharacters(in: .whitespaces)
    }
    return out
}

// MARK: - gh

func runGh() -> [[String: Any]] {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [
        "gh", "issue", "list",
        "--repo", "darrylmorley/whatcable",
        "--label", "cable-report",
        "--state", "closed",
        "--json", "number,body,title",
        "--limit", "200",
    ]
    let stdout = Pipe()
    let stderr = Pipe()
    proc.standardOutput = stdout
    proc.standardError = stderr
    do { try proc.run() } catch {
        fputs("error: could not run gh: \(error)\n", Darwin.stderr)
        exit(3)
    }
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        fputs("error: gh exited \(proc.terminationStatus): \(err)\n", Darwin.stderr)
        exit(4)
    }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        fputs("error: could not parse gh JSON output\n", Darwin.stderr)
        exit(5)
    }
    return json
}

// MARK: - Body parsing

struct Report {
    let issueNumber: Int
    let vid: Int           // 0 for zeroed
    let pid: Int           // 0 for zeroed
    let xidCol: String     // "none" or formatted hex
    let speed: String      // empty for missing
    let power: String      // empty for missing
    let type: String       // "passive" / "active" / etc; empty for missing
}

/// Find the value cell of a "| <field> | <value> |" row.
func extractField(_ field: String, from body: String) -> String? {
    for raw in body.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("|") else { continue }
        var trimmed = line
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        let parts = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { continue }
        if parts[0] == field { return parts[1] }
    }
    return nil
}

/// Pull `0xABCD` out of a string. Returns the integer value or nil.
func extractHex(_ s: String) -> Int? {
    let re = try! NSRegularExpression(pattern: "0x([0-9A-Fa-f]+)")
    let range = NSRange(s.startIndex..., in: s)
    guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges >= 2 else { return nil }
    guard let r = Range(m.range(at: 1), in: s) else { return nil }
    return Int(String(s[r]), radix: 16)
}

func parse(body: String, issueNumber: Int) -> Report? {
    guard let vidCell = extractField("Vendor ID", from: body),
          let vid = extractHex(vidCell) else {
        fputs("warn: issue #\(issueNumber): no Vendor ID, skipping\n", Darwin.stderr)
        return nil
    }
    let pid = extractField("Product ID", from: body).flatMap { extractHex($0) } ?? 0

    // XID: "USB-IF certification ID" cell. May be missing entirely on
    // older reports. May contain "none (XID = 0)" or a hex value.
    let xidCol: String
    if let xidCell = extractField("USB-IF certification ID", from: body) {
        if xidCell.lowercased().contains("none") || xidCell.contains("XID = 0") {
            xidCol = "none"
        } else if let xid = extractHex(xidCell), xid != 0 {
            xidCol = String(format: "`0x%X`", xid)
        } else {
            xidCol = "none"
        }
    } else {
        xidCol = "none"
    }

    // Cable speed / current rating / type are plain text in the template.
    // Strip backticks if present, leave wording verbatim.
    func stripCode(_ s: String) -> String {
        s.replacingOccurrences(of: "`", with: "")
    }

    let speed = extractField("Cable speed", from: body).map(stripCode) ?? ""
    let power = extractField("Current rating", from: body).map(humanisePower) ?? ""
    let type = extractField("Type", from: body).map(stripCode) ?? ""

    return Report(
        issueNumber: issueNumber,
        vid: vid,
        pid: pid,
        xidCol: xidCol,
        speed: speed,
        power: power,
        type: type
    )
}

/// Reformat "5 A at up to 20V (~100W)" as "5 A / 20 V (100 W)" to match
/// the existing table convention. Falls back to the raw string if it
/// doesn't match.
func humanisePower(_ raw: String) -> String {
    let re = try! NSRegularExpression(
        pattern: "(\\d+(?:\\.\\d+)?)\\s*A\\s+at\\s+up\\s+to\\s+(\\d+(?:\\.\\d+)?)\\s*V\\s*\\(~?(\\d+(?:\\.\\d+)?)\\s*W\\)",
        options: [.caseInsensitive]
    )
    let range = NSRange(raw.startIndex..., in: raw)
    guard let m = re.firstMatch(in: raw, range: range), m.numberOfRanges >= 4,
          let amps = Range(m.range(at: 1), in: raw),
          let volts = Range(m.range(at: 2), in: raw),
          let watts = Range(m.range(at: 3), in: raw)
    else {
        return raw
    }
    return "\(raw[amps]) A / \(raw[volts]) V (\(raw[watts]) W)"
}

// MARK: - Existing-context extraction

/// Read the current data/known-cables.md and return a map of
/// `issue_number → "Brand / model context"` from the existing table,
/// so re-syncing preserves hand-edited notes.
func loadExistingContexts() -> [Int: String] {
    guard let md = try? String(contentsOf: mdURL, encoding: .utf8) else { return [:] }
    let lines = md.components(separatedBy: "\n")
    var out: [Int: String] = [:]

    var inTable = false
    for line in lines {
        if line.hasPrefix("## Table") { inTable = true; continue }
        if inTable, line.hasPrefix("## ") { break }
        guard inTable, line.hasPrefix("|"), !line.contains("---") else { continue }
        let parts = line.dropFirst().dropLast().components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Data rows have a code span like `0xABCD` in column 1 (the VID).
        // Header row has plain text "VID" there. We use that as the
        // discriminator so we skip the header without a name match.
        guard parts.count == 9, parts[1].hasPrefix("`0x") else { continue }
        let context = parts[0]
        let source = parts[8]
        // Source cell is "[#NN](url)"; pull out NN.
        let re = try! NSRegularExpression(pattern: "#(\\d+)")
        let range = NSRange(source.startIndex..., in: source)
        if let m = re.firstMatch(in: source, range: range),
           m.numberOfRanges >= 2,
           let r = Range(m.range(at: 1), in: source),
           let n = Int(String(source[r])) {
            out[n] = context
        }
    }
    return out
}

// MARK: - Row rendering

func renderRow(_ report: Report, context: String, vendors: [Int: String]) -> String {
    let vidCol = String(format: "`0x%04X`", report.vid)
    let pidCol = String(format: "`0x%04X`", report.pid)
    let vendor: String
    if report.vid == 0 {
        vendor = "(zeroed)"
    } else if let name = vendors[report.vid] {
        vendor = name
    } else {
        vendor = "Unregistered"
    }
    let speed = report.speed.isEmpty ? "(none advertised)" : report.speed
    let power = report.power.isEmpty ? "(not advertised)" : report.power
    let type = report.type.isEmpty ? "passive" : report.type
    let source = "[#\(report.issueNumber)](https://github.com/darrylmorley/whatcable/issues/\(report.issueNumber))"
    return "| \(context) | \(vidCol) | \(pidCol) | \(vendor) | \(report.xidCol) | \(speed) | \(power) | \(type) | \(source) |"
}

// MARK: - Update markdown

func rewriteMarkdown(rows: [String]) {
    guard let md = try? String(contentsOf: mdURL, encoding: .utf8) else {
        fputs("error: could not read \(mdURL.path)\n", Darwin.stderr)
        exit(6)
    }
    let lines = md.components(separatedBy: "\n")

    // Find the header row and the first non-table line after it.
    var headerIdx: Int?
    for (i, line) in lines.enumerated() where line.hasPrefix("## Table") {
        for j in (i + 1) ..< lines.count where lines[j].hasPrefix("|") {
            headerIdx = j
            break
        }
        break
    }
    guard let h = headerIdx, h + 1 < lines.count, lines[h + 1].contains("---") else {
        fputs("error: could not find table header in \(mdURL.path)\n", Darwin.stderr)
        exit(7)
    }

    // Walk forward past data rows.
    var endIdx = h + 2
    while endIdx < lines.count, lines[endIdx].hasPrefix("|") { endIdx += 1 }

    var newLines = Array(lines[..<(h + 2)])  // up to and including separator
    newLines.append(contentsOf: rows)
    newLines.append(contentsOf: lines[endIdx...])

    do {
        try newLines.joined(separator: "\n").write(to: mdURL, atomically: true, encoding: .utf8)
    } catch {
        fputs("error: could not write \(mdURL.path): \(error)\n", Darwin.stderr)
        exit(8)
    }
}

// MARK: - Main

let vendors = loadVendors()
let issues = runGh()
let existingContexts = loadExistingContexts()

var reports: [Report] = []
for issue in issues {
    guard let n = issue["number"] as? Int,
          let body = issue["body"] as? String else { continue }
    if let r = parse(body: body, issueNumber: n) { reports.append(r) }
}

// Sort: VID ascending, zeroed last, then by issue number ascending.
reports.sort { a, b in
    let aZero = a.vid == 0
    let bZero = b.vid == 0
    if aZero != bZero { return !aZero }  // non-zero first
    if a.vid != b.vid { return a.vid < b.vid }
    return a.issueNumber < b.issueNumber
}

var newCount = 0
let rendered = reports.map { report -> String in
    let context = existingContexts[report.issueNumber] ?? {
        newCount += 1
        return needsReview
    }()
    return renderRow(report, context: context, vendors: vendors)
}

rewriteMarkdown(rows: rendered)
print("synced \(reports.count) reports (\(newCount) new, needs hand-edit on '\(needsReview)' rows)")
print("now run: swift scripts/render-known-cables.swift")
