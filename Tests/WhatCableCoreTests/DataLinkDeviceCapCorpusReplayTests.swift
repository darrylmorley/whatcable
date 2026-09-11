import Foundation
import Testing
@testable import WhatCableCore

/// Corpus replay for the device-cap upper guard: no port anywhere in the
/// corpus may report a `.deviceLimit` whose device figure sits meaningfully
/// below the rate the link was measured carrying. An endpoint cannot be
/// slower than a link it took part in, so such a verdict blames a party the
/// evidence exonerates.
///
/// The replay feeds real probe-01 ports and a real probe-29 Thunderbolt
/// fabric into `DataLinkDiagnostic` and asserts against the verdict it
/// produces, rather than against hand-built inputs.
///
/// ## Parsing-reuse note (duplication is intentional)
///
/// Swift `private` is file-scoped, so a `private` helper in one file is not
/// visible from another even inside the same target. Following the
/// convention `DataLinkDiagnosticCIOCorpusTests` documents, this file copies
/// the parsing approach rather than widening another file's API:
///
/// - probe-01 port loading: from `DataLinkDiagnosticProbeSweepTests`
/// - probe-29 instance blocks, key reads and hop rows: from
///   `ThunderboltProbeSweepTests`
///
/// ## How the fabric is rebuilt, and what that costs
///
/// Probe 29 is a flat dump: it prints `IOThunderboltSwitch` and
/// `IOThunderboltPort` in separate sections and does not say which switch
/// owns which port. Three things put it back:
///
/// - a downstream switch's LANE ports carry `Micro Route String`, equal to
///   that switch's own `Route String`;
/// - a host root's user-visible lane ports carry a `Socket ID`, the same
///   `@N` suffix the USB-C port publishes;
/// - protocol adapters carry neither, so they are attributed by position: the
///   port section is printed grouped by owning switch, every block in a group
///   carries that switch's silicon `Vendor ID` and `Device ID`, and the
///   group's own lanes name the route it belongs to.
///
/// That last one is load-bearing. Without it no switch in the replay has a
/// non-lane adapter, every partner reads as a passthrough, and the walk under
/// test is never the one production runs.
///
/// What is missing is which of a Mac's several depth-0 switches owns a given
/// socket: 1289 of 1336 folders publish more than one root and the port
/// blocks do not name their parent. So the replay builds one host root per
/// socket ID, holding that socket's own lane ports, with a synthetic UID
/// (real UIDs belong to switches, and no real one is resolvable here). A
/// depth-1 switch is attached to the socket root whose lane port number
/// matches hop byte 0 of its route string; when that matches more than one
/// socket root the folder is ambiguous and is skipped rather than guessed
/// at. Deeper switches attach to the switch one hop up their own route.
///
/// The replay therefore covers fewer ports than production sees, and never
/// more: an unresolvable folder drops out. That is the safe direction for an
/// invariant test.
@Suite("DataLinkDiagnostic - device cap corpus replay")
struct DataLinkDeviceCapCorpusReplayTests {

