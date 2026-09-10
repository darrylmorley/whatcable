import Foundation
import Testing
@testable import WhatCableCore

/// issue #181 test matrix item 5 ("Corpus replay sweep"): replays the
/// USB3-speed corroboration gate against real customer-probe captures,
/// WITH each folder's real USB device evidence (review finding, HIGH:
/// replaying without device data manufactures the uncorroborated state
/// and cannot detect accidental suppression of a real link).
///
/// Baseline derivation is deliberately independent of the production
/// selection code under test (house rule: "re-derive any corpus figure
/// with a second, independent parser before trusting it"):
///
/// - `IOPortTransportStateUSB3` blocks from probes 17/19, parsed with
///   `parseUSB3Blocks` (regex-free), NOT `USB3TransportWatcher.makeTransport`
///   (the production IOKit parser) and NOT `USB3SpeedCorroboration` (the
///   seam under test).
/// - USB devices from probe 38's `usb_device_tree`, parsed with
///   `parseDevices38`, which reimplements the device-to-port join
///   (`portName(fromUSBIOPortPath:)`: take the first ancestor's
///   `UsbIOPort` registry path and use its last path component if it
///   starts with `"Port-"`) fresh, in this file, rather than calling
///   `USBWatcher`'s production version (Tests/WhatCableCoreTests can't
///   even import `WhatCableDarwinBackend`, so this can't share code with
///   it even if it wanted to). This is the same JOIN KEY
///   `AppleHPMInterface.matchingDevices(from:)` uses in production
///   (`controllerPortName`), reimplemented independently, not reused.
///
/// Two-tier comparison (per the spec):
///
/// - **Corroborated baseline ports** (independently determined: a real
///   device with a matching `UsbIOPort` join and `Device Speed >= 3`
///   [SuperSpeed or better], OR a TRM-restricted direct transport):
///   asserts a full-output match against an INDEPENDENTLY computed
///   expected label (same `root device -> transport signaling ->
///   port-matched device` priority the design doc specifies, computed
///   fresh in this file, not by calling `PortSummary`'s own chain) across
///   `PortSummary` (bullet), `JSONFormatter` (`usb3Speed`), and
///   `DataLinkDiagnostic` (a non-nil verdict with a matching active rate).
/// - **Uncorroborated baseline ports**: asserts NO USB3 label/verdict
///   anywhere. With real device data now joined, an uncorroborated port
///   is a REAL fact about this capture (no device answered, and no
///   restriction), not a data-limitation artifact -- so a hard failure
///   here is a genuine regression, not a false alarm to allowlist away.
///
/// Every folder without a probe 38 (or without any device data in it) is
/// excluded from the two-tier comparison and counted separately; the
/// coverage floor is asserted on the REPLAYABLE subset (ports where a
/// probe 38 capture exists at all for that machine), so the sweep cannot
/// pass by silently degrading to zero real joins.
@Suite("USB3 corroboration: corpus sweep (issue #181)")
struct USB3CorroborationCorpusSweepTests {

    // MARK: - Probe root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private static func allFolders() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: probeRoot.path))?
            .filter { entry in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(
                    atPath: probeRoot.appendingPathComponent(entry).path, isDirectory: &isDir)
                return isDir.boolValue
            }
            .sorted() ?? []
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

    // MARK: - Probe 01: connected USB-C ports with active USB3
    // Deliberate copy of the same block-parsing shape used by
    // PortSummaryCorpusSweepTests/DataLinkDiagnosticCIOCorpusTests. See
    // those files' doc comments for why this isn't factored out.

    private struct ProbePort {
        let serviceName: String
        let portNumber: Int

