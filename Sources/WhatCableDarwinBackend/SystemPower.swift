import Foundation
import IOKit
import IOKit.ps
import WhatCableCore

/// External power adapter info from the system. Independent of the per-port
/// IOKit views.
public enum SystemPower {
    public static func currentAdapter() -> AdapterInfo? {
        guard let info = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return AdapterInfo(watts: nil, isCharging: nil, source: nil)
        }
        let w = (info["Watts"] as? NSNumber)?.intValue
        return AdapterInfo(watts: w, isCharging: nil, source: "AC")
    }
}

extension ChargingDiagnostic {
    /// Convenience: fetches the system adapter via IOKit and constructs
    /// a diagnostic. Callers that need a custom adapter (e.g. tests)
    /// can use the core init that takes `adapter:` explicitly.
    public init?(
        port: USBCPort,
        sources: [PowerSource],
        identities: [PDIdentity]
    ) {
        self.init(
            port: port,
            sources: sources,
            identities: identities,
            adapter: SystemPower.currentAdapter()
        )
    }
}

