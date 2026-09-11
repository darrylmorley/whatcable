import Foundation
import Testing
@testable import WhatCableCore

/// Corpus replay of the verdicts `DataLinkDiagnostic` and `PortSummary`
/// produce on real Thunderbolt ports, with every input real: the port from
/// probe 01, the cable e-marker from probe 01's SOP'/SOP'' blocks, the
/// controller's CIO reading from probes 17/19, and the trained lane rate
/// from a probe-29 fabric rebuild. There is no `tbActiveGbps` seam here.
///
/// The two existing sweeps each leave one input out. The device-cap replay
/// feeds `cio: nil` and no identities, so it never reaches the CIO half of
/// the diagnostic. The CIO sweep has no fabric, so it sets the active rate
/// equal to the CIO figure, which is the premise this file exists to test:
/// the corpus shows `CableSpeed` sitting above the trained lane on live
/// links, and reading 0 on live links, so the two are not the same reading.
///
/// Five invariants are asserted, each over the diagnostic's OUTPUT:
///
/// 1. a `.degraded` verdict needs a device known to exceed the active rate;
/// 2. a port with a live CIO row (the row's `Active` flag set, on a port
///    whose active transports include CIO, which is what the diagnostic
///    calls live) never yields `.cableContradictsActive`;
/// 3. no measured-group bullet calls the cable "N Gbps capable" for an N
///    above the lane the port trained at;
/// 4. `cableSignalConflict` survives only where the e-marker itself makes a
///    Thunderbolt-class claim (USB4 Gen 3 or Gen 4 speed bits, and only
///    those: an active-cable VDO is not a speed claim), never on a
///    USB-only speed field;
/// 5. no `.hostLimit` verdict names a host figure meaningfully below the
///    rate the link carried (a port cannot be slower than a link it
///    trained).
///
/// ## Parsing-reuse note (duplication is intentional)
///
/// Swift `private` is file-scoped, so a `private` helper in one file is not
/// visible from another even inside the same target. Following the
/// convention `DataLinkDiagnosticCIOCorpusTests` documents, this file copies
/// the parsing approach rather than widening another file's API:
///
/// - probe-01 port loading, SOP identity decoding, probe-17/19 CIO block
///   extraction and the `CIOCableCapability` conversion: from
///   `DataLinkDiagnosticCIOCorpusTests`;
/// - probe-29 instance blocks, key reads and the fabric rebuild, including
///   its ambiguity skip: from `DataLinkDeviceCapCorpusReplayTests`. That
///   file's doc comment explains what the rebuild can and cannot attribute
///   from a flat dump; the same limits apply here, and the folders it drops
///   drop out of this replay too.
///
/// The only local adaptation is that both copies read probe text through one
/// `loadProbeText(folder:probe:)` rather than two differently named loaders.
///
/// ## Dump mode
///
/// With `WC_DUMP_VERDICTS` set to a path, one TSV row per replayed port is
/// written there, so the verdicts before and after a diagnostic change can
/// be diffed port by port. Folder, port and device names go in as-is: they
/// are the product's join keys. The write is a side channel and never fails
/// a test.
@Suite("DataLinkDiagnostic - verdict corpus replay")
struct DataLinkDiagnosticVerdictReplayTests {

    // MARK: - Corpus root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private static func allProbeFolders() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: probeRoot.path) else { return [] }
        return entries.filter { entry in
            var isDir: ObjCBool = false
            let path = probeRoot.appendingPathComponent(entry).path
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted()
    }

