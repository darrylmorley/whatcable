import Foundation
import Testing
@testable import WhatCableDarwinBackend
import WhatCableCore

// MARK: - HPMPortUUIDMapCorpusSweepTests
//
// Corpus-replay coverage for `HPMPortUUIDMap` (Reading/HPMPortUUIDMap.swift)
// over probe 35 (`35_hpm_port_uuid.json`), which had zero corpus coverage
// before this file (`WatcherCorpusSweepTests.swift` covers `.normalise` only).
//
// SEAM NOTE: `HPMPortUUIDMap.current()` is unreachable from a test -- it walks
// live `AppleHPMDeviceHALType3` IOKit services directly, with no `read`
// closure seam at all. `HPMPortUUIDMap.from(ports:)`, by contrast, is fully
// reachable: it takes a plain `[AppleHPMInterface]` array, and
// `AppleHPMInterface.from(...)` (the public factory already covered by
// `WatcherCorpusSweepTests.swift`'s HPM sweep) builds those from a `read`
// closure with no IOKit involved. This file drives `.from(ports:)` with
// `AppleHPMInterface` values built the same production way, fed from probe
// 35's ground-truth port/UUID pairs, so both the join (`.from`) and the
// normalisation (`.normalise`, exercised indirectly here too) run against
// real per-machine UUID sets.
//
// Probe 35 format (verified against the corpus, 2026-07). UUIDs below are
// SYNTHETIC placeholders: an earlier version of this comment pasted two REAL
// contributor UUIDs from the corpus straight into tracked test source, which is
// exactly the leak the privacy rule below exists to prevent (Codex review, #403).
//   [0] Port-USB-C@3        class=AppleHPMDeviceHALType3
//         UUID=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE  RID=2  Address=12
//         ConnectionUUID=11111111-2222-3333-4444-555555555555
//   [1] Port-MagSafe 3@1    class=AppleHPMDevice          <- M1/M2 base class
//         UUID=...
//   [2] (no port child)     class=AppleHPMDevice          <- controller, NOT a port
//
// PRIVACY: UUIDs are an internal join key only (see HPMPortUUIDMap's own
// doc comment and MEMORY.md "UUID/UID is private research data"). Assertion
// messages below only ever print an 8-char truncated prefix, never the full
// value, matching that rule even in local test failure output.
@Suite("HPMPortUUIDMap corpus sweep - port/UUID join (probe 35)")
struct HPMPortUUIDMapCorpusSweepTests {

