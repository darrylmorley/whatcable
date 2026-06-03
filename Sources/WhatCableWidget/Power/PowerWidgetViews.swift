import SwiftUI
import WidgetKit
import WhatCableCore

// MARK: - Widget definition

struct PowerMonitorWidget: Widget {
    let kind = "uk.whatcable.whatcable.power-monitor"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PowerTimelineProvider()) { entry in
            PowerMonitorEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text(String(localized: "Power Monitor", bundle: _coreLocalizedBundle)))
        .description(Text(String(localized: "Battery and charging at a glance.", bundle: _coreLocalizedBundle)))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry view dispatcher

struct PowerMonitorEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: PowerMonitorEntry

    var body: some View {
        if let snapshot = entry.snapshot, snapshot.powerState != nil {
            switch family {
            case .systemSmall:
                PowerSmallView(snapshot: snapshot)
            case .systemMedium:
                PowerMediumView(snapshot: snapshot)
            case .systemLarge:
                PowerLargeView(snapshot: snapshot)
            default:
                PowerMediumView(snapshot: snapshot)
            }
        } else {
            PowerEmptyStateView()
        }
    }
}

// MARK: - Shared power presentation

extension WidgetSnapshot.PowerState {
    /// Colour for the battery glyph: green full, yellow charging, muted idle.
    var chargeColor: Color {
        if fullyCharged { return .green }
        if isCharging { return .yellow }
        return .secondary
    }

    var statusLabel: String {
        if isDesktopMac { return prettyAdapterDescription ?? "" }
        if fullyCharged { return String(localized: "Battery full", bundle: _coreLocalizedBundle) }
        if isCharging { return String(localized: "Charging", bundle: _coreLocalizedBundle) }
        return String(localized: "On battery", bundle: _coreLocalizedBundle)
    }

    /// IOKit hands us the adapter description lowercase ("pd charger"). Present
    /// it tidily, uppercasing known acronyms so it reads "PD Charger".
    var prettyAdapterDescription: String? {
        guard let raw = adapterDescription, !raw.isEmpty else { return nil }
        return raw.split(separator: " ").map { word -> String in
            switch word.lowercased() {
            case "pd": return "PD"
            case "ac": return "AC"
            case "usb", "usbc", "usb-c": return "USB-C"
            case "magsafe": return "MagSafe"
            default: return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
        }.joined(separator: " ")
    }

    var batteryIcon: String {
        if isDesktopMac { return "desktopcomputer" }
        if isCharging { return "battery.100.bolt" }
        guard let pct = batteryPercent else { return "battery.100" }
        if pct <= 25 { return "battery.25" }
        if pct <= 50 { return "battery.50" }
        if pct <= 75 { return "battery.75" }
        return "battery.100"
    }

    /// Big-number tint: red low, orange mid, neutral healthy.
    func batteryTint(_ pct: Int) -> Color {
        if pct <= 20 { return .red }
        if pct <= 50 { return .orange }
        return .primary
    }
}

/// "3.1W" from a wattage double, for a pill or muted line.
private func wattText(_ w: Double) -> String {
    String(format: "%.1f", w) + "W"
}

// MARK: - Small: battery anchor + charger pill

struct PowerSmallView: View {
    let snapshot: WidgetSnapshot

