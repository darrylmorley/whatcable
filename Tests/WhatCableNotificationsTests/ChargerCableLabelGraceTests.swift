import XCTest
@testable import WhatCableNotifications
import WhatCableCore

/// Issue #593, timing half. `NotificationManagerChargerCableNameTests` covers
/// WHAT a charger banner says once a name is known; this file covers WHEN it
/// is allowed to say it.
///
/// The problem: a USB-C cable's e-marker can resolve a second or two after
/// the port reports connected, which is later than the 1.5s charger settle,
/// so a connect banner can post before the name exists. A banner already on
/// screen cannot be corrected, so `reconcileChargers` waits one bounded
/// window (`chargerCableLabelGraceWindow`) for a name that could still
/// arrive, and posts regardless once that window is spent.
///
/// Deliberately NOT the device path's machinery (`pendingCableLabelEvent`,
/// `graceCableLabelEvent`, `heldDeviceBatch`, the 5s
/// `cablePlausibilityHoldWindow`). That exists because a USB device tree
/// cannot be tied to a physical port, so labels there are matched by timing.
/// The charger path joins by port identity and needs only a bounded wait.
///
/// Driven by `ManualClock` throughout, so every "at 200ms" / "at the cap"
/// claim below is an exact assertion, not a flake margin.
@MainActor
final class ChargerCableLabelGraceTests: XCTestCase {

    // MARK: - Fixtures

    /// A MagSafe port key. Matches `PowerSource.portKey` for
    /// `parentPortType: 17, parentPortNumber: 1` (no `hpmControllerUUID`, so
    /// `canonicalJoinKey` falls back to `portKey`).
    private let magSafeKey = "17/1"
    /// A second, USB-C port, for the cases where the grace waits on more than
    /// one port at once.
    private let usbcKey = "2/1"

    private func negotiatedSource(
        port: Int = 17, id: UInt64 = 1, watts: Int = 30, uuid: String? = nil
    ) -> PowerSource {
        PowerSource(
            id: id, name: "USB-PD",
            parentPortType: port, parentPortNumber: 1,
            options: [],
            winning: PowerOption(voltageMV: 20000, maxCurrentMA: watts * 1000 / 20, maxPowerMW: watts * 1000),
            hpmControllerUUID: uuid
        )
    }

    /// A resolved HPM controller UUID for the MagSafe port under test.
    ///
    /// Every other fixture in this file deliberately has none, which is stated
    /// at `magSafeKey`. That made the whole suite structurally blind to the
    /// change from grouping charger labels by `canonicalJoinKey` to grouping
    /// them by `portKey`: with no UUID the two keys are the same string, so no
    /// test here could have regressed, and none could confirm the change
    /// either. The four tests at the end of this file are the ones that can.
    private let magSafeUUID = "aaaabbbbccccddddeeeeffff00001111"

    /// The MagSafe port as the FEED publishes it once a UUID resolved: under
    /// both of its keys. `NotificationCableLabelProvider.joinAliases(of:)` writes
    /// every name and every identity-set membership twice, once under the port's
    /// join key and once under its plain `portKey`, and the charger side relies
    /// on that to find a name with a plain `portKey` lookup. Hand-built feeds
    /// have to mirror it or they are not testing the real shape.
    private var magSafeBothKeys: Set<String> { [magSafeUUID, magSafeKey] }

