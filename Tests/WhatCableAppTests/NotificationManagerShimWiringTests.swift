import XCTest
import Combine
import Foundation
import UserNotifications
import WhatCableCore
import WhatCableAppKit
import WhatCableDarwinBackend
@testable import WhatCable
@testable import WhatCableNotifications

/// Proves the app-side shim's `post` closure actually reaches
/// `NotificationManager.shared.notificationSink`, not just that the
/// sequencer's OWN unit tests agree with themselves. Since unit 2 of the
/// notifications-module extraction, nothing else in the suite drives
/// `NotificationManager.shared.sequencer` end to end: every timing behaviour
/// moved to `DeviceDiffSequencerTests`, which constructs its own standalone
/// sequencer and never touches the app's shared singleton or its `post`
/// closure at all. If that closure's indirection through `notificationSink`
/// (`NotificationManager.swift`'s `init`, documented there as necessary
/// because `self` isn't fully initialized yet at that point) were ever
/// silently disconnected, this suite would otherwise stay green.
///
/// Drives `runNowOrDelayForRecentChargerPost` directly (internal on
/// `DeviceDiffSequencer`, reachable via `@testable import
/// WhatCableNotifications`) rather than `reconcileChargers`: that path posts
/// synchronously with no dependency on the real, live charger set
/// `WatcherHub.shared.powerWatcher.sources` returns in the `swift test`
/// process (which the old, now-removed wiring tests' equivalent charger-path
/// tests DID depend on, and is genuinely nondeterminate: this Mac may or may
/// not be on external power when the suite runs). `lastChargerPostTime` is
/// reset to `nil` first so `devicePostDelay` always resolves to zero delay,
/// regardless of what an earlier test in the suite may have left behind.
final class NotificationManagerShimWiringTests: XCTestCase {
    private func fakeDevice(id: UInt64) -> USBDevice {
        USBDevice(
            id: id, locationID: 0x01_00_00_00, vendorID: 0, productID: 0,
            vendorName: nil, productName: "Shim Wiring Test Device", serialNumber: nil,
            usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
    }

    // This test writes `settings.notifyOnChanges`, backed by
    // `UserDefaults.standard`, a domain every `swift test` process on this
    // machine shares. Wrapped in `withScratchAppSettingsDefaults` so a
    // concurrent run can't flip it mid-assertion.
    @MainActor
    func testASequencerGeneratedPostReachesNotificationManagersSink() {
        withScratchAppSettingsDefaults {
            let manager = NotificationManager.shared
            let sequencer = manager.sequencer
            let settings = AppSettings.shared

            let originalSink = manager.notificationSink
            let originalDidPrimeBaseline = sequencer.didPrimeBaseline
            let originalKnownDevices = sequencer.knownDevices
            let originalLastChargerPostTime = sequencer.lastChargerPostTime
            let originalNotifyOnChanges = settings.notifyOnChanges
            let originalRequestAuth = settings.requestNotificationAuthorization
            settings.requestNotificationAuthorization = {}
            defer {
                manager.notificationSink = originalSink
                sequencer.didPrimeBaseline = originalDidPrimeBaseline
                sequencer.knownDevices = originalKnownDevices
                sequencer.lastChargerPostTime = originalLastChargerPostTime
                settings.notifyOnChanges = originalNotifyOnChanges
                settings.requestNotificationAuthorization = originalRequestAuth
            }

            settings.notifyOnChanges = true
            sequencer.didPrimeBaseline = true
            sequencer.knownDevices = [:]
            sequencer.lastChargerPostTime = nil

            var posted: [(NotificationManager.NotificationCategory, NotificationManager.NotificationContent, NotificationManager.DeliveryDirective)] = []
            manager.notificationSink = { category, content, directive in posted.append((category, content, directive)) }

            sequencer.runNowOrDelayForRecentChargerPost([fakeDevice(id: 9001)])

            XCTAssertEqual(
                posted.map(\.0),
                [.device],
                "a sequencer-generated device post must reach NotificationManager.shared's own notificationSink"
            )
            XCTAssertEqual(posted.first?.1.title, "Connected: Shim Wiring Test Device")
            XCTAssertFalse(
                posted.first?.2.identifier.isEmpty ?? true,
                "the sink must receive a non-empty delivery directive identifier"
            )
        }
    }

    /// Gate-fixes fix 3 (licence staleness, Codex 1 + 4): `NotificationManager.start()`
    /// must ALSO subscribe to `WatcherHub.shared.didRefresh`, re-pushing the
    /// folded provider snapshot on every tick, not just on PD identity
    /// publishes. A licence deactivation never touches `pdWatcher.$identities`
    /// at all (no PD identity changed), so without this second subscription
    /// a lock could sit unseen by the sequencer far longer than the 5s hold
    /// cap or the 2s device-post spacing floor.
    ///
    /// Proves the wiring by registering a temporary provider on the real,
    /// process-wide `PluginRegistry.shared` (an append-only singleton;
    /// there is no way to unregister, so this closure staying registered
    /// for the rest of the process is accepted, harmless: it always returns
    /// the same fixed feed) and confirming `WatcherHub.shared.didRefresh.send(())`
    /// actually invokes it, which can only happen if `start()` wired the
    /// subscription through to a fold call.
    ///
    /// Red-proof: comment out the `WatcherHub.shared.didRefresh` subscription
    /// in `NotificationManager.start()` and this goes red (the provider is
    /// never called, `callCount` stays 0).
    /// A no-op fake `center`, just enough to let `start()` run without
    /// crashing: `start()`'s startup sweep touches `center` (lazy
    /// `UNUserNotificationCenter.current()`, which aborts outside a signed
    /// app bundle -- see `NotificationManager.center`'s own doc comment),
    /// so it must be swapped out first, exactly like
    /// `NotificationManagerDeliveryExecutionTests`'s `RecordingCenter` does
    /// for its own `start()`-calling test.
    private final class NoOpCenter: NotificationCenterExecuting {
        func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {}
        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
        func getDeliveredNotifications(completionHandler: @escaping @Sendable ([UNNotification]) -> Void) {}
        func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void) {}
    }

