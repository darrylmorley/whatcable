import Combine
import Foundation
import Testing
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

/// A fake read the test can hold open, and count. Returns `readings` in
/// order, repeating the last one once the list runs out.
final class FakeRead: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _ranOnMain: [Bool] = []
    private var _holds = false
    let gate = DispatchSemaphore(value: 0)
    let readings: [HubReading]

    var calls: Int { lock.withLock { _calls } }
    var ranOnMain: [Bool] { lock.withLock { _ranOnMain } }
    var holds: Bool {
        get { lock.withLock { _holds } }
        set { lock.withLock { _holds = newValue } }
    }

    init(reading: HubReading) { self.readings = [reading] }
    init(readings: [HubReading]) { self.readings = readings }

    func read(_ r: HubReadRequest, _ s: SMCPowerReader) -> HubReading {
        let index: Int = lock.withLock {
            _calls += 1
            _ranOnMain.append(Thread.isMainThread)
            return _calls - 1
        }
        if holds { gate.wait() }
        return readings[min(index, readings.count - 1)]
    }
}

extension HubReading {
    static let empty = HubReading.with(usb3: [])

    static func with(usb3: [USB3Transport]) -> HubReading {
        HubReading(
            ports: .init(ports: [], liveEntryIDs: []),
            pd: .init(identities: [], stateCCEntryIDs: []),
            power: .init(sources: [], charger: nil),
            thunderbolt: .init(switches: [], liveEntryIDs: [], modelEntryIDs: []),
            usb3: usb3, trm: .init(transports: [], cioCapabilities: []),
            phy: nil, display: [], uvdm: []
        )
    }

    static func with(chargeState: BatteryChargeState?) -> HubReading {
        HubReading(
            ports: .init(ports: [], liveEntryIDs: []),
            pd: .init(identities: [], stateCCEntryIDs: []),
            power: .init(sources: [], charger: nil, chargeState: chargeState),
            thunderbolt: .init(switches: [], liveEntryIDs: [], modelEntryIDs: []),
            usb3: [], trm: .init(transports: [], cioCapabilities: []),
            phy: nil, display: [], uvdm: []
        )
    }
}

/// Waits until `didRefresh` has fired `n` times, or `timeout` passes.
/// Returns whether all `n` ticks arrived, so a missing tick fails the test
/// instead of hanging the run.
@MainActor
private func waitForTicks(_ hub: WatcherHub, _ n: Int, timeout: Duration = .seconds(5)) async -> Bool {
    var seen = 0
    var sub: AnyCancellable?
    let done = AsyncStream<Bool> { c in
        sub = hub.didRefresh.sink { seen += 1; if seen >= n { c.yield(true); c.finish() } }
        Task { @MainActor in
            try? await Task.sleep(for: timeout)
            c.yield(false)
            c.finish()
        }
    }
    defer { sub?.cancel() }
    for await arrived in done { return arrived }
    return false
}

func transport(_ id: UInt64) -> USB3Transport {
    USB3Transport(id: id, portKey: "USB-C/\(id)", signaling: 2, signalingDescription: "Gen 2", dataRole: "host")
}

/// Serialized: each held fake read blocks a cooperative-pool thread until the
/// test signals it. Run in parallel, the parameterised cases park more reads
/// than the pool has threads and stall every other test in the process.
@MainActor @Suite(.serialized) struct WatcherHubTickTests {
    @Test func tickReadsOffMainAndPublishes() async {
        let fake = FakeRead(reading: .empty)
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.refreshAll()
        #expect(await waitForTicks(hub, 1))
        #expect(fake.calls == 1)
        #expect(fake.ranOnMain == [false])
    }

    @Test func hubFeedsTheChargeStateOnEachRead() async {
        let fake = FakeRead(reading: .with(chargeState: .chargeLimitReached))
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.refreshAll()
        #expect(await waitForTicks(hub, 1))
        #expect(hub.powerWatcher.batteryChargeState == .chargeLimitReached)
    }

