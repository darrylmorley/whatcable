import Foundation
import Testing
import WhatCableCore

// MARK: - PDEventTraceCorpusSweepTests
//
// Corpus coverage for `PDEventTrace.parse`, the tokeniser for the
// AppleSmartBattery `PortControllerEvtBuffer` ring. The parse itself lives in
// Core and has byte-exact fixture tests in
// `Tests/WhatCableCoreTests/PDEventTests.swift`; those fixtures come from seven
// before/after captures on two machines. This file is the replay half: every
// `PortControllerEvtBuffer` in the customer-probe corpus (probe 32) tokenised
// and checked against that same machine's own PortController* counters.
//
// The check is a less-or-equal one, not equality, and that is deliberate. The
// buffer is a 120-byte ring and probe 32 truncates its dump to 64 bytes, so a
// buffer holds only the tail of the machine's history while the counters hold
// all of it. Tokens can therefore only ever be FEWER than the counter. Two
// tokens are dropped before counting:
//
//   - the FIRST, because the ring seam can split a record, so the leading
//     opcode may really be some earlier record's argument byte, and
//   - the LAST, because the 64-byte truncation can cut a record in half.
//
// Anything left over that still exceeds its counter means the tokeniser
// invented an event, which is exactly the failure the old one-byte-per-event
// decode produced.
//
// House convention: the corpus lives behind the gitignored `research` symlink
// (scripts/link-research.sh). A machine without it SKIPS with a message rather
// than failing, and the count floors below only apply once enough of the
// corpus is actually present, so a fresh clone with only the git-tracked
// probe-32 files does not trip them.
@Suite("PDEventTrace corpus sweep - PortControllerEvtBuffer (probe 32)")
struct PDEventTraceCorpusSweepTests {

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
    // `PortDiagnosticsWatcherCorpusSweepTests.extractPortControllerInfoItems`
    // keeps only the values that parse as an integer, which throws the event
    // buffer away, so this file needs its own reader. Same section-finding
    // rule as that one (the FIRST `PortControllerInfo` array, at two-space
    // indent; probe 32 prints the array a second time further down under a
    // child node, and counting both would double every port), but the values
    // are kept as raw strings so both shapes survive:
    //
    //   PortControllerEvtBuffer =   Data[120]: 03 01 1a 01 ... ...
    //   PortControllerIrqCntPlg =   76 (0x4c)

    private static func portControllerEntries(_ text: String) -> [[String: String]] {
        let lines = text.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: {
            $0.hasPrefix("  PortControllerInfo = ") && $0.contains("Array[")
        }) else { return [] }

        var entries: [[String: String]] = []
        var current: [String: String]?

        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.contains("Dict[") {
                if let current { entries.append(current) }
                current = [:]
            } else if current != nil, trimmed.hasPrefix("PortController") {
                guard let eq = trimmed.range(of: " = ") else { continue }
                let key = String(trimmed[..<eq.lowerBound])
                let value = String(trimmed[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
                current?[key] = value
            } else if current != nil, !trimmed.isEmpty, !trimmed.hasPrefix("["), !line.hasPrefix(" ") {
                break
            }
        }
        if let current { entries.append(current) }
        return entries
    }

    /// The bytes out of a `Data[120]: 03 01 1a ...` value. Anything that is not
    /// a two-character hex pair (the trailing `...` the dump ends with, most
    /// obviously) is skipped rather than treated as an error, and a value with
    /// no `Data[` marker at all yields nil.
    private static func hexBytes(_ value: String) -> [UInt8]? {
        guard let marker = value.range(of: "Data[") else { return nil }
        guard let colon = value.range(of: ":", range: marker.upperBound..<value.endIndex) else { return nil }
        var bytes: [UInt8] = []
        for field in value[colon.upperBound...].split(separator: " ") {
            guard field.count == 2, let byte = UInt8(field, radix: 16) else { continue }
            bytes.append(byte)
        }
        return bytes
    }

