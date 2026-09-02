import XCTest
@testable import WhatCableNotifications
import WhatCableCore

/// Issue #593: a saved cable's name never reached a charger notification. A
/// MagSafe plug produces no USB device at all, so the device path (issue
/// #570's timing/episode machinery) can never see it; the charger path joins
/// on the port itself instead (`knownLabelledCablesByPort`, keyed by
/// `canonicalJoinKey`), because a `PowerSource` and the port a cable sits on
/// collapse to the same key. These tests drive `reconcileChargers` end to
/// end (mirrors `ChargerBannerWattageTests`'s harness) rather than only the
/// pure `NotificationDecision` layer, because the interesting behaviour here
/// is what the sequencer REMEMBERS across reconciles: a disconnect banner
/// has to name a cable using state captured at connect time, since by the
/// time a charger goes, the live feed has already lost the attribution too.
@MainActor
final class NotificationManagerChargerCableNameTests: XCTestCase {

    // MARK: - Fixtures

    /// A MagSafe port key. Matches `PowerSource.portKey` for
    /// `parentPortType: 17, parentPortNumber: 1` (no `hpmControllerUUID`, so
    /// `canonicalJoinKey` falls back to `portKey`), the same shape a real
    /// M1/M2 MagSafe port produces.
    private let magSafeKey = "17/1"
    /// A USB-C port key, for the "two ports, one named" cases.
    private let usbcKey = "2/1"

    private func negotiatedSource(port: Int, number: Int = 1, id: UInt64, watts: Int) -> PowerSource {
        PowerSource(
            id: id, name: "USB-PD",
            parentPortType: port, parentPortNumber: number,
            options: [],
            winning: PowerOption(voltageMV: 20000, maxCurrentMA: watts * 1000 / 20, maxPowerMW: watts * 1000)
        )
    }

    private func feed(byPort: [String: String]) -> NotificationDecision.CableLabelFeed {
        NotificationDecision.CableLabelFeed(hasSavedCables: true, attachedLabelled: [:], attachedLabelledByPort: byPort)
    }

    private final class PostedLog {
        var entries: [(NotificationCategory, NotificationContent)] = []
    }

    /// Mutable box so a test can change what `currentChargerSources` returns
    /// BETWEEN reconciles, without constructing a fresh sequencer (which
    /// would also reset `knownChargerCableLabels`, the exact state under
    /// test).
    private final class SourcesBox {
        var sources: [PowerSource] = []
    }

    private func makeSequencer(clock: ManualClock, posted: PostedLog, box: SourcesBox) -> DeviceDiffSequencer<ManualClock> {
        DeviceDiffSequencer(
            clock: clock,
            currentDevices: { [] },
            currentChargerSources: { box.sources },
            currentPorts: { [] },
            currentAdapter: { nil },
            notifyOnChanges: { true },
            post: { category, content, _ in posted.entries.append((category, content)) },
            launchToken: "test-launch"
        )
    }

    // MARK: - Tests

