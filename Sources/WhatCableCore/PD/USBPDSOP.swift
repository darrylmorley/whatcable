import Foundation

/// Discover Identity response from a USB-PD endpoint, parsed from
/// `IOPortTransportComponentCCUSBPDSOP` services.
public struct USBPDSOP: Identifiable, Hashable {
    public enum Endpoint: String {
        case sop = "SOP"        // Port partner (the connected device/charger)
        case sopPrime = "SOP'"  // Cable's near-side e-marker
        case sopDoublePrime = "SOP''" // Cable's far-side e-marker
        case unknown
    }

    public let id: UInt64
    public let endpoint: Endpoint
    public let parentPortType: Int
    public let parentPortNumber: Int
    public let vendorID: Int
    public let productID: Int
    public let bcdDevice: Int
    public let vdos: [UInt32]
    public let specRevision: Int

    /// HPM controller UUID captured by walking the IOKit parent chain from the
    /// SOP/SOP' node up through `AppleHPMInterfaceType10` to `AppleHPMDeviceHALType3`.
    /// Internal join key only. Never serialised to JSON or text output.
    public let hpmControllerUUID: String?

    public init(
        id: UInt64,
        endpoint: Endpoint,
        parentPortType: Int,
        parentPortNumber: Int,
        vendorID: Int,
        productID: Int,
        bcdDevice: Int,
        vdos: [UInt32],
        specRevision: Int,
        hpmControllerUUID: String? = nil
    ) {
        self.id = id
        self.endpoint = endpoint
        self.parentPortType = parentPortType
        self.parentPortNumber = parentPortNumber
        self.vendorID = vendorID
        self.productID = productID
        self.bcdDevice = bcdDevice
        self.vdos = vdos
        self.specRevision = specRevision
        self.hpmControllerUUID = hpmControllerUUID
    }

    public var portKey: String { "\(parentPortType)/\(parentPortNumber)" }

    /// Canonical in-session join key: normalised UUID when captured, else portKey.
    /// Internal only; never expose in JSON or text output.
    public var canonicalJoinKey: String {
        if let uuid = hpmControllerUUID {
            let n = uuid.replacingOccurrences(of: "-", with: "").lowercased()
            if n.count == 32 { return n }
        }
        return portKey
    }

    public var idHeader: PDVDO.IDHeader? {
        guard let v = vdos.first else { return nil }
        return PDVDO.decodeIDHeader(v)
    }

    /// True when this endpoint's Discover Identity response declares itself a
    /// cable (passive or active). A cable normally answers at SOP' / SOP'',
    /// but a cable plugged in on its own can answer at the SOP/partner
    /// address instead, declaring its cable identity there.
    ///
    /// Also returns true when the DFP field's raw bits match UFP cable-type
    /// values, which some non-compliant real-world firmware emits at SOP with
    /// UFP = undefined. The spec-correct check is `idHeader?.isCable`; use
    /// this property when a best-effort heuristic for identifying cables is
    /// appropriate (e.g. trust-signal softening in CableTrustReport).
    public var identifiesAsCable: Bool {
        guard let header = idHeader else { return false }
        return header.isCable || header.dfpRawValueLooksLikeCable
    }

    /// The Cert Stat VDO is at index 1. Carries the USB-IF-issued XID,
    /// or 0 for cables that haven't gone through certification.
    public var certStatVDO: PDVDO.CertStat? {
        guard endpoint == .sopPrime || endpoint == .sopDoublePrime,
              vdos.count > 1 else { return nil }
        return PDVDO.decodeCertStat(vdos[1])
    }

    /// The Cable VDO is at index 3 (VDO[3] in 1-indexed PD spec terms).
    public var cableVDO: PDVDO.CableVDO? {
        guard endpoint == .sopPrime || endpoint == .sopDoublePrime,
              vdos.count > 3 else { return nil }
        let header = idHeader
        let isActive = header?.ufpProductType == .activeCable
        return PDVDO.decodeCableVDO(vdos[3], isActive: isActive)
    }

