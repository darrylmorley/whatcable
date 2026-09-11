import Foundation
import Combine
import WidgetKit
import os.log
import WhatCableCore
import WhatCableDarwinBackend
import WhatCableAppKit

/// Writes a pre-computed WidgetSnapshot to the macOS team-prefixed App Group
/// shared container whenever cable state changes, then tells WidgetKit to
/// refresh.
///
/// WidgetKit extensions are sandboxed even though the WhatCable host app is
/// not. For Developer ID builds, the `group.` App Group form requires an
/// embedded provisioning profile. Using `M4RUJ7W6MP.uk.whatcable.whatcable`
/// keeps the distribution profile-free while giving both processes the same
/// sandbox-authorized container.
///
/// Reads from the shared WatcherHub.
@MainActor
final class WidgetDataWriter {
    static let shared = WidgetDataWriter()

    private nonisolated static let log = Logger(
        subsystem: "uk.whatcable.whatcable",
        category: "widget-data"
    )

    private var portWatcher: AppleHPMInterfaceWatcher { WatcherHub.shared.portWatcher }
    private var deviceWatcher: USBWatcher { WatcherHub.shared.deviceWatcher }
    private var powerWatcher: PowerSourceWatcher { WatcherHub.shared.powerWatcher }
    private var pdWatcher: USBPDSOPWatcher { WatcherHub.shared.pdWatcher }
    private var tbWatcher: IOIOThunderboltSwitchWatcher { WatcherHub.shared.tbWatcher }
    private var usb3Watcher: USB3TransportWatcher { WatcherHub.shared.usb3Watcher }
    private var trmWatcher: TRMTransportWatcher { WatcherHub.shared.trmWatcher }
    private var uvdmWatcher: AppleUVDMWatcher { WatcherHub.shared.uvdmWatcher }
    private var displayWatcher: DisplayPortTransportWatcher { WatcherHub.shared.displayWatcher }

    private var cancellables = Set<AnyCancellable>()
    private var writeTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    /// Pending write scheduled for when the last port still inside the
    /// e-marker read window exits it. Nil when nothing written this pass was
    /// inside the window. See `scheduleExpiryWriteIfNeeded(remaining:)`.
    private var expiryWriteTask: Task<Void, Never>?
    private var lastSnapshot: WidgetSnapshot?
    private var lastReloadSignature: ReloadSignature?
    private var isStarted = false
    /// Test-observable count of calls to `writeToDefaults`, incremented
    /// regardless of whether the underlying file write succeeds. See
    /// `writeToDefaults` for why tests need this rather than the write's own
    /// success/failure.
    private(set) var writeAttemptCount = 0
    /// Test-observable count of calls to `scheduleExpiryWriteIfNeeded`,
    /// incremented on every call regardless of `remaining` or of whether the
    /// caller's structural dedup goes on to skip the write. Exists to pin the
    /// ordering fix in `performScheduledWrite()`: this bookkeeping must run
    /// even when the write itself gets deduped away, or a replug during the
    /// e-marker read window that renders an identical subtitle to the cached
    /// one would leave a stale expiry task pending. See
    /// `WidgetDataWriterExpiryOrderingTests`.
    private(set) var scheduleExpiryWriteCallCountForTesting = 0

    private var contributorCancellables = Set<AnyCancellable>()

    /// The writer's per-port device inputs, extracted as a pure seam so the
    /// app test target can exercise THIS builder's wiring (it is independent
    /// of `WidgetSnapshot.init(from:)`, review finding): `attributed` is the
    /// union with tunnelled devices structurally scoped to the port
    /// (LG UltraFine-class PCIe docks), feeding liveness and the device
    /// count; `matched` is native matches only, feeding PortSummary's
    /// bus-local speed corroboration.
    nonisolated static func deviceInputs(
        for port: AppleHPMInterface,
        devices: [USBDevice],
        thunderboltSwitches: [IOThunderboltSwitch]
    ) -> (attributed: [USBDevice], matched: [USBDevice]) {
        (
            TunnelledDeviceGrouping.attributedDevices(
                for: port, in: devices, thunderboltSwitches: thunderboltSwitches
            ),
            port.matchingDevices(from: devices)
        )
    }

