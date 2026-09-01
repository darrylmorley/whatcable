import Foundation
import WhatCableCore

/// Namespace for the pure notification-decision rules moved out of
/// `NotificationManager` (the app-side sequencer that owns the timing
/// machinery: settle tasks, parked-diff state, gap/deadline scheduling).
/// Everything on here is `nonisolated` and side-effect free, so it's testable
/// without `Task`, `UNUserNotificationCenter`, or `WatcherHub`.
public enum NotificationDecision {
    /// What one post should do, decided entirely in the module: the
    /// identifier to post under, and any previously-delivered identifiers
    /// (same category, earlier posts) the shim should clear from
    /// Notification Centre first.
    ///
    /// This replaces the old fixed-per-category identifier
    /// (`"device-event"`/`"charger-event"` reused on every post, relying on
    /// macOS's own identifier-replacement semantics to keep exactly one
    /// notification standing). The owner observed a no-banner fault
    /// (2026-08-26: notifications landed in Notification Centre with no live
    /// banner) that a controlled same-identifier repost didn't reproduce, so
    /// the fix stops depending on those semantics altogether: every post
    /// gets a fresh, never-reused identifier (so macOS always treats it as
    /// new and always banners it), and the "one standing notification per
    /// category" behaviour is now enforced explicitly, by the directive
    /// telling the shim which older identifier to remove.
    public struct DeliveryDirective: Equatable, Sendable {
        /// Identifier this post must use. Never reused, so a banner always
        /// fires: macOS has no reason to treat this post as "replacing" an
        /// existing entry, because nothing already in Notification Centre
        /// carries this identifier.
        public let identifier: String
        /// Previously-delivered identifiers, same category only, that the
        /// shim must remove from Notification Centre before (or alongside)
        /// posting the new one. Empty for a category's first-ever post.
        /// Never more than one entry in the current design (one post per
        /// category ever stands at a time), but `[String]` rather than
        /// `String?` so the shim's removal call
        /// (`removeDeliveredNotifications(withIdentifiers:)`) can hand this
        /// straight through without translating shapes.
        public let removeDeliveredIdentifiers: [String]
        /// The SAME previous-post identifier as `removeDeliveredIdentifiers`,
        /// but only when the previous same-category post is recent enough
        /// that it might still be PENDING (enqueued via `add` but not yet
        /// actually delivered) rather than already sitting in Notification
        /// Centre. Empty otherwise. Gate-fixes finding (Codex 5): with the
        /// device-post spacing floor (`DeviceDiffSequencer`'s device-post
        /// queue), device posts are normally >= one spacing window apart,
        /// so this is normally empty for `.device` -- clearing a PENDING
        /// request that a full spacing window has already elapsed since
        /// would risk destroying a notification that never got the chance
        /// to actually deliver, for no reason (nothing about to replace it
        /// is racing it any more). The one case this stays non-empty is two
        /// posts from the SAME settled batch going out back-to-back with NO
        /// spacing between them (a merged removed+added pair, or a reconnect
        /// content immediately following an unrelated flush) -- there, the
        /// first genuinely might still be pending when the second's `add`
        /// call happens, and the old collapse-both-into-one-list behaviour
        /// still applies.
        ///
        /// Accepted trade-off, deliberate (spec fix 2): a previous post that
        /// is STILL pending after a FULL spacing window has elapsed is left
        /// alone rather than swept. Two standing entries under extreme
        /// Notification Centre contention is judged better than the
        /// alternative, silently destroying a notification that was about
        /// to deliver on its own.
        public let removePendingIdentifiers: [String]

        public init(identifier: String, removeDeliveredIdentifiers: [String], removePendingIdentifiers: [String] = []) {
            self.identifier = identifier
            self.removeDeliveredIdentifiers = removeDeliveredIdentifiers
            self.removePendingIdentifiers = removePendingIdentifiers
        }
    }

    /// Pure identifier construction: `sequence` is a per-category, ever-
    /// increasing counter the caller supplies (`NotificationDeliveryLedger`
    /// owns it in production), never `Date()` or `UUID()` inside this
    /// module, so the result is deterministic and testable without a clock.
    /// `launchToken` is likewise supplied by the caller (never generated
    /// here): a short string unique to the current app launch, folded into
    /// the identifier so a fresh launch's sequence-1 post can never collide
    /// with a previous launch's sequence-1 post still sitting in
    /// Notification Centre (Codex finding: delivered notifications survive
    /// a relaunch even though this module's own counters don't).
    /// `previousIdentifier` is the identifier of the LAST post in the same
    /// category, or `nil` for a category's first post; it becomes the sole
    /// entry in `removeDeliveredIdentifiers` (or an empty array), always.
    /// `previousPostWasRecent` additionally gates `removePendingIdentifiers`
    /// (spec fix 2): the caller (`DeviceDiffSequencer.postNotification`)
    /// knows whether the PREVIOUS same-category post went out within the
    /// spacing window, which this function has no clock access to determine
    /// itself.
    public static func deliveryDirective(
        for category: NotificationCategory,
        sequence: UInt64,
        previousIdentifier: String?,
        previousPostWasRecent: Bool,
        launchToken: String
    ) -> DeliveryDirective {
        DeliveryDirective(
            identifier: "\(category.rawValue)-\(launchToken)-\(sequence)",
            removeDeliveredIdentifiers: previousIdentifier.map { [$0] } ?? [],
            removePendingIdentifiers: previousPostWasRecent ? (previousIdentifier.map { [$0] } ?? []) : []
        )
    }

