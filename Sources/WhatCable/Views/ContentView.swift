import SwiftUI
import WhatCableCore
import WhatCableDarwinBackend
import WhatCableAppKit

// MARK: - Font scaling environment

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var fontScale: Double {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

/// View modifier that reads the fontScale environment and applies a scaled
/// version of the given text style. Use `.scaledFont(.caption)` instead of
/// `.font(.caption)` on any text that should respond to the slider.
struct ScaledFontModifier: ViewModifier {
    @Environment(\.fontScale) private var scale
    let style: Font.TextStyle
    let design: Font.Design?
    let weight: Font.Weight?
    let monospacedDigit: Bool

    init(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil, monospacedDigit: Bool = false) {
        self.style = style
        self.design = design
        self.weight = weight
        self.monospacedDigit = monospacedDigit
    }

    func body(content: Content) -> some View {
        let baseSize = Self.baseSize(for: style)
        let size = baseSize * scale
        var font: Font = design != nil
            ? .system(size: size, design: design!)
            : .system(size: size)
        if let weight { font = font.weight(weight) }
        if monospacedDigit { font = font.monospacedDigit() }
        return content.font(font)
    }

    static func baseSize(for style: Font.TextStyle) -> Double {
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline: return 13
        case .body: return 13
        case .callout: return 12
        case .subheadline: return 11
        case .footnote: return 10
        case .caption: return 10
        case .caption2: return 9
        @unknown default: return 13
        }
    }
}

extension View {
    func scaledFont(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil, monospacedDigit: Bool = false) -> some View {
        modifier(ScaledFontModifier(style, design: design, weight: weight, monospacedDigit: monospacedDigit))
    }
}

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
    @State private var isDesktopMac = false

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
        // content never overflows and clips. Height stays content-fit so a
        // near-empty popover isn't half the screen (issue #159).
        .frame(minWidth: 560, idealWidth: 560, maxWidth: 760, minHeight: 200, maxHeight: 760)
        .environment(\.fontScale, settings.fontSize)
        .onAppear {
            isDesktopMac = AppleSmartBatteryReader.read().isDesktopMac
        }
        .onChange(of: refresh.tick) { _, _ in
            WatcherHub.shared.refreshAll()
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
            if visiblePorts.isEmpty {
                if portWatcher.ports.isEmpty {
                    noPortsState
                } else {
                    nothingConnectedState
                }
            } else {
                let activePortCount = portWatcher.ports.filter { $0.connectionActive == true }.count
                let adapter = SystemPower.currentAdapter()
                let batteryFull = SystemPower.batteryFullyCharged()
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
                                adapter: adapter
                            )
                            PortCard(
                                port: port,
                                devices: matchingDevices(for: port),
                                powerSources: portSources,
                                identities: pdWatcher.identities(for: port),
                                thunderboltSwitches: tbWatcher.switches,
                                usb3Transports: usb3Watcher.transports(for: port),
                                isLive: isPortLive(port),
                                showAdvanced: showAdvanced,
                                cioCapability: trmWatcher.cioCapabilities.first { $0.portKey == port.portKey },
                                displayPorts: displayWatcher.statuses.filter { $0.status.portKey == port.portKey }.map(\.status),
                                chargerWattageSource: wattageSource,
                                batteryFullyCharged: batteryFull,
                                adapter: adapter,
                                anotherPortActivelyCharging: port.portKey.map { key in chargingPortKeys.contains { $0 != key } } ?? false
                            )
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
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Refresh", bundle: _appLocalizedBundle))
            Button {
                refresh.showSettings = true
            } label: {
                Image(systemName: "gearshape")
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
            matchingDevices: matchingDevices(for: port)
        )
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
        case .downloading:
            Text(String(localized: "Downloading…", bundle: _appLocalizedBundle))
        case .verifying:
            Text(String(localized: "Verifying signature…", bundle: _appLocalizedBundle))
        case .installing:
            Text(String(localized: "Installing, WhatCable will relaunch", bundle: _appLocalizedBundle))
        case .failed(let message):
            Text(String(localized: "Install failed: \(message)", bundle: _appLocalizedBundle)).foregroundStyle(.red)
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
        case .downloading, .verifying, .installing:
            ProgressView().controlSize(.small)
        }
    }
}

// MARK: - Port card

