import Foundation
import Testing
@testable import WhatCableCore

/// Corpus-replay sweep for `ConnectionCounters.init(port:)` and the
/// `ConnectionDiagnostic` tiers built on it (DAR-230).
///
/// `research/corpus-test-coverage.md` lists `ConnectionCounters.init(port:)`
/// as REPLAYABLE from probe 01 with no covering suite. This is that suite.
///
/// It exists because the banner's copy was wrong for a reason the corpus can
/// see: the count it quoted was assumed to be one plug event per reconnect,
/// and it is not. Two things are pinned here so a future change has to argue
/// with real data rather than with a comment:
///
/// 1. **A port logs roughly two plug events per connection.** That is what
///    made a threshold of 2 fire on one ordinary unplug-and-replug, which is
///    how both reporters (discussions #434, #478) tripped it.
/// 2. **MagSafe ports do climb this counter**, so the connection-events tier
///    would fire there in normal use if it were not suppressed. A magnetic
///    connector detaching is not a fault, and that tier's advice ("a different
///    port or cable") cannot be followed on a captive cable.
///
/// Probe 01 is git-tracked for every corpus folder, so this runs on a fresh
/// clone with no re-fetch from KV.
@Suite("Connection counters - corpus sweep (DAR-230)")
struct ConnectionCountersProbeSweepTests {

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // MARK: - Parsed corpus port

    private struct ProbePort {
        let folder: String
        let serviceName: String
        let portTypeDescription: String
        let plugEventCount: Int?
        let connectionCount: Int?
        let overcurrentCount: Int?

        var isMagSafe: Bool { portTypeDescription.hasPrefix("MagSafe") }

        /// Only the fields `ConnectionCounters.init(port:)` reads are real;
        /// the rest are inert defaults. Keeping the real ones real is what
        /// makes this a replay of production code rather than a fixture test.
        var asAppleHPMInterface: AppleHPMInterface {
            AppleHPMInterface(
                id: 0,
                serviceName: serviceName,
                className: isMagSafe ? "AppleHPMInterfaceType11" : "AppleHPMInterfaceType10",
                portDescription: serviceName,
                portTypeDescription: portTypeDescription,
                portNumber: nil,
                connectionActive: nil,
                activeCable: nil,
                opticalCable: nil,
                usbActive: nil,
                superSpeedActive: nil,
                usbModeType: nil,
                usbConnectString: nil,
                transportsSupported: [],
                transportsActive: [],
                transportsProvisioned: [],
                plugOrientation: nil,
                plugEventCount: plugEventCount,
                connectionCount: connectionCount,
                overcurrentCount: overcurrentCount,
                pinConfiguration: [:],
                powerCurrentLimits: [],
                firmwareVersion: nil,
                bootFlagsHex: nil,
                rawProperties: [:]
            )
        }
    }

    // MARK: - Corpus loading

