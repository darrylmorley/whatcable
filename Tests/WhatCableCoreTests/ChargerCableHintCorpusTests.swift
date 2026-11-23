import Foundation
import Testing
@testable import WhatCableCore

/// Corpus replay for the #672 cable hint (`ChargingDiagnostic`'s
/// `.possibleCableLimit` arm, gated by `ChargerCableHint`).
///
/// Every customer-probe folder is rebuilt into the inputs `ChargingDiagnostic`
/// takes in production, as far as probe text allows, one case per USB-C port
/// holding a live USB-PD contract:
///
/// - `port`: `Port-USB-C@N`, N from the probe 17 `IOPortFeaturePowerSource`
///   whose `WinningPowerSourceOption` is above 0 mW (dash or nested block).
/// - `sources`: one USB-PD source. `winning` is that option. `options` are the
///   charger's offers. Probe 17 prints `PowerSourceOptions` as an opaque
///   `<CFType 17>`, so the offers come from probe 19's raw
///   `PortControllerInfo` PDO words instead, decoded through the production
///   `PDO.decode` + `PowerSourceSynthesis.option`, every slot including the EPR
///   ones. The entry is the one live entry whose `maxPower` is within 500 mW of
///   the winning option's power; a port with no unique match is not replayed. macOS 15
///   publishes no PDO words, so an entry with none falls back to probe 19's
///   decoded HVC menu (which omits EPR; a charger capped at 3 A has no EPR
///   offer to omit).
/// - `identities`: probe 01 SOP' / SOP'' nodes on that port, with their VDOs.
/// - `accessoryIdentity`: probe 17 `IOPortTransportProtocolAppleUVDM` on that port.
/// - `adapter`: probe 32 `AdapterDetails` (Name, Manufacturer, Watts).
/// - `anotherPortActivelyCharging`: another USB-C port in the same capture
///   also holds a live contract.
///
/// The Python cross-check (a second parser that reads probe 19's decoded text,
/// not its raw words) found the same 8 signature folders on 2026-11-21. Seven
/// of them reach the diagnostic. The eighth, `m4_macos15.7.7`, shows the
/// signature in PortControllerInfo and AdapterDetails, but macOS 15.7.7
/// published no USB-PD power-source node for that port (only Brick ID and
/// TypeC, neither with a winning option), so `ChargingDiagnostic` sees no
/// contract there and cannot fire. Pinned below so a change in that is seen.
@Suite("Charger cable hint (#672): corpus replay")
struct ChargerCableHintCorpusTests {

    // MARK: - Expectations

    /// The signature captures that reach the diagnostic: an Apple charger
    /// rated well above 60 W, every offer at 3 A or less, and no e-marker
    /// read. Folder -> (rated W, offered W).
    static let signature: [String: (rated: Int, offered: Int)] = [
        "m2_macos26.3.1": (70, 60),
        "m2_macos26.5.2_b": (140, 60),
        "m2_macos26.5.2_j": (67, 60),
        "m2_macos26.6_e": (67, 60),
        "m2pro_macos26.5.1": (67, 60),
        "m4pro_macos26.5.2_k": (70, 60),
        "m4pro_macos26.6.2_k": (70, 60),
    ]

    /// The eighth signature capture (96 W at 20 V x 3 A): no USB-PD node in
    /// probe 17, so no contract for the diagnostic to judge. See the type doc.
    static let signatureWithoutUSBPDNode = "m4_macos15.7.7"

    /// Dual-port 35 W chargers splitting power: named in the ticket as must-stay-silent.
    static let dualPort35W: Set<String> = [
        "m3_macos26.5_f", "m3_macos26.6.1", "m3_macos27.0_i", "m3_macos27.0_j", "m4pro_macos27.0_w",
    ]

    // MARK: - Case building

    struct Case {
        let folder: String
        let portType: Int
        let portNumber: Int
        let chargerName: String?
        let diagnostic: ChargingDiagnostic?
    }

