import Foundation
import Testing
@testable import WhatCableCore

/// Corpus guard for issue #10: no machine in the customer-probe
/// corpus should produce a `caution` or `notPerforming` verdict from its
/// real single-snapshot data.
///
/// The corpus is one-shot snapshots (not longitudinal sessions), so this
/// test pins the must-NOT-convict direction. The positive conviction path
/// (sustained belowClaim, high resistance, overcurrent) is covered by the
/// synthetic unit tests in SessionMonitorTests.
///
/// Two assertions per connected port:
/// 1. Single observation: a port seen once, even with a real overcurrent
///    baseline count, must stay `performing`.
/// 2. Stable session (10 identical observations): repeating the same
///    healthy snapshot 10 times must still stay `performing`. This rules
///    out any accidental accumulation path for consistently-neutral evidence.
@Suite("Session Monitor - corpus sweep")
struct SessionMonitorProbeSweepTests {

    // MARK: - Corpus root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // MARK: - Port data

    /// One IOAccessoryManager entry extracted from a probe's PD-tree walk,
    /// with the fields the session monitor and data-link diagnostic need.
    private struct ProbePort {
        let folder: String
        let serviceName: String
        let portTypeDescription: String?
        let portNumber: Int
        let transportsSupported: [String]
        let transportsActive: [String]
        let connectionActive: Bool
        let overcurrentCount: Int?

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
                overcurrentCount: overcurrentCount,
                pinConfiguration: [:],
                powerCurrentLimits: [],
                firmwareVersion: nil,
                bootFlagsHex: nil,
                rawProperties: [:]
            )
        }
    }

    // MARK: - Corpus helpers

    private static func allFolders() -> [String] {
        guard let entries = try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path)
        else { return [] }
        return entries.filter { entry in
            var isDir: ObjCBool = false
            let path = probeRoot.appendingPathComponent(entry).path
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        }.sorted()
    }

    /// Parse connected USB-C ports from a probe's 01_walk_pd_tree.json.
    /// Returns only ports where `ConnectionActive = true` and the port
    /// type is USB-C (not MagSafe, not HDMI).
    private static func connectedUSBCPorts(folder: String) -> [ProbePort] {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("01_walk_pd_tree.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return [] }

        // Split on IOAccessoryManager block headers, matching both
        // AppleHPMInterfaceType* (M3+) and AppleTCControllerType* (M1/M2).
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

            guard body.contains("PortTypeDescription"),
                  body.contains("ConnectionActive = true")
            else { continue }

            let portType = parseQuoted(body, key: "PortTypeDescription")
            // Only USB-C ports can produce a data-link signal.
            guard portType == "USB-C" else { continue }

            let serviceName = parseQuoted(body, key: "Description") ?? "Port-Unknown@0"
            let portNumber = parseInt(body, key: "PortNumber") ?? 0
            let supp = parseList(body, key: "TransportsSupported")
            let act = parseList(body, key: "TransportsActive")
            let oc = parseInt(body, key: "Overcurrent Count")

            ports.append(ProbePort(
                folder: folder,
                serviceName: serviceName,
                portTypeDescription: portType,
                portNumber: portNumber,
                transportsSupported: supp,
                transportsActive: act,
                connectionActive: true,
                overcurrentCount: oc
            ))
        }
        return ports
    }

    // MARK: - Field parsers

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

    // MARK: - Observation builder

    /// Build one session-monitor observation for a port from corpus data.
    /// No USB3 transports, no CIO, no TB switches are passed, so the
    /// DataLinkDiagnostic returns nil (no active speed to judge) and the
    /// delivery outcome is .notApplicable. The overcurrent baseline is the
    /// probe's real Overcurrent Count (0 on healthy machines).
    private static func observation(for port: ProbePort) -> SessionMonitor.Observation {
        let hpm = port.asAppleHPMInterface
        let diag = DataLinkDiagnostic(
            port: hpm,
            identities: [],
            devices: [],
            usb3Transports: [],
            cio: nil,
            thunderboltSwitches: []
        )
        let delivery = SessionMonitor.DataDelivery.from(
            diag?.bottleneck,
            hasCableSpeedClaim: diag?.facts.cableGbps != nil
        )
        // Use the service name as the fingerprint: consistent across all
        // observations for the same port in this test.
        return SessionMonitor.Observation(
            fingerprint: port.serviceName,
            dataDelivery: delivery,
            resistanceTier: nil,
            overcurrentCount: port.overcurrentCount
        )
    }

    // MARK: - Tests

    /// Every connected USB-C port in the customer-probe corpus must stay
    /// `performing` after one observation and after 10 identical observations.
    /// The trailing floor assertions guard against the sweep silently going vacuous.
    @Test("Corpus sweep: session monitor never convicts on single healthy snapshots")
    func corpusSweepNeverConvicts() {
        let folders = Self.allFolders()
        // No corpus on this clone (research/ is excluded from the public mirror).
        // Skip silently, matching the convention in sibling sweep tests.
        guard !folders.isEmpty else { return }

        var machineCount = 0
        var connectedPortCount = 0

        for folder in folders {
            let ports = Self.connectedUSBCPorts(folder: folder)
            guard !ports.isEmpty else { continue }
            machineCount += 1

            for port in ports {
                connectedPortCount += 1
                let obs = Self.observation(for: port)

                // 1. Single observation: must never convict.
                var singleShot = SessionMonitor()
                singleShot.record(obs)
                #expect(
                    singleShot.verdict == .performing,
                    "Folder \(folder): port \(port.serviceName) single-obs verdict is \(singleShot.verdict) (expected .performing)"
                )

                // 2. Stable session (10 identical observations): consistently
                //    neutral evidence must not accumulate into a conviction.
                var stable = SessionMonitor()
                for _ in 0..<10 {
                    stable.record(obs)
                }
                #expect(
                    stable.verdict == .performing,
                    "Folder \(folder): port \(port.serviceName) 10-obs stable verdict is \(stable.verdict) (expected .performing)"
                )
            }
        }

        print("[SessionMonitorProbeSweep] swept \(machineCount) machines, \(connectedPortCount) connected USB-C ports")

        #expect(
            machineCount >= 50,
            "Expected at least 50 machines with connected USB-C ports; found \(machineCount)"
        )
        #expect(
            connectedPortCount >= 50,
            "Expected at least 50 connected USB-C port observations; found \(connectedPortCount)"
        )
    }
}
