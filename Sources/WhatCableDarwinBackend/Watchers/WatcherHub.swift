import Foundation
import Combine
import os.log

/// Single owner of the app's IOKit watchers. Lives in the backend (not the app
/// target) so both the menu bar app and the Pro plugin can share one set of
/// watchers instead of each constructing its own. Builds the watchers once,
/// starts them together, polls every second, and fires a burst of refreshes on
/// plug/unplug.
@MainActor
public final class WatcherHub {
    public static let shared = WatcherHub()

    private static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "watcher-hub")

    /// The process's one AppleSMC connection.
    ///
    /// The SMC user client is a real kernel resource, not a registry read, and
    /// up to three separate connections used to be open at once with the Power
    /// Monitor showing (`PowerSourceWatcher`, `PowerService`, and a
    /// third inside `DarwinSnapshotProvider`'s own watcher). Harmless, since the
    /// reader is lazy, read-only and idempotent, but "one owner of the SMC" has
    /// to mean one instance rather than one class or nothing has improved.
    ///
    /// **Only the hub closes this.** A watcher handed a shared reader must never
    /// call `close()` on it: the menu bar's watts readout runs off the same
    /// connection for the app's whole life, so closing the Power Monitor window
    /// would tear it out from under the menu bar. The rule is enforced by
    /// `PowerService.ownsSMCReader`.
    public let smcReader = SMCPowerReader()

    public let portWatcher    = AppleHPMInterfaceWatcher()
    public let deviceWatcher  = USBWatcher()
    public let powerWatcher: PowerSourceWatcher
    public let pdWatcher      = USBPDSOPWatcher()
    public let tbWatcher      = IOIOThunderboltSwitchWatcher()
    public let usb3Watcher    = USB3TransportWatcher()
    public let trmWatcher     = TRMTransportWatcher()
    public let displayWatcher = DisplayPortTransportWatcher()
    public let uvdmWatcher    = AppleUVDMWatcher()

    /// Fires once after each applied read (steady poll, burst, or any other
    /// `refreshAll()`), on main, once every watcher has the result. Lets an
    /// always-on consumer (the Pro cable-history sampler) sample at the hub's
    /// own cadence (1 Hz while a UI surface is visible, 30 s idle) without
    /// starting a second IOKit poll. A bare tick, no payload: the consumer reads
    /// whichever watcher state it needs after the tick.
    public let didRefresh = PassthroughSubject<Void, Never>()

    private var isStarted = false
    private var pollTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// The shared hardware read. The real one for `shared`; tests inject a fake.
    private let read: @Sendable (HubReadRequest, SMCPowerReader) -> HubReading
    /// A read is running off the main thread right now.
    private var readInFlight = false
    /// One more read is owed once the running one finishes.
    private var followUpQueued = false

    /// Steady-poll cadence. 1 Hz while a UI surface (the popover or a visible
    /// window) is on screen, so live readings tick smoothly. When nothing is
    /// visible we back right off: connect/disconnect already arrives via the
    /// watchers' own IOKit notifications (and the burst triggers below), so the
    /// steady poll's only idle job is catching slow value drift, which no one
    /// can see with the UI hidden. This is the bulk of the app's energy use
    /// when it just sits in the menu bar.
    private let activeInterval: Duration = .seconds(1)
    private let idleInterval: Duration = .seconds(30)
    /// Tokens for the UI surfaces currently on screen. The hub polls at the
    /// active cadence whenever any surface is visible. This is a set, not a
    /// single bool, so the main popover/window and any number of detached Pro
    /// windows each report independently: closing one detached window can't
    /// wrongly mark the hub idle while the popover (or another detached window)
    /// is still open. Starts empty: in menu-bar mode (the default) the app
    /// launches with the popover closed, so it begins idle.
    private var visibleSurfaces: Set<String> = []
    /// Derived: a UI surface is visible when at least one surface is on screen.
    private var isUIVisible: Bool { !visibleSurfaces.isEmpty }

    private convenience init() {
        self.init(read: { HubRead.readAll($0, smcReader: $1) })
    }

    /// Internal so only this module and `@testable` tests can build a hub with
    /// a custom read; everything else goes through `shared`. A test hub that
    /// never calls `start()` opens no IOKit notification ports.
    init(read: @escaping @Sendable (HubReadRequest, SMCPowerReader) -> HubReading) {
        self.read = read
        // Assigned here rather than inline because it needs `smcReader`, and a
        // stored property's own initialiser cannot see its siblings.
        powerWatcher = PowerSourceWatcher(smcReader: smcReader)
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        portWatcher.start()
        deviceWatcher.start()
        powerWatcher.start()
        pdWatcher.start()
        tbWatcher.start()
        usb3Watcher.start()
        trmWatcher.start()
        displayWatcher.start()
        uvdmWatcher.start()

        // Lets powerWatcher.refresh() synthesize a per-port source when macOS
        // never publishes a real IOPortFeaturePowerSource node (M1 Pro/Max/Ultra
        // USB-C, issue #401). Weak self: the closure only reads live watcher
        // state, never touches the hub's own lifecycle.
        powerWatcher.synthesisContext = { [weak self] in
            guard let self else { return nil }
            return .live(ports: self.portWatcher.ports, identities: self.pdWatcher.identities)
        }

        // Initial synchronous readiness refresh (issue #568). On M1 Pro/Max/Ultra
        // macOS never publishes a real IOPortFeaturePowerSource node for USB-C,
        // so the charger source only exists once powerWatcher.refresh() has run
        // synthesis (see synthesisContext above). Without this, the first
        // refresh doesn't happen until the poll's first sleep finishes (30s
        // idle, or ~2s if the popover opens first), so NotificationManager
        // primes its baseline against an empty charger list and then reads
        // this refresh as a fresh connect.
        //
        // Contract: once start() returns, powerWatcher.sources reflects
        // current reality, synthesis included, so NotificationManager's
        // baseline prime (which now runs synchronously right after this, see
        // NotificationManager.start()) sees the same charger already primed
        // rather than diffing against an empty one.
        //
        // Port then PD then power, not a full refreshAll(): synthesis needs
        // this tick's ports and PD identities (same ordering as refreshAll()
        // above), and the TB/USB3/TRM/display walks aren't needed for
        // baseline correctness, so skipping them keeps launch cost down.
        // Deliberately doesn't send didRefresh: nothing is listening yet at
        // this point in start(), and the burst/poll machinery below covers
        // every later refresh.
        let startupRefreshClock = ContinuousClock()
        let startupRefreshStart = startupRefreshClock.now
        portWatcher.refresh()
        pdWatcher.refresh()
        powerWatcher.refresh()
        Self.log.info("WatcherHub.start() initial refresh took \(startupRefreshClock.now - startupRefreshStart, privacy: .public)")

        startPoll()
        setupBurstTriggers()
    }

    /// Tell the hub whether a UI surface is on screen. The app calls this when
    /// the popover opens/closes (menu-bar mode) or the window's visibility
    /// changes (window mode). Becoming visible refreshes once immediately so the
    /// surface paints current data, then restarts the poll at the faster
    /// cadence; going idle restarts it at the slower one. Connect/disconnect
    /// detection is unaffected either way: it runs off IOKit notifications, not
    /// this poll.
    public func setUIVisible(_ visible: Bool) {
        setSurfaceVisible(visible, surface: "main")
    }

    /// Mark a named UI surface as visible or hidden. The main popover/window
    /// reports through `setUIVisible` (surface "main"); detached Pro windows
    /// report their own per-window token. The hub becomes visible when the
    /// first surface appears (refreshing once so the surface paints current
    /// data) and goes idle only when the last one disappears.
    public func setSurfaceVisible(_ visible: Bool, surface: String) {
        guard isStarted else { return }
        let wasVisible = isUIVisible
        if visible {
            visibleSurfaces.insert(surface)
        } else {
            visibleSurfaces.remove(surface)
        }
        guard wasVisible != isUIVisible else { return }
        if isUIVisible { refreshAll() }
        startPoll()
    }

    /// Ask for a fresh read. Returns at once; the result is applied on main
    /// and `didRefresh` fires after it. The read runs off the main thread so a
    /// slow registry (a busy dock) never freezes the UI.
    public func refreshAll() { requestRefresh(steady: false) }

    /// `steady` is the 1 Hz / 30 s poll. A steady tick that lands while a read
    /// is running is dropped: the running read is already fresh enough. Any
    /// other request (a burst after a plug event, a surface becoming visible,
    /// the refresh button) queues one more read for when the current one
    /// finishes, so a change is never missed.
    func requestRefresh(steady: Bool) {
        guard !readInFlight else {
            if !steady { followUpQueued = true }
            return
        }
        readInFlight = true
        let request = HubReadRequest(
            readsChargerWatts: powerWatcher.readsChargerInputWatts,
            displayBitsPerComponent: DisplayModeReader.currentBitsPerComponent(),
            includesPhy: false
        )
        let generations = currentGenerations()
        let read = self.read
        let smc = smcReader
        Task { @MainActor [weak self] in
            let reading = await Task.detached(priority: .userInitiated) { read(request, smc) }.value
            guard let self else { return }
            self.apply(reading, readStartedAt: generations)
            self.didRefresh.send(())
            self.readInFlight = false
            if self.followUpQueued {
                self.followUpQueued = false
                self.requestRefresh(steady: false)
            }
        }
    }

    /// Each watcher's `refreshGeneration` at the moment a read started.
    private struct Generations {
        let port, pd, power, charger, tb, usb3, trm, display, uvdm: Int
    }

    private func currentGenerations() -> Generations {
        Generations(
            port: portWatcher.refreshGeneration,
            pd: pdWatcher.refreshGeneration,
            power: powerWatcher.refreshGeneration,
            charger: powerWatcher.chargerGeneration,
            tb: tbWatcher.refreshGeneration,
            usb3: usb3Watcher.refreshGeneration,
            trm: trmWatcher.refreshGeneration,
            display: displayWatcher.refreshGeneration,
            uvdm: uvdmWatcher.refreshGeneration
        )
    }

    /// Hand a finished read to each watcher, in the read's own order (port,
    /// PD, power, Thunderbolt, USB3, TRM, display, UVDM).
    ///
    /// A watcher whose generation moved since the read started is skipped: a
    /// change alert or match handler published newer state while this read
    /// was running. Applying the older read would roll it back, and for ports
    /// would feed the session tracker a false transition. Any skip queues a
    /// follow-up read, because the other watchers' results (power synthesis
    /// in particular) were computed from the skipped watcher's older read, and
    /// one more read brings them back in line.
    private func apply(_ reading: HubReading, readStartedAt start: Generations) {
        var skipped = false
        if portWatcher.refreshGeneration == start.port { portWatcher.apply(reading.ports) } else { skipped = true }
        if pdWatcher.refreshGeneration == start.pd { pdWatcher.apply(reading.pd) } else { skipped = true }
        // Power was synthesized from this read's ports and PD identities, so a
        // skipped port or PD slice makes it stale too (`skipped` is already set).
        if powerWatcher.refreshGeneration == start.power, !skipped {
            powerWatcher.apply(.init(sources: reading.power.sources, charger: nil))
        } else {
            skipped = true
        }
        // The charger figures have their own generation and do not depend on
        // ports or PD. They also need the readout still on: switching it off
        // mid-read zeroes them, and the read's figures must not come back. No
        // follow-up for a charger skip: the next tick reads it again.
        if let charger = reading.power.charger,
           powerWatcher.chargerGeneration == start.charger,
           powerWatcher.readsChargerInputWatts {
            powerWatcher.apply(.init(sources: powerWatcher.sources, charger: charger))
        }
        // Charge state: once per read, whatever was skipped above. The second
        // apply above carries no charge state, so it must not feed the window.
        powerWatcher.applyChargeState(reading.power.chargeState)
        powerWatcher.applyChargerSupply(reading.power.chargerHeldOffCandidate)
        if tbWatcher.refreshGeneration == start.tb { tbWatcher.apply(reading.thunderbolt) } else { skipped = true }
        if usb3Watcher.refreshGeneration == start.usb3 { usb3Watcher.apply(reading.usb3) } else { skipped = true }
        if trmWatcher.refreshGeneration == start.trm { trmWatcher.apply(reading.trm) } else { skipped = true }
        if displayWatcher.refreshGeneration == start.display { displayWatcher.apply(reading.display) } else { skipped = true }
        if uvdmWatcher.refreshGeneration == start.uvdm { uvdmWatcher.apply(reading.uvdm) } else { skipped = true }
        if skipped { followUpQueued = true }
    }

    /// The steady poll. Each tick requests a read and goes straight back to
    /// sleep, so the period is the interval itself, not interval plus read
    /// time; a tick that lands while a read is still running is dropped.
    private func startPoll() {
        pollTask?.cancel()
        let interval = isUIVisible ? activeInterval : idleInterval
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.requestRefresh(steady: true)
            }
        }
    }

    private func setupBurstTriggers() {
        deviceWatcher.$devices
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleBurst()
            }
            .store(in: &cancellables)

        powerWatcher.$sources
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleBurst()
            }
            .store(in: &cancellables)

        pdWatcher.$identities
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleBurst()
            }
            .store(in: &cancellables)
    }

    private func scheduleBurst() {
        burstTask?.cancel()
        burstTask = Task { @MainActor [weak self] in
            for delay in [150, 500, 1500, 3000, 6000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.refreshAll()
            }
        }
    }
}
