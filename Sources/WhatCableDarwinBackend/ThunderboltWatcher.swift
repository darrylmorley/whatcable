import Foundation
import IOKit
import WhatCableCore

/// Watches `IOThunderboltSwitch` services and assembles them into a normalised
/// list of `ThunderboltSwitch` models. Modelled on `USBCPortWatcher`:
///
/// - Match notification on the abstract parent class so all subclass variants
///   come in (we've seen `Type3`, `Type5`, `Type7`, `IntelJHL8440` so far,
///   and there will be more once TB5 silicon ships).
/// - Per-service interest notifications for property changes (link state
///   moves, dock plug/unplug). Mirrors the USB-C watcher's pattern.
/// - `refresh()` re-walks the registry; `read()`-style consumers can call it
///   on every snapshot read.
/// - The factory in `WhatCableCore.ThunderboltSwitch.from(...)` does the
///   actual property decoding so unit tests can run on hand-built dictionaries.
@MainActor
public final class ThunderboltWatcher: ObservableObject {
    @Published public private(set) var switches: [ThunderboltSwitch] = []

    private var notifyPort: IONotificationPortRef?
    private var matchIterator: io_iterator_t = 0
    private var interestNotifications: [UInt64: io_object_t] = [:]

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        // C callback bridge: capture self via Unmanaged so the IOKit
        // notification machinery can call us back. Same pattern as
        // USBCPortWatcher and PDIdentityWatcher.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<ThunderboltWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                // Drain the iterator so the kernel re-arms the notification,
                // then do a full re-walk so we pick up parent linkage and
                // sort consistently.
                while case let s = IOIteratorNext(iterator), s != 0 {
                    IOObjectRelease(s)
                }
                watcher.refresh()
            }
        }

        let matching = IOServiceMatching("IOThunderboltSwitch")
        var iter: io_iterator_t = 0
        if IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            matching,
            cb,
            selfPtr,
            &iter
        ) == KERN_SUCCESS {
            matchIterator = iter
            // Drain the initial set the kernel hands back so the notification
            // re-arms. The actual model build happens in refresh().
            while case let s = IOIteratorNext(iter), s != 0 {
                IOObjectRelease(s)
            }
            refresh()
        }
    }

    public func stop() {
        if matchIterator != 0 {
            IOObjectRelease(matchIterator)
            matchIterator = 0
        }
        for (_, n) in interestNotifications { IOObjectRelease(n) }
        interestNotifications.removeAll()
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        switches.removeAll()
    }

    /// Re-walk every `IOThunderboltSwitch` service. Cheap to call on every
    /// snapshot read, mirroring `USBCPortWatcher.refresh()`. Property
    /// changes (link-state moves) tend to arrive via interest notifications
    /// but we don't rely on them for correctness.
    public func refresh() {
        let matching = IOServiceMatching("IOThunderboltSwitch")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            if !switches.isEmpty { switches = [] }
            return
        }
        defer { IOObjectRelease(iter) }

        // First pass: build a list of (service, props, parentService) so
        // we can resolve parent UIDs in a second pass once every switch has
        // been parsed.
        struct RawEntry {
            let service: io_service_t
            let className: String
            let properties: [String: Any]
            let parentService: io_service_t  // 0 if no IOThunderboltSwitch parent
            let entryID: UInt64
        }

        var raw: [RawEntry] = []
        defer {
            for entry in raw {
                IOObjectRelease(entry.service)
                if entry.parentService != 0 { IOObjectRelease(entry.parentService) }
            }
        }

        while case let service = IOIteratorNext(iter), service != 0 {
            // Read everything we need before deciding to keep or release.
            var className = "<unknown>"
            var nameBuf = [CChar](repeating: 0, count: 128)
            if IOObjectGetClass(service, &nameBuf) == KERN_SUCCESS {
                className = String(cString: nameBuf)
            }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else {
                IOObjectRelease(service)
                continue
            }

            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)

            // Walk up to the nearest IOThunderboltSwitch ancestor (skipping
            // adapter / port intermediaries). On Apple Silicon, downstream
            // switches sit below their parent switch in the IOService plane,
            // so this gives us the parent linkage for free.
            let parentService = nearestThunderboltSwitchAncestor(of: service)

            raw.append(RawEntry(
                service: service,
                className: className,
                properties: dict,
                parentService: parentService,
                entryID: entryID
            ))
        }

        // Build a UID lookup keyed by service so we can resolve parent UIDs.
        var uidByService: [io_service_t: Int64] = [:]
        for entry in raw {
            if let uidNum = entry.properties["UID"] as? NSNumber {
                uidByService[entry.service] = uidNum.int64Value
            }
        }

        var rebuilt: [ThunderboltSwitch] = []
        rebuilt.reserveCapacity(raw.count)

        for entry in raw {
            let ports = parsePorts(of: entry.service)
            let parentUID: Int64? = entry.parentService != 0
                ? uidByService[entry.parentService]
                : nil

            if let model = ThunderboltSwitch.from(
                properties: entry.properties,
                className: entry.className,
                ports: ports,
                parentSwitchUID: parentUID
            ) {
                rebuilt.append(model)
                registerInterest(for: entry.service, entryID: entry.entryID)
            }
        }

        // Stable order: host roots first (Depth=0), then by Route String, then UID.
        rebuilt.sort { lhs, rhs in
            if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
            if lhs.routeString != rhs.routeString { return lhs.routeString < rhs.routeString }
            return lhs.id < rhs.id
        }

        if rebuilt != switches { switches = rebuilt }
    }

    /// Walk port children of a switch service. Returns the parsed ports
    /// in registry order. Skips non-port children (driver shims sometimes
    /// hang off a switch service).
    private func parsePorts(of switchService: io_service_t) -> [ThunderboltPort] {
        var ports: [ThunderboltPort] = []
        var childIter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(switchService, kIOServicePlane, &childIter) == KERN_SUCCESS else {
            return ports
        }
        defer { IOObjectRelease(childIter) }

        while case let child = IOIteratorNext(childIter), child != 0 {
            defer { IOObjectRelease(child) }

            // Class name must contain "Port" to qualify; this filters out
            // the adapter shims (AppleThunderboltUSBDownAdapter etc.) which
            // are driver matches rather than registry-backed ports.
            var classBuf = [CChar](repeating: 0, count: 128)
            guard IOObjectGetClass(child, &classBuf) == KERN_SUCCESS else { continue }
            let className = String(cString: classBuf)
            guard className.contains("Port") else { continue }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(child, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            if let port = ThunderboltPort.from(properties: dict) {
                ports.append(port)
            }
        }
        ports.sort { $0.portNumber < $1.portNumber }
        return ports
    }

    /// Walk up the IOService plane and return the nearest ancestor whose
    /// class is an IOThunderboltSwitch. Caller takes ownership of the
    /// returned service and must `IOObjectRelease` it (returns 0 if none).
    private func nearestThunderboltSwitchAncestor(of service: io_service_t) -> io_service_t {
        var current = service
        IOObjectRetain(current)
        for _ in 0..<32 {
            var parent: io_service_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                IOObjectRelease(current)
                return 0
            }
            IOObjectRelease(current)

            var classBuf = [CChar](repeating: 0, count: 128)
            if IOObjectGetClass(parent, &classBuf) == KERN_SUCCESS {
                let name = String(cString: classBuf)
                // Match the abstract prefix; covers Type3 / Type5 / Type7 /
                // IntelJHL8440 / future variants.
                if name.hasPrefix("IOThunderboltSwitch") {
                    return parent  // caller releases
                }
            }
            current = parent
        }
        IOObjectRelease(current)
        return 0
    }

    /// Subscribe to property changes on a switch service. Apple's IOKit
    /// fires `kIOMessageServicePropertyChange` when link state moves
    /// (e.g. dock cable plugged), so this gives us a refresh trigger
    /// without polling. Same pattern as `USBCPortWatcher.registerInterest`.
    private func registerInterest(for service: io_service_t, entryID: UInt64) {
        guard let notifyPort, interestNotifications[entryID] == nil else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let watcher = Unmanaged<ThunderboltWatcher>.fromOpaque(refcon).takeUnretainedValue()
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
}
