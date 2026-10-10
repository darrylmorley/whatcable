import Foundation
import Testing
@testable import WhatCableCore

/// Corpus guard for the front-port detection rewrite (issue #348).
///
/// The first cut of #348 classified a "built-in front port" device by matching
/// its parent hub against a fixed PID allow-list (`{0x800B, 0x800C}`). Sweeping
/// the customer-probe corpus showed that approach is wrong two ways, and that
/// finding is what justified replacing it with the structural gate in
/// `USBWatcher.controllerInfo` (reached-native-controller AND not-tunnelled AND
/// no-`UsbIOPort`-ancestor). This test pins the evidence so nobody reintroduces
/// a PID allow-list.
///
/// IMPORTANT: this does NOT validate the structural walk itself. The probes
/// dump each `IOUSBHostDevice` as a flat record with no parent chain, no
/// `UsbIOPort`, no host-controller class, and no physical-port label, so the
/// walk's three inputs (native controller, tunnelled, port name) are all
/// absent from the corpus. The walk is verified live on-device, not here. What
/// the corpus *does* carry is each device's identity (VID/PID/class) plus a
/// per-machine form factor, which is exactly what's needed to show a PID
/// allow-list cannot work.
///
/// Two corpus-backed assertions:
/// 1. **Too narrow.** Desktops exist whose internal Apple hub uses a PID
///    outside `{0x800B, 0x800C}` entirely (M1 / M2 / Studio families). The old
///    set would have rendered no front-port section for them.
/// 2. **Ambiguous.** Some Apple-VID hub PIDs appear on both desktops and
///    laptops, so no fixed PID set can classify internal-vs-external.
///
/// Reads `04_raw_registry_dump.json`, which is not committed (only
/// `01_walk_pd_tree.json` + distillations are). On a tree without the raw
/// probes (fresh clone, worktree) the sweep finds nothing and skips, matching
/// the other corpus sweeps. It runs for real in the local pre-push CI,
/// where the raw probes are present on disk.
@Suite("Internal-hub PID corpus sweep (issue #348)")
struct InternalHubPIDCorpusTests {

    /// The PID allow-list the first cut of #348 shipped with. The point of this
    /// test is that this set is not a workable classifier.
    private static let retiredPIDSet: Set<Int> = [0x800B, 0x800C]

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    /// folder name -> coarse form factor, read from the committed corpus.jsonl
    /// (`form_factor` is one of "laptop", "desktop", "iOS device",
    /// "unknown ...").
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

    private static func allFolders() -> [String] {
        guard let entries = try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path)
        else { return [] }
        return entries.filter { entry in
            var isDir: ObjCBool = false
            let path = probeRoot.appendingPathComponent(entry).path
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }

    /// The set of Apple-VID (0x05AC) USB-hub (`bDeviceClass` 9) product IDs
    /// enumerated in one machine's raw registry dump. Empty when the raw probe
    /// is absent or the machine has no Apple internal hub.
    private static func appleHubPIDs(folder: String) -> Set<Int> {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("04_raw_registry_dump.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = obj["output"] as? String
        else { return [] }

        var pids: Set<Int> = []
        // The dump is one flat block per device, headed by "IOUSBHostDevice[N]".
        let blocks = output.components(separatedBy: "IOUSBHostDevice[")
        for block in blocks.dropFirst() {
            guard let vid = intValue(block, key: "idVendor"), vid == 0x05AC,
                  let cls = intValue(block, key: "bDeviceClass"), cls == 9,
                  let pid = intValue(block, key: "idProduct")
            else { continue }
            pids.insert(pid)
        }
        return pids
    }

    /// Pulls the decimal integer from a `"key": 1452 (0x5ac)` line.
    private static func intValue(_ block: String, key: String) -> Int? {
        let marker = "\"\(key)\":"
        guard let range = block.range(of: marker) else { return nil }
        let after = block[range.upperBound...]
        let digits = after.drop { $0 == " " }.prefix { $0.isNumber }
        return Int(digits)
    }

    @Test("A fixed Apple-hub PID set is both too narrow and ambiguous (corpus)")
    func pidAllowListCannotClassify() {
        let folders = Self.allFolders()
        let ff = Self.formFactors()

        var hubPIDsByFolder: [String: (bucket: String, pids: Set<Int>)] = [:]
        for folder in folders {
            let pids = Self.appleHubPIDs(folder: folder)
            guard !pids.isEmpty else { continue }
            hubPIDsByFolder[folder] = (Self.bucket(forFormFactor: ff[folder]), pids)
        }

        // Skip on a tree without the raw probes (fresh clone / worktree), like
        // the other corpus sweeps. Nothing to assert there.
        guard !hubPIDsByFolder.isEmpty else { return }

        let desktops = hubPIDsByFolder.filter { $0.value.bucket == "desktop" }
        let laptops = hubPIDsByFolder.filter { $0.value.bucket == "laptop" }

        // Floor guard: keep the sweep from passing vacuously if the corpus is
        // only partially present. Most laptops have no internal hub at all (the
        // whole reason this feature is desktop-only), so the laptop floor is
        // low: only the few with an attached Apple hub / Studio Display appear,
        // and those are what source the ambiguity overlap below.
        #expect(desktops.count >= 20, "expected a meaningful desktop sample, got \(desktops.count)")
        #expect(laptops.count >= 5, "expected some laptops with an Apple hub, got \(laptops.count)")

        // 1. Too narrow: desktops whose Apple internal hub PIDs are entirely
        //    outside the retired set. The old code rendered no front-port
        //    section for these machines.
        let missedDesktops = desktops.filter {
            $0.value.pids.isDisjoint(with: Self.retiredPIDSet)
        }
        #expect(
            !missedDesktops.isEmpty,
            """
            Retired PID set \(Self.retiredPIDSet.map { String(format: "0x%04X", $0) }) \
            matched every desktop, so the 'too narrow' finding no longer holds. \
            Re-examine before trusting a PID allow-list.
            """
        )

        // 2. Ambiguous: at least one PID seen on both a desktop and a laptop, so
        //    a PID alone cannot say internal-vs-external.
        let desktopPIDs = desktops.values.reduce(into: Set<Int>()) { $0.formUnion($1.pids) }
        let laptopPIDs = laptops.values.reduce(into: Set<Int>()) { $0.formUnion($1.pids) }
        let ambiguous = desktopPIDs.intersection(laptopPIDs)
        #expect(
            !ambiguous.isEmpty,
            "No Apple-hub PID overlapped desktop and laptop, so the 'ambiguous' finding no longer holds."
        )

        print(
            "[InternalHubPIDCorpus] desktops=\(desktops.count) laptops=\(laptops.count) "
            + "missed-by-old-set=\(missedDesktops.count) "
            + "ambiguous-PIDs=\(ambiguous.sorted().map { String(format: "0x%04X", $0) })"
        )
    }
}
