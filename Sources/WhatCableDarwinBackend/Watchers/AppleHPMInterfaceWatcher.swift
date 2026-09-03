import Foundation
import IOKit
import WhatCableCore

/// Watches USB-C / MagSafe port-controller services. On Apple-silicon Macs the
/// relevant class is `AppleHPMInterfaceType10` (USB-C) and `Type11` (MagSafe).
@MainActor
public final class AppleHPMInterfaceWatcher: ObservableObject {
    @Published public private(set) var ports: [AppleHPMInterface] = []

    // Match only Type-C / MagSafe physical port controllers. Generic
    // `AppleUSBHostPort` would sweep in internal DRD (dual-role device)
    // ports — those have no physical connector and just confuse the UI.
    // The exact IOKit class for a USB-C port node varies by chip
    // generation. M3-era machines expose `AppleHPMInterfaceType10/11/12`;
    // M1 and M2 expose `AppleTCControllerType10/11`; MacBook Neo
    // (A-series) uses `AppleHPMInterfaceType18`. Apple-silicon desktop
    // front USB-C ports (Mac mini, Studio) are plain USB behind an
    // internal hub with no port-controller node, so they never appear
    // here regardless of class (see issue #291). `IOPort` is the shared
    // superclass of these port nodes, kept as a defensive catch-all, not
    // a front-port mechanism. It is probably redundant on M3+ (the HPM
    // classes above are `IOPort` subclasses, already matched by name), but
    // it is left in deliberately: dropping it is a behaviour change that
    // could hide a USB-C port on hardware we haven't tested, for no proven
    // gain. Revisit only if it ever pulls in noise. The
    // `PortTypeDescription` / `Port-` filter in `makePort` drops anything
    // that isn't a real physical port.
    ///
    /// The named classes are shared with the other reader that walks them
    /// (`PowerService.hpmPortKeysWithRIDs`); the `IOPort` catch-all is
    /// added here and only here, which is the whole of the difference between
    /// the two lists and is now visible in one place instead of being a silent
    /// mismatch between two copies.
    nonisolated static let candidateClasses = HPMPortControllerClasses.named + ["IOPort"]

    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    // Interest notifications registered per-port so we hear about property
    // changes (connection state, contract negotiation) as they happen, instead
    // of relying purely on polling. Keyed by registry entry ID so we don't
    // double-register when a port is rediscovered during a manual refresh.
    private var interestNotifications: [UInt64: io_object_t] = [:]

