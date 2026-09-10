import Foundation
import IOKit
import WhatCableCore

/// The one place the app talks to the `AppleSmartBattery` IOKit service.
///
/// Desktop Macs have no `AppleSmartBattery` service at all, or report
/// `BatteryInstalled = false`.
///
/// Four other places used to name this class themselves: a second full reader
/// on `PowerService`, and two lookups plus an alias on
/// `PortDiagnosticsWatcher`. They now all come through here, so the class name
/// appears once and a change to how the service is found cannot reach three of
/// its four callers and miss the fourth.
///
/// **The two read strategies below are a deliberate divergence, not leftover
/// duplication.** `read()` fetches keys one at a time because the bulk fetch
/// (`IORegistryEntryCreateCFProperties`) can abort the process from inside
/// `IOCFUnserializeBinary` when the kernel returns a malformed serialised blob,
/// typically while a service is being torn down (issue #181). `properties()`
/// does the bulk fetch anyway, because its callers enumerate keys they do not
/// know in advance and there is no per-key alternative for that. Merging them
/// would either lose the crash-avoidance or lose the unknown-key access. If a
/// duplicate-reader check ever flags these two, that is the answer.
public enum AppleSmartBatteryReader {
    public struct Result {
        public let isDesktopMac: Bool
        public let federatedIdentities: [FederatedIdentity]
        public let battery: AppleSmartBattery?
    }

    /// The IOKit matching dictionary for this service, for callers registering
    /// a notification rather than reading.
    ///
    /// Returns an unmanaged `CFMutableDictionary` following IOKit's convention:
    /// the `IOServiceAddMatchingNotification` family consumes a reference, so
    /// the caller must either hand it to one of those or release it.
    public static func matchingDictionary() -> CFMutableDictionary? {
        IOServiceMatching(serviceClassName)
    }