    /// Issue 672: the hub is the app's only feed for the held-off charger
    /// signal. One read: the raw candidate is recorded (the widget reads it)
    /// and the held signal waits.
    @Test func hubFeedsTheHeldOffCandidateOnEachRead() async {
        let reading = HubReading(
            ports: .init(ports: [], liveEntryIDs: []),
            pd: .init(identities: [], stateCCEntryIDs: []),
            power: .init(sources: [], charger: nil, chargeState: .notPluggedIn, chargerHeldOffCandidate: true),
            thunderbolt: .init(switches: [], liveEntryIDs: [], modelEntryIDs: []),
            usb3: [], trm: .init(transports: [], cioCapabilities: []),
            phy: nil, display: [], uvdm: []
        )
        let fake = FakeRead(reading: reading)
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.refreshAll()
        #expect(await waitForTicks(hub, 1))
        #expect(hub.powerWatcher.lastHeldOffCandidate == true)
        #expect(hub.powerWatcher.chargerHeldOffSignal == false)
    }

    /// The plug-in burst reads 150 ms and 500 ms after a change; two quick
    /// reads inside one CH0R pulse must not publish running on battery.
    @Test func quickRunningOnBatteryReadsDoNotPublish() async {
        let fake = FakeRead(reading: .with(chargeState: .runningOnBattery))
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.refreshAll()
        #expect(await waitForTicks(hub, 1))
        hub.refreshAll()
        #expect(await waitForTicks(hub, 1))
        #expect(hub.powerWatcher.batteryChargeState == nil)
    }

    @Test func steadyTickIsSkippedWhileAReadRuns() async {
        let fake = FakeRead(reading: .empty)
        fake.holds = true
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.requestRefresh(steady: true)
        try? await Task.sleep(for: .milliseconds(50))
        hub.requestRefresh(steady: true)
        hub.requestRefresh(steady: true)
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
        // A dropped steady tick leaves nothing behind to observe, so this
        // negative check needs a short settle window.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(fake.calls == 1)
    }

    @Test func otherRequestsQueueOneFollowUp() async {
        let fake = FakeRead(reading: .empty)
        fake.holds = true
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.requestRefresh(steady: true)
        try? await Task.sleep(for: .milliseconds(50))
        hub.refreshAll()
        hub.refreshAll()
        fake.holds = false
        fake.gate.signal()
        #expect(await waitForTicks(hub, 2))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(fake.calls == 2)
    }

    @Test func staleReadDoesNotOverwriteNewerState() async {
        // The held read carries transport 1. While it runs, a newer state
        // (transport 2) is published directly, as a match handler would. The
        // follow-up read then sees what the hardware now says (transport 2).
        let older = HubReading.with(usb3: [transport(1)])
        let newer = HubReading.with(usb3: [transport(2)])
        let fake = FakeRead(readings: [older, newer])
        fake.holds = true
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.requestRefresh(steady: true)
        try? await Task.sleep(for: .milliseconds(50))
        hub.usb3Watcher.apply([transport(2)])
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
        // After the held read applied: the newer direct state survived.
        #expect(hub.usb3Watcher.transports == [transport(2)])
        // The follow-up read is held too, so its tick cannot land before
        // this wait subscribes.
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
        // The skip queued exactly one follow-up read.
        #expect(fake.calls == 2)
        #expect(hub.usb3Watcher.transports == [transport(2)])
    }

    // MARK: - Every slice published, and the stale guard on every watcher

    @Test func publishesEverySliceOfAFixedRead() async {
        let reading = Fixture.reading(1)
        let fake = FakeRead(reading: reading)
        let hub = WatcherHub(read: { fake.read($0, $1) })
        // The hub applies the charger figures only while the readout is on.
        hub.powerWatcher.readsChargerInputWatts = true
        defer { hub.powerWatcher.readsChargerInputWatts = false }
        hub.refreshAll()
        #expect(await waitForTicks(hub, 1))
        #expect(hub.portWatcher.ports == reading.ports.ports)
        #expect(hub.pdWatcher.identities == reading.pd.identities)
        #expect(hub.powerWatcher.sources == reading.power.sources)
        #expect(hub.powerWatcher.chargerInputWatts == 40)
        #expect(hub.powerWatcher.chargerRatedWatts == 60)
        #expect(hub.tbWatcher.switches == reading.thunderbolt.switches)
        #expect(hub.usb3Watcher.transports == reading.usb3)
        #expect(hub.trmWatcher.transports == reading.trm.transports)
        #expect(hub.trmWatcher.cioCapabilities == reading.trm.cioCapabilities)
        #expect(hub.displayWatcher.statuses == reading.display)
        #expect(hub.uvdmWatcher.identities == reading.uvdm)
    }