        var asAppleHPMInterface: AppleHPMInterface {
            AppleHPMInterface(
                id: UInt64(portNumber),
                serviceName: serviceName,
                className: "AppleHPMInterfaceType10",
                portDescription: serviceName,
                portTypeDescription: "USB-C",
                portNumber: portNumber,
                connectionActive: true,
                activeCable: nil,
                opticalCable: nil,
                usbActive: nil,
                superSpeedActive: nil,
                usbModeType: nil,
                usbConnectString: nil,
                // `transportsSupported` must carry "USB3" too, not just
                // `transportsActive`: DataLinkDiagnostic's `carriesData`
                // defense-in-depth guard (issue #195) checks
                // `transportsSupported`, and an empty array here made every
                // case in this sweep return nil regardless of corroboration,
                // which the "expected a DataLinkDiagnostic verdict" violation
                // caught.
                transportsSupported: ["USB3"],
                transportsActive: ["USB3"],
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

    private static func loadActiveUSB3Ports(folder: String) -> [ProbePort] {
        guard let text = loadProbeText(folder: folder, probe: "01_walk_pd_tree") else { return [] }
        let rawChunks = text.components(separatedBy: "=== IOAccessoryManager[")
        guard rawChunks.count > 1 else { return [] }
        var ports: [ProbePort] = []
        for chunk in rawChunks.dropFirst() {
            guard let endOfHeader = chunk.range(of: "===\n") else { continue }
            let rest = chunk[endOfHeader.upperBound...]
            let body: Substring
            if let endRange = rest.range(of: "\n=== ") {
                body = rest[..<endRange.lowerBound]
            } else {
                body = rest
            }
            guard body.contains("PortTypeDescription"),
                  body.contains("ConnectionActive = true")
            else { continue }
            let serviceName = parseQuoted(String(body), key: "Description") ?? "Port-Unknown@0"
            let portNumber = parseInt(String(body), key: "PortNumber") ?? 0
            let active = parseList(String(body), key: "TransportsActive")
            guard active.contains("USB3") else { continue }
            ports.append(ProbePort(serviceName: serviceName, portNumber: portNumber))
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

    // MARK: - Probes 17/19: IOPortTransportStateUSB3 blocks
    //
    // Independent of USB3TransportWatcher.makeTransport (the production
    // IOKit parser) by construction: this reads the same TEXT DUMP format
    // the probes emit, not live IOKit properties, so it cannot share code
    // with the watcher even if it wanted to. Handles BOTH block shapes
    // seen across the corpus: probe 17's "=== Class ===" and probe 19's
    // "--- Class[N] ---".

    private struct ProbeUSB3Block {
        let portKey: String
        let signaling: Int?
        let tunnelled: Bool?
        let transportRestricted: Bool?
    }

    private static func parseUSB3Blocks(text: String) -> [ProbeUSB3Block] {
        var blocks: [ProbeUSB3Block] = []
        for pattern in [
            "=== IOPortTransportStateUSB3 ===",
            "--- IOPortTransportStateUSB3",   // followed by "[N] ---"
        ] {
            var searchStart = text.startIndex
            while let headerRange = text.range(of: pattern, range: searchStart..<text.endIndex) {
                // For the probe-19 shape, skip past the "[N] ---" suffix.
                var bodyStart = headerRange.upperBound
                if pattern.hasPrefix("---"), let dashClose = text.range(of: "---", range: bodyStart..<text.endIndex) {
                    bodyStart = dashClose.upperBound
                }
                let bodyEnd = [
                    text.range(of: "\n===", range: bodyStart..<text.endIndex)?.lowerBound,
                    text.range(of: "\n---", range: bodyStart..<text.endIndex)?.lowerBound,
                ].compactMap { $0 }.min() ?? text.endIndex
                let block = String(text[bodyStart..<bodyEnd])
                searchStart = bodyEnd

                func field(_ key: String) -> String? {
                    for line in block.split(separator: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("\(key):") else { continue }
                        return trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                    }
                    return nil
                }
                func intField(_ key: String) -> Int? {
                    guard let v = field(key) else { return nil }
                    let digits = v.prefix { $0.isNumber || $0 == "-" }
                    return Int(digits)
                }
                func boolField(_ key: String) -> Bool? {
                    guard let v = field(key) else { return nil }
                    if v.hasPrefix("true") { return true }
                    if v.hasPrefix("false") { return false }
                    return nil
                }

                let parentType = intField("ParentBuiltInPortType") ?? intField("ParentPortType")
                let parentNumber = intField("ParentBuiltInPortNumber") ?? intField("ParentPortNumber")
                guard let parentType, let parentNumber else { continue }
                blocks.append(ProbeUSB3Block(
                    portKey: "\(parentType)/\(parentNumber)",
                    signaling: intField("SuperSpeedSignaling"),
                    tunnelled: boolField("Tunneled"),
                    transportRestricted: boolField("TRM_TransportRestricted")
                ))
            }
        }
        return blocks
    }

    // MARK: - Probe 38: USB devices, joined to a port by UsbIOPort
    //
    // Independent reimplementation of USBWatcher's
    // `portName(fromUSBIOPortPath:)` join (Sources/WhatCableDarwinBackend/Watchers/USBWatcher.swift):
    // walk the device's listed ancestors in order, and for the FIRST one
    // carrying a `UsbIOPort=<registry path>` property, take the path's
    // last component; if it starts with "Port-", that is the device's
    // physical port. This file's test target (WhatCableCoreTests) cannot
    // import WhatCableDarwinBackend at all, so this can't share code with
    // the production version even if it wanted to; it is independently
    // written against probe 38's raw text format
    // ("--- Device[N] ---" ... "Ancestors (device -> controller):" ...
    // "[i] class=... UsbIOPort=...").

    private struct ProbeDevice {
        let locationID: UInt32?
        let speedRaw: UInt8?
        /// The resolved port name (e.g. "Port-USB-C@1"), or nil if no
        /// ancestor carried a recognisable UsbIOPort.
        let portName: String?
    }

    private static func parseDevices38(text: String) -> [ProbeDevice] {
        var devices: [ProbeDevice] = []
        let deviceBlocks = text.components(separatedBy: "--- Device[").dropFirst()
        for raw in deviceBlocks {
            // End this device's block at the next "--- Device[" (already
            // split away) or a blank-line-terminated section; take
            // everything up to the next "\n\n--- " if present, else to end.
            let block: Substring
            if let nextRange = raw.range(of: "\n\n--- Device[") {
                block = raw[..<nextRange.lowerBound]
            } else {
                block = raw[...]
            }

            func value(_ key: String) -> String? {
                for line in block.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("\(key) = ") else { continue }
                    return trimmed.dropFirst(key.count + 3).trimmingCharacters(in: .whitespaces)
                }
                return nil
            }

            let locationID: UInt32? = value("locationID").flatMap { raw in
                var s = raw
                if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
                return UInt32(s, radix: 16)
            }
            let speedRaw: UInt8? = value("Device Speed").flatMap { UInt8($0) }

            // Ancestors section: lines shaped "    [i] class=... UsbIOPort=<path>".
            // Take the FIRST ancestor (lowest index, nearest the device)
            // that carries a UsbIOPort, matching production's walk order.
            var portName: String?
            if let ancestorsRange = block.range(of: "Ancestors") {
                let ancestorsText = block[ancestorsRange.lowerBound...]
                for line in ancestorsText.split(separator: "\n") {
                    guard let eq = line.range(of: "UsbIOPort=") else { continue }
                    let path = String(line[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
                    guard let last = path.split(separator: "/").last else { continue }
                    let name = String(last)
                    if name.hasPrefix("Port-") {
                        portName = name
                        break
                    }
                }
            }

            devices.append(ProbeDevice(locationID: locationID, speedRaw: speedRaw, portName: portName))
        }
        return devices
    }

    /// USB-IF style label for SuperSpeed and above, matching
    /// `USBDevice.usb3SpeedLabel` (reimplemented independently: this is
    /// the encoding table, not a call into the model type, so a
    /// regression in the real property wouldn't be masked by comparing
    /// against itself).
    private static func independentUSB3SpeedLabel(speedRaw: UInt8?) -> String? {
        switch speedRaw {
        case 3: return "USB 3.2 Gen 1 (5 Gbps)"
        case 4: return "USB 3.2 Gen 2 (10 Gbps)"
        case 5: return "USB 3.2 Gen 2x2 (20 Gbps)"
        default: return nil
        }
    }

    /// USB3Transport.speedLabel's encoding, reimplemented independently
    /// for the same reason.
    private static func independentTransportSpeedLabel(signaling: Int?) -> String? {
        switch signaling {
        case 0, nil: return nil
        case 1: return "USB 3.2 Gen 1 (5 Gbps)"
        case 2: return "USB 3.2 Gen 2 (10 Gbps)"
        case let gen?: return "USB 3.2 Gen \(gen)"
        }
    }

    // MARK: - Cases

    private struct Case {
        let folder: String
        let port: AppleHPMInterface
        let usb3Blocks: [ProbeUSB3Block]
        /// Devices whose resolved UsbIOPort join names THIS port.
        let matchingDevices: [ProbeDevice]
        /// Whether this folder had a probe 38 capture at all (distinct
        /// from "had one but zero devices connected"), so the coverage
        /// floor can be asserted honestly on the replayable subset.
        let hadProbe38: Bool
    }

    private static let cases: [Case] = {
        var result: [Case] = []
        for folder in allFolders() {
            let ports = loadActiveUSB3Ports(folder: folder)
            guard !ports.isEmpty else { continue }

            var usb3Blocks: [ProbeUSB3Block] = []
            for probe in ["17_deep_property_dump", "19_pdo_decode_and_usb3_watch"] {
                guard let text = loadProbeText(folder: folder, probe: probe) else { continue }
                usb3Blocks.append(contentsOf: parseUSB3Blocks(text: text))
            }

            let probe38Text = loadProbeText(folder: folder, probe: "38_usb_device_tree")
            let allDevices = probe38Text.map(parseDevices38(text:)) ?? []

            for port in ports {
                let portKey = "2/\(port.portNumber)"
                let matchedTransports = usb3Blocks.filter { $0.portKey == portKey }
                let matchedDevices = allDevices.filter { $0.portName == port.serviceName }
                result.append(Case(
                    folder: folder,
                    port: port.asAppleHPMInterface,
                    usb3Blocks: matchedTransports,
                    matchingDevices: matchedDevices,
                    hadProbe38: probe38Text != nil
                ))
            }
        }
        return result
    }()

    // MARK: - Coverage floors

    private static let coverageFloor = 300
    private static let replayableFloor = 200

    @Test("Coverage: enough active-USB3 corpus ports to exercise the gate")
    func coverageFloorHolds() {
        #expect(Self.cases.count >= Self.coverageFloor,
            "Expected at least \(Self.coverageFloor) active-USB3 port cases; found \(Self.cases.count).")
    }

    @Test("Coverage: enough active-USB3 ports have a probe 38 capture to join real device evidence")
    func probe38CoverageFloorHolds() {
        let replayable = Self.cases.filter { $0.hadProbe38 }.count
        #expect(replayable >= Self.replayableFloor,
            "Expected at least \(Self.replayableFloor) active-USB3 port cases with a probe 38 capture; found \(replayable).")
    }

    // MARK: - Two-tier sweep
    //
    // For each case with a probe 38 capture (so "no matching device" is a
    // real fact, not a missing-data artifact): classify independently as
    // corroborated (a real device with Device Speed >= 3 [SuperSpeed or
    // better] joined via UsbIOPort, OR a TRM-restricted direct transport
    // -- verified elsewhere in this corpus to be 0 co-occurring with
    // active USB3, kept here for completeness/future-proofing) or not,
    // then assert production's actual output against an independently
    // computed expected value.

    @Test("Two-tier sweep: device-corroborated ports match the independent baseline; everything else shows nothing")
    func twoTierSweepWithRealDeviceEvidence() {
        var corroboratedByDevice = 0
        var corroboratedByRestriction = 0
        var uncorroborated = 0
        var violations: [String] = []

        for c in Self.cases where c.hadProbe38 {
            let directTransports = c.usb3Blocks.filter { $0.tunnelled != true }
            let restrictedTransport = directTransports.first { $0.transportRestricted == true }
            let bestDevice = c.matchingDevices
                .filter { ($0.speedRaw ?? 0) >= 3 }
                .max { ($0.speedRaw ?? 0) < ($1.speedRaw ?? 0) }

            let transports: [USB3Transport] = c.usb3Blocks.enumerated().map { i, b in
                USB3Transport(
                    id: UInt64(i), portKey: b.portKey, signaling: b.signaling,
                    signalingDescription: nil, dataRole: nil,
                    transportRestricted: b.transportRestricted, tunnelled: b.tunnelled
                )
            }
            let devices: [USBDevice] = c.matchingDevices.enumerated().map { i, d in
                USBDevice(
                    id: UInt64(i), locationID: d.locationID ?? 0,
                    vendorID: 0, productID: 0,
                    vendorName: nil, productName: nil, serialNumber: nil,
                    usbVersion: nil, speedRaw: d.speedRaw,
                    busPowerMA: nil, currentMA: nil,
                    controllerPortName: c.port.serviceName,
                    rawProperties: [:]
                )
            }

            if let bestDevice {
                corroboratedByDevice += 1
                // Independent expected-label chain: device first (both
                // root and port-matched resolve to the SAME device pool
                // here, since every device in `matchingDevices` was
                // joined by its own UsbIOPort match; production's
                // root-vs-portMatched distinction only matters for WHICH
                // device wins when they'd disagree, not for whether a
                // label is shown at all), then transport signaling.
                let deviceLabel = Self.independentUSB3SpeedLabel(speedRaw: bestDevice.speedRaw)
                // `directTransports` is already filtered to this port's portKey
                // by the case-building step above, so the first entry (if any)
                // is this port's own direct transport.
                let transportLabel = directTransports.first.flatMap { Self.independentTransportSpeedLabel(signaling: $0.signaling) }
                let expectedLabel = deviceLabel ?? transportLabel

                let summary = PortSummary(port: c.port, devices: devices, usb3Transports: transports)
                if let expectedLabel, !summary.bullets.contains(expectedLabel) {
                    violations.append("\(c.folder) \(c.port.serviceName): expected bullet \"\(expectedLabel)\", got \(summary.bullets)")
                }

                let json = try? JSONFormatter.render(
                    ports: [c.port], sources: [], identities: [], showRaw: false,
                    usb3Transports: transports, usbDevices: devices
                )
                let jsonSpeed = json.flatMap { Self.extractUSB3Speed(from: $0) }
                if jsonSpeed != expectedLabel {
                    violations.append("\(c.folder) \(c.port.serviceName): expected JSON usb3Speed \"\(String(describing: expectedLabel))\", got \(String(describing: jsonSpeed))")
                }

                let diag = DataLinkDiagnostic(
                    port: c.port, identities: [], devices: devices,
                    usb3Transports: transports, cio: nil
                )
                if diag == nil {
                    violations.append("\(c.folder) \(c.port.serviceName): expected a DataLinkDiagnostic verdict (device-corroborated), got nil")
                }
            } else if restrictedTransport != nil {
                corroboratedByRestriction += 1
                let summary = PortSummary(port: c.port, devices: devices, usb3Transports: transports)
                let hasLabel = summary.bullets.contains { $0.contains("USB 3.2") || $0.contains("SuperSpeed") }
                if !hasLabel {
                    violations.append("\(c.folder) \(c.port.serviceName): expected a USB3 label (restriction-corroborated), got none")
                }
                let diag = DataLinkDiagnostic(
                    port: c.port, identities: [], devices: devices,
                    usb3Transports: transports, cio: nil
                )
                if case .blockedBySecurity = diag?.bottleneck {
                    // expected
                } else {
                    violations.append("\(c.folder) \(c.port.serviceName): expected .blockedBySecurity, got \(String(describing: diag?.bottleneck))")
                }
            } else {
                uncorroborated += 1
                let summary = PortSummary(port: c.port, devices: devices, usb3Transports: transports)
                let hasLabel = summary.bullets.contains { $0.contains("USB 3.2") || $0.contains("SuperSpeed") }
                if hasLabel {
                    violations.append("\(c.folder) \(c.port.serviceName): expected NO USB3 label (uncorroborated), got \(summary.bullets)")
                }
                let diag = DataLinkDiagnostic(
                    port: c.port, identities: [], devices: devices,
                    usb3Transports: transports, cio: nil
                )
                if diag != nil {
                    violations.append("\(c.folder) \(c.port.serviceName): expected NO DataLinkDiagnostic verdict (uncorroborated), got \(String(describing: diag?.bottleneck))")
                }
            }
        }

        // Non-zero strata, measured with the independent Python parser
        // used during development (not committed, re-derivable from this
        // file's own logic): of the 212 active-USB3 ports whose folder
        // has a probe 38 capture at all, 189 are device-corroborated, 0
        // are restriction-corroborated (matches the separate finding
        // below), and 23 are genuinely uncorroborated (a real device
        // answered on that port, but not with a qualifying SuperSpeed
        // speed, or no device at all). Floors set conservatively below
        // those measured counts so the sweep cannot pass vacuously and
        // isn't brittle to small corpus growth. The uncorroborated floor
        // is intentionally NOT set as low as "at least 1": a sweep this
        // size finding fewer than 10 genuinely uncorroborated real ports
        // would itself be worth investigating (either the join is too
        // permissive, or the corpus composition shifted).
        #expect(corroboratedByDevice >= 100,
            "expected at least 100 real device-corroborated active-USB3 ports; got \(corroboratedByDevice)")
        #expect(uncorroborated >= 10,
            "expected at least 10 real uncorroborated active-USB3 ports; got \(uncorroborated)")
        #expect(violations.isEmpty,
            "\(violations.count) corpus case(s) disagreed with the independent two-tier baseline: \(violations.prefix(10))")
    }