    /// True when `identifier` is one this module considers itself the
    /// owner of, so the app-side shim's startup sweep (`NotificationManager
    /// .start()`) knows which entries still sitting in Notification Centre
    /// from a PREVIOUS launch are safe to clear. Two shapes count as owned:
    /// - The legacy fixed identifiers this module used before the
    ///   launch-token fix above (`"device-event"`, `"charger-event"`,
    ///   i.e. exactly a `NotificationCategory`'s bare `rawValue`), so
    ///   notifications posted by an older build still get swept.
    /// - Anything prefixed `"<category rawValue>-"` for a known category
    ///   (e.g. `"device-event-4f2a-3"`), which is every identifier this
    ///   module has produced since. The prefix check (not an exact match)
    ///   is deliberate: the launch token and sequence number both vary
    ///   across launches and posts, so there is no fixed string to compare
    ///   against for the current scheme.
    ///
    /// Pure and static, so the shim's sweep and this module's own tests can
    /// both exercise the exact ownership rule without touching
    /// `UNUserNotificationCenter`.
    public static func ownsIdentifier(_ identifier: String) -> Bool {
        for category in [NotificationCategory.device, .charger] {
            if identifier == category.rawValue || identifier.hasPrefix("\(category.rawValue)-") {
                return true
            }
        }
        return false
    }

    /// The startup sweep's actual removal guard: `ownsIdentifier` decides
    /// which identifiers this module could ever have produced; this adds a
    /// second condition, that the identifier must NOT carry the CURRENT
    /// launch's own token.
    ///
    /// Why this is needed: `sweepDeliveredNotificationsOwnedFromEarlierLaunches`
    /// (`NotificationManager.start()`) fires `getDeliveredNotifications`
    /// before this launch has posted anything, on the assumption that
    /// whatever comes back is necessarily from an earlier launch. That
    /// assumption doesn't hold under login contention: `getDeliveredNotifications`
    /// is async with no bounded latency, and this launch's very first post
    /// can land in Notification Centre (and in a second, concurrent
    /// `getDeliveredNotifications` call this launch's own code makes) before
    /// the sweep's completion handler runs. If that happens, `ownsIdentifier`
    /// alone would match the fresh post and the sweep would remove a
    /// notification this launch just posted, seconds after posting it. The
    /// token exclusion closes that: an identifier carrying this launch's own
    /// token can only have been posted by this launch, so it is never safe
    /// to sweep, no matter when the completion handler happens to run.
    ///
    /// The token is matched as `"-<currentLaunchToken>-"` (dashes either
    /// side), the same interior shape `deliveryDirective(for:sequence:
    /// previousIdentifier:launchToken:)` always produces
    /// (`"<category>-<token>-<sequence>"`): this rules out a token that
    /// happens to be a substring of a different token or of the sequence
    /// number matching by accident.
    public static func sweepShouldRemove(_ identifier: String, currentLaunchToken: String) -> Bool {
        ownsIdentifier(identifier) && !identifier.contains("-\(currentLaunchToken)-")
    }

    /// Stack-order fix (owner report): unplugging a powered dock fires a
    /// device settle and a charger settle from the same physical event, and
    /// they used to post device-then-charger. macOS stacks the newest post
    /// on top, so the charger banner landed on top of the richer device
    /// banner, the one users actually read. When both settle windows belong
    /// to the same episode, the charger content must post FIRST so the
    /// device content posts LAST and stacks on top.
    ///
    /// An earlier version of this fix cancelled the pending charger settle
    /// timer and ran `reconcileChargers` early, synchronously, from here.
    /// Review (Codex) caught that `isChargerSettlePending` only means "a
    /// charger update happened in the last `chargerSettleWindow`", not "the
    /// charger set has stopped changing": running the reconcile on that
    /// signal can fire mid-flap, posting exactly the spurious
    /// disconnected/connected pair issue #227's debounce exists to
    /// suppress. So the charger side is never touched early. Instead the
    /// DEVICE post is deferred: `reconcileChargers` still runs on its own
    /// undisturbed 1.5s window, and once it finishes it lands the waiting
    /// device diff itself, so the charger post always precedes it.
    public enum DeviceDiffDisposition: Equatable {
        case runNow
        case deferUntilChargerReconcile
    }