    /// The decimal half of a `76 (0x4c)` value.
    private static func counter(_ entry: [String: String], _ name: String) -> Int? {
        guard let value = entry["PortController" + name] else { return nil }
        let digits = value.prefix { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    /// Tokens with the ring seam and the truncation edge removed. Fewer than
    /// three tokens means the whole buffer is edge, so nothing is countable.
    private static func countableEvents(_ trace: PDEventTrace) -> [PDEventRecord] {
        guard trace.events.count > 2 else { return [] }
        return Array(trace.events.dropFirst().dropLast())
    }

    // MARK: - The sweep

    @Test("Probe 32 sweep: no decoded event outruns the counter that records it")
    func eventCountsNeverExceedTheirCounters() {
        let folders = Self.allProbeFolders()
        guard !folders.isEmpty else {
            print("[PDEventTraceSweep] SKIP: no customer-probe corpus at \(Self.probeRoot.path). "
                + "Run scripts/link-research.sh to link it, or this sweep tests nothing.")
            return
        }

        // Each pairing is (opcode we count, the counter that must not be beaten).
        // Verified against counter deltas on 2026-09-05: see the decode brief.
        let pairs: [(PDEvent, String)] = [
            (.uvdmStatusUpdate, "IrqCntUvdmStsUpd"),
            (.identityReceived, "IrqCntRxIdSop"),
            (.plugEvent, "IrqCntPlg"),
        ]

        var foldersScanned = 0
        var portsSeen = 0
        var buffersParsed = 0
        var comparisonsMade = 0
        var violations: [String] = []
        // Which branch of the seam rule each buffer took, read back off the
        // buffer and the parse result rather than asked of the parser: the
        // leading zero run says which of the three zero cases applies, and the
        // flag on the first record says which way the L == 0 choice went.
        var unfilledRing = 0      // three or more leading zeros, no seam
        var zeroFragment = 0      // one or two leading zeros, they are the seam
        var firstByteKept = 0     // L == 0, read as a record (H1)
        var firstByteDropped = 0  // L == 0, read as a leftover argument (H2)
        // How many records each L == 0 buffer flagged: every record before the
        // two readings of the seam reconverge. A buffer whose records are ALL
        // flagged never reconverged before the buffer ended.
        var flaggedPerSeamBuffer: [Int] = []
        var neverReconverged: [String] = []
        // 0x5e against IrqCntUvdmEnum is held separately: the naive decode had
        // four violating ports across the corpus, so this one is a recorded
        // baseline rather than an assumed zero. Measured 2026-09-05 with the
        // first-and-last-token rule applied: 0 violating ports out of 2010
        // non-zero buffers, so it is asserted at zero like the rest, and this
        // list exists to print the offenders if that ever stops being true.
        var uvdmEnumViolations: [String] = []

        for folder in folders {
            guard let text = Self.loadProbeText(folder: folder, fileName: "32_smart_battery_full_keys.json") else { continue }
            let entries = Self.portControllerEntries(text)
            guard !entries.isEmpty else { continue }
            foldersScanned += 1

            for (portIndex, entry) in entries.enumerated() {
                portsSeen += 1
                guard let value = entry["PortControllerEvtBuffer"],
                      let bytes = Self.hexBytes(value)
                else { continue }
                // An all-zero buffer is a port whose ring has never been
                // written. It parses to nothing, which is correct, but it is
                // not evidence of anything, so it is not counted as a case.
                guard bytes.contains(where: { $0 != 0x00 }) else { continue }
                buffersParsed += 1

                let trace = PDEventTrace.parse(Data(bytes))
                let countable = Self.countableEvents(trace)

                let leadingZeros = bytes.prefix { $0 == 0x00 }.count
                if leadingZeros >= 3 {
                    unfilledRing += 1
                } else if leadingZeros > 0 {
                    zeroFragment += 1
                } else {
                    // H2 records the first byte as a bare leftover, argument
                    // nil. H1 on a 64-byte buffer gives an argument-taking
                    // opcode its argument, and the only H1 records without one
                    // are 0x48 and 0x5f, which take none (an unknown first byte
                    // is always H2). So a nil argument on anything but those
                    // two is the leftover reading.
                    let leading = trace.events[0]
                    let standsAlone = leading.event == .identityReceived || leading.event == .uvdmStatusUpdate
                    if leading.argument == nil, !standsAlone {
                        firstByteDropped += 1
                    } else {
                        firstByteKept += 1
                    }
                    let flagged = trace.events.filter(\.isSeamAffected).count
                    flaggedPerSeamBuffer.append(flagged)
                    if flagged == trace.events.count {
                        neverReconverged.append("\(folder) port[\(portIndex)]: "
                            + bytes.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ") + " ...")
                    }
                }

                for (event, counterName) in pairs {
                    guard let limit = Self.counter(entry, counterName) else { continue }
                    comparisonsMade += 1
                    let seen = countable.filter { $0.event == event }.count
                    if seen > limit {
                        violations.append("\(folder) port[\(portIndex)]: \(seen) x "
                            + "0x\(String(event.rawValue, radix: 16)) decoded but \(counterName) is \(limit)")
                    }
                }

                if let limit = Self.counter(entry, "IrqCntUvdmEnum") {
                    comparisonsMade += 1
                    let seen = countable.filter { $0.event == .uvdmEnum }.count
                    if seen > limit {
                        uvdmEnumViolations.append("\(folder) port[\(portIndex)]: \(seen) x 0x5e "
                            + "decoded but IrqCntUvdmEnum is \(limit)")
                    }
                }
            }
        }

        print("[PDEventTraceSweep] \(foldersScanned) folders, \(portsSeen) ports, "
            + "\(buffersParsed) non-zero buffers parsed, \(comparisonsMade) counter comparisons, "
            + "\(violations.count) violations, \(uvdmEnumViolations.count) UVDM-enum violations")
        print("[PDEventTraceSweep] seam rule: \(firstByteKept) first byte kept (H1), "
            + "\(firstByteDropped) first byte dropped as a leftover (H2), "
            + "\(zeroFragment) zero-byte leftovers, \(unfilledRing) unfilled rings")
        let maxFlagged = flaggedPerSeamBuffer.max() ?? 0
        let moreThanTwo = flaggedPerSeamBuffer.filter { $0 > 2 }.count
        print("[PDEventTraceSweep] seam flags per L == 0 buffer: max \(maxFlagged), "
            + "\(moreThanTwo) buffers with more than 2 flagged, "
            + "\(neverReconverged.count) never reconverged (every record flagged)")

        let violationReport = "Decoded more events than the port's own counters recorded:\n"
            + violations.prefix(20).joined(separator: "\n")
            + (violations.count > 20 ? "\n... and \(violations.count - 20) more" : "")
        #expect(violations.isEmpty, "\(violationReport)")

        // Baseline, not a hard rule by assumption: measured at zero on
        // 2026-09-05 across 2010 non-zero buffers, so zero is what it holds to.
        let uvdmEnumReport = "0x5e outran IrqCntUvdmEnum, which measured zero violations on 2026-09-05:\n"
            + uvdmEnumViolations.prefix(20).joined(separator: "\n")
            + (uvdmEnumViolations.count > 20 ? "\n... and \(uvdmEnumViolations.count - 20) more" : "")
        #expect(uvdmEnumViolations.isEmpty, "\(uvdmEnumReport)")

        // Coverage floor. A sweep that collected no cases is green for the
        // wrong reason, which is the whole failure this rule guards against.
        // Only 12 probe-32 files are git-tracked, so gate the corpus-sized
        // floor on the corpus actually being linked; the correctness checks
        // above run either way.
        #expect(buffersParsed > 0,
            "The corpus is present (\(foldersScanned) folders) but no non-zero event buffer was parsed from it")

        // Every buffer takes exactly one branch of the seam rule. Printing the
        // split without checking it adds up would let a buffer fall through
        // the classification unnoticed, and the numbers would still look fine.
        let branchTotal = firstByteKept + firstByteDropped + zeroFragment + unfilledRing
        #expect(branchTotal == buffersParsed,
            "Seam branches sum to \(branchTotal) but \(buffersParsed) buffers were parsed")
        // Flagging hides records, so a seam that stays ambiguous for long
        // would hide real history. Measured 2026-09-06 across the 1425 L == 0
        // buffers: max 3 flagged, 3 buffers over 2, 0 never reconverged. Four
        // leaves room for a longer disagreement, not a runaway.
        let reconvergenceReport = "A seam flagged \(maxFlagged) records; the two readings should reconverge within 4:\n"
            + neverReconverged.prefix(20).joined(separator: "\n")
        #expect(maxFlagged <= 4, "\(reconvergenceReport)")
        if foldersScanned >= 50 {
            // 2010 non-zero buffers measured 2026-09-05; the corpus only grows.
            #expect(buffersParsed >= 1500,
                "Expected at least 1500 non-zero PortControllerEvtBuffers across the corpus; got \(buffersParsed)")
        }
    }

    // MARK: - Malformed input

    @Test("A short, odd-length or garbage buffer parses instead of crashing")
    func malformedBuffersStillParse() {
        // Shorter than the 64 bytes probe 32 dumps.
        #expect(PDEventTrace.parse(Data([0x03, 0x01, 0x48])).events.count == 2)
        // Ends on an opcode that wants an argument it never got.
        let cut = PDEventTrace.parse(Data([0x48, 0x30]))
        #expect(cut.events.last?.argument == nil)
        // Nothing but bytes with no known meaning.
        #expect(PDEventTrace.parse(Data([0xaa, 0xbb, 0xcc])).events.count == 3)
        // Empty, and all-zero.
        #expect(PDEventTrace.parse(Data()).events.isEmpty)
        #expect(PDEventTrace.parse(Data(repeating: 0x00, count: 64)).events.isEmpty)
        // A full-length buffer of one repeated argument-taking opcode: 64 is
        // even, so this is the odd-trailing-byte boundary from the other side.
        #expect(PDEventTrace.parse(Data(repeating: 0x30, count: 63)).events.count == 32)
    }
}
