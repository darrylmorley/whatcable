import Foundation

/// Lightweight, pre-computed snapshot of port state for the desktop widget.
///
/// The main app builds this from its live watcher data and writes it to the
/// App Group shared container as JSON. The widget extension reads and
/// decodes it without touching IOKit.
public struct WidgetSnapshot: Codable, Equatable {
    public let ports: [PortEntry]
    public let timestamp: Date
    public let powerState: PowerState?

    public init(ports: [PortEntry], timestamp: Date = Date(), powerState: PowerState? = nil) {
        self.ports = ports
        self.timestamp = timestamp
        self.powerState = powerState
    }

    /// Custom decoder so that JSON written before `powerState` was added still
    /// decodes without error.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ports = try c.decode([PortEntry].self, forKey: .ports)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        powerState = try c.decodeIfPresent(PowerState.self, forKey: .powerState)
    }

    /// One port's display-ready state. Every field is pre-computed by the
    /// main app so the widget just decodes and renders.
    public struct PortEntry: Codable, Equatable, Identifiable {
        /// Stable numeric ID from the underlying AppleHPMInterface. Using the
        /// display name would break SwiftUI if two ports share the same
        /// description string.
        public let id: UInt64

        public let portName: String
        public let status: Status
        public let headline: String
        public let subtitle: String
        /// First bullet from PortSummary, used in the large widget size.
        public let topBullet: String?
        /// SF Symbol name for the port's current state.
        public let iconName: String
        /// Number of USB devices matched to this port. Zero when nothing
        /// is plugged in or the connection is power-only.
        public let deviceCount: Int
        /// Recent per-port wattage samples (oldest first), pre-rounded to 1
        /// decimal. Empty unless the port has been delivering power. Capped to
        /// keep the widget JSON small.
        public let recentPower: [Double]
        /// Stable string key matching the port in PowerState.perPortWatts.
        public let portKey: String?
        /// Wattage of any charger on this port, when available.
        public let chargerWatts: Int?
        /// Structured negotiated link speed, for the colour-coded speed badge.
        /// Nil when there's no active data link to badge.
        public let linkSpeed: LinkSpeed?
        /// Compact live display mode for the display card, e.g. "5K 60Hz".
        /// Nil unless a display is connected on this port.
        public let displayMode: String?
        /// Monitor name from EDID when a display is connected, e.g. "Studio
        /// Display". Often nil on generic displays; the card falls back to the
        /// mode alone. When several monitors share one port (a dock fan-out,
        /// issue #271) this is the first; `displayCount` carries the total.
        public let monitorName: String?
        /// Number of monitors driven through this port. 0 when none, 1 in the
        /// common case, more when a dock fans several out of one port. The card
        /// shows a "+N" hint when this exceeds 1 (issue #271).
        public let displayCount: Int
        /// Apple's own name for the accessory, from the port's UVDM node
        /// ("iPhone", "Studio Display", "96W USB-C Power Adapter"). Nil for
        /// every non-Apple accessory, which never publishes one. Carried as its
        /// own field rather than left to `topBullet`: the top line is whatever
        /// the Mac measured, so an iPhone on USB 2 showed a link-speed string
        /// where the device name belonged.
        public let accessoryName: String?

        public init(
            id: UInt64,
            portName: String,
            status: Status,
            headline: String,
            subtitle: String,
            topBullet: String?,
            iconName: String,
            deviceCount: Int = 0,
            recentPower: [Double] = [],
            portKey: String? = nil,
            chargerWatts: Int? = nil,
            linkSpeed: LinkSpeed? = nil,
            displayMode: String? = nil,
            monitorName: String? = nil,
            displayCount: Int = 0,
            accessoryName: String? = nil
        ) {
            self.id = id
            self.portName = portName
            self.status = status
            self.headline = headline
            self.subtitle = subtitle
            self.topBullet = topBullet
            self.iconName = iconName
            self.deviceCount = deviceCount
            self.recentPower = recentPower
            self.portKey = portKey
            self.chargerWatts = chargerWatts
            self.linkSpeed = linkSpeed
            self.displayMode = displayMode
            self.monitorName = monitorName
            self.displayCount = displayCount
            self.accessoryName = accessoryName
        }

        /// Custom decoder so that JSON written before `deviceCount` was
        /// added (pre-0.9.0) still decodes without error. Swift's
        /// synthesized Decodable ignores init parameter defaults, so
        /// without this a missing key would throw. The same applies to the
        /// later `linkSpeed` / `displayMode` / `monitorName` fields.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UInt64.self, forKey: .id)
            portName = try c.decode(String.self, forKey: .portName)
            status = try c.decode(Status.self, forKey: .status)
            headline = try c.decode(String.self, forKey: .headline)
            subtitle = try c.decode(String.self, forKey: .subtitle)
            topBullet = try c.decodeIfPresent(String.self, forKey: .topBullet)
            iconName = try c.decode(String.self, forKey: .iconName)
            deviceCount = try c.decodeIfPresent(Int.self, forKey: .deviceCount) ?? 0
            recentPower = try c.decodeIfPresent([Double].self, forKey: .recentPower) ?? []
            portKey = try c.decodeIfPresent(String.self, forKey: .portKey)
            chargerWatts = try c.decodeIfPresent(Int.self, forKey: .chargerWatts)
            linkSpeed = try c.decodeIfPresent(LinkSpeed.self, forKey: .linkSpeed)
            displayMode = try c.decodeIfPresent(String.self, forKey: .displayMode)
            monitorName = try c.decodeIfPresent(String.self, forKey: .monitorName)
            displayCount = try c.decodeIfPresent(Int.self, forKey: .displayCount) ?? 0
            accessoryName = try c.decodeIfPresent(String.self, forKey: .accessoryName)
        }
    }

    /// System-wide power state, populated by the Pro power telemetry plugin.
    /// Nil in builds without the plugin or when no power data is available.
    public struct PowerState: Codable, Equatable {
        public let batteryPercent: Int?
        public let isCharging: Bool
        public let fullyCharged: Bool
        public let isDesktopMac: Bool
        public let adapterWatts: Int?
        public let adapterDescription: String?
        public let systemPowerInWatts: Double?
        public let perPortWatts: [PortPowerEntry]?
        public let recentSystemPower: [Double]

        public init(
            batteryPercent: Int? = nil,
            isCharging: Bool = false,
            fullyCharged: Bool = false,
            isDesktopMac: Bool = false,
            adapterWatts: Int? = nil,
            adapterDescription: String? = nil,
            systemPowerInWatts: Double? = nil,
            perPortWatts: [PortPowerEntry]? = nil,
            recentSystemPower: [Double] = []
        ) {
            self.batteryPercent = batteryPercent
            self.isCharging = isCharging
            self.fullyCharged = fullyCharged
            self.isDesktopMac = isDesktopMac
            self.adapterWatts = adapterWatts
            self.adapterDescription = adapterDescription
            self.systemPowerInWatts = systemPowerInWatts
            self.perPortWatts = perPortWatts
            self.recentSystemPower = recentSystemPower
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            batteryPercent = try c.decodeIfPresent(Int.self, forKey: .batteryPercent)
            isCharging = try c.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
            fullyCharged = try c.decodeIfPresent(Bool.self, forKey: .fullyCharged) ?? false
            isDesktopMac = try c.decodeIfPresent(Bool.self, forKey: .isDesktopMac) ?? false
            adapterWatts = try c.decodeIfPresent(Int.self, forKey: .adapterWatts)
            adapterDescription = try c.decodeIfPresent(String.self, forKey: .adapterDescription)
            systemPowerInWatts = try c.decodeIfPresent(Double.self, forKey: .systemPowerInWatts)
            perPortWatts = try c.decodeIfPresent([PortPowerEntry].self, forKey: .perPortWatts)
            recentSystemPower = try c.decodeIfPresent([Double].self, forKey: .recentSystemPower) ?? []
        }
    }

    /// Per-port power reading, keyed so the widget can correlate with PortEntry.
    public struct PortPowerEntry: Codable, Equatable {
        public let portKey: String
        public let portName: String
        public let watts: Double
        public let recentSamples: [Double]

        public init(portKey: String, portName: String, watts: Double, recentSamples: [Double] = []) {
            self.portKey = portKey
            self.portName = portName
            self.watts = watts
            self.recentSamples = recentSamples
        }
    }

    /// Mirrors PortSummary.Status but Codable. The widget extension maps
    /// this to colors independently (no SwiftUI in WhatCableCore).
    public enum Status: String, Codable {
        case empty
        case charging
        case batteryFull
        case dataDevice
        case thunderboltCable
        case displayCable
        case unknown
    }
}