    /// Pure ordering rule: given a charger event still IN FLIGHT in the same
    /// episode as a settling device diff, the device diff must wait for that
    /// charger reconcile to land it, not run immediately.
    ///
    /// The parameter was `chargerSettlePending` until the issue #593 review
    /// (F1). A pending settle used to be the whole of "a charger post is
    /// still owed", because `reconcileChargers` always posted synchronously
    /// once the settle fired. The cable-name grace broke that: its first pass
    /// clears the settle flag, posts nothing, and returns, leaving a charger
    /// banner owed for up to another `chargerCableLabelGraceWindow`. A device
    /// settle landing in that window read `.runNow` and posted AHEAD of the
    /// charger banner, the exact inversion this rule exists to prevent. The
    /// caller now passes the broader signal (`isChargerEventInFlight`), and
    /// the parameter name says so, so a future third way of owing a charger
    /// post has one obvious place to be added.
    public static func deviceDiffDisposition(chargerEventInFlight: Bool) -> DeviceDiffDisposition {
        chargerEventInFlight ? .deferUntilChargerReconcile : .runNow
    }

    /// Whether a Thunderbolt device was involved in this settled batch: a
    /// downstream Thunderbolt fabric switch (depth > 0, so not one of the
    /// Mac's own host-root switches, which are always present) appeared or
    /// disappeared alongside the USB diff. A non-empty symmetric difference
    /// between the baseline and current sets of switch IDs covers both
    /// directions (appear, disappear) and also the case where one appeared
    /// AND a different one disappeared within the same settle window: any
    /// change to the downstream set counts, not just a net change in count.
    /// Pure and separate from `DeviceDiffSequencer` so the rule is
    /// unit-testable without `WatcherHub` or a real Thunderbolt device.
    public static func thunderboltInvolved(previous: Set<Int64>, current: Set<Int64>) -> Bool {
        previous != current
    }

    /// Whether landing a parked device diff, on the reconcile-completion
    /// path specifically, should wait out a deliberate presentation gap
    /// first or run immediately. Pure rule extracted so the decision is
    /// unit-testable without `Task`. Only `landDeferredDeviceDiff(token:
    /// afterChargerPost:)` reads it; the timeout path in `deferDeviceDiff`
    /// never asks, because a diff that timed out waiting for a reconcile has,
    /// by definition, no charger post to clash with.
    public enum DeferredDiffLanding: Equatable {
        case immediate
        case afterPresentationGap
    }

    /// `reconcileChargers` actually posted charger content this time ->
    /// its post and the device post would otherwise land in the same
    /// millisecond and macOS would show only the later one. Nothing posted
    /// -> nothing on screen to clash with, so land immediately, unchanged
    /// from before this fix.
    public static func deferredDiffLanding(reconcilePostedChargerContent: Bool) -> DeferredDiffLanding {
        reconcilePostedChargerContent ? .afterPresentationGap : .immediate
    }

    /// Pure guard behind the "lands exactly once" property: a landing
    /// attempt may proceed only while its captured `token` still matches the
    /// live one. `landDeferredDeviceDiffNow` invalidates the live token (by
    /// incrementing it) as the very first thing it does after this check
    /// passes, before running the diff, so a second attempt with the same
    /// captured token always sees a stale value and backs out.
    public static func shouldLandDeferredDiff(token: Int, liveToken: Int) -> Bool {
        token == liveToken
    }

    /// Both-orders fix: how long a device post must wait, given how long ago
    /// the last CHARGER post actually went out. `nil` elapsed (no charger
    /// post yet this app launch) or an elapsed at or past `presentationGap`
    /// both mean nothing to delay for: zero. Otherwise the REMAINDER of the
    /// window (`presentationGap - elapsed`), not the full window again, so a
    /// device post that already waited some of the gap out (by settling a
    /// little later) doesn't wait the full window a second time. Pure and
    /// separate from `runNowOrDelayForRecentChargerPost` so the arithmetic is
    /// unit-testable without `Task` or a real clock.
    public static func devicePostDelay(
        elapsedSinceLastChargerPost: Duration?,
        presentationGap: Duration
    ) -> Duration {
        guard let elapsed = elapsedSinceLastChargerPost, elapsed < presentationGap else {
            return .zero
        }
        return presentationGap - elapsed
    }

