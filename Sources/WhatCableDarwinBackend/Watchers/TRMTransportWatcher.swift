import Foundation
import IOKit
import WhatCableCore

/// Watches `IOPortTransportState*` services for TRM (Trust and Restrict
/// Management) properties and CIO cable capability data. These transport
/// services appear dynamically when a USB-C accessory is connected and
/// disappear on unplug.
///
/// Each transport (USB2, DisplayPort, etc.) can carry its own TRM state,
/// so a single port might have USB2 restricted while DisplayPort is not.
///
/// CIO transports additionally carry cable capability fields
/// (`CableGeneration`, `CableSpeed`, etc.) that represent the TB
/// controller's assessment of the cable, independent of the USB-PD
/// e-marker. These are published separately as `CIOCableCapability`.
@MainActor
public final class TRMTransportWatcher: ObservableObject {
    @Published public private(set) var transports: [TRMTransport] = []
    @Published public private(set) var cioCapabilities: [CIOCableCapability] = []

    // Transport state classes that carry TRM properties. USB2 and
    // DisplayPort are the ones confirmed to have meaningful TRM data.
    // USB3 and CIO may also carry TRM state when those transports are
    // active, so we watch them too.
    nonisolated static let watchedClasses = [
        "IOPortTransportStateUSB2",
        "IOPortTransportStateDisplayPort",
        "IOPortTransportStateUSB3",
        "IOPortTransportStateCIO",
    ]

