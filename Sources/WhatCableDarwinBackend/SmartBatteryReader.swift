import Foundation
import IOKit
import WhatCableCore

/// Reads AppleSmartBattery properties from IOKit. Desktop Macs have no
/// AppleSmartBattery service at all, or report BatteryInstalled = false.
/// Laptops expose FedDetails (federated per-port PD identity).
public enum SmartBatteryReader {
    public struct Result {
        public let isDesktopMac: Bool
        public let federatedIdentities: [FederatedIdentity]
    }

    public static func read() -> Result {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return Result(isDesktopMac: true, federatedIdentities: [])
        }
        defer { IOObjectRelease(iter) }

        let service = IOIteratorNext(iter)
        guard service != 0 else {
            return Result(isDesktopMac: true, federatedIdentities: [])
        }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return Result(isDesktopMac: true, federatedIdentities: [])
        }

        let batteryInstalled = (dict["BatteryInstalled"] as? Bool) ?? false
        if !batteryInstalled {
            return Result(isDesktopMac: true, federatedIdentities: [])
        }

        let fedDetails = parseFedDetails(dict["FedDetails"])
        return Result(isDesktopMac: false, federatedIdentities: fedDetails)
    }

    private static func parseFedDetails(_ value: Any?) -> [FederatedIdentity] {
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
}