    /// The live service handle, or 0 when this Mac publishes none. The caller
    /// owns the returned object and must `IOObjectRelease` it.
    public static func matchingService() -> io_service_t {
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceClassName))
    }

    /// The whole property dictionary, for callers that enumerate keys they do
    /// not know in advance (per-port arrays like `PortControllerInfo` and
    /// `PowerOutDetails`). See the type's doc comment for why this coexists
    /// with `read()`'s per-key strategy.
    ///
    /// `AppleSmartBattery` is a persistent service that is never torn down
    /// mid-read, so the `IOCFUnserializeBinary` crash path does not apply here.
    public static func properties() -> [String: Any]? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClassName), &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var attempt = 0
        while true {
            attempt += 1
            var sawAny = false
            var next = IOIteratorNext(iter)
            while next != 0 {
                sawAny = true
                let service = next
                defer { IOObjectRelease(service) }
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    return dict
                }
                next = IOIteratorNext(iter)
            }
            // Nothing usable was found in this pass. If the iterator was
            // invalidated mid-walk (not just genuinely empty), retry from the
            // start; IOIteratorReset rewinds it, so there is nothing collected
            // here to discard.
            let invalidatedMidWalk = sawAny && IOIteratorIsValid(iter) == 0
            if !invalidatedMidWalk || attempt >= 3 { break }
            IOIteratorReset(iter)
        }
        return nil
    }

    /// The IOKit class name. Private on purpose: everything that needs it goes
    /// through the three entry points above.
    private static let serviceClassName = "AppleSmartBattery"

    public static func read() -> Result {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClassName), &iter) == KERN_SUCCESS else {
            return Result(isDesktopMac: true, federatedIdentities: [], battery: nil)
        }
        defer { IOObjectRelease(iter) }

        let service = IOIteratorNext(iter)
        guard service != 0 else {
            return Result(isDesktopMac: true, federatedIdentities: [], battery: nil)
        }
        defer { IOObjectRelease(service) }

        // Read keys individually rather than fetching the full property
        // dictionary. The bulk fetch (IORegistryEntryCreateCFProperties)
        // can abort the process from inside IOCFUnserializeBinary when
        // the kernel returns a malformed serialised properties blob,
        // typically when the service is being torn down mid-read. The
        // per-key call has no such failure path. See issue #181.
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        return parse(read: read)
    }

    /// The whole of this reader's parsing, with IOKit swapped for a plain
    /// property-lookup closure.
    ///
    /// `read()` above is now only the IOKit half: find the service, hand back a
    /// key-reader. Everything that turns properties into models happens here, so
    /// a test can drive the real production parsers with recorded probe data.
    /// Until this seam existed the parse family was unreachable from tests (all
    /// `private`, and `@testable import` does not reach `private`), which
    /// `AppleSmartBatteryReaderCorpusSweepTests` documented at length and worked
    /// around by re-implementing the extraction it wanted to check.
    ///
    /// The `internal` access level is deliberate: this is a test seam, not a new
    /// public API. `read()` remains the only supported entry point.
    static func parse(read: (String) -> Any?) -> Result {
        let batteryInstalled = boolVal(read("BatteryInstalled"))
        if !batteryInstalled {
            return Result(isDesktopMac: true, federatedIdentities: [], battery: nil)
        }

        let fedDetails = parseFedDetails(read("FedDetails"))
        let battery = parseBattery(read, federatedIdentities: fedDetails)
        return Result(isDesktopMac: false, federatedIdentities: fedDetails, battery: battery)
    }

    static func parseBattery(_ read: (String) -> Any?, federatedIdentities: [FederatedIdentity]) -> AppleSmartBattery {
        AppleSmartBattery(
            batteryInstalled: true,
            deviceName: (read("DeviceName") as? String) ?? "",
            serial: (read("Serial") as? String) ?? "",
            designCapacity: intVal(read("DesignCapacity")),
            nominalChargeCapacity: intVal(read("NominalChargeCapacity")),
            designCycleCount: intVal(read("DesignCycleCount9C")),
            gasGaugeFirmwareVersion: intVal(read("GasGaugeFirmwareVersion")),
            currentCapacity: intVal(read("CurrentCapacity")),
            maxCapacity: intVal(read("MaxCapacity")),
            voltage: intVal(read("Voltage")),
            amperage: intVal(read("Amperage")),
            instantAmperage: intVal(read("InstantAmperage")),
            temperature: intVal(read("Temperature")),
            virtualTemperature: intVal(read("VirtualTemperature")),
            cycleCount: intVal(read("CycleCount")),
            isCharging: boolVal(read("IsCharging")),
            fullyCharged: boolVal(read("FullyCharged")),
            externalConnected: boolVal(read("ExternalConnected")),
            externalChargeCapable: boolVal(read("ExternalChargeCapable")),
            atCriticalLevel: boolVal(read("AtCriticalLevel")),
            timeRemaining: intVal(read("TimeRemaining")),
            avgTimeToFull: intVal(read("AvgTimeToFull")),
            avgTimeToEmpty: intVal(read("AvgTimeToEmpty")),
            rawCurrentCapacity: intVal(read("AppleRawCurrentCapacity")),
            rawMaxCapacity: intVal(read("AppleRawMaxCapacity")),
            rawBatteryVoltage: intVal(read("AppleRawBatteryVoltage")),
            rawExternalConnected: boolVal(read("AppleRawExternalConnected")),
            chargerConfiguration: intVal(read("ChargerConfiguration")),
            packReserve: intVal(read("PackReserve")),
            postChargeWaitSeconds: intVal(read("PostChargeWaitSeconds")),
            postDischargeWaitSeconds: intVal(read("PostDischargeWaitSeconds")),
            batteryInvalidWakeSeconds: intVal(read("BatteryInvalidWakeSeconds")),
            bootVoltage: intVal(read("BootVoltage")),
            permanentFailureStatus: intVal(read("PermanentFailureStatus")),
            batteryCellDisconnectCount: intVal(read("BatteryCellDisconnectCount")),
            updateTime: intVal(read("UpdateTime")),
            fullPathUpdated: intVal(read("FullPathUpdated")),
            bootPathUpdated: intVal(read("BootPathUpdated")),
            userVisiblePathUpdated: intVal(read("UserVisiblePathUpdated")),
            chargerData: parseChargerData(read("ChargerData")),
            carrierMode: parseCarrierMode(read("CarrierMode")),
            batteryShutdownReason: parseShutdownReason(read("BatteryShutdownReason")),
            adapterDetails: parseAdapterDetails(read("AdapterDetails")),
            powerTelemetryData: parsePowerTelemetry(read("PowerTelemetryData")),
            portControllerInfo: parsePortControllerInfo(read("PortControllerInfo")),
            federatedIdentities: federatedIdentities
        )
    }

    // MARK: - Sub-parsers

    static func parseChargerData(_ value: Any?) -> ChargerData? {
        guard let d = value as? [String: Any] else { return nil }
        return ChargerData(
            chargingVoltage: intVal(d["ChargingVoltage"]),
            chargingCurrent: intVal(d["ChargingCurrent"]),
            notChargingReason: intVal(d["NotChargingReason"]),
            slowChargingReason: intVal(d["SlowChargingReason"]),
            chargerID: intVal(d["ChargerID"]),
            chargerResetCounter: intVal(d["ChargerResetCounter"]),
            chargerInhibitReason: intVal(d["ChargerInhibitReason"]),
            timeChargingThermallyLimited: intVal(d["TimeChargingThermallyLimited"]),
            vacVoltageLimit: intVal(d["VacVoltageLimit"])
        )
    }

    static func parseCarrierMode(_ value: Any?) -> CarrierMode? {
        guard let d = value as? [String: Any] else { return nil }
        return CarrierMode(
            lowVoltage: intVal(d["CarrierModeLowVoltage"]),
            highVoltage: intVal(d["CarrierModeHighVoltage"]),
            status: intVal(d["CarrierModeStatus"])
        )
    }

    static func parseShutdownReason(_ value: Any?) -> BatteryShutdownReason? {
        guard let d = value as? [String: Any] else { return nil }
        return BatteryShutdownReason(
            shutDownVoltage: intVal(d["ShutDownVoltage"]),
            shutDownTemperature: intVal(d["ShutDownTemperature"]),
            shutDownTimestamp: intVal(d["ShutDownTimestamp"]),
            shutDownFullChargeCapacity: intVal(d["ShutDownFullChargeCapacity"]),
            shutDownNominalChargeCapacity: intVal(d["ShutDownNominalChargeCapacity"]),
            shutDownRemainingCapacity: intVal(d["ShutDownRemainingCapacity"]),
            shutDownPassedCharge: intVal(d["ShutDownPassedCharge"]),
            dataError: intVal(d["ShutDownDataError"]),
            criticalFlags: intVal(d["ShutdownDataCriticalFlagsKey"])
        )
    }

    static func parseAdapterDetails(_ value: Any?) -> AdapterInfo? {
        guard let d = value as? [String: Any] else { return nil }
        let watts = (d["Watts"] as? NSNumber)?.intValue
        let hvcMenu = parseHVCMenu(d["UsbHvcMenu"])
        return AdapterInfo(
            watts: watts,
            isCharging: nil,
            source: nil,
            voltageMV: (d["AdapterVoltage"] as? NSNumber)?.intValue,
            currentMA: (d["Current"] as? NSNumber)?.intValue,
            adapterDescription: d["Description"] as? String,
            powerTier: (d["AdapterPowerTier"] as? NSNumber)?.intValue,
            isWireless: (d["IsWireless"] as? NSNumber)?.boolValue,
            hvcMenu: hvcMenu,
            hvcActiveIndex: (d["UsbHvcHvcIndex"] as? NSNumber)?.intValue,
            familyCode: (d["FamilyCode"] as? NSNumber)?.intValue,
            adapterID: (d["AdapterID"] as? NSNumber)?.intValue,
            pmuConfiguration: (d["PMUConfiguration"] as? NSNumber)?.intValue,
            manufacturer: nonEmptyString(d["Manufacturer"]),
            name: nonEmptyString(d["Name"]),
            model: nonEmptyString(d["Model"])
        )
    }

    /// Returns the value as a non-empty trimmed string, or nil when the
    /// value is missing or only whitespace. Used so the AdapterDetails
    /// identity fields (Manufacturer, Name, Model) are either present-
    /// and-meaningful or nil, with no in-between empty case.
    ///
    /// Accepts both `String` and `NSNumber`. IOKit's AdapterDetails dict
    /// has stored `Model` as a string ("0x7019") in every observed
    /// sample, but the dict is `[String: Any]` and a future macOS or a
    /// different brick could return it as a number; recover that case
    /// rather than silently dropping it.
    static func nonEmptyString(_ value: Any?) -> String? {
        let raw: String?
        if let s = value as? String {
            raw = s
        } else if let n = value as? NSNumber {
            raw = n.stringValue
        } else {
            raw = nil
        }
        guard let s = raw else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseHVCMenu(_ value: Any?) -> [AdapterHVCEntry] {
        guard let arr = value as? [[String: Any]] else { return [] }
        return arr.compactMap { entry in
            guard let mv = (entry["MaxVoltage"] as? NSNumber)?.intValue,
                  let ma = (entry["MaxCurrent"] as? NSNumber)?.intValue else { return nil }
            return AdapterHVCEntry(voltageMV: mv, currentMA: ma)
        }
    }

    static func parsePowerTelemetry(_ value: Any?) -> PowerTelemetrySystemData? {
        guard let d = value as? [String: Any] else { return nil }
        return PowerTelemetrySystemData(
            systemVoltageIn: intVal(d["SystemVoltageIn"]),
            systemCurrentIn: intVal(d["SystemCurrentIn"]),
            systemPowerIn: intVal(d["SystemPowerIn"]),
            systemLoad: intVal(d["SystemLoad"]),
            batteryPower: intVal(d["BatteryPower"]),
            wallEnergyEstimate: intVal(d["WallEnergyEstimate"]),
            adapterEfficiencyLoss: intVal(d["AdapterEfficiencyLoss"]),
            systemEnergyConsumed: intVal(d["SystemEnergyConsumed"]),
            powerTelemetryErrorCount: intVal(d["PowerTelemetryErrorCount"]),
            accumulatedSystemPowerIn: intVal(d["AccumulatedSystemPowerIn"]),
            accumulatedSystemLoad: intVal(d["AccumulatedSystemLoad"]),
            accumulatedSystemEnergyConsumed: intVal(d["AccumulatedSystemEnergyConsumed"]),
            accumulatedWallEnergyEstimate: intVal(d["AccumulatedWallEnergyEstimate"]),
            accumulatedBatteryPower: intVal(d["AccumulatedBatteryPower"]),
            accumulatedBatteryDischarge: intVal(d["AccumulatedBatteryDischarge"]),
            accumulatedAdapterEfficiencyLoss: intVal(d["AccumulatedAdapterEfficiencyLoss"]),
            systemPowerInAccumulatorCount: intVal(d["SystemPowerInAccumulatorCount"]),
            systemLoadAccumulatorCount: intVal(d["SystemLoadAccumulatorCount"]),
            batteryPowerAccumulatorCount: intVal(d["BatteryPowerAccumulatorCount"]),
            batteryDischargeAccumulatorCount: intVal(d["BatteryDischargeAccumulatorCount"]),
            adapterEfficiencyLossAccumulatorCount: intVal(d["AdapterEfficiencyLossAccumulatorCount"])
        )
    }

    /// Parses the `PortControllerInfo` array into the shared entry model.
    ///
    /// Uses the tolerant `wcArray` / `wcDictionary` / `wcUInt32` helpers rather
    /// than a direct `as? [[String: Any]]` cast. IOKit hands these back as CF
    /// types, and every other reader in the app already goes through the
    /// tolerant helpers; the strict cast here was the odd one out. An array
    /// shape the cast would have rejected wholesale now yields entries instead
    /// of silently nothing.
    ///
    /// The PDO array is zero-filled, not compacted: a non-numeric element
    /// keeps its slot. `PortControllerPortPDO` is a fixed 13-slot layout and
    /// the RDO's object position names a slot number in it, so dropping one
    /// element shifts every later slot down one and the position lookup then
    /// selects the wrong PDO, on exactly the M1 Pro/Max machines synthesis
    /// exists for. Dropping was defensible while this array was cut to
    /// `PortControllerNPDOs` and the position lookup mostly fell out of range
    /// anyway; now that the array is passed through whole and indexed by
    /// position, it is not defensible. `contract(from:)` in
    /// `PortDiagnosticsWatcher` keeps the slot the same way, via `wcUInt32`,
    /// and the two producers must not disagree about position. Every OTHER
    /// `compactMap` in this function is unchanged: see `optionalUInt32` for
    /// why dropping is still right where position carries no meaning.
    static func parsePortControllerInfo(_ value: Any?) -> [PortControllerEntry] {
        let arr = wcArray(value).map(wcDictionary)
        guard !arr.isEmpty else { return [] }
        return arr.enumerated().map { offset, d in
            let pdos = wcArray(d["PortControllerPortPDO"]).map { optionalUInt32($0) ?? 0 }
            return PortControllerEntry(
                portIndex: offset + 1,
                firmwareVersion: intVal(d["PortControllerFwVersion"]),
                powerState: intVal(d["PortControllerPowerState"]),
                portMode: intVal(d["PortControllerPortMode"]),
                maxPower: intVal(d["PortControllerMaxPower"]),
                activeContractRdo: uint32Val(d["PortControllerActiveContractRdo"]),
                numberOfPDOs: intVal(d["PortControllerNPDOs"]),
                numberOfEprPDOs: intVal(d["PortControllerNEprPDOs"]),
                portPDOs: pdos,
                fetStatus: intVal(d["PortControllerFetStatus"]),
                bootFlags: intVal(d["PortControllerBootFlags"]),
                capMismatch: intVal(d["PortControllerCapMismatch"]),
                attachCount: intVal(d["PortControllerAttachCount"]),
                detachCount: intVal(d["PortControllerDetachCount"]),
                hardResetCount: intVal(d["PortControllerHardResetCount"]),
                dataRoleSwapCount: intVal(d["PortControllerDataRoleSwapCount"]),
                dataRoleSwapFailCount: intVal(d["PortControllerDataRoleSwapFailCount"]),
                pwrRoleSwapCount: intVal(d["PortControllerPwrRoleSwapCount"]),
                pwrRoleSwapFailCount: intVal(d["PortControllerPwrRoleSwapFailCount"]),
                vdoFailCount: intVal(d["PortControllerVdoFailCount"]),
                shortDetectCount: intVal(d["PortControllerShortDetectCount"]),
                wakeFailCount: intVal(d["PortControllerWakeFailCount"]),
                wakeTimeoutCount: intVal(d["PortControllerWakeTimeoutCount"]),
                sleepCmdFailCount: intVal(d["PortControllerSleepCmdFailCount"]),
                wakeCmdFailCount: intVal(d["PortControllerWakeCmdFailCount"]),
                stuckCmdCount: intVal(d["PortControllerStuckCmdCount"]),
                surpriseAckCount: intVal(d["PortControllerSurpriseAckCount"]),
                surpriseNackCount: intVal(d["PortControllerSurpriseNackCount"]),
                srdyCount: intVal(d["PortControllerSrdyCount"]),
                srdoCount: intVal(d["PortControllerSrdoCount"]),
                srdyRejectCount: intVal(d["PortControllerSrdyRejectCount"]),
                srdoRejectCount: intVal(d["PortControllerSrdoRejectCount"]),
                srdoRetryCount: intVal(d["PortControllerSrdoRetryCount"]),
                hvEnRecoveryCount: intVal(d["PortControllerHvEnRecoveryCount"]),
                inpFetEnFailCount: intVal(d["PortControllerInpFetEnFailCount"]),
                i2cErrCount: intVal(d["PortControllerI2cErrCount"]),
                loserReason: intVal(d["PortControllerLoserReason"]),
                electionFailReason: intVal(d["PortControllerElectionFailReason"]),
                uvdmStatus: intVal(d["PortControllerUvdmStatus"]),
                srcTypes: intVal(d["PortControllerSrcTypes"]),
                dnSt: intVal(d["PortControllerDnSt"]),
                pdSt: intVal(d["PortControllerPDst"]),
                isSleepEnabled: intVal(d["PortControllerSlpWakIsSleepEnabled"]) != 0,
                sleepDisableTime: intVal(d["PortControllerSlpWakDisTime"]),
                sleepDisableCause: intVal(d["PortControllerSlpWakDisCause"])
            )
        }
    }

    // MARK: - FedDetails

    static func parseFedDetails(_ value: Any?) -> [FederatedIdentity] {
        guard let arr = value as? NSArray else { return [] }
        var results: [FederatedIdentity] = []
        for (offset, element) in arr.enumerated() {
            guard let entry = element as? NSDictionary else { continue }
            let vid = (entry["FedVendorID"] as? NSNumber)?.intValue ?? 0
            let pid = (entry["FedProductID"] as? NSNumber)?.intValue ?? 0
            let pdRev = (entry["FedPdSpecRevision"] as? NSNumber)?.intValue ?? 0
            let role = (entry["FedPortPowerRole"] as? NSNumber)?.intValue ?? 0
            let drp = (entry["FedDualRolePower"] as? NSNumber)?.intValue ?? 0
            let ext = (entry["FedExternalConnected"] as? NSNumber)?.intValue ?? 0
            results.append(FederatedIdentity(
                portIndex: offset + 1,
                vendorID: vid,
                productID: pid,
                pdSpecRevision: pdRev,
                powerRole: role,
                dualRolePower: drp != 0,
                externalConnected: ext != 0
            ))
        }
        return results
    }

    // MARK: - Helpers

    // These three delegate to the module's shared `wc*` helpers rather than
    // carrying their own narrower copies.
    //
    // Found by the Codex review of the commit that routed the synthesis path
    // through this parser. That path previously read its fields with `wcInt`,
    // which accepts a numeric STRING; the local `intVal` here did not, and
    // turned "60000" into 0. So a consolidation meant to change nothing had
    // quietly picked the stricter of two helpers and would have made an
    // M1 Pro's synthesized contract vanish if macOS ever string-encoded
    // `PortControllerMaxPower`. Nobody has seen that encoding. The point is
    // that the old code tolerated it and the new code did not, and nothing
    // said so.
    //
    // Delegating widens the typed `AppleSmartBattery` model too. That is a fix,
    // not a regression: a field that used to read 0 from a string now reads the
    // number.
    static func intVal(_ value: Any?) -> Int {
        wcInt(value)
    }

    static func uint32Val(_ value: Any?) -> UInt32 {
        if let u = value as? UInt32 { return u }
        // Via `wcInt` so a numeric string converts here too. `wcUInt32` alone
        // would return 0 for one, reintroducing half the bug above.
        return UInt32(truncatingIfNeeded: wcInt(value))
    }

    static func boolVal(_ value: Any?) -> Bool {
        wcBool(value)
    }

    /// A PDO array element, or nil when it is not a number at all.
    ///
    /// Deliberately NOT `wcUInt32`, which returns 0 for a non-number. The array
    /// this feeds is indexed positionally by the RDO's object-position field,
    /// so dropping an element and zero-filling it are genuinely different
    /// answers, and the old parser dropped. Zero-filling is arguably the better
    /// behaviour, but "arguably better" is not what a no-behaviour-change phase
    /// gets to ship: there is nothing to gain, since every one of the 34,566 PDO
    /// elements across 585 corpus dumps is a clean number. If we ever want the
    /// position-preserving form, that is its own change with its own evidence.
    private static func optionalUInt32(_ value: Any?) -> UInt32? {
        if let n = value as? NSNumber { return UInt32(truncatingIfNeeded: n.int64Value) }
        if let i = value as? Int { return UInt32(truncatingIfNeeded: i) }
        if let u = value as? UInt32 { return u }
        return nil
    }
}