// MARK: - Structural comparison

extension WidgetSnapshot {
    /// A structural-only view of the snapshot: everything that changes the
    /// widget's shape (a port appearing or disappearing, headline/subtitle
    /// text, charger wattage, link speed badge, display mode...) but none of
    /// the live power magnitudes.
    ///
    /// Power readings wobble by tenths of a watt roughly once a second (the
    /// Pro power telemetry poll runs at 1 Hz). Comparing full `PortEntry` /
    /// `PowerState` values, sample arrays included, means every tick looks
    /// different and nothing is ever deduped. This signature deliberately
    /// omits `recentPower`, `systemPowerInWatts`, `perPortWatts` wattage and
    /// samples, and `recentSystemPower`, keeping only their PRESENCE where
    /// presence itself is structural (e.g. "some system-power reading now
    /// exists" or "this port now has power" is a real state change; the
    /// number attached to it is not).
    ///
    /// Two snapshots with the same signature look the same to the app-side
    /// caller deciding whether to write the shared cache file. The
    /// fluctuating values are still delivered: the heartbeat write carries a
    /// fresh copy of the whole snapshot on its own fixed cadence regardless
    /// of this signature.
    public struct StructuralSignature: Equatable {
        public struct Port: Equatable {
            public let id: UInt64
            public let portName: String
            public let status: Status
            public let headline: String
            public let subtitle: String
            public let topBullet: String?
            public let iconName: String
            public let deviceCount: Int
            public let portKey: String?
            public let chargerWatts: Int?
            public let linkSpeed: LinkSpeed?
            public let displayMode: String?
            public let monitorName: String?
            public let displayCount: Int
            public let accessoryName: String?
        }