    /// One provider's saved-cable feed (issue #570 part B, post-review
    /// fix). Splits two facts that a bare `[String: String]?` collapsed
    /// into one and got wrong: whether the user has ANY saved cable at all
    /// (`hasSavedCables`), and which ones are CURRENTLY attached and
    /// uniquely identified (`attachedLabelled`). The bug this fixes: the
    /// hold's "is there any point waiting" gate used to read
    /// `attachedLabelled.isEmpty` as a proxy for "no saved cables exist",
    /// but the flagship case for this whole feature -- a user with exactly
    /// ONE saved cable, currently unplugged, who then plugs it in -- has
    /// `attachedLabelled == [:]` at the exact moment the connect settles
    /// (the e-marker hasn't resolved yet, which is the entire reason the
    /// hold exists). Reading that as "no saved cables exist" skipped the
    /// hold and posted unlabelled every single time, on the feature's own
    /// primary scenario. `hasSavedCables` is a separate, provider-supplied
    /// fact (the saved-cables STORE's count, not the attached snapshot), so
    /// an empty attached map never again gets misread as an empty catalog.
    ///
    /// `Sendable`: crosses from the app-side shim's Combine sink into the
    /// `@MainActor` sequencer as a plain value, same as the `[String: String]?`
    /// it replaces.
    public struct CableLabelFeed: Equatable, Sendable {
        /// True when the user has at least one saved cable ANYWHERE, saved
        /// or attached, connected or not. Read once, cheaply, from the
        /// saved-cables store's own count; never inferred from
        /// `attachedLabelled`.
        public let hasSavedCables: Bool
        /// "cableID -> saved name" for saved cables CURRENTLY attached and
        /// uniquely attributed. Exactly the shape the old `[String: String]`
        /// half of the feed carried; empty is a completely normal, common
        /// value (nothing is attached right now), not a signal about
        /// `hasSavedCables`.
        public let attachedLabelled: [String: String]
        /// "port canonicalJoinKey -> saved name" for the SAME cables
        /// `attachedLabelled` holds, keyed by the port they are attached to
        /// instead of by cable ID. The charger path joins on this; the device
        /// path cannot (a USB device tree has no reliable port key) and keeps
        /// using `attachedLabelled` plus the timing machinery.
        public let attachedLabelledByPort: [String: String]
        /// Port canonicalJoinKeys whose connected cable has not identified
        /// itself yet (`CableFingerprint.canTrack` false: no VDO recorded and
        /// not a MagSafe ID-only identity). A name may still be coming for
        /// these; for every other connected port the answer is already in, so
        /// an absent name means the cable simply is not saved.
        ///
        /// INDEPENDENT of attribution, and that is the whole point: a port
        /// can be `canTrack` true and still absent from
        /// `attachedLabelledByPort` (an identified cable that simply is not
        /// saved, or one that matched ambiguously). That case must NOT wait,
        /// and it is the common one, so it cannot be inferred from the two
        /// maps above; it needs this separate fact.
        ///
        /// MagSafe is IN the identified camp, not the awaiting one:
        /// `canTrack` is true for a MagSafe ID-only fingerprint
        /// (`isMagSafeIDOnly`), so a MagSafe port leaves this set as soon as
        /// its VID+PID are read rather than sitting in it forever waiting for
        /// a VDO blob macOS never publishes for MagSafe.
        public let portsAwaitingCableIdentity: Set<String>
        /// The complement of the set above, over CONNECTED ports only:
        /// connected ports whose cable HAS answered (`canTrack` true). While
        /// a port is connected it sits in exactly one of the two sets; once
        /// it is not connected it sits in NEITHER.
        ///
        /// That third state is the whole reason this is a separate set
        /// rather than something inferred from the one above. "Absent from
        /// `portsAwaitingCableIdentity`" conflates "the chip answered" with
        /// "the port is not connected right now", and a USB-C port can
        /// briefly drop out and return during PD renegotiation (the same
        /// flap `chargerSettleWindow` exists to absorb). The charger grace
        /// reads presence HERE as "stop waiting, the answer is in", and
        /// absence from both as "still nothing to go on, keep waiting", so a
        /// flap costs a little latency instead of costing the name the grace
        /// exists to wait for.
        ///
        /// Two sets rather than one `[String: Bool]`: they carry the same
        /// three states (absent / present-awaiting / present-resolved), and
        /// the pair makes the "in neither" case visible at the use site
        /// instead of hiding it behind an optional lookup that reads as a
        /// boolean.
        public let portsWithResolvedCableIdentity: Set<String>

        public init(
            hasSavedCables: Bool,
            attachedLabelled: [String: String],
            attachedLabelledByPort: [String: String] = [:],
            portsAwaitingCableIdentity: Set<String> = [],
            portsWithResolvedCableIdentity: Set<String> = []
        ) {
            self.hasSavedCables = hasSavedCables
            self.attachedLabelled = attachedLabelled
            self.attachedLabelledByPort = attachedLabelledByPort
            self.portsAwaitingCableIdentity = portsAwaitingCableIdentity
            self.portsWithResolvedCableIdentity = portsWithResolvedCableIdentity
        }
    }