    @MainActor
    func testDidRefreshSubscriptionPushesTheFold() {
        let manager = NotificationManager.shared
        manager.center = NoOpCenter()
        manager.start()

        final class CallCounter {
            var count = 0
        }
        let counter = CallCounter()
        PluginRegistry.shared.register(notificationCableLabelProvider: {
            counter.count += 1
            return nil
        })

        let countBeforeRefresh = counter.count
        WatcherHub.shared.didRefresh.send(())

        XCTAssertGreaterThan(
            counter.count, countBeforeRefresh,
            "WatcherHub.shared.didRefresh firing must reach the registered provider through NotificationManager's own subscription"
        )
    }

    /// Fix 4 (licence deactivation reaching the label provider): a change
    /// signal registered via `PluginRegistry.register(notificationCableLabelChangeSignal:)`
    /// (in production, `LicenceManager.licenceDidChange`, wired by
    /// `bootstrapPlugins` -- never referenced directly here, since this file
    /// must never import `WhatCablePlugins`/`LicenceManager`) firing must
    /// push a fresh fold, exactly like the `didRefresh` tick above does.
    /// Registered BEFORE `start()` is called (unlike the provider in the
    /// test above, which is read fresh on every fold call): `start()`
    /// subscribes to `PluginRegistry.shared.notificationCableLabelChangeSignals`
    /// ONCE, by iterating the array at that moment, matching production
    /// ordering (`bootstrapPlugins` populates the registry before
    /// `NotificationManager.shared.start()` runs, in `App.swift`).
    ///
    /// Red-proof: comment out the
    /// `for signal in PluginRegistry.shared.notificationCableLabelChangeSignals`
    /// subscription loop in `NotificationManager.start()` and this goes red
    /// (the provider registered below is never called, `callCount` stays 0).
    @MainActor
    func testRegisteredChangeSignalFiringPushesTheFold() {
        let manager = NotificationManager.shared
        manager.center = NoOpCenter()

        final class CallCounter {
            var count = 0
        }
        let counter = CallCounter()
        PluginRegistry.shared.register(notificationCableLabelProvider: {
            counter.count += 1
            return nil
        })

        let signal = PassthroughSubject<Void, Never>()
        PluginRegistry.shared.register(notificationCableLabelChangeSignal: signal.eraseToAnyPublisher())

        manager.start()

        let countBeforeSignal = counter.count
        signal.send(())

        // The subscription applies `.receive(on: DispatchQueue.main)` (spec
        // design 4), which schedules delivery via `DispatchQueue.main.async`
        // even when `send(())` is itself already called from the main
        // thread/actor, so the fold does not land synchronously within this
        // call. Spin the run loop briefly to let that scheduled block run,
        // rather than asserting immediately (which would only prove the
        // OLD, pre-fix4 didRefresh-style synchronous wiring, not this one).
        let deadline = Date().addingTimeInterval(1.0)
        while counter.count <= countBeforeSignal && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertGreaterThan(
            counter.count, countBeforeSignal,
            "a registered notificationCableLabelChangeSignal firing must reach the registered provider through NotificationManager's own subscription"
        )
    }
}

