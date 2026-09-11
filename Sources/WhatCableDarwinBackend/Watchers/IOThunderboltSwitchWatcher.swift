import Foundation
import IOKit
import WhatCableCore
import os.log

/// Watches `IOIOThunderboltSwitch` services and assembles them into a normalised
/// list of `IOThunderboltSwitch` models. Modelled on `AppleHPMInterfaceWatcher`:
///
/// - Match notification on the abstract parent class so all subclass variants
///   come in (we've seen `Type3`, `Type5`, `Type7`, `IntelJHL8440`, and
///   `IntelJHL9580` so far, and there will be more once new silicon ships).
/// - Per-service interest notifications for property changes (link state
///   moves, dock plug/unplug). Mirrors the USB-C watcher's pattern.
/// - `refresh()` re-walks the registry; `read()`-style consumers can call it
///   on every snapshot read.
/// - The factory in `WhatCableCore.IOThunderboltSwitch.from(...)` does the
///   actual property decoding so unit tests can run on hand-built dictionaries.
@MainActor
public final class IOIOThunderboltSwitchWatcher: ObservableObject {
    @Published public private(set) var switches: [IOThunderboltSwitch] = []

    /// Class names to match. Apple uses `IOIOThunderboltSwitch*` on some
    /// macOS / Mac generations and `IOThunderboltSwitch*` on others (M5 /
    /// macOS 26 was observed to ship `IOThunderboltSwitchType7` without
    /// the double-IO prefix, while older Macs ship `IOIOThunderboltSwitchType5`).
    /// Registering against both ensures the watcher works across the fleet.
    private static let matchClasses = ["IOIOThunderboltSwitch", "IOThunderboltSwitch"]

    private var notifyPort: IONotificationPortRef?
    private var matchIterators: [io_iterator_t] = []
    private var interestNotifications: [UInt64: io_object_t] = [:]

