import Foundation
import IOKit
import WhatCableCore
import os.log

@MainActor
public final class PortDiagnosticsWatcher: ObservableObject {
    public struct PortDiagnosticsSnapshot: Codable, Sendable, Equatable {
        public let timestamp: Date
        public let healthCounters: [String: PortHealthCounters]
        public let contracts: [String: PDContract]
        public let eventTraces: [String: PDEventTrace]
    }

    @Published public private(set) var latestSnapshot: PortDiagnosticsSnapshot?

    public let snapshots: AsyncStream<PortDiagnosticsSnapshot>

    private var continuation: AsyncStream<PortDiagnosticsSnapshot>.Continuation?
    private var notifyPort: IONotificationPortRef?
    private var matchIterator: io_iterator_t = 0
    /// Property-change subscription on the `AppleSmartBattery` node. The
    /// counters we read live in that node's properties, and property changes
    /// do not fire match notifications, so without this the data never moves
    /// (issue #460).
    private var interestNotification: io_object_t = 0
    private var pollTask: Task<Void, Never>?
    private var cachedPortKeys: [String] = []

    /// Backstop poll interval. The interest notification above is the primary
    /// trigger; this exists because `AppleSmartBattery` batches its property
    /// republishes, so a counter can tick a second or two before the node
    /// reflects it. Only runs while the Cable Diagnostics window is open.
    private static let pollInterval: Duration = .seconds(2)

