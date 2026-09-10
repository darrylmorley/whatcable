import Foundation
import Testing
@testable import WhatCableDarwinBackend
import WhatCableCore

/// Corpus-replay tests for PowerService's pure parsing helpers (DAR-77).
///
/// Coverage is two-layered:
///
/// 1. Fixture tests (always run): hand-crafted PDO/RDO values and
///    PowerOutDetails / PortControllerInfo shapes that exercise the
///    parsing paths without any live IOKit or @MainActor isolation.
///
/// 2. Corpus sweep (runs only when probe-32 files are on disk): sweeps
///    every `research/customer-probes/<folder>/32_smart_battery_full_keys.json`
///    and calls the parsing helpers against real PortControllerInfo /
///    PowerOutDetails shapes. Passes trivially on a fresh clone.
///
/// Helpers under test (all `nonisolated static` on `PowerService`):
///   - `decodeNegotiatedContract(pdoList:maxPowerMW:operatingCurrentMA:)`
///   - `rdoSelectedPdoType(rdo:pdoList:)`
///   - `portPowerSamples(from:portKeys:)`
///   - `portPowerSamplesFromControllerInfo(_:sources:)`
@Suite("PowerTelemetry parsing (DAR-77)")
struct PowerTelemetryParsingTests {

    // MARK: - Probe root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // MARK: - Corpus helpers

    private static func allProbes() throws -> [String] {
        guard FileManager.default.fileExists(atPath: probeRoot.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path)
            .filter { entry in
                var isDir: ObjCBool = false
                let path = probeRoot.appendingPathComponent(entry).path
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                return isDir.boolValue
            }
            .sorted()
    }

    /// Load the output text from a probe-32 JSON (AppleSmartBattery full keys).
    /// Returns nil when the file is absent (fresh clone).
    private static func loadProbe32(folder: String) throws -> String? {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("32_smart_battery_full_keys.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Probe-32 text parsers
    //
    // Probe-32 is a free-text dump via `printCFType`. Arrays appear as:
    //   Array[N]:
    //     [0] Dict[M]:
    //       KEY = VALUE
    //     [1] Dict[M]:
    //       ...
    // Numbers appear as "N (0xHEX)" or just "N".
    // We do a best-effort extraction just sufficient to call the helpers.

    /// Extract integer values from a named "Array[N]:" section in probe-32 text.
    /// Returns the raw NSNumber array items, suitable for passing as `pdoList`.
    ///
    /// Real probe-32 format: "  KEY =     Array[N]:" (multiple spaces between = and Array).
    private static func extractArray(_ text: String, key: String) -> [Any] {
        // Search for the key prefix only; the "=   Array[" spacing varies.
        let headerPrefix = "  \(key) = "
        guard let prefixRange = text.range(of: headerPrefix) else { return [] }
        // Advance to the line end to start scanning from the next line.
        let lineStart = text[prefixRange.lowerBound...]
        guard let newline = lineStart.firstIndex(of: "\n") else { return [] }
        let after = text[text.index(after: newline)...]

        var result: [Any] = []
        let lines = String(after).components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Array items start with "[N] " followed by either Dict or a value.
            if trimmed.hasPrefix("[") {
                let afterBracket = trimmed.dropFirst()
                if let close = afterBracket.firstIndex(of: "]") {
                    let rest = afterBracket[afterBracket.index(after: close)...].trimmingCharacters(in: .whitespaces)
                    if let n = parseFirstInt(from: rest) {
                        result.append(NSNumber(value: n))
                    }
                }
            } else if !trimmed.hasPrefix(" ") && !trimmed.isEmpty {
                // Indent dropped back: end of array.
                break
            }
        }
        return result
    }

    /// Parse the first integer from a string like "N (0xHEX)" or just "N".
    private static func parseFirstInt(from s: String) -> Int? {
        let trimmed = s.drop(while: { $0 == " " })
        let digits = trimmed.prefix { c in c.isNumber || c == "-" }
        return Int(digits)
    }

    /// Extract a top-level integer field by key from probe-32 text.
    /// Real probe-32 format: "  KEY =     N (0xHEX)" with multiple spaces between = and N.
    private static func extractInt(_ text: String, key: String) -> Int? {
        let prefix = "  \(key) = "
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(prefix) {
                // Skip any spaces between the prefix and the integer value.
                let rest = line.dropFirst(prefix.count).drop(while: { $0 == " " })
                let digits = rest.prefix { c in c.isNumber || c == "-" }
                return Int(digits)
            }
        }
        return nil
    }