    private var notifyPort: IONotificationPortRef?
    private var addedIters: [io_iterator_t] = []
    private var removedIters: [io_iterator_t] = []

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let added: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<TRMTransportWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handleAdded(iter) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<TRMTransportWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handleRemoved(iter) }
        }

        for cls in Self.watchedClasses {
            var addIter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(port, kIOMatchedNotification,
                                                 IOServiceMatching(cls),
                                                 added, selfPtr, &addIter) == KERN_SUCCESS {
                addedIters.append(addIter)
                handleAdded(addIter)
            }

            var rmIter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                                 IOServiceMatching(cls),
                                                 removed, selfPtr, &rmIter) == KERN_SUCCESS {
                removedIters.append(rmIter)
                handleRemoved(rmIter)
            }
        }
    }

    public func stop() {
        for iter in addedIters { IOObjectRelease(iter) }
        addedIters.removeAll()
        for iter in removedIters { IOObjectRelease(iter) }
        removedIters.removeAll()
        if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
        transports.removeAll()
        cioCapabilities.removeAll()
    }

    public func refresh() {
        // Build both lists locally and assign once. Mutating the published
        // properties in place (removeAll then re-append) emits a transient
        // empty value that downstream subscribers see as "everything gone."
        // See issue #227.
        var rebuiltTransports: [TRMTransport] = []
        var rebuiltCIO: [CIOCableCapability] = []
        for cls in Self.watchedClasses {
            var iter: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS {
                defer { IOObjectRelease(iter) }
                let results = wcDrainAllRetrying(iter) { service -> (transport: TRMTransport?, cio: CIOCableCapability?)? in
                    var entryID: UInt64 = 0
                    guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }

                    func read(_ key: String) -> Any? {
                        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                    }

                    var classBuf = [CChar](repeating: 0, count: 128)
                    guard IOObjectGetClass(service, &classBuf) == KERN_SUCCESS else { return nil }
                    let className = String(cString: classBuf)
                    let transportType = Self.transportType(from: className)

                    let t = makeTRMTransport(entryID: entryID, service: service, read: read, transportType: transportType)
                    let c = transportType == "CIO" ? makeCIOCapability(entryID: entryID, service: service, read: read) : nil
                    return (t, c)
                }
                for result in results {
                    guard let result else { continue }
                    if let t = result.transport, !rebuiltTransports.contains(where: { $0.id == t.id }) {
                        rebuiltTransports.append(t)
                    }
                    if let c = result.cio, !rebuiltCIO.contains(where: { $0.id == c.id }) {
                        rebuiltCIO.append(c)
                    }
                }
            }
        }
        if rebuiltTransports != transports { transports = rebuiltTransports }
        if rebuiltCIO != cioCapabilities { cioCapabilities = rebuiltCIO }
    }

    private func handleAdded(_ iter: io_iterator_t) {
        let results = wcDrainAllRetrying(iter) { service -> (transport: TRMTransport?, cio: CIOCableCapability?)? in
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }

            // Read keys individually rather than fetching the full property
            // dictionary. The bulk fetch (IORegistryEntryCreateCFProperties)
            // can abort the process from inside IOCFUnserializeBinary when
            // the kernel returns a malformed serialised properties blob,
            // typically when the service is being torn down mid-read. The
            // per-key call has no such failure path. See issue #181.
            func read(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }

            var classBuf = [CChar](repeating: 0, count: 128)
            guard IOObjectGetClass(service, &classBuf) == KERN_SUCCESS else { return nil }
            let className = String(cString: classBuf)
            let transportType = Self.transportType(from: className)

            let t = makeTRMTransport(entryID: entryID, service: service, read: read, transportType: transportType)
            let c = transportType == "CIO" ? makeCIOCapability(entryID: entryID, service: service, read: read) : nil
            return (t, c)
        }
        for result in results {
            guard let result else { continue }
            if let t = result.transport, !transports.contains(where: { $0.id == t.id }) {
                transports.append(t)
            }
            if let c = result.cio, !cioCapabilities.contains(where: { $0.id == c.id }) {
                cioCapabilities.append(c)
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
            transports.removeAll { $0.id == entryID }
            cioCapabilities.removeAll { $0.id == entryID }
        }
    }

    // MARK: - IOKit wrapper (private)

    private func makeTRMTransport(entryID: UInt64, service: io_service_t, read: (String) -> Any?, transportType: String) -> TRMTransport? {
        let uuid = wcHPMControllerUUID(for: service)
        return Self.makeTRMTransport(entryID: entryID, read: read, transportType: transportType, hpmControllerUUID: uuid)
    }

    private func makeCIOCapability(entryID: UInt64, service: io_service_t, read: (String) -> Any?) -> CIOCableCapability? {
        let uuid = wcHPMControllerUUID(for: service)
        return Self.makeCIOCapability(entryID: entryID, read: read, hpmControllerUUID: uuid)
    }

    // MARK: - Parse functions (internal, testable)

    /// Parse a TRM transport from a property-read closure. The `hpmControllerUUID`
    /// is passed in rather than looked up here so the caller (an IOKit wrapper)
    /// can walk the parent chain once and tests can supply nil without IOKit.
    ///
    /// Gate: returns nil when TRM_State is absent (no TRM data on this service).
    nonisolated static func makeTRMTransport(
        entryID: UInt64,
        read: (String) -> Any?,
        transportType: String,
        hpmControllerUUID: String?
    ) -> TRMTransport? {
        // Use TRM_State as the presence gate: it is the primary TRM field and
        // is always published when TRM data exists. This replaces the old
        // dict.keys.contains { $0.hasPrefix("TRM_") } check, which required
        // the full bulk dict and cannot be reproduced with per-key reads.
        // Cache the value here so the guard and the field assignment share
        // the same IOKit call -- avoiding a second round-trip and a potential
        // race if the service transitions state between the two reads.
        let trmStateRaw = read("TRM_State")
        guard trmStateRaw != nil else { return nil }

        let parent = parentPortIdentity(read: read)
        let portKey = "\(parent.type)/\(parent.number)"

        return TRMTransport(
            id: entryID,
            portKey: portKey,
            transportType: transportType,
            state: (trmStateRaw as? NSNumber)?.intValue,
            stateDescription: read("TRM_StateDescription") as? String,
            transportRestricted: (read("TRM_TransportRestricted") as? NSNumber)?.boolValue,
            transportSupervised: (read("TRM_TransportSupervised") as? NSNumber)?.boolValue,
            identificationRestricted: (read("TRM_IdentificationRestricted") as? NSNumber)?.boolValue,
            deviceLocked: (read("TRM_DeviceLocked") as? NSNumber)?.boolValue,
            relaxedPeriod: (read("TRM_RelaxedPeriod") as? NSNumber)?.boolValue,
            gracePeriodReason: (read("TRM_GracePeriodReason") as? NSNumber)?.intValue,
            gracePeriodReasonDescription: read("TRM_GracePeriodReasonDescription") as? String,
            profile: (read("TRM_Profile") as? NSNumber)?.intValue,
            profileDescription: read("TRM_ProfileDescription") as? String,
            cacheMiss: (read("TRM_CacheMiss") as? NSNumber)?.boolValue,
            tunnelled: (read("Tunneled") as? NSNumber)?.boolValue,
            hpmControllerUUID: hpmControllerUUID
        )
    }

    /// Parse a CIO cable capability from a property-read closure. The
    /// `hpmControllerUUID` is passed in so tests can supply nil without IOKit.
    ///
    /// Unlike TRM, CIO has no hard gate key -- any IOPortTransportStateCIO
    /// service is a valid candidate. Callers guard on transportType == "CIO".
    /// An explicit `Active: false` is filtered here (see gate below): it
    /// means the CIO leg is not currently up, even though a cable can be
    /// seated (measured: on every affected corpus port, the port's own HPM
    /// node shows `ConnectionActive`/`PlugOrientation` for a plugged cable).
    nonisolated static func makeCIOCapability(
        entryID: UInt64,
        read: (String) -> Any?,
        hpmControllerUUID: String?
    ) -> CIOCableCapability? {
        // `Active: false` means the CIO leg is not currently up -- a cable
        // can still be seated (measured: corpus ports carrying this row also
        // show ConnectionActive/PlugOrientation for a plugged cable, with
        // only CC active). In most observed cases (3 of 4 affected ports)
        // the accessory is TRM-restricted/Unauthorized. Either way, a row
        // like that must never reach a consumer as if it described a live
        // link. Absence of the key is not a gate here (see doc comment
        // above) -- only an explicit `false` drops the row. Across the whole
        // corpus, `Active` is present on all 707 real CIO blocks (700 true,
        // 7 false, 0 absent), so the absent-key branch is only exercised by
        // a synthetic test; it stays because IOKit gives no guarantee the
        // key is always present, and failing open (treat unknown as active)
        // is the safer default for a field with no observed absence case.
        if (read("Active") as? NSNumber)?.boolValue == false {
            return nil
        }

        let parent = parentPortIdentity(read: read)
        let portKey = "\(parent.type)/\(parent.number)"

        return CIOCableCapability(
            id: entryID,
            portKey: portKey,
            cableGeneration: (read("CableGeneration") as? NSNumber)?.intValue,
            negotiatedLinkSpeed: (read("CableSpeed") as? NSNumber)?.intValue,
            generation: (read("Generation") as? NSNumber)?.intValue,
            asymmetricModeSupported: (read("AsymmetricModeSupported") as? NSNumber)?.boolValue,
            legacyAdapter: (read("LegacyAdapter") as? NSNumber)?.boolValue,
            linkTrainingMode: (read("LinkTrainingMode") as? NSNumber)?.intValue,
            hpmControllerUUID: hpmControllerUUID
        )
    }

    /// Reads the parent port type and number from the service's properties.
    /// Same approach as `USB3TransportWatcher` and `PowerSourceWatcher`.
    nonisolated static func parentPortIdentity(read: (String) -> Any?) -> (type: Int, number: Int) {
        let type = (read("ParentBuiltInPortType") as? NSNumber)?.intValue
            ?? (read("ParentPortType") as? NSNumber)?.intValue
            ?? 0
        let number = (read("ParentBuiltInPortNumber") as? NSNumber)?.intValue
            ?? (read("ParentPortNumber") as? NSNumber)?.intValue
            ?? Int(((read("Priority") as? NSNumber)?.uint64Value ?? 0) & 0xFF)
        return (type, number)
    }

    /// Extracts a short transport type label from the IOKit class name.
    /// "IOPortTransportStateUSB2" -> "USB2", etc.
    nonisolated static func transportType(from className: String) -> String {
        let prefix = "IOPortTransportState"
        if className.hasPrefix(prefix) {
            return String(className.dropFirst(prefix.count))
        }
        return className
    }
}