    /// The saved-cable label to attach to a settled device notification
    /// (issue #570 part B): when the labelled-cables key SET changed by
    /// EXACTLY ONE cable (added or removed) between two snapshots, that
    /// cable's name; otherwise nil (zero changes, or two-or-more changes,
    /// both read as ambiguous). Same symmetric-difference shape as
    /// `thunderboltInvolved` above.
    ///
    /// Comparing the KEY SETS (cable IDs), not the dictionaries themselves,
    /// is deliberate: a saved cable renamed while it stays connected changes
    /// the VALUE for an unchanged KEY, which must NOT read as a label
    /// change, since nothing about the connection itself changed
    /// ("rename-while-connected is inert").
    ///
    /// Edge case, deliberately accepted (spec #570 part B): one saved
    /// record, two identical physical cables. Attribution matches by
    /// e-marker fingerprint against the saved record, not by physical
    /// cable, so unplugging the first and plugging in the second reports
    /// the SAME cableID both times: the id is present in both `previous`
    /// and `current` throughout the swap, so the key set never changes and
    /// the swap produces no label. A cable moved between ports is inert for
    /// the same reason: the key is cable-ID keyed, not port-keyed, so it
    /// never leaves the map on a port move ("port-move inert").
    public static func cableLabelChange(
        previous: [String: String],
        current: [String: String]
    ) -> (name: String, wasAdded: Bool)? {
        let changedIDs = Set(previous.keys).symmetricDifference(current.keys)
        guard changedIDs.count == 1, let id = changedIDs.first else { return nil }
        if let name = current[id] { return (name, true) }
        if let name = previous[id] { return (name, false) }
        return nil
    }

    /// The saved-cable name, verbatim, for the subtitle slot. `nil` (or the
    /// empty string) returns "" so every existing call site (none of which
    /// pass a label) produces a `NotificationContent` with an empty
    /// subtitle, same as before this feature added the parameter. No
    /// localisation here: this is the user's own saved name, not app copy.
    private static func cableLabelSubtitle(_ cableLabel: String?) -> String {
        cableLabel ?? ""
    }

    /// The cable-plausibility gate behind the notification hold (issue #570
    /// part B, spec "Design 5"). A device tree appearing or vanishing
    /// directly at a Mac port is always cable-mediated (unplugging the
    /// cable is the only way it can happen); a device changing INSIDE an
    /// existing tree (a mouse plugged into an already-connected hub, a
    /// device appearing behind a dock's downstream port) never is, because
    /// nothing about the Mac's own port connection changed. This function
    /// tells the two apart, pure over data `diffDevices` already holds: no
    /// PD or port-key join anywhere, matching the spec's requirement that
    /// cable-ID keying never joins to the device diff's key space.
    ///
    /// The test: walk `group.rootLocationID`'s parent chain
    /// (`USBDevice.parentLocationID`). If any ancestor locationID is
    /// present in BOTH `previousLocationIDs` and `currentLocationIDs` (an
    /// ancestor that existed before this settle window and still exists
    /// after it -- unrelated to whatever changed), that ancestor SURVIVED
    /// the diff, so this group's root sits inside an existing tree: an
    /// in-tree change, not port-level. If the walk reaches the top with no
    /// such surviving ancestor, nothing above this root was already there
    /// AND still there, so the root itself is what appeared/vanished at the
    /// port: a port-level tree change.
    ///
    /// Accepted residual cost, documented in the spec (reviewer amendment
    /// 2): this over-triggers on (a) a device plugged directly into a Mac
    /// port with no saved-name match (unlabelled cable, captive-cable
    /// device) and (b) Thunderbolt-tunnelled downstream devices whose USB
    /// subtree root appears with no physical plug at the Mac's port (dock
    /// wake, tunnel renegotiation). Both fail safe: held the full hold
    /// window, then posted unlabelled, never mislabelled.
    public static func isPortLevelChange(
        group: USBDeviceChangeGrouper.ChangeGroup,
        previousLocationIDs: Set<UInt32>,
        currentLocationIDs: Set<UInt32>
    ) -> Bool {
        var locationID = USBDevice.parentLocationID(group.rootLocationID)
        while let currentAncestor = locationID {
            if previousLocationIDs.contains(currentAncestor), currentLocationIDs.contains(currentAncestor) {
                return false
            }
            locationID = USBDevice.parentLocationID(currentAncestor)
        }
        return true
    }

