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
    @Published public private(set) var transports: [USB3Transport] = []

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
            Task { @MainActor in w.handleAdded(iter) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<USB3TransportWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in w.handleRemoved(iter) }
        }

        let matching = IOServiceMatching("IOPortTransportStateUSB3")
        IOServiceAddMatchingNotification(port, kIOMatchedNotification, matching, added, selfPtr, &addedIter)
        handleAdded(addedIter)

        let matching2 = IOServiceMatching("IOPortTransportStateUSB3")
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching2, removed, selfPtr, &removedIter)
        handleRemoved(removedIter)
    }

    public func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
        transports.removeAll()
    }

    public func refresh() {
        // Build locally and assign once so subscribers never see a transient
        // empty list mid-refresh. See issue #227.
        var rebuilt: [USB3Transport] = []
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportStateUSB3"), &iter) == KERN_SUCCESS {
            while case let service = IOIteratorNext(iter), service != 0 {
                if let t = makeTransport(from: service), !rebuilt.contains(where: { $0.id == t.id }) {
                    rebuilt.append(t)
                }
                IOObjectRelease(service)
            }
            IOObjectRelease(iter)
        }
        if rebuilt != transports { transports = rebuilt }
    }

    private func handleAdded(_ iter: io_iterator_t) {
        while case let service = IOIteratorNext(iter), service != 0 {
            if let t = makeTransport(from: service), !transports.contains(where: { $0.id == t.id }) {
                transports.append(t)
            }
            IOObjectRelease(service)
        }
    }

    private func handleRemoved(_ iter: io_iterator_t) {
        while case let service = IOIteratorNext(iter), service != 0 {
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            transports.removeAll { $0.id == entryID }
            IOObjectRelease(service)
        }
    }

    private func makeTransport(from service: io_service_t) -> USB3Transport? {
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryID)

        // Read keys individually rather than fetching the full property
        // dictionary. The bulk fetch (IORegistryEntryCreateCFProperties)
        // can abort the process from inside IOCFUnserializeBinary when
        // the kernel returns a malformed serialised properties blob,
        // typically when the service is being torn down mid-read. The
        // per-key call has no such failure path. See issue #181.
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

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

        return USB3Transport(
            id: entryID,
            portKey: portKey,
            signaling: signaling,
            signalingDescription: signalingDesc,
            dataRole: dataRole
        )
    }
}

extension USB3TransportWatcher {
    /// USB3 transports attached to a given port.
    public func transports(for port: AppleHPMInterface) -> [USB3Transport] {
        guard let key = port.portKey else { return [] }
        return transports.filter { $0.portKey == key }
    }
}