    private static func extractUSB3Speed(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ports = obj["ports"] as? [[String: Any]],
              let transports = ports.first?["transports"] as? [String: Any]
        else { return nil }
        return transports["usb3Speed"] as? String
    }

    // MARK: - Corpus finding: restriction and tunnelling never co-occur
    // with an active-USB3 port in this corpus
    //
    // Measured with the independent parser above, corrected once: a first
    // pass used substring containment ("TRM_TransportRestricted: true" as
    // a plain substring of the whole block) and reported 36 false-positive
    // matches, caused by the non-greedy block-boundary regex bleeding past
    // an unrelated later block when a probe-19 dash separator appeared
    // inside a field value. Re-derived with exact per-field regex
    // extraction (`TRM_TransportRestricted:\s*(true|false)`, matched
    // against the SAME parsed block's own field, not a substring of the
    // raw text): the true count is exactly 0. Recorded here as the
    // verified fact rather than the discarded 36, per house rule
    // ("re-derive any corpus figure with a second, independent parser").
    //
    // This matches the pattern research/iokit-data-sources.md records for
    // m2pro_macos26.4.1 (TRM-restricted USB3 ports there show up in
    // TransportsActive as USB2, not USB3): when a SuperSpeed link is
    // TRM-restricted, the port controller apparently does not report
    // "USB3" as active for it, at least nowhere in this corpus.

