import Foundation
import Testing
@testable import WhatCableCore

/// Call-site pins for `ChargerWattageSource.resolve`'s `portIsActive`
/// argument (issue #542).
///
/// The parameter being required stops a call site failing to COMPILE, but
/// nothing stopped one passing the literal `true` and reinstating the bug
/// across every surface. These drive the two Core assemblers end to end on a
/// machine whose sole active port is a different port from the one under
/// test, so a hardcoded `true` at either call site turns them red.
///
/// The app-target call sites (`ContentView`, `WidgetDataWriter`) cannot be
/// reached from this test target and stay unpinned.
struct ChargerWattageCallSitePinTests {

    /// The #542 machine shape: one active port with no per-port power source
    /// (so the source-less fallback is live), one INACTIVE port beside it,
    /// and a system adapter reporting 67W.
    private func snapshot() -> CableSnapshot {
        CableSnapshot(
            ports: [activePort(), inactivePort()],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: AdapterInfo(watts: 67, isCharging: true, source: "AC"),
            thunderboltSwitches: [],
            isDesktopMac: false,
            batteryFullyCharged: false,
            batteryIsCharging: true
        )
    }

    @Test("CableSnapshotContext does not hand the adapter reading to an inactive port")
    func cableSnapshotContextGuardsInactivePort() throws {
        let context = CableSnapshotContext(snapshot: snapshot())
        #expect(context.portContexts.count == 2)

        // The active port still gets the fallback. Without this the test
        // could pass on a fixture that never reaches the branch at all.
        let active = try #require(context.portContexts.first)
        #expect(active.chargerWattageSource == .systemAdapterFallback(watts: 67))

        let inactive = try #require(context.portContexts.last)
        #expect(inactive.chargerWattageSource == .unknown)
        #expect(inactive.chargerWattageSource.watts == nil)
    }

    @Test("WidgetSnapshot does not hand the adapter reading to an inactive port")
    func widgetSnapshotGuardsInactivePort() throws {
        let widget = WidgetSnapshot(from: snapshot())
        let entries = widget.ports.filter { $0.id == 1 || $0.id == 2 }
        #expect(entries.count == 2)

        let active = try #require(entries.first { $0.id == 1 })
        #expect(active.chargerWatts == 67)

        let inactive = try #require(entries.first { $0.id == 2 })
        #expect(inactive.chargerWatts == nil)
    }

    // MARK: - Fixtures

    private func activePort() -> AppleHPMInterface { makePort(id: 1, number: 1, active: true) }
    private func inactivePort() -> AppleHPMInterface { makePort(id: 2, number: 2, active: false) }

    private func makePort(id: UInt64, number: Int, active: Bool) -> AppleHPMInterface {
        AppleHPMInterface(
            id: id,
            serviceName: "Port-USB-C@\(number)",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@\(number)",
            portTypeDescription: "USB-C",
            portNumber: number,
            connectionActive: active,
            activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "2"]
        )
    }
}