        public let ports: [Port]
        public let batteryPercent: Int?
        public let isCharging: Bool
        public let fullyCharged: Bool
        public let isDesktopMac: Bool
        public let adapterWatts: Int?
        public let adapterDescription: String?
        /// Whether a system-draw reading exists at all, not its value.
        public let hasSystemPower: Bool
        /// Which ports currently report power, by key. Presence, not wattage.
        public let poweredPortKeys: [String]
    }

    /// The structural signature of this snapshot. See `StructuralSignature`.
    public var structuralSignature: StructuralSignature {
        StructuralSignature(
            ports: ports.map { p in
                StructuralSignature.Port(
                    id: p.id,
                    portName: p.portName,
                    status: p.status,
                    headline: p.headline,
                    subtitle: p.subtitle,
                    topBullet: p.topBullet,
                    iconName: p.iconName,
                    deviceCount: p.deviceCount,
                    portKey: p.portKey,
                    chargerWatts: p.chargerWatts,
                    linkSpeed: p.linkSpeed,
                    displayMode: p.displayMode,
                    monitorName: p.monitorName,
                    displayCount: p.displayCount,
                    accessoryName: p.accessoryName
                )
            },
            batteryPercent: powerState?.batteryPercent,
            isCharging: powerState?.isCharging ?? false,
            fullyCharged: powerState?.fullyCharged ?? false,
            isDesktopMac: powerState?.isDesktopMac ?? false,
            adapterWatts: powerState?.adapterWatts,
            adapterDescription: powerState?.adapterDescription,
            hasSystemPower: powerState?.systemPowerInWatts != nil,
            poweredPortKeys: (powerState?.perPortWatts ?? []).map(\.portKey).sorted()
        )
    }
}

// MARK: - App Group constants

extension WidgetSnapshot {
    /// App Group suite name shared between the main app and widget extension.
    ///
    /// This intentionally uses macOS' unprovisioned App Group format:
    /// `<Developer Team ID>.<group name>`. For Developer ID notarized builds,
    /// Apple requires `group.` identifiers to be present in an embedded
    /// provisioning profile, but team-prefixed identifiers are authorized by
    /// the signing TeamIdentifier alone. That keeps the GitHub/Homebrew build
    /// profile-free while still giving the sandboxed WidgetKit extension a
    /// real shared container with the non-sandboxed host app.
    public static let appGroupID = "M4RUJ7W6MP.uk.whatcable.whatcable"

    /// UserDefaults key for the encoded snapshot blob (legacy, kept for reference).
    public static let defaultsKey = "widgetSnapshot"