    struct WinningSource {
        let portType: Int
        let portNumber: Int
        let winning: PowerOption
    }

    static let cases: [Case] = ProbeCorpus.allFolders().flatMap(buildCases(folder:))

    static func buildCases(folder: String) -> [Case] {
        guard let text17 = ProbeCorpus.loadText(folder: folder, probe: "17_deep_property_dump"),
              let text19 = ProbeCorpus.loadText(folder: folder, probe: "19_pdo_decode_and_usb3_watch")
        else { return [] }

        // MagSafe is replayed too, so the silence there is shown, not assumed.
        let winners = winningUSBPDSources(text17: text17)
        guard !winners.isEmpty else { return [] }
        let entries = liveControllerEntries(text19: text19)
        let adapter = adapterInfo(folder: folder)
        let uvdm = uvdmIdentities(text17: text17)
        let ids = cableIdentities(folder: folder)

        var out: [Case] = []
        for w in winners {
            // PortControllerMaxPower is the precise figure (17280 mW) where the
            // winning option is rounded (17200 mW), so match within 500 mW. One
            // winner and one live entry pair up regardless.
            var matches = entries.filter { abs($0.maxPowerMW - w.winning.maxPowerMW) <= 500 }
            if matches.isEmpty, winners.count == 1, entries.count == 1 { matches = entries }
            guard matches.count == 1 else { continue }   // cannot attribute the offers
            let port = makePort(type: w.portType, number: w.portNumber)
            let source = PowerSource(
                id: UInt64(5000 + w.portNumber), name: "USB-PD",
                parentPortType: w.portType, parentPortNumber: w.portNumber,
                options: matches[0].offers, winning: w.winning)
            let accessory = uvdm.first { $0.portKey == "\(w.portType)/\(w.portNumber)" }
            let another = winners.contains { $0.portType != w.portType || $0.portNumber != w.portNumber }
            let isUSBC = w.portType == PortIdentity.usbCTypeCode
            let diag = ChargingDiagnostic(
                port: port, sources: [source],
                identities: isUSBC ? ids.filter { $0.parentPortNumber == w.portNumber } : [],
                adapter: adapter,
                anotherPortActivelyCharging: another,
                accessoryIdentity: accessory)
            let name = ChargerCableHint.chargerName(
                accessory: accessory, adapter: adapter,
                portHasLiveContract: true, anotherPortActivelyCharging: another)
            out.append(Case(folder: folder, portType: w.portType, portNumber: w.portNumber,
                            chargerName: name, diagnostic: diag))
        }
        return out
    }

    // MARK: - Tests

