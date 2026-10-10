import Foundation
import Testing
@testable import WhatCableDarwinBackend
import WhatCableCore

// MARK: - SnapshotRenderCorpusSweepTests
//
// The end-to-end release-confidence sweep: for every
// corpus folder that has probe 01, assemble the fullest `CableSnapshot` the
// on-disk probes for that folder allow, using ONLY production factory
// functions (`AppleHPMInterface.from`, `USBPDSOPWatcher.parseIdentity`,
// `TRMTransportWatcher.makeCIOCapability`, `USB3TransportWatcher.makeTransport`,
// `PowerSourceWatcher.makeSource`, `IOThunderboltSwitch.from`,
// `IOThunderboltPort.from`, and `USBDevice`'s public initialiser for probe
// 38), then render it through BOTH `JSONFormatter.render` and
// `TextFormatter.render`. This is the first sweep in the corpus-coverage
// pass to touch the formatters at all.
//
// Every parsing helper below is a duplicate (with light renaming) of a
// helper already proven correct in another sweep file, per the house rule of
// copying shared parsing helpers into each new file rather than editing an
// existing one:
//   - probe-01 SOP blocks:            WatcherCorpusSweepTests.loadSOPBlocks
//   - probe-17 HPM interface blocks:  WatcherCorpusSweepTests.loadProbe17Blocks / parseProbe17Blocks
//   - probe-17 TRM/CIO/USB3/PowerSource dash+equals blocks: TransportWatcherSweepTests
//   - probe-29 TB switch/port blocks: ThunderboltProbeSweepTests.parseInstanceBlocks
//   - probe-35 port/UUID records:     HPMPortUUIDMapCorpusSweepTests.parseProbe35
//   - probe-38 USB device blocks:     Probe38TreeWalkTests.parse (WhatCableCoreTests;
//     duplicated here since that file lives in a different test target)
//
// PRIVACY: this file feeds REAL per-machine HPM controller UUIDs (from probe
// 35, when present) and REAL Thunderbolt switch UIDs (from probe 29) into the
// snapshot, specifically so the "no UUID/UID leak into JSON/text output"
// assertion is checked against genuine customer identifiers, not synthetic
// placeholders that might accidentally dodge a real leak path. Assertion
// messages only ever print an 8-char truncated prefix or the leak boolean,
// never a full UUID, matching the house privacy rule even in failure output.
@Suite("Snapshot render corpus sweep - end-to-end JSON/Text formatter integration")
struct SnapshotRenderCorpusSweepTests {

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

