import CoreGraphics
import Foundation
import os.log
import WhatCableCore

/// macOS implementation of `CableSnapshotProvider`. Takes the shared
/// `HubRead` hardware read, publishes it through the IOKit watcher classes
/// and assembles their state into a `CableSnapshot`.
///
/// `snapshot()` starts the watchers once, refreshes the polling-driven ones
/// (the others fire IOKit match notifications during start), and reads.
/// `watch()` keeps them started and polls for changes on a 1s timer.
/// Polling is sufficient because `AppleHPMInterfaceWatcher` already requires it for
/// property-change events; the others share the same loop for simplicity.
public final class DarwinSnapshotProvider: CableSnapshotProvider, @unchecked Sendable {
    public init() { ownState = nil }

    /// A provider with its own state and a fully injected environment, so a
    /// test can drive `snapshot()`, `liveSurfaceSnapshot()` and `watch()`
    /// with a fixed `HubReading`. It opens no IOKit at all: no watcher is
    /// started (so no notification port can outlive a freed test provider,
    /// the #341 hazard) and every read the state makes is injected, as with
    /// `WatcherHub.init(read:)`. Production uses the shared state.
    @MainActor
    init(environment: Environment) {
        ownState = State(environment: environment)
    }

    /// Everything the state reaches outside itself. `live` is the hardware.
    struct Environment {
        var hubRead: (HubReadRequest, SMCPowerReader) -> HubReading
        /// Whether `ensureStarted()` starts the IOKit watchers. Only the
        /// hardware environment does.
        var startsWatchers: Bool
        var bitsPerComponent: @MainActor () -> [CGDirectDisplayID: Int]
        var readBattery: () -> AppleSmartBatteryReader.Result
        var readAdapter: () -> AdapterInfo?
        var readChargeStateAgain: (SMCPowerReader) -> BatteryChargeState?
        var sleep: (TimeInterval) async -> Void
        /// The power watcher's clock (the held-off hold, the charge-state
        /// debounce).
        var clock: () -> TimeInterval

        @MainActor static let live = Environment(
            hubRead: { HubRead.readAll($0, smcReader: $1) },
            startsWatchers: true,
            bitsPerComponent: { DisplayModeReader.currentBitsPerComponent() },
            readBattery: { AppleSmartBatteryReader.read() },
            readAdapter: { SystemPower.currentAdapter() },
            readChargeStateAgain: { PowerSourceWatcher.readChargeState(smcReader: $0) },
            sleep: { try? await Task.sleep(for: .seconds($0)) },
            clock: PowerSourceWatcher.monotonicNow)
    }

    private let ownState: State?

