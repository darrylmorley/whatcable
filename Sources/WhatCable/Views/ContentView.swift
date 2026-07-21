import SwiftUI
import WhatCableCore
import WhatCableDarwinBackend
import WhatCableAppKit

struct ContentView: View {
    @ObservedObject private var portWatcher = WatcherHub.shared.portWatcher
    @ObservedObject private var deviceWatcher = WatcherHub.shared.deviceWatcher
    @ObservedObject private var powerWatcher = WatcherHub.shared.powerWatcher
    @ObservedObject private var pdWatcher = WatcherHub.shared.pdWatcher
    @ObservedObject private var tbWatcher = WatcherHub.shared.tbWatcher
    @ObservedObject private var usb3Watcher = WatcherHub.shared.usb3Watcher
    @ObservedObject private var trmWatcher = WatcherHub.shared.trmWatcher
    @ObservedObject private var displayWatcher = WatcherHub.shared.displayWatcher
    @EnvironmentObject private var refresh: RefreshSignal
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateChecker.shared
    /// Whether this Mac has no internal battery (desktop). A hardware fact that
    /// can't change during a session, so it's resolved once at launch and used
    /// as the initial state. Resolving it here rather than in `.onAppear` means
    /// the desktop-gated UI (the charger-identity note, the Built-in USB ports
    /// card) is correct on the first frame instead of popping in a frame late.
    private static let isDesktopMacAtLaunch = AppleSmartBatteryReader.read().isDesktopMac
    @State private var isDesktopMac = ContentView.isDesktopMacAtLaunch
    /// Tracks per-port fault-counter deltas across a connection (DAR-51) so
    /// mid-session overcurrent trips and repeated drops surface as a free
    /// inline banner on the relevant port card.
    @StateObject private var faultTracker = ConnectionFaultTracker()

    private var showAdvanced: Bool {
        settings.showTechnicalDetails || refresh.optionHeld
    }

    @ViewBuilder
    private var rootContent: some View {
        if let route = refresh.activeProScreen,
           let screen = PluginRegistry.shared.proScreen(id: route.id, portCard: route.portCard) {
            ProScreenContainer(
                isMenuBarMode: settings.useMenuBarMode,
                isPinned: refresh.keepOpen,
                onTogglePin: { refresh.keepOpen.toggle() },
                onBack: { refresh.activeProScreen = nil },
                onDetach: {
                    DetachedProWindowManager.shared.open(route: route)
                    refresh.activeProScreen = nil
                }
            ) {
                screen
            }
        } else if refresh.showSettings {
            SettingsView(dismiss: { refresh.showSettings = false })
        } else {
            mainContent
        }
    }