    /// True when the raw probe files are on disk. Without them every test
    /// below returns early, the same way the CIO sweep does; with them, an
    /// empty case list is a failure, never a pass.
    private static func hasCIOProbeFiles() -> Bool {
        for folder in allProbeFolders().prefix(10) {
            for probe in ["17_deep_property_dump", "19_pdo_decode_and_usb3_watch"] {
                let url = probeRoot.appendingPathComponent(folder).appendingPathComponent("\(probe).json")
                if FileManager.default.fileExists(atPath: url.path) { return true }
            }
        }
        return false
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

    // MARK: - Probe 01: ports (duplicated from DataLinkDiagnosticCIOCorpusTests)

    private struct ProbePort {
        let serviceName: String
        let portTypeDescription: String?
        let portNumber: Int
        let transportsSupported: [String]
        let transportsActive: [String]
        let connectionActive: Bool

        var asAppleHPMInterface: AppleHPMInterface {
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

            ports.append(ProbePort(
                serviceName: parseQuoted(body, key: "Description") ?? "Port-Unknown@0",
                portTypeDescription: parseQuoted(body, key: "PortTypeDescription"),
                portNumber: parseInt(body, key: "PortNumber") ?? 0,
                transportsSupported: parseList(body, key: "TransportsSupported"),
                transportsActive: parseList(body, key: "TransportsActive"),
                connectionActive: body.contains("ConnectionActive = true")
            ))
        }
        return ports
    }

    private static func parseQuoted(_ block: String, key: String) -> String? {
        let prefix = "    \(key) = \""
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix(prefix) {
            let after = line.dropFirst(prefix.count)
            guard let closing = after.firstIndex(of: "\"") else { return nil }
            return String(after[..<closing])
        }
        return nil
    }

    private static func parseInt(_ block: String, key: String) -> Int? {
        let prefix = "    \(key) = "
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix(prefix) {
            return Int(line.dropFirst(prefix.count).prefix { $0.isNumber })
        }
        return nil
    }

    private static func parseList(_ block: String, key: String) -> [String] {
        let opener = "    \(key) = ["
        guard let openRange = block.range(of: opener) else { return [] }
        let afterOpen = block[openRange.upperBound...]
        guard let close = afterOpen.range(of: "\n    ]") else { return [] }
        return afterOpen[..<close.lowerBound].split(separator: "\n").compactMap { line -> String? in
            guard let q1 = line.firstIndex(of: "\""),
                  let q2 = line.lastIndex(of: "\""), q1 != q2 else { return nil }
            return String(line[line.index(after: q1)..<q2])
        }
    }

    // MARK: - Probe 01: SOP identities (duplicated from DataLinkDiagnosticCIOCorpusTests)

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
                    // Little-endian: "01 2b e0 05" -> 0x05e02b01
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

    // MARK: - Probes 17/19: CIO blocks (duplicated from DataLinkDiagnosticCIOCorpusTests)

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
                // A probe-17 capture chopped at the 64KB cap can end
                // mid-block with no closing marker; a fixed window keeps a
                // truncated final block from reading garbage to end of string.
                body = String(rest.prefix(2000))
            }
            blocks.append(parseProperties(body: body, indent: "    "))
            searchFrom = range.upperBound
        }
        return blocks
    }

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

    private static func parseIntLiteral(_ s: String) -> Int? {
        if let spaceIdx = s.firstIndex(of: " ") {
            if let v = Int(s[..<spaceIdx]) { return v }
        }
        return Int(s)
    }

    private static func extractCIOBlocks(text: String) -> [[String: Any]] {
        var blocks = parseEqualsBlocks(text: text, className: "IOPortTransportStateCIO")
        blocks += parseDashBlocks(text: text, classPrefix: "IOPortTransportStateCIO")
        return blocks
    }

    /// Same portKey derivation as `TRMTransportWatcher.parentPortIdentity`:
    /// `ParentBuiltInPortType`/`Number` first, then `ParentPortType`/`Number`,
    /// then the `Priority` low byte for the number.
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

    // MARK: - Probe 29 parsing (duplicated from DataLinkDeviceCapCorpusReplayTests)

    private static func parseInstanceBlocks(_ text: String, className: String) -> [String] {
        var results: [String] = []
        var open = false
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--- \(className)") && trimmed.hasSuffix("---") {
                if open { results.append(current.joined(separator: "\n")) }
                open = true
                current = []
            } else if trimmed.hasPrefix("=== ") && trimmed.hasSuffix(" ===") {
                if open { results.append(current.joined(separator: "\n")) }
                open = false
                current = []
            } else if open {
                current.append(line)
            }
        }
        if open { results.append(current.joined(separator: "\n")) }
        return results
    }

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

    private static func parseIntLine(_ body: String, key: String) -> Int? {
        for line in body.components(separatedBy: "\n") {
            guard let after = valuePart(line, key: key)?.drop(while: { $0 == " " }) else { continue }
            if let v = Int(after.prefix { $0.isNumber || $0 == "-" }) { return v }
        }
        return nil
    }

    private static func parseStringLine(_ body: String, key: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            guard let after = valuePart(line, key: key)?.drop(while: { $0 == " " }),
                  after.hasPrefix("\"") else { continue }
            let inner = after.dropFirst()
            if let close = inner.firstIndex(of: "\"") { return String(inner[..<close]) }
        }
        return nil
    }

    private static func makeReadClosure(body: String) -> (String) -> Any? {
        { key in
            if let s = parseStringLine(body, key: key) { return s as Any }
            if let n = parseIntLine(body, key: key) { return NSNumber(value: n) }
            return nil
        }
    }

    // MARK: - Fabric rebuild (duplicated from DataLinkDeviceCapCorpusReplayTests)

    /// Every switch the folder's fabric resolves to, or `nil` when the
    /// folder publishes no socket-bearing root lane at all. A downstream
    /// chain whose owning socket cannot be told apart from another's is
    /// left out rather than guessed at.
    private static func fabric(folder: String) -> [IOThunderboltSwitch]? {
        guard let text = loadProbeText(folder: folder, probe: "29_usb4_router_interfaces") else { return nil }

        // Only lane adapters carry `Micro Route String`. Non-lane adapters
        // are attributed by position: the port section is printed grouped by
        // owning switch, every block in a group carries that switch's
        // silicon `Vendor ID` and `Device ID`, and the run's own lanes name
        // the route it belongs to.
        var rootLanesBySocket: [String: [IOThunderboltPort]] = [:]
        var portsByRoute: [Int: [IOThunderboltPort]] = [:]

        struct RawPort {
            let port: IOThunderboltPort
            let micro: Int?
            let silicon: String
        }
        var rawPorts: [RawPort] = []
        for body in parseInstanceBlocks(text, className: "IOThunderboltPort") {
            guard let port = IOThunderboltPort.from(read: makeReadClosure(body: body)) else { continue }
            let vendor = parseIntLine(body, key: "Vendor ID") ?? -1
            let device = parseIntLine(body, key: "Device ID") ?? -1
            rawPorts.append(RawPort(
                port: port,
                micro: parseIntLine(body, key: "Micro Route String"),
                silicon: "\(vendor)/\(device)"
            ))
        }

        var runStart = 0
        while runStart < rawPorts.count {
            var runEnd = runStart + 1
            while runEnd < rawPorts.count, rawPorts[runEnd].silicon == rawPorts[runStart].silicon {
                runEnd += 1
            }
            let run = rawPorts[runStart..<runEnd]
            let routes = Set(run.compactMap { $0.port.adapterType.isLane ? $0.micro : nil }.filter { $0 != 0 })
            for raw in run {
                if let socketID = raw.port.socketID, !socketID.isEmpty,
                   raw.port.adapterType.isLane, raw.micro ?? 0 == 0 {
                    rootLanesBySocket[socketID, default: []].append(raw.port)
                } else if let micro = raw.micro, micro != 0 {
                    portsByRoute[micro, default: []].append(raw.port)
                } else if !raw.port.adapterType.isLane, routes.count == 1, let route = routes.first {
                    portsByRoute[route, default: []].append(raw.port)
                }
            }
            runStart = runEnd
        }
        guard !rootLanesBySocket.isEmpty else { return nil }

        // One synthetic host root per socket, ports in ascending port-number
        // order as production supplies them. The UID is a join key inside
        // this test only.
        var syntheticUID: Int64 = -1
        var roots: [IOThunderboltSwitch] = []
        for lanes in rootLanesBySocket.sorted(by: { $0.key < $1.key })
            .map({ $0.value.sorted { $0.portNumber < $1.portNumber } }) {
            let mask = lanes.reduce(UInt8(0)) { $0 | ($1.supportedSpeed?.rawValue ?? 0) }
            roots.append(IOThunderboltSwitch(
                id: syntheticUID,
                className: "IOThunderboltSwitch",
                vendorID: 1452,
                vendorName: "Apple Inc.",
                modelName: "Mac",
                routerID: 0,
                depth: 0,
                routeString: 0,
                upstreamPortNumber: 0,
                maxPortNumber: lanes.map(\.portNumber).max() ?? 0,
                supportedSpeed: SupportedSpeedMask(rawValue: mask),
                ports: lanes,
                parentSwitchUID: nil
            ))
            syntheticUID -= 1
        }

        struct RawDownstream {
            let uid: Int64
            let depth: Int
            let routeString: Int64
            let read: (String) -> Any?
            let ports: [IOThunderboltPort]
        }
        var downstream: [RawDownstream] = []
        for body in parseInstanceBlocks(text, className: "IOThunderboltSwitch") {
            guard let depth = parseIntLine(body, key: "Depth"), depth >= 1,
                  let uid = parseIntLine(body, key: "UID").map(Int64.init) else { continue }
            let route = Int64(parseIntLine(body, key: "Route String") ?? 0)
            downstream.append(RawDownstream(
                uid: uid, depth: depth, routeString: route,
                read: makeReadClosure(body: body),
                ports: (portsByRoute[Int(route)] ?? []).sorted { $0.portNumber < $1.portNumber }
            ))
        }

        // A route string repeated across two roots names no single parent.
        var routeCounts: [Int64: Int] = [:]
        for raw in downstream { routeCounts[raw.routeString, default: 0] += 1 }
        let resolvable = downstream.filter { routeCounts[$0.routeString] == 1 }

        var switches = roots
        var attachedUIDByRoute: [Int64: Int64] = [:]
        for raw in resolvable.sorted(by: { $0.depth < $1.depth }) {
            let parentUID: Int64
            if raw.depth == 1 {
                let hopByte = Int(raw.routeString & 0xFF)
                var owners = roots.filter { root in
                    root.ports.contains { $0.adapterType.isLane && $0.portNumber == hopByte }
                }
                if owners.count > 1 {
                    // Two controllers can both number a socket's lane the
                    // same. A trained lane is the one carrying a chain.
                    owners = owners.filter { root in
                        root.ports.contains {
                            $0.adapterType.isLane && $0.portNumber == hopByte && $0.hasTrainedLanes
                        }
                    }
                }
                guard owners.count == 1, let owner = owners.first else { continue }
                parentUID = owner.id
            } else {
                let parentRoute = raw.routeString & ~(Int64(0xFF) << (8 * Int64(raw.depth - 1)))
                guard let parent = attachedUIDByRoute[parentRoute] else { continue }
                parentUID = parent
            }
            guard let sw = IOThunderboltSwitch.from(
                uid: raw.uid,
                read: raw.read,
                className: "IOThunderboltSwitch",
                ports: raw.ports,
                parentSwitchUID: parentUID
            ) else { continue }
            attachedUIDByRoute[raw.routeString] = raw.uid
            switches.append(sw)
        }
        return switches
    }

    // MARK: - Replayed ports

    /// One port with an active CIO row, before the fabric gate. Kept
    /// separately from `ReplayedPort` so the e-marker/CIO counts can be
    /// reported both before and after the fabric requirement, which is the
    /// gap the Python cross-check has to explain.
    private struct Candidate {
        let folder: String
        let port: ProbePort
        /// SOP'/SOP'' entries for this port number, in probe order. The
        /// diagnostic reads the first; the claim class below reads the same
        /// one so the harness and the code under test agree on which cable.
        let identities: [USBPDSOP]
        let cio: CIOCableCapability

        var cableVDO: PDVDO.CableVDO? {
            identities.first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime })?.cableVDO
        }

        /// The e-marker makes a Thunderbolt-class claim: a USB4 Gen 3 or
        /// Gen 4 speed field, speed bits only. An active-cable VDO is not
        /// one: an active TB3 cable with a USB 2.0 data path is the normal
        /// design for that generation. False with no decodable Cable VDO.
        var tbClassClaim: Bool {
            guard let cv = cableVDO else { return false }
            return cv.speed == .usb4Gen3 || cv.speed == .usb4Gen4
        }

        var cioGbps: Double? { DataLinkDiagnostic.cioCableGbps(cio.negotiatedLinkSpeed) }
    }

    private struct ReplayedPort {
        let candidate: Candidate
        let diagnostic: DataLinkDiagnostic?
        let measuredLines: [String]
        let laneGbps: Double?

        var folder: String { candidate.folder }
        var portName: String { candidate.port.serviceName }

        /// The measured-group line the controller contributes, if any.
        var controllerBullet: String? {
            measuredLines.first { $0.contains("Controller confirms") || $0.contains("Thunderbolt link active") }
        }
    }

    /// Every (folder, port) with an active CIO row on a connected USB-C port
    /// carrying CIO, whether or not the fabric rebuilds.
    private static func computeCandidates() -> [Candidate] {
        var out: [Candidate] = []
        for folder in allProbeFolders() {
            let ports = loadPorts(folder: folder)
            guard !ports.isEmpty else { continue }

            let text17 = loadProbeText(folder: folder, probe: "17_deep_property_dump") ?? ""
            let text19 = loadProbeText(folder: folder, probe: "19_pdo_decode_and_usb3_watch") ?? ""
            let cioProps = extractCIOBlocks(text: text17) + extractCIOBlocks(text: text19)
            guard !cioProps.isEmpty else { continue }

            let ids = identities(folder: folder)

            // Probes 17 and 19 can both carry a block for the same port. One
            // row per port: the first active block wins, so a port is never
            // replayed twice with two readings.
            var seenPortNumbers = Set<Int>()
            for (i, props) in cioProps.enumerated() {
                guard (props["Active"] as? NSNumber)?.boolValue == true else { continue }
                let cio = cioCapability(entryID: UInt64(1000 + i), props: props)
                guard let portNumber = cio.portKey.split(separator: "/").last.flatMap({ Int($0) }),
                      !seenPortNumbers.contains(portNumber) else { continue }
                guard let port = ports.first(where: {
                    $0.portTypeDescription == "USB-C"
                        && $0.portNumber == portNumber
                        && $0.connectionActive
                        && $0.transportsActive.contains("CIO")
                }) else { continue }
                seenPortNumbers.insert(portNumber)
                out.append(Candidate(
                    folder: folder,
                    port: port,
                    identities: ids.filter {
                        ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime)
                            && $0.parentPortNumber == portNumber
                    },
                    cio: cio
                ))
            }
        }
        return out
    }

    private static let candidates: [Candidate] = computeCandidates()

    /// Computed once: every test walks the same corpus, and the dump is
    /// written from the same pass so the TSV and the assertions cannot
    /// disagree about what was replayed.
    private static let replay: [ReplayedPort] = computeReplay()

    private static func computeReplay() -> [ReplayedPort] {
        var out: [ReplayedPort] = []
        var fabricByFolder: [String: [IOThunderboltSwitch]?] = [:]
        for c in candidates {
            if fabricByFolder[c.folder] == nil {
                fabricByFolder[c.folder] = .some(fabric(folder: c.folder))
            }
            guard let switches = fabricByFolder[c.folder] ?? nil else { continue }
            let hpm = c.port.asAppleHPMInterface
            let diag = DataLinkDiagnostic(
                port: hpm,
                identities: c.identities,
                devices: [],
                usb3Transports: [],
                cio: c.cio,
                thunderboltSwitches: switches
            )
            let summary = PortSummary(
                port: hpm,
                identities: c.identities,
                thunderboltSwitches: switches,
                cioCapability: c.cio
            )
            out.append(ReplayedPort(
                candidate: c,
                diagnostic: diag,
                measuredLines: summary.group(.measured)?.lines ?? [],
                laneGbps: DataLinkDiagnostic.activeTBGbps(port: hpm, switches: switches)
            ))
        }
        out.sort { ($0.folder, $0.portName) < ($1.folder, $1.portName) }
        writeDump(out)
        return out
    }

    // MARK: - Dump

    private static func verdictName(_ diag: DataLinkDiagnostic?) -> String {
        guard let diag else { return "" }
        switch diag.bottleneck {
        case .fine: return "fine"
        case .cableLimit: return "cableLimit"
        case .hostLimit: return "hostLimit"
        case .deviceLimit: return "deviceLimit"
        case .degraded: return "degraded"
        case .unknownCable: return "unknownCable"
        case .cableContradictsActive: return "cableContradictsActive"
        case .blockedBySecurity: return "blockedBySecurity"
        }
    }

    private static func cell(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : "\(value)"
    }

    private static func cell(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func writeDump(_ rows: [ReplayedPort]) {
        guard let path = ProcessInfo.processInfo.environment["WC_DUMP_VERDICTS"], !path.isEmpty else { return }
        let header = [
            "folder", "port", "cableSpeed", "laneGbps", "cioGbps", "emarkerGbps", "emarkerSpeedCode",
            "cableType", "hostGbps", "deviceGbps", "deviceName", "cableGbps", "verdict", "activeGbps",
            "expectedGbps", "conflict", "controllerBullet", "diagNil"
        ]
        var lines = [header.joined(separator: "\t")]
        for r in rows {
            let c = r.candidate
            let facts = r.diagnostic?.facts
            var expected: Double?
            if case .degraded(_, let e) = r.diagnostic?.bottleneck { expected = e }
            let cableType: String
            if let cv = c.cableVDO {
                cableType = cv.cableType == .active ? "active" : "passive"
            } else {
                cableType = "none"
            }
            let row: [String] = [
                c.folder,
                c.port.serviceName,
                cell(c.cio.negotiatedLinkSpeed),
                cell(r.laneGbps),
                cell(c.cioGbps),
                cell(facts?.cableEmarkerGbps),
                cell(c.cableVDO?.speed.rawValue),
                cableType,
                cell(facts?.hostGbps),
                cell(facts?.deviceGbps),
                facts?.deviceName ?? "",
                cell(facts?.cableGbps),
                verdictName(r.diagnostic),
                cell(facts?.activeGbps),
                cell(expected),
                r.diagnostic.map { $0.cableSignalConflict ? "true" : "false" } ?? "",
                r.controllerBullet ?? "",
                r.diagnostic == nil ? "true" : "false"
            ]
            lines.append(row.joined(separator: "\t"))
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                        atomically: true, encoding: .utf8)
    }

    // MARK: - Cross-check counts

    /// The three predicates the Python cross-check counts, over any set of
    /// candidates, so the two parsers report the same things.
    private struct CrossCheck {
        var speedZeroWithGen1Emarker = 0
        var emarkerBelowCIOBySpeedCode: [Int: Int] = [:]
        var emarkerBelowCIO: Int { emarkerBelowCIOBySpeedCode.values.reduce(0, +) }
        var emarkerBelowCIOWithTBClaim = 0

        init(_ candidates: [Candidate]) {
            for c in candidates {
                guard let cv = c.cableVDO else { continue }
                if c.cio.negotiatedLinkSpeed == 0, cv.speed == .usb32Gen1 {
                    speedZeroWithGen1Emarker += 1
                }
                // The pre-fix conflict predicate: e-marker tier meaningfully
                // below a mapped CIO tier.
                if let cioGbps = c.cioGbps, DataLinkDiagnostic.meaningfullySlower(cv.speed.maxGbps, than: cioGbps) {
                    emarkerBelowCIOBySpeedCode[cv.speed.rawValue, default: 0] += 1
                    if c.tbClassClaim { emarkerBelowCIOWithTBClaim += 1 }
                }
            }
        }

        var description: String {
            let byCode = emarkerBelowCIOBySpeedCode.sorted { $0.key < $1.key }
                .map { "code \($0.key): \($0.value)" }.joined(separator: ", ")
            return "(a) CableSpeed=0 with Gen 1 e-marker: \(speedZeroWithGen1Emarker); "
                + "(b) e-marker below CIO tier: \(emarkerBelowCIO) [\(byCode)]; "
                + "(c) of those making a TB-class claim: \(emarkerBelowCIOWithTBClaim)"
        }
    }

    private static func recordViolators(_ title: String, _ violators: [String]) {
        guard !violators.isEmpty else { return }
        let detail = violators.joined(separator: "\n")
        Issue.record("\(title): \(violators.count) violator(s)\n\(detail)")
    }

    // MARK: - Invariants

    @Test("Corpus replay: a degraded verdict needs a device known to exceed the active rate")
    func noDegradedWithoutDeviceAboveActive() {
        guard Self.hasCIOProbeFiles() else { return }
        let replay = Self.replay
        guard !replay.isEmpty else {
            Issue.record("No ports replayed; the degraded invariant tested nothing")
            return
        }
        var degraded = 0
        var violators: [String] = []
        for r in replay {
            guard let diag = r.diagnostic, case .degraded(let active, _) = diag.bottleneck else { continue }
            degraded += 1
            if let device = diag.facts.deviceGbps,
               DataLinkDiagnostic.meaningfullySlower(active, than: device) {
                continue
            }
            violators.append("\(r.folder) \(r.portName): degraded at \(Self.cell(active)), device \(Self.cell(diag.facts.deviceGbps))")
        }
        print("Verdict replay (degraded): \(replay.count) ports, \(degraded) degraded, \(violators.count) without a device above the active rate")
        Self.recordViolators("Degraded without a device above the active rate", violators)
        #expect(violators.isEmpty)
    }

    @Test("Corpus replay: a live CIO row never yields a cable contradiction")
    func noCableContradictionWithLiveCIORow() {
        // Every replayed row is live in the diagnostic's sense: `Active`
        // set and CIO in the port's active transports (see `replay`).
        guard Self.hasCIOProbeFiles() else { return }
        let replay = Self.replay
        guard !replay.isEmpty else {
            Issue.record("No ports replayed; the contradiction invariant tested nothing")
            return
        }
        var violators: [String] = []
        for r in replay {
            guard let diag = r.diagnostic,
                  case .cableContradictsActive(let cable, let active) = diag.bottleneck else { continue }
            violators.append("\(r.folder) \(r.portName): cable \(Self.cell(cable)), active \(Self.cell(active)), CableSpeed \(Self.cell(r.candidate.cio.negotiatedLinkSpeed))")
        }
        print("Verdict replay (contradiction): \(replay.count) ports, \(violators.count) cable contradictions")
        Self.recordViolators("Cable contradiction on a port with an active CIO row", violators)
        #expect(violators.isEmpty)
    }

    @Test("Corpus replay: no capable bullet names a figure above the trained lane")
    func noCapableBulletAboveLane() {
        guard Self.hasCIOProbeFiles() else { return }
        let replay = Self.replay
        guard !replay.isEmpty else {
            Issue.record("No ports replayed; the capable-bullet invariant tested nothing")
            return
        }
        var checked = 0
        var violators: [String] = []
        for r in replay {
            guard let lane = r.laneGbps else { continue }
            for line in r.measuredLines {
                guard let range = line.range(of: " Gbps capable") else { continue }
                let digits = line[..<range.lowerBound].reversed().prefix { $0.isNumber }
                guard let figure = Int(String(digits.reversed())) else { continue }
                checked += 1
                if Double(figure) > lane {
                    violators.append("\(r.folder) \(r.portName): \"\(line)\" with lane \(Self.cell(lane))")
                }
            }
        }
        print("Verdict replay (capable bullet): \(replay.count) ports, \(checked) capable bullets, \(violators.count) above the lane")
        Self.recordViolators("Capable bullet above the trained lane", violators)
        // Floor so a wording change that stops the bullet matching cannot
        // pass vacuously: 237 capable bullets measured 2026-09-11 (read the
        // figure off the print above), floor at roughly 85%.
        #expect(checked >= 200, "only \(checked) capable bullets checked: the invariant may be matching nothing")
        #expect(violators.isEmpty)
    }

    @Test("Corpus replay: a signal conflict survives only on a Thunderbolt-class e-marker claim")
    func conflictSurvivorsMakeTBClassClaims() {
        guard Self.hasCIOProbeFiles() else { return }
        let replay = Self.replay
        guard !replay.isEmpty else {
            Issue.record("No ports replayed; the conflict invariant tested nothing")
            return
        }
        var conflicts = 0
        var violators: [String] = []
        for r in replay {
            guard let diag = r.diagnostic, diag.cableSignalConflict else { continue }
            conflicts += 1
            guard !r.candidate.tbClassClaim else { continue }
            let cv = r.candidate.cableVDO
            violators.append("\(r.folder) \(r.portName): e-marker speed \(cv.map { $0.speed.reportLabel } ?? "none"), cable type \(cv.map { $0.cableType == .active ? "active" : "passive" } ?? "none"), CIO \(Self.cell(r.candidate.cioGbps))")
        }
        print("Verdict replay (conflict): \(replay.count) ports, \(conflicts) conflicts, \(violators.count) on a USB-only e-marker")
        print("Verdict replay cross-check, replayed ports: \(CrossCheck(replay.map(\.candidate)).description)")
        print("Verdict replay cross-check, all active CIO ports (no fabric gate): \(CrossCheck(Self.candidates).description)")
        Self.recordViolators("Signal conflict on a USB-only e-marker", violators)
        #expect(violators.isEmpty)
    }

    @Test("Corpus replay: no host-limit verdict names a host figure below the active rate")
    func noHostLimitBelowActiveRate() {
        guard Self.hasCIOProbeFiles() else { return }
        let replay = Self.replay
        guard !replay.isEmpty else {
            Issue.record("No ports replayed; the host-limit invariant tested nothing")
            return
        }
        var hostLimits = 0
        var violators: [String] = []
        for r in replay {
            guard let diag = r.diagnostic, case .hostLimit(let host, _) = diag.bottleneck else { continue }
            hostLimits += 1
            guard DataLinkDiagnostic.meaningfullySlower(host, than: diag.facts.activeGbps) else { continue }
            violators.append("\(r.folder) \(r.portName): host limit \(Self.cell(host)) on a link carrying \(Self.cell(diag.facts.activeGbps)), lane \(Self.cell(r.laneGbps))")
        }
        print("Verdict replay (host limit): \(replay.count) ports, \(hostLimits) host limits, \(violators.count) below the active rate")
        Self.recordViolators("Host limit below the active rate", violators)
        #expect(violators.isEmpty)
    }

    // MARK: - Coverage

    /// Floors, so a green run over an empty or shrunken corpus fails loudly.
    /// Re-derived 2026-09-11 from this file's own print against the
    /// 1415-folder corpus (385 ports replayed, 383 non-nil diagnostics),
    /// then set at roughly 85% of the measured figure. Raise these only
    /// against another measured run, and read the figure off the print
    /// rather than from here.
    @Test("Corpus replay: coverage floors and named folders")
    func coverageFloorsHold() {
        guard Self.hasCIOProbeFiles() else { return }
        let replay = Self.replay
        let nonNil = replay.filter { $0.diagnostic != nil }
        let foldersWithCIORows = Set(Self.candidates.map(\.folder)).count
        let foldersReplayed = Set(replay.map(\.folder)).count
        print("Verdict replay coverage: \(foldersWithCIORows) folders with active CIO rows, \(foldersReplayed) with a rebuilt fabric, \(Self.candidates.count) candidate ports, \(replay.count) replayed, \(nonNil.count) non-nil diagnostics, \(replay.count - nonNil.count) nil")

        #expect(replay.count >= 327,
            "only \(replay.count) ports replayed: the corpus is missing or the fabric rebuild stopped resolving")
        #expect(nonNil.count >= 325,
            "only \(nonNil.count) non-nil diagnostics: the invariants have nothing left to bite on")

        // Named cases the diagnostic change was written against. Each must
        // resolve a non-nil diagnostic, or the fix has nothing to prove on.
        let named: [(folder: String, portNumber: Int?)] = [
            ("m5pro_macos26.5.1_b", 3),
            ("m1max_macos26.5.1_c", 1),
            ("m3pro_macos26.5.1", 1),
            ("m2max_macos26.6.2", nil)
        ]
        for (folder, portNumber) in named {
            let hit = nonNil.first {
                $0.folder == folder && (portNumber == nil || $0.candidate.port.portNumber == portNumber)
            }
            #expect(hit != nil,
                "\(folder) port \(portNumber.map(String.init) ?? "any") did not resolve a non-nil diagnostic")
            if let hit {
                print("Verdict replay named case: \(folder) \(hit.portName) -> \(Self.verdictName(hit.diagnostic)), device \(hit.diagnostic?.facts.deviceName ?? "none")")
            }
        }
    }

    // MARK: - Verdict-case stability (wording-only changes must not move a case)

    /// One row per replayed port: which `Bottleneck` CASE it resolved to
    /// (never the wording). A wording-only change to `DataLinkDiagnostic`'s
    /// `detail` strings must never move a port from one case to another;
    /// this is the corpus-wide net that proves it, the same golden-file
    /// idiom `FormatterGoldenOutputTests` uses for rendered output.
    ///
    /// The comparison is keyed by `folder\tport`, not by the row set: a port
    /// present in both the golden snapshot and the current replay fails the
    /// test if its verdict case differs, but a port that is only in one side
    /// (the corpus gained or lost a folder since the golden file was
    /// captured, e.g. a new test-kit submission was ingested) is not a
    /// failure on its own. Corpus growth/shrinkage is not a verdict-wording
    /// regression, and a `#expect` over the raw row set would red every
    /// checkout the next time a probe is ingested, for a reason this test
    /// has nothing to do with.
    ///
    /// Regenerating: `WC_REGENERATE_GOLDEN=1 swift test --filter
    /// DataLinkDiagnosticVerdictReplayTests` rewrites the golden file and
    /// the run reports the rewrite as a failure, so a regeneration can never
    /// be mistaken for a pass. Only regenerate against a change that is
    /// KNOWN to alter verdict selection (never for a wording-only change,
    /// which is the exact thing this net exists to catch), or to pick up new
    /// corpus coverage after growth; review the diff before committing a
    /// regenerated file.
    private static let goldenDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("golden")

    private static let goldenFileName = "data-link-verdict-replay-cases.tsv"

    private static var isRegeneratingGolden: Bool {
        ProcessInfo.processInfo.environment["WC_REGENERATE_GOLDEN"] == "1"
    }

    /// `folder\tport\tverdict` per replayed port, sorted the same way
    /// `replay` already is (folder, then port name), so the golden file
    /// diffs cleanly and the comparison needs no re-sorting.
    private static func verdictCaseRows(_ replay: [ReplayedPort]) -> String {
        replay.map { "\($0.folder)\t\($0.portName)\t\(Self.verdictName($0.diagnostic))" }
            .joined(separator: "\n") + "\n"
    }

    /// Parses `folder\tport\tverdict` rows into a map keyed by `folder\tport`,
    /// so the comparison below can tell "changed" apart from "new" or "gone".
    private static func verdictCaseMap(_ rows: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in rows.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            map["\(fields[0])\t\(fields[1])"] = String(fields[2])
        }
        return map
    }

    @Test("Corpus replay: verdict CASE per port is unchanged (wording-only net)")
    func verdictCasesUnchanged() throws {
        guard Self.hasCIOProbeFiles() else { return }
        let replay = Self.replay
        guard !replay.isEmpty else {
            Issue.record("No ports replayed; the verdict-case stability net tested nothing")
            return
        }
        let actual = Self.verdictCaseRows(replay)
        let url = Self.goldenDirectory.appendingPathComponent(Self.goldenFileName)

        if Self.isRegeneratingGolden {
            try FileManager.default.createDirectory(
                at: Self.goldenDirectory, withIntermediateDirectories: true)
            try actual.write(to: url, atomically: true, encoding: .utf8)
            Issue.record("Regenerated \(Self.goldenFileName) (\(replay.count) rows). Review the diff, then re-run without WC_REGENERATE_GOLDEN.")
            return
        }
        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record("Missing golden file \(Self.goldenFileName). Run WC_REGENERATE_GOLDEN=1 swift test --filter DataLinkDiagnosticVerdictReplayTests to create it.")
            return
        }

        let actualMap = Self.verdictCaseMap(actual)
        let expectedMap = Self.verdictCaseMap(expected)

        let changed = actualMap.compactMap { key, verdict -> String? in
            guard let was = expectedMap[key], was != verdict else { return nil }
            return "\(key)\t\(was) -> \(verdict)"
        }.sorted()

        let added = actualMap.keys.filter { expectedMap[$0] == nil }
        let removed = expectedMap.keys.filter { actualMap[$0] == nil }
        if !added.isEmpty || !removed.isEmpty {
            print("""
                Verdict replay golden note: \(added.count) port(s) new since the golden \
                snapshot, \(removed.count) no longer replayed. Not a failure on their own \
                (corpus growth/shrinkage, not a wording change); regenerate with \
                WC_REGENERATE_GOLDEN=1 if the golden file should cover them.
                """)
        }

        if !changed.isEmpty {
            Issue.record("""
                verdict case(s) changed for \(changed.count) port(s) present in both the \
                golden snapshot and the current replay:
                \(changed.prefix(10).joined(separator: "\n"))
                If this is a deliberate verdict-selection change, regenerate with \
                WC_REGENERATE_GOLDEN=1 and review the diff. A wording-only change must \
                never hit this.
                """)
        }
        #expect(changed.isEmpty, "\(changed.count) port(s) changed verdict case since the golden snapshot")
    }
}
