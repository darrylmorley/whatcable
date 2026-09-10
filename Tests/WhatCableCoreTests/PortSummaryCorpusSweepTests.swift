import Foundation
import Testing
@testable import WhatCableCore

/// Corpus-replay sweep for `PortSummary.init` (`Sources/WhatCableCore/Output/PortSummary.swift`),
/// the app's master per-port headline/status derivation. Before this file, nothing
/// in the corpus-replay suite exercised `PortSummary` directly against real
/// hardware data; every existing sweep (CIO, cable trust) feeds a narrower
/// downstream type instead.
///
/// This sweep builds the same inputs `ContentView`/`WidgetSnapshot` pass in
/// production, as far as a `WhatCableCoreTests`-only target can reconstruct
/// them from raw probe text:
///
/// - `port`: from probe 01's PD-tree walk (`AppleHPMInterface`, USB-C ports only).
/// - `identities`: SOP/SOP'/SOP'' entries from probe 01, matched to a port by
///   `parentPortNumber == port.portNumber`.
/// - `sources`: `PowerSource` built from probe 17/19's
///   `IOPortFeaturePowerSource` dash-style blocks, matched the same way.
///   `PowerSourceOptions` itself serialises as an opaque `<CFType 17>` in every
///   probe capture (never a decodable array), so `PowerSource.options` is
///   always empty here; only `winning` (the `WinningPowerSourceOption`
///   sub-dict) is real. `PortSummary`'s "Charger advertises up to NW" bullet
///   depends on `options`, so it never fires in this sweep; the "Currently
///   negotiated" bullet (which depends on `winning`) does.
/// - `cioCapability`: from probe 17/19's `IOPortTransportStateCIO` blocks,
///   filtered to `Active == true`, matched by the `portKey` derived the same
///   way `TRMTransportWatcher.parentPortIdentity` does (see the doc comment on
///   `DataLinkDiagnosticCIOCorpusTests`, which this file's CIO decode mirrors).
///
/// Not reconstructed (documented limitation, not faked): `devices` (USB device
/// to physical-port correlation needs live IOKit `controllerPortName`/`busIndex`
/// data that flat probe text doesn't carry (see `Probe38TreeWalkTests`'s and
/// `InternalHubPIDCorpusTests`'s doc comments for the same limitation on a
/// different type) and `thunderboltSwitches` (building an `IOThunderboltSwitch`
/// tree from probe 29 is a separate, much larger parser this file doesn't
/// attempt). Both default to empty, which only weakens the Thunderbolt-fabric
/// and device-listing bullets, not the core status/headline logic under test.
///
/// The sweep also feeds the port controller's own `ActiveCable` flag through
/// from probe 01, so `CableClassification.resolve` is exercised against real
/// hardware rather than a hardcoded nil. It asserts the exact set of corpus
/// ports the flag promotes from passive to active, that no port is ever
/// demoted the other way, that a VCONN-Powered Device is never promoted, and
/// that every other classifiable port keeps the e-marker's own verdict.
@Suite("PortSummary: corpus sweep")
struct PortSummaryCorpusSweepTests {

