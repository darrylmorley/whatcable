import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var portWatcher = USBCPortWatcher()
    @StateObject private var deviceWatcher = USBWatcher()
    @StateObject private var powerWatcher = PowerSourceWatcher()
    @StateObject private var pdWatcher = PDIdentityWatcher()
    @EnvironmentObject private var refresh: RefreshSignal
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if portWatcher.ports.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(portWatcher.ports) { port in
                            PortCard(
                                port: port,
                                devices: matchingDevices(for: port),
                                powerSources: powerWatcher.sources(for: port),
                                identities: pdWatcher.identities(for: port),
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
        .onAppear {
            portWatcher.start()
            deviceWatcher.start()
            powerWatcher.start()
            pdWatcher.start()
        }
        .onDisappear {
            portWatcher.stop()
            deviceWatcher.stop()
            powerWatcher.stop()
            pdWatcher.stop()
        }
        .onChange(of: refresh.tick) { _, _ in
            portWatcher.refresh()
            powerWatcher.refresh()
            pdWatcher.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
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
            Menu {
                Button("About \(AppInfo.name)") { AppDelegate.showAboutPanel() }
                Button("Help") { NSWorkspace.shared.open(AppInfo.helpURL) }
                Divider()
                Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More options")
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Toggle("Show technical details", isOn: $showAdvanced)
                .toggleStyle(.switch)
                .controlSize(.small)
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

    private var emptyState: some View {
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
    }

    /// Heuristic: USB devices' `locationID` upper byte often correlates with the
    /// physical port. Without a perfect map, just surface all devices on the
    /// first connected port.
    private func matchingDevices(for port: USBCPort) -> [USBDevice] {
        guard port.connectionActive == true else { return [] }
        return deviceWatcher.devices
    }
}

// MARK: - Port card

struct PortCard: View {
    let port: USBCPort
    let devices: [USBDevice]
    let powerSources: [PowerSource]
    let identities: [PDIdentity]
    let showAdvanced: Bool

    var summary: PortSummary {
        PortSummary(port: port, sources: powerSources, identities: identities)
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

            if !devices.isEmpty && port.connectionActive == true {
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

            if showAdvanced {
                Divider()
                AdvancedPortDetails(port: port)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            group("Connection") {
                row("Active", bool(port.connectionActive))
                row("E-marker chip", bool(port.activeCable))
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
