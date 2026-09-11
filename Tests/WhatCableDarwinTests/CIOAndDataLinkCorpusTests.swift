import Foundation
import Testing
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

/// Corpus-back tests for CIO cable capability parsing and DataLink diagnostic
/// inputs from probes 17 and 19. Covers (DAR-138):
///
/// (a) CIO verdict-level assertions: per-machine CableSpeed values cross-checked
///     against `research/cio-value-mappings.md`. `cableSpeed` is asserted against
///     corpus-confirmed mappings, and the `linkTrainingMode <= cableGeneration`
///     invariant is asserted across the corpus (settled 2026-07-22: the two are
///     distinct fields, a capability ceiling and the trained-link result, not the
///     "same value" once believed). Their exact 1/2 value encoding stays
///     unconfirmed pending the DAR-185 cable swap, so semantic meaning is not
///     asserted; `generation` is likewise stored raw and not asserted.
///
/// (b) DataLink diagnostic: USB3/TRM inputs from probes 17/19 joined with port
///     data from probe 01. Verifies that TRM-restricted ports do not produce a
///     `.fine` verdict (the DAR-134 regression class).
///
/// Helpers are file-private; no shared ProbeCorpus.swift dependency.
@Suite("CIO capability and DataLink input paths -- corpus sweep (DAR-138)")
struct CIOAndDataLinkCorpusTests {

    // MARK: - Probe root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // MARK: - Probe file loader

    /// Load the "output" text from a numbered probe JSON inside a folder.
    private static func loadProbeText(folder: String, probe: String) -> String? {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("\(probe).json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Block parsers (file-private)

    /// Parse `=== ClassName ===` style blocks (4-space-indented properties).
    /// Used for CIO blocks in probe 17's HPM deep-dive section.
    private static func parseEqualsBlocks(text: String, className: String) -> [[String: Any]] {
        let header = "=== \(className) ==="
        var blocks: [[String: Any]] = []
        var searchFrom = text.startIndex
        while let range = text.range(of: header, range: searchFrom..<text.endIndex) {
            let bodyStart = range.upperBound
            let rest = String(text[bodyStart...])
            let body: String
            if let nextSection = rest.range(of: "\n=== ") ?? rest.range(of: "\n--- ") {
                body = String(rest[..<nextSection.lowerBound])
            } else {
                body = String(rest.prefix(2000))
            }
            blocks.append(parseProperties(body: body, indent: "    "))
            searchFrom = range.upperBound
        }
        return blocks
    }

    /// Parse `--- ClassName[N] ---` style blocks (2-space-indented properties).
    /// Used for USB2/USB3 blocks in probe 17's flat-services section,
    /// and USB3 blocks in probe 19.
    private static func parseDashBlocks(text: String, classPrefix: String) -> [[String: Any]] {
        let escapedPrefix = NSRegularExpression.escapedPattern(for: classPrefix)
        guard let regex = try? NSRegularExpression(
            pattern: "--- \(escapedPrefix)\\[\\d+\\] ---")
        else { return [] }
        let nsText = text as NSString
        let headerMatches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var blocks: [[String: Any]] = []
        for (i, match) in headerMatches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < headerMatches.count
                ? headerMatches[i + 1].range.lowerBound
                : nsText.length
            var body = nsText.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
            for sep in ["\n---", "\n==="] {
                if let r = body.range(of: sep) { body = String(body[..<r.lowerBound]) }
            }
            blocks.append(parseProperties(body: body, indent: "  "))
        }
        return blocks
    }

    /// Convert a block body to a property dict.
    /// Supports: `N (0xHEX)` -> Int, `"quoted"` -> String, true/false -> Bool.
    private static func parseProperties(body: String, indent: String) -> [String: Any] {
        var props: [String: Any] = [:]
        let deeper = indent + " "
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.hasPrefix(indent), !s.hasPrefix(deeper) else { continue }
            let stripped = String(s.dropFirst(indent.count))
            guard let colonRange = stripped.range(of: ": ") else { continue }
            let key = String(stripped[..<colonRange.lowerBound])
            let valStr = String(stripped[colonRange.upperBound...])
            if valStr == "true" {
                props[key] = NSNumber(value: true)
            } else if valStr == "false" {
                props[key] = NSNumber(value: false)
            } else if valStr.hasPrefix("\""), valStr.hasSuffix("\""), valStr.count >= 2 {
                props[key] = String(valStr.dropFirst().dropLast())
            } else if let m = parseIntLiteral(valStr) {
                props[key] = NSNumber(value: m)
            }
        }
        return props
    }

    /// Parse `N (0xHEX)` or plain integer strings.
    private static func parseIntLiteral(_ s: String) -> Int? {
        if let spaceIdx = s.firstIndex(of: " ") {
            if let v = Int(s[..<spaceIdx]) { return v }
        }
        return Int(s)
    }

    // MARK: - Port loader (probe 01)

    /// One USB-C port extracted from a probe's 01_walk_pd_tree.json.
    private struct ProbePort {
        let serviceName: String
        let portTypeDescription: String?
        let portNumber: Int
        let transportsSupported: [String]
        let transportsActive: [String]
        let connectionActive: Bool

        var hpmInterface: AppleHPMInterface {
            AppleHPMInterface(
                id: UInt64(portNumber),
                serviceName: serviceName,
                className: portTypeDescription == "MagSafe 3"
                    ? "AppleTCControllerType11"
                    : "AppleTCControllerType10",
                portDescription: serviceName,
                portTypeDescription: portTypeDescription,
                portNumber: portNumber,
                connectionActive: connectionActive,
                activeCable: nil,
                opticalCable: nil,
                usbActive: nil,
                superSpeedActive: nil,
                usbModeType: nil,
                usbConnectString: nil,
                transportsSupported: transportsSupported,
                transportsActive: transportsActive,
                transportsProvisioned: [],
                plugOrientation: nil,
                plugEventCount: nil,
                connectionCount: nil,
                overcurrentCount: nil,
                pinConfiguration: [:],
                powerCurrentLimits: [],
                firmwareVersion: nil,
                bootFlagsHex: nil,
                rawProperties: [:]
            )
        }
    }

