import XCTest
@testable import WhatCableNotifications
import WhatCableCore

/// Issue #593: `knownChargerCableLabels`, the per-port name captured at
/// connect so a DISCONNECT banner can still name its cable (by disconnect
/// time the cable is gone and the live feed no longer attributes it).
///
/// These tests own the three-way decision in `refreshCapturedCableName`,
/// which was write-only before the F3/F4 review findings:
///
///  - the feed NAMES the port: capture.
///  - the feed says RESOLVED and does not name it: clear. The chip answered
///    and no name applies.
///  - NEITHER: hold. The port is not in the feed's connected sets at all, so
///    this is a gap, not a withdrawal.
///
/// Plus the load-bearing gate that keeps a name seen while a port was a plain
/// data port from surfacing when that same port later becomes a charger. That
/// gate shipped with a comment calling it load-bearing and no test behind it:
/// it could be deleted with the whole suite staying green (F4).
@MainActor
final class ChargerCapturedCableNameTests: XCTestCase {

    private let key = "2/1"

    private final class PostedLog {
        var entries: [(NotificationCategory, NotificationContent)] = []
    }
    private final class SourcesBox { var sources: [PowerSource] = [] }

    private func flush(_ clock: ManualClock) async { await clock.settle() }

    private func makeSequencer(
        clock: ManualClock, posted: PostedLog, box: SourcesBox
    ) -> DeviceDiffSequencer<ManualClock> {
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

    private func source() -> PowerSource {
        PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1, options: [],
            winning: PowerOption(voltageMV: 20000, maxCurrentMA: 1500, maxPowerMW: 30000)
        )
    }

    /// `awaiting` empty and `resolved` carrying the port is "the chip has
    /// answered"; passing `resolved: []` with `awaiting: []` too is the
    /// feed-gap shape (the port is in neither set, so it is not connected).
    private func feed(
        byPort: [String: String],
        resolved: Set<String>,
        hasSavedCables: Bool = true
    ) -> NotificationDecision.CableLabelFeed {
        NotificationDecision.CableLabelFeed(
            hasSavedCables: hasSavedCables,
            attachedLabelled: [:],
            attachedLabelledByPort: byPort,
            portsAwaitingCableIdentity: [],
            portsWithResolvedCableIdentity: resolved
        )
    }

    /// Connects a named charger on `key` and returns once its banner posted.
    private func connectNamed(
        _ sequencer: DeviceDiffSequencer<ManualClock>, _ box: SourcesBox, _ clock: ManualClock,
        name: String = "Desk cable"
    ) async {
        sequencer.updateLabelledCables(feed(byPort: [key: name], resolved: [key]))
        box.sources = [source()]
        sequencer.reconcileChargers()
        await flush(clock)
    }

    // MARK: - The gate (F4): a name seen while the port held no charger

    /// The `knownChargerLabels` gate on the refresh pass. A saved cable in a
    /// plain DATA port is named by the feed like any other; capturing that
    /// name would leave it sitting there to surface the first time that same
    /// port later becomes a charger, naming a completely different cable.
    ///
    /// Red-proof: drop the `for portKey in knownChargerLabels.keys` gate in
    /// `updateLabelledCables` and refresh from the feed's own name map
    /// instead. Goes red on the disconnect banner
    /// ("XCTAssertEqual failed: ("Desk cable") is not equal to ("")").
    func testANameSeenWhileThePortWasADataPortMustNotNameALaterCharger() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // A saved cable is attached to a plain data port. Named, no charger.
        sequencer.updateLabelledCables(feed(byPort: [key: "Desk cable"], resolved: [key]))
        await flush(clock)

        // That cable goes, an UNSAVED charger cable goes into the same port,
        // and the feed is in a GAP for this port (nothing published about it
        // yet) at the moment the charger settles. The gap is what stops the
        // three-way clear from tidying up after a removed gate, so this test
        // pins the gate itself rather than the clear.
        sequencer.updateLabelledCables(feed(byPort: [:], resolved: []))
        box.sources = [source()]
        sequencer.reconcileChargers()
        await flush(clock)
        await clock.advance(by: .seconds(5))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(posted.entries[0].1.subtitle, "", "connect banner must not name an unsaved cable")