struct PortCard: View {
    let port: AppleHPMInterface
    let devices: [USBDevice]
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
    /// System-wide adapter info from `SystemPower.currentAdapter()`.
    /// Threaded through so the "Charger: <Manufacturer> <Name>" bullet
    /// can fire on the active charging port.
    let adapter: AdapterInfo?
    /// True when a different port holds the live charging contract, so a
    /// connected-but-idle charger here reads as on standby rather than
    /// stuck mid-negotiation. See issue #264.
    var anotherPortActivelyCharging: Bool = false

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
            adapter: adapter
        )
    }

    /// Switches in the chain from this port's host root to the deepest
    /// connected device. Empty if the port doesn't map to any TB switch.
    var thunderboltChain: [IOThunderboltSwitch] {
        guard let socketID = ThunderboltTopology.socketID(for: port),
              let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches) else {
            return []
        }
        return ThunderboltTopology.chain(from: root, in: thunderboltSwitches)
    }

    private var cableEmarker: USBPDSOP? {
        identities.first { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }
    }

    private var cablePartner: USBPDSOP? {
        identities.first { $0.endpoint == .sop }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            if let diag = ChargingDiagnostic(port: port, sources: powerSources, identities: identities, wattageSource: chargerWattageSource, batteryFullyCharged: batteryFullyCharged, anotherPortActivelyCharging: anotherPortActivelyCharging) {
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

            if !devices.isEmpty {
                let tree = USBDeviceNode.flatten(USBDeviceNode.buildTree(from: devices))
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Connected devices", bundle: _appLocalizedBundle))
                        .scaledFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.secondary)
                    ForEach(tree) { node in
                        let name = node.device.productName ?? String(localized: "Unknown", bundle: _appLocalizedBundle)
                        let prefix = node.depth > 0 ? "\u{21B3} " : "\u{2022} "
                        Text(verbatim: "\(prefix)\(name) - \(node.device.speedLabel)")
                            .scaledFont(.callout)
                            .padding(.leading, CGFloat(node.depth) * 16)
                    }
                }
                .padding(.leading, 48)
                .padding(.top, 4)
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
                    thunderboltChain: thunderboltChain
                )
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .sheet(item: $reportingCable) { cable in
            CableReportSheet(cableIdentity: cable, cioCapability: cioCapability) {
                reportingCable = nil
            }
        }
    }

}

/// Visual weight of a top-of-card callout, by severity. Warnings get a filled
/// box so they stand out; positive, info, and neutral notes are lighter (no
/// fill) so the eye lands on problems first within the callout group.
enum CalloutRole {
    case warning    // a problem worth the user's attention
    case positive   // reassurance: everything is fine
    case info       // an informational note, no problem
    case neutral    // could not determine, no verdict

    var accent: Color {
        switch self {
        case .warning: return .orange
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

struct DisplayBanner: View {
    let diagnostic: DisplayDiagnostic

    private var role: CalloutRole {
        switch diagnostic.bottleneck {
        case .fine: return .positive
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
        case .compressionPlausible: return "info.circle"
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
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Open in a separate window", bundle: _appLocalizedBundle))
                    Button(action: onTogglePin) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
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
    let thunderboltChain: [IOThunderboltSwitch]

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
            if !thunderboltChain.isEmpty {
                ThunderboltFabricSection(chain: thunderboltChain)
            }
            let rawCount = port.rawProperties.count
            DisclosureGroup(String(localized: "All raw IOKit properties (\(rawCount))", bundle: _appLocalizedBundle)) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(port.rawProperties.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        HStack(alignment: .top) {
                            Text(kv.key).scaledFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .frame(width: 200, alignment: .leading)
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
            Text(key).scaledFont(.caption).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Active cable (VDO 2)")
                .scaledFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
            row("Physical connection", vdo2.physicalConnection.label)
            row("Active element", vdo2.activeElement.label)
            row("Optically isolated", bool(vdo2.opticallyIsolated))
            row("USB lanes", vdo2.twoLanesSupported ? "Two" : "One")
            row("USB Gen", vdo2.usbGen2OrHigher ? "Gen 2 or higher" : "Gen 1")
            row("USB4 supported", bool(vdo2.usb4Supported))
            row("USB 3.2 supported", bool(vdo2.usb32Supported))
            row("USB 2.0 supported", bool(vdo2.usb2Supported))
            row("USB 2.0 hub hops", String(vdo2.usb2HubHopsConsumed))
            row("USB4 asymmetric", bool(vdo2.usb4AsymmetricMode))
            row("U3 to U0 transition", vdo2.u3ToU0TransitionThroughU3S ? "Through U3S" : "Direct")
            row("Idle power (U3/CLd)", vdo2.u3CLdPower.label)
            row("Max operating temp", temp(vdo2.maxOperatingTempC))
            row("Shutdown temp", temp(vdo2.shutdownTempC))
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).scaledFont(.caption).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
            Text(value).scaledFont(.caption, design: .monospaced)
            Spacer()
        }
    }

    private func bool(_ v: Bool) -> String { v ? "Yes" : "No" }

    /// 0 in this field means "not specified" per the spec text. Show
    /// the dash placeholder rather than the misleading literal "0°C".
    private func temp(_ v: Int) -> String {
        v == 0 ? "—" : "\(v)°C"
    }
}

/// Compact tree view of the Thunderbolt fabric for one port. Shows the
/// host root, every downstream switch in the chain, and the active
/// downstream lane port's link state for each hop. Hidden behind the
/// existing "show technical details" toggle.
struct ThunderboltFabricSection: View {
    let chain: [IOThunderboltSwitch]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Thunderbolt fabric", bundle: _appLocalizedBundle))
                .scaledFont(.caption, weight: .bold).foregroundStyle(.secondary)
            ForEach(Array(chain.enumerated()), id: \.element.id) { index, sw in
                hopRow(sw, index: index)
            }
        }
    }

    @ViewBuilder
    private func hopRow(_ sw: IOThunderboltSwitch, index: Int) -> some View {
        let indent = String(repeating: "  ", count: index)
        let arrow = index == 0 ? "" : "↳ "
        let name = sw.isHostRoot ? String(localized: "Host (\(sw.className))", bundle: _appLocalizedBundle) : ThunderboltLabels.deviceName(for: sw)
        let port = ThunderboltTopology.activeDownstreamLanePort(sw)
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