    /// Whether this clone has the probe corpus at all.
    ///
    /// `research/` is excluded from the public mirror (`.public-exclude`), so
    /// on that tree the directory is simply absent and every sweep here would
    /// otherwise fail its coverage floor rather than skip. Sibling sweeps take
    /// the same escape hatch (see `SessionMonitorProbeSweepTests`).
    ///
    /// Deliberately answered from the **filesystem**, not from `ports`. If the
    /// corpus is on disk but this file's parser stops matching, `ports` goes
    /// empty while this stays `true`, and the floors below fire. That is the
    /// whole point of the floors, and keying the skip off `ports.isEmpty`
    /// would hand a parser regression a free pass.
    private static let corpusAvailable: Bool = {
        guard let entries = try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path) else { return false }
        return entries.contains { folder in
            FileManager.default.fileExists(atPath: probeRoot
                .appendingPathComponent(folder)
                .appendingPathComponent("01_walk_pd_tree.json").path)
        }
    }()

    private static let ports: [ProbePort] = {
        guard let entries = try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path) else { return [] }
        var all: [ProbePort] = []
        for folder in entries.sorted() {
            all.append(contentsOf: parse(folder: folder))
        }
        return all
    }()

    /// Every real physical port block in one folder's probe 01 that publishes
    /// a `Plug Event Count`. Blocks are the probe's `=== ... ===` sections.
    private static func parse(folder: String) -> [ProbePort] {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("01_walk_pd_tree.json")
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return [] }

        var result: [ProbePort] = []
        for block in text.components(separatedBy: "\n=== ") {
            guard block.contains("Plug Event Count") else { continue }
            // `PortTypeDescription` and the `Parent...` variants both end in
            // the same suffix, so match on the exact indented key to avoid
            // reading a child node's copy of its parent's type.
            guard let type = quoted(block, key: "PortTypeDescription") else { continue }
            result.append(ProbePort(
                folder: folder,
                serviceName: quoted(block, key: "PortDescription") ?? "Port-Unknown@0",
                portTypeDescription: type,
                plugEventCount: int(block, key: "Plug Event Count"),
                connectionCount: int(block, key: "ConnectionCount"),
                overcurrentCount: int(block, key: "Overcurrent Count")
            ))
        }
        return result
    }

    private static func quoted(_ block: String, key: String) -> String? {
        let prefix = "    \(key) = \""
        for line in block.split(separator: "\n", omittingEmptySubsequences: false)
        where line.hasPrefix(prefix) {
            let after = line.dropFirst(prefix.count)
            guard let close = after.firstIndex(of: "\"") else { return nil }
            return String(after[..<close])
        }
        return nil
    }

    private static func int(_ block: String, key: String) -> Int? {
        let prefix = "    \(key) = "
        for line in block.split(separator: "\n", omittingEmptySubsequences: false)
        where line.hasPrefix(prefix) {
            return Int(line.dropFirst(prefix.count).prefix { $0.isNumber })
        }
        return nil
    }

    // MARK: - Coverage floor
    //
    // Measured against the corpus on 2026-07-28 by two independent parsers
    // (this one, and a standalone Python pass): 2510 port blocks across 731
    // machines publish a `Plug Event Count`. The 7 folders with none are Intel
    // Macs, which publish no port-controller data at all, as documented in
    // research/findings/chip-families.md. Floors are set below the measured values so ingesting new
    // submissions never turns this red, while a parser regression that drops
    // most rows still does.

    private static let portFloor = 2200
    private static let magSafeFloor = 450

    // MARK: - Tests

    @Test("Coverage: the corpus has enough real ports to exercise the counters")
    func coverageFloorHolds() {
        guard Self.corpusAvailable else { return }
        #expect(Self.ports.count >= Self.portFloor,
            "Expected at least \(Self.portFloor) port blocks publishing a plug-event count (2510 when this sweep was written); found \(Self.ports.count). A big drop means the parser stopped matching, not that the corpus shrank.")
    }

    @Test("No crash: every corpus port survives a ConnectionCounters round trip")
    func countersReadFromEveryPort() {
        guard Self.corpusAvailable else { return }
        var read = 0
        for port in Self.ports {
            let counters = ConnectionCounters(port: port.asAppleHPMInterface)
            // The factory must pass the values straight through, not
            // reinterpret them: a rise in these is what the banner acts on.
            #expect(counters.plugEvents == port.plugEventCount)
            #expect(counters.overcurrents == port.overcurrentCount)
            if counters.plugEvents != nil { read += 1 }
        }
        #expect(read >= Self.portFloor,
            "Only \(read) ports yielded a plug-event count; this sweep would be asserting on nothing")
    }

    @Test("A port logs about two plug events per connection, so the count is not a drop count")
    func plugEventsRunAtRoughlyTwicePerConnection() {
        guard Self.corpusAvailable else { return }
        // The load-bearing fact behind the threshold. If a future macOS starts
        // reporting one plug event per connection, this goes red and the bar
        // of 4 should be revisited, rather than quietly becoming too lax.
        let pairs = Self.ports.compactMap { port -> (Int, Int)? in
            guard let pe = port.plugEventCount, let cc = port.connectionCount else { return nil }
            return (pe, cc)
        }
        #expect(pairs.count >= Self.portFloor,
            "Only \(pairs.count) ports publish both counters; not enough to judge the relationship")
        // `#expect` records and carries on, so an empty `pairs` would reach the
        // division below and make `share` NaN, and `Int(NaN)` traps. That would
        // abort the whole run with a crash instead of the clean red the floor
        // above already gives. Stop here: the floor has said what is wrong.
        guard !pairs.isEmpty else { return }

        let nearDouble = pairs.filter { pe, cc in
            pe == 2 * cc || pe == 2 * cc + 1 || pe == 2 * cc - 1
        }
        let share = Double(nearDouble.count) / Double(pairs.count)
        #expect(share >= 0.80,
            "Only \(nearDouble.count) of \(pairs.count) ports (\(Int(share * 100))%) carry a plug-event count within one of twice their connection count; it was 89.5% when the threshold of 4 was chosen on that basis")
    }

    @Test("MagSafe ports do climb the plug-event counter")
    func magSafePortsCountPlugEvents() {
        guard Self.corpusAvailable else { return }
        // The standing evidence that suppressing the tier on MagSafe is
        // necessary rather than theoretical: if MagSafe never counted, the
        // tier could never fire there and the suppression would be dead code.
        let magSafe = Self.ports.filter(\.isMagSafe)
        #expect(magSafe.count >= Self.magSafeFloor,
            "Found \(magSafe.count) MagSafe ports; expected at least \(Self.magSafeFloor) (520 when written)")

        let zero = magSafe.filter { ($0.plugEventCount ?? 0) == 0 }
        #expect(zero.isEmpty,
            "\(zero.count) MagSafe ports report a zero plug-event count; when written, all 520 were non-zero")

        let atOrAboveBar = magSafe.filter { ($0.plugEventCount ?? 0) >= ConnectionDiagnostic.eventThreshold }
        #expect(!atOrAboveBar.isEmpty,
            "No MagSafe port in the corpus reaches the banner's bar, so the suppression this sweep defends would never be exercised in the field")
    }

    @Test("No corpus MagSafe port can produce the connection-events banner")
    func magSafeNeverShowsTheEventsBanner() {
        guard Self.corpusAvailable else { return }
        // Replays each MagSafe port's real lifetime count as though it were an
        // in-session rise, which is the worst case for this tier, and checks
        // the banner stays silent. The same deltas on USB-C must still fire,
        // or the suppression is hiding the tier rather than scoping it.
        var suppressed = 0
        var wouldHaveFired = 0
        for port in Self.ports where port.isMagSafe {
            guard let pe = port.plugEventCount, pe >= ConnectionDiagnostic.eventThreshold else { continue }
            let delta = SessionDelta(plugEvents: pe, overcurrents: 0)
            #expect(ConnectionDiagnostic(delta: delta, elapsedSeconds: 300, isMagSafe: true) == nil,
                "\(port.folder) \(port.serviceName): MagSafe produced a connection-events banner from \(pe) events")
            if ConnectionDiagnostic(delta: delta, elapsedSeconds: 300, isMagSafe: false) != nil {
                wouldHaveFired += 1
            }
            suppressed += 1
        }
        #expect(suppressed > 0, "No MagSafe port exercised the suppression path")
        #expect(wouldHaveFired == suppressed,
            "Every one of these \(suppressed) MagSafe ports should have fired the banner on a USB-C port; only \(wouldHaveFired) did, so this test is not proving the suppression is what silenced them")
    }
}
