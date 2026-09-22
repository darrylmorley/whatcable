#!/usr/bin/env swift
// Regenerates Sources/WhatCableCore/Display/EDIDTimingTables.generated.swift
// from data/edid-timings/vesa-dmt.csv and data/edid-timings/cta-861-vic.csv.
//
// Usage:
//   swift scripts/edid-timings/build-edid-timings.swift            # regenerate
//   swift scripts/edid-timings/build-edid-timings.swift --check    # verify only, exit 1 on drift
//
// Run this after regenerating the CSVs with extract-dmt.py / extract-cta-vic.py
// and cross-checking them with check-edid-timings.py. See scripts/edid-timings/README.md.

import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // edid-timings/
    .deletingLastPathComponent()  // scripts/
    .deletingLastPathComponent()  // repo root

let dmtCSVPath = repoRoot.appendingPathComponent("data/edid-timings/vesa-dmt.csv")
let vicCSVPath = repoRoot.appendingPathComponent("data/edid-timings/cta-861-vic.csv")
let outputPath = repoRoot.appendingPathComponent("Sources/WhatCableCore/Display/EDIDTimingTables.generated.swift")

let checkOnly = CommandLine.arguments.contains("--check")

// MARK: - Tiny CSV reader (no quoting needed: every field here is a plain
// number, hex literal, or true/false token, per the extractor scripts).

func readCSV(_ url: URL) throws -> [[String: String]] {
    let text = try String(contentsOf: url, encoding: .utf8)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    guard !lines.isEmpty else { return [] }
    let header = lines.removeFirst().split(separator: ",").map(String.init)
    return lines.map { line in
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var row: [String: String] = [:]
        for (i, key) in header.enumerated() where i < fields.count {
            row[key] = fields[i]
        }
        return row
    }
}

func parseHexOptional(_ s: String?) -> String? {
    guard let s, !s.isEmpty else { return nil }
    return s  // already "0xNNNN" from the extractor
}

// MARK: - DMT

struct DMTRow {
    let id: Int
    let width: Int
    let height: Int
    let hTotal: Int
    let vTotal: Int
    let pixelClockKHz: Int
    let interlaced: Bool
    let reducedBlanking: Bool
    let standardCode: String?
    let cvtCode: String?
}

func loadDMT() throws -> [DMTRow] {
    let rows = try readCSV(dmtCSVPath)
    return try rows.map { r in
        guard let idStr = r["dmt_id"], let id = Int(idStr.dropFirst(2), radix: 16),
              let width = Int(r["width"] ?? ""), let height = Int(r["height"] ?? ""),
              let hTotal = Int(r["h_total"] ?? ""), let vTotal = Int(r["v_total"] ?? ""),
              let pixelClockKHz = Int(r["pixel_clock_khz"] ?? "")
        else {
            throw GeneratorError.badRow("vesa-dmt.csv row could not be parsed: \(r)")
        }
        return DMTRow(
            id: id, width: width, height: height, hTotal: hTotal, vTotal: vTotal,
            pixelClockKHz: pixelClockKHz,
            interlaced: r["interlaced"] == "true",
            reducedBlanking: r["reduced_blanking"] == "true",
            standardCode: parseHexOptional(r["std_code"]),
            cvtCode: parseHexOptional(r["cvt_code"])
        )
    }.sorted { $0.id < $1.id }
}

// MARK: - VIC

struct VICRow {
    let vic: Int
    let width: Int
    let height: Int
    let hTotal: Int
    let vTotal: Int
    let pixelClockKHz: Int
    let interlaced: Bool
}

func loadVIC() throws -> [VICRow] {
    let rows = try readCSV(vicCSVPath)
    return try rows.map { r in
        guard let vic = Int(r["vic"] ?? ""), let width = Int(r["width"] ?? ""),
              let height = Int(r["height"] ?? ""), let hTotal = Int(r["h_total"] ?? ""),
              let vTotal = Int(r["v_total"] ?? ""), let pixelClockKHz = Int(r["pixel_clock_khz"] ?? "")
        else {
            throw GeneratorError.badRow("cta-861-vic.csv row could not be parsed: \(r)")
        }
        return VICRow(
            vic: vic, width: width, height: height, hTotal: hTotal, vTotal: vTotal,
            pixelClockKHz: pixelClockKHz, interlaced: r["interlaced"] == "true"
        )
    }.sorted { $0.vic < $1.vic }
}

enum GeneratorError: Error, CustomStringConvertible {
    case badRow(String)
    var description: String {
        switch self {
        case .badRow(let msg): return msg
        }
    }
}

// MARK: - Rendering

func renderDMT(_ r: DMTRow) -> String {
    let std = r.standardCode.map { "\($0)" } ?? "nil"
    let cvt = r.cvtCode.map { "\($0)" } ?? "nil"
    let id = String(format: "0x%02X", r.id)
    return """
            \(id): DMTTiming(id: \(id), width: \(r.width), height: \(r.height), hTotal: \(r.hTotal), vTotal: \(r.vTotal), pixelClockKHz: \(r.pixelClockKHz), interlaced: \(r.interlaced), reducedBlanking: \(r.reducedBlanking), standardCode: \(std), cvtCode: \(cvt)),
    """
}

