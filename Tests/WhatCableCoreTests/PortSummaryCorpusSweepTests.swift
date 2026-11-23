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
/// demoted the other way, that a VCONN-Powered Device does not classify at
/// all, and that every other classifiable port keeps the e-marker's own verdict.
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
    // The port-controller promotion is held as a rule over every classifiable
    // case, not as a list of ports: a case resolves with source
    // `.portController` exactly when its port controller reports
    // `ActiveCable = true` and its e-marker says it is not active. The corpus
    // grows, so which ports carry that today is printed, never pinned.

    /// "folder port N", one entry per case.
    private static func key(_ c: Case) -> String {
        "\(c.folder) port \(c.port.portNumber ?? -1)"
    }

    /// The promotion rule, from the test's own reading of the case: the port
    /// controller says active and the e-marker's decoded Cable VDO says not
    /// active. Only meaningful on a classifiable case (one with a Cable VDO).
    private static func portControllerSaysPromote(_ c: Case, _ cv: PDVDO.CableVDO) -> Bool {
        c.port.activeCable == true && cv.cableType != .active
    }

    /// VID 0x0138, VDO[3] 0x0008404A. The controller flag is false here, so
    /// this case is the proof that the contradiction path still runs after
    /// the port controller was given precedence over it.
    private static let expectedLayoutContradiction = "m1_macos26.2 port 1"

    /// VCONN-Powered Devices (ID Header product type 6) sitting on a port
    /// whose controller reports `ActiveCable = true`. They must not classify
    /// at all: a VPD is not a cable, so it carries no cable VDO and
    /// `CableClassification.resolve` returns nil. Promoting one, or calling
    /// it passive, would both assert it is a cable.
    private static let expectedVPDCases: Set<String> = [
        "m3_macos26.5.2_f port 1",      // VID 0x05AC, VDO[3] 0x11000000
        "m4pro_macos27.0_d port 3"      // VID 0x05AC, VDO[3] 0x11000000
    ]

    // MARK: - Tests

    @Test("Coverage: the corpus has connected USB-C port cases to exercise PortSummary")
    func coverageFloorHolds() {
        #expect(Self.cases.count > 0,
            "no connected USB-C port case found: checked at least one. An empty set means the corpus is missing or the parsing regressed.")
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
        #expect(examined > 0, "no case examined: checked at least one")
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
        #expect(Self.cases.count > 0, "no connected corpus port: checked at least one")
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
            // found in the first version: far more ports were "examined" than
            // reached the decision under test, so a guard on inputs could
            // stay satisfied while the sweep stopped testing anything.
            if summary(onBattery: false).headline.contains("Plugged in") {
                reachedTheBranch += 1
                let onBattery = summary(onBattery: true)
                if onBattery.status == .charging || onBattery.headline.contains("Plugged in") {
                    violations.append("\(c.folder) \(c.port.serviceName): \(onBattery.headline)")
                }
            }
        }
        // The guard is on ports that actually reach the guarded decision,
        // not on ports fed to the sweep.
        #expect(reachedTheBranch > 0,
            "none of \(examined) ports reached the FedDetails branch: checked at least one, so this sweep is no longer testing the guard")
        #expect(violations.isEmpty,
            "\(violations.count) real port(s) claimed power while on battery: \(violations.prefix(5))")
    }

    @Test("Coverage: corpus cases classify, so the cable-type assertions mean anything")
    func classifiableCaseFloorHolds() {
        let classifiable = Self.cases.filter { Self.resolution($0) != nil }.count
        #expect(classifiable > 0,
            "none of \(Self.cases.count) cases produced a cable classification: checked at least one. With none, every cable-type assertion in this file passes over an empty set, so treat it as a parsing or join regression first.")
    }

    @Test("Rule: a port is promoted to active by the port controller exactly when the controller says active and the e-marker says not")
    func portControllerPromotionsFollowTheRule() {
        var promoted: [String] = []
        var violations: [String] = []
        for c in Self.cases {
            guard let em = Self.cableEmarker(c), let cv = em.cableVDO, let r = Self.resolution(c) else { continue }
            let key = Self.key(c)
            let rule = Self.portControllerSaysPromote(c, cv)
            let isPromotion = r.source == .portController
            if isPromotion { promoted.append(key) }
            if isPromotion && !rule {
                violations.append("\(key): resolved \(r.type)/portController, but port ActiveCable \(String(describing: c.port.activeCable)), e-marker said \(cv.cableType)")
            } else if rule && !(isPromotion && r.type == .active) {
                violations.append("\(key): port ActiveCable true and e-marker said \(cv.cableType), yet resolved \(r.type)/\(r.source)")
            }
        }
        print("PortSummaryCorpusSweep: \(promoted.count) port-controller promotions: \(promoted.sorted())")
        #expect(promoted.count > 0, "no port-controller promotion in the corpus: checked at least one")
        #expect(violations.isEmpty,
            "\(violations.count) case(s) break the promotion rule (promoted exactly when the port controller says ActiveCable true and the e-marker says not active):\n\(violations.joined(separator: "\n"))")
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
        var contradictions = 0
        var violations: [String] = []
        for c in Self.cases {
            let key = Self.key(c)
            guard let em = Self.cableEmarker(c), let cv = em.cableVDO, let r = Self.resolution(c) else { continue }
            // Excluded by rule, not by name: the port-controller promotion
            // (the rule above), and the layout contradiction, which fires on a
            // passive self-report whose VDO[3] uses the active-only layout.
            if Self.portControllerSaysPromote(c, cv) { continue }
            // Read from the raw bits, never through production's
            // `hasActiveLayoutContradiction`: a production predicate here would
            // let a broken decode skip exactly the cases that show it. ID Header
            // product type passive, and VDO[3] bit 3 (SOP'' Controller Present,
            // reserved in the passive layout) set.
            let rawContradiction = em.idHeader?.ufpProductType == .passiveCable
                && em.vdos.count > 3 && (em.vdos[3] >> 3) & 1 == 1
            if rawContradiction {
                contradictions += 1
                if r.type != .active || r.source != .layoutContradiction {
                    violations.append("\(key): passive ID Header with VDO[3] bit 3 set, resolved \(r.type)/\(r.source), expected active/layoutContradiction")
                }
                continue
            }
            examined += 1
            if r.type != cv.cableType || r.source != .emarker {
                violations.append("\(key): resolved \(r.type)/\(r.source), e-marker said \(cv.cableType)")
            }
        }
        print("PortSummaryCorpusSweep: \(examined) unpromoted classifiable cases, \(contradictions) layout contradictions")
        #expect(examined > 0, "no unpromoted classifiable case: checked at least one")
        #expect(violations.isEmpty,
            "\(violations.count) case(s) outside the port-controller promotions and the layout contradictions did not simply keep the e-marker's own verdict: \(violations.prefix(5))")
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
        // A captive plug is a property of whatever was plugged in on the day,
        // so the number moves with the corpus and is not asserted.
        var captive: [String] = []
        for c in Self.cases {
            guard let cv = Self.cableEmarker(c)?.cableVDO else { continue }
            if cv.plugType == .captive { captive.append(Self.key(c)) }
        }
        #expect(captive.count > 0,
            "no corpus case decoded a captive plug: checked at least one")

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
        var chipVendor: [String] = []
        for c in Self.cases {
            guard let em = Self.cableEmarker(c), em.cableVDO != nil else { continue }
            if EmarkerSilicon.shortName(for: em.vendorID) != nil { chipVendor.append(Self.key(c)) }
        }
        #expect(chipVendor.count > 0,
            "no corpus case carried an e-marker silicon vendor ID: checked at least one")

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
            #expect(r == nil,
                "\(key) carries a VCONN-Powered Device, not a cable, so it has no cable VDO and nothing to classify; any resolution here would assert it is a cable. Resolved \(String(describing: r))")

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
        // lines. Corpus ports are in exactly that state.
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
        print("PortSummaryCorpusSweep: \(examined) e-marker responses, \(read) read, \(unread) unread")
        #expect(violations.isEmpty,
            "\(violations.count) case(s) had an e-marker response but produced no e-marker group: \(violations.prefix(5))")
    }

    @Test("Invariant: a decoded Cable VDO always produces a 'Cable speed' bullet")
    func decodedCableVDOProducesSpeedBullet() {
        // Source: PortSummary.init -- `if let cable = cableEmarker, let cv = cable.cableVDO { let speedLabel = cv.speed.label; bullets.append("Cable speed: \(speedLabel)") ... }`.
        // `cableEmarker` prefers a populated e-marker (`!$0.vdos.isEmpty`) over
        // an empty one, so whenever a port's e-marker has `vdos.count > 3` and
        // declares itself a cable (the preconditions for `cableVDO` to decode,
        // see USBPDSOP.cableVDO), the resolved cableEmarker must be that
        // populated one, and the speed bullet must appear. The `isCable` half
        // excludes VCONN-powered devices, whose VDO[3] is not cable data
        // (issue #542).
        var examined = 0
        var violations: [String] = []
        for c in Self.cases {
            guard c.identities.contains(where: {
                ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime)
                    && $0.vdos.count > 3
                    && $0.idHeader?.isCable == true
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

    // MARK: - Charger attached but the Mac held on battery (public issue 672)
    //
    // The system-power inputs this sweep otherwise leaves out, read per folder:
    //
    // - probe 32: the top-level `IsCharging` and `ExternalConnected` flags of
    //   the AppleSmartBattery dump (2-space indent; deeper copies are nested
    //   dicts and are skipped).
    // - probe 39: whether `IOPSCopyExternalPowerAdapterDetails` was nil, which
    //   is the app's `adapter`. Older captures have no probe 39; for those the
    //   battery's `ExternalConnected` stands in. Measured on the 455 folders
    //   that carry both: nil details exactly when `ExternalConnected` is false,
    //   455 of 455.
    // - probe 34: SMC `VD0R` (little-endian IEEE float) and `AC-W` (signed
    //   byte), decoded here from their raw bytes, not the probe's printed value.
    // - probes 17/19: which ports (by type AND number, so MagSafe 3@1 and
    //   USB-C@1 stay apart) hold a live winning contract, for the cross-port
    //   rule.

    private struct SystemPower {
        let onBattery: Bool
        let dcInputVolts: Double?
        let acW: Int?
        /// "type/number" of every port holding a live winning contract.
        let liveContractKeys: Set<String>

        var supply: Bool? { SystemPowerState.chargerSupplyPresent(dcInputVolts: dcInputVolts, acW: acW) }
    }

    private static func topLevelFlag(_ text: String, key: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("  \(key) ="), !line.hasPrefix("   ") else { continue }
            return line.split(separator: "=", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)
        }
        return nil
    }

    /// Raw bytes of one SMC key from probe 34, in the order the probe prints.
    private static func smcRawBytes(folder: String, key: String) -> [UInt8]? {
        guard let text = loadProbeText(folder: folder, probe: "34_smc_power_keys") else { return nil }
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ")
            guard fields.first.map(String.init) == key,
                  let raw = fields.first(where: { $0.hasPrefix("raw=") })?.dropFirst(4),
                  raw.count % 2 == 0, !raw.isEmpty else { continue }
            var bytes: [UInt8] = []
            var i = raw.startIndex
            while i < raw.endIndex {
                let j = raw.index(i, offsetBy: 2)
                guard let b = UInt8(raw[i..<j], radix: 16) else { return nil }
                bytes.append(b)
                i = j
            }
            return bytes
        }
        return nil
    }

    private static func vd0rVolts(folder: String) -> Double? {
        guard let b = smcRawBytes(folder: folder, key: "VD0R"), b.count == 4 else { return nil }
        let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        let v = Float(bitPattern: bits)
        return v.isFinite ? Double(v) : nil
    }

    private static func acW(folder: String) -> Int? {
        guard let b = smcRawBytes(folder: folder, key: "AC-W"), b.count == 1 else { return nil }
        return Int(Int8(bitPattern: b[0]))
    }

    /// Connected ports only, as `PowerSource.portKeysWithLiveContract`: a
    /// retained contract on an empty port is not a live port.
    private static func liveContractKeys(folder: String) -> Set<String> {
        let connected = Set(loadPorts(folder: folder).filter(\.connectionActive).map { p in
            "\(p.portTypeDescription?.hasPrefix("MagSafe") == true ? 17 : 2)/\(p.portNumber)"
        })
        let grouped = Dictionary(grouping: powerSources(folder: folder)) { "\($0.parentPortType)/\($0.parentPortNumber)" }
        return Set(grouped.compactMap { key, sources in
            connected.contains(key) && PowerSource.hasLiveChargingContract(in: sources) ? key : nil
        })
    }

    private static func systemPower(folder: String) -> SystemPower? {
        guard let p32 = loadProbeText(folder: folder, probe: "32_smart_battery_full_keys"),
              let charging = topLevelFlag(p32, key: "IsCharging") else { return nil }
        let isCharging = !(charging == "false" || charging == "0")
        let adapterNil: Bool
        if let p39 = loadProbeText(folder: folder, probe: "39_system_power_adapter"),
           let section = p39.components(separatedBy: "=== IOPSCopyExternalPowerAdapterDetails ===").dropFirst().first {
            adapterNil = section.components(separatedBy: "===").first?.contains("status: nil") == true
        } else if let ext = topLevelFlag(p32, key: "ExternalConnected") {
            adapterNil = ext == "false" || ext == "0"
        } else {
            return nil
        }
        let onBattery = !isCharging && adapterNil
        return SystemPower(
            onBattery: onBattery,
            dcInputVolts: vd0rVolts(folder: folder),
            acW: acW(folder: folder),
            liveContractKeys: onBattery ? liveContractKeys(folder: folder) : [])
    }

    /// One read per folder, shared by every test below.
    private static let powerByFolder: [String: SystemPower] = {
        var result: [String: SystemPower] = [:]
        for folder in allFolders() {
            if let p = systemPower(folder: folder) { result[folder] = p }
        }
        return result
    }()

    /// The Macs held on battery with a charger attached and powered: about 20 V
    /// on the DC-in rail, AC-W set, SMC CH0R 0x08, a live contract on the port.
    ///
    /// Every USB-C one is a dock or hub that also supplies power (Thunderbolt,
    /// DisplayPort or USB data on the same port), so the data headline keeps
    /// its place and what changes is the charger group: the offer now shows,
    /// labelled as not in use. No corpus capture is a bare USB-C charger held
    /// on battery (the reporter's shape); the "Charger connected" headline for
    /// that is pinned by the unit tests in `PortSummaryTests`. The fifth held
    /// Mac, `m3_macos27.0`, holds its charger on MagSafe; see
    /// `magSafeHeldOffReplay`.
    private static let heldOffPorts: Set<String> = [
        "m2max_macos27.2 port 2",
        "m5_macos27.0_aa port 1",
        "m1_macos26.5.1_p port 2",
        "m5pro_macos26.5.2_m port 1",
    ]
    private static let heldOffFolders: Set<String> = [
        "m2max_macos27.2", "m5_macos27.0_aa", "m1_macos26.5.1_p", "m5pro_macos26.5.2_m", "m3_macos27.0",
    ]

    /// On battery with a retained 30W contract on a connected port, at
    /// 0.016 V and AC-W 0xff: the stale case. It must keep today's card exactly.
    private static let staleRetainedContractPort = "m1_macos26.5.1_u port 1"

    /// On battery with stale PD contract registers (PortControllerInfo state 5,
    /// a non-zero RDO, MaxPower 0) and AC-W ff, from the issue 672 investigation. Only
    /// `m5pro_macos26.6.1_c` has a connected USB-C port to render.
    private static let staleContractFolders: [String] = [
        "m4max_macos26.5.2_l", "m4pro_macos27.0_t", "m5_macos27.0_s", "m5_macos27.0_t",
        "m5pro_macos26.5.2_s", "m5pro_macos26.6.1_c", "m5pro_macos27.2",
    ]

    /// This sweep joins sources to ports by port NUMBER alone, so MagSafe 3@1's
    /// source lands on USB-C@1 too (`m3_macos27.0`, a MagSafe charger held on
    /// battery). The app joins by controller UUID and never does that, so the
    /// replay keeps only sources whose parent port type matches.
    private static func sources(_ sources: [PowerSource], type: Int, number: Int) -> [PowerSource] {
        sources.filter { $0.parentPortType == type && $0.parentPortNumber == number }
    }

    private static func heldOffSummary(
        port: AppleHPMInterface, type: Int, sources: [PowerSource],
        identities: [USBPDSOP], cio: CIOCableCapability?, power: SystemPower
    ) -> PortSummary {
        let key = "\(type)/\(port.portNumber ?? -1)"
        return PortSummary(
            port: port,
            sources: sources,
            identities: identities,
            cioCapability: cio,
            batteryIsCharging: false,
            adapter: nil,
            chargerHeldOffSignal: power.supply,
            anotherPortActivelyCharging: power.liveContractKeys.contains { $0 != key }
        )
    }

    private static func heldOffSummary(_ c: Case, _ power: SystemPower) -> PortSummary {
        heldOffSummary(port: c.port, type: 2,
                       sources: sources(c.sources, type: 2, number: c.port.portNumber ?? -1),
                       identities: c.identities, cio: c.cio, power: power)
    }

    private static func fired(_ s: PortSummary) -> Bool {
        s.headline == "Charger connected" || s.bullets.contains { $0.hasSuffix("W, not in use") }
    }

    @Test("Issue 672: the SMC supply signal is set on exactly the held-on-battery Macs")
    func supplySignalSeparatesHeldFromNothingAttached() {
        var withBoth = 0
        var supplied: Set<String> = []
        for (folder, power) in Self.powerByFolder where power.onBattery {
            guard power.dcInputVolts != nil, power.acW != nil else { continue }
            withBoth += 1
            if power.supply == true { supplied.insert(folder) }
        }
        print("Issue 672 supply: \(withBoth) on-battery captures with VD0R and AC-W; supplied: \(supplied.sorted())")
        #expect(withBoth > 0)
        #expect(Self.heldOffFolders.isSubset(of: supplied), "held folders without supply: \(Self.heldOffFolders.subtracting(supplied).sorted())")
        // Only the held Macs: AC-W reads 0xff on every other on-battery capture.
        #expect(supplied == Self.heldOffFolders, "unexpected supplied folders: \(supplied.subtracting(Self.heldOffFolders).sorted())")
    }

    @Test("Issue 672: m5_macos26.5.2_r (6.7 V, AC-W 0xff, nothing attached) is not a charger")
    func voltageWithoutAdapterSlotIsNotACharger() throws {
        let folder = "m5_macos26.5.2_r"
        let power = try #require(Self.powerByFolder[folder])
        #expect(power.onBattery)
        let volts = try #require(power.dcInputVolts)
        #expect(volts > 4.5, "\(volts) V: the case is only meaningful while the voltage alone would pass")
        #expect(power.acW == -1)
        #expect(power.supply == false)
        // Its retained 67W contract is on Port-USB-C@4, which only
        // ConnectionActive=false kept off the card. Force it live: still silent.
        let port4 = try #require(Self.loadPorts(folder: folder).first {
            $0.portTypeDescription == "USB-C" && $0.portNumber == 4
        })
        let src = Self.sources(Self.powerSources(folder: folder), type: 2, number: 4)
        #expect(PowerSource.hasLiveChargingContract(in: src), "fixture lost its retained contract")
        var forced = Self.heldOffSummary(port: port4.asAppleHPMInterface, type: 2, sources: src,
                                         identities: [], cio: nil, power: power)
        #expect(!Self.fired(forced), "\(forced.headline) / \(forced.bullets)")
        forced = PortSummary(port: port4.asAppleHPMInterface, sources: src, isConnectedOverride: true,
                             batteryIsCharging: false, adapter: nil, chargerHeldOffSignal: power.supply)
        #expect(!Self.fired(forced), "\(forced.headline) / \(forced.bullets)")
    }

    @Test("Issue 672: held-on-battery ports show the charger as not in use; stale contracts keep 'Connect a charger'")
    func heldOnBatteryReplay() {
        var fired: Set<String> = []
        var reached: [String: PortSummary] = [:]
        var onBatteryCases = 0
        for c in Self.cases {
            guard let power = Self.powerByFolder[c.folder], power.onBattery else { continue }
            onBatteryCases += 1
            let summary = Self.heldOffSummary(c, power)
            reached[Self.key(c)] = summary
            if Self.fired(summary) {
                fired.insert(Self.key(c))
                // The rule, from the test's own reading.
                let volts = power.dcInputVolts ?? 0
                let own = "2/\(c.port.portNumber ?? -1)"
                #expect(volts > 4.5 && power.acW != -1 && power.liveContractKeys == [own],
                    "\(Self.key(c)) fired at \(volts) V, AC-W \(power.acW ?? 99), live ports \(power.liveContractKeys)")
                #expect(summary.status != .charging && summary.status != .batteryFull)
                #expect(!summary.bullets.contains { $0.contains("Currently negotiated") })
                #expect(summary.bullets.contains { $0.hasSuffix("W, not in use") }, "\(Self.key(c)): \(summary.bullets)")
                #expect(!summary.headline.contains("Charging") && !summary.headline.contains("Plugged in")
                        && summary.subtitle != "Connect a charger to identify the cable.",
                        "\(Self.key(c)): \(summary.headline) / \(summary.subtitle)")
            }
        }
        print("Issue 672 replay: \(onBatteryCases) on-battery connected USB-C ports; fired: \(fired.sorted())")
        #expect(onBatteryCases > 0, "no on-battery corpus port reached: the sweep tests nothing")
        let missing = Self.heldOffPorts.subtracting(fired)
        #expect(missing.isEmpty, "held-on-battery ports that did not fire: \(missing.sorted().map { "\($0): \(reached[$0].map { "\($0.headline) / \($0.subtitle) / \($0.bullets)" } ?? "not reached")" })")
        #expect(fired.subtracting(Self.heldOffPorts).isEmpty, "unexpected: \(fired.subtracting(Self.heldOffPorts).sorted())")
        let key = Self.staleRetainedContractPort
        if let summary = reached[key] {
            #expect(summary.headline == "Connected", "\(key): \(summary.headline)")
            #expect(summary.subtitle == "Connect a charger to identify the cable.", "\(key): \(summary.subtitle)")
            #expect(!fired.contains(key))
        } else {
            Issue.record("\(key) was not replayed as an on-battery connected port")
        }
    }

    @Test("Issue 672: a MagSafe charger held on battery (m3_macos27.0) reads 'Charger connected'; its USB-C neighbours don't")
    func magSafeHeldOffReplay() throws {
        let folder = "m3_macos27.0"
        let power = try #require(Self.powerByFolder[folder])
        #expect(power.onBattery && power.supply == true)
        let ports = Self.loadPorts(folder: folder).filter { $0.connectionActive }
        let all = Self.powerSources(folder: folder)
        let magSafe = try #require(ports.first { $0.portTypeDescription?.hasPrefix("MagSafe") == true })
        let summary = Self.heldOffSummary(
            port: magSafe.asAppleHPMInterface, type: 17,
            sources: Self.sources(all, type: 17, number: magSafe.portNumber),
            identities: [], cio: nil, power: power)
        #expect(summary.headline == "Charger connected", "\(summary.headline) / \(summary.bullets)")
        #expect(summary.subtitle == "This Mac is running on battery and isn't drawing power from the charger. A charge-limit app can cause this.")
        #expect(summary.bullets.contains("Charger offering up to 60W, not in use"), "\(summary.bullets)")
        var usbC = 0
        for p in ports where p.portTypeDescription == "USB-C" {
            usbC += 1
            let s = Self.heldOffSummary(
                port: p.asAppleHPMInterface, type: 2,
                sources: Self.sources(all, type: 2, number: p.portNumber),
                identities: Self.identities(folder: folder).filter { $0.parentPortNumber == p.portNumber },
                cio: nil, power: power)
            #expect(!Self.fired(s), "USB-C@\(p.portNumber) relabelled: \(s.headline) / \(s.bullets)")
        }
        #expect(usbC > 0, "m3_macos27.0 lost its connected USB-C ports")
    }

    @Test("Issue 672: the 7 stale-contract folders read no charger supply and never fire")
    func staleContractFoldersStaySilent() {
        for folder in Self.staleContractFolders {
            guard let power = Self.powerByFolder[folder] else {
                Issue.record("\(folder): missing probe 32 or its flags")
                continue
            }
            #expect(power.onBattery, "\(folder) is not on battery by the app's rule")
            #expect(power.dcInputVolts != nil && power.acW != nil, "\(folder): SMC keys missing")
            #expect(power.supply == false, "\(folder): \(power.dcInputVolts ?? -1) V, AC-W \(power.acW ?? 99)")
            for c in Self.cases where c.folder == folder {
                let summary = Self.heldOffSummary(c, power)
                #expect(!Self.fired(summary), "\(Self.key(c)) fired")
            }
        }
    }

    @Test("Issue 672: off battery, the charger-supply signal changes no corpus card")
    func voltageSignalIsInertOffBattery() {
        let adapter = AdapterInfo(watts: 96, isCharging: true, source: "AC")
        var examined = 0
        var changed: [String] = []
        for c in Self.cases {
            examined += 1
            func summary(_ voltage: Bool?) -> PortSummary {
                PortSummary(port: c.port, sources: c.sources, identities: c.identities, cioCapability: c.cio,
                            batteryIsCharging: false, adapter: adapter, chargerHeldOffSignal: voltage)
            }
            let a = summary(true), b = summary(nil)
            if a.headline != b.headline || a.subtitle != b.subtitle || a.bullets != b.bullets {
                changed.append(Self.key(c))
            }
        }
        #expect(examined > 0)
        #expect(changed.isEmpty, "the supply signal changed \(changed.count) off-battery card(s): \(changed.prefix(5))")
    }
}
