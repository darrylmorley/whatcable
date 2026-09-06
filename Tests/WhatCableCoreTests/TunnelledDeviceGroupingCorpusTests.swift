import Foundation
import Testing
@testable import WhatCableCore

/// Corpus-replay sweep for `TunnelledDeviceGrouping.group`
/// (`Sources/WhatCableCore/Devices/TunnelledDeviceGrouping.swift`).
///
/// ## Honest limitation (read before extending this file)
///
/// `TunnelledDeviceGrouping.group` itself is pure: it only reads the
/// `isThunderboltTunnelled` / `isBehindInternalHub` booleans already stamped
/// onto each `USBDevice`. Those booleans are computed live, in
/// `USBWatcher.controllerInfo`, by walking the IOKit *service-plane* parent
/// chain of a running `IOUSBHostDevice` looking for a `UsbIOPort` ancestor, a
/// native (`AppleT*USBXHCI`) vs tunnelled (`AppleUSBXHCITR`) host controller
/// class, and a `USBPortType` on the nearest hub ancestor.
///
/// CORRECTION (2026-07-14): an earlier revision of this header claimed probe
/// 38 dumps flat records with "no parent chain, no controller class, no
/// UsbIOPort path". That was wrong: probe 38 has recorded the full ancestor
/// walk (class, locationID, USBPortType, UsbIOPort per hop) since it first
/// shipped (v1.1.6), and
/// `Tests/WhatCableDarwinTests/USBWatcherCorpusSweepTests.swift` now replays
/// those chains through the actual production classifier
/// (`USBWatcher.classifyAncestry`). That sweep is where the per-device flag
/// derivation is corpus-tested.
///
/// This file lives in Core and cannot import the Darwin backend, so it does
/// not touch the real flag derivation. It keeps an independent approximation
/// of `isBehindInternalHub` built from the device records alone: locationID
/// nesting. A desktop Mac's internal Apple hub enumerates in probe 38 as an
/// ordinary device (VID `0x05AC`, `bDeviceClass == 9`); everything nested
/// under it by `USBDevice.parentLocationID`'s hub-nibble walk (the exact
/// heuristic `USBDeviceNode.buildTree` already uses, proven against real
/// corpus topology by `Probe38TreeWalkTests`) is a device physically behind
/// that hub. That's a structural fact independent of how the real watcher
/// derives its flag, so it's a legitimate input to `group()`'s contract
/// (which only cares about the boolean, not its provenance) -- just not a
/// replay of `USBWatcher`'s own algorithm. Every place this matters is called
/// out below.
@Suite("TunnelledDeviceGrouping.group: corpus sweep")
struct TunnelledDeviceGroupingCorpusTests {

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // MARK: - Probe 38 parsing
    // Copied from Probe38TreeWalkTests.parse (same target) -- Swift `private`
    // is file-scoped, so this is a deliberate duplicate, not a shared helper.

