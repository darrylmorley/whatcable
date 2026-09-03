import Foundation
import IOKit
import WhatCableCore

/// Snapshot of the other watchers `PowerSourceWatcher.refresh()` needs in
/// order to attempt `PowerSourceSynthesis` (issue #401: M1 Pro/Max/Ultra
/// never publish a real `IOPortFeaturePowerSource` node for USB-C). Built by
/// whichever owner constructs this watcher alongside a port watcher and an
/// identity watcher; supplied via `PowerSourceWatcher.synthesisContext`.
public struct PowerSourceSynthesisContext {
    public let ports: [AppleHPMInterface]
    public let identities: [USBPDSOP]
    /// Port keys in HPM traversal order, matching the order Apple builds
    /// `PortControllerInfo` in. See `PowerService.hpmPortKeys()`.
    ///
    /// Lazy on purpose: `hpmPortKeys()` walks six IOKit service classes, so
    /// it must only run on the rare tick that's actually about to attempt
    /// synthesis, not on every `refresh()` call. `synthesizeIfNeeded` only
    /// evaluates this closure right before calling
    /// `PowerSourceSynthesis.synthesizedSource`, after every cheaper gate
    /// has already passed.
    public let positionalPortKeys: () -> [String]

    public init(ports: [AppleHPMInterface], identities: [USBPDSOP], positionalPortKeys: @escaping () -> [String]) {
        self.ports = ports
        self.identities = identities
        self.positionalPortKeys = positionalPortKeys
    }
}

/// Watches `IOPortFeaturePowerSource` services. These appear under each port's
/// `Power In` feature when something that advertises PD is connected.
@MainActor
public final class PowerSourceWatcher: ObservableObject {
    @Published public private(set) var sources: [PowerSource] = []

    /// Injected by the owner (`WatcherHub` / `DarwinSnapshotProvider`) so
    /// `refresh()` can synthesize a per-port source when macOS publishes none
    /// (M1 Pro/Max/Ultra USB-C, issue #401). Returns nil when the owner has
    /// no port/identity watchers to draw from, in which case `refresh()`
    /// skips synthesis entirely and behaves exactly as before.
    public var synthesisContext: (() -> PowerSourceSynthesisContext?)?

    /// Live charger-in wattage for the menu bar readout. Recomputed on the hub's
    /// poll cadence (1 Hz while a UI surface is visible, 30 s idle) and on each
    /// system power-source change notification, so the number stays fresh between
    /// idle polls without a separate per-second timer. 0 on battery or when
    /// nothing is readable. Only populated while ``readsChargerInputWatts`` is on.
    @Published public private(set) var chargerInputWatts: Int = 0

    /// The connected charger's rated wattage (its maximum, e.g. 70), used as the
    /// denominator for the menu bar power bar. 0 on battery or when the adapter
    /// doesn't report a rating. Published alongside `chargerInputWatts` on the
    /// same cadence and gate.
    @Published public private(set) var chargerRatedWatts: Int = 0

    /// Whether each refresh should also read the live charger-in wattage. Off by
    /// default, so the common case (menu bar watts readout disabled) does no
    /// SMC / battery read at all. The app turns this on only while the readout is
    /// shown. Flipping it on computes once immediately so the label paints without
    /// waiting for the next poll; flipping it off clears the value.
    public var readsChargerInputWatts = false {
        didSet {
            guard readsChargerInputWatts != oldValue else { return }
            if readsChargerInputWatts {
                startPowerSourceNotification()
                refreshChargerInputWatts()
            } else {
                stopPowerSourceNotification()
                if chargerInputWatts != 0 { chargerInputWatts = 0 }
                if chargerRatedWatts != 0 { chargerRatedWatts = 0 }
            }
        }
    }