    /// The delay before the widget cache should get a fresh write, given the
    /// live connection ages of the ports in a snapshot just built. Pure seam
    /// so the "which port's expiry governs the wait" arithmetic is testable
    /// without a live `WatcherHub` (`WidgetDataWriterExpiryWriteTests`).
    ///
    /// Returns the LARGEST remaining time among ports still inside
    /// `PortSummary.emarkerReadWindow` (the youngest connection, spec
    /// section 4): scheduling at that instant guarantees every reading-state
    /// port in this snapshot has resolved to its post-window verdict by the
    /// time the rewrite fires. Returns `nil` when no port is inside the
    /// window, meaning nothing needs a rewrite.
    nonisolated static func readingWindowRemaining(ages: [TimeInterval?]) -> TimeInterval? {
        ages.compactMap { age -> TimeInterval? in
            guard let age, age < PortSummary.emarkerReadWindow else { return nil }
            return PortSummary.emarkerReadWindow - age
        }.max()
    }


    /// Checks whether any WhatCable widget is currently on the user's
    /// desktop. Injectable so tests can stub the result without a live
    /// WidgetKit runtime.
    private let presenceChecker: WidgetPresenceChecking
    /// Cached presence result, refreshed once at startup and again on every
    /// heartbeat tick. See `WidgetPresenceState` for the "unknown defaults to
    /// write" and "flip to installed writes immediately" rules.
    private var presenceState = WidgetPresenceState()
    /// Read-only view of the cached presence state, for tests. The writer's
    /// own logic only ever reads `presenceState` through the gate methods
    /// above; this exists purely so a test can assert what got cached.
    var presenceStateForTesting: WidgetPresenceState { presenceState }

    /// Test-only seam: sets `lastSnapshot` directly, so a test can simulate
    /// "this exact snapshot is already cached" without needing a real App
    /// Group write to succeed first (`writeToDefaults` always fails in the
    /// sandboxed test process; see `writeAttemptCount`'s doc comment). Used
    /// to drive `performScheduledWrite()` into its structural-dedup branch.
    func primeLastSnapshotForTesting(_ snapshot: WidgetSnapshot) {
        lastSnapshot = snapshot
    }
    /// Bumped at the start of every `refreshPresence()` call, before the
    /// `await`. Lets a call whose result comes back late discard itself
    /// instead of overwriting a newer result.
    ///
    /// The startup seed check and the heartbeat's periodic check both call
    /// `refreshPresence()`, and nothing enforces they complete in the order
    /// they started: a slow startup lookup can finish after a later
    /// heartbeat lookup already found a widget installed. Without this guard
    /// the slow, stale "false" would land last and overwrite the correct
    /// "true", suppressing writes for up to another heartbeat interval. Only
    /// applying a result while it is still the most recently *started* call
    /// rules that out; both call sites run on the main actor, so a plain
    /// counter captured before the `await` is enough, no locking needed.
    private var presenceRequestGeneration = 0

    /// How often to re-write the snapshot and reload the widget even when
    /// nothing structural changed. Keeps the timestamp fresh so the widget's
    /// staleness check doesn't discard valid data, and is the one path that
    /// advances the live power chart: WidgetKit budgets refreshes, so a steady
    /// ~60s cadence is the most "live" a desktop widget can be without the
    /// chart blinking from refresh-budget throttling. This is also the
    /// cadence at which widget presence is re-checked.
    private let heartbeatInterval: Duration = .seconds(60)