    nonisolated private static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "port-diagnostics")

    public init() {
        var continuation: AsyncStream<PortDiagnosticsSnapshot>.Continuation?
        snapshots = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func start() {
        guard notifyPort == nil else { return }
        cachedPortKeys = PowerService.hpmPortKeysRIDOrdered()
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<PortDiagnosticsWatcher>.fromOpaque(refcon).takeUnretainedValue()
            // Capture weakly so that if the watcher is torn down before this
            // task runs, it becomes a no-op rather than touching freed memory.
            Task { @MainActor [weak watcher] in
                guard let watcher else { return }
                // A `false` return means this notification iterator
                // was still invalidated (registry changed mid-walk) after
                // every retry. No stronger recovery is needed: `pollTask`
                // below already re-runs `refresh()` every 2 seconds
                // regardless of notifications, which is the backstop that
                // converges state even if this one notification stays deaf.
                if !wcDrainIterator(iterator) {
                    PortDiagnosticsWatcher.log.error("PortDiagnosticsWatcher: match-notification iterator stayed invalid after retries; relying on the 2s poll to converge")
                }
                watcher.refresh()
            }
        }

        if IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            AppleSmartBatteryReader.matchingDictionary(),
            cb,
            selfPtr,
            &matchIterator
        ) == KERN_SUCCESS {
            // Same recovery note as above: the 2s poll started below is the
            // backstop on terminal invalidation.
            if !wcDrainIterator(matchIterator) {
                Self.log.error("PortDiagnosticsWatcher: initial drain stayed invalid after retries; relying on the 2s poll to converge")
            }
            refresh()
        }

        registerInterest()

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                // `guard let self` rather than `self?.refresh()`: the optional
                // form would keep looping and sleeping forever after the
                // watcher is gone, since nothing else ends the loop.
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    /// Release the IOKit registrations if the watcher is dropped without
    /// `stop()` being called.
    ///
    /// Both callbacks hold `Unmanaged.passUnretained(self)` as their refcon, so
    /// a live registration outliving the object is a use-after-free waiting for
    /// the next battery property change, not merely a leak. The SwiftUI views
    /// that own these watchers do call `stop()` in `.onDisappear`, but that is
    /// a convention, and this is the backstop for when it is not honoured.
    ///
    /// `IONotificationPortDestroy` and `IOObjectRelease` are safe to call from
    /// any thread, which is what lets this run in a `nonisolated deinit` on a
    /// `@MainActor` class.
    ///
    /// Thread-safety here rests on a single-owner assumption. Today the only
    /// owner is one `@StateObject` in `CableDiagnosticView`, so the last
    /// reference is always dropped on the main thread as part of SwiftUI view
    /// teardown, and both IOKit callbacks are dispatched on
    /// `DispatchQueue.main`. That serialises `deinit` against any pending
    /// callback on the same queue: a callback cannot be mid-flight touching a
    /// refcon while `deinit` frees the registration. If this watcher ever gains
    /// a second owner that can drop it off the main thread, that guarantee is
    /// gone and this `deinit` opens a real use-after-free window against an
    /// already-enqueued callback. Keep it single-owner, or move teardown behind
    /// a main-thread hop before adding another.
    deinit {
        pollTask?.cancel()
        if interestNotification != 0 { IOObjectRelease(interestNotification) }
        if matchIterator != 0 { IOObjectRelease(matchIterator) }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        if interestNotification != 0 {
            IOObjectRelease(interestNotification)
            interestNotification = 0
        }
        if matchIterator != 0 {
            IOObjectRelease(matchIterator)
            matchIterator = 0
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        cachedPortKeys = []
        latestSnapshot = nil
    }

    /// Subscribe to property changes on the `AppleSmartBattery` node, mirroring
    /// what `AppleHPMInterfaceWatcher` does per port. `AppleSmartBattery` is
    /// published once at boot and never republished, so the matching
    /// notification in `start()` fires exactly once and can never report a
    /// plug or unplug on its own.
    private func registerInterest() {
        guard let notifyPort, interestNotification == 0 else { return }
        let service = AppleSmartBatteryReader.matchingService()
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let watcher = Unmanaged<PortDiagnosticsWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak watcher] in watcher?.refresh() }
        }
        var notification: io_object_t = 0
        if IOServiceAddInterestNotification(
            notifyPort,
            service,
            kIOGeneralInterest,
            cb,
            selfPtr,
            &notification
        ) == KERN_SUCCESS {
            interestNotification = notification
        }
    }

    public func refresh() {
        guard let dict = AppleSmartBatteryReader.properties() else { return }
        let entries = wcArray(dict["PortControllerInfo"]).map(wcDictionary)
        var counters: [String: PortHealthCounters] = [:]
        var contracts: [String: PDContract] = [:]
        var traces: [String: PDEventTrace] = [:]

        // Read the live self-keyed power sources so watts-based join can anchor
        // entries that have an active contract to the correct port key.
        let liveSources = PowerSourceWatcher.readAllPowerSources()
        let keyMap = Self.portKeyMap(entries: entries, portKeys: cachedPortKeys, sources: liveSources)

        for (offset, entry) in entries.enumerated() {
            guard let key = keyMap[offset] else { continue }
            counters[key] = Self.healthCounters(from: entry)
            contracts[key] = Self.contract(from: entry)
            traces[key] = Self.eventTrace(from: entry)
        }

        let snapshot = PortDiagnosticsSnapshot(
            timestamp: Date(),
            healthCounters: counters,
            contracts: contracts,
            eventTraces: traces
        )
        latestSnapshot = snapshot
        continuation?.yield(snapshot)
    }

    /// Map each `PortControllerInfo` array index to a port key.
    ///
    /// `PortControllerInfo` entries carry no port identifier (no `PortIndex` or
    /// similar key). The reliable signal for entries that have an active charge
    /// contract is `PortControllerMaxPower`: `PowerControllerPortJoin` matches
    /// that wattage to the self-keyed `IOPortFeaturePowerSource` that owns the
    /// port, so entries with live contracts land on the right key regardless of
    /// array order.
    ///
    /// For entries with zero `PortControllerMaxPower` (idle or disconnected
    /// ports), no watts signal is available, so the positional fallback is
    /// unavoidable. The `portKeys` array comes from `hpmPortKeys()`, which now
    /// orders ports by their HPM controller's `RID`: the same order Apple uses
    /// to build `PortControllerInfo` (see
    /// `PowerService.orderedPortKeys(_:)`). Before that ordering
    /// existed this took raw IOKit traversal order, which is not the same thing,
    /// and idle ports routinely showed another port's counters (issue #460).
    ///
    /// When the two signals disagree (an entry the watts join places on key X
    /// while position places a different entry on that same X), the watts match
    /// wins and the displaced entry is left unmapped rather than written onto
    /// some third port's key. Showing nothing for a port is recoverable;
    /// showing another port's health counters is not distinguishable from a
    /// real reading by anyone looking at it.
    nonisolated static func portKeyMap(
        entries: [[String: Any]],
        portKeys: [String],
        sources: [PowerSource]
    ) -> [Int: String] {
        let maxPowers = entries.map { wcInt($0["PortControllerMaxPower"]) }
        // Watts-based join from PowerControllerPortJoin. Returns only the
        // indices that unambiguously match a self-keyed source port. Idle-port
        // entries (zero max power) are always absent from this map.
        let wattsMap = PowerControllerPortJoin.portKeysByContent(
            controllerMaxPowerMW: maxPowers,
            sources: sources
        )

        var result: [Int: String] = [:]
        // Watts matches are content-based, so they are the stronger signal and
        // are placed first. Their keys are then off-limits to the positional
        // pass below.
        //
        // `portKeysByContent` decides each entry independently: it asks "does
        // exactly one port draw this wattage?". Two entries reporting the same
        // wattage therefore both come back naming that one port, which is not a
        // match, it is a tie. Those are dropped here and left to the positional
        // pass, which is the same treatment an entry gets when the wattage is
        // ambiguous on the source side. The check lives in this caller rather
        // than in the join because the join's per-entry contract is what its
        // other callers want.
        let contested = Set(
            Dictionary(grouping: wattsMap, by: \.value)
                .filter { $0.value.count > 1 }
                .keys
        )
        // `contested` MUST be computed before this loop, not merged into it.
        // `wattsMap` is a Dictionary, so its iteration order is unspecified;
        // deciding ties as we go would make which entry wins depend on hash
        // order. Computed up front, every pair reaching this loop already has
        // a globally unique key, so iteration order cannot affect the result.
        var claimed: Set<String> = []
        for (offset, key) in wattsMap where !contested.contains(key) {
            result[offset] = key
            claimed.insert(key)
        }

        for (offset, _) in entries.enumerated() where result[offset] == nil {
            if offset < portKeys.count {
                // No watts signal (idle port). Fall back to position, which is
                // RID order on both sides. See comment above.
                let key = portKeys[offset]
                // Already taken by a watts match at another offset, so the two
                // signals disagree about this port. Leave this entry unmapped
                // rather than guessing a different port for it.
                guard !claimed.contains(key) else { continue }
                result[offset] = key
                claimed.insert(key)
            } else if !portKeys.isEmpty {
                // More entries than known HPM ports (unexpected). Use a best-
                // effort 1-based index key so data still surfaces rather than
                // being silently dropped.
                let key = "2/\(offset + 1)"
                guard !claimed.contains(key) else { continue }
                result[offset] = key
                claimed.insert(key)
            }
            // An empty `portKeys` is `hpmPortKeysRIDOrdered()` refusing to
            // answer: it could not establish the order Apple built
            // `PortControllerInfo` in. Inventing "2/1", "2/2" here would put
            // real counters under fabricated port names, so entries the wattage
            // join could not place are left unmapped instead.
        }
        return result
    }

    private static func contract(from dict: [String: Any]) -> PDContract {
        let rawPDOs = wcArray(dict["PortControllerPortPDO"]).map(wcUInt32)
        let pdoCount = wcInt(dict["PortControllerNPDOs"])
        let decoded = rawPDOs.prefix(pdoCount > 0 ? pdoCount : rawPDOs.count).map(PDO.decode(rawValue:))
        return PDContract(
            activeRdo: wcUInt32(dict["PortControllerActiveContractRdo"]),
            pdoList: decoded,
            pdoCount: pdoCount,
            maxPower: wcInt(dict["PortControllerMaxPower"]),
            capMismatch: wcBool(dict["PortControllerCapMismatch"]),
            srcTypes: wcInt(dict["PortControllerSrcTypes"])
        )
    }

    private static func healthCounters(from dict: [String: Any]) -> PortHealthCounters {
        PortHealthCounters(
            attachCount: wcInt(dict["PortControllerAttachCount"]),
            detachCount: wcInt(dict["PortControllerDetachCount"]),
            hardResetCount: wcInt(dict["PortControllerHardResetCount"]),
            shortDetectCount: wcInt(dict["PortControllerShortDetectCount"]),
            i2cErrCount: wcInt(dict["PortControllerI2cErrCount"]),
            dataRoleSwapCount: wcInt(dict["PortControllerDataRoleSwapCount"]),
            dataRoleSwapFailCount: wcInt(dict["PortControllerDataRoleSwapFailCount"]),
            pwrRoleSwapCount: wcInt(dict["PortControllerPwrRoleSwapCount"]),
            pwrRoleSwapFailCount: wcInt(dict["PortControllerPwrRoleSwapFailCount"]),
            vdoFailCount: wcInt(dict["PortControllerVdoFailCount"]),
            fetEnableFailCount: wcInt(dict["PortControllerInpFetEnFailCount"]),
            fetStatus: wcUInt8(dict["PortControllerFetStatus"]),
            pdState: wcUInt8(dict["PortControllerPDst"]),
            dnState: wcUInt8(dict["PortControllerDnSt"])
        )
    }

    private static func eventTrace(from dict: [String: Any]) -> PDEventTrace {
        let raw = wcData(dict["PortControllerEvtBuffer"]) ?? Data(wcArray(dict["PortControllerEvtBuffer"]).map(wcUInt8))
        // Hand the buffer over untouched. Tokenising it is Core's job, and zeros
        // inside it are real argument bytes, not padding.
        return PDEventTrace.parse(raw)
    }
}
