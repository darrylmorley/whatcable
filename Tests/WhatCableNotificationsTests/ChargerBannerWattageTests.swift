import XCTest
@testable import WhatCableNotifications
import WhatCableCore

/// Public issue #592: with a third-party charger on MagSafe, macOS publishes
/// only a "Brick ID" power source (junk options, never a winning PD contract),
/// so the connect banner fell back to a bare "PD source" label while the port
/// summary already showed the real wattage through the issue #154 adapter
/// divert. These tests pin the banner onto that same
/// `ChargerWattageSource.resolve` path, and pin that nothing claims
/// "negotiated" without a winning contract.
@MainActor
final class ChargerBannerWattageTests: XCTestCase {

    // MARK: - Fixtures

    private func magSafePort(active: Bool = true) -> AppleHPMInterface {
        AppleHPMInterface(
            id: 1,
            serviceName: "Port-MagSafe 3@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-MagSafe 3@1",
            portTypeDescription: "MagSafe 3",
            portNumber: 1,
            connectionActive: active,
            activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "17"]
        )
    }

    /// The #592 shape: a Brick ID source on MagSafe with a junk ~3W option
    /// and no winning contract.
    private func brickIDSource() -> PowerSource {
        PowerSource(
            id: 1, name: "Brick ID",
            parentPortType: 17, parentPortNumber: 1,
            options: [PowerOption(voltageMV: 5000, maxCurrentMA: 600, maxPowerMW: 3000)],
            winning: nil
        )
    }

    /// A normal USB-C wall charger with a live contract.
    private func negotiatedSource() -> PowerSource {
        PowerSource(
            id: 2, name: "USB-PD",
            parentPortType: 2, parentPortNumber: 1,
            options: [],
            winning: PowerOption(voltageMV: 20000, maxCurrentMA: 1500, maxPowerMW: 30000)
        )
    }

    private func adapter(watts: Int) -> AdapterInfo {
        AdapterInfo(watts: watts, isCharging: true, source: "AC")
    }

    private final class PostedLog {
        var entries: [(NotificationCategory, NotificationContent)] = []
    }

    private func makeSequencer(
        clock: ManualClock,
        posted: PostedLog,
        sources: [PowerSource],
        ports: [AppleHPMInterface] = [],
        adapter: AdapterInfo? = nil
    ) -> DeviceDiffSequencer<ManualClock> {
        DeviceDiffSequencer(
            clock: clock,
            currentDevices: { [] },
            currentChargerSources: { sources },
            currentPorts: { ports },
            currentAdapter: { adapter },
            notifyOnChanges: { true },
            post: { category, content, _ in posted.entries.append((category, content)) },
            launchToken: "test-launch"
        )
    }

    /// Runs one charger reconcile against an empty baseline, so every source
    /// handed in reads as newly connected.
    private func connectBanner(
        sources: [PowerSource],
        ports: [AppleHPMInterface] = [],
        adapter: AdapterInfo? = nil
    ) async -> NotificationContent? {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(
            clock: clock, posted: posted, sources: sources, ports: ports, adapter: adapter)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.reconcileChargers()
        await clock.settle()

        return posted.entries.first?.1
    }

    // MARK: - Tests

    /// The reported case. Brick ID only, one charger-source port, and the
    /// system adapter reading the real wattage: the banner reports that
    /// wattage instead of "PD source".
    func testBrickIDOnlySourceReportsTheSystemAdapterWattage() async {
        let content = await connectBanner(
            sources: [brickIDSource()],
            ports: [magSafePort()],
            adapter: adapter(watts: 15)
        )

        XCTAssertEqual(content?.title, "Charger connected")
        XCTAssertEqual(content?.body, "System reports charger at 15W")
    }

    /// A winning contract still labels exactly as before.
    func testWinningContractStillLabelsAsNegotiated() async {
        let content = await connectBanner(sources: [negotiatedSource()])

        XCTAssertEqual(content?.title, "Charger connected")
        XCTAssertEqual(content?.body, "30W negotiated")
    }

    /// Advertised options with no winning contract are a claim by the
    /// charger, not a measurement, so the label mirrors the port summary's
    /// "advertises up to" wording and never says "negotiated".
    func testAdvertisedOnlySourceNeverClaimsNegotiated() async {
        let advertisedOnly = PowerSource(
            id: 3, name: "USB-PD",
            parentPortType: 2, parentPortNumber: 1,
            options: [PowerOption(voltageMV: 20000, maxCurrentMA: 3250, maxPowerMW: 65000)],
            winning: nil
        )

        let content = await connectBanner(sources: [advertisedOnly])

        XCTAssertEqual(content?.body, "Charger advertises up to 65W")
        XCTAssertFalse(content?.body.contains("negotiated") ?? true)
    }

    /// Nothing resolvable to a wattage: the banner still names the change,
    /// and says plainly that no wattage was reported rather than going out
    /// with an empty body.
    func testUnresolvableSourceSaysWattageNotReported() async {
        let bare = PowerSource(
            id: 4, name: "Brick ID",
            parentPortType: 17, parentPortNumber: 1,
            options: [],
            winning: nil
        )

        let content = await connectBanner(sources: [bare])

        XCTAssertEqual(content?.title, "Charger connected")
        XCTAssertEqual(content?.body, "Wattage not reported")
    }

    /// Fix round 1, F3. A Brick ID node's options are a junk analog
    /// identifier, not a PD menu. With no adapter reading the #154 divert
    /// cannot fire and `ChargerWattageSource.resolve` falls through to that
    /// junk figure, so the banner must suppress it rather than print "3W".
    func testBrickIDJunkOptionWithNoAdapterReportsNoWattage() async {
        let content = await connectBanner(
            sources: [brickIDSource()],
            ports: [magSafePort()],
            adapter: nil
        )

        XCTAssertEqual(content?.body, "Wattage not reported")
        XCTAssertFalse(content?.body.contains("3W") ?? true)
    }

    /// Same suppression when an adapter reading exists but is not higher
    /// than the brick's own junk figure, the other way the divert declines.
    func testBrickIDJunkOptionWithEqualAdapterReportsNoWattage() async {
        let content = await connectBanner(
            sources: [brickIDSource()],
            ports: [magSafePort()],
            adapter: adapter(watts: 3)
        )

        XCTAssertEqual(content?.body, "Wattage not reported")
    }

    /// A genuine USB-PD charger caught before its contract lands: 0W, no
    /// winning option, nothing to report yet. The old empty body said
    /// nothing at all, which cannot tell one port from another.
    func testUSBPDMidNegotiationSaysWattageNotReported() async {
        let midNegotiation = PowerSource(
            id: 5, name: "USB-PD",
            parentPortType: 2, parentPortNumber: 1,
            options: [],
            winning: nil
        )

        let content = await connectBanner(sources: [midNegotiation])

        XCTAssertEqual(content?.title, "Charger connected")
        XCTAssertEqual(content?.body, "Wattage not reported")
    }

    /// Every charger now carries a label, so this only guards the join:
    /// an empty label must never become a blank line in a merged body.
    func testEmptyLabelIsDroppedFromAMergedBody() {
        let contents = NotificationDecision.chargerNotificationContents(
            added: [
                NotificationDecision.ChargerLine(wattage: "", cableName: nil),
                NotificationDecision.ChargerLine(wattage: "30W negotiated", cableName: nil)
            ],
            removed: []
        )

        XCTAssertEqual(contents, [
            NotificationContent(title: "Charger connected", body: "30W negotiated")
        ])
    }
}
