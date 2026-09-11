import Foundation

/// Cable/link data from Apple's CIO (Thunderbolt) transport controller.
///
/// These properties come from `IOPortTransportStateCIO`, which appears
/// dynamically when a Thunderbolt link is active. Most fields in
/// `PORT_CS_18` are cable-state values populated per-connection from
/// VDM exchange during link bring-up, not static port capabilities.
///
/// `negotiatedLinkSpeed` is the controller's claim about the cable and
/// peer pair, a floor on cable capability that can sit above the trained
/// lane (see `research/cio-value-mappings.md`). `generation` is the
/// downstream controller's era, fixed by its (Vendor ID, Device ID).
/// `cableGeneration` is the cable's Gen 4 capability, corpus-confirmed
/// but not yet register-proven. `asymmetricModeSupported` is a cable
/// property (Cable Asymmetric Support from PORT_CS_18.CSA), still
/// unsurfaced.
public struct CIOCableCapability: Identifiable, Hashable, Sendable {
    public let id: UInt64
    /// Port correlation key matching `PowerSource.portKey`.
    public let portKey: String

    /// Cable capability tier: cable Gen 4 capability from `PORT_CS_18.CG4`
    /// (bit 21), populated via VDM during link bring-up; 1 = cable is
    /// Gen 3 only, 2 = cable supports Gen 4. The register mechanism is
    /// vendor-confirmed (Intel `tbtools` + a real `tbdump`: `PORT_CS_18`
    /// bit 20 = Cable Gen 3 Support, bit 21 = Cable Gen 4 Support, read
    /// from the cable e-marker). Apple's value mapping is corpus-confirmed
    /// by the Studio Display cable swap (43 ports, 22 passive reading 1,
    /// 21 active reading 2): correlational, not a register proof, so
    /// still no user-facing label until that proof exists. This is a
    /// DISTINCT field from `linkTrainingMode` (the cable capability
    /// ceiling vs the trained-link result; settled 2026-07-22). The
    /// earlier "unstable across successive reads" note is RETRACTED (118
    /// ports read by two probes, zero mismatches).
    public let cableGeneration: Int?
    /// The controller's claim about the cable and peer pair (IOKit
    /// `CableSpeed`), a floor on cable capability that can sit above the
    /// trained lane: 31 of 378 replayed ports read a CIO tier above the
    /// port's own lane, and 13 of the 70 code-4 ports have an endpoint
    /// that cannot run 80 Gbps at all. What the register physically
    /// measures is an open question (see `research/cio-value-mappings.md`).
    /// Confirmed tiers: 2 = 20 Gbps (TB3), 3 = 40 Gbps (TB4), 4 = 80 Gbps
    /// (TB5); 0 means no rate reported (5 ports). Named
    /// `negotiatedLinkSpeed` rather than the raw IOKit key name
    /// (`CableSpeed`) so the "floor, not a cap" meaning survives at
    /// every call site; the JSON output key stays `"cableSpeed"` for
    /// schema stability (see `JSONFormatter`'s `CIOCableCapabilityDTO`).
    public let negotiatedLinkSpeed: Int?
    /// The downstream controller's era, fixed by the CIO node's (Vendor
    /// ID, Device ID) on 397 of the 398 ports that publish one: 1 =
    /// TB1/TB2 controllers, 2 = TB3, 3 = TB4/USB4. It varies within one
    /// machine on 42 of 74 multi-port folders, which a host property
    /// cannot do. Kept raw and unlabelled because the Device ID already
    /// gives it.
    public let generation: Int?
    /// Cable asymmetric-mode capability from `PORT_CS_18.CSA` (bit 22).
    /// This is a cable-state field populated per-connection from VDM
    /// exchange during link bring-up, not a static port capability.
    /// Different cables on the same port produce different values (true
    /// x345, false x64, absent x3). On Titan Ridge endpoints the better
    /// cable is the one reporting false, so the cleared string "Cable
    /// supports asymmetric mode" would read backwards to a Studio
    /// Display owner who upgraded their cable. Reaches three sinks
    /// today: JSON, the cable-report markdown, and the bench report's
    /// CIO row. Stays unsurfaced until the direction is understood.
    public let asymmetricModeSupported: Bool?
    /// True on 14 of 412 ports, exactly the ports with `generation == 1`
    /// (TB1/TB2 products); all 103 Titan Ridge and 56 Alpine Ridge ports
    /// read false. The earlier "true for TB3" reading stays disproven.
    public let legacyAdapter: Bool?
    /// The tier the link actually trained to (the result of link bring-up),
    /// settled 2026-07-22 as a field DISTINCT from `cableGeneration`:
    /// `linkTrainingMode <= cableGeneration` in every sample, i.e. the
    /// trained result never exceeds the cable capability. Concept matches
    /// the Linux driver's link generation (derived from the trained
    /// per-lane speed). The exact 1/2 value encoding is the same open
    /// question as `cableGeneration`'s. Do not surface a label yet.
    public let linkTrainingMode: Int?