    /// True when at least one group in either side is a port-level tree
    /// change (`isPortLevelChange`). This is the batch-level trigger for the
    /// notification hold: the hold applies to the WHOLE settled batch (spec
    /// "hold granularity") the moment any group in it is cable-mediated,
    /// even in a MIXED batch where another group in the same settle window
    /// is a plain in-tree change.
    public static func batchNeedsCablePlausibilityHold(
        removedGroups: [USBDeviceChangeGrouper.ChangeGroup],
        addedGroups: [USBDeviceChangeGrouper.ChangeGroup],
        previousLocationIDs: Set<UInt32>,
        currentLocationIDs: Set<UInt32>
    ) -> Bool {
        (removedGroups + addedGroups).contains {
            isPortLevelChange(group: $0, previousLocationIDs: previousLocationIDs, currentLocationIDs: currentLocationIDs)
        }
    }

    /// Decides the full batch of notification content for one settled device
    /// diff: the reconnect gate first, then (when it doesn't fire) the usual
    /// removed-then-added composition. Pure and separate from `diffDevices`
    /// so the GATE ITSELF, not just its two halves, is unit-testable without
    /// `UNUserNotificationCenter`.
    ///
    /// A device can disconnect and re-enumerate under a new entryID within
    /// one settle window (e.g. a hub power-cycling), so the same settled
    /// diff can hold both a removal and an addition for what was physically
    /// one event. Both post under the shared "device-event" identifier
    /// (issue #567), so the second post replaces the first in Notification
    /// Centre: only the LATEST post is ever shown, not both. Removed-before-
    /// added ordering means a device that reconnects within the window
    /// leaves "Connected" standing (its true current state); a device that
    /// only disconnects leaves "Disconnected" standing because there's no
    /// later add to replace it.
    ///
    /// A narrow subset of that "reconnects within the window" case gets its
    /// own wording: exactly one removed group and one added group, matching
    /// by physical port. That flap deserves to say "Reconnected" rather than
    /// silently reading as a fresh "Connected", since to the user it looked
    /// like a fault, not a first-time plug-in. Every other shape (multiple
    /// groups, no match, adds only, removes only) keeps the removed-then-
    /// added composition below untouched.
    ///
    /// - Parameters:
    ///   - addedCableLabel / removedCableLabel: the saved-cable name
    ///     (`cableLabelChange`'s result) to append, direction-aware: only
    ///     the side that matches which way the labelled cable changed ever
    ///     gets a non-nil label, so at most one of the two is ever set.
    ///     `reconnectedNotificationContent` accepts a `cableLabel` parameter
    ///     structurally, but the sequencer (`DeviceDiffSequencer.resolveDevicePost`)
    ///     never passes one on the reconnect path: reviewer amendment 3
    ///     gate-exempts reconnect pairs from the hold AND from labelling
    ///     ("a power-cycling device re-enumerating at the same locationID
    ///     is not a cable event, the label structurally cannot resolve").
    ///     This doc comment previously claimed the opposite (that a label
    ///     WAS threaded into reconnect content); it wasn't, and isn't. Fixed
    ///     as a P3 doc-only correction; no behaviour change.
    public static func deviceNotificationContents(
        removedGroups: [USBDeviceChangeGrouper.ChangeGroup],
        addedGroups: [USBDeviceChangeGrouper.ChangeGroup],
        thunderboltInvolved: Bool = false,
        addedCableLabel: String? = nil,
        removedCableLabel: String? = nil,
        singleDeviceBody: (UInt64) -> String?
    ) -> [NotificationContent] {
        if let removed = removedGroups.first, removedGroups.count == 1,
           let added = addedGroups.first, addedGroups.count == 1,
           isReconnectPair(removed: removed, added: added) {
            return [reconnectedNotificationContent(for: added, cableLabel: addedCableLabel, singleDeviceBody: singleDeviceBody)]
        }
        return removedNotificationContents(groups: removedGroups, thunderboltInvolved: thunderboltInvolved, cableLabel: removedCableLabel)
            + addedNotificationContents(groups: addedGroups, thunderboltInvolved: thunderboltInvolved, cableLabel: addedCableLabel, singleDeviceBody: singleDeviceBody)
    }

    /// True when a removed group and an added group are almost certainly the
    /// same physical device re-enumerating rather than a genuine disconnect
    /// paired with an unrelated connect: same physical port path
    /// (`rootLocationID`, which survives a re-enumeration even though the
    /// entryID doesn't) AND the same product name. A different name at the
    /// same port (a device swapped on that port within the settle window) is
    /// deliberately NOT a reconnect: it falls through to today's separate
    /// "Disconnected" / "Connected" pair instead.
    public static func isReconnectPair(
        removed: USBDeviceChangeGrouper.ChangeGroup,
        added: USBDeviceChangeGrouper.ChangeGroup
    ) -> Bool {
        removed.rootLocationID == added.rootLocationID && removed.rootName == added.rootName
    }

