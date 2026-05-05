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
    /// a diagnostic. Darwin-only sugar; on Linux callers must pass
    /// `adapter:` explicitly to the core init.
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
