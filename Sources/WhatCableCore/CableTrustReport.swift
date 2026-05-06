import Foundation

/// Heuristic flags raised against a cable's e-marker data. We trust the
/// e-marker by design, so wording is hedged: "looks unusual," "common
/// counterfeit pattern," never "this cable is fake."
public struct CableTrustReport: Hashable {
    public let flags: [TrustFlag]

    public var isEmpty: Bool { flags.isEmpty }

    public init(flags: [TrustFlag]) {
        self.flags = flags
    }

    /// Build a report from an SOP' / SOP'' e-marker identity. Returns an
    /// empty report when no flags fire so callers can decide whether to
    /// render anything.
    public init(identity: PDIdentity) {
        guard identity.endpoint == .sopPrime || identity.endpoint == .sopDoublePrime else {
            self.flags = []
            return
        }

        var collected: [TrustFlag] = []

        if identity.vendorID == 0 {
            collected.append(.zeroVendorID)
        }

        if let cv = identity.cableVDO {
            for warning in cv.decodeWarnings {
                switch warning {
                case .reservedSpeedEncoding(let bits):
                    collected.append(.reservedSpeedEncoding(bits))
                case .reservedCurrentEncoding(let bits):
                    collected.append(.reservedCurrentEncoding(bits))
                }
            }
        }

        self.flags = collected
    }
}

public enum TrustFlag: Hashable {
    /// E-marker present but vendor ID is zero. Legitimate USB-IF members
    /// have non-zero VIDs, so this is a common counterfeit signature.
    case zeroVendorID

    /// Cable VDO speed field uses a reserved bit pattern (5, 6, or 7).
    /// Real e-marker chips shouldn't emit reserved values.
    case reservedSpeedEncoding(Int)

    /// Cable VDO current field uses the reserved bit pattern (3).
    case reservedCurrentEncoding(Int)

    /// Short identifier suitable for JSON output. Stable across releases.
    public var code: String {
        switch self {
        case .zeroVendorID: return "zeroVendorID"
        case .reservedSpeedEncoding: return "reservedSpeedEncoding"
        case .reservedCurrentEncoding: return "reservedCurrentEncoding"
        }
    }

    /// One-line headline for UI surfacing.
    public var title: String {
        switch self {
        case .zeroVendorID:
            return "E-marker reports no vendor identity"
        case .reservedSpeedEncoding:
            return "E-marker uses a reserved data-speed value"
        case .reservedCurrentEncoding:
            return "E-marker uses a reserved current-rating value"
        }
    }

    /// Longer hedged explanation, safe to show next to the title.
    public var detail: String {
        switch self {
        case .zeroVendorID:
            return "Legitimate USB-IF members ship cables with a non-zero vendor ID. A zeroed VID is a common counterfeit signature."
        case .reservedSpeedEncoding(let bits):
            return "The cable's e-marker reports speed value \(bits), which is reserved by the USB-PD spec. Real e-marker chips should not emit reserved values."
        case .reservedCurrentEncoding(let bits):
            return "The cable's e-marker reports current value \(bits), which is reserved by the USB-PD spec. Real e-marker chips should not emit reserved values."
        }
    }
}