    /// HPM controller UUID captured by walking the IOKit parent chain.
    /// Internal join key only. Never serialised to JSON or text output.
    public let hpmControllerUUID: String?

    public init(
        id: UInt64,
        portKey: String,
        cableGeneration: Int?,
        negotiatedLinkSpeed: Int?,
        generation: Int?,
        asymmetricModeSupported: Bool?,
        legacyAdapter: Bool?,
        linkTrainingMode: Int?,
        hpmControllerUUID: String? = nil
    ) {
        self.id = id
        self.portKey = portKey
        self.cableGeneration = cableGeneration
        self.negotiatedLinkSpeed = negotiatedLinkSpeed
        self.generation = generation
        self.asymmetricModeSupported = asymmetricModeSupported
        self.legacyAdapter = legacyAdapter
        self.linkTrainingMode = linkTrainingMode
        self.hpmControllerUUID = hpmControllerUUID
    }

    /// Canonical in-session join key: normalised UUID when captured, else portKey.
    /// Internal only; never expose in JSON or text output.
    public var canonicalJoinKey: String {
        if let uuid = hpmControllerUUID {
            let n = uuid.replacingOccurrences(of: "-", with: "").lowercased()
            if n.count == 32 { return n }
        }
        return portKey
    }

    /// True when this capability record belongs to the same physical port as `port`.
    /// UUID-keyed when both sides have a UUID, portKey fallback otherwise.
    public func canonicallyMatches(port: AppleHPMInterface) -> Bool {
        guard let portKey = port.portKey else { return false }
        if let srcUUID = hpmControllerUUID, let portUUID = port.hpmControllerUUID {
            let sn = srcUUID.replacingOccurrences(of: "-", with: "").lowercased()
            let pn = portUUID.replacingOccurrences(of: "-", with: "").lowercased()
            if sn.count == 32 && pn.count == 32 { return sn == pn }
        }
        return self.portKey == portKey
    }

    /// Human-readable speed label for a confirmed `negotiatedLinkSpeed`
    /// value, or `nil` when the code is unrecognised.
    ///
    /// Maps the CIO negotiated-link-rate codes confirmed by real probes
    /// spanning TB3, TB4, and TB5 (2 = 20 Gbps, 3 = 40 Gbps,
    /// 4 = 80 Gbps; see `research/cio-value-mappings.md`). Returns
    /// `nil` for unknown codes so callers can fall back to a generic
    /// bullet rather than leaking raw IOKit numbers into user-facing
    /// text.
    ///
    /// The input is the negotiated rate, a floor on cable capability,
    /// not a cap (issue #393). The label names the tier of the
    /// controller's claim; `PortSummary` only prints it once the trained
    /// lane corroborates that claim, so that split lives there, not here.
    public static func speedLabel(for cableSpeed: Int) -> String? {
        switch cableSpeed {
        case 2: return String(localized: "20 Gbps capable", bundle: _coreLocalizedBundle)
        case 3: return String(localized: "40 Gbps capable", bundle: _coreLocalizedBundle)
        case 4: return String(localized: "80 Gbps capable", bundle: _coreLocalizedBundle)
        default: return nil
        }
    }
}