    /// Content for the single "Reconnected: <name>" notification posted for
    /// a matched drop-and-return pair. Same body treatment as
    /// `addedNotificationContents`'s single-group case (member names, or the
    /// speed/vendor line for a memberless group), because the added group's
    /// content is what's true of the device right now.
    public static func reconnectedNotificationContent(
        for added: USBDeviceChangeGrouper.ChangeGroup,
        cableLabel: String? = nil,
        singleDeviceBody: (UInt64) -> String?
    ) -> NotificationContent {
        let title = String(localized: "Reconnected: \(added.rootName)", bundle: _notificationsLocalizedBundle)
        let body = added.memberNames.isEmpty
            ? (singleDeviceBody(added.rootID) ?? "")
            : added.memberNames.joined(separator: "\n")
        return NotificationContent(title: title, subtitle: cableLabelSubtitle(cableLabel), body: body)
    }

    /// Decides what to post for one settled batch of added groups. A dock
    /// with several subtrees (main USB3 hub, USB2 companion hubs, PD device)
    /// arrives as multiple groups in a single settle window; posting one
    /// `UNUserNotificationCenter.add` per group produced 2-3 simultaneous
    /// banners with only the last one visible, so most of the devices never
    /// showed up as "connected" even though they were posted. Mirrors
    /// `removedNotificationContents`'s merge so >1 group becomes ONE
    /// notification, same as a disconnect. See issue #556.
    ///
    /// - Parameter thunderboltInvolved: when true and there's more than one
    ///   group (so this is the MERGED title, never the single-group
    ///   "Connected: <name>" title), the title reads "Thunderbolt devices
    ///   connected" instead of "USB devices connected". Set by the caller
    ///   from `NotificationDecision.thunderboltInvolved(previous:current:)`
    ///   when a downstream Thunderbolt fabric switch appeared or disappeared
    ///   in the same settle window. Defaults to false so existing call sites
    ///   keep compiling and today's wording is byte-identical when it isn't
    ///   passed.
    public static func addedNotificationContents(
        groups: [USBDeviceChangeGrouper.ChangeGroup],
        thunderboltInvolved: Bool = false,
        cableLabel: String? = nil,
        singleDeviceBody: (UInt64) -> String?
    ) -> [NotificationContent] {
        if groups.count == 1, let group = groups.first {
            let title = String(localized: "Connected: \(group.rootName)", bundle: _notificationsLocalizedBundle)
            let body = group.memberNames.isEmpty
                ? (singleDeviceBody(group.rootID) ?? "")
                : group.memberNames.joined(separator: "\n")
            return [NotificationContent(title: title, subtitle: cableLabelSubtitle(cableLabel), body: body)]
        } else if groups.count > 1 {
            let allNames = groups.flatMap { [$0.rootName] + $0.memberNames }
            let baseTitle = thunderboltInvolved
                ? String(localized: "Thunderbolt devices connected", bundle: _notificationsLocalizedBundle)
                : String(localized: "USB devices connected", bundle: _notificationsLocalizedBundle)
            return [NotificationContent(title: baseTitle, subtitle: cableLabelSubtitle(cableLabel), body: allNames.joined(separator: "\n"))]
        }
        return []
    }

    /// Decides what to post for one settled batch of removed groups. Mirrors
    /// `addedNotificationContents`'s merge (>1 group becomes ONE "USB
    /// devices disconnected" notification), extracted so
    /// `deviceNotificationContents` can compose it with the reconnect gate.
    /// See issue #556.
    ///
    /// - Parameter thunderboltInvolved: same swap as
    ///   `addedNotificationContents`'s own parameter, "Thunderbolt devices
    ///   disconnected" in place of "USB devices disconnected", only for the
    ///   merged (>1 group) title.
    public static func removedNotificationContents(
        groups: [USBDeviceChangeGrouper.ChangeGroup],
        thunderboltInvolved: Bool = false,
        cableLabel: String? = nil
    ) -> [NotificationContent] {
        if groups.count == 1, let group = groups.first {
            let title = String(localized: "Disconnected: \(group.rootName)", bundle: _notificationsLocalizedBundle)
            return [NotificationContent(title: title, subtitle: cableLabelSubtitle(cableLabel), body: group.memberNames.joined(separator: "\n"))]
        } else if groups.count > 1 {
            let allNames = groups.flatMap { [$0.rootName] + $0.memberNames }
            let baseTitle = thunderboltInvolved
                ? String(localized: "Thunderbolt devices disconnected", bundle: _notificationsLocalizedBundle)
                : String(localized: "USB devices disconnected", bundle: _notificationsLocalizedBundle)
            return [NotificationContent(title: baseTitle, subtitle: cableLabelSubtitle(cableLabel), body: allNames.joined(separator: "\n"))]
        }
        return []
    }

