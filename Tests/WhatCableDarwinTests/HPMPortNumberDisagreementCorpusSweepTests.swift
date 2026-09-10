import Foundation
import Testing
@testable import WhatCableDarwinBackend

// MARK: - HPMPortNumberDisagreementCorpusSweepTests
//
// Corpus evidence for the rule that the `UsbIOPort` path is the ONLY truth
// about which HPM port a USB port belongs to, and that no positional or offset
// rule can stand in for it.
//
// WHY THIS MATTERS: two subsystems number the same physical USB-C port. The USB
// side publishes `usb-c-port-number=N` on its xHCI port node; the HPM
// (port-controller) side names its node `Port-USB-C@N`. Where a device's
// ancestor chain carries a `UsbIOPort` path, the shipped code follows that path
// and reads the port name off its tail. Only where no such path exists (macOS
// 14 and 15) does it fall back to a positional controller index.
//
// WHAT THIS SWEEP GUARDS, AND WHAT IT DOES NOT. It pins two things: the corpus
// fact (the two numbering schemes really do disagree, in exactly two shapes)
// and the shipped path-tail parse, `USBWatcher.portName(fromUSBIOPortPath:)`.
// It does NOT exercise the ancestor walk that prefers a `UsbIOPort` path in the
// first place, because it feeds the parser a path string lifted straight out of
// the probe text. Replacing the join itself with a positional or offset rule
// leaves this sweep green; the suite that goes red for that is
// `USBWatcherCorpusSweepTests`, which resolves port names through the shipped
// join. Run that one when refactoring the join. What this file kills is the
// BELIEF that makes a positional rule look safe: that the two schemes agree.
//
// THE TWO MEASURED DISAGREEMENT SHAPES, from probe 36 across the whole corpus:
//
//   - Base M1 SWAPS the two ports: USB 1 is `@2` and USB 2 is `@1`, both
//     directions present in equal numbers.
//   - Base M4 and base M5 SKIP `@3`: USB 3 is `@4`.
//
// A swap and a skip cannot share an offset. There is no constant, and no
// per-family constant either, that reconciles `1 -> 2, 2 -> 1` with `3 -> 4`
// while leaving every other port on those same machines alone. That is the
// whole argument for keeping the path lookup, and it is why the assertions
// below pin the SHAPES exactly (which families disagree, and which
// (usbNumber, atN) pairs occur) while leaving the COUNTS as floors, so ordinary
// corpus growth cannot fail the build but a new family or a new shape can.
//
// WHICH FOLDERS CONTRIBUTE, and it is not an OS split. A folder contributes
// records only if its probe build emitted the join section: 690 of the 991
// probe-36 folders carry it, and that tracks the PROBE VERSION, not macOS. 61
// folders on macOS 14 or 15 do print the section, and 250 on macOS 26 or 27 do
// not. macOS 15 and below have a separate, real limit: where the section IS
// present on those, every path reads `UsbIOPort=(none)`, so no port name
// resolves and they contribute nothing. Measured records by macOS major: 2251
// on 26, 751 on 27, zero on 14 and 15. Keep the two apart when a coverage drop
// needs diagnosing: a missing section is a probe-version gap, a `(none)` path
// inside a present section is the macOS 15 limit.
//
// This sweep backs the doc comment on `busIndex(for:)` in
// `Sources/WhatCableDarwinBackend/Watchers/AppleHPMInterfaceWatcher.swift`,
// which cites these figures as the reason the positional fallback stays a
// fallback.
//
// TWO DELTAS AGAINST THE RESEARCH REGISTER, both understood, recorded here so a
// future reader does not go hunting for a broken parser:
//
//   - This file counts about 3002 records where the register quotes 3000, and
//     its M4 folder denominator is one higher (102 vs 101). `corpus.jsonl`
//     records chip `?` on five probe-36 folders, one of them M4, so a
//     corpus.jsonl-driven parser buckets those differently. This sweep takes
//     the chip from probe 36's own `chip` field instead.
//   - The register's parser A matched `HPM-UUID=(\S+)`, which cannot match the
//     empty UUID on `m2_macos27.0_i`, so it dropped that folder's two rows.
//
// The disagreement figures themselves are identical on every route.
//
// EMPTY-CORPUS BEHAVIOUR: if `research/customer-probes` is absent (a fresh
// clone or a worktree where `scripts/link-research.sh` has not been run, and
// the public mirror, where the corpus never exists) the sweep prints one loud
// line and returns without asserting. `scripts/ci.sh` carries the
// corpus-presence check that fails loudly for a local run in that state. In
// EVERY other case the sweep fails rather than passing quietly: if the
// directory is there but the record count is under the floor, that is a parser
// regression, not corpus churn, and it goes red.
@Suite("xHCI usb-c-port-number vs HPM Port-USB-C@N disagreement sweep (probe 36)")
struct HPMPortNumberDisagreementCorpusSweepTests {

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