func renderVIC(_ r: VICRow) -> String {
    """
            \(r.vic): VICTiming(vic: \(r.vic), width: \(r.width), height: \(r.height), hTotal: \(r.hTotal), vTotal: \(r.vTotal), pixelClockKHz: \(r.pixelClockKHz), interlaced: \(r.interlaced)),
    """
}

func render(dmt: [DMTRow], vic: [VICRow]) -> String {
    var out = """
    // DO NOT EDIT. Generated by scripts/edid-timings/build-edid-timings.swift from
    // data/edid-timings/vesa-dmt.csv and data/edid-timings/cta-861-vic.csv.
    //
    // Sources of record:
    //   VESA DMT Standard v1.0 Rev 13 (https://glenwing.github.io/docs/VESA-DMT-1.13.pdf)
    //   ANSI/CTA-861-H (https://archive.org/download/ansi-cta-861-h-final/ANSI-CTA-861-H-Final.pdf)
    //
    // Both CSVs are cross-checked against edid-decode (MIT, commit
    // f341ed8e3742118a86619e5f499017db2de30d94) and the Linux kernel's
    // drm_edid.c (GPL-2.0, numeric cross-check only) by
    // scripts/edid-timings/check-edid-timings.py before this file is generated.
    //
    // Regenerate: swift scripts/edid-timings/build-edid-timings.swift
    // Check only: swift scripts/edid-timings/build-edid-timings.swift --check

    public enum EDIDTimingTables {
        public struct DMTTiming: Hashable, Sendable {
            public let id: Int            // DMT ID, 0x01...0x58
            public let width: Int
            public let height: Int
            public let hTotal: Int
            public let vTotal: Int
            public let pixelClockKHz: Int
            public let interlaced: Bool
            public let reducedBlanking: Bool
            public let standardCode: UInt16?   // EDID 2-byte standard timing code, big-endian as printed in the spec
            public let cvtCode: UInt32?        // 3-byte CVT code, 0xRRGGBB as printed

            public init(
                id: Int,
                width: Int,
                height: Int,
                hTotal: Int,
                vTotal: Int,
                pixelClockKHz: Int,
                interlaced: Bool,
                reducedBlanking: Bool,
                standardCode: UInt16?,
                cvtCode: UInt32?
            ) {
                self.id = id
                self.width = width
                self.height = height
                self.hTotal = hTotal
                self.vTotal = vTotal
                self.pixelClockKHz = pixelClockKHz
                self.interlaced = interlaced
                self.reducedBlanking = reducedBlanking
                self.standardCode = standardCode
                self.cvtCode = cvtCode
            }
        }

        public struct VICTiming: Hashable, Sendable {
            public let vic: Int
            public let width: Int
            public let height: Int
            public let hTotal: Int
            public let vTotal: Int             // frame total for interlaced (e.g. 1125 for VIC 5)
            public let pixelClockKHz: Int
            public let interlaced: Bool

            public init(
                vic: Int,
                width: Int,
                height: Int,
                hTotal: Int,
                vTotal: Int,
                pixelClockKHz: Int,
                interlaced: Bool
            ) {
                self.vic = vic
                self.width = width
                self.height = height
                self.hTotal = hTotal
                self.vTotal = vTotal
                self.pixelClockKHz = pixelClockKHz
                self.interlaced = interlaced
            }
        }

        public static let dmt: [Int: DMTTiming] = [

    """
    out += dmt.map(renderDMT).joined(separator: "\n") + "\n"
    out += "    ]\n\n"
    out += "    public static let vic: [Int: VICTiming] = [\n"
    out += vic.map(renderVIC).joined(separator: "\n") + "\n"
    out += "    ]\n"
    out += "}\n"
    return out
}

// MARK: - Main

do {
    let dmt = try loadDMT()
    let vic = try loadVIC()
    let rendered = render(dmt: dmt, vic: vic)

    if checkOnly {
        let existing = (try? String(contentsOf: outputPath, encoding: .utf8)) ?? ""
        if existing == rendered {
            print("OK: EDIDTimingTables.generated.swift matches data/edid-timings/*.csv")
            exit(0)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("EDIDTimingTables.generated.swift")
        try rendered.write(to: tmp, atomically: true, encoding: .utf8)
        let diff = Process()
        diff.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        diff.arguments = ["-u", outputPath.path, tmp.path]
        try diff.run()
        diff.waitUntilExit()
        exit(1)
    } else {
        try rendered.write(to: outputPath, atomically: true, encoding: .utf8)
        print("Wrote \(outputPath.path) (\(dmt.count) DMT rows, \(vic.count) VIC rows)")
    }
} catch {
    FileHandle.standardError.write("build-edid-timings.swift: \(error)\n".data(using: .utf8)!)
    exit(1)
}