    @Test(arguments: HubSlice.allCases)
    func staleReadDoesNotOverwriteAnyWatcher(_ slice: HubSlice) async {
        let fake = FakeRead(reading: Fixture.reading(1))
        fake.holds = true
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.requestRefresh(steady: true)
        try? await Task.sleep(for: .milliseconds(50))
        slice.applyNewer(to: hub)
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
        #expect(slice.holdsNewer(hub), "\(slice): the stale read overwrote newer state")
        // The skip queued a follow-up; release it so no read is left parked.
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
        #expect(fake.calls == 2)
    }

    // MARK: - Power depends on this read's ports and PD identities

    @Test(arguments: [HubSlice.port, HubSlice.pd])
    func powerIsSkippedWhenItsInputsWere(_ input: HubSlice) async {
        // The read's power slice was synthesized from its own ports and PD
        // identities. If either was skipped as stale, power must be too.
        let fake = FakeRead(reading: Fixture.reading(1))
        fake.holds = true
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.requestRefresh(steady: true)
        try? await Task.sleep(for: .milliseconds(50))
        input.applyNewer(to: hub)
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
        #expect(hub.powerWatcher.sources == [], "power took a slice built from a stale \(input) read")
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
    }

    // MARK: - Charger readout

    @Test func newerChargerFiguresSurviveAStaleRead() async {
        let fake = FakeRead(reading: Fixture.reading(1))  // charger 40 / 60
        fake.holds = true
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.powerWatcher.readsChargerInputWatts = true
        defer { hub.powerWatcher.readsChargerInputWatts = false }
        hub.requestRefresh(steady: true)
        try? await Task.sleep(for: .milliseconds(50))
        // A power-source notification publishes newer figures mid-read.
        hub.powerWatcher.apply(.init(sources: hub.powerWatcher.sources, charger: .init(input: 55, rated: 70)))
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
        #expect(hub.powerWatcher.chargerInputWatts == 55)
        #expect(hub.powerWatcher.chargerRatedWatts == 70)
    }

    @Test func chargerReadoutSwitchedOffMidReadStaysZero() async {
        let fake = FakeRead(reading: Fixture.reading(1))  // charger 40 / 60
        fake.holds = true
        let hub = WatcherHub(read: { fake.read($0, $1) })
        hub.powerWatcher.readsChargerInputWatts = true
        // Start from zero so switching the readout off changes no figure:
        // only the readout flag itself can stop the stale apply.
        hub.powerWatcher.apply(.init(sources: [], charger: .init(input: 0, rated: 0)))
        hub.requestRefresh(steady: true)
        try? await Task.sleep(for: .milliseconds(50))
        hub.powerWatcher.readsChargerInputWatts = false
        fake.gate.signal()
        #expect(await waitForTicks(hub, 1))
        #expect(hub.powerWatcher.chargerInputWatts == 0)
        #expect(hub.powerWatcher.chargerRatedWatts == 0)
    }
}

/// One hub watcher, for the stale-guard tests: how to publish a newer value
/// into it directly, and whether it still holds that value.
enum HubSlice: String, CaseIterable, Sendable, CustomStringConvertible {
    case port, pd, power, tb, usb3, trm, display, uvdm
    var description: String { rawValue }

    @MainActor func applyNewer(to hub: WatcherHub) {
        let r = Fixture.reading(2)
        switch self {
        case .port: hub.portWatcher.apply(r.ports)
        case .pd: hub.pdWatcher.apply(r.pd)
        case .power: hub.powerWatcher.apply(.init(sources: r.power.sources, charger: nil))
        case .tb: hub.tbWatcher.apply(r.thunderbolt)
        case .usb3: hub.usb3Watcher.apply(r.usb3)
        case .trm: hub.trmWatcher.apply(r.trm)
        case .display: hub.displayWatcher.apply(r.display)
        case .uvdm: hub.uvdmWatcher.apply(r.uvdm)
        }
    }