    /// Internal, not private: `shared` is still the one instance the app
    /// uses, but tests construct their own instance with a stub
    /// `presenceChecker` to exercise the real gate + write logic below
    /// without a live WidgetKit runtime.
    init(presenceChecker: WidgetPresenceChecking = WidgetKitPresenceChecker()) {
        self.presenceChecker = presenceChecker
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        Self.log.debug("WidgetDataWriter starting (sharedFileURL: \(WidgetSnapshot.sharedFileURL?.path ?? "nil"))")
        // Write an initial snapshot once watchers have had a tick to populate.
        // Presence is unknown at this point, so WidgetPresenceState's
        // fail-safe default (write) applies until the first check below
        // returns.
        DispatchQueue.main.async { [weak self] in
            self?.scheduleWrite()
        }
        // Seed the presence cache as soon as possible, rather than waiting
        // for the first heartbeat up to 60s away. If nothing is installed
        // this stops the per-second wobble writes from ever starting.
        Task { @MainActor [weak self] in
            await self?.refreshPresence()
        }

        // Watch every signal the snapshot above is built from. A single cable
        // plug can fire several of these within a few ms, so scheduleWrite()
        // debounces into one write. A watcher that is read but not watched
        // here is not a missing value, it is a late one: the widget keeps the
        // previous row until something else publishes or the heartbeat comes
        // round, up to `heartbeatInterval` later.
        WatcherHub.shared.portWatcher.$ports
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        WatcherHub.shared.deviceWatcher.$devices
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        WatcherHub.shared.powerWatcher.$sources
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        WatcherHub.shared.pdWatcher.$identities
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        WatcherHub.shared.tbWatcher.$switches
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        WatcherHub.shared.usb3Watcher.$transports
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        WatcherHub.shared.trmWatcher.$cioCapabilities
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        WatcherHub.shared.displayWatcher.$statuses
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        WatcherHub.shared.uvdmWatcher.$identities
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        for contributor in PluginRegistry.shared.widgetDataContributors {
            contributor.start()
            contributor.changes
                .sink { [weak self] in self?.scheduleWrite() }
                .store(in: &contributorCancellables)
        }

        // Periodic heartbeat: re-write the snapshot with a fresh timestamp
        // even when ports haven't changed. This prevents the widget's
        // staleness check from discarding valid data during long idle
        // periods, and is the one place that carries fresh power magnitudes
        // to disk (see scheduleWrite's structural-only dedup below). Also
        // re-checks widget presence on the same cadence: cheap, and it
        // bounds how stale the "any widgets installed?" cache can get.
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.heartbeatInterval ?? .seconds(120))
                guard !Task.isCancelled, let self else { return }
                await self.performHeartbeatTick()
            }
        }
    }

    /// Asks the presence checker whether any widget is installed and updates
    /// the cached state. Returns true exactly when this call flips the state
    /// from "known none installed" to "installed".
    ///
    /// Internal, not private: exercised directly by
    /// `WidgetPresenceRaceTests` to prove the generation guard discards a
    /// stale, late-arriving result rather than reimplementing the guard in
    /// the test.
    @discardableResult
    func refreshPresence() async -> Bool {
        presenceRequestGeneration += 1
        let generation = presenceRequestGeneration
        let installed = await presenceChecker.hasInstalledWidgets()
        guard generation == presenceRequestGeneration else {
            // A newer refreshPresence() call started while this one was
            // still awaiting its result. Applying this one now could
            // overwrite that newer, more current result with a stale one
            // (the exact race that used to let a slow startup check
            // silently undo a heartbeat check that had already found a
            // widget installed). Drop it.
            Self.log.debug("Widget presence check superseded by a newer request; result discarded")
            return false
        }
        return presenceState.update(installed: installed)
    }

    /// One heartbeat tick's worth of work: refresh presence, then write if
    /// the gate allows it.
    ///
    /// Extracted from the timer loop in `start()` so both the real timer and
    /// tests can drive it directly, awaited, instead of the test having to
    /// wait out `heartbeatInterval`. Internal, not private, for that reason.
    @discardableResult
    func performHeartbeatTick() async -> Bool {
        let flippedToInstalled = await refreshPresence()
        guard presenceState.shouldWrite else {
            Self.log.debug("Widget heartbeat skipped: no widgets installed")
            return false
        }
        if flippedToInstalled {
            // Presence just went from "known none installed" to "installed".
            // The forceWrite() right below is already that immediate write:
            // presence is only re-checked on this same heartbeat cadence, so
            // there is no earlier moment it could have happened at.
            Self.log.debug("Widget presence flipped to installed; writing immediately")
        }
        forceWrite()
        return true
    }

    /// Debounced write. Cancels any pending write and waits 200ms for
    /// additional watcher updates to settle before encoding and writing.
    /// Mirrors the debounce pattern in ContentView.scheduleLivePortRefresh().
    private func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            performScheduledWrite()
        }
    }

    /// Schedules a rewrite for when the reading-window ports in the snapshot
    /// just written resolve to their post-window verdict, so the cached file
    /// never freezes a premature "No e-marker response" claim (or the old
    /// "Reading..." state past its actual expiry). `remaining` is
    /// `readingWindowRemaining(ages:)`'s result for the snapshot just built:
    /// `nil` when nothing in it is inside the window, in which case any
    /// previously pending expiry write is cancelled outright since it would
    /// now be scheduling against stale data.
    ///
    /// Called on every `performScheduledWrite()` / `forceWrite()` pass
    /// UNCONDITIONALLY, including when the structural-signature dedup goes
    /// on to skip the write itself (see the call site's comment): a replug
    /// during the read window restamps the session and produces a fresh
    /// age even when the rendered subtitle happens to be byte-identical to
    /// what is already cached ("Reading cable details..." both times), so
    /// this bookkeeping cannot wait for a write to actually happen.
    private func scheduleExpiryWriteIfNeeded(remaining: TimeInterval?) {
        scheduleExpiryWriteCallCountForTesting += 1
        expiryWriteTask?.cancel()
        expiryWriteTask = nil
        guard let remaining else { return }
        // Small epsilon past the window boundary, mirroring the menu bar
        // card's expiry wait, so the rewrite lands just after macOS's own
        // read schedule rather than exactly on it.
        let delay = remaining + 0.1
        expiryWriteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.scheduleWrite()
        }
    }

    /// The debounced write's actual body: the presence gate, the
    /// structural-only dedup, the write, and the conditional WidgetKit
    /// reload. Extracted from `scheduleWrite()`'s `Task` so tests can call it
    /// directly and synchronously instead of waiting out the 200ms debounce.
    /// Internal, not private, for that reason; `scheduleWrite()` is still the
    /// only caller in the app itself.
    @discardableResult
    func performScheduledWrite() -> Bool {
        guard presenceState.shouldWrite else { return false }

        let (snapshot, readingWindowRemaining) = buildSnapshot()

        // Rescheduled from every fresh age computation, BEFORE the
        // structural-signature dedup below, and unconditionally on the
        // outcome of that dedup. A replug during the read window restamps
        // the tracker (a fresh session, fresh age) but can render an
        // IDENTICAL subtitle to the one already on disk ("Reading cable
        // details..." both times), so the dedup below returns early and
        // skips the write. If scheduling waited until after that early
        // return, the previous session's now-stale pending task would fire
        // into the same dedup, itself do nothing, and leave the cache
        // showing "Reading..." until the next 60s heartbeat instead of the
        // new session's own, earlier expiry. Only the WRITE and RELOAD stay
        // gated on the dedup; this bookkeeping does not touch the cache
        // file or WidgetKit.
        scheduleExpiryWriteIfNeeded(remaining: readingWindowRemaining)

        // Skip the write if nothing STRUCTURAL changed. Pro power
        // telemetry polls at 1 Hz and its readings wobble by tenths of a
        // watt on every tick; each tick used to be compared with full
        // `==` on `ports`/`powerState`, sample arrays included, which
        // never matched and wrote the file on almost every tick (roughly
        // once a second whenever power was flowing, instead of the
        // designed debounce-on-change plus 60s heartbeat). Comparing
        // structuralSignature instead ignores those wobbling magnitudes;
        // the heartbeat above is what carries fresh power numbers to
        // disk on its own fixed cadence.
        if snapshot.structuralSignature == lastSnapshot?.structuralSignature { return false }

        // Only update lastSnapshot after a confirmed write. If the
        // write fails (missing container, encoding error), we want
        // the next change to retry rather than silently deduping.
        guard writeToDefaults(snapshot) else { return false }
        lastSnapshot = snapshot

        // Reload WidgetKit only on a *structural* change (a port plugged or
        // unplugged, charger or charging state changed, etc). The live
        // power magnitudes wobble every second; reloading on each wobble
        // hammers WidgetKit's refresh budget and makes the chart blink in
        // and out. Those values are already in the file we just wrote, so
        // WidgetKit picks them up on its next scheduled refresh and on the
        // heartbeat. reloadAllTimelines() is a no-op when no widgets are
        // installed, so it's safe to call unconditionally (the presence
        // gate above already skips this whole block when none are).
        let signature = ReloadSignature(snapshot)
        guard signature != lastReloadSignature else { return false }
        lastReloadSignature = signature
        WidgetCenter.shared.reloadAllTimelines()

        Self.log.debug("Widget timelines reloaded after structural change")
        return true
    }

    /// Unconditional write with a fresh timestamp. Called by
    /// `performHeartbeatTick()` to keep the snapshot from going stale during
    /// idle periods, which is also the immediate write when presence flips
    /// to installed. Callers are responsible for the presence gate; this
    /// always writes when called.
    private func forceWrite() {
        let (snapshot, readingWindowRemaining) = buildSnapshot()
        // Scheduled from the freshly computed remaining regardless of
        // whether this particular write succeeds below, mirroring
        // `performScheduledWrite()`: the expiry bookkeeping reflects the
        // current live age, not this call's write outcome. A later
        // `scheduleWrite()` firing from it rebuilds the snapshot fresh
        // anyway, so there is nothing stale to propagate even if
        // `writeToDefaults` fails here.
        scheduleExpiryWriteIfNeeded(remaining: readingWindowRemaining)
        guard writeToDefaults(snapshot) else { return }
        lastSnapshot = snapshot
        // The heartbeat is the deliberate periodic reload, so resync the
        // signature here too: it stops the next structural-change check from
        // firing a second, redundant reload right after this one.
        lastReloadSignature = ReloadSignature(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        Self.log.debug("Widget heartbeat: refreshed timestamp and reloaded timelines (\(snapshot.ports.count) ports)")
    }


    /// Builds the snapshot to write, plus the delay (if any) before the next
    /// write should fire to resolve a port still inside the e-marker read
    /// window (see `readingWindowRemaining(ages:)`).
    ///
    /// Internal, not private: `WidgetDataWriterExpiryOrderingTests` calls
    /// this directly to prime `lastSnapshot` (via
    /// `primeLastSnapshotForTesting(_:)`) with a REAL structural signature,
    /// so it can drive `performScheduledWrite()` into its dedup branch
    /// without needing a live App Group write to succeed first.
    func buildSnapshot() -> (snapshot: WidgetSnapshot, readingWindowRemaining: TimeInterval?) {
        let batteryResult = AppleSmartBatteryReader.read()
        let batteryFull = batteryResult.battery?.fullyCharged
        let batteryCharging = batteryResult.battery?.isCharging
        let adapter = SystemPower.currentAdapter()
        let chargerAttached = (adapter?.watts ?? 0) > 0
        let activePortCount = portWatcher.ports.filter { $0.connectionActive == true }.count
        let chargerSourceCount = ChargerWattageSource.chargerSourceCount(
            ports: portWatcher.ports, sources: powerWatcher.sources)

        // Native HDMI / built-in display port entries. Synthesized as widget
        // PortEntry rows so the existing widget layout (which already shows
        // monitor + mode for displays attached to USB-C ports) picks them up
        // for free. Built first so they can be appended to the USB-C / MagSafe
        // group below in stable order. Issue #352.
        let builtInDisplayEntries: [WidgetSnapshot.PortEntry] = displayWatcher.builtInDisplayPorts.map { hdmiPort in
            // Grouping filters inactive DP nodes, so each entity here always
            // carries at least one attached display.
            let firstDiag = hdmiPort.displays.compactMap { DisplayDiagnostic(dp: $0, cable: nil) }.first
            let headline = String(localized: "Display connected", bundle: _appLocalizedBundle)
            let subtitle = String(localized: "Built-in \(hdmiPort.portType) port \(hdmiPort.portNumber)", bundle: _appLocalizedBundle)
            // Real port ids are kernel-assigned IOKit entry ids, always small.
            // Use the top end of the UInt64 range so synthesized HDMI entries
            // never collide with them, even across many ports.
            let id = UInt64.max - UInt64(max(0, hdmiPort.portNumber))
            return WidgetSnapshot.PortEntry(
                id: id,
                portName: hdmiPort.serviceName,
                status: .displayCable,
                headline: headline,
                subtitle: subtitle,
                topBullet: nil,
                iconName: "display",
                deviceCount: 0,
                recentPower: [],
                portKey: nil,
                chargerWatts: nil,
                linkSpeed: nil,
                displayMode: firstDiag?.facts.currentMode?.shortLabel,
                monitorName: firstDiag?.facts.monitorName,
                displayCount: hdmiPort.displays.count
            )
        }

        // Collected alongside the entries below, one per port, so the expiry
        // rewrite can be scheduled from the same live ages the snapshot's
        // subtitles were actually rendered with.
        var portAges: [TimeInterval?] = []

        let entries: [WidgetSnapshot.PortEntry] = portWatcher.ports.map { port in
            let (attributed, devices) = Self.deviceInputs(
                for: port, devices: deviceWatcher.devices, thunderboltSwitches: tbWatcher.switches
            )
            let sources = powerWatcher.sources(for: port)
            let identities = pdWatcher.identities(for: port)
            // Live age from the same session tracker the menu bar card uses,
            // so the widget cache never freezes a premature no-e-marker
            // verdict for a connection still inside the read window (spec
            // section 4). `WidgetDataWriter` runs in the host app with
            // `WatcherHub` access, unlike the widget extension's own
            // one-shot live read, which stays nil.
            let connectionAge = portWatcher.connectionAge(for: port.id)
            portAges.append(connectionAge)

            let isLive = WhatCableCore.isPortLive(
                port: port,
                powerSources: sources,
                identities: identities,
                matchingDevices: attributed,
                chargerAttached: chargerAttached
            )

            let wattageSource = ChargerWattageSource.resolve(
                portSources: sources,
                portIsActive: port.connectionActive == true,
                activePortCount: activePortCount,
                chargerSourceCount: chargerSourceCount,
                adapter: adapter
            )

            let summary = PortSummary(
                port: port,
                sources: sources,
                identities: identities,
                devices: devices,
                thunderboltSwitches: tbWatcher.switches,
                federatedIdentities: batteryResult.federatedIdentities,
                usb3Transports: usb3Watcher.transports(for: port),
                trmTransports: trmWatcher.transports.filter { $0.canonicallyMatches(port: port) },
                cioCapability: trmWatcher.cioCapabilities.first { $0.canonicallyMatches(port: port) },
                accessoryIdentity: uvdmWatcher.identities.first { $0.canonicallyMatches(port: port) },
                isConnectedOverride: isLive,
                chargerWattageSource: wattageSource,
                batteryFullyCharged: batteryFull,
                batteryIsCharging: batteryCharging,
                adapter: adapter,
                connectionAge: connectionAge
            )

            let status = WidgetSnapshot.Status(from: summary.status)

            var recentPower: [Double] = []
            if let key = port.portKey {
                for contributor in PluginRegistry.shared.widgetDataContributors {
                    if let samples = contributor.recentPower(forPortKey: key), !samples.isEmpty {
                        recentPower = samples
                        break
                    }
                }
            }

            // Display detail: when a DisplayPort transport matches this port,
            // read the live mode + monitor name. Both are cable-independent, so
            // we pass `cable: nil` rather than recompute the e-marker. This is
            // free-tier data (the CLI's `--json` already emits the same facts).
            var displayMode: String?
            var monitorName: String?
            var displayCount = 0
            // Guard a non-nil port key first: without it, a keyless port would
            // nil-match a keyless display status and wrongly borrow its mode.
            // A dock can drive several monitors through one port (issue #271):
            // show the first here and carry the total so the card can hint "+N".
            if port.portKey != nil {
                let diags = displayWatcher.statuses
                    .filter { $0.status.canonicallyMatches(port: port) }
                    .compactMap { DisplayDiagnostic(dp: $0.status, cable: nil) }
                displayCount = diags.count
                if let first = diags.first {
                    displayMode = first.facts.currentMode?.shortLabel
                    monitorName = first.facts.monitorName
                }
            }

            return WidgetSnapshot.PortEntry(
                id: port.id,
                portName: port.portDescription ?? port.serviceName,
                status: status,
                headline: summary.headline,
                subtitle: summary.subtitle,
                topBullet: summary.topLine,
                iconName: status.iconName,
                deviceCount: attributed.count,
                recentPower: recentPower,
                portKey: port.portKey,
                // Gate the wattage pill on the same stale-PDO signal as the
                // status, so the widget can't show "96W" while reading "Connected".
                chargerWatts: SystemPowerState.onBattery(batteryIsCharging: batteryCharging, adapter: adapter)
                    ? nil : wattageSource.watts,
                linkSpeed: summary.linkSpeed,
                displayMode: displayMode,
                monitorName: monitorName,
                displayCount: displayCount,
                accessoryName: uvdmWatcher.identities
                    .first { $0.canonicallyMatches(port: port) }?.displayName
            )
        }

        // Gather Pro power data from contributors (nil for free-tier users).
        var systemPowerInWatts: Double?
        var recentSystemPower: [Double] = []
        var perPortWatts: [WidgetSnapshot.PortPowerEntry]?
        for contributor in PluginRegistry.shared.widgetDataContributors {
            if let sys = contributor.latestSystemPower() {
                systemPowerInWatts = sys.current
                recentSystemPower = sys.history
            }
            // Build per-port power entries from the contributor's port data.
            let portEntries: [WidgetSnapshot.PortPowerEntry] = entries.compactMap { entry in
                guard let key = entry.portKey,
                      let samples = contributor.recentPower(forPortKey: key),
                      let latest = samples.last, latest > 0 else { return nil }
                return WidgetSnapshot.PortPowerEntry(
                    portKey: key,
                    portName: entry.portName,
                    watts: latest,
                    recentSamples: samples
                )
            }
            if !portEntries.isEmpty { perPortWatts = portEntries }
        }

        let batteryPercent: Int? = {
            guard let bat = batteryResult.battery, bat.maxCapacity > 0 else { return nil }
            let raw = Int((Double(bat.currentCapacity) / Double(bat.maxCapacity) * 100).rounded())
            return min(100, max(0, raw))
        }()

        let powerState = WidgetSnapshot.PowerState(
            batteryPercent: batteryPercent,
            isCharging: batteryResult.battery?.isCharging ?? false,
            fullyCharged: batteryResult.battery?.fullyCharged ?? false,
            isDesktopMac: batteryResult.isDesktopMac,
            adapterWatts: adapter?.watts,
            adapterDescription: adapter?.adapterDescription,
            systemPowerInWatts: systemPowerInWatts,
            perPortWatts: perPortWatts,
            recentSystemPower: recentSystemPower
        )

        let snapshot = WidgetSnapshot(ports: entries + builtInDisplayEntries, powerState: powerState)
        return (snapshot, Self.readingWindowRemaining(ages: portAges))
    }

    @discardableResult
    private func writeToDefaults(_ snapshot: WidgetSnapshot) -> Bool {
        // Counted regardless of outcome. The test process has no App Group
        // entitlement, so the actual file write below always fails there;
        // this is how tests confirm the presence gate and structural dedup
        // let a call reach the write at all, which is what they are
        // actually deciding.
        writeAttemptCount += 1
        guard let url = WidgetSnapshot.sharedFileURL else {
            Self.log.error("Failed to resolve App Group container URL")
            return false
        }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            Self.log.debug("Widget snapshot written to \(url.path, privacy: .public): \(snapshot.ports.count, privacy: .public) ports, \(data.count, privacy: .public) bytes")
            return true
        } catch {
            Self.log.error("Failed to write widget snapshot at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// A digest of the snapshot fields that define the widget's labels and shape,
/// deliberately excluding the fast-fluctuating power magnitudes (system draw,
/// per-port watts, and the sparkline sample arrays). Two snapshots with the
/// same signature look the same to the user, so spending a WidgetKit reload on
/// the difference between them only burns the refresh budget and makes the
/// chart blink. The fluctuating values still reach the widget: they are written
/// to the shared file every change, and the widget reads them on its next
/// scheduled refresh or on the 60s heartbeat.
private struct ReloadSignature: Equatable {
    struct Port: Equatable {
        let id: UInt64
        let status: WidgetSnapshot.Status
        let headline: String
        let subtitle: String
        let topBullet: String?
        let accessoryName: String?
        let iconName: String
        let deviceCount: Int
        let portKey: String?
        let chargerWatts: Int?
        let linkSpeedBadge: String?
        let displayMode: String?
        let monitorName: String?
    }

    let ports: [Port]
    let batteryPercent: Int?
    let isCharging: Bool
    let fullyCharged: Bool
    let isDesktopMac: Bool
    let adapterWatts: Int?
    let adapterDescription: String?
    /// Whether a system-draw reading exists at all. The large widget adds or
    /// removes its whole "System draw" row on this presence, so the nil -> first
    /// sample transition is structural and must reload; the wattage *value*
    /// behind it still isn't.
    let hasSystemPower: Bool
    /// Which ports currently have power, by key (presence, not wattage). A port
    /// gaining or losing power is structural; the watts themselves are not.
    let poweredPortKeys: [String]

    init(_ snapshot: WidgetSnapshot) {
        ports = snapshot.ports.map { p in
            Port(
                id: p.id,
                status: p.status,
                headline: p.headline,
                subtitle: p.subtitle,
                topBullet: p.topBullet,
                accessoryName: p.accessoryName,
                iconName: p.iconName,
                deviceCount: p.deviceCount,
                portKey: p.portKey,
                chargerWatts: p.chargerWatts,
                linkSpeedBadge: p.linkSpeed?.badge,
                displayMode: p.displayMode,
                monitorName: p.monitorName
            )
        }
        let ps = snapshot.powerState
        batteryPercent = ps?.batteryPercent
        isCharging = ps?.isCharging ?? false
        fullyCharged = ps?.fullyCharged ?? false
        isDesktopMac = ps?.isDesktopMac ?? false
        adapterWatts = ps?.adapterWatts
        adapterDescription = ps?.adapterDescription
        hasSystemPower = ps?.systemPowerInWatts != nil
        poweredPortKeys = (ps?.perPortWatts ?? []).map(\.portKey).sorted()
    }
}

// MARK: - Widget presence gate

/// Seam for asking whether any WhatCable widget is on the user's desktop.
/// The only real consumer of `widgetSnapshot.json` is a widget extension
/// process, so when nothing is installed there is nothing reading the file:
/// skip the write and the WidgetKit reload entirely rather than doing them
/// on a schedule nobody looks at.
///
/// A protocol rather than calling WidgetCenter directly so tests can stub the
/// result without a live WidgetKit runtime.
protocol WidgetPresenceChecking {
    func hasInstalledWidgets() async -> Bool
}

/// Real implementation, backed by `WidgetCenter.getCurrentConfigurations`.
struct WidgetKitPresenceChecker: WidgetPresenceChecking {
    /// How long to wait for WidgetKit before falling back to the fail-safe
    /// default. `WidgetDataWriter`'s heartbeat loop awaits this call every
    /// tick for the app's whole life; if `WidgetCenter` ever fails to invoke
    /// its completion handler at all, an unbounded await here would hang
    /// that loop forever; no more staleness refreshes, no more presence
    /// checks, permanently, not just a slow tick.
    private let timeout: Duration

    init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    func hasInstalledWidgets() async -> Bool {
        await withTimeout(timeout, fallback: true) {
            await withCheckedContinuation { continuation in
                WidgetCenter.shared.getCurrentConfigurations { result in
                    switch result {
                    case .success(let configurations):
                        continuation.resume(returning: !configurations.isEmpty)
                    case .failure:
                        // Fail safe: a lookup error must never be read as "no
                        // widgets", which would silently stop writing for a
                        // user who does have one on their desktop.
                        continuation.resume(returning: true)
                    }
                }
            }
        }
    }
}

/// Races `operation` against a plain timer and returns whichever finishes
/// first, falling back to `fallback` if the timer wins.
///
/// This is NOT built on `withTaskGroup`. A task group is structured
/// concurrency: when its body returns, the group implicitly waits for every
/// child task to finish, even ones you already got an answer from via
/// `group.next()`. That is exactly wrong here, because the one case this
/// function exists for is an `operation` that never finishes at all (a
/// checked continuation whose completion handler never fires, which is the
/// real-world failure this guards against: `WidgetCenter` never calling
/// back). A task-group version of this function would hang on that exact
/// input, silently defeating the whole point of having a timeout.
///
/// Instead, `operation` and the timer both run as unstructured `Task`s
/// (fire-and-forget: nothing ever awaits them directly), and a small actor
/// holds the one continuation both race to resume, guarded so only the
/// first to arrive actually resumes it. A loser that never finishes (the
/// hung-operation case) is not awaited by anything and does not block this
/// function's return; it is simply abandoned, running harmlessly until it
/// either completes on its own or the process exits.
///
/// Internal, not private: `WidgetKitPresenceCheckerTimeoutTests` drives this
/// directly with a controllable operation, rather than depending on
/// WidgetKit's own timing to prove the timeout path works.
func withTimeout<T: Sendable>(
    _ timeout: Duration,
    fallback: T,
    operation: @escaping @Sendable () async -> T
) async -> T {
    await TimeoutRace<T>().run(timeout: timeout, fallback: fallback, operation: operation)
}

/// Single-resume gate backing `withTimeout`. Actor-isolated so "has this
/// already settled" is checked and set atomically: without that, both racers
/// arriving at nearly the same instant could each see `settled == false` and
/// both call `resume`, which is a hard crash (a `CheckedContinuation` may be
/// resumed exactly once).
private actor TimeoutRace<T: Sendable> {
    private var settled = false
    private var continuation: CheckedContinuation<T, Never>?

    func run(timeout: Duration, fallback: T, operation: @escaping @Sendable () async -> T) async -> T {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            // Unstructured on purpose: see withTimeout's doc comment. Neither
            // Task here is awaited by `run()`, so a hung `operation` cannot
            // block this function from returning once the timer settles it.
            Task { await self.settle(with: await operation()) }
            Task {
                try? await Task.sleep(for: timeout)
                await self.settle(with: fallback)
            }
        }
    }

    private func settle(with value: T) {
        guard !settled, let continuation else { return }
        settled = true
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

/// Tracks the cached "are any widgets installed" result and the two rules
/// around it: an unknown result defaults to writing, and a transition from
/// "known none installed" to "installed" is reported so the caller can write
/// immediately instead of waiting for the next heartbeat.
///
/// Pure value type, deliberately kept free of WidgetKit and the MainActor
/// isolation `WidgetDataWriter` needs, so the decision logic is unit
/// testable on its own.
struct WidgetPresenceState: Equatable {
    /// nil = no presence check has completed yet.
    private(set) var installed: Bool?

    /// Whether writes (file writes and WidgetKit reloads) should proceed
    /// given the currently known state. Fail-safe: unknown (nil) writes,
    /// same as a confirmed "installed" result. Only a confirmed "not
    /// installed" result stops writes.
    var shouldWrite: Bool { installed != false }

    /// Records a fresh presence result. Returns true exactly when this
    /// update flips the cached state from "known none installed" to
    /// "installed": the one transition that should not wait for the next
    /// scheduled write.
    @discardableResult
    mutating func update(installed newValue: Bool) -> Bool {
        let flippedToInstalled = installed == false && newValue == true
        installed = newValue
        return flippedToInstalled
    }
}