    /// One changed charger port's line: what it is delivering, and the saved
    /// cable name attributed to that port, when there is one. Issue #593:
    /// the device path can name a cable because a settled device diff joins
    /// on cable ID and timing (`attachedLabelled` plus the grace/episode
    /// machinery in `DeviceDiffSequencer`); the charger path has no device
    /// tree to time against, so it joins on the port itself
    /// (`attachedLabelledByPort`) instead. `cableName` is that join's
    /// result, carried alongside the port key long enough for
    /// `chargerNotificationContents` to decide where the name goes.
    public struct ChargerLine: Equatable, Sendable {
        public let wattage: String
        public let cableName: String?

        public init(wattage: String, cableName: String?) {
            self.wattage = wattage
            self.cableName = cableName
        }
    }

    /// Decides what to post for one settled charger reconcile. With the
    /// shared "charger-event" identifier (issue #567), posting one
    /// notification per changed port meant each later post replaced the
    /// one before it under Notification Centre's own rules, so 2+ charger
    /// changes in a single settle window silently lost all but the last.
    /// Mirrors the device path's merge: every added charger becomes ONE
    /// "Charger connected" post (labels joined by newline), every removed
    /// charger becomes ONE "Charger disconnected" post, same as before for
    /// the single-charger case. Removed comes first, added second, mirroring
    /// `diffDevices`'s ordering so the same "latest post wins" reasoning
    /// applies if a charger both drops and reconnects within the window.
    ///
    /// Empty labels are dropped from the joined body. `chargerLabels` no
    /// longer produces one (a charger whose wattage doesn't resolve says
    /// "Wattage not reported" instead), so this is a guard rather than a live
    /// path: it is what stops any future label gap from rendering as a blank
    /// line, or as a leading newline beside a describable charger.
    ///
    /// Saved-cable name placement (issue #593): a subtitle can only ever say
    /// one thing, so it can only be trusted with a name when there is
    /// exactly one line in that direction (added or removed) AND that line
    /// has a name -- with two or more lines, a subtitle naming one cable
    /// would read as naming the whole merged notification, so instead each
    /// named line gets its own "<wattage> (<name>)" suffix in the body
    /// (`"%@ (%@)"`, restored for this feature) and the subtitle stays
    /// empty. No names anywhere reproduces today's output exactly, subtitle
    /// included: this is a strict superset of the old behaviour, not a
    /// parallel path.
    public static func chargerNotificationContents(
        added: [ChargerLine],
        removed: [ChargerLine]
    ) -> [NotificationContent] {
        var contents: [NotificationContent] = []
        if !removed.isEmpty {
            contents.append(chargerContent(
                title: String(localized: "Charger disconnected", bundle: _notificationsLocalizedBundle),
                lines: removed
            ))
        }
        if !added.isEmpty {
            contents.append(chargerContent(
                title: String(localized: "Charger connected", bundle: _notificationsLocalizedBundle),
                lines: added
            ))
        }
        return contents
    }

    /// One direction's (added or removed) content, isolated from
    /// `chargerNotificationContents` so the subtitle-vs-suffix decision
    /// isn't duplicated between the two call sites above.
    private static func chargerContent(title: String, lines: [ChargerLine]) -> NotificationContent {
        if lines.count == 1, let name = lines[0].cableName {
            return NotificationContent(
                title: title,
                subtitle: cableLabelSubtitle(name),
                body: lines[0].wattage
            )
        }
        // Two or more lines: no subtitle (it can't say which port the name
        // belongs to). Each named line carries its own suffix; an unnamed
        // line passes through untouched, whether or not another line in
        // this same batch has a name.
        let bodyLines = lines.map { line -> String in
            guard let name = line.cableName else { return line.wattage }
            return String(localized: "\(line.wattage) (\(name))", bundle: _notificationsLocalizedBundle)
        }
        return NotificationContent(
            title: title,
            body: bodyLines.filter { !$0.isEmpty }.joined(separator: "\n")
        )
    }

    /// Turns a set of changed charger port keys into their `ChargerLine`s,
    /// sorted by the stable port key rather than left in Set iteration
    /// order. Set and Dictionary don't guarantee a stable order between
    /// runs, so without this the merged notification's line order would
    /// flap for no reason a user could see. Pure and separate from
    /// `reconcileChargers` so the ordering is unit-testable without
    /// `WatcherHub`. A port key with no entry in `labels` is skipped, same
    /// as the wattage-only form this replaces.
    public static func sortedChargerLines(
        for portKeys: some Sequence<String>,
        labels: [String: String],
        cableNames: [String: String]
    ) -> [ChargerLine] {
        portKeys.sorted().compactMap { portKey in
            guard let wattage = labels[portKey] else { return nil }
            return ChargerLine(wattage: wattage, cableName: cableNames[portKey])
        }
    }
}
