import Foundation
import Testing
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

// MARK: - AppleUVDMCorpusSweepTests
//
// Corpus-replay tests for `AppleUVDMWatcher.makeAccessoryIdentity`, proving
// the `AppleAccessoryIdentity.displayName` rule against every
// `IOPortTransportProtocolAppleUVDM` node in `research/customer-probes/`.
// This is the feature's only evidence of real hardware behaviour: there is
// no unit test that can stand in for a corpus this shaped.
//
// Modelled on `TransportWatcherSweepTests.swift`: same corpus root
// resolution from `#filePath`, same folder enumeration, same
// skip-rather-than-fail guard when the raw corpus is absent.
@Suite("AppleUVDMWatcher.makeAccessoryIdentity -- customer probe sweep")
struct AppleUVDMCorpusSweepTests {

    // MARK: - Corpus root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // MARK: - Folder enumeration

    private static func allProbeFolders() -> [String] {
        guard let entries = try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path) else { return [] }
        return entries.filter { entry in
            var isDir: ObjCBool = false
            let path = probeRoot.appendingPathComponent(entry).path
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted()
    }

    /// True once at least one folder on disk actually carries probe 17. A
    /// fresh clone (or a worktree that hasn't run `scripts/link-research.sh`)
    /// enumerates zero folders, so this is false there.
    private static func hasUVDMProbeFiles() -> Bool {
        for folder in allProbeFolders() {
            let url = probeRoot
                .appendingPathComponent(folder)
                .appendingPathComponent("17_deep_property_dump.json")
            if FileManager.default.fileExists(atPath: url.path) { return true }
        }
        return false
    }

    // MARK: - JSON probe loader

    private static func loadProbeText(folder: String) -> String? {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("17_deep_property_dump.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - UVDM node parser
    //
    // Probe 17 prints each `IOPortTransportProtocolAppleUVDM` node as a
    // header indented exactly 6 spaces, with its own properties at 8 spaces.
    // `AppleUVDMEndpoint` nests inside at 8 with its own properties at 10, so
    // a depth filter of "exactly 8 spaces" walks past it untouched: its
    // `=== AppleUVDMEndpoint ===` header line has no ": " so the key/value
    // split below skips it the same way it skips a closing "}".
    //
    // `parseEqualsBlocks` in TransportWatcherSweepTests cannot be reused
    // here. Two nodes in the corpus (m4_macos26.5.2_ac, m4max_macos26.6_b)
    // have a raw newline byte inside a quoted Serial Number value, so the
    // value spans two physical lines and the second is not indented at all.
    // Ending the block at the first line indented less than 8 -- what
    // `parseEqualsBlocks` does -- truncates those two nodes and silently
    // drops every property after the serial. Measured: an indentation-walk
    // parser reports 91 nodes carrying a Vendor ID; this parser reports 93.

    private static let headerLine = "      === IOPortTransportProtocolAppleUVDM ==="

    /// Parse every UVDM node's property dict out of one probe 17 text dump.
    private static func parseUVDMBlocks(text: String) -> [[String: Any]] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [[String: Any]] = []
        var i = 0
        while i < lines.count {
            guard lines[i] == headerLine else { i += 1; continue }
            i += 1
            var props: [String: Any] = [:]
            while i < lines.count {
                let line = lines[i]
                if line.hasPrefix("         ") { i += 1; continue }   // 9+ spaces: nested, skip
                guard line.hasPrefix("        ") else { break }       // < 8 spaces: block ends

                let stripped = String(line.dropFirst(8))
                guard let colonRange = stripped.range(of: ": ") else { i += 1; continue }
                let key = String(stripped[..<colonRange.lowerBound])
                var valStr = String(stripped[colonRange.upperBound...])

                if valStr.hasPrefix("\""), !valStr.hasSuffix("\"") {
                    // Multi-line value: the value opened a quote but did not
                    // close it on this line. Keep consuming raw lines
                    // (regardless of their own indentation) until one ends
                    // with a quote, then strip the outer quotes from the
                    // joined result. This is the newline-in-Serial-Number
                    // trap documented above.
                    i += 1
                    while i < lines.count, !lines[i].hasSuffix("\"") {
                        valStr += "\n" + lines[i]
                        i += 1
                    }
                    if i < lines.count {
                        valStr += "\n" + lines[i]
                        i += 1
                    }
                    props[key] = String(valStr.dropFirst().dropLast())
                    continue
                }

                props[key] = decodeValue(valStr)
                i += 1
            }
            blocks.append(props)
        }
        return blocks
    }

    /// `N (0xHEX)` and bare integers become `Int`, `"quoted"` becomes
    /// `String` with the quotes stripped, `true` / `false` become `Bool`.
    /// Matches what the watcher's `read` closure hands
    /// `makeAccessoryIdentity`. Anything else (nested dicts, `<CFType N>`)
    /// is left unrecognised and the assignment at the call site is a no-op.
    private static func decodeValue(_ s: String) -> Any? {
        if s == "true" { return true }
        if s == "false" { return false }
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
            return String(s.dropFirst().dropLast())
        }
        if let spaceIdx = s.firstIndex(of: " "), let v = Int(s[..<spaceIdx]) {
            return v
        }
        return Int(s)
    }

