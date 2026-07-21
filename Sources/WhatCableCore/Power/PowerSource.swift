import Foundation

/// One PDO (Power Data Object) advertised by the connected source.
public struct PowerOption: Hashable {
    public let voltageMV: Int
    public let maxCurrentMA: Int
    public let maxPowerMW: Int

    public init(voltageMV: Int, maxCurrentMA: Int, maxPowerMW: Int) {
        self.voltageMV = voltageMV
        self.maxCurrentMA = maxCurrentMA
        self.maxPowerMW = maxPowerMW
    }

    public var voltsLabel: String {
        String(format: "%.0fV", Double(voltageMV) / 1000)
    }
    public var ampsLabel: String {
        String(format: "%.2fA", Double(maxCurrentMA) / 1000)
    }
    public var wattsLabel: String {
        String(format: "%.0fW", Double(maxPowerMW) / 1000)
    }
}

/// A power source advertised on a USB-C / MagSafe port (parsed from
/// `IOPortFeaturePowerSource`). One port may have multiple sources
/// (e.g. "USB-PD" + "Brick ID").
public struct PowerSource: Identifiable, Hashable {
    public let id: UInt64
    public let name: String                // "USB-PD", "Brick ID"
    public let parentPortType: Int         // 0x2 = USB-C, 0x11 = MagSafe 3
    public let parentPortNumber: Int
    public let options: [PowerOption]
    public let winning: PowerOption?
    /// HPM controller UUID for this port, captured by walking the IOKit
    /// parent chain from the `IOPortFeaturePowerSource` node up through the
    /// HPM interface to the HPM device (`AppleHPMDevice` / `AppleHPMDeviceHALType3`).
    /// Internal join key only. Never serialised to JSON or text output.
    public let hpmControllerUUID: String?
    /// True when this source was built by `PowerSourceSynthesis` from
    /// `AppleSmartBattery`'s `PortControllerInfo` rather than read from a
    /// real `IOPortFeaturePowerSource` node (issue #401: macOS never
    /// creates that node for USB-C on M1 Pro/Max/Ultra). Defaults to false
    /// so every existing call site and fixture keeps working unchanged.
    public let isSynthesized: Bool

    public init(
        id: UInt64,
        name: String,
        parentPortType: Int,
        parentPortNumber: Int,
        options: [PowerOption],
        winning: PowerOption?,
        hpmControllerUUID: String? = nil,
        isSynthesized: Bool = false
    ) {
        self.id = id
        self.name = name
        self.parentPortType = parentPortType
        self.parentPortNumber = parentPortNumber
        self.options = options
        self.winning = winning
        self.hpmControllerUUID = hpmControllerUUID
        self.isSynthesized = isSynthesized
    }

    public var maxPowerMW: Int {
        if let max = options.map(\.maxPowerMW).max(), max > 0 {
            return max
        }
        return winning?.maxPowerMW ?? 0
    }

    /// Match key joining a power source to its port.
    public var portKey: String { "\(parentPortType)/\(parentPortNumber)" }

    /// Canonical in-session join key: normalised UUID (32 lowercase hex chars)
    /// when one was captured, else `portKey`. Mirrors `AppleHPMInterface.canonicalJoinKey`.
    /// Internal only; never expose in JSON or text output.
    public var canonicalJoinKey: String {
        if let uuid = hpmControllerUUID {
            let normalised = uuid.replacingOccurrences(of: "-", with: "").lowercased()
            if normalised.count == 32 { return normalised }
        }
        return portKey
    }
}