    /// File-based shared data URL. The widget reads this same path via the
    /// matching team-prefixed App Group entitlement; no provisioning profile
    /// is required for Developer ID distribution on macOS.
    public static var sharedFileURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )?.appendingPathComponent("widgetSnapshot.json")
    }
}

// MARK: - Conversion from CableSnapshot

extension WidgetSnapshot {
    /// Build a WidgetSnapshot from a live CableSnapshot.
    ///
    /// Called by the widget's timeline provider after a direct IOKit read.
    /// The main app's WidgetDataWriter path is richer (it has Pro power
    /// telemetry and live per-port wattage histories from plugin contributors).
    /// This conversion produces the same structural shape with these differences:
    ///
    /// - `recentPower`: always empty. Power history comes from the running app's
    ///   Pro plugin contributors. The widget shows it when the app has written
    ///   it to the cache; the live-read path just leaves it blank rather than
    ///   inventing values. Callers that want the chart should prefer the cached
    ///   snapshot's recentPower for any port whose structural identity matches.
    ///
    /// - `powerState.systemPowerInWatts` / `perPortWatts`: always nil for the
    ///   same reason. The battery percent, isCharging, adapterWatts, and
    ///   isDesktopMac are all available from the live read and are populated.
    ///
    /// - `chargerWatts`: resolved from USB-PD sources in the snapshot, with
    ///   the same ChargerWattageSource logic the app uses. May differ from the
    ///   cached value if the adapter reading changed between runs.
    ///
    /// - `displayMode` / `monitorName` / `displayCount`: read from
    ///   `CableSnapshot.displayPorts` via DisplayDiagnostic, the same path the
    ///   CLI's JSON output uses.
    public init(from cable: CableSnapshot) {
        let batteryFullyCharged = cable.batteryFullyCharged
        let batteryIsCharging = cable.batteryIsCharging
        let adapter = cable.adapter
        let chargerAttached = (adapter?.watts ?? 0) > 0
        let activePortCount = cable.ports.filter { $0.connectionActive == true }.count
        let chargerSourceCount = ChargerWattageSource.chargerSourceCount(
            ports: cable.ports, sources: cable.powerSources)

        let entries: [PortEntry] = cable.ports.map { port in
            // Two device values on purpose (plan pcie-tunnelled-usb-attribution):
            // `attributed` is the union of native matches and tunnelled devices
            // structurally scoped to this port (LG UltraFine-class PCIe docks);
            // it feeds liveness and the device count, so the widget sees
            // everything the port card shows. `matched` (native only) feeds
            // PortSummary, whose speed-corroboration inputs are
            // native-bus-local by design; the app's card does the same, so
            // widget and app headlines cannot diverge.
            let attributed = TunnelledDeviceGrouping.attributedDevices(
                for: port, in: cable.usbDevices, thunderboltSwitches: cable.thunderboltSwitches
            )
            let devices = port.matchingDevices(from: cable.usbDevices)
            let sources = cable.powerSources.filter { $0.canonicallyMatches(port: port) }
            let identities = cable.identities.filter { $0.canonicallyMatches(port: port) }

            let isLive = isPortLive(
                port: port,
                powerSources: sources,
                identities: identities,
                matchingDevices: attributed,
                chargerAttached: chargerAttached
            )

            let usb3 = cable.usb3Transports.filter { $0.canonicallyMatches(port: port) }
            let cio = cable.cioCapabilities.first { $0.canonicallyMatches(port: port) }
            let accessory = cable.accessoryIdentities.first { $0.canonicallyMatches(port: port) }

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
                thunderboltSwitches: cable.thunderboltSwitches,
                federatedIdentities: cable.federatedIdentities,
                usb3Transports: usb3,
                trmTransports: cable.trmTransports.filter { $0.canonicallyMatches(port: port) },
                cioCapability: cio,
                accessoryIdentity: accessory,
                isConnectedOverride: isLive,
                chargerWattageSource: wattageSource,
                batteryFullyCharged: batteryFullyCharged,
                batteryIsCharging: batteryIsCharging,
                adapter: adapter
            )

            let status = Status(from: summary.status)

            // Display detail from the live DisplayPort transport list.
            // Only populated when a display is connected; `portKey != nil` guard
            // prevents a keyless port from borrowing a keyless display entry.
            var displayMode: String?
            var monitorName: String?
            var displayCount = 0
            if port.portKey != nil {
                let diags = cable.displayPorts
                    .filter { $0.canonicallyMatches(port: port) }
                    .compactMap { DisplayDiagnostic(dp: $0, cable: nil) }
                displayCount = diags.count
                if let first = diags.first {
                    displayMode = first.facts.currentMode?.shortLabel
                    monitorName = first.facts.monitorName
                }
            }

            return PortEntry(
                id: port.id,
                portName: port.portDescription ?? port.serviceName,
                status: status,
                headline: summary.headline,
                subtitle: summary.subtitle,
                topBullet: summary.topLine,
                iconName: status.iconName,
                deviceCount: attributed.count,
                // recentPower is always empty here: power history comes from
                // the app's Pro plugin contributors and is not in CableSnapshot.
                // The widget will show the sparkline when the app has written it
                // to the App Group cache; the live-read path leaves it blank.
                recentPower: [],
                portKey: port.portKey,
                // Gate the wattage pill on the same stale-PDO signal as the
                // status, so the widget can't show "96W" while reading "Connected".
                chargerWatts: SystemPowerState.onBattery(batteryIsCharging: batteryIsCharging, adapter: adapter)
                    ? nil : wattageSource.watts,
                linkSpeed: summary.linkSpeed,
                displayMode: displayMode,
                monitorName: monitorName,
                displayCount: displayCount,
                accessoryName: accessory?.displayName
            )
        }

