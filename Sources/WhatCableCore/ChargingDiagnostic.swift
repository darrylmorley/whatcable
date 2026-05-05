import Foundation
import IOKit
import IOKit.ps

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
    public init?(port: USBCPort, sources: [PowerSource], identities: [PDIdentity]) {
        guard let usbPD = sources.first(where: { $0.name == "USB-PD" }) else {
            return nil // No PD source on this port, no diagnostic to make.
        }
        // MagSafe (and at least some USB-C ports) keep the last negotiated
        // PDO around as cached data even after the charger is unplugged, so
        // a port that is actually idle still looks like it is drawing ~94W.
        // Gate on the port-level ConnectionActive flag instead of trusting
        // the PowerSource node alone.
        guard port.connectionActive == true else { return nil }

        let chargerMaxW = Int((Double(usbPD.maxPowerMW) / 1000).rounded())
        let negotiatedW = usbPD.winning.map { Int((Double($0.maxPowerMW) / 1000).rounded()) }

        let cableMaxW: Int? = identities
            .first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime })?
            .cableVDO?.maxWatts

        // Order of suspicion:
        // 1. If cable rated below charger, cable is the bottleneck.
        // 2. If negotiated below both, the Mac (or current state) limits.
        // 3. Otherwise charger is the ceiling.
        if let cableW = cableMaxW, cableW < chargerMaxW {
            self.bottleneck = .cableLimit(cableW: cableW, chargerW: chargerMaxW)
            self.summary = "Cable is limiting charging speed"
            self.detail = "Charger can deliver up to \(chargerMaxW)W, but this cable is only rated to carry \(cableW)W. Replace the cable to charge faster."
        } else if let n = negotiatedW, n < chargerMaxW - max(5, chargerMaxW / 10),
                  (cableMaxW.map { n < $0 - max(5, $0 / 10) } ?? true) {
            self.bottleneck = .macLimit(negotiatedW: n, chargerW: chargerMaxW, cableW: cableMaxW)
            self.summary = "Charging at \(n)W (charger can do up to \(chargerMaxW)W)"
            self.detail = "Both the charger and cable can do more, but the Mac is currently asking for less. This is normal once the battery is mostly full, or when the system is idle."
        } else if let n = negotiatedW {
            self.bottleneck = .fine(negotiatedW: n)
            self.summary = "Charging well at \(n)W"
            self.detail = "Charger and cable are well-matched."
        } else {
            self.bottleneck = .chargerLimit(chargerW: chargerMaxW)
            self.summary = "Charger advertises up to \(chargerMaxW)W"
            self.detail = "Negotiation hasn't completed yet."
        }
    }
}

/// External power adapter info from the system. Independent of the per-port
/// IOKit views — useful when you want to know what the Mac thinks it's getting.
public enum SystemPower {
    public struct AdapterInfo {
        public let watts: Int?
        public let isCharging: Bool?
        public let source: String?  // "AC" / "Battery"

        public init(watts: Int?, isCharging: Bool?, source: String?) {
            self.watts = watts
            self.isCharging = isCharging
            self.source = source
        }
    }

    public static func currentAdapter() -> AdapterInfo? {
        guard let info = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return AdapterInfo(watts: nil, isCharging: nil, source: nil)
        }
        let w = (info["Watts"] as? NSNumber)?.intValue
        return AdapterInfo(watts: w, isCharging: nil, source: "AC")
    }
}
