import Foundation
import IOKit
import WhatCableCore

/// Watches `IOPortTransportProtocolAppleUVDM` services: the node macOS
/// publishes under a port's PD SOP node when an Apple accessory is attached,
/// carrying the accessory's own name over Apple's private UVDM (vendor-defined
/// USB-PD) channel.
@MainActor
public final class AppleUVDMWatcher: ObservableObject {
    @Published public private(set) var identities: [AppleAccessoryIdentity] = []

    nonisolated static let watchedClass = "IOPortTransportProtocolAppleUVDM"

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
            let w = Unmanaged<AppleUVDMWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handleAdded(iter) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<AppleUVDMWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handleRemoved(iter) }
        }

        if IOServiceAddMatchingNotification(port, kIOMatchedNotification,
                                             IOServiceMatching(Self.watchedClass),
                                             added, selfPtr, &addedIter) == KERN_SUCCESS {
            handleAdded(addedIter)
        }

        if IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                             IOServiceMatching(Self.watchedClass),
                                             removed, selfPtr, &removedIter) == KERN_SUCCESS {
            handleRemoved(removedIter)
        }
    }

    public func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
        identities.removeAll()
    }

    public func refresh() {
        // Rebuild locally and assign once. Mutating the published property in
        // place (removeAll then re-append) emits a transient empty value that
        // downstream subscribers read as "everything gone." See issue #227.
        var rebuilt: [AppleAccessoryIdentity] = []
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(Self.watchedClass), &iter) == KERN_SUCCESS {
            defer { IOObjectRelease(iter) }
            let results = wcDrainAllRetrying(iter) { service -> AppleAccessoryIdentity? in
                self.makeAccessoryIdentity(service: service)
            }
            for result in results {
                guard let result else { continue }
                if !rebuilt.contains(where: { $0.id == result.id }) {
                    rebuilt.append(result)
                }
            }
        }
        if rebuilt != identities { identities = rebuilt }
    }

    private func handleAdded(_ iter: io_iterator_t) {
        let results = wcDrainAllRetrying(iter) { service -> AppleAccessoryIdentity? in
            self.makeAccessoryIdentity(service: service)
        }
        for result in results {
            guard let result else { continue }
            if !identities.contains(where: { $0.id == result.id }) {
                identities.append(result)
            }
        }
    }

    private func handleRemoved(_ iter: io_iterator_t) {
        let removedEntryIDs = wcDrainAllRetrying(iter) { service -> UInt64? in
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }
            return entryID
        }
        for entryID in removedEntryIDs {
            guard let entryID else { continue }
            identities.removeAll { $0.id == entryID }
        }
    }

    // MARK: - IOKit wrapper (private)

    private func makeAccessoryIdentity(service: io_service_t) -> AppleAccessoryIdentity? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }

        // Read keys individually rather than fetching the full property
        // dictionary. The bulk fetch (IORegistryEntryCreateCFProperties) can
        // abort the process from inside IOCFUnserializeBinary when the kernel
        // returns a malformed serialised properties blob, typically when the
        // service is being torn down mid-read. The per-key call has no such
        // failure path. See issue #181.
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        let uuid = wcHPMControllerUUID(for: service)
        return Self.makeAccessoryIdentity(entryID: entryID, read: read, hpmControllerUUID: uuid)
    }

    // MARK: - Parse function (internal, testable)

    /// Parse an Apple accessory identity from a property-read closure. The
    /// `hpmControllerUUID` is passed in rather than looked up here so the
    /// caller (an IOKit wrapper) can walk the parent chain once and tests can
    /// supply nil without IOKit.
    ///
    /// Gate: returns nil unless at least one of Manufacturer, Vendor, Product
    /// or User String is present. A node with none of them carries no identity
    /// (eight corpus nodes are exactly that shape).
    nonisolated static func makeAccessoryIdentity(
        entryID: UInt64,
        read: (String) -> Any?,
        hpmControllerUUID: String?
    ) -> AppleAccessoryIdentity? {
        let manufacturer = read("Manufacturer") as? String
        let vendor = read("Vendor") as? String
        let product = read("Product") as? String
        let userString = read("User String") as? String

        guard manufacturer != nil || vendor != nil || product != nil || userString != nil else {
            return nil
        }

        let parent = TRMTransportWatcher.parentPortIdentity(read: read)
        let portKey = "\(parent.type)/\(parent.number)"

        return AppleAccessoryIdentity(
            id: entryID,
            portKey: portKey,
            manufacturer: manufacturer,
            vendor: vendor,
            product: product,
            userString: userString,
            model: read("Model") as? String,
            serialNumber: read("Serial Number") as? String,
            hardwareVersion: read("Hardware Version") as? String,
            vendorID: (read("Vendor ID") as? NSNumber)?.intValue,
            productID: (read("Product ID") as? NSNumber)?.intValue,
            hpmControllerUUID: hpmControllerUUID
        )
    }
}
