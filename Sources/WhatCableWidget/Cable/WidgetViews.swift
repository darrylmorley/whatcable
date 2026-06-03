import SwiftUI
import WidgetKit
import WhatCableCore

// MARK: - Main entry view for static widget (small + medium + large)

struct CableWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: CableWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.ports.isEmpty {
            switch family {
            case .systemSmall:
                SmallWidgetView(port: resolveSmallPort(snapshot))
            case .systemMedium:
                MediumWidgetView(ports: resolveFilteredPorts(snapshot))
            case .systemLarge:
                LargeWidgetView(ports: resolveFilteredPorts(snapshot))
            default:
                MediumWidgetView(ports: resolveFilteredPorts(snapshot))
            }
        } else {
            EmptyStateView()
        }
    }

    private func resolveSmallPort(_ snapshot: WidgetSnapshot) -> WidgetSnapshot.PortEntry {
        if let pinned = entry.configuration.selectedPort,
           let match = snapshot.ports.first(where: { String($0.id) == pinned.id }) {
            return match
        }
        return mostInteresting(snapshot.ports)
    }

    private func resolveFilteredPorts(_ snapshot: WidgetSnapshot) -> [WidgetSnapshot.PortEntry] {
        if let selected = entry.configuration.selectedPorts, !selected.isEmpty {
            let ids = Set(selected.map(\.id))
            let filtered = snapshot.ports.filter { ids.contains(String($0.id)) }
            if !filtered.isEmpty { return filtered }
        }

        let nonEmpty = snapshot.ports.filter { $0.status != .empty }
        return nonEmpty.isEmpty ? snapshot.ports : nonEmpty
    }
}

// MARK: - Shared metrics

/// One spacing scale for every widget view, so gaps are consistent instead of
/// ad-hoc 3/6/10 magic numbers. Steps roughly double: 2, 4, 8, 12.
enum WidgetMetrics {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
}

// MARK: - Section header

/// Small uppercase header, mirroring the muted date label on the macOS
/// Calendar widget. Anchors every card to the same top-left treatment.
struct WidgetHeader: View {
    var icon: String? = nil
    let title: String

