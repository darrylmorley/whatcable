import Foundation

/// Discover Identity response from a USB-PD endpoint, parsed from
/// `IOPortTransportComponentCCUSBPDSOP` services.
public struct PDIdentity: Identifiable, Hashable {
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

    public init(
        id: UInt64,
        endpoint: Endpoint,
        parentPortType: Int,
        parentPortNumber: Int,
        vendorID: Int,
        productID: Int,
        bcdDevice: Int,
        vdos: [UInt32],
        specRevision: Int
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
    }

    public var portKey: String { "\(parentPortType)/\(parentPortNumber)" }

    public var idHeader: PDVDO.IDHeader? {
        guard let v = vdos.first else { return nil }
        return PDVDO.decodeIDHeader(v)
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
    public var activeCableVDO2: PDVDO.ActiveCableVDO2? {
        guard endpoint == .sopPrime || endpoint == .sopDoublePrime,
              vdos.count > 4,
              idHeader?.ufpProductType == .activeCable else { return nil }
        return PDVDO.decodeActiveCableVDO2(vdos[4])
    }
}
