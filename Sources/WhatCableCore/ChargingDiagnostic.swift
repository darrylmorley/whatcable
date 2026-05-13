import Foundation

/// Compares charger output, cable rating, and currently negotiated PDO to
/// identify the bottleneck — the "why is my Mac charging slowly?" answer.
public struct ChargingDiagnostic {
    public enum Bottleneck: Hashable {
        case noCharger
        case chargerLimit(chargerW: Int)
        case cableLimit(cableW: Int, chargerW: Int)
        case macLimit(negotiatedW: Int, chargerW: Int, cableW: Int?)
        case fine(negotiatedW: Int)
    }

    public let bottleneck: Bottleneck
    public let summary: String
    public let detail: String

    public var isWarning: Bool {
        switch bottleneck {
        case .fine: return false
        default: return true
        }
    }
}

extension ChargingDiagnostic {
    public init?(
        port: USBCPort,
        sources: [PowerSource],
        identities: [PDIdentity],
        adapter: AdapterInfo? = nil
    ) {
        // `adapter` is retained for API compatibility but intentionally unused.
        // Earlier versions used `IOPSCopyExternalPowerAdapterDetails().Watts`
        // as a fallback when the per-port USB-PD source had no winning PDO.
        // That value is system-wide, so on a Mac with two ports each carrying
        // a different charger (e.g. an 87W adapter on @1 and a 30W power bank
        // on @2), the adapter watts for @1 leaked into @2's diagnostic and
        // claimed "Charging well at 87W" on the 30W port. See issue #46.
        _ = adapter

        guard let source = PowerSource.preferredChargingSource(in: sources) else {
            return nil // No USB-PD or MagSafe Brick ID source on this port.
        }
        // MagSafe (and at least some USB-C ports) keep the last negotiated
        // PDO around as cached data even after the charger is unplugged, so
        // a port that is actually idle still looks like it is drawing ~94W.
        // Gate on the port-level ConnectionActive flag instead of trusting
        // the PowerSource node alone.
        guard port.connectionActive == true else { return nil }

        let chargerMaxW = Int((Double(source.maxPowerMW) / 1000).rounded())
        let negotiatedW = source.winning.map { Int((Double($0.maxPowerMW) / 1000).rounded()) }

        // No real per-port wattage to report. Don't fabricate one from
        // system-wide signals, and don't render "Charging well at 0W" if a
        // winning PDO rounds to zero. The charging block simply doesn't
        // appear for this port.
        if chargerMaxW <= 0 && (negotiatedW ?? 0) <= 0 {
            return nil
        }

        let cableMaxW: Int? = identities
            .first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime })?
            .cableVDO?.maxWatts

        // Order of suspicion:
        // 1. If cable rated below charger, cable is the bottleneck.
        // 2. If negotiated below both, the Mac (or current state) limits.
        // 3. Otherwise charger is the ceiling.
        if let cableW = cableMaxW, cableW < chargerMaxW {
            self.bottleneck = .cableLimit(cableW: cableW, chargerW: chargerMaxW)
            self.summary = String(localized: "Cable is limiting charging speed", bundle: .module)
            self.detail = String(localized: "Charger can deliver up to \(chargerMaxW)W, but this cable is only rated to carry \(cableW)W. Replace the cable to charge faster.", bundle: .module)
        } else if let n = negotiatedW, n < chargerMaxW - max(5, chargerMaxW / 10),
                  (cableMaxW.map { n < $0 - max(5, $0 / 10) } ?? true) {
            self.bottleneck = .macLimit(negotiatedW: n, chargerW: chargerMaxW, cableW: cableMaxW)
            self.summary = String(localized: "Charging at \(n)W (charger can do up to \(chargerMaxW)W)", bundle: .module)
            self.detail = String(localized: "Both the charger and cable can do more, but the Mac is currently asking for less. This is normal once the battery is mostly full, or when the system is idle.", bundle: .module)
        } else if let n = negotiatedW {
            self.bottleneck = .fine(negotiatedW: n)
            self.summary = String(localized: "Charging well at \(n)W", bundle: .module)
            self.detail = String(localized: "Charger and cable are well-matched.", bundle: .module)
        } else {
            self.bottleneck = .chargerLimit(chargerW: chargerMaxW)
            self.summary = String(localized: "Charger advertises up to \(chargerMaxW)W", bundle: .module)
            self.detail = String(localized: "Negotiation hasn't completed yet.", bundle: .module)
        }
    }
}
