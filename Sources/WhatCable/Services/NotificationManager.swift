import Foundation
import Combine
import UserNotifications
import os.log
import WhatCableCore
import WhatCableNotifications
import WhatCableDarwinBackend
import WhatCableAppKit

/// The subset of `UNUserNotificationCenter` the default `notificationSink`
/// drives. Extracted as a protocol so a test can inject a fake, recording
/// center and exercise the REAL `notificationSink` closure end to end
/// (rather than replacing it wholesale, which is all the older wiring tests
/// could do), proving the shim executes removals BEFORE add, not just that
/// it eventually calls both. `UNUserNotificationCenter` conforms
/// structurally below: every method here matches its real signature.
protocol NotificationCenterExecuting: AnyObject {
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?)
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    /// Matches `UNUserNotificationCenter`'s real
    /// `removePendingNotificationRequests(withIdentifiers:)`. `add`
    /// enqueues a request that isn't necessarily delivered yet (it can
    /// still be sitting pending), so a same-category repost that only
    /// called `removeDeliveredNotifications` could leave an EARLIER,
    /// not-yet-delivered request to land on its own moments later,
    /// standing alongside the new one (Codex P2 finding). Removing both
    /// pending and delivered before every `add` closes that gap.
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func getDeliveredNotifications(completionHandler: @escaping @Sendable ([UNNotification]) -> Void)
    func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void)
}

extension UNUserNotificationCenter: NotificationCenterExecuting {}

