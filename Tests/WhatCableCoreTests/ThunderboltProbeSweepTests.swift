import Foundation
import Testing
@testable import WhatCableCore

/// Corpus-replay tests for Thunderbolt switch and port parsing (DAR-77).
///
/// Two sources of coverage here:
///
/// 1. Fixture tests (always run): hand-crafted dictionaries transcribed from
///    real `whatcable --tb-debug` paste-backs. Cover the full round-trip from
///    raw `[String: Any]` through `IOThunderboltSwitch.from` and
///    `IOThunderboltPort.from` to model values.
///
/// 2. Corpus sweep (runs only when probe 29 files are on disk): sweeps every
///    `research/customer-probes/<folder>/29_usb4_router_interfaces.json` file
///    and asserts model properties against the raw text. Passes trivially on a
///    fresh clone where probe 29 has not been fetched from KV.
///
/// Probe 29 output format:
///   Top-level sections: "=== ClassName ===" followed by instance blocks
///   "--- ClassName[N] \"<name>\" ---". IOThunderboltSwitch and
///   IOThunderboltPort appear in separate top-level sections (ports are NOT
///   nested inside switch blocks). Key-value lines use "  KEY =     N (0xHEX)"
///   with multiple spaces between "=" and the value. String values appear as
///   "  KEY =     \"value\"".
@Suite("Thunderbolt probe sweep (DAR-77)")
struct ThunderboltProbeSweepTests {

    // MARK: - Probe root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    /// The two corpus pairs carrying an asymmetric TB5 lane, measured
    /// 2026-09-11. Add a new pair here when one lands, so the asymmetric
    /// sweep keeps requiring a real hit rather than passing on an empty set.
    private static let knownAsymmetricFolders = ["m4max_macos26.5.2_f", "m5max_macos26.5.1"]

    // MARK: - Known link-speed codes (from IOThunderboltLink.swift)

    /// All speed codes the code can label. Any value outside this set
    /// goes to `.unknown`; the test asserts that branch too.
    private static let knownSpeedCodes: Set<UInt8> = [0x0, 0x8, 0x4, 0x2]

    // MARK: - Corpus helpers

    private static func allProbes() throws -> [String] {
        guard FileManager.default.fileExists(atPath: probeRoot.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path)
            .filter { entry in
                var isDir: ObjCBool = false
                let path = probeRoot.appendingPathComponent(entry).path
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                return isDir.boolValue
            }
            .sorted()
    }

    /// Load text from a probe-29 JSON file. Returns nil if the file does not
    /// exist (fresh clone where KV data has not been fetched).
    private static func loadProbe29(folder: String) throws -> String? {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("29_usb4_router_interfaces.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Probe-29 text parsers

    /// Extract instance blocks for a given IOKit class from probe-29 output.
    /// Probe 29 uses "--- ClassName[N] \"name\" ---" instance headers inside
    /// "=== ClassName ===" top-level sections. Blocks run from one instance
    /// header to the next or to the next "===" section header.
    private static func parseInstanceBlocks(_ text: String, className: String)
        -> [(header: String, body: String)]
    {
        var results: [(header: String, body: String)] = []
        let lines = text.components(separatedBy: "\n")
        var currentHeader: String? = nil
        var currentBody: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--- \(className)") && trimmed.hasSuffix("---") {
                if let h = currentHeader {
                    results.append((h, currentBody.joined(separator: "\n")))
                }
                currentHeader = trimmed
                currentBody = []
            } else if trimmed.hasPrefix("=== ") && trimmed.hasSuffix(" ===") {
                // New top-level section: close any open block.
                if let h = currentHeader {
                    results.append((h, currentBody.joined(separator: "\n")))
                    currentHeader = nil
                    currentBody = []
                }
            } else if currentHeader != nil {
                currentBody.append(line)
            }
        }
        if let h = currentHeader {
            results.append((h, currentBody.joined(separator: "\n")))
        }
        return results
    }

    /// Everything after `key`'s `" = "` separator on one probe-29 line, or
    /// nil when the key is not on it.
    ///
    /// The key is looked for anywhere on the line, not only at its start:
    /// probe 29 prints an empty `Hop Table` with no trailing newline, so
    /// the key that follows shares the physical line
    /// ("  Hop Table =   Thunderbolt Version =     32 (0x20)"). Matching on
    /// the line prefix dropped that key silently, in 1319 of 1336 corpus
    /// folders.
    ///
    /// A free-floating match would then read `Port RID` out of
    /// `Dual-Link Port RID`, so the whitespace run before the match has to
    /// reach the start of the line or be at least two characters wide:
    /// a real key is either indented by two spaces or follows an earlier
    /// `=` and its padding, while the tail of a longer key name has exactly
    /// one space in front of it.
    private static func valuePart(_ line: String, key: String) -> Substring? {
        let needle = "\(key) = "
        var searchStart = line.startIndex
        while let range = line.range(of: needle, range: searchStart..<line.endIndex) {
            searchStart = min(line.index(after: range.lowerBound), line.endIndex)
            var spaces = 0
            var cursor = range.lowerBound
            while cursor > line.startIndex {
                let previous = line.index(before: cursor)
                guard line[previous] == " " else { break }
                spaces += 1
                cursor = previous
            }
            guard cursor == line.startIndex || spaces >= 2 else { continue }
            return line[range.upperBound...]
        }
        return nil
    }

    /// Parse an integer from a probe-29 body line.
    /// Real format: "  KEY =     N (0xHEX)" - note multiple spaces between "=" and N.
    private static func parseIntLine(_ body: String, key: String) -> Int? {
        for line in body.components(separatedBy: "\n") {
            guard let after = valuePart(line, key: key)?.drop(while: { $0 == " " }) else { continue }
            let digits = after.prefix { $0.isNumber || $0 == "-" }
            if let v = Int(digits) { return v }
        }
        return nil
    }