    private static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "charging")

    @MainActor
    private final class State {
        let portWatcher = AppleHPMInterfaceWatcher()
        let smcReader = SMCPowerReader()
        let powerWatcher: PowerSourceWatcher
        let pdWatcher = USBPDSOPWatcher()
        let usbWatcher = USBWatcher()
        let tbWatcher = IOIOThunderboltSwitchWatcher()
        let usb3Watcher = USB3TransportWatcher()
        let trmWatcher = TRMTransportWatcher()
        let phyWatcher = AppleTypeCPhyWatcher()
        let displayWatcher = DisplayPortTransportWatcher()
        let uvdmWatcher = AppleUVDMWatcher()
        var started = false
        /// The last read's undebounced charge state, for the one-shot confirm.
        var lastRawChargeState: BatteryChargeState?
        /// The last read's held-off candidate before the hold, which a one-shot
        /// `snapshot()` uses as is (issue 672).
        var lastRawHeldOffCandidate: Bool?

        let environment: Environment
        /// True once the IOKit watchers have been started. Never true for an
        /// injected (test) environment.
        private(set) var watchersStarted = false

        init(environment: Environment) {
            self.environment = environment
            powerWatcher = PowerSourceWatcher(smcReader: smcReader, clock: environment.clock)
        }

        func ensureStarted() {
            guard !started else { return }
            started = true
            // An injected (test) environment starts nothing: a started watcher
            // holds an IOKit notification port that would outlive a freed test
            // provider (#341).
            guard environment.startsWatchers else { return }
            watchersStarted = true
            portWatcher.start()
            powerWatcher.start()
            pdWatcher.start()
            usbWatcher.start()
            tbWatcher.start()
            usb3Watcher.start()
            trmWatcher.start()
            phyWatcher.start()
            displayWatcher.start()
            uvdmWatcher.start()
        }

        func read() -> CableSnapshot {
            // One shared read (HubRead) in the fixed order, then each watcher
            // publishes its piece. AppleHPMInterface property changes don't
            // fire match notifications, so every read refreshes everything;
            // the others are notification-driven but the read is cheap and
            // keeps the snapshot consistent. Power synthesis (issue #401)
            // is built inside the read from this read's own ports and
            // identities.
            let reading = environment.hubRead(
                HubReadRequest(readsChargerWatts: false,
                               displayBitsPerComponent: environment.bitsPerComponent(),
                               includesPhy: true),
                smcReader
            )
            portWatcher.apply(reading.ports)
            pdWatcher.apply(reading.pd)
            powerWatcher.apply(reading.power)
            powerWatcher.applyChargeState(reading.power.chargeState)
            powerWatcher.applyChargerSupply(reading.power.chargerHeldOffCandidate)
            lastRawHeldOffCandidate = reading.power.chargerHeldOffCandidate
            lastRawChargeState = reading.power.chargeState
            tbWatcher.apply(reading.thunderbolt)
            usb3Watcher.apply(reading.usb3)
            trmWatcher.apply(reading.trm)
            if let phy = reading.phy { phyWatcher.apply(phy) }
            displayWatcher.apply(reading.display)
            uvdmWatcher.apply(reading.uvdm)
            let battery = environment.readBattery()
            let snap = CableSnapshot(
                ports: portWatcher.ports,
                powerSources: powerWatcher.sources,
                identities: pdWatcher.identities,
                usbDevices: usbWatcher.devices,
                adapter: environment.readAdapter(),
                thunderboltSwitches: tbWatcher.switches,
                isDesktopMac: battery.isDesktopMac,
                federatedIdentities: battery.federatedIdentities,
                usb3Transports: usb3Watcher.transports,
                trmTransports: trmWatcher.transports,
                cioCapabilities: trmWatcher.cioCapabilities,
                accessoryIdentities: uvdmWatcher.identities,
                typeCPhys: phyWatcher.phys,
                // statuses are enriched with the live CoreGraphics mode at the
                // watcher source now, so no enrich is needed here.
                displayPorts: displayWatcher.statuses.map(\.status),
                batteryFullyCharged: battery.battery?.fullyCharged,
                batteryIsCharging: battery.battery?.isCharging,
                batteryChargeState: powerWatcher.batteryChargeState,
                chargerHeldOffSignal: powerWatcher.chargerHeldOffSignal
            )
            DarwinSnapshotProvider.logChargingSignals(snap)
            return snap
        }
    }

    @MainActor
    private static let sharedState = State(environment: .live)

    /// This provider's state: its own when built for a test, else the shared one.
    @MainActor
    private var state: State { ownState ?? Self.sharedState }

    /// Test hooks: whether this provider started any IOKit watcher, and one
    /// read exactly as a `watch()` tick makes it.
    @MainActor var watchersStartedForTesting: Bool { state.watchersStarted }
    @MainActor func streamTickForTesting() -> CableSnapshot { state.read() }

    /// One read for a one-shot caller (the CLI, bench report). The time
    /// window can't elapse inside one read, so a running-on-battery result is
    /// confirmed by a second SMC read 2 s later. The held-off charger signal
    /// is this read's raw value (a one-shot output has nothing to flash).
    @MainActor
    public func snapshot() async throws -> CableSnapshot {
        await oneShot(liveSurface: false)
    }

    /// The same read for a LIVE surface that paints from single reads between
    /// `watch()` updates (the dashboard's first paint and its `r` refresh). It
    /// carries the held-off charger signal after `ChargerHeldOffHold`, exactly
    /// as `watch()` does, so the card can't flip between a read's raw value and
    /// the stream's held one (issue 672). Reads advance the same hold the
    /// stream uses.
    @MainActor
    public func liveSurfaceSnapshot() async throws -> CableSnapshot {
        await oneShot(liveSurface: true)
    }

    @MainActor
    private func oneShot(liveSurface: Bool) async -> CableSnapshot {
        state.ensureStarted()
        let snap = state.read()
        let state = self.state
        let smc = state.smcReader
        let env = state.environment
        let result = await Self.finishOneShot(
            snap,
            rawChargeState: state.lastRawChargeState,
            // A live surface keeps the read's HELD value, as watch() yields it.
            rawHeldOff: liveSurface ? snap.chargerHeldOffSignal : state.lastRawHeldOffCandidate,
            readChargeStateAgain: { env.readChargeStateAgain(smc) },
            sleep: env.sleep)
        guard liveSurface else { return result }
        // The confirm read above can sleep (2 s) while the stream keeps
        // reading. Take the held value as it stands NOW, from the same hold
        // the stream advances, so this paint can't send the card back to an
        // older value that `watch()` (which yields only on change) would then
        // never correct (issue 672).
        var current = result
        current.chargerHeldOffSignal = state.powerWatcher.chargerHeldOffSignal
        return current
    }

    /// The one-shot finishing step, split out so a test can drive it with no
    /// hardware and no sleeping.
    nonisolated static func finishOneShot(
        _ read: CableSnapshot,
        rawChargeState: BatteryChargeState?,
        rawHeldOff: Bool?,
        readChargeStateAgain: () -> BatteryChargeState?,
        sleep: (TimeInterval) async -> Void
    ) async -> CableSnapshot {
        var snap = read
        snap.batteryChargeState = await PowerSourceWatcher.confirmedOneShotChargeState(
            first: rawChargeState, readAgain: readChargeStateAgain, sleep: sleep)
        // The held-off charger state (issue 672) waits only on live surfaces,
        // where it could flash. A one-shot read has nothing to flash, so it
        // uses this read's raw precondition and never waits: waiting here added
        // 5 s to every CLI call, the dashboard and each bench pass on a held Mac.
        snap.chargerHeldOffSignal = rawHeldOff
        return snap
    }

    private static func logChargingSignals(_ snap: CableSnapshot) {
        let activePorts = snap.ports.filter { $0.connectionActive == true }
        let adapterW = snap.adapter?.watts.map(String.init) ?? "none"
        log.debug(
            """
            charging signals: \(snap.ports.count) ports, \
            \(activePorts.count) active, \
            adapter \(adapterW)W
            """
        )
        for port in activePorts {
            guard let key = port.portKey else { continue }
            let sources = snap.powerSources.filter { $0.portKey == key }
            let names = sources.map { src -> String in
                let w = Int((Double(src.maxPowerMW) / 1000).rounded())
                return "\(src.name)(\(w)W)"
            }
            let label = port.portDescription ?? port.serviceName
            log.debug("  port \(label): sources=[\(names.joined(separator: ", "))]")
        }
    }

    public func watch() -> AsyncThrowingStream<CableSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let state = self.state
                state.ensureStarted()
                var last: CableSnapshot? = nil
                while !Task.isCancelled {
                    let snap = state.read()
                    if last != snap {
                        continuation.yield(snap)
                        last = snap
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

/// Default backend on Darwin platforms. CLI / GUI call this rather than
/// naming `DarwinSnapshotProvider` directly.
public func makeDefaultSnapshotProvider() -> any CableSnapshotProvider {
    DarwinSnapshotProvider()
}