    /// Reads the live SMC DC-in rail. Held once and reused (its `open()` is lazy
    /// and idempotent) so the per-tick read doesn't churn the AppleSMC user client.
    ///
    /// Injected by `WatcherHub` so the whole app shares one AppleSMC connection.
    /// A caller that passes nothing gets its own, which is right for the CLI and
    /// the widget: separate processes, nothing to share with.
    ///
    /// This watcher never closes the reader either way. It is the always-on hub
    /// watcher behind the menu bar's watts readout, so its connection is meant
    /// to live as long as the process.
    private let smcReader: SMCPowerReader

    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0

    /// System power-source change notification. Fires the watts recompute on a
    /// real charging change (charge ramp near full, charger swap) so the menu bar
    /// number stays fresh between the hub's idle (30 s) polls without a 1 Hz
    /// timer. Only registered while ``readsChargerInputWatts`` is on, so the
    /// readout-off majority schedules nothing.
    private var powerSourceRunLoopSource: CFRunLoopSource?

    public init(smcReader: SMCPowerReader? = nil) {
        self.smcReader = smcReader ?? SMCPowerReader()
    }

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let added: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<PowerSourceWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handleAdded(iter) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<PowerSourceWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handleRemoved(iter) }
        }

        let matching = IOServiceMatching("IOPortFeaturePowerSource")
        if IOServiceAddMatchingNotification(port, kIOMatchedNotification, matching, added, selfPtr, &addedIter) == KERN_SUCCESS {
            handleAdded(addedIter)
        }

        let matching2 = IOServiceMatching("IOPortFeaturePowerSource")
        if IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching2, removed, selfPtr, &removedIter) == KERN_SUCCESS {
            handleRemoved(removedIter)
        }

        // Reconcile the power-source notification to the flag: stop() tears the
        // source down but leaves readsChargerInputWatts as-is, so a stop/start
        // cycle must re-register it here rather than silently lose it.
        if readsChargerInputWatts { startPowerSourceNotification() }
    }

    public func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
        stopPowerSourceNotification()
        sources.removeAll()
    }

    // MARK: - Charger-in watts notification

    /// Register the system power-source change notification on the main run loop.
    /// The callback fires on a charging-state change, which recomputes the watts
    /// without polling. Idempotent.
    private func startPowerSourceNotification() {
        guard powerSourceRunLoopSource == nil else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let w = Unmanaged<PowerSourceWatcher>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak w] in w?.handlePowerSourceNotification() }
        }
        guard let unmanaged = IOPSNotificationCreateRunLoopSource(callback, selfPtr) else { return }
        let source = unmanaged.takeRetainedValue()
        // .commonModes so the callback still fires while the run loop is in a
        // tracking/modal mode (e.g. a menu open), not only the default mode.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceRunLoopSource = source
    }

    private func stopPowerSourceNotification() {
        guard let source = powerSourceRunLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceRunLoopSource = nil
    }

    private func handlePowerSourceNotification() {
        guard readsChargerInputWatts else { return }
        refreshChargerInputWatts()
    }

    public func refresh() {
        // Build the new list locally and assign once. Mutating the published
        // `sources` in place (removeAll then re-append) emits a transient empty
        // value that downstream subscribers see as "everything disconnected,"
        // which made NotificationManager fire a charger-connect/disconnect pair
        // on every poll tick. See issue #227.
        var rebuilt = Self.readAllPowerSources()
        if let synthesized = synthesizeIfNeeded(realSources: rebuilt) {
            rebuilt.append(synthesized)
        }
        if rebuilt != sources { sources = rebuilt }
        if readsChargerInputWatts { refreshChargerInputWatts() }
    }

    /// Attempt `PowerSourceSynthesis` (issue #401). Gated cheap-first so
    /// healthy machines (a real node exists) and idle machines (no active
    /// uncovered USB-C port) never pay for the extra `AppleSmartBattery`
    /// read: only once both checks below pass do we read the battery
    /// property dictionary at all.
    private func synthesizeIfNeeded(realSources: [PowerSource]) -> PowerSource? {
        guard let context = synthesisContext?() else { return nil }
        // Cheapest gates first, inside the shared chain. The battery
        // dictionary is only read once those gates have passed, which is why
        // this closure is evaluated lazily rather than read up front.
        return Self.synthesizedSource(
            realSources: realSources,
            context: context,
            smcReader: smcReader,
            batteryProperties: AppleSmartBatteryReader.properties()
        )
    }

    /// Whether the battery dictionary says the Mac is externally powered, for
    /// the synthesis gate chain.
    ///
    /// Three cases, and they do not all default the same way.
    ///
    /// An ABSENT key reads as CONNECTED. That is the pre-existing behaviour of
    /// this chain, it matches `refreshChargerInputWatts()`, and it stays. No
    /// corpus machine actually lands here: measured 2026-09-03 over probe 32,
    /// all 1338 folders carrying a non-empty `AppleSmartBattery` dump publish
    /// the key. The eleven folders that publish the section header with
    /// nothing under it have no battery node at all, which is the `dict == nil`
    /// path rather than this one, and every one of them is an Intel desktop.
    ///
    /// A key present as a number (what IOKit publishes a `CFBoolean` as) reads
    /// as whatever it says.
    ///
    /// A key PRESENT but not readable as a number (`NSNull`, a string, data)
    /// reads as NOT connected. It used to fall through the cast to the
    /// absent-key default and read as connected, which is the same
    /// anti-pattern this PR fixed for `Class` in `parseOption` one file over:
    /// a present-but-unusable value has to count as "something was reported",
    /// never as "nothing was". Which way is fail-safe differs between the two
    /// missing cases, so they are handled separately rather than sharing one
    /// default. Connected is the permissive answer here: it lets synthesis run
    /// and lets the resolver start a charging-path measurement. Doing that on
    /// a machine we cannot confirm is plugged in risks publishing a resistance
    /// figure measured on the wrong power state, while refusing only costs an
    /// estimate that the next tick can produce.
    ///
    /// It exists as a named helper because `PowerService.refresh()` hoists this
    /// same check in front of the chain, to avoid a full HPM class walk once a
    /// second on a machine that is not charging, and it used to build the value
    /// with `wcBool`, which returns FALSE for an absent key. The two therefore
    /// disagreed on a battery dictionary that has no `ExternalConnected` key:
    /// the service skipped synthesis where the chain would have proceeded,
    /// which is a false negative in exactly the direction this feature exists
    /// to prevent, on the silicon it was written for. Found by the PR #599
    /// review gate.
    ///
    /// EXACTLY TWO CALLERS SHARE IT, not every reader of the key, and an
    /// earlier version of this comment claimed "one expression, every caller".
    /// That was wrong when it was written. The two that do share it are the
    /// synthesis gate chain below (``synthesizedSource(realSources:context:smcReader:batteryProperties:)``)
    /// and `PowerService.refresh()`. Those two cannot drift again. Two other
    /// readers of the same key still do their own cast, and they are recorded
    /// here so the next person closes the gap deliberately instead of
    /// discovering it. All three were run side by side (2026-09-03): they
    /// agree on every value that is a number, including a non-boolean one like
    /// `NSNumber(value: 5)`, and differ only here.
    ///
    /// - `refreshChargerInputWatts()` in this file reads
    ///   `(dict["ExternalConnected"] as? Bool) ?? true`. A value that is
    ///   PRESENT but unusable (NSNull, a string, data) reads as CONNECTED
    ///   there and as not connected here. That is the divergence item 5 of
    ///   PR #599's round 3 created: it changed this helper's unusable case and
    ///   left that line alone.
    /// - `AppleSmartBatteryReader.parseBattery` reads it through `wcBool`, so
    ///   an ABSENT key reads as NOT connected there and as connected here.
    ///   That is the original divergence, still live on that path.
    ///
    /// Neither is changed here, and the watts path deliberately so: it feeds
    /// the menu bar charger readout, not the resistance estimate, and no
    /// machine we hold can tell the three apart. Measured 2026-09-03 across
    /// every probe-32 dump in the corpus, truncated captures included: 1338 of
    /// 1349 folders carry a populated `AppleSmartBattery` section, all 1338 of
    /// those publish `ExternalConnected`, and every printed value is a plain
    /// `true` or `false`. Absent never happens, and neither does unusable. So
    /// closing either gap is a tidy-up with no observable effect, which is why
    /// it is a note rather than a fix.
    ///
    /// There is no `as? Bool` branch after the `NSNumber` cast. Round 3 added
    /// one and it was dead on arrival: on Darwin a Swift `Bool` and a
    /// `kCFBooleanTrue` both bridge to `NSNumber`, so the first cast takes
    /// every boolean-shaped value and nothing reaches a second. Executed
    /// rather than reasoned (2026-09-03): Swift `true` and `false`,
    /// `NSNumber(value:)`, `kCFBooleanTrue`, and a value pulled back out of an
    /// `NSDictionary` all take the `NSNumber` branch; only NSNull, a string
    /// and data fall through to the default. `wcBool` in `IOKitHelpers` still
    /// carries the same dead branch, untouched here because it predates this
    /// PR and every other reader in the app goes through it.
    nonisolated static func externalConnectedFlag(from dict: [String: Any]) -> Bool {
        guard let value = dict["ExternalConnected"] else { return true }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    /// The synthesis gate chain, shared by the watcher and `PowerService`.
    ///
    /// It lives here as a static because two callers need it and only one of
    /// them is this watcher. `PowerService.refresh()` reads power sources
    /// through the static `readAllPowerSources()`, which returns real IOKit
    /// nodes only, so it never used to see a synthesized contract at all: on
    /// M1 Pro/Max/Ultra, where macOS publishes no USB-C power-source node at
    /// all (issue #401), the charging-path resistance resolver was handed an
    /// empty list and the estimate stayed `insufficient` forever. Two copies
    /// of this chain would drift, so there is one.
    ///
    /// - Parameters:
    ///   - realSources: every real node this tick, synthesized entries excluded.
    ///   - context: the port and identity snapshot to synthesize against.
    ///   - smcReader: the SMC route's reader, or nil to skip that route.
    ///   - batteryProperties: `AppleSmartBattery`'s property dictionary, read
    ///     ONCE by the caller and passed in. nil means no battery service,
    ///     which is a desktop, and the answer there is nil rather than a
    ///     defaulted "connected". Passed in rather than read here because
    ///     `PowerService.refresh()` has already read it on this same tick and
    ///     a second registry fetch per tick is exactly the cost an earlier
    ///     reviewer caught in this function.
    nonisolated static func synthesizedSource(
        realSources: [PowerSource],
        context: PowerSourceSynthesisContext,
        smcReader: SMCPowerReader?,
        batteryProperties: @autoclosure () -> [String: Any]?
    ) -> PowerSource? {
        // Cheapest check first: needs only the sources this tick's
        // readAllPowerSources() already read, no context and no extra IOKit
        // work. Not `PowerSource.hasLiveChargingContract(in:)`: that only
        // inspects the first source named "USB-PD" in the array, which is
        // correct for every existing caller (they all pass an already-
        // per-port-filtered array) but wrong here, where `realSources` spans
        // every port. See the matching comment in
        // `PowerSourceSynthesis.synthesizedSource` (gate 2) for the corpus
        // evidence.
        let anyRealSourceHasLiveContract = realSources.contains { source in
            guard let winning = source.winning else { return false }
            return winning.maxPowerMW > 0
        }
        guard !anyRealSourceHasLiveContract else { return nil }

        // context.ports is a cheap read of an already-published property, no
        // IOKit call. USB-C is required explicitly (portKey prefix "2/"),
        // not just "not MagSafe": A18 Pro ("MacBook Neo") corpus machines
        // have Port-Inductive ports, and other non-USB-C, non-MagSafe port
        // types may exist that we've never seen. Positive match only.
        let hasUncoveredActivePort = context.ports.contains { port in
            port.portKey?.hasPrefix("2/") == true
                && port.connectionActive == true
                && realSources.filter({ $0.canonicallyMatches(port: port) }).isEmpty
        }
        guard hasUncoveredActivePort else { return nil }

        // The SMC first, because on the silicon this whole path exists for
        // (M1 Pro / Max / Ultra) it answers on machines the decoded fallback
        // below cannot: 23 of them in the corpus, against 4 the other way, and
        // where both answer they agree on the port 19 times out of 19. It is
        // also cheaper: no AppleSmartBattery read at all.
        //
        // Public issue 491. See `SMCContractSynthesis` for the evidence and for
        // the switch that turns it off.
        //
        // The battery dictionary is read ONCE here and shared by both routes.
        // The first version read it inside the SMC branch and then again in the
        // fallback below, so a tick that tried the SMC and failed paid for two
        // full registry fetches where there used to be one. A reviewer caught
        // that, along with the comment below that still claimed nothing had
        // been paid for yet.
        //
        // A desktop Mac has no AppleSmartBattery service at all, so there is no
        // PortControllerInfo to synthesize from and no ExternalConnected to
        // read; returning nil is correct, not a fallback default.
        guard let dict = batteryProperties() else { return nil }
        // A dict without the flag still reads as connected. So does
        // refreshChargerInputWatts(), but only on that case: the two paths part
        // company on a present-but-unusable value. See `externalConnectedFlag`
        // for the full divergence and why it is unreachable on real hardware.
        let externalConnected = Self.externalConnectedFlag(from: dict)

        // The SMC is only worth asking when the Mac is actually taking power
        // in. Without this, an idle Mac with a plain USB accessory plugged in
        // (no PD, so no power-source node, so the gate above passes) paid for
        // up to forty kernel round trips every tick to learn nothing. That is
        // the COMMON case on any Mac, not the rare M1 Pro case this feature is
        // for, and the reviewer was right that the first version did not
        // distinguish them.
        if externalConnected {
            let contracts = smcReader?.readPortContracts() ?? []
            if !contracts.isEmpty,
               let fromSMC = SMCContractSynthesis.synthesizedSource(
                   contracts: contracts,
                   uuidMap: HPMPortUUIDMap.from(ports: context.ports),
                   ports: context.ports,
                   realSources: realSources,
                   externalConnected: externalConnected
               ) {
                return fromSMC
            }
        }
        // Parsed through the shared entry reader rather than hand-read here.
        // `PortControllerInfo` used to be pulled apart in four places; this was
        // one of them, and it is the one the M1 Pro synthesis path depends on.
        let entries = AppleSmartBatteryReader.parsePortControllerInfo(dict["PortControllerInfo"])
            .enumerated()
            .map { offset, entry in
                // The PDO array is zero-padded to a fixed length, so trim it to
                // the count the controller reported. Only synthesis cares:
                // the RDO's PDO-position field indexes into the untrimmed list,
                // and a trailing zero would otherwise look like an offered PDO.
                let count = entry.numberOfPDOs > 0 ? entry.numberOfPDOs : entry.portPDOs.count
                return PowerSourceSynthesis.ContractEntry(
                    index: offset,
                    rawPDOs: Array(entry.portPDOs.prefix(count)),
                    activeRdo: entry.activeContractRdo,
                    maxPowerMW: entry.maxPower
                )
            }

        return PowerSourceSynthesis.synthesizedSource(
            realSources: realSources,
            ports: context.ports,
            identities: context.identities,
            entries: entries,
            // Evaluated here, right before the call that needs it: this is
            // the one point in the whole gate chain where the IOKit walk in
            // hpmPortKeys() actually runs.
            positionalPortKeys: context.positionalPortKeys(),
            externalConnected: externalConnected
        )
    }

    /// Read the live charger-in wattage and publish it when the rounded value
    /// changes. Same source order the menu bar has always shown: the live SMC
    /// DC-in rail first, then `AppleSmartBattery`'s coarse `SystemPowerIn`, then
    /// the rated adapter. Runs on the hub's poll cadence, not a private timer.
    private func refreshChargerInputWatts() {
        let dict = AppleSmartBatteryReader.properties()
        // No battery dict at all means a desktop: treat as always externally
        // powered. A dict without the flag also reads as connected.
        let externalConnected = dict.map { ($0["ExternalConnected"] as? Bool) ?? true } ?? true
        // On battery there is nothing to show. Return before the SMC user-client
        // and adapter reads so those run only while a charger is attached (the
        // same short-circuit the old menu-bar read had).
        guard externalConnected else {
            if chargerInputWatts != 0 { chargerInputWatts = 0 }
            if chargerRatedWatts != 0 { chargerRatedWatts = 0 }
            return
        }

        let smcWatts = smcReader.readSystemPowerInput()?.watts
        let telemetry = dict?["PowerTelemetryData"] as? [String: Any]
        let systemPowerInMilliwatts = telemetry?["SystemPowerIn"] as? Int
        let adapterWatts = SystemPower.currentAdapter()?.watts

        let watts = Self.selectChargerInputWatts(
            externalConnected: externalConnected,
            smcWatts: smcWatts,
            systemPowerInMilliwatts: systemPowerInMilliwatts,
            adapterWatts: adapterWatts
        )
        if watts != chargerInputWatts { chargerInputWatts = watts }

        // The adapter's rated maximum, the denominator for the power bar.
        let rated = adapterWatts ?? 0
        if rated != chargerRatedWatts { chargerRatedWatts = rated }
    }

    /// Pure watts-selection policy, testable without IOKit. Returns 0 on battery
    /// (`externalConnected == false`) or when no source reports a usable figure.
    /// Prefers the live SMC rail, then the battery gauge (milliwatts, rounded to
    /// the nearest watt), then the rated adapter wattage.
    nonisolated static func selectChargerInputWatts(
        externalConnected: Bool,
        smcWatts: Double?,
        systemPowerInMilliwatts: Int?,
        adapterWatts: Int?
    ) -> Int {
        guard externalConnected else { return 0 }
        if let smcWatts, smcWatts > 0 { return Int(smcWatts.rounded()) }
        if let systemPowerInMilliwatts, systemPowerInMilliwatts > 0 {
            return (systemPowerInMilliwatts + 500) / 1000
        }
        if let adapterWatts, adapterWatts > 0 { return adapterWatts }
        return 0
    }

    /// Enumerate every `IOPortFeaturePowerSource` once and parse it into the
    /// self-keyed `PowerSource` model. Shared with `PowerService`,
    /// which needs the keyed contract to attribute `PortControllerInfo` detail
    /// to the right port (instead of array-offset guessing).
    public nonisolated static func readAllPowerSources() -> [PowerSource] {
        var rebuilt: [PowerSource] = []
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortFeaturePowerSource"), &iter) == KERN_SUCCESS {
            defer { IOObjectRelease(iter) }
            let found = wcDrainAllRetrying(iter) { service in makeSource(from: service) }
            for s in found {
                guard let s, !rebuilt.contains(where: { $0.id == s.id }) else { continue }
                rebuilt.append(s)
            }
        }
        return rebuilt
    }

    private func handleAdded(_ iter: io_iterator_t) {
        var addedRealUSBCSource = false
        let found = wcDrainAllRetrying(iter) { service in Self.makeSource(from: service) }
        for s in found {
            guard let s, !sources.contains(where: { $0.id == s.id }) else { continue }
            sources.append(s)
            if s.parentPortType == 2 { addedRealUSBCSource = true }
        }
        // A real USB-C-parented node just arrived: gate 2b in
        // PowerSourceSynthesis means synthesis must stop for this machine
        // from now on, so drop any synthesized entry immediately rather than
        // leaving it in `sources` until the next refresh() tick clears it.
        if addedRealUSBCSource {
            sources.removeAll { $0.isSynthesized }
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
            sources.removeAll { $0.id == entryID }
        }
    }

    // MARK: - IOKit wrapper (package-internal)

    nonisolated static func makeSource(from service: io_service_t) -> PowerSource? {
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

        // Walk the parent chain to get the HPM controller UUID. This is the
        // same UUID stored on the AppleHPMInterface node two levels above, so
        // matching by UUID ties a power source to its port with no @N guessing.
        let uuid = wcHPMControllerUUID(for: service)
        return makeSource(entryID: entryID, read: read, hpmControllerUUID: uuid)
    }

    // MARK: - Parse function (internal, testable)

    /// Parse a power source from a property-read closure. The `hpmControllerUUID`
    /// is passed in so the caller can walk the parent chain once and tests can
    /// supply nil without IOKit.
    nonisolated static func makeSource(
        entryID: UInt64,
        read: (String) -> Any?,
        hpmControllerUUID: String?
    ) -> PowerSource? {
        let name = (read("PowerSourceName") as? String) ?? "Unknown"
        let parent = parentPortIdentity(read: read)

        let options: [PowerOption] = parseOptions(read("PowerSourceOptions"))
        let winning: PowerOption? = parseOption(read("WinningPowerSourceOption"))

        return PowerSource(
            id: entryID,
            name: name,
            parentPortType: parent.type,
            parentPortNumber: parent.number,
            options: options,
            winning: winning,
            hpmControllerUUID: hpmControllerUUID
        )
    }

    nonisolated static func parentPortIdentity(read: (String) -> Any?) -> (type: Int, number: Int) {
        let type = (read("ParentBuiltInPortType") as? NSNumber)?.intValue
            ?? (read("ParentPortType") as? NSNumber)?.intValue
            ?? 0
        let number = (read("ParentBuiltInPortNumber") as? NSNumber)?.intValue
            ?? (read("ParentPortNumber") as? NSNumber)?.intValue
            ?? Int(((read("Priority") as? NSNumber)?.uint64Value ?? 0) & 0xFF)
        return (type, number)
    }

    nonisolated static func parseOptions(_ value: Any?) -> [PowerOption] {
        // IOKit publishes PowerSourceOptions as an __NSCFSet (CF set), not
        // an NSArray. ioreg renders it as "[{...}]" which looks like an
        // array, but the actual CF type is a set. Handle both.
        let items: [Any]
        if let set = value as? NSSet {
            items = set.allObjects
        } else if let arr = value as? NSArray {
            items = arr.compactMap { $0 }
        } else {
            return []
        }
        return items.compactMap { parseOption($0) }
            .sorted { $0.maxPowerMW > $1.maxPowerMW }
    }

    /// The class name IOKit gives a fixed-voltage power-source option.
    ///
    /// Corpus, re-derived 2026-09-03: every `WinningPowerSourceOption`
    /// dictionary in probe 17 carries a `Class` key, and every one of them
    /// reads this string. 1122 blocks across the 1339 folders carrying an
    /// untruncated probe 17, counted twice with parsers sharing no code and
    /// agreeing exactly.
    ///
    /// This used to report "1027 and 1122 blocks" from two parsers and
    /// explained the gap as different handling of captures truncated at the
    /// 64 KB pipe cap. That explanation cannot be right: including the 41
    /// truncated captures RAISES the count to 1160, so no truncation rule
    /// produces a figure below 1122, and whatever found 1027 was dropping
    /// about 95 blocks for another reason. The finding survives (key present
    /// on every block, value identical on every block); the 1027 does not.
    ///
    /// Consistent with the raw PDO evidence too: every active contract that
    /// resolves against its own advertised PDO list decodes to a fixed supply
    /// type, the single exception being a Variable PDO on
    /// `m1_macos26.5.2_af`, and not one is augmented. That exception sits on a
    /// port that LOST the supply election, in a register that appears to
    /// latch, so it is not a Mac charging from a Variable contract. See
    /// `PowerOption.SupplyKind` for that evidence and for why no total is
    /// quoted there.
    nonisolated static let fixedOptionClass = "IOPortFeaturePowerSourceOptionFixed"

    /// Classify an option's `Class` string.
    ///
    /// Fail-closed by construction: only the one string we have actually
    /// observed maps to `.fixed`. Everything else is `.nonFixed`, including
    /// strings we have never seen. We cannot map an unseen string to a
    /// specific supply type without inventing the mapping, and we must not
    /// let it reach `.unknown`, because `.unknown` carries a weaker gate
    /// downstream and a class string we failed to recognise is evidence that
    /// the option is NOT fixed, not an absence of evidence.
    nonisolated static func supplyKind(fromOptionClass className: String) -> PowerOption.SupplyKind {
        className == fixedOptionClass ? .fixed : .nonFixed
    }

    nonisolated static func parseOption(_ value: Any?) -> PowerOption? {
        let dict: [String: Any]?
        if let d = value as? [String: Any] {
            dict = d
        } else if let nsd = value as? NSDictionary {
            var converted: [String: Any] = [:]
            for case let (key, val) as (String, Any) in nsd {
                converted[key] = val
            }
            dict = converted
        } else {
            dict = nil
        }
        guard let dict else { return nil }
        let v = (dict["Voltage (mV)"] as? NSNumber)?.intValue ?? 0
        let i = (dict["Max Current (mA)"] as? NSNumber)?.intValue ?? 0
        let p = (dict["Max Power (mW)"] as? NSNumber)?.intValue ?? (v * i / 1000)
        guard v > 0 else { return nil }
        // `Class` is absent on no corpus machine, but an absent key is still
        // "nothing was reported" rather than "not fixed", so it maps to
        // `.unknown` and picks up the weaker downstream gate.
        //
        // Presence has to be tested separately from type. The previous line
        // here was `(dict["Class"] as? String).map(supplyKind(fromOptionClass:))
        // ?? .unknown`, which cannot tell "the key is absent" from "the key
        // is present but did not cast to String" (an unexpected CF type, or
        // NSNull): both fell through the `?? .unknown`. That fails open,
        // because `.unknown` accepts a standard-tier voltage downstream. A
        // key that is PRESENT is positive evidence that something was
        // reported, even if we cannot read it, so it must classify as
        // `.nonFixed`, the same as any unrecognised string, and must never
        // reach `.unknown`.
        //
        // The empty string is NOT part of that change, and an earlier version
        // of this comment wrongly said it was. It casts to String fine, so the
        // old line classified it through `supplyKind(fromOptionClass:)` and
        // got `.nonFixed`. The `!classString.isEmpty` guard below sends it to
        // the present-but-unreadable branch instead, which returns `.nonFixed`
        // as well. Same verdict either way; the guard is there to keep an
        // empty string from being treated as a readable class name, not to
        // change what it resolves to.
        let kind: PowerOption.SupplyKind
        if let classString = dict["Class"] as? String, !classString.isEmpty {
            kind = supplyKind(fromOptionClass: classString)
        } else if dict["Class"] != nil {
            kind = .nonFixed
        } else {
            kind = .unknown
        }
        return PowerOption(voltageMV: v, maxCurrentMA: i, maxPowerMW: p, supplyKind: kind)
    }
}

extension PowerSourceWatcher {
    /// All power sources attached to a given port.
    /// Uses UUID-based matching when available (M3+), else portKey fallback.
    public func sources(for port: AppleHPMInterface) -> [PowerSource] {
        return sources.filter { $0.canonicallyMatches(port: port) }
    }
}

