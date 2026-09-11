import Foundation
import Testing
@testable import WhatCableCore

// MARK: - ChargingDiagnosticProbeSweepTests

/// Corpus-replay tests for ChargingDiagnostic.
///
/// These tests parse real customer probe files and run ChargingDiagnostic
/// against the extracted inputs. Assertions check verdict-level outcomes
/// (bottleneck type and wattage ceiling) against ground truth in each
/// machine's inspection.md.
///
/// Probes used:
///   - 17_deep_property_dump.json: IOPortFeaturePowerSource blocks (PowerSource inputs)
///   - 32_smart_battery_full_keys.json: AppleSmartBattery keys (adapter W, FullyCharged)
///
/// Fixtures in this branch: 12 machines committed under research/customer-probes/.
/// See the test/dar138-charging branch for the fixture selection rationale.
@Suite("ChargingDiagnostic -- customer probe sweep (DAR-138)")
struct ChargingDiagnosticProbeSweepTests {

    // MARK: - Parsing helpers

    /// Parse every IOPortFeaturePowerSource block from probe 17's "flat" section
    /// (--- dash style, 2-space indent) into PowerSource models.
    private static func parseDashPowerSources(text: String) -> [PowerSource] {
        var result: [PowerSource] = []
        let blocks = ProbeCorpus.parseDashBlocks(text: text, classPrefix: "IOPortFeaturePowerSource")
        for (i, props) in blocks.enumerated() {
            let name = (props["PowerSourceName"] as? String) ?? "Unknown"
            let parentType = (props["ParentPortType"] as? NSNumber)?.intValue
                ?? (props["ParentBuiltInPortType"] as? NSNumber)?.intValue
                ?? 0
            let parentNum = (props["ParentBuiltInPortNumber"] as? NSNumber)?.intValue
                ?? (props["ParentPortNumber"] as? NSNumber)?.intValue
                ?? 0
            // Recover the WinningPowerSourceOption sub-dict from raw text
            let winRaw = ProbeCorpus.parseWinningOption(
                text: text,
                blockIndex: i,
                classPrefix: "IOPortFeaturePowerSource"
            )
            let winning: PowerOption? = winRaw.flatMap { w in
                guard let v = w["Voltage (mV)"], v > 0 else { return nil }
                let c = w["Max Current (mA)"] ?? 0
                let p = w["Max Power (mW)"] ?? (v * c / 1000)
                return PowerOption(voltageMV: v, maxCurrentMA: c, maxPowerMW: p)
            }
            result.append(PowerSource(
                id: UInt64(1000 + i),
                name: name,
                parentPortType: parentType,
                parentPortNumber: parentNum,
                options: [],   // Options are a CFSet in IOKit; probe 17 renders them opaque
                winning: winning
            ))
        }
        return result
    }

    /// Parse IOPortFeaturePowerSource blocks from probe 17's HPM deep-dive section.
    ///
    /// In probe 17 the power-source sub-records appear as nested equals blocks
    /// indented 4 spaces inside an outer IOPortFeaturePowerIn block:
    ///
    ///     === IOPortFeaturePowerIn ===
    ///         ...
    ///         === IOPortFeaturePowerSource ===   <- 4-space indent
    ///               PowerSourceName: "USB-PD"   <- 6-space properties
    ///
    /// `ProbeCorpus.parseEqualsBlocks` only splits on `\n=== ` (top-level equals
    /// headers), so it merges all three sub-blocks into one body and the last
    /// `PowerSourceName` ("TypeC") wins. We therefore do our own split here using
    /// the indented header `    === IOPortFeaturePowerSource ===`.
    private static func parseEqualsPowerSources(text: String) -> [PowerSource] {
        let nestedHeader = "    === IOPortFeaturePowerSource ==="
        // Split on the 4-space-indented sub-header to get individual block bodies.
        var bodies: [String] = []
        var searchFrom = text.startIndex
        var prevBodyStart: String.Index? = nil
        while let range = text.range(of: nestedHeader, range: searchFrom..<text.endIndex) {
            if let prev = prevBodyStart {
                bodies.append(String(text[prev..<range.lowerBound]))
            }
            prevBodyStart = range.upperBound
            searchFrom = range.upperBound
        }
        if let last = prevBodyStart {
            // Clamp to 3000 chars so we don't pull in unrelated sections.
            let tail = String(text[last...])
            let end: String.Index
            if let nextSection = tail.range(of: "\n  === ") ?? tail.range(of: "\n--- ") {
                end = nextSection.lowerBound
            } else {
                end = tail.index(tail.startIndex, offsetBy: min(3000, tail.count))
            }
            bodies.append(String(tail[..<end]))
        }

        var result: [PowerSource] = []
        for (i, body) in bodies.enumerated() {
            // Properties are at 6-space indent inside each sub-block body.
            let props = ProbeCorpus.parseProperties(body: body, indent: "      ")
            let name = (props["PowerSourceName"] as? String) ?? "Unknown"
            let parentType = (props["ParentPortType"] as? NSNumber)?.intValue
                ?? (props["ParentBuiltInPortType"] as? NSNumber)?.intValue
                ?? 0
            let parentNum = (props["ParentBuiltInPortNumber"] as? NSNumber)?.intValue
                ?? (props["ParentPortNumber"] as? NSNumber)?.intValue
                ?? 0
            // WinningPowerSourceOption sub-dict uses 6-space close brace and 8-space inner.
            let winning: PowerOption? = ProbeCorpus.parseWinningOptionFromEqualsBlock(body)
                .flatMap { w in
                    guard let v = w["Voltage (mV)"], v > 0 else { return nil }
                    let c = w["Max Current (mA)"] ?? 0
                    let p = w["Max Power (mW)"] ?? (v * c / 1000)
                    return PowerOption(voltageMV: v, maxCurrentMA: c, maxPowerMW: p)
                }
            result.append(PowerSource(
                id: UInt64(2000 + i),
                name: name,
                parentPortType: parentType,
                parentPortNumber: parentNum,
                options: [],
                winning: winning
            ))
        }
        return result
    }