    @MainActor func holdsNewer(_ hub: WatcherHub) -> Bool {
        let r = Fixture.reading(2)
        switch self {
        case .port: return hub.portWatcher.ports == r.ports.ports
        case .pd: return hub.pdWatcher.identities == r.pd.identities
        case .power: return hub.powerWatcher.sources == r.power.sources
        case .tb: return hub.tbWatcher.switches == r.thunderbolt.switches
        case .usb3: return hub.usb3Watcher.transports == r.usb3
        case .trm: return hub.trmWatcher.transports == r.trm.transports && hub.trmWatcher.cioCapabilities == r.trm.cioCapabilities
        case .display: return hub.displayWatcher.statuses == r.display
        case .uvdm: return hub.uvdmWatcher.identities == r.uvdm
        }
    }
}

/// Fixed model values with every slice non-empty. `n` varies the ids and
/// names so two fixtures never compare equal. Entry ids are far above any
/// real registry id, so an apply's service lookup finds nothing and
/// registers no interest.
enum Fixture {
    static func reading(_ n: UInt64) -> HubReading {
        let fakeEntry: UInt64 = 0x7FFF_0000_0000_0000 + n
        let port = AppleHPMInterface(
            id: n, serviceName: "Port-USB-C@\(n)", className: "AppleHPMInterfaceType10",
            portDescription: nil, portTypeDescription: "USB-C", portNumber: Int(n),
            connectionActive: true, activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, hpmControllerUUID: nil,
            rawProperties: ["PortType": "2"]
        )
        let sop = USBPDSOP(
            id: n, endpoint: .sop, parentPortType: 2, parentPortNumber: Int(n),
            vendorID: 0x05AC, productID: Int(n), bcdDevice: 0, vdos: [], specRevision: 3
        )
        let option = PowerOption(voltageMV: 20000, maxCurrentMA: 3000, maxPowerMW: 60000)
        let source = PowerSource(
            id: n, name: "USB-PD \(n)", parentPortType: 2, parentPortNumber: Int(n),
            options: [option], winning: option
        )
        let tbSwitch = IOThunderboltSwitch(
            id: Int64(n), className: "IOThunderboltSwitchType5", vendorID: 0x8087,
            vendorName: "Box \(n)", modelName: "Box \(n)", routerID: 0, depth: 0,
            routeString: 0, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [], parentSwitchUID: nil
        )
        let trm = TRMTransport(
            id: n, portKey: "2/\(n)", transportType: "USB2", state: 2, stateDescription: "Limited",
            transportRestricted: true, transportSupervised: nil, identificationRestricted: nil,
            deviceLocked: nil, relaxedPeriod: nil, gracePeriodReason: nil,
            gracePeriodReasonDescription: nil, profile: nil, profileDescription: nil, cacheMiss: nil
        )
        let cio = CIOCableCapability(
            id: n, portKey: "2/\(n)", cableGeneration: 3, negotiatedLinkSpeed: 2, generation: 3,
            asymmetricModeSupported: nil, legacyAdapter: nil, linkTrainingMode: nil
        )
        let display = DisplayPortTransportWatcher.DisplayPortUpdate(
            entryID: fakeEntry, portIndex: Int(n), portType: "HDMI",
            status: IOPortTransportStateDisplayPort(
                link: DisplayPortLink(
                    active: true, laneCount: 4, maxLaneCount: 4,
                    linkRate: 3, linkRateDescription: "5.4 Gbps (HBR2)",
                    tunneled: false, hpdState: 1
                ),
                monitor: nil, parentPortTypeDescription: "HDMI", parentPortNumber: Int(n)
            )
        )
        let accessory = AppleAccessoryIdentity(
            id: n, portKey: "2/\(n)", manufacturer: nil, vendor: nil, product: "Accessory \(n)",
            userString: nil, model: nil, serialNumber: nil, hardwareVersion: nil,
            vendorID: nil, productID: nil
        )
        return HubReading(
            ports: .init(ports: [port], liveEntryIDs: [fakeEntry]),
            pd: .init(identities: [sop], stateCCEntryIDs: [fakeEntry]),
            power: .init(sources: [source], charger: .init(input: 40, rated: 60)),
            thunderbolt: .init(switches: [tbSwitch], liveEntryIDs: [fakeEntry], modelEntryIDs: [fakeEntry]),
            usb3: [transport(n)],
            trm: .init(transports: [trm], cioCapabilities: [cio]),
            phy: nil, display: [display], uvdm: [accessory]
        )
    }
}