    // Tracks per-port connection-session age (issue: honest "Reading cable
    // details..." wording during the ~5s e-marker read window). Pure type,
    // fed the rebuilt port list on every `refresh()`. Monotonic clock via
    // mach uptime, never `Date` (wall-clock jumps would corrupt the age).
    private let sessionTracker = PortConnectionSessionTracker(
        now: { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
    )

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<AppleHPMInterfaceWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak watcher] in watcher?.drain(iterator: iterator) }
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
        sessionTracker.reset()
    }

    /// Seconds since the current physical connection on this port was
    /// stamped, or nil when unknown (never observed active with a known
    /// start, or the port is currently inactive). See
    /// `PortConnectionSessionTracker` for the full transition rules.
    public func connectionAge(for portID: UInt64) -> TimeInterval? {
        sessionTracker.connectionAge(for: portID)
    }

    /// The monotonic instant the current session was stamped at. For a
    /// caller that wants to recompute age itself on every render rather than
    /// consume a sampled snapshot that goes stale between renders.
    public func connectionAttachInstant(for portID: UInt64) -> TimeInterval? {
        sessionTracker.attachInstant(for: portID)
    }

    /// Changes only when the port's session is genuinely (re)stamped, never
    /// on a churn round-trip reuse. Intended for keying a SwiftUI
    /// `.task(id:)` expiry timer so it restarts on a real replug only.
    public func connectionSessionGeneration(for portID: UInt64) -> Int? {
        sessionTracker.sessionGeneration(for: portID)
    }

    /// The monotonic instant the current session was stamped at, RETAINED
    /// across a transient inactive interval (unlike
    /// `connectionAttachInstant(for:)`, which returns nil the moment the
    /// port goes inactive). See
    /// `PortConnectionSessionTracker.retainedAttachInstant(for:)` for the
    /// full rationale and the dead-session caveat: a young retained instant
    /// can belong to a session that has already ended, so the caller must
    /// gate on the authoritative visibility/liveness state before treating
    /// it as a live session's start.
    public func connectionRetainedAttachInstant(for portID: UInt64) -> TimeInterval? {
        sessionTracker.retainedAttachInstant(for: portID)
    }

    /// Re-walk the registry. Property changes (cable plug/unplug) don't fire
    /// match notifications, so callers poll this on demand. Builds the new
    /// list in a local array and assigns once, so observers see a single
    /// transition instead of an empty intermediate state. Skips the
    /// assignment entirely when nothing changed, which keeps the UI calm
    /// when refresh() is called speculatively after every device event.
    public func refresh() {
        var rebuilt: [AppleHPMInterface] = []
        var liveEntryIDs: Set<UInt64> = []

        for cls in Self.candidateClasses {
            let matching = IOServiceMatching(cls)
            var iter: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS {
                defer { IOObjectRelease(iter) }
                // `registerInterest` runs inside the transform: it is
                // idempotent (guarded by `interestNotifications[entryID] ==
                // nil`), so it is safe to run again on a discarded, retried
                // pass. Only `rebuilt`/`liveEntryIDs` need the retry-safe
                // merge-after-walk treatment.
                let ports = wcDrainAllRetrying(iter) { service -> AppleHPMInterface? in
                    guard let port = Self.makePort(from: service, bulkPropertyFetch: true) else { return nil }
                    registerInterest(for: service, entryID: port.id)
                    return port
                }
                for port in ports {
                    guard let port else { continue }
                    if !rebuilt.contains(where: { $0.id == port.id }) {
                        rebuilt.append(port)
                        liveEntryIDs.insert(port.id)
                    }
                }
            }
        }

        // Prune interest notifications for port services that are no longer
        // present in the registry. Only kIOMatchedNotification is registered
        // (no terminated callback), so without this prune, stale io_object_t
        // handles would accumulate across plug/unplug cycles without limit.
        // Each handle is a Mach port reference and must be released explicitly.
        for entryID in interestNotifications.keys where !liveEntryIDs.contains(entryID) {
            if let n = interestNotifications.removeValue(forKey: entryID) {
                IOObjectRelease(n)
            }
        }

        // Stable order (serviceName only, no active-first grouping). See
        // `AppleHPMInterface.stableOrder` for why: macOS's #536 power-source
        // attribution churn flips `connectionActive` on its own, and an
        // active-first sort reordered the card list on every flip.
        rebuilt.sort(by: AppleHPMInterface.stableOrder)

        // Feed the tracker on every refresh, even when the publish below is
        // skipped: a session-token-only change already makes `rebuilt !=
        // ports` today (see `AppleHPMInterface`'s synthesized `Hashable`
        // conformance, which includes `plugEventCount`/`connectionCount`),
        // but calling this unconditionally doesn't depend on that staying
        // true if the struct's equality ever narrows.
        sessionTracker.observe(rebuilt)

        if rebuilt != ports { ports = rebuilt }
    }

    private func drain(iterator: io_iterator_t) {
        // Same treatment as `refresh()`: `registerInterest` inside the
        // transform is idempotent, so a discarded retry pass calling it again
        // is harmless; only the `ports` merge needs to happen after the walk.
        let found = wcDrainAllRetrying(iterator) { service -> AppleHPMInterface? in
            guard let port = Self.makePort(from: service, bulkPropertyFetch: true) else { return nil }
            registerInterest(for: service, entryID: port.id)
            return port
        }
        for port in found {
            guard let port, !ports.contains(where: { $0.id == port.id }) else { continue }
            ports.append(port)
        }
        // Stable order (serviceName only). See `refresh()` above and
        // `AppleHPMInterface.stableOrder`.
        ports.sort(by: AppleHPMInterface.stableOrder)

        // Feed the tracker here too, not just from `refresh()`. Without
        // this, a port whose FIRST observation ever arrives via `refresh()`
        // (triggered by a cable plug's interest notification) looks to the
        // tracker like "already active on first sight": the
        // already-active-on-first-observation rule then leaves its age
        // unknown for the whole connection, so "Reading cable details..."
        // never shows for a cable plugged before `refresh()` had run once.
        // Seeding an INACTIVE baseline here means the later plug is a real
        // false -> true transition, which stamps normally.
        //
        // Safety of passing a possibly-PARTIAL array here: `drain(_:)` is
        // called once per candidate class, and `ports` (this property, not
        // the local `found`) already holds the running merge of every class
        // drained so far this call chain. `observe(_:)` prunes tracker
        // state for ids missing from what it's given, so the question is
        // whether a partial `ports` array can ever drop state a concurrent
        // `refresh()` still needs. It can't:
        //   - `AppleHPMInterfaceWatcher` is `@MainActor` and neither
        //     `drain(_:)` nor `refresh()` suspends internally (no `await`
        //     in either body), so Swift's cooperative executor never
        //     interleaves them mid-function; each call runs to completion
        //     before the next starts.
        //   - During `start()`'s initial burst, `drain(_:)` runs
        //     synchronously once per class in a plain `for` loop with no
        //     suspension point, so no `refresh()` (which is only ever
        //     scheduled via an async `Task` off an interest-notification
        //     callback) can run between those calls and observe a
        //     mid-burst array.
        //   - The tracker itself starts empty on `init()` and is cleared by
        //     `stop()`, so at the very first `observe(_:)` call in any
        //     watcher lifetime there is no existing state to prune away by
        //     mistake; a partial array can only ever add first-observation
        //     entries for the ports found so far, never lose ones from
        //     ports not yet drained.
        //   - Once startup finishes, a later `drain(_:)` call only fires
        //     for a brand-new match (e.g. a hot-plugged controller); by
        //     then `ports` already holds the full previously-known set
        //     (from prior `refresh()`/`drain()` calls) plus the new find,
        //     so it's the full current picture, not a partial one.
        sessionTracker.observe(ports)
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
            let watcher = Unmanaged<AppleHPMInterfaceWatcher>.fromOpaque(refcon).takeUnretainedValue()
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

    /// Every HPM port service, read once with no notification registration and
    /// no published state.
    ///
    /// The instance `refresh()` cannot be reused for this: it registers
    /// interest notifications, prunes them, feeds the session tracker and
    /// publishes `ports`. A caller that only wants the current port list must
    /// not do any of that. Mirrors `PowerSourceWatcher.readAllPowerSources()`,
    /// which exists for the same reason.
    ///
    /// Not cheap: it walks every HPM controller class. Callers gate it.
    ///
    /// Deliberately skips the bulk property fetch. `PowerService.refresh()`
    /// calls this once a second, and `IORegistryEntryCreateCFProperties` can
    /// abort the process from inside `IOCFUnserializeBinary` when a service is
    /// torn down mid-read (issue #181, and the comment in `makePort`). Paying
    /// that risk at 1 Hz to fill `rawProperties`, which only CLI verbose and
    /// `--raw` ever read, is not a trade worth making. Found by the PR #599
    /// review gate.
    ///
    /// `rawProperties` is still populated, from the crash-safe per-key reads
    /// in `AppleHPMInterface.rawPropertyFallbackKeys`. That covers everything
    /// the power-source synthesis chain reads, `PortType` included, which is
    /// what `identity` and `portKey` are built from. A caller that needs the
    /// complete property dump wants the instance watcher, not this.
    nonisolated public static func readAllPorts() -> [AppleHPMInterface] {
        var rebuilt: [AppleHPMInterface] = []
        for cls in candidateClasses {
            var iter: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iter) }
            let ports = wcDrainAllRetrying(iter) { service in makePort(from: service, bulkPropertyFetch: false) }
            for port in ports {
                guard let port, !rebuilt.contains(where: { $0.id == port.id }) else { continue }
                rebuilt.append(port)
            }
        }
        rebuilt.sort(by: AppleHPMInterface.stableOrder)
        return rebuilt
    }

    /// - Parameter bulkPropertyFetch: whether to populate `rawProperties` with
    ///   the full property table via `IORegistryEntryCreateCFProperties`. The
    ///   watcher's own walks pass true, because the complete dump is what CLI
    ///   verbose and `--raw` exist to show. `readAllPorts()` passes false: see
    ///   there for why.
    nonisolated private static func makePort(
        from service: io_service_t,
        bulkPropertyFetch: Bool
    ) -> AppleHPMInterface? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }

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
        guard IOObjectGetClass(service, &classBuf) == KERN_SUCCESS else { return nil }
        let className = String(cString: classBuf)

        // Read keys individually rather than fetching the full property
        // dictionary. The bulk fetch (IORegistryEntryCreateCFProperties)
        // can abort the process from inside IOCFUnserializeBinary when
        // the kernel returns a malformed serialised properties blob,
        // typically when the service is being torn down mid-read. The
        // per-key call has no such failure path. See issue #181.
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        // Pass a bulk-fetch closure for rawProperties so the CLI verbose
        // and --raw output captures every key the HPM controller publishes,
        // not just the 26 known operational keys. HPM port services are
        // long-lived (boot to dock-removal), so the teardown crash window
        // is narrow. All operational fields come from per-key `read` calls;
        // this closure is only called to populate rawProperties.
        func readAll() -> [String: Any]? {
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
                return nil
            }
            return props?.takeRetainedValue() as? [String: Any]
        }

        return AppleHPMInterface.from(
            entryID: entryID,
            serviceName: serviceName,
            className: className,
            read: read,
            readAll: bulkPropertyFetch ? readAll : nil,
            busIndex: Self.busIndex(for: service),
            hpmControllerUUID: Self.hpmControllerUUID(for: service)
        )
    }

    /// Walks the IOKit parent chain looking for a controller-index node. M3-era
    /// Macs commonly expose `hpm<N>`, while M1/M2 machines can expose `atc<N>`
    /// or `usb-drd<N>`. Direct `UsbIOPort` paths are still preferred.
    nonisolated private static func busIndex(for service: io_service_t) -> Int? {
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

    /// Walks the IOKit parent chain to find the HPM power-controller node and
    /// returns its `UUID` property. The probe reads `AppleHPMDevice` (the base
    /// class) so it catches both M1/M2 (`AppleHPMDevice` exact) and M3+
    /// (`AppleHPMDeviceHALType3`, a subclass). This matches probe 35's
    /// class-agnostic sweep. Corpus (206 machines, 2026-07-13): **704/704 ports**
    /// carry a UUID -- 409/409 `AppleHPMDeviceHALType3` and 295/295
    /// `AppleHPMDevice` -- zero misses. The class PREDICATE is pinned everywhere
    /// by `HPMControllerClassGateTests` (pure fixtures) via the shared
    /// `wcIsHPMControllerClass`; the 704/704 corpus figure itself is only checked
    /// where probe 35 is on disk (gitignored, so not in CI).
    ///
    /// The UUID is an internal in-session join key only. It is stored on
    /// `AppleHPMInterface.hpmControllerUUID` and must never be serialised to
    /// `--json` / `--raw` or shown in the UI.
    ///
    /// Falls back to `nil` when the parent walk finds no HPM controller or the
    /// controller has no `UUID` property (defensive; corpus says never, but
    /// malformed or sandboxed cases could hit it).
    nonisolated private static func hpmControllerUUID(for service: io_service_t) -> String? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<8 {
            var classBuf = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(current, &classBuf)
            let cls = String(cString: classBuf)
            // Match both the M1/M2 base class and the M3+ subclass. Shared with
            // `wcHPMControllerUUID` so the two walks can never drift apart on
            // which classes count; see that predicate for why it must stay
            // class-agnostic.
            if wcIsHPMControllerClass(cls) {
                if let uuid = IORegistryEntryCreateCFProperty(
                    current,
                    "UUID" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? String, !uuid.isEmpty {
                    return uuid
                }
                // Found the controller but no UUID (e.g. M1/M2 variant without
                // the property). Stop walking; no point going further up.
                return nil
            }

            var parent: io_service_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                break
            }
            IOObjectRelease(current)
            current = parent
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

