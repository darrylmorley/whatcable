import SwiftUI
import WhatCableCore
import WhatCableDarwinBackend

struct ContentView: View {
    @StateObject private var portWatcher = USBCPortWatcher()
    @StateObject private var deviceWatcher = USBWatcher()
    @StateObject private var powerWatcher = PowerSourceWatcher()
    @StateObject private var pdWatcher = PDIdentityWatcher()
    @StateObject private var tbWatcher = ThunderboltWatcher()
    @EnvironmentObject private var refresh: RefreshSignal
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var portRefreshTask: Task<Void, Never>?
    @State private var portPollTask: Task<Void, Never>?

    private var showAdvanced: Bool {
        settings.showTechnicalDetails || refresh.optionHeld
    }

    var body: some View {
        Group {
            if refresh.showSettings {
                SettingsView(dismiss: { refresh.showSettings = false })
            } else {
                mainContent
            }
        }
        .onAppear {
            portWatcher.start()
            deviceWatcher.start()
            powerWatcher.start()
            pdWatcher.start()
            tbWatcher.start()
            startPortPoll()
        }
        .onDisappear {
            portRefreshTask?.cancel()
            portRefreshTask = nil
            portPollTask?.cancel()
            portPollTask = nil
            portWatcher.stop()
            deviceWatcher.stop()
            powerWatcher.stop()
            pdWatcher.stop()
            tbWatcher.stop()
        }
        .onChange(of: refresh.tick) { _, _ in
            portWatcher.refresh()
            powerWatcher.refresh()
            pdWatcher.refresh()
            tbWatcher.refresh()
        }
        // Port controller services don't fire IOKit match notifications when
        // their connection state flips, so we re-poll the port watcher
        // whenever any of the three live signals (device add/remove, power
        // source add/remove, PD identity add/remove) changes. Debounced so a
        // single plug event, which can fire all three within a few ms,
        // produces one refresh, with a backoff to catch slow controllers.
        .onChange(of: deviceWatcher.devices) { _, _ in scheduleLivePortRefresh() }
        .onChange(of: powerWatcher.sources) { _, _ in scheduleLivePortRefresh() }
        .onChange(of: pdWatcher.identities) { _, _ in scheduleLivePortRefresh() }
    }

    private func scheduleLivePortRefresh() {
        portRefreshTask?.cancel()
        portRefreshTask = Task { @MainActor in
            // Some port controllers (notably AppleHPMInterfaceType11 / MagSafe)
            // hold ConnectionActive=true for several seconds after unplug, so
            // we re-poll over a long backoff instead of guessing one delay.
            // refresh() is a no-op when nothing changed, so extra polls are
            // cheap and never cause flicker.
            for delay in [150, 500, 1500, 3000, 6000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                portWatcher.refresh()
            }
        }
    }