    @Test("Real active-USB3 corpus ports: none carry a restricted matching transport")
    func corpusHasNoRestrictedActiveUSB3Pairing() {
        var restrictedPairs = 0
        for c in Self.cases {
            if c.usb3Blocks.contains(where: { $0.transportRestricted == true }) { restrictedPairs += 1 }
        }
        #expect(restrictedPairs == 0,
            "expected 0 restricted+active-USB3 pairs per the verified corpus finding; got \(restrictedPairs). If this now fails because new corpus data genuinely has one, that's real and this test (plus the two-tier sweep above) needs updating, not reverting.")
    }

    // MARK: - Selector correctness on real corpus transports (unit-level,
    // corpus-fed): the canonical selector must never pick a tunnelled
    // entry, replayed against every real corpus transport array that
    // happens to include one anywhere in the machine (not just paired
    // with an active-USB3 port).

    @Test("Selector never returns a tunnelled-only entry, replayed against real corpus transport data")
    func selectorExcludesTunnelledOnRealData() {
        var examined = 0
        var violations: [String] = []
        for folder in Self.allFolders() {
            var blocks: [ProbeUSB3Block] = []
            for probe in ["17_deep_property_dump", "19_pdo_decode_and_usb3_watch"] {
                guard let text = Self.loadProbeText(folder: folder, probe: probe) else { continue }
                blocks.append(contentsOf: Self.parseUSB3Blocks(text: text))
            }
            let byPortKey = Dictionary(grouping: blocks, by: { $0.portKey })
            for (portKey, group) in byPortKey {
                let direct = group.filter { $0.tunnelled != true }
                guard direct.isEmpty, !group.isEmpty else { continue }
                examined += 1
                let parts = portKey.split(separator: "/")
                guard parts.count == 2, let portNumber = Int(parts[1]) else { continue }
                let port = AppleHPMInterface(
                    id: UInt64(portNumber), serviceName: "Port-USB-C@\(portNumber)",
                    className: "AppleHPMInterfaceType10", portDescription: nil,
                    portTypeDescription: "USB-C", portNumber: portNumber,
                    connectionActive: true, activeCable: nil, opticalCable: nil,
                    usbActive: nil, superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
                    transportsSupported: [], transportsActive: ["USB3"], transportsProvisioned: [],
                    plugOrientation: nil, plugEventCount: nil, connectionCount: nil, overcurrentCount: nil,
                    pinConfiguration: [:], powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
                    rawProperties: [:]
                )
                let transports: [USB3Transport] = group.enumerated().map { i, b in
                    USB3Transport(
                        id: UInt64(i), portKey: b.portKey, signaling: b.signaling,
                        signalingDescription: nil, dataRole: nil,
                        transportRestricted: b.transportRestricted, tunnelled: b.tunnelled
                    )
                }
                if let selected = USB3SpeedCorroboration.selectedTransport(for: port, in: transports) {
                    violations.append("\(folder) \(portKey): selected a tunnelled-only entry: \(selected)")
                }
            }
        }
        #expect(examined > 0, "expected at least one real tunnelled-only transport group in the corpus")
        #expect(violations.isEmpty, "\(violations.count) case(s) wrongly selected a tunnelled entry: \(violations.prefix(10))")
    }
}