    // MARK: - Corpus root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private static func allProbes() -> [String] {
        guard FileManager.default.fileExists(atPath: probeRoot.path),
              let entries = try? FileManager.default.contentsOfDirectory(atPath: probeRoot.path)
        else { return [] }
        return entries.filter { entry in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(
                atPath: probeRoot.appendingPathComponent(entry).path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted()
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

    // MARK: - Probe 01 ports (duplicated from DataLinkDiagnosticProbeSweepTests)

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
        return afterOpen[..<close.lowerBound].split(separator: "\n").compactMap { line in
            guard let q1 = line.firstIndex(of: "\""),
                  let q2 = line.lastIndex(of: "\""), q1 != q2 else { return nil }
            return String(line[line.index(after: q1)..<q2])
        }
    }

    private static func loadPorts(folder: String) -> [AppleHPMInterface] {
        guard let text = loadProbeText(folder: folder, fileName: "01_walk_pd_tree.json") else { return [] }
        let rawChunks = text.components(separatedBy: "=== IOAccessoryManager[")
        guard rawChunks.count > 1 else { return [] }
        let parts: [String] = rawChunks.dropFirst().compactMap { chunk in
            guard let endOfHeader = chunk.range(of: "===\n") else { return nil }
            return String(chunk[endOfHeader.upperBound...])
        }

        var ports: [AppleHPMInterface] = []
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
            ports.append(AppleHPMInterface(
                id: UInt64(portNumber),
                serviceName: serviceName,
                className: portType == "MagSafe 3" ? "AppleTCControllerType11" : "AppleTCControllerType10",
                portDescription: serviceName,
                portTypeDescription: portType,
                portNumber: portNumber,
                connectionActive: body.contains("ConnectionActive = true"),
                activeCable: nil,
                opticalCable: nil,
                usbActive: nil,
                superSpeedActive: nil,
                usbModeType: nil,
                usbConnectString: nil,
                transportsSupported: parseList(body, key: "TransportsSupported"),
                transportsActive: parseList(body, key: "TransportsActive"),
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
            ))
        }
        return ports
    }

    // MARK: - Probe 29 parsing (duplicated from ThunderboltProbeSweepTests)

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

    // MARK: - Fabric rebuild

