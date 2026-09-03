import Foundation
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

// MARK: - Shared corpus probe readers for the power slice
//
// Every existing sweep file in this target carries its own private copy of the
// probe-root lookup and its own probe parsers, "duplicated by house
// convention". That convention is the thing the power-slice refactor exists to
// stop, so new power sweeps share these instead. The older files are not
// touched here: rewriting five working sweeps is not what this phase is for,
// and doing it in the same PR would bury the change under churn.
//
// BEFORE WRITING A NEW PROBE PARSER, read `research/corpus-parser-traps.md`.
// It records the ways this corpus has silently fooled a careful parser, all of
// them generic to the corpus rather than specific to one feature, and all of
// them producing a clean plausible result while dropping exactly the rows the
// question was about. The four that bit whatcable-app PR #599, in short:
//
//  - probe 32 prints `PortControllerInfo` TWICE (once under its own section,
//    again under `=== AppleACAdapter / ChargerData ===`), so a flat scan
//    double-counts every port block. Exactly twice, in all 926 untruncated
//    folders carrying it.
//  - a PDO's type is bits 31:30, and both non-fixed classes set bit 31, so
//    every augmented and every variable PDO prints as a NEGATIVE signed
//    decimal. A `(\d+)` pattern drops all of them and reports zero.
//  - `PortControllerNPDOs` is not the array length: augmented PDOs sit AFTER
//    that count, so truncating to it reproduces a false "zero augmented".
//  - supply labels are multi-word and can carry a range (`SPR PPS
//    5000-11000mV`), so a single-word-label pattern drops the PPS rows.
//
// The general rule behind all four: make a new parser find something you
// already know is there before you trust what it reports, and prefer a
// structural claim over a total.
//
// Nothing in here re-implements production logic. Each parser turns raw probe
// text into the same shape IOKit hands the real code, then calls the real
// production factory. Where a value could be derived two ways (an SMC float,
// for instance) the parser uses the production decoder and the tests
// cross-check it against the probe's own independently-printed decode.
enum CorpusPowerProbes {

    // MARK: - Files

