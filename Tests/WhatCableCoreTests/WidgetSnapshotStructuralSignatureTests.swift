import Foundation
import Testing
@testable import WhatCableCore

/// Tests for `WidgetSnapshot.structuralSignature`.
///
/// Support report: with power flowing, `WidgetDataWriter` was rewriting
/// `widgetSnapshot.json` (the App Group cache the widget extension reads)
/// roughly once a second instead of the designed "on structural change, plus
/// a 60s heartbeat". Root cause: `PowerTelemetryContributor` polls at 1 Hz
/// and its readings wobble by tenths of a watt on every tick; the old dedup
/// compared full `ports`/`powerState` values (sample arrays included), which
/// never matched twice in a row, so every tick looked like a change worth
/// writing.
///
/// `structuralSignature` exists so a comparison can ignore the wobbling
/// magnitudes (`recentPower`, `systemPowerInWatts`, per-port `watts` /
/// `recentSamples`, `recentSystemPower`) while still catching every real
/// shape change (a port appearing/disappearing, status, headline, charger
/// wattage, link speed, display info, presence of a power reading at all).
@Suite("WidgetSnapshot.structuralSignature")
struct WidgetSnapshotStructuralSignatureTests {

    // MARK: - Fixtures

    private func makePort(
        id: UInt64 = 1,
        portName: String = "Port-USB-C@1",
        status: WidgetSnapshot.Status = .charging,
        headline: String = "Charging",
        subtitle: String = "65W adapter",
        chargerWatts: Int? = 65,
        recentPower: [Double] = [],
        portKey: String? = "port-1",
        displayMode: String? = nil,
        monitorName: String? = nil,
        displayCount: Int = 0,
        accessoryName: String? = nil
    ) -> WidgetSnapshot.PortEntry {
        WidgetSnapshot.PortEntry(
            id: id,
            portName: portName,
            status: status,
            headline: headline,
            subtitle: subtitle,
            topBullet: nil,
            iconName: status.iconName,
            deviceCount: 0,
            recentPower: recentPower,
            portKey: portKey,
            chargerWatts: chargerWatts,
            linkSpeed: nil,
            displayMode: displayMode,
            monitorName: monitorName,
            displayCount: displayCount,
            accessoryName: accessoryName
        )
    }

    private func makePowerState(
        batteryPercent: Int? = 80,
        isCharging: Bool = true,
        systemPowerInWatts: Double? = 12.3,
        perPortWatts: [WidgetSnapshot.PortPowerEntry]? = nil,
        recentSystemPower: [Double] = [12.1, 12.2, 12.3]
    ) -> WidgetSnapshot.PowerState {
        WidgetSnapshot.PowerState(
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            fullyCharged: false,
            isDesktopMac: false,
            adapterWatts: 65,
            adapterDescription: "65W USB-C Power Adapter",
            systemPowerInWatts: systemPowerInWatts,
            perPortWatts: perPortWatts,
            recentSystemPower: recentSystemPower
        )
    }

    // MARK: - Wobble-only changes: must compare equal

    @Test("Two snapshots differing only in per-port recentPower samples are structurally equal")
    func recentPowerWobbleIsIgnored() {
        let a = WidgetSnapshot(ports: [makePort(recentPower: [4.9, 5.0])], powerState: makePowerState())
        let b = WidgetSnapshot(ports: [makePort(recentPower: [5.0, 5.1])], powerState: makePowerState())

        #expect(a.ports != b.ports, "Fixture setup check: the raw ports must actually differ, or this test proves nothing")
        #expect(a.structuralSignature == b.structuralSignature)
    }