    var body: some View {
        rootContent
        // Width: wide enough for the widest Pro screen's own minWidth
        // (Negotiation 560, Power Monitor 520, Cable Diagnostics 500) so
        // content never overflows and clips.
        //
        // The max cap is only applied in menu-bar mode, where the surface is
        // an NSPopover. A popover sizes itself to its content and can't be
        // user-resized, so the cap keeps a near-empty popover from being half
        // the screen (issue #159) and stops the wide Pro screens clipping.
        //
        // In Dock-app (window) mode the surface is a real resizable NSWindow,
        // so we drop the cap and let the content fill whatever size the user
        // drags the window to (issue #281). The min still applies.
        //
        // The outer popover frame is NOT keyed to the font slider on purpose.
        // Pro screens (Power Monitor, Negotiation, Display) carry their own
        // `frame(minWidth: 520 * fontScale)` etc., so opening one still grows
        // the popover to fit at any scale (a one-shot resize on entry, not a
        // per-step move). If we made the outer frame depend on fontSize too,
        // every 0.1 step of the slider would resize the popover under the
        // user's finger and the whole UI would judder during a drag.
        .frame(
            minWidth: 560,
            idealWidth: 560,
            maxWidth: settings.useMenuBarMode ? 760 : .infinity,
            minHeight: 200,
            maxHeight: settings.useMenuBarMode ? 760 : .infinity
        )
        // `\.fontScale` is now injected at the NSHostingController root by
        // `ScaledHost`, which observes `FontScaleStore` so every SwiftUI
        // surface (popover, dock window, detached Pro windows, welcome,
        // licence) tracks the slider live. No need to re-inject here.
        .onChange(of: refresh.tick) { _, _ in
            WatcherHub.shared.refreshAll()
        }
        // Fold each refresh into the fault tracker. A counter tick changes the
        // port value (the counts are part of `AppleHPMInterface`'s equality),
        // so a real overcurrent or drop republishes `ports` and lands here.
        // `isPortLive` also reads the power/PD/device watchers, which don't
        // themselves trigger this closure; a port that turns live purely from
        // one of those just has its baseline set on the next `ports` change
        // (one refresh interval later at most). Setting a baseline late is
        // conservative, never a false fault. `initial` seeds baselines from
        // whatever is already plugged in when the popover opens.
        .onChange(of: portWatcher.ports, initial: true) { _, ports in
            let liveKeys = Set(ports.compactMap { isPortLive($0) ? $0.portKey : nil })
            faultTracker.ingest(ports: ports, liveKeys: liveKeys)
        }
        // If a Pro screen is re-opened while it's already detached into
        // its own window, focus that window instead of also showing it
        // in-place, so it's never in two places at once.
        .onChange(of: refresh.activeProScreen?.id) { _, newID in
            guard newID != nil, let route = refresh.activeProScreen else { return }
            if DetachedProWindowManager.shared.focusIfOpen(route: route) {
                refresh.activeProScreen = nil
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            if let update = updates.available {
                UpdateBanner(update: update)
            }
            Divider()
            if isDesktopMac {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text(String(localized: "Desktop Mac: charger identity (FedDetails) is not available.", bundle: _appLocalizedBundle))
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            let visiblePorts = settings.hideEmptyPorts
                ? portWatcher.ports.filter { isPortLive($0) }
                : portWatcher.ports
            // Native HDMI / built-in display ports come from a parallel source.
            // They only exist when a display is plugged in (the IOKit transport
            // node has no idle representation), so the list is empty whenever
            // the user has no HDMI display connected. Issue #352.
            let builtInDisplayPorts = displayWatcher.builtInDisplayPorts
            // Devices behind a Thunderbolt dock or display match no port
            // (issue #274). Group once: nest under the single connected
            // Thunderbolt port when unambiguous, else show a flat card.
            // Grouped here, above the empty-state check, because these cards
            // (and the desktop-only built-in front-port card, #348) can be the
            // only thing to show when every port is filtered out: without this
            // a Mac mini with a drive only in a front port and "hide empty
            // ports" on would read "nothing connected".
            let tunnelledGroup = TunnelledDeviceGrouping.group(
                devices: deviceWatcher.devices,
                ports: portWatcher.ports,
                thunderboltSwitches: tbWatcher.switches,
                isDesktopMac: isDesktopMac
            )
            let hasOffPortUSBContent = !tunnelledGroup.devices.isEmpty
                || !tunnelledGroup.internalHubDevices.isEmpty
            if visiblePorts.isEmpty && builtInDisplayPorts.isEmpty && !hasOffPortUSBContent {
                if portWatcher.ports.isEmpty {
                    noPortsState
                } else {
                    nothingConnectedState
                }
            } else {
                let activePortCount = portWatcher.ports.filter { $0.connectionActive == true }.count
                let chargerSourceCount = ChargerWattageSource.chargerSourceCount(
                    ports: portWatcher.ports, sources: powerWatcher.sources)
                let adapter = SystemPower.currentAdapter()
                let batteryFull = SystemPower.batteryFullyCharged()
                let batteryCharging = SystemPower.batteryIsCharging()
                // Port keys actually drawing charging power, so a connected-
                // but-idle second charger can tell another port is the
                // active source rather than being stuck mid-negotiation (#264).
                let chargingPortKeys = Set(portWatcher.ports.compactMap { port -> String? in
                    PowerSource.hasLiveChargingContract(in: powerWatcher.sources(for: port)) ? port.portKey : nil
                })
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(visiblePorts) { port in
                            let portSources = powerWatcher.sources(for: port)
                            let wattageSource = ChargerWattageSource.resolve(
                                portSources: portSources,
                                activePortCount: activePortCount,
                                chargerSourceCount: chargerSourceCount,
                                adapter: adapter
                            )
                            PortCard(
                                port: port,
                                devices: matchingDevices(for: port),
                                tunnelledDevices: port.serviceName == tunnelledGroup.hostPortServiceName ? tunnelledGroup.devices : [],
                                powerSources: portSources,
                                identities: pdWatcher.identities(for: port),
                                thunderboltSwitches: tbWatcher.switches,
                                usb3Transports: usb3Watcher.transports(for: port),
                                isLive: isPortLive(port),
                                showAdvanced: showAdvanced,
                                cioCapability: trmWatcher.cioCapabilities.first { $0.canonicallyMatches(port: port) },
                                displayPorts: displayWatcher.statuses.filter { $0.status.canonicallyMatches(port: port) }.map(\.status),
                                chargerWattageSource: wattageSource,
                                batteryFullyCharged: batteryFull,
                                batteryIsCharging: batteryCharging,
                                adapter: adapter,
                                anotherPortActivelyCharging: port.portKey.map { key in chargingPortKeys.contains { $0 != key } } ?? false,
                                connectionDiagnostic: faultTracker.diagnostic(for: port.portKey)
                            )
                        }
                        // Tunnelled devices normally nest inside their host
                        // port's card (above). Fall back to a flat card when the
                        // host port can't show them: either it's unknown
                        // (hostPortServiceName nil) or it was filtered out of
                        // visiblePorts (e.g. "hide empty ports" dropped a host
                        // whose connectionActive lagged the TB link). Without the
                        // visibility check those devices would render nowhere.
                        let hostPortVisible = tunnelledGroup.hostPortServiceName.map { name in
                            visiblePorts.contains { $0.serviceName == name }
                        } ?? false
                        if !hostPortVisible, !tunnelledGroup.devices.isEmpty {
                            OtherUSBDevicesCard(devices: tunnelledGroup.devices, kind: .thunderboltTunnelled)
                        }
                        // internalHubDevices is already desktop-gated by group(),
                        // so it is empty on a laptop and this card renders only
                        // on Mac mini / Studio / Pro (issue #348).
                        if !tunnelledGroup.internalHubDevices.isEmpty {
                            OtherUSBDevicesCard(devices: tunnelledGroup.internalHubDevices, kind: .builtInUSBPort)
                        }
                        // Native HDMI ports render after the USB-C / MagSafe
                        // group. They have no PD, no transports, no e-marker,
                        // so the card is a slim variant: just the port label
                        // and the display verdict(s). Issue #352.
                        ForEach(builtInDisplayPorts) { hdmiPort in
                            BuiltInDisplayPortCard(port: hdmiPort)
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "cable.connector.horizontal")
                .scaledFont(.title2)
            Text(AppInfo.name).scaledFont(.headline, weight: .bold)
            Spacer()
            ForEach(Array(PluginRegistry.shared.headerButtonBuilders.enumerated()), id: \.offset) { _, builder in
                builder()
            }
            if settings.useMenuBarMode {
                Button {
                    refresh.keepOpen.toggle()
                } label: {
                    Image(systemName: refresh.keepOpen ? "pin.fill" : "pin")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(refresh.keepOpen
                    ? String(localized: "Unpin (popover closes when you click away)", bundle: _appLocalizedBundle)
                    : String(localized: "Keep window open", bundle: _appLocalizedBundle))
            }
            Button {
                refresh.bump()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Refresh", bundle: _appLocalizedBundle))
            Button {
                refresh.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Settings", bundle: _appLocalizedBundle))
        }
        .padding(12)
        .background(
            Button("") {
                refresh.showSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private var footer: some View {
        HStack {
            Toggle(String(localized: "Show technical details", bundle: _appLocalizedBundle), isOn: $settings.showTechnicalDetails)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .scaledFont(.caption)
            Spacer()
            Text(String(localized: "\(deviceWatcher.devices.count) USB devices", bundle: _appLocalizedBundle))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "·").scaledFont(.caption).foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.open(AppInfo.releaseURL)
            } label: {
                Text(verbatim: "v\(AppInfo.version)")
                    .scaledFont(.caption)
                    .underline()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            Text(verbatim: "· \(AppInfo.credit)")
                .scaledFont(.caption)
                .foregroundStyle(.tertiary)
            Text(verbatim: "·").scaledFont(.caption).foregroundStyle(.secondary)
            ForEach(Array(PluginRegistry.shared.footerButtonBuilders.enumerated()), id: \.offset) { _, builder in
                builder()
            }
            Button(String(localized: "Quit", bundle: _appLocalizedBundle)) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var noPortsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "powerplug")
                .scaledFont(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "No USB-C ports detected", bundle: _appLocalizedBundle))
                .scaledFont(.headline, weight: .bold)
            Text(String(localized: "This Mac doesn't seem to expose its port-controller services. Hit refresh, or check System Information > USB.", bundle: _appLocalizedBundle))
                .scaledFont(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private var nothingConnectedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cable.connector.slash")
                .scaledFont(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "Nothing connected", bundle: _appLocalizedBundle))
                .scaledFont(.headline, weight: .bold)
            Text(String(localized: "\(portWatcher.ports.count) USB-C ports detected, but nothing is currently plugged in. Turn off \"Hide empty ports\" in Settings to see them.", bundle: _appLocalizedBundle))
                .scaledFont(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Live-signal check delegating to the pure helper in `WhatCableCore`,
    /// so the same rules apply to both the GUI and any test harness.
    private func isPortLive(_ port: AppleHPMInterface) -> Bool {
        WhatCableCore.isPortLive(
            port: port,
            powerSources: powerWatcher.sources(for: port),
            identities: pdWatcher.identities(for: port),
            matchingDevices: matchingDevices(for: port),
            chargerAttached: chargerAttached
        )
    }

    /// True when the Mac reports an external power adapter attached right now.
    /// Corroborates a MagSafe `connectionActive` in `isPortLive`: M1/M2 MagSafe
    /// ports expose no per-port power source, so without this a connected
    /// MagSafe charger reads as "nothing connected". Read from the system
    /// adapter, which clears on unplug, so a lingering `connectionActive` can't
    /// keep the port live.
    private var chargerAttached: Bool {
        (SystemPower.currentAdapter()?.watts ?? 0) > 0
    }

    /// Match USB devices to their physical port. The IOKit relationship
    /// isn't direct: USB devices live under the XHCI controller subtree,
    /// physical ports under the SPMI/HPM subtree. Two strategies, in order:
    ///
    ///   1. `controllerPortName`: each XHCI controller exposes a `UsbIOPort`
    ///      property whose path ends in the physical port's service name
    ///      (e.g. ".../Port-USB-C@1"). When present, this gives a direct
    ///      link with no ambiguity.
    ///   2. `busIndex`: derived from the `hpm<N>` ancestor on the port side
    ///      and the XHCI controller's `locationID` upper byte on the device
    ///      side. Fragile, breaks when devices sit deeper behind a hub
    ///      than the parent walk reaches, or when hpm numbering diverges
    ///      from controller numbering.
    ///
    /// If neither is available we return [] rather than dumping every
    /// device onto the port. Showing all devices on every active USB port
    /// is worse than showing none, and it caused the bug that issue #21
    /// reported.
    private func matchingDevices(for port: AppleHPMInterface) -> [USBDevice] {
        port.matchingDevices(from: deviceWatcher.devices)
    }
}

struct UpdateBanner: View {
    let update: AvailableUpdate
    @ObservedObject private var installer = Installer.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "WhatCable \(update.version) is available", bundle: _appLocalizedBundle))
                    .scaledFont(.callout, weight: .bold)
                statusLine
                    .scaledFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.12))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch installer.state {
        case .idle:
            Text(String(localized: "You're on \(AppInfo.version)", bundle: _appLocalizedBundle))
        case .resolving:
            Text(String(localized: "Checking for the latest version…", bundle: _appLocalizedBundle))
        case .downloading, .verifying, .installing:
            // When the re-check bumped to a newer release, keep saying so for
            // the whole install (download/verify/install), not just the brief
            // download phase, so a fast install doesn't hide the note.
            if installer.didFindNewerVersion {
                Text(String(localized: "Newer version found, installing it…", bundle: _appLocalizedBundle))
            } else if case .verifying = installer.state {
                Text(String(localized: "Verifying signature…", bundle: _appLocalizedBundle))
            } else if case .installing = installer.state {
                Text(String(localized: "Installing, WhatCable will relaunch", bundle: _appLocalizedBundle))
            } else {
                Text(String(localized: "Downloading…", bundle: _appLocalizedBundle))
            }
        case .failed(let message):
            Text(String(localized: "Install failed: \(message)", bundle: _appLocalizedBundle)).foregroundStyle(.red)
        case .blocked(let message):
            Text(message).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch installer.state {
        case .idle, .failed:
            HStack(spacing: 6) {
                Button(String(localized: "View release", bundle: _appLocalizedBundle)) {
                    NSWorkspace.shared.open(update.url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if update.downloadURL != nil {
                    Button(String(localized: "Install update", bundle: _appLocalizedBundle)) {
                        Installer.shared.install(update)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        case .blocked:
            // Self-update can't run here; only offer the manual download path.
            Button(String(localized: "View release", bundle: _appLocalizedBundle)) {
                NSWorkspace.shared.open(update.url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .resolving, .downloading, .verifying, .installing:
            ProgressView().controlSize(.small)
        }
    }
}

// MARK: - Port card

/// A flat top-level card listing USB devices reached over a Thunderbolt tunnel,
/// shown when two or more Thunderbolt devices are connected so we can't safely
/// say which one they sit behind (issue #274). The single-device case nests
/// under that port's card instead, so this card is the ambiguous fallback.
struct OtherUSBDevicesCard: View {
    enum Kind {
        /// Devices behind a TB dock or display (issue #274).
        case thunderboltTunnelled
        /// Devices on built-in plain-USB ports behind the Mac's internal hub
        /// (front USB-C / USB-A on Mac mini, Studio, Pro; issue #348).
        case builtInUSBPort
    }

    let devices: [USBDevice]
    let kind: Kind

    private var title: String {
        switch kind {
        case .thunderboltTunnelled:
            return String(localized: "Other USB devices", bundle: _appLocalizedBundle)
        case .builtInUSBPort:
            return String(localized: "Built-in USB ports", bundle: _appLocalizedBundle)
        }
    }

    private var footer: String {
        switch kind {
        case .thunderboltTunnelled:
            return String(localized: "Reached through a Thunderbolt dock or display, so there's no cable, power, or Thunderbolt data for them.", bundle: _appLocalizedBundle)
        case .builtInUSBPort:
            return String(localized: "Plain USB ports behind the Mac's internal hub, so there's no cable, power, or Thunderbolt data for them.", bundle: _appLocalizedBundle)
        }
    }

    var body: some View {
        let tree = USBDeviceNode.flatten(USBDeviceNode.buildTree(from: devices))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundStyle(.secondary)
                Text(title)
                    .scaledFont(.headline, weight: .semibold)
            }
            ForEach(tree) { node in
                let name = node.device.productName ?? String(localized: "Unknown", bundle: _appLocalizedBundle)
                let prefix = node.depth > 0 ? "\u{21B3} " : "\u{2022} "
                Text(verbatim: "\(prefix)\(name) - \(node.device.speedLabel)")
                    .scaledFont(.callout)
                    .padding(.leading, CGFloat(node.depth) * 16)
            }
            Text(footer)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PortCard: View {
    let port: AppleHPMInterface
    let devices: [USBDevice]
    /// USB devices reached over a Thunderbolt tunnel that belong behind this
    /// port's dock or display (issue #274). Non-empty only on the one port a
    /// single connected Thunderbolt device is on; rendered as its own
    /// "Connected over Thunderbolt" subsection. Empty otherwise.
    var tunnelledDevices: [USBDevice] = []
    let powerSources: [PowerSource]
    let identities: [USBPDSOP]
    let thunderboltSwitches: [IOThunderboltSwitch]
    let usb3Transports: [USB3Transport]
    /// Authoritative connection state derived from the live IOKit watchers,
    /// passed in from the parent so we don't have to consult them from here
    /// and so PortSummary doesn't fall back to the unreliable
    /// `port.connectionActive` property.
    let isLive: Bool
    let showAdvanced: Bool
    let cioCapability: CIOCableCapability?
    /// DisplayPort transports for this port (link rate, lanes, monitor EDID),
    /// matched by `portKey`. One entry per connected monitor: a dock can drive
    /// several through a single port (issue #271). Empty when none.
    let displayPorts: [IOPortTransportStateDisplayPort]
    let chargerWattageSource: ChargerWattageSource
    let batteryFullyCharged: Bool?
    /// AppleSmartBattery's IsCharging flag. `nil` on desktops. `false` when
    /// macOS has paused charging (charge limit or Optimized Battery Charging).
    let batteryIsCharging: Bool?
    /// System-wide adapter info from `SystemPower.currentAdapter()`.
    /// Threaded through so the "Charger: <Manufacturer> <Name>" bullet
    /// can fire on the active charging port.
    let adapter: AdapterInfo?
    /// True when a different port holds the live charging contract, so a
    /// connected-but-idle charger here reads as on standby rather than
    /// stuck mid-negotiation. See issue #264.
    var anotherPortActivelyCharging: Bool = false
    /// Mid-session fault banner for this port (DAR-51): overcurrent trip or
    /// repeated drops observed while the cable stayed plugged in. `nil` when
    /// the session is clean. Owned by `ConnectionFaultTracker` upstream.
    var connectionDiagnostic: ConnectionDiagnostic? = nil

    @State private var reportingCable: USBPDSOP?

    var summary: PortSummary {
        PortSummary(
            port: port,
            sources: powerSources,
            identities: identities,
            devices: devices,
            thunderboltSwitches: thunderboltSwitches,
            usb3Transports: usb3Transports,
            cioCapability: cioCapability,
            isConnectedOverride: isLive,
            chargerWattageSource: chargerWattageSource,
            batteryFullyCharged: batteryFullyCharged,
            batteryIsCharging: batteryIsCharging,
            adapter: adapter
        )
    }

    /// The host root switch for this port, if it maps to one.
    var thunderboltRoot: IOThunderboltSwitch? {
        guard let socketID = ThunderboltTopology.socketID(for: port) else { return nil }
        return ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches)
    }

    /// The full downstream Thunderbolt fabric tree for this port, following
    /// every branch (a dock with two TB devices yields two subtrees, issue
    /// #280). Empty if the port doesn't map to any TB switch.
    var thunderboltTree: [IOThunderboltSwitchNode] {
        guard let root = thunderboltRoot else { return [] }
        return ThunderboltTopology.tree(from: root, in: thunderboltSwitches)
    }

    /// A titled USB device tree (the "Connected devices" list, reused for the
    /// "Connected over Thunderbolt" subsection). `note` adds a caption line.
    @ViewBuilder
    private func deviceTree(_ devices: [USBDevice], title: String, note: String? = nil) -> some View {
        let tree = USBDeviceNode.flatten(USBDeviceNode.buildTree(from: devices))
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(.subheadline, weight: .semibold)
                .foregroundStyle(.secondary)
            ForEach(tree) { node in
                let name = node.device.productName ?? String(localized: "Unknown", bundle: _appLocalizedBundle)
                let prefix = node.depth > 0 ? "\u{21B3} " : "\u{2022} "
                Text(verbatim: "\(prefix)\(name) - \(node.device.speedLabel)")
                    .scaledFont(.callout)
                    .padding(.leading, CGFloat(node.depth) * 16)
            }
            if let note {
                Text(note)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 48)
        .padding(.top, 4)
    }

    /// The "Connected devices" list built from pre-labelled rows
    /// (`ConnectedDeviceTree`), so the app and the CLI render the identical
    /// tree: the Thunderbolt device as root with its live link speed, then
    /// monitors and USB devices indented under it.
    @ViewBuilder
    private func rowTree(_ rows: [ConnectedDeviceTree.Row], title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(.subheadline, weight: .semibold)
                .foregroundStyle(.secondary)
            // Offset-keyed: rows are value snapshots rebuilt on every state
            // change, and two identical monitors would collide on a
            // label-derived id.
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let prefix = row.depth > 0 ? "\u{21B3} " : "\u{2022} "
                Text(verbatim: "\(prefix)\(row.label)")
                    .scaledFont(.callout)
                    .padding(.leading, CGFloat(row.depth) * 16)
            }
        }
        .padding(.leading, 48)
        .padding(.top, 4)
    }

    private var cableEmarker: USBPDSOP? {
        identities.first { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }
    }

    private var cablePartner: USBPDSOP? {
        identities.first { $0.endpoint == .sop }
    }

    var body: some View {
        let summary = self.summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.icon)
                    .scaledFont(.title2)
                    .foregroundStyle(summary.iconColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(port.portDescription ?? port.serviceName)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.headline)
                        .scaledFont(.title3, weight: .bold)
                    if !summary.subtitle.isEmpty {
                        Text(summary.subtitle)
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                let ctx = PortCardContext(
                    portKey: port.portKey,
                    portNumber: port.portNumber,
                    serviceName: port.serviceName,
                    portTypeDescription: port.portTypeDescription,
                    pinConfiguration: port.pinConfiguration,
                    plugOrientation: port.plugOrientation
                )
                ForEach(Array(PluginRegistry.shared.portCardTrailingBuilders.enumerated()), id: \.offset) { _, builder in
                    if let view = builder(ctx) {
                        view
                    }
                }
            }

            // A mid-session fault (overcurrent trip, repeated drops) is the
            // most urgent thing on the card, so it leads the callout group.
            if let connectionDiagnostic {
                ConnectionBanner(diagnostic: connectionDiagnostic)
                    .padding(.leading, 48)
            }

            if let diag = ChargingDiagnostic(port: port, sources: powerSources, identities: identities, adapter: adapter, wattageSource: chargerWattageSource, batteryFullyCharged: batteryFullyCharged, batteryIsCharging: batteryIsCharging, anotherPortActivelyCharging: anotherPortActivelyCharging) {
                DiagnosticBanner(diagnostic: diag)
                    .padding(.leading, 48)
            }

            if let dataDiag = DataLinkDiagnostic(
                port: port,
                identities: identities,
                devices: devices,
                usb3Transports: usb3Transports,
                cio: cioCapability,
                thunderboltSwitches: thunderboltSwitches
            ) {
                DataLinkBanner(diagnostic: dataDiag)
                    .padding(.leading, 48)
            }

            // One banner per connected monitor (a dock can drive several
            // through one port, issue #271). Keyed by offset because the
            // DisplayPort node carries no unique id and two identical monitors
            // would otherwise collide.
            ForEach(Array(displayPorts.enumerated()), id: \.offset) { _, displayPort in
                if let displayDiag = DisplayDiagnostic(dp: displayPort, cable: cableEmarker) {
                    DisplayBanner(diagnostic: displayDiag)
                        .padding(.leading, 48)
                }
            }

            // Trust signals sit with the other top-of-card callouts (charging,
            // link speed, display) rather than below the bullets, so the cable
            // verdict is read alongside the link-speed verdict.
            if let cable = cableEmarker {
                let trust = CableTrustReport(identity: cable, partner: cablePartner)
                if !trust.isEmpty {
                    TrustFlagsCard(flags: trust.flags)
                        .padding(.leading, 48)
                }
            }

            // Name only, no diagnosis: a Billboard device is often benign, so
            // the inline card just names it. Any inference about a failed Alt
            // Mode lives only in the Pro Display Diagnostics screen, gated on a
            // degraded link.
            if let billboard = port.billboardDevice(among: devices) {
                HStack(alignment: .top, spacing: 6) {
                    Text(verbatim: "•").foregroundStyle(.secondary)
                    Text(billboard.billboardPresenceLabel(bundle: _appLocalizedBundle))
                        .scaledFont(.callout)
                    Spacer()
                }
                .padding(.leading, 48)
            }

            if !summary.bullets.isEmpty {
                // "Cable details" subheading + the extra top gap mark the break
                // between the callout verdicts above and the plain spec facts
                // below, mirroring the "Connected devices" subheading.
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Cable details", bundle: _appLocalizedBundle))
                        .scaledFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.secondary)
                    ForEach(summary.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text(verbatim: "•").foregroundStyle(.secondary)
                            Text(bullet).scaledFont(.callout)
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 48)
                .padding(.top, 4)
            }

            let connectedRows = ConnectedDeviceTree.rows(
                devices: devices,
                port: port,
                thunderboltSwitches: thunderboltSwitches,
                displayPorts: displayPorts
            )
            if !connectedRows.isEmpty {
                rowTree(connectedRows, title: String(localized: "Connected devices", bundle: _appLocalizedBundle))
            }

            if !tunnelledDevices.isEmpty {
                deviceTree(
                    tunnelledDevices,
                    title: String(localized: "Connected over Thunderbolt", bundle: _appLocalizedBundle),
                    note: String(localized: "Reached through a Thunderbolt dock or display, so there's no cable, power, or Thunderbolt data for them.", bundle: _appLocalizedBundle)
                )
            }

            if !powerSources.isEmpty && isLive {
                PowerSourceList(sources: powerSources)
                    .padding(.leading, 48)
                    .padding(.top, 4)
            }

            // Trust card is rendered up with the callouts above; only the
            // report action stays at the bottom of the card.
            if let cable = cableEmarker {
                HStack {
                    Spacer()
                    Button {
                        reportingCable = cable
                    } label: {
                        Label(String(localized: "Report this cable", bundle: _appLocalizedBundle), systemImage: "exclamationmark.bubble")
                            .scaledFont(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "File a GitHub issue with this cable's e-marker fingerprint", bundle: _appLocalizedBundle))
                }
                .padding(.leading, 48)
            }

            if showAdvanced {
                Divider()
                AdvancedPortDetails(
                    port: port,
                    cableEmarker: cableEmarker,
                    thunderboltRoot: thunderboltRoot,
                    thunderboltTree: thunderboltTree,
                    thunderboltSwitches: thunderboltSwitches
                )
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .sheet(item: $reportingCable) { cable in
            // Wrapped so the sheet's own window picks up the opacity slider too
            // (sheets are separate child windows, not covered by the parent's
            // ScaledHost).
            ScaledHost {
                CableReportSheet(cableIdentity: cable, cioCapability: cioCapability) {
                    reportingCable = nil
                }
            }
        }
    }

}

/// Visual weight of a top-of-card callout, by severity. Warnings get a filled
/// box so they stand out; positive, info, and neutral notes are lighter (no
/// fill) so the eye lands on problems first within the callout group.
enum CalloutRole {
    case warning    // a problem worth the user's attention
    case caution    // a softer heads-up: worth a look, not "act now"
    case positive   // reassurance: everything is fine
    case info       // an informational note, no problem
    case neutral    // could not determine, no verdict

    var accent: Color {
        switch self {
        case .warning: return .orange
        // Amber, distinct from the orange warning tier so the eye can tell a
        // "worth a look" note (repeated drops) from an "act now" one
        // (overcurrent, cable bottleneck).
        case .caution: return Color(red: 0.85, green: 0.6, blue: 0.0)
        case .positive: return .green
        case .info: return .blue
        case .neutral: return .secondary
        }
    }

    var isWarning: Bool { self == .warning }
}

extension View {
    /// Shared chrome for every callout (diagnostic banners + trust card) so
    /// the group reads as one family: a tinted, rounded fill keyed to the
    /// callout's accent colour.
    func calloutChrome(role: CalloutRole) -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(role.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// One consistent callout for a single verdict (charging, link speed, display).
/// All four top-of-card callouts share this chrome and anatomy: a coloured
/// icon, a bold summary, and a secondary detail line.
struct CalloutBanner: View {
    let role: CalloutRole
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(role.accent)
                .scaledFont(.callout)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).scaledFont(.callout, weight: .bold)
                Text(detail)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .calloutChrome(role: role)
    }
}

struct DiagnosticBanner: View {
    let diagnostic: ChargingDiagnostic

    // Only a cable limit is a warning. A fine/standby charger reads positive;
    // the benign/transient states (Mac drawing less, negotiation pending,
    // adapter-fallback wattage) read as calm neutral notes, not alarms.
    private var role: CalloutRole {
        switch diagnostic.bottleneck {
        case .cableLimit: return .warning
        case .fine, .standbyCharger: return .positive
        case .macLimit, .chargerLimit, .noCharger: return .neutral
        }
    }

    var body: some View {
        CalloutBanner(
            role: role,
            icon: diagnostic.icon,
            title: diagnostic.summary,
            detail: diagnostic.detail
        )
    }
}

struct DataLinkBanner: View {
    let diagnostic: DataLinkDiagnostic

    var body: some View {
        CalloutBanner(
            role: diagnostic.isWarning ? .warning : .positive,
            icon: diagnostic.icon,
            title: diagnostic.summary,
            detail: diagnostic.detail
        )
    }
}

/// Mid-session fault banner (DAR-51). Overcurrent reads as an orange warning
/// (a hardware protection trip, "act now"); repeated drops read as an amber
/// caution ("worth a look").
struct ConnectionBanner: View {
    let diagnostic: ConnectionDiagnostic

    private var role: CalloutRole {
        switch diagnostic.severity {
        case .warning: return .warning
        case .caution: return .caution
        }
    }

    private var icon: String {
        switch diagnostic.fault {
        case .overcurrent: return "exclamationmark.triangle.fill"
        case .repeatedDrops: return "bolt.horizontal.circle.fill"
        }
    }

    var body: some View {
        CalloutBanner(
            role: role,
            icon: icon,
            title: diagnostic.summary,
            detail: diagnostic.detail
        )
    }
}

struct DisplayBanner: View {
    let diagnostic: DisplayDiagnostic

    private var role: CalloutRole {
        switch diagnostic.bottleneck {
        case .fine, .compressionActive: return .positive
        case .belowMonitorMax, .adapterLimit: return .warning
        case .unknownMode, .compressionPlausible: return .neutral
        }
    }

    private var icon: String {
        switch diagnostic.bottleneck {
        case .fine: return "checkmark.seal.fill"
        case .belowMonitorMax: return "exclamationmark.triangle.fill"
        case .adapterLimit: return "arrow.triangle.swap"
        case .unknownMode: return "questionmark.circle"
        case .compressionPlausible, .compressionActive: return "info.circle"
        }
    }

    var body: some View {
        CalloutBanner(role: role, icon: icon, title: diagnostic.summary, detail: diagnostic.detail)
    }
}

/// Thin chrome around an in-place Pro screen: a Back button to return to
/// the main content, and (menu-bar mode only) the pin toggle so the
/// popover can be kept open while plugging cables in and out. The screen
/// keeps its own header/title below this bar.
struct ProScreenContainer<Content: View>: View {
    let isMenuBarMode: Bool
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onBack: () -> Void
    let onDetach: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label(
                        String(localized: "Back", bundle: _appLocalizedBundle),
                        systemImage: "chevron.left"
                    )
                    .scaledFont(.callout)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                if isMenuBarMode {
                    Button(action: onDetach) {
                        Image(systemName: "macwindow")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Open in a separate window", bundle: _appLocalizedBundle))
                    Button(action: onTogglePin) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(isPinned
                        ? String(localized: "Unpin (popover closes when you click away)", bundle: _appLocalizedBundle)
                        : String(localized: "Keep window open", bundle: _appLocalizedBundle))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            content
        }
    }
}

struct PowerSourceList: View {
    let sources: [PowerSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources) { src in
                if !src.options.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        let srcName = src.name
                        Text(String(localized: "\(srcName) profiles", bundle: _appLocalizedBundle))
                            .scaledFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.secondary)
                        ForEach(src.options.sorted(by: { $0.voltageMV < $1.voltageMV }), id: \.self) { opt in
                            let isWinning = opt == src.winning
                            HStack(spacing: 6) {
                                Image(systemName: isWinning ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isWinning ? Color.green : Color.secondary)
                                    .scaledFont(.caption)
                                Text(verbatim: "\(opt.voltsLabel) @ \(opt.ampsLabel) - \(opt.wattsLabel)")
                                    .scaledFont(.callout, monospacedDigit: true)
                                if isWinning {
                                    Text(String(localized: "active", bundle: _appLocalizedBundle)).scaledFont(.caption2).foregroundStyle(.green)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct AdvancedPortDetails: View {
    let port: AppleHPMInterface
    let cableEmarker: USBPDSOP?
    let thunderboltRoot: IOThunderboltSwitch?
    let thunderboltTree: [IOThunderboltSwitchNode]
    /// Full live switch list, needed (beyond `thunderboltRoot`/`thunderboltTree`)
    /// to resolve `ActiveTunnelPresentation`'s tunnel terminal switches, which
    /// can sit anywhere in the fabric, not just on the direct root-to-leaf path.
    let thunderboltSwitches: [IOThunderboltSwitch]
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            group(String(localized: "Connection", bundle: _appLocalizedBundle)) {
                row(String(localized: "Active", bundle: _appLocalizedBundle), bool(port.connectionActive))
                row(String(localized: "Active cable electronics", bundle: _appLocalizedBundle), bool(port.activeCable))
                row(String(localized: "Optical", bundle: _appLocalizedBundle), bool(port.opticalCable))
                row(String(localized: "USB active", bundle: _appLocalizedBundle), bool(port.usbActive))
                row(String(localized: "SuperSpeed", bundle: _appLocalizedBundle), bool(port.superSpeedActive))
                row(String(localized: "Plug events", bundle: _appLocalizedBundle), port.plugEventCount.map(String.init) ?? "—")
            }
            group(String(localized: "Transports", bundle: _appLocalizedBundle)) {
                row(String(localized: "Supported", bundle: _appLocalizedBundle), port.transportsSupported.joined(separator: ", "))
                row(String(localized: "Provisioned", bundle: _appLocalizedBundle), port.transportsProvisioned.joined(separator: ", "))
                row(String(localized: "Active", bundle: _appLocalizedBundle), port.transportsActive.isEmpty ? "—" : port.transportsActive.joined(separator: ", "))
            }
            if let v2 = cableEmarker?.activeCableVDO2 {
                ActiveCableVDO2Section(vdo2: v2)
            }
            if let root = thunderboltRoot, !thunderboltTree.isEmpty {
                ThunderboltFabricSection(root: root, nodes: thunderboltTree)
            }
            if let root = thunderboltRoot {
                // Bundle is Core's, not the app's: ActiveTunnelPresentation's
                // strings ("Video" / "USB data" / "adapter %lld" / the
                // "Active tunnels:" header reused below) live in
                // WhatCableCore's Localizable.strings, the same catalog the
                // CLI reads, so both surfaces render identical text without
                // a second app-bundle copy of the same keys.
                let tunnels = ThunderboltTopology.tunnels(from: root, in: thunderboltSwitches)
                let tunnelLines = ActiveTunnelPresentation.lines(tunnels: tunnels, switches: thunderboltSwitches, bundle: _coreLocalizedBundle)
                if !tunnelLines.isEmpty {
                    group(String(localized: "Active tunnels:", bundle: _coreLocalizedBundle)) {
                        ForEach(Array(tunnelLines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).scaledFont(.caption, design: .monospaced)
                        }
                    }
                }
            }
            let rawCount = port.redactedRawProperties.count
            DisclosureGroup(String(localized: "All raw IOKit properties (\(rawCount))", bundle: _appLocalizedBundle)) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(port.redactedRawProperties.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        HStack(alignment: .top) {
                            Text(kv.key).scaledFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .frame(width: 200 * fontScale, alignment: .leading)
                            Text(kv.value).scaledFont(.caption, design: .monospaced)
                                .textSelection(.enabled)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)
            }
            .scaledFont(.caption)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).scaledFont(.caption, weight: .bold).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).scaledFont(.caption).foregroundStyle(.secondary).frame(width: 160 * fontScale, alignment: .leading)
            Text(value).scaledFont(.caption, design: .monospaced)
            Spacer()
        }
    }

    private func bool(_ v: Bool?) -> String {
        guard let v else { return "—" }
        return v ? String(localized: "Yes", bundle: _appLocalizedBundle) : String(localized: "No", bundle: _appLocalizedBundle)
    }
}

/// Renders every field in Active Cable VDO 2. Hidden behind the
/// existing "show technical details" toggle. The bullet list above the
/// fold already surfaces the user-facing essentials (medium, active
/// element, optical isolation), so this section is the deep view for
/// people who want to see USB protocol support, lane count, idle power,
/// thermal limits, etc.
struct ActiveCableVDO2Section: View {
    let vdo2: PDVDO.ActiveCableVDO2
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Active cable (VDO 2)", bundle: _appLocalizedBundle))
                .scaledFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
            row(String(localized: "Physical connection", bundle: _appLocalizedBundle), vdo2.physicalConnection.label)
            row(String(localized: "Active element", bundle: _appLocalizedBundle), vdo2.activeElement.label)
            row(String(localized: "Optically isolated", bundle: _appLocalizedBundle), bool(vdo2.opticallyIsolated))
            row(String(localized: "USB lanes", bundle: _appLocalizedBundle), vdo2.twoLanesSupported ? String(localized: "Two", bundle: _appLocalizedBundle) : String(localized: "One", bundle: _appLocalizedBundle))
            row(String(localized: "USB Gen", bundle: _appLocalizedBundle), vdo2.usbGen2OrHigher ? String(localized: "Gen 2 or higher", bundle: _appLocalizedBundle) : String(localized: "Gen 1", bundle: _appLocalizedBundle))
            row(String(localized: "USB4 supported", bundle: _appLocalizedBundle), bool(vdo2.usb4Supported))
            row(String(localized: "USB 3.2 supported", bundle: _appLocalizedBundle), bool(vdo2.usb32Supported))
            row(String(localized: "USB 2.0 supported", bundle: _appLocalizedBundle), bool(vdo2.usb2Supported))
            row(String(localized: "USB 2.0 hub hops", bundle: _appLocalizedBundle), String(vdo2.usb2HubHopsConsumed))
            row(String(localized: "USB4 asymmetric", bundle: _appLocalizedBundle), bool(vdo2.usb4AsymmetricMode))
            row(String(localized: "U3 to U0 transition", bundle: _appLocalizedBundle), vdo2.u3ToU0TransitionThroughU3S ? String(localized: "Through U3S", bundle: _appLocalizedBundle) : String(localized: "Direct", bundle: _appLocalizedBundle))
            row(String(localized: "Idle power (U3/CLd)", bundle: _appLocalizedBundle), vdo2.u3CLdPower.label)
            row(String(localized: "Max operating temp", bundle: _appLocalizedBundle), temp(vdo2.maxOperatingTempC))
            row(String(localized: "Shutdown temp", bundle: _appLocalizedBundle), temp(vdo2.shutdownTempC))
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).scaledFont(.caption).foregroundStyle(.secondary).frame(width: 160 * fontScale, alignment: .leading)
            Text(value).scaledFont(.caption, design: .monospaced)
            Spacer()
        }
    }

    private func bool(_ v: Bool) -> String {
        v ? String(localized: "Yes", bundle: _appLocalizedBundle) : String(localized: "No", bundle: _appLocalizedBundle)
    }

    /// 0 in this field means "not specified" per the spec text. Show
    /// the dash placeholder rather than the misleading literal "0°C".
    private func temp(_ v: Int) -> String {
        v == 0 ? "—" : "\(v)°C"
    }
}

/// Expandable tree view of the Thunderbolt fabric for one port. Shows the
/// host root and every downstream switch, following all branches (a dock with
/// two TB devices shows both, issue #280). Each row shows the device name and
/// the link by which it connects. Hidden behind the existing "show technical
/// details" toggle, and collapsible within it.
struct ThunderboltFabricSection: View {
    let root: IOThunderboltSwitch
    let nodes: [IOThunderboltSwitchNode]
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                row(
                    depth: 0,
                    arrow: "",
                    name: String(localized: "Host (\(root.className))", bundle: _appLocalizedBundle),
                    port: ThunderboltTopology.activeDownstreamLanePort(root)
                )
                ForEach(ThunderboltTopology.flatten(nodes), id: \.id) { node in
                    row(
                        depth: node.depth + 1,
                        arrow: "↳ ",
                        name: ThunderboltLabels.deviceName(for: node.sw),
                        port: ThunderboltTopology.connectionLanePort(node.sw)
                    )
                }
            }
            .padding(.top, 2)
        } label: {
            Text(String(localized: "Thunderbolt fabric", bundle: _appLocalizedBundle))
                .scaledFont(.caption, weight: .bold).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(depth: Int, arrow: String, name: String, port: IOThunderboltPort?) -> some View {
        let indent = String(repeating: "  ", count: depth)
        let linkLabel = port.flatMap { ThunderboltLabels.linkLabel(for: $0) } ?? String(localized: "no active link", bundle: _appLocalizedBundle)
        HStack(alignment: .top) {
            Text(verbatim: "\(indent)\(arrow)\(name)")
                .scaledFont(.caption, design: .monospaced)
            Spacer()
            Text(linkLabel)
                .scaledFont(.caption, design: .monospaced)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrustFlagsCard: View {
    let flags: [TrustFlag]

    /// A card with any real warning reads as a warning (orange triangle).
    /// A card with only neutral notes reads calm (blue info), so a softened
    /// false-positive doesn't look like an alarm.
    private var hasWarning: Bool {
        flags.contains { $0.severity == .warning }
    }

    // Shares the callout family's chrome (see CalloutRole / calloutChrome):
    // a real warning fills the box; a softened note reads as a calm, unfilled
    // info note, so a false-positive does not look like an alarm.
    private var role: CalloutRole { hasWarning ? .warning : .info }

    private var headerIcon: String {
        hasWarning ? "exclamationmark.triangle.fill" : "info.circle.fill"
    }

    private var headerText: String {
        hasWarning
            ? String(localized: "Cable trust signals", bundle: _appLocalizedBundle)
            : String(localized: "Cable note", bundle: _appLocalizedBundle)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: headerIcon)
                .foregroundStyle(role.accent)
                .scaledFont(.callout)
            VStack(alignment: .leading, spacing: 4) {
                Text(headerText)
                    .scaledFont(.caption, weight: .bold)
                    .foregroundStyle(.secondary)
                ForEach(flags, id: \.code) { flag in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flag.title).scaledFont(.callout, weight: .bold)
                        Text(flag.detail)
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .calloutChrome(role: role)
    }
}