    /// Collect all PowerSource models from probe 17: dash-style blocks first,
    /// falling back to equals-style if no dash blocks are found.
    ///
    /// Some machines (M4 Pro) only emit equals-style; others (M1/M2) only dash.
    /// M3+ often have both, but the dash section is authoritative (top-level
    /// "All services" enumeration). When both exist, prefer dash.
    private static func allPowerSources(probe17Text text: String) -> [PowerSource] {
        let dash = parseDashPowerSources(text: text)
        if !dash.isEmpty { return dash }
        return parseEqualsPowerSources(text: text)
    }

    /// Parse adapter watts and FullyCharged from probe 32 (AppleSmartBattery).
    /// Returns (adapterWatts, isFullyCharged). Both nil when probe 32 is absent.
    private static func parseBatteryState(folder: String) -> (adapterW: Int?, fullyCharged: Bool?) {
        guard let text = ProbeCorpus.loadText(folder: folder, probe: "32_smart_battery_full_keys")
        else { return (nil, nil) }

        var adapterW: Int? = nil
        var fullyCharged: Bool? = nil

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "Watts = N (0xHEX)" inside AppleRawAdapterDetails[0]; first hit wins.
            // Exclude UsbHvcMenu entries which have MaxVoltage/MaxCurrent, not Watts.
            if trimmed.hasPrefix("Watts =") && adapterW == nil {
                let afterKey = String(trimmed.dropFirst("Watts =".count))
                    .trimmingCharacters(in: .whitespaces)
                if let m = ProbeCorpus.matchInt(afterKey) {
                    adapterW = m
                }
            }
            // Top-level "  FullyCharged = true/false"
            if line.hasPrefix("  FullyCharged =") && fullyCharged == nil {
                fullyCharged = trimmed.contains("true")
            }
        }
        return (adapterW, fullyCharged)
    }

    /// Parse the `FedDetails` array from probe 32 into `FederatedIdentity`
    /// values (1-based `portIndex` = array offset + 1), mirroring what
    /// `AppleSmartBatteryReader.parseFedDetails` does from the live registry.
    /// This is the per-port charger identity the #459 fallback consumes on
    /// M1 Pro/Max/Ultra, where no USB-C PowerSource node exists.
    private static func parseFedDetails(folder: String) -> [FederatedIdentity] {
        guard let text = ProbeCorpus.loadText(folder: folder, probe: "32_smart_battery_full_keys")
        else { return [] }
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("FedDetails =") && $0.contains("Array") })
        else { return [] }
        let arrayIndent = lines[start].prefix { $0 == " " }.count

        var result: [FederatedIdentity] = []
        var idx = -1
        var vid = 0, pid = 0, rev = 0, role = 0, drp = 0, ext = 0
        func flush() {
            guard idx >= 0 else { return }
            result.append(FederatedIdentity(
                portIndex: idx + 1, vendorID: vid, productID: pid,
                pdSpecRevision: rev, powerRole: role, dualRolePower: drp != 0,
                externalConnected: ext != 0))
        }
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent <= arrayIndent { break }   // left the array
            if let m = entryHeaderIndex(trimmed) {
                flush()
                idx = m; vid = 0; pid = 0; rev = 0; role = 0; drp = 0; ext = 0
                continue
            }
            if let v = fedInt(trimmed, "FedVendorID") { vid = v }
            else if let v = fedInt(trimmed, "FedProductID") { pid = v }
            else if let v = fedInt(trimmed, "FedPdSpecRevision") { rev = v }
            else if let v = fedInt(trimmed, "FedPortPowerRole") { role = v }
            else if let v = fedInt(trimmed, "FedDualRolePower") { drp = v }
            else if let v = fedInt(trimmed, "FedExternalConnected") { ext = v }
        }
        flush()
        return result
    }

    /// "[N]         Dict[12]:" -> N. Only matches an entry header, not a PDO row.
    private static func entryHeaderIndex(_ trimmed: String) -> Int? {
        guard trimmed.hasPrefix("["), trimmed.contains("Dict"),
              let close = trimmed.firstIndex(of: "]") else { return nil }
        return Int(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
    }

    private static func fedInt(_ trimmed: String, _ key: String) -> Int? {
        guard trimmed.hasPrefix("\(key) =") else { return nil }
        return ProbeCorpus.matchInt(
            String(trimmed.dropFirst("\(key) =".count)).trimmingCharacters(in: .whitespaces))
    }

    /// Build a minimal AppleHPMInterface for a charging port, given portType and portNumber.
    /// connectionActive is set to true because a PowerSource block is only present when
    /// something is connected.
    private static func makePort(
        portTypeDescription: String,
        portType: Int,
        portNumber: Int
    ) -> USBCPort {
        let serviceName: String
        let className: String
        if portTypeDescription.hasPrefix("MagSafe") {
            serviceName = "Port-MagSafe 3@\(portNumber)"
            className = "AppleHPMInterfaceType11"
        } else {
            serviceName = "Port-USB-C@\(portNumber)"
            className = "AppleHPMInterfaceType10"
        }
        let rawPortType = portType == 0x11 ? "17" : "2"
        return USBCPort(
            id: UInt64(portNumber),
            serviceName: serviceName,
            className: className,
            portDescription: nil,
            portTypeDescription: portTypeDescription,
            portNumber: portNumber,
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [],
            transportsActive: [],
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: ["PortType": rawPortType]
        )
    }

    /// Resolve which port the charger is on, using the preferred PowerSource's
    /// parentPortType and parentPortNumber.
    private static func chargingPort(sources: [PowerSource]) -> USBCPort? {
        guard let preferred = PowerSource.preferredChargingSource(in: sources) else { return nil }
        let portTypeDesc = preferred.parentPortType == 0x11 ? "MagSafe 3" : "USB-C"
        return makePort(
            portTypeDescription: portTypeDesc,
            portType: preferred.parentPortType,
            portNumber: preferred.parentPortNumber
        )
    }

    /// Parse the real port list from `01_walk_pd_tree.json`: every
    /// `=== IOAccessoryManager[...] ===` block, keeping its type, number, and
    /// live `ConnectionActive` flag. This is what the charger-source count and
    /// the active-port count consume on real hardware.
    private static func loadProbe01Ports(folder: String) -> [USBCPort] {
        guard let text = ProbeCorpus.loadText(folder: folder, probe: "01_walk_pd_tree") else { return [] }
        var ports: [USBCPort] = []
        for chunk in text.components(separatedBy: "=== IOAccessoryManager[").dropFirst() {
            guard let typeDesc = quotedValue(chunk, key: "PortTypeDescription") else { continue }
            let number = intValue(chunk, key: "PortNumber") ?? 0
            let active = chunk.contains("ConnectionActive = true")
            let rawType = typeDesc.hasPrefix("MagSafe") ? "17" : "2"
            ports.append(USBCPort(
                id: UInt64(number),
                serviceName: "Port-\(typeDesc)@\(number)",
                className: typeDesc.hasPrefix("MagSafe") ? "AppleHPMInterfaceType11" : "AppleHPMInterfaceType10",
                portDescription: nil,
                portTypeDescription: typeDesc,
                portNumber: number,
                connectionActive: active,
                activeCable: nil, opticalCable: nil, usbActive: nil,
                superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
                transportsSupported: [], transportsActive: [], transportsProvisioned: [],
                plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
                overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
                firmwareVersion: nil, bootFlagsHex: nil, rawProperties: ["PortType": rawType]
            ))
        }
        return ports
    }

    private static func quotedValue(_ block: String, key: String) -> String? {
        guard let r = block.range(of: "\(key) = \"") else { return nil }
        let after = block[r.upperBound...]
        guard let close = after.firstIndex(of: "\"") else { return nil }
        return String(after[..<close])
    }

    private static func intValue(_ block: String, key: String) -> Int? {
        guard let r = block.range(of: "\(key) = ") else { return nil }
        let digits = block[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    // MARK: - Specific machine tests

    // MARK: m1pro_macos15.7.4 -- 140W EPR, MagSafe Brick ID + a second active USB-C port
    //
    // Ground truth (probe 01): FOUR ports, TWO active at once -- MagSafe 3@1
    // (charging) AND USB-C@1 (an Apple data device attached, no power source).
    // Probe 17: exactly ONE power-source node ("Brick ID", on MagSafe).
    // This is the real-hardware #443 shape: a second active port with no source
    // must NOT inflate the charger count, and must NOT borrow the charger's
    // wattage. Counts are computed from the real probes, not hardcoded.

    @Test("m1pro_macos15.7.4: MagSafe Brick ID reads 140W; the second active USB-C port is not a charger (#443)")
    func m1pro_macos15_7_4_140w_magsafe_brickid() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m1pro_macos15.7.4", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        #expect(!sources.isEmpty, "Expected at least one PowerSource in probe 17")

        let ports = Self.loadProbe01Ports(folder: "m1pro_macos15.7.4")
        guard !ports.isEmpty else {
            Issue.record("Could not parse probe-01 ports"); return
        }

        // Real counts from the corpus, not hardcoded. Two ports are active;
        // only one (MagSafe) exposes a power source.
        let activePortCount = ports.filter { $0.connectionActive == true }.count
        let chargerSourceCount = ChargerWattageSource.chargerSourceCount(ports: ports, sources: sources)
        #expect(activePortCount == 2, "Expected 2 active ports (MagSafe + USB-C); got \(activePortCount)")
        #expect(chargerSourceCount == 1, "Expected 1 port with a power source (MagSafe); got \(chargerSourceCount)")

        let (adapterW, fullyCharged) = Self.parseBatteryState(folder: "m1pro_macos15.7.4")
        #expect(adapterW == 140, "Expected adapter 140W from probe 32; got \(adapterW as Any)")
        let adapter = adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }

        // Locate the two active ports by role.
        guard let magsafe = ports.first(where: { $0.portTypeDescription?.hasPrefix("MagSafe") == true && $0.connectionActive == true }),
              let dataPort = ports.first(where: { $0.portTypeDescription == "USB-C" && $0.connectionActive == true })
        else {
            Issue.record("Expected an active MagSafe port and an active USB-C port"); return
        }

        // MagSafe: the Brick ID divert must fire even with a second active port,
        // because that second port has no power source (chargerSourceCount == 1).
        let magsafeWattage = ChargerWattageSource.resolve(
            portSources: sources.filter { $0.canonicallyMatches(port: magsafe) },
            portIsActive: magsafe.connectionActive == true,
            activePortCount: activePortCount,
            chargerSourceCount: chargerSourceCount,
            adapter: adapter
        )
        #expect(magsafeWattage == .systemAdapterFallback(watts: 140))

        let diag = ChargingDiagnostic(
            port: magsafe,
            sources: sources,
            identities: [],
            wattageSource: magsafeWattage,
            batteryFullyCharged: fullyCharged
        )
        guard case .chargerLimit(let w) = diag?.bottleneck else {
            Issue.record("Expected .chargerLimit, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(w == 140, "Expected 140W charger ceiling; got \(w)")
        #expect(diag?.isWarning == false)

        // The second active USB-C port has no power source of its own. The
        // adapter reading must NOT be attributed to it (the Codex-caught
        // regression on real data): resolve returns .unknown, no charger watts.
        let dataWattage = ChargerWattageSource.resolve(
            portSources: sources.filter { $0.canonicallyMatches(port: dataPort) },
            portIsActive: dataPort.connectionActive == true,
            activePortCount: activePortCount,
            chargerSourceCount: chargerSourceCount,
            adapter: adapter
        )
        #expect(dataWattage == .unknown, "Second active port must not borrow the charger wattage; got \(dataWattage)")
    }

    // MARK: m1pro_macos26.5_k -- 140W EPR, MagSafe USB-PD, battery full
    //
    // Ground truth (inspection.md): not charging (battery full), adapter 140W.
    // The USB-PD source has WinningOption ~140W (28V x 4.99A = 139720 mW).
    // FullyCharged=true.
    // Expected: .fine(negotiatedW: ~140) with batteryFull => summary "Battery full"

    @Test("m1pro_macos26.5_k: 140W EPR MagSafe USB-PD, battery full -> fine with battery-full summary")
    func m1pro_macos26_5_k_140w_battery_full() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m1pro_macos26.5_k", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, fullyCharged) = Self.parseBatteryState(folder: "m1pro_macos26.5_k")
        #expect(adapterW == 140)
        #expect(fullyCharged == true)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource,
            batteryFullyCharged: fullyCharged
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        // Battery full with 140W contract -> .fine with "Battery full, not charging" summary
        guard case .fine(let n) = diag.bottleneck else {
            Issue.record("Expected .fine(negotiatedW: ~140), got \(diag.bottleneck)")
            return
        }
        // 139720 mW / 1000 rounds to 140W
        #expect(n >= 139 && n <= 141, "Expected negotiatedW ~140W; got \(n)")
        #expect(diag.summary == "Battery full, not charging",
            "Expected battery-full summary; got \"\(diag.summary)\"")
        #expect(diag.isWarning == false)
    }

    // MARK: m1pro_macos26.5_m -- 140W EPR, MagSafe USB-PD, not full
    //
    // Ground truth: charging, adapter 140W, not fully charged.
    // WinningOption ~140W -> .fine(140)

    @Test("m1pro_macos26.5_m: 140W EPR MagSafe USB-PD, not full -> fine at 140W")
    func m1pro_macos26_5_m_140w_not_full() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m1pro_macos26.5_m", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, fullyCharged) = Self.parseBatteryState(folder: "m1pro_macos26.5_m")
        #expect(adapterW == 140)
        #expect(fullyCharged == false)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource,
            batteryFullyCharged: fullyCharged
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        guard case .fine(let n) = diag.bottleneck else {
            Issue.record("Expected .fine(~140W), got \(diag.bottleneck)")
            return
        }
        #expect(n >= 139 && n <= 141, "Expected ~140W; got \(n)")
        #expect(diag.summary.contains("Charging well"), "Expected 'Charging well' summary; got \"\(diag.summary)\"")
        #expect(diag.isWarning == false)
    }

    // MARK: m4_macos26.5_d -- 100W, battery full, MagSafe USB-PD WinningOption
    //
    // Ground truth: not charging (battery full), adapter 100W.
    // This machine uses === style blocks in probe 17.

    @Test("m4_macos26.5_d: 100W battery-full MagSafe USB-PD -> fine with battery-full summary")
    func m4_macos26_5_d_100w_battery_full() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m4_macos26.5_d", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, fullyCharged) = Self.parseBatteryState(folder: "m4_macos26.5_d")
        #expect(adapterW == 100)
        #expect(fullyCharged == true)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource,
            batteryFullyCharged: fullyCharged
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        guard case .fine(let n) = diag.bottleneck else {
            Issue.record("Expected .fine(~100W), got \(diag.bottleneck)")
            return
        }
        #expect(n >= 95 && n <= 105, "Expected ~100W; got \(n)")
        #expect(diag.summary == "Battery full, not charging")
        #expect(diag.isWarning == false)
    }

    // MARK: m5pro_macos26.5_c -- 100W, M5 Pro, PPS, not full
    //
    // Ground truth: charging, adapter 100W, not fully charged.

    @Test("m5pro_macos26.5_c: 100W M5 Pro charging -> fine at ~100W")
    func m5pro_macos26_5_c_100w_m5pro() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m5pro_macos26.5_c", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, fullyCharged) = Self.parseBatteryState(folder: "m5pro_macos26.5_c")
        #expect(adapterW == 100)
        #expect(fullyCharged == false)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource,
            batteryFullyCharged: fullyCharged
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        guard case .fine(let n) = diag.bottleneck else {
            // If negotiatedW < chargerW - tolerance, we get macLimit instead
            if case .macLimit(let n2, _, _) = diag.bottleneck {
                // Also acceptable: the Mac was drawing less than 100W at capture time
                #expect(n2 >= 50, "macLimit negotiatedW too low: \(n2)")
                #expect(diag.isWarning == false)
                return
            }
            Issue.record("Expected .fine or .macLimit, got \(diag.bottleneck)")
            return
        }
        #expect(n >= 80 && n <= 105, "Expected ~100W (allow ±20W for PPS throttling); got \(n)")
        #expect(diag.isWarning == false)
    }

    // MARK: m3pro_macos26.5_b -- 100W, M3 Pro, not full
    //
    // Ground truth: charging, adapter 100W.

    @Test("m3pro_macos26.5_b: 100W M3 Pro charging -> non-nil diagnosis with wattage ~100W")
    func m3pro_macos26_5_b_100w_m3pro() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m3pro_macos26.5_b", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, _) = Self.parseBatteryState(folder: "m3pro_macos26.5_b")
        #expect(adapterW == 100)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        // Should be fine or macLimit (Mac drawing less than 100W is normal)
        switch diag.bottleneck {
        case .fine(let n):
            #expect(n >= 80 && n <= 105, "fine: expected ~100W; got \(n)")
        case .macLimit(let n, let cW, _):
            #expect(n >= 30, "macLimit negotiatedW reasonable; got \(n)")
            #expect(cW >= 95, "chargerW should be ~100W; got \(cW)")
        case .chargerLimit(let w):
            // Acceptable if no WinningOption parsed: charger ceiling without contract
            #expect(w >= 95 && w <= 105, "chargerLimit: expected ~100W; got \(w)")
        default:
            Issue.record("Unexpected bottleneck: \(diag.bottleneck)")
        }
        #expect(diag.isWarning == false)
    }

    // MARK: m3pro_macos15.7.5 -- 94W, MagSafe, Brick ID + TypeC only, macOS 15
    //
    // Ground truth: charging, adapter 94W. No USB-PD source (Brick ID + TypeC).
    // Expected: adapter fallback -> chargerLimit(94)

    @Test("m3pro_macos15.7.5: 94W MagSafe Brick-ID-only (macOS 15) -> chargerLimit via adapter fallback")
    func m3pro_macos15_7_5_94w_brickid() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m3pro_macos15.7.5", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, _) = Self.parseBatteryState(folder: "m3pro_macos15.7.5")
        #expect(adapterW == 94)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil (wattageSource=\(wattageSource))"); return
        }
        guard case .chargerLimit(let w) = diag.bottleneck else {
            Issue.record("Expected .chargerLimit(94), got \(diag.bottleneck)")
            return
        }
        #expect(w == 94, "Expected 94W ceiling; got \(w)")
        #expect(diag.isWarning == false)
    }

    // MARK: m2_macos26.3.1 -- 60W, USB-PD with WinningOption, M2 laptop
    //
    // Ground truth: charging, adapter 60W.

    @Test("m2_macos26.3.1: 60W USB-C charging -> fine at 60W")
    func m2_macos26_3_1_60w() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m2_macos26.3.1", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, fullyCharged) = Self.parseBatteryState(folder: "m2_macos26.3.1")
        #expect(adapterW == 60)
        #expect(fullyCharged == false)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        switch diag.bottleneck {
        case .fine(let n):
            #expect(n >= 55 && n <= 65, "fine: expected ~60W; got \(n)")
        case .macLimit(let n, let cW, _):
            #expect(cW >= 55 && cW <= 65, "macLimit chargerW ~60W; got \(cW)")
            #expect(n >= 10, "macLimit: reasonably positive negotiatedW")
        default:
            Issue.record("Expected .fine or .macLimit at ~60W; got \(diag.bottleneck)")
        }
        #expect(diag.isWarning == false)
    }

    // MARK: m4pro_macos26.5_j -- 60W, M4 Pro, equals-style blocks only
    //
    // Ground truth: charging, adapter 60W.

    @Test("m4pro_macos26.5_j: 60W M4 Pro (===block only) -> diagnosis at ~60W")
    func m4pro_macos26_5_j_60w_eqblocks() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m4pro_macos26.5_j", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        // This machine only has === blocks
        let dashSources = Self.parseDashPowerSources(text: text17)
        let eqSources = Self.parseEqualsPowerSources(text: text17)
        #expect(dashSources.isEmpty, "Expected no dash blocks on M4 Pro probe")
        #expect(!eqSources.isEmpty, "Expected equals-style blocks on M4 Pro")

        let sources = eqSources
        let (adapterW, _) = Self.parseBatteryState(folder: "m4pro_macos26.5_j")
        #expect(adapterW == 60)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil (wattageSource=\(wattageSource))"); return
        }
        switch diag.bottleneck {
        case .fine(let n):
            #expect(n >= 55 && n <= 65, "fine: expected ~60W; got \(n)")
        case .macLimit(let n, let cW, _):
            #expect(cW >= 55 && cW <= 65, "macLimit chargerW ~60W; got \(cW)")
            #expect(n >= 10)
        case .chargerLimit(let w):
            #expect(w >= 55 && w <= 65, "chargerLimit ~60W; got \(w)")
        default:
            Issue.record("Expected .fine/.macLimit/.chargerLimit at ~60W; got \(diag.bottleneck)")
        }
        #expect(diag.isWarning == false)
    }

    // MARK: m1_macos26.5_o -- 25W low-watt charger
    //
    // Ground truth: charging, adapter 25W.

    @Test("m1_macos26.5_o: 25W low-watt charger -> non-nil diagnosis ~25W, no warning")
    func m1_macos26_5_o_25w() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m1_macos26.5_o", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, _) = Self.parseBatteryState(folder: "m1_macos26.5_o")
        #expect(adapterW == 25)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        // A 25W charger is fine for a small accessory / slow charge; no warning expected.
        // The wattage should be in the range 20-30W.
        let ceiling = diag.chargerW ?? 0
        #expect(ceiling >= 20 && ceiling <= 35,
            "Expected charger ceiling ~25W; got \(ceiling)")
        #expect(diag.isWarning == false,
            "A 25W charger without cable limitation should not warn; got isWarning=true")
    }

    // MARK: m3_macos26.5_g -- 15W very low-watt charger
    //
    // Ground truth: charging, adapter 15W.

    @Test("m3_macos26.5_g: 15W very low-watt charger -> non-nil diagnosis ~15W, no warning")
    func m3_macos26_5_g_15w() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m3_macos26.5_g", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        let (adapterW, _) = Self.parseBatteryState(folder: "m3_macos26.5_g")
        #expect(adapterW == 15)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        let ceiling = diag.chargerW ?? 0
        #expect(ceiling >= 10 && ceiling <= 20,
            "Expected charger ceiling ~15W; got \(ceiling)")
        #expect(diag.isWarning == false,
            "A 15W charger is not a cable fault; got isWarning=true")
    }

    // MARK: m1_macos26.5_n -- 100W charger, M1 laptop, multiple ports with sources
    //
    // Ground truth: charging, adapter 100W. Has 3 PowerSource blocks.
    // Tests that we correctly pick the charging port from multiple sources.

    @Test("m1_macos26.5_n: 100W multi-source M1 -> picks charging port, ~100W ceiling")
    func m1_macos26_5_n_100w_multiport() {
        guard let text17 = ProbeCorpus.loadText(
            folder: "m1_macos26.5_n", probe: "17_deep_property_dump")
        else { return }  // skip: fixture not present in this checkout

        let sources = Self.allPowerSources(probe17Text: text17)
        #expect(sources.count >= 2, "Expected multiple PowerSource blocks; got \(sources.count)")

        let (adapterW, _) = Self.parseBatteryState(folder: "m1_macos26.5_n")
        #expect(adapterW == 100)

        guard let port = Self.chargingPort(sources: sources) else {
            Issue.record("Could not resolve charging port from \(sources.count) sources"); return
        }
        let portSources = sources.filter { $0.canonicallyMatches(port: port) }
        let wattageSource = ChargerWattageSource.resolve(
            portSources: portSources,
            portIsActive: port.connectionActive == true,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
        )
        let diag = ChargingDiagnostic(
            port: port,
            sources: sources,
            identities: [],
            wattageSource: wattageSource
        )
        guard let diag else {
            Issue.record("Expected a diagnosis, got nil"); return
        }
        let ceiling = diag.chargerW ?? 0
        #expect(ceiling >= 85 && ceiling <= 105,
            "Expected ~100W charger ceiling; got \(ceiling)")
        #expect(diag.isWarning == false)
    }

    // MARK: - Sweep test: all fixtures produce non-nil diagnostics

    /// Sanity check across all 12 fixture machines: every machine with a charging
    /// signal and probe 17 available should produce a non-nil ChargingDiagnostic.
    /// No isWarning should fire (none of these machines have a cable-limit scenario).
    @Test("Sweep: all fixture charging machines produce non-nil verdicts without cable-limit warnings")
    func sweepAllFixturesNonNil() {
        let fixtureMachines = [
            "m1pro_macos15.7.4",
            "m1pro_macos26.5_k",
            "m1pro_macos26.5_m",
            "m4_macos26.5_d",
            "m5pro_macos26.5_c",
            "m3pro_macos26.5_b",
            "m3pro_macos15.7.5",
            "m2_macos26.3.1",
            "m4pro_macos26.5_j",
            "m1_macos26.5_o",
            "m3_macos26.5_g",
            "m1_macos26.5_n",
        ]

        var producedDiagnosis = 0
        var warnings = 0

        for folder in fixtureMachines {
            guard let text17 = ProbeCorpus.loadText(folder: folder, probe: "17_deep_property_dump")
            else { continue }

            let sources = Self.allPowerSources(probe17Text: text17)
            guard !sources.isEmpty else { continue }

            let (adapterW, fullyCharged) = Self.parseBatteryState(folder: folder)
            guard let port = Self.chargingPort(sources: sources) else { continue }

            let portSources = sources.filter { $0.canonicallyMatches(port: port) }
            let wattageSource = ChargerWattageSource.resolve(
                portSources: portSources,
                portIsActive: port.connectionActive == true,
                activePortCount: 1,
                chargerSourceCount: 1,
                adapter: adapterW.map { AdapterInfo(watts: $0, isCharging: nil, source: "AC") }
            )
            let diag = ChargingDiagnostic(
                port: port,
                sources: sources,
                identities: [],
                wattageSource: wattageSource,
                batteryFullyCharged: fullyCharged
            )
            if diag != nil { producedDiagnosis += 1 }
            if diag?.isWarning == true { warnings += 1 }
        }

        // All 12 fixture machines should produce a diagnosis
        #expect(producedDiagnosis == fixtureMachines.count,
            "Expected all \(fixtureMachines.count) fixture machines to produce a ChargingDiagnostic; only \(producedDiagnosis) did")

        // None of these are cable-limit scenarios; no warnings expected
        #expect(warnings == 0,
            "None of the fixture machines should produce a cableLimit warning; got \(warnings) warning(s)")
    }

    // MARK: - #459: FedDetails fallback replayed against real probe 32

    /// Replays the #459 no-PowerSource fallback across every committed folder's
    /// real `FedDetails` (probe 32) + port state (probe 01). For each source-less
    /// USB-C port (the fallback's domain), holding "another port is charging"
    /// true, the standby verdict must appear **iff** the real FedDetails gates
    /// hold: a charger is attached (`externalConnected`), the Mac is the sink
    /// (`powerRole == 0`, not sourcing out to a phone), and the port is live.
    ///
    /// This exercises the fallback on real data, including the corpus's genuine
    /// `powerRole == 1` (Mac-sources-out) entries and inactive-port entries,
    /// which the gates must reject. No committed machine has the full live
    /// losing-charger shape (consistent with #416 "unobserved"), so the positive
    /// verdict is proven by the unit tests; here every real evaluation is a
    /// correct rejection, and the count asserts the path was actually walked.
    @Test("#459 sweep: FedDetails fallback fires iff the real gates hold, never misfires")
    func fedDetailsFallbackSweep() {
        let adapter = AdapterInfo(watts: 65, isCharging: nil, source: "AC")  // not on battery
        var portsEvaluated = 0
        var chargerAttachedSeen = 0   // ext == 1 on a source-less USB-C port

        for folder in ProbeCorpus.allFolders() {
            let ports = Self.loadProbe01Ports(folder: folder)
            guard !ports.isEmpty else { continue }
            let feds = Self.parseFedDetails(folder: folder)
            guard !feds.isEmpty else { continue }
            let sources = ProbeCorpus.loadText(folder: folder, probe: "17_deep_property_dump")
                .map { Self.allPowerSources(probe17Text: $0) } ?? []

            for port in ports where port.portTypeDescription == "USB-C" {
                // The fallback's domain is a port with no PowerSource node.
                let portSources = sources.filter { $0.canonicallyMatches(port: port) }
                guard PowerSource.preferredChargingSource(in: portSources) == nil else { continue }
                guard let fed = feds.first(where: { $0.portIndex == port.portNumber }) else { continue }
                portsEvaluated += 1
                if fed.externalConnected { chargerAttachedSeen += 1 }

                let diag = ChargingDiagnostic(
                    port: port,
                    sources: portSources,
                    identities: [],
                    adapter: adapter,
                    anotherPortActivelyCharging: true,   // isolate the FedDetails gates
                    federatedIdentities: feds
                )
                let firedStandby: Bool
                if case .standbyCharger = diag?.bottleneck { firedStandby = true } else { firedStandby = false }

                let gatesHold = fed.externalConnected && fed.powerRole == 0 && port.connectionActive == true
                #expect(firedStandby == gatesHold,
                    "\(folder) USB-C@\(port.portNumber): fired=\(firedStandby) but gates=\(gatesHold) (ext=\(fed.externalConnected) role=\(fed.powerRole) active=\(port.connectionActive == true))")
            }
        }

        // Non-vacuous: the fallback path was walked on real source-less USB-C
        // ports, and at least one carried a charger (externalConnected), so the
        // gates did real rejection work rather than skipping every row. The fire
        // branch (all gates true) has no committed live fixture, consistent with
        // #416 "unobserved", and is proven by the unit tests instead.
        #expect(portsEvaluated > 0, "FedDetails fallback sweep evaluated no ports; fixtures missing?")
        #expect(chargerAttachedSeen > 0, "expected at least one source-less USB-C port with a charger attached in the corpus")
    }
}