    private static func parseProbe38(_ text: String) -> [USBDevice] {
        text.components(separatedBy: "--- Device[").dropFirst().compactMap { block in
            func value(_ key: String) -> String? {
                for line in block.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix(key),
                          trimmed.dropFirst(key.count).first == " " || trimmed.dropFirst(key.count).first == "=",
                          let eq = trimmed.firstIndex(of: "=")
                    else { continue }
                    return trimmed[trimmed.index(after: eq)...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                return nil
            }
            func hex(_ key: String) -> UInt64? {
                guard var raw = value(key) else { return nil }
                if raw.hasPrefix("0x") || raw.hasPrefix("0X") { raw = String(raw.dropFirst(2)) }
                return UInt64(raw, radix: 16)
            }
            guard let loc = hex("locationID").map({ UInt32(truncatingIfNeeded: $0) }) else { return nil }
            return USBDevice(
                id: UInt64(loc),
                locationID: loc,
                vendorID: hex("idVendor").map { UInt16(truncatingIfNeeded: $0) } ?? 0,
                productID: hex("idProduct").map { UInt16(truncatingIfNeeded: $0) } ?? 0,
                vendorName: value("USB Vendor Name"),
                productName: value("USB Product Name"),
                serialNumber: nil,
                usbVersion: nil,
                speedRaw: value("Device Speed").flatMap { UInt8($0) },
                busPowerMA: nil,
                currentMA: nil,
                deviceClass: value("bDeviceClass").flatMap { UInt8($0) },
                rawProperties: [:]
            )
        }
    }

    private static func loadProbe38(folder: String) -> String? {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent("38_usb_device_tree.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

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

    // MARK: - Form factor bucketing
    // Copied from InternalHubPIDCorpusTests (same target) -- reads the
    // committed corpus.jsonl `form_factor` field.

    private static func formFactors() -> [String: String] {
        let url = probeRoot.appendingPathComponent("corpus.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = obj["folder"] as? String,
                  let ff = obj["form_factor"] as? String
            else { continue }
            map[folder] = ff
        }
        return map
    }

    private static func bucket(forFormFactor ff: String?) -> String {
        guard let ff = ff?.lowercased() else { return "other" }
        if ff.contains("ios") { return "other" }
        if ff.contains("desktop") || ff.contains("mini") || ff.contains("studio")
            || ff.contains("mac pro") || ff.contains("imac") { return "desktop" }
        if ff.contains("laptop") || ff.contains("book") || ff.contains("air") { return "laptop" }
        return "other"
    }

    // MARK: - Apple internal-hub descendant marking (the approximation)

    /// Rebuilds `devices` with `isBehindInternalHub` set on every device
    /// structurally nested (via `USBDevice.parentLocationID`, the same
    /// heuristic `USBDeviceNode.buildTree` uses) under the first Apple
    /// internal-hub-shaped device (VID `0x05AC`, `bDeviceClass == 9`) found in
    /// the list. The hub device itself is never flagged (mirrors
    /// `TunnelledDeviceGrouping`'s own doc: "The Mac's own internal hub ...
    /// never a member of either set"). Returns `nil` when no such hub exists
    /// in this folder's devices.
    private static func markInternalHubDescendants(_ devices: [USBDevice]) -> (marked: [USBDevice], hubLocationID: UInt32, descendantLocationIDs: Set<UInt32>)? {
        guard let hub = devices.first(where: { $0.vendorID == 0x05AC && $0.deviceClass == 9 }) else {
            return nil
        }
        let byLocation = Dictionary(devices.map { ($0.locationID, $0) }, uniquingKeysWith: { first, _ in first })

        func isDescendant(_ locationID: UInt32) -> Bool {
            var current = locationID
            var hops = 0
            while hops < 20 {
                guard let parent = USBDevice.parentLocationID(current), byLocation[parent] != nil else { return false }
                if parent == hub.locationID { return true }
                current = parent
                hops += 1
            }
            return false
        }

        var descendantIDs: Set<UInt32> = []
        let marked: [USBDevice] = devices.map { device in
            guard device.locationID != hub.locationID, isDescendant(device.locationID) else { return device }
            descendantIDs.insert(device.locationID)
            return USBDevice(
                id: device.id,
                locationID: device.locationID,
                vendorID: device.vendorID,
                productID: device.productID,
                vendorName: device.vendorName,
                productName: device.productName,
                serialNumber: device.serialNumber,
                usbVersion: device.usbVersion,
                speedRaw: device.speedRaw,
                busPowerMA: device.busPowerMA,
                currentMA: device.currentMA,
                isBehindInternalHub: true,
                deviceClass: device.deviceClass,
                rawProperties: device.rawProperties
            )
        }
        guard !descendantIDs.isEmpty else { return nil }
        return (marked, hub.locationID, descendantIDs)
    }

    // MARK: - Desktop + Apple-hub-descendant cases

    private struct HubCase {
        let folder: String
        let devices: [USBDevice]
        let hubLocationID: UInt32
        let descendantLocationIDs: Set<UInt32>
    }

    private static let hubCases: [HubCase] = {
        let ff = formFactors()
        var result: [HubCase] = []
        for folder in allFolders() {
            guard bucket(forFormFactor: ff[folder]) == "desktop",
                  let text = loadProbe38(folder: folder)
            else { continue }
            let devices = parseProbe38(text)
            guard !devices.isEmpty, let marked = markInternalHubDescendants(devices) else { continue }
            result.append(HubCase(
                folder: folder,
                devices: marked.marked,
                hubLocationID: marked.hubLocationID,
                descendantLocationIDs: marked.descendantLocationIDs
            ))
        }
        return result
    }()

    // MARK: - All-folders no-crash sweep (unmarked, default flags)

    private static let allProbe38Folders: [(folder: String, devices: [USBDevice])] = {
        var result: [(String, [USBDevice])] = []
        for folder in allFolders() {
            guard let text = loadProbe38(folder: folder) else { continue }
            let devices = parseProbe38(text)
            guard !devices.isEmpty else { continue }
            result.append((folder, devices))
        }
        return result
    }()

    // MARK: - Coverage floors
    //
    // Measured directly against the corpus snapshot at the time this sweep
    // was written (410 folders; probe 38 is gitignored raw data, so only
    // folders where it happens to be on disk in this worktree count -- 30 of
    // them here):
    //   - 30 folders have a probe-38 capture on disk at all.
    //     Floor = 85% of 30, rounded down: 30 * 0.85 = 25.5 -> 25.
    //   - Of those, 2 are desktop-bucketed AND have an Apple internal-hub
    //     device (`markInternalHubDescendants` matches the FIRST such device
    //     in the folder's device list, mirroring `group()`'s own
    //     single-boundary model) with at least one structural descendant,
    //     covering 4 descendant devices in total. These are small numbers
    //     (desktop machines with something plugged into a front port are a
    //     minority of an already-small probe-38 sample), so the floors are
    //     set to the exact figures found rather than 85% of them: a single
    //     fresh probe re-fetch could plausibly swing a sample this size by
    //     more than 15% in either direction, and the point of this floor is
    //     "did the corpus shrink to nothing", not "did it grow monotonically".
    private static let allFoldersFloor = 25
    private static let hubCaseFolderFloor = 2
    private static let hubCaseDescendantFloor = 4

    // Two-tier reality: probe 38 is gitignored raw data, but it is NOT fully
    // absent on a fresh clone -- exactly one folder (`m3pro_macos26.5.1_h`,
    // the anchored fixture `Probe38TreeWalkTests` also relies on) carries a
    // committed probe-38 fixture, and it's a laptop with a Thunderbolt dock,
    // not a desktop with an Apple internal hub. A plain "is it empty" guard
    // would treat that one tracked folder as "raw data present" and then run
    // the full-corpus floors (25 folders, 2 hub-case folders) against just
    // it, failing every time. `fullRawCorpusThreshold` distinguishes "just
    // the one tracked fixture" from "the full raw corpus is present" (30
    // folders); it sits well above the former and well below the latter.
    private static let fullRawCorpusThreshold = 10

    /// True when at least one probe-38 fixture is on disk, tracked or not.
    /// Used to gate the no-crash sweep, which has no floor to satisfy and is
    /// worth running even against the single tracked fixture.
    private static func hasRawProbeFiles() -> Bool {
        !allProbe38Folders.isEmpty
    }

    /// True only when the full raw corpus (not just the one tracked fixture)
    /// is present. Used to gate every assertion that makes a claim about the
    /// FULL corpus -- the folder-count floors, and the hub-case invariants
    /// (which need a broad sample to have any chance of finding a desktop
    /// Apple-hub case at all) -- so they skip rather than fail when only the
    /// tracked fixture is available.
    private static func hasFullRawCorpus() -> Bool {
        allProbe38Folders.count >= fullRawCorpusThreshold
    }

    // MARK: - Tests

    @Test("Coverage: enough probe-38 captures on disk to exercise TunnelledDeviceGrouping at all")
    func probe38CoverageFloorHolds() {
        guard Self.hasFullRawCorpus() else { return }
        #expect(Self.allProbe38Folders.count >= Self.allFoldersFloor,
            "Expected at least \(Self.allFoldersFloor) folders with a probe-38 capture on disk; found \(Self.allProbe38Folders.count).")
    }

    @Test("Coverage: enough desktop Apple-internal-hub cases to exercise the internalHubDevices path")
    func hubCaseCoverageFloorHolds() {
        guard Self.hasFullRawCorpus() else { return }
        #expect(Self.hubCases.count >= Self.hubCaseFolderFloor,
            "Expected at least \(Self.hubCaseFolderFloor) desktop folders with Apple-hub descendants; found \(Self.hubCases.count).")
        let totalDescendants = Self.hubCases.reduce(0) { $0 + $1.descendantLocationIDs.count }
        #expect(totalDescendants >= Self.hubCaseDescendantFloor,
            "Expected at least \(Self.hubCaseDescendantFloor) total descendant devices; found \(totalDescendants).")
    }