    /// Probe 36 carries the chip string alongside the dump, so this sweep reads
    /// both from the one file rather than joining to `corpus.jsonl` (see the
    /// register-delta note in the header).
    private static func loadProbe(folder: String, fileName: String) -> (text: String, chip: String)? {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return (text: text, chip: (root["chip"] as? String) ?? "")
    }

    // MARK: - Chip family

    /// `"Apple M4 Pro"` -> `"M4 Pro"`, `"Apple M1"` -> `"M1"`, anything Intel ->
    /// `"Intel"`. Families are what the disagreement sorts by: the swap is a
    /// base-M1 trait and the skip a base-M4/M5 one, and the Pro/Max/Ultra dies
    /// of the same generation do neither.
    static func chipFamily(_ raw: String) -> String {
        var chip = raw.trimmingCharacters(in: .whitespaces)
        if chip.hasPrefix("Apple ") { chip = String(chip.dropFirst("Apple ".count)) }
        if chip.hasPrefix("Intel") { return "Intel" }

        var scalars = Array(chip)
        guard let first = scalars.first, first == "M" || first == "A" else { return chip }

        var index = 1
        while index < scalars.count, scalars[index].isNumber { index += 1 }
        guard index > 1 else { return chip }
        // M-series takes a single digit (M1..M5); A-series takes the whole run
        // (A18 Pro).
        if first == "M" { index = 2 }
        var family = String(scalars[0..<index])

        let rest = String(scalars[index...])
        for suffix in [" Pro", " Max", " Ultra"] where rest.hasPrefix(suffix) {
            if first == "A" && suffix != " Pro" { continue }
            family += suffix
            break
        }
        return family
    }

    // MARK: - Probe 36 parsing
    //
    // Two sections matter, and they are keyed on the same xHCI node name:
    //
    //   usb-drd1-port-ss         usb-c-port-number=1  locationID=18874368 (0x1200000)
    //
    // and, under the per-record ancestor-join heading,
    //
    //   usb-drd1-port-ss         UsbIOPort=IOService:/.../AppleHPMDevice@3F/Port-USB-C@2
    //
    // Folders whose probe build predates the join section print no heading at
    // all and contribute nothing. Where the section is present but a path reads
    // `(none)` (every macOS 14/15 folder that has one) no port name resolves,
    // so those contribute nothing either.

    private static let joinHeading = "=== XHCI port -> HPM UUID via UsbIOPort (per-record ancestor join) ==="

