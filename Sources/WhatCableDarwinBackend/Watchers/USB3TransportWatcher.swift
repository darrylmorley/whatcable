import Foundation
import IOKit
import WhatCableCore

/// Watches `IOPortTransportStateUSB3` services. These appear dynamically
/// when a USB 3 SuperSpeed device is connected and disappear on unplug.
/// Each service carries the negotiated signaling generation (Gen 1 / Gen 2)
/// which lets the app show the precise USB 3 speed instead of a generic
/// "5 Gbps or faster" label.
@MainActor
public final class USB3TransportWatcher: ObservableObject {
    /// Bumped on every change to the published state, from any path (apply,
    /// match/terminate handlers, drain, stop). The hub compares it before and
    /// after its background read so a stale read never overwrites newer state.
    public private(set) var refreshGeneration = 0
    @Published public private(set) var transports: [USB3Transport] = [] {
        didSet { refreshGeneration &+= 1 }
    }

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
            let w = Unmanaged<USB3TransportWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handleAdded(iter) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<USB3TransportWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handleRemoved(iter) }
        }

        // Only drain the iterator when registration succeeds. The out-parameter
        // iterator is only valid on KERN_SUCCESS; passing an uninitialised value
        // to IOIteratorNext is undefined behaviour. Sibling pattern: USBPDSOPWatcher.
        let matching = IOServiceMatching("IOPortTransportStateUSB3")
        if IOServiceAddMatchingNotification(port, kIOMatchedNotification, matching, added, selfPtr, &addedIter) == KERN_SUCCESS {
            handleAdded(addedIter)
        }

        let matching2 = IOServiceMatching("IOPortTransportStateUSB3")
        if IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching2, removed, selfPtr, &removedIter) == KERN_SUCCESS {
            handleRemoved(removedIter)
        }
    }

    public func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
        transports.removeAll()
    }

    public func refresh() { apply(Self.readTransports()) }

    public func apply(_ transports: [USB3Transport]) {
        if transports != self.transports { self.transports = transports }
    }

    nonisolated public static func readTransports() -> [USB3Transport] {
        // Build locally and assign once so subscribers never see a transient
        // empty list mid-refresh. See issue #227.
        var rebuilt: [USB3Transport] = []
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportStateUSB3"), &iter) == KERN_SUCCESS {
            defer { IOObjectRelease(iter) }
            let found = wcDrainAllRetrying(iter) { service in makeTransport(from: service) }
            for t in found {
                guard let t, !rebuilt.contains(where: { $0.id == t.id }) else { continue }
                rebuilt.append(t)
            }
        }
        return rebuilt
    }

    private func handleAdded(_ iter: io_iterator_t) {
        let found = wcDrainAllRetrying(iter) { service in Self.makeTransport(from: service) }
        for t in found {
            guard let t, !transports.contains(where: { $0.id == t.id }) else { continue }
            transports.append(t)
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
        }
    }

    // MARK: - IOKit wrapper (private)

    nonisolated private static func makeTransport(from service: io_service_t) -> USB3Transport? {
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

        // Walk the parent chain to get the HPM controller UUID so this
        // transport can be matched to its port by identity, not by @N.
        let uuid = wcHPMControllerUUID(for: service)
        return Self.makeTransport(entryID: entryID, read: read, hpmControllerUUID: uuid, model: DarwinSystemInfo.macModel)
    }

    // MARK: - Parse function (internal, testable)

    /// Parse a USB3 transport from a property-read closure. The `hpmControllerUUID`
    /// is passed in so the caller can walk the parent chain once and tests can
    /// supply nil without IOKit.
    ///
    /// `model` is the Mac's `hw.model`: the parent-port keys are read through
    /// `PortNumberingCorrection` so this transport joins the corrected port
    /// card. Required with no default; tests pass nil.
    nonisolated static func makeTransport(
        entryID: UInt64,
        read: (String) -> Any?,
        hpmControllerUUID: String?,
        model: String?
    ) -> USB3Transport? {
        PortNumberingCorrection.correctingRead(read, model: model) { read in
            parseTransport(entryID: entryID, read: read, hpmControllerUUID: hpmControllerUUID)
        }
    }

    nonisolated private static func parseTransport(
        entryID: UInt64,
        read: (String) -> Any?,
        hpmControllerUUID: String?
    ) -> USB3Transport? {
        let parentType = (read("ParentBuiltInPortType") as? NSNumber)?.intValue
            ?? (read("ParentPortType") as? NSNumber)?.intValue
            ?? 0
        let parentNumber = (read("ParentBuiltInPortNumber") as? NSNumber)?.intValue
            ?? (read("ParentPortNumber") as? NSNumber)?.intValue
            ?? Int(((read("Priority") as? NSNumber)?.uint64Value ?? 0) & 0xFF)
        let portKey = "\(parentType)/\(parentNumber)"

        let signaling = (read("SuperSpeedSignaling") as? NSNumber)?.intValue
        let signalingDesc = read("SuperSpeedSignalingDescription") as? String
        let dataRole = (read("DataRole") as? String)
            ?? (read("PortDataRole") as? String)
        let active = (read("Active") as? NSNumber)?.boolValue
        let transportRestricted = (read("TRM_TransportRestricted") as? NSNumber)?.boolValue
        let tunnelled = (read("Tunneled") as? NSNumber)?.boolValue

        return USB3Transport(
            id: entryID,
            portKey: portKey,
            signaling: signaling,
            signalingDescription: signalingDesc,
            dataRole: dataRole,
            hpmControllerUUID: hpmControllerUUID,
            active: active,
            transportRestricted: transportRestricted,
            tunnelled: tunnelled
        )
    }
}

extension USB3TransportWatcher {
    /// USB3 transports attached to a given port.
    /// Uses UUID-based matching when available (M3+), else portKey fallback.
    public func transports(for port: AppleHPMInterface) -> [USB3Transport] {
        return transports.filter { $0.canonicallyMatches(port: port) }
    }
}