    /// A hub present in BOTH the baseline and the parked diff, plus a child
    /// arriving under it. Copied from `DeviceDiffSequencerCableLabelHoldTests`
    /// for one reason: the child's `ChangeGroup` root has a surviving
    /// ancestor, so `isPortLevelChange` is false and issue #570's 5s
    /// saved-cable HOLD never engages.
    ///
    /// That matters for the ordering test below. The charger grace only ever
    /// arms when a feed exists and saved cables exist, which is exactly the
    /// condition that makes the device path's own hold eligible too. A
    /// port-level device fixture would sit in that 5s hold and the ordering
    /// assertion would be measuring the hold, not the grace. An in-tree
    /// change isolates the one mechanism under test.
    private func hubDevice(id: UInt64, bus: UInt8 = 0x03) -> USBDevice {
        USBDevice(
            id: id, locationID: (UInt32(bus) << 24) | 0x0010_0000, vendorID: 0, productID: 0,
            vendorName: nil, productName: "Hub", serialNumber: nil,
            usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
    }

    private func childDevice(id: UInt64, bus: UInt8 = 0x03, name: String = "Mouse") -> USBDevice {
        USBDevice(
            id: id, locationID: (UInt32(bus) << 24) | 0x0011_0000, vendorID: 0, productID: 0,
            vendorName: nil, productName: name, serialNumber: nil,
            usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
    }

    /// `hasSavedCables: true` by default: the grace only ever arms for a
    /// user who HAS saved cables, so that is the interesting state, and the
    /// two tests that need `false` say so at the call site.
    /// `awaiting` defaults to the MagSafe port under test: these are timing
    /// tests, and the state they are about is "the chip has not answered
    /// yet, so a name may still be coming". The tests that need the opposite
    /// (the chip HAS answered) pass `awaiting: []` plus `resolved:
    /// [magSafeKey]` and say why at the call site.
    ///
    /// `awaiting` and `resolved` PARTITION the connected ports, exactly as
    /// the provider builds them: a port is in one or the other while it is
    /// connected, and in NEITHER once it is not. Every call site below keeps
    /// to that, and the one test that deliberately puts a port in neither
    /// (the flap) says so loudly.
    private func feed(
        byPort: [String: String],
        byCableID: [String: String] = [:],
        awaiting: Set<String>? = nil,
        resolved: Set<String> = [],
        hasSavedCables: Bool = true
    ) -> NotificationDecision.CableLabelFeed {
        NotificationDecision.CableLabelFeed(
            hasSavedCables: hasSavedCables,
            attachedLabelled: byCableID,
            attachedLabelledByPort: byPort,
            portsAwaitingCableIdentity: awaiting ?? [magSafeKey],
            portsWithResolvedCableIdentity: resolved
        )
    }

    /// A device plugged straight into a Mac port: its `ChangeGroup` root has
    /// no surviving ancestor, so `isPortLevelChange` is true and the batch
    /// is eligible for a saved-cable label. The opposite of `hubDevice` /
    /// `childDevice` below, and needed by the one test that cares which
    /// cable-label event a landing diff picks up.
    private func portLevelDevice(id: UInt64, bus: UInt8 = 0x02, name: String = "Cable Device") -> USBDevice {
        USBDevice(
            id: id, locationID: (UInt32(bus) << 24) | 0x0010_0000, vendorID: 0, productID: 0,
            vendorName: nil, productName: name, serialNumber: nil,
            usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
    }

    private final class PostedLog {
        var entries: [(NotificationCategory, NotificationContent)] = []
    }

    /// Mutable box so a test can change what `currentChargerSources` returns
    /// between reconciles without constructing a fresh sequencer (which
    /// would reset the very grace state under test).
    private final class SourcesBox {
        var sources: [PowerSource] = []
    }

    /// Same idea for the live device read, so a test can let the USB tree
    /// enumerate a beat after the charger's power source publishes.
    private final class DevicesBox {
        var devices: [USBDevice] = []
    }

    private func makeSequencer(
        clock: ManualClock,
        posted: PostedLog,
        box: SourcesBox,
        presentationGapWindow: Duration = DeviceDiffSequencer<ManualClock>.defaultPresentationGapWindow
    ) -> DeviceDiffSequencer<ManualClock> {
        DeviceDiffSequencer(
            clock: clock,
            currentDevices: { [] },
            currentChargerSources: { box.sources },
            currentPorts: { [] },
            currentAdapter: { nil },
            notifyOnChanges: { true },
            post: { category, content, _ in posted.entries.append((category, content)) },
            presentationGapWindow: presentationGapWindow,
            launchToken: "test-launch"
        )
    }

    /// A freshly-created `Task { @MainActor ... }` is enqueued, not run
    /// inline, so it hasn't registered its `clock.sleep` waiter yet. Call
    /// this after anything that arms a task and before the `advance` meant
    /// to fire it. Same helper, same reasoning, as `DeviceDiffSequencerTests`.
    private func flush(_ clock: ManualClock) async {
        await clock.settle()
    }

    private var graceWindow: Duration { DeviceDiffSequencer<ManualClock>.chargerCableLabelGraceWindow }

    // MARK: - The early collapse

    /// The common case, and the reason the grace isn't just a flat delay: a
    /// name that resolves 200ms after the settle must produce the banner at
    /// 200ms, named, not at the full grace cap. `updateLabelledCables` is
    /// what collapses the wait the moment it supplies a name for a port the
    /// grace is waiting on.
    ///
    /// Red-proof: delete the early-collapse block in
    /// `updateLabelledCables`. Goes red at the 200ms assertion
    /// ("XCTAssertEqual failed: ("0") is not equal to ("1")"): the banner is
    /// still correct 1.3s later, but the user waited the whole window for a
    /// name that was ready almost immediately.
    func testANameArrivingDuringTheGraceCollapsesItImmediately() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // Saved cables exist, but nothing is attributed to this port yet:
        // exactly the state a USB-C plug is in while its e-marker read is
        // still outstanding.
        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 0, "an added port with no name yet must wait, not post unnamed")

        await clock.advance(by: .milliseconds(200))
        XCTAssertEqual(posted.entries.count, 0, "still nothing 200ms in, before the name arrives")

        // The e-marker resolves and the feed republishes.
        sequencer.updateLabelledCables(feed(byPort: [magSafeKey: "Kitchen MagSafe"], awaiting: [], resolved: [magSafeKey]))
        await flush(clock)

        XCTAssertEqual(
            posted.entries.count, 1,
            "the name arriving must collapse the grace and post right away, not wait out the rest of the window"
        )
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(
            title: "Charger connected", subtitle: "Kitchen MagSafe", body: "30W negotiated"
        ))

        // Out past the cap: the armed task must have been cancelled, not
        // left to wake and post a second, duplicate banner.
        await clock.advance(by: graceWindow)
        XCTAssertEqual(posted.entries.count, 1, "the collapsed grace's own task must not post again at the cap")
        await clock.advance(by: .seconds(10))
    }

