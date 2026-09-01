import XCTest
import WhatCableNotifications

/// The stack-order fix defers the DEVICE post (never flushes the charger
/// reconcile early) when a device settle window fires and a charger settle
/// task is still pending from the same physical event, so the charger post
/// always lands first and the device post stacks on top (macOS puts the
/// newest notification on top). Both `NotificationDecision.deviceDiffDisposition`
/// (should this diff wait?) and `shouldLandDeferredDiff` (has it already been
/// landed by the other path?) are pure, unit-tested here without `Task` or
/// `UNUserNotificationCenter`.
final class NotificationManagerStackOrderTests: XCTestCase {
    // MARK: - deviceDiffDisposition

    func testDefersWhenAChargerEventIsInFlight() {
        XCTAssertEqual(
            NotificationDecision.deviceDiffDisposition(chargerEventInFlight: true),
            .deferUntilChargerReconcile,
            "a same-episode charger event still owing a banner must hold the device post back"
        )
    }

    func testRunsNowWhenNoChargerEventIsInFlight() {
        XCTAssertEqual(
            NotificationDecision.deviceDiffDisposition(chargerEventInFlight: false),
            .runNow,
            "a device-only event (no charger event in flight) must post immediately, unchanged"
        )
    }

    // MARK: - shouldLandDeferredDiff (exactly-once landing)

    func testALandingAttemptWithTheLiveTokenMayProceed() {
        XCTAssertTrue(
            NotificationDecision.shouldLandDeferredDiff(token: 1, liveToken: 1),
            "the first landing attempt, whichever path reaches it, must be allowed to run the diff"
        )
    }

    func testASecondLandingAttemptForTheSameDeferralIsRejected() {
        // Mirrors landDeferredDeviceDiff's own sequence: the winning path
        // invalidates the live token (increments it) before it runs the
        // diff, so a second attempt still holding the ORIGINAL captured
        // token must see a stale value and back out.
        let capturedToken = 1
        var liveToken = capturedToken
        XCTAssertTrue(NotificationDecision.shouldLandDeferredDiff(token: capturedToken, liveToken: liveToken))

        liveToken += 1 // the winning landing path's invalidation

        XCTAssertFalse(
            NotificationDecision.shouldLandDeferredDiff(token: capturedToken, liveToken: liveToken),
            "a deferred diff must land exactly once: reconcile-completion and timeout must not both run it"
        )
    }

    func testANewerDeferralInvalidatesAnOlderCapturedToken() {
        // deferDeviceDiff supersedes an earlier still-waiting diff by
        // incrementing the token before storing new devices, the same shape
        // as deviceSettleTask/chargerSettleTask's own "latest wins" rule.
        let staleToken = 1
        let liveTokenAfterASecondDefer = 2
        XCTAssertFalse(
            NotificationDecision.shouldLandDeferredDiff(token: staleToken, liveToken: liveTokenAfterASecondDefer),
            "a diff superseded by a newer deferral must not land using the old, now-stale devices"
        )
    }

    // MARK: - deferredDiffLanding (presentation-gap fix)
    //
    // Live verification found that landing a parked device diff SYNCHRONOUSLY
    // inside reconcileChargers's defer put both posts in the same
    // millisecond, and macOS only presents the LAST of two simultaneous
    // banners: "Charger disconnected" reached Notification Centre but never
    // showed on screen. This rule decides whether a landing on the
    // reconcile-completion path needs a deliberate presentation gap first.

    func testWaitsForThePresentationGapWhenTheReconcilePostedChargerContent() {
        XCTAssertEqual(
            NotificationDecision.deferredDiffLanding(reconcilePostedChargerContent: true),
            .afterPresentationGap,
            "a reconcile that actually posted charger content would otherwise post the device content in the same instant, so the device post must wait"
        )
    }

    func testLandsImmediatelyWhenTheReconcilePostedNothing() {
        XCTAssertEqual(
            NotificationDecision.deferredDiffLanding(reconcilePostedChargerContent: false),
            .immediate,
            "no charger post means nothing on screen to clash with, so this must be unchanged from before the presentation-gap fix"
        )
    }

    // MARK: - devicePostDelay (both-orders fix)
    //
    // Live logs showed the OTHER order: the charger settle fires first and
    // posts, and the device settle's own window elapses moments later,
    // finding isChargerSettlePending already false. The stack-order fix only
    // covered device-fires-first; this rule covers charger-fires-first by
    // consulting how long ago the last charger post actually went out.

    func testReturnsTheRemainderWhenInsideTheWindow() {
        XCTAssertEqual(
            NotificationDecision.devicePostDelay(
                elapsedSinceLastChargerPost: .milliseconds(200),
                presentationGap: .milliseconds(500)
            ),
            .milliseconds(300),
            "a device post settling 200ms after a charger post, inside a 500ms gap, must wait out the REMAINDER (300ms), not the full gap again"
        )
    }

    func testReturnsZeroWhenOutsideTheWindow() {
        XCTAssertEqual(
            NotificationDecision.devicePostDelay(
                elapsedSinceLastChargerPost: .milliseconds(600),
                presentationGap: .milliseconds(500)
            ),
            .zero,
            "a device post settling well after the gap has already elapsed has nothing to clash with"
        )
    }

    func testReturnsZeroWhenNoChargerHasEverPosted() {
        XCTAssertEqual(
            NotificationDecision.devicePostDelay(
                elapsedSinceLastChargerPost: nil,
                presentationGap: .milliseconds(500)
            ),
            .zero,
            "nil (no charger post yet this launch) must not be treated as 'infinitely recent'"
        )
    }

    func testReturnsZeroExactlyAtTheBoundary() {
        XCTAssertEqual(
            NotificationDecision.devicePostDelay(
                elapsedSinceLastChargerPost: .milliseconds(500),
                presentationGap: .milliseconds(500)
            ),
            .zero,
            "elapsed exactly equal to the gap means the gap has already fully elapsed, not 'still inside it'"
        )
    }

    func testPlugInDirectionsNaturalSeparationIsNeverDelayed() {
        // The plug-in direction's charger and device settles land roughly 2s
        // apart in practice. That used to be a comfortable 4x margin over
        // the 500ms gap; now that the gap itself is 2s (measured
        // insufficient at 500ms, see `deferredDeviceDiffPresentationGapWindow`'s
        // doc comment), the margin is gone -- a plug-in whose natural
        // separation happens to land AT or under 2s could now get delayed
        // for real, not just in a synthetic test. 2.5s here is a deliberately
        // generous separation (comfortably above the 2s production gap) so
        // this still demonstrates "genuinely separated, not delayed", not the
        // boundary case `testReturnsZeroExactlyAtTheBoundary` already covers.
        XCTAssertEqual(
            NotificationDecision.devicePostDelay(
                elapsedSinceLastChargerPost: .milliseconds(2500),
                presentationGap: .milliseconds(2000)
            ),
            .zero,
            "a plug-in separation comfortably above the 2s gap must remain undelayed"
        )
    }
}