        // Unplug. The disconnect line reads the captured map, which is where
        // a name captured while the port held no charger would be waiting.
        box.sources = []
        sequencer.reconcileChargers()
        await flush(clock)
        await clock.advance(by: .seconds(5))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 2)
        XCTAssertEqual(
            posted.entries[1].1.subtitle, "",
            "the disconnect banner must not carry a name captured while the port held no charger"
        )
    }

    // MARK: - The clear (F3 / H4): a withdrawn attribution

    /// The user deletes the saved cable while its charger stays plugged in.
    /// The feed republishes with the port RESOLVED and unnamed, which is an
    /// unambiguous "the chip answered and no name applies". The captured name
    /// has to go, or the eventual disconnect banner names a cable the user
    /// has deleted.
    ///
    /// Red-proof: delete the `resolvedPorts` clear branch in
    /// `refreshCapturedCableName` (return after the name check). Goes red
    /// with `("Desk cable")` instead of `("")`.
    func testDeletingTheSavedCableWhileItsChargerIsAttachedClearsTheCapturedName() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        await connectNamed(sequencer, box, clock)
        XCTAssertEqual(posted.entries.first?.1.subtitle, "Desk cable")

        // Deleted: nothing saved anywhere now, and the port is resolved.
        sequencer.updateLabelledCables(feed(byPort: [:], resolved: [key], hasSavedCables: false))
        await flush(clock)

        box.sources = []
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 2)
        XCTAssertEqual(
            posted.entries[1].1.subtitle, "",
            "the cable was deleted, so the disconnect banner must not still name it"
        )
    }

    /// The same rule reached through the OTHER sequence the review named: a
    /// named cable swapped for an unsaved one on the same port, fast enough
    /// that the charger never dropped out of `knownChargerLabels`. There is
    /// no removal to trigger the drop-at-disconnect path, so only the clear
    /// can stop cable A's name describing cable B.
    ///
    /// Red-proof: same as above. Goes red with `("Desk cable")` instead of
    /// `("")`.
    func testACableSwappedForAnUnsavedOneInsideTheDebounceLosesTheOldName() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        await connectNamed(sequencer, box, clock)

        // Cable B, unsaved, on the same port. The charger source never went
        // away, so no add and no remove: the reconcile below is a no-op for
        // the diff, and only the refresh pass can act.
        sequencer.updateLabelledCables(feed(byPort: [:], resolved: [key]))
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 1, "no add or remove, so that reconcile posts nothing")

        box.sources = []
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 2)
        XCTAssertEqual(
            posted.entries[1].1.subtitle, "",
            "cable A's name must not describe the unsaved cable B that replaced it"
        )
    }

    // MARK: - The hold: a feed gap is not a withdrawal

    // MARK: - The nil-feed contract the clear leans on

    /// N3 review finding. `refreshCapturedCableName` has no "is the feed
    /// available" parameter: an earlier draft did, and removing it was
    /// correct, because the resolved set is emptied on a nil feed and so the
    /// membership test is already false in exactly the case that guard
    /// claimed to cover. But nothing pinned the emptying, so the removal's
    /// own justification rested on an untested property: the same "a gate
    /// nobody has watched fail" pattern that produced the F4 finding.
    ///
    /// Pinned as a property rather than through a banner deliberately. No
    /// behaviour depends on it today (the wholesale
    /// `knownChargerCableLabels = [:]` on a nil feed is what actually
    /// protects the licence-lock case, and that IS covered by
    /// `testALockedLicenceFeedDoesNotLeakTheCapturedNameIntoTheDisconnectBanner`),
    /// so a behavioural test would pass either way and prove nothing. This is
    /// the invariant the clear's reasoning leans on, asserted where it lives.
    ///
    /// Red-proof: make the assignment sticky
    /// (`feed?.portsWithResolvedCableIdentity ?? knownPortsWithResolvedCableIdentity`).
    /// Goes red with the set still holding the port.
    func testANilFeedEmptiesBothIdentitySets() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(NotificationDecision.CableLabelFeed(
            hasSavedCables: true,
            attachedLabelled: [:],
            attachedLabelledByPort: [:],
            portsAwaitingCableIdentity: ["awaiting-port"],
            portsWithResolvedCableIdentity: [key]
        ))
        XCTAssertEqual(sequencer.knownPortsWithResolvedCableIdentity, [key], "control: the feed populated it")
        XCTAssertEqual(sequencer.knownPortsAwaitingCableIdentity, ["awaiting-port"])

        // Pro deactivates: the provider returns nil, folded into a nil feed.
        sequencer.updateLabelledCables(nil)

        XCTAssertTrue(
            sequencer.knownPortsWithResolvedCableIdentity.isEmpty,
            "a nil feed must empty the resolved set: the clear in refreshCapturedCableName relies on it"
        )
        XCTAssertTrue(
            sequencer.knownPortsAwaitingCableIdentity.isEmpty,
            "and the awaiting set, which gates the arming decision the same way"
        )
    }

    /// The third branch, and the reason the clear keys on PRESENCE in the
    /// resolved set rather than absence of a name. A port that is in neither
    /// identity set is not connected as far as the feed is concerned (a flap,
    /// or a publish that raced the port teardown), which says nothing about
    /// whether the name still applies. Clearing there would drop a good name
    /// over a momentary gap.
    ///
    /// Red-proof: make the clear unconditional (drop the `resolvedPorts`
    /// check so any unnamed refresh clears). Goes red with `("")` instead of
    /// `("Desk cable")`.
    func testAFeedGapHoldsTheCapturedNameRatherThanClearingIt() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        await connectNamed(sequencer, box, clock)

        // A gap: the port is in NEITHER set, and unnamed.
        sequencer.updateLabelledCables(feed(byPort: [:], resolved: []))
        await flush(clock)

        box.sources = []
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 2)
        XCTAssertEqual(
            posted.entries[1].1.subtitle, "Desk cable",
            "a momentary feed gap must not drop a name that was captured legitimately"
        )
    }
}