    // MARK: - Probe root (duplicated across sweep files by house convention)

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private static func allProbeFolders() -> [String] {
        (try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path)
            .filter { entry in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(
                    atPath: probeRoot.appendingPathComponent(entry).path,
                    isDirectory: &isDir
                )
                return isDir.boolValue
            }
            .sorted()
        ) ?? []
    }

    // MARK: - Probe-35 parsing

    /// One `[N] Port-...@M  class=...` record plus its `UUID=` line.
    private struct Probe35Record {
        let label: String       // e.g. "Port-USB-C@3" or "Port-MagSafe 3@1"
        let portNumber: Int     // parsed decimal suffix after "@"
        let isMagSafe: Bool
        let controllerClass: String   // e.g. "AppleHPMDevice" (M1/M2) or "AppleHPMDeviceHALType3" (M3+)
        /// nil when the probe printed `UUID=(none)`. MUST stay optional: an
        /// earlier version dropped such records at parse time, which made the
        /// central "every port carries a UUID" claim UNFALSIFIABLE -- a port that
        /// lost its UUID would simply vanish from the sweep instead of failing it
        /// (Codex review, #403). Zero ports report (none) today; the point is that
        /// we would now find out if that changed.
        let uuid: String?

        /// True for the M1/M2 base class. This is the case that used to be
        /// invisible to this sweep, because `makeHPMInterface` hardcoded the
        /// M3+ subclass and threw the real `class=` away.
        var isPreM3BaseClass: Bool { controllerClass == "AppleHPMDevice" }
    }

    private static func parseProbe35(_ text: String) -> [Probe35Record] {
        var results: [Probe35Record] = []
        var pendingLabel: String?
        var pendingPortNumber: Int?
        var pendingIsMagSafe = false
        var pendingClass: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), let closeIdx = trimmed.firstIndex(of: "]") {
                let afterBracket = trimmed[trimmed.index(after: closeIdx)...].trimmingCharacters(in: .whitespaces)
                guard let classRange = afterBracket.range(of: "class=") else { continue }
                let label = String(afterBracket[..<classRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                // The controller class is the rest of the line after "class=".
                // Capture it: it is the whole point of the M1/M2 assertions below.
                let cls = String(afterBracket[classRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                    .prefix { !$0.isWhitespace }
                guard let atIdx = label.lastIndex(of: "@") else { continue }
                let numDigits = label[label.index(after: atIdx)...].prefix { $0.isNumber }
                guard let num = Int(numDigits) else { continue }
                pendingLabel = label
                pendingPortNumber = num
                pendingIsMagSafe = label.contains("MagSafe")
                pendingClass = String(cls)
            } else if trimmed.hasPrefix("UUID="),
                      let label = pendingLabel,
                      let num = pendingPortNumber,
                      let cls = pendingClass {
                let afterEq = trimmed.dropFirst("UUID=".count)
                let raw = String(afterEq.prefix { $0 != " " })
                guard !raw.isEmpty else { continue }
                // Record the ABSENCE rather than discarding the port, so a port
                // without a UUID fails the sweep instead of disappearing from it.
                let uuid: String? = (raw == "(none)") ? nil : raw
                results.append(Probe35Record(label: label, portNumber: num, isMagSafe: pendingIsMagSafe,
                                             controllerClass: cls, uuid: uuid))
                pendingLabel = nil
                pendingPortNumber = nil
                pendingClass = nil
            }
        }
        return results
    }

    private static func loadProbe35(folder: String) -> [Probe35Record] {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent("35_hpm_port_uuid.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return [] }
        return parseProbe35(text)
    }

    /// Truncate a UUID to 8 chars for assertion messages (privacy rule: never
    /// print a full HPM/Connection UUID, even in local test output).
    private static func shortUUID(_ uuid: String) -> String {
        String(uuid.prefix(8))
    }

    /// Build a real `AppleHPMInterface` via the production factory, the same
    /// way `AppleHPMInterfaceWatcher` would from live IOKit data, using the
    /// fields probe 35's ground truth gives us plus the minimum
    /// `AppleHPMInterface.from` needs to accept the record as a real port.
    private static func makeHPMInterface(from record: Probe35Record, entryID: UInt64) -> AppleHPMInterface? {
        let props: [String: Any] = [
            "PortTypeDescription": record.isMagSafe ? "MagSafe 3" : "USB-C",
            "PortNumber": NSNumber(value: record.portNumber),
            "PortType": NSNumber(value: record.isMagSafe ? 0x11 : 0x2),
        ]
        // `className` here is the PORT node's class, which is an
        // `AppleHPMInterface*` type on every generation. The CONTROLLER class
        // (record.controllerClass: AppleHPMDevice on M1/M2, AppleHPMDeviceHAL*
        // on M3+) is a separate upstream node and is what the ancestor-walk gate
        // keys on. An earlier version of this file passed the *controller* class
        // here, hardcoded to "AppleHPMDeviceHALType3", which both mislabelled the
        // port node and made every M1/M2 record look like an M3+ one -- so the
        // M1/M2 join was never actually exercised by this sweep.
        // Gate the UUID on the SHARED production predicate, applied to the real
        // controller class from probe 35. This is what makes the sweep exercise
        // the class gate rather than merely injecting a UUID it already read:
        // narrow `wcIsHPMControllerClass` and all 295 M1/M2 ports stop resolving.
        // (Codex review #403: previously `controllerClass` only selected records
        // and never controlled UUID acquisition, so the sweep proved only that
        // `from(ports:)` copies a supplied UUID into a dictionary.)
        let uuid = wcIsHPMControllerClass(record.controllerClass) ? record.uuid : nil
        return AppleHPMInterface.from(
            entryID: entryID,
            serviceName: record.label,
            className: "AppleHPMInterfaceType10",
            read: { props[$0] },
            hpmControllerUUID: uuid
        )
    }

    /// Ground-truth expected portKey from probe 35's own label, matching the
    /// format `AppleHPMInterface.portKey` produces: "17/N" for MagSafe (0x11
    /// decimal), "2/N" for USB-C (0x2 decimal).
    private static func expectedPortKey(_ record: Probe35Record) -> String {
        "\(record.isMagSafe ? 17 : 2)/\(record.portNumber)"
    }

    // MARK: - Corpus sweep

    @Test("Probe-35 sweep: every port record joins to a UUID with no collisions, portKey matches the probe's own label")
    func probe35SweepJoinAndPortKey() {
        var foldersScanned = 0
        var recordsTotal = 0
        var joinedTotal = 0
        var portKeyMismatches = 0
        var missingUUIDPorts = 0

        for folder in Self.allProbeFolders() {
            let records = Self.loadProbe35(folder: folder)
            guard !records.isEmpty else { continue }
            foldersScanned += 1
            recordsTotal += records.count

            // Build AppleHPMInterface ports the same way the watcher would,
            // one per probe-35 record, via the real public factory.
            let ports: [AppleHPMInterface] = records.enumerated().compactMap { index, record in
                Self.makeHPMInterface(from: record, entryID: UInt64(index + 1))
            }
            #expect(ports.count == records.count,
                "\(folder): AppleHPMInterface.from rejected \(records.count - ports.count) of \(records.count) probe-35 records")

            // Production join: HPMPortUUIDMap.from(ports:).
            let map = HPMPortUUIDMap.from(ports: ports)

            // Invariant 1: every port's UUID resolves to a portKey (UUID
            // present for every port record, per the task brief). A distinct
            // UUID per record is expected (each physical port has its own HPM
            // controller UUID), so map.count should equal the number of
            // distinct normalised UUIDs across this machine's records.
            // THE claim, now falsifiable: every port record must carry a UUID.
            // Previously a UUID-less port was dropped at parse time and this could
            // never fail.
            let missing = records.filter { $0.uuid == nil }
            #expect(missing.isEmpty,
                "\(folder): \(missing.count) port(s) report UUID=(none) -- 'every port carries a controller UUID' no longer holds")
            missingUUIDPorts += missing.count

            let distinctUUIDs = Set(records.compactMap { $0.uuid.map(HPMPortUUIDMap.normalise) })
            #expect(map.count == distinctUUIDs.count,
                "\(folder): map has \(map.count) entries but \(distinctUUIDs.count) distinct UUIDs were present")

            // Invariant 2: no collisions within a machine -- every record's
            // own (normalised) UUID must be a key in the map, and it must map
            // back to that record's own portKey.
            for record in records {
                guard let rawUUID = record.uuid else { continue }   // already asserted above
                let normalised = HPMPortUUIDMap.normalise(rawUUID)
                guard let resolvedKey = map[normalised] else {
                    Issue.record("\(folder): UUID \(Self.shortUUID(normalised))... from \(record.label) did not resolve in the map")
                    continue
                }
                joinedTotal += 1
                let expected = Self.expectedPortKey(record)
                if resolvedKey != expected { portKeyMismatches += 1 }
                #expect(resolvedKey == expected,
                    "\(folder): \(record.label) resolved to portKey \(resolvedKey), expected \(expected) (UUID \(Self.shortUUID(normalised))...)")
            }

            // Invariant 3: normalise() always yields exactly 32 lowercase hex
            // chars for a well-formed UUID (the format HPMPortUUIDMap.from
            // requires internally to accept an entry at all).
            for record in records {
                guard let rawUUID = record.uuid else { continue }
                let normalised = HPMPortUUIDMap.normalise(rawUUID)
                // NOTE: bind the comparison to a Bool BEFORE asserting. Swift
                // Testing auto-captures the operands of `#expect(a == b)` and
                // prints them on failure, so `#expect(normalised == normalised
                // .lowercased())` would dump a FULL real contributor UUID into
                // test output the moment normalise() regressed -- breaking this
                // file's own privacy guarantee (adversarial review, #403;
                // reproduced: it printed 704 full UUIDs). Capturing a Bool prints
                // only `false`. `count == 32` above is safe: it captures the Int.
                #expect(normalised.count == 32,
                    "\(folder): normalised UUID length \(normalised.count) != 32 for \(record.label)")
                let isLowercased = normalised == normalised.lowercased()
                #expect(isLowercased,
                    "\(folder): normalise() did not lowercase for \(record.label) (UUID \(Self.shortUUID(normalised))...)")
            }
        }

        print("[HPMPortUUIDMapSweep] \(foldersScanned) folders, \(recordsTotal) port records, "
            + "\(joinedTotal) joined, \(portKeyMismatches) portKey mismatches, "
            + "\(missingUUIDPorts) ports missing a UUID")

        // Correctness invariant: run whenever there is ANY probe-35 data at
        // all. A portKey mismatch is a real bug regardless of corpus size.
        if foldersScanned > 0 {
            #expect(portKeyMismatches == 0,
                "Expected zero portKey mismatches between HPMPortUUIDMap.from(ports:) and probe-35's own labels")
        }

        // Coverage floor: actual 206 folders, 704 PORT records as of 2026-07-13
        // (409 AppleHPMDeviceHALType3 + 295 AppleHPMDevice). Probe 35 also lists 50
        // `(no port child)` internal controllers, which are NOT ports and are
        // excluded by the parser. Floor at ~85% of actual (175 folders, 598 records).
        //
        // Two-tier reality: probe 35 has ZERO git-tracked files, so
        // `foldersScanned` is 0 on a fresh clone and the floor block below skips
        // entirely. The explicit 50 threshold is defensive consistency with the
        // other sweeps.
        if foldersScanned >= 50 {
            #expect(foldersScanned >= 175,
                "Expected at least 175 folders with probe-35 records; got \(foldersScanned)")
            #expect(recordsTotal >= 598,
                "Expected at least 598 probe-35 port records across the corpus; got \(recordsTotal)")
        }
    }

    // MARK: - The M1/M2 claim, against real hardware data
    //
    // This is the assertion that the old version of this sweep could not make,
    // because `makeHPMInterface` hardcoded the M3+ controller class and threw
    // probe 35's real `class=` away. The claim "M1/M2 machines carry a controller
    // UUID and it flows through the production join" was asserted in prose, got
    // reversed twice, and was never executable. Now it is.
    @Test("M1/M2 (AppleHPMDevice) ports carry a UUID and join through the production map")
    func preM3BaseClassPortsCarryUUIDAndJoin() {
        var preM3Ports = 0
        var m3PlusPorts = 0
        var preM3MachinesJoined = 0
        var preM3MachinesSeen = 0
        var classesSeen: Set<String> = []

        for folder in Self.allProbeFolders() {
            let records = Self.loadProbe35(folder: folder)
            guard !records.isEmpty else { continue }
            for r in records { classesSeen.insert(r.controllerClass) }

            let preM3 = records.filter { $0.isPreM3BaseClass }
            preM3Ports += preM3.count
            m3PlusPorts += records.count - preM3.count
            guard !preM3.isEmpty else { continue }
            preM3MachinesSeen += 1

            // Drive the PRODUCTION join with this M1/M2 machine's real ports.
            let ports: [AppleHPMInterface] = preM3.enumerated().compactMap { i, r in
                Self.makeHPMInterface(from: r, entryID: UInt64(i + 1))
            }
            let map = HPMPortUUIDMap.from(ports: ports)

            // The load-bearing assertion. An empty map here means every M1/M2
            // machine silently drops out of the port/power join.
            #expect(!map.isEmpty,
                "\(folder): M1/M2 (AppleHPMDevice) ports produced an EMPTY join map -- M1/M2 would be silently dropped")
            #expect(map.count == Set(preM3.compactMap { $0.uuid.map(HPMPortUUIDMap.normalise) }).count,
                "\(folder): M1/M2 join map lost entries (collision or rejected UUID)")
            if !map.isEmpty { preM3MachinesJoined += 1 }
        }

        print("[HPMPortUUIDMapSweep/M1M2] classes=\(classesSeen.sorted()) "
            + "preM3Ports=\(preM3Ports) m3PlusPorts=\(m3PlusPorts) "
            + "preM3MachinesJoined=\(preM3MachinesJoined)/\(preM3MachinesSeen)")

        // Non-vacuity: this test is worthless if the corpus happens to contain no
        // M1/M2 machines -- it would pass by iterating over nothing. Only assert
        // when probe-35 data is actually present (skips on a fresh clone, where
        // probe 35 is entirely untracked).
        if preM3Ports + m3PlusPorts > 0 {
            #expect(preM3Ports > 0,
                "No AppleHPMDevice (M1/M2) ports found in probe 35: either the corpus lost its M1/M2 machines or the class parse broke, and either way this test no longer proves the M1/M2 claim (corpus as of 2026-07-13: 295 AppleHPMDevice ports across 91 machines)")
            #expect(preM3MachinesJoined == preM3MachinesSeen,
                "\(preM3MachinesSeen - preM3MachinesJoined) M1/M2 machines failed to produce a join map")
        }
    }

    // MARK: - MagSafe / USB-C same-@N collision fixture
    //
    // research/issue-195-investigation.md covers this: the `@N` socket suffix on a power-only
    // (MagSafe) port can collide with the first USB-C port on the same HPM
    // controller (issue #195). HPMPortUUIDMap must keep them apart because
    // MagSafe and USB-C use different rawType prefixes (17 vs 2) even when N
    // is identical. Restated here as a fixture because it is easy for a
    // future edit to `expectedPortKey`'s reasoning (or the production
    // `portKey` computed property it mirrors) to silently collapse this case,
    // and the real corpus may not always have a same-@N MagSafe/USB-C pair on
    // disk to catch it via the sweep alone.
    @Test("Fixture: MagSafe@1 and USB-C@1 on the same machine keep distinct portKeys")
    func fixtureMagSafeAndUSBCSameNumberDoNotCollide() {
        // Deliberately the M1/M2 base class: the #195 collision must be kept
        // apart on every generation, not just M3+.
        let usbC = Probe35Record(label: "Port-USB-C@1", portNumber: 1, isMagSafe: false,
                                  controllerClass: "AppleHPMDevice",
                                  uuid: "11111111-1111-1111-1111-111111111111")
        let magSafe = Probe35Record(label: "Port-MagSafe 3@1", portNumber: 1, isMagSafe: true,
                                     controllerClass: "AppleHPMDevice",
                                     uuid: "22222222-2222-2222-2222-222222222222")
        let ports = [usbC, magSafe].enumerated().compactMap { i, r in
            Self.makeHPMInterface(from: r, entryID: UInt64(i + 1))
        }
        #expect(ports.count == 2)
        let map = HPMPortUUIDMap.from(ports: ports)
        #expect(map.count == 2)
        #expect(map[HPMPortUUIDMap.normalise(usbC.uuid!)] == "2/1")
        #expect(map[HPMPortUUIDMap.normalise(magSafe.uuid!)] == "17/1")
    }

    @Test("Fixture: a port with no hpmControllerUUID is excluded from the map, not crashed on")
    func fixturePortWithoutUUIDIsExcluded() {
        let props: [String: Any] = [
            "PortTypeDescription": "USB-C",
            "PortNumber": NSNumber(value: 2),
            "PortType": NSNumber(value: 0x2),
        ]
        let port = AppleHPMInterface.from(
            entryID: 1, serviceName: "Port-USB-C@2", className: "AppleHPMInterfaceType10",
            read: { props[$0] }, hpmControllerUUID: nil
        )
        #expect(port != nil)
        let map = HPMPortUUIDMap.from(ports: [port!])
        #expect(map.isEmpty, "a port with no UUID must not appear in the join map")
    }
}
