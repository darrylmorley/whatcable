#if os(macOS)
import Foundation
import IOKit
import WhatCableCore

/// Watches `IOPortTransportComponentCCUSBPDSOP` services. These hold the PD
/// Discover Identity response for the port partner (SOP) and any e-marker
/// chips on the cable (SOP', SOP'').
@MainActor
public final class PDIdentityWatcher: ObservableObject {
    @Published public private(set) var identities: [PDIdentity] = []

    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let added: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<PDIdentityWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in w.handleAdded(iter) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<PDIdentityWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in w.handleRemoved(iter) }
        }

        IOServiceAddMatchingNotification(port, kIOMatchedNotification,
            IOServiceMatching("IOPortTransportComponentCCUSBPDSOP"),
            added, selfPtr, &addedIter)
        handleAdded(addedIter)

        IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
            IOServiceMatching("IOPortTransportComponentCCUSBPDSOP"),
            removed, selfPtr, &removedIter)
        handleRemoved(removedIter)
    }

    public func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
        identities.removeAll()
    }

    public func refresh() {
        identities.removeAll()
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOPortTransportComponentCCUSBPDSOP"), &iter) == KERN_SUCCESS {
            handleAdded(iter)
            IOObjectRelease(iter)
        }
    }

    private func handleAdded(_ iter: io_iterator_t) {
        while case let service = IOIteratorNext(iter), service != 0 {
            if let identity = makeIdentity(from: service),
               !identities.contains(where: { $0.id == identity.id }) {
                identities.append(identity)
            }
            IOObjectRelease(service)
        }
    }

    private func handleRemoved(_ iter: io_iterator_t) {
        while case let service = IOIteratorNext(iter), service != 0 {
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            identities.removeAll { $0.id == entryID }
            IOObjectRelease(service)
        }
    }

    private func makeIdentity(from service: io_service_t) -> PDIdentity? {
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryID)

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let endpoint = Self.endpoint(from: dict)
        let parent = Self.parentPortIdentity(from: dict)
        let specRev = (dict["Specification Revision"] as? NSNumber)?.intValue ?? 0

        let metadata = Self.metadataDictionary(from: dict)
        let vendorID = Self.vendorID(from: dict, metadata: metadata)
        let productID = Self.productID(from: dict, metadata: metadata)
        let bcdDevice = Self.bcdDevice(from: metadata)

        let vdos: [UInt32] = ((metadata["VDOs"] as? [Any]) ?? []).compactMap { value in
            guard let data = value as? Data else { return nil }
            return PDVDO.vdoFromData(data)
        }

        return PDIdentity(
            id: entryID,
            endpoint: endpoint,
            parentPortType: parent.type,
            parentPortNumber: parent.number,
            vendorID: vendorID,
            productID: productID,
            bcdDevice: bcdDevice,
            vdos: vdos,
            specRevision: specRev
        )
    }

    nonisolated static func endpointName(from dict: [String: Any]) -> String {
        (dict["ComponentName"] as? String)
            ?? (dict["AddressDescription"] as? String)
            ?? (dict["Address Description"] as? String)
            ?? (dict["TransportTypeDescription"] as? String)
            ?? "Unknown"
    }

    nonisolated static func endpoint(from dict: [String: Any]) -> PDIdentity.Endpoint {
        if let name = (dict["ComponentName"] as? String)
            ?? (dict["AddressDescription"] as? String)
            ?? (dict["Address Description"] as? String) {
            return PDIdentity.Endpoint(rawValue: name) ?? .unknown
        }
        // MagSafe CC transport has no ComponentName; map "CC" only from
        // TransportTypeDescription so a future node with ComponentName="CC"
        // is not misclassified as a cable e-marker.
        switch dict["TransportTypeDescription"] as? String {
        case "SOP": return .sop
        case "SOP'", "CC": return .sopPrime
        default: return .unknown
        }
    }

    nonisolated static func parentPortIdentity(from dict: [String: Any]) -> (type: Int, number: Int) {
        let type = (dict["ParentPortType"] as? NSNumber)?.intValue
            ?? (dict["ParentBuiltInPortType"] as? NSNumber)?.intValue
            ?? 0
        let number = (dict["ParentPortNumber"] as? NSNumber)?.intValue
            ?? (dict["ParentBuiltInPortNumber"] as? NSNumber)?.intValue
            ?? 0
        return (type, number)
    }

    nonisolated static func metadataDictionary(from dict: [String: Any]) -> [String: Any] {
        if let metadata = dict["Metadata"] as? [String: Any] {
            return metadata
        }
        if let nsMetadata = dict["Metadata"] as? NSDictionary {
            var converted: [String: Any] = [:]
            for case let (key, value) as (String, Any) in nsMetadata {
                converted[key] = value
            }
            return converted
        }
        return [:]
    }

    nonisolated static func vendorID(from dict: [String: Any], metadata: [String: Any]) -> Int {
        (metadata["Vendor ID"] as? NSNumber)?.intValue
            ?? (metadata["Vendor ID (SOP1)"] as? NSNumber)?.intValue
            ?? (dict["Vendor ID (SOP1)"] as? NSNumber)?.intValue
            ?? (dict["Vendor ID"] as? NSNumber)?.intValue
            ?? 0
    }

    nonisolated static func productID(from dict: [String: Any], metadata: [String: Any]) -> Int {
        (metadata["Product ID"] as? NSNumber)?.intValue
            ?? (metadata["Product ID (SOP1)"] as? NSNumber)?.intValue
            ?? (dict["Product ID (SOP1)"] as? NSNumber)?.intValue
            ?? (dict["Product ID"] as? NSNumber)?.intValue
            ?? 0
    }

    nonisolated static func bcdDevice(from metadata: [String: Any]) -> Int {
        (metadata["bcdDevice"] as? NSNumber)?.intValue ?? 0
    }

    public func identities(for port: USBCPort) -> [PDIdentity] {
        guard let key = port.portKey else { return [] }
        return identities.filter { $0.portKey == key }
    }
}

#endif
