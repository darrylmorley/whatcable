import Foundation

/// One voltage/current combo from the charger's HVC (High Voltage Charging)
/// menu. This is what the charger advertises it can deliver at the system
/// level, read from `IOPSCopyExternalPowerAdapterDetails()`. Distinct from
/// `PowerOption` (which is the per-port USB-PD negotiation result).
public struct AdapterHVCEntry: Hashable, Sendable {
    /// Voltage in millivolts (e.g. 20000 for 20V).
    public let voltageMV: Int
    /// Maximum current in milliamps (e.g. 4990 for ~5A).
    public let currentMA: Int

    public init(voltageMV: Int, currentMA: Int) {
        self.voltageMV = voltageMV
        self.currentMA = currentMA
    }

    /// Watts this entry can deliver (voltage * current).
    public var wattsInt: Int {
        Int((Double(voltageMV) * Double(currentMA) / 1_000_000).rounded())
    }

    public var label: String { label(locale: .current) }

    /// Locale-injectable form, so tests can pin a locale instead of
    /// inheriting the runner's region.
    public func label(locale: Locale) -> String {
        let v = String(format: "%.0fV", locale: locale, Double(voltageMV) / 1000)
        let a = String(format: "%.2fA", locale: locale, Double(currentMA) / 1000)
        return "\(v)/\(a)"
    }
}

/// The single definition of "the Mac is running on battery, so a retained
/// (stale) winning PDO must not drive charging copy, wattage, or diagnostics."
///
/// A USB-C controller can keep a winning PDO around after macOS stops drawing
/// external power. Charging output keyed on that PDO alone then lies. This is
/// the one definition of the gate, so callers can't each inline a subtly
/// different test (an earlier fix did exactly that and other surfaces silently
/// bypassed it).
///
/// Charging-STATUS surfaces route through it today: `PortSummary`,
/// `ChargingDiagnostic`, the widget `chargerWatts` pill, the Dashboard, and the
/// Negotiation window. The WATTAGE-telemetry surfaces are now gated too
/// and each is keyed on the same idea via the signals it has to hand:
/// - The Power Monitor window drops stale incoming-contract samples with
///   `[PortPowerSample].droppingStaleContracted(externalPowerAbsent:)`, passing
///   `PowerMonitorSnapshot.externalPowerAbsent` (`onBattery || !chargerAttached`)
///   so the live adapter closes the post-unplug race the lagging `onBattery`
///   alone leaves open. Both signals now come from the snapshot, so they
///   describe the same tick as the samples they qualify.
/// - The widget's `PowerTelemetryContributor` uses the same
///   `PowerMonitorSnapshot.externalPowerAbsent`. It used to gate on plain
///   `onBattery`, justified as "it isn't a live surface, so it doesn't need the
///   `chargerAttached` refinement". That was right about the widget's DISPLAY,
///   which the OS refreshes on its own schedule, and wrong about the buffer it
///   reads: the contributor updates that at 1 Hz inside the app, so during the
///   seconds ExternalConnected lags an unplug it kept recording a contract the
///   window had already dropped, and the stale values stayed in its rolling
///   history.
/// - Cable Diagnostics gates its charger card / pin overlay on
///   `SystemPowerState.onBattery(...)` directly.
/// The gate targets only the incoming charging contract
/// (`isContractedFallback == true`); SMC-measured readings and `PowerOutDetails`
/// power-out throughput are never suppressed, so a Mac delivering power out of a
/// port on battery still shows. New charging/wattage display must apply the same
/// gate (this helper for a sample list, or `SystemPowerState.onBattery`).
///
/// True only when charging is *explicitly* off AND no system adapter is present.
/// A nil `batteryIsCharging` (desktop Mac, unknown) is never on battery here, so
/// desktops are never suppressed. A genuine 100% charge hold reports an adapter,
/// so `adapter != nil` keeps it out too; battery-full is deliberately not part
/// of the test.
public enum SystemPowerState {
    public static func onBattery(batteryIsCharging: Bool?, adapter: AdapterInfo?) -> Bool {
        batteryIsCharging == false && adapter == nil
    }
}

