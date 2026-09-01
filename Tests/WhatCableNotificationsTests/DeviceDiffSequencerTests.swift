import XCTest
@testable import WhatCableNotifications
import WhatCableCore

/// Direct tests of `DeviceDiffSequencer`'s timing/ordering machinery, driven
/// by `ManualClock` instead of real sleeps. These replace the 9 wiring tests
/// that used to live in `Tests/WhatCableAppTests/NotificationManagerStackOrderWiringTests.swift`
/// and poke `NotificationManager.shared` end to end; every behaviour that
/// file guarded is re-covered here, against the extracted sequencer
/// directly. See that file's own (now-removed) doc comments, preserved
/// inline below per test, for the reasoning behind each scenario.
///
/// `@testable import`, not a plain `import` (unlike the pure-decision test
/// files in this same target): these tests reach `knownDevices`,
/// `knownChargerLabels`, `didPrimeBaseline`, `deferDeviceDiff`,
/// `runNowOrDelayForRecentChargerPost`, and `reconcileChargers` directly,
/// none of which need to be `public` (the app-facing surface is just
/// `init`, `primeBaseline`, `scheduleDeviceDiff`, and `diffSources`).
/// Mirrors the original wiring test file's own reasoning for why those
/// members weren't marked `private` on `NotificationManager`.
@MainActor
final class DeviceDiffSequencerTests: XCTestCase {
    /// Minimal single-device fixture. Only `id`/`productName` matter here:
    /// `diffDevices` groups by these via `USBDeviceChangeGrouper`, and an
    /// empty `knownDevices` baseline means this one device is a clean
    /// "added" group, producing exactly one "Connected: <name>" content.
    private func fakeDevice(id: UInt64) -> USBDevice {
        USBDevice(
            id: id, locationID: 0x01_00_00_00, vendorID: 0, productID: 0,
            vendorName: nil, productName: "Test Hub", serialNumber: nil,
            usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
    }

    /// Minimal single-port charger fixture with a winning 30W contract, so
    /// `chargerLabels(for:)` resolves it to "30W negotiated" (matching the
    /// label convention the other tests in this file already use for
    /// `knownChargerLabels`).
    private func fakeChargerSource(id: UInt64 = 1) -> PowerSource {
        PowerSource(
            id: id, name: "USB-PD",
            parentPortType: 2, parentPortNumber: 1,
            options: [],
            winning: PowerOption(voltageMV: 20000, maxCurrentMA: 1500, maxPowerMW: 30000)
        )
    }

    /// A sequencer wired to `clock`, an always-empty live device/charger
    /// read (every test drives `knownDevices`/`knownChargerLabels` directly
    /// instead, exactly as the original wiring tests did against the real,
    /// empty `WatcherHub` in the `swift test` process), and a `post`
    /// closure that appends into `posted`. `notifyOnChanges` is always true:
    /// the gating behaviour itself is covered by the pure `NotificationDecision`
    /// tests and by `diffDevices`/`reconcileChargers`'s own doc comments, not
    /// by this file.
    private func makeSequencer(
        clock: ManualClock,
        posted: PostedLog,
        currentChargerSources: @escaping () -> [PowerSource] = { [] },
        currentDownstreamTBSwitchIDs: @escaping () -> Set<Int64> = { [] },
        notifyOnChanges: @escaping () -> Bool = { true }
    ) -> DeviceDiffSequencer<ManualClock> {
        DeviceDiffSequencer(
            clock: clock,
            currentDevices: { [] },
            currentChargerSources: currentChargerSources,
            currentDownstreamTBSwitchIDs: currentDownstreamTBSwitchIDs,
            notifyOnChanges: notifyOnChanges,
            post: { category, content, _ in posted.entries.append((category, content)) },
            // Fixed, not generated: this file tests ordering/timing, not
            // identifier content, so a stable token keeps every directive
            // this sequencer hands out deterministic across runs.
            launchToken: "test-launch"
        )
    }

    /// Reference type so the `post` closure above can append into it
    /// without the closure needing to capture `self` or a `var` across
    /// concurrency boundaries.
    private final class PostedLog {
        var entries: [(NotificationCategory, NotificationContent)] = []
    }

    /// Reference type letting a test mutate what an injected closure
    /// returns AFTER the sequencer has already captured it once (e.g.
    /// `currentDownstreamTBSwitchIDs`), to simulate state changing during a
    /// parked diff's wait.
    private final class MutableBox<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    /// A freshly-created `Task { @MainActor ... }` is enqueued, not run
    /// inline: it doesn't reach its first `clock.sleep` call (and register
    /// itself as a waiter) until it gets a turn. Call this after any action
    /// that schedules a settle/gap/deadline task and before the first
    /// `clock.advance(by:)` that's meant to fire it, so the registration has
    /// actually happened. Delegates to `ManualClock.settle()`'s barrier-drain
    /// rather than a fixed yield count (see that method's doc comment for
    /// why a fixed count measured flaky here).
    private func flush(_ clock: ManualClock) async {
        await clock.settle()
    }

    // MARK: - 1 & 2: device post waits for a pending charger settle, and
    // lands after the presentation gap once the charger reconcile actually
    // posted content.

    /// Live verification found that landing the parked diff SYNCHRONOUSLY
    /// put both posts in the same millisecond, and macOS presents only the
    /// LAST of two simultaneous banners: "Charger disconnected" reached
    /// Notification Centre but never showed on screen. So when
    /// `reconcileChargers` actually posts charger content, a parked device
    /// diff must wait out a deliberate presentation gap before landing, not
    /// land in the same call.
    func testDevicePostWaitsForPendingChargerSettleAndLandsAfterThePresentationGap() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.deferredDeviceDiffPresentationGapWindow = .milliseconds(30)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        // Seeding a baseline charger means reconcileChargers (which always
        // reads an empty live set here) sees a removal and posts real
        // content ("Charger disconnected"), not just a landing with nothing
        // before it.
        sequencer.knownChargerLabels = ["fake-port-1": "30W negotiated"]

        sequencer.deferDeviceDiff([fakeDevice(id: 901)])
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger],
            "the device post must not land in the same call as the charger post it needs to stack on top of"
        )

        await clock.advance(by: .milliseconds(29))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger],
            "must not land one millisecond before the presentation gap elapses"
        )

        await clock.advance(by: .milliseconds(1))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger, .device],
            "after the presentation gap, the parked device diff must land, still after the charger post"
        )
        XCTAssertEqual(posted.entries.last?.1.title, "Connected: Test Hub")
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 7: a reconcile that posted nothing lands the parked diff
    // immediately.

    /// When `reconcileChargers` posts nothing (no charger change in this
    /// settle), there is no simultaneous-banner problem to avoid, so the
    /// parked diff must still land synchronously, exactly as before the
    /// presentation-gap fix.
    func testANoOpReconcileLandsTheParkedDiffImmediately() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        // Empty baseline, matching the always-empty live charger set:
        // reconcileChargers sees no added or removed ports and posts
        // nothing.
        sequencer.knownChargerLabels = [:]

        sequencer.deferDeviceDiff([fakeDevice(id: 903)])
        sequencer.reconcileChargers()

        XCTAssertEqual(
            posted.entries.map(\.0),
            [.device],
            "a reconcile that posted nothing must land the parked diff synchronously, no presentation gap needed"
        )
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 6a: a second reconcile that posts nothing must not land the
    // diff early while an earlier gap is still pending
    // (isPresentationGapPending guard).

    /// Codex review: a SECOND `reconcileChargers` call that posts nothing of
    /// its own, arriving while the presentation gap from a FIRST (which DID
    /// post charger content) is still pending, must not land the parked
    /// diff early. Landing it right there, next to the second call's
    /// return, would defeat the gap the first call scheduled: the device
    /// post would still cluster close to the charger post, just relative to
    /// the wrong reconcile. `isPresentationGapPending` must make the second
    /// call's `.immediate` disposition yield to the pending gap instead.
    func testASecondReconcileThatPostsNothingDoesNotLandBeforeAPendingGapElapses() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.deferredDeviceDiffPresentationGapWindow = .milliseconds(30)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        // Baseline charger so the FIRST reconcileChargers call below reads
        // as a removal and posts real content, scheduling the gap.
        sequencer.knownChargerLabels = ["fake-port-1": "30W negotiated"]

        sequencer.deferDeviceDiff([fakeDevice(id: 904)])

        sequencer.reconcileChargers() // A: posts "Charger disconnected", schedules the gap
        await flush(clock)
        // B: knownChargerLabels is already [:] after A, so the always-empty
        // live set matches it exactly. This posts nothing and, absent the
        // guard, would take .immediate and land the parked diff right here,
        // defeating A's still-pending gap.
        sequencer.reconcileChargers()

        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger],
            "a second reconcile posting nothing must not land the diff while an earlier gap is still pending"
        )

        await clock.advance(by: .milliseconds(30))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger, .device],
            "the pending gap from the first reconcile must still land the diff once it elapses"
        )
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 6b: a newer gap task supersedes an older still-pending one
    // (the cancel + generation guard).

    /// Codex review, second finding: two reconciles that BOTH post real
    /// charger content, close enough together that the second supersedes
    /// the first's still-pending gap.
    ///
    /// Window choice is deliberate: A (the one that gets superseded) is
    /// given the SHORT window, B (the newer, "real" one) the LONG window. If
    /// the bug were present (no cancel, no generation guard on the outgoing
    /// task), A's stale task is exactly the one that would fire FIRST (its
    /// short window elapses well before B's long one) and land the diff
    /// early via the pre-existing token check alone (nothing has landed yet
    /// at that point, so the token still matches). With `ManualClock` this
    /// is checked EXACTLY at A's window, not just "well before" it: advance
    /// to A's window precisely and assert nothing landed.
    func testANewerGapSupersedesAnOlderStillPendingOne() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        sequencer.knownChargerLabels = ["fake-port-1": "30W negotiated"]

        sequencer.deferDeviceDiff([fakeDevice(id: 905)])

        // A: posts "Charger disconnected" (removes fake-port-1), schedules a
        // SHORT gap. This is the one that must end up cancelled/superseded.
        sequencer.deferredDeviceDiffPresentationGapWindow = .milliseconds(30)
        sequencer.reconcileChargers()
        // A's gap Task reads deferredDeviceDiffPresentationGapWindow lazily,
        // the moment its body actually starts running, not at the point the
        // Task was created above. Flushing lets A's body begin (and commit
        // to its 30ms sleep) before the window is mutated to 300ms below.
        await flush(clock)

        // B: re-seed a DIFFERENT baseline charger so this call ALSO reads
        // as a removal (of "fake-port-2") and posts real content of its
        // own, superseding A's still-pending gap with a LONG one.
        sequencer.knownChargerLabels = ["fake-port-2": "45W negotiated"]
        sequencer.deferredDeviceDiffPresentationGapWindow = .milliseconds(300)
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger, .charger],
            "neither reconcile lands the diff itself; both just post charger content"
        )

        // Exactly A's 30ms window, well short of B's 300ms one. The
        // stale-task bug lands the diff HERE; the fix must not have landed
        // it yet.
        await clock.advance(by: .milliseconds(30))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger, .charger],
            "the superseded (shorter) gap must not land the diff; only the newer gap may"
        )

        // Exactly B's remaining window.
        await clock.advance(by: .milliseconds(270))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger, .charger, .device],
            "the newer gap must still land the diff once its own window elapses"
        )
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 8: the absolute deadline path lands a parked diff even when
    // the charger side never reconciles at all.

    /// The bounded fallback: if `reconcileChargers` never runs (charger side
    /// stayed quiet), the parked diff must still land, capped at
    /// `deferredDeviceDiffDeadlineWindow` rather than waiting forever. This
    /// is also the "flush/deadline path does not bypass charger debounce"
    /// behaviour: the deadline landing runs through the exact same
    /// `landDeferredDeviceDiffNow` / token machinery as every other landing
    /// path, never an early flush of a still-pending charger settle.
    func testATimedOutDeferralLandsWithoutAReconcile() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.deferredDeviceDiffDeadlineWindow = .milliseconds(50)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]

        sequencer.deferDeviceDiff([fakeDevice(id: 902)])
        await flush(clock)
        // Deliberately never call reconcileChargers: only the bounded
        // deadline can land this diff.
        await clock.advance(by: .milliseconds(50))
        await flush(clock)

        XCTAssertEqual(
            posted.entries.map(\.0),
            [.device],
            "a deferred diff with no reconcile must still land via the bounded deadline"
        )
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 3: the symmetric case, the charger fires FIRST (devicePostDelay
    // remainder rule).

    /// Both-orders fix: live logs showed the CHARGER settle firing first. By
    /// the time the device settle's own window elapses, the charger has
    /// already reconciled and posted, `isChargerSettlePending` reads false,
    /// and `deviceDiffDisposition` says `.runNow`. Drives
    /// `runNowOrDelayForRecentChargerPost` directly, the same function
    /// `scheduleDeviceDiff`'s `.runNow` case calls, so this exercises the
    /// actual wiring, not just `devicePostDelay` in isolation.
    func testARunNowDeviceDiffShortlyAfterAChargerPostWaitsOutTheRemainder() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.deferredDeviceDiffPresentationGapWindow = .milliseconds(30)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        // Baseline charger so reconcileChargers reads as a removal and
        // actually posts (and so records lastChargerPostTime).
        sequencer.knownChargerLabels = ["fake-port-1": "30W negotiated"]

        // Charger settle fires FIRST and finishes reconciling entirely,
        // posting "Charger disconnected" and recording lastChargerPostTime.
        // Nothing is parked afterwards: reconcileChargers's own defer lands
        // nothing because deferDeviceDiff was never called on this path.
        sequencer.reconcileChargers()

        // The device settle fires a moment later, finding
        // isChargerSettlePending already false (not simulated here
        // directly; this IS the .runNow entry point scheduleDeviceDiff
        // would have called).
        sequencer.runNowOrDelayForRecentChargerPost([fakeDevice(id: 906)])
        await flush(clock)

        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger],
            "the device post must not land in the same call as the charger post it just missed by a moment"
        )

        await clock.advance(by: .milliseconds(30))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger, .device],
            "once the remainder of the presentation gap elapses, the device post must still land"
        )
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    /// Same scenario as the test above, but driven through the ACTUAL
    /// production call site (`scheduleDeviceDiff`, with `deviceSettleWindow`
    /// shrunk) instead of calling `runNowOrDelayForRecentChargerPost`
    /// directly. Codex review: the test above calls the helper directly, so
    /// it stays green even if `scheduleDeviceDiff`'s `.runNow` case
    /// regressed back to a bare `diffDevices(devices)` call, which is
    /// exactly the charger-fires-first bug this fix exists to catch.
    /// Keeping BOTH tests: the direct-helper one pins
    /// `runNowOrDelayForRecentChargerPost`'s own logic in isolation, this
    /// one pins that the production call site actually reaches it.
    func testSchedulingADeviceDiffShortlyAfterAChargerPostWaitsOutTheRemainder() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.didPrimeBaseline = true
        // A non-empty baseline here means the settled (always-empty-live)
        // diff reads as a removal and actually posts, same reasoning as the
        // charger baseline below.
        sequencer.knownDevices = [
            907: USBDeviceChangeGrouper.Snapshot(id: 907, locationID: 0x01_00_00_00, name: "Test Hub")
        ]
        sequencer.knownChargerLabels = ["fake-port-1": "30W negotiated"]
        sequencer.deviceSettleWindow = .milliseconds(20)
        sequencer.deferredDeviceDiffPresentationGapWindow = .milliseconds(200)

        // Charger settle fires first and finishes reconciling entirely,
        // posting "Charger disconnected" and recording lastChargerPostTime
        // at clock t=0.
        sequencer.reconcileChargers()

        // Device settle fires moments later, through the real production
        // call site: scheduleDeviceDiff's own 20ms settle sleep, then a
        // (always-empty) live device read, then deviceDiffDisposition
        // (isChargerSettlePending was never set by this test's direct
        // reconcileChargers() call, so this reads .runNow), then
        // runNowOrDelayForRecentChargerPost.
        sequencer.scheduleDeviceDiff()
        await flush(clock)

        // Exactly at the 20ms settle window: the .runNow decision has just
        // been made and the remainder (200ms - 20ms = 180ms) parked.
        await clock.advance(by: .milliseconds(20))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger],
            "the device post must not land before the remainder of the presentation gap elapses"
        )

        // The gap is measured from the CHARGER post (t=0), so total landing
        // is at t=200: one millisecond short of that must still show
        // nothing new.
        await clock.advance(by: .milliseconds(179))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger],
            "must not land one millisecond before the total 200ms gap (measured from the charger post) elapses"
        )

        await clock.advance(by: .milliseconds(1))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.charger, .device],
            "once the remainder elapses, scheduleDeviceDiff's own .runNow path must still land the device post"
        )
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 5 & 9: supersedeAnyParkedDiff invalidates an older parked diff
    // (exactly-once), and its stale token backs out when its own deadline
    // eventually fires.

    /// Adversarial review: `supersedeAnyParkedDiff` made a no-op leaves
    /// every other test in this file green, because none of them exercise
    /// "an OLDER parked diff is still waiting when a NEWER, immediate
    /// (`delay == 0`) device diff runs". Reproduces the actual consequence:
    /// an older diff parked via `deferDeviceDiff` (e.g. because a charger
    /// settle was pending at the time) is still sitting there when a LATER
    /// device settle's `.runNow` disposition, with no recent charger post
    /// to delay for, posts immediately. If the older diff isn't invalidated
    /// first, its own timeout later lands it against the ALREADY-MUTATED
    /// `knownDevices` baseline the immediate post just wrote, producing a
    /// second, spurious device notification: exactly the `shouldLandDeferredDiff`
    /// stale-token guard's job to prevent.
    ///
    /// `fakeDevice(id:)` always uses the same `locationID`/`productName`, so
    /// two different-id fake devices are a same-port "reconnect" to
    /// `USBDeviceChangeGrouper`: this is what turns the stale landing's diff
    /// (previous device removed, new device added) into exactly ONE extra
    /// "Reconnected: Test Hub" post rather than a two-content batch, so a
    /// bug here is visible as a clean `[.device, .device]` vs the correct
    /// `[.device]`.
    func testAnOlderParkedDiffDoesNotLandAfterANewerImmediateDeviceDiffRuns() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        sequencer.deferredDeviceDiffDeadlineWindow = .milliseconds(40)
        // lastChargerPostTime already starts nil on a fresh sequencer
        // (unlike the original process-wide-singleton test, which had to
        // reset it explicitly against leakage from an earlier test).

        // Park an OLDER diff (as deferDeviceDiff would if a charger settle
        // had been pending), starting its 40ms deadline backstop.
        sequencer.deferDeviceDiff([fakeDevice(id: 950)])
        await flush(clock)

        // A NEWER device settle's .runNow disposition, with no recent
        // charger post (lastChargerPostTime is nil), so devicePostDelay is
        // zero: posts immediately. Correct code must invalidate the older
        // parked diff (950) first, via supersedeAnyParkedDiff, so it can
        // never land later.
        sequencer.runNowOrDelayForRecentChargerPost([fakeDevice(id: 951)])

        XCTAssertEqual(
            posted.entries.map(\.0),
            [.device],
            "the immediate post must land exactly once, and the older parked diff must already be invalidated"
        )

        // Exactly where the older diff's 40ms deadline would have elapsed.
        await clock.advance(by: .milliseconds(40))
        await flush(clock)
        XCTAssertEqual(
            posted.entries.map(\.0),
            [.device],
            "the older parked diff's deadline must never land a second, spurious device post"
        )
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 4: the absolute deadline bounds the wait even under sustained
    // gap re-extension (starvation fix).

    /// Starvation fix, the actual replacement test: drives eight reconciles
    /// in a row, each posting real charger content and re-extending the
    /// presentation gap before the previous one would have elapsed on its
    /// own, so the gap NEVER naturally completes across the whole run. The
    /// diff must still land, by the absolute deadline (fixed at park time),
    /// despite that continuous re-extension.
    ///
    /// With `ManualClock` there is no flake-margin concern at all (the
    /// original real-clock version of this test was rebuilt twice over
    /// scheduler-jitter false negatives): gap 400ms, reconciles every 250ms
    /// (comfortably inside the gap, so every one lands before the previous
    /// would have expired), deadline 1500ms, landing on EXACTLY the 6th
    /// reconcile's boundary (t=1500). Reconciles continue past the deadline
    /// too (up to t=1750), so the gap is STILL being actively re-extended
    /// right up to the point the deadline fires: there is no moment where a
    /// merely-quiescent gap could coincidentally land the diff instead of
    /// the deadline actually doing its job.
    func testTheAbsoluteDeadlineLandsTheDiffDespiteSustainedGapReExtension() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(clock: clock, posted: posted)
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        // Gap window: each reconcile below is spaced 250ms apart, well
        // inside this 400ms window (150ms margin per re-extension), so
        // every one re-extends the gap before the previous one could
        // complete naturally.
        sequencer.deferredDeviceDiffPresentationGapWindow = .milliseconds(400)
        // Deadline: fixed at park time (t=0), independent of the gap
        // re-scheduling below. Deliberately BETWEEN the 4th and 8th
        // reconciles (t=750 and t=1750), so at the moment it fires the gap
        // is still being actively re-extended, not idle: the deadline is
        // provably what lands the diff, never a gap that just happened to
        // go quiet.
        sequencer.deferredDeviceDiffDeadlineWindow = .milliseconds(1500)

        // Park a diff as deferDeviceDiff would if the device settle found a
        // charger settle pending, starting the 1500ms deadline at t=0.
        sequencer.deferDeviceDiff([fakeDevice(id: 908)])
        await flush(clock)

        // Eight reconciles, each with a DIFFERENT baseline charger port so
        // each one reads as a genuine removal and posts real content
        // (re-extending the gap), 250ms apart: t=0, 250, 500, 750, 1000,
        // 1250, 1500, 1750. The loop pauses after the 4th (t=750) to take
        // the "still waiting" measurement at t=1000, 500ms clear of the
        // deadline in either direction from the nearest reconcile.
        let chargerPortKeys = (1...8).map { "fake-port-\($0)" }
        for (index, portKey) in chargerPortKeys.enumerated() {
            sequencer.knownChargerLabels = [portKey: "30W negotiated"]
            sequencer.reconcileChargers()
            await flush(clock)
            let isLast = index == chargerPortKeys.count - 1
            if !isLast {
                await clock.advance(by: .milliseconds(250))
                await flush(clock)
            }
            if index == 3 {
                // t=1000: comfortably past several re-extensions,
                // comfortably (500ms) short of the 1500ms deadline.
                XCTAssertEqual(
                    posted.entries.map(\.0),
                    Array(repeating: .charger, count: 4),
                    "still waiting at t=1000: four charger posts, no device post yet, 500ms clear of the 1500ms deadline"
                )
            }
        }
        // Loop ends right after the 8th reconcile, at cumulative t=1750.

        // t=1750 + 250ms = t=2000: 500ms past the deadline (1500), and the
        // 8th (final, now-uninterrupted) gap would only reach its OWN
        // natural elapse at t=1750+400=2150, still 150ms in the future
        // here. Landing by this point can only be the deadline's doing.
        await clock.advance(by: .milliseconds(250))
        await flush(clock)

        // Counts, not an exact ordered sequence: reconciles #6/#7 land at
        // essentially the same simulated instant as the 1500ms deadline
        // (t=1500), and which side of the deadline's landing they happen to
        // be processed on is a legitimate ordering question the
        // token/generation guards resolve safely, not something this
        // assertion should pin an exact position to.
        XCTAssertEqual(
            posted.entries.filter { $0.0 == .charger }.count, 8,
            "all eight charger posts must have gone out"
        )
        XCTAssertEqual(
            posted.entries.filter { $0.0 == .device }.count, 1,
            "the absolute deadline must land the diff exactly once, despite the gap having been continuously re-extended, well before the final gap's own natural elapse"
        )
        // Drain every outstanding waiter (including cancelled/superseded
        // tasks whose deadline this test never otherwise reaches) before the
        // clock and sequencer go out of scope, so no CheckedContinuation is
        // ever left un-resumed.
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 10 & 11: Thunderbolt-involvement wiring (issue #570 part 1).
    // `NotificationManagerThunderboltInvolvedTests` covers the pure rule and
    // the content-decision swap in isolation; these two prove the sequencer
    // actually wires the injected TB-switch-ID closure to
    // `deviceNotificationContents`, and that the TB baseline updates on the
    // real production discipline (in lockstep with `knownDevices`, even
    // while notifications are gated off).

    /// The real call site (`runNowOrDelayForRecentChargerPost`, reached via
    /// `scheduleDeviceDiff`) reads `currentDownstreamTBSwitchIDs()` at
    /// settle time, diffs it against the baseline, and threads the result
    /// into `deviceNotificationContents` as `thunderboltInvolved`. A TB
    /// switch not present at baseline appearing by settle time must flip
    /// the merged title. This test's settle time and landing time coincide
    /// (the `.runNow` disposition with no recent charger post), so it does
    /// NOT exercise the parked path; see
    /// `testAnUnrelatedTBSwitchChangeDuringTheParkWindowDoesNotRelabelTheBatch`
    /// and its sibling below for that.
    ///
    /// Red-proof: hardcode `thunderboltInvolved: false` at the
    /// `deviceNotificationContents` call site in `diffDevices` (instead of
    /// the derived value); this goes red (expects "Thunderbolt devices
    /// disconnected", gets "USB devices disconnected"), proving the flag
    /// genuinely reaches the content decision through the sequencer, not
    /// just in the pure-function tests.
    func testTBSwitchAppearingAcrossASettleFlipsTheMergedTitleToThunderbolt() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(
            clock: clock,
            posted: posted,
            currentDownstreamTBSwitchIDs: { [99] }
        )
        sequencer.didPrimeBaseline = true
        // Baseline: no downstream TB switch yet, so the live closure
        // returning [99] at settle time is a genuine appearance.
        sequencer.knownTBSwitchIDs = []
        // Two distinct top-level roots so the diff merges into ONE "...
        // devices ..." content rather than a single "Disconnected: <name>".
        sequencer.knownDevices = [
            901: USBDeviceChangeGrouper.Snapshot(id: 901, locationID: 0x01_00_00_00, name: "Hub A"),
            902: USBDeviceChangeGrouper.Snapshot(id: 902, locationID: 0x02_00_00_00, name: "Hub B")
        ]
        sequencer.deviceSettleWindow = .milliseconds(10)

        // scheduleDeviceDiff's own settle sleep, then a (always-empty) live
        // device read: both baseline roots read as removed.
        sequencer.scheduleDeviceDiff()
        await flush(clock)
        await clock.advance(by: .milliseconds(10))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(
            posted.entries.first?.1.title,
            "Thunderbolt devices disconnected",
            "a TB switch absent at baseline but present at settle time must flip the merged title"
        )
    }

    /// Baseline discipline: the TB baseline (`knownTBSwitchIDs`) must
    /// refresh on every device-diff settle exactly where `knownDevices`
    /// does, INCLUDING while `notifyOnChanges` is off, so a user who
    /// re-enables notifications later doesn't see a stale baseline
    /// manufacture a false "Thunderbolt involved" on the very next diff.
    ///
    /// Red-proof: move the TB baseline refresh in `diffDevices` to AFTER
    /// the `notifyOnChanges` guard (skipping it while the gate is off);
    /// this goes red (`knownTBSwitchIDs` expected `[7]`, stays `[]`).
    func testTBBaselineUpdatesEvenWhileNotifyOnChangesIsOff() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let sequencer = makeSequencer(
            clock: clock,
            posted: posted,
            currentDownstreamTBSwitchIDs: { [7] },
            notifyOnChanges: { false }
        )
        sequencer.didPrimeBaseline = true
        sequencer.knownDevices = [:]
        sequencer.knownTBSwitchIDs = []
        sequencer.deviceSettleWindow = .milliseconds(10)

        sequencer.scheduleDeviceDiff()
        await flush(clock)
        await clock.advance(by: .milliseconds(10))
        await flush(clock)

        XCTAssertEqual(
            sequencer.knownTBSwitchIDs, [7],
            "the TB baseline must refresh even while notifyOnChanges is off, exactly like knownDevices"
        )
        XCTAssertTrue(posted.entries.isEmpty, "notifications must stay suppressed while the gate is off")
    }

    // MARK: - 12 & 13: the TB-involvement snapshot is taken at PARK time,
    // not landing time (both review rounds' critical finding).

    /// A parked device diff must be labelled from the TB switch set that
    /// existed when its batch actually settled, not from whatever the live
    /// closure returns whenever the diff happens to land (up to
    /// `deferredDeviceDiffDeadlineWindow`, 5s in production, later). An
    /// UNRELATED TB switch appearing during that wait must not relabel a
    /// batch of plain USB devices.
    ///
    /// Red-proof: revert `landDeferredDeviceDiffNow` to re-read
    /// `currentDownstreamTBSwitchIDs()` at landing instead of using the
    /// captured `deferredDeviceDiffTBSwitchIDs`; this goes red (expects
    /// "USB devices disconnected", gets "Thunderbolt devices disconnected").
    func testAnUnrelatedTBSwitchChangeDuringTheParkWindowDoesNotRelabelTheBatch() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let tbBox = MutableBox<Set<Int64>>([])
        let sequencer = makeSequencer(
            clock: clock,
            posted: posted,
            currentDownstreamTBSwitchIDs: { tbBox.value }
        )
        sequencer.didPrimeBaseline = true
        sequencer.knownTBSwitchIDs = []
        // Two distinct top-level roots so the diff merges into ONE "...
        // devices ..." content rather than a single "Disconnected: <name>".
        sequencer.knownDevices = [
            910: USBDeviceChangeGrouper.Snapshot(id: 910, locationID: 0x01_00_00_00, name: "Hub A"),
            911: USBDeviceChangeGrouper.Snapshot(id: 911, locationID: 0x02_00_00_00, name: "Hub B")
        ]
        sequencer.knownChargerLabels = [:]

        // Parks a plain-USB diff (both baseline roots removed).
        // `deferDeviceDiff` samples `currentDownstreamTBSwitchIDs()` AT THIS
        // CALL, capturing `[]` (no TB switch present when the batch
        // settled).
        sequencer.deferDeviceDiff([])

        // An unrelated TB switch appears DURING the park window, after the
        // batch's own settle-time snapshot was already captured.
        tbBox.value = [99]

        // A charger reconcile that posts nothing lands the parked diff
        // immediately (no gap needed): see
        // `testANoOpReconcileLandsTheParkedDiffImmediately`.
        sequencer.reconcileChargers()

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(
            posted.entries.first?.1.title,
            "USB devices disconnected",
            "a TB switch change during the park window must not relabel an unrelated USB batch"
        )
        await clock.advance(by: .seconds(10))
    }

    /// The mirror image, covering the absolute-deadline landing path
    /// instead of the immediate no-op-reconcile path: a batch that settles
    /// WITH a Thunderbolt switch present must keep its "Thunderbolt
    /// devices" label even if that switch disappears again before the
    /// parked diff lands.
    ///
    /// Red-proof: same revert as above (landing-time sampling instead of
    /// the captured snapshot); this goes red (expects "Thunderbolt devices
    /// disconnected", gets "USB devices disconnected").
    func testATBSwitchDisappearingDuringTheParkWindowDoesNotUndoTheBatchsThunderboltLabel() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let tbBox = MutableBox<Set<Int64>>([99])
        let sequencer = makeSequencer(
            clock: clock,
            posted: posted,
            currentDownstreamTBSwitchIDs: { tbBox.value }
        )
        sequencer.deferredDeviceDiffDeadlineWindow = .milliseconds(50)
        sequencer.didPrimeBaseline = true
        sequencer.knownTBSwitchIDs = []
        sequencer.knownDevices = [
            912: USBDeviceChangeGrouper.Snapshot(id: 912, locationID: 0x01_00_00_00, name: "Hub A"),
            913: USBDeviceChangeGrouper.Snapshot(id: 913, locationID: 0x02_00_00_00, name: "Hub B")
        ]

        // Parks a batch that settled WITH a TB switch present (captures
        // `[99]` at this call).
        sequencer.deferDeviceDiff([])
        await flush(clock)

        // The TB switch disappears during the park window.
        tbBox.value = []

        // Deliberately never call reconcileChargers: only the bounded
        // deadline can land this diff, covering that landing path too.
        await clock.advance(by: .milliseconds(50))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(
            posted.entries.first?.1.title,
            "Thunderbolt devices disconnected",
            "a TB switch disappearing during the park window must not undo the batch's Thunderbolt label"
        )
        await clock.advance(by: .seconds(10))
    }

    // MARK: - 14 & 15: issue #568, the baseline prime must already agree with
    // the first live charger read, so app launch on existing charger power
    // never reads as a fresh connect.

    /// `diffSources(_:)` ignores its argument and re-reads
    /// `currentChargerSources()` fresh, after the settle window, so this
    /// (and the test below) drive the charger side through a mutable box the
    /// injected closure reads, exactly like `MutableBox` is already used for
    /// `currentDownstreamTBSwitchIDs` above.
    ///
    /// This test is the "fixed" case: the baseline was primed WITH the same
    /// charger source the live closure keeps returning (mirroring
    /// `WatcherHub.start()`'s new initial refresh landing before
    /// `NotificationManager`'s synchronous prime). A settle that finds
    /// nothing changed must post nothing.
    func testPrimingWithTheLiveChargerAlreadyPresentPostsNothingOnTheFirstSettle() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let chargerBox = MutableBox<[PowerSource]>([fakeChargerSource()])
        let sequencer = makeSequencer(
            clock: clock,
            posted: posted,
            currentChargerSources: { chargerBox.value }
        )

        sequencer.primeBaseline(devices: [], chargerSources: chargerBox.value)
        sequencer.diffSources([])
        await flush(clock)
        await clock.advance(by: DeviceDiffSequencer<ManualClock>.defaultChargerSettleWindow)
        await flush(clock)

        XCTAssertTrue(
            posted.entries.isEmpty,
            "a charger present at both prime time and the first live read must not post a phantom connect"
        )
        await clock.advance(by: .seconds(10))
    }

    /// The "bug reproduced" case: the baseline was primed EMPTY (as it would
    /// be if `NotificationManager` primed before `WatcherHub` had a chance to
    /// refresh, the pre-#568-fix ordering), and the live closure only starts
    /// returning the charger source after priming, standing in for the
    /// synthesis path that only exists once `powerWatcher.refresh()` has run.
    /// The subsequent settle must read this as a genuine connect and post
    /// exactly one "Charger connected".
    func testPrimingEmptyThenTheChargerAppearingPostsOneConnectedNotification() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let chargerBox = MutableBox<[PowerSource]>([])
        let sequencer = makeSequencer(
            clock: clock,
            posted: posted,
            currentChargerSources: { chargerBox.value }
        )

        sequencer.primeBaseline(devices: [], chargerSources: chargerBox.value)
        chargerBox.value = [fakeChargerSource()]
        sequencer.diffSources([])
        await flush(clock)
        await clock.advance(by: DeviceDiffSequencer<ManualClock>.defaultChargerSettleWindow)
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(posted.entries.first?.0, .charger)
        XCTAssertEqual(
            posted.entries.first?.1.title,
            "Charger connected",
            "an empty baseline followed by the charger appearing on the first live read must post Charger connected"
        )
        await clock.advance(by: .seconds(10))
    }
}