    static let root: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    static func folders() -> [String] {
        (try? FileManager.default
            .contentsOfDirectory(atPath: root.path)
            .filter { entry in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(entry).path,
                    isDirectory: &isDir
                )
                return isDir.boolValue
            }
            .sorted()
        ) ?? []
    }

    /// The `output` string of one probe, or nil when the folder does not carry
    /// that probe.
    ///
    /// Returns nil for a file truncated at the 64 KB pipe cap as well. Probe 17
    /// and probe 32 both hit that cap on real machines, and a half-written
    /// property dump silently loses whichever keys fell off the end, so a
    /// consumer would read "no PowerOutDetails" where the truth is "the dump
    /// stopped". Dropping them by exact size is the same rule the Thunderbolt
    /// corpus sweep already uses for probe 29.
    static func text(folder: String, probe: String) -> String? {
        let url = root.appendingPathComponent(folder).appendingPathComponent("\(probe).json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let output = obj["output"] as? String
        else { return nil }
        guard output.utf8.count != 65_536 else { return nil }
        return output
    }

    /// Like ``text(folder:probe:)`` but keeps truncated dumps, for the callers
    /// that want to count how many were dropped.
    static func textAllowingTruncation(folder: String, probe: String) -> String? {
        let url = root.appendingPathComponent(folder).appendingPathComponent("\(probe).json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let output = obj["output"] as? String
        else { return nil }
        return output
    }

    // MARK: - Probe 32: AppleSmartBattery full property dump

    /// Turns probe 32's indented property dump back into the `[String: Any]`
    /// tree IOKit would have handed `AppleSmartBatteryReader`.
    ///
    /// The dump is a faithful printout of the real property dictionary, so this
    /// recovers nested `Dict[N]` and `Array[N]` containers rather than
    /// scalar-grepping the text. That matters: `PowerOutDetails` and
    /// `PortControllerInfo` are arrays of dictionaries, and nothing about them
    /// can be replayed from a flat key/value scan.
    ///
    /// `Data[N]:` values are skipped. Nothing in the power path reads one, and
    /// they are the only value shape the printer elides with a trailing `...`.
    ///
    /// Only the `AppleSmartBattery` section is parsed. The dump carries three
    /// top-level sections (`AppleSmartBattery`, `AppleSmartBatteryManager`,
    /// `AppleACAdapter / ChargerData`), all printing their properties at the
    /// same indent, so a parser that merely strips the headers reads all three
    /// into one dictionary and lets a later section overwrite an earlier one.
    /// That is not hypothetical: `IOConfigOrder` already collides on
    /// `m2ultra_macos27.0_b`. It happens to be a key nothing reads, but a future
    /// collision on something like `ExternalConnected` would silently corrupt
    /// the replay inputs, so the section is bounded rather than the headers
    /// dropped. Found by the Codex review of the commit that added this file.
    static func probe32Properties(_ text: String) -> [String: Any] {
        // Cut at the next top-level header so sibling sections cannot leak in.
        // No marker means a dump shape we do not recognise: return nothing
        // rather than parse the whole file, and let the sweep's floors report
        // it. Every untruncated dump carries this header: 1141 of the 1349
        // folders holding a probe 32 are untruncated, and the header is
        // present in all 1141 (measured 2026-09-03 two ways, a Python pass
        // over the JSON and a `jq`/`wc -c` pass, agreeing exactly). The 585
        // this line used to quote was stale.
        guard let sectionStart = text.range(of: "=== AppleSmartBattery (full property dump) ===") else { return [:] }
        var section = String(text[sectionStart.upperBound...])
        if let nextHeader = section.range(of: "\n===") {
            section = String(section[..<nextHeader.lowerBound])
        }

        // Blank lines and the probe's own banner lines carry no indent
        // information, and a zero-indent line would otherwise close every open
        // container. Drop them before walking.
        var lines: [(indent: Int, body: String)] = []
        for raw in section.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = raw.prefix { $0 == " " }.count
            let body = raw.trimmingCharacters(in: .whitespaces)
            if body.isEmpty || body.hasPrefix("===") || body.hasPrefix("---") { continue }
            lines.append((indent, body))
        }
        // Property lines sit at indent 2 under the dump header. Find the first
        // one that actually looks like a property so a leading banner at some
        // other indent cannot set the level.
        guard let firstIndent = lines.first(where: { $0.body.contains(" = ") })?.indent else { return [:] }
        var cursor = lines.firstIndex(where: { $0.indent == firstIndent && $0.body.contains(" = ") }) ?? 0
        let (dict, _) = parseEntries(lines, &cursor, at: firstIndent)
        return dict
    }

    /// Parses every entry at exactly `indent`, recursing into containers.
    /// Returns both the dictionary and array views: a block is one or the
    /// other, and the caller knows which from the container header.
    private static func parseEntries(
        _ lines: [(indent: Int, body: String)],
        _ cursor: inout Int,
        at indent: Int
    ) -> ([String: Any], [Any]) {
        var dict: [String: Any] = [:]
        var array: [Any] = []

        while cursor < lines.count {
            let line = lines[cursor]
            if line.indent < indent { break }
            if line.indent > indent {
                // Deeper than this block without a container header above it.
                // Not a shape the printer produces; skip rather than loop.
                cursor += 1
                continue
            }

            var key: String?
            var rest: String

            if line.body.hasPrefix("["), let close = line.body.firstIndex(of: "]") {
                // Array element: "[0]         Dict[23]:" or "[0]    0 (0x0)".
                rest = String(line.body[line.body.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
            } else if let sep = line.body.range(of: " = ") {
                key = String(line.body[..<sep.lowerBound])
                rest = String(line.body[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                cursor += 1
                continue
            }

            cursor += 1

            let value: Any?
            if rest.hasSuffix(":"), rest.hasPrefix("Array[") || rest.hasPrefix("Dict[") {
                let isArray = rest.hasPrefix("Array[")
                // The container's children are whatever indent the next line
                // uses, read rather than assumed: the printer's step has been
                // 4 in every dump seen, but nothing depends on that here.
                if cursor < lines.count, lines[cursor].indent > indent {
                    let childIndent = lines[cursor].indent
                    let (childDict, childArray) = parseEntries(lines, &cursor, at: childIndent)
                    value = isArray ? childArray : childDict
                } else {
                    value = isArray ? [Any]() : [String: Any]()
                }
            } else {
                value = scalar(rest)
            }

            guard let value else { continue }
            if let key {
                dict[key] = value
            } else {
                array.append(value)
            }
        }

        return (dict, array)
    }

    /// One printed scalar. Returns nil for shapes the power path never reads
    /// (`Data[N]`, and anything unrecognised), so an unparsed value is absent
    /// rather than silently zero.
    private static func scalar(_ text: String) -> Any? {
        if text == "true" { return NSNumber(value: true) }
        if text == "false" { return NSNumber(value: false) }
        if text.hasPrefix("\"") {
            let inner = text.dropFirst()
            guard let end = inner.firstIndex(of: "\"") else { return nil }
            return String(inner[..<end])
        }
        if text.hasPrefix("Data[") { return nil }
        // "15000 (0x3a98)" or "-536854518 (0xffffffffe000400a)" or a bare
        // integer. The decimal form is authoritative; the hex is the printer
        // echoing it back.
        let digits = text.prefix { $0.isNumber || $0 == "-" }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        return NSNumber(value: n)
    }

    // MARK: - Probe 34: SMC keys

    /// One D-channel exactly as the probe printed it, before any decode.
    struct RawSMCChannel {
        let index: Int
        /// Raw `DxUI` hex, already normalised to the 32-char lowercase form the
        /// live reader produces.
        let uuid: String
        /// Raw `DxJV` / `DxJI` payload bytes, for decoding with the production
        /// float decoder.
        let voltsBytes: [UInt8]
        let ampsBytes: [UInt8]
        /// The value the probe itself printed after `= `, kept so a test can
        /// cross-check the production decode against an independent one.
        let printedVolts: Double?
        let printedAmps: Double?
        let present: Bool
    }

    static func probe34RawChannels(_ text: String) -> [RawSMCChannel] {
        var uuid: [Int: String] = [:]
        var voltsBytes: [Int: [UInt8]] = [:]
        var ampsBytes: [Int: [UInt8]] = [:]
        var printedVolts: [Int: Double] = [:]
        var printedAmps: [Int: Double] = [:]
        var present: [Int: Bool] = [:]

        for rawLine in text.split(separator: "\n") {
            // "  D1JV flt   4    raw=00000000  = 0.0000"
            let tokens = rawLine.split(separator: " ", omittingEmptySubsequences: true)
            guard let key = tokens.first, key.count == 4, key.hasPrefix("D"),
                  let idx = key.dropFirst().first?.wholeNumberValue, (1...4).contains(idx)
            else { continue }
            let field = String(key.suffix(2))
            let rawToken = tokens.first(where: { $0.hasPrefix("raw=") }).map { String($0.dropFirst(4)) }
            switch field {
            case "UI":
                if let rawToken { uuid[idx] = HPMPortUUIDMap.normalise(rawToken) }
            case "JV":
                if let rawToken { voltsBytes[idx] = hexBytes(rawToken) }
                if let last = tokens.last, let v = Double(last) { printedVolts[idx] = v }
            case "JI":
                if let rawToken { ampsBytes[idx] = hexBytes(rawToken) }
                if let last = tokens.last, let v = Double(last) { printedAmps[idx] = v }
            case "PR":
                if let rawToken { present[idx] = rawToken != "00" }
            default:
                break
            }
        }

        return (1...4).compactMap { idx in
            guard let u = uuid[idx], !u.isEmpty else { return nil }
            return RawSMCChannel(
                index: idx,
                uuid: u,
                voltsBytes: voltsBytes[idx] ?? [],
                ampsBytes: ampsBytes[idx] ?? [],
                printedVolts: printedVolts[idx],
                printedAmps: printedAmps[idx],
                present: present[idx] ?? false
            )
        }
    }

    /// The live reader's own shape, built by running the raw payload bytes
    /// through the production float decoder rather than trusting the probe's
    /// printed decode.
    static func smcChannel(from raw: RawSMCChannel) -> SMCPortPowerChannel {
        SMCPortPowerChannel(
            channel: raw.index,
            present: raw.present,
            volts: Double(SMCPowerReader.decodeFloat(raw.voltsBytes) ?? 0),
            amps: Double(SMCPowerReader.decodeFloat(raw.ampsBytes) ?? 0),
            uuid: raw.uuid
        )
    }

    private static func hexBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return [] }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    // MARK: - Probe 35: port to controller-UUID map

    struct Probe35Record {
        let label: String
        let portNumber: Int
        let isMagSafe: Bool
        let controllerClass: String
        let uuid: String?
    }

    static func probe35Records(_ text: String) -> [Probe35Record] {
        var results: [Probe35Record] = []
        var pendingLabel: String?
        var pendingNumber: Int?
        var pendingMagSafe = false
        var pendingClass: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
                let after = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
                guard let classRange = after.range(of: "class=") else { continue }
                let label = String(after[..<classRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let cls = String(after[classRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                    .prefix { !$0.isWhitespace }
                guard let at = label.lastIndex(of: "@"),
                      let num = Int(label[label.index(after: at)...].prefix { $0.isNumber })
                else { continue }
                pendingLabel = label
                pendingNumber = num
                pendingMagSafe = label.contains("MagSafe")
                pendingClass = String(cls)
            } else if trimmed.hasPrefix("UUID="),
                      let label = pendingLabel, let num = pendingNumber, let cls = pendingClass {
                let raw = String(trimmed.dropFirst("UUID=".count).prefix { $0 != " " })
                guard !raw.isEmpty else { continue }
                results.append(Probe35Record(
                    label: label, portNumber: num, isMagSafe: pendingMagSafe,
                    controllerClass: cls, uuid: raw == "(none)" ? nil : raw
                ))
                pendingLabel = nil
                pendingNumber = nil
                pendingClass = nil
            }
        }
        return results
    }

    /// Real `AppleHPMInterface` values built through the production factory, so
    /// the UUID map below is the production map and not a re-derivation of it.
    static func hpmPorts(from records: [Probe35Record]) -> [AppleHPMInterface] {
        records.enumerated().compactMap { offset, record in
            let props: [String: Any] = [
                "PortTypeDescription": record.isMagSafe ? "MagSafe 3" : "USB-C",
                "PortNumber": NSNumber(value: record.portNumber),
                "PortType": NSNumber(value: record.isMagSafe ? 0x11 : 0x2),
            ]
            // The UUID is gated on the same production predicate the live
            // ancestor walk uses, applied to the controller class the probe
            // actually recorded. Injecting the UUID unconditionally would make
            // the map look like it works on silicon where it does not.
            let uuid = wcIsHPMControllerClass(record.controllerClass) ? record.uuid : nil
            return AppleHPMInterface.from(
                entryID: UInt64(offset + 1),
                serviceName: record.label,
                className: "AppleHPMInterfaceType10",
                read: { props[$0] },
                hpmControllerUUID: uuid
            )
        }
    }

    /// Real ports from probe 17's `AppleHPMInterfaceType*` blocks, which unlike
    /// probe 35 carry the live connection state.
    ///
    /// Probe 35 publishes only the port label, class, controller UUID, RID and
    /// address; there is no `ConnectionActive` in it at all. Anything gated on
    /// a port being in use therefore has to come from here, and a sweep that
    /// built its ports from probe 35 alone would find every such gate closed
    /// and report a clean zero. That is not hypothetical: it is what the first
    /// version of `SMCContractCorpusSweepTests` did.
    ///
    /// - Parameter controllerUUIDs: port key to controller UUID, from probe 35.
    ///   Probe 17 does not reliably expose the controller UUID on the port
    ///   block (it lives on a parent node), so the two probes are joined on the
    ///   port key both publish. Every value stays real; only their pairing is
    ///   reconstructed, and it is reconstructed per machine.
    static func probe17HPMPorts(_ text: String, controllerUUIDs: [String: String]) -> [AppleHPMInterface] {
        guard let re = try? NSRegularExpression(pattern: #"--- (\w+)\[(\d+)\] ---"#) else { return [] }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var ports: [AppleHPMInterface] = []
        for (idx, match) in matches.enumerated() {
            guard let classRange = Range(match.range(at: 1), in: text),
                  String(text[classRange]).hasPrefix("AppleHPMInterfaceType"),
                  let blockStart = Range(match.range, in: text).map({ $0.upperBound })
            else { continue }
            let blockEnd = idx + 1 < matches.count
                ? Range(matches[idx + 1].range, in: text)!.lowerBound
                : text.endIndex
            let body = String(text[blockStart..<blockEnd])
            // Bound at the first nested class header so a child block's own
            // Description cannot clobber the port's identity.
            var flatZone = body
            if let innerRe = try? NSRegularExpression(pattern: #"=== (\w+) ==="#) {
                let inner = innerRe.matches(in: body, range: NSRange(body.startIndex..., in: body))
                if inner.count > 1, let second = Range(inner[1].range, in: body) {
                    flatZone = String(body[..<second.lowerBound])
                }
            }
            var props: [String: Any] = [:]
            for line in flatZone.split(separator: "\n", omittingEmptySubsequences: false) {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty, !t.hasPrefix("==="), !t.hasPrefix("---"),
                      let sep = t.range(of: ": ") ?? t.range(of: " = ") else { continue }
                let key = String(t[..<sep.lowerBound])
                let value = String(t[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
                if value == "true" { props[key] = NSNumber(value: true) }
                else if value == "false" { props[key] = NSNumber(value: false) }
                else if value.hasPrefix("\""), let end = value.dropFirst().firstIndex(of: "\"") {
                    props[key] = String(value.dropFirst()[..<end])
                } else if let n = Int(value.prefix { $0.isNumber }), !value.prefix(1).isEmpty {
                    props[key] = NSNumber(value: n)
                }
            }
            let serviceName = (props["Description"] as? String) ?? ""
            let portType = (props["PortTypeDescription"] as? String) ?? ""
            guard portType == "USB-C" || portType.hasPrefix("MagSafe"),
                  serviceName.hasPrefix("Port-"), !serviceName.contains("/") else { continue }
            // Built without a UUID first, so its portKey can be used to look one
            // up, then rebuilt with it.
            guard let bare = AppleHPMInterface.from(
                entryID: UInt64(idx + 1), serviceName: serviceName,
                className: "AppleHPMInterfaceType10", read: { props[$0] }
            ), let key = bare.portKey else { continue }
            guard let withUUID = AppleHPMInterface.from(
                entryID: UInt64(idx + 1), serviceName: serviceName,
                className: "AppleHPMInterfaceType10", read: { props[$0] },
                hpmControllerUUID: controllerUUIDs[key]
            ) else { continue }
            ports.append(withUUID)
        }
        return ports
    }

    /// Port key to controller UUID, from probe 35.
    static func controllerUUIDsByPortKey(_ records: [Probe35Record]) -> [String: String] {
        var map: [String: String] = [:]
        for record in records {
            guard wcIsHPMControllerClass(record.controllerClass), let uuid = record.uuid else { continue }
            let identity = PortIdentity(
                typeCode: record.isMagSafe ? PortIdentity.magSafeTypeCode : PortIdentity.usbCTypeCode,
                number: record.portNumber
            )
            map[identity.key] = uuid
        }
        return map
    }

    // MARK: - Probe 17: IOPortFeaturePowerSource blocks

    /// Real `PowerSource` values via `PowerSourceWatcher.makeSource`, the same
    /// factory the live watcher calls.
    static func powerSources(from text: String) -> [PowerSource] {
        powerSourceBlocks(text).enumerated().compactMap { offset, props in
            PowerSourceWatcher.makeSource(
                entryID: UInt64(offset + 1),
                read: { props[$0] },
                hpmControllerUUID: nil
            )
        }
    }

    /// Every `=== IOPortFeaturePowerSource ===` block as a flat property dict.
    ///
    /// Each block's body is bounded at the next header of ANY indent. A search
    /// for an unindented `\n===` misses the indented ones (PowerSource blocks
    /// sit at 2 or 4 spaces depending on how deep the port's "Power In" feature
    /// is), letting one block's body run to the end of the file and merging
    /// several ports' fields into one corrupted dict.
    private static func powerSourceBlocks(_ text: String) -> [[String: Any]] {
        let ns = text as NSString
        guard let headerRE = try? NSRegularExpression(pattern: #"\n[ \t]*(?:===|---)"#) else { return [] }
        let headerStarts = headerRE
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map(\.range.location)
            .sorted()

        var results: [[String: Any]] = []
        var searchLocation = 0
        let marker = "=== IOPortFeaturePowerSource ==="
        while searchLocation < ns.length {
            let found = ns.range(
                of: marker,
                options: [],
                range: NSRange(location: searchLocation, length: ns.length - searchLocation)
            )
            guard found.location != NSNotFound else { break }
            let bodyStart = found.location + found.length
            let bodyEnd = headerStarts.first { $0 > bodyStart } ?? ns.length
            let body = ns.substring(with: NSRange(location: bodyStart, length: max(0, bodyEnd - bodyStart)))
            results.append(powerSourceProps(body))
            searchLocation = bodyEnd > bodyStart ? bodyEnd : bodyStart + 1
        }
        return results
    }

    private static func powerSourceProps(_ body: String) -> [String: Any] {
        var dict: [String: Any] = [:]
        let lines = Array(body.split(separator: "\n", omittingEmptySubsequences: false))
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("WinningPowerSourceOption:") {
                var sub: [String: Any] = [:]
                var inner = index + 1
                while inner < lines.count {
                    let subLine = lines[inner].trimmingCharacters(in: .whitespaces)
                    if subLine == "}" { break }
                    if let sep = subLine.range(of: ": ") {
                        let key = String(subLine[..<sep.lowerBound])
                        if let value = scalarOrQuoted(String(subLine[sep.upperBound...])) { sub[key] = value }
                    }
                    inner += 1
                }
                dict["WinningPowerSourceOption"] = sub
                index = inner + 1
                continue
            }
            if !line.isEmpty, !line.hasPrefix("==="), !line.hasPrefix("---"),
               let sep = line.range(of: ": ") {
                let key = String(line[..<sep.lowerBound])
                if let value = scalarOrQuoted(String(line[sep.upperBound...])) { dict[key] = value }
            }
            index += 1
        }
        return dict
    }

    /// Probe 17 prints plain values with no `(0x...)` echo, so this is the
    /// simpler sibling of ``scalar(_:)``.
    private static func scalarOrQuoted(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == "true" { return NSNumber(value: true) }
        if trimmed == "false" { return NSNumber(value: false) }
        if trimmed.hasPrefix("\"") {
            let inner = trimmed.dropFirst()
            guard let end = inner.firstIndex(of: "\"") else { return nil }
            return String(inner[..<end])
        }
        let digits = trimmed.prefix { $0.isNumber || $0 == "-" }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        return NSNumber(value: n)
    }

    // MARK: - Probe 17: winning power source option class strings

    /// Folders that carry an untruncated probe 17 dump. A truncated dump can
    /// end mid-block, which would either drop or corrupt whichever
    /// `WinningPowerSourceOption` block straddles the cut, so those folders
    /// are excluded the same way ``text(folder:probe:)`` already excludes
    /// them for every other probe-17 reader in this file.
    static func foldersWithProbe17() -> [String] {
        folders().filter { probe17Text($0) != nil }
    }

    /// Probe 17's raw text for one folder, or nil when the folder has no
    /// probe 17 dump or it was truncated at the 64 KB pipe cap.
    static func probe17Text(_ folder: String) -> String? {
        text(folder: folder, probe: "17_deep_property_dump")
    }

    /// Which of probe 17's two block shapes a `WinningPowerSourceOption`
    /// block was found under.
    enum WinningOptionBlockShape {
        /// `--- Class[N] ---` header, 4-space inner indent. The flat "All
        /// IOPortFeature* services" section, present on every machine.
        case dash
        /// `=== Class ===` header, 8-space inner indent. The nested "HPM
        /// Interface -> all children" deep-dive section, M3+ only.
        case equals
    }

    /// One `WinningPowerSourceOption: { ... }` block, reduced to its `Class`
    /// string and which header shape it was found under.
    struct WinningOptionBlock {
        let classString: String?
        /// nil only when no header of either known shape precedes the block,
        /// which should not happen on a well-formed dump; a reader that hits
        /// this should be treated as suspect, not as "shape unknown, ignore".
        let shape: WinningOptionBlockShape?
    }

    /// Every `WinningPowerSourceOption: { ... }` block in a probe 17 dump,
    /// with the `Class` value each one carries (or nil when the block has no
    /// `Class` key).
    ///
    /// Probe 17 prints these blocks in two shapes, depending on which section
    /// of the dump they sit in: a `--- Class[N] ---` header with a 4-space
    /// inner indent (the flat "All IOPortFeature* services" section, present
    /// on every machine), and an `=== Class ===` header with an 8-space inner
    /// indent (the nested "HPM Interface -> all children" deep-dive section,
    /// M3+ only). Both shapes print the sub-dict itself the same way, one
    /// `key: value` line per line ending in a lone `}`, so scanning forward
    /// line by line to that closing brace reads both shapes without caring
    /// which indent the surrounding block used. `ProbeCorpus.parseWinningOption`
    /// / `parseWinningOptionFromEqualsBlock` in `WhatCableCoreTests` DO rely on
    /// the indent, because they need to pull the block's other keys out as
    /// typed integers; this reader only needs one string value, so it does
    /// not need their machinery.
    static func winningOptionClassStrings(in text: String) -> [WinningOptionBlock] {
        let headers = winningOptionHeaderMarks(in: text)
        var results: [WinningOptionBlock] = []
        let marker = "WinningPowerSourceOption: {"
        var searchRange = text.startIndex..<text.endIndex
        while let markerRange = text.range(of: marker, range: searchRange) {
            var classString: String?
            var cursor = markerRange.upperBound
            while cursor < text.endIndex {
                let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
                let line = String(text[cursor..<lineEnd]).trimmingCharacters(in: .whitespaces)
                cursor = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
                if line == "}" { break }
                if line.hasPrefix("Class: \"") {
                    let afterPrefix = line.dropFirst("Class: \"".count)
                    if let closingQuote = afterPrefix.firstIndex(of: "\"") {
                        classString = String(afterPrefix[..<closingQuote])
                    }
                }
            }
            // The block's shape is whichever header (of either kind) most
            // recently precedes it. `WinningPowerSourceOption` is a plain
            // property of the enclosing `IOPortFeaturePowerSource` block, so
            // no other header can sit between that block's own header and
            // this marker.
            let shape = headers.last { $0.location <= markerRange.lowerBound }?.shape
            results.append(WinningOptionBlock(classString: classString, shape: shape))
            searchRange = cursor..<text.endIndex
        }
        return results
    }

    /// Every block-header line in a probe 17 dump, with which shape it is,
    /// in ascending text-position order.
    ///
    /// A dash header reads `--- Class[N] ---` (optionally indented). An
    /// equals header reads `=== Class ===` (optionally indented). Probe 17
    /// also prints a plain banner line of unbroken `=` characters
    /// ("============================================================")
    /// around section titles; that banner has no interior space next to the
    /// `=` runs, so it does not match the equals-header pattern below, which
    /// requires whitespace right after the opening `===` and right before the
    /// closing `===`.
    private static func winningOptionHeaderMarks(
        in text: String
    ) -> [(location: String.Index, shape: WinningOptionBlockShape)] {
        guard let dashRE = try? NSRegularExpression(pattern: #"(?m)^[ \t]*---\s+\S.*\S\s+---\s*$"#),
              let equalsRE = try? NSRegularExpression(pattern: #"(?m)^[ \t]*===\s+\S.*\S\s+===\s*$"#)
        else { return [] }
        var marks: [(location: String.Index, shape: WinningOptionBlockShape)] = []
        for (regex, shape) in [(dashRE, WinningOptionBlockShape.dash), (equalsRE, WinningOptionBlockShape.equals)] {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                marks.append((range.lowerBound, shape))
            }
        }
        return marks.sorted { $0.location < $1.location }
    }
}
