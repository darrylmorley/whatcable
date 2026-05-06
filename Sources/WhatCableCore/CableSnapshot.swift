import Foundation

/// External power adapter info. Populated by the Darwin backend from IOKit.
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
    /// Top-level array of every Thunderbolt switch the host can see. Empty
    /// on machines without a Thunderbolt controller, or when IOKit returns
    /// nothing (the JSON shape adds the key but with an empty array, so
    /// downstream consumers can rely on the field always being present).
    public let thunderboltSwitches: [ThunderboltSwitch]

    public init(
        ports: [USBCPort],
        powerSources: [PowerSource],
        identities: [PDIdentity],
        usbDevices: [USBDevice],
        adapter: AdapterInfo?,
        thunderboltSwitches: [ThunderboltSwitch] = []
    ) {
        self.ports = ports
        self.powerSources = powerSources
        self.identities = identities
        self.usbDevices = usbDevices
        self.adapter = adapter
        self.thunderboltSwitches = thunderboltSwitches
    }
}

/// Platform backends conform to this. CLI and GUI bind to the protocol,
/// not to a concrete watcher class.
///
/// `watch()` semantics:
/// - Emits an initial snapshot immediately.
/// - After that, emits only when the snapshot actually changes.
/// - Cancellation tears down underlying IOKit notifications and timers
///   via the stream's `onTermination` handler.
/// - Errors finish the stream; backends must not retry silently.
public protocol CableSnapshotProvider: Sendable {
    func snapshot() async throws -> CableSnapshot
    func watch() -> AsyncThrowingStream<CableSnapshot, Error>
}
