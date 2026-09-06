import Foundation

/// A compact, structured read of the negotiated link speed on a port.
///
/// `PortSummary` already explains the speed in plain-English bullets ("Linked
/// at up to 40 Gb/s", "USB 2.0 only (480 Mbps)"). Those are localized prose,
/// which is fine to read but awkward to render as a small coloured badge or to
/// consume programmatically. `LinkSpeed` is the same fact in a structured form:
/// a coarse `tier` (drives badge colour) plus a short `badge` string.
///
/// Pure value type, no platform imports, so it travels in the widget snapshot
/// and JSON output unchanged.
public struct LinkSpeed: Codable, Equatable, Sendable, Hashable {
    /// Coarse speed bucket, ordered slow → fast. Drives the badge colour in
    /// the widget; the raw value is what gets stored in the snapshot/JSON.
    public enum Tier: String, Codable, Sendable, Hashable, CaseIterable {
        case usb2    // USB 2.0, 480 Mbps
        case usb5g   // USB 3.2 Gen 1, 5 Gbps
        case usb10g  // USB 3.2 Gen 2, 10 Gbps
        case usb20g  // USB 3.2 Gen 2x2, 20 Gbps
        case tb40    // Thunderbolt 3 / 4 or USB4, 40 Gbps
        case tb80    // Thunderbolt 5 / USB4 v2, 80 Gbps
    }

    public let tier: Tier
    /// Short badge text: "480M", "5G", "10G", "20G", "40G", "80G".
    public let badge: String

    public init(tier: Tier, badge: String) {
        self.tier = tier
        self.badge = badge
    }
}
