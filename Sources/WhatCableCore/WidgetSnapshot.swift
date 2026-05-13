import Foundation

/// Lightweight, pre-computed snapshot of port state for the desktop widget.
///
/// The main app builds this from its live watcher data and writes it to the
/// App Group shared container as JSON. The widget extension reads and
/// decodes it without touching IOKit.
public struct WidgetSnapshot: Codable, Equatable {
    public let ports: [PortEntry]
    public let timestamp: Date

    public init(ports: [PortEntry], timestamp: Date = Date()) {
        self.ports = ports
        self.timestamp = timestamp
    }

    /// One port's display-ready state. Every field is pre-computed by the
    /// main app so the widget just decodes and renders.
    public struct PortEntry: Codable, Equatable, Identifiable {
        /// Stable numeric ID from the underlying USBCPort. Using the
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

        public init(
            id: UInt64,
            portName: String,
            status: Status,
            headline: String,
            subtitle: String,
            topBullet: String?,
            iconName: String,
            deviceCount: Int = 0,
            recentPower: [Double] = []
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
        }

        /// Custom decoder so that JSON written before `deviceCount` was
        /// added (pre-0.9.0) still decodes without error. Swift's
        /// synthesized Decodable ignores init parameter defaults, so
        /// without this a missing key would throw.
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
        }
    }

    /// Mirrors PortSummary.Status but Codable. The widget extension maps
    /// this to colors independently (no SwiftUI in WhatCableCore).
    public enum Status: String, Codable {
        case empty
        case charging
        case dataDevice
        case thunderboltCable
        case displayCable
        case unknown
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

// MARK: - Convenience builders

extension WidgetSnapshot.Status {
    /// Convert from the existing PortSummary.Status enum.
    public init(from summary: PortSummary.Status) {
        switch summary {
        case .empty: self = .empty
        case .charging: self = .charging
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
        case .dataDevice: return "cable.connector"
        case .thunderboltCable: return "bolt.horizontal.fill"
        case .displayCable: return "display"
        case .unknown: return "questionmark.circle"
        }
    }
}
