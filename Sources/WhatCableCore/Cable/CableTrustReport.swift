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
    ///
    /// - Parameters:
    ///   - identity: the cable's e-marker (SOP' / SOP'') Discover Identity.
    ///   - partner: the same port's SOP/partner identity, when present. A
    ///     cable plugged in on its own can answer at the SOP address and
    ///     declare a registered vendor there even though its e-marker reads
    ///     a blank vendor ID. In that case the cable does carry a vendor
    ///     identity, so the blank-e-marker reading is a neutral note, not a
    ///     counterfeit signal. See DAR-140 / issue #250.
    public init(identity: USBPDSOP, partner: USBPDSOP? = nil) {
        guard identity.endpoint == .sopPrime || identity.endpoint == .sopDoublePrime else {
            self.flags = []
            return
        }

        var collected: [TrustFlag] = []

        // Does the plug (SOP partner) declare itself a cable with a
        // USB-IF-registered vendor ID? Only then does the partner identity
        // belong to *this cable* (not a connected device), so only then can
        // it soften a blank e-marker VID. We require registration, not just
        // a non-zero value: a registered VID is real proof of a known maker.
        let partnerIsRegisteredCable = partner.map {
            $0.identifiesAsCable && $0.vendorID != 0 && VendorDB.isRegistered($0.vendorID)
        } ?? false

        // Vendor ID handling:
        //   0x0000 — no value. A blank e-marker VID is a common counterfeit
        //            signature, so it fires zeroVendorID — UNLESS the plug
        //            identifies the same cable as a registered vendor, in
        //            which case it's a neutral note (the cable does have an
        //            identity, just at a different address).
        //   0xFFFF — spec-defined "vendor opted out of USB-IF
        //            registration." Legitimate per spec, so this is
        //            neutral metadata, not a trust flag. Surfaced via
        //            the vendor-name path (see VendorDB.name) so the
        //            UI describes it without flagging a warning.
        //   anything else not in the bundled USB-IF list — fires
        //            vidNotInUSBIFList (H3).
        if identity.vendorID == 0 {
            if partnerIsRegisteredCable, let partner {
                collected.append(.eMarkerVIDBlankRegisteredPartner(partner.vendorID))
            } else {
                collected.append(.zeroVendorID)
            }
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
    /// How strongly a flag should read. A `.warning` is a real "this looks
    /// unusual" signal; a `.note` is neutral, informational context that
    /// happens to live in the same list (so the UI can render it calmly
    /// rather than as an alarm).
    public enum Severity: Hashable {
        case note
        case warning
    }

    /// E-marker present but vendor ID is zero. Legitimate USB-IF members
    /// have non-zero VIDs, so this is a common counterfeit signature.
    ///
    /// Note: the *spec-defined* sentinel `0xFFFF` (vendor opted out of
    /// USB-IF registration) is intentionally NOT a TrustFlag — it's
    /// allowed by the PD spec, so flagging it as a warning would be
    /// misleading. It's surfaced via VendorDB / the cable report instead.
    case zeroVendorID

    /// The e-marker's vendor ID is blank, but the plug (SOP partner)
    /// identifies this same cable as a USB-IF-registered vendor. The cable
    /// does carry a vendor identity, so this is a neutral note, not a
    /// counterfeit signal. Associated value is the plug's registered VID.
    case eMarkerVIDBlankRegisteredPartner(Int)

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

    /// How strongly this flag should read in the UI. Everything is a
    /// `.warning` except the explicitly neutral notes.
    public var severity: Severity {
        switch self {
        case .eMarkerVIDBlankRegisteredPartner:
            return .note
        default:
            return .warning
        }
    }

    /// Short identifier suitable for JSON output. Stable across releases.
    public var code: String {
        switch self {
        case .zeroVendorID: return "zeroVendorID"
        case .eMarkerVIDBlankRegisteredPartner: return "eMarkerVIDBlankRegisteredPartner"
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
            return String(localized: "E-marker reports no vendor identity", bundle: _coreLocalizedBundle)
        case .eMarkerVIDBlankRegisteredPartner:
            return String(localized: "E-marker vendor ID is blank, but the cable is identified at the connector", bundle: _coreLocalizedBundle)
        case .reservedSpeedEncoding:
            return String(localized: "E-marker uses a reserved data-speed value", bundle: _coreLocalizedBundle)
        case .reservedCurrentEncoding:
            return String(localized: "E-marker uses a reserved current-rating value", bundle: _coreLocalizedBundle)
        case .reservedCableLatencyEncoding:
            return String(localized: "E-marker uses a reserved cable-latency value", bundle: _coreLocalizedBundle)
        case .vidNotInUSBIFList:
            return String(localized: "Vendor ID isn't in USB-IF's published list", bundle: _coreLocalizedBundle)
        case .invalidVDOVersion:
            return String(localized: "E-marker uses an invalid VDO version", bundle: _coreLocalizedBundle)
        case .invalidCableTermination:
            return String(localized: "E-marker uses an invalid cable-termination value", bundle: _coreLocalizedBundle)
        case .eprClaimedWithLowMaxVoltage:
            return String(localized: "E-marker claims EPR support but reports only 20V max VBUS", bundle: _coreLocalizedBundle)
        }
    }

    /// Longer hedged explanation, safe to show next to the title.
    public var detail: String {
        switch self {
        case .zeroVendorID:
            return String(localized: "Legitimate USB-IF members ship cables with a non-zero vendor ID. A zeroed VID is a common counterfeit signature.", bundle: _coreLocalizedBundle)
        case .eMarkerVIDBlankRegisteredPartner(let vid):
            let hex = String(format: "0x%04X", vid)
            let vendor = VendorDB.name(for: vid) ?? hex
            return String(localized: "The cable's e-marker chip reports a blank vendor ID, but the connector identifies the cable as \(vendor) (\(hex)), a USB-IF-registered vendor. A blank e-marker VID by itself is common on genuine passive cables, so it isn't a sign of a problem.", bundle: _coreLocalizedBundle)
        case .reservedSpeedEncoding(let bits):
            return String(localized: "The cable's e-marker reports speed value \(bits), which is reserved by the USB-PD spec. Real e-marker chips should not emit reserved values.", bundle: _coreLocalizedBundle)
        case .reservedCurrentEncoding(let bits):
            return String(localized: "The cable's e-marker reports current value \(bits), which is reserved by the USB-PD spec. Real e-marker chips should not emit reserved values.", bundle: _coreLocalizedBundle)
        case .reservedCableLatencyEncoding(let bits):
            return String(localized: "The cable's e-marker reports cable-latency value \(bits), which is reserved by the USB-PD spec for this cable type. Real e-marker chips should not emit reserved values.", bundle: _coreLocalizedBundle)
        case .vidNotInUSBIFList(let vid):
            let hex = String(format: "0x%04X", vid)
            return String(localized: "The cable's e-marker reports vendor \(hex), which isn't in our bundled USB-IF list. The number could be unassigned, copied, or assigned after the bundled list was generated. On its own this isn't proof of a problem, but on a clone cable it often appears alongside other inconsistencies.", bundle: _coreLocalizedBundle)
        case .invalidVDOVersion(let bits):
            return String(localized: "The cable's e-marker reports VDO version \(bits), which is reserved or marked Invalid by the USB-PD spec for this cable type. Real e-marker silicon should not emit Invalid version values.", bundle: _coreLocalizedBundle)
        case .invalidCableTermination(let bits):
            return String(localized: "The cable's e-marker reports cable termination \(bits), which the USB-PD spec marks as Invalid for this cable type. Mis-flashed e-markers commonly disagree with the cable's actual physical wiring here.", bundle: _coreLocalizedBundle)
        case .eprClaimedWithLowMaxVoltage:
            return String(localized: "The cable's e-marker advertises EPR Capable, but reports its Max VBUS Voltage as 20V. EPR operation needs 48V or 50V VBUS, so the two fields contradict each other.", bundle: _coreLocalizedBundle)
        }
    }
}