    nonisolated private static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "tb-switch")

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        // C callback bridge: capture self via Unmanaged so the IOKit
        // notification machinery can call us back. Same pattern as
        // AppleHPMInterfaceWatcher and USBPDSOPWatcher.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<IOIOThunderboltSwitchWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak watcher] in
                // Drain the iterator so the kernel re-arms the notification,
                // then do a full re-walk so we pick up parent linkage and
                // sort consistently.
                //
                // A `false` return means this iterator was still
                // invalidated (registry changed mid-walk) after every retry,
                // so this notification may not be fully re-armed. No
                // stronger recovery is needed here: `WatcherHub.refreshAll()`
                // polls `refresh()` on this watcher independently (1s active
                // / 30s idle), which is the backstop that converges state
                // even if this one notification stays deaf.
                if !wcDrainIterator(iterator) {
                    IOIOThunderboltSwitchWatcher.log.error("IOThunderboltSwitchWatcher: match-notification iterator stayed invalid after retries; relying on WatcherHub's poll to converge")
                }
                watcher?.refresh()
            }
        }

        // Register one matching notification per known class name. Each
        // registration owns its own iterator; we hold all of them so stop()
        // can release them. Apple's class naming differs across hardware
        // (see `matchClasses`).
        for className in Self.matchClasses {
            let matching = IOServiceMatching(className)
            var iter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(
                port,
                kIOMatchedNotification,
                matching,
                cb,
                selfPtr,
                &iter
            ) == KERN_SUCCESS {
                matchIterators.append(iter)
                // Drain the initial set the kernel hands back so the
                // notification re-arms. The model build happens in refresh().
                // Same recovery note as above: WatcherHub's poll is the
                // backstop on terminal invalidation.
                if !wcDrainIterator(iter) {
                    Self.log.error("IOThunderboltSwitchWatcher: initial drain for \(className, privacy: .public) stayed invalid after retries; relying on WatcherHub's poll to converge")
                }
            }
        }
        refresh()
    }

    public func stop() {
        for iter in matchIterators {
            IOObjectRelease(iter)
        }
        matchIterators.removeAll()
        for (_, n) in interestNotifications { IOObjectRelease(n) }
        interestNotifications.removeAll()
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        switches.removeAll()
    }

    /// Re-walk every Thunderbolt switch service. Cheap to call on every
    /// snapshot read, mirroring `AppleHPMInterfaceWatcher.refresh()`. Property
    /// changes (link-state moves) tend to arrive via interest notifications
    /// but we don't rely on them for correctness.
    public func refresh() {
        // First pass: build a list of (service, props, parent entry ID) so
        // we can resolve parent UIDs in a second pass once every switch has
        // been parsed.
        //
        // The parent linkage is keyed by registry entry ID (the stable
        // 64-bit identifier IOKit assigns per registry object), not by the
        // raw `io_service_t` mach-port value. Different IOKit calls can
        // hand back different mach-port handles for the same registry
        // object, so a port-handle keyed lookup would silently miss and
        // collapse the topology to "host only".
        struct RawEntry {
            let service: io_service_t
            let className: String
            // UID extracted up-front so we can build the UID lookup table in
            // the first pass without a second IOKit call. The full property
            // read happens in the second pass via per-key reads.
            let uid: Int64?
            let entryID: UInt64
            let parentEntryID: UInt64  // 0 if no Thunderbolt-switch parent
            let acioRootName: String?  // only set on a host root (parentEntryID == 0)
        }

        var raw: [RawEntry] = []
        var seenEntryIDs: Set<UInt64> = []
        defer {
            for entry in raw {
                IOObjectRelease(entry.service)
            }
        }

        // Iterate matching services for each known class name. Apple uses
        // `IOIOThunderboltSwitch*` on some hardware (older Macs / macOS)
        // and `IOThunderboltSwitch*` on others (M5 / macOS 26 onward).
        // Querying both keeps the watcher generation-agnostic. If the same
        // service somehow matches both (it shouldn't, but defensive),
        // entry-ID dedup keeps it once.
        for matchClassName in Self.matchClasses {
            let matching = IOServiceMatching(matchClassName)
            var iter: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iter) }

            // Note this class's io_service_t handles are NOT released as
            // they're read: unlike most watchers, `raw` keeps them alive
            // (for the second pass below) and the `defer` at the top of
            // `refresh()` releases all of them together once every class
            // has been walked. So a discarded, retried pass here must
            // release the handles it already put into `raw` itself, and roll
            // back `seenEntryIDs`, before re-walking.
            var attempt = 0
            while true {
                attempt += 1
                let rawCountBefore = raw.count
                var sawAny = false
                var next = IOIteratorNext(iter)
                while next != 0 {
                    sawAny = true
                    let service = next

                    // Read class name and entry ID up front.
                    var className = "<unknown>"
                    var nameBuf = [CChar](repeating: 0, count: 128)
                    if IOObjectGetClass(service, &nameBuf) == KERN_SUCCESS {
                        className = String(cString: nameBuf)
                    }

                    var entryID: UInt64 = 0
                    IORegistryEntryGetRegistryEntryID(service, &entryID)

                    // Dedup: a service that matched a previous class iteration
                    // shouldn't be added twice. Release the duplicate handle.
                    if !seenEntryIDs.insert(entryID).inserted {
                        IOObjectRelease(service)
                        next = IOIteratorNext(iter)
                        continue
                    }

                    // Read keys individually rather than fetching the full
                    // property dictionary. The bulk fetch can abort the process
                    // from inside IOCFUnserializeBinary when the kernel returns
                    // a malformed serialised properties blob (issue #181).
                    func readProp(_ key: String) -> Any? {
                        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                    }
                    let uid = (readProp("UID") as? NSNumber)?.int64Value

                    // Walk up to the nearest Thunderbolt switch ancestor (skipping
                    // adapter / port intermediaries). On Apple Silicon, downstream
                    // switches sit below their parent switch in the IOService
                    // plane, so this gives us the parent linkage for free. For a
                    // host root (no switch ancestor), the same walk also surfaces
                    // the acioN root name (port-scoping join, see `switchAncestry`).
                    let ancestry = switchAncestry(of: service)

                    raw.append(RawEntry(
                        service: service,
                        className: className,
                        uid: uid,
                        entryID: entryID,
                        parentEntryID: ancestry.parentEntryID,
                        acioRootName: ancestry.acioRootName
                    ))
                    next = IOIteratorNext(iter)
                }
                let invalidatedMidWalk = sawAny && IOIteratorIsValid(iter) == 0
                if !invalidatedMidWalk || attempt >= 3 { break }
                // Discard everything this attempt added to `raw`: release
                // the io_service_t handles it holds (they were never
                // released above, unlike most watchers) and undo the
                // matching `seenEntryIDs` inserts. IOIteratorReset rewinds
                // to the start of the list, so keeping this attempt's
                // entries would double count them once the re-walk reaches
                // them again.
                for entry in raw[rawCountBefore...] {
                    IOObjectRelease(entry.service)
                    seenEntryIDs.remove(entry.entryID)
                }
                raw.removeSubrange(rawCountBefore...)
                IOIteratorReset(iter)
            }
        }

        if raw.isEmpty {
            // No switches present: release any lingering interest-notification
            // handles and clear the published list.
            for (_, n) in interestNotifications { IOObjectRelease(n) }
            interestNotifications.removeAll()
            if !switches.isEmpty { switches = [] }
            return
        }

        // Build a UID lookup keyed by registry entry ID. Stable across
        // separate IOKit calls, unlike the raw mach-port handle.
        var uidByEntryID: [UInt64: Int64] = [:]
        for entry in raw {
            if let uid = entry.uid {
                uidByEntryID[entry.entryID] = uid
            }
        }

        var rebuilt: [IOThunderboltSwitch] = []
        rebuilt.reserveCapacity(raw.count)

        for entry in raw {
            // If UID was unreadable in the first pass, skip -- from() would
            // return nil for the same reason and we'd waste parsePorts + all
            // other per-key reads getting there.
            guard let uid = entry.uid else { continue }

            let ports = parsePorts(of: entry.service)
            let parentUID: Int64? = entry.parentEntryID != 0
                ? uidByEntryID[entry.parentEntryID]
                : nil

            // The service is still alive here (released by the defer above
            // after this loop finishes), so per-key reads are safe.
            func read(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(entry.service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            // Pass the UID read in the first pass so from() does not make a
            // second IOKit round-trip for the same key.
            if let model = IOThunderboltSwitch.from(
                uid: uid,
                read: read,
                className: entry.className,
                ports: ports,
                parentSwitchUID: parentUID,
                acioRootName: entry.acioRootName
            ) {
                rebuilt.append(model)
                registerInterest(for: entry.service, entryID: entry.entryID)
            }
        }

        // Prune interest notifications for switch services that are no longer
        // present in the registry. Only kIOMatchedNotification is registered
        // (no terminated callback), so without this prune, stale io_object_t
        // handles would accumulate across plug/unplug cycles without limit.
        // Each handle is a Mach port reference and must be released explicitly.
        // seenEntryIDs was built in the first-pass walk above and holds every
        // entry ID still live in the registry, so it doubles as the prune key.
        for entryID in interestNotifications.keys where !seenEntryIDs.contains(entryID) {
            if let n = interestNotifications.removeValue(forKey: entryID) {
                IOObjectRelease(n)
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

    /// The ports of a switch service, ready for `IOThunderboltSwitch.from`:
    /// the registry walk, then the ordering guarantee below.
    ///
    /// This is the ONLY place a switch gets its ports, so the sort has to
    /// happen here or not at all. The IOKit walk is injected as
    /// `readChildren` so that the assembly step itself is reachable from a
    /// test: the walk needs a live `io_service_t` on a Thunderbolt Mac and
    /// cannot be, but the ordering is pure and now has
    /// `ThunderboltPortOrderTests.parsePortsOrdersWhatTheRegistryWalkReturned`
    /// standing over it. Before the seam existed, deleting the sort call
    /// from here was invisible to the entire test suite.
    nonisolated static func parsePorts(
        readChildren: () -> [IOThunderboltPort]
    ) -> [IOThunderboltPort] {
        portsInPortNumberOrder(readChildren())
    }

    private func parsePorts(of switchService: io_service_t) -> [IOThunderboltPort] {
        Self.parsePorts(readChildren: { Self.portChildrenInRegistryOrder(of: switchService) })
    }

    /// Walk port children of a switch service. Returns the parsed ports
    /// in registry order. Skips non-port children (driver shims sometimes
    /// hang off a switch service).
    nonisolated private static func portChildrenInRegistryOrder(
        of switchService: io_service_t
    ) -> [IOThunderboltPort] {
        var ports: [IOThunderboltPort] = []
        var childIter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(switchService, kIOServicePlane, &childIter) == KERN_SUCCESS else {
            return ports
        }
        defer { IOObjectRelease(childIter) }

        let results = wcDrainAllRetrying(childIter) { child -> IOThunderboltPort? in
            // Class name must contain "Port" to qualify; this filters out
            // the adapter shims (AppleThunderboltUSBDownAdapter etc.) which
            // are driver matches rather than registry-backed ports.
            var classBuf = [CChar](repeating: 0, count: 128)
            guard IOObjectGetClass(child, &classBuf) == KERN_SUCCESS else { return nil }
            let className = String(cString: classBuf)
            guard className.contains("Port") else { return nil }

            func read(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(child, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            return IOThunderboltPort.from(read: read)
        }
        ports.append(contentsOf: results.compactMap { $0 })
        return ports
    }

    /// Ports in the order every consumer assumes: ascending by port number.
    ///
    /// The registry hands them back in its own order, which is not port
    /// order: the corpus dump prints lane 2 before lane 1 on 21 machines.
    ///
    /// ONE live consumer depends on this, `ThunderboltTopology`
    /// `.trainedDownstreamLanePort`, which feeds the link rate. It takes the
    /// FIRST trained lane of what it is handed and it cannot see this file,
    /// so the guarantee has to be made here and pinned by
    /// `ThunderboltPortOrderTests`. 4 dual-link pairs in the corpus have two
    /// lanes that decode different rates, and picking the wrong one publishes
    /// the higher figure on the lower link (`m4max_macos26.5.2_f` socket 2:
    /// 120 Gb/s on an 80 Gb/s link, where `Link Bandwidth` corroborates 80).
    /// That is the whole blast radius today.
    ///
    /// It used to be two. `DataLinkDiagnostic.partnerSwitch` also resolved a
    /// socket to its first lane, and in registry order 21 CIO-active ports
    /// lost their Thunderbolt partner. It no longer depends on the order:
    /// `partnerSwitch` now consults both lanes of the socket through
    /// `ThunderboltTopology.socketLanePorts`, and the device-cap corpus
    /// replay returns the same 40 device limits in registry order and in
    /// port-number order alike. Kept here because it is why the sort was
    /// written, not because it still needs it.
    nonisolated static func portsInPortNumberOrder(_ ports: [IOThunderboltPort]) -> [IOThunderboltPort] {
        ports.sorted { $0.portNumber < $1.portNumber }
    }

    /// The two things a single upward walk from a switch's registry entry
    /// can establish. `parentEntryID` is `0` when no Thunderbolt-switch
    /// ancestor was found (a host root). `acioRootName` is only ever
    /// non-nil in that same case: a downstream switch's walk always stops
    /// at its parent switch first, well short of `acioN`.
    private struct AncestryResult {
        let parentEntryID: UInt64
        let acioRootName: String?
    }

    /// Walk up the IOService plane. Returns the registry entry ID of the
    /// nearest ancestor whose class is an IOIOThunderboltSwitch (`0` if none
    /// found), and, only when none was found (this switch is a host root),
    /// the `acioN` Thunderbolt HAL root name the walk passed through (the
    /// port-scoping half of the apciec<->acio join, mirroring `USBWatcher
    /// .tunnelBridgeAncestry`'s walk to `apciecN` on the USB tunnel side).
    /// The walker manages all IOKit handle lifetimes internally so callers
    /// don't have to track ownership.
    ///
    /// Returning the entry ID (a stable 64-bit identifier per registry
    /// object) rather than the raw service handle avoids a class of bug
    /// where two `io_service_t` values for the same registry object
    /// compare unequal because IOKit can hand back distinct mach-port
    /// handles for the same underlying entry.
    private func switchAncestry(of service: io_service_t) -> AncestryResult {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<32 {
            var parent: io_service_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return AncestryResult(parentEntryID: 0, acioRootName: nil)
            }
            // Move ownership into `current` for the next iteration / cleanup.
            IOObjectRelease(current)
            current = parent

            var classBuf = [CChar](repeating: 0, count: 128)
            if IOObjectGetClass(current, &classBuf) == KERN_SUCCESS {
                let name = String(cString: classBuf)
                // Match either prefix: `IOIOThunderboltSwitch*` (older macOS
                // / older Macs) or `IOThunderboltSwitch*` (M5 / macOS 26).
                // Covers Type3 / Type5 / Type7 / IntelJHL8440 / IntelJHL9580
                // / future variants in both naming families.
                if name.hasPrefix("IOIOThunderboltSwitch") || name.hasPrefix("IOThunderboltSwitch") {
                    var entryID: UInt64 = 0
                    if IORegistryEntryGetRegistryEntryID(current, &entryID) == KERN_SUCCESS {
                        return AncestryResult(parentEntryID: entryID, acioRootName: nil)
                    }
                    return AncestryResult(parentEntryID: 0, acioRootName: nil)
                }
            }

            // No switch ancestor yet: check for the acioN root (strict
            // "acio" + digits, `RegistryRootNaming`). Only reachable for a
            // host root, since any downstream switch's walk already
            // returned above at its parent switch.
            var nameBuf = [CChar](repeating: 0, count: 128)
            if IORegistryEntryGetName(current, &nameBuf) == KERN_SUCCESS {
                let name = String(cString: nameBuf)
                if RegistryRootNaming.isRootName(name, prefix: "acio") {
                    return AncestryResult(parentEntryID: 0, acioRootName: name)
                }
            }
        }
        return AncestryResult(parentEntryID: 0, acioRootName: nil)
    }

    /// Subscribe to property changes on a switch service. Apple's IOKit
    /// fires `kIOMessageServicePropertyChange` when link state moves
    /// (e.g. dock cable plugged), so this gives us a refresh trigger
    /// without polling. Same pattern as `AppleHPMInterfaceWatcher.registerInterest`.
    private func registerInterest(for service: io_service_t, entryID: UInt64) {
        guard let notifyPort, interestNotifications[entryID] == nil else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let watcher = Unmanaged<IOIOThunderboltSwitchWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak watcher] in watcher?.refresh() }
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