    /// Locate the start of a top-level array section in probe-32 output.
    /// Probe-32 format: "  KEY =     Array[N]:" (spaces between = and Array).
    /// Returns the substring starting after the Array header line.
    private static func findArraySection(_ text: String, key: String) -> String? {
        let prefix = "  \(key) = "
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(prefix) {
                let rest = line.dropFirst(prefix.count).drop(while: { $0 == " " })
                if rest.hasPrefix("Array[") {
                    // Found the header line; find its position in the original text
                    // and return everything after it.
                    if let range = text.range(of: line) {
                        let afterLine = text[range.upperBound...]
                        if afterLine.hasPrefix("\n") {
                            return String(afterLine.dropFirst())
                        }
                        return String(afterLine)
                    }
                }
            }
        }
        return nil
    }

    /// Extract PortControllerInfo-style array from probe-32 output.
    /// Returns one [String: Any] per array element (best-effort).
    ///
    /// Real format: "  PortControllerInfo =     Array[N]:" with dict items
    /// indented as "      [N]         Dict[M]:" and keys as
    /// "          PortControllerKEY =             VALUE (0xHEX)".
    private static func extractPortControllerInfoItems(_ text: String) -> [[String: Any]] {
        guard let after = findArraySection(text, key: "PortControllerInfo") else { return [] }
        var items: [[String: Any]] = []
        var current: [String: Any] = [:]
        var inItem = false

        for line in after.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Dict item header: "[N]         Dict[M]:" after trimming.
            // Multiple spaces may appear between "]" and "Dict[", so check
            // for "[" prefix and "Dict[" anywhere in the trimmed string.
            if trimmed.hasPrefix("[") && trimmed.contains("Dict[") {
                if inItem { items.append(current) }
                current = [:]
                inItem = true
            } else if inItem && trimmed.hasPrefix("PortController") {
                // Key line: "PortControllerMaxPower =             0 (0x0)"
                // Split on first " = " only; value follows after optional spaces.
                if let eqRange = trimmed.range(of: " = ") {
                    let key = String(trimmed[..<eqRange.lowerBound])
                    let valStr = String(trimmed[eqRange.upperBound...]).drop(while: { $0 == " " })
                    if let n = parseFirstInt(from: String(valStr)) {
                        current[key] = NSNumber(value: n)
                    }
                }
            } else if inItem && !trimmed.hasPrefix(" ") && !trimmed.isEmpty && !trimmed.hasPrefix("[") {
                // Indent dropped: end of array.
                break
            }
        }
        if inItem { items.append(current) }
        return items
    }

    /// Extract PowerOutDetails array from probe-32 output.
    ///
    /// Real format: "  PowerOutDetails =     Array[N]:" with dict items
    /// indented as "      [N]         Dict[M]:" and keys as
    /// "          KEY =             VALUE (0xHEX)".
    private static func extractPowerOutDetailsItems(_ text: String) -> [[String: Any]] {
        guard let after = findArraySection(text, key: "PowerOutDetails") else { return [] }
        var items: [[String: Any]] = []
        var current: [String: Any] = [:]
        var inItem = false

        let interestingKeys: Set<String> = [
            "PortIndex", "Watts", "Current", "ConfiguredVoltage", "ConfiguredCurrent",
            "AdapterVoltage", "VConnCurrent", "VConnPower", "PowerState", "PortType"
        ]

        for line in after.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Dict item header: "[N]         Dict[M]:" with multiple spaces.
            if trimmed.hasPrefix("[") && trimmed.contains("Dict[") {
                if inItem { items.append(current) }
                current = [:]
                inItem = true
            } else if inItem {
                // Key line: "KEY =             VALUE (0xHEX)"
                guard let eqRange = trimmed.range(of: " = ") else { continue }
                let key = String(trimmed[..<eqRange.lowerBound])
                guard interestingKeys.contains(key) else { continue }
                let valStr = String(trimmed[eqRange.upperBound...]).drop(while: { $0 == " " })
                if let n = parseFirstInt(from: String(valStr)) {
                    current[key] = NSNumber(value: n)
                }
            }
        }
        if inItem { items.append(current) }
        return items
    }

    // MARK: - Corpus sweep

    @Test("Corpus sweep: probe-32 PortControllerInfo items produce samples without crashing")
    func probe32SweepPortControllerInfo() throws {
        let folders = try Self.allProbes()
        var foldersWithProbe32 = 0
        var totalSamplesProduced = 0
        var foldersWithItems = 0
        var foldersWithSamples = 0

        for folder in folders {
            guard let text = try Self.loadProbe32(folder: folder) else { continue }
            foldersWithProbe32 += 1

            let items = Self.extractPortControllerInfoItems(text)
            guard !items.isEmpty else { continue }
            foldersWithItems += 1

            // Build a minimal sources array: one winning source per non-zero
            // max-power item so the helpers have something to join against.
            var sources: [PowerSource] = []
            for (i, item) in items.enumerated() {
                let maxPower = (item["PortControllerMaxPower"] as? NSNumber)?.intValue ?? 0
                guard maxPower > 0 else { continue }
                sources.append(PowerSource(
                    id: UInt64(i + 1),
                    name: "USB-PD",
                    parentPortType: 2,
                    parentPortNumber: i + 1,
                    options: [],
                    winning: PowerOption(
                        voltageMV: 20_000,
                        maxCurrentMA: maxPower / 20,
                        maxPowerMW: maxPower
                    )
                ))
            }

            let samples = PowerService.portPowerSamplesFromControllerInfo(
                items as Any, sources: sources
            )
            totalSamplesProduced += samples.count
            if !samples.isEmpty { foldersWithSamples += 1 }

            for sample in samples {
                // Watts must be non-negative (a port at 0W is valid).
                //
                // Note: `sample.watts` here is `winning.maxPowerMW` (see
                // portPowerSamplesFromControllerInfo) -- despite the field
                // name, it is milliwatts on this path, confirmed by a corpus
                // max of 140000 (140W EPR MagSafe, a real and unremarkable
                // value once read as mW).
                //
                // The 2026-07 hardening pass rejected a "sane wattage
                // ceiling" invariant here on the grounds that the field
                // "isn't consistently watts across call sites". That premise
                // was wrong and is retracted (2026-09-03): the other path is
                // milliwatts too. Its corpus max of 15543 is 15.5W on a 15W
                // contract, not a rogue unit. See probe32SweepPowerOutDetails
                // below. A physical ceiling is therefore a real invariant now
                // and worth adding, but it is new behaviour and needs its own
                // watched-red run, so it stays out of the labelling fix that
                // corrected this comment. Non-negativity is what this sweep
                // asserts today.
                #expect(sample.watts >= 0,
                    "Folder \(folder): negative watts \(sample.watts) from PortControllerInfo")
                // portKey must be non-empty.
                #expect(!sample.portKey.isEmpty,
                    "Folder \(folder): empty portKey in PortControllerInfo sample")
            }
        }

        // Minimum guard: only enforced when probe-32 files exist on disk.
        // Most machines are laptops with a battery and PortControllerInfo.
        // Desktop machines may legitimately have no PortControllerInfo. This
        // is a weak "some data parsed" sanity check, not a raw-count floor,
        // so it keeps running against whatever is on disk -- tracked-only
        // fixtures or the full corpus alike.
        if foldersWithProbe32 > 0 {
            // At least some folders must contain parseable PortControllerInfo.
            #expect(foldersWithItems > 0,
                "Expected to find PortControllerInfo data in at least some probe-32 files; foldersWithProbe32=\(foldersWithProbe32)")
        }

        // Parse-coverage floor: actual 276 of 387 probe-32 folders yield at
        // least one charge-contract sample, as of 2026-07. Floor set to
        // ~87% of actual (240). This is stronger than the "some folders"
        // check above: it catches a regression that still produces a few
        // items but silently stops joining most of them to a source.
        //
        // Two-tier reality: only 12 probe-32 files are git-tracked, out of
        // ~387 on disk. Gate on a raw-corpus-presence threshold (50) well
        // above that 12-file fresh-clone case, so a fresh clone SKIPS this
        // floor instead of failing it.
        if foldersWithProbe32 >= 50 {
            #expect(foldersWithSamples >= 240,
                "Expected at least 240 folders to yield a PortControllerInfo-derived sample; got \(foldersWithSamples) of \(foldersWithProbe32) probe-32 folders")
        }
    }

    @Test("Corpus sweep: probe-32 PowerOutDetails items produce non-negative watts")
    func probe32SweepPowerOutDetails() throws {
        let folders = try Self.allProbes()
        var foldersWithData = 0
        var totalSamplesProduced = 0
        var foldersWithSamples = 0

        for folder in folders {
            guard let text = try Self.loadProbe32(folder: folder) else { continue }
            let items = Self.extractPowerOutDetailsItems(text)
            guard !items.isEmpty else { continue }
            foldersWithData += 1

            // portPowerSamples expects the raw array as Any? plus portKeys.
            // Pass an empty portKeys: the helper uses fallback "2/N" keys.
            let samples = PowerService.portPowerSamples(
                from: items as Any, portKeys: []
            )
            totalSamplesProduced += samples.count
            if !samples.isEmpty { foldersWithSamples += 1 }

            for sample in samples {
                // Note: `sample.watts` here is the raw IOKit "Watts" field
                // (see portPowerSamples). It is milliwatts, not watts, which
                // is why the corpus max of 15543 looks impossible read as
                // watts and is unremarkable read as 15.5W. Swept over every
                // PowerOutDetails entry on disk, Watts tracks AdapterVoltage
                // (mV) x Current (mA) / 1000, and never exceeds its own row's
                // PD contract by more than about 4%.
                //
                // An earlier version of this comment said the unit was not
                // watts and left it there, and used that to reject a physical
                // ceiling. The unit is settled now, so a ceiling is viable;
                // see the longer note in probe32SweepPortControllerInfo above
                // for why it is not being added in the same change.
                #expect(sample.watts >= 0,
                    "Folder \(folder): negative watts \(sample.watts) from PowerOutDetails")
                #expect(!sample.portKey.isEmpty,
                    "Folder \(folder): empty portKey in PowerOutDetails sample")
            }
        }
        print("Probe-32 PowerOutDetails sweep: \(foldersWithData) folders with data, \(totalSamplesProduced) samples")
        // Parse-coverage floor: actual 145 of 410 folders yield at least one
        // PowerOutDetails-derived sample, as of 2026-07 (desktop machines and
        // machines without this optional probe legitimately contribute zero,
        // so this is well under the full corpus size). Floor set to ~86% of
        // actual (125), not the previous "no hard minimum" (purely
        // informational, so a regression that dropped every sample would
        // have passed silently).
        //
        // Two-tier reality: only 12 probe-32 files are git-tracked in total
        // (of which a subset carry PowerOutDetails at all), out of ~387 on
        // disk. Gate on a raw-corpus-presence threshold (50) well above that
        // fresh-clone case, so a fresh clone SKIPS this floor instead of
        // failing it.
        if foldersWithData >= 50 {
            #expect(foldersWithSamples >= 125,
                "Expected at least 125 folders to yield a PowerOutDetails-derived sample; got \(foldersWithSamples) of \(foldersWithData) folders with PowerOutDetails data")
        }
    }

    // MARK: - decodeNegotiatedContract fixture tests

    /// Encode a fixed-supply PDO. Voltage in 50 mV units (bits 19:10),
    /// current in 10 mA units (bits 9:0). Bits 31:30 = 00 (fixed).
    private func fixedPDO(voltageMV: Int, currentMA: Int) -> NSNumber {
        let voltageUnits = UInt32(voltageMV / 50) & 0x3FF
        let currentUnits = UInt32(currentMA / 10) & 0x3FF
        let raw: UInt32 = (voltageUnits << 10) | currentUnits
        return NSNumber(value: raw)
    }

    /// A simple charger: 20V / 5A = 100W.
    private var singlePDOList: [Any] {
        [fixedPDO(voltageMV: 20_000, currentMA: 5_000)]
    }

    @Test("decodeNegotiatedContract: single fixed PDO at exact wattage")
    func decodeContractSinglePDO() {
        let result = PowerService.decodeNegotiatedContract(
            pdoList: singlePDOList as Any,
            maxPowerMW: 100_000,
            operatingCurrentMA: 0
        )
        #expect(result != nil)
        // Voltage must be in a plausible USB PD range: 5-48V.
        let voltageMV = result?.voltageMV ?? 0
        #expect(voltageMV >= 5_000, "voltageMV \(voltageMV) below 5V minimum")
        #expect(voltageMV <= 48_000, "voltageMV \(voltageMV) above 48V maximum")
        // Current must be plausible: 0-6.5A.
        let currentMA = result?.currentMA ?? 0
        #expect(currentMA >= 0)
        #expect(currentMA <= 6_500, "currentMA \(currentMA) above 6.5A maximum")
        // Round-trip the watts.
        let decoded = (voltageMV * currentMA) / 1_000
        #expect(abs(decoded - 100_000) <= 1_000,
            "Decoded power \(decoded) mW differs from contract 100000 mW by more than 1 W")
    }

    @Test("decodeNegotiatedContract: returns nil for empty PDO list")
    func decodeContractNilForEmptyPDOList() {
        let result = PowerService.decodeNegotiatedContract(
            pdoList: [] as Any,
            maxPowerMW: 45_000,
            operatingCurrentMA: 0
        )
        #expect(result == nil)
    }

    @Test("decodeNegotiatedContract: returns nil for zero maxPowerMW")
    func decodeContractNilForZeroMaxPower() {
        let result = PowerService.decodeNegotiatedContract(
            pdoList: singlePDOList as Any,
            maxPowerMW: 0,
            operatingCurrentMA: 0
        )
        #expect(result == nil)
    }

    @Test("decodeNegotiatedContract: tie broken by operating current")
    func decodeContractTieBrokenByOperatingCurrent() {
        // Two PDOs at the same wattage (45W): 15V/3A and 20V/2.25A (rounded to 2250 mA).
        let pdo15v3a = fixedPDO(voltageMV: 15_000, currentMA: 3_000)
        let pdo20v2250 = fixedPDO(voltageMV: 20_000, currentMA: 2_250)
        let pdos: [Any] = [pdo15v3a, pdo20v2250]

        // operatingCurrentMA = 3000: should pick the 15V/3A PDO.
        let result3a = PowerService.decodeNegotiatedContract(
            pdoList: pdos as Any,
            maxPowerMW: 45_000,
            operatingCurrentMA: 3_000
        )
        #expect(result3a?.voltageMV == 15_000)
        #expect(result3a?.currentMA == 3_000)
    }

    @Test("decodeNegotiatedContract: tie broken by higher voltage when no operating current")
    func decodeContractTieBrokenByHigherVoltage() {
        let pdo15v3a = fixedPDO(voltageMV: 15_000, currentMA: 3_000)
        let pdo20v2250 = fixedPDO(voltageMV: 20_000, currentMA: 2_250)
        let pdos: [Any] = [pdo15v3a, pdo20v2250]

        // operatingCurrentMA = 0: no operating-current hint, pick higher voltage.
        let result = PowerService.decodeNegotiatedContract(
            pdoList: pdos as Any,
            maxPowerMW: 45_000,
            operatingCurrentMA: 0
        )
        #expect(result?.voltageMV == 20_000,
            "Expected 20V (higher voltage) when tie cannot be broken by operating current")
    }

    @Test("decodeNegotiatedContract: non-fixed PDOs (battery, APDO) are ignored")
    func decodeContractIgnoresNonFixedPDOs() {
        // Battery PDO: bits 31:30 = 01.
        let batteryPDO = NSNumber(value: UInt32(0x1 << 30) | 0x5DC)
        // APDO: bits 31:30 = 11.
        let apdoPDO = NSNumber(value: UInt32(0x3 << 30) | 0x1000)
        let fixedPDO = fixedPDO(voltageMV: 20_000, currentMA: 3_000)
        let pdos: [Any] = [batteryPDO, apdoPDO, fixedPDO]

        let result = PowerService.decodeNegotiatedContract(
            pdoList: pdos as Any,
            maxPowerMW: 60_000,
            operatingCurrentMA: 0
        )
        #expect(result?.voltageMV == 20_000,
            "Non-fixed PDOs must be skipped; only the fixed 20V PDO should match")
    }

    @Test("decodeNegotiatedContract: zero PDO entries are skipped")
    func decodeContractSkipsZeroPDOs() {
        // A zero PDO word is common padding in real PortControllerPortPDO arrays.
        let pdos: [Any] = [NSNumber(value: 0), fixedPDO(voltageMV: 9_000, currentMA: 3_000)]
        let result = PowerService.decodeNegotiatedContract(
            pdoList: pdos as Any,
            maxPowerMW: 27_000,
            operatingCurrentMA: 0
        )
        #expect(result?.voltageMV == 9_000)
    }

    // MARK: - rdoSelectedPdoType fixture tests

    /// Encode a minimal RDO with the given object position (bits 31:28).
    private func rdoWith(objectPosition: Int) -> UInt32 {
        UInt32(objectPosition & 0xF) << 28
    }

    @Test("rdoSelectedPdoType: fixed PDO (bits 31:30 == 00) returns fixedOrVariable")
    func rdoSelectedPdoTypeFixed() {
        let fixedPDO = self.fixedPDO(voltageMV: 20_000, currentMA: 5_000)
        // Object position 1 selects pdos[0].
        let rdo = rdoWith(objectPosition: 1)
        let type = PowerService.rdoSelectedPdoType(rdo: rdo, pdoList: [fixedPDO] as Any)
        #expect(type == .fixedOrVariable)
    }

    @Test("rdoSelectedPdoType: battery PDO (bits 31:30 == 01) returns battery")
    func rdoSelectedPdoTypeBattery() {
        let batteryPDO = NSNumber(value: UInt32(0x1 << 30))
        let rdo = rdoWith(objectPosition: 1)
        let type = PowerService.rdoSelectedPdoType(rdo: rdo, pdoList: [batteryPDO] as Any)
        #expect(type == .battery)
    }

    @Test("rdoSelectedPdoType: APDO (bits 31:30 == 11) returns apdo")
    func rdoSelectedPdoTypeAPDO() {
        let apdoPDO = NSNumber(value: UInt32(0x3 << 30))
        let rdo = rdoWith(objectPosition: 1)
        let type = PowerService.rdoSelectedPdoType(rdo: rdo, pdoList: [apdoPDO] as Any)
        #expect(type == .apdo)
    }

    @Test("rdoSelectedPdoType: object position 0 (no contract) returns fixedOrVariable")
    func rdoSelectedPdoTypeNoContract() {
        let type = PowerService.rdoSelectedPdoType(
            rdo: 0, pdoList: [fixedPDO(voltageMV: 20_000, currentMA: 5_000)] as Any
        )
        #expect(type == .fixedOrVariable)
    }

    @Test("rdoSelectedPdoType: out-of-range position returns fixedOrVariable")
    func rdoSelectedPdoTypeOutOfRange() {
        // PDO list has only 1 entry; position 2 is out-of-range.
        let rdo = rdoWith(objectPosition: 2)
        let type = PowerService.rdoSelectedPdoType(
            rdo: rdo, pdoList: [fixedPDO(voltageMV: 20_000, currentMA: 3_000)] as Any
        )
        #expect(type == .fixedOrVariable)
    }

    // MARK: - portPowerSamples fixture tests

    /// Build a PowerOutDetails-style dict for one port.
    private func portOutDict(
        portIndex: Int,
        watts: Int = 65_000,
        configuredVoltage: Int = 20_000,
        configuredCurrent: Int = 3_250,
        adapterVoltage: Int = 19_500,
        current: Int = 3_100,
        powerState: Int = 3
    ) -> [String: Any] {
        [
            "PortIndex":          NSNumber(value: portIndex),
            "Watts":              NSNumber(value: watts),
            "ConfiguredVoltage":  NSNumber(value: configuredVoltage),
            "ConfiguredCurrent":  NSNumber(value: configuredCurrent),
            "AdapterVoltage":     NSNumber(value: adapterVoltage),
            "Current":            NSNumber(value: current),
            "PowerState":         NSNumber(value: powerState),
            "PortType":           NSNumber(value: 0)
        ]
    }

    @Test("portPowerSamples: single port entry produces one sample")
    func portPowerSamplesSingleEntry() {
        let items: [[String: Any]] = [portOutDict(portIndex: 1)]
        let samples = PowerService.portPowerSamples(
            from: items as Any, portKeys: ["2/1"]
        )
        #expect(samples.count == 1)
        let s = samples[0]
        #expect(s.portKey == "2/1")
        #expect(s.watts == 65_000)
        #expect(s.configuredVoltage == 20_000)
        #expect(s.configuredCurrent == 3_250)
        #expect(s.adapterVoltage == 19_500)
        #expect(s.portIndex == 1)
    }

    @Test("portPowerSamples: multiple ports")
    func portPowerSamplesMultiplePorts() {
        let items: [[String: Any]] = [
            portOutDict(portIndex: 1, watts: 65_000),
            portOutDict(portIndex: 2, watts: 0)
        ]
        let samples = PowerService.portPowerSamples(
            from: items as Any, portKeys: ["2/1", "2/2"]
        )
        // Both entries produce a sample (the helper does not filter zero-watt
        // entries in portPowerSamples; that filtering happens in portPowerSamplesFromControllerInfo).
        #expect(samples.count == 2)
        let s1 = samples.first { $0.portIndex == 1 }
        let s2 = samples.first { $0.portIndex == 2 }
        #expect(s1?.watts == 65_000)
        #expect(s2?.watts == 0)
    }

    @Test("portPowerSamples: nil input returns empty array")
    func portPowerSamplesNilInput() {
        let samples = PowerService.portPowerSamples(from: nil, portKeys: [])
        #expect(samples.isEmpty)
    }

    @Test("portPowerSamples: empty dict entry is skipped")
    func portPowerSamplesEmptyDictSkipped() {
        let items: [Any] = [[:] as [String: Any]]
        let samples = PowerService.portPowerSamples(from: items as Any, portKeys: [])
        #expect(samples.isEmpty)
    }

    @Test("portPowerSamples: falls back to 2/N key when no portKeys match")
    func portPowerSamplesFallsBackToDefaultKey() {
        let items: [[String: Any]] = [portOutDict(portIndex: 3)]
        // portKeys has no entry ending in /3 for a non-MagSafe port.
        let samples = PowerService.portPowerSamples(
            from: items as Any, portKeys: ["2/1", "2/2"]
        )
        #expect(samples.count == 1)
        // Falls back to "2/3" since rawPortIndex=3 but no portKey matches.
        #expect(samples[0].portKey == "2/3")
    }

    // MARK: - portPowerSamplesFromControllerInfo fixture tests

    /// Build a PortControllerInfo-style dict.
    private func controllerInfoDict(
        maxPowerMW: Int,
        pdos: [NSNumber]? = nil,
        rdo: Int32? = nil
    ) -> [String: Any] {
        var d: [String: Any] = ["PortControllerMaxPower": NSNumber(value: maxPowerMW)]
        if let pdos = pdos {
            d["PortControllerPortPDO"] = pdos
        }
        if let rdo = rdo {
            d["PortControllerActiveContractRdo"] = NSNumber(value: rdo)
        }
        return d
    }

    private func makeSource(portKey: String, winningWatts: Int) -> PowerSource {
        let portType = Int(portKey.split(separator: "/").first.map(String.init) ?? "2") ?? 2
        let portNum  = Int(portKey.split(separator: "/").last.map(String.init) ?? "1")  ?? 1
        return PowerSource(
            id: UInt64(portNum),
            name: "USB-PD",
            parentPortType: portType,
            parentPortNumber: portNum,
            options: [],
            winning: PowerOption(
                voltageMV: 20_000,
                maxCurrentMA: winningWatts / 20,
                maxPowerMW: winningWatts
            )
        )
    }

    @Test("portPowerSamplesFromControllerInfo: produces sample for matching source")
    func fromControllerInfoProducesSample() {
        let source = makeSource(portKey: "2/1", winningWatts: 65_000)
        let pdoList: [NSNumber] = [fixedPDO(voltageMV: 20_000, currentMA: 3_250)]
        let controllerItems: [[String: Any]] = [
            controllerInfoDict(maxPowerMW: 65_000, pdos: pdoList)
        ]
        let samples = PowerService.portPowerSamplesFromControllerInfo(
            controllerItems as Any, sources: [source]
        )
        #expect(samples.count == 1)
        let s = samples[0]
        #expect(s.portKey == "2/1")
        #expect(s.watts == 65_000)
        #expect(s.isContractedFallback == true)
        // Voltage from PDO decode (within USB PD plausible range).
        #expect(s.configuredVoltage >= 5_000)
        #expect(s.configuredVoltage <= 48_000)
    }

    @Test("portPowerSamplesFromControllerInfo: source with no winning contract is skipped")
    func fromControllerInfoNoWinningSampleSkipped() {
        let source = PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [], winning: nil
        )
        let samples = PowerService.portPowerSamplesFromControllerInfo(
            [[String: Any]() as Any] as Any, sources: [source]
        )
        #expect(samples.isEmpty)
    }

    @Test("portPowerSamplesFromControllerInfo: zero winning wattage is skipped")
    func fromControllerInfoZeroWattageSkipped() {
        let source = makeSource(portKey: "2/1", winningWatts: 0)
        let samples = PowerService.portPowerSamplesFromControllerInfo(
            [] as Any, sources: [source]
        )
        #expect(samples.isEmpty)
    }

    @Test("portPowerSamplesFromControllerInfo: nil input returns empty array")
    func fromControllerInfoNilInputEmpty() {
        let source = makeSource(portKey: "2/1", winningWatts: 65_000)
        let samples = PowerService.portPowerSamplesFromControllerInfo(
            nil, sources: [source]
        )
        // No PortControllerInfo to enrich with, so falls back to source winning.
        // Result is 1 sample keyed by the source (not dropped).
        #expect(samples.count == 1)
        #expect(samples[0].portKey == "2/1")
    }

    @Test("portPowerSamplesFromControllerInfo: PDO decode enriches voltage and current")
    func fromControllerInfoPDODecodeEnrichesVoltageAndCurrent() {
        let source = makeSource(portKey: "2/2", winningWatts: 45_000)
        // 15V / 3A PDO matches exactly.
        let pdoList: [NSNumber] = [fixedPDO(voltageMV: 15_000, currentMA: 3_000)]
        let controllerItems: [[String: Any]] = [
            controllerInfoDict(maxPowerMW: 45_000, pdos: pdoList)
        ]
        let samples = PowerService.portPowerSamplesFromControllerInfo(
            controllerItems as Any, sources: [source]
        )
        #expect(samples.count == 1)
        let s = samples[0]
        // PDO decode should recover 15V / 3A.
        #expect(s.configuredVoltage == 15_000,
            "Expected 15000 mV from PDO decode, got \(s.configuredVoltage)")
        #expect(s.configuredCurrent == 3_000,
            "Expected 3000 mA from PDO decode, got \(s.configuredCurrent)")
    }

    // MARK: - Plausible-range sweep over fixture matrix

    /// Run decodeNegotiatedContract over a realistic matrix of PDO lists and
    /// contracts seen in the wild. All decoded voltages must be in USB PD range
    /// (3-48V) and all currents must be in 0-6.5A range.
    @Test("decodeNegotiatedContract: all plausible PDO matrix values in range")
    func decodeContractPlausibleRanges() {
        // Tuples: (voltageMV, currentMA, contractMW)
        let fixtures: [(Int, Int, Int)] = [
            (5_000, 3_000, 15_000),
            (9_000, 3_000, 27_000),
            (15_000, 3_000, 45_000),
            (20_000, 2_250, 45_000),
            (20_000, 3_250, 65_000),
            (20_000, 5_000, 100_000),
            (28_000, 5_000, 140_000),  // GaN charger
            (36_000, 5_000, 180_000),  // USB PD 3.1 EPR
            (48_000, 5_000, 240_000)   // USB PD 3.1 EPR max
        ]

        for (voltageMV, currentMA, contractMW) in fixtures {
            let pdo = fixedPDO(voltageMV: voltageMV, currentMA: currentMA)
            let result = PowerService.decodeNegotiatedContract(
                pdoList: [pdo] as Any,
                maxPowerMW: contractMW,
                operatingCurrentMA: 0
            )
            guard let r = result else {
                Issue.record("decodeNegotiatedContract returned nil for \(voltageMV)mV/\(currentMA)mA/\(contractMW)mW")
                continue
            }
            #expect(r.voltageMV >= 3_000,
                "\(voltageMV)mV contract: decoded voltage \(r.voltageMV) below 3V")
            #expect(r.voltageMV <= 48_000,
                "\(voltageMV)mV contract: decoded voltage \(r.voltageMV) above 48V")
            #expect(r.currentMA >= 0,
                "\(voltageMV)mV contract: negative current \(r.currentMA)")
            #expect(r.currentMA <= 6_500,
                "\(voltageMV)mV contract: current \(r.currentMA) above 6.5A")
        }
    }
}
