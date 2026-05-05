import Foundation
import IOKit
import WhatCableCore

/// Watches USB-C / MagSafe port-controller services. On Apple-silicon Macs the
/// relevant class is `AppleHPMInterfaceType10` (USB-C) and `Type11` (MagSafe).
@MainActor
public final class USBCPortWatcher: ObservableObject {
    @Published public private(set) var ports: [USBCPort] = []

    // Match only Type-C / MagSafe physical port controllers. Generic
    // `AppleUSBHostPort` would sweep in internal DRD (dual-role device)
    // ports — those have no physical connector and just confuse the UI.
    // The exact IOKit class for a USB-C port node varies by chip
    // generation. M3-era machines expose `AppleHPMInterfaceType10/11/12`;
    // M1 and M2 expose `AppleTCControllerType10/11`; M4 Mac mini front
    // USB-C ports can expose the physical port as `IOPort`. The
    // `PortTypeDescription` / `Port-` filter in `makePort` drops anything
    // that isn't a real physical port.
    nonisolated static let candidateClasses = [
        "AppleHPMInterfaceType10",
        "AppleHPMInterfaceType11",
        "AppleHPMInterfaceType12",
        "AppleTCControllerType10",
        "AppleTCControllerType11",
        "IOPort"
    ]

    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    // Interest notifications registered per-port so we hear about property
    // changes (connection state, contract negotiation) as they happen, instead
    // of relying purely on polling. Keyed by registry entry ID so we don't
    // double-register when a port is rediscovered during a manual refresh.
    private var interestNotifications: [UInt64: io_object_t] = [:]

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<USBCPortWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.drain(iterator: iterator) }
        }

        for cls in Self.candidateClasses {
            let matching = IOServiceMatching(cls)
            var iter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(port, kIOMatchedNotification, matching, cb, selfPtr, &iter) == KERN_SUCCESS {
                iterators.append(iter)
                drain(iterator: iter)
            }
        }
    }

    public func stop() {
        for iter in iterators { IOObjectRelease(iter) }
        iterators.removeAll()
        for (_, n) in interestNotifications { IOObjectRelease(n) }
        interestNotifications.removeAll()
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        ports.removeAll()
    }

    /// Re-walk the registry. Property changes (cable plug/unplug) don't fire
    /// match notifications, so callers poll this on demand. Builds the new
    /// list in a local array and assigns once, so observers see a single
    /// transition instead of an empty intermediate state. Skips the
    /// assignment entirely when nothing changed, which keeps the UI calm
    /// when refresh() is called speculatively after every device event.
    public func refresh() {
        var rebuilt: [USBCPort] = []
        for cls in Self.candidateClasses {
            let matching = IOServiceMatching(cls)
            var iter: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS {
                while case let service = IOIteratorNext(iter), service != 0 {
                    if let port = makePort(from: service),
                       !rebuilt.contains(where: { $0.id == port.id }) {
                        rebuilt.append(port)
                        registerInterest(for: service, entryID: port.id)
                    }
                    IOObjectRelease(service)
                }
                IOObjectRelease(iter)
            }
        }
        rebuilt.sort { lhs, rhs in
            let lhsActive = lhs.connectionActive == true
            let rhsActive = rhs.connectionActive == true
            if lhsActive != rhsActive { return lhsActive }
            return lhs.serviceName < rhs.serviceName
        }
        if rebuilt != ports { ports = rebuilt }
    }

    private func drain(iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let port = makePort(from: service), !ports.contains(where: { $0.id == port.id }) {
                ports.append(port)
                registerInterest(for: service, entryID: port.id)
            }
            IOObjectRelease(service)
        }
        // Active connections first, then alphabetically within each group.
        ports.sort { lhs, rhs in
            let lhsActive = lhs.connectionActive == true
            let rhsActive = rhs.connectionActive == true
            if lhsActive != rhsActive { return lhsActive }
            return lhs.serviceName < rhs.serviceName
        }
    }

    /// Subscribe to property/state changes on a port controller. The kernel
    /// fires `kIOMessageServicePropertyChange` (and related lifecycle
    /// messages) when a cable is plugged or unplugged, so this gives us a
    /// timely refresh trigger that doesn't depend on polling.
    private func registerInterest(for service: io_service_t, entryID: UInt64) {
        guard let notifyPort, interestNotifications[entryID] == nil else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let watcher = Unmanaged<USBCPortWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.refresh() }
        }
        var notification: io_object_t = 0
        let result = IOServiceAddInterestNotification(
            notifyPort,
            service,
            kIOGeneralInterest,
            cb,
            selfPtr,
            &notification
        )
        if result == KERN_SUCCESS {
            interestNotifications[entryID] = notification
        }
    }

    private func makePort(from service: io_service_t) -> USBCPort? {
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryID)

        // Build the full registry entry name with its location suffix
        // (e.g. "Port-USB-C@1"). `IORegistryEntryGetName` returns just the
        // base name ("Port-USB-C"); the "@1" comes from
        // `IORegistryEntryGetLocationInPlane`. Devices reference ports by
        // this combined form via their XHCI controller's `UsbIOPort`
        // property, so the two must match.
        var nameBuf = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(service, &nameBuf)
        let baseName = String(cString: nameBuf)

        var locBuf = [CChar](repeating: 0, count: 128)
        let serviceName: String
        if IORegistryEntryGetLocationInPlane(service, kIOServicePlane, &locBuf) == KERN_SUCCESS {
            let location = String(cString: locBuf)
            serviceName = location.isEmpty ? baseName : "\(baseName)@\(location)"
        } else {
            serviceName = baseName
        }

        var classBuf = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(service, &classBuf)
        let className = String(cString: classBuf)

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return USBCPort.from(
            entryID: entryID,
            serviceName: serviceName,
            className: className,
            properties: dict,
            busIndex: busIndex(for: service)
        )
    }

    /// Walks the IOKit parent chain looking for a controller-index node. M3-era
    /// Macs commonly expose `hpm<N>`, while M1/M2 machines can expose `atc<N>`
    /// or `usb-drd<N>`. Direct `UsbIOPort` paths are still preferred.
    private func busIndex(for service: io_service_t) -> Int? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<8 {
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(current, &nameBuf)
            if let n = Self.busIndex(fromRegistryName: String(cString: nameBuf)) {
                return n
            }

            var parent: io_service_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                break
            }
            IOObjectRelease(current)
            current = parent
        }

        var locBuf = [CChar](repeating: 0, count: 128)
        if IORegistryEntryGetLocationInPlane(service, kIOServicePlane, &locBuf) == KERN_SUCCESS,
           let n = Self.busIndex(fromLocation: String(cString: locBuf)) {
            return n
        }

        return nil
    }

    nonisolated static func busIndex(fromRegistryName name: String) -> Int? {
        for prefix in ["hpm", "atc", "usb-drd"] where name.hasPrefix(prefix) {
            let suffix = name.dropFirst(prefix.count)
            let digits = suffix.prefix { $0.isNumber }
            if !digits.isEmpty, let n = Int(digits) {
                return n
            }
        }
        return nil
    }

    nonisolated static func busIndex(fromLocation location: String) -> Int? {
        guard !location.isEmpty else { return nil }
        return Int(location, radix: 16)
    }
}