extension PowerSource {
    /// True when this source belongs to the same physical port as `port`.
    ///
    /// Matching is UUID-based when both sides resolved a UUID (M3+, guaranteed
    /// correct: distinct HPM controller dies have distinct UUIDs). Falls back to
    /// `portKey` comparison when either side is missing a UUID (M1/M2, or a
    /// defensive nil from an unusual registry layout). The fallback preserves
    /// existing behaviour on hardware that predates the UUID probe.
    ///
    /// A source that fails to resolve a UUID while the port has one is NOT
    /// silently dropped: `canonicalJoinKey` falls back to `portKey` on the
    /// source side, so it still matches the port's `portKey` fallback, and
    /// the match still fires as long as `ParentPortType/Number` agrees.
    public func canonicallyMatches(port: AppleHPMInterface) -> Bool {
        guard let portKey = port.portKey else { return false }
        // When both sides have a UUID, compare them directly. This is the
        // collision-proof path on M3+.
        if let sourceUUID = hpmControllerUUID,
           let portUUID = port.hpmControllerUUID {
            let sn = sourceUUID.replacingOccurrences(of: "-", with: "").lowercased()
            let pn = portUUID.replacingOccurrences(of: "-", with: "").lowercased()
            if sn.count == 32 && pn.count == 32 { return sn == pn }
        }
        // Fallback: compare portKey strings. Works correctly on M1/M2 where
        // MagSafe and USB-C portKeys already differ by type prefix (17/ vs 2/).
        return self.portKey == portKey
    }

    /// The charging source to represent this port by. Name priority is
    /// USB-PD, then Apple's brick identity ("Brick ID"), then plain Type-C
    /// current ("TypeC", the basic 5V/1.5A-3A a charger delivers over the CC
    /// resistor without PD negotiation, up to ~15W).
    ///
    /// A source that actually holds a winning (negotiated) contract is
    /// preferred over one that does not, even if the latter ranks higher by
    /// name. Otherwise a bare "Brick ID" identity node with no contract would
    /// shadow a winning "TypeC" on the same port (a real non-PD charger),
    /// and the port would read as "no live source" and spin forever. Only
    /// when no source has a contract do we fall back to name priority alone
    /// (a charger still negotiating, or advertised capability).
    public static func preferredChargingSource(in sources: [PowerSource]) -> PowerSource? {
        let priority = ["USB-PD", "Brick ID", "TypeC"]
        // First: a source that holds a winning contract, by name priority.
        for name in priority {
            if let s = sources.first(where: { $0.name == name && ($0.winning?.maxPowerMW ?? 0) > 0 }) {
                return s
            }
        }
        // Then: any source by name priority (no contract yet / advertised only).
        for name in priority {
            if let s = sources.first(where: { $0.name == name }) {
                return s
            }
        }
        return nil
    }

    /// True when these sources expose a negotiated contract: a `winning` PDO
    /// with positive wattage. This does not prove that the system accepted
    /// external power. Callers that make a charging claim must also check the
    /// system adapter and battery state.
    public static func hasLiveChargingContract(in sources: [PowerSource]) -> Bool {
        guard let source = preferredChargingSource(in: sources),
              let winning = source.winning else { return false }
        return winning.maxPowerMW > 0
    }
}

extension AppleHPMInterface {
    public var portKey: String? {
        guard let n = portNumber else { return nil }
        let rawType: Int
        if portTypeDescription?.hasPrefix("MagSafe") == true {
            rawType = 0x11
        } else {
            rawType = rawProperties["PortType"].flatMap { Int($0) } ?? 0x2
        }
        return "\(rawType)/\(n)"
    }

    /// The canonical in-session join key for this port.
    ///
    /// When `hpmControllerUUID` is present, this is the UUID with dashes
    /// stripped and lowercased (32 hex chars) -- the same normalised form
    /// `HPMPortUUIDMap` uses. When absent (M1/M2 or defensive nil), it falls
    /// back to `portKey` so every port still has a key.
    ///
    /// **Internal only.** This value must never appear in JSON, text output,
    /// or the UI. Use `portKey` for all user-visible output.
    ///
    /// Two ports that share the same `@N` suffix but belong to different
    /// physical connectors (MagSafe@1 and USB-C@1, both wired to separate
    /// HPM controller dies) carry distinct UUIDs. Their canonical join keys
    /// are therefore distinct even when their `portKey` values would agree.
    public var canonicalJoinKey: String? {
        if let uuid = hpmControllerUUID {
            let normalised = uuid.replacingOccurrences(of: "-", with: "").lowercased()
            if normalised.count == 32 { return normalised }
        }
        return portKey
    }
}