        // Build PowerState from what is available in the live snapshot.
        // systemPowerInWatts and perPortWatts are nil: they require the Pro
        // plugin's accumulation loop, which only runs in the main app process.
        let battery = cable.batteryFullyCharged != nil || cable.batteryIsCharging != nil
        let powerState = WidgetSnapshot.PowerState(
            batteryPercent: nil, // not in CableSnapshot; battery % is in SmartBattery reader
            isCharging: cable.batteryIsCharging ?? false,
            fullyCharged: cable.batteryFullyCharged ?? false,
            isDesktopMac: cable.isDesktopMac,
            adapterWatts: adapter?.watts,
            adapterDescription: adapter?.adapterDescription,
            systemPowerInWatts: nil,
            perPortWatts: nil,
            recentSystemPower: []
        )

        // Native HDMI / built-in display port entries. Synthesized as widget
        // PortEntry rows so the widget's existing display-card layout picks
        // them up alongside USB-C ports. Issue #352.
        let builtInDisplayEntries: [PortEntry] = BuiltInDisplayPort.group(from: cable.displayPorts).map { hdmiPort in
            // The grouping function filters inactive DP nodes, so each
            // entity carries at least one attached display.
            let firstDiag = hdmiPort.displays.compactMap { DisplayDiagnostic(dp: $0, cable: nil) }.first
            let headline = String(localized: "Display connected", bundle: _coreLocalizedBundle)
            let subtitle = String(localized: "Built-in \(hdmiPort.portType) port \(hdmiPort.portNumber)", bundle: _coreLocalizedBundle)
            // Real port ids are kernel-assigned IOKit entry ids and always
            // small. Synthesized HDMI ids sit at the top of UInt64 so they
            // never collide.
            let id = UInt64.max - UInt64(max(0, hdmiPort.portNumber))
            return PortEntry(
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

        self.init(
            ports: entries + builtInDisplayEntries,
            timestamp: Date(),
            powerState: battery ? powerState : nil
        )
    }
}

// MARK: - Convenience builders

extension WidgetSnapshot.Status {
    /// Convert from the existing PortSummary.Status enum.
    public init(from summary: PortSummary.Status) {
        switch summary {
        case .empty: self = .empty
        case .charging: self = .charging
        case .batteryFull: self = .batteryFull
        case .dataDevice: self = .dataDevice
        case .thunderboltCable: self = .thunderboltCable
        case .displayCable: self = .displayCable
        case .unknown: self = .unknown
        }
    }
}

extension WidgetSnapshot.Status {
    /// SF Symbol name for this status. Matches the icon mapping in
    /// PortSummary+UI.swift so the widget and main app show the same icons.
    public var iconName: String {
        switch self {
        case .empty: return "powerplug"
        case .charging: return "bolt.fill"
        case .batteryFull: return "battery.100"
        case .dataDevice: return "cable.connector"
        case .thunderboltCable: return "bolt.horizontal.fill"
        case .displayCable: return "display"
        case .unknown: return "questionmark.circle"
        }
    }
}