    private static func loadProbeText(folder: String, fileName: String) -> String? {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Shared text-parsing primitives (duplicated from TransportWatcherSweepTests)

    private static func parseIntLiteral(_ s: String) -> Int? {
        let trimmed = s.drop(while: { $0 == " " })
        let digits = trimmed.prefix { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    private static func parseQuotedString(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("\""), let endQ = t.dropFirst().firstIndex(of: "\"") else { return nil }
        return String(t.dropFirst()[..<endQ])
    }

    private static func parseDashBlocks(text: String, classPrefix: String) -> [[String: Any]] {
        let escapedPrefix = NSRegularExpression.escapedPattern(for: classPrefix)
        guard let regex = try? NSRegularExpression(pattern: "--- \(escapedPrefix)\\[\\d+\\] ---") else { return [] }
        let nsText = text as NSString
        let headerMatches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var blocks: [[String: Any]] = []
        for (i, match) in headerMatches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < headerMatches.count ? headerMatches[i + 1].range.lowerBound : nsText.length
            var body = nsText.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
            for sep in ["\n---", "\n==="] {
                if let r = body.range(of: sep) { body = String(body[..<r.lowerBound]) }
            }
            blocks.append(parseProperties(body: body, indent: "  "))
        }
        return blocks
    }

    private static func parseEqualsBlocks(text: String, className: String) -> [[String: Any]] {
        let header = "=== \(className) ==="
        var blocks: [[String: Any]] = []
        var searchFrom = text.startIndex
        while let range = text.range(of: header, range: searchFrom..<text.endIndex) {
            let bodyStart = range.upperBound
            var body: String
            let rest = String(text[bodyStart...])
            if let nextSection = rest.range(of: "\n=== ") ?? rest.range(of: "\n--- ") {
                body = String(rest[..<nextSection.lowerBound])
            } else {
                body = String(rest.prefix(2000))
            }
            blocks.append(parseProperties(body: body, indent: "    "))
            searchFrom = range.upperBound
        }
        return blocks
    }

    private static func parseProperties(body: String, indent: String) -> [String: Any] {
        var props: [String: Any] = [:]
        let deeper = indent + " "
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.hasPrefix(indent), !s.hasPrefix(deeper) else { continue }
            let stripped = String(s.dropFirst(indent.count))
            guard let colonRange = stripped.range(of: ": ") else { continue }
            let key = String(stripped[..<colonRange.lowerBound])
            let valStr = String(stripped[colonRange.upperBound...])
            if valStr == "true" {
                props[key] = NSNumber(value: true)
            } else if valStr == "false" {
                props[key] = NSNumber(value: false)
            } else if valStr.hasPrefix("\""), valStr.hasSuffix("\""), valStr.count >= 2 {
                props[key] = String(valStr.dropFirst().dropLast())
            } else if let m = parseIntLiteral(valStr) {
                props[key] = NSNumber(value: m)
            }
        }
        return props
    }

    // MARK: - Probe-01 SOP identity (duplicated from WatcherCorpusSweepTests.loadSOPBlocks)

    private struct SOPBlock {
        let className: String
        let portNumber: Int
        let read: (String) -> Any?
    }

    private static func loadSOPBlocks(folder: String) -> [SOPBlock] {
        guard let text = loadProbeText(folder: folder, fileName: "01_walk_pd_tree.json") else { return [] }
        let blocks = text.components(separatedBy: "=== ").dropFirst()
        var results: [SOPBlock] = []
        for block in blocks {
            guard block.contains("CCUSBPDSOP") else { continue }
            let firstLine = String(block.prefix(while: { $0 != "\n" }))
            let rawClass = firstLine.replacingOccurrences(
                of: #"\[\d+\].*$"#, with: "", options: .regularExpression
            ).trimmingCharacters(in: .whitespaces)
            guard rawClass.hasPrefix("IOPortTransportComponentCCUSBPDSOP") else { continue }

            var portNumber = 0
            if let re = try? NSRegularExpression(pattern: #"Description = "Port-USB-C@(\d+)/CC"#),
               let m = re.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
               let r = Range(m.range(at: 1), in: block), let n = Int(block[r]) {
                portNumber = n
            }

            var dict: [String: Any] = [:]
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            var i = 0
            while i < lines.count {
                let line = lines[i]
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("Metadata =") || t.hasPrefix("Metadata:") {
                    let bodyLines = Array(lines[(i + 1)...])
                    var metaDict: [String: Any] = [:]
                    var j = 0
                    var vdos: [Data] = []
                    var inVDOs = false
                    while j < bodyLines.count {
                        let ml = bodyLines[j].trimmingCharacters(in: .whitespaces)
                        if ml == "}" { break }
                        if ml.hasPrefix("VDOs") { inVDOs = true; j += 1; continue }
                        if inVDOs {
                            if ml == "]" { inVDOs = false; j += 1; continue }
                            if let re = try? NSRegularExpression(pattern: #"<data 4 bytes: ([0-9a-fA-F ]+)>"#),
                               let m = re.firstMatch(in: ml, range: NSRange(ml.startIndex..., in: ml)),
                               let r = Range(m.range(at: 1), in: ml) {
                                let parts = String(ml[r]).split(separator: " ").compactMap { UInt8($0, radix: 16) }
                                if parts.count == 4 { vdos.append(Data(parts)) }
                            }
                            j += 1; continue
                        }
                        if let sep = ml.range(of: " = ") {
                            let key = String(ml[..<sep.lowerBound])
                            let val = String(ml[sep.upperBound...])
                            if val == "true" { metaDict[key] = NSNumber(value: true) }
                            else if val == "false" { metaDict[key] = NSNumber(value: false) }
                            else if let s = parseQuotedString(val) { metaDict[key] = s }
                            else if let n = parseIntLiteral(val) { metaDict[key] = NSNumber(value: n) }
                        }
                        j += 1
                    }
                    if !vdos.isEmpty { metaDict["VDOs"] = vdos as [Any] }
                    dict["Metadata"] = metaDict as Any
                    i += 1
                    continue
                }
                if line.hasPrefix("    "), let sep = t.range(of: " = ") {
                    let key = String(t[..<sep.lowerBound])
                    let val = String(t[sep.upperBound...])
                    if val == "true" { dict[key] = NSNumber(value: true) }
                    else if val == "false" { dict[key] = NSNumber(value: false) }
                    else if let s = parseQuotedString(val) { dict[key] = s }
                    else if let n = parseIntLiteral(val) { dict[key] = NSNumber(value: n) }
                }
                i += 1
            }
            results.append(SOPBlock(className: rawClass, portNumber: portNumber, read: { dict[$0] }))
        }
        return results
    }

    // MARK: - Probe-17 HPM interface blocks (duplicated from WatcherCorpusSweepTests)

    private static func parseHPMBlocks(folder: String) -> [(serviceName: String, portType: String, portNumber: Int, className: String, read: (String) -> Any?)] {
        guard let text = loadProbeText(folder: folder, fileName: "17_deep_property_dump.json") else { return [] }
        let pattern = #"--- (\w+)\[(\d+)\] ---"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))

        var results: [(String, String, Int, String, (String) -> Any?)] = []
        for (idx, m) in matches.enumerated() {
            guard let classRange = Range(m.range(at: 1), in: text) else { continue }
            let outerClass = String(text[classRange])
            guard outerClass.hasPrefix("AppleHPMInterfaceType") else { continue }
            guard let blockStart = Range(m.range, in: text).map({ $0.upperBound }) else { continue }
            let blockEnd: String.Index = idx + 1 < matches.count
                ? Range(matches[idx + 1].range, in: text)!.lowerBound
                : text.endIndex
            let body = String(text[blockStart..<blockEnd])
            var innerClass = outerClass
            // The block's own flat properties (Description, PortNumber,
            // PortTypeDescription, ...) all appear BEFORE any nested
            // "=== ChildClass ===" sub-component section (confirmed against
            // the corpus: nested PD-identity/UVDM sub-blocks carry their OWN
            // "Description" key, e.g. "Port-USB-C@1/CC/SOP/AppleUVDM", which
            // would silently clobber the correct outer "Port-USB-C@1" value
            // in a flat, nesting-unaware scan). Bound the property scan to
            // end at the SECOND "=== " occurrence (the first is the block's
            // own inner class header, e.g. "=== AppleHPMInterfaceType18 ===";
            // the second is the first nested child, where the flat zone
            // ends), so only genuinely top-level keys are captured.
            var flatZone = body
            if let innerRe = try? NSRegularExpression(pattern: #"=== (\w+) ==="#) {
                let allMatches = innerRe.matches(in: body, range: NSRange(body.startIndex..., in: body))
                if let first = allMatches.first, let ir = Range(first.range(at: 1), in: body) {
                    innerClass = String(body[ir])
                }
                if allMatches.count > 1, let secondRange = Range(allMatches[1].range, in: body) {
                    flatZone = String(body[..<secondRange.lowerBound])
                }
            }
            let props = parseGenericProperties(body: flatZone)
            let read: (String) -> Any? = { props[$0] }
            let serviceName = (read("Description") as? String) ?? ""
            let portType = (read("PortTypeDescription") as? String) ?? ""
            let portNumber = (read("PortNumber") as? NSNumber)?.intValue ?? 0
            guard (portType == "USB-C" || portType.hasPrefix("MagSafe")) && serviceName.hasPrefix("Port-") else { continue }
            results.append((serviceName, portType, portNumber, innerClass, read))
        }
        return results
    }

    /// Generic `KEY: VALUE` / `KEY = VALUE` property parser for probe-17
    /// blocks (handles the subset of fields the render sweep needs: strings,
    /// bools, ints, and `[String]` arrays). Duplicated (simplified) from
    /// WatcherCorpusSweepTests.makeReadClosure.
    private static func parseGenericProperties(body: String) -> [String: Any] {
        var dict: [String: Any] = [:]
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("===") || t.hasPrefix("---") { i += 1; continue }
            if let sepRange = (t.range(of: ": [") ?? t.range(of: " = [")) {
                let key = String(t[..<sepRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                var arr: [String] = []
                var j = i + 1
                while j < lines.count {
                    let tl = lines[j].trimmingCharacters(in: .whitespaces)
                    if tl == "]" { break }
                    if let q1 = tl.firstIndex(of: "\""), let q2 = tl.lastIndex(of: "\""), q1 != q2 {
                        arr.append(String(tl[tl.index(after: q1)..<q2]))
                    }
                    j += 1
                }
                dict[key] = arr as [Any]
                i += 1
                continue
            }
            if let sepRange = t.range(of: ": ") ?? t.range(of: " = ") {
                let key = String(t[..<sepRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let val = String(t[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if val == "true" { dict[key] = NSNumber(value: true) }
                else if val == "false" { dict[key] = NSNumber(value: false) }
                else if let s = parseQuotedString(val) { dict[key] = s }
                else if let n = parseIntLiteral(val) { dict[key] = NSNumber(value: n) }
            }
            i += 1
        }
        return dict
    }

    // MARK: - Probe-35 port/UUID (duplicated from HPMPortUUIDMapCorpusSweepTests.parseProbe35)

    private struct Probe35Record { let label: String; let portNumber: Int; let isMagSafe: Bool; let uuid: String }

    private static func parseProbe35(folder: String) -> [Probe35Record] {
        guard let text = loadProbeText(folder: folder, fileName: "35_hpm_port_uuid.json") else { return [] }
        var results: [Probe35Record] = []
        var pendingLabel: String?
        var pendingPortNumber: Int?
        var pendingIsMagSafe = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), let closeIdx = trimmed.firstIndex(of: "]") {
                let afterBracket = trimmed[trimmed.index(after: closeIdx)...].trimmingCharacters(in: .whitespaces)
                guard let classRange = afterBracket.range(of: "class=") else { continue }
                let label = String(afterBracket[..<classRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                guard let atIdx = label.lastIndex(of: "@") else { continue }
                let numDigits = label[label.index(after: atIdx)...].prefix { $0.isNumber }
                guard let num = Int(numDigits) else { continue }
                pendingLabel = label; pendingPortNumber = num; pendingIsMagSafe = label.contains("MagSafe")
            } else if trimmed.hasPrefix("UUID="), let label = pendingLabel, let num = pendingPortNumber {
                let afterEq = trimmed.dropFirst("UUID=".count)
                let uuid = String(afterEq.prefix { $0 != " " })
                guard !uuid.isEmpty else { continue }
                results.append(Probe35Record(label: label, portNumber: num, isMagSafe: pendingIsMagSafe, uuid: uuid))
                pendingLabel = nil; pendingPortNumber = nil
            }
        }
        return results
    }

    // MARK: - Probe-29 Thunderbolt switches (duplicated from ThunderboltProbeSweepTests)

    private static func parseInstanceBlocks(_ text: String, className: String) -> [(header: String, body: String)] {
        var results: [(header: String, body: String)] = []
        let lines = text.components(separatedBy: "\n")
        var currentHeader: String?
        var currentBody: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--- \(className)") && trimmed.hasSuffix("---") {
                if let h = currentHeader { results.append((h, currentBody.joined(separator: "\n"))) }
                currentHeader = trimmed; currentBody = []
            } else if trimmed.hasPrefix("=== ") && trimmed.hasSuffix(" ===") {
                if let h = currentHeader {
                    results.append((h, currentBody.joined(separator: "\n")))
                    currentHeader = nil; currentBody = []
                }
            } else if currentHeader != nil {
                currentBody.append(line)
            }
        }
        if let h = currentHeader { results.append((h, currentBody.joined(separator: "\n"))) }
        return results
    }

    private static func parseTBIntLine(_ body: String, key: String) -> Int? {
        let prefix = "  \(key) = "
        for line in body.components(separatedBy: "\n") where line.hasPrefix(prefix) {
            let after = line.dropFirst(prefix.count).drop(while: { $0 == " " })
            let digits = after.prefix { $0.isNumber || $0 == "-" }
            return Int(digits)
        }
        return nil
    }

    private static func parseTBStringLine(_ body: String, key: String) -> String? {
        let prefix = "  \(key) = "
        for line in body.components(separatedBy: "\n") where line.hasPrefix(prefix) {
            let after = line.dropFirst(prefix.count).drop(while: { $0 == " " })
            guard after.hasPrefix("\"") else { continue }
            let inner = after.dropFirst()
            if let close = inner.firstIndex(of: "\"") { return String(inner[..<close]) }
        }
        return nil
    }

    private static func makeTBReadClosure(body: String) -> (String) -> Any? {
        { key in
            if let s = parseTBStringLine(body, key: key) { return s as Any }
            if let n = parseTBIntLine(body, key: key) { return NSNumber(value: n) }
            return nil
        }
    }

    private static func loadThunderboltSwitches(folder: String) -> [IOThunderboltSwitch] {
        guard let text = loadProbeText(folder: folder, fileName: "29_usb4_router_interfaces.json") else { return [] }
        var switches: [IOThunderboltSwitch] = []
        for (_, body) in parseInstanceBlocks(text, className: "IOThunderboltSwitch") {
            let read = makeTBReadClosure(body: body)
            // Real UID from the probe, used deliberately for the privacy leak
            // check below (see file doc comment).
            let uid = parseTBIntLine(body, key: "UID").map(Int64.init) ?? 0
            if let sw = IOThunderboltSwitch.from(uid: uid, read: read, className: "IOThunderboltSwitch", ports: []) {
                switches.append(sw)
            }
        }
        return switches
    }

    // MARK: - Probe-38 USB devices (duplicated from Probe38TreeWalkTests, WhatCableCoreTests)

    private static func loadUSBDevices(folder: String) -> [USBDevice] {
        guard let text = loadProbeText(folder: folder, fileName: "38_usb_device_tree.json") else { return [] }
        return text.components(separatedBy: "--- Device[").dropFirst().compactMap { block in
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
                id: UInt64(loc), locationID: loc,
                vendorID: hex("idVendor").map { UInt16(truncatingIfNeeded: $0) } ?? 0,
                productID: hex("idProduct").map { UInt16(truncatingIfNeeded: $0) } ?? 0,
                vendorName: value("USB Vendor Name"), productName: value("USB Product Name"),
                serialNumber: nil, usbVersion: nil,
                speedRaw: value("Device Speed").flatMap { UInt8($0) },
                busPowerMA: nil, currentMA: nil,
                deviceClass: value("bDeviceClass").flatMap { UInt8($0) },
                rawProperties: [:]
            )
        }
    }

    // MARK: - Snapshot assembly

    private struct AssembledSnapshot {
        let snapshot: CableSnapshot
        /// Real UUIDs/UIDs fed into this snapshot, for the privacy leak check.
        let sensitiveIdentifiers: [String]
    }

    private static func assembleSnapshot(folder: String) -> AssembledSnapshot? {
        let sopBlocks = loadSOPBlocks(folder: folder)
        guard !sopBlocks.isEmpty else { return nil }   // probe 01 is the gate; every folder has it committed

        var sensitiveIdentifiers: [String] = []

        // Identities (probe 01)
        let identities: [USBPDSOP] = sopBlocks.enumerated().compactMap { idx, block in
            let endpoint: USBPDSOP.Endpoint
            switch block.className {
            case "IOPortTransportComponentCCUSBPDSOP": endpoint = .sop
            case "IOPortTransportComponentCCUSBPDSOPp": endpoint = .sopPrime
            case "IOPortTransportComponentCCUSBPDSOPpp": endpoint = .sopDoublePrime
            default: endpoint = .unknown
            }
            _ = endpoint
            return USBPDSOPWatcher.parseIdentity(entryID: UInt64(idx + 1), read: block.read, className: block.className, hpmControllerUUID: nil)
        }

        // Ports (probe 17), enriched with real UUIDs from probe 35 when present.
        let probe35 = parseProbe35(folder: folder)
        func matchedUUID(portType: String, portNumber: Int) -> String? {
            let isMagSafe = portType.hasPrefix("MagSafe")
            return probe35.first { $0.isMagSafe == isMagSafe && $0.portNumber == portNumber }?.uuid
        }
        let hpmBlocks = parseHPMBlocks(folder: folder)
        let ports: [AppleHPMInterface] = hpmBlocks.enumerated().compactMap { idx, block in
            let uuid = matchedUUID(portType: block.portType, portNumber: block.portNumber)
            if let uuid { sensitiveIdentifiers.append(uuid) }
            return AppleHPMInterface.from(
                entryID: UInt64(idx + 1), serviceName: block.serviceName, className: block.className,
                read: block.read, hpmControllerUUID: uuid
            )
        }
        guard !ports.isEmpty else { return nil }   // need at least one real port to render meaningfully

        // Power sources (probe 17, IOPortFeaturePowerSource dash blocks)
        var powerSources: [PowerSource] = []
        var trmTransports: [TRMTransport] = []
        var cioCapabilities: [CIOCableCapability] = []
        var usb3Transports: [USB3Transport] = []
        if let probe17Text = loadProbeText(folder: folder, fileName: "17_deep_property_dump.json") {
            for (i, props) in parseDashBlocks(text: probe17Text, classPrefix: "IOPortFeaturePowerSource").enumerated() {
                let read: (String) -> Any? = { props[$0] }
                if let src = PowerSourceWatcher.makeSource(entryID: UInt64(4000 + i), read: read, hpmControllerUUID: nil) {
                    powerSources.append(src)
                }
            }
            for cls in TRMTransportWatcher.watchedClasses {
                for (i, props) in (parseDashBlocks(text: probe17Text, classPrefix: cls)
                                    + parseEqualsBlocks(text: probe17Text, className: cls)).enumerated() {
                    guard props["TRM_State"] != nil else { continue }
                    let read: (String) -> Any? = { props[$0] }
                    if let t = TRMTransportWatcher.makeTRMTransport(
                        entryID: UInt64(5000 + i), read: read,
                        transportType: TRMTransportWatcher.transportType(from: cls), hpmControllerUUID: nil
                    ) {
                        trmTransports.append(t)
                    }
                }
            }
            for (i, props) in parseEqualsBlocks(text: probe17Text, className: "IOPortTransportStateCIO").enumerated() {
                let read: (String) -> Any? = { props[$0] }
                if let c = TRMTransportWatcher.makeCIOCapability(entryID: UInt64(6000 + i), read: read, hpmControllerUUID: nil) {
                    cioCapabilities.append(c)
                }
            }
            for (i, props) in parseDashBlocks(text: probe17Text, classPrefix: "IOPortTransportStateUSB3").enumerated() {
                let read: (String) -> Any? = { props[$0] }
                if let t = USB3TransportWatcher.makeTransport(entryID: UInt64(7000 + i), read: read, hpmControllerUUID: nil) {
                    usb3Transports.append(t)
                }
            }
        }

        // Thunderbolt fabric (probe 29), real UIDs fed in deliberately.
        let thunderboltSwitches = loadThunderboltSwitches(folder: folder)
        sensitiveIdentifiers.append(contentsOf: thunderboltSwitches.map { String($0.id) })

        // USB devices (probe 38)
        let usbDevices = loadUSBDevices(folder: folder)

        let snapshot = CableSnapshot(
            ports: ports,
            powerSources: powerSources,
            identities: identities,
            usbDevices: usbDevices,
            adapter: nil,
            thunderboltSwitches: thunderboltSwitches,
            isDesktopMac: false,
            federatedIdentities: [],
            usb3Transports: usb3Transports,
            trmTransports: trmTransports,
            cioCapabilities: cioCapabilities,
            typeCPhys: [],
            displayPorts: []
        )
        return AssembledSnapshot(snapshot: snapshot, sensitiveIdentifiers: sensitiveIdentifiers)
    }

    // MARK: - Corpus sweep

    @Test("Render sweep: every folder with probe 01 renders via JSON and Text with no crash, valid JSON, full port coverage, and no UUID/UID leak")
    func renderSweepNoCrashValidJSONFullCoverageNoLeak() throws {
        var foldersWithProbe01 = 0
        var foldersRendered = 0
        var jsonParseFailures = 0
        var portCoverageFailures = 0
        var leakDetections = 0

        for folder in Self.allProbeFolders() {
            guard Self.loadProbeText(folder: folder, fileName: "01_walk_pd_tree.json") != nil else { continue }
            foldersWithProbe01 += 1

            guard let assembled = Self.assembleSnapshot(folder: folder) else { continue }
            let snapshot = assembled.snapshot
            foldersRendered += 1

            // Render with showRaw: true deliberately -- the raw-properties
            // path is the highest-risk path for a UUID leak (rawProperties
            // vs redactedRawProperties), so exercising it here is the
            // meaningful version of the privacy check, not the safe default.
            let jsonString: String
            do {
                jsonString = try JSONFormatter.render(
                    ports: snapshot.ports, sources: snapshot.powerSources, identities: snapshot.identities,
                    showRaw: true, adapter: snapshot.adapter, thunderboltSwitches: snapshot.thunderboltSwitches,
                    isDesktopMac: snapshot.isDesktopMac, batteryFullyCharged: snapshot.batteryFullyCharged,
                    batteryIsCharging: snapshot.batteryIsCharging, federatedIdentities: snapshot.federatedIdentities,
                    usb3Transports: snapshot.usb3Transports, trmTransports: snapshot.trmTransports,
                    cioCapabilities: snapshot.cioCapabilities, usbDevices: snapshot.usbDevices,
                    displayPorts: snapshot.displayPorts
                )
            } catch {
                Issue.record("\(folder): JSONFormatter.render threw: \(error)")
                continue
            }

            let textString = TextFormatter.render(
                ports: snapshot.ports, sources: snapshot.powerSources, identities: snapshot.identities,
                showRaw: true, adapter: snapshot.adapter, thunderboltSwitches: snapshot.thunderboltSwitches,
                isDesktopMac: snapshot.isDesktopMac, batteryFullyCharged: snapshot.batteryFullyCharged,
                batteryIsCharging: snapshot.batteryIsCharging, federatedIdentities: snapshot.federatedIdentities,
                usb3Transports: snapshot.usb3Transports, cioCapabilities: snapshot.cioCapabilities,
                usbDevices: snapshot.usbDevices, displayPorts: snapshot.displayPorts
            )

            // Invariant 1: JSON output parses back as valid JSON.
            guard let jsonData = jsonString.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                jsonParseFailures += 1
                Issue.record("\(folder): JSONFormatter output did not parse as valid JSON")
                continue
            }

            // Invariant 2: every port appears in both outputs (identified by
            // its serviceName, the label both formatters fall back to).
            let portsArray = parsed["ports"] as? [[String: Any]] ?? []
            if portsArray.count != snapshot.ports.count {
                portCoverageFailures += 1
                Issue.record("\(folder): JSON ports array has \(portsArray.count) entries, expected \(snapshot.ports.count)")
            }
            for port in snapshot.ports {
                if !textString.contains(port.serviceName) {
                    portCoverageFailures += 1
                    Issue.record("\(folder): TextFormatter output missing port \(port.serviceName)")
                }
                let namesInJSON = portsArray.compactMap { $0["name"] as? String }
                if !namesInJSON.contains(where: { $0 == port.portDescription || $0 == port.serviceName }) {
                    portCoverageFailures += 1
                    Issue.record("\(folder): JSON output missing port \(port.serviceName)")
                }
            }

            // Invariant 3: no HPM/Connection UUID or TB UID leaks into either
            // output. Checked against the REAL identifiers fed into this
            // snapshot (probe 35 UUIDs, probe 29 TB UIDs).
            for identifier in assembled.sensitiveIdentifiers {
                guard identifier.count >= 6 else { continue }   // skip trivially-short/zero UIDs that could collide by chance
                let leaked = jsonString.localizedCaseInsensitiveContains(identifier)
                    || textString.localizedCaseInsensitiveContains(identifier)
                if leaked {
                    leakDetections += 1
                    Issue.record("\(folder): a sensitive identifier (\(identifier.prefix(8))...) leaked into rendered output")
                }
            }
        }

        print("[SnapshotRenderSweep] \(foldersWithProbe01) folders with probe 01, "
            + "\(foldersRendered) rendered, \(jsonParseFailures) JSON parse failures, "
            + "\(portCoverageFailures) port-coverage failures, \(leakDetections) leak detections")

        // foldersWithProbe01 >= 350 is safe unconditionally: probe 01 is
        // git-tracked for essentially every folder (409 of 410), so a fresh
        // clone already has ~409 here, well above this floor. No two-tier
        // gating needed for this one specifically.
        #expect(foldersWithProbe01 >= 350,
            "Expected at least 350 folders with a committed probe-01 file; got \(foldersWithProbe01)")

        // Correctness invariants: run whenever ANY snapshot was assembled at
        // all, including a fresh clone where rendering can only draw on the
        // 27 git-tracked probe-17 fixtures. A JSON-validity, port-coverage,
        // or UUID-leak failure is a real bug regardless of corpus size, so
        // these must never be skipped just because the full corpus isn't on
        // disk (unlike the raw-count floor below).
        if foldersRendered > 0 {
            #expect(jsonParseFailures == 0, "JSONFormatter must always produce valid JSON")
            #expect(portCoverageFailures == 0, "every port must appear in both JSON and Text output")
            #expect(leakDetections == 0, "no HPM/Connection UUID or TB UID may appear in rendered output")
        }

        // Coverage floor: actual 409 folders with probe 01, 201 rendered, as
        // of 2026-07 (see printed sweep summary above for this run's exact
        // numbers). probe 01 is committed for every folder (410 total per
        // corpus.jsonl), but rendering also requires at least one real port
        // from probe 17 (gitignored, on-disk only, and not every probe-01
        // folder has a matching probe-17 file), so foldersRendered is
        // naturally well below foldersWithProbe01. Floor set to ~85% of
        // actual (171 of 201).
        //
        // Two-tier reality: only 27 probe-17 files are git-tracked, so
        // `foldersRendered` tops out well below 171 on a fresh clone. Gate on
        // a raw-corpus-presence threshold well above that 27-file case, so a
        // fresh clone SKIPS this floor instead of failing it.
        if foldersRendered >= 50 {
            #expect(foldersRendered >= 171,
                "Expected at least 171 folders to assemble a renderable snapshot; got \(foldersRendered)")
        }
    }

    // MARK: - Fixture: minimal two-port snapshot renders cleanly
    //
    // A small deterministic fixture so this suite always has coverage even
    // on a fresh clone with no corpus on disk (the sweep above trivially
    // passes with zero folders in that case).
    @Test("Fixture: minimal snapshot with one USB-C port and one power source renders via both formatters")
    func fixtureMinimalSnapshotRenders() throws {
        let props: [String: Any] = [
            "PortTypeDescription": "USB-C", "PortNumber": NSNumber(value: 1),
            "PortType": NSNumber(value: 0x2), "ConnectionActive": NSNumber(value: true),
            "TransportsSupported": ["USB2", "USB3"] as [Any],
        ]
        let port = AppleHPMInterface.from(
            entryID: 1, serviceName: "Port-USB-C@1", className: "AppleHPMInterfaceType10",
            read: { props[$0] }, hpmControllerUUID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )
        #expect(port != nil)

        let source = PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1, options: [],
            winning: PowerOption(voltageMV: 20_000, maxCurrentMA: 3_250, maxPowerMW: 65_000)
        )

        let json = try JSONFormatter.render(
            ports: [port!], sources: [source], identities: [], showRaw: true
        )
        let text = TextFormatter.render(
            ports: [port!], sources: [source], identities: [], showRaw: true
        )

        #expect(json.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } != nil)
        #expect(text.contains("Port-USB-C@1"))
        #expect(!json.localizedCaseInsensitiveContains("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        #expect(!text.localizedCaseInsensitiveContains("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
    }
}
