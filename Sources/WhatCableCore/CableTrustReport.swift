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

        // Vendor ID handling:
        //   0x0000 — no value; suspicious blank, fires zeroVendorID.
        //   0xFFFF — spec-defined "vendor opted out of USB-IF
        //            registration." Legitimate per spec, so this is
        //            neutral metadata, not a trust flag. Surfaced via
        //            the vendor-name path (see VendorDB.name) so the
        //            UI describes it without flagging a warning.
        //   anything else not in the bundled USB-IF list — fires
        //            vidNotInUSBIFList (H3).
        if identity.vendorID == 0 {
            collected.append(.zeroVendorID)
        } else if identity.vendorID == 0xFFFF {
            // Intentionally no flag.
        } else if !VendorDB.isRegistered(identity.vendorID) {
            collected.append(.vidNotInUSBIFList(identity.vendorID))
        }

        if let cv = identity.cableVDO {
            for warning in cv.decodeWarnings {
                switch warning {
                case .reservedSpeedEncoding(let bits):
                    collected.append(.reservedSpeedEncoding(bits))
                case .reservedCurrentEncoding(let bits):
                    collected.append(.reservedCurrentEncoding(bits))
                case .reservedCableLatencyEncoding(let bits):
                    collected.append(.reservedCableLatencyEncoding(bits))
                case .invalidVDOVersion(let bits):
                    collected.append(.invalidVDOVersion(bits))
                case .invalidCableTermination(let bits):
                    collected.append(.invalidCableTermination(bits))
                case .eprClaimedWithLowMaxVoltage:
                    collected.append(.eprClaimedWithLowMaxVoltage)
                }
            }
        }

        self.flags = collected
    }
}

public enum TrustFlag: Hashable {
    /// E-marker present but vendor ID is zero. Legitimate USB-IF members
    /// have non-zero VIDs, so this is a common counterfeit signature.
    ///
    /// Note: the *spec-defined* sentinel `0xFFFF` (vendor opted out of
    /// USB-IF registration) is intentionally NOT a TrustFlag — it's
    /// allowed by the PD spec, so flagging it as a warning would be
    /// misleading. It's surfaced via VendorDB / the cable report instead.
    case zeroVendorID

    /// Cable VDO speed field uses a reserved bit pattern (5, 6, or 7).
    /// Real e-marker chips shouldn't emit reserved values.
    case reservedSpeedEncoding(Int)

    /// Cable VDO current field uses the reserved bit pattern (3).
    case reservedCurrentEncoding(Int)

    /// Cable VDO cable-latency field uses a reserved value. Bounds depend
    /// on cable type (passive: 0000 / 1001..1111; active: 0000 /
    /// 1011..1111).
    case reservedCableLatencyEncoding(Int)

    /// E-marker reports a non-zero vendor ID that isn't in any of our
    /// known sources (the curated VendorDB or the bundled USB-IF list).
    /// Could be a post-bundle assignment, a copied number, or a typo
    /// from a knock-off chip programmer. Hedged accordingly.
    case vidNotInUSBIFList(Int)

    /// Cable VDO Version (bits 23..21) is a value the spec marks as
    /// Invalid for this cable type.
    case invalidVDOVersion(Int)

    /// Cable Termination (bits 12..11) is a value the spec marks as
    /// Invalid for this cable type.
    case invalidCableTermination(Int)

    /// Passive cable claims EPR Capable but reports only 20V Max VBUS.
    /// The two fields contradict each other: EPR requires 48V or 50V.
    case eprClaimedWithLowMaxVoltage

    /// Short identifier suitable for JSON output. Stable across releases.
    public var code: String {
        switch self {
        case .zeroVendorID: return "zeroVendorID"
        case .reservedSpeedEncoding: return "reservedSpeedEncoding"
        case .reservedCurrentEncoding: return "reservedCurrentEncoding"
        case .reservedCableLatencyEncoding: return "reservedCableLatencyEncoding"
        case .vidNotInUSBIFList: return "vidNotInUSBIFList"
        case .invalidVDOVersion: return "invalidVDOVersion"
        case .invalidCableTermination: return "invalidCableTermination"
        case .eprClaimedWithLowMaxVoltage: return "eprClaimedWithLowMaxVoltage"
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
        case .reservedCableLatencyEncoding:
            return "E-marker uses a reserved cable-latency value"
        case .vidNotInUSBIFList:
            return "Vendor ID isn't in USB-IF's published list"
        case .invalidVDOVersion:
            return "E-marker uses an invalid VDO version"
        case .invalidCableTermination:
            return "E-marker uses an invalid cable-termination value"
        case .eprClaimedWithLowMaxVoltage:
            return "E-marker claims EPR support but reports only 20V max VBUS"
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
        case .reservedCableLatencyEncoding(let bits):
            return "The cable's e-marker reports cable-latency value \(bits), which is reserved by the USB-PD spec for this cable type. Real e-marker chips should not emit reserved values."
        case .vidNotInUSBIFList(let vid):
            let hex = String(format: "0x%04X", vid)
            return "The cable's e-marker reports vendor \(hex), which isn't in our bundled USB-IF list. The number could be unassigned, copied, or assigned after the bundled list was generated. On its own this isn't proof of a problem, but on a clone cable it often appears alongside other inconsistencies."
        case .invalidVDOVersion(let bits):
            return "The cable's e-marker reports VDO version \(bits), which is reserved or marked Invalid by the USB-PD spec for this cable type. Real e-marker silicon should not emit Invalid version values."
        case .invalidCableTermination(let bits):
            return "The cable's e-marker reports cable termination \(bits), which the USB-PD spec marks as Invalid for this cable type. Mis-flashed e-markers commonly disagree with the cable's actual physical wiring here."
        case .eprClaimedWithLowMaxVoltage:
            return "The cable's e-marker advertises EPR Capable, but reports its Max VBUS Voltage as 20V. EPR operation needs 48V or 50V VBUS, so the two fields contradict each other."
        }
    }
}
