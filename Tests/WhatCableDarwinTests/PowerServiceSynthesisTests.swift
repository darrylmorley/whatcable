import Testing
import Foundation
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

/// Phase 2, item 3. `PowerService.refresh()` read only real IOKit power-source
/// nodes, so on M1 Pro/Max/Ultra (which publish none for USB-C, issue #401)
/// the resistance resolver never saw a charging input and the feature stayed
/// `insufficient` forever. The synthesis existed, in `PowerSourceWatcher`'s
/// instance `refresh()`, where the service could not reach it.
///
/// The live read cannot be unit-tested. What can be tested, and what actually
/// broke, is that both callers now run the SAME gate chain rather than two
/// copies that drift.
@Suite("PowerService synthesis wiring")
struct PowerServiceSynthesisTests {

    @Test("Synthesis declines when a real source already holds a live contract")
    func declinesWhenRealContractExists() {
        let real = PowerSource(
            id: 1, name: "USB-PD",
            parentPortType: PortIdentity.usbCTypeCode, parentPortNumber: 1,
            options: [], winning: PowerOption(voltageMV: 20_000, maxCurrentMA: 4_700, maxPowerMW: 94_000),
            hpmControllerUUID: nil
        )
        let context = PowerSourceSynthesisContext(ports: [], identities: [], positionalPortKeys: { [] })
        let result = PowerSourceWatcher.synthesizedSource(
            realSources: [real], context: context, smcReader: nil, batteryProperties: [:]
        )
        #expect(result == nil)
    }

    @Test("Synthesis declines when no port is active and uncovered")
    func declinesWithNoUncoveredPort() {
        let context = PowerSourceSynthesisContext(ports: [], identities: [], positionalPortKeys: { [] })
        let result = PowerSourceWatcher.synthesizedSource(
            realSources: [], context: context, smcReader: nil, batteryProperties: [:]
        )
        #expect(result == nil)
    }

    @Test("Synthesis declines when there is no battery dictionary at all")
    func declinesOnDesktop() {
        // A desktop has no AppleSmartBattery service, so nothing to
        // synthesize from and no ExternalConnected to read. nil, not a
        // defaulted "connected".
        let context = PowerSourceSynthesisContext(ports: [], identities: [], positionalPortKeys: { [] })
        let result = PowerSourceWatcher.synthesizedSource(
            realSources: [], context: context, smcReader: nil, batteryProperties: nil
        )
        #expect(result == nil)
    }
}
