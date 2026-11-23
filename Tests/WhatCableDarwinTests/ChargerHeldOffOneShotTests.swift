import Foundation
import Testing
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

/// Public issue 672, review of the wait: one-shot reads (CLI snapshot and
/// JSON, the dashboard's first paint, bench report) have nothing to flash, so
/// they use the single read's raw held-off signal and never sleep for it.
@Suite("Charger held off: one-shot reads")
struct ChargerHeldOffOneShotTests {
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

    /// What one hardware read of a held Mac produces: the watcher has seen the
    /// held-off precondition once, so its held value is still false; the raw
    /// read says true. SMC charge state as on every corpus held Mac.
    private func heldRead() -> CableSnapshot {
        let w = PowerOption(voltageMV: 20_000, maxCurrentMA: 4_700, maxPowerMW: 94_000)
        return CableSnapshot(
            ports: [port()],
            powerSources: [PowerSource(id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1, options: [w], winning: w)],
            identities: [], usbDevices: [], adapter: nil,
            batteryFullyCharged: false, batteryIsCharging: false, batteryChargeState: .notPluggedIn,
            chargerHeldOffSignal: false)
    }

    @Test("A single read of a held Mac shows 'Charger connected' in the CLI, with no wait")
    func oneShotUsesTheRawRead() async {
        var slept: [TimeInterval] = []
        let snap = await DarwinSnapshotProvider.finishOneShot(
            heldRead(), rawChargeState: .notPluggedIn, rawHeldOff: true,
            readChargeStateAgain: { .notPluggedIn }, sleep: { slept.append($0) })
        #expect(snap.chargerHeldOffSignal == true)
        #expect(slept.isEmpty, "one-shot must not wait for the held-off state, slept \(slept)")
        let out = TextFormatter.render(
            ports: snap.ports, sources: snap.powerSources, identities: snap.identities, showRaw: false,
            adapter: snap.adapter, batteryFullyCharged: snap.batteryFullyCharged,
            batteryIsCharging: snap.batteryIsCharging, batteryChargeState: snap.batteryChargeState,
            chargerHeldOffSignal: snap.chargerHeldOffSignal)
        #expect(out.contains("Charger connected"), "\(out)")
    }

    @Test("One-shot passes the raw read through as is: false and unknown stay so, with no wait", arguments: [false, nil] as [Bool?])
    func oneShotPassesThrough(raw: Bool?) async {
        var slept = false
        let snap = await DarwinSnapshotProvider.finishOneShot(
            heldRead(), rawChargeState: .notPluggedIn, rawHeldOff: raw,
            readChargeStateAgain: { nil }, sleep: { _ in slept = true })
        #expect(snap.chargerHeldOffSignal == raw)
        #expect(!slept)
    }

    // MARK: - The provider's own wiring, through an injected environment

    /// A hardware read whose held-off precondition is true, as on a held Mac.
    private static func heldHubReading(chargeState: BatteryChargeState? = .notPluggedIn) -> HubReading {
        HubReading(
            ports: .init(ports: [], liveEntryIDs: []),
            pd: .init(identities: [], stateCCEntryIDs: []),
            power: .init(sources: [], charger: nil, chargeState: chargeState, chargerHeldOffCandidate: true),
            thunderbolt: .init(switches: [], liveEntryIDs: [], modelEntryIDs: []),
            usb3: [], trm: .init(transports: [], cioCapabilities: []),
            phy: nil, display: [], uvdm: []
        )
    }

    final class Clock: @unchecked Sendable { var now: TimeInterval = 100 }

    /// No IOKit anywhere: every read is a fixture, sleeps are recorded.
    private static func environment(
        reading: HubReading = heldHubReading(), clock: Clock = Clock(),
        sleep: @escaping (TimeInterval) async -> Void = { _ in }
    ) -> DarwinSnapshotProvider.Environment {
        .init(
            hubRead: { _, _ in reading },
            startsWatchers: false,
            bitsPerComponent: { [:] },
            readBattery: { .init(isDesktopMac: false, federatedIdentities: [], battery: nil) },
            readAdapter: { nil },
            readChargeStateAgain: { _ in reading.power.chargeState },
            sleep: sleep,
            clock: { clock.now })
    }

    @MainActor @Test("The test seam opens no IOKit: no watcher is ever started")
    func testSeamStartsNoWatcher() async throws {
        let provider = DarwinSnapshotProvider(environment: Self.environment())
        _ = try await provider.snapshot()
        _ = try await provider.liveSurfaceSnapshot()
        #expect(!provider.watchersStartedForTesting)
    }

    @MainActor @Test("snapshot() carries this read's raw held-off precondition")
    func snapshotPassesTheRawRead() async throws {
        let provider = DarwinSnapshotProvider(environment: Self.environment())
        let snap = try await provider.snapshot()
        #expect(snap.chargerHeldOffSignal == true)
    }

    @MainActor @Test("Dashboard first paint (liveSurfaceSnapshot) agrees with the watch() stream: both held, not raw")
    func liveSurfaceAgreesWithTheStream() async throws {
        let painted = try await DarwinSnapshotProvider(environment: Self.environment()).liveSurfaceSnapshot()
        var streamed: CableSnapshot?
        for try await snap in DarwinSnapshotProvider(environment: Self.environment()).watch() {
            streamed = snap
            break
        }
        let first = try #require(streamed)
        #expect(painted.chargerHeldOffSignal == first.chargerHeldOffSignal,
                "first paint \(String(describing: painted.chargerHeldOffSignal)) vs stream \(String(describing: first.chargerHeldOffSignal))")
        // One read can't have held for the wait yet: both read false.
        #expect(first.chargerHeldOffSignal == false)
    }

    /// The `r` race: liveSurfaceSnapshot() can sleep 2 s confirming a
    /// running-on-battery charge state. If the stream shows the held state
    /// during that sleep, the refresh must not paint it back to false.
    @MainActor @Test("An `r` refresh that sleeps returns the held value as it is AFTER the sleep")
    func liveSurfaceDoesNotGoBackwards() async throws {
        let clock = Clock()
        final class Box: @unchecked Sendable { var provider: DarwinSnapshotProvider? }
        let box = Box()
        var slept = 0
        let env = Self.environment(
            reading: Self.heldHubReading(chargeState: .runningOnBattery), clock: clock,
            sleep: { _ in
                // During the confirm sleep the stream keeps ticking past the hold.
                await MainActor.run {
                    slept += 1
                    clock.now = 100 + ChargerHeldOffHold.holdSeconds + 1
                    let tick = box.provider!.streamTickForTesting()
                    #expect(tick.chargerHeldOffSignal == true, "fixture: the stream should show held by now")
                }
            })
        let provider = DarwinSnapshotProvider(environment: env)
        box.provider = provider
        let refreshed = try await provider.liveSurfaceSnapshot()
        #expect(slept == 1, "fixture: the running-on-battery confirm should have slept once")
        #expect(refreshed.chargerHeldOffSignal == true, "the refresh painted the card back to false after the stream showed it")
    }
}