    private static func loadPorts(folder: String) -> [ProbePort] {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("01_walk_pd_tree.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return [] }

        let rawChunks = text.components(separatedBy: "=== IOAccessoryManager[")
        guard rawChunks.count > 1 else { return [] }
        let parts: [String] = rawChunks.dropFirst().compactMap { chunk in
            guard let endOfHeader = chunk.range(of: "===\n") else { return nil }
            return String(chunk[endOfHeader.upperBound...])
        }
        var ports: [ProbePort] = []
        for raw in parts {
            let body: String
            if let endRange = raw.range(of: "\n=== ") {
                body = String(raw[..<endRange.lowerBound])
            } else {
                body = raw
            }
            guard body.contains("PortTypeDescription") else { continue }
            let portType = parseQuotedProp(body, key: "PortTypeDescription")
            let serviceName = parseQuotedProp(body, key: "Description") ?? "Port-Unknown@0"
            let portNumber = parseIntProp(body, key: "PortNumber") ?? 0
            let supp = parseListProp(body, key: "TransportsSupported")
            let act  = parseListProp(body, key: "TransportsActive")
            let conn = body.contains("ConnectionActive = true")
            ports.append(ProbePort(
                serviceName: serviceName,
                portTypeDescription: portType,
                portNumber: portNumber,
                transportsSupported: supp,
                transportsActive: act,
                connectionActive: conn
            ))
        }
        return ports
    }

    // Probe-01 field parsers (4-space indent in IOAccessoryManager blocks)
    private static func parseQuotedProp(_ block: String, key: String) -> String? {
        let prefix = "    \(key) = \""
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) {
                let after = line.dropFirst(prefix.count)
                guard let closing = after.firstIndex(of: "\"") else { return nil }
                return String(after[..<closing])
            }
        }
        return nil
    }

    private static func parseIntProp(_ block: String, key: String) -> Int? {
        let prefix = "    \(key) = "
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) {
                let after = line.dropFirst(prefix.count)
                let digits = after.prefix { $0.isNumber }
                return Int(digits)
            }
        }
        return nil
    }

    private static func parseListProp(_ block: String, key: String) -> [String] {
        let opener = "    \(key) = ["
        guard let openRange = block.range(of: opener) else { return [] }
        let afterOpen = block[openRange.upperBound...]
        guard let close = afterOpen.range(of: "\n    ]") else { return [] }
        let inside = afterOpen[..<close.lowerBound]
        return inside.split(separator: "\n").compactMap { line -> String? in
            guard let q1 = line.firstIndex(of: "\""),
                  let q2 = line.lastIndex(of: "\""), q1 != q2 else { return nil }
            return String(line[line.index(after: q1)..<q2])
        }
    }

    // MARK: - CIO block extractor

    /// Extract all CIO blocks from probe 17, combining both text styles
    /// (=== HPM deep-dive style and --- flat-services style).
    private static func extractCIOBlocks(text: String) -> [[String: Any]] {
        // The HPM section uses === style (4-space indent)
        var blocks = parseEqualsBlocks(text: text, className: "IOPortTransportStateCIO")
        // The flat "All IOPortTransportState* services" section uses --- style (2-space indent)
        blocks += parseDashBlocks(text: text, classPrefix: "IOPortTransportStateCIO")
        return blocks
    }

    // MARK: - Speed label validation

    /// Returns the expected speed label for a confirmed cableSpeed code,
    /// per cio-value-mappings.md. Only codes 2/3/4 are asserted.
    private static func confirmedSpeedLabel(for cableSpeed: Int) -> String? {
        switch cableSpeed {
        case 2: return "20 Gbps capable"   // TB3: one sample (M1 Max + Lenovo TB3 dock)
        case 3: return "40 Gbps capable"   // TB4: 19/27 data points in mapping doc
        case 4: return "80 Gbps capable"   // TB5: 7/27 data points in mapping doc
        default: return nil
        }
    }

    // MARK: - CIO Tests

    // MARK: (a1) CIO parse: every block produces a model, fields round-trip

    @Test("CIO parse: every active block produces a model and cableSpeed round-trips (probe 17)")
    func cioEveryBlockProducesModel() {
        let machines = Self.cioFixtureMachines

        var totalBlocks = 0
        var totalModels = 0
        var totalInactiveBlocks = 0

        for machine in machines {
            guard let text = Self.loadProbeText(folder: machine, probe: "17_deep_property_dump")
            else {
                Issue.record("Missing probe 17 for fixture machine \(machine)")
                continue
            }

            let blocks = Self.extractCIOBlocks(text: text)
            for (i, props) in blocks.enumerated() {
                totalBlocks += 1
                let read: (String) -> Any? = { props[$0] }
                let model = TRMTransportWatcher.makeCIOCapability(
                    entryID: UInt64(1000 + i),
                    read: read,
                    hpmControllerUUID: nil
                )

                // An explicit Active=false row means the CIO leg is not
                // currently up (often because the accessory is TRM-restricted),
                // even though a cable is seated, and is correctly dropped --
                // that's not a parse failure, so it's excluded from the
                // "every block produces a model" expectation below.
                if (props["Active"] as? NSNumber)?.boolValue == false {
                    totalInactiveBlocks += 1
                    #expect(model == nil,
                        "Machine \(machine) CIO block \(i): Active=false should be dropped, not produce a model")
                    continue
                }

                #expect(model != nil,
                    "Machine \(machine) CIO block \(i): makeCIOCapability should not return nil for a non-inactive block")
                guard let model else { continue }
                totalModels += 1

                // cableSpeed round-trips exactly
                if let speed = (props["CableSpeed"] as? NSNumber)?.intValue {
                    #expect(model.negotiatedLinkSpeed == speed,
                        "Machine \(machine) block \(i): cableSpeed round-trip: got \(model.negotiatedLinkSpeed ?? -1), expected \(speed)")
                }

                // cableGeneration round-trips (we don't assert semantic meaning here;
                // the mapping is not yet confirmed per cio-value-mappings.md)
                if let gen = (props["CableGeneration"] as? NSNumber)?.intValue {
                    #expect(model.cableGeneration == gen,
                        "Machine \(machine) block \(i): cableGeneration round-trip: got \(model.cableGeneration ?? -1), expected \(gen)")
                }

                // portKey is well-formed
                #expect(model.portKey.contains("/"),
                    "Machine \(machine) block \(i): portKey '\(model.portKey)' should contain '/'")
            }
        }

        #expect(totalBlocks >= 20,
            "Expected at least 20 CIO blocks across CIO fixtures; got \(totalBlocks)")
        #expect(totalModels == totalBlocks - totalInactiveBlocks,
            "Every non-inactive CIO block must produce a model: expected \(totalBlocks - totalInactiveBlocks), got \(totalModels)")
        #expect(totalInactiveBlocks == 2,
            "Expected exactly 2 inactive CIO blocks in the fixture set (m3max_macos26.5 port 2, m5_macos26.4_b port 1); got \(totalInactiveBlocks)")
    }

    // MARK: - (a6) CIO Active gate

    @Test("CIO Active gate: makeCIOCapability drops a row with Active=false")
    func makeCIOCapabilityDropsInactiveRow() {
        let props: [String: Any] = [
            "Active": NSNumber(value: false),
            "CableSpeed": NSNumber(value: 3),
            "ParentBuiltInPortType": NSNumber(value: 2),
            "ParentBuiltInPortNumber": NSNumber(value: 1),
        ]
        let model = TRMTransportWatcher.makeCIOCapability(
            entryID: 1,
            read: { props[$0] },
            hpmControllerUUID: nil
        )
        #expect(model == nil,
            "A CIO row with Active=false means the CIO leg is not currently up and must not produce a model")
    }

    @Test("CIO Active gate: makeCIOCapability keeps a row with Active=true")
    func makeCIOCapabilityKeepsActiveRow() {
        let props: [String: Any] = [
            "Active": NSNumber(value: true),
            "CableSpeed": NSNumber(value: 3),
            "ParentBuiltInPortType": NSNumber(value: 2),
            "ParentBuiltInPortNumber": NSNumber(value: 1),
        ]
        let model = TRMTransportWatcher.makeCIOCapability(
            entryID: 1,
            read: { props[$0] },
            hpmControllerUUID: nil
        )
        #expect(model != nil, "An Active=true row must still produce a model")
        #expect(model?.negotiatedLinkSpeed == 3)
    }

    @Test("CIO Active gate: makeCIOCapability keeps a row with no Active key at all")
    func makeCIOCapabilityKeepsRowWithoutActiveKey() {
        // Per the function's own doc comment, CIO has no hard gate key: any
        // IOPortTransportStateCIO service is a valid candidate. Absence of
        // Active must not be misread as an inactive row.
        let props: [String: Any] = [
            "CableSpeed": NSNumber(value: 3),
            "ParentBuiltInPortType": NSNumber(value: 2),
            "ParentBuiltInPortNumber": NSNumber(value: 1),
        ]
        let model = TRMTransportWatcher.makeCIOCapability(
            entryID: 1,
            read: { props[$0] },
            hpmControllerUUID: nil
        )
        #expect(model != nil,
            "CIO has no hard gate key; absence of Active must not be treated as inactive")
    }

    /// Corpus replay: the 4 real ports (re-derived and confirmed with two
    /// independent parsers) that carry a CIO row with Active=false while
    /// their only actually-active transport is CC -- a cable is seated
    /// (ConnectionActive/PlugOrientation on the port's own HPM node) but the
    /// CIO leg is not up, in 3 of 4 cases because the accessory is
    /// TRM-restricted/Unauthorized. That row must never reach a consumer as
    /// if it described a live link.
    @Test("CIO Active gate: inactive rows are dropped across the corpus")
    func cioInactiveRowsAreDroppedAcrossCorpus() {
        let machines = ["m1_macos27.0_p", "m3max_macos26.5", "m4_macos26.6", "m5_macos26.4_b"]
        var droppedCount = 0

        for machine in machines {
            guard let text = Self.loadProbeText(folder: machine, probe: "19_pdo_decode_and_usb3_watch")
            else {
                Issue.record("Missing probe 19 for \(machine); this corpus sweep cannot verify this port")
                continue
            }
            let blocks = Self.extractCIOBlocks(text: text)
            guard !blocks.isEmpty else {
                Issue.record("No CIO blocks found in probe 19 for \(machine); this corpus sweep cannot verify this port")
                continue
            }

            var sawInactiveBlock = false
            for (i, props) in blocks.enumerated() {
                let read: (String) -> Any? = { props[$0] }
                let model = TRMTransportWatcher.makeCIOCapability(
                    entryID: UInt64(3000 + i),
                    read: read,
                    hpmControllerUUID: nil
                )
                let isActive = (props["Active"] as? NSNumber)?.boolValue

                if isActive == false {
                    sawInactiveBlock = true
                    droppedCount += 1
                    #expect(model == nil,
                        "\(machine) CIO block \(i): Active=false must be dropped, but produced a model")
                } else if isActive == true {
                    #expect(model != nil,
                        "\(machine) CIO block \(i): Active=true must still produce a model")
                }
            }

            #expect(sawInactiveBlock,
                "\(machine): expected an Active=false CIO block in probe 19; found none")
        }

        #expect(droppedCount == 4,
            "Expected exactly 4 dropped CIO rows across the named ports (m1_macos27.0_p port 1, m3max_macos26.5 port 2, m4_macos26.6 port 1, m5_macos26.4_b port 1); got \(droppedCount)")
    }

    // MARK: (a1b) CIO invariant: LinkTrainingMode <= CableGeneration

    /// Settled 2026-07-22: `CableGeneration` and `LinkTrainingMode` are DISTINCT
    /// fields, not the "same value" once believed. `CableGeneration` is the cable
    /// capability ceiling; `LinkTrainingMode` is the tier the link actually
    /// trained to. The trained result can never exceed the cable's capability, so
    /// across the whole corpus `LinkTrainingMode <= CableGeneration` in every
    /// block where both are present, and it is `<` on exactly one block
    /// (`m3pro_macos26.5.2_g`, a Gen-4 cable trained down by a TB3 dock).
    ///
    /// The two guard `#expect`s below keep this test from passing vacuously:
    /// the corpus MUST contain at least one equal pair (the common case) AND at
    /// least one strict-< pair (the discriminating case). If the divergent
    /// fixture is ever dropped, the strict-< guard fails loudly rather than the
    /// invariant silently degrading to "all pairs equal". See
    /// `research/cio-value-mappings.md`, "2026-07-22 ... settled".
    @Test("CIO invariant: LinkTrainingMode <= CableGeneration across the corpus (never above)")
    func ltmNeverExceedsCableGeneration() {
        var pairsChecked = 0
        var equalPairs = 0
        var strictlyLessPairs = 0
        var strictlyLessMachines: [String] = []

        for machine in Self.cioFixtureMachines {
            guard let text = Self.loadProbeText(folder: machine, probe: "17_deep_property_dump")
            else {
                Issue.record("Missing probe 17 for fixture machine \(machine)")
                continue
            }
            for props in Self.extractCIOBlocks(text: text) {
                guard let cg = (props["CableGeneration"] as? NSNumber)?.intValue,
                      let ltm = (props["LinkTrainingMode"] as? NSNumber)?.intValue
                else { continue }
                pairsChecked += 1

                // The invariant: a trained-link result never exceeds the cable's
                // capability ceiling.
                #expect(ltm <= cg,
                    "\(machine): LinkTrainingMode (\(ltm)) must not exceed CableGeneration (\(cg))")

                if ltm == cg { equalPairs += 1 }
                if ltm < cg {
                    strictlyLessPairs += 1
                    strictlyLessMachines.append(machine)
                }
            }
        }

        // Non-vacuity guards: the boundary must actually be exercised on BOTH
        // sides, not just the trivial equal case.
        #expect(equalPairs >= 1,
            "Expected at least one CableGeneration == LinkTrainingMode block (the common case); got \(equalPairs)")
        #expect(strictlyLessPairs >= 1,
            "Expected at least one CableGeneration > LinkTrainingMode block (the strict boundary case, m3pro_macos26.5.2_g); got \(strictlyLessPairs). If this fails, the divergent fixture was dropped and the invariant test is now vacuous.")
        #expect(strictlyLessMachines.contains("m3pro_macos26.5.2_g"),
            "The known strict-< block (m3pro_macos26.5.2_g) must be among the fixtures; got \(strictlyLessMachines)")
        #expect(pairsChecked >= 10,
            "Expected the CIO fixtures to carry >= 10 blocks with both fields; got \(pairsChecked)")
    }

    // MARK: (a2) CIO speedLabel: confirmed mapping cross-check

    @Test("CIO speedLabel: confirmed codes map to the right Gbps label per cio-value-mappings.md")
    func cioSpeedLabelMapping() {
        // The cio-value-mappings.md mapping doc confirms:
        //   2 -> "20 Gbps capable" (TB3 class, 1 sample)
        //   3 -> "40 Gbps capable" (TB4 class, 19 samples)
        //   4 -> "80 Gbps capable" (TB5 class, 7 samples)
        // Unknown codes return nil. Assert only the confirmed range.
        #expect(CIOCableCapability.speedLabel(for: 2) == "20 Gbps capable")
        #expect(CIOCableCapability.speedLabel(for: 3) == "40 Gbps capable")
        #expect(CIOCableCapability.speedLabel(for: 4) == "80 Gbps capable")
        #expect(CIOCableCapability.speedLabel(for: 0) == nil)
        #expect(CIOCableCapability.speedLabel(for: 1) == nil)
        #expect(CIOCableCapability.speedLabel(for: 5) == nil)
    }

    // MARK: (a3) CIO per-machine: corpus-specific cableSpeed verdicts

    @Test("CIO per-machine: TB5 machines report cableSpeed=4, TB3 connection reports cableSpeed=2")
    func cioPerMachineSpeedExpectations() {
        // m5pro_macos26.5: CalDigit TS5 Plus (JHL9580), M5 Pro, Type7 host.
        // Per cio-value-mappings.md data point 9: CableSpeed=4 (TB5).
        assertCIOActiveSpeed(
            machine: "m5pro_macos26.5",
            expectedSpeed: 4,
            reason: "M5 Pro + CalDigit TS5 Plus (JHL9580) = TB5 link (data point 9 in mapping doc)"
        )

        // m4pro_macos26.5: Type7 host with TB5 CIO (our probe data shows speed=4)
        assertCIOActiveSpeed(
            machine: "m4pro_macos26.5",
            expectedSpeed: 4,
            reason: "M4 Pro + TB5 peer (Type7 host) = TB5 link"
        )

        // m4max_macos26.5_f block 1: speed=2 (TB3 class, JHL6540 Alpine Ridge equivalent).
        // This is the only TB3 speed=2 in our fixture set.
        assertCIOBlockContainsSpeed(
            machine: "m4max_macos26.5_f",
            requiredSpeed: 2,
            reason: "m4max_macos26.5_f has a TB3-class connection (CableSpeed=2) on one port"
        )

        // m4max_macos26.5_c block 1: speed=4 (TB5 port among mixed-speed blocks)
        assertCIOBlockContainsSpeed(
            machine: "m4max_macos26.5_c",
            requiredSpeed: 4,
            reason: "m4max_macos26.5_c has a TB5 port (CableSpeed=4) in its mixed-class setup"
        )
    }

    // MARK: (a4) CIO: legacyAdapter is always false across the corpus

    @Test("CIO legacyAdapter: always false across all fixture machines (mapping doc: never observed true)")
    func cioLegacyAdapterAlwaysFalse() {
        // Per cio-value-mappings.md: LegacyAdapter has been false on every
        // sampled connection including real TB3 docks. A true value would indicate
        // TB3-mode lane adapter; Apple Silicon apparently never sets it.
        for machine in Self.cioFixtureMachines {
            guard let text = Self.loadProbeText(folder: machine, probe: "17_deep_property_dump")
            else { continue }
            let blocks = Self.extractCIOBlocks(text: text)
            for (i, props) in blocks.enumerated() {
                let legacyRaw = props["LegacyAdapter"]
                // When present it must be false; when absent that is also expected
                if let legacy = (legacyRaw as? NSNumber)?.boolValue {
                    #expect(legacy == false,
                        "Machine \(machine) block \(i): LegacyAdapter should be false; mapping doc has never seen it true")
                }
            }
        }
    }

    // MARK: (a5) CIO: asymmetricModeSupported is a cable property (per-port variance)

    @Test("CIO asymmetricModeSupported: m3_macos26.5 reports false (cable does not support asymmetric)")
    func cioAsymmetricModePerCable() {
        // m3_macos26.5 probe shows AsymmetricModeSupported=false on the one CIO block.
        // Per cio-value-mappings.md, this is a cable-state property (PORT_CS_18.CSA)
        // populated per-connection from VDM exchange; it reflects the cable/link partner,
        // not the host port. Different machines with different cables can show different values.
        guard let text = Self.loadProbeText(folder: "m3_macos26.5", probe: "17_deep_property_dump")
        else {
            Issue.record("Missing probe 17 for m3_macos26.5")
            return
        }
        let blocks = Self.extractCIOBlocks(text: text)
        #expect(!blocks.isEmpty, "m3_macos26.5 should have at least one CIO block")

        var foundFalse = false
        for (i, props) in blocks.enumerated() {
            if let asym = (props["AsymmetricModeSupported"] as? NSNumber)?.boolValue, asym == false {
                let read: (String) -> Any? = { props[$0] }
                let model = TRMTransportWatcher.makeCIOCapability(
                    entryID: UInt64(i),
                    read: read,
                    hpmControllerUUID: nil
                )
                #expect(model?.asymmetricModeSupported == false,
                    "m3_macos26.5: parsed CIO model should carry asymmetricModeSupported=false")
                foundFalse = true
                break
            }
        }
        #expect(foundFalse,
            "m3_macos26.5: expected at least one CIO block with AsymmetricModeSupported=false")
    }

    // MARK: (a7) CIO: TRM-restricted CIO block (m3max_macos26.5 port @2)

    @Test("CIO TRM restricted: m3max_macos26.5 port @2 CIO block has transportRestricted=true, and is the same Active=false row")
    func cioTRMRestrictedBlock() {
        // m3max_macos26.5 inspection.md: 1 port restricted. Probe 17 shows
        // IOPortTransportStateCIO on port @2 with TRM_TransportRestricted=true
        // and CableSpeed=3 (TB4 class). This same block also carries
        // Active=false: the CIO leg is not currently up on this
        // TRM-restricted/Unauthorized port, even though a cable is seated.
        // The raw fields this test is about still round-trip out of the
        // property dict; the parsed model is now correctly nil rather than
        // describing a link that is not actually live.
        guard let text = Self.loadProbeText(folder: "m3max_macos26.5", probe: "17_deep_property_dump")
        else {
            Issue.record("Missing probe 17 for m3max_macos26.5")
            return
        }
        let blocks = Self.extractCIOBlocks(text: text)
        var foundRestrictedCIOBlock = false
        for (i, props) in blocks.enumerated() {
            let isRestricted = (props["TRM_TransportRestricted"] as? NSNumber)?.boolValue == true
            guard isRestricted else { continue }

            #expect((props["CableSpeed"] as? NSNumber)?.intValue == 3,
                "m3max_macos26.5: restricted CIO block should still carry raw cableSpeed=3 (TB4)")
            #expect((props["Active"] as? NSNumber)?.boolValue == false,
                "m3max_macos26.5: the TRM-restricted CIO block is expected to be the same Active=false row")

            let read: (String) -> Any? = { props[$0] }
            let model = TRMTransportWatcher.makeCIOCapability(
                entryID: UInt64(i),
                read: read,
                hpmControllerUUID: nil
            )
            #expect(model == nil,
                "m3max_macos26.5: TRM-restricted CIO block is also Active=false and must be dropped")
            foundRestrictedCIOBlock = true
        }
        #expect(foundRestrictedCIOBlock,
            "m3max_macos26.5: expected at least one CIO block with TRM_TransportRestricted=true")
    }

    // MARK: (a8) CIO: cableSpeed range across the corpus

    @Test("CIO cableSpeed: only values 2, 3, 4 appear across fixture machines")
    func cioCableSpeedRangeCheck() {
        var allSpeeds = Set<Int>()
        for machine in Self.cioFixtureMachines {
            guard let text = Self.loadProbeText(folder: machine, probe: "17_deep_property_dump")
            else { continue }
            for props in Self.extractCIOBlocks(text: text) {
                if let speed = (props["CableSpeed"] as? NSNumber)?.intValue {
                    allSpeeds.insert(speed)
                }
            }
        }
        // The mapping doc confirms only 2, 3, 4 are observed across 27 data points.
        let unexpected = allSpeeds.subtracting([2, 3, 4])
        #expect(unexpected.isEmpty,
            "Unexpected cableSpeed values in corpus: \(unexpected). The mapping doc only confirms 2, 3, 4.")
        // All three should appear across our fixture set
        #expect(allSpeeds.contains(2), "Expected cableSpeed=2 (TB3) in fixture set (m4max_macos26.5_f)")
        #expect(allSpeeds.contains(3), "Expected cableSpeed=3 (TB4) in fixture set")
        #expect(allSpeeds.contains(4), "Expected cableSpeed=4 (TB5) in fixture set")
    }

    // MARK: - DataLink Diagnostic Tests

    // MARK: (b1) TRM-restricted ports: DataLink must return .blockedBySecurity

    @Test("DataLink TRM-restricted: restricted USB3 ports yield .blockedBySecurity verdict (DAR-134)")
    func dataLinkTRMRestrictedBlockedBySecurity() {
        // DAR-134 fix: when macOS TRM blocks a port's USB3 transport,
        // DataLinkDiagnostic must now emit .blockedBySecurity instead of .fine.
        // USB3Transport now carries `transportRestricted` (from TRM_TransportRestricted)
        // and DataLinkDiagnostic short-circuits to the new verdict when it is true.
        //
        // Fixtures m1pro_macos26.5_d and m3_macos26.5_d have probe 19 data with
        // TRM_TransportRestricted=true on their restricted USB3 transport. These
        // were the machines that previously produced the false .fine verdict.

        let restrictedMachines: [(folder: String, restrictedPortKeys: Set<String>)] = [
            // m1pro_macos26.5_d: portKey 2/2 restricted (USB2+USB3)
            ("m1pro_macos26.5_d", ["2/2"]),
            // m3_macos26.5_d: portKey 2/2 restricted (USB2+USB3)
            ("m3_macos26.5_d", ["2/2"]),
        ]

        for (folder, restrictedKeys) in restrictedMachines {
            guard let text17 = Self.loadProbeText(folder: folder, probe: "17_deep_property_dump"),
                  let text19 = Self.loadProbeText(folder: folder, probe: "19_pdo_decode_and_usb3_watch")
            else {
                Issue.record("Missing probe 17/19 for \(folder)")
                continue
            }

            // Parse USB3 transports from probe 19 (now includes transportRestricted)
            let usb3Props = Self.parseDashBlocks(text: text19, classPrefix: "IOPortTransportStateUSB3")
            let usb3Transports: [USB3Transport] = usb3Props.enumerated().compactMap { (i, props) in
                let read: (String) -> Any? = { props[$0] }
                return USB3TransportWatcher.makeTransport(entryID: UInt64(2000 + i), read: read, hpmControllerUUID: nil)
            }

            // Parse CIO capabilities from probe 17
            let cioBlocks = Self.extractCIOBlocks(text: text17)
            let cioCapabilities: [CIOCableCapability] = cioBlocks.enumerated().compactMap { (i, props) in
                let read: (String) -> Any? = { props[$0] }
                return TRMTransportWatcher.makeCIOCapability(entryID: UInt64(1000 + i), read: read, hpmControllerUUID: nil)
            }

            // Load ports from probe 01
            let ports = Self.loadPorts(folder: folder)
            let usbCPorts = ports.filter { $0.portTypeDescription == "USB-C" }

            for port in usbCPorts {
                let suffix = String(port.serviceName.split(separator: "@").last ?? "")
                let portKey = "2/\(suffix)"
                guard restrictedKeys.contains(portKey) else { continue }

                let cio = cioCapabilities.first { $0.portKey == portKey }
                let usb3 = usb3Transports.filter { $0.portKey == portKey }

                let hpm = port.hpmInterface
                let diag = DataLinkDiagnostic(
                    port: hpm,
                    identities: [],
                    devices: [],
                    usb3Transports: usb3,
                    cio: cio,
                    thunderboltSwitches: []
                )

                if let diag {
                    // After the DAR-134 fix: restricted ports with a resolvable USB3
                    // signaling rate must produce .blockedBySecurity, not .fine.
                    guard case .blockedBySecurity = diag.bottleneck else {
                        Issue.record("Expected .blockedBySecurity on TRM-restricted port \(portKey) in \(folder), got \(diag.bottleneck)")
                        continue
                    }
                    #expect(diag.isWarning, "blockedBySecurity must be a warning verdict")
                }
                // nil is also acceptable: the diagnostic can abstain when there is
                // no USB3 transport to gate on (e.g. only USB2 restricted, no USB3).
            }
        }
    }

    // MARK: (b2) DataLink: connected USB-C ports with USB3 active produce a verdict

    @Test("DataLink inputs: connected USB3-active ports resolve a verdict from probe 17/19 inputs")
    func dataLinkConnectedUSB3ActivePorts() {
        // For each CIO fixture machine: find USB-C ports that were connected and
        // had USB3 in transportsActive at capture time. Build DataLink inputs from
        // the USB3 transports in probes 17/19.
        //
        // issue #181: DataLinkDiagnostic now requires corroboration
        // (an enumerated SuperSpeed device, or a TRM-restricted transport)
        // before it will produce a verdict at all, to suppress the transient
        // "USB3 active but no data peer" handshake reading. This file (per
        // its own doc comment) deliberately does not reconstruct device data
        // from probe 38 -- correlating a device to a physical port needs
        // live `controllerPortName`/`busIndex` data flat probe text doesn't
        // carry cleanly (see `Probe38TreeWalkTests`'s doc comment for the
        // same limitation elsewhere). Without device data, corroboration can
        // only come from a TRM-restricted transport, and every fixture
        // machine's active-USB3 ports happen to have neither (their
        // restricted ports run USB2, not USB3; see the m2pro_macos26.4.1
        // case checked at ingest time). So the correct, issue #181-aware
        // expectation for THIS test is zero verdicts, not "at least one" --
        // asserting otherwise would either be vacuous or require the device
        // reconstruction this file explicitly scopes out. `examineCount`
        // still proves the fixture set has active-USB3 ports to examine, so
        // this isn't a vacuous pass.
        let machines = Self.cioFixtureMachines + Self.trmFixtureMachines

        var examineCount = 0
        var gotVerdictCount = 0

        for machine in machines {
            guard let text17 = Self.loadProbeText(folder: machine, probe: "17_deep_property_dump"),
                  let text19 = Self.loadProbeText(folder: machine, probe: "19_pdo_decode_and_usb3_watch")
            else { continue }

            let usb3Props = Self.parseDashBlocks(text: text19, classPrefix: "IOPortTransportStateUSB3")
            let usb3Transports: [USB3Transport] = usb3Props.enumerated().compactMap { (i, props) in
                USB3TransportWatcher.makeTransport(entryID: UInt64(2000 + i), read: { props[$0] }, hpmControllerUUID: nil)
            }

            let cioBlocks = Self.extractCIOBlocks(text: text17)
            let cioCapabilities: [CIOCableCapability] = cioBlocks.enumerated().compactMap { (i, props) in
                TRMTransportWatcher.makeCIOCapability(entryID: UInt64(1000 + i), read: { props[$0] }, hpmControllerUUID: nil)
            }

            let ports = Self.loadPorts(folder: machine)
            for port in ports where port.portTypeDescription == "USB-C"
                                 && port.connectionActive
                                 && port.transportsActive.contains("USB3") {
                examineCount += 1
                let hpm = port.hpmInterface
                let suffix = String(port.serviceName.split(separator: "@").last ?? "")
                let portKey = "2/\(suffix)"
                let cio = cioCapabilities.first { $0.portKey == portKey }
                let usb3 = usb3Transports.filter { $0.portKey == portKey }

                let diag = DataLinkDiagnostic(
                    port: hpm,
                    identities: [],
                    devices: [],
                    usb3Transports: usb3,
                    cio: cio,
                    thunderboltSwitches: []
                )
                if diag != nil { gotVerdictCount += 1 }
            }
        }

        // We should examine at least a few such ports across the fixture set
        // (proves this sweep is not vacuous), but per issue #181 (see above),
        // none of them should produce a verdict without device data.
        #expect(examineCount > 0,
            "Expected at least one connected USB3-active port in the fixture set to examine; found none")
        #expect(gotVerdictCount == 0,
            "issue #181: expected zero verdicts without device-corroboration data (see comment above); got \(gotVerdictCount) out of \(examineCount) examined. If this now fails because some port has TRM-restricted USB3 data, that's a legitimate new corroborated verdict -- update this expectation, don't revert it.")
    }

    // MARK: (b3) DataLink: CIO-active ports (CIO in transportsActive) resolve TB rate

    @Test("DataLink inputs: CIO-active ports require tbActiveGbps to produce a verdict")
    func dataLinkCIOActivePortsNeedTBRate() {
        // DataLinkDiagnostic.activeTBGbps() requires:
        //   (1) CIO in transportsActive, AND
        //   (2) a non-empty thunderboltSwitches array
        // Without (2), the diagnostic returns nil even for CIO-active ports.
        // This test confirms that without switch data, the diagnostic abstains.
        // With an explicit tbActiveGbps override it should produce a verdict.
        guard let text = Self.loadProbeText(folder: "m5pro_macos26.5", probe: "17_deep_property_dump")
        else {
            Issue.record("Missing probe 17 for m5pro_macos26.5")
            return
        }

        let cioBlocks = Self.extractCIOBlocks(text: text)
        let cio = cioBlocks.first.flatMap { props -> CIOCableCapability? in
            TRMTransportWatcher.makeCIOCapability(entryID: 1, read: { props[$0] }, hpmControllerUUID: nil)
        }
        #expect(cio != nil, "m5pro_macos26.5 should have a CIO capability model")
        #expect(cio?.negotiatedLinkSpeed == 4, "m5pro_macos26.5 should have cableSpeed=4 (TB5)")

        let ports = Self.loadPorts(folder: "m5pro_macos26.5")
        guard let cioPort = ports.first(where: { $0.transportsActive.contains("CIO") }) else {
            // Not all probe captures have CIO in TransportsActive even when CIO blocks exist
            // (the port may show USB3 as active while CIO is the TB-level transport).
            // This is expected; skip gracefully.
            return
        }
        let hpm = cioPort.hpmInterface

        // Without switch data: should abstain (can't resolve TB rate without switch graph)
        let diagNoSwitches = DataLinkDiagnostic(
            port: hpm,
            identities: [],
            devices: [],
            usb3Transports: [],
            cio: cio,
            thunderboltSwitches: []
        )
        #expect(diagNoSwitches == nil,
            "m5pro_macos26.5 CIO-active port without switch data should produce nil (no active rate)")

        // With explicit tbActiveGbps (test seam): should produce a verdict using CIO speed
        let diagWithRate = DataLinkDiagnostic(
            port: hpm,
            identities: [],
            devices: [],
            usb3Transports: [],
            cio: cio,
            thunderboltSwitches: [],
            tbActiveGbps: 80   // matches cableSpeed=4 -> 80 Gbps
        )
        #expect(diagWithRate != nil,
            "m5pro_macos26.5 CIO-active port with explicit tbActiveGbps should produce a verdict")
        if let diag = diagWithRate {
            #expect(diag.facts.activeGbps == 80,
                "m5pro_macos26.5: activeGbps should be 80 when tbActiveGbps=80")
            // With no cable e-marker or device data the verdict should be .unknownCable
            if case .unknownCable(let active) = diag.bottleneck {
                #expect(active == 80, "m5pro_macos26.5: unknownCable active rate should be 80")
            }
        }
    }

    // MARK: (b4) DataLink: CIO cable speed is used when both CIO and USB3 are available

    @Test("DataLink inputs: CIO cableGbps is preferred over USB3 signaling when TB link is active")
    func dataLinkCIOSpeedPreferredOverUSB3() {
        // m3max_macos26.5 port @1 (block 1): CIO active=true, cableSpeed=3 (40 Gbps, TB4).
        // The USB3 transport for the same port would give 5 or 10 Gbps.
        // With explicit tbActiveGbps=40, the facts should show cableControllerGbps=40.
        guard let text17 = Self.loadProbeText(folder: "m3max_macos26.5", probe: "17_deep_property_dump"),
              let text19 = Self.loadProbeText(folder: "m3max_macos26.5", probe: "19_pdo_decode_and_usb3_watch")
        else {
            Issue.record("Missing probe 17/19 for m3max_macos26.5")
            return
        }

        let cioBlocks = Self.extractCIOBlocks(text: text17)
        // Find the active CIO block (cableSpeed=3, portKey=2/1, active=true)
        var activeCIO: CIOCableCapability? = nil
        for (i, props) in cioBlocks.enumerated() {
            let isActive = (props["Active"] as? NSNumber)?.boolValue == true
            let speed = (props["CableSpeed"] as? NSNumber)?.intValue ?? 0
            guard isActive, speed == 3 else { continue }
            let read: (String) -> Any? = { props[$0] }
            activeCIO = TRMTransportWatcher.makeCIOCapability(entryID: UInt64(i), read: read, hpmControllerUUID: nil)
            break
        }
        #expect(activeCIO != nil, "m3max_macos26.5: should find an active CIO block with cableSpeed=3")
        #expect(activeCIO?.negotiatedLinkSpeed == 3, "m3max_macos26.5: active CIO block speed should be 3")

        // USB3 transports from probe 19
        let usb3Props = Self.parseDashBlocks(text: text19, classPrefix: "IOPortTransportStateUSB3")
        let usb3Transports: [USB3Transport] = usb3Props.enumerated().compactMap { (i, props) in
            USB3TransportWatcher.makeTransport(entryID: UInt64(2000 + i), read: { props[$0] }, hpmControllerUUID: nil)
        }

        // Get the port for portKey 2/1
        let ports = Self.loadPorts(folder: "m3max_macos26.5")
        guard let port = ports.first(where: { $0.serviceName.hasSuffix("@1") && $0.portTypeDescription == "USB-C" })
        else {
            // Accept gracefully -- probe may not expose the port we need
            return
        }
        let hpm = port.hpmInterface
        let usb3ForPort = usb3Transports.filter { $0.portKey == "2/1" }

        // With explicit tbActiveGbps=40, CIO should fill in cableControllerGbps
        let diag = DataLinkDiagnostic(
            port: hpm,
            identities: [],
            devices: [],
            usb3Transports: usb3ForPort,
            cio: activeCIO,
            thunderboltSwitches: [],
            tbActiveGbps: 40
        )
        #expect(diag != nil, "m3max_macos26.5 port @1: should produce a DataLink verdict")
        if let diag {
            #expect(diag.facts.cableControllerGbps == 40,
                "m3max_macos26.5: CIO cableControllerGbps should be 40 (cableSpeed=3 -> 40 Gbps)")
            #expect(diag.facts.activeGbps == 40,
                "m3max_macos26.5: activeGbps should be 40 (tbActiveGbps=40)")
        }
    }

    // MARK: (b5) DataLink: USB3 input from probe 19 produces correct signaling

    @Test("DataLink inputs: USB3 transport from probe 19 correctly resolves Gen1/Gen2 signaling")
    func dataLinkUSB3SignalingFromProbe19() {
        // m3_macos26.5_d probe 19: USB3 block with signaling=2 (10 Gbps, Gen 2).
        // m1pro_macos26.5_d probe 19: USB3 block with signaling=1 (5 Gbps, Gen 1).
        // Verify that USB3TransportWatcher.makeTransport parses signaling correctly
        // and that DataLinkDiagnostic uses the USB3 active rate.

        let cases: [(folder: String, expectedSignaling: Int, expectedGbps: Double)] = [
            ("m3_macos26.5_d", 2, 10),     // USB 3.2 Gen 2 (10 Gbps)
            ("m1pro_macos26.5_d", 1, 5),   // USB 3.2 Gen 1 (5 Gbps)
        ]

        for (folder, expectedSignaling, expectedGbps) in cases {
            guard let text19 = Self.loadProbeText(folder: folder, probe: "19_pdo_decode_and_usb3_watch")
            else {
                Issue.record("Missing probe 19 for \(folder)")
                continue
            }

            let usb3Props = Self.parseDashBlocks(text: text19, classPrefix: "IOPortTransportStateUSB3")
            let transports: [USB3Transport] = usb3Props.enumerated().compactMap { (i, props) in
                USB3TransportWatcher.makeTransport(entryID: UInt64(i), read: { props[$0] }, hpmControllerUUID: nil)
            }

            #expect(!transports.isEmpty,
                "\(folder): expected USB3 transport(s) from probe 19")

            // Find the transport with the expected signaling
            let matched = transports.first { $0.signaling == expectedSignaling }
            #expect(matched != nil,
                "\(folder): expected USB3 transport with signaling=\(expectedSignaling); got \(transports.map { $0.signaling ?? -1 })")

            // Build a minimal port with USB3 active (using portKey matching from the transport)
            if let t = matched {
                let parts = t.portKey.split(separator: "/")
                let portNum = Int(parts.last ?? "2") ?? 2
                let testPort = AppleHPMInterface(
                    id: UInt64(portNum),
                    serviceName: "Port-USB-C@\(portNum)",
                    className: "AppleTCControllerType10",
                    portDescription: "Port-USB-C@\(portNum)",
                    portTypeDescription: "USB-C",
                    portNumber: portNum,
                    connectionActive: true,
                    activeCable: nil,
                    opticalCable: nil,
                    usbActive: nil,
                    superSpeedActive: nil,
                    usbModeType: nil,
                    usbConnectString: nil,
                    transportsSupported: ["USB3", "USB2"],
                    transportsActive: ["USB3", "USB2"],
                    transportsProvisioned: [],
                    plugOrientation: nil,
                    plugEventCount: nil,
                    connectionCount: nil,
                    overcurrentCount: nil,
                    pinConfiguration: [:],
                    powerCurrentLimits: [],
                    firmwareVersion: nil,
                    bootFlagsHex: nil,
                    rawProperties: [:]
                )
                let diag = DataLinkDiagnostic(
                    port: testPort,
                    identities: [],
                    devices: [],
                    usb3Transports: [t],
                    cio: nil,
                    thunderboltSwitches: []
                )
                #expect(diag != nil,
                    "\(folder): DataLink should produce a verdict for a connected USB3-active port with signaling=\(expectedSignaling)")
                if let diag {
                    #expect(diag.facts.activeGbps == expectedGbps,
                        "\(folder): activeGbps should be \(expectedGbps) for signaling=\(expectedSignaling)")
                }
            }
        }
    }

    // MARK: - Fixture machine lists (file-private)

    private static let cioFixtureMachines: [String] = [
        "m4max_macos26.5_c",   // 4 CIO blocks, desktop M4 Max Type7, mixed TB3/TB4/TB5
        "m5pro_macos26.5",     // 1 CIO block, M5 Pro laptop, TB5 (speed=4)
        "m4pro_macos26.5",     // 1 CIO block, M4 Pro laptop Type7, TB5 (speed=4)
        "m3max_macos26.5",     // 2 CIO blocks, M3 Max laptop Type5, 1 restricted
        "m3_macos26.5",        // 1 CIO block, M3 base Type5, asymm=false
        "m3pro_macos26.5_d",   // 1 CIO block, M3 Pro Type5
        "m4_macos26.3",        // 1 CIO block, M4 Type5
        "m4_macos26.5_b",      // 3 CIO blocks, M4 Type5, mixed cableGeneration
        "m4max_macos26.5_f",   // 2 CIO blocks, M4 Max Type7, 1 TB3 (speed=2)
        "m5_macos26.4_b",      // 1 CIO block, M5 Type7, TRM-restricted
        "m5pro_macos26.5.1",   // 2 CIO blocks, M5 Pro Type7
        "m4max_macos15.7.7",   // 1 CIO block, M4 Max macOS 15 (older OS coverage)
        "m3pro_macos26.5.2_g", // 1 CIO block, Kensington SD5600T TB3 dock (JHL7440):
                               // the ONLY corpus block where CableGeneration (2) >
                               // LinkTrainingMode (1). The strict-< boundary case
                               // for the ltmNeverExceedsCableGeneration invariant.
    ]

    private static let trmFixtureMachines: [String] = [
        "m1pro_macos26.5_d",   // 2 restricted ports (USB2+USB3), zeroed VID cable
        "m3_macos26.5_d",      // 4 restricted ports (USB2+USB3)
        "m2pro_macos26.4.1",   // 3 restricted ports (USB3 on 2 ports)
    ]

    // MARK: - Assertion helpers (file-private)

    /// Assert that the machine's probe 17 contains exactly one active CIO block
    /// with the expected cableSpeed. Fails if the machine is missing or the
    /// speed doesn't match.
    private func assertCIOActiveSpeed(machine: String, expectedSpeed: Int, reason: String) {
        guard let text = Self.loadProbeText(folder: machine, probe: "17_deep_property_dump")
        else {
            Issue.record("Missing probe 17 for \(machine): \(reason)")
            return
        }
        let blocks = Self.extractCIOBlocks(text: text)
        // Look for an active block with the expected speed
        let activeMatches = blocks.filter { props in
            let isActive = (props["Active"] as? NSNumber)?.boolValue == true
            let speed = (props["CableSpeed"] as? NSNumber)?.intValue
            return isActive && speed == expectedSpeed
        }
        #expect(!activeMatches.isEmpty,
            "Machine \(machine): expected at least one active CIO block with cableSpeed=\(expectedSpeed). Reason: \(reason)")
    }

    /// Assert that the machine's probe 17 contains at least one CIO block
    /// (active or not) with the given cableSpeed.
    private func assertCIOBlockContainsSpeed(machine: String, requiredSpeed: Int, reason: String) {
        guard let text = Self.loadProbeText(folder: machine, probe: "17_deep_property_dump")
        else {
            Issue.record("Missing probe 17 for \(machine): \(reason)")
            return
        }
        let blocks = Self.extractCIOBlocks(text: text)
        let matched = blocks.filter { props in
            (props["CableSpeed"] as? NSNumber)?.intValue == requiredSpeed
        }
        #expect(!matched.isEmpty,
            "Machine \(machine): expected at least one CIO block with cableSpeed=\(requiredSpeed). Reason: \(reason)")
    }
}