    // MARK: - Probe root / folder enumeration
    // Same resolution as the other WhatCableCoreTests corpus sweeps.

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private static func allFolders() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: probeRoot.path) else { return [] }
        return entries.filter { entry in
            var isDir: ObjCBool = false
            let path = probeRoot.appendingPathComponent(entry).path
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted()
    }

    private static func loadProbeText(folder: String, probe: String) -> String? {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent("\(probe).json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Probe 01: ports
    // Copied from DataLinkDiagnosticCIOCorpusTests.ProbePort / loadPorts (same
    // target) -- see that file's type-level doc comment for why this is a
    // deliberate copy (Swift `private` is file-scoped) rather than a shared
    // internal helper.

    private struct ProbePort {
        let serviceName: String
        let portTypeDescription: String?
        let portNumber: Int
        let transportsSupported: [String]
        let transportsActive: [String]
        let connectionActive: Bool
        /// The port controller's own `ActiveCable` verdict, nil when this
        /// probe never published the key for the port.
        let activeCable: Bool?

        var asAppleHPMInterface: AppleHPMInterface {
            AppleHPMInterface(
                id: UInt64(portNumber),
                serviceName: serviceName,
                className: "AppleHPMInterfaceType10",
                portDescription: serviceName,
                portTypeDescription: portTypeDescription,
                portNumber: portNumber,
                connectionActive: connectionActive,
                activeCable: activeCable,
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
        guard let text = loadProbeText(folder: folder, probe: "01_walk_pd_tree") else { return [] }

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

            let portType = parseQuoted(body, key: "PortTypeDescription")
            let serviceName = parseQuoted(body, key: "Description") ?? "Port-Unknown@0"
            let portNumber = parseInt(body, key: "PortNumber") ?? 0
            let supp = parseList(body, key: "TransportsSupported")
            let act = parseList(body, key: "TransportsActive")
            let conn = body.contains("ConnectionActive = true")
            let active = parseBool(body, key: "ActiveCable")

            ports.append(ProbePort(
                serviceName: serviceName,
                portTypeDescription: portType,
                portNumber: portNumber,
                transportsSupported: supp,
                transportsActive: act,
                connectionActive: conn,
                activeCable: active
            ))
        }
        return ports
    }

    private static func parseQuoted(_ block: String, key: String) -> String? {
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

    private static func parseInt(_ block: String, key: String) -> Int? {
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

    /// nil when the key is absent, so a probe that never published it stays
    /// unknown rather than becoming false.
    private static func parseBool(_ block: String, key: String) -> Bool? {
        let prefix = "    \(key) = "
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) {
                let after = line.dropFirst(prefix.count)
                if after.hasPrefix("true") { return true }
                if after.hasPrefix("false") { return false }
                return nil
            }
        }
        return nil
    }

    private static func parseList(_ block: String, key: String) -> [String] {
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

    // MARK: - Probe 01: SOP identities
    // Copied from CableTrustProbeSweepTests.identities (same target) -- the
    // existing corpus parser that decodes real VDO bytes into USBPDSOP.

    private static func identities(folder: String) -> [USBPDSOP] {
        guard let text = loadProbeText(folder: folder, probe: "01_walk_pd_tree") else { return [] }

        var result: [USBPDSOP] = []
        let blocks = text.components(separatedBy: "=== ").dropFirst()
        for block in blocks {
            guard block.contains("CCUSBPDSOP") else { continue }

            let endpoint: USBPDSOP.Endpoint
            if let name = firstMatch(#"Name:\s+(\S+)"#, in: block) {
                switch name {
                case "SOP": endpoint = .sop
                case "SOP'": endpoint = .sopPrime
                case "SOP''": endpoint = .sopDoublePrime
                default: endpoint = .unknown
                }
            } else {
                continue
            }

            let portNumber = firstMatch(#"Description = "Port-USB-C@(\d+)/CC"#, in: block)
                .flatMap { Int($0) } ?? 0

            let vendorID = firstMatch(#"Vendor ID = \d+ \(0x([0-9a-fA-F]+)\)"#, in: block)
                .flatMap { Int($0, radix: 16) } ?? 0

            let vdos = allMatches(#"\[\d+\] <data 4 bytes: ([0-9a-fA-F ]+)>"#, in: block)
                .map { bytes -> UInt32 in
                    let parts = bytes.split(separator: " ").compactMap { UInt32($0, radix: 16) }
                    return parts.reversed().reduce(UInt32(0)) { ($0 << 8) | $1 }
                }

            result.append(USBPDSOP(
                id: UInt64(result.count),
                endpoint: endpoint,
                parentPortType: 0,
                parentPortNumber: portNumber,
                vendorID: vendorID,
                productID: 0,
                bcdDevice: 0,
                vdos: vdos,
                specRevision: 3
            ))
        }
        return result
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard
            let re = try? NSRegularExpression(pattern: pattern),
            let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            m.numberOfRanges > 1,
            let r = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    // MARK: - Probes 17/19: IOPortFeaturePowerSource -> PowerSource
    //
    // Uses `ProbeCorpus` (Support/ProbeCorpus.swift) directly rather than
    // copying its block/property parsing: that file exists specifically to be
    // shared across corpus sweeps in this target, unlike the probe-01 parsers
    // above (which live in files outside this target too, forcing a copy).

    private static func powerSources(folder: String) -> [PowerSource] {
        var result: [PowerSource] = []
        for probe in ["17_deep_property_dump", "19_pdo_decode_and_usb3_watch"] {
            guard let text = loadProbeText(folder: folder, probe: probe) else { continue }
            let blocks = ProbeCorpus.parseDashBlocks(text: text, classPrefix: "IOPortFeaturePowerSource")
            for (i, props) in blocks.enumerated() {
                guard let name = props["PowerSourceName"] as? String else { continue }
                let parentType = (props["ParentPortType"] as? NSNumber)?.intValue
                    ?? (props["ParentBuiltInPortType"] as? NSNumber)?.intValue ?? 2
                let parentNumber = (props["ParentPortNumber"] as? NSNumber)?.intValue
                    ?? (props["ParentBuiltInPortNumber"] as? NSNumber)?.intValue ?? 0
                // Only the dash-style ("--- ClassName[N] ---") flat-services
                // section is handled: that's where every corpus sample with a
                // WinningPowerSourceOption sub-dict was found. The rarer
                // "=== ClassName ===" HPM deep-dive section is skipped (see
                // the type doc comment); this is a documented gap, not faked
                // data.
                let winning = ProbeCorpus.parseWinningOption(
                    text: text, blockIndex: i, classPrefix: "IOPortFeaturePowerSource")
                let winningOption: PowerOption? = winning.map {
                    PowerOption(
                        voltageMV: $0["Voltage (mV)"] ?? 0,
                        maxCurrentMA: $0["Max Current (mA)"] ?? 0,
                        maxPowerMW: $0["Max Power (mW)"] ?? 0
                    )
                }
                result.append(PowerSource(
                    id: UInt64(2000 + result.count),
                    name: name,
                    parentPortType: parentType,
                    parentPortNumber: parentNumber,
                    options: [],
                    winning: winningOption
                ))
            }
        }
        return result
    }

    // MARK: - Probes 17/19: IOPortTransportStateCIO -> CIOCableCapability
    // CIO block extraction delegates to ProbeCorpus's generic block parsers
    // (className/classPrefix parameterised, so no duplication needed here).
    // The CIOCableCapability mapping itself is copied from
    // DataLinkDiagnosticCIOCorpusTests.cioCapability (same target) -- see
    // that file's doc comment for why (portKey derivation must exactly mirror
    // TRMTransportWatcher.parentPortIdentity, which lives in
    // WhatCableDarwinBackend, a target this one does not depend on).

    private static func cioCapabilities(folder: String) -> [(portNumber: Int, cio: CIOCableCapability)] {
        var result: [(Int, CIOCableCapability)] = []
        for probe in ["17_deep_property_dump", "19_pdo_decode_and_usb3_watch"] {
            guard let text = loadProbeText(folder: folder, probe: probe) else { continue }
            var blocks = ProbeCorpus.parseEqualsBlocks(text: text, className: "IOPortTransportStateCIO")
            blocks += ProbeCorpus.parseDashBlocks(text: text, classPrefix: "IOPortTransportStateCIO")
            for (i, props) in blocks.enumerated() {
                guard (props["Active"] as? NSNumber)?.boolValue == true else { continue }
                let cio = cioCapability(entryID: UInt64(3000 + result.count + i), props: props)
                let parts = cio.portKey.split(separator: "/")
                guard let portNumber = parts.last.flatMap({ Int($0) }) else { continue }
                result.append((portNumber, cio))
            }
        }
        return result
    }

    private static func cioCapability(entryID: UInt64, props: [String: Any]) -> CIOCableCapability {
        let type = (props["ParentBuiltInPortType"] as? NSNumber)?.intValue
            ?? (props["ParentPortType"] as? NSNumber)?.intValue
            ?? 0
        let number = (props["ParentBuiltInPortNumber"] as? NSNumber)?.intValue
            ?? (props["ParentPortNumber"] as? NSNumber)?.intValue
            ?? Int(((props["Priority"] as? NSNumber)?.uint64Value ?? 0) & 0xFF)

        return CIOCableCapability(
            id: entryID,
            portKey: "\(type)/\(number)",
            cableGeneration: (props["CableGeneration"] as? NSNumber)?.intValue,
            negotiatedLinkSpeed: (props["CableSpeed"] as? NSNumber)?.intValue,
            generation: (props["Generation"] as? NSNumber)?.intValue,
            asymmetricModeSupported: (props["AsymmetricModeSupported"] as? NSNumber)?.boolValue,
            legacyAdapter: (props["LegacyAdapter"] as? NSNumber)?.boolValue,
            linkTrainingMode: (props["LinkTrainingMode"] as? NSNumber)?.intValue
        )
    }

    // MARK: - One examined case per (folder, connected USB-C port)

    private struct Case {
        let folder: String
        let port: AppleHPMInterface
        let identities: [USBPDSOP]
        let sources: [PowerSource]
        let cio: CIOCableCapability?
    }

    private static let cases: [Case] = computeCases()

    private static func computeCases() -> [Case] {
        var result: [Case] = []
        for folder in allFolders() {
            let ports = loadPorts(folder: folder)
            guard !ports.isEmpty else { continue }
            let ids = identities(folder: folder)
            let sources = powerSources(folder: folder)
            let cios = cioCapabilities(folder: folder)

            for port in ports where port.portTypeDescription == "USB-C" && port.connectionActive {
                let matchedIDs = ids.filter { $0.parentPortNumber == port.portNumber }
                let matchedSources = sources.filter { $0.parentPortNumber == port.portNumber }
                let matchedCIO = cios.first { $0.portNumber == port.portNumber }?.cio
                result.append(Case(
                    folder: folder,
                    port: port.asAppleHPMInterface,
                    identities: matchedIDs,
                    sources: matchedSources,
                    cio: matchedCIO
                ))
            }
        }
        return result
    }

    // MARK: - Cable classification helpers
    //
    // Mirrors `PortSummary.init`'s own `cableEmarker` selection exactly:
    // prefer an SOP'/SOP'' identity that carries VDOs, fall back to one that
    // responded with none. `CableClassification.resolve` is then handed that
    // identity together with the port it belongs to, as every production
    // caller does.

    private static func cableEmarker(_ c: Case) -> USBPDSOP? {
        c.identities.first(where: {
            ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime) && !$0.vdos.isEmpty
        }) ?? c.identities.first(where: {
            $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
        })
    }

    private static func resolution(_ c: Case) -> CableClassification.Resolution? {
        cableEmarker(c).flatMap { CableClassification.resolve(identity: $0, port: c.port) }
    }

    // MARK: - Expected classification outcomes
    //
    // Measured by this sweep against the corpus snapshot these assertions
    // were written against: of 1776 connected USB-C port cases, 764 carry a
    // cable e-marker with VDO[3] and so classify at all. Of those, 12 are
    // promoted to active by the port controller's `ActiveCable` flag, 1 by
    // the active-cable layout contradiction, and the remaining 751 are the
    // e-marker's own word.
    //
    // Held as exact sets rather than counts on purpose: a count alone passes
    // when one port drops out and a different one appears.

    /// "folder port N", one entry per case.
    private static func key(_ c: Case) -> String {
        "\(c.folder) port \(c.port.portNumber ?? -1)"
    }

    private static let expectedPortControllerPromotions: Set<String> = [
        "m1_macos15.7.7_c port 2",      // VID 0x20C2, VDO[3] 0x45082043
        "m1_macos26.6.2_c port 1",      // VID 0x0522, VDO[3] 0x110A2644
        "m1_macos26.6.2_c port 2",      // VID 0x20C2, VDO[3] 0x45082043
        "m2max_macos26.3.1_c port 2",   // VID 0x2B1D, VDO[3] 0x3208485A
        "m2max_macos26.6.1 port 3",     // VID 0x2B1D, VDO[3] 0x3208485A
        "m2max_macos27.0_b port 2",     // VID 0x2B1D, VDO[3] 0x3208485A
        "m2ultra_macos27.0_b port 3",   // VID 0x2B1D, VDO[3] 0x3208485A
        "m3_macos26.5.2_c port 1",      // VID 0x2B1D, VDO[3] 0x32084842
        "m3_macos26.5.2_e port 2",      // VID 0x20C2, VDO[3] 0x350A4E42
        "m4_macos26.5.2_s port 2",      // VID 0x2B1D, VDO[3] 0x32084842
        "m4_macos26.6.2_f port 4",      // VID 0x2B1D, VDO[3] 0x32084842
        "m5pro_macos26.5.1_c port 3"    // VID 0x2B1D, VDO[3] 0x32084842
    ]

    /// VID 0x0138, VDO[3] 0x0008404A. The controller flag is false here, so
    /// this case is the proof that the contradiction path still runs after
    /// the port controller was given precedence over it.
    private static let expectedLayoutContradiction = "m1_macos26.2 port 1"

    /// VCONN-Powered Devices (ID Header product type 6) sitting on a port
    /// whose controller reports `ActiveCable = true`. They must not be
    /// promoted: the e-marker reported a VPD, not a passive cable, so
    /// "e-marker reports passive" would be false of them.
    private static let expectedVPDCases: Set<String> = [
        "m3_macos26.5.2_f port 1",      // VID 0x05AC, VDO[3] 0x11000000
        "m4pro_macos27.0_d port 3"      // VID 0x05AC, VDO[3] 0x11000000
    ]

    // MARK: - Classifiable-case floor
    //
    // Measured 764 by this sweep against the corpus snapshot it was written
    // against: cases whose cable e-marker carries VDO[3], so
    // `CableClassification.resolve` returns non-nil. Floor = 85% of 764
    // rounded down (649.4 -> 649), taken to 650, matching the `coverageFloor`
    // convention above.
    //
    // Every classification assertion below filters this same set. Without a
    // floor on it, a broken `loadPorts` or a broken identity join would empty
    // the set and turn all of them into vacuous passes.
    private static let classifiableFloor = 650

    // MARK: - Coverage floor
    //
    // Measured directly from this Swift parser against the corpus snapshot at
    // the time this sweep was written (410 folders, full raw corpus
    // hard-linked into this worktree): the sweep produces 645 connected
    // USB-C port cases. Floor = 85% of 645, rounded down:
    // 645 * 0.85 = 548.25 -> 548.
    //
    // A worktree without the raw corpus (only 01_walk_pd_tree.json committed)
    // still has probe 01 (it's the one committed distillation), so this floor
    // does NOT skip on a fresh clone the way the CIO-specific sweeps do; it
    // only needs probe 01, which is always present.
    private static let coverageFloor = 548

    // MARK: - Tests

    @Test("Coverage: the corpus has enough connected USB-C port cases to exercise PortSummary")
    func coverageFloorHolds() {
        #expect(Self.cases.count >= Self.coverageFloor,
            "Expected at least \(Self.coverageFloor) connected USB-C port cases (85% of the 645 counted when this sweep was written); found \(Self.cases.count). A drop this large means the corpus shrank or the parsing regressed, not normal noise.")
    }

    @Test("No crash: PortSummary.init handles every real connected-port case in the corpus")
    func noCrashAcrossCorpus() {
        var examined = 0
        for c in Self.cases {
            _ = PortSummary(
                port: c.port,
                sources: c.sources,
                identities: c.identities,
                cioCapability: c.cio
            )
            examined += 1
        }
        // Reaching this line for every case means none of them crashed.
        #expect(examined == Self.cases.count)
    }

    @Test("Invariant: a connected port never reports the 'Nothing connected' status")
    func connectedPortNeverReadsEmpty() {
        var violations: [String] = []
        for c in Self.cases {
            let summary = PortSummary(
                port: c.port,
                sources: c.sources,
                identities: c.identities,
                cioCapability: c.cio
            )
            // Source: PortSummary.init's very first branch --
            // `if !connected { self.status = .empty; ... return }`. `connected`
            // here is `isConnectedOverride ?? (port.connectionActive == true)`;
            // every case in this sweep sets `port.connectionActive == true` and
            // passes no override, so `.empty` must never be reached.
            if summary.status == .empty {
                violations.append("\(c.folder) port \(c.port.serviceName)")
            }
            #expect(!summary.headline.isEmpty,
                "\(c.folder) port \(c.port.serviceName): headline must never be empty for a connected port")
        }
        #expect(violations.isEmpty,
            "\(violations.count) connected corpus port(s) reported .empty status: \(violations.prefix(5))")
    }

    /// No real port may claim to be plugged in while the system says there is
    /// no external power.
    ///
    /// The bug this guards was reproduced on an M5 on 2026-08-10: `pmset`
    /// reported battery power and discharging while the card showed a charging
    /// bolt and "Plugged in". Three branches conclude a charger is present;
    /// the FedDetails recovery added for #459 was the one missing
    /// `!systemPowerUnavailable`, and it rests on `FedExternalConnected`,
    /// which is stale roughly 40% of the time.
    ///
    /// The FedDetails entry is SYNTHESISED rather than parsed from probe 32,
    /// and that is deliberate: this sweep asks "given a charger claim on this
    /// real port, does on-battery state suppress it?", so the claim has to be
    /// present on every case or the assertion would be vacuous on the many
    /// corpus ports that have no charger. The port, its transports and its
    /// identities are all real. Every case is fed the strongest possible
    /// charger claim and must still refuse to say "Plugged in".
    @Test("Invariant: no corpus port claims 'Plugged in' while the system is on battery")
    func noPortClaimsPluggedInOnBattery() {
        var examined = 0
        var reachedTheBranch = 0
        var violations: [String] = []
        for c in Self.cases {
            guard let portNumber = c.port.portNumber else { continue }
            examined += 1

            let fed = [
                FederatedIdentity(
                    portIndex: portNumber,
                    vendorID: 0x05AC,
                    productID: 0,
                    pdSpecRevision: 0,
                    powerRole: 0,
                    dualRolePower: false,
                    externalConnected: true   // the stale signal
                )
            ]
            func summary(onBattery: Bool) -> PortSummary {
                PortSummary(
                    port: c.port,
                    sources: [],          // the #459 case: no PowerSource node
                    identities: c.identities,
                    federatedIdentities: fed,
                    cioCapability: c.cio,
                    batteryIsCharging: onBattery ? false : true,
                    adapter: nil
                )
            }

            // The same port, twice, differing only in battery state. If the
            // off-battery run says "Plugged in", this case genuinely reaches
            // the FedDetails branch, so the on-battery run is a real test of
            // the guard rather than a case that exited somewhere earlier in
            // the chain and would have passed regardless.
            //
            // Counting inputs instead of this was the weakness a reviewer
            // found in the first version: 1515 ports were "examined" while
            // only 340 reached the decision under test, so the floor could
            // stay satisfied while the sweep stopped testing anything.
            if summary(onBattery: false).headline.contains("Plugged in") {
                reachedTheBranch += 1
                let onBattery = summary(onBattery: true)
                if onBattery.status == .charging || onBattery.headline.contains("Plugged in") {
                    violations.append("\(c.folder) \(c.port.serviceName): \(onBattery.headline)")
                }
            }
        }
        #expect(examined >= 400,
            "only \(examined) corpus ports carried a port number; expected 400+")
        // Measured at 340 on 2026-08-10. The floor is on ports that actually
        // reach the guarded decision, not on ports fed to the sweep.
        #expect(reachedTheBranch >= 300,
            "only \(reachedTheBranch) of \(examined) ports reached the FedDetails branch; expected 300+, so this sweep is no longer testing the guard")
        #expect(violations.isEmpty,
            "\(violations.count) real port(s) claimed power while on battery: \(violations.prefix(5))")
    }

    @Test("Coverage: enough corpus cases classify for the cable-type assertions to mean anything")
    func classifiableCaseFloorHolds() {
        let classifiable = Self.cases.filter { Self.resolution($0) != nil }.count
        #expect(classifiable >= Self.classifiableFloor,
            "Only \(classifiable) of \(Self.cases.count) cases produced a cable classification; expected at least \(Self.classifiableFloor) (85% of the 764 counted when these assertions were written). Below this floor every cable-type assertion in this file is passing over an empty or near-empty set, so treat it as a parsing or join regression first.")
    }

    @Test("Exactly these corpus ports are promoted to active by the port controller")
    func portControllerPromotionsAreExactlySet() {
        let found = Set(Self.cases.filter { Self.resolution($0)?.source == .portController }.map(Self.key))
        let missing = Self.expectedPortControllerPromotions.subtracting(found).sorted()
        let unexpected = found.subtracting(Self.expectedPortControllerPromotions).sorted()
        #expect(missing.isEmpty && unexpected.isEmpty,
            """
            Port-controller promotions do not match the recorded set.
            Missing (recorded, not found now): \(missing)
            Unexpected (found now, not recorded): \(unexpected)
            The most likely cause is a corpus ingest since these figures were derived, in which case the figures need re-deriving rather than the code needing a fix. Check the corpus for new folders first, and only then suspect the classifier.
            """)
    }

    @Test("Invariant: a cable that self-reports active is never demoted to passive")
    func activeSelfReportIsNeverDemoted() {
        var demotions: [String] = []
        for c in Self.cases {
            guard let em = Self.cableEmarker(c), let cv = em.cableVDO, cv.cableType == .active else { continue }
            if Self.resolution(c)?.type == .passive { demotions.append(Self.key(c)) }
        }
        #expect(demotions.isEmpty,
            "\(demotions.count) case(s) had an e-marker self-reporting active and were resolved passive: \(demotions.prefix(5)). The whole design rests on a self-report of active never being demoted: a port disagreeing in that direction is the port being wrong, not the cable.")
    }

    @Test("Every other corpus port keeps the e-marker's own verdict")
    func unpromotedPortsKeepTheEmarkerVerdict() {
        var examined = 0
        var violations: [String] = []
        for c in Self.cases {
            let key = Self.key(c)
            guard !Self.expectedPortControllerPromotions.contains(key), key != Self.expectedLayoutContradiction else { continue }
            guard let em = Self.cableEmarker(c), let cv = em.cableVDO, let r = Self.resolution(c) else { continue }
            examined += 1
            if r.type != cv.cableType || r.source != .emarker {
                violations.append("\(key): resolved \(r.type)/\(r.source), e-marker said \(cv.cableType)")
            }
        }
        #expect(examined >= Self.classifiableFloor - Self.expectedPortControllerPromotions.count - 1,
            "only \(examined) unpromoted classifiable cases; the set this assertion covers has shrunk, so it is no longer testing what it claims")
        #expect(violations.isEmpty,
            "\(violations.count) case(s) outside the 12 port-controller promotions and the 1 layout contradiction did not simply keep the e-marker's own verdict: \(violations.prefix(5))")
    }

    @Test("The layout-contradiction branch still fires on the one corpus port that carries it")
    func layoutContradictionStillFires() {
        let parts = Self.expectedLayoutContradiction.split(separator: " ")
        let folder = String(parts[0])
        let portNumber = Int(parts[2])
        guard let c = Self.cases.first(where: { $0.folder == folder && $0.port.portNumber == portNumber }) else {
            Issue.record("\(Self.expectedLayoutContradiction) is no longer a connected USB-C case in the corpus; the contradiction path is untested by this sweep")
            return
        }
        let r = Self.resolution(c)
        #expect(r?.type == .active && r?.source == .layoutContradiction,
            "\(Self.expectedLayoutContradiction) resolved \(String(describing: r)); expected active/layoutContradiction. Its port controller reports ActiveCable false, so this is the case that proves giving the port controller precedence did not swallow the contradiction path.")
    }

    @Test("Captive plugs: the corpus carries enough of them, and one renders its line")
    func captivePlugsAreDecodedAndRendered() {
        // Measured 37 across 35 folders. The floor is deliberately below that:
        // a captive plug is a property of whatever was plugged in on the day,
        // so the exact number moves with the corpus.
        var captive: [String] = []
        for c in Self.cases {
            guard let cv = Self.cableEmarker(c)?.cableVDO else { continue }
            if cv.plugType == .captive { captive.append(Self.key(c)) }
        }
        #expect(captive.count >= 30,
            "only \(captive.count) corpus cases decoded a captive plug; expected at least 30 (37 measured when this was written)")

        // m1_macos26.5.1_d port 1: VID 0x413C, VDO[3] 0x110C2042.
        guard let named = Self.cases.first(where: { $0.folder == "m1_macos26.5.1_d" && $0.port.portNumber == 1 }) else {
            Issue.record("m1_macos26.5.1_d port 1 is no longer a connected USB-C case in the corpus; the captive rendering is untested by this sweep")
            return
        }
        let summary = PortSummary(port: named.port, sources: named.sources, identities: named.identities, cioCapability: named.cio)
        let lines = summary.group(.emarker)?.lines ?? []
        #expect(lines.contains(PDVDO.PlugType.captive.label),
            "m1_macos26.5.1_d port 1 decodes a captive plug but its rendered e-marker group has no captive line: \(lines)")
    }

    @Test("E-marker silicon: the corpus carries enough of it, and one renders its line")
    func chipVendorIsRecognisedAndRendered() {
        // Measured 72 across 65 folders, all five silicon makers between them.
        var chipVendor: [String] = []
        for c in Self.cases {
            guard let em = Self.cableEmarker(c), em.cableVDO != nil else { continue }
            if EmarkerSilicon.shortName(for: em.vendorID) != nil { chipVendor.append(Self.key(c)) }
        }
        #expect(chipVendor.count >= 60,
            "only \(chipVendor.count) corpus cases carried an e-marker silicon vendor ID; expected at least 60 (72 measured when this was written)")

        // m1_macos26.5.2_i port 1: VID 0x315C, so the short name is CPS.
        guard let named = Self.cases.first(where: { $0.folder == "m1_macos26.5.2_i" && $0.port.portNumber == 1 }) else {
            Issue.record("m1_macos26.5.2_i port 1 is no longer a connected USB-C case in the corpus; the chip-vendor rendering is untested by this sweep")
            return
        }
        let summary = PortSummary(port: named.port, sources: named.sources, identities: named.identities, cioCapability: named.cio)
        let lines = summary.group(.database)?.lines ?? []
        #expect(lines.contains(where: { $0.contains("chip maker's default vendor ID (CPS)") }),
            "m1_macos26.5.2_i port 1 carries VID 0x315C but its rendered database group has no chip-vendor line: \(lines)")
    }

    @Test("A VCONN-Powered Device is never promoted, whatever the port controller says")
    func vpdCasesAreNotPromoted() {
        var examined = 0
        for key in Self.expectedVPDCases.sorted() {
            let parts = key.split(separator: " ")
            let folder = String(parts[0])
            let portNumber = Int(parts[2])
            guard let c = Self.cases.first(where: { $0.folder == folder && $0.port.portNumber == portNumber }) else {
                Issue.record("\(key) is no longer a connected USB-C case in the corpus; the VPD gate is untested by this sweep")
                continue
            }
            examined += 1
            #expect(c.port.activeCable == true,
                "\(key) no longer has ActiveCable true on its port, so it no longer tests the gate: without the flag, nothing would promote it anyway")
            let r = Self.resolution(c)
            #expect(r?.type == .passive && r?.source == .emarker,
                "\(key) carries a VCONN-Powered Device, not a passive cable, so it must keep the e-marker's own verdict; resolved \(String(describing: r))")

            let summary = PortSummary(port: c.port, sources: c.sources, identities: c.identities, cioCapability: c.cio)
            let lines = summary.group(.emarker)?.lines ?? []
            #expect(!lines.contains(where: { $0.contains("the port controller detects an active cable") }),
                "\(key) rendered the port-controller line, which tells the user the e-marker reported passive. It reported a VPD: \(lines)")
        }
        #expect(examined == Self.expectedVPDCases.count,
            "expected \(Self.expectedVPDCases.count) VPD cases in the corpus, found \(examined)")
    }

    @Test("Invariant: an e-marker response always produces an e-marker group")
    func emarkerResponseProducesBullet() {
        // Source: PortSummary.init, the e-marker section --
        // `let hasEmarker = identities.contains { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }`.
        // When it responded and was read, its claims are the group's lines.
        // When it responded but was not read, that read state is the group's
        // subtitle. Either way the group exists, so `hasEmarker == true` must
        // imply a non-nil e-marker group.
        //
        // This used to assert `bullets.count >= 1`, which the read-state
        // rework broke for a real reason worth pinning: an unread e-marker
        // has NO claims to list, so it now contributes a subtitle and no
        // lines. 32 corpus ports are in exactly that state.
        var examined = 0
        var read = 0
        var unread = 0
        var violations: [String] = []
        for c in Self.cases {
            let hasEmarker = c.identities.contains {
                $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
            }
            guard hasEmarker else { continue }
            examined += 1
            let summary = PortSummary(
                port: c.port,
                sources: c.sources,
                identities: c.identities,
                cioCapability: c.cio
            )
            guard let group = summary.group(.emarker) else {
                violations.append("\(c.folder) port \(c.port.serviceName)")
                continue
            }
            if group.lines.isEmpty { unread += 1 } else { read += 1 }
        }
        if examined == 0 {
            Issue.record("No corpus case had a decodable SOP'/SOP'' e-marker; this invariant is untested by this sweep")
        }
        #expect(violations.isEmpty,
            "\(violations.count) case(s) had an e-marker response but produced no e-marker group: \(violations.prefix(5))")
        // Floors, so a parser change that quietly empties one of the two paths
        // shows up as a failure rather than a clean run. Measured 2026-08-10.
        #expect(read >= 100, "only \(read) read e-markers in the sweep; expected 100+")
        #expect(unread >= 20, "only \(unread) unread e-markers in the sweep; expected 20+")
    }

    @Test("Invariant: a decoded Cable VDO always produces a 'Cable speed' bullet")
    func decodedCableVDOProducesSpeedBullet() {
        // Source: PortSummary.init -- `if let cable = cableEmarker, let cv = cable.cableVDO { let speedLabel = cv.speed.label; bullets.append("Cable speed: \(speedLabel)") ... }`.
        // `cableEmarker` prefers a populated e-marker (`!$0.vdos.isEmpty`) over
        // an empty one, so whenever a port's e-marker has `vdos.count > 3`
        // (the precondition for `cableVDO` to decode, see USBPDSOP.cableVDO),
        // the resolved cableEmarker must be that populated one, and the
        // speed bullet must appear.
        var examined = 0
        var violations: [String] = []
        for c in Self.cases {
            guard c.identities.contains(where: {
                ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime) && $0.vdos.count > 3
            }) else { continue }
            examined += 1
            let summary = PortSummary(
                port: c.port,
                sources: c.sources,
                identities: c.identities,
                cioCapability: c.cio
            )
            if !summary.bullets.contains(where: { $0.hasPrefix("Cable speed:") }) {
                violations.append("\(c.folder) port \(c.port.serviceName)")
            }
        }
        if examined == 0 {
            Issue.record("No corpus case had a decodable Cable VDO; this invariant is untested by this sweep")
        }
        #expect(violations.isEmpty,
            "\(violations.count) case(s) had a decodable Cable VDO but no 'Cable speed' bullet: \(violations.prefix(5))")
    }
}