    /// Parse a quoted string from a probe-29 body line.
    /// Real format: "  KEY =     \"value\"" - note multiple spaces between "=" and quote.
    private static func parseStringLine(_ body: String, key: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            guard let after = valuePart(line, key: key)?.drop(while: { $0 == " " }),
                  after.hasPrefix("\"") else { continue }
            let inner = after.dropFirst()
            if let close = inner.firstIndex(of: "\"") {
                return String(inner[..<close])
            }
        }
        return nil
    }

    /// Build a `read` closure from a probe-29 switch body block. Only reads
    /// the numeric and string keys that `IOThunderboltSwitch.from` and
    /// `IOThunderboltPort.from` access; other keys return nil (fine, they
    /// are optional in the model).
    private static func makeReadClosure(body: String) -> (String) -> Any? {
        { key in
            if let s = parseStringLine(body, key: key) { return s as Any }
            if let n = parseIntLine(body, key: key) { return NSNumber(value: n) }
            return nil
        }
    }

    // MARK: - Sweep test

    @Test("Corpus sweep: probe-29 switch and port blocks parse without crashing")
    func probe29SweepParsesWithoutCrashing() throws {
        let folders = try Self.allProbes()
        // Corpus minimum guard: only enforced when at least one probe-29 file
        // exists. On a fresh clone all files are absent and the sweep
        // trivially skips.
        //
        // Probe-29 structure: IOThunderboltSwitch and IOThunderboltPort appear
        // in separate top-level "=== ClassName ===" sections. Ports are NOT
        // nested inside switch blocks; each section is parsed independently.
        var switchesParsed = 0
        var portsParsed = 0
        var foldersWithProbe29 = 0

        for folder in folders {
            guard let text = try Self.loadProbe29(folder: folder) else { continue }
            foldersWithProbe29 += 1

            // Parse IOThunderboltSwitch instances from the switch section.
            let switchBlocks = Self.parseInstanceBlocks(text, className: "IOThunderboltSwitch")
            for (_, body) in switchBlocks {
                let read = Self.makeReadClosure(body: body)
                // UIDs in probe-29 are reported as "N (0xHEX)". We parse the
                // decimal as the uid. If no UID line, use 0 as sentinel.
                let uid = Self.parseIntLine(body, key: "UID").map(Int64.init) ?? 0

                if let sw = IOThunderboltSwitch.from(
                    uid: uid,
                    read: read,
                    className: "IOThunderboltSwitch",
                    ports: [],       // ports are in a separate section
                    parentSwitchUID: nil
                ) {
                    switchesParsed += 1

                    // UID must round-trip; depth must be non-negative.
                    #expect(sw.id == uid,
                        "Folder \(folder): TB switch UID did not round-trip, stored \(sw.id), expected \(uid)")
                    #expect(sw.depth >= 0,
                        "Folder \(folder): depth must be non-negative, got \(sw.depth)")
                    _ = sw.vendorName
                    _ = sw.modelName
                }
            }

            // Parse IOThunderboltPort instances from the port section.
            let portBlocks = Self.parseInstanceBlocks(text, className: "IOThunderboltPort")
            for (_, body) in portBlocks {
                let read = Self.makeReadClosure(body: body)
                if let port = IOThunderboltPort.from(read: read) {
                    portsParsed += 1

                    if port.adapterType.isLane {
                        if let speed = port.currentSpeed {
                            switch speed {
                            case .tb3, .usb4Tb4, .tb5:
                                let gbps = speed.perLaneGbps ?? 0
                                #expect(gbps > 0,
                                    "Folder \(folder): known speed code must have positive per-lane Gbps, got \(gbps)")
                            case .unknown:
                                break
                            }
                        }
                        #expect(port.portNumber > 0,
                            "Folder \(folder): parsed lane port has portNumber \(port.portNumber)")
                    }
                }
            }
        }

        // Only assert minimums when files were actually found.
        if foldersWithProbe29 > 0 {
            // Expect at least 1 switch per folder (the host controller is always present).
            #expect(switchesParsed >= foldersWithProbe29,
                "Expected at least \(foldersWithProbe29) switches from \(foldersWithProbe29) probe-29 files; parsed \(switchesParsed)")
            // Expect at least 1 port per folder (every machine has at least one USB-C port).
            #expect(portsParsed >= foldersWithProbe29,
                "Expected at least \(foldersWithProbe29) ports from \(foldersWithProbe29) probe-29 files; parsed \(portsParsed)")
        }
    }

    // MARK: - Rate sweep

    @Test("Corpus sweep: activeGbps x 10 equals Link Bandwidth on every symmetric lane link")
    func probe29SweepActiveRateMatchesLinkBandwidth() throws {
        // `Link Bandwidth` is per-lane Gbps x lanes x 10, so it is the
        // corpus's own check on the width-aware rate. Records are skipped
        // when there is nothing to compare: an unknown speed code has no
        // per-lane figure, `Current Link Width` 0 means no lane is trained
        // (six records read a real speed code that way), and `Link
        // Bandwidth` 0 or absent is a field the firmware did not populate,
        // not a measured zero.
        var symmetricChecked = 0
        var asymmetricChecked = 0
        var foldersWithProbe29 = 0

        for folder in try Self.allProbes() {
            guard let text = try Self.loadProbe29(folder: folder) else { continue }
            foldersWithProbe29 += 1

            for (_, body) in Self.parseInstanceBlocks(text, className: "IOThunderboltPort") {
                guard let port = IOThunderboltPort.from(read: Self.makeReadClosure(body: body)),
                      port.adapterType.isLane,
                      let speed = port.currentSpeed,
                      let perLane = speed.perLaneGbps,
                      let width = port.currentWidth,
                      let bandwidth = port.linkBandwidthRaw,
                      bandwidth != 0
                else { continue }

                switch width.rawValue {
                case 0x1, 0x2:
                    symmetricChecked += 1
                    #expect(port.activeGbps.map { $0 * 10 } == Double(bandwidth),
                        """
                        Folder \(folder), port \(port.portNumber): activeGbps \
                        \(String(describing: port.activeGbps)) x 10 does not match \
                        Link Bandwidth \(bandwidth) (speed code per-lane \(perLane), \
                        width raw \(width.rawValue))
                        """)
                case 0x4, 0x8:
                    // The one place the two figures part company. On an
                    // asymmetric link `Link Bandwidth` follows the RX lanes,
                    // while `activeGbps` is deliberately TX-based, so an
                    // asymmetric TX link reads as the 3 lane figure the host
                    // is actually sending at. Both corpus records satisfy the
                    // identity against `rxLanes`.
                    asymmetricChecked += 1
                    #expect(Double(perLane * width.rxLanes * 10) == Double(bandwidth),
                        """
                        Folder \(folder), port \(port.portNumber): asymmetric \
                        Link Bandwidth \(bandwidth) does not match per-lane \(perLane) \
                        x rxLanes \(width.rxLanes) x 10
                        """)
                    // These two records are the only place in the corpus where
                    // TX and RX differ, so they are the only sweep evidence
                    // that the rate is the TX one the design asks for. Without
                    // this, an activeGbps switched to rxLanes sweeps green.
                    #expect(port.activeGbps == Double(perLane * width.txLanes),
                        """
                        Folder \(folder), port \(port.portNumber): activeGbps \
                        \(String(describing: port.activeGbps)) is not the TX figure \
                        per-lane \(perLane) x txLanes \(width.txLanes)
                        """)
                default:
                    continue
                }
            }
        }

        guard foldersWithProbe29 > 0 else { return }
        print("""
            Rate sweep: \(symmetricChecked) symmetric and \(asymmetricChecked) \
            asymmetric lane records checked across \(foldersWithProbe29) folders.
            """)
        // A green run on an empty or half-parsed corpus proves nothing, so
        // the record count is asserted too. 6546 at the corpus size this was
        // written against, over the 1336 folders that carry a probe-29 file.
        #expect(symmetricChecked > 5000,
            "Expected over 5000 symmetric lane records to compare; checked \(symmetricChecked)")
        // Only 2 asymmetric records carry a non-zero Link Bandwidth today, so
        // this is a floor rather than a pin: asymmetric links are rare and
        // the count moves with any new TB5 submission.
        #expect(asymmetricChecked >= 2,
            "Expected at least 2 asymmetric lane records to compare; checked \(asymmetricChecked)")
    }

    // MARK: - Asymmetric label sweep

    @Test("Corpus sweep: every asymmetric lane renders one rate per direction on both ends")
    func probe29SweepAsymmetricLabelIsDirectionAware() throws {
        // Port-level only, deliberately not routed through ThunderboltTopology
        // or the switch tree: m5max_macos26.5.1's probe 29 is truncated at
        // 64 KB and carries no IOThunderboltSwitch section at all, so a
        // switch-based check would silently skip the one live sample.
        var records = 0
        var txSideCount = 0   // 0x4: 3 TX / 1 RX
        var rxSideCount = 0   // 0x8: 1 TX / 3 RX
        var foldersWithProbe29 = 0
        var perFolderCounts: [String: (tx: Int, rx: Int)] = [:]
        var foldersTouched: Set<String> = []

        for folder in try Self.allProbes() {
            guard let text = try Self.loadProbe29(folder: folder) else { continue }
            foldersWithProbe29 += 1

            for (_, body) in Self.parseInstanceBlocks(text, className: "IOThunderboltPort") {
                guard let port = IOThunderboltPort.from(read: Self.makeReadClosure(body: body)),
                      port.adapterType.isLane,
                      let speed = port.currentSpeed,
                      let perLane = speed.perLaneGbps,
                      let width = port.currentWidth,
                      width.rawValue == 0x4 || width.rawValue == 0x8
                else { continue }

                records += 1
                foldersTouched.insert(folder)
                let tx = perLane * width.txLanes
                let rx = perLane * width.rxLanes

                #expect(port.txGbps == Double(tx),
                    "Folder \(folder), port \(port.portNumber), width raw \(width.rawValue): txGbps \(String(describing: port.txGbps)) != \(tx)")
                #expect(port.rxGbps == Double(rx),
                    "Folder \(folder), port \(port.portNumber), width raw \(width.rawValue): rxGbps \(String(describing: port.rxGbps)) != \(rx)")
                #expect(ThunderboltLabels.linkLabel(for: port) == "Up to \(tx) Gb/s out, \(rx) Gb/s in",
                    "Folder \(folder), port \(port.portNumber), width raw \(width.rawValue): label is not one rate per direction")

                var counts = perFolderCounts[folder] ?? (tx: 0, rx: 0)
                if width.rawValue == 0x4 {
                    counts.tx += 1
                    txSideCount += 1
                } else {
                    counts.rx += 1
                    rxSideCount += 1
                }
                perFolderCounts[folder] = counts
            }
        }

        // Fresh clone, nothing to assert.
        guard foldersWithProbe29 > 0 else { return }

        print("""
            Asymmetric label sweep: \(records) asymmetric lane records \
            (\(txSideCount) at 3 TX / 1 RX, \(rxSideCount) at 1 TX / 3 RX) across \
            \(foldersTouched.count) folders: \(foldersTouched.sorted().joined(separator: ", ")).
            """)

        // Both corpus pairs carry both ends; a folder with one end only is a
        // parse regression or a new shape worth seeing. No minimum on the
        // totals: the samples are rare and the sweep must pass on a corpus
        // that has none.
        for folder in foldersTouched.sorted() {
            let counts = perFolderCounts[folder] ?? (tx: 0, rx: 0)
            #expect(counts.tx > 0,
                "Folder \(folder): expected at least one 3 TX / 1 RX (0x4) record; found \(counts.tx)")
            #expect(counts.rx > 0,
                "Folder \(folder): expected at least one 1 TX / 3 RX (0x8) record; found \(counts.rx)")
        }

        // The two corpus pairs measured on 2026-09-11. A folder existing but
        // missing from foldersTouched means its probe failed to load or
        // parsed to no asymmetric lane, which the "any probe29 exists"
        // guard above does not catch on its own. Add a new pair here when
        // one lands. A folder not present at all is a fresh clone or a
        // corpus without that sample, not a failure.
        for folder in Self.knownAsymmetricFolders {
            let dir = Self.probeRoot.appendingPathComponent(folder)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            #expect(foldersTouched.contains(folder),
                "Folder \(folder): known asymmetric corpus pair but its probe 29 parsed to no asymmetric lane")
        }
    }

    // MARK: - Parser regression: keys collapsed onto a shared line

    @Test("Collapsed line after an empty Hop Table still yields the key that follows it")
    func collapsedHopTableLineStillParses() {
        // Probe 29 prints an empty `Hop Table` with no newline after it, so
        // the next key lands on the same physical line. Verbatim from
        // research/customer-probes/intel_corei3_1000ng4_macos14.3.1. Across
        // the corpus this shape hides `Thunderbolt Version` 20343 times,
        // `Dual-Link Port RID` 7801 times, `Max In Hop ID` 498 times and
        // `HPM Address` 6 times, in 1319 of 1336 folders.
        let body = """
          Port Number =     1 (0x1)
          Hop Table =   Thunderbolt Version =     32 (0x20)
          Adapter Type =     1 (0x1)
        """
        #expect(Self.parseIntLine(body, key: "Thunderbolt Version") == 32)
        #expect(Self.parseIntLine(body, key: "Port Number") == 1)
    }

    @Test("A key is not matched as the tail of a longer key name")
    func longerKeyNameIsNotMatchedAsSuffix() {
        // `Dual-Link Port RID` must not answer a read of `Port RID`, and
        // `Max In Hop ID` must not answer a read of `Hop ID`.
        let body = """
          Dual-Link Port RID =     7 (0x7)
          Max In Hop ID =     9 (0x9)
        """
        #expect(Self.parseIntLine(body, key: "Port RID") == nil)
        #expect(Self.parseIntLine(body, key: "Hop ID") == nil)
        #expect(Self.parseIntLine(body, key: "Dual-Link Port RID") == 7)
    }

    @Test("Collapsed line still yields a quoted string value")
    func collapsedLineStillYieldsStringValue() {
        let body = """
          Hop Table =   Description =     "Thunderbolt Port"
        """
        #expect(Self.parseStringLine(body, key: "Description") == "Thunderbolt Port")
    }

    // MARK: - Fixture tests (always run, even on fresh clones)
    //
    // These fixtures are transcribed from the two topologies anchored in
    // ThunderboltLinkFromTests (Steve's Samsung + Joe's CalDigit chain), plus
    // a few edge-case dictionaries. They exercise the same code paths that
    // the corpus sweep hits, so CI always has at least this coverage.

    /// Fixture: a TB4/USB4 host-root switch (Apple M3, Type5).
    private var appleHostRootDict: [String: Any] {
        [
            "Vendor ID":           NSNumber(value: 1452),
            "Device Vendor Name":  "Apple Inc.",
            "Device Model Name":   "Mac",
            "Router ID":           NSNumber(value: 0),
            "Depth":               NSNumber(value: 0),
            "Route String":        NSNumber(value: 0),
            "Upstream Port Number": NSNumber(value: 0),
            "Max Port Number":     NSNumber(value: 8),
            "Thunderbolt Version": NSNumber(value: 32),
            "Firmware Version":    "19.2 build 3 Oct 17 2023 09:47:16,RELEASE,A-type"
        ]
    }

    /// Fixture: a TB5 host-root switch (Apple M5 Pro, Type7).
    private var appleType7Dict: [String: Any] {
        [
            "Vendor ID":           NSNumber(value: 1452),
            "Device Vendor Name":  "Apple Inc.",
            "Device Model Name":   "Mac",
            "Router ID":           NSNumber(value: 0),
            "Depth":               NSNumber(value: 0),
            "Route String":        NSNumber(value: 0),
            "Upstream Port Number": NSNumber(value: 0),
            "Max Port Number":     NSNumber(value: 12),
            "Thunderbolt Version": NSNumber(value: 64)
        ]
    }

    /// Fixture: an active TB4/USB4 dual-lane port (speed=4, width=2).
    private var activeTb4PortDict: [String: Any] {
        [
            "Port Number":          NSNumber(value: 1),
            "Adapter Type":         NSNumber(value: 1),     // lane
            "Socket ID":            "1",
            "Current Link Speed":   NSNumber(value: 4),     // USB4/TB4
            "Current Link Width":   NSNumber(value: 2),     // dual
            "Target Link Speed":    NSNumber(value: 12),
            "Target Link Width":    NSNumber(value: 3),     // dual encoding
            "Supported Link Speed": NSNumber(value: 12),
            "Supported Link Width": NSNumber(value: 2),
            "Link Bandwidth":       NSNumber(value: 400)
        ]
    }

    /// Fixture: an active TB5 dual-lane port (speed=2, width=2).
    private var activeTb5PortDict: [String: Any] {
        [
            "Port Number":          NSNumber(value: 1),
            "Adapter Type":         NSNumber(value: 1),
            "Socket ID":            "2",
            "Current Link Speed":   NSNumber(value: 2),     // TB5
            "Current Link Width":   NSNumber(value: 2),
            "Target Link Speed":    NSNumber(value: 14),
            "Target Link Width":    NSNumber(value: 3),
            "Supported Link Speed": NSNumber(value: 14),
            "Link Bandwidth":       NSNumber(value: 800)
        ]
    }

    /// Fixture: TB5 asymmetric TX port (3 TX / 1 RX).
    private var tb5AsymmetricTxPortDict: [String: Any] {
        [
            "Port Number":        NSNumber(value: 1),
            "Adapter Type":       NSNumber(value: 1),
            "Socket ID":          "1",
            "Current Link Speed": NSNumber(value: 2),
            "Current Link Width": NSNumber(value: 4),   // asymmetric TX
            "Link Bandwidth":     NSNumber(value: 600)
        ]
    }

    /// Fixture: a DP-in adapter port (non-lane; should have no link state).
    private var dpInPortDict: [String: Any] {
        [
            "Port Number":    NSNumber(value: 3),
            "Adapter Type":   NSNumber(value: 0x0e0101),  // dpIn
            "Link Bandwidth": NSNumber(value: 40)
        ]
    }

    /// Fixture: an idle lane port (speed=0, width=0).
    private var idleLanePortDict: [String: Any] {
        [
            "Port Number":        NSNumber(value: 2),
            "Adapter Type":       NSNumber(value: 1),
            "Socket ID":          "2",
            "Current Link Speed": NSNumber(value: 0),
            "Current Link Width": NSNumber(value: 0)
        ]
    }

    // MARK: Switch fixture tests

    @Test("Host root switch (Apple M3 Type5) parses")
    func appleHostRootParses() {
        let sw = IOThunderboltSwitch.from(
            uid: 42,
            read: { self.appleHostRootDict[$0] },
            className: "IOThunderboltSwitchType5",
            ports: []
        )
        #expect(sw != nil)
        #expect(sw?.id == 42)
        #expect(sw?.depth == 0)
        #expect(sw?.isHostRoot == true)
        #expect(sw?.vendorName == "Apple Inc.")
        #expect(sw?.thunderboltVersion == 32)
        #expect(sw?.firmwareVersion?.contains("RELEASE") == true)
    }

    @Test("Apple Type7 switch (M5 Pro) parses")
    func appleType7Parses() {
        let sw = IOThunderboltSwitch.from(
            uid: 99,
            read: { self.appleType7Dict[$0] },
            className: "IOThunderboltSwitchType7",
            ports: []
        )
        #expect(sw?.depth == 0)
        #expect(sw?.thunderboltVersion == 64)
    }

    @Test("Switch without Vendor ID returns nil")
    func switchWithoutVendorIDReturnsNil() {
        let sw = IOThunderboltSwitch.from(
            uid: 1,
            read: { _ in nil },
            className: "IOThunderboltSwitchType5",
            ports: []
        )
        #expect(sw == nil)
    }

    @Test("Switch supported-speed aggregated from lane ports when absent at switch level")
    func switchSpeedAggregatedFromLanePorts() {
        // No "Supported Link Speed" on the switch dict itself; must aggregate
        // from port-level supportedSpeed masks.
        var dict = appleHostRootDict
        dict.removeValue(forKey: "Supported Link Speed")

        let lane = IOThunderboltPort.from(read: { self.activeTb4PortDict[$0] })!
        let sw = IOThunderboltSwitch.from(
            uid: 7,
            read: { dict[$0] },
            className: "IOThunderboltSwitchType5",
            ports: [lane]
        )
        // Lane port reports Supported Link Speed = 12 (TB3 | TB4).
        #expect(sw?.supportedSpeed.supportsUsb4Tb4 == true)
        #expect(sw?.supportedSpeed.supportsTb3 == true)
    }

    @Test("Downstream switch carries parentSwitchUID")
    func downstreamSwitchCarriesParentUID() {
        let sw = IOThunderboltSwitch.from(
            uid: 200,
            read: { self.appleHostRootDict[$0] },
            className: "IOThunderboltSwitchType5",
            ports: [],
            parentSwitchUID: 100
        )
        #expect(sw?.parentSwitchUID == 100)
    }

    // MARK: Port fixture tests

    @Test("Active TB4/USB4 dual-lane port parses correctly")
    func activeTb4PortParsesCorrectly() {
        let port = IOThunderboltPort.from(read: { self.activeTb4PortDict[$0] })
        #expect(port != nil)
        #expect(port?.adapterType == .lane)
        #expect(port?.socketID == "1")
        #expect(port?.currentSpeed == .usb4Tb4)
        #expect(port?.perLaneGbps == 20)
        #expect(port?.currentWidth?.dual == true)
        #expect(port?.txLanes == 2)
        #expect(port?.rxLanes == 2)
        #expect(port?.targetWidth == .dual)
        #expect(port?.supportedSpeed?.supportsUsb4Tb4 == true)
        #expect(port?.hasTrainedLanes == true)
        #expect(port?.isBandwidthLimited == false)
    }

    @Test("Active TB5 dual-lane port parses correctly")
    func activeTb5PortParsesCorrectly() {
        let port = IOThunderboltPort.from(read: { self.activeTb5PortDict[$0] })
        #expect(port?.currentSpeed == .tb5)
        #expect(port?.perLaneGbps == 40)
        #expect(port?.currentWidth?.dual == true)
        #expect(port?.hasTrainedLanes == true)
        // TB5 total: 80 Gbps
        #expect(port?.currentSpeed?.totalGbps == 80)
    }

    @Test("TB5 asymmetric TX port (3 TX / 1 RX) parses correctly")
    func tb5AsymmetricTxPortParsesCorrectly() {
        let port = IOThunderboltPort.from(read: { self.tb5AsymmetricTxPortDict[$0] })
        #expect(port?.currentSpeed == .tb5)
        #expect(port?.currentWidth?.asymmetricTx == true)
        #expect(port?.txLanes == 3)
        #expect(port?.rxLanes == 1)
        #expect(port?.hasTrainedLanes == true)
    }

    @Test("DP-in protocol adapter port has no link state")
    func dpInAdapterPortHasNoLinkState() {
        let port = IOThunderboltPort.from(read: { self.dpInPortDict[$0] })
        #expect(port?.adapterType == .dpIn)
        #expect(port?.currentSpeed == nil)
        #expect(port?.currentWidth == nil)
        #expect(port?.hasTrainedLanes == false)
    }

    @Test("Idle lane port has no active link")
    func idleLanePortHasNoActiveLink() {
        let port = IOThunderboltPort.from(read: { self.idleLanePortDict[$0] })
        #expect(port?.adapterType == .lane)
        #expect(port?.currentSpeed == nil)
        #expect(port?.currentWidth?.isActive == false)
        #expect(port?.hasTrainedLanes == false)
    }

    @Test("Port without port number returns nil")
    func portWithoutPortNumberReturnsNil() {
        let port = IOThunderboltPort.from(read: { _ in nil })
        #expect(port == nil)
    }

    @Test("Lane-limited port (single-width when dual supported) is bandwidth-limited")
    func laneLimitedPortIsBandwidthLimited() {
        // Single-width current, dual-width supported: isBandwidthLimited.
        let dict: [String: Any] = [
            "Port Number":          NSNumber(value: 1),
            "Adapter Type":         NSNumber(value: 1),
            "Current Link Speed":   NSNumber(value: 4),
            "Current Link Width":   NSNumber(value: 1),   // single
            "Supported Link Width": NSNumber(value: 2)    // dual supported
        ]
        let port = IOThunderboltPort.from(read: { dict[$0] })
        #expect(port?.isBandwidthLimited == true)
    }

    @Test("ThunderboltLabels link label: TB4 dual-lane")
    func tb4LinkLabel() {
        let lane = IOThunderboltPort.from(read: { self.activeTb4PortDict[$0] })!
        let label = ThunderboltLabels.linkLabel(for: lane)
        #expect(label != nil)
        #expect(label?.contains("20 Gb/s") == true)
        #expect(label?.contains("2") == true)
    }

    @Test("ThunderboltLabels link label: TB5 dual-lane")
    func tb5LinkLabel() {
        let lane = IOThunderboltPort.from(read: { self.activeTb5PortDict[$0] })!
        let label = ThunderboltLabels.linkLabel(for: lane)
        #expect(label?.contains("40 Gb/s") == true)
    }

    @Test("ThunderboltLabels link label: TB5 asymmetric TX side reads one rate per direction")
    func tb5AsymmetricLinkLabel() {
        let lane = IOThunderboltPort.from(read: { self.tb5AsymmetricTxPortDict[$0] })!
        let label = ThunderboltLabels.linkLabel(for: lane)
        #expect(label == "Up to 120 Gb/s out, 40 Gb/s in")
    }

    @Test("ThunderboltLabels link label: idle port returns nil")
    func idlePortLinkLabelNil() {
        let lane = IOThunderboltPort.from(read: { self.idleLanePortDict[$0] })!
        #expect(ThunderboltLabels.linkLabel(for: lane) == nil)
    }

    @Test("ThunderboltLabels deviceName: vendor and model combined")
    func deviceNameVendorAndModelCombined() {
        let sw = IOThunderboltSwitch.from(
            uid: 1,
            read: { self.appleHostRootDict[$0] },
            className: "IOThunderboltSwitchType5",
            ports: []
        )!
        let name = ThunderboltLabels.deviceName(for: sw)
        #expect(name.contains("Apple Inc."))
        #expect(name.contains("Mac"))
    }

    @Test("ThunderboltLabels deviceName: vendor only when model empty")
    func deviceNameVendorOnlyWhenModelEmpty() {
        var dict = appleHostRootDict
        dict["Device Model Name"] = ""
        let sw = IOThunderboltSwitch.from(
            uid: 1,
            read: { dict[$0] },
            className: "IOThunderboltSwitchType5",
            ports: []
        )!
        #expect(ThunderboltLabels.deviceName(for: sw) == "Apple Inc.")
    }

    @Test("ThunderboltLabels deviceName: unknown device when both empty")
    func deviceNameUnknownWhenBothEmpty() {
        var dict = appleHostRootDict
        dict["Device Model Name"] = ""
        dict["Device Vendor Name"] = ""
        let sw = IOThunderboltSwitch.from(
            uid: 1,
            read: { dict[$0] },
            className: "IOThunderboltSwitchType5",
            ports: []
        )!
        let name = ThunderboltLabels.deviceName(for: sw)
        // Localised to "Unknown device"; just check it's non-empty.
        #expect(!name.isEmpty)
    }

    // MARK: - Topology fixture tests

    @Test("socketID(fromServiceName:) parses trailing @N suffix")
    func socketIDFromServiceNameParsesTrailingSuffix() {
        #expect(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C@1") == "1")
        #expect(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C@12") == "12")
        #expect(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C") == nil)
        #expect(ThunderboltTopology.socketID(fromServiceName: "") == nil)
    }

    @Test("hostRoot finds correct root for socketID")
    func hostRootFindsCorrectRoot() {
        let lane1 = IOThunderboltPort(
            portNumber: 1, socketID: "1", adapterType: .lane,
            currentSpeed: .usb4Tb4, currentWidth: LinkWidth(rawValue: 2),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil
        )
        let lane2 = IOThunderboltPort(
            portNumber: 2, socketID: "2", adapterType: .lane,
            currentSpeed: nil, currentWidth: LinkWidth(rawValue: 0),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil
        )
        let root1 = IOThunderboltSwitch(
            id: 10, className: "IOThunderboltSwitchType5", vendorID: 1452,
            vendorName: "Apple Inc.", modelName: "Mac",
            routerID: 0, depth: 0, routeString: 0,
            upstreamPortNumber: 0, maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [lane1], parentSwitchUID: nil
        )
        let root2 = IOThunderboltSwitch(
            id: 11, className: "IOThunderboltSwitchType5", vendorID: 1452,
            vendorName: "Apple Inc.", modelName: "Mac",
            routerID: 0, depth: 0, routeString: 0,
            upstreamPortNumber: 0, maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [lane2], parentSwitchUID: nil
        )
        let found1 = ThunderboltTopology.hostRoot(forSocketID: "1", in: [root1, root2])
        let found2 = ThunderboltTopology.hostRoot(forSocketID: "2", in: [root1, root2])
        #expect(found1?.id == 10)
        #expect(found2?.id == 11)
        #expect(ThunderboltTopology.hostRoot(forSocketID: "3", in: [root1, root2]) == nil)
    }

    // MARK: - Stage B v2 corpus replay (PCI Path / PCI Entry ID), test 15

    /// Sweeps every probe-29 capture, parsing `IOThunderboltPort` blocks
    /// through the PRODUCTION parser (`IOThunderboltPort.from(read:)`, the
    /// same one live code and `probe29SweepParsesWithoutCrashing` above both
    /// use), and checks the switch side of the Stage B v2 PCI-Path-prefix
    /// join (`planning/pcie-tunnelled-usb-attribution.md`): `PCI Path` /
    /// `PCI Entry ID` on PCIe up-adapters.
    ///
    /// Two assertions, both corpus-wide:
    ///   - a hard floor: at least 1100 captures yield at least one adapter
    ///     with a usable `pciPath` (the plan's own re-derived figure, 1136 of
    ///     1150; a floor rather than an exact match so the test doesn't need
    ///     updating every time a new probe-29 file lands);
    ///   - no cross-switch duplicate paths: within one capture, every PCIe
    ///     up-adapter's `pciPath` is DISTINCT. A duplicate would mean two
    ///     switches claim the identical landing node, which the join's
    ///     deepest-match/tie logic depends on not happening in practice
    ///     (an actual duplicate is exactly the registry anomaly that trips
    ///     `resolvePCIeTunnelCandidate`'s tie rule and forces port level).
    // MARK: - Hop-table parsing for the idle sweep

    /// Hop-table rows out of a probe-29 port block, in the dictionary shape
    /// `IOThunderboltPort.from` expects. `makeReadClosure` only returns
    /// scalars, so without this the parsed model's `hopTable` is always
    /// empty and a tunnel-carrying lane is indistinguishable from an idle
    /// one. Same read-by-name approach as `TunnelPathCorpusTests` (whose
    /// copy is private to that file): key order inside a row is not stable,
    /// and an EFI-inherited row carries no `Counter`.
    private static func parseHopEntries(fromPortBody body: String) -> [[String: Any]] {
        guard let hopStart = body.range(of: "Hop Table =") else { return [] }
        var table = String(body[hopStart.upperBound...])
        if let end = try? NSRegularExpression(
            pattern: "^  [A-Za-z][A-Za-z0-9 _-]*\\s*=", options: [.anchorsMatchLines]),
           let m = end.firstMatch(in: table, range: NSRange(table.startIndex..., in: table)),
           let r = Range(m.range, in: table) {
            table = String(table[table.startIndex..<r.lowerBound])
        }
        let rowMarker = try! NSRegularExpression(pattern: #"\[\d+\]"#)
        let pathRegex = try! NSRegularExpression(
            pattern: #"Path\s*=\s*"([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})""#
        )
        func int(_ chunk: String, _ key: String) -> Int? {
            guard let re = try? NSRegularExpression(
                pattern: "^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*(-?\\d+)",
                options: [.anchorsMatchLines]),
                  let m = re.firstMatch(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)),
                  let r = Range(m.range(at: 1), in: chunk) else { return nil }
            return Int(chunk[r])
        }
        let ns = table as NSString
        let marks = rowMarker.matches(in: table, range: NSRange(location: 0, length: ns.length))
        var out: [[String: Any]] = []
        for (i, m) in marks.enumerated() {
            let start = m.range.location + m.range.length
            let end = (i + 1 < marks.count) ? marks[i + 1].range.location : ns.length
            guard end > start else { continue }
            let chunk = ns.substring(with: NSRange(location: start, length: end - start))
            guard let pm = pathRegex.firstMatch(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)),
                  let pr = Range(pm.range(at: 1), in: chunk),
                  let dstHopID = int(chunk, "Dst Hop ID"),
                  let dstPort = int(chunk, "Dst Port"),
                  let hopID = int(chunk, "Hop ID") else { continue }
            var entry: [String: Any] = [
                "Path": String(chunk[pr]),
                "Dst Hop ID": NSNumber(value: dstHopID),
                "Dst Port": NSNumber(value: dstPort),
                "Hop ID": NSNumber(value: hopID)
            ]
            if let counter = int(chunk, "Counter") { entry["Counter"] = NSNumber(value: counter) }
            out.append(entry)
        }
        return out
    }

    /// `makeReadClosure` plus the port's hop table, so the parsed model
    /// carries the tunnel rows the idle sweep keys on.
    private static func makePortReadClosure(body: String) -> (String) -> Any? {
        let scalars = makeReadClosure(body: body)
        let hops = parseHopEntries(fromPortBody: body)
        return { key in
            if key == "Hop Table" { return hops.isEmpty ? nil : hops as Any }
            return scalars(key)
        }
    }

    /// The probe's own output cap. A capture of exactly this many bytes was
    /// cut off mid-dump, whatever it still appears to contain.
    private static let probeOutputCap = 65536

    // MARK: - Idle-link sweep

    /// Every folder whose fabric holds nothing but host roots must report no
    /// linked lane at all.
    ///
    /// This sweep runs corpus-wide, on every folder with a switch section,
    /// and deliberately builds its switches with `parentSwitchUID` nil: it
    /// asks only about machines with nothing downstream, where every switch
    /// is a host root and every lane port belongs to one, so no parent link
    /// and no port-to-switch attribution is needed. The linked direction, and
    /// the empty sockets on a dock, are proved by
    /// `probe29SweepParentGraphLinkState` below, on the 824 folders that
    /// publish `RegistryEntryID` / `ParentSwitchEntryID`. Read neither count
    /// as covering the other.
    @Test("Corpus sweep: no host-root lane is linked on a machine with nothing attached")
    func probe29SweepIdleHostRootsAreNotLinked() throws {
        let folders = try Self.allProbes()
        var sweptFolders = 0
        var laneRecords = 0
        var trainedLanes = 0
        var truncated = 0
        var hopTableLanes = 0
        var siblingLanesExcluded = 0
        var hopTableSocketLanesLinked = 0
        var ambiguousSockets = 0

        for folder in folders {
            guard let text = try Self.loadProbe29(folder: folder) else { continue }

            // 13 corpus captures are cut off at exactly 65536 bytes, the
            // probe's output cap. On those, "no depth-1 switch" is an
            // artefact of the cut, not a measured state: a machine with a
            // dock plainly attached would be swept as a machine with nothing
            // attached.
            //
            // Both conditions are needed. The length test alone would miss a
            // capture truncated by anything other than that cap, and a
            // hand-trimmed or re-serialised copy would slip through. The
            // missing-section test alone catches only 7 of the 13: the other
            // 6 keep a PARTIAL switch section, so the section header is there
            // while the switch list behind it is not.
            guard text.utf8.count != Self.probeOutputCap,
                  text.contains("=== IOThunderboltSwitch ===") else {
                truncated += 1
                continue
            }

            var switches: [IOThunderboltSwitch] = []
            var hostRootBody: String?
            for (_, body) in Self.parseInstanceBlocks(text, className: "IOThunderboltSwitch") {
                let uid = Self.parseIntLine(body, key: "UID").map(Int64.init) ?? 0
                if let sw = IOThunderboltSwitch.from(
                    uid: uid,
                    read: Self.makeReadClosure(body: body),
                    className: "IOThunderboltSwitch",
                    ports: [],
                    parentSwitchUID: nil
                ) {
                    switches.append(sw)
                    if sw.isHostRoot, hostRootBody == nil { hostRootBody = body }
                }
            }
            guard !switches.isEmpty, !switches.contains(where: { $0.depth >= 1 }) else { continue }
            guard let hostRoot = switches.first(where: { $0.isHostRoot }),
                  let hostRootBody else { continue }
            sweptFolders += 1

            // Lanes grouped into the physical sockets they belong to. One
            // socket is a PAIR of lane adapters sharing a Socket ID, and only
            // one of the pair carries the hop table. Handing `isLinked` a
            // lane on a switch with no ports at all, as this sweep used to,
            // makes the pairing unreachable, so the sweep asked a question
            // production never asks and its answer said nothing about the
            // sibling.
            var lanesBySocket: [String: [IOThunderboltPort]] = [:]
            var unpairedLanes: [IOThunderboltPort] = []
            for (_, body) in Self.parseInstanceBlocks(text, className: "IOThunderboltPort") {
                guard let port = IOThunderboltPort.from(read: Self.makePortReadClosure(body: body)),
                      port.adapterType.isLane else { continue }
                laneRecords += 1
                if port.hasTrainedLanes { trainedLanes += 1 }
                if let socketID = port.socketID, !socketID.isEmpty {
                    lanesBySocket[socketID, default: []].append(port)
                } else {
                    unpairedLanes.append(port)
                }
            }

            // A Socket ID naming more than two lanes is two controllers
            // reusing the number, not one socket, and pairing across them
            // would invent a sibling. Left out rather than guessed at.
            let grouped = lanesBySocket.sorted { $0.key < $1.key }.map(\.value)
            ambiguousSockets += grouped.filter { $0.count > 2 }.count
            let sockets = grouped.filter { $0.count <= 2 } + unpairedLanes.map { [$0] }

            for lanes in sockets {
                guard let root = IOThunderboltSwitch.from(
                    uid: hostRoot.id,
                    read: Self.makeReadClosure(body: hostRootBody),
                    className: "IOThunderboltSwitch",
                    ports: lanes.sorted { $0.portNumber < $1.portNumber },
                    parentSwitchUID: nil
                ) else { continue }

                // The exclusion is by SOCKET, not by lane. A lane carrying a
                // hop table has a tunnel routed across it, so something is
                // attached even though macOS published no switch record; the
                // dual-link sibling is the other half of that same physical
                // socket and is just as attached, while carrying none of the
                // evidence itself. Excluding only the lane holding the rows
                // left the sibling asserting NOT linked, so this sweep pinned
                // as correct the very reading the gate exists to stop making:
                // 7 lanes across 6 CIO-active folders, and their siblings.
                // An earlier hop-table count of 45 was inflated by truncated
                // captures, which the guard above now skips.
                //
                // These sockets are asserted, not skipped. They ARE the
                // evidence the per-socket rule was built on, so skipping past
                // them left the fix with no corpus assertion behind it at
                // all: reverting `isLinked` to a per-lane answer kept this
                // sweep green. Both halves are pinned, because both are
                // production behaviour on this shape: a trained lane of a
                // hop-table socket must read linked (that is the fix), and an
                // untrained one must not, because `hasTrainedLanes` guards
                // above the socket loop and an untrained lane adapter is
                // genuinely carrying nothing.
                if lanes.contains(where: { !$0.hopTable.isEmpty }) {
                    hopTableLanes += lanes.filter { !$0.hopTable.isEmpty }.count
                    siblingLanesExcluded += lanes.filter { $0.hopTable.isEmpty }.count
                    for port in root.ports {
                        if port.hasTrainedLanes { hopTableSocketLanesLinked += 1 }
                        #expect(
                            ThunderboltTopology.isLinked(port: port, on: root, in: switches)
                                == port.hasTrainedLanes,
                            """
                            Folder \(folder): lane port \(port.portNumber) of a socket carrying a \
                            hop table reads \
                            \(ThunderboltTopology.isLinked(port: port, on: root, in: switches) ? "linked" : "not linked"), \
                            trained \(port.hasTrainedLanes) (speed \(String(describing: port.currentSpeed)), \
                            width \(String(describing: port.currentWidth)), \
                            dual-link \(String(describing: port.dualLinkPort)))
                            """
                        )
                    }
                    continue
                }
                for port in root.ports {
                    #expect(
                        ThunderboltTopology.isLinked(port: port, on: root, in: switches) == false,
                        """
                        Folder \(folder): lane port \(port.portNumber) reads as linked on a machine \
                        with no downstream switch (speed \(String(describing: port.currentSpeed)), \
                        width \(String(describing: port.currentWidth)))
                        """
                    )
                }
            }
        }

        // Sized against the corpus on 2026-09-10: 1336 folders carry a
        // probe-29 file, 13 are truncated at the output cap, 17 print the
        // section with no switch instances, 282 hold a depth-1 switch, and
        // the remaining 1024 are swept here. The floor guards against a
        // sweep that silently stops finding folders; it only applies once
        // any probe-29 file is on disk (a fresh clone has none).
        if sweptFolders > 0 {
            #expect(sweptFolders > 900, "swept only \(sweptFolders) idle folders")
            #expect(trainedLanes > 0,
                "sweep is vacuous: \(laneRecords) lane records, none reporting trained lanes")
            // 7 today. The upper bound catches the switch record going
            // missing far more often than measured, which would be a
            // different finding and wants looking at rather than being
            // absorbed here. The lower bound keeps the hop-table clause
            // exercised: at zero, nothing in this sweep would touch it.
            #expect((1..<40).contains(hopTableLanes),
                "\(hopTableLanes) tunnel-carrying lanes on machines with no switch record")
            // The hop-table sockets are the fix's own evidence, so their
            // linked assertion must not go vacuous. At zero, the per-socket
            // rule would once again have nothing in this sweep holding it.
            #expect(hopTableSocketLanesLinked > 0,
                "no trained lane on any hop-table socket, so the per-socket rule is unasserted here")
        }
        print("Idle-link sweep: \(sweptFolders) folders, \(laneRecords) lane records, \(trainedLanes) trained, \(hopTableLanes) hop-table lanes with \(siblingLanesExcluded) siblings, \(hopTableSocketLanesLinked) of those asserted linked, \(ambiguousSockets) ambiguous sockets, \(truncated) truncated captures skipped")
    }

    // MARK: - Parent-graph sweep

    /// Probe 29 DOES publish the parent link on switch blocks:
    /// `RegistryEntryID` and `ParentSwitchEntryID`, the same pair the watcher
    /// keys on, with a host root reading `ParentSwitchEntryID = 0`. 824 of the
    /// 1336 folders carry it. Ports carry no owner key, but they do carry
    /// `Micro Route String`, which equals the owning switch's `Route String`,
    /// so a switch whose route is unique in its folder can have its ports
    /// reassembled.
    ///
    /// Everything in THIS test runs on that subset. The idle sweep above runs
    /// corpus-wide and its counts say nothing about this one.
    ///
    /// The parent's downstream port for a child at depth d is route byte d-1,
    /// not byte 0: byte 0 is the first hop from the host root. Checked over
    /// every child whose parent's ports are visible, the byte names one of
    /// them in 47 of 47 cases; 4 more children sit under a parent that
    /// published no port blocks at all, so nothing could be compared there.
    @Test("Corpus sweep: parent graph pins which lanes are linked and which are empty sockets")
    func probe29SweepParentGraphLinkState() throws {
        let folders = try Self.allProbes()
        var foldersUsed = 0
        var childLanes = 0
        var upstreamLanes = 0
        var hopLanes = 0
        var emptyDockLanes = 0

        for folder in folders {
            guard let text = try Self.loadProbe29(folder: folder) else { continue }
            // Same cut-off captures the idle sweep skips: a truncated switch
            // list would invent missing children.
            guard text.utf8.count != Self.probeOutputCap else { continue }
            let switchBlocks = Self.parseInstanceBlocks(text, className: "IOThunderboltSwitch")
            guard !switchBlocks.isEmpty else { continue }

            // Every block must carry the parent pair, or the graph would be
            // part real and part guessed.
            let entries = switchBlocks.compactMap { block -> (body: String, registryID: Int, parentID: Int)? in
                guard let registryID = Self.parseIntLine(block.body, key: "RegistryEntryID") else { return nil }
                return (block.body, registryID, Self.parseIntLine(block.body, key: "ParentSwitchEntryID") ?? 0)
            }
            guard entries.count == switchBlocks.count else { continue }

            let routes = entries.map { Self.parseIntLine($0.body, key: "Route String") ?? 0 }
            let depths = entries.map { Self.parseIntLine($0.body, key: "Depth") ?? 0 }
            let downstreamRoutes = zip(routes, depths).filter { $0.1 >= 1 }.map(\.0)
            guard !downstreamRoutes.isEmpty,
                  Set(downstreamRoutes).count == downstreamRoutes.count else { continue }

            // Ports carry Micro Route String = the owning switch's Route
            // String. Only downstream switches can be resolved that way: every
            // host root reads route 0, so a multi-root Mac's root ports are
            // not separable, and this test asks nothing about them.
            var portsByRoute: [Int: [IOThunderboltPort]] = [:]
            for (_, body) in Self.parseInstanceBlocks(text, className: "IOThunderboltPort") {
                guard let micro = Self.parseIntLine(body, key: "Micro Route String"), micro != 0,
                      let port = IOThunderboltPort.from(read: Self.makePortReadClosure(body: body))
                else { continue }
                portsByRoute[micro, default: []].append(port)
            }

            var uidByRegistryID: [Int: Int64] = [:]
            for (index, entry) in entries.enumerated() {
                uidByRegistryID[entry.registryID] =
                    Self.parseIntLine(entry.body, key: "UID").map(Int64.init) ?? Int64(index + 1)
            }

            var switches: [IOThunderboltSwitch] = []
            for (index, entry) in entries.enumerated() {
                guard let uid = uidByRegistryID[entry.registryID] else { continue }
                let parentUID = entry.parentID != 0 ? uidByRegistryID[entry.parentID] : nil
                if let sw = IOThunderboltSwitch.from(
                    uid: uid,
                    read: Self.makeReadClosure(body: entry.body),
                    className: "IOThunderboltSwitch",
                    ports: portsByRoute[routes[index]] ?? [],
                    parentSwitchUID: parentUID
                ) {
                    switches.append(sw)
                }
            }
            guard switches.contains(where: { !$0.isHostRoot && !$0.ports.isEmpty }) else { continue }
            foldersUsed += 1

            for sw in switches where !sw.isHostRoot && !sw.ports.isEmpty {
                // Port numbers this switch's own children hang off.
                let childPorts = Set(
                    switches
                        .filter { $0.parentSwitchUID == sw.id && $0.depth >= 1 }
                        .map { Int(($0.routeString >> (8 * ($0.depth - 1))) & 0xFF) }
                )

                for port in sw.ports where port.adapterType.isLane && port.hasTrainedLanes {
                    let linked = ThunderboltTopology.isLinked(port: port, on: sw, in: switches)
                    // Every term below is asked of the whole SOCKET, because
                    // one socket is a pair of lane adapters and only one of
                    // the pair carries the route byte, the hop table or the
                    // upstream port number. Asked lane by lane, the other
                    // half of a live socket lands in the empty-socket arm and
                    // the sweep asserts a live lane is dark: two dock lanes
                    // (m5pro_macos27.0_g and _l, lane 8, sibling of the
                    // tunnel-carrying lane 7) did exactly that.
                    //
                    // The sibling is resolved here rather than through
                    // `ThunderboltTopology.socketLanePorts`, so this stays an
                    // independent check of the production rule rather than a
                    // restatement of it.
                    let sibling = port.dualLinkPort.flatMap { number in
                        sw.ports.first { $0.portNumber == number && $0.adapterType.isLane }
                    }
                    let socketLanes = [port] + (sibling.map { [$0] } ?? [])
                    let carriesChild = socketLanes.contains { childPorts.contains($0.portNumber) }
                    let carriesTunnel = socketLanes.contains { !$0.hopTable.isEmpty }
                    let isUpstream = socketLanes.contains { $0.portNumber == sw.upstreamPortNumber }

                    // The first three arms assert the same thing, so which
                    // one a lane lands in is descriptive only. Upstream is
                    // asked before the tunnel because it is the structural
                    // fact: every upstream socket also carries tunnel rows,
                    // and asking the tunnel first would empty the upstream
                    // count and read as a sweep that had stopped working.
                    if carriesChild {
                        childLanes += 1
                        #expect(linked,
                            "Folder \(folder): lane \(port.portNumber) has a child switch hanging off it and must read as linked")
                    } else if isUpstream {
                        upstreamLanes += 1
                        #expect(linked,
                            "Folder \(folder): lane \(port.portNumber) is how this switch reaches the Mac and must read as linked")
                    } else if carriesTunnel {
                        hopLanes += 1
                        #expect(linked,
                            "Folder \(folder): lane \(port.portNumber) carries a tunnel and must read as linked")
                    } else {
                        // An empty socket on a dock: trained, nothing hanging
                        // off it, no tunnel, not the leg to the Mac.
                        emptyDockLanes += 1
                        #expect(linked == false,
                            "Folder \(folder): empty dock socket on lane \(port.portNumber) reads as linked")
                    }
                }
            }
        }

        // Sized on 2026-09-10 over the 824 folders carrying the parent pair:
        // 157 of them hold a downstream switch whose ports are resolvable.
        if foldersUsed > 0 {
            #expect(foldersUsed > 100, "only \(foldersUsed) folders had a resolvable parent graph")
            #expect(childLanes > 50, "only \(childLanes) lanes with a child switch")
            #expect(emptyDockLanes > 100, "only \(emptyDockLanes) empty dock sockets swept")
        }
        print("Parent-graph sweep: \(foldersUsed) folders, \(childLanes) child lanes, \(hopLanes) tunnel lanes, \(upstreamLanes) upstream lanes, \(emptyDockLanes) empty dock sockets")
    }

    @Test("Stage B v2 corpus replay: PCI Path / PCI Entry ID parse via the production parser, no cross-switch duplicates")
    func stageBPCIPathCorpusReplay() throws {
        let folders = try Self.allProbes()
        var capturesWithAnyPath = 0
        var capturesChecked = 0

        for folder in folders {
            guard let text = try Self.loadProbe29(folder: folder) else { continue }
            capturesChecked += 1

            let portBlocks = Self.parseInstanceBlocks(text, className: "IOThunderboltPort")
            var upAdapterPaths: [String] = []
            for (_, body) in portBlocks {
                let read = Self.makeReadClosure(body: body)
                guard let port = IOThunderboltPort.from(read: read) else { continue }
                if port.pciPath != nil { capturesWithAnyPath += 1; break }
            }
            for (_, body) in portBlocks {
                let read = Self.makeReadClosure(body: body)
                guard let port = IOThunderboltPort.from(read: read),
                      port.adapterType == .pcieUp,
                      let path = port.pciPath
                else { continue }
                upAdapterPaths.append(path)
            }
            #expect(Set(upAdapterPaths).count == upAdapterPaths.count,
                "Folder \(folder): expected every PCIe up-adapter's PCI Path to be distinct within one capture, found a duplicate among \(upAdapterPaths)")
        }

        if capturesChecked > 0 {
            #expect(capturesWithAnyPath >= 1100,
                "Expected at least 1100 of \(capturesChecked) probe-29 captures to yield at least one adapter with a PCI Path; got \(capturesWithAnyPath)")
        }
    }

    /// Pins the exact PCI Path / PCI Entry ID string the reporter's own
    /// capture produced for the LG UltraFine 5K's PCIe up-adapter (the
    /// motivating case for Stage B v2), parsed through the production
    /// parser, not re-typed by hand: this is the read that lets the FL1100
    /// controller behind it join to the LG's switch.
    @Test("m2max_macos26.6.1 pin: LG UltraFine PCIe up-adapter PCI Path / PCI Entry ID / Device ID")
    func m2maxLGPinExactStrings() throws {
        guard let text = try Self.loadProbe29(folder: "m2max_macos26.6.1") else {
            // Not fetched into this worktree/clone; nothing to pin against.
            return
        }
        let portBlocks = Self.parseInstanceBlocks(text, className: "IOThunderboltPort")
        var matched: IOThunderboltPort?
        for (_, body) in portBlocks {
            let read = Self.makeReadClosure(body: body)
            guard let port = IOThunderboltPort.from(read: read),
                  port.adapterType == .pcieUp,
                  port.deviceID == 0x15d3
            else { continue }
            matched = port
            break
        }
        let port = try #require(matched, "Expected to find the LG's Device ID 0x15d3 PCIe up-adapter in m2max_macos26.6.1's probe-29 capture")
        #expect(port.pciPath == "IOService:/AppleARMPE/arm-io/AppleT602xIO/apciec1@30000000/AppleT6000PCIeC/pcic1-bridge@0/IOPP/pci-bridge@0")
        #expect(port.pciEntryID == 0x100001442)
    }

    /// Pins the m3pro_macos27.0_l tracked probe-29 fixture (LaCie 1big +
    /// Studio Display, chained behind each other on `apciec2`): a real
    /// multi-switch topology whose PCIe up-adapter paths nest, one a strict
    /// prefix of the other, which is exactly the structural property the
    /// deepest-match step of the join depends on. This fixture is git-tracked
    /// (`research/customer-probes/m3pro_macos27.0_l/29_usb4_router_interfaces.json`),
    /// so it is always present, unlike the wider sweep above.
    @Test("m3pro_macos27.0_l pin: multi-switch PCIe up-adapter paths nest as strict prefixes")
    func m3proMultiSwitchPinNestsAsPrefixes() throws {
        let text = try #require(try Self.loadProbe29(folder: "m3pro_macos27.0_l"),
            "Expected the tracked m3pro_macos27.0_l probe-29 fixture to be present")
        let portBlocks = Self.parseInstanceBlocks(text, className: "IOThunderboltPort")
        var upPaths: [String] = []
        for (_, body) in portBlocks {
            let read = Self.makeReadClosure(body: body)
            guard let port = IOThunderboltPort.from(read: read),
                  port.adapterType == .pcieUp,
                  let path = port.pciPath
            else { continue }
            upPaths.append(path)
        }
        #expect(upPaths.count >= 2,
            "Expected at least 2 PCIe up-adapters (a daisy chain) in m3pro_macos27.0_l, got \(upPaths.count): \(upPaths)")
        let hasNestedPrefix = upPaths.contains { shallow in
            upPaths.contains { deep in deep != shallow && deep.hasPrefix(shallow + "/") }
        }
        #expect(hasNestedPrefix,
            "Expected at least one PCIe up-adapter path to be a strict prefix of another (daisy-chain nesting), got \(upPaths)")
    }
}
