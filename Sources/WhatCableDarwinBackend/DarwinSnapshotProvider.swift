import Foundation
import WhatCableCore

/// macOS implementation of `CableSnapshotProvider`. Wraps the existing
/// IOKit watcher classes and assembles their state into a `CableSnapshot`.
///
/// For now `watch()` is a poll-based stream (1s interval). The Darwin
/// watchers already publish notifications internally; replacing the
/// poller with a notification-driven stream is a future tightening, not
/// part of the carve-out.
public final class DarwinSnapshotProvider: CableSnapshotProvider, @unchecked Sendable {
    public init() {}

    @MainActor
    public func snapshot() async throws -> CableSnapshot {
        let portWatcher = USBCPortWatcher()
        let powerWatcher = PowerSourceWatcher()
        let pdWatcher = PDIdentityWatcher()

        portWatcher.refresh()
        powerWatcher.refresh()
        pdWatcher.refresh()

        // USBWatcher is notification-driven and doesn't expose a synchronous
        // refresh; USB devices are omitted from one-shot snapshots for now.
        // The watch() path via DarwinSnapshotProvider is not yet wired into
        // the CLI or GUI (that's sub-step 1f), so this is acceptable.
        return CableSnapshot(
            ports: portWatcher.ports,
            powerSources: powerWatcher.sources,
            identities: pdWatcher.identities,
            usbDevices: [],
            adapter: SystemPower.currentAdapter()
        )
    }

    public func watch() -> AsyncThrowingStream<CableSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                var last: CableSnapshot? = nil
                while !Task.isCancelled {
                    do {
                        let snap = try await self.snapshot()
                        if last == nil || !snapshotsEqual(last!, snap) {
                            continuation.yield(snap)
                            last = snap
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
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

/// Naive equality: compare stable IDs. Replaced with structural
/// equality once value types adopt `Equatable` cleanly.
private func snapshotsEqual(_ a: CableSnapshot, _ b: CableSnapshot) -> Bool {
    a.ports.map(\.id) == b.ports.map(\.id)
        && a.powerSources.map(\.id) == b.powerSources.map(\.id)
        && a.identities.map(\.id) == b.identities.map(\.id)
        && a.usbDevices.map(\.id) == b.usbDevices.map(\.id)
        && a.adapter?.watts == b.adapter?.watts
}

/// Default backend on Darwin platforms. CLI / GUI call this rather than
/// naming `DarwinSnapshotProvider` directly.
public func makeDefaultSnapshotProvider() -> any CableSnapshotProvider {
    DarwinSnapshotProvider()
}
