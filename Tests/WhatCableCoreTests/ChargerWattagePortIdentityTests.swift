import Testing
@testable import WhatCableCore

/// Public issue #542: `resolve`'s source-less fallback was gated only on
/// `activePortCount`, a machine-wide count with no port identity in it. With
/// exactly one active port on the machine, every port being summarised
/// inherited the system adapter reading, including a port that was itself
/// disconnected, so a 67W figure appeared beside an accessory drawing no
/// power. `portIsActive` carries the identity the count lacks.
///
/// Measured on the customer-probe corpus: 462 of the 930 machines that report
/// an adapter wattage have exactly one `connectionActive` port, so the
/// fallback is live on a third of the corpus.
@Suite("Charger wattage port identity")
struct ChargerWattagePortIdentityTests {

    private func adapter(watts: Int) -> AdapterInfo {
        AdapterInfo(watts: watts, isCharging: nil, source: "AC")
    }

    /// The #542 shape: a third-party MagSafe brick's junk analog identifier,
    /// well below the adapter reading, so the issue #154 divert fires.
    private func lowBrickID() -> PowerSource {
        PowerSource(
            id: 1, name: "Brick ID", parentPortType: 0x11, parentPortNumber: 1,
            options: [PowerOption(voltageMV: 5_000, maxCurrentMA: 500, maxPowerMW: 2_500)],
            winning: nil
        )
    }

    @Test("Source-less fallback is suppressed on a port that is not itself active")
    func sourcelessFallbackSuppressedOnInactivePort() {
        let resolved = ChargerWattageSource.resolve(
            portSources: [],
            portIsActive: false,
            activePortCount: 1,
            chargerSourceCount: 0,
            adapter: adapter(watts: 67)
        )
        #expect(resolved == .unknown)
        #expect(resolved.watts == nil)
    }

    @Test("Source-less fallback still fires on the port that is active")
    func sourcelessFallbackFiresOnActivePort() {
        let resolved = ChargerWattageSource.resolve(
            portSources: [],
            portIsActive: true,
            activePortCount: 1,
            chargerSourceCount: 0,
            adapter: adapter(watts: 67)
        )
        #expect(resolved == .systemAdapterFallback(watts: 67))
    }

    /// The Brick ID divert returns the same machine-wide adapter reading, so
    /// it needs the same guard. A Brick ID node persists on a disconnected
    /// port: measured, 22 corpus ports publish one while reporting
    /// `connectionActive == false`, against 507 on active ports, so the node
    /// is not evidence a charger is attached here.
    ///
    /// This is `m4_macos15.7.7_f`'s shape: an active USB-C port charging at
    /// 75W beside an inactive MagSafe port whose only sources are Brick ID,
    /// where both used to resolve to 75W.
    @Test("Brick ID divert is gated on the port's own active state too")
    func brickIDDivertSuppressedOnInactivePort() {
        let resolved = ChargerWattageSource.resolve(
            portSources: [lowBrickID()],
            portIsActive: false,
            activePortCount: 2,
            chargerSourceCount: 1,
            adapter: adapter(watts: 75)
        )
        #expect(resolved == .unknown)
        #expect(resolved.watts == nil)
    }

    @Test("Brick ID divert still fires on the port that is active")
    func brickIDDivertFiresOnActivePort() {
        let resolved = ChargerWattageSource.resolve(
            portSources: [lowBrickID()],
            portIsActive: true,
            activePortCount: 2,
            chargerSourceCount: 1,
            adapter: adapter(watts: 75)
        )
        #expect(resolved == .systemAdapterFallback(watts: 75))
    }

    /// A port with its own negotiated contract owns its wattage regardless of
    /// `connectionActive`. That combination is a real corpus shape: 5 of the
    /// 440 ports whose winning PD contract resolves to a known port report
    /// `ConnectionActive == false` while carrying one.
    @Test("Negotiated wattage is unaffected by the port's active state")
    func portNegotiatedUnaffectedByInactivePort() {
        let usbPD = PowerSource(
            id: 2, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [PowerOption(voltageMV: 20_000, maxCurrentMA: 4_800, maxPowerMW: 96_000)],
            winning: PowerOption(voltageMV: 20_000, maxCurrentMA: 4_800, maxPowerMW: 96_000)
        )
        let resolved = ChargerWattageSource.resolve(
            portSources: [usbPD],
            portIsActive: false,
            activePortCount: 1,
            chargerSourceCount: 1,
            adapter: adapter(watts: 67)
        )
        #expect(resolved == .portNegotiated(watts: 96))
    }
}