    /// Active Cable VDO 2 lives at index 4 and is only present on active
    /// cables. Carries info that doesn't fit in VDO[3]: physical medium
    /// (copper/optical), active element (re-driver/re-timer), thermal
    /// limits, idle-state power, and per-lane / per-protocol support.
    ///
    /// Also decoded when `hasActiveLayoutContradiction` is true: a cable
    /// that mis-reports its ID Header as passive but uses the active-cable
    /// VDO layout in VDO[3] is likely an active cable with a mis-programmed
    /// e-marker. Decoding VDO[4] as Active Cable VDO 2 gives richer info
    /// than leaving it undecoded. The VDO[3] decode is intentionally kept
    /// as-is (passive layout) to avoid raising false trust flags.
    public var activeCableVDO2: PDVDO.ActiveCableVDO2? {
        guard endpoint == .sopPrime || endpoint == .sopDoublePrime,
              vdos.count > 4 else { return nil }
        guard idHeader?.ufpProductType == .activeCable || hasActiveLayoutContradiction else {
            return nil
        }
        return PDVDO.decodeActiveCableVDO2(vdos[4])
    }

    /// True when the cable's ID Header self-reports as passive (Product Type = 3)
    /// but VDO[3] bit 3 is set, which in the Active Cable VDO1 layout (Table 6.43)
    /// means "SOP'' Controller Present." In the Passive Cable VDO layout (Table 6.42),
    /// bits [4:3] are Reserved and the spec requires them to be zero. A genuine
    /// passive cable cannot have this bit set, so its presence is a structural
    /// contradiction: the cable is using a field that only exists in the active layout.
    ///
    /// This is the spec-grounded signal for the CalDigit-style bug reported in
    /// issue #111, where a real active Thunderbolt 4 cable mis-programs its
    /// ID Header as passive while leaving active-layout bits set in VDO[3].
    ///
    /// Always `false` for cables that self-report as active (no contradiction).
    /// Always `false` when VDO[3] is absent.
    public var hasActiveLayoutContradiction: Bool {
        guard endpoint == .sopPrime || endpoint == .sopDoublePrime,
              idHeader?.ufpProductType == .passiveCable,
              let cv = cableVDO else { return false }
        return cv.sopDoubleControllerPresent
    }

    /// True when this identity belongs to the same physical port as `port`.
    ///
    /// UUID-keyed when both sides have a UUID (collision-proof on M3+). Falls
    /// back to `portKey` when either side is missing a UUID (M1/M2, or a
    /// defensive nil from an unusual registry layout). A source that fails to
    /// resolve a UUID while the port has one still matches via portKey fallback.
    public func canonicallyMatches(port: AppleHPMInterface) -> Bool {
        guard let portKey = port.portKey else { return false }
        if let srcUUID = hpmControllerUUID, let portUUID = port.hpmControllerUUID {
            let sn = srcUUID.replacingOccurrences(of: "-", with: "").lowercased()
            let pn = portUUID.replacingOccurrences(of: "-", with: "").lowercased()
            if sn.count == 32 && pn.count == 32 { return sn == pn }
        }
        return self.portKey == portKey
    }

    /// Human-readable PD spec revision (e.g. "PD 3.0"). The raw value is the
    /// IOKit `Specification Revision` property on the SOP / SOP' / SOP'' node,
    /// passed through untransformed. Per `research/iokit-data-sources.md` §7
    /// and the M3 Ultra HPM dump, the mapping is:
    ///
    /// - `2` = PD 2.0 (seen on real e-marked cables and partners back to M1)
    /// - `3` = PD 3.0 (the majority of modern hardware)
    /// - `0` = unset
    /// - `1` = placeholder; in every observed case (M3 Max, M4, M5 customer
    ///   probes) the `Metadata` block is empty, so this is not a real PD
    ///   contract and we return `nil` rather than invent a spec version.
    ///
    /// Note that PD 3.1 hardware still reports `3` here. The 2-bit SpecRev
    /// header field cannot encode 3.1; that revision is distinguished by EPR
    /// PDOs, not by this property.
    public var pdRevisionLabel: String? {
        switch specRevision {
        case 2: return "PD 2.0"
        case 3: return "PD 3.0"
        default: return nil
        }
    }
}