    // MARK: - One full sweep, shared by every test below

    private struct SweepNode {
        let folder: String
        let props: [String: Any]
        let identity: AppleAccessoryIdentity?
    }

    private struct SweepResult {
        let foldersWithProbe17: Int
        let nodes: [SweepNode]
    }

    private static func sweep() -> SweepResult {
        let folders = allProbeFolders()
        var foldersWithProbe17 = 0
        var nodes: [SweepNode] = []
        var syntheticID: UInt64 = 0

        for folder in folders {
            guard let text = loadProbeText(folder: folder) else { continue }
            foldersWithProbe17 += 1
            for props in parseUVDMBlocks(text: text) {
                syntheticID += 1
                let read: (String) -> Any? = { props[$0] }
                let identity = AppleUVDMWatcher.makeAccessoryIdentity(
                    entryID: syntheticID, read: read, hpmControllerUUID: nil)
                nodes.append(SweepNode(folder: folder, props: props, identity: identity))
            }
        }
        return SweepResult(foldersWithProbe17: foldersWithProbe17, nodes: nodes)
    }

    // MARK: - Tests

    @Test("Corpus coverage: probe 17 folders, UVDM node count, and the newline-trap Vendor ID floor")
    func corpusCoverageAndVendorIDFloor() {
        guard Self.hasUVDMProbeFiles() else {
            print("[AppleUVDMCorpusSweep] SKIP: no customer-probe corpus at \(Self.probeRoot.path). "
                + "Run scripts/link-research.sh to link it, or this sweep tests nothing.")
            return
        }

        let result = Self.sweep()
        let distinctFolders = Set(result.nodes.map(\.folder))
        let vendorIDCount = result.nodes.filter { $0.props["Vendor ID"] != nil }.count

        // The corpus only grows, so these are floors, not exact counts.
        #expect(result.foldersWithProbe17 >= 1300,
            "Expected at least 1300 folders carrying probe 17; got \(result.foldersWithProbe17)")
        #expect(result.nodes.count >= 126,
            "Expected at least 126 UVDM nodes parsed; got \(result.nodes.count)")
        #expect(distinctFolders.count >= 118,
            "Expected UVDM nodes on at least 118 distinct folders; got \(distinctFolders.count)")
        // This is the count that catches the newline-in-Serial-Number trap:
        // an indentation-walk parser stops at 91, this parser reaches 93.
        #expect(vendorIDCount >= 93,
            "Expected at least 93 nodes publishing a Vendor ID; got \(vendorIDCount) -- a regression here likely means the multi-line value handling broke")

        print("[AppleUVDMCorpusSweep] \(result.foldersWithProbe17) folders with probe 17, "
            + "\(result.nodes.count) UVDM nodes on \(distinctFolders.count) folders, "
            + "\(vendorIDCount) nodes with a Vendor ID")
    }

    @Test("displayName rule: floors and hard invariants hold across every corpus node")
    func displayNameRuleHoldsAcrossCorpus() {
        guard Self.hasUVDMProbeFiles() else {
            print("[AppleUVDMCorpusSweep] SKIP: no customer-probe corpus at \(Self.probeRoot.path). "
                + "Run scripts/link-research.sh to link it, or this sweep tests nothing.")
            return
        }

        let result = Self.sweep()
        var nonNilDisplayNames = 0
        var fromUserString = 0
        var distinctUserStringNames: Set<String> = []
        var namesSeen: Set<String> = []
        let requiredNames: Set<String> = [
            "Studio Display", "iPhone", "iPad", "Macintosh", "Display",
            "Vision Pro Battery", "DevBand",
        ]
        var rawUserStringsWithWhitespace = 0

        for node in result.nodes {
            if let us = node.props["User String"] as? String,
               us != us.trimmingCharacters(in: .whitespacesAndNewlines) {
                rawUserStringsWithWhitespace += 1
            }

            guard let name = node.identity?.displayName else { continue }
            nonNilDisplayNames += 1
            namesSeen.insert(name)

            // Hard invariants of the display rule: none of these placeholder
            // or corrupt shapes may ever surface as a name.
            #expect(name != "EV", "Probe \(node.folder): displayName should never be the EV placeholder")
            // Vacuous against today's corpus, and kept deliberately: every
            // node with `Product == "0"` also carries a `User String`, so the
            // userString branch returns before the "0" guard is consulted and
            // no node can reach this expectation with that value. It holds the
            // line for a future node that carries one without the other.
            #expect(name != "0", "Probe \(node.folder): displayName should never be the \"0\" placeholder")
            // Forward-looking guard, not this sweep's evidence: no corpus
            // `Product` or `User String` carries a control byte today (only
            // the serials do), so deleting the control-character check from
            // `isDisplayable` leaves this sweep green. The check itself is
            // covered by
            // `AppleAccessoryIdentityTests`, "a userString containing a
            // control character gives nil". This line catches the day a probe
            // arrives carrying one.
            #expect(name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) },
                "Probe \(node.folder): displayName \(name.debugDescription) contains a control character")
            #expect(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Probe \(node.folder): displayName should never be empty or whitespace-only")
            #expect(name.count <= 64,
                "Probe \(node.folder): displayName \(name.debugDescription) is \(name.count) characters, over the 64 limit")

            if let us = node.props["User String"] as? String {
                let trimmed = us.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed == name {
                    fromUserString += 1
                    distinctUserStringNames.insert(name)
                    // Sourced from User String: never leading/trailing
                    // whitespace, even though some raw corpus values carry a
                    // trailing space inside the quotes.
                    #expect(name == name.trimmingCharacters(in: .whitespacesAndNewlines),
                        "Probe \(node.folder): displayName \(name.debugDescription) sourced from User String should carry no leading/trailing whitespace")
                }
            }
        }

        // Corpus-growth floors.
        #expect(nonNilDisplayNames >= 104,
            "Expected at least 104 non-nil displayName values; got \(nonNilDisplayNames)")
        #expect(fromUserString >= 33,
            "Expected at least 33 displayName values sourced from User String; got \(fromUserString)")
        #expect(distinctUserStringNames.count >= 9,
            "Expected at least 9 distinct power-adapter names from User String; got \(distinctUserStringNames.count)")
        // Not a hard invariant (a future submission could arrive with every
        // User String value already trimmed), but a floor keeps this check
        // from being vacuously true: at least some raw corpus values must
        // actually carry the whitespace the trim above is proving it strips.
        #expect(rawUserStringsWithWhitespace >= 7,
            "Expected at least 7 raw User String values with leading/trailing whitespace; got \(rawUserStringsWithWhitespace)")

        for required in requiredNames {
            #expect(namesSeen.contains(required),
                "Expected \(required.debugDescription) to appear as a displayName somewhere in the corpus")
        }

        print("[AppleUVDMCorpusSweep] \(nonNilDisplayNames) non-nil displayName values, "
            + "\(fromUserString) from User String (\(distinctUserStringNames.count) distinct), "
            + "\(rawUserStringsWithWhitespace) raw User String values with whitespace")
    }

    @Test("Vendor ID is Apple-only across every UVDM node in the corpus")
    func vendorIDIsAppleOnly() {
        guard Self.hasUVDMProbeFiles() else {
            print("[AppleUVDMCorpusSweep] SKIP: no customer-probe corpus at \(Self.probeRoot.path). "
                + "Run scripts/link-research.sh to link it, or this sweep tests nothing.")
            return
        }

        let result = Self.sweep()
        var distinctVendorIDs: Set<Int> = []
        for node in result.nodes {
            guard let vendorID = node.props["Vendor ID"] as? Int else { continue }
            distinctVendorIDs.insert(vendorID)
        }

        // Hard invariant: Apple-only is a load-bearing claim in the ticket.
        #expect(distinctVendorIDs == [0x05AC],
            "Expected every Vendor ID in the corpus to be 0x05AC (1452); got \(distinctVendorIDs)")
    }

    @Test("Identifiers are never dropped: control-byte serials stay byte-identical, EV nodes stay on the model without a name")
    func identifiersAreNeverDropped() {
        guard Self.hasUVDMProbeFiles() else {
            print("[AppleUVDMCorpusSweep] SKIP: no customer-probe corpus at \(Self.probeRoot.path). "
                + "Run scripts/link-research.sh to link it, or this sweep tests nothing.")
            return
        }

        let result = Self.sweep()

        // Serial numbers carrying a control byte: kept exactly as read, and
        // the corruption never propagates into displayName (which never
        // reads serialNumber at all -- the invariants proven for every node
        // in displayNameRuleHoldsAcrossCorpus already cover these nodes too).
        var controlByteSerialCount = 0
        for node in result.nodes {
            guard let rawSerial = node.props["Serial Number"] as? String,
                  rawSerial.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { continue }
            controlByteSerialCount += 1

            #expect(node.identity != nil,
                "Probe \(node.folder): a node with a control-byte serial should still produce an identity")
            #expect(node.identity?.serialNumber == rawSerial,
                "Probe \(node.folder): serialNumber should be byte-identical to the parsed input")
        }
        #expect(controlByteSerialCount >= 9,
            "Expected at least 9 nodes with a control byte in Serial Number; got \(controlByteSerialCount)")

        // The engineering-validation accessory: floor because the corpus
        // only grows, but every node found must match the fixed shape
        // exactly (that fixed shape is the hard invariant).
        var evCount = 0
        for node in result.nodes where node.props["Product"] as? String == "EV" {
            evCount += 1
            #expect(node.props["Serial Number"] as? String == "1234567890",
                "Probe \(node.folder): EV node should carry serial 1234567890")
            #expect(node.props["Product ID"] as? Int == 0x1657,
                "Probe \(node.folder): EV node should carry Product ID 0x1657")
            #expect(node.identity != nil,
                "Probe \(node.folder): EV node should still be kept on the model")
            #expect(node.identity?.displayName == nil,
                "Probe \(node.folder): EV node should never produce a displayName")
        }
        #expect(evCount >= 11, "Expected at least 11 EV nodes; got \(evCount)")

        print("[AppleUVDMCorpusSweep] \(controlByteSerialCount) nodes with a control-byte serial, "
            + "\(evCount) EV nodes")
    }
}
