import Foundation

/// Decides whether a cable is active or passive from two independent sources
/// rather than one.
///
/// The e-marker's ID Header is a self-report, and issue #111 showed it can be
/// mis-programmed: a real active Thunderbolt 4 cable that declares itself
/// passive. The port controller publishes its own `ActiveCable` verdict, which
/// `AppleHPMInterface.activeCable` already reads. Reading both means a
/// mis-programmed e-marker no longer decides the answer alone.
///
/// A self-report of active is never demoted, whatever the port says. Across
/// the corpus no port contradicts an active self-report in that direction, so
/// a disagreement there would be the port being wrong, not the cable.
public enum CableClassification {
    /// Which of the two readings settled the verdict.
    public enum Source: Hashable, Sendable {
        /// The cable's own ID Header, taken at face value.
        case emarker
        /// The port controller's `ActiveCable` flag, overriding a passive
        /// self-report.
        case portController
        /// VDO[3] uses a field that only exists in the active-cable layout
        /// while the ID Header says passive. See
        /// `USBPDSOP.hasActiveLayoutContradiction`.
        case layoutContradiction
    }

    public struct Resolution: Hashable, Sendable {
        public let type: PDVDO.CableType
        public let source: Source

        public init(type: PDVDO.CableType, source: Source) {
            self.type = type
            self.source = source
        }
    }

    /// Resolve the cable type. Returns nil when the identity carries no
    /// VDO[3], because there is then nothing to classify.
    ///
    /// Promotion needs a genuine passive self-report, because "not active"
    /// also covers a VCONN-Powered Device and an Alternate Mode Adapter.
    ///
    /// The caller must pass the port this identity belongs to. The join is
    /// `USBPDSOP.canonicallyMatches(port:)`. A different port's `ActiveCable`
    /// flag would promote a passive cable here, and machines really do carry
    /// both values at once (`m3_macos26.5` has `USB-C@1` true beside
    /// `MagSafe 3@1` false). There is deliberately no check for it in here:
    /// re-doing the join would hide a caller's wiring bug rather than let it
    /// surface.
    public static func resolve(identity: USBPDSOP, port: AppleHPMInterface?) -> Resolution? {
        guard let cable = identity.cableVDO else { return nil }

        if cable.cableType == .active {
            return Resolution(type: .active, source: .emarker)
        }

        // A controller measurement beats a structural inference drawn from a
        // bit pattern, so the port is checked first when both would fire.
        //
        // Gated on the passive product type, not on `cableType != .active`:
        // `cableType` is decoded from `ufpProductType == .activeCable`, so
        // "not active" also covers a VCONN-Powered Device and an Alternate
        // Mode Adapter, neither of which is a cable claiming to be passive.
        // Two real corpus ports carry an Apple VPD on a controller reporting
        // ActiveCable true. Same gate `hasActiveLayoutContradiction` applies.
        if identity.idHeader?.ufpProductType == .passiveCable, port?.activeCable == true {
            return Resolution(type: .active, source: .portController)
        }
        if identity.hasActiveLayoutContradiction {
            return Resolution(type: .active, source: .layoutContradiction)
        }

        return Resolution(type: .passive, source: .emarker)
    }
}
