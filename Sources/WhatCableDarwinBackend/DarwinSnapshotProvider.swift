#if os(macOS)
import Foundation
import WhatCableCore

/// macOS implementation of `CableSnapshotProvider`. Wraps the four IOKit
/// watcher classes and assembles their state into a `CableSnapshot`.
///
/// `snapshot()` starts the watchers once, refreshes the polling-driven ones
/// (the others fire IOKit match notifications during start), and reads.
/// `watch()` keeps them started and polls for changes on a 1s timer.
/// Polling is sufficient because `USBCPortWatcher` already requires it for
/// property-change events; the others share the same loop for simplicity.
public final class DarwinSnapshotProvider: CableSnapshotProvider, @unchecked Sendable {
    public init() {}

    @MainActor
    private final class State {
        let portWatcher = USBCPortWatcher()
        let powerWatcher = PowerSourceWatcher()
        let pdWatcher = PDIdentityWatcher()
        let usbWatcher = USBWatcher()
        var started = false

        func ensureStarted() {
            guard !started else { return }
            portWatcher.start()
            powerWatcher.start()
            pdWatcher.start()
            usbWatcher.start()
            started = true
        }

        func read() -> CableSnapshot {
            // USBCPort property changes don't fire match notifications,
            // so refresh on every read. The others are notification-driven
            // but refresh is cheap and keeps reads consistent.
            portWatcher.refresh()
            powerWatcher.refresh()
            pdWatcher.refresh()
            return CableSnapshot(
                ports: portWatcher.ports,
                powerSources: powerWatcher.sources,
                identities: pdWatcher.identities,
                usbDevices: usbWatcher.devices,
                adapter: SystemPower.currentAdapter()
            )
        }
    }

    @MainActor
    private static let state = State()

    @MainActor
    public func snapshot() async throws -> CableSnapshot {
        Self.state.ensureStarted()
        return Self.state.read()
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

#endif