    /// xHCI node name -> published `usb-c-port-number`. Negative values (`-1`)
    /// are kept here and filtered by the caller, which counts them separately:
    /// there is no number to disagree with.
    private static func parsePortNumbers(_ text: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let range = line.range(of: "usb-c-port-number="),
                  let node = line.split(separator: " ").first
            else { continue }
            let rest = line[range.upperBound...]
            let negative = rest.hasPrefix("-")
            let digits = rest.dropFirst(negative ? 1 : 0).prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else { continue }
            result[String(node)] = negative ? -value : value
        }
        return result
    }

    /// xHCI node name -> the `UsbIOPort` registry path published on it.
    private static func parseUsbIOPortPaths(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let range = line.range(of: "UsbIOPort="),
                  let node = line.split(separator: " ").first
            else { continue }
            let path = line[range.upperBound...].prefix { !$0.isWhitespace }
            guard !path.isEmpty else { continue }
            result[String(node)] = String(path)
        }
        return result
    }

    /// The `N` in a `Port-USB-C@N` tail, via the SHIPPED path parser.
    ///
    /// Deliberately runs `USBWatcher.portName(fromUSBIOPortPath:)` rather than
    /// splitting the path inline. An inline private splitter here would prove
    /// the corpus fact while testing none of the code, so breaking the shipped
    /// path parse (the very thing this sweep exists to protect) would leave the
    /// sweep green.
    private static func hpmPortIndex(fromUSBIOPortPath path: String) -> Int? {
        guard let name = USBWatcher.portName(fromUSBIOPortPath: path),
              let at = name.range(of: "@"),
              name.hasPrefix("Port-USB-C@")
        else { return nil }
        let digits = name[at.upperBound...]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(digits)
    }

    // MARK: - The sweep

    @Test("usb-c-port-number and Port-USB-C@N disagree in exactly two shapes, on exactly three families")
    func portNumberDisagreementsAreTwoKnownShapes() {
        guard FileManager.default.fileExists(atPath: Self.probeRoot.path) else {
            print("[HPMPortNumberDisagreementSweep] SKIPPED: no corpus at \(Self.probeRoot.path). "
                + "Run scripts/link-research.sh in this checkout to sweep for real.")
            return
        }

        var records = 0
        var negativePortNumbers = 0
        var foldersWithProbe = 0
        var foldersWithJoinSection = 0

        var disagreementsByFamily: [String: Int] = [:]
        var recordsByFamily: [String: Int] = [:]
        var pairsByFamily: [String: [String: Int]] = [:]
        var disagreeingFoldersByFamily: [String: Set<String>] = [:]
        var examples: [String] = []

        for folder in Self.allProbeFolders() {
            guard let probe = Self.loadProbe(folder: folder, fileName: "36_xhci_port_map.json") else { continue }
            foldersWithProbe += 1

            let family = Self.chipFamily(probe.chip)
            // Split on the join heading so a `UsbIOPort=` string appearing
            // anywhere above it cannot be mistaken for a join record, and so
            // that dumps from a probe build predating the join section
            // contribute nothing rather than half a record.
            guard let headingRange = probe.text.range(of: Self.joinHeading) else { continue }
            foldersWithJoinSection += 1

            let numbers = Self.parsePortNumbers(String(probe.text[..<headingRange.lowerBound]))
            let paths = Self.parseUsbIOPortPaths(String(probe.text[headingRange.upperBound...]))

            for (node, usbNumber) in numbers.sorted(by: { $0.key < $1.key }) {
                // Sign guard first, on purpose: counting negatives after the
                // path lookup under-reported them by 39, because a port with
                // `usb-c-port-number=-1` and `UsbIOPort=(none)` was dropped
                // before it could be counted. This counter now means every
                // negative-numbered port in a folder carrying the join section,
                // resolvable path or not.
                guard usbNumber >= 0 else { negativePortNumbers += 1; continue }
                guard let path = paths[node], let atN = Self.hpmPortIndex(fromUSBIOPortPath: path) else { continue }

                records += 1
                recordsByFamily[family, default: 0] += 1
                guard usbNumber != atN else { continue }

                disagreementsByFamily[family, default: 0] += 1
                pairsByFamily[family, default: [:]]["(\(usbNumber), \(atN))", default: 0] += 1
                disagreeingFoldersByFamily[family, default: []].insert(folder)
                if examples.count < 5 {
                    examples.append("\(folder) [\(family)]: \(node) usb-c-port-number=\(usbNumber) but path ends @\(atN)")
                }
            }
        }

        let totalDisagreements = disagreementsByFamily.values.reduce(0, +)
        print("[HPMPortNumberDisagreementSweep] \(foldersWithProbe) folders hold probe 36, "
            + "\(foldersWithJoinSection) of them from a probe build that emits the UsbIOPort "
            + "join section (a probe-version split, not an OS one). "
            + "\(records) records with a real usb-c-port-number and a resolvable @N "
            + "(\(negativePortNumbers) more ports published a negative usb-c-port-number and "
            + "were excluded before any path lookup). \(totalDisagreements) disagreements.")
        for family in disagreementsByFamily.keys.sorted() {
            let pairs = (pairsByFamily[family] ?? [:]).sorted { $0.key < $1.key }
                .map { "\($0.key) x\($0.value)" }.joined(separator: ", ")
            print("[HPMPortNumberDisagreementSweep]   \(family): \(disagreementsByFamily[family] ?? 0) of "
                + "\(recordsByFamily[family] ?? 0) records disagree, across "
                + "\(disagreeingFoldersByFamily[family]?.count ?? 0) folders. Pairs: \(pairs)")
        }
        for example in examples { print("[HPMPortNumberDisagreementSweep]   e.g. \(example)") }

        // 1. Coverage floor. The corpus as it stands supports about 3002
        //    records; the floor sits well under that so growth is fine, while a
        //    parser regression that silently stops finding records goes red.
        #expect(records >= 2500,
            "only \(records) joinable records found; the corpus supports about 3002, so the parsers or the probe shape have changed")

        // 2 and 3. Exactly three families disagree at all, and they are the base
        //    M1, M4 and M5 dies. Any other family showing up here is a NEW
        //    numbering quirk and must be looked at before this test is relaxed.
        let disagreeingFamilies = Set(disagreementsByFamily.filter { $0.value > 0 }.keys)
        let expectedFamilies: Set<String> = ["M1", "M4", "M5"]
        let unexpected = disagreeingFamilies.subtracting(expectedFamilies).sorted()
        let fullTally = disagreementsByFamily.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        #expect(unexpected.isEmpty,
            "families outside the known set now disagree: \(unexpected.joined(separator: ", ")). Full tally: \(fullTally)")
        #expect(disagreeingFamilies == expectedFamilies,
            "expected exactly \(expectedFamilies.sorted()) to disagree, got \(disagreeingFamilies.sorted())")

        // 4. M1 is a straight swap of ports 1 and 2, both directions.
        #expect(Set((pairsByFamily["M1"] ?? [:]).keys) == ["(1, 2)", "(2, 1)"],
            "M1 disagreement shapes changed: \((pairsByFamily["M1"] ?? [:]).sorted { $0.key < $1.key })")

        // 5. M4 and M5 skip @3, so USB 3 lands on @4. One shape, one direction.
        #expect(Set((pairsByFamily["M4"] ?? [:]).keys) == ["(3, 4)"],
            "M4 disagreement shapes changed: \((pairsByFamily["M4"] ?? [:]).sorted { $0.key < $1.key })")
        #expect(Set((pairsByFamily["M5"] ?? [:]).keys) == ["(3, 4)"],
            "M5 disagreement shapes changed: \((pairsByFamily["M5"] ?? [:]).sorted { $0.key < $1.key })")

        // 6. Each family still actually disagrees. Measured today: M1 32
        //    (16 each way), M4 76, M5 44. Floors sit comfortably below so corpus
        //    growth cannot fail the build, while a family quietly dropping out
        //    of the sample does.
        #expect((disagreementsByFamily["M1"] ?? 0) >= 20,
            "M1 disagreements fell to \(disagreementsByFamily["M1"] ?? 0); the corpus supports 32 (16 each way)")
        #expect((disagreementsByFamily["M4"] ?? 0) >= 50,
            "M4 disagreements fell to \(disagreementsByFamily["M4"] ?? 0); the corpus supports 76")
        #expect((disagreementsByFamily["M5"] ?? 0) >= 30,
            "M5 disagreements fell to \(disagreementsByFamily["M5"] ?? 0); the corpus supports 44")

        // 7. Distinct folders holding at least one disagreement: M1 8, M4 38,
        //    M5 22 today. Printed above, deliberately not asserted tightly: the
        //    folder count moves with every ingest, and the shapes are what this
        //    sweep is guarding.
    }
}
