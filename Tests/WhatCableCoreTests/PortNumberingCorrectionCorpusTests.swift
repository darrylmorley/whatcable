import Foundation
import Testing
@testable import WhatCableCore

// Public issue #627, plan §4 T4 and T5, over the format-1 runs in
// research-data/runs. Skips when research-data is not linked (public and
// fresh clones), like SnapshotCorpusTests. When it is linked, a missing run,
// a wrong model or a run with no model is a failure.

private let mac17_14Runs = [
    "397cf7be-d888-4b06-b64d-d5adac29f7ba",
    "305e3a4f-8992-487e-8d8e-2124b87c2b89",
]

private let swappedSockets: Set<[Int]> = [[2, 6], [3, 2]]
private let swappedNames = ["Port-USB-C@6", "Port-USB-A@2"]

/// The (type, number) pairs a registry entry names a port by.
private let portKeyPairs = [
    ("PortType", "PortNumber"),
    ("ParentPortType", "ParentPortNumber"),
    ("ParentBuiltInPortType", "ParentBuiltInPortNumber"),
]

/// Whether `text` names one of the two sockets: the name, not followed by
/// another digit.
private func namesSwappedSocket(_ text: String) -> Bool {
    swappedNames.contains { name in
        var search = text[...]
        while let range = search.range(of: name) {
            if range.upperBound == search.endIndex || !search[range.upperBound].isNumber { return true }
            search = search[range.upperBound...]
        }
        return false
    }
}

/// Every string in a typed value, recursively.
private func strings(in value: TypedValue) -> [String] {
    switch value {
    case let .string(s): return [s]
    case let .array(items), let .set(items): return items.flatMap(strings(in:))
    case let .dict(entries): return entries.flatMap { strings(in: $0.value) }
    default: return []
    }
}

/// A typed value as the Foundation value IOKit would return, for feeding a
/// per-key read.
private func foundation(_ value: TypedValue) -> Any? {
    switch value {
    case let .int(_, raw): return NSNumber(value: raw)
    case let .bool(b): return NSNumber(value: b)
    case let .string(s): return s
    case let .data(d, _): return d
    case let .array(items), let .set(items): return items.compactMap(foundation)
    case let .dict(entries):
        var out: [String: Any] = [:]
        for entry in entries {
            if case let .string(key) = entry.key, let v = foundation(entry.value) { out[key] = v }
        }
        return out
    default: return nil
    }
}

private func properties(_ value: TypedValue) -> [String: Any] {
    (foundation(value) as? [String: Any]) ?? [:]
}

private func names(_ props: [String: Any]) -> Bool {
    for (typeKey, numberKey) in portKeyPairs {
        if let t = (props[typeKey] as? NSNumber)?.intValue, let n = (props[numberKey] as? NSNumber)?.intValue,
           swappedSockets.contains([t, n]) { return true }
    }
    return false
}

private func corpusLinked() -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: SnapshotCorpus.root.path, isDirectory: &isDir) && isDir.boolValue
}

@Suite("Mac17,14 swapped sockets: corpus checks (issue #627)")
struct PortNumberingCorrectionCorpusTests {