    /// One added charger port, with a name in the feed: the name goes in
    /// the subtitle, and the body stays the bare wattage untouched.
    func testOneAddedChargerWithANameNamesTheSubtitle() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [magSafeKey: "Kitchen MagSafe"]))
        box.sources = [negotiatedSource(port: 17, id: 1, watts: 30)]
        sequencer.reconcileChargers()
        await clock.settle()

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(posted.entries[0].1, NotificationContent(
            title: "Charger connected", subtitle: "Kitchen MagSafe", body: "30W negotiated"
        ))
    }

    /// The same port disconnects later: the name captured at connect time
    /// still appears on the disconnect banner, even though the live feed no
    /// longer names the port by then (the cable is already gone, same as
    /// the charger).
    func testDisconnectAfterNamedConnectStillNamesTheDisconnectBanner() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [magSafeKey: "Kitchen MagSafe"]))
        box.sources = [negotiatedSource(port: 17, id: 1, watts: 30)]
        sequencer.reconcileChargers()
        await clock.settle()

        // The feed loses the attribution the moment the cable itself is
        // gone, same as production: nothing left to attribute a name to.
        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = []
        sequencer.reconcileChargers()
        await clock.settle()

        XCTAssertEqual(posted.entries.count, 2)
        XCTAssertEqual(posted.entries[1].1, NotificationContent(
            title: "Charger disconnected", subtitle: "Kitchen MagSafe", body: "30W negotiated"
        ))
    }

    /// Two ports added in the same reconcile, only one named: a subtitle
    /// can't say which port the name belongs to, so it stays empty, and
    /// only the named line's body carries the "(name)" suffix.
    func testTwoAddedPortsOneNamedGetsNoSubtitleAndOnlyThatLineIsSuffixed() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [magSafeKey: "Kitchen MagSafe"]))
        box.sources = [
            negotiatedSource(port: 17, id: 1, watts: 30),
            negotiatedSource(port: 2, id: 2, watts: 65)
        ]
        sequencer.reconcileChargers()
        await clock.settle()
        // No cable-name grace here (issue #593): the USB-C port is not in
        // `portsAwaitingCableIdentity`, so its chip has already answered and
        // an absent name means the cable simply is not saved. Nothing to
        // wait for, so the banner posts on this pass.
        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(posted.entries[0].1, NotificationContent(
            title: "Charger connected",
            body: "30W negotiated (Kitchen MagSafe)\n65W negotiated"
        ))
    }

    /// No saved cables anywhere: output must be byte-identical to before
    /// this feature, subtitle included. Pins the exact strings so a future
    /// leak (a name showing up when it shouldn't) fails right here.
    func testNoNamesAnywhereIsByteIdenticalToToday() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // No `updateLabelledCables` call at all: `knownLabelledCablesByPort`
        // stays nil, the unavailable state, same as a free/locked build.
        box.sources = [negotiatedSource(port: 17, id: 1, watts: 30)]
        sequencer.reconcileChargers()
        await clock.settle()

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(posted.entries[0].1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        XCTAssertEqual(posted.entries[0].1.subtitle, "")
    }

    /// A name that resolves AFTER the connect banner already posted (the
    /// e-marker read finishing later than the charger settle) still reaches
    /// the eventual disconnect banner: `updateLabelledCables` refreshes
    /// `knownChargerCableLabels` for any port already in `knownChargerLabels`.
    func testNameArrivingAfterTheConnectBannerStillNamesTheDisconnectBanner() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // Connect settles with NOTHING in the feed yet.
        box.sources = [negotiatedSource(port: 17, id: 1, watts: 30)]
        sequencer.reconcileChargers()
        await clock.settle()

        // The name resolves afterward.
        sequencer.updateLabelledCables(feed(byPort: [magSafeKey: "Kitchen MagSafe"]))

        box.sources = []
        sequencer.reconcileChargers()
        await clock.settle()

        XCTAssertEqual(posted.entries.count, 2)
        XCTAssertEqual(posted.entries[0].1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        XCTAssertEqual(posted.entries[1].1, NotificationContent(
            title: "Charger disconnected", subtitle: "Kitchen MagSafe", body: "30W negotiated"
        ))
    }

    /// A port whose charger disconnected and later reconnected with no
    /// cable attributed this time must NOT inherit the name from its
    /// earlier connection.
    func testAPortThatReturnsWithNoCableAttributedDoesNotInheritTheOldName() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // First connection, named.
        sequencer.updateLabelledCables(feed(byPort: [magSafeKey: "Kitchen MagSafe"]))
        box.sources = [negotiatedSource(port: 17, id: 1, watts: 30)]
        sequencer.reconcileChargers()
        await clock.settle()

        // Disconnect.
        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = []
        sequencer.reconcileChargers()
        await clock.settle()

        // Reconnect on the SAME port, no cable attributed this time. No
        // cable-name grace (issue #593): the port is not in
        // `portsAwaitingCableIdentity`, so there is no name still coming.
        box.sources = [negotiatedSource(port: 17, id: 2, watts: 30)]
        sequencer.reconcileChargers()
        await clock.settle()

        XCTAssertEqual(posted.entries.count, 3)
        XCTAssertEqual(posted.entries[2].1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        XCTAssertEqual(posted.entries[2].1.subtitle, "")

        // The real risk isn't the connect banner above (added lines always
        // read the LIVE feed, never the captured map, so a stale captured
        // name could never surface there even if it were still sitting in
        // `knownChargerCableLabels`). It's this SECOND disconnect: if the
        // first disconnect hadn't dropped the captured entry, it would
        // still be sitting there for this port to inherit now, with no
        // cable ever having been attributed to this second connection.
        box.sources = []
        sequencer.reconcileChargers()
        await clock.settle()

        XCTAssertEqual(posted.entries.count, 4)
        XCTAssertEqual(posted.entries[3].1, NotificationContent(title: "Charger disconnected", body: "30W negotiated"))
        XCTAssertEqual(posted.entries[3].1.subtitle, "")
    }

    /// Review finding: a name captured while Pro was unlocked must not
    /// survive a licence lock and reach a banner posted while locked.
    /// Reachable path: a charger's cable gets named, the user deactivates
    /// Pro (`NotificationCableLabelProvider.snapshot` -> nil, folded into a
    /// nil feed), then the charger disconnects. `reconcileChargers` builds
    /// the disconnect line from `knownChargerCableLabels`, not the live
    /// feed, so without a clear on the nil feed the pre-lock name would
    /// leak into a locked build's own notification.
    func testALockedLicenceFeedDoesNotLeakTheCapturedNameIntoTheDisconnectBanner() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // Connect while unlocked and named.
        sequencer.updateLabelledCables(feed(byPort: [magSafeKey: "Kitchen MagSafe"]))
        box.sources = [negotiatedSource(port: 17, id: 1, watts: 30)]
        sequencer.reconcileChargers()
        await clock.settle()

        // Pro locks: the provider now returns nil, folded into a nil feed.
        sequencer.updateLabelledCables(nil)

        // The charger disconnects while still locked.
        box.sources = []
        sequencer.reconcileChargers()
        await clock.settle()

        XCTAssertEqual(posted.entries.count, 2)
        XCTAssertEqual(posted.entries[1].1, NotificationContent(title: "Charger disconnected", body: "30W negotiated"))
        XCTAssertEqual(posted.entries[1].1.subtitle, "")
    }
}