    @Test("No crash: group() handles every real probe-38 device list, marked or not")
    func noCrashAcrossCorpus() {
        guard Self.hasRawProbeFiles() else { return }
        for (folder, devices) in Self.allProbe38Folders {
            for isDesktop in [true, false] {
                let result = TunnelledDeviceGrouping.group(
                    devices: devices, ports: [], thunderboltSwitches: [], isDesktopMac: isDesktop)
                // None of these devices are flagged tunnelled or
                // behind-internal-hub (default USBDevice flags are false), so
                // with no ports/switches supplied the result must be
                // structurally empty. A non-empty result here would mean
                // `group()` invented state from nothing.
                #expect(result.devices.isEmpty,
                    "\(folder) isDesktopMac=\(isDesktop): unflagged devices produced a non-empty tunnelled set")
                #expect(result.internalHubDevices.isEmpty,
                    "\(folder) isDesktopMac=\(isDesktop): unflagged devices produced a non-empty internal-hub set")
            }
        }
    }

    @Test("Invariant: every marked descendant appears in internalHubDevices exactly once, the hub itself never does")
    func internalHubDevicesMatchesMarkedDescendantsExactly() {
        // Gated on the specific data this test needs (hubCases non-empty),
        // NOT the raw-corpus-size threshold `hasFullRawCorpus()` uses: a
        // partial corpus that happens to include a qualifying desktop
        // Apple-hub case should still run this correctness check even when
        // it's below the full-corpus floor. `hubCaseCoverageFloorHolds`
        // above is the dedicated test that raises the alarm if the FULL
        // corpus stops producing hub cases; this one only needs "is there
        // anything to check" and skips silently (no Issue.record) otherwise,
        // so it can never misfire as a false failure on a fresh clone (the
        // one tracked probe-38 fixture, m3pro_macos26.5.1_h, is laptop-
        // bucketed, so it never enters hubCases in the first place) or any
        // other hub-case-less environment.
        guard !Self.hubCases.isEmpty else { return }
        for c in Self.hubCases {
            let result = TunnelledDeviceGrouping.group(
                devices: c.devices, ports: [], thunderboltSwitches: [], isDesktopMac: true)

            let resultLocationIDs = result.internalHubDevices.map(\.locationID)
            // No duplication: the result should contain each descendant once.
            #expect(Set(resultLocationIDs).count == resultLocationIDs.count,
                "\(c.folder): internalHubDevices contains a duplicate")
            // No loss / no invention: the result set must equal exactly the
            // descendants this test marked, nothing more, nothing less.
            #expect(Set(resultLocationIDs) == c.descendantLocationIDs,
                "\(c.folder): internalHubDevices \(Set(resultLocationIDs)) does not match the marked descendant set \(c.descendantLocationIDs)")
            // The internal hub's own boundary is never itself a member (its
            // own doc comment's invariant).
            #expect(!resultLocationIDs.contains(c.hubLocationID),
                "\(c.folder): the Apple internal hub device itself appeared in internalHubDevices")
        }
    }

    @Test("Invariant: isDesktopMac: false fails closed, even with real desktop-shaped flagged devices")
    func laptopGateFailsClosed() {
        // Same gating rationale as internalHubDevicesMatchesMarkedDescendantsExactly
        // above: this only needs hubCases to be non-empty, not the raw-corpus
        // floor, and skips silently (no Issue.record) when it's empty.
        guard !Self.hubCases.isEmpty else { return }
        for c in Self.hubCases {
            // Source: `let internalHub = isDesktopMac ? devices.filter { ... } : []`.
            // Same devices, same flags, only the gate flipped.
            let result = TunnelledDeviceGrouping.group(
                devices: c.devices, ports: [], thunderboltSwitches: [], isDesktopMac: false)
            #expect(result.internalHubDevices.isEmpty,
                "\(c.folder): isDesktopMac: false still produced \(result.internalHubDevices.count) internal-hub device(s)")
        }
    }
}