/// Proves the DEFAULT `notificationSink` implementation (not a test double
/// standing in for it) executes a `DeliveryDirective`'s removals BEFORE it
/// adds the new notification, by injecting a fake, recording
/// `NotificationCenterExecuting` in place of the real
/// `UNUserNotificationCenter`. `NotificationManagerShimWiringTests` above
/// only proves the sequencer's post reaches `notificationSink`; it swaps
/// `notificationSink` out entirely, so it can't see anything about what the
/// real closure body does. This class drives the real closure directly.
final class NotificationManagerDeliveryExecutionTests: XCTestCase {
    /// Records calls in the order they happen, so ordering (not just
    /// "both happened") is what the test asserts.
    private final class RecordingCenter: NotificationCenterExecuting {
        enum Call: Equatable {
            case remove([String])
            case removePending([String])
            // Findings 1: records the full posted content (title, subtitle,
            // body), not just the identifier, so a test can prove the
            // subtitle actually reaches the request `notificationSink`
            // builds, not merely that SOME request was added.
            case add(identifier: String, title: String, subtitle: String, body: String)
            case getDelivered
        }

        private(set) var calls: [Call] = []

        func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
            calls.append(.add(
                identifier: request.identifier,
                title: request.content.title,
                subtitle: request.content.subtitle,
                body: request.content.body
            ))
            completionHandler?(nil)
        }

        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
            calls.append(.remove(identifiers))
        }

        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            calls.append(.removePending(identifiers))
        }

        func getDeliveredNotifications(completionHandler: @escaping @Sendable ([UNNotification]) -> Void) {
            // No real `UNNotification` can be constructed in a test (no
            // public initializer), so this records that the call happened
            // (proving `start()`/`notificationSink` actually reach it) but
            // never invokes the completion handler. `NotificationManager
            // .removeOwnedDeliveredNotifications(identifiers:via:)` below
            // is where the filter-and-remove logic that would normally run
            // INSIDE this completion handler is tested directly instead,
            // with a plain `[String]` standing in for what real
            // `UNNotification`s would supply.
            calls.append(.getDelivered)
        }

        func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void) {
            // Same reasoning as above: `UNNotificationSettings` has no
            // public initializer either, and this diagnostic isn't under
            // test here.
        }
    }

    @MainActor
    func testDefaultSinkExecutesRemovalsBeforeAdd() {
        let manager = NotificationManager.shared

        // No save/restore of `manager.center` around this test (unlike the
        // `notificationSink` swap above): `center` is `lazy`, specifically
        // so nothing resolves the real `UNUserNotificationCenter` under
        // `swift test` (see its doc comment). READING it here just to save
        // the original would force that resolution and crash. Nothing else
        // in this suite depends on `center`'s value, so leaving the fake in
        // place after this test is harmless -- DELIBERATELY, not an
        // oversight. This is a shared, process-wide singleton
        // (`NotificationManager.shared`): once this test runs, EVERY test
        // that runs afterward in the same process (in this file or any
        // other target sharing the process) that touches `manager.center`,
        // or drives the default `notificationSink` without swapping its own
        // fake in first, inherits THIS fake, not the real
        // `UNUserNotificationCenter`. That is intentional and safe here
        // (nothing else currently reads `center` without first assigning
        // its own fake), but it is the reason no `defer { manager.center =
        // original }` exists below: restoring it would force the very
        // `UNUserNotificationCenter.current()` resolution this test exists
        // to avoid, which aborts outside a signed app bundle (no
        // `bundleProxyForCurrentProcess`), i.e. it would crash `swift test`
        // itself. If a future test needs to observe the REAL
        // `UNUserNotificationCenter` default, it cannot rely on `center`
        // still being unassigned by the time it runs.
        let recording = RecordingCenter()
        manager.center = recording

        // Gate-fixes fix 2: the two lists are DELIBERATELY different here
        // (not both `["device-event-1"]` as before the split), to prove the
        // sink executes each against its OWN directive field rather than
        // reusing one list for both APIs.
        let directive = NotificationManager.DeliveryDirective(
            identifier: "device-event-2",
            removeDeliveredIdentifiers: ["device-event-1"],
            removePendingIdentifiers: ["device-event-0"]
        )
        manager.notificationSink(.device, NotificationManager.NotificationContent(title: "Connected: Test Device", body: ""), directive)

        XCTAssertEqual(
            recording.calls,
            // `.getDelivered` between the removals and the add is the
            // sink's own pre-existing forensic diagnostic call (see
            // `notificationSink`'s doc comment: a snapshot of what's
            // sitting in Notification Centre right around this post),
            // unrelated to the startup sweep this fake's `.getDelivered`
            // case also records; it's asserted here purely because it's
            // part of the real, observed call sequence, not because this
            // test cares about it.
            [
                .remove(["device-event-1"]), .removePending(["device-event-0"]), .getDelivered,
                .add(identifier: "device-event-2", title: "Connected: Test Device", subtitle: "", body: ""),
            ],
            "the delivered removal must use removeDeliveredIdentifiers and the pending removal must use its OWN, separate removePendingIdentifiers list, both before the add, and the add must use the directive's own identifier"
        )
    }

    /// An EMPTY `removePendingIdentifiers` (the normal case with the
    /// device-post spacing floor: gate-fixes fix 2) must call NEITHER
    /// `.removePending` nor `.remove` for pending -- the sink only calls
    /// `removePendingNotificationRequests` when that list is non-empty,
    /// mirroring the existing `removeDeliveredIdentifiers` guard.
    ///
    /// Red-proof: remove the `if !directive.removePendingIdentifiers.isEmpty`
    /// guard in `notificationSink` and this goes red (an extra
    /// `.removePending([])` call appears).
    @MainActor
    func testDefaultSinkSkipsPendingRemovalWhenListIsEmpty() {
        let manager = NotificationManager.shared
        let recording = RecordingCenter()
        manager.center = recording

        let directive = NotificationManager.DeliveryDirective(
            identifier: "device-event-3",
            removeDeliveredIdentifiers: ["device-event-2"],
            removePendingIdentifiers: []
        )
        manager.notificationSink(.device, NotificationManager.NotificationContent(title: "Connected: Test Device", body: ""), directive)

        XCTAssertEqual(
            recording.calls,
            [
                .remove(["device-event-2"]), .getDelivered,
                .add(identifier: "device-event-3", title: "Connected: Test Device", subtitle: "", body: ""),
            ],
            "no .removePending call at all when removePendingIdentifiers is empty"
        )
    }

    /// Finding 1: proves the subtitle actually reaches the
    /// `UNNotificationRequest` the real `notificationSink` builds, not just
    /// that `NotificationDecision` computed one correctly (that's already
    /// covered by the module's own tests, which never touch
    /// `UNMutableNotificationContent` at all). Drives the real closure
    /// directly, the same way `testDefaultSinkExecutesRemovalsBeforeAdd`
    /// does above.
    ///
    /// Red-proof: comment out `notificationSink`'s
    /// `mutableContent.subtitle = content.subtitle` line and this goes red.
    @MainActor
    func testDefaultSinkSetsSubtitleOnTheRequestWhenPresent() {
        let manager = NotificationManager.shared
        let recording = RecordingCenter()
        manager.center = recording

        let directive = NotificationManager.DeliveryDirective(
            identifier: "device-event-4",
            removeDeliveredIdentifiers: [],
            removePendingIdentifiers: []
        )
        manager.notificationSink(
            .device,
            NotificationManager.NotificationContent(title: "Connected: Cable Device", subtitle: "Apple TB 1m", body: "10 Gbps"),
            directive
        )

        XCTAssertEqual(
            recording.calls,
            [
                .getDelivered,
                .add(identifier: "device-event-4", title: "Connected: Cable Device", subtitle: "Apple TB 1m", body: "10 Gbps"),
            ],
            "a non-empty subtitle must reach the posted request's own content, unchanged"
        )
    }

    /// The companion negative case: an empty subtitle (the normal, no-label
    /// case) must leave the request's `subtitle` empty, not carry over a
    /// stray default. Same real closure, same fake center.
    @MainActor
    func testDefaultSinkLeavesSubtitleEmptyWhenAbsent() {
        let manager = NotificationManager.shared
        let recording = RecordingCenter()
        manager.center = recording

        let directive = NotificationManager.DeliveryDirective(
            identifier: "device-event-5",
            removeDeliveredIdentifiers: [],
            removePendingIdentifiers: []
        )
        manager.notificationSink(
            .device,
            NotificationManager.NotificationContent(title: "Connected: Test Device", body: ""),
            directive
        )

        XCTAssertEqual(
            recording.calls,
            [
                .getDelivered,
                .add(identifier: "device-event-5", title: "Connected: Test Device", subtitle: "", body: ""),
            ],
            "no label -> the request's subtitle stays empty"
        )
    }

    // MARK: - Startup sweep (Codex P1, part 2)

    /// Direct test of the filter-and-remove decision, bypassing
    /// `getDeliveredNotifications` entirely (see that method's doc comment
    /// above for why): a mix of legacy, current-scheme, and foreign
    /// identifiers goes in, and only the ones `ownsIdentifier` claims come
    /// out the other end, in one `removeDeliveredNotifications` call.
    func testRemoveOwnedDeliveredNotificationsRemovesExactlyTheOwnedIdentifiers() {
        let recording = RecordingCenter()
        // "CURRENT" is a fixed stand-in launch token, deliberately not
        // present in any identifier below: none of these are meant to be
        // excluded by the sweep race guard, only by ownership.
        NotificationManager.removeOwnedDeliveredNotifications(
            identifiers: [
                "device-event", // legacy, owned
                "charger-event", // legacy, owned
                "device-event-abc-7", // current scheme, owned
                "charger-event-4f2a-1", // current scheme, owned
                "update-1.2.3", // foreign, not owned
                "some-random-string", // foreign, not owned
            ],
            via: recording,
            currentLaunchToken: "CURRENT"
        )

        XCTAssertEqual(
            recording.calls,
            [.remove(["device-event", "charger-event", "device-event-abc-7", "charger-event-4f2a-1"])],
            "only identifiers this module owns must be removed; foreign identifiers (update-*, arbitrary strings) must never be touched"
        )
    }

    /// A pure "nothing owned" case gets no removal call at all, not a call
    /// with an empty array: `removeDeliveredNotifications(withIdentifiers:
    /// [])` is a harmless no-op on the real API, but asserting the call
    /// never happens is a stronger, more precise proof of the guard.
    func testRemoveOwnedDeliveredNotificationsCallsNothingWhenNoneAreOwned() {
        let recording = RecordingCenter()
        NotificationManager.removeOwnedDeliveredNotifications(
            identifiers: ["update-1.2.3", "some-random-string"],
            via: recording,
            currentLaunchToken: "CURRENT"
        )
        XCTAssertEqual(recording.calls, [])
    }

    /// Sweep race guard (final gate finding): an identifier carrying THIS
    /// launch's own token must never be removed by the startup sweep, even
    /// though `ownsIdentifier` alone would claim it, because
    /// `getDeliveredNotifications`'s completion has no bounded latency and
    /// can run after this launch's own first post has already landed. Mixed
    /// in with an owned-but-foreign-token identifier and a genuinely foreign
    /// one, to prove the guard is additive on top of ownership, not a
    /// replacement for it.
    func testRemoveOwnedDeliveredNotificationsNeverRemovesTheCurrentLaunchsOwnIdentifier() {
        let recording = RecordingCenter()
        NotificationManager.removeOwnedDeliveredNotifications(
            identifiers: [
                "device-event", // legacy, owned, no token to exclude on
                "device-event-OLDTOKEN-3", // owned, earlier launch's token
                "device-event-CURRENT-1", // owned, but THIS launch's token: must survive
                "foreign", // not owned
            ],
            via: recording,
            currentLaunchToken: "CURRENT"
        )

        XCTAssertEqual(
            recording.calls,
            [.remove(["device-event", "device-event-OLDTOKEN-3"])],
            "the sweep must remove the legacy and earlier-launch identifiers but never the current launch's own"
        )
    }

    /// Cross-category symmetry: the same current-token exclusion must hold
    /// for a charger identifier, not just a device one, since
    /// `sweepShouldRemove` is category-agnostic.
    func testRemoveOwnedDeliveredNotificationsNeverRemovesAChargerIdentifierWithTheCurrentToken() {
        let recording = RecordingCenter()
        NotificationManager.removeOwnedDeliveredNotifications(
            identifiers: ["charger-event-CURRENT-1"],
            via: recording,
            currentLaunchToken: "CURRENT"
        )

        XCTAssertEqual(
            recording.calls, [],
            "a charger identifier carrying the current launch's token must survive the sweep exactly like a device one does"
        )
    }

    /// Proves `start()` itself is wired to fetch delivered notifications for
    /// the sweep, not just that the filter-and-remove logic works in
    /// isolation (the two tests above). Doesn't assert on what happens
    /// inside the completion handler (see `getDeliveredNotifications`'s
    /// fake above for why it can't), only that `start()` reaches
    /// `center.getDeliveredNotifications` at all.
    @MainActor
    func testStartFetchesDeliveredNotificationsForTheStartupSweep() {
        let manager = NotificationManager.shared
        let recording = RecordingCenter()
        manager.center = recording

        manager.start()

        XCTAssertTrue(
            recording.calls.contains(.getDelivered),
            "start() must fetch delivered notifications so the startup sweep can clear anything this module still owns from an earlier launch"
        )
    }
}