    @Test("Exactly the 7 reachable signature captures fire, with the expected wattages")
    func signatureFoldersFire() {
        guard !Self.cases.isEmpty else {
            Issue.record("corpus not linked: run scripts/link-research.sh"); return
        }
        var fired: [String: (Int, Int)] = [:]
        for c in Self.cases {
            if case .possibleCableLimit(let offered, let rated, _) = c.diagnostic?.bottleneck {
                #expect(fired[c.folder] == nil, "\(c.folder) fired on two ports")
                fired[c.folder] = (rated, offered)
            }
        }
        #expect(Set(fired.keys) == Set(Self.signature.keys),
                "fired: \(fired.keys.sorted()) expected: \(Self.signature.keys.sorted())")
        for (folder, want) in Self.signature {
            guard let got = fired[folder] else { continue }
            #expect(got.0 == want.rated && got.1 == want.offered,
                    "\(folder): got rated \(got.0) offered \(got.1), want \(want.rated)/\(want.offered)")
        }
    }

    @Test("Every signature capture is replayed and was silent before #672 (no e-marker read)")
    func signatureFoldersHadNoEmarker() {
        for folder in Self.signature.keys.sorted() {
            let replayed = Self.cases.filter { $0.folder == folder }
            #expect(!replayed.isEmpty, "\(folder) not replayed")
            for c in replayed { #expect(c.diagnostic?.cableW == nil, "\(folder): e-marker rating was read") }
        }
    }

    @Test("Named false-positive classes stay silent, and each class was actually replayed")
    func falsePositiveClassesStaySilent() {
        func fires(_ c: Case) -> Bool {
            if case .possibleCableLimit = c.diagnostic?.bottleneck { return true }
            return false
        }
        func rated(_ c: Case) -> Int? { ChargerCableHint.ratedWatts(appleChargerName: c.chargerName) }

        // 61 W / 60 W Apple chargers (normal 20 V x 3 A).
        let w61 = Self.cases.filter { [60, 61].contains(rated($0)) }
        // 140 W in normal use: 20 V above 3 A (the HVC menu omits the 28 V offer).
        let w140 = Self.cases.filter { rated($0) == 140 && Self.signature[$0.folder] == nil }
        // Apple chargers rated 65 W+ in normal use, name 1 to 4 W above the top offer.
        let normalHigh = Self.cases.filter { (rated($0) ?? 0) >= 65 && Self.signature[$0.folder] == nil }
        // The five named dual-port 35 W captures.
        let dual = Self.cases.filter { Self.dualPort35W.contains($0.folder) }

        #expect(!w61.isEmpty && !w140.isEmpty && !normalHigh.isEmpty,
                "a false-positive class replayed nothing: 61W \(w61.count), 140W \(w140.count), normal \(normalHigh.count)")
        // Every named dual-port folder must actually be replayed, not skipped.
        #expect(Set(dual.map(\.folder)) == Self.dualPort35W,
                "dual-port folders replayed: \(Set(dual.map(\.folder)).sorted())")
        for c in w61 + w140 + normalHigh + dual {
            #expect(!fires(c), "\(c.folder) port \(c.portNumber) fired (\(c.chargerName ?? "nil"))")
        }
        // The 143 W iMac supply has no USB-PD contract, so it never reaches a
        // case; its name is not a USB-C Power Adapter either.
        #expect(ChargerCableHint.ratedWatts(appleChargerName: "143W Power Adapter") == nil)
        print("[#672 corpus] cases \(Self.cases.count); silent 61/60W \(w61.count), 140W \(w140.count), 65W+ normal \(normalHigh.count), dual-35W \(dual.count) (folders \(Set(dual.map(\.folder)).sorted()))")
    }

    @Test("m4_macos15.7.7 shows the signature but has no USB-PD node, so it is not replayed")
    func signatureWithoutNodeIsUnreachable() {
        let folder = Self.signatureWithoutUSBPDNode
        guard let text17 = ProbeCorpus.loadText(folder: folder, probe: "17_deep_property_dump"),
              let text19 = ProbeCorpus.loadText(folder: folder, probe: "19_pdo_decode_and_usb3_watch")
        else { Issue.record("\(folder) probes missing: run scripts/link-research.sh"); return }
        // The signature is in the data: one live entry, offers all 3 A, top 60 W,
        // and AdapterDetails names a 96 W Apple charger.
        let entries = Self.liveControllerEntries(text19: text19)
        #expect(entries.count == 1)
        #expect(entries.first.map { ChargerCableHint.evaluate(
            chargerName: Self.adapterInfo(folder: folder)?.name,
            source: PowerSource(id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 2,
                                options: $0.offers, winning: nil)) }
                == ChargerCableHint(chargerRatedW: 96, offeredW: 60))
        // But no USB-PD source with a winning option, so no case is built.
        #expect(Self.winningUSBPDSources(text17: text17).isEmpty)
        #expect(Self.cases.filter { $0.folder == folder }.isEmpty)
    }

    // MARK: - Probe 17: winning USB-PD sources

    static func winningUSBPDSources(text17: String) -> [WinningSource] {
        var bodies: [String] = []
        // Flat dash blocks and nested "=== IOPortFeaturePowerSource ===" blocks.
        for header in [#"--- IOPortFeaturePowerSource\[\d+\] ---"#, #"=== IOPortFeaturePowerSource ==="#] {
            let re = try! NSRegularExpression(pattern: header)
            let ns = text17 as NSString
            let ms = re.matches(in: text17, range: NSRange(location: 0, length: ns.length))
            for m in ms {
                let start = m.range.upperBound
                let rest = ns.substring(from: start)
                var end = rest.count
                for sep in ["\n--- ", "=== "] {
                    if let r = rest.range(of: sep) { end = min(end, rest.distance(from: rest.startIndex, to: r.lowerBound)) }
                }
                bodies.append(String(rest.prefix(end)))
            }
        }
        var seen = Set<Int>()
        var out: [WinningSource] = []
        for b in bodies {
            guard b.contains(#"PowerSourceName: "USB-PD""#),
                  let winStart = b.range(of: "WinningPowerSourceOption: {") else { continue }
            let win = String(b[winStart.upperBound...].prefix { $0 != "}" })
            guard let mw = intAfter("Max Power (mW): ", in: win), mw > 0,
                  let mv = intAfter("Voltage (mV): ", in: win) else { continue }
            let ma = intAfter("Max Current (mA): ", in: win) ?? 0
            let type = intAfter("ParentBuiltInPortType: ", in: b) ?? intAfter("ParentPortType: ", in: b) ?? 2
            guard let number = intAfter("ParentBuiltInPortNumber: ", in: b) ?? intAfter("ParentPortNumber: ", in: b),
                  seen.insert(type * 1000 + number).inserted else { continue }
            out.append(WinningSource(portType: type, portNumber: number,
                                     winning: PowerOption(voltageMV: mv, maxCurrentMA: ma, maxPowerMW: mw, supplyKind: .fixed)))
        }
        return out
    }

    // MARK: - Probe 19: live PortControllerInfo entries

    struct ControllerEntry {
        let maxPowerMW: Int
        let offers: [PowerOption]
    }

    static func liveControllerEntries(text19: String) -> [ControllerEntry] {
        let parts = text19.components(separatedBy: "AdapterDetails:")
        let controllerText = parts[0]
        let hvcText = parts.count > 1 ? parts[1].components(separatedBy: "=====")[0] : ""
        let hvc: [PowerOption] = matches(#"\[\d+\] (\d+)mV / (\d+)mA"#, in: hvcText).compactMap { g in
            guard let v = Int(g[0]), let i = Int(g[1]), v > 0, i > 0 else { return nil }
            return PowerOption(voltageMV: v, maxCurrentMA: i, maxPowerMW: v * i / 1000, supplyKind: .fixed)
        }
        var out: [ControllerEntry] = []
        for chunk in controllerText.components(separatedBy: "\n  Port ").dropFirst() {
            guard let mp = intAfter("maxPower=", in: chunk), mp > 0 else { continue }
            let words = matches(#"PDO\[\d+\] = 0x([0-9a-fA-F]+)"#, in: chunk).compactMap { UInt32($0[0], radix: 16) }
            let offers = words.compactMap { PowerSourceSynthesis.option(for: PDO.decode(rawValue: $0)) }
            out.append(ControllerEntry(maxPowerMW: mp, offers: words.isEmpty ? hvc : offers))
        }
        return out
    }

    // MARK: - Probe 32: AdapterDetails

    static func adapterInfo(folder: String) -> AdapterInfo? {
        // The top-level key only, at two spaces. "AppleRawAdapterDetails ="
        // contains the same substring and comes first; nested copies sit deeper.
        guard let text = ProbeCorpus.loadText(folder: folder, probe: "32_smart_battery_full_keys"),
              let r = text.range(of: "\n  AdapterDetails =") else { return nil }
        var seg = ""
        for line in text[r.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            if line.hasPrefix("  "), !line.hasPrefix("   ") { break }   // next top-level key
            seg += "\n" + line
        }
        let name = matches(#"\n\s+Name =\s+"([^"]*)""#, in: seg).first?[0]
        let maker = matches(#"\n\s+Manufacturer =\s+"([^"]*)""#, in: seg).first?[0]
        let watts = matches(#"\n\s+Watts =\s+(\d+)"#, in: seg).first.flatMap { Int($0[0]) }
        return AdapterInfo(watts: watts, isCharging: nil, source: "AC", manufacturer: maker, name: name)
    }

    // MARK: - Probe 17: Apple UVDM identity

    static func uvdmIdentities(text17: String) -> [AppleAccessoryIdentity] {
        var out: [AppleAccessoryIdentity] = []
        for chunk in text17.components(separatedBy: "=== IOPortTransportProtocolAppleUVDM ===").dropFirst() {
            let body = chunk.components(separatedBy: "===")[0]
            guard let n = intAfter("ParentPortNumber: ", in: body) else { continue }
            let t = intAfter("ParentBuiltInPortType: ", in: body) ?? intAfter("ParentPortType: ", in: body) ?? 2
            out.append(AppleAccessoryIdentity(
                id: UInt64(6000 + out.count), portKey: "\(t)/\(n)",
                manufacturer: matches(#"Manufacturer: "([^"]*)""#, in: body).first?[0],
                vendor: nil,
                product: matches(#"\bProduct: "([^"]*)""#, in: body).first?[0],
                userString: matches(#"User String: "([^"]*)""#, in: body).first?[0],
                model: nil, serialNumber: nil, hardwareVersion: nil,
                vendorID: intAfter("Vendor ID: ", in: body),
                productID: intAfter("Product ID: ", in: body)))
        }
        return out
    }

    // MARK: - Probe 01: cable e-marker identities

    static func cableIdentities(folder: String) -> [USBPDSOP] {
        guard let text = ProbeCorpus.loadText(folder: folder, probe: "01_walk_pd_tree") else { return [] }
        var out: [USBPDSOP] = []
        for block in text.components(separatedBy: "=== ").dropFirst() where block.contains("CCUSBPDSOP") {
            guard let name = matches(#"Name:\s+(\S+)"#, in: block).first?[0],
                  name == "SOP'" || name == "SOP''",
                  let port = matches(#"Description = "Port-USB-C@(\d+)/CC"#, in: block).first.flatMap({ Int($0[0]) })
            else { continue }
            let vdos = matches(#"\[\d+\] <data 4 bytes: ([0-9a-fA-F ]+)>"#, in: block).map { g -> UInt32 in
                g[0].split(separator: " ").compactMap { UInt32($0, radix: 16) }
                    .reversed().reduce(UInt32(0)) { ($0 << 8) | $1 }
            }
            out.append(USBPDSOP(
                id: UInt64(7000 + out.count), endpoint: name == "SOP'" ? .sopPrime : .sopDoublePrime,
                parentPortType: 2, parentPortNumber: port, vendorID: 0, productID: 0, bcdDevice: 0,
                vdos: vdos, specRevision: 3))
        }
        return out
    }

    // MARK: - Helpers

    static func makePort(type: Int, number: Int) -> USBCPort {
        let magSafe = type == PortIdentity.magSafeTypeCode
        return USBCPort(
            id: UInt64(type * 1000 + number),
            serviceName: magSafe ? "Port-MagSafe 3@\(number)" : "Port-USB-C@\(number)",
            className: magSafe ? "AppleHPMInterfaceType11" : "AppleHPMInterfaceType10",
            portDescription: nil, portTypeDescription: magSafe ? "MagSafe 3" : "USB-C", portNumber: number,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: ["PortType": String(type)])
    }

    static func intAfter(_ key: String, in text: String) -> Int? {
        guard let r = text.range(of: key) else { return nil }
        let digits = text[r.upperBound...].prefix { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    /// Capture groups (1...) of every match.
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (1..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }
}
