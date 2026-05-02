import Foundation
import IOKit

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
    // M1 and M2 expose `AppleTCControllerType10`. We register against
    // both. The `PortTypeDescription` / `Port-` filter in `makePort`
    // drops anything that isn't a real physical port.
    private static let candidateClasses = [
        "AppleHPMInterfaceType10",
        "AppleHPMInterfaceType11",
        "AppleHPMInterfaceType12",
        "AppleTCControllerType10",
        "AppleTCControllerType11"
    ]

    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

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
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        ports.removeAll()
    }

    /// Re-walk the registry. Property changes (cable plug/unplug) don't fire
    /// match notifications, so we expose this for manual polling.
    public func refresh() {
        ports.removeAll()
        for cls in Self.candidateClasses {
            let matching = IOServiceMatching(cls)
            var iter: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS {
                drain(iterator: iter)
                IOObjectRelease(iter)
            }
        }
    }

    private func drain(iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let port = makePort(from: service), !ports.contains(where: { $0.id == port.id }) {
                ports.append(port)
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

    /// Walks the IOKit parent chain looking for an `hpm<N>@…` SPMI node and
    /// returns N. On M3+ machines this N matches the upper byte of the
    /// associated XHCI controller's `locationID`, giving a bus index that
    /// can be matched against `USBDevice.busIndex`. Returns `nil` on
    /// machines that don't expose the hpm hierarchy (M1/M2, where ports
    /// register directly under `AppleTCControllerType10/11`).
    private func busIndex(for service: io_service_t) -> Int? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<8 {
            var parent: io_service_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                break
            }
            IOObjectRelease(current)
            current = parent

            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(current, &nameBuf)
            let name = String(cString: nameBuf)
            if name.hasPrefix("hpm"), let at = name.firstIndex(of: "@") {
                let digits = name[name.index(name.startIndex, offsetBy: 3)..<at]
                if let n = Int(digits) {
                    return n
                }
            }
        }

        // Fallback for M1/M2: use the port's own location if it's a simple index.
        // On these machines the port's location (e.g. "@1") typically matches
        // the upper byte of its XHCI controller's locationID.
        var locBuf = [CChar](repeating: 0, count: 128)
        if IORegistryEntryGetLocationInPlane(service, kIOServicePlane, &locBuf) == KERN_SUCCESS {
            let loc = String(cString: locBuf)
            if let n = Int(loc, radix: 16) {
                return n
            }
        }

        return nil
    }

}