/// External power adapter info. Populated by the Darwin backend from
/// `IOPSCopyExternalPowerAdapterDetails()`. This is a system-wide view
/// of the connected charger brick, not a per-port reading.
public struct AdapterInfo: Hashable, Sendable {
    public let watts: Int?
    public let isCharging: Bool?
    public let source: String?  // "AC" / "Battery" / nil
    /// Negotiated adapter voltage in millivolts (e.g. 20000 for 20V).
    public let voltageMV: Int?
    /// Negotiated adapter current in milliamps (e.g. 4990 for ~5A).
    public let currentMA: Int?
    /// Short description from IOKit, e.g. "pd charger" or "magsafe charger".
    public let adapterDescription: String?
    /// Apple's internal power tier classification (e.g. 2 for 100W).
    public let powerTier: Int?
    /// True when the adapter is wireless (MagSafe pad, etc.).
    public let isWireless: Bool?
    /// The charger's HVC (High Voltage Charging) menu: all voltage/current
    /// combos the charger says it can deliver. Empty when not available.
    public let hvcMenu: [AdapterHVCEntry]
    /// Index into hvcMenu indicating the currently active PDO step.
    public let hvcActiveIndex: Int?
    /// Charger family code from Apple's internal classification.
    public let familyCode: Int?
    /// Unique adapter identifier.
    public let adapterID: Int?
    /// PMU (Power Management Unit) configuration value.
    public let pmuConfiguration: Int?
    /// Charger brand from the IOKit `AdapterDetails.Manufacturer` key
    /// (e.g. "Apple Inc."). Present mostly on Apple bricks. Nil when the
    /// field is absent or empty.
    public let manufacturer: String?
    /// Product name from the IOKit `AdapterDetails.Name` key (e.g.
    /// "140W USB-C Power Adapter"). Pairs with `manufacturer`. Nil when
    /// the field is absent or empty.
    public let name: String?
    /// Apple-internal model code from `AdapterDetails.Model` (e.g. "0x7019").
    /// Distinct from the `Name`; not currently surfaced to users.
    public let model: String?

    public init(
        watts: Int?,
        isCharging: Bool?,
        source: String?,
        voltageMV: Int? = nil,
        currentMA: Int? = nil,
        adapterDescription: String? = nil,
        powerTier: Int? = nil,
        isWireless: Bool? = nil,
        hvcMenu: [AdapterHVCEntry] = [],
        hvcActiveIndex: Int? = nil,
        familyCode: Int? = nil,
        adapterID: Int? = nil,
        pmuConfiguration: Int? = nil,
        manufacturer: String? = nil,
        name: String? = nil,
        model: String? = nil
    ) {
        self.watts = watts
        self.isCharging = isCharging
        self.source = source
        self.voltageMV = voltageMV
        self.currentMA = currentMA
        self.adapterDescription = adapterDescription
        self.powerTier = powerTier
        self.isWireless = isWireless
        self.hvcMenu = hvcMenu
        self.hvcActiveIndex = hvcActiveIndex
        self.familyCode = familyCode
        self.adapterID = adapterID
        self.pmuConfiguration = pmuConfiguration
        self.manufacturer = manufacturer
        self.name = name
        self.model = model
    }
}