    /// The other half of the collapse, and the one that removes most of the
    /// remaining latency: the waited-on port's chip answers, and the answer
    /// is "not a saved cable". No name is ever coming, so the banner must
    /// post unnamed AT THAT MOMENT rather than sitting out the rest of the
    /// cap.
    ///
    /// This is not a tail case. A USB-C e-marker is readable a variable
    /// ~2-3s after plug against a 1.5s charger settle, so most USB-C charger
    /// plugs are still awaiting identity when the settle runs and do arm the
    /// grace. The saved ones collapse on the name (test above); without this
    /// half, every unsaved one paid the full window.
    ///
    /// Red-proof: drop `|| feed.portsWithResolvedCableIdentity.contains($0)`
    /// from the collapse condition in `updateLabelledCables`. Goes red at
    /// the 200ms assertion ("XCTAssertEqual failed: ("0") is not equal to
    /// ("1")"): the banner is still correct at the cap, but the user waited
    /// 1.3s longer than there was any reason to.
    func testAWaitedOnPortResolvingToAnUnsavedCableCollapsesTheGrace() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "an added port with no answer yet must wait")

        await clock.advance(by: .milliseconds(200))
        XCTAssertEqual(posted.entries.count, 0, "still nothing 200ms in, before the chip answers")

        // The e-marker resolves. It attributes to nothing (this cable is not
        // saved), so the port moves to the resolved half of the partition
        // with no name alongside it.
        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: [], resolved: [magSafeKey]))
        await flush(clock)

        XCTAssertEqual(
            posted.entries.count, 1,
            "the chip answered and produced no name, so there is nothing left to wait for"
        )
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        XCTAssertEqual(posted.entries.first?.1.subtitle, "", "no name resolved, so no subtitle")

        await clock.advance(by: graceWindow)
        XCTAssertEqual(posted.entries.count, 1, "the collapsed grace's own task must not post again at the cap")
        await clock.advance(by: .seconds(10))
    }

    /// The flap, and the reason the collapse tests PRESENCE in the resolved
    /// set rather than ABSENCE from the awaiting set. A USB-C port can drop
    /// out and return during PD renegotiation (the same flap
    /// `chargerSettleWindow` exists to absorb). While it is out it is in
    /// NEITHER set, which says "nothing to go on", not "the chip answered".
    ///
    /// So the flap publish must collapse nothing, and the name arriving
    /// afterwards must still land on the banner. Collapsing on absence would
    /// end the grace on the flap and post unnamed a moment before the name
    /// it was waiting for actually arrived, which is the exact outcome this
    /// whole mechanism exists to prevent.
    ///
    /// Red-proof: change the collapse's second arm to
    /// `!feed.portsAwaitingCableIdentity.contains($0)` (collapse on absence
    /// from the awaiting set). Goes red twice: first at the flap assertion
    /// ("XCTAssertEqual failed: ("1") is not equal to ("0")"), then on the
    /// subtitle, which comes back "" instead of "Kitchen MagSafe". That
    /// second failure is the actual user harm: a lost cable name.
    func testAFlappingPortInNeitherSetDoesNotCollapseTheGrace() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "an added port with no answer yet must wait")

        await clock.advance(by: .milliseconds(200))

        // The port flaps out mid-read: not connected, so it is in NEITHER
        // set. Deliberately inconsistent with the partition every other call
        // site keeps to, because that is exactly what a flap looks like.
        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: [], resolved: []))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.count, 0,
            "a port in neither set has not answered, it has gone away: the grace must run on"
        )

        // It comes back, and this time the e-marker resolves to a saved
        // cable. The name still reaches the banner.
        await clock.advance(by: .milliseconds(200))
        sequencer.updateLabelledCables(feed(
            byPort: [magSafeKey: "Kitchen MagSafe"], awaiting: [], resolved: [magSafeKey]
        ))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(
            posted.entries.first?.1,
            NotificationContent(title: "Charger connected", subtitle: "Kitchen MagSafe", body: "30W negotiated"),
            "collapsing on the flap would have posted this banner unnamed, 200ms before the name arrived"
        )
        await clock.advance(by: .seconds(10))
    }

    /// The NAME arm of the collapse, on its own. In every realistic feed a
    /// named port is also a resolved one (a name can only come from an
    /// attribution, and attribution needs `canTrack`), so the two arms
    /// normally fire together and no realistic test can tell them apart.
    /// This one uses a deliberately partition-inconsistent feed, naming a
    /// port without listing it as resolved, which is the only way to
    /// exercise the name arm alone.
    ///
    /// Worth keeping rather than deleting the arm as redundant: the provider
    /// invariant that makes it redundant lives in `WhatCablePlugins`, the
    /// sequencer cannot enforce it, and `foldLabelledCables` unions across
    /// providers, so nothing here should depend on every future provider
    /// reporting both facts consistently. A name is sufficient on its own.
    ///
    /// Red-proof: drop `feed.attachedLabelledByPort[$0] != nil ||` from the
    /// collapse condition. Goes red at the collapse assertion
    /// ("XCTAssertEqual failed: ("0") is not equal to ("1")"); nothing else
    /// in the suite notices, which is exactly the point.
    func testANameAloneCollapsesTheGraceEvenWithoutAResolvedFlag() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0)

        await clock.advance(by: .milliseconds(200))

        // Named, but NOT reported resolved: a shape the shipping provider
        // never produces, standing in for any future provider that reports
        // one fact and not the other.
        sequencer.updateLabelledCables(feed(
            byPort: [magSafeKey: "Kitchen MagSafe"], awaiting: [], resolved: []
        ))
        await flush(clock)

        XCTAssertEqual(
            posted.entries.count, 1,
            "a name is sufficient on its own: the sequencer must not require the resolved flag alongside it"
        )
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(
            title: "Charger connected", subtitle: "Kitchen MagSafe", body: "30W negotiated"
        ))
        await clock.advance(by: .seconds(10))
    }

    // MARK: - The cap

    /// A name that never arrives (the cable simply isn't saved, or the
    /// e-marker never resolves) must not silence the banner: it posts
    /// unnamed once the grace window is spent, and not one millisecond
    /// before.
    ///
    /// Red-proof: make `armChargerCableLabelGrace` set its state but skip
    /// scheduling the task. Goes red at the cap ("XCTAssertEqual failed:
    /// ("0") is not equal to ("1")"): nothing ever wakes the second pass, so
    /// the charger connect is swallowed entirely.
    func testANameThatNeverArrivesPostsUnnamedAtTheGraceCap() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)

        await clock.advance(by: graceWindow - .milliseconds(1))
        XCTAssertEqual(posted.entries.count, 0, "must not post one millisecond before the grace window elapses")

        await clock.advance(by: .milliseconds(1))
        XCTAssertEqual(posted.entries.count, 1, "the grace is a cap, not a condition: the banner posts regardless")
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        XCTAssertEqual(posted.entries.first?.1.subtitle, "", "no name resolved, so no subtitle")
        await clock.advance(by: .seconds(10))
    }

    // MARK: - One grace per charger event

    /// The budget is per charger event, spent at the first wait. A second
    /// reconcile inside the same event (no intervening `diffSources`) must
    /// proceed and post, named or not, rather than arming a fresh wait. If
    /// it re-armed, a charger whose cable is simply not saved could be
    /// deferred forever and never produce a banner at all.
    ///
    /// Red-proof: remove `chargerCableLabelGraceUsed = true` from
    /// `armChargerCableLabelGrace`. Goes red immediately after the second
    /// reconcile ("XCTAssertEqual failed: ("0") is not equal to ("1")"):
    /// that call re-arms instead of posting.
    func testTheGraceIsUsedAtMostOncePerChargerEvent() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "first pass waits")

        // A second reconcile in the SAME charger event: the grace is spent,
        // so this one has to finish the job.
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 1, "a second reconcile in the same event must post, not wait again")
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(title: "Charger connected", body: "30W negotiated"))

        // The first pass's armed task must not wake later and post again.
        await clock.advance(by: graceWindow)
        XCTAssertEqual(posted.entries.count, 1, "the superseded grace task must not produce a duplicate banner")
        await clock.advance(by: .seconds(10))
    }

    // MARK: - When no grace applies at all

    /// A user with no saved cables anywhere has provably no name coming, so
    /// there is nothing to wait for: the banner posts at the charger settle
    /// window, 1.5s, exactly as it did before this change.
    ///
    /// Drives `diffSources` rather than `reconcileChargers` directly,
    /// because the claim being pinned is about total elapsed time from the
    /// raw publish, not just about the reconcile.
    ///
    /// Red-proof: drop `knownHasSavedCables` from the grace guard in
    /// `reconcileChargers`. Goes red at the 1.5s assertion
    /// ("XCTAssertEqual failed: ("0") is not equal to ("1")"): every charger
    /// plug on a free-of-saved-cables install would gain a second of delay
    /// for nothing.
    func testNoSavedCablesMeansNoGraceAndTheBannerPostsAtTheSettleWindow() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // A real feed (Pro unlocked, so not nil), but the user has saved no
        // cables: `hasSavedCables` false is the whole difference from the
        // waiting cases above.
        sequencer.updateLabelledCables(feed(byPort: [:], hasSavedCables: false))
        box.sources = [negotiatedSource()]
        sequencer.diffSources([])
        await flush(clock)

        await clock.advance(by: DeviceDiffSequencer<ManualClock>.defaultChargerSettleWindow - .milliseconds(1))
        XCTAssertEqual(posted.entries.count, 0, "still inside the ordinary charger settle window")

        await clock.advance(by: .milliseconds(1))
        XCTAssertEqual(
            posted.entries.count, 1,
            "with no saved cables there is nothing to wait for: the banner must post at the settle window"
        )
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        await clock.advance(by: .seconds(10))
    }

    /// F3, and the case this whole narrowing exists for: the user HAS saved
    /// cables, the feed IS available, and the added port still has no name,
    /// but its chip has already answered (it is not in
    /// `portsAwaitingCableIdentity`). An absent name there means the cable
    /// simply is not saved, so there is nothing to wait for and the banner
    /// posts at the settle window.
    ///
    /// This is the common case for anyone with saved cables: before the
    /// narrowing, every plug of an unsaved cable paid a full grace window
    /// for a name that was never coming.
    ///
    /// Red-proof: drop `&& knownPortsAwaitingCableIdentity.contains($0)`
    /// from the grace guard in `reconcileChargers`. Goes red at the 1.5s
    /// assertion ("XCTAssertEqual failed: ("0") is not equal to ("1")"),
    /// which is exactly the regression the narrowing removes.
    func testAnIdentifiedButUnsavedPortDoesNotGrace() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // Saved cables exist and the feed is live, but NOTHING is awaiting:
        // this port's cable identified itself and did not match anything
        // saved. The only difference from the graced cases above.
        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: [], resolved: [magSafeKey]))
        box.sources = [negotiatedSource()]
        sequencer.diffSources([])
        await flush(clock)

        await clock.advance(by: DeviceDiffSequencer<ManualClock>.defaultChargerSettleWindow - .milliseconds(1))
        XCTAssertEqual(posted.entries.count, 0, "still inside the ordinary charger settle window")

        await clock.advance(by: .milliseconds(1))
        XCTAssertEqual(
            posted.entries.count, 1,
            "an already-identified cable will never gain a name, so its charger must not wait for one"
        )
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        XCTAssertEqual(posted.entries.first?.1.subtitle, "")
        await clock.advance(by: .seconds(10))
    }

    /// The positive half of the same rule, stated on its own rather than
    /// left implicit in the timing tests above: a port that IS awaiting
    /// identity still graces. Same fixtures as the test above, one field
    /// different, so the pair isolates exactly what
    /// `portsAwaitingCableIdentity` decides.
    ///
    /// Red-proof: make the guard's filter `namesByPort[$0] == nil && false`
    /// (never wait). Goes red at the settle-window assertion
    /// ("XCTAssertEqual failed: ("1") is not equal to ("0")"): the banner
    /// posts unnamed at 1.5s instead of waiting for the name that was
    /// genuinely still coming.
    func testAPortStillAwaitingIdentityDoesGrace() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: [magSafeKey]))
        box.sources = [negotiatedSource()]
        sequencer.diffSources([])
        await flush(clock)

        await clock.advance(by: DeviceDiffSequencer<ManualClock>.defaultChargerSettleWindow)
        await flush(clock)
        XCTAssertEqual(
            posted.entries.count, 0,
            "the chip has not answered yet, so the settle must hand off to the grace rather than post"
        )

        // The name lands during the grace and collapses it.
        sequencer.updateLabelledCables(feed(byPort: [magSafeKey: "Kitchen MagSafe"], awaiting: [], resolved: [magSafeKey]))
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(
            title: "Charger connected", subtitle: "Kitchen MagSafe", body: "30W negotiated"
        ))
        await clock.advance(by: .seconds(10))
    }

    /// A free or licence-locked build gets no feed at all
    /// (`updateLabelledCables` is either never called or called with nil),
    /// so there is no name map to join against and no grace: same 1.5s as
    /// before this change.
    ///
    /// Red-proof: replace the whole grace guard with a bare
    /// `if !chargerCableLabelGraceUsed`, arming on any unnamed added port
    /// regardless of the feed. Goes red at the 1.5s assertion
    /// ("XCTAssertEqual failed: ("0") is not equal to ("1")").
    ///
    /// Note, honestly: the guard's nil arm and its `knownHasSavedCables` arm
    /// cannot be red-proofed independently through the public API, because
    /// `updateLabelledCables` derives `knownHasSavedCables` from the same
    /// optional (`feed?.hasSavedCables ?? false`), so a nil feed always
    /// forces it false. Removing either arm alone leaves the other still
    /// blocking. They are two expressions of one fact and are proved as one.
    func testAnUnavailableFeedMeansNoGraceAndTheBannerPostsAtTheSettleWindow() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // No `updateLabelledCables` call at all: `knownLabelledCablesByPort`
        // stays nil, the unavailable state.
        box.sources = [negotiatedSource()]
        sequencer.diffSources([])
        await flush(clock)

        await clock.advance(by: DeviceDiffSequencer<ManualClock>.defaultChargerSettleWindow - .milliseconds(1))
        XCTAssertEqual(posted.entries.count, 0, "still inside the ordinary charger settle window")

        await clock.advance(by: .milliseconds(1))
        XCTAssertEqual(
            posted.entries.count, 1,
            "an unavailable feed can never supply a name, so a locked build must not wait for one"
        )
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        await clock.advance(by: .seconds(10))
    }

    // MARK: - A charger event is still in flight during the grace

    /// F1 review finding, a MEASURED ordering regression against the base
    /// commit. The charger settle task clears `isChargerSettlePending` and
    /// THEN calls `reconcileChargers()`. Before the grace that was safe: the
    /// reconcile posted synchronously in the same turn, so the flag going
    /// false and the banner going out were the same instant. The grace return
    /// opens a window, up to `chargerCableLabelGraceWindow` long, where the
    /// flag reads false and a charger banner is still owed.
    ///
    /// A device settle landing in that window used to take `.runNow`, find
    /// `lastChargerPostTime` untouched (the first pass posted nothing, so
    /// there was nothing recent to space against either) and post the device
    /// banner FIRST. That is the inversion the park/defer/gap machinery
    /// exists to prevent, and `467e1e61` does not have it.
    ///
    /// The device change is IN-TREE on purpose: a port-level batch would sit
    /// in issue #570's 5s hold and mask the inversion, so this shape (a hub
    /// already attached, then a charger plus a downstream device) is the one
    /// that actually reaches the router.
    ///
    /// Red-proof: route `scheduleDeviceDiff` on `isChargerSettlePending`
    /// again instead of `isChargerEventInFlight`. Goes red at the t=1510
    /// assertion ("XCTAssertTrue failed - a device banner here beats the
    /// charger banner the grace is still waiting to post. Got: [device]") and
    /// then on the final ordering with `[device, charger]`.
    func testADeviceSettleInsideTheGraceMustNotPostAheadOfTheChargerBanner() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let devices = DevicesBox()
        let sequencer = DeviceDiffSequencer(
            clock: clock,
            currentDevices: { devices.devices },
            currentChargerSources: { box.sources },
            currentPorts: { [] },
            currentAdapter: { nil },
            notifyOnChanges: { true },
            post: { category, content, _ in posted.entries.append((category, content)) },
            presentationGapWindow: .milliseconds(30),
            launchToken: "test-launch"
        )
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [
            900: USBDeviceChangeGrouper.Snapshot(id: 900, locationID: 0x03_10_00_00, name: "Hub")
        ]
        sequencer.knownChargerLabels = [:]
        sequencer.updateLabelledCables(feed(byPort: [:]))

        // t=0: the charger's PowerSource publishes.
        box.sources = [negotiatedSource()]
        sequencer.diffSources([])
        await flush(clock)

        // t=10: the dock's USB tree enumerates.
        await clock.advance(by: .milliseconds(10))
        devices.devices = [hubDevice(id: 900), childDevice(id: 901)]
        sequencer.scheduleDeviceDiff()
        await flush(clock)

        // t=1500: the charger settle fires, arms the grace, posts nothing.
        await clock.advance(by: .milliseconds(1490))
        await flush(clock)
        XCTAssertTrue(posted.entries.isEmpty, "the grace return posts nothing")

        // t=1510: the device settle fires, inside the grace window.
        await clock.advance(by: .milliseconds(10))
        await flush(clock)
        XCTAssertTrue(
            posted.entries.isEmpty,
            "a device banner here beats the charger banner the grace is still waiting to post. Got: \(posted.entries.map(\.0))"
        )

        // t=3000: the grace expires and the charger banner posts.
        await clock.advance(by: .milliseconds(1490))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0), [.charger],
            "the charger banner must be first. Got: \(posted.entries.map(\.0))"
        )

        // The parked device diff follows, after the presentation gap.
        await clock.advance(by: .milliseconds(30))
        await flush(clock)
        XCTAssertEqual(posted.entries.map(\.0), [.charger, .device])
        await clock.advance(by: .seconds(10))
    }

    // MARK: - The grace waits for EVERY port it armed on

    /// H3 review finding. A grace can wait on several ports at once, and the
    /// reconcile it wakes posts ONE banner covering all of them. Collapsing
    /// as soon as ANY waited-on port settled published that banner while the
    /// other port's name was still on its way, and a banner already on screen
    /// cannot be corrected: the second port's saved name was lost outright.
    ///
    /// Here the unsaved cable resolves first and the saved one second, which
    /// is the order that loses the name.
    ///
    /// Red-proof: change the collapse back to `contains(where:)`. Goes red at
    /// the first-resolution assertion ("XCTAssertEqual failed: ("1") is not
    /// equal to ("0")"), and the banner it posts there carries no name for
    /// the MagSafe port at all.
    func testTheGraceWaitsForEveryPortNotJustTheFirstToSettle() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // Two charger ports arrive together, neither identified yet.
        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: [magSafeKey, usbcKey]))
        box.sources = [
            negotiatedSource(),
            negotiatedSource(port: 2, id: 2, watts: 65)
        ]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "both ports are awaiting identity, so the grace arms")

        // The USB-C cable answers first and is not saved.
        await clock.advance(by: .milliseconds(200))
        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: [magSafeKey], resolved: [usbcKey]))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.count, 0,
            "one port settling is not enough: the other's name is still coming, and one banner covers both"
        )

        // The MagSafe cable answers second and IS saved.
        await clock.advance(by: .milliseconds(200))
        sequencer.updateLabelledCables(feed(
            byPort: [magSafeKey: "Kitchen MagSafe"], awaiting: [], resolved: [magSafeKey, usbcKey]
        ))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(
            posted.entries.first?.1.body, "30W negotiated (Kitchen MagSafe)\n65W negotiated",
            "both ports on one banner, and the saved one keeps its name"
        )
        await clock.advance(by: .seconds(10))
    }

    // MARK: - The bound the window's doc comment claims

    /// F7 review finding, measured rather than reasoned. `diffSources` resets
    /// the one-grace budget on every power publish, because that is where a
    /// genuinely new charger event starts and the debounce cannot tell a new
    /// event from a flap of the current one. So a source-set change during
    /// the grace buys a fresh settle AND a fresh grace, and the delay from
    /// the physical plug exceeds the 3s that `chargerCableLabelGraceWindow`'s
    /// doc comment used to promise outright.
    ///
    /// Pinned rather than fixed, and the comment now says so. The settle
    /// window has always been unbounded under sustained flapping, so this
    /// amplifies an accepted property rather than adding a stall; capping the
    /// budget instead would deny a grace to a real unplug-then-replug.
    ///
    /// This test is a characterisation: it records what the code does so the
    /// doc comment can be checked against it, and it fails if the timing ever
    /// silently changes.
    func testAPowerFlapDuringTheGraceWidensTheWait() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = [negotiatedSource()]
        sequencer.diffSources([])
        await flush(clock)

        // t=1500: settle fires, grace armed, due t=3000.
        await clock.advance(by: .milliseconds(1500))
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0)

        // t=1600: the power source set changes again. Fresh settle (due
        // t=3100) and a fresh grace budget.
        await clock.advance(by: .milliseconds(100))
        sequencer.diffSources([])
        await flush(clock)

        // t=3000: where the banner would have landed without the flap.
        await clock.advance(by: .milliseconds(1400))
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "the flap moved the banner past the un-flapped 3s worst case")

        // t=3100: the second settle fires and arms the second grace. Stepped
        // to land EXACTLY here rather than advancing through it: the grace
        // task is created inside this advance and does not reach its
        // `clock.sleep` until the flush, so an advance that ran past t=3100
        // would register the sleep against the later `now` and the deadline
        // would move with it. Same reason every advance in this file is
        // followed by a flush.
        await clock.advance(by: .milliseconds(100))
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "the second settle hands off to a second grace, it does not post")

        // t=4599: one millisecond short of the second grace's expiry.
        await clock.advance(by: .milliseconds(1499))
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "still inside the second grace")

        await clock.advance(by: .milliseconds(1))
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 1, "one flap moves the banner from t=3000 to t=4600")
        await clock.advance(by: .seconds(10))
    }

    // MARK: - Hazard 1: the grace return must not land a parked device diff

    /// `reconcileChargers`'s `defer` lands any parked device diff on EVERY
    /// return. The grace return is a return that has posted nothing and
    /// reconciled nothing, so landing there would put the device banner
    /// ahead of the charger banner that is still coming, inverting the
    /// ordering the whole park machinery exists to enforce.
    ///
    /// Two separate guards have to hold for this to pass, and the test is
    /// built so that breaking either one flips the order:
    ///  1. the `defer` is gated on `passCompleted`, so the grace return
    ///     lands nothing;
    ///  2. `deferredDeviceDiffDeadlineWindow` includes the grace window, so
    ///     the parked diff's own absolute backstop cannot expire mid-grace
    ///     and land the device banner first anyway.
    ///
    /// The 500ms offset between parking and reconciling is what makes guard
    /// 2's failure unambiguous rather than a tie: without the grace term the
    /// deadline lands at 1530ms while the grace still has until 2000ms, so
    /// the t=1600 checkpoint below falls cleanly between the two.
    ///
    /// Red-proof (guard 1): make the `defer` unconditional again. Goes red
    /// at the grace-return assertion ("XCTAssertTrue failed - the grace
    /// return must land nothing at all"), then at the ordering assertion
    /// with `[.device, .charger]`: the device banner posts at 500ms, a full
    /// 1.5s before the charger it was supposed to stack on top of.
    ///
    /// Red-proof (guard 2): drop `Self.chargerCableLabelGraceWindow` from
    /// the `deferredDeviceDiffDeadlineWindow` arithmetic in `init`. Goes red
    /// at the t=1600 checkpoint ("XCTAssertTrue failed - the parked diff's
    /// deadline must not expire mid-grace"): the deadline fires at 1530ms,
    /// while the charger still has 470ms of grace left.
    func testADeviceDiffParkedBeforeAGracedChargerEventStillPostsAfterTheCharger() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        // A short presentation gap keeps this test about the grace, not
        // about the gap; the deadline is derived from it at init, so the
        // arithmetic under test still moves with it.
        let sequencer = makeSequencer(
            clock: clock, posted: posted, box: box, presentationGapWindow: .milliseconds(30)
        )
        sequencer.didPrimeBaseline = true
        // The hub is already in the baseline, so the parked diff below is an
        // in-tree add and issue #570's device hold stays out of the way (see
        // `hubDevice`'s doc comment).
        sequencer.knownDevices = [
            900: USBDeviceChangeGrouper.Snapshot(id: 900, locationID: 0x03_10_00_00, name: "Hub")
        ]
        sequencer.knownChargerLabels = [:]
        sequencer.updateLabelledCables(feed(byPort: [:]))

        // t=0: a device diff parks, waiting on the charger reconcile, and
        // starts its own absolute deadline (30 + 1500 + 1500 = 3030ms).
        sequencer.deferDeviceDiff([hubDevice(id: 900), childDevice(id: 901)])
        await flush(clock)

        await clock.advance(by: .milliseconds(500))

        // t=500: the charger settle fires. The added port has no name yet,
        // so this returns having posted nothing, with a grace due at t=2000.
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertTrue(
            posted.entries.isEmpty,
            "the grace return must land nothing at all: no charger post yet, and no parked device post either"
        )

        // t=1600: past where the parked diff's absolute deadline would sit
        // WITHOUT the grace term (30 + 1500 = 1530ms), still inside the
        // grace. Nothing may have posted: this is the assertion that pins
        // the deadline arithmetic, and it is deliberately separated from the
        // one below so the result does not depend on which of two waiters
        // resumes first inside a single `advance`.
        await clock.advance(by: .milliseconds(1100))
        await flush(clock)
        XCTAssertTrue(
            posted.entries.isEmpty,
            "the parked diff's deadline must not expire mid-grace and land the device banner before the charger"
        )

        // t=2000: the grace expires, the charger banner posts, and only then
        // is the parked diff handed to its presentation gap. The explicit
        // `flush` matters: the gap task is CREATED inside this advance's own
        // drain, so it hasn't reached its `clock.sleep` yet and would
        // otherwise register against a later `now`. Same reason
        // `DeviceDiffSequencerTests` flushes after every advance.
        await clock.advance(by: .milliseconds(400))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0), [.charger],
            "the charger banner must come first; a device banner here means the grace return landed the parked diff"
        )

        // t=2030: the device banner follows, after the gap.
        await clock.advance(by: .milliseconds(30))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0), [.charger, .device],
            "the parked device diff must land after the charger post, exactly as it does without a grace"
        )
        XCTAssertEqual(posted.entries.last?.1.title, "Connected: Mouse")
        await clock.advance(by: .seconds(10))
    }

    // MARK: - The collapse runs LAST inside updateLabelledCables

    /// The early collapse re-enters `reconcileChargers`, which can land a
    /// parked device diff on its way out, so WHERE inside
    /// `updateLabelledCables` the collapse sits decides whether that landing
    /// sees this publish's cable-label event or the previous one.
    /// `assignCableLabelEvent(_:)` is the last thing that function does, so
    /// the collapse has to run after it: it does, from a `defer`.
    ///
    /// This is the one interleaving where the placement is observable. Two
    /// cable-label events arrive while a single device diff sits parked, and
    /// the second publish also supplies the charger name that collapses the
    /// grace. The file's own policy is that the LATEST event wins for an
    /// episode (`assignCableLabelEvent` overwrites unconditionally), so the
    /// landing must carry cable B, not the stale cable A.
    ///
    /// The charger going away between the two grace passes is what makes the
    /// collapse's reconcile post nothing, which is what makes it land the
    /// parked diff SYNCHRONOUSLY (`.immediate`) instead of through the
    /// presentation gap. Via the gap the landing happens in a later task,
    /// after `assignCableLabelEvent` has run regardless, and the placement
    /// stops mattering. That is why this is a narrow, defensive fix rather
    /// than a bug anyone reported.
    ///
    /// Red-proof: move the collapse back out of the `defer`, to where it sat
    /// before (straight after the `known...` assignments). Goes red with
    /// subtitle "Cable A" instead of "Cable B": the parked diff consumed the
    /// PREVIOUS publish's event, because this publish had not assigned its
    /// own yet.
    func testTheCollapseRunsAfterTheCableLabelEventIsAssigned() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        sequencer.knownChargerLabels = [:]

        // Baseline publish: establishes a non-nil `previous` so the next two
        // publishes can each register as a one-cable change.
        sequencer.updateLabelledCables(feed(byPort: [:]))

        // A port-level device batch parks, waiting on the charger reconcile.
        sequencer.deferDeviceDiff([portLevelDevice(id: 1)])
        await flush(clock)

        // The charger settles with no name yet: grace armed, nothing posted,
        // nothing landed.
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertTrue(posted.entries.isEmpty)

        // Cable A resolves. Tagged to the parked episode. No charger name in
        // this publish, so the grace is NOT collapsed by it.
        sequencer.updateLabelledCables(feed(byPort: [:], byCableID: ["cable-a": "Cable A"]))
        await flush(clock)
        XCTAssertTrue(posted.entries.isEmpty, "no charger name in that publish, so the grace must still be waiting")

        // The charger goes away before the grace resolves, so the collapse's
        // own reconcile has nothing to post and lands the parked diff
        // synchronously rather than through the presentation gap.
        box.sources = []

        // Cable B resolves AND the charger port gets its name, in one
        // publish: this both assigns the newer event and collapses the grace.
        sequencer.updateLabelledCables(feed(
            byPort: [magSafeKey: "Kitchen MagSafe"],
            byCableID: ["cable-a": "Cable A", "cable-b": "Cable B"],
            awaiting: [], resolved: [magSafeKey]
        ))
        await flush(clock)

        XCTAssertEqual(posted.entries.map(\.0), [.device], "the charger vanished, so only the landed device diff posts")
        XCTAssertEqual(
            posted.entries.first?.1.subtitle, "Cable B",
            "the landing must carry THIS publish's event; \"Cable A\" means the collapse ran before the assignment"
        )
        await clock.advance(by: .seconds(10))
    }

    // MARK: - Hazard 2: the grace return must mutate nothing

    /// The grace return happens BEFORE `knownChargerLabels` absorbs the
    /// current charger set, and it has to stay that way. The second pass
    /// re-derives its added ports by diffing the live set against
    /// `knownChargerLabels`; if the first pass had already written the live
    /// set in, the second would see nothing added and post nothing at all.
    /// That is a silent total failure (no banner, ever), strictly worse than
    /// the missing name this feature fixes.
    ///
    /// Red-proof: move `knownChargerLabels = currentLabels` above the grace
    /// check. Goes red twice over: first at the "mutated nothing" assertion
    /// ("XCTAssertTrue failed"), and, with that assertion removed, at the
    /// post count after the cap ("XCTAssertEqual failed: ("0") is not equal
    /// to ("1")") -- the banner is gone entirely, not merely unnamed.
    func testTheGraceReturnDoesNotMutateTheChargerBaseline() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:]))
        box.sources = [negotiatedSource()]
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertTrue(
            sequencer.knownChargerLabels.isEmpty,
            "the grace return must leave the charger baseline untouched, or the second pass sees nothing added"
        )
        XCTAssertNil(
            sequencer.lastChargerPostTime,
            "the grace return posted nothing, so it must not look like a charger post just went out"
        )

        await clock.advance(by: graceWindow)
        XCTAssertEqual(
            posted.entries.count, 1,
            "the second pass must still see the port as newly added and post its connect banner"
        )
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(title: "Charger connected", body: "30W negotiated"))
        XCTAssertEqual(
            sequencer.knownChargerLabels, [magSafeKey: "30W negotiated"],
            "the completed pass, and only the completed pass, absorbs the live set into the baseline"
        )
        await clock.advance(by: .seconds(10))
    }

    // MARK: - The grace with a resolved UUID (gate review LOW-3)
    //
    // Every other test in this file uses a port with no `hpmControllerUUID`, so
    // `canonicalJoinKey == portKey` throughout and the suite cannot see the
    // key-space change at all. These four drive the same machinery with a UUID
    // resolved, which is the combination the deleted
    // `chargerCableLabelGracePortKeyFallbacks` existed for. Two of them
    // discriminate (they go red if the grouping is reverted); the other two pass
    // either way on purpose, and that is the useful result, because it is the
    // direct evidence that deleting the alias fallback was inert for the grace
    // rather than an argument that it was.

    /// Inert-path evidence: the ordinary arm-then-collapse cycle still works
    /// when both sides resolved a UUID. Passes before and after the grouping
    /// change; it is here to show the deletion broke nothing, not to catch a
    /// regression.
    func testGraceArmsAndCollapsesWhenBothSidesResolvedAUUID() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: magSafeBothKeys))
        box.sources = [negotiatedSource(uuid: magSafeUUID)]
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 0, "a port with no name yet must wait, UUID or not")

        // The e-marker resolves. The provider publishes the name under BOTH keys.
        sequencer.updateLabelledCables(feed(
            byPort: [magSafeUUID: "Kitchen MagSafe", magSafeKey: "Kitchen MagSafe"],
            awaiting: [], resolved: magSafeBothKeys
        ))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1, "the name must collapse the grace even with a UUID resolved")
        XCTAssertEqual(posted.entries.first?.1, NotificationContent(
            title: "Charger connected", subtitle: "Kitchen MagSafe", body: "30W negotiated"
        ))
    }

    /// Inert-path evidence, and the failure mode worth ruling out explicitly:
    /// the one-per-event grace budget must not get stuck in a state where a
    /// charger event can never post at all. With a UUID resolved and a name that
    /// never arrives, the cap must still fire exactly one unnamed banner.
    func testGraceCapStillPostsWithAUUIDPresent() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: magSafeBothKeys))
        box.sources = [negotiatedSource(uuid: magSafeUUID)]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0)

        // No name ever arrives. The cap is the backstop.
        await clock.advance(by: graceWindow)
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1, "the cap must post even when no name ever arrives")
        XCTAssertEqual(posted.entries.first?.1.title, "Charger connected")
        XCTAssertEqual(posted.entries.first?.1.body, "30W negotiated")

        // And nothing further: a spent budget must not re-arm or double-post.
        await clock.advance(by: .seconds(10))
        XCTAssertEqual(posted.entries.count, 1, "the spent grace must not post twice")
    }

    /// DISCRIMINATING. Two sibling power-source nodes on ONE physical MagSafe
    /// port whose UUID walks disagree, driven through the whole grace path
    /// rather than through a direct `reconcileChargers()` call.
    ///
    /// Red-proof: revert the grouping in `chargerLabels(for:)` to
    /// `canonicalJoinKey`. Goes red with the port split in two, the name stamped
    /// on both halves, and an empty subtitle. The body comes out as:
    /// "Wattage not reported (Kitchen MagSafe)\n30W negotiated (Kitchen MagSafe)".
    ///
    /// That order is not arbitrary, and an earlier version of this comment had
    /// it backwards. `sortedChargerLines` sorts by key. Under the revert the
    /// split port's two keys are "17/1" (the Brick ID sibling, whose walk
    /// failed, so it has no contract to report) and the UUID
    /// "aaaabbbb..." (the sibling carrying the contract). "1" sorts before "a",
    /// so the unreported half prints first. A recipe that does not reproduce is
    /// worse than none, because the next person assumes they broke something.
    func testMixedUUIDSiblingsThroughTheFullGracePath() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        sequencer.updateLabelledCables(feed(byPort: [:], awaiting: magSafeBothKeys))
        // The sibling whose walk resolved carries the contract; the one whose
        // walk failed carries nothing. Same physical port.
        box.sources = [
            negotiatedSource(id: 1, uuid: magSafeUUID),
            PowerSource(
                id: 2, name: "Brick ID", parentPortType: 17, parentPortNumber: 1,
                options: [], winning: nil, hpmControllerUUID: nil
            ),
        ]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "no name yet, so the grace must be waiting")

        sequencer.updateLabelledCables(feed(
            byPort: [magSafeUUID: "Kitchen MagSafe", magSafeKey: "Kitchen MagSafe"],
            awaiting: [], resolved: magSafeBothKeys
        ))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(
            posted.entries.first?.1,
            NotificationContent(
                title: "Charger connected", subtitle: "Kitchen MagSafe", body: "30W negotiated"
            ),
            "one physical port must produce one named line through the grace path too"
        )
    }

    /// DISCRIMINATING. A UUID walk that resolves on one pass and fails on the
    /// next, with a feed present and saved cables, so the grace machinery is
    /// live throughout. Nothing physically moved, so nothing may be posted.
    ///
    /// Red-proof: revert the grouping in `chargerLabels(for:)` to
    /// `canonicalJoinKey`. Goes red with 2 posts instead of 0, a
    /// "Charger disconnected" followed by a "Charger connected" for a charger
    /// that never moved.
    func testFlickerThroughTheFullDebouncePostsNothing() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)

        // Already attached and already named, so no grace can arm and any post
        // from here is a genuine add or remove rather than a wait expiring.
        sequencer.updateLabelledCables(feed(
            byPort: [magSafeUUID: "Kitchen MagSafe", magSafeKey: "Kitchen MagSafe"],
            awaiting: [], resolved: magSafeBothKeys
        ))
        sequencer.primeBaseline(devices: [], chargerSources: [negotiatedSource(uuid: magSafeUUID)])

        // The same charger one pass later, its registry walk having failed.
        box.sources = [negotiatedSource(uuid: nil)]
        sequencer.reconcileChargers()
        await flush(clock)
        await clock.advance(by: graceWindow)
        await flush(clock)

        XCTAssertEqual(
            posted.entries.count, 0,
            "a stationary charger posted: \(posted.entries.map(\.1.title))"
        )

        // Non-vacuity: this sequencer does post when the charger really goes.
        box.sources = []
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(posted.entries.last?.1.title, "Charger disconnected")
    }
}
