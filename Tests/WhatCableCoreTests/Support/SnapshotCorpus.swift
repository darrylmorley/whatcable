import Foundation

/// Reader for format 1 probe output (`probes/test-kit/FORMAT.md`): the
/// registry snapshot (50) and the small probes (51 to 55).
///
/// Runs live under `research-data/runs/<run_id>/` in the repo root, a link
/// made by link-research.sh (private) to the local data folder that ingest
/// fills from KV (never in git). Each run folder holds `<probe>.jsonl` per
/// capture, `50_registry_snapshot_end.jsonl` for the end-of-run snapshot, and
/// `run.json`. A fresh clone has no link, so `allRuns()` is empty: tests that
/// sweep runs must report how many they read, so an empty sweep is visible.
public enum SnapshotCorpus {

    /// Absolute path to `research-data/runs/`, resolved from this file's
    /// compile-time path so it works regardless of working directory.
    public static let root: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support/
            .deletingLastPathComponent()   // WhatCableCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research-data/runs")
    }()

    /// Every run folder, sorted by name. Empty when the data folder is absent.
    public static func allRuns() -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.sorted().map { root.appendingPathComponent($0) }.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// One probe's output in one run, or nil when that file is absent.
    public static func load(run: URL, probe: String) throws -> FormatOneFile? {
        let url = run.appendingPathComponent("\(probe).jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try FormatOneFile(contentsOf: url)
    }

    /// The run's `hw.model` from `run.json`: `summary.model`, else the
    /// registry snapshot probe's own `model`. Nil when neither is present.
    public static func model(run: URL) -> String? {
        guard let data = try? Data(contentsOf: run.appendingPathComponent("run.json")),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let model = (meta["summary"] as? [String: Any])?["model"] as? String { return model }
        let probes = meta["probes"] as? [String: Any]
        return (probes?["50_registry_snapshot"] as? [String: Any])?["model"] as? String
    }
}

/// One format 1 file: header, records, footer.
public struct FormatOneFile {
    public enum LoadError: Error, Equatable {
        case notJSONLines(line: Int)
        case noHeader
        case unsupportedFormat(Int?)
    }

    public let header: [String: Any]
    /// Every line between the header and the footer, in order.
    public let records: [[String: Any]]
    /// Nil when the file was cut off (crash, kill, runner cap): never read
    /// such a file as complete.
    public let footer: [String: Any]?

    public var probe: String? { header["probe"] as? String }
    public var isComplete: Bool { footer?["status"] as? String == "complete" }

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    public init(data: Data) throws {
        var lines: [[String: Any]] = []
        let raw = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        for (index, line) in raw.enumerated() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                // A probe killed mid-write (the runners' watchdog) leaves its last
                // line half written: the file is cut off, and the lines before it
                // still read. Any earlier bad line is corruption.
                if index == raw.count - 1 { break }
                throw LoadError.notJSONLines(line: index + 1)
            }
            lines.append(object)
        }
        guard let first = lines.first, first["record"] as? String == "header" else { throw LoadError.noHeader }
        guard first["format"] as? Int == 1 else { throw LoadError.unsupportedFormat(first["format"] as? Int) }
        header = first
        if lines.count > 1, lines[lines.count - 1]["record"] as? String == "footer" {
            footer = lines[lines.count - 1]
            records = Array(lines[1..<(lines.count - 1)])
        } else {
            footer = nil
            records = Array(lines.dropFirst())
        }
    }

    /// Records of one type, in file order.
    public func records(_ type: String) -> [[String: Any]] {
        records.filter { $0["record"] as? String == type }
    }
}

