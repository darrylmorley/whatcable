import Foundation

/// External power adapter info, platform-agnostic. Populated by the Darwin
/// backend from IOKit, or by the Linux backend from sysfs (where exposed).
public struct AdapterInfo: Hashable {
    public let watts: Int?
    public let isCharging: Bool?
    public let source: String?  // "AC" / "Battery" / nil

    public init(watts: Int?, isCharging: Bool?, source: String?) {
        self.watts = watts
        self.isCharging = isCharging
        self.source = source
    }
}

/// One unified view of cable / port / power state at a point in time.
/// Backends produce these; CLI and GUI consume them.
// TODO: Sendable — requires USBCPort, PowerSource, PDIdentity, USBDevice to conform first
public struct CableSnapshot: Equatable {
    public let ports: [USBCPort]
    public let powerSources: [PowerSource]
    public let identities: [PDIdentity]
    public let usbDevices: [USBDevice]
    public let adapter: AdapterInfo?

    public init(
        ports: [USBCPort],
        powerSources: [PowerSource],
        identities: [PDIdentity],
        usbDevices: [USBDevice],
        adapter: AdapterInfo?
    ) {
        self.ports = ports
        self.powerSources = powerSources
        self.identities = identities
        self.usbDevices = usbDevices
        self.adapter = adapter
    }
}

/// Platform backends conform to this. CLI and GUI bind to the protocol,
/// not to a concrete watcher class.
///
/// `watch()` semantics:
/// - Emits an initial snapshot immediately.
/// - After that, emits only when the snapshot actually changes.
/// - Cancellation tears down underlying timers / udev / netlink sources
///   via the stream's `onTermination` handler.
/// - Errors finish the stream; backends must not retry silently.
public protocol CableSnapshotProvider: Sendable {
    func snapshot() async throws -> CableSnapshot
    func watch() -> AsyncThrowingStream<CableSnapshot, Error>
}