    var body: some View {
        HStack(spacing: WidgetMetrics.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Status icon (with optional live dot)

/// The status SF Symbol, with a small "live" dot in the corner when the port
/// is actively doing something (carrying data, on a TB link, charging). The
/// dot gets a thin background-coloured ring so it reads cleanly over the glyph.
struct StatusIcon: View {
    let name: String
    let color: Color
    var live: Bool = false
    var font: Font = .callout

    var body: some View {
        Image(systemName: name)
            .font(font)
            .foregroundStyle(color)
            .overlay(alignment: .topTrailing) {
                if live {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }
    }
}

// MARK: - Pills

extension View {
    /// One pill treatment for every metric chip (speed, power, devices), so
    /// they read as a consistent family: tinted capsule, semibold, monospaced
    /// digits so live values don't jitter as they change.
    func badgeChip(_ color: Color, compact: Bool = false) -> some View {
        self
            .font(compact ? .caption2 : .caption)
            .fontWeight(.semibold)
            .monospacedDigit()
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 1 : 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// A plain text pill in the shared style. `.fixedSize` keeps the label on one
/// line so a narrow container wraps whole pills (via FlowLayout) rather than
/// breaking "100W" into "100" / "W".
struct Pill: View {
    let text: String
    var color: Color = .gray
    var compact: Bool = false

    var body: some View {
        Text(text)
            .badgeChip(color, compact: compact)
            .fixedSize()
    }
}

/// A leading-aligned layout that wraps its subviews onto new rows when they
/// run out of horizontal space. Used for the pill cluster on narrow cards.
struct FlowLayout: Layout {
    var spacing: CGFloat = WidgetMetrics.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                      anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Negotiated link speed pill, colour-keyed to the tier.
struct LinkSpeedBadge: View {
    let speed: LinkSpeed
    var compact: Bool = false

    var body: some View {
        Pill(text: speed.badge, color: speed.tier.color, compact: compact)
    }
}

/// Charger wattage pill.
struct PowerPill: View {
    let watts: Int
    var compact: Bool = false

    var body: some View {
        Pill(text: "\(watts)W", color: .orange, compact: compact)
    }
}

/// Matched-device-count pill (icon + count).
struct DeviceCountBadge: View {
    let count: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: count == 1 ? "laptopcomputer" : "square.stack.3d.up")
            Text("\(count)")
        }
        .badgeChip(.gray, compact: compact)
        .fixedSize()
    }
}

extension LinkSpeed.Tier {
    /// Badge colour by tier: grey USB 2.0, blue USB 3 (5/10/20 Gbps), green
    /// Thunderbolt / USB4 (40/80 Gbps). USB 3 shares one blue so the colour
    /// reads as "data" and never collides with the teal display status; the
    /// exact rate is in the badge text.
    var color: Color {
        switch self {
        case .usb2: return .gray
        case .usb5g, .usb10g, .usb20g: return .blue
        case .tb40, .tb80: return .green
        }
    }
}

// MARK: - Port presentation helpers

extension WidgetSnapshot.PortEntry {
    /// Short type title for the row. Metrics live in pills, not the title, so
    /// this stays one short word/phrase that never wraps.
    var title: String {
        switch status {
        case .empty: return String(localized: "Nothing connected", bundle: _coreLocalizedBundle)
        case .charging: return String(localized: "Charging", bundle: _coreLocalizedBundle)
        case .batteryFull: return String(localized: "Battery full", bundle: _coreLocalizedBundle)
        case .dataDevice: return String(localized: "USB device", bundle: _coreLocalizedBundle)
        case .thunderboltCable: return String(localized: "Thunderbolt", bundle: _coreLocalizedBundle)
        case .displayCable: return String(localized: "Display", bundle: _coreLocalizedBundle)
        case .unknown: return String(localized: "Connected", bundle: _coreLocalizedBundle)
        }
    }

    /// Muted detail line: monitor + mode for a display, else the subtitle.
    var rowDetail: String? {
        if let detail = displayDetail { return detail }
        return subtitle.isEmpty ? nil : subtitle
    }

    /// One-line display detail: "Studio Display · 5K 60Hz", or just the mode
    /// when the monitor name is unknown. Nil when no display.
    var displayDetail: String? {
        guard let mode = displayMode else { return monitorName }
        if let name = monitorName, !name.isEmpty { return "\(name) · \(mode)" }
        return mode
    }

    /// True when there's any pill to show.
    var hasMetrics: Bool {
        linkSpeed != nil || chargerWatts != nil || deviceCount > 0
    }
}

/// The pill column: speed, power, devices, in that order. `wrap` lays them out
/// in a FlowLayout so a narrow card pushes overflow pills onto a new row,
/// instead of compressing them. Rows keep the plain HStack (they have room).
struct PillCluster: View {
    let port: WidgetSnapshot.PortEntry
    var compact: Bool = false
    var wrap: Bool = false

    var body: some View {
        if wrap {
            FlowLayout(spacing: WidgetMetrics.xs) { pills }
        } else {
            HStack(spacing: WidgetMetrics.xs) { pills }
        }
    }

    @ViewBuilder private var pills: some View {
        if let speed = port.linkSpeed {
            LinkSpeedBadge(speed: speed, compact: compact)
        }
        if let watts = port.chargerWatts {
            PowerPill(watts: watts, compact: compact)
        }
        if port.deviceCount > 0 {
            DeviceCountBadge(count: port.deviceCount, compact: compact)
        }
    }
}

// MARK: - Unified port row (used by medium + large)

/// One row shared across sizes: a status accent bar, a small icon, a short
/// title with optional muted detail, and the right-aligned pill column.
/// Mirrors the Calendar widget's event rows (accent bar + title + right time).
struct PortRow: View {
    let port: WidgetSnapshot.PortEntry
    var showDetail: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: WidgetMetrics.s) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(port.status.color)
                .frame(width: 3)

            StatusIcon(name: port.iconName, color: port.status.color, live: port.status.isLive, font: .callout)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: WidgetMetrics.xxs) {
                Text(port.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if showDetail, let detail = port.rowDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: WidgetMetrics.s)

            PillCluster(port: port, compact: compact)
        }
    }
}

// MARK: - Small: single featured port

struct SmallWidgetView: View {
    let port: WidgetSnapshot.PortEntry

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetMetrics.s) {
            WidgetHeader(title: "WhatCable")
            Spacer(minLength: 0)

            // Same accent-bar treatment as the list rows, just larger. No tinted
            // block, so every widget reads as one family.
            HStack(alignment: .top, spacing: WidgetMetrics.s) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(port.status.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: WidgetMetrics.s) {
                    HStack(spacing: WidgetMetrics.s) {
                        StatusIcon(name: port.iconName, color: port.status.color, live: port.status.isLive, font: .title3)
                        Text(port.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    if port.hasMetrics {
                        PillCluster(port: port, wrap: true)
                    }
                    if let detail = port.rowDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Medium: short list of ports

struct MediumWidgetView: View {
    let ports: [WidgetSnapshot.PortEntry]

    var body: some View {
        let shown = Array(ports.prefix(3))
        let overflow = ports.count - shown.count

        VStack(alignment: .leading, spacing: WidgetMetrics.s) {
            WidgetHeader(title: "WhatCable")
            VStack(spacing: WidgetMetrics.s) {
                // Show the detail line only when there's room (1-2 ports).
                ForEach(shown) { port in
                    PortRow(port: port, showDetail: shown.count <= 2)
                }
                if overflow > 0 {
                    OverflowRow(count: overflow)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Compact "+N" line when more ports exist than the rows shown.
struct OverflowRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: WidgetMetrics.xs) {
            Image(systemName: "ellipsis.circle")
            Text("+\(count)")
                .monospacedDigit()
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Large: full port list

struct LargeWidgetView: View {
    let ports: [WidgetSnapshot.PortEntry]

    var body: some View {
        let shown = Array(ports.prefix(6))
        let overflow = ports.count - shown.count
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(icon: "cable.connector.horizontal", title: "WhatCable")
                .padding(.bottom, WidgetMetrics.s)

            ForEach(Array(shown.enumerated()), id: \.element.id) { index, port in
                if index > 0 {
                    Divider().padding(.vertical, WidgetMetrics.xs)
                }
                PortRow(port: port, showDetail: true)
            }
            if overflow > 0 {
                Divider().padding(.vertical, WidgetMetrics.xs)
                OverflowRow(count: overflow)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: WidgetMetrics.s) {
            Image(systemName: "cable.connector.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "No cable data", bundle: _coreLocalizedBundle))
                .font(.headline)
            Text(String(localized: "Open WhatCable to start monitoring.", bundle: _coreLocalizedBundle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Status colour + live mapping

extension WidgetSnapshot.Status {
    var color: Color {
        switch self {
        case .empty: return .secondary
        case .charging: return .yellow
        case .batteryFull: return .green
        case .dataDevice: return .blue
        case .thunderboltCable: return .purple
        case .displayCable: return .teal
        case .unknown: return .orange
        }
    }

    /// True when the port is actively transferring or charging, which drives
    /// the live dot. A full battery or empty port is connected-but-idle.
    var isLive: Bool {
        switch self {
        case .charging, .dataDevice, .thunderboltCable, .displayCable: return true
        case .empty, .batteryFull, .unknown: return false
        }
    }
}

// MARK: - Most interesting port selection

func mostInteresting(_ ports: [WidgetSnapshot.PortEntry]) -> WidgetSnapshot.PortEntry {
    ports.sorted { a, b in
        let aRank = a.status.interestRank
        let bRank = b.status.interestRank
        if aRank != bRank { return aRank > bRank }
        return a.id < b.id
    }.first ?? WidgetSnapshot.PortEntry(
        id: 0,
        portName: "USB-C",
        status: .empty,
        headline: "Nothing connected",
        subtitle: "Plug a cable in to see what it can do.",
        topBullet: nil,
        iconName: "powerplug",
        deviceCount: 0
    )
}

private extension WidgetSnapshot.Status {
    var interestRank: Int {
        switch self {
        case .thunderboltCable: return 5
        case .displayCable: return 4
        case .dataDevice: return 3
        case .charging: return 2
        case .batteryFull: return 2
        case .unknown: return 1
        case .empty: return 0
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder
}

#Preview("Empty", as: .systemMedium) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry(date: Date(), snapshot: nil, configuration: CableWidgetIntent())
}
