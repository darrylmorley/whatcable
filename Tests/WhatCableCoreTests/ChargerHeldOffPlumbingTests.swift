import Foundation
import Testing
@testable import WhatCableCore

/// Public issue 672: a charger attached and powered while macOS holds the Mac
/// on battery. One snapshot, three renderers: the CLI text, the CLI JSON and
/// the widget must all carry the snapshot's charger-voltage flag through to
/// the port card, or they keep saying "Connect a charger" next to a charger.
@Suite("Charger held off on battery reaches every renderer")
struct ChargerHeldOffPlumbingTests {
    private func port() -> AppleHPMInterface {
        AppleHPMInterface(
            id: 1, serviceName: "Port-USB-C@1", className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C", portNumber: 1,
            connectionActive: true, activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3"], transportsActive: ["CC"], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil, overcurrentCount: nil,
            pinConfiguration: [:], powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "2"])
    }

    private func source() -> PowerSource {
        let w = PowerOption(voltageMV: 20_000, maxCurrentMA: 4_700, maxPowerMW: 94_000)
        return PowerSource(id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1, options: [w], winning: w)
    }

    /// The #672 shape: live 94W contract, no system adapter, not charging,
    /// SMC says not plugged in (CHCE reads 0 while input is inhibited).
    private func snapshot(voltage: Bool?) -> CableSnapshot {
        CableSnapshot(
            ports: [port()], powerSources: [source()], identities: [], usbDevices: [],
            adapter: nil,
            batteryFullyCharged: false, batteryIsCharging: false, batteryChargeState: .notPluggedIn,
            chargerHeldOffSignal: voltage)
    }

    private func requireJoin(_ s: CableSnapshot) throws {
        let ctx = CableSnapshotContext(snapshot: s)
        try #require(!(ctx.portContexts.first?.portSources.isEmpty ?? true), "fixture source did not join the port")
    }

    private func text(_ s: CableSnapshot) -> String {
        TextFormatter.render(
            ports: s.ports, sources: s.powerSources, identities: s.identities, showRaw: false,
            adapter: s.adapter, batteryFullyCharged: s.batteryFullyCharged,
            batteryIsCharging: s.batteryIsCharging, batteryChargeState: s.batteryChargeState,
            chargerHeldOffSignal: s.chargerHeldOffSignal)
    }

    private func json(_ s: CableSnapshot) throws -> String {
        try JSONFormatter.render(
            ports: s.ports, sources: s.powerSources, identities: s.identities, showRaw: false,
            adapter: s.adapter, batteryFullyCharged: s.batteryFullyCharged,
            batteryIsCharging: s.batteryIsCharging, batteryChargeState: s.batteryChargeState,
            chargerHeldOffSignal: s.chargerHeldOffSignal)
    }

    @Test("CLI text says the charger is connected")
    func textHeldOff() throws {
        let s = snapshot(voltage: true)
        try requireJoin(s)
        let out = text(s)
        #expect(out.contains("Charger connected"), "\(out)")
        #expect(out.contains("Charger offering up to 94W, not in use"), "\(out)")
        #expect(!out.contains("Connect a charger"), "\(out)")
    }

    @Test("CLI JSON says the charger is connected")
    func jsonHeldOff() throws {
        let s = snapshot(voltage: true)
        try requireJoin(s)
        let out = try json(s)
        #expect(out.contains("\"headline\" : \"Charger connected\""), "\(out)")
        #expect(!out.contains("Connect a charger"), "\(out)")
    }

    @Test("Widget headline says the charger is connected, with no wattage pill")
    func widgetHeldOff() {
        let w = WidgetSnapshot(from: snapshot(voltage: true))
        #expect(w.ports.first?.headline == "Charger connected", "\(w.ports.first?.headline ?? "")")
        // The pill reads as power being drawn; nothing is.
        #expect(w.ports.first?.chargerWatts == nil)
    }

    @Test("Without charger supply every renderer keeps 'Connect a charger'", arguments: [false, nil] as [Bool?])
    func staleKeepsTodaysWording(voltage: Bool?) throws {
        let s = snapshot(voltage: voltage)
        #expect(text(s).contains("Connect a charger to identify the cable."))
        #expect(try json(s).contains("Connect a charger to identify the cable."))
        #expect(WidgetSnapshot(from: s).ports.first?.subtitle == "Connect a charger to identify the cable.")
    }

    // MARK: - Widget fallback to the app's value (the sandbox may block the SMC)

    private func cached(supply: Bool?, age: TimeInterval, now: Date) -> WidgetSnapshot {
        WidgetSnapshot(ports: [], timestamp: now.addingTimeInterval(-age), chargerHeldOffSignal: supply)
    }

    @Test("Widget: no live SMC read falls back to the app's fresh value")
    func widgetFallsBackToFreshAppValue() {
        let now = Date()
        #expect(WidgetSnapshot.chargerSupply(live: nil, cached: cached(supply: true, age: 30, now: now), now: now) == true)
        #expect(WidgetSnapshot.chargerSupply(live: nil, cached: cached(supply: false, age: 30, now: now), now: now) == false)
    }

    @Test("Widget: a stale or missing app snapshot gives no value; a live read always wins")
    func widgetFallbackRules() {
        let now = Date()
        // Older than chargeStateFreshness (120 s): not trusted.
        #expect(WidgetSnapshot.chargerSupply(live: nil, cached: cached(supply: true, age: 121, now: now), now: now) == nil)
        // From the future (clock change): not trusted.
        #expect(WidgetSnapshot.chargerSupply(live: nil, cached: cached(supply: true, age: -5, now: now), now: now) == nil)
        #expect(WidgetSnapshot.chargerSupply(live: nil, cached: nil, now: now) == nil)
        #expect(WidgetSnapshot.chargerSupply(live: false, cached: cached(supply: true, age: 30, now: now), now: now) == false)
        #expect(WidgetSnapshot.chargerSupply(live: true, cached: nil, now: now) == true)
    }

    @Test("Widget: the app's value survives the App Group round trip, and old JSON decodes as nil")
    func widgetSnapshotCarriesSupply() throws {
        let w = WidgetSnapshot(from: snapshot(voltage: true))
        #expect(w.chargerHeldOffSignal == true)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(w))
        #expect(decoded.chargerHeldOffSignal == true)
        let old = #"{"ports":[],"timestamp":0}"#
        let legacy = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        #expect(legacy.chargerHeldOffSignal == nil)
    }

    // MARK: - Cross-port: the supply signal is machine-wide

    /// A MagSafe charger held off on battery (corpus m3_macos27.0: 59.8W,
    /// CH0R 0x08), optionally next to a USB-C port with a retained contract.
    private func magSafeSnapshot(staleUSBCContract: Bool) -> CableSnapshot {
        let magSafe = AppleHPMInterface(
            id: 9, serviceName: "Port-MagSafe 3@1", className: "AppleHPMInterfaceType11",
            portDescription: "Port-MagSafe 3@1", portTypeDescription: "MagSafe 3", portNumber: 1,
            connectionActive: true, activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC"], transportsActive: ["CC"], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil, overcurrentCount: nil,
            pinConfiguration: [:], powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "17"])
        let w = PowerOption(voltageMV: 20_000, maxCurrentMA: 2_990, maxPowerMW: 59_800)
        let magSafeSource = PowerSource(id: 9, name: "USB-PD", parentPortType: 17, parentPortNumber: 1,
                                        options: [], winning: w)
        return CableSnapshot(
            ports: [magSafe, port()],
            powerSources: staleUSBCContract ? [magSafeSource, source()] : [magSafeSource],
            identities: [], usbDevices: [],
            adapter: nil,
            batteryFullyCharged: false, batteryIsCharging: false, batteryChargeState: .notPluggedIn,
            chargerHeldOffSignal: true)
    }

    private func headlines(_ s: CableSnapshot) throws -> (widget: [String], text: String, json: String) {
        (WidgetSnapshot(from: s).ports.map(\.headline), text(s), try json(s))
    }

    @Test("MagSafe held off, nothing else live: every renderer labels the MagSafe charger only")
    func magSafeHeldOffEveryRenderer() throws {
        let s = magSafeSnapshot(staleUSBCContract: false)
        let (widget, out, j) = try headlines(s)
        #expect(widget == ["Charger connected", "Connected"], "\(widget)")
        #expect(out.components(separatedBy: "Charger connected").count == 2, "\(out)")
        #expect(j.components(separatedBy: "\"headline\" : \"Charger connected\"").count == 2, "\(j)")
    }

    /// The reviewer's case: the supply is real (MagSafe), but a USB-C port also
    /// holds a contract, so the supply can't be pinned to either port. The
    /// USB-C port must keep today's card; MagSafe gives up its label too,
    /// which is the price of not guessing.
    @Test("Cross-port: a held-off MagSafe charger never relabels a USB-C port with a stale contract, in any renderer")
    func crossPortEveryRenderer() throws {
        let s = magSafeSnapshot(staleUSBCContract: true)
        let ctx = CableSnapshotContext(snapshot: s)
        try #require(ctx.portContexts.allSatisfy { !$0.portSources.isEmpty }, "fixture sources did not join their ports")
        let (widget, out, j) = try headlines(s)
        #expect(!widget.contains("Charger connected"), "\(widget)")
        #expect(WidgetSnapshot(from: s).ports.last?.subtitle == "Connect a charger to identify the cable.")
        #expect(!out.contains("Charger connected") && !out.contains("not in use"), "\(out)")
        #expect(out.contains("Connect a charger to identify the cable."), "\(out)")
        #expect(!j.contains("Charger connected") && !j.contains("not in use"), "\(j)")
        #expect(j.contains("Connect a charger to identify the cable."), "\(j)")
    }

    // MARK: - Only CONNECTED ports count as "another live port"

    /// A second USB-C port, disconnected, still holding a retained contract.
    private func disconnectedStalePort() -> (AppleHPMInterface, PowerSource) {
        let p = AppleHPMInterface(
            id: 2, serviceName: "Port-USB-C@2", className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@2", portTypeDescription: "USB-C", portNumber: 2,
            connectionActive: false, activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2"], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil, overcurrentCount: nil,
            pinConfiguration: [:], powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "2"])
        let w = PowerOption(voltageMV: 20_000, maxCurrentMA: 3_350, maxPowerMW: 67_000)
        return (p, PowerSource(id: 2, name: "USB-PD", parentPortType: 2, parentPortNumber: 2, options: [], winning: w))
    }

    @Test("A disconnected port's retained contract is not a live port")
    func disconnectedPortIsNotLive() {
        let (stale, staleSource) = disconnectedStalePort()
        let keys = PowerSource.portKeysWithLiveContract(ports: [port(), stale], sources: [source(), staleSource])
        #expect(keys == [port().portKey].compactMap { $0 }.reduce(into: Set<String>()) { $0.insert($1) }, "\(keys)")
    }

    @Test("A stale contract on a disconnected port does not block a held-off charger on this port, in any renderer")
    func disconnectedStalePortDoesNotBlock() throws {
        let (stale, staleSource) = disconnectedStalePort()
        let s = CableSnapshot(
            ports: [port(), stale], powerSources: [source(), staleSource], identities: [], usbDevices: [],
            adapter: nil,
            batteryFullyCharged: false, batteryIsCharging: false, batteryChargeState: .notPluggedIn,
            chargerHeldOffSignal: true)
        #expect(WidgetSnapshot(from: s).ports.first?.headline == "Charger connected",
                "\(WidgetSnapshot(from: s).ports.map(\.headline))")
        #expect(text(s).contains("Charger connected"), "\(text(s))")
        #expect(try json(s).contains("\"headline\" : \"Charger connected\""))
    }
}