    private var power: WidgetSnapshot.PowerState { snapshot.powerState! }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetMetrics.s) {
            WidgetHeader(title: String(localized: "Power Monitor", bundle: _coreLocalizedBundle))
            Spacer(minLength: 0)

            HStack(spacing: WidgetMetrics.s) {
                Image(systemName: power.batteryIcon)
                    .font(.title2)
                    .foregroundStyle(power.chargeColor)
                Spacer()
                if let watts = power.adapterWatts {
                    PowerPill(watts: watts)
                }
            }

            if power.isDesktopMac {
                Text(String(localized: "Power connected", bundle: _coreLocalizedBundle))
                    .font(.headline)
            } else if let pct = power.batteryPercent {
                Text("\(pct)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(power.batteryTint(pct))
            }

            Text(power.statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Medium: battery anchor + charger / draw

struct PowerMediumView: View {
    let snapshot: WidgetSnapshot

    private var power: WidgetSnapshot.PowerState { snapshot.powerState! }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetMetrics.s) {
            WidgetHeader(title: String(localized: "Power Monitor", bundle: _coreLocalizedBundle))

            HStack(spacing: WidgetMetrics.m) {
                VStack(alignment: .leading, spacing: WidgetMetrics.xxs) {
                    HStack(spacing: WidgetMetrics.s) {
                        Image(systemName: power.batteryIcon)
                            .font(.title3)
                            .foregroundStyle(power.chargeColor)
                        if power.isDesktopMac {
                            Text(String(localized: "Power connected", bundle: _coreLocalizedBundle))
                                .font(.headline)
                        } else if let pct = power.batteryPercent {
                            Text("\(pct)%")
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .monospacedDigit()
                        }
                    }
                    Text(power.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: WidgetMetrics.xs) {
                    if let watts = power.adapterWatts {
                        PowerPill(watts: watts)
                    }
                    if let desc = power.prettyAdapterDescription {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let sysW = power.systemPowerInWatts {
                        let drawFormat = String(localized: "%@W draw", bundle: _coreLocalizedBundle)
                        Text(String(format: drawFormat, String(format: "%.1f", sysW)))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Large: full power dashboard

struct PowerLargeView: View {
    let snapshot: WidgetSnapshot

    private var power: WidgetSnapshot.PowerState { snapshot.powerState! }

    /// Per-port rows that fit below the battery / charger / draw rows before
    /// the large widget runs out of height. Extra ports collapse into "+N".
    private let maxPortRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(icon: "bolt.fill", title: String(localized: "Power Monitor", bundle: _coreLocalizedBundle))
                .padding(.bottom, WidgetMetrics.s)

            // Battery anchor row.
            powerRow(accent: power.chargeColor, icon: power.batteryIcon, iconColor: power.chargeColor) {
                if power.isDesktopMac {
                    Text(String(localized: "Power connected", bundle: _coreLocalizedBundle))
                        .font(.callout)
                        .fontWeight(.semibold)
                } else if let pct = power.batteryPercent {
                    Text("\(pct)%")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
                Text(power.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } trailing: { EmptyView() }

            if let watts = power.adapterWatts {
                Divider().padding(.vertical, WidgetMetrics.xs)
                powerRow(accent: .orange, icon: "powerplug.portrait.fill", iconColor: .orange) {
                    Text(String(localized: "Charger", bundle: _coreLocalizedBundle))
                        .font(.callout)
                        .fontWeight(.semibold)
                    if let desc = power.prettyAdapterDescription {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } trailing: {
                    PowerPill(watts: watts)
                }
            }

            if let sysW = power.systemPowerInWatts {
                Divider().padding(.vertical, WidgetMetrics.xs)
                powerRow(accent: .orange, icon: "bolt.horizontal.fill", iconColor: .orange) {
                    Text(String(localized: "System draw", bundle: _coreLocalizedBundle))
                        .font(.callout)
                        .fontWeight(.semibold)
                } trailing: {
                    Pill(text: wattText(sysW), color: .orange)
                }
            }

            if let portWatts = power.perPortWatts, !portWatts.isEmpty {
                Divider().padding(.vertical, WidgetMetrics.xs)
                // Highest-draw ports first, capped so a many-port desktop Mac
                // doesn't overflow the widget; the rest collapse into "+N".
                let sorted = portWatts.sorted { $0.watts > $1.watts }
                let shown = sorted.prefix(maxPortRows)
                ForEach(shown, id: \.portKey) { portPower in
                    HStack(spacing: WidgetMetrics.s) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.blue)
                            .frame(width: 3)
                        Image(systemName: "cable.connector")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .frame(width: 22)
                        Text(portPower.portName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: WidgetMetrics.s)
                        Pill(text: wattText(portPower.watts), color: .blue, compact: true)
                    }
                }
                if sorted.count > shown.count {
                    OverflowRow(count: sorted.count - shown.count)
                        .padding(.leading, 25)  // align under the port names
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Shared accent-bar row: colour bar, icon, a content block, trailing item.
    @ViewBuilder
    private func powerRow<Content: View, Trailing: View>(
        accent: Color,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: WidgetMetrics.s) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3)
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(iconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: WidgetMetrics.xxs) {
                content()
            }
            Spacer(minLength: WidgetMetrics.s)
            trailing()
        }
    }
}

// MARK: - Empty state

struct PowerEmptyStateView: View {
    var body: some View {
        VStack(spacing: WidgetMetrics.s) {
            Image(systemName: "bolt.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "No power data", bundle: _coreLocalizedBundle))
                .font(.headline)
            Text(String(localized: "Open WhatCable to start monitoring.", bundle: _coreLocalizedBundle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