/// Posts user notifications when USB-C cables / power sources connect or
/// disconnect, gated by the user's `AppSettings.notifyOnChanges` preference.
///
/// All timing and sequencing (settle debounce, parked-diff bookkeeping,
/// presentation gap, absolute deadline, token/generation guards) lives in
/// `DeviceDiffSequencer`, in `WhatCableNotifications`. This type is the thin
/// app-side shim around it: it subscribes to `WatcherHub`'s publishers and
/// feeds the sequencer plain values, executes the sequencer's post requests
/// via `UNUserNotificationCenter`, gates on `AppSettings.notifyOnChanges`,
/// and forwards diagnostic log lines. See `DeviceDiffSequencer`'s own doc
/// comment for the ordering mechanism itself.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private nonisolated static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "notifications")

    private var cancellables = Set<AnyCancellable>()

    /// The sequencer this shim drives. `ContinuousClock` in production; a
    /// sequencer test builds its own instance with a fake clock instead.
    /// Not `private`: a wiring test still reaches into `NotificationManager`
    /// via `@testable import` for the handful of concerns that remain here
    /// (`notificationSink`), and the sequencer itself needs to be readable
    /// for `AppSettings.requestNotificationAuthorization`-style plumbing if
    /// that ever grows.
    let sequencer: DeviceDiffSequencer<ContinuousClock>

    /// `NotificationCategory` moved to `WhatCableNotifications` (pure, no
    /// `UNUserNotificationCenter` dependency). Typealiased here so every
    /// existing call site (`NotificationManager.NotificationCategory`,
    /// `.device`, `.charger`) keeps compiling unchanged.
    typealias NotificationCategory = WhatCableNotifications.NotificationCategory

    /// `NotificationContent` itself moved to `WhatCableNotifications` as a
    /// top-level type; typealiased here so every existing call site
    /// (`NotificationManager.NotificationContent`) keeps compiling unchanged.
    typealias NotificationContent = WhatCableNotifications.NotificationContent

    /// `DeliveryDirective` decides the identifier a post uses and what to
    /// remove first; typealiased for the same reason as the two above.
    typealias DeliveryDirective = WhatCableNotifications.NotificationDecision.DeliveryDirective

    /// Folds every registered Pro cable-label provider into one feed (at
    /// most one registers in practice; see
    /// `PluginRegistry.notificationCableLabelProviders`'s doc comment). No
    /// providers at all (the public-mirror build) -> nil: the feature is
    /// unavailable, matching the free build with Pro locked. With
    /// providers, only the ones that actually returned a value (non-nil)
    /// contribute; if EVERY provider returned nil (licence locked), the
    /// fold is nil too, not an empty feed. Collapsing "unavailable" into
    /// "available, empty" would let a licence transition mid-session read,
    /// to the sequencer's diff, as every attached labelled cable
    /// disconnecting or appearing at once.
    ///
    /// `hasSavedCables` folds by OR (any provider reporting a saved cable
    /// is enough), `attachedLabelled` merges first-writer-wins, matching
    /// the same policy the old bare-dictionary fold used.
    /// `attachedLabelledByPort` (issue #593) folds with the SAME
    /// first-writer-wins policy as `attachedLabelled`, since it carries the
    /// same cables, just re-keyed by port instead of by cable ID.
    /// `portsAwaitingCableIdentity` and `portsWithResolvedCableIdentity`
    /// both fold by UNION, not first-writer-wins: they are sets of ports,
    /// not keyed choices between competing values, and union is right for
    /// each on its own terms. Any provider still waiting on a port is reason
    /// enough for the charger path to wait on it too (erring toward waiting
    /// costs one bounded window; erring the other way posts a banner that
    /// can never be corrected), and any provider that has SEEN a port answer
    /// is reason enough to stop waiting on it.
    ///
    /// With one provider registered, which is the shipping configuration,
    /// the two sets stay disjoint because that provider partitions its own
    /// connected ports between them. What a DISAGREEMENT would actually do,
    /// stated correctly (the previous wording here claimed `reconcileChargers`
    /// only ever asks whether a port is resolved, which is false and was an
    /// F5 review finding): a port in both sets ARMS the grace, because
    /// `reconcileChargers` reads the awaiting set to decide that, and then
    /// COLLAPSES it on the very next publish, because `updateLabelledCables`
    /// reads the resolved set to decide that. So the cost of a disagreement
    /// is one extra publish of latency, bounded by the grace cap either way.
    /// Nothing is corrupted, but it is not a no-op, and a future reader
    /// should not be told it is.
    ///
    /// A free function of `providers` rather than a closure reading
    /// `PluginRegistry.shared` directly, purely so it's testable in
    /// isolation: `PluginRegistry` is an append-only global singleton (no
    /// way to reset registrations between tests), so a test asserting on
    /// "zero providers registered" against the live registry would be
    /// order-dependent on whatever else in the same process happened to
    /// call `bootstrapPlugins` first. Passing the provider list in as a
    /// plain argument sidesteps that entirely.
    static func foldLabelledCables(
        from providers: [() -> WhatCableNotifications.NotificationDecision.CableLabelFeed?]
    ) -> WhatCableNotifications.NotificationDecision.CableLabelFeed? {
        guard !providers.isEmpty else { return nil }
        var attachedLabelled: [String: String] = [:]
        var attachedLabelledByPort: [String: String] = [:]
        var portsAwaitingCableIdentity: Set<String> = []
        var portsWithResolvedCableIdentity: Set<String> = []
        var hasSavedCables = false
        var anyAvailable = false
        for provider in providers {
            guard let feed = provider() else { continue }
            anyAvailable = true
            hasSavedCables = hasSavedCables || feed.hasSavedCables
            attachedLabelled.merge(feed.attachedLabelled, uniquingKeysWith: { first, _ in first })
            attachedLabelledByPort.merge(feed.attachedLabelledByPort, uniquingKeysWith: { first, _ in first })
            portsAwaitingCableIdentity.formUnion(feed.portsAwaitingCableIdentity)
            portsWithResolvedCableIdentity.formUnion(feed.portsWithResolvedCableIdentity)
        }
        guard anyAvailable else { return nil }
        return WhatCableNotifications.NotificationDecision.CableLabelFeed(
            hasSavedCables: hasSavedCables,
            attachedLabelled: attachedLabelled,
            attachedLabelledByPort: attachedLabelledByPort,
            portsAwaitingCableIdentity: portsAwaitingCableIdentity,
            portsWithResolvedCableIdentity: portsWithResolvedCableIdentity
        )
    }

    /// Where `notificationSink` actually calls `UNUserNotificationCenter`.
    /// `lazy`, not a plain stored default: `UNUserNotificationCenter.current()`
    /// aborts outside a real, signed app bundle (`bundleProxyForCurrentProcess
    /// is nil`), which is exactly the environment `swift test` runs in. A
    /// plain `= UNUserNotificationCenter.current()` default is evaluated
    /// during `init`, i.e. the moment ANYTHING first touches
    /// `NotificationManager.shared`, so it would crash every test in the
    /// suite, not just ones that use this property. `lazy` defers that
    /// resolution to the first actual READ, and nothing reads `center`
    /// except `notificationSink`'s own body and a test that assigns a fake
    /// first. `var`: a test swaps this for a fake, recording center to
    /// drive the real `notificationSink` closure and observe ordering.
    lazy var center: NotificationCenterExecuting = UNUserNotificationCenter.current()

    /// A string unique to this app launch, generated ONCE here (the only
    /// place in this feature allowed to call `UUID()`: the
    /// `WhatCableNotifications` module itself never does, see
    /// `DeviceDiffSequencer.init`'s `launchToken` parameter doc comment)
    /// and threaded into the sequencer, which threads it into
    /// `NotificationDeliveryLedger`. The full UUID string, not a truncated
    /// prefix: a 4-character prefix collides across two launches at 1 in
    /// 65536, and a collision landing during the sweep race guard's exact
    /// window (`NotificationDecision.sweepShouldRemove`'s doc comment) would
    /// recreate the very identifier-reuse bug that guard exists to close,
    /// just with the token matching by accident instead of the sweep simply
    /// running late. The full UUID makes that negligible. This also feeds
    /// the sweep's own exclusion check (`sweepShouldRemove`'s
    /// `currentLaunchToken` parameter), so it needs to keep being this
    /// launch's actual token, not just "distinct enough" for identifier
    /// construction.
    private static let launchToken = UUID().uuidString

    private init() {
        sequencer = DeviceDiffSequencer(
            clock: ContinuousClock(),
            currentDevices: { WatcherHub.shared.deviceWatcher.devices },
            currentChargerSources: { WatcherHub.shared.powerWatcher.sources },
            currentDownstreamTBSwitchIDs: {
                Set(WatcherHub.shared.tbWatcher.switches.filter { $0.depth > 0 }.map(\.id))
            },
            currentPorts: { WatcherHub.shared.portWatcher.ports },
            currentAdapter: { SystemPower.currentAdapter() },
            notifyOnChanges: { AppSettings.shared.notifyOnChanges },
            // Not a `[weak self]` capture: `self` isn't fully initialized
            // yet at this point in `init` (this closure is itself part of
            // the expression that initializes `sequencer`, one of `self`'s
            // own stored properties), so Swift refuses to capture it here.
            // Indirecting through the static `shared` singleton instead
            // reads `notificationSink` lazily, at call time (always after
            // `init` has completed), which also means a test that swaps
            // `NotificationManager.shared.notificationSink` is honoured.
            post: { category, content, directive in
                NotificationManager.shared.notificationSink(category, content, directive)
            },
            log: { message in
                NotificationManager.log.info("\(message, privacy: .public)")
            },
            launchToken: Self.launchToken
        )
    }

    func start() {
        // Startup sweep (Codex P1, part 2): clear every delivered
        // notification this module still owns from a PREVIOUS launch. The
        // launch-token fix above stops a fresh launch's own posts from
        // colliding with a stale one, but does nothing about a stale one
        // already sitting in Notification Centre from before this launch
        // even started; this sweep is what actually removes it. Called
        // unconditionally, before anything else in `start()` posts.
        //
        // This USED to reason that nothing has been posted this launch yet
        // at the point this call is made, so every owned identifier found
        // by the completion handler is, by definition, from an earlier
        // launch. That reasoning doesn't hold: `getDeliveredNotifications`
        // is async with unbounded latency, so under login contention its
        // completion can run AFTER this launch's own first post has already
        // landed, well after this call site executed. The sweep no longer
        // relies on timing to make that distinction; it excludes anything
        // carrying this launch's own token instead (`sweepShouldRemove`,
        // threaded through below).
        sweepDeliveredNotificationsOwnedFromEarlierLaunches()

        // Prime baseline synchronously, before the Combine subscriptions
        // below, so we don't fire a flurry of "connected" notifications for
        // things already plugged in at launch. Each `@Published` sink below
        // replays its current value the moment it's subscribed to; with the
        // baseline already primed to those same values, that replay diffs as
        // a no-op instead of a fresh connect.
        //
        // This used to prime on the next runloop tick (`DispatchQueue.main.async`)
        // to dodge a startup ordering problem: on M1 Pro/Max/Ultra the
        // charger power source doesn't exist until `powerWatcher.refresh()`
        // has run synthesis, and priming before that refresh happened primed
        // against an empty charger list (issue #568). `WatcherHub.start()`
        // now performs that refresh synchronously before this shim's own
        // `start()` runs, so the async hop is no longer needed and priming
        // can happen right here, in order.
        sequencer.primeBaseline(
            devices: WatcherHub.shared.deviceWatcher.devices,
            chargerSources: WatcherHub.shared.powerWatcher.sources
        )

        WatcherHub.shared.deviceWatcher.$devices
            .sink { [weak self] _ in self?.sequencer.scheduleDeviceDiff() }
            .store(in: &cancellables)

        WatcherHub.shared.powerWatcher.$sources
            .sink { [weak self] sources in self?.sequencer.diffSources(sources) }
            .store(in: &cancellables)

        // Issue #570 part B (saved-cable notification labels): feed the
        // sequencer a fresh folded provider snapshot on every PD identity
        // publish (spec design 2). WatcherHub's own burst refreshes
        // (150/500/1500/3000/6000ms after a change) drive `pdWatcher.refresh()`,
        // so this fires as the e-marker read progresses, with no separate
        // IOKit read or polling of its own here. The subscription exists in
        // every build; for free/locked builds `foldLabelledCables` always
        // returns nil (no providers registered, or every provider returns
        // nil), so this is an idle no-op there.
        WatcherHub.shared.pdWatcher.$identities
            .sink { [weak self] _ in self?.pushLabelledCablesFold() }
            .store(in: &cancellables)

        // Licence-staleness fix (gate finding, Codex 1 + 4): a licence
        // DEACTIVATION never touches `pdWatcher.$identities` at all (no PD
        // identity changed), so without this second subscription a lock
        // could sit unseen by the sequencer indefinitely -- past the 5s
        // hold cap, past the 2s device-post spacing floor, however long
        // until the next unrelated PD publish happens to fire. `didRefresh`
        // is WatcherHub's own tick, fired after every steady-poll or burst
        // `refreshAll()` (see its doc comment), which runs at the hub's 1s
        // VISIBLE cadence: the Settings screen a licence deactivation
        // happens on IS a visible UI surface, so the hub is already in that
        // 1s cadence the moment the toggle flips. Re-pushing the fold here
        // means the nil feed reaches the sequencer within ~1s of a lock,
        // comfortably inside any 5s hold or 2s spacing window it might be
        // sitting in the middle of.
        WatcherHub.shared.didRefresh
            .sink { [weak self] _ in self?.pushLabelledCablesFold() }
            .store(in: &cancellables)

        // Fix 4 (licence deactivation reaching the label provider):
        // subscribe to every registered change signal (in practice, at most
        // one -- LicenceManager's licenceDidChange, wired through
        // PluginRegistry.notificationCableLabelChangeSignals by
        // bootstrapPlugins) so an in-app activate/deactivate re-pushes the
        // fold immediately, rather than waiting for the didRefresh tick
        // above (~1s) or the next PD identity publish. This file never
        // imports WhatCablePlugins/LicenceManager directly -- the seam is
        // the whole point (see that registry property's doc comment). The
        // public-mirror stub's bootstrapPlugins registers nothing, so this
        // array is empty there and the loop below subscribes to nothing.
        for signal in PluginRegistry.shared.notificationCableLabelChangeSignals {
            signal
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.pushLabelledCablesFold() }
                .store(in: &cancellables)
        }
    }

    /// Recomputes the folded provider snapshot and hands it to the
    /// sequencer. Shared by both feed subscriptions above (PD identity
    /// publishes and the hub's own refresh tick) so they can't drift into
    /// two different fold call sites.
    private func pushLabelledCablesFold() {
        sequencer.updateLabelledCables(
            NotificationManager.foldLabelledCables(from: PluginRegistry.shared.notificationCableLabelProviders)
        )
    }

    /// Fetches delivered notifications from `center` and removes every one
    /// `NotificationDecision.ownsIdentifier` claims. `center` is captured
    /// as a local `let` (not re-read as `self.center` inside the
    /// completion), for the same reason `notificationSink` below captures
    /// it the same way: `UNUserNotificationCenter` can call completion
    /// handlers on an arbitrary queue, and `center` is a plain,
    /// non-actor-isolated protocol requirement, so reading it once up
    /// front (on the `@MainActor` call site) and using the captured value
    /// inside the closure avoids ever touching `self` off the main actor.
    ///
    /// Split from `removeOwnedDeliveredNotifications(identifiers:via:currentLaunchToken:)`
    /// below on purpose: `UNNotification` has no public initializer, so no
    /// test in this codebase can construct one to drive this method's own
    /// completion handler end to end (see `RecordingCenter`'s doc comment
    /// on `NotificationManagerDeliveryExecutionTests`). The actual
    /// decision-and-removal logic lives in the `nonisolated static` method
    /// below instead, which takes a plain `[String]` and so IS directly
    /// testable; this method is the thin, untestable wrapper that adapts
    /// the real API's `[UNNotification]` down to that shape.
    private func sweepDeliveredNotificationsOwnedFromEarlierLaunches() {
        let sweepCenter = center
        // Captured as a local `let`, same reasoning as `sweepCenter` right
        // above: the completion handler below can run off the main actor,
        // and `launchToken` is a main-actor-isolated static property, so
        // reading it once here (on the `@MainActor` call site) rather than
        // as `Self.launchToken` inside the closure is what keeps the
        // closure itself free of any main-actor-isolated reference.
        let currentLaunchToken = Self.launchToken
        sweepCenter.getDeliveredNotifications { notifications in
            NotificationManager.removeOwnedDeliveredNotifications(
                identifiers: notifications.map(\.request.identifier),
                via: sweepCenter,
                currentLaunchToken: currentLaunchToken
            )
        }
    }

    /// The actual startup-sweep decision: filter `identifiers` down to the
    /// ones `NotificationDecision.sweepShouldRemove` says are safe to clear
    /// (owned by this module AND not carrying `currentLaunchToken`), and if
    /// any survive, remove them via `center`. `nonisolated static` rather
    /// than an instance method: it touches no `NotificationManager` state
    /// (`center` and `currentLaunchToken` are parameters, not read from
    /// `self`), so it needs no main-actor isolation, which is what lets
    /// `sweepDeliveredNotificationsOwnedFromEarlierLaunches` call it
    /// directly from inside a completion handler that may run off the main
    /// actor. Not `private`: a wiring test calls this directly with a
    /// plain `[String]`, proving the filter-and-remove behaviour without
    /// needing a real `UNNotification`.
    nonisolated static func removeOwnedDeliveredNotifications(
        identifiers: [String],
        via center: NotificationCenterExecuting,
        currentLaunchToken: String
    ) {
        let owned = identifiers.filter {
            WhatCableNotifications.NotificationDecision.sweepShouldRemove($0, currentLaunchToken: currentLaunchToken)
        }
        guard !owned.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: owned)
    }

    /// Request notification permission. Call when the user enables the toggle.
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        Self.log.error("Notification auth failed: \(error.localizedDescription, privacy: .public)")
                    } else {
                        Self.log.info("Notification auth granted: \(granted)")
                    }
                }
            default:
                break
            }
        }
    }

    /// Where a notification actually gets posted. Injected (default is the
    /// real `UNUserNotificationCenter` flow, via `center`) so a test can
    /// drive `notificationSink` itself, the real call site, rather than only
    /// the pure content-decision functions in `WhatCableNotifications`.
    /// Mirrors `UpdateChecker.notificationSink`: without a seam like this, a
    /// wiring test can only prove the pure rules agree with each other,
    /// never that the plumbing between them (e.g. the sequencer's
    /// parked-diff landing actually reaching `UNUserNotificationCenter`) is
    /// still wired up.
    ///
    /// The module decides delivery (`DeliveryDirective`); this closure only
    /// EXECUTES it: remove whatever the directive names, then post under its
    /// identifier. It makes no delivery decisions of its own, and never
    /// reuses an identifier, so every post always banners regardless of what
    /// still sits in Notification Centre (the point of this change: see
    /// `NotificationDecision.DeliveryDirective`'s doc comment for the
    /// no-banner fault this replaces).
    var notificationSink: (NotificationCategory, NotificationContent, DeliveryDirective) -> Void = { category, content, directive in
        let center = NotificationManager.shared.center

        let mutableContent = UNMutableNotificationContent()
        mutableContent.title = content.title
        if !content.subtitle.isEmpty { mutableContent.subtitle = content.subtitle }
        if !content.body.isEmpty { mutableContent.body = content.body }
        mutableContent.sound = nil

        let bodyLineCount = content.body.isEmpty ? 0 : content.body.split(separator: "\n").count
        NotificationManager.log.info("postNotification: identifier=\(directive.identifier, privacy: .public) removeDelivered=\(directive.removeDeliveredIdentifiers.joined(separator: ", "), privacy: .public) removePending=\(directive.removePendingIdentifiers.joined(separator: ", "), privacy: .public) title=\(content.title, privacy: .public) subtitle=\(content.subtitle, privacy: .public) bodyLines=\(bodyLineCount, privacy: .public)")

        // Executes the directive's removals, BEFORE the add below. One
        // notification per category standing in Notification Centre at any
        // time is now enforced here, explicitly, rather than by macOS's own
        // identifier-replacement semantics (which the fresh-identifier-per-
        // post scheme below deliberately stops relying on).
        //
        // Gate-fixes fix 2: the two lists are executed SEPARATELY now, each
        // against its own directive field, rather than the same list
        // against both APIs. `removeDeliveredIdentifiers` (always the
        // previous same-category identifier, if any) always clears whatever
        // has already reached Notification Centre.
        // `removePendingIdentifiers` is populated ONLY when the previous
        // post is recent enough it might still be sitting PENDING (enqueued
        // via `add` but not yet delivered): with the device-post spacing
        // floor, that's normally empty, so a previous post that's still
        // pending after a full spacing window is deliberately left alone
        // rather than swept (see `DeliveryDirective.removePendingIdentifiers`'s
        // doc comment for the trade-off).
        if !directive.removeDeliveredIdentifiers.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: directive.removeDeliveredIdentifiers)
        }
        if !directive.removePendingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: directive.removePendingIdentifiers)
        }

        // Diagnostic only, async, non-blocking: snapshot of what's actually
        // sitting in Notification Centre right around this post, the
        // forensic hook for the unreproduced no-banner fault (owner report,
        // 2026-08-26). Doesn't gate or delay the add below.
        center.getDeliveredNotifications { notifications in
            let ids = notifications.map(\.request.identifier).joined(separator: ", ")
            NotificationManager.log.info("postNotification: deliveredCount=\(notifications.count, privacy: .public) deliveredIdentifiers=\(ids, privacy: .public)")
        }

        // Diagnostic only: surface whether the system would even show this,
        // so a "posted but never seen" report can be told apart from
        // "never posted". Doesn't gate or change the post below.
        center.getNotificationSettings { settings in
            NotificationManager.log.info("postNotification: authorizationStatus=\(settings.authorizationStatus.rawValue, privacy: .public) alertSetting=\(settings.alertSetting.rawValue, privacy: .public)")
        }

        // Never a reused identifier (see `DeliveryDirective`'s doc comment):
        // macOS therefore has nothing to "replace" and always banners this.
        let request = UNNotificationRequest(
            identifier: directive.identifier,
            content: mutableContent,
            trigger: nil
        )
        center.add(request, withCompletionHandler: { error in
            if let error {
                NotificationManager.log.error("Post failed: \(error.localizedDescription, privacy: .public)")
            }
        })
    }
}