    /// Every switch the folder's fabric resolves to, or `nil` when the
    /// folder publishes no socket-bearing root lane at all.
    ///
    /// A downstream chain whose owning socket cannot be told apart from
    /// another's is left out rather than guessed at. That costs coverage on
    /// those ports (they replay with no partner, so no device cap) and never
    /// invents one, which is the safe direction for an invariant test.
    private static func fabric(folder: String) -> [IOThunderboltSwitch]? {
        guard let text = loadProbeText(folder: folder, fileName: "29_usb4_router_interfaces.json") else { return nil }

        // Ports, split into socket-bearing root lanes and everything a
        // downstream switch claims.
        //
        // Only lane adapters carry `Micro Route String`, so a switch's PCIe,
        // DisplayPort and USB adapters have to be attributed some other way.
        // Probe 29 prints the port section grouped by owning switch, and every
        // block in a group carries that switch's silicon `Vendor ID` and
        // `Device ID`, so a contiguous run of blocks sharing those two is one
        // switch's ports. The run's own lanes then name the route it belongs
        // to. A run whose lanes name more than one route is ambiguous and its
        // non-lane adapters are left off rather than guessed at.
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
                    // A non-lane adapter in a run whose lanes name exactly one
                    // downstream route belongs to that switch.
                    portsByRoute[route, default: []].append(raw.port)
                }
            }
            runStart = runEnd
        }
        guard !rootLanesBySocket.isEmpty else { return nil }

        // One synthetic host root per socket. The UID is synthetic because
        // no real one is attributable from a flat dump; it is a join key
        // inside this test only and never leaves it.
        // Ports go in ascending port-number order, the order production
        // supplies them in (see the watcher's `portsInPortNumberOrder`), and
        // two consumers take the FIRST lane of what they are handed. The dump
        // prints lane 2 before lane 1 on 21 machines, so replaying it
        // verbatim would replay a fabric production never sees: those 21
        // ports resolve no Thunderbolt partner in dump order and do in port
        // order.
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

        // Downstream switches, real UIDs, real ports.
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

        // A route string repeated across two roots names no single parent,
        // so every switch sharing it is left out.
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

    // MARK: - The invariant

    /// The chain shape the terminal-walk guard is about, replayed. Two
    /// folders whose direct partner is a dock with a display or a drive
    /// behind it: the device on the cable is the dock, never the leaf.
    ///
    /// `m1_macos26.5.1_y` is the third folder of this shape and is
    /// deliberately absent. Two of its roots both number a lane 1 and both
    /// read trained, so the socket that owns its chain cannot be told apart
    /// from a flat probe-29 dump. Production resolves that with the real
    /// `parentSwitchUID` from the registry tree, which this harness does not
    /// have. It is a harness limit, not a product gap, and forcing a
    /// tie-break here would make the folder prove whatever the tie-break
    /// chose.
    @Test("Corpus replay: a dock names the dock, not what is behind it")
    func dockNamesTheDockNotTheLeaf() {
        let expected = [
            "m4max_macos27.0_b": "FusionDock Pro 3",
            "m4pro_macos26.5.2_p": "Thunderbolt 4 Pro Dock"
        ]
        var checked = 0
        for (folder, dockName) in expected.sorted(by: { $0.key < $1.key }) {
            guard let switches = Self.fabric(folder: folder) else {
                Issue.record("\(folder): fabric did not rebuild")
                continue
            }
            var names: [String] = []
            for port in Self.loadPorts(folder: folder) {
                guard let diag = DataLinkDiagnostic(
                    port: port,
                    identities: [],
                    devices: [],
                    usb3Transports: [],
                    cio: nil,
                    thunderboltSwitches: switches
                ), let name = diag.facts.deviceName else { continue }
                names.append(name)
            }
            checked += 1
            #expect(names.contains(dockName),
                "\(folder): expected the device on the cable to be \(dockName), got \(names)")
        }
        #expect(checked == expected.count,
            "only \(checked) of \(expected.count) chain folders replayed")
    }

    @Test("Corpus replay: no device limit is reported below the rate the link carried")
    func noDeviceLimitBelowActiveRate() {
        var foldersReplayed = 0
        var verdicts = 0
        var deviceLimits = 0
        var hostCapsBelowActive = 0

        for folder in Self.allProbes() {
            guard let switches = Self.fabric(folder: folder) else { continue }
            let ports = Self.loadPorts(folder: folder)
            guard !ports.isEmpty else { continue }
            foldersReplayed += 1

            for port in ports {
                guard let diag = DataLinkDiagnostic(
                    port: port,
                    identities: [],
                    devices: [],
                    usb3Transports: [],
                    cio: nil,
                    thunderboltSwitches: switches
                ) else { continue }
                verdicts += 1
                // Measurement, not an assertion: the same shape on the host
                // side would want its own guard, and this counts whether the
                // corpus holds one.
                if let hostGbps = diag.facts.hostGbps,
                   DataLinkDiagnostic.meaningfullySlower(hostGbps, than: diag.facts.activeGbps) {
                    hostCapsBelowActive += 1
                }
                guard case .deviceLimit(let deviceGbps) = diag.bottleneck else { continue }
                deviceLimits += 1
                #expect(
                    !DataLinkDiagnostic.meaningfullySlower(deviceGbps, than: diag.facts.activeGbps),
                    """
                    \(folder) \(port.serviceName): device limit \(deviceGbps) Gbps \
                    is below the measured link rate \(diag.facts.activeGbps) Gbps
                    """
                )
            }
        }

        print("""
            Device-cap replay: \(foldersReplayed) folders, \(verdicts) verdicts, \
            \(deviceLimits) of them device limits, \(hostCapsBelowActive) host caps below the link rate
            """)
        // Floors, so a green run over an empty corpus fails loudly instead of
        // reading as a pass. Re-derived 2026-09-11 from the run's own print:
        // 1234 folders replayed, 384 verdicts, 40 of them device limits.
        // Checked against a port-number-ordered run too (ports sorted by
        // `portNumber` before the inner loop, temporarily, then reverted):
        // same 40, confirming the earlier 25 was a stale reading rather than
        // an ordering effect this loop is actually sensitive to (each port's
        // diagnostic only depends on that port and the shared fabric, never
        // on iteration order). Raise these only against another measured
        // run, and read the figure off the print rather than from here.
        #expect(verdicts > 250,
            "only \(verdicts) verdicts replayed: the corpus is missing or the fabric rebuild stopped resolving")
        #expect(deviceLimits > 10,
            "only \(deviceLimits) device limits replayed: the invariant has nothing left to bite on")
    }
}
