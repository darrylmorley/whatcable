import Foundation

/// A small reader for one format-1 run (`probes/test-kit/FORMAT.md`): the
/// registry snapshot's entries, IOService-plane links and class records, plus
/// the model from `run.json`.
///
/// WhatCableCoreTests has the full reader (`SnapshotCorpus`), but test
/// targets cannot import each other, and moving it to a shared target would
/// mean editing `Package.swift` and the public mirror's copy of it (issue #627
/// plan, Q3). So this reads only what the DarwinTests replays need, and turns
/// typed values into the Foundation types IOKit hands the watchers (NSNumber,
/// String, Data, arrays, dictionaries), so they can be fed to the same
/// per-key `read` closures production uses.
///
/// Links are parsed the way `SnapshotCorpus`'s `RegistrySnapshot` parses
/// them: a link without `plane`, `id` or `pos` is an error, so the two
/// readers accept and reject the same files.
///
/// Runs live under `research-data/runs/<run_id>/`, a link made by
/// `scripts/link-research.sh`. A fresh or public clone has no link, and
/// tests skip (`corpusPresent` is false), like every other corpus test.
struct FormatOneRun {
    enum LoadError: Error, CustomStringConvertible {
        case missingRun(String)
        case malformed(String)

        var description: String {
            switch self {
            case let .missingRun(id): return "run \(id) is not in research-data/runs"
            case let .malformed(what): return "malformed format-1 data: \(what)"
            }
        }
    }

    struct Entry {
        let id: UInt64
        let className: String?
        /// Properties as Foundation values. String keys only; values the
        /// probe withheld, skipped or could not read are left out.
        let properties: [String: Any]
    }

    struct Link {
        let plane: String
        let id: UInt64
        let parent: UInt64?
        let position: Int
        let name: String?
        let location: String?
    }

    /// Absolute path to `research-data/runs/`, from this file's compile-time
    /// path so it works from any working directory.
    static let runsRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support/
            .deletingLastPathComponent()   // WhatCableDarwinTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research-data/runs")
    }()

    /// True when the private data folder is linked. When false, corpus tests
    /// skip; when true, a missing run is a failure.
    static var corpusPresent: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: runsRoot.path, isDirectory: &isDir) && isDir.boolValue
    }

    let runID: String
    /// `hw.model` from `run.json`: `summary.model`, else the snapshot probe's
    /// own `model`.
    let model: String?
    let entries: [UInt64: Entry]
    /// IOService-plane links only, in file order.
    let serviceLinks: [Link]
    /// Class name -> superclasses, immediate superclass first.
    let superclasses: [String: [String]]

    init(runID: String) throws {
        self.runID = runID
        let dir = Self.runsRoot.appendingPathComponent(runID)
        guard FileManager.default.fileExists(atPath: dir.path) else { throw LoadError.missingRun(runID) }

        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("run.json"))) as? [String: Any]
        let summaryModel = (meta?["summary"] as? [String: Any])?["model"] as? String
        let probeModel = ((meta?["probes"] as? [String: Any])?["50_registry_snapshot"] as? [String: Any])?["model"] as? String
        model = summaryModel ?? probeModel

        let data = try Data(contentsOf: dir.appendingPathComponent("50_registry_snapshot.jsonl"))
        var entries: [UInt64: Entry] = [:]
        var links: [Link] = []
        var supers: [String: [String]] = [:]
        var sawHeader = false
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        for (index, line) in lines.enumerated() {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                // A cut-off final line is a truncated file, as in SnapshotCorpus.
                if index == lines.count - 1 { break }
                throw LoadError.malformed("line \(index + 1) is not JSON")
            }
            switch record["record"] as? String {
            case "header":
                guard record["format"] as? Int == 1 else { throw LoadError.malformed("not format 1") }
                sawHeader = true
            case "entry":
                guard let id = Self.entryID(record["id"]), let props = record["props"] else {
                    throw LoadError.malformed("entry without id or props")
                }
                entries[id] = Entry(
                    id: id,
                    className: record["class"] as? String,
                    properties: (Self.foundationValue(props) as? [String: Any]) ?? [:]
                )
            case "link":
                guard let plane = record["plane"] as? String, let id = Self.entryID(record["id"]),
                      let position = record["pos"] as? Int else {
                    throw LoadError.malformed("link without plane, id or pos")
                }
                if plane == "IOService" {
                    links.append(Link(
                        plane: plane, id: id, parent: Self.entryID(record["parent"]), position: position,
                        name: record["name"] as? String, location: record["location"] as? String
                    ))
                }
            case "class":
                if let name = record["name"] as? String { supers[name] = record["super"] as? [String] ?? [] }
            default:
                break
            }
        }
        guard sawHeader else { throw LoadError.malformed("no header") }
        self.entries = entries
        self.serviceLinks = links
        self.superclasses = supers
    }

    /// Whether `id`'s class is `className` or a subclass of it.
    func conforms(_ id: UInt64, to className: String) -> Bool {
        guard let cls = entries[id]?.className else { return false }
        return cls == className || (superclasses[cls] ?? []).contains(className)
    }

    /// The first IOService parent of `id`, as `IORegistryEntryGetParentEntry`
    /// returns it.
    func parent(of id: UInt64) -> UInt64? {
        serviceLinks.first { $0.id == id }?.parent
    }

    /// `id`'s IOService-plane name with its location, e.g. `Port-USB-A@2`,
    /// built the way `AppleHPMInterfaceWatcher.makePort` builds it.
    func serviceName(of id: UInt64) -> String? {
        guard let link = serviceLinks.first(where: { $0.id == id }), let name = link.name else { return nil }
        guard let location = link.location, !location.isEmpty else { return name }
        return "\(name)@\(location)"
    }

    /// `id`'s plain IOService-plane name (`IORegistryEntryGetName`).
    func plainName(of id: UInt64) -> String? {
        serviceLinks.first { $0.id == id }?.name
    }

    static func entryID(_ value: Any?) -> UInt64? {
        guard let text = value as? String, text.hasPrefix("0x") else { return nil }
        return UInt64(text.dropFirst(2), radix: 16)
    }

    /// A format-1 typed value as the Foundation value IOKit would have
    /// returned. Nil for withheld, skipped, failed and unreadable values.
    static func foundationValue(_ json: Any) -> Any? {
        guard let object = json as? [String: Any], let t = object["t"] as? String else { return nil }
        switch t {
        case "int":
            guard let text = object["hex"] as? String, let raw = UInt64(text, radix: 16) else { return nil }
            return NSNumber(value: raw)
        case "bool":
            return (object["v"] as? Bool).map { NSNumber(value: $0) }
        case "str":
            if let v = object["v"] as? String { return v }
            guard let hex = object["utf16"] as? String, let data = Data(formatOneHex: hex) else { return nil }
            return String(data: data, encoding: .utf16BigEndian)
        case "data":
            return (object["hex"] as? String).flatMap { Data(formatOneHex: $0) }
        case "array", "set":
            return (object["v"] as? [Any])?.compactMap(foundationValue)
        case "dict":
            guard let pairs = object["v"] as? [[Any]] else { return nil }
            var dict: [String: Any] = [:]
            for pair in pairs where pair.count == 2 {
                if let key = pair[0] as? String, let value = foundationValue(pair[1]) { dict[key] = value }
            }
            return dict
        default:
            return nil
        }
    }
}

private extension Data {
    init?(formatOneHex hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
