import SwiftUI
import WidgetKit
import WhatCableCore

// MARK: - Main entry view for static widget (small + medium + large)

struct CableWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: CableWidgetEntry

    var body: some View {
        let language = entry.snapshot?.language ?? WhatCableLanguage.persistedForWidget()
        if let snapshot = entry.snapshot, !snapshot.ports.isEmpty {
            switch family {
            case .systemSmall:
                SmallWidgetView(port: mostInteresting(snapshot.ports, language: language))
            case .systemMedium:
                MediumWidgetView(ports: snapshot.ports)
            case .systemLarge:
                LargeWidgetView(ports: snapshot.ports)
            default:
                MediumWidgetView(ports: snapshot.ports)
            }
        } else {
            EmptyStateView(language: language)
        }
    }
}

// MARK: - Small: single most interesting port

struct SmallWidgetView: View {
    let port: WidgetSnapshot.PortEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: port.iconName)
                    .font(.title2)
                    .foregroundStyle(port.status.color)
                Spacer()
                if port.deviceCount > 0 {
                    DeviceCountBadge(count: port.deviceCount)
                }
            }
            Text(port.headline)
                .font(.headline)
                .lineLimit(2)
            Text(port.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(port.portName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Medium: all ports in a row

struct MediumWidgetView: View {
    let ports: [WidgetSnapshot.PortEntry]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ports.prefix(4).enumerated()), id: \.element.id) { index, port in
                if index > 0 {
                    Divider().padding(.vertical, 4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: port.iconName)
                            .font(.title3)
                            .foregroundStyle(port.status.color)
                        if port.deviceCount > 0 {
                            DeviceCountBadge(count: port.deviceCount, compact: true)
                        }
                    }
                    Text(port.headline)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Large: all ports with detail

struct LargeWidgetView: View {
    let ports: [WidgetSnapshot.PortEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundStyle(.secondary)
                Text("WhatCable")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)

            ForEach(Array(ports.prefix(6).enumerated()), id: \.element.id) { index, port in
                if index > 0 {
                    Divider().padding(.vertical, 4)
                }
                LargePortRow(port: port)
            }
            Spacer(minLength: 0)
        }
    }
}

struct LargePortRow: View {
    let port: WidgetSnapshot.PortEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: port.iconName)
                .font(.title3)
                .foregroundStyle(port.status.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(port.headline)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(port.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let bullet = port.topBullet {
                    Text(bullet)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if port.deviceCount > 0 {
                DeviceCountBadge(count: port.deviceCount)
            }
        }
    }
}

// MARK: - Device count badge

/// Small label showing how many USB devices are connected to a port.
/// Uses a compact layout on the medium widget (icon only with count)
/// and a slightly larger one on small/large widgets.
struct DeviceCountBadge: View {
    let count: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: count == 1 ? "laptopcomputer" : "square.stack.3d.up")
                .font(compact ? .caption2 : .caption)
            Text("\(count)")
                .font(compact ? .caption2 : .caption)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let language: WhatCableLanguage

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cable.connector.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(LocalizedCopy.string("No cable data", bundle: .main, language: language))
                .font(.headline)
            Text(LocalizedCopy.string("Open WhatCable to start monitoring.", bundle: .main, language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Status color mapping

extension WidgetSnapshot.Status {
    /// Widget-side color for each status. Matches the mapping in
    /// PortSummary+UI.swift in the main app.
    var color: Color {
        switch self {
        case .empty: return .secondary
        case .charging: return .yellow
        case .dataDevice: return .blue
        case .thunderboltCable: return .purple
        case .displayCable: return .teal
        case .unknown: return .orange
        }
    }
}

// MARK: - Most interesting port selection

/// Pick the single most interesting port for the small widget. Uses a
/// deterministic ranking so the displayed port doesn't flip randomly
/// between refreshes.
///
/// Ranking: connected ports beat empty ones. Among connected ports,
/// richer connections rank higher (Thunderbolt > display > data > charging).
/// Ties break by port ID for stability.
func mostInteresting(
    _ ports: [WidgetSnapshot.PortEntry],
    language: WhatCableLanguage = .default
) -> WidgetSnapshot.PortEntry {
    ports.sorted { a, b in
        let aRank = a.status.interestRank
        let bRank = b.status.interestRank
        if aRank != bRank { return aRank > bRank }
        return a.id < b.id
    }.first ?? WidgetSnapshot.PortEntry(
        id: 0,
        portName: "USB-C",
        status: .empty,
        headline: LocalizedCopy.string("Nothing connected", language: language),
        subtitle: LocalizedCopy.string("Plug a cable in to see what it can do.", bundle: .main, language: language),
        topBullet: nil,
        iconName: "powerplug",
        deviceCount: 0
    )
}

private extension WidgetSnapshot.Status {
    /// Higher number = more interesting for the small widget.
    var interestRank: Int {
        switch self {
        case .thunderboltCable: return 5
        case .displayCable: return 4
        case .dataDevice: return 3
        case .charging: return 2
        case .unknown: return 1
        case .empty: return 0
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder()
}

#Preview("Medium", as: .systemMedium) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder()
}

#Preview("Large", as: .systemLarge) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder()
}

#Preview("Empty", as: .systemMedium) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry(date: Date(), snapshot: nil)
}
