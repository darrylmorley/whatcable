import Foundation
import WhatCableCore

/// Stub Linux backend. Returns empty snapshots until the sysfs / udev
/// implementation lands. Wires up the build graph and CI so the parser
/// work in subsequent sub-steps drops into a working scaffold.
public final class LinuxSnapshotProvider: CableSnapshotProvider, @unchecked Sendable {
    public init() {}

    public func snapshot() async throws -> CableSnapshot {
        CableSnapshot(
            ports: [],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil
        )
    }

    public func watch() -> AsyncThrowingStream<CableSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let empty = CableSnapshot(
                    ports: [],
                    powerSources: [],
                    identities: [],
                    usbDevices: [],
                    adapter: nil
                )
                continuation.yield(empty)
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

public func makeDefaultSnapshotProvider() -> any CableSnapshotProvider {
    LinuxSnapshotProvider()
}