    /// T4: on Mac17,14 every entry that names C@6 or A@2 is one of the kinds
    /// the fix corrects. A new kind would mean a reader the fix does not
    /// cover.
    @Test("T4: only the corrected entry kinds name these sockets on Mac17,14", arguments: mac17_14Runs)
    func surfaceCheck(runID: String) throws {
        guard corpusLinked() else { return }
        let run = SnapshotCorpus.root.appendingPathComponent(runID)
        #expect(SnapshotCorpus.model(run: run) == "Mac17,14", "\(runID)")
        let file = try #require(try SnapshotCorpus.load(run: run, probe: "50_registry_snapshot"), "\(runID) has no snapshot")
        let snapshot = try RegistrySnapshot(file)
        var superclasses: [String: [String]] = [:]
        for record in file.records("class") {
            if let name = record["name"] as? String { superclasses[name] = record["super"] as? [String] ?? [] }
        }
        func isUSBDevice(_ cls: String) -> Bool {
            cls == "IOUSBHostDevice" || (superclasses[cls] ?? []).contains("IOUSBHostDevice")
        }

        let allowed: Set<String> = [
            "IOPort", "IOPortTransportStateUSB2", "IOPortTransportStateUSB3",
            "AppleUSB20HubPort", "AppleUSB30HubPort",
        ]
        var byClass: [String: Int] = [:]
        for entry in snapshot.entries.values {
            let props = properties(entry.properties)
            guard names(props) || strings(in: entry.properties).contains(where: namesSwappedSocket) else { continue }
            let cls = entry.className ?? "nil"
            byClass[cls, default: 0] += 1
            #expect(allowed.contains(cls) || isUSBDevice(cls),
                    "\(runID): \(cls) entry 0x\(String(entry.id, radix: 16)) names a swapped socket")
        }
        // One of each kind per socket: proves the scan found the entries.
        for cls in allowed {
            #expect(byClass[cls] == 2, "\(runID): \(cls) x\(byClass[cls] ?? 0)")
        }
    }

    /// T5: on every other model the correction is a no-op for every port
    /// node, transport node and `UsbIOPort` path.
    @Test("T5: no other model's port names, codes or reads change")
    func noOpSweep() throws {
        guard corpusLinked() else { return }
        let runs = SnapshotCorpus.allRuns()
        #expect(!runs.isEmpty, "research-data/runs is linked but empty")
        var otherModelRuns = 0
        var runsNamingSockets: [String: Int] = [:]
        var checkedEntries = 0
        let keys = portKeyPairs.flatMap { [$0.0, $0.1] } + [
            "PortTypeDescription", "PortDescription", "Description",
            "ParentPortTypeDescription", "ParentBuiltInPortTypeDescription", "TransportDescription",
        ]
        // Only lines that can name a port are parsed: the full parse of every
        // snapshot is SnapshotCorpusTests' job and takes over a minute.
        let needles = [Data(#"PortType""#.utf8), Data(#""UsbIOPort""#.utf8)]

        for run in runs {
            let url = run.appendingPathComponent("50_registry_snapshot.jsonl")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let model = SnapshotCorpus.model(run: run)
            let name = run.lastPathComponent
            try #require(model != nil, "\(name) has a snapshot but no model")
            guard let model, model != "Mac17,14" else { continue }
            otherModelRuns += 1

            var namesSockets = false
            let data = try Data(contentsOf: url)
            for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                let lineData = Data(line)
                guard needles.contains(where: { lineData.range(of: $0) != nil }),
                      let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      record["record"] as? String == "entry",
                      let rawProps = record["props"],
                      let typed = try? TypedValue(json: rawProps) else { continue }
                let props = properties(typed)
                checkedEntries += 1
                if names(props) { namesSockets = true }

                if let t = (props["PortType"] as? NSNumber)?.intValue, let n = (props["PortNumber"] as? NSNumber)?.intValue {
                    let out = PortNumberingCorrection.corrected(type: t, number: n, model: model)
                    #expect(out.type == t && out.number == n, "\(name) \(model): \(t)/\(n)")
                }
                for key in keys where props[key] != nil {
                    let out = PortNumberingCorrection.correctingRead({ props[$0] }, model: model) { read in read(key) }
                    #expect((out as? NSObject)?.isEqual(props[key]) == true, "\(name) \(model): \(key)")
                }
                for key in ["PortDescription", "Description"] {
                    guard let value = props[key] as? String else { continue }
                    if namesSwappedSocket(value) { namesSockets = true }
                    #expect(PortNumberingCorrection.corrected(portNodeName: value, model: model) == value, "\(name): \(value)")
                }
                let path = (props["UsbIOPort"] as? String)
                    ?? (props["UsbIOPort"] as? Data).flatMap { String(data: $0, encoding: .utf8) }
                if let path, let last = path.split(separator: "/").last.map(String.init) {
                    if namesSwappedSocket(last) { namesSockets = true }
                    #expect(PortNumberingCorrection.corrected(portNodeName: last, model: model) == last, "\(name): \(last)")
                }
            }
            if namesSockets { runsNamingSockets[model, default: 0] += 1 }
        }

        #expect(otherModelRuns > 0, "no non-Mac17,14 run with a snapshot: checked nothing")
        #expect(checkedEntries > 0)
        // Today: Mac16,9 x5, Mac16,10 x9. These are the models most at risk
        // of a careless table change, so the sweep must actually cover them.
        let total = runsNamingSockets.values.reduce(0, +)
        #expect(total >= 14, "only \(total) other-model runs name C@6 or A@2: \(runsNamingSockets)")
    }

    /// Both Mac17,14 runs must be present when the corpus is linked.
    @Test("The two Mac17,14 runs are present and have the right model", arguments: mac17_14Runs)
    func runsPresent(runID: String) {
        guard corpusLinked() else { return }
        let run = SnapshotCorpus.root.appendingPathComponent(runID)
        #expect(FileManager.default.fileExists(atPath: run.appendingPathComponent("50_registry_snapshot.jsonl").path), "\(runID)")
        #expect(SnapshotCorpus.model(run: run) == "Mac17,14", "\(runID)")
    }
}