/// A format 1 typed value. Integers keep their width and raw bits: whether a
/// field is signed is the reader's call, so ask for `unsigned` or `signed`.
public indirect enum TypedValue: Equatable {
    case int(bits: Int, raw: UInt64)
    case float(bits: Int, raw: UInt64)
    case string(String)
    /// A string UTF-8 cannot carry: its UTF-16 code units, big-endian.
    case utf16(Data)
    /// Bytes; `withheld` lists the ranges blanked for privacy (empty if none).
    case data(Data, withheld: [Range<Int>])
    case bool(Bool)
    case array([TypedValue])
    case set([TypedValue])
    /// Pairs in file order (sorted by key). A key is a string, or a typed value
    /// when it is not a CFString or was withheld.
    case dict([DictEntry])
    case date(raw: UInt64)
    case null
    case withheld
    case skipped
    case failed(what: String)
    case other(cfType: String?)

    public struct DictEntry: Equatable {
        public let key: Key
        public let value: TypedValue
    }

    public enum Key: Equatable {
        case string(String)
        case typed(TypedValue)
    }

    public enum DecodeError: Error, Equatable {
        case malformed(String)
    }

    /// The value as an unsigned integer of its own width.
    public var unsigned: UInt64? {
        if case let .int(_, raw) = self { return raw }
        return nil
    }

    /// The value as a signed integer: the top bit of its width is the sign.
    public var signed: Int64? {
        guard case let .int(bits, raw) = self else { return nil }
        if bits >= 64 { return Int64(bitPattern: raw) }
        let sign: UInt64 = 1 << UInt64(bits - 1)
        return raw & sign != 0 ? Int64(bitPattern: raw | ~((sign << 1) - 1)) : Int64(raw)
    }

    /// The value for a string key in a `.dict`, if present.
    public subscript(key: String) -> TypedValue? {
        guard case let .dict(entries) = self else { return nil }
        return entries.first { $0.key == .string(key) }?.value
    }

    public init(json: Any) throws {
        guard let object = json as? [String: Any], let t = object["t"] as? String else {
            throw DecodeError.malformed("not a typed value")
        }
        func hex(_ field: String) throws -> Data {
            guard let text = object[field] as? String, let data = Data(hexString: text) else {
                throw DecodeError.malformed("\(t) without valid \(field)")
            }
            return data
        }
        func bitsAndRaw() throws -> (Int, UInt64) {
            guard let bits = object["bits"] as? Int, let text = object["hex"] as? String,
                  let raw = UInt64(text, radix: 16), text.count * 4 == bits else {
                throw DecodeError.malformed("\(t) without matching bits and hex")
            }
            return (bits, raw)
        }
        switch t {
        case "int":
            let (bits, raw) = try bitsAndRaw()
            self = .int(bits: bits, raw: raw)
        case "float":
            let (bits, raw) = try bitsAndRaw()
            self = .float(bits: bits, raw: raw)
        case "str":
            if let v = object["v"] as? String {
                self = .string(v)
            } else {
                self = .utf16(try hex("utf16"))
            }
        case "data":
            let bytes = try hex("hex")
            guard object["len"] as? Int == bytes.count else { throw DecodeError.malformed("data len does not match hex") }
            let ranges = try (object["withheld"] as? [[Int]] ?? []).map { pair -> Range<Int> in
                guard pair.count == 2, pair[0] >= 0, pair[1] > 0, pair[0] + pair[1] <= bytes.count else {
                    throw DecodeError.malformed("withheld range out of bounds")
                }
                return pair[0]..<(pair[0] + pair[1])
            }
            self = .data(bytes, withheld: ranges)
        case "bool":
            guard let v = object["v"] as? Bool else { throw DecodeError.malformed("bool without v") }
            self = .bool(v)
        case "array", "set":
            guard let members = object["v"] as? [Any] else { throw DecodeError.malformed("\(t) without v") }
            let values = try members.map(TypedValue.init(json:))
            self = t == "array" ? .array(values) : .set(values)
        case "dict":
            guard let pairs = object["v"] as? [[Any]] else { throw DecodeError.malformed("dict without v") }
            self = .dict(try pairs.map { pair in
                guard pair.count == 2 else { throw DecodeError.malformed("dict pair is not two items") }
                let key: Key = try (pair[0] as? String).map { .string($0) } ?? .typed(TypedValue(json: pair[0]))
                return DictEntry(key: key, value: try TypedValue(json: pair[1]))
            })
        case "date":
            let (_, raw) = try bitsAndRaw()
            self = .date(raw: raw)
        case "null": self = .null
        case "withheld": self = .withheld
        case "skipped": self = .skipped
        case "failed": self = .failed(what: object["what"] as? String ?? "")
        case "other": self = .other(cfType: object["cf_type"] as? String)
        default: throw DecodeError.malformed("unknown type \(t)")
        }
    }
}

/// The registry snapshot's entries and links, by entry ID.
public struct RegistrySnapshot {
    public struct Entry {
        public let id: UInt64
        public let className: String?
        public let properties: TypedValue
    }

    public struct Link {
        public let plane: String
        public let id: UInt64
        public let parent: UInt64?
        public let position: Int
        public let name: String?
        public let location: String?
        public let path: String?
    }

    public let entries: [UInt64: Entry]
    public let links: [Link]

    public init(_ file: FormatOneFile) throws {
        guard file.probe == "50_registry_snapshot" else {
            throw TypedValue.DecodeError.malformed("not a registry snapshot: \(file.probe ?? "no probe")")
        }
        var entries: [UInt64: Entry] = [:]
        for record in file.records("entry") {
            guard let id = Self.entryID(record["id"]), let props = record["props"] else {
                throw TypedValue.DecodeError.malformed("entry without id or props")
            }
            entries[id] = Entry(id: id, className: record["class"] as? String, properties: try TypedValue(json: props))
        }
        self.entries = entries
        links = try file.records("link").map { record in
            guard let plane = record["plane"] as? String, let id = Self.entryID(record["id"]),
                  let position = record["pos"] as? Int else {
                throw TypedValue.DecodeError.malformed("link without plane, id or pos")
            }
            return Link(plane: plane, id: id, parent: Self.entryID(record["parent"]), position: position,
                        name: record["name"] as? String, location: record["location"] as? String,
                        path: record["path"] as? String)
        }
    }

    /// The entries whose class is exactly `className`.
    public func entries(ofClass className: String) -> [Entry] {
        entries.values.filter { $0.className == className }.sorted { $0.id < $1.id }
    }

    /// The children of `id` in `plane`, in registry order.
    public func children(of id: UInt64, in plane: String) -> [UInt64] {
        links.filter { $0.plane == plane && $0.parent == id }.sorted { $0.position < $1.position }.map(\.id)
    }

    /// The parents of `id` in `plane` (an entry can have more than one).
    public func parents(of id: UInt64, in plane: String) -> [UInt64] {
        links.filter { $0.plane == plane && $0.id == id }.compactMap(\.parent)
    }

    static func entryID(_ value: Any?) -> UInt64? {
        guard let text = value as? String, text.hasPrefix("0x") else { return nil }
        return UInt64(text.dropFirst(2), radix: 16)
    }
}

extension Data {
    /// Bytes from lowercase or uppercase hex, nil if the text is not hex.
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