    @Test("Two snapshots differing only in system-power wobble are structurally equal")
    func systemPowerWobbleIsIgnored() {
        let a = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(
            systemPowerInWatts: 12.3, recentSystemPower: [12.1, 12.2, 12.3]))
        let b = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(
            systemPowerInWatts: 12.4, recentSystemPower: [12.2, 12.3, 12.4]))

        #expect(a.powerState != b.powerState, "Fixture setup check")
        #expect(a.structuralSignature == b.structuralSignature)
    }

    @Test("Two snapshots differing only in per-port watts/recentSamples are structurally equal")
    func perPortWattsWobbleIsIgnored() {
        let a = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(
            perPortWatts: [.init(portKey: "port-1", portName: "Port-USB-C@1", watts: 5.0, recentSamples: [4.9, 5.0])]))
        let b = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(
            perPortWatts: [.init(portKey: "port-1", portName: "Port-USB-C@1", watts: 5.2, recentSamples: [5.0, 5.2])]))

        #expect(a.powerState != b.powerState, "Fixture setup check")
        #expect(a.structuralSignature == b.structuralSignature)
    }

    @Test("Battery percent, which changes slowly, is treated as structural (not filtered)")
    func batteryPercentIsStructural() {
        let a = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(batteryPercent: 80))
        let b = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(batteryPercent: 81))

        #expect(a.structuralSignature != b.structuralSignature)
    }

    // MARK: - Real structural changes: must compare unequal

    @Test("A port appearing changes the signature")
    func portAppearingIsStructural() {
        let a = WidgetSnapshot(ports: [makePort(id: 1)], powerState: nil)
        let b = WidgetSnapshot(ports: [makePort(id: 1), makePort(id: 2, portKey: "port-2")], powerState: nil)

        #expect(a.structuralSignature != b.structuralSignature)
    }

    @Test("Status change is structural")
    func statusChangeIsStructural() {
        let a = WidgetSnapshot(ports: [makePort(status: .empty)], powerState: nil)
        let b = WidgetSnapshot(ports: [makePort(status: .charging)], powerState: nil)

        #expect(a.structuralSignature != b.structuralSignature)
    }

    @Test("Charger wattage change is structural")
    func chargerWattsChangeIsStructural() {
        let a = WidgetSnapshot(ports: [makePort(chargerWatts: 65)], powerState: nil)
        let b = WidgetSnapshot(ports: [makePort(chargerWatts: 96)], powerState: nil)

        #expect(a.structuralSignature != b.structuralSignature)
    }

    @Test("Display mode change is structural")
    func displayModeChangeIsStructural() {
        let a = WidgetSnapshot(ports: [makePort(displayMode: "4K 60Hz")], powerState: nil)
        let b = WidgetSnapshot(ports: [makePort(displayMode: "5K 60Hz")], powerState: nil)

        #expect(a.structuralSignature != b.structuralSignature)
    }

    @Test("Display count change is structural (a dock fanning out to a second monitor)")
    func displayCountChangeIsStructural() {
        let a = WidgetSnapshot(ports: [makePort(displayCount: 1)], powerState: nil)
        let b = WidgetSnapshot(ports: [makePort(displayCount: 2)], powerState: nil)

        #expect(a.structuralSignature != b.structuralSignature)
    }

    @Test("A system-power reading appearing for the first time is structural")
    func systemPowerPresenceIsStructural() {
        let a = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(systemPowerInWatts: nil))
        let b = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(systemPowerInWatts: 12.3))

        #expect(a.structuralSignature != b.structuralSignature)
    }

    @Test("A port gaining power (perPortWatts key presence) is structural")
    func poweredPortKeyPresenceIsStructural() {
        let a = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(perPortWatts: nil))
        let b = WidgetSnapshot(ports: [makePort()], powerState: makePowerState(
            perPortWatts: [.init(portKey: "port-1", portName: "Port-USB-C@1", watts: 5.0, recentSamples: [5.0])]))

        #expect(a.structuralSignature != b.structuralSignature)
    }

    @Test("The timestamp never affects the structural signature")
    func timestampIsIgnored() {
        let ports = [makePort()]
        let powerState = makePowerState()
        let early = WidgetSnapshot(ports: ports, timestamp: Date(timeIntervalSince1970: 0), powerState: powerState)
        let late = WidgetSnapshot(ports: ports, timestamp: Date(timeIntervalSince1970: 1_000_000), powerState: powerState)

        #expect(early.timestamp != late.timestamp, "Fixture setup check")
        #expect(early.structuralSignature == late.structuralSignature)
    }

    // MARK: - The bug, demonstrated directly

    /// This is the exact shape of the reported bug: a snapshot that only
    /// differs by the 1 Hz power wobble. The OLD dedup (full `Equatable` on
    /// `ports/powerState`) treats these as different and would write; the new
    /// `structuralSignature`-based dedup correctly treats them as the same.
    @Test("Old-style full-equality comparison would NOT have deduped this pair (documents the bug)")
    func oldComparisonWouldHaveWritten() {
        let a = WidgetSnapshot(ports: [makePort(recentPower: [4.9])], powerState: makePowerState(systemPowerInWatts: 12.3))
        let b = WidgetSnapshot(ports: [makePort(recentPower: [5.0])], powerState: makePowerState(systemPowerInWatts: 12.4))

        // The old WidgetDataWriter.scheduleWrite() dedup, reproduced here:
        let oldComparisonSaysUnchanged = (a.ports == b.ports) && (a.powerState == b.powerState)
        #expect(!oldComparisonSaysUnchanged, "Old comparison should see these as different (that's the bug)")

        // The new comparison correctly dedupes the same pair.
        #expect(a.structuralSignature == b.structuralSignature)
    }

    @Test("The accessory name is structural: it is the row's own detail line")
    func accessoryNameChangeIsStructural() {
        // An iPhone unplugged and an iPad plugged in reads differently on the
        // widget, so it must earn a reload rather than being deduped away.
        let a = WidgetSnapshot(ports: [makePort(accessoryName: "iPhone")], powerState: nil)
        let b = WidgetSnapshot(ports: [makePort(accessoryName: "iPad")], powerState: nil)

        #expect(a.structuralSignature != b.structuralSignature)
    }
}