    /// Background safety net: poll the port watcher once a second while the
    /// popover is visible. Catches slow-updating controllers that don't fire
    /// IOKit interest notifications when their connection state flips, and
    /// covers state changes that happen outside the burst window triggered
    /// by scheduleLivePortRefresh. The conditional assignment in
    /// USBCPortWatcher.refresh() means polls are free when nothing changed.
    private func startPortPoll() {
        portPollTask?.cancel()
        portPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                portWatcher.refresh()
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
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(visiblePorts) { port in
                            PortCard(
                                port: port,
                                devices: matchingDevices(for: port),
                                powerSources: powerWatcher.sources(for: port),
                                identities: pdWatcher.identities(for: port),
                                thunderboltSwitches: tbWatcher.switches,
                                isLive: isPortLive(port),
                                showAdvanced: showAdvanced
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
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name).font(.headline)
                Text(AppInfo.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                refresh.bump()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            Button {
                refresh.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
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
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(deviceWatcher.devices.count) USB device\(deviceWatcher.devices.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·").font(.caption).foregroundStyle(.secondary)
            Text("v\(AppInfo.version) · \(AppInfo.credit)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var noPortsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "powerplug")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No USB-C ports detected")
                .font(.headline)
            Text("This Mac doesn't seem to expose its port-controller services. Hit refresh, or check System Information → USB.")
                .font(.caption)
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
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Nothing connected")
                .font(.headline)
            Text("\(portWatcher.ports.count) USB-C port\(portWatcher.ports.count == 1 ? "" : "s") detected, but nothing is currently plugged in. Turn off \"Hide empty ports\" in Settings to see them.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Live-signal check delegating to the pure helper in `WhatCableCore`,
    /// so the same rules apply to both the GUI and any test harness.
    private func isPortLive(_ port: USBCPort) -> Bool {
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
    private func matchingDevices(for port: USBCPort) -> [USBDevice] {
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
                Text("WhatCable \(update.version) is available")
                    .font(.callout).bold()
                statusLine
                    .font(.caption).foregroundStyle(.secondary)
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
            Text("You're on \(AppInfo.version)")
        case .downloading:
            Text("Downloading…")
        case .verifying:
            Text("Verifying signature…")
        case .installing:
            Text("Installing — WhatCable will relaunch")
        case .failed(let message):
            Text("Install failed: \(message)").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch installer.state {
        case .idle, .failed:
            HStack(spacing: 6) {
                Button("View release") {
                    NSWorkspace.shared.open(update.url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if update.downloadURL != nil {
                    Button("Install update") {
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
    let port: USBCPort
    let devices: [USBDevice]
    let powerSources: [PowerSource]
    let identities: [PDIdentity]
    let thunderboltSwitches: [ThunderboltSwitch]
    /// Authoritative connection state derived from the live IOKit watchers,
    /// passed in from the parent so we don't have to consult them from here
    /// and so PortSummary doesn't fall back to the unreliable
    /// `port.connectionActive` property.
    let isLive: Bool
    let showAdvanced: Bool

    @State private var reportingCable: PDIdentity?

    var summary: PortSummary {
        PortSummary(
            port: port,
            sources: powerSources,
            identities: identities,
            devices: devices,
            thunderboltSwitches: thunderboltSwitches,
            isConnectedOverride: isLive
        )
    }

    /// Switches in the chain from this port's host root to the deepest
    /// connected device. Empty if the port doesn't map to any TB switch.
    var thunderboltChain: [ThunderboltSwitch] {
        guard let socketID = ThunderboltTopology.socketID(fromServiceName: port.serviceName),
              let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches) else {
            return []
        }
        return ThunderboltTopology.chain(from: root, in: thunderboltSwitches)
    }

    private var cableEmarker: PDIdentity? {
        identities.first { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(summary.iconColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(port.portDescription ?? port.serviceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.headline)
                        .font(.title3).bold()
                    Text(summary.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !summary.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(bullet).font(.callout)
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 48)
            }

            if !devices.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected device\(devices.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(devices) { d in
                        Text("• \(d.productName ?? "Unknown") — \(d.speedLabel)")
                            .font(.callout)
                    }
                }
                .padding(.leading, 48)
            }

            if let diag = ChargingDiagnostic(port: port, sources: powerSources, identities: identities) {
                DiagnosticBanner(diagnostic: diag)
                    .padding(.leading, 48)
            }

            if !powerSources.isEmpty {
                PowerSourceList(sources: powerSources)
                    .padding(.leading, 48)
            }

            if let cable = cableEmarker {
                let trust = CableTrustReport(identity: cable)
                if !trust.isEmpty {
                    TrustFlagsCard(flags: trust.flags)
                        .padding(.leading, 48)
                }

                HStack {
                    Spacer()
                    Button {
                        reportingCable = cable
                    } label: {
                        Label("Report this cable", systemImage: "exclamationmark.bubble")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("File a GitHub issue with this cable's e-marker fingerprint")
                }
                .padding(.leading, 48)
            }

            if showAdvanced {
                Divider()
                AdvancedPortDetails(port: port, thunderboltChain: thunderboltChain)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .sheet(item: $reportingCable) { cable in
            CableReportSheet(cableIdentity: cable) {
                reportingCable = nil
            }
        }
    }
}

struct DiagnosticBanner: View {
    let diagnostic: ChargingDiagnostic

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: diagnostic.icon)
                .foregroundStyle(diagnostic.isWarning ? Color.orange : Color.green)
                .font(.callout)
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.summary).font(.callout).bold()
                Text(diagnostic.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            (diagnostic.isWarning ? Color.orange : Color.green)
                .opacity(0.1),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

struct PowerSourceList: View {
    let sources: [PowerSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources) { src in
                if !src.options.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(src.name) profiles")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(src.options.sorted(by: { $0.voltageMV < $1.voltageMV }), id: \.self) { opt in
                            let isWinning = opt == src.winning
                            HStack(spacing: 6) {
                                Image(systemName: isWinning ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isWinning ? Color.green : Color.secondary)
                                    .font(.caption)
                                Text("\(opt.voltsLabel) @ \(opt.ampsLabel) — \(opt.wattsLabel)")
                                    .font(.callout.monospacedDigit())
                                if isWinning {
                                    Text("active").font(.caption2).foregroundStyle(.green)
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
    let port: USBCPort
    let thunderboltChain: [ThunderboltSwitch]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            group("Connection") {
                row("Active", bool(port.connectionActive))
                row("Active cable electronics", bool(port.activeCable))
                row("Optical", bool(port.opticalCable))
                row("USB active", bool(port.usbActive))
                row("SuperSpeed", bool(port.superSpeedActive))
                row("Plug events", port.plugEventCount.map(String.init) ?? "—")
            }
            group("Transports") {
                row("Supported", port.transportsSupported.joined(separator: ", "))
                row("Provisioned", port.transportsProvisioned.joined(separator: ", "))
                row("Active", port.transportsActive.isEmpty ? "—" : port.transportsActive.joined(separator: ", "))
            }
            if !thunderboltChain.isEmpty {
                ThunderboltFabricSection(chain: thunderboltChain)
            }
            DisclosureGroup("All raw IOKit properties (\(port.rawProperties.count))") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(port.rawProperties.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        HStack(alignment: .top) {
                            Text(kv.key).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 200, alignment: .leading)
                            Text(kv.value).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).font(.system(.caption, design: .monospaced))
            Spacer()
        }
    }

    private func bool(_ v: Bool?) -> String {
        guard let v else { return "—" }
        return v ? "Yes" : "No"
    }
}

/// Compact tree view of the Thunderbolt fabric for one port. Shows the
/// host root, every downstream switch in the chain, and the active
/// downstream lane port's link state for each hop. Hidden behind the
/// existing "show technical details" toggle.
struct ThunderboltFabricSection: View {
    let chain: [ThunderboltSwitch]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Thunderbolt fabric")
                .font(.caption).bold().foregroundStyle(.secondary)
            ForEach(Array(chain.enumerated()), id: \.element.id) { index, sw in
                hopRow(sw, index: index)
            }
        }
    }

    @ViewBuilder
    private func hopRow(_ sw: ThunderboltSwitch, index: Int) -> some View {
        let indent = String(repeating: "  ", count: index)
        let arrow = index == 0 ? "" : "↳ "
        let name = sw.isHostRoot ? "Host (\(sw.className))" : ThunderboltLabels.deviceName(for: sw)
        let port = ThunderboltTopology.activeDownstreamLanePort(sw)
        let linkLabel = port.flatMap { ThunderboltLabels.linkLabel(for: $0) } ?? "no active link"

        HStack(alignment: .top) {
            Text("\(indent)\(arrow)\(name)")
                .font(.system(.caption, design: .monospaced))
            Spacer()
            Text(linkLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrustFlagsCard: View {
    let flags: [TrustFlag]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Cable trust signals")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
            }
            ForEach(flags, id: \.code) { flag in
                VStack(alignment: .leading, spacing: 2) {
                    Text(flag.title).font(.callout).bold()
                    Text(flag.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