/// One unified view of cable / port / power state at a point in time.
/// Backends produce these; CLI and GUI consume them.
// TODO: Sendable — requires AppleHPMInterface, PowerSource, USBPDSOP, USBDevice to conform first
public struct CableSnapshot: Equatable {
    public let ports: [AppleHPMInterface]
    public let powerSources: [PowerSource]
    public let identities: [USBPDSOP]
    public let usbDevices: [USBDevice]
    public let adapter: AdapterInfo?
    /// Top-level array of every Thunderbolt switch the host can see. Empty
    /// on machines without a Thunderbolt controller, or when IOKit returns
    /// nothing (the JSON shape adds the key but with an empty array, so
    /// downstream consumers can rely on the field always being present).
    public let thunderboltSwitches: [IOThunderboltSwitch]
    /// True on desktop Macs (Mac Studio, Mac Mini, Mac Pro) where the
    /// AppleSmartBattery node is absent or reports BatteryInstalled=false.
    /// Per-port PD diagnostics from the battery controller are unavailable.
    public let isDesktopMac: Bool
    /// Per-port federated PD identity from AppleSmartBattery's FedDetails.
    /// Empty on desktops or when nothing is connected.
    public let federatedIdentities: [FederatedIdentity]
    /// USB 3 SuperSpeed link state per port. Present only while a USB 3
    /// device is connected; the IOKit services appear and disappear
    /// dynamically with plug/unplug events.
    public let usb3Transports: [USB3Transport]
    /// Per-transport TRM (Trust and Restrict Management) state. Present
    /// only while an accessory is connected; the IOKit transport services
    /// appear and disappear dynamically with plug/unplug events.
    public let trmTransports: [TRMTransport]
    /// CIO cable capability data from the Thunderbolt transport controller.
    /// Independent of USB-PD e-marker data. Present only while a
    /// Thunderbolt link is active.
    public let cioCapabilities: [CIOCableCapability]
    /// Apple accessory identity read from the port's UVDM node. Present only
    /// while an Apple accessory is connected; Apple-only by construction, since
    /// macOS decodes UVDM for vendor 0x05AC alone.
    public let accessoryIdentities: [AppleAccessoryIdentity]
    /// Per-port physical layer state from the TypeC PHY controller. Shows
    /// per-lane transport mode (CIO/DisplayPort/idle), USB2 state, and DP
    /// pixel clock. One entry per physical USB-C port.
    public let typeCPhys: [AppleTypeCPhy]
    /// Per-port DisplayPort transport state (link rate, lane count, and the
    /// monitor's EDID). Present only while a display is connected; the IOKit
    /// services appear and disappear with plug/unplug. Correlated to a port
    /// via `IOPortTransportStateDisplayPort.portKey`.
    public let displayPorts: [IOPortTransportStateDisplayPort]
    /// AppleSmartBattery's FullyCharged flag. `nil` on desktop Macs / when
    /// no battery is present, so consumers never claim "battery full" on a
    /// machine that has no battery.
    public let batteryFullyCharged: Bool?
    /// AppleSmartBattery's IsCharging flag. `nil` on desktop Macs / when no
    /// battery is present. `false` while a charger is connected but macOS has
    /// paused charging (charge limit or Optimized Battery Charging), even
    /// though FullyCharged is still false.
    public let batteryIsCharging: Bool?

    public init(
        ports: [AppleHPMInterface],
        powerSources: [PowerSource],
        identities: [USBPDSOP],
        usbDevices: [USBDevice],
        adapter: AdapterInfo?,
        thunderboltSwitches: [IOThunderboltSwitch] = [],
        isDesktopMac: Bool = false,
        federatedIdentities: [FederatedIdentity] = [],
        usb3Transports: [USB3Transport] = [],
        trmTransports: [TRMTransport] = [],
        cioCapabilities: [CIOCableCapability] = [],
        accessoryIdentities: [AppleAccessoryIdentity] = [],
        typeCPhys: [AppleTypeCPhy] = [],
        displayPorts: [IOPortTransportStateDisplayPort] = [],
        batteryFullyCharged: Bool? = nil,
        batteryIsCharging: Bool? = nil
    ) {
        self.ports = ports
        self.powerSources = powerSources
        self.identities = identities
        self.usbDevices = usbDevices
        self.adapter = adapter
        self.thunderboltSwitches = thunderboltSwitches
        self.isDesktopMac = isDesktopMac
        self.federatedIdentities = federatedIdentities
        self.usb3Transports = usb3Transports
        self.trmTransports = trmTransports
        self.cioCapabilities = cioCapabilities
        self.accessoryIdentities = accessoryIdentities
        self.typeCPhys = typeCPhys
        self.displayPorts = displayPorts
        self.batteryFullyCharged = batteryFullyCharged
        self.batteryIsCharging = batteryIsCharging
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
