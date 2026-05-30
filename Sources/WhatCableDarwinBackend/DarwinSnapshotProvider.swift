import Foundation
import os.log
import WhatCableCore

/// macOS implementation of `CableSnapshotProvider`. Wraps the four IOKit
/// watcher classes and assembles their state into a `CableSnapshot`.
///
/// `snapshot()` starts the watchers once, refreshes the polling-driven ones
/// (the others fire IOKit match notifications during start), and reads.
/// `watch()` keeps them started and polls for changes on a 1s timer.
/// Polling is sufficient because `AppleHPMInterfaceWatcher` already requires it for
/// property-change events; the others share the same loop for simplicity.
public final class DarwinSnapshotProvider: CableSnapshotProvider, @unchecked Sendable {
    public init() {}

    private static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "charging")

    @MainActor
    private final class State {
        let portWatcher = AppleHPMInterfaceWatcher()
        let powerWatcher = PowerSourceWatcher()
        let pdWatcher = USBPDSOPWatcher()
        let usbWatcher = USBWatcher()
        let tbWatcher = IOIOThunderboltSwitchWatcher()
        let usb3Watcher = USB3TransportWatcher()
        let trmWatcher = TRMTransportWatcher()
        let phyWatcher = AppleTypeCPhyWatcher()
        let displayWatcher = DisplayPortTransportWatcher()
        var started = false

        func ensureStarted() {
            guard !started else { return }
            portWatcher.start()
            powerWatcher.start()
            pdWatcher.start()
            usbWatcher.start()
            tbWatcher.start()
            usb3Watcher.start()
            trmWatcher.start()
            phyWatcher.start()
            displayWatcher.start()
            started = true
        }

        func read() -> CableSnapshot {
            // AppleHPMInterface property changes don't fire match notifications,
            // so refresh on every read. The others are notification-driven
            // but refresh is cheap and keeps reads consistent.
            portWatcher.refresh()
            powerWatcher.refresh()
            pdWatcher.refresh()
            tbWatcher.refresh()
            usb3Watcher.refresh()
            trmWatcher.refresh()
            phyWatcher.refresh()
            displayWatcher.refresh()
            let battery = AppleSmartBatteryReader.read()
            let snap = CableSnapshot(
                ports: portWatcher.ports,
                powerSources: powerWatcher.sources,
                identities: pdWatcher.identities,
                usbDevices: usbWatcher.devices,
                adapter: SystemPower.currentAdapter(),
                thunderboltSwitches: tbWatcher.switches,
                isDesktopMac: battery.isDesktopMac,
                federatedIdentities: battery.federatedIdentities,
                usb3Transports: usb3Watcher.transports,
                trmTransports: trmWatcher.transports,
                cioCapabilities: trmWatcher.cioCapabilities,
                typeCPhys: phyWatcher.phys,
                displayPorts: displayWatcher.statuses.map(\.status),
                batteryFullyCharged: battery.battery?.fullyCharged
            )
            DarwinSnapshotProvider.logChargingSignals(snap)
            return snap
        }
    }

    @MainActor
    private static let state = State()

    @MainActor
    public func snapshot() async throws -> CableSnapshot {
        Self.state.ensureStarted()
        return Self.state.read()
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
                Self.state.ensureStarted()
                var last: CableSnapshot? = nil
                while !Task.isCancelled {
                    let snap = Self.state.read()
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

