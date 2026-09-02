import Foundation
import WhatCableCore

/// Owns every timing/ordering concern behind USB device and charger
/// notifications: debouncing the two raw event streams, deciding which of
/// two near-simultaneous posts must go out first, and bounding how long a
/// post can be delayed. Driven entirely by injected time (`ClockType`) and
/// injected reads/writes (`currentDevices`, `currentChargerSources`,
/// `notifyOnChanges`, `post`, `log`), so it has no dependency on
/// `WatcherHub`, `UNUserNotificationCenter`, or `AppSettings`. The app-side
/// shim (`NotificationManager`) owns those; this type owns the mechanism.
///
/// `@MainActor` on purpose, mirroring the class this was extracted from:
/// every settle task, deadline task, and gap task hops through the main
/// actor, so two of them can never truly run at the same instant. The
/// token/generation guards below lean on that fact.
///
/// Every scheduled `Task { @MainActor [weak self] in ... }` below keeps
/// `self` WEAK across its sleep: it reads whatever window it needs (with a
/// literal fallback matching `init`'s own default) and copies `clock` out
/// as an independent local value before awaiting, then only promotes to a
/// strong `self` after the sleep returns. This mirrors the class this was
/// extracted from, which read its windows via `self?.window ?? default`
/// around a bare `Task.sleep` and re-checked `self` afterward. A sequencer
/// with no other strong reference left can deallocate while one of its own
/// tasks sleeps; a `guard let self` taken BEFORE the sleep would retain it
/// for the sleep's whole duration instead.
///
/// # Ordering mechanism, at a glance
///
/// Two independent settle tasks debounce the two raw event streams before
/// anything gets posted: `deviceSettleTask` (`scheduleDeviceDiff`) and
/// `chargerSettleTask` (`diffSources`). Each waits for its own stream to
/// stop flapping, then runs its diff/reconcile once.
///
/// A device diff that must not post ahead of a same-episode charger post
/// gets PARKED rather than posted immediately. The parking state is:
///   - `deferredDeviceDiffDevices`: the one slot holding the parked diff.
///   - `deferredDeviceDiffToken`: identifies which parked diff is live, so
///     a stale landing attempt can tell it's been superseded and back out.
///   - `deferredDeviceDiffPresentationGapGeneration`: same idea, scoped to
///     just the current presentation-gap task, so a cancelled gap task
///     can't mutate state even if it somehow still runs.
///   - `isPresentationGapPending`: true only while a gap task is the
///     scheduled lander, so a second reconcile landing mid-gap yields to
///     it instead of racing it.
///   - `deferredDeviceDiffPresentationGapTask` / `Window`: the deliberate
///     delay that lets both banners actually present on screen.
///   - `deferredDeviceDiffDeadlineTask` / `Window`: the absolute,
///     non-resetting backstop that bounds the total wait no matter how
///     many times the gap above gets re-scheduled.
///   - `lastChargerPostTime`: when a charger post last actually went out,
///     so a device diff that finds no charger settle CURRENTLY pending can
///     still tell "a charger post just landed" from "nothing to wait for".
///
/// A diff gets parked from exactly three entry points: `deferDeviceDiff`
/// (device settle found a charger settle pending), `parkAndDelayDevicePost`
/// (device settle found no charger settle pending, but a charger post went
/// out moments ago), and `runNowOrDelayForRecentChargerPost` (the router
/// that decides between an immediate post and the `parkAndDelayDevicePost`
/// path above).
///
/// A parked diff LANDS through exactly one of three paths, all converging
/// on `landDeferredDeviceDiffNow`: the synchronous `.immediate` case
/// inside `landDeferredDeviceDiff` (the most common case: a reconcile that
/// posted no charger content of its own), the presentation-gap task
/// (`scheduleGapLanding`), or the absolute deadline task
/// (`scheduleAbsoluteDeadline`). A parked diff can also be DISCARDED
/// rather than landed, if a newer diff supersedes it before any of those
/// three fires (`deferDeviceDiff` / `supersedeAnyParkedDiff` invalidating
/// it in favour of the new one; the superseded diff's own devices are
/// simply dropped, never posted). `landDeferredDeviceDiff(token:
/// afterChargerPost:)`'s doc comment walks through every interleaving of
/// landing and discarding in detail; start there for the mechanics.
///
/// Why TWO windows, not one: the settle windows (`chargerSettleWindow`,
/// `deviceSettleWindow`) exist to group several raw IOKit publishes from
/// one physical event into a single episode. The presentation gap
/// (`deferredDeviceDiffPresentationGapWindow`) is a different problem:
/// giving macOS enough real wall-clock time between two posts that both
/// banners actually render, not just reach Notification Centre's list.
/// The absolute deadline is derived from both, because the worst case has
/// to cover one full charger settle (in case the diff was parked before
/// the charger even started reconciling) plus one full presentation gap
/// (in case the charger reconciles right at the last moment). It carries a
/// THIRD term, `chargerCableLabelGraceWindow`, because a charger reconcile
/// can return without posting at all while it waits a bounded window for a
/// saved cable name (issue #593); a deadline that didn't cover that could
/// expire mid-grace and land the device banner first.
@MainActor
public final class DeviceDiffSequencer<ClockType: Clock> where ClockType.Duration == Duration {
    private let clock: ClockType

    /// Reads the live device list. Injected so the sequencer never depends
    /// on `WatcherHub`; called fresh at the moment each settle task actually
    /// needs it (after its sleep), never the value captured when the
    /// publisher first fired, exactly mirroring the original
    /// `WatcherHub.shared.deviceWatcher.devices` read.
    private let currentDevices: () -> [USBDevice]
    /// Same idea for charger power sources, read fresh inside
    /// `reconcileChargers` (which runs both from the charger settle task and
    /// directly from tests).
    private let currentChargerSources: () -> [PowerSource]
    /// Live IDs of the downstream Thunderbolt fabric switches (depth > 0;
    /// the Mac's own host-root switches are depth 0 and always present, so
    /// they're excluded before this closure is even called). Read fresh at
    /// settle time, same discipline as `currentDevices` /
    /// `currentChargerSources`. A bare `Set<Int64>`, not
    /// `WhatCableCore.IOThunderboltSwitch`, on purpose: the sequencer only
    /// ever needs identity (did the downstream set change), never any other
    /// field on the switch, so the seam carries the smallest type that says
    /// that, rather than a Core model this type has no other use for. The
    /// shim maps it from `WatcherHub.shared.tbWatcher.switches.filter {
    /// $0.depth > 0 }.map(\.id)`.
    private let currentDownstreamTBSwitchIDs: () -> Set<Int64>
    /// Every port on the machine, and the system-wide adapter reading. Both
    /// feed `ChargerWattageSource.resolve` in `chargerLabels`, so a charger
    /// that never wins a PD contract (a third-party MagSafe brick publishes
    /// only a junk Brick ID source, issue #592) still gets a wattage in the
    /// banner instead of a bare "PD source". Injected closures rather than a
    /// direct read for the same reason as the ones above: this module has no
    /// platform imports, so the app-side shim owns the IOKit call.
    private let currentPorts: () -> [AppleHPMInterface]
    private let currentAdapter: () -> AdapterInfo?
    /// Gate read AFTER baseline bookkeeping in `diffDevices` /
    /// `reconcileChargers`, exactly where `AppSettings.shared.notifyOnChanges`
    /// was read in the original, so state stays primed even when
    /// notifications are off.
    private let notifyOnChanges: () -> Bool
    /// Where a decided notification actually gets posted. The shim builds
    /// and submits the real `UNNotificationRequest`; this type only ever
    /// hands it a category, content, and the `DeliveryDirective` deciding
    /// what identifier to post under and what to remove first. The shim
    /// makes NO delivery decisions of its own: it just executes the
    /// directive (remove, then add).
    private let post: (NotificationCategory, NotificationContent, NotificationDecision.DeliveryDirective) -> Void

    /// Per-category sequence counter + last-posted-identifier bookkeeping
    /// behind every `DeliveryDirective`. See its own doc comment for why
    /// it's a separate type rather than more ad-hoc state on this class.
    /// `let`, not `var`: constructed once per sequencer instance and never
    /// swapped out, so "a fresh sequencer starts clean" holds by
    /// construction. Built in `init` now (rather than as a property
    /// initializer), because it needs `launchToken`, an `init` parameter.
    private let deliveryLedger: NotificationDeliveryLedger
    /// Diagnostic log sink. Called with the exact same message text the
    /// original `os.log` calls produced (module stays free of `import os`),
    /// so the shim can wrap each call in `Logger.info("\(msg, privacy:
    /// .public)")` and the printed output is unchanged.
    private let log: (String) -> Void

    // The three below are `internal` (not `private`) for the same reason
    // the original properties on `NotificationManager` were: a
    // `@testable import` sequencer test primes them directly to drive
    // `diffDevices`/`reconcileChargers` themselves, the actual call sites,
    // without needing the injected closures above to already reflect a
    // baseline.
    var knownDevices: [UInt64: USBDeviceChangeGrouper.Snapshot] = [:]
    var knownChargerLabels: [String: String] = [:]
    /// Baseline for `NotificationDecision.thunderboltInvolved(previous:current:)`.
    /// Updated in exactly the same two places `knownDevices` is (primed in
    /// `primeBaseline`, refreshed in `diffDevices` unconditionally, BEFORE
    /// the `notifyOnChanges` gate), so a user who has notifications off and
    /// later turns them on doesn't see a stale baseline manufacture a false
    /// "Thunderbolt involved" on the next diff.
    var knownTBSwitchIDs: Set<Int64> = []

    /// Issue #570 part B (saved-cable notification labels): the sequencer's
    /// live view of "cableID -> saved name" for currently-attached,
    /// uniquely-attributed saved cables. `nil` = the feature reads as
    /// unavailable right now (Pro locked, or no provider registered
    /// anywhere -- the public mirror build); `[:]` = available, nothing
    /// attached. Double-optional semantics, same shape the reverted design
    /// used: the OUTER optionality (this property being `nil` vs `.some`)
    /// is availability, never "no data yet" -- `didPrimeBaseline` is what
    /// tracks the latter, and this stays `nil` until the app-side shim's
    /// first `updateLabelledCables(_:)` call, which can arrive before or
    /// after `primeBaseline`, in either order (see that method's doc
    /// comment; unlike `knownDevices`/`knownChargerLabels`/`knownTBSwitchIDs`
    /// there is no seeding step here).
    ///
    /// Updated UNCONDITIONALLY by every `updateLabelledCables(_:)` call,
    /// independent of whether any device diff is in flight (design "3.
    /// Baseline"): a saved cable's e-marker read can complete anywhere from
    /// milliseconds to ~2-3s after the physical plug, entirely decoupled
    /// from USB device settle timing, so tying this update to `diffDevices`
    /// (the way `knownTBSwitchIDs` is tied to it) would let a connect that
    /// settled before the cable's data arrived permanently poison the
    /// following disconnect's own comparison: the ONLY reference this or a
    /// later diff could compare against would still show the cable never
    /// having been there. Keeping this update independent means the truth
    /// is always current by the time anything reads it.
    ///
    /// This being empty (`[:]`) is a completely ordinary state (nothing is
    /// attached right now) and must NEVER be read as "no saved cables
    /// exist anywhere": see `knownHasSavedCables`, the separate,
    /// provider-supplied fact that answers that question instead.
    var knownLabelledCables: [String: String]?

    /// Issue #593: the SAME cables `knownLabelledCables` holds, keyed by the
    /// port they are attached to instead of by cable ID. Each port appears
    /// under BOTH of its keys, its join key and its plain `portKey`, because
    /// `NotificationCableLabelProvider` publishes every name twice (see its
    /// join-alias helper). That is what lets the charger side, which is keyed
    /// purely by `portKey`, find a name with a plain lookup even on a port
    /// whose own registry walk resolved a UUID.
    /// A MagSafe plug produces no USB device at all, so the device path
    /// (`knownLabelledCables` plus the grace/episode machinery above) can
    /// never reach it; the charger path joins on port identity instead,
    /// which needs this. Same nil-means-unavailable / `[:]`-means-nothing-
    /// attached shape as `knownLabelledCables`, updated in the same place
    /// (`updateLabelledCables(_:)`), for the same reason: both come out of
    /// one attribution pass, so they can never disagree with each other.
    var knownLabelledCablesByPort: [String: String]?

    /// Ports whose connected cable has not answered yet, as of the most
    /// recent `updateLabelledCables(_:)` call
    /// (`NotificationDecision.CableLabelFeed.portsAwaitingCableIdentity`).
    /// The charger cable-name grace waits ONLY on ports in this set.
    ///
    /// Why it has to exist separately: "this added port has no saved name"
    /// on its own cannot tell "the e-marker read is still outstanding" from
    /// "the chip already answered and the cable simply is not saved".
    /// Waiting on the second case charges every charger plug a full grace
    /// window for a name that was never coming, and that is the COMMON case
    /// for anyone who has saved even one cable. This is the provider-supplied
    /// fact that separates them, the same shape of fix as
    /// `knownHasSavedCables` for the device path's own hold.
    ///
    /// A plain `Set`, not an optional: unlike `knownLabelledCablesByPort` it
    /// carries no availability meaning of its own. A nil feed clears it to
    /// empty, which reads as "nothing is awaiting", and that is correct:
    /// with no feed the grace is already blocked by its own nil check, so an
    /// emptied set can never be the thing that lets a wait through.
    ///
    /// The floor this does NOT lift, stated honestly: a cable with a
    /// genuinely silent chip stays in this set for as long as it is plugged
    /// in, so it pays the full window on every charger connect. IOKit cannot
    /// distinguish "the read is outstanding" from "the read completed and
    /// found nothing", so no signal exists that would tell those apart.
    var knownPortsAwaitingCableIdentity: Set<String> = []

    /// The other half of the same partition
    /// (`NotificationDecision.CableLabelFeed.portsWithResolvedCableIdentity`):
    /// connected ports whose cable HAS answered. An armed grace collapses
    /// the moment a port it is waiting on turns up here, whether or not a
    /// name came with it.
    ///
    /// Why this is not simply "absent from
    /// `knownPortsAwaitingCableIdentity`": a port sits in NEITHER set while
    /// it is not connected, and a USB-C port can flap out and back during PD
    /// renegotiation (the same flap `chargerSettleWindow` exists to absorb).
    /// Collapsing on absence would end the grace on a flap and post the
    /// banner unnamed a moment before the name it was waiting for actually
    /// arrived, which is the exact outcome this whole mechanism exists to
    /// prevent. Collapsing on PRESENCE here means a flap fires nothing and
    /// the grace simply runs on: a little latency, no correctness lost.
    ///
    /// What it buys, and why it is not a tail case: a USB-C e-marker is
    /// readable a variable ~2-3s after plug (see
    /// `NotificationCableLabelProvider`'s own doc comment) against a 1.5s
    /// charger settle, so MOST USB-C charger plugs are still awaiting
    /// identity when the settle runs and do arm the grace. The saved ones
    /// already collapsed on the name arriving; without this, every unsaved
    /// one sat out the full cap. `knownPortsAwaitingCableIdentity` alone
    /// only removed the cost for cables that had already answered within the
    /// first 1.5s.
    var knownPortsWithResolvedCableIdentity: Set<String> = []

    /// Whether a saved cable exists ANYWHERE (the whole catalog, not just
    /// what's attached), as of the most recent `updateLabelledCables(_:)`
    /// call. `false` while unavailable (no feed yet, or the feed's own
    /// `nil`).
    ///
    /// Post-review fix: this used to be inferred from `knownLabelledCables`
    /// being non-empty, which is WRONG on the feature's own flagship case.
    /// A user with exactly one saved cable, currently unplugged, has
    /// `knownLabelledCables == [:]` right up until that cable's e-marker
    /// resolves -- and waiting for exactly that is the entire reason the
    /// hold exists. Reading `[:]` as "no saved cables exist anywhere"
    /// skipped the hold and posted unlabelled on every single connect of a
    /// user's only saved cable. This property is instead a fact the
    /// PROVIDER supplies directly (the saved-cables store's own count), so
    /// an empty attached snapshot never again gets misread as an empty
    /// catalog. See `NotificationDecision.CableLabelFeed`'s doc comment for
    /// the full story.
    private var knownHasSavedCables = false

    /// "port `portKey` -> saved cable name" for ports that currently
    /// hold a charger, captured when the charger was first seen and
    /// refreshed on every later feed publish while it stays. A disconnect
    /// reads this, not the live feed: by the time the charger goes, the
    /// cable has gone too and the feed no longer names it. Same reason
    /// `knownChargerLabels` remembers the wattage.
    private var knownChargerCableLabels: [String: String] = [:]

    /// The armed cable-name grace, if a charger reconcile is currently
    /// waiting one out (issue #593). Cancelled by an early collapse in
    /// `updateLabelledCables(_:)` (a name arrived for a port this grace is
    /// waiting on) and by `diffSources(_:)` (a fresh charger episode
    /// starting, whose own settle will reconcile anyway).
    private var chargerCableLabelGraceTask: Task<Void, Never>?
    /// Identity for the CURRENT grace task, bumped every time one is armed
    /// and checked by that task after its sleep before it touches anything.
    /// Same belt-and-braces discipline as
    /// `deferredDeviceDiffPresentationGapGeneration`, for the same reason: a
    /// cancelled or superseded task must not be able to mutate shared state
    /// even if `.cancel()` somehow wasn't observed in time.
    private var chargerCableLabelGraceGeneration = 0
    /// The ADDED port keys the armed grace is waiting on: exactly the ports
    /// that gained a charger but had no saved cable name yet.
    /// `updateLabelledCables(_:)` watches this set so the common case (the
    /// e-marker resolving a couple of hundred milliseconds later) collapses
    /// the grace immediately instead of sitting out the full window. Empty
    /// whenever no grace is armed.
    private var chargerCableLabelGracePortKeys: Set<String> = []
    /// One grace per charger event, no more. Set when a grace is armed,
    /// cleared in `diffSources(_:)`, which is where a genuinely new charger
    /// event starts. Without it the second pass would look at the same
    /// still-unnamed port, decide to wait again, and a charger whose cable
    /// simply isn't saved would never produce a banner at all.
    private var chargerCableLabelGraceUsed = false

    /// The most recent, not-yet-consumed single-cable label transition
    /// (`NotificationDecision.cableLabelChange`'s result), computed fresh
    /// inside `updateLabelledCables(_:)` every time two consecutive non-nil
    /// snapshots differ by exactly one cable ID. "Not-yet-consumed" =
    /// nothing has yet MATCHED and CAPTURED it onto a `DevicePostJob`.
    /// ALWAYS overwritten by the latest transition, whether or not the
    /// previous one was ever consumed: a connect batch that already posted
    /// unlabelled (cap expired before the cable's data arrived) leaves this
    /// event pending, and it is exactly what lets the FOLLOWING disconnect,
    /// whenever it eventually settles, still find the correct vanished-key
    /// transition once the cable's own removal is observed.
    ///
    /// Consumption is CAPTURE-TIME BINDING (gate-fixes P2, follow-up
    /// finding), not fire-time: the two places that ever read this property
    /// -- `resolveDevicePost`'s "usable label already present" branch, and
    /// `flushHeldDeviceBatch` -- both match AND clear it to `nil`
    /// immediately, the moment a `DevicePostJob` is created, copying the
    /// matched value onto that job's own `capturedLabel`. `fireDevicePostJob`
    /// never reads this property at all; it only ever reads the job's own
    /// already-captured value.
    ///
    /// An event sitting here UNCONSUMED (no job has matched it yet) is
    /// completely normal and not stale by itself -- see the connect/cap/
    /// disconnect example above. But it is emphatically NOT "harmless" in
    /// the sense an earlier version of this comment claimed: this file used
    /// to bind at FIRE time (a queued job matched against whatever this
    /// property held at the moment it actually posted, not at the moment it
    /// was created), and that was a genuine bug, not a hygiene nit. A job
    /// enqueued for cable A could sit behind the device-post spacing floor
    /// while cable B's event landed here in the meantime, overwriting A's
    /// own match; when A's job finally fired, it read B's event and posted
    /// with B's name. Binding at capture time is what makes an unconsumed
    /// event safe to leave sitting here: it is never read by anything that
    /// doesn't ALSO consume it in the same breath, so nothing can ever pick
    /// up a value meant for a different job.
    ///
    /// Episode-scoped (fix1, follow-up to the review round above): capture
    /// time is not enough on its own. Two failure paths survived it, both
    /// real: a label arriving AFTER its own batch's cap (the batch already
    /// flushed unlabelled) used to sit here indefinitely and label the NEXT
    /// unrelated batch that happened to settle in the same direction; and a
    /// labelled-cables change with NO device diff at all (a bare TB
    /// renegotiation flap) used to park an event that could label a much
    /// later, completely unrelated plug. `episodeID` is what closes both
    /// holes: every event is now tagged with the `deviceEpisodeID` of
    /// whichever settling, parked, or held device episode it was assigned to
    /// at the moment it arrived (see `assignCableLabelEvent(_:)`), and every
    /// consumption site -- the at-settle check in `resolveDevicePost`
    /// (against the `episodeID` PARAMETER that round is running under, not
    /// a live property; see `settlingDeviceEpisodeID`'s doc comment for why)
    /// and `flushHeldDeviceBatch`/`tryFlushHeldDeviceBatchForPendingEvent`
    /// -- only ever matches when that tag equals the episode it is being
    /// checked against. `clearEventIfOwnedBy(_:)`, driving
    /// `closeParkedEpisode()`/`closeHeldEpisode()` and every direct terminal
    /// branch in `diffDevices`/`resolveDevicePost`, clears an event still
    /// tagged to the episode being closed, consumed or not, so a stale tag
    /// can never survive to be misread by a later, unrelated episode.
    ///
    /// Round-2 fix (adversarial review, P2): episode-close clearing alone
    /// missed a quick lock/unlock landing entirely BEFORE the owning episode
    /// ever reaches a terminal path -- the event would still be correctly
    /// owned and still get legitimately consumed once that episode resolves,
    /// even though a lock happened in between. `updateLabelledCables(_:)`
    /// clears this (and `graceCableLabelEvent`) outright on every nil feed
    /// again, on top of episode-close clearing, to close that gap. See
    /// `graceCableLabelEvent` for the fourth case: an event arriving while NO
    /// episode is open at all.
    private var pendingCableLabelEvent: (episodeID: UInt64, name: String, wasAdded: Bool)?

    /// Monotonically increasing, never reused: the source of every
    /// `deviceEpisodeID` handed out below. A device episode is the unit
    /// this file's header doc already describes end to end (settle debounce
    /// through charger deferral, presentation delay, `diffDevices`, and any
    /// cable-plausibility hold): this counter is what gives that unit an
    /// identity a cable-label event can be tagged with.
    private var deviceEpisodeIDCounter: UInt64 = 0

    /// Non-nil from the moment a device episode opens (see
    /// `openDeviceEpisodeIfNeeded()`) until whichever of `runNowOrDelayForRecentChargerPost`
    /// or `deferDeviceDiff` next runs clears it, right after capturing the
    /// episode id into a local value: it is a pure GATE for "may a new raw
    /// publish open a fresh episode", never a source of truth read later in
    /// the pipeline. `diffDevices`/`resolveDevicePost` are handed the
    /// episode id as a PARAMETER instead of reading this property, precisely
    /// because by the time they run it may already be `nil` (this round is
    /// resolving/parking right now) or may belong to a totally different,
    /// NEWER episode (a fresh raw publish opened one while this round was
    /// parked or held) -- see `parkedDeviceEpisodeID` and
    /// `heldDeviceBatchEpisodeID`'s doc comments for why those exist as
    /// separate properties rather than reusing this one across a park/hold.
    ///
    /// P1-a fix (adversarial round 2): opening used to happen only once a
    /// settle round actually FIRED (inside `runNowOrDelayForRecentChargerPost`/
    /// `deferDeviceDiff`, called from `scheduleDeviceDiff`'s task after its
    /// sleep). That silently lost the flagship "label arrives just before
    /// the first USB publish" case under a burst-heavy debounce: each raw
    /// publish resets `scheduleDeviceDiff`'s settle timer with no upper
    /// bound, so four publishes 600ms apart can push the actual fire time
    /// out to 4+ seconds after the label arrived, well past
    /// `deviceSettleWindow` -- the grace slot would expire before the
    /// episode that should claim it ever opened. `openDeviceEpisodeIfNeeded()`
    /// is now called SYNCHRONOUSLY from `scheduleDeviceDiff()` itself, on
    /// EVERY raw publish, not just the one that survives the debounce: the
    /// first publish of a burst opens the episode (and claims the grace slot
    /// there and then, at the moment of the burst's start, not its end);
    /// every further publish in the SAME burst is a no-op here (idempotent
    /// on an already-open episode), which is exactly "further
    /// `scheduleDeviceDiff` calls during the same settle debounce belong to
    /// that episode."
    private var settlingDeviceEpisodeID: UInt64?

    /// Non-nil exactly while a device diff is parked in the
    /// `deferredDeviceDiffDevices` slot (the charger-ordering park/defer/gap/
    /// deadline machinery above, entirely distinct from the cable-plausibility
    /// hold below): the id of the episode that diff belongs to. Set,
    /// alongside `deferredDeviceDiffDevices`, at every park site
    /// (`deferDeviceDiff`, `parkAndDelayDevicePost`), after first closing
    /// whatever was PREVIOUSLY parked (`closeParkedEpisode()`, P1-b fix: a
    /// superseded parked diff's episode must close, not silently lend its
    /// identity to whatever supersedes it). Cleared, together with any event
    /// still tagged to it, the moment that diff is discarded
    /// (`supersedeAnyParkedDiff`) -- and simply cleared (ownership transfers
    /// into the `diffDevices` call, untouched) the moment it actually lands
    /// (`landDeferredDeviceDiffNow`, which reads this value and hands it to
    /// `diffDevices` as the `episodeID` parameter).
    ///
    /// `settlingDeviceEpisodeID` is cleared the instant a diff parks (see
    /// its own doc comment), specifically so a raw publish arriving while
    /// something is parked opens a genuinely FRESH episode rather than
    /// reusing the parked one's id (P1-b fix, adversarial round 2): the
    /// parked-diff-supersede path (`runNowOrDelayForRecentChargerPost`'s
    /// `delay == 0` branch, `supersedeAnyParkedDiff`, then `diffDevices`
    /// directly) used to run under the STILL-OPEN `settlingDeviceEpisodeID`,
    /// so an event that had been tagged to the now-discarded parked diff
    /// could wrongly label the completely unrelated diff that superseded it.
    private var parkedDeviceEpisodeID: UInt64?

    /// Non-nil exactly while `heldDeviceBatch` is non-nil: the id of the
    /// episode that produced the currently held batch, carried over
    /// unchanged from the `episodeID` `resolveDevicePost` was called with at
    /// the moment it decided to hold (same episode, same id -- holding is
    /// not a new episode). Cleared, together with any event still tagged to
    /// it, the moment that batch actually flushes
    /// (`flushHeldDeviceBatch`/`closeHeldEpisode()`). A NEW raw device
    /// publish arriving while a batch is held is free to open a fresh
    /// episode of its own (`settlingDeviceEpisodeID` being `nil` is what
    /// gates that, and holding never sets it) -- this is what lets a
    /// completely unrelated plug settle, and even hold its own batch, while
    /// an OLDER one is still waiting out its cap.
    private var heldDeviceBatchEpisodeID: UInt64?

    /// A cable-label change that arrived while NO device episode was open
    /// at all (`settlingDeviceEpisodeID`, `parkedDeviceEpisodeID`, and
    /// `heldDeviceBatchEpisodeID` all `nil`): the streams have no ordering
    /// guarantee, so a saved cable's identity can legitimately resolve a
    /// moment BEFORE the USB publish that will open its episode ever
    /// arrives. Bounded and single-slot, exactly like `pendingCableLabelEvent`,
    /// but unowned until claimed: the NEXT episode to open
    /// (`openDeviceEpisodeIfNeeded()`) claims it only if `arrivedAt` is
    /// still within `deviceSettleWindow` of `clock.now` at the moment it
    /// opens; otherwise it has expired, and is discarded rather than
    /// claimed. Either way, opening an episode always clears this slot -- it
    /// is claimable by exactly the next episode to open, never a later one.
    /// See `assignCableLabelEvent(_:)` and
    /// `claimGraceCableLabelEventIfEligible(for:)`.
    private var graceCableLabelEvent: (name: String, wasAdded: Bool, arrivedAt: ClockType.Instant)?

    /// Opens a fresh device episode if none is currently settling
    /// (`settlingDeviceEpisodeID == nil`), and, if one opens, immediately
    /// gives it first claim on any pending `graceCableLabelEvent`. A batch
    /// being PARKED or HELD does not block a new episode from opening here
    /// -- see `parkedDeviceEpisodeID`/`heldDeviceBatchEpisodeID`'s doc
    /// comments -- only a still-settling one does. Idempotent: returns the
    /// existing episode id if one is already open, so calling this more than
    /// once for the same settle round is always safe.
    ///
    /// Called from THREE places: `scheduleDeviceDiff()` itself (P1-a fix,
    /// adversarial round 2 -- see `settlingDeviceEpisodeID`'s doc comment for
    /// why opening has to happen at the FIRST raw publish, not when the
    /// settle eventually fires), and, defensively, at the top of both
    /// `runNowOrDelayForRecentChargerPost` and `deferDeviceDiff` too, so a
    /// test driving either of those directly (bypassing `scheduleDeviceDiff`
    /// and its settle sleep entirely, as most of this file's tests do -- see
    /// their own doc comments) still opens an episode correctly.
    @discardableResult
    private func openDeviceEpisodeIfNeeded() -> UInt64 {
        if let existing = settlingDeviceEpisodeID { return existing }
        deviceEpisodeIDCounter += 1
        let episodeID = deviceEpisodeIDCounter
        settlingDeviceEpisodeID = episodeID
        claimGraceCableLabelEventIfEligible(for: episodeID)
        return episodeID
    }

    /// Claims `graceCableLabelEvent` for the just-opened `episodeID` if it
    /// is still within `deviceSettleWindow` of its own arrival; otherwise
    /// discards it. Either way the grace slot is cleared here: it is only
    /// ever offered to the FIRST episode to open after it arrived, never
    /// held open for a later one.
    private func claimGraceCableLabelEventIfEligible(for episodeID: UInt64) {
        guard let grace = graceCableLabelEvent else { return }
        graceCableLabelEvent = nil
        guard grace.arrivedAt.duration(to: clock.now) <= deviceSettleWindow else { return }
        pendingCableLabelEvent = (episodeID: episodeID, name: grace.name, wasAdded: grace.wasAdded)
    }

    /// Clears `pendingCableLabelEvent` only if it is STILL tagged to
    /// `episodeID` (consumed or not): the shared primitive behind every
    /// episode close (`closeParkedEpisode()`, `closeHeldEpisode()`, and the
    /// terminal branches in `diffDevices`/`resolveDevicePost`, which pass
    /// their own `episodeID` parameter straight through). A no-op when the
    /// event belongs to a different episode, or there is none.
    private func clearEventIfOwnedBy(_ episodeID: UInt64) {
        if let event = pendingCableLabelEvent, event.episodeID == episodeID {
            pendingCableLabelEvent = nil
        }
    }

    /// Closes whatever diff is CURRENTLY parked, if anything: clears
    /// `parkedDeviceEpisodeID` and any event still tagged to it. Called from
    /// two places, both discarding a parked diff rather than landing it: the
    /// top of `deferDeviceDiff`/`parkAndDelayDevicePost` (a NEWER diff
    /// overwriting the single park slot; the OLD parked diff's own devices
    /// are dropped the same way `deferredDeviceDiffDevices` always was, this
    /// just extends that discard to the episode identity too), and
    /// `supersedeAnyParkedDiff` (the P1-b fix target: the zero-delay
    /// `.runNow` branch discarding a parked diff in favour of running fresh
    /// data immediately). A no-op if nothing is parked.
    ///
    /// Defense-in-depth (verified during red-proofing, adversarial round 2):
    /// on the `supersedeAnyParkedDiff` path specifically, dropping this call
    /// ALONE does not reproduce the misattribution leak it fixes, because
    /// `settlingDeviceEpisodeID` is already freed at park time (see its own
    /// doc comment), so the superseding diff normally runs under a freshly-
    /// opened `episodeID` anyway, and the owner check in `resolveDevicePost`/
    /// `flushHeldDeviceBatch` independently blocks the mismatch. Reproducing
    /// the leak needs BOTH guards down at once (this clear skipped, AND the
    /// settling-gate freed at park time reverted, so the superseding diff
    /// reuses the parked diff's still-open id) -- confirmed by deliberately
    /// breaking both together and watching the exact bug reappear
    /// ("Connected: Device B (Cable A)" instead of unlabelled). This call
    /// stays as the explicit, unambiguous fix for the failure mode as
    /// originally described (a superseded parked diff's event surviving to
    /// label whatever replaces it), on top of the id-freshness guard, not
    /// instead of it.
    private func closeParkedEpisode() {
        guard let episodeID = parkedDeviceEpisodeID else { return }
        clearEventIfOwnedBy(episodeID)
        parkedDeviceEpisodeID = nil
    }

    /// Closes the episode owning the currently held batch, called from
    /// `flushHeldDeviceBatch` the moment that batch actually flushes
    /// (matched or unmatched): clears `heldDeviceBatchEpisodeID`, and, if
    /// `pendingCableLabelEvent` is STILL tagged to the episode being closed,
    /// clears that too (the matched case has already consumed it by this
    /// point, so this is only ever observable on the unmatched case). A
    /// no-op if nothing is held.
    private func closeHeldEpisode() {
        guard let episodeID = heldDeviceBatchEpisodeID else { return }
        clearEventIfOwnedBy(episodeID)
        heldDeviceBatchEpisodeID = nil
    }

    /// Assigns a freshly computed label change to whichever device episode
    /// owns it right now (spec design "2. Events carry an owner"), in
    /// priority order:
    ///  1. A settling episode (open, pre-resolve): assign to it. Preferred
    ///     over an older parked or held one, so a genuinely new physical
    ///     change is never swallowed by an unrelated batch still parked or
    ///     waiting out its cap.
    ///  2. No settling episode, but a diff is parked (charger-ordering
    ///     machinery, not yet landed): assign to that parked episode -- it
    ///     is exactly as "still pursuing its own outcome" as a settling one,
    ///     just further along the park/defer/gap/deadline pipeline.
    ///  3. No settling or parked episode, but a batch is held: assign to
    ///     that held episode -- the feature's core path (a label arriving
    ///     mid-hold).
    ///  4. No episode active at all: the bounded pre-episode
    ///     `graceCableLabelEvent` slot.
    /// A newer change always overwrites whatever was pending before,
    /// whichever of the four slots it lands in: single event, single owner,
    /// at a time.
    private func assignCableLabelEvent(_ change: (name: String, wasAdded: Bool)) {
        if let settlingID = settlingDeviceEpisodeID {
            graceCableLabelEvent = nil
            pendingCableLabelEvent = (episodeID: settlingID, name: change.name, wasAdded: change.wasAdded)
        } else if let parkedID = parkedDeviceEpisodeID {
            graceCableLabelEvent = nil
            pendingCableLabelEvent = (episodeID: parkedID, name: change.name, wasAdded: change.wasAdded)
        } else if let heldID = heldDeviceBatchEpisodeID {
            graceCableLabelEvent = nil
            pendingCableLabelEvent = (episodeID: heldID, name: change.name, wasAdded: change.wasAdded)
            tryFlushHeldDeviceBatchForPendingEvent()
        } else {
            graceCableLabelEvent = (name: change.name, wasAdded: change.wasAdded, arrivedAt: clock.now)
        }
    }

    /// Fixed, owner-locked cap on the notification hold (spec design 5):
    /// "Deadline semantics, cap 5 seconds (owner-locked)". Deliberately NOT
    /// a `var` init parameter like the other windows (`deviceSettleWindow`,
    /// `chargerSettleWindow`, `presentationGapWindow`): those are tunable
    /// debounce/presentation knobs; this one is a product-level ceiling the
    /// owner fixed explicitly. Tests drive `ManualClock.advance(by:)`
    /// straight to (and past) this value rather than shrinking it.
    public nonisolated static var cablePlausibilityHoldWindow: Duration { .seconds(5) }

    /// One settled .device batch waiting on the cable-plausibility hold
    /// (spec design 5/6). Held at BATCH granularity: one slot, one 5.0s
    /// timer, for every `NotificationContent` the settle would have
    /// produced, with the direction-match rule evaluated PER SIDE only at
    /// flush time (`removedEligible` / `addedEligible` below), never a
    /// separate timer per item.
    private struct HeldDeviceBatch {
        let removedGroups: [USBDeviceChangeGrouper.ChangeGroup]
        let addedGroups: [USBDeviceChangeGrouper.ChangeGroup]
        let thunderboltInvolved: Bool
        let singleDeviceBody: (UInt64) -> String?
        /// Whether the REMOVED side of this batch may EVER take a label:
        /// at least one removed group is a port-level tree change
        /// (`NotificationDecision.isPortLevelChange`). An in-tree removed
        /// group mixed into an otherwise-holding batch (the "mixed batch"
        /// case) never gets a label even though the batch as a whole waits.
        let removedEligible: Bool
        /// Same for the ADDED side.
        let addedEligible: Bool

        // fix2 (device-post queue reconciliation): the same diff ingredients
        // `DevicePostJob` carries, threaded through so a batch that flushes
        // into the queue (hold-cap expiry, or a superseding new diff) hands
        // its job everything a later queue merge needs. Values, not a
        // captured closure over live state: the whole point is that a
        // coalesced job's reconciliation reads what was TRUE at each
        // endpoint, not whatever `knownDevices` happens to say later.
        let previousSnapshots: [USBDeviceChangeGrouper.Snapshot]
        let currentSnapshots: [USBDeviceChangeGrouper.Snapshot]
        let previousTBSwitchIDs: Set<Int64>
        let currentTBSwitchIDs: Set<Int64>
        let bodyMap: [UInt64: String]
    }

    /// `nil` when nothing is held. `.some` from the moment `resolveDevicePost`
    /// decides to hold until `flushHeldDeviceBatch` clears it (labelled,
    /// unlabelled at cap, or flushed early by a superseding new diff).
    private var heldDeviceBatch: HeldDeviceBatch?
    /// Mirrors `deferredDeviceDiffToken`'s discipline, scoped to this stage:
    /// bumped every time a batch is newly held OR flushed, so a stale
    /// deadline task (captured token from an EARLIER hold) that fires after
    /// its batch was already flushed by something else sees a mismatched
    /// token and backs out instead of double-flushing or flushing the WRONG
    /// (newer) batch.
    private var heldDeviceBatchToken = 0
    /// The ABSOLUTE 5.0s backstop for the currently held batch, scheduled
    /// once at hold-start (`scheduleHeldDeviceBatchDeadline`), cancelled by
    /// any earlier flush (label match, or a superseding new diff's
    /// flush-first). Independent of `deferredDeviceDiffDeadlineTask` in
    /// every respect (own property, own timer, own token): this stage sits
    /// strictly AFTER the park/defer/deadline machinery resolves and does
    /// not splice into it (spec design 6).
    private var heldDeviceBatchDeadlineTask: Task<Void, Never>?

    var didPrimeBaseline = false

    private var chargerSettleTask: Task<Void, Never>?
    /// True from the moment a charger settle task is scheduled until the
    /// moment it actually runs `reconcileChargers` (or is superseded). A
    /// non-nil `chargerSettleTask` isn't enough on its own to mean "still
    /// pending": the task reference is never cleared after it fires, so a
    /// long-finished task would look identical to one still waiting out its
    /// window. It gates a DEFERRAL of the device post, never an early run of
    /// the charger reconcile itself (see `deferDeviceDiff`'s doc comment for
    /// why an early flush was rejected on review). `private(set)`, not
    /// `private`: a sequencer test drives the sequencer end to end and needs
    /// to read it.
    ///
    /// NOT what `scheduleDeviceDiff` routes on any more: it feeds
    /// `isChargerEventInFlight` into `deviceDiffDisposition`, and this is one
    /// of the two things that answers to. See that property (F1 review fix).
    private(set) var isChargerSettlePending = false

    /// Whether a charger banner is still OWED for an event already underway.
    /// This, not `isChargerSettlePending` alone, is what a settling device
    /// diff routes on (`deviceDiffDisposition`).
    ///
    /// F1 review fix, a MEASURED ordering regression. `isChargerSettlePending`
    /// used to be the whole answer, because the settle task cleared it and
    /// then called `reconcileChargers()`, which posted synchronously in the
    /// same turn: there was never an observable moment where the flag read
    /// false and a charger banner was still coming. The cable-name grace
    /// creates exactly that moment and holds it open for up to
    /// `chargerCableLabelGraceWindow`. A device settle landing inside it took
    /// `.runNow`, found `lastChargerPostTime` untouched (the first pass posted
    /// nothing, so there was no recent charger post to space against either),
    /// and posted the device banner AHEAD of the charger banner. That is the
    /// inversion the whole park/defer/gap machinery exists to prevent, and the
    /// base commit does not have it.
    ///
    /// Deferring instead is not a new code path: the diff parks exactly as it
    /// would for a pending settle, and `reconcileChargers`'s own `defer`
    /// lands it on the second pass, after the charger post, through the
    /// normal presentation gap. The parked diff's absolute deadline already
    /// covers the grace (see `deferredDeviceDiffDeadlineWindow`), so it
    /// cannot expire mid-grace and land early either.
    ///
    /// Any future third way of owing a charger post belongs here, not at the
    /// call site.
    var isChargerEventInFlight: Bool {
        isChargerSettlePending || chargerCableLabelGraceTask != nil
    }

    /// State for a device diff that is waiting on a same-episode charger
    /// reconcile to post first (see `deviceDiffDisposition`). Only one diff
    /// can be deferred at a time: a device settle firing again while one is
    /// already waiting means a fresh device episode is starting, so the
    /// waiting one is superseded, same as `deviceSettleTask` itself.
    private var deferredDeviceDiffDevices: [USBDevice]?
    /// The downstream TB switch-ID set captured ALONGSIDE `deferredDeviceDiffDevices`,
    /// at the same settle-time moment, not re-read when the diff eventually
    /// lands. Landing can be delayed up to `deferredDeviceDiffDeadlineWindow`
    /// (5s in production) after settle time; sampling
    /// `currentDownstreamTBSwitchIDs()` at landing instead of settle would
    /// let an UNRELATED TB switch change during that window mislabel a
    /// batch of plain USB devices as Thunderbolt (or the reverse: a real
    /// TB event settling with the batch, then reverting before landing,
    /// would wrongly read as "no Thunderbolt involved"). Set together with
    /// `deferredDeviceDiffDevices` at every park site (`deferDeviceDiff`,
    /// `parkAndDelayDevicePost`), cleared together at every consuming site
    /// (`landDeferredDeviceDiffNow`, `supersedeAnyParkedDiff`).
    private var deferredDeviceDiffTBSwitchIDs: Set<Int64>?
    /// The ABSOLUTE, NON-RESETTING backstop for a parked diff. Started ONCE,
    /// at park time (`scheduleAbsoluteDeadline`, called from `deferDeviceDiff`
    /// and `parkAndDelayDevicePost`), and never touched again except by an
    /// actual landing or a NEWER parked diff superseding this one. See
    /// `deferredDeviceDiffDeadlineWindow`'s doc comment for why this has to
    /// be non-resetting.
    private var deferredDeviceDiffDeadlineTask: Task<Void, Never>?
    /// ONE task, scheduled at park time, that nothing resets. Gap
    /// re-schedules never touch it (`scheduleGapLanding` doesn't reference
    /// it at all); only an actual landing, a fresh `deferDeviceDiff` /
    /// `parkAndDelayDevicePost` call (a NEWER parked diff superseding this
    /// one, which cancels this deadline and starts its own), or
    /// `supersedeAnyParkedDiff` (the zero-delay `.runNow` path cancelling
    /// this one outright, with no replacement parked) can stop it.
    /// Worst case, a device banner waits `deferredDeviceDiffPresentationGapWindow`
    /// + `chargerSettleWindow` + `chargerCableLabelGraceWindow` from the
    /// moment it was parked: one full charger debounce (in case the charger
    /// hadn't even reconciled yet when the diff was parked), plus one full
    /// cable-name grace (issue #593: the charger reconcile can return without
    /// posting anything at all, waiting on a saved cable name, and only post
    /// on its SECOND pass one grace window later), plus one full presentation
    /// gap (in case the charger reconciles right at the last moment and needs
    /// the full gap to present). Derived from those windows at `init()` time
    /// (5s at their defaults), not a fresh literal, so it moves automatically
    /// if any of them changes. `var`, like the other windows, so a test can
    /// shrink it.
    ///
    /// The grace term is load-bearing, not padding: without it a diff parked
    /// at the start of a graced charger event hits this deadline DURING the
    /// grace and lands the device banner first, which is precisely the
    /// inversion the parking machinery exists to prevent.
    ///
    /// Starvation fix (both reviewers, on an earlier design this replaces):
    /// that design cancelled the parked diff's backstop the moment a
    /// presentation gap took over landing, on the theory that the gap is
    /// then the sole scheduled lander. That left the gap phase with NO upper
    /// bound: every charger post while a diff sat parked re-scheduled a
    /// fresh `deferredDeviceDiffPresentationGapWindow`-long gap
    /// (`scheduleGapLanding`), and sustained PD flapping (real; see
    /// `chargerSettleWindow`'s own doc comment) could delay the device
    /// banner indefinitely.
    var deferredDeviceDiffDeadlineWindow: Duration
    /// Re-scheduled on every `scheduleGapLanding` call (unlike
    /// `deferredDeviceDiffDeadlineTask`, which is scheduled once at park
    /// time and never re-scheduled); both are cancelled on an actual
    /// landing, see `landDeferredDeviceDiffNow`.
    ///
    /// Presentation-gap fix (owner, live verification): when a parked device
    /// diff landed synchronously inside `reconcileChargers`'s `defer`, the
    /// charger post and the device post both reached
    /// `UNUserNotificationCenter` in the same millisecond. macOS presents
    /// only the LAST of two simultaneous banners, so "Charger disconnected"
    /// never showed on screen (it only reached Notification Centre's list):
    /// the fix that made ordering correct accidentally made the older of the
    /// two invisible. The old code's accidental ~300ms gap between the two
    /// posts is what used to let both banners present, so a deliberate delay
    /// restores that presentation gap on purpose.
    private var deferredDeviceDiffPresentationGapTask: Task<Void, Never>?
    /// True from the moment `landDeferredDeviceDiff` schedules a presentation
    /// gap until that gap actually lands the diff (or is cancelled by a
    /// fresh deferral). Guards a specific interleaving Codex review raised:
    /// a SECOND `reconcileChargers` call that lands while the gap from a
    /// FIRST is still pending, and posts no charger content of its own,
    /// would otherwise take the `.immediate` branch below and land the diff
    /// right there, defeating the gap the first call scheduled. This guard
    /// is load-bearing, not precautionary: at the current 2s gap (see
    /// `deferredDeviceDiffPresentationGapWindow`'s doc comment), 2s
    /// comfortably EXCEEDS the 1.5s charger debounce, so a second charger
    /// settle completing while the first's gap is still pending is a real
    /// production interleaving, not just a timing coincidence.
    ///
    /// Originally reasoned unreachable live at the 500ms gap
    /// (`reconcileChargers` is trailing-debounced to `chargerSettleWindow`,
    /// 1.5s, comfortably longer than a 500ms gap, so two reconciles for the
    /// same charger couldn't land inside one gap window) and kept only as
    /// belt-and-braces. That reasoning stopped holding once the gap was
    /// raised to 2s.
    private var isPresentationGapPending = false
    /// Identity for the CURRENT gap task, bumped every time
    /// `landDeferredDeviceDiff`'s `.afterPresentationGap` case schedules one.
    /// A second Codex finding on the guard above: scheduling a new gap task
    /// used to just overwrite `deferredDeviceDiffPresentationGapTask` without
    /// cancelling the outgoing one, so a stale task could wake later, run its
    /// body (its `Task.isCancelled` check never tripped, because nothing
    /// cancelled it), and unconditionally clear `isPresentationGapPending` --
    /// even though a NEWER gap for the same diff was still legitimately
    /// pending. That wrong clear is exactly what would let a subsequent
    /// `.immediate` reconcile land the diff early. Two independent guards
    /// close this, both required per review ("neither a cancelled nor a
    /// superseded task can mutate shared state"):
    ///  1. `landDeferredDeviceDiff` now explicitly cancels any existing gap
    ///     task before scheduling a new one, so `Task.isCancelled` trips for
    ///     the outgoing task.
    ///  2. Every gap task also captures its own generation here and checks it
    ///     against the live value before touching ANYTHING (not just before
    ///     landing, before even clearing the flag). This is the one that
    ///     actually matters: it makes "a stale task can't mutate shared
    ///     state" true by construction, not by relying on `.cancel()` having
    ///     been observed in time. In this codebase's single `@MainActor`
    ///     scheduling, `.cancel()` alone would already be sufficient (it
    ///     completes synchronously before any queued continuation resumes),
    ///     so this is deliberate belt-and-braces on top of belt-and-braces:
    ///     it holds even if this code is ever restructured off the actor.
    private var deferredDeviceDiffPresentationGapGeneration = 0
    /// How long `landDeferredDeviceDiff(token:afterChargerPost:)` waits
    /// before landing a diff that reconciled alongside real charger content.
    /// `var`, mirroring `deferredDeviceDiffDeadlineWindow`, so a test can
    /// shrink it to a few tens of milliseconds. Production stays at 2s:
    /// 500ms was tried first and measured insufficient on macOS 26 in live
    /// testing (owner, scratch build) -- the device banner still visually
    /// covered the charger banner before it had time to present. 2s is the
    /// live-verified value, and it also matches the plug-in direction's own
    /// natural spacing between the two settle timers, so it doesn't read as
    /// an artificially long pause.
    var deferredDeviceDiffPresentationGapWindow: Duration
    /// Recorded here, in `postNotification`, whenever a CHARGER post
    /// actually goes out, so the `.runNow` path (see
    /// `runNowOrDelayForRecentChargerPost`) can tell "a charger post just
    /// went out and hasn't had time to present yet" from "nothing charger-
    /// related happened recently". `nil` until the first charger post of the
    /// app's lifetime; `devicePostDelay` treats `nil` the same as "outside
    /// the window" (nothing to delay for).
    /// Not `private`: a sequencer test resets this to `nil` before
    /// exercising `runNowOrDelayForRecentChargerPost`, mirroring the
    /// original wiring test's reasoning about a process-wide singleton
    /// leaking state between tests.
    ///
    /// Both-orders fix (owner, live verification): the gap fix above only
    /// covers the DEVICE-fires-first order (device settle finds
    /// `isChargerSettlePending` true, defers, and the charger reconcile lands
    /// it later). Logs showed the opposite order happens too: the CHARGER
    /// settle fires first and posts, and by the time the device settle fires
    /// a moment later, `isChargerSettlePending` already reads false, so
    /// `deviceDiffDisposition` says `.runNow` and the device post goes out
    /// ~1ms after the charger post, same-millisecond problem again, charger
    /// banner suppressed. This property is the fix that closes that gap.
    var lastChargerPostTime: ClockType.Instant?
    /// Guards against the deferred diff landing twice. Incremented both when
    /// a new diff is deferred (invalidating any earlier one still in
    /// flight) and by whichever landing path actually runs the diff
    /// (`landDeferredDeviceDiffNow`, reached either straight from
    /// `reconcileChargers` when it posted nothing, or after the timeout
    /// above, or after the presentation gap above). All three paths hop
    /// through the `@MainActor`, so two can never truly run at the same
    /// instant; the token exists so whichever arrives SECOND sees a value
    /// that no longer matches what it captured and backs out instead of
    /// running the diff again. `shouldLandDeferredDiff` is the pure
    /// comparison this reads. See `landDeferredDeviceDiff(token:afterChargerPost:)`'s
    /// doc comment for the full three-path interleaving walk-through.
    private var deferredDeviceDiffToken = 0
    /// A charger's power-source services can briefly disappear and reappear
    /// during PD renegotiation / re-enumeration, so the published list flaps
    /// (present -> absent -> present). Comparing each publish in isolation
    /// fires a "connected" notification per flap. Instead we wait for the set
    /// to stop changing, then reconcile once. The window must exceed the gap
    /// between consecutive publishes during a connect. Those publishes are
    /// driven by the power-source IOKit notifications (match/terminated), not
    /// by WatcherHub's steady poll, so the flap happens at IOKit speed
    /// regardless of the poll cadence; the gap is sub-second. 1.5s clears it
    /// with margin. See issue #227 follow-up.
    ///
    /// Deliberately `private let`, not `var` like the other windows above:
    /// a sequencer test drives around this window's real 1.5s length
    /// (waiting it out, or triggering `reconcileChargers()` directly instead
    /// of going through `diffSources`'s debounce) rather than needing to
    /// shrink it after construction. Still an init parameter (see `init`'s
    /// doc comment), unlike the original's hardcoded literal: a test that
    /// genuinely needs a different value constructs its own sequencer with
    /// it, rather than mutating a shared one.
    private let chargerSettleWindow: Duration

    /// The three window defaults, named once so the `init` parameter
    /// defaults and every `?? ...` fallback read inside a task body (used
    /// only if `self` has already been deallocated when the task's weak
    /// `clock`/window read happens) reference the SAME literal instead of
    /// two independently hand-copied ones drifting apart. Codex review:
    /// `deferredDeviceDiffDeadlineWindow`'s fallback was a hand-copied
    /// `.milliseconds(3500)` that happened to equal
    /// `defaultPresentationGapWindow + defaultChargerSettleWindow` today,
    /// but nothing enforced that if either default ever changed.
    // `static var` with a computed body, not `static let`: `DeviceDiffSequencer`
    // is generic, and Swift doesn't support static STORED properties on a
    // generic type (there's no single shared storage slot across every
    // `ClockType` instantiation). A computed property has no storage, so
    // it's allowed, and for a constant literal it costs nothing extra.
    //
    // `nonisolated`: `init`'s parameter DEFAULT VALUES are evaluated in a
    // nonisolated context even though `init` itself (and this whole class)
    // is `@MainActor`, so a plain main-actor-isolated property here
    // couldn't be read from those defaults. `Duration` is `Sendable`, so
    // nonisolated access to an immutable value is sound regardless.
    //
    // `public`, not `private`: a public `init`'s default argument
    // expressions must be at least as accessible as the `init` itself, so
    // these can't stay `private` while still being usable there. They're
    // otherwise unremarkable `Duration` values, harmless to expose.
    public nonisolated static var defaultDeviceSettleWindow: Duration { .milliseconds(1500) }
    public nonisolated static var defaultChargerSettleWindow: Duration { .milliseconds(1500) }
    public nonisolated static var defaultPresentationGapWindow: Duration { .milliseconds(2000) }

    /// How long a charger connect may wait for a saved cable name that has not
    /// resolved yet. One charger settle window, so a settled charger event
    /// waits at most `chargerSettleWindow` + this, 3s. Deliberately far below
    /// the device path's 5s `cablePlausibilityHoldWindow`: a charger banner is
    /// the only notification a MagSafe plug produces, so a long silence reads
    /// as the app having missed the event entirely, where a device plug has
    /// other evidence on screen.
    ///
    /// That 3s is per SETTLED EVENT, not per physical plug, and the
    /// difference is worth stating because an earlier version of this comment
    /// claimed the stronger thing (F7 review finding). `diffSources` resets
    /// the one-grace budget on every power publish, because that is where a
    /// genuinely new charger event starts and the debounce cannot tell a new
    /// event from a flap of the current one. So a source-set change during
    /// the grace buys a fresh settle AND a fresh grace. MEASURED: one flap at
    /// t=1600ms moves the banner from t=3000ms to t=4600ms
    /// (`ChargerCableLabelGraceTests.testAPowerFlapDuringTheGraceWidensTheWait`).
    ///
    /// Not bounded, deliberately. The settle window has always been unbounded
    /// under sustained flapping (`chargerSettleTask?.cancel()` on every
    /// publish, which is the whole point of a trailing debounce), so this
    /// amplifies an accepted property rather than introducing a new stall,
    /// and every round still terminates in a post. Capping the budget instead
    /// would deny a grace to a real unplug-then-replug, which is the case the
    /// reset exists to serve.
    ///
    /// Why a grace is needed at all (issue #593): a USB-C cable's e-marker can
    /// resolve a second or two after the port reports connected, which is
    /// later than the 1.5s charger settle, so the connect banner can post
    /// before the name exists. MagSafe is EXPECTED to be immediate (its IDs
    /// come from `StateCC` with no Discover Identity round trip), but that is
    /// inferred, not measured, so this grace covers both.
    ///
    /// Not an `init` parameter, unlike the settle/gap windows: it is a fixed
    /// property of the feature (mirroring `cablePlausibilityHoldWindow`, which
    /// is also a bare static), and the deadline arithmetic below reads the
    /// static directly rather than a per-instance value, so making it
    /// injectable would need a second parameter threading through `init` for
    /// no behaviour a test can't already reach by shrinking
    /// `deferredDeviceDiffDeadlineWindow`.
    public nonisolated static var chargerCableLabelGraceWindow: Duration { .milliseconds(1500) }

    /// `presentationGap + chargerSettle + chargerCableLabelGrace`: the grace
    /// term is there because a parked device diff can be waiting while a
    /// charger event sits out its cable-name grace, and that grace happens
    /// entirely BEFORE the charger reconcile completes and posts. Without it
    /// the parked diff's deadline could expire mid-grace and land the device
    /// banner ahead of the charger banner, inverting the ordering this whole
    /// file exists to protect. See `deferredDeviceDiffDeadlineWindow`.
    public nonisolated static var defaultDeadlineWindow: Duration {
        defaultPresentationGapWindow + defaultChargerSettleWindow + chargerCableLabelGraceWindow
    }

    private var deviceSettleTask: Task<Void, Never>?
    /// A hub's own termination and its children's terminations don't arrive
    /// from IOKit as one atomic batch: unplugging a hub can surface the
    /// child's "gone" callback and the hub's "gone" callback in separate
    /// fires, sometimes with the hub arriving late, sometimes the other way
    /// round. Diffing every publish in isolation reports whatever happened to
    /// have settled by that point, so which device names show up in the
    /// notification varies. Mirrors `chargerSettleWindow`: wait for the
    /// published device list to stop changing, then diff once, so a hub
    /// teardown (or a hub-and-children connect) lands inside a single diff
    /// instead of being split across several. See issue #551.
    /// `var`, not `let` (like `deferredDeviceDiffDeadlineWindow` and
    /// `deferredDeviceDiffPresentationGapWindow`), purely so a test can
    /// shrink it and exercise `scheduleDeviceDiff` itself, the actual
    /// production call site, rather than only the helpers it calls
    /// (`runNowOrDelayForRecentChargerPost` etc.) driven directly.
    var deviceSettleWindow: Duration

    /// - Parameters:
    ///   - clock: The time source every settle/gap/deadline task sleeps
    ///     against. Generic (rather than a fixed `ContinuousClock`) so tests
    ///     can supply a fake clock and drive the whole mechanism without any
    ///     real sleeps. Production constructs this with `ContinuousClock()`.
    ///   - currentDevices / currentChargerSources: read fresh at the moment
    ///     each settle task actually needs them, never a value captured when
    ///     the underlying publisher fired.
    ///   - currentPorts / currentAdapter: same discipline, read fresh inside
    ///     `chargerLabels` so the wattage resolution sees the port and adapter
    ///     state the charger set was read against. Default to empty/nil so a
    ///     test that only cares about ordering can leave them out.
    ///   - notifyOnChanges: read AFTER baseline bookkeeping in `diffDevices`
    ///     / `reconcileChargers`, matching where the original read
    ///     `AppSettings.shared.notifyOnChanges`.
    ///   - post: where a decided notification is handed off; the caller
    ///     builds and submits the real `UNNotificationRequest`.
    ///   - log: called with plain message text at the same two points the
    ///     original `os.log` calls fired (`diffDevices`, `reconcileChargers`);
    ///     defaults to a no-op so tests that don't care about logging don't
    ///     have to supply one.
    ///   - deviceSettleWindow / chargerSettleWindow / presentationGapWindow:
    ///     every window moved to an init parameter with the same default the
    ///     original hardcoded, so a test can pick a small window at
    ///     construction time instead of mutating a shared instance; each one
    ///     stays independently mutable (or not) afterward exactly as before
    ///     (`chargerSettleWindow` stays `private let`, the other two stay
    ///     `var`). `deferredDeviceDiffDeadlineWindow` is never a parameter:
    ///     it's always derived from the other two, exactly as the original
    ///     `init()` computed it, so it can't drift out of sync with a custom
    ///     `presentationGapWindow` / `chargerSettleWindow` pair.
    ///   - launchToken: a short string unique to this app launch, passed
    ///     straight through to `NotificationDeliveryLedger` (see its own
    ///     doc comment). No default, deliberately: `DeviceDiffSequencer`
    ///     itself never calls `UUID()` or `Date()` (this module has no
    ///     platform imports), so the app-side shim must generate this and
    ///     hand it in; a default here would either have to violate that
    ///     purity rule or silently pick a non-unique constant. Tests pass a
    ///     fixed string so directives stay deterministic.
    public init(
        clock: ClockType,
        currentDevices: @escaping () -> [USBDevice],
        currentChargerSources: @escaping () -> [PowerSource],
        currentDownstreamTBSwitchIDs: @escaping () -> Set<Int64> = { [] },
        currentPorts: @escaping () -> [AppleHPMInterface] = { [] },
        currentAdapter: @escaping () -> AdapterInfo? = { nil },
        notifyOnChanges: @escaping () -> Bool,
        post: @escaping (NotificationCategory, NotificationContent, NotificationDecision.DeliveryDirective) -> Void,
        log: @escaping (String) -> Void = { _ in },
        deviceSettleWindow: Duration = defaultDeviceSettleWindow,
        chargerSettleWindow: Duration = defaultChargerSettleWindow,
        presentationGapWindow: Duration = defaultPresentationGapWindow,
        launchToken: String
    ) {
        self.clock = clock
        self.currentDevices = currentDevices
        self.currentChargerSources = currentChargerSources
        self.currentDownstreamTBSwitchIDs = currentDownstreamTBSwitchIDs
        self.currentPorts = currentPorts
        self.currentAdapter = currentAdapter
        self.notifyOnChanges = notifyOnChanges
        self.post = post
        self.log = log
        self.deviceSettleWindow = deviceSettleWindow
        self.chargerSettleWindow = chargerSettleWindow
        self.deferredDeviceDiffPresentationGapWindow = presentationGapWindow
        self.deliveryLedger = NotificationDeliveryLedger(launchToken: launchToken)
        // Derived, not a fresh literal: see `deferredDeviceDiffDeadlineWindow`'s
        // doc comment for why the deadline is presentationGap + chargerSettleWindow
        // + chargerCableLabelGraceWindow. Computed once here rather than as a
        // property-declaration default so it tracks whatever the injected
        // windows' OWN values are, instead of a hand-copied literal going stale
        // if any of them changes. Still a plain `var` afterward: a test can
        // overwrite it directly, same as it always could.
        //
        // The grace term is the static, not an injected value: it isn't an
        // `init` parameter (see `chargerCableLabelGraceWindow`'s doc comment),
        // and `reconcileChargers` arms the real grace off that same static, so
        // reading it here keeps the deadline and the thing it has to outlast
        // derived from one source rather than two.
        self.deferredDeviceDiffDeadlineWindow =
            presentationGapWindow + chargerSettleWindow + Self.chargerCableLabelGraceWindow
    }

    /// Sets the baseline device/charger state without diffing against it, so
    /// the app doesn't fire a flurry of "connected" notifications for things
    /// already plugged in at launch. The app-side shim calls this once,
    /// synchronously, during its own `start()`, before subscribing to any of
    /// the watcher publishers, relying on `WatcherHub.start()` having already
    /// performed its own initial refresh (issue #568) so the values read here
    /// already reflect current reality, synthesised charger sources included.
    public func primeBaseline(devices: [USBDevice], chargerSources: [PowerSource]) {
        let baselineSnapshots = devices.map(snapshot(for:))
        knownDevices = Dictionary(
            baselineSnapshots.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Primed through `chargerLabels` itself, the same call
        // `reconcileChargers` makes, so the baseline and the diff use the same
        // key space (else every connected charger would fire a spurious
        // "connected" on the first poll).
        knownChargerLabels = chargerLabels(for: chargerSources)
        // Issue #593: same priming for the cable-name side, so a cable
        // already attached at launch isn't treated as newly arrived by the
        // first `reconcileChargers()` call. `knownLabelledCablesByPort` can
        // legitimately still be nil here (the app-side shim's first
        // `updateLabelledCables(_:)` call can land before or after this
        // method, see that property's doc comment); when it is, this seeds
        // nothing and `updateLabelledCables(_:)`'s own refresh -- gated on
        // the port already being in `knownChargerLabels`, which it now is
        // -- backfills the name once the feed does arrive.
        let primedCableNames = knownLabelledCablesByPort ?? [:]
        knownChargerCableLabels = Dictionary(uniqueKeysWithValues: knownChargerLabels.keys.compactMap { portKey in
            primedCableNames[portKey].map { (portKey, $0) }
        })
        knownTBSwitchIDs = currentDownstreamTBSwitchIDs()
        didPrimeBaseline = true
    }

    /// Trailing-edge debounce mirroring `diffSources`/`reconcileChargers`:
    /// keep resetting the timer while the device list is still changing,
    /// then diff once it settles. This is what coalesces a hub's split-fire
    /// termination (child gone, then hub gone in a later publish) into one
    /// diff. See `deviceSettleWindow` and issue #551.
    ///
    /// Not `private`: a sequencer test calls this directly (with
    /// `deviceSettleWindow` shrunk) to drive the ACTUAL `.runNow` call site
    /// end to end, rather than only `runNowOrDelayForRecentChargerPost`
    /// itself. Codex review: a test that only drives the helper directly
    /// would stay green even if this call site regressed back to a bare
    /// `diffDevices(devices)` call, which is exactly the bug this exists to
    /// catch.
    public func scheduleDeviceDiff() {
        // P1-a fix (adversarial round 2): open (or confirm) the episode
        // HERE, synchronously, on every raw publish -- not only once the
        // settle task below actually fires. See `settlingDeviceEpisodeID`'s
        // doc comment for the burst-debounce scenario this closes.
        openDeviceEpisodeIfNeeded()
        deviceSettleTask?.cancel()
        deviceSettleTask = Task { @MainActor [weak self] in
            guard let clock = self?.clock else { return }
            try? await clock.sleep(for: self?.deviceSettleWindow ?? Self.defaultDeviceSettleWindow)
            guard !Task.isCancelled, let self else { return }
            let devices = self.currentDevices()
            switch NotificationDecision.deviceDiffDisposition(chargerEventInFlight: self.isChargerEventInFlight) {
            case .runNow:
                // Both-orders fix: `isChargerSettlePending` being false here
                // only means no charger settle is CURRENTLY pending; it says
                // nothing about whether one just landed and posted a moment
                // ago. `runNowOrDelayForRecentChargerPost` is what actually
                // decides immediate vs delayed for this case.
                self.runNowOrDelayForRecentChargerPost(devices)
            case .deferUntilChargerReconcile:
                self.deferDeviceDiff(devices)
            }
        }
    }

    /// Park a settled device diff until the pending charger reconcile lands
    /// it (see `reconcileChargers`'s `defer`) or `deferredDeviceDiffDeadlineTask`
    /// bounds the wait. Superseding an earlier still-waiting diff (rather
    /// than composing with it) mirrors `deviceSettleTask`/`chargerSettleTask`:
    /// only the latest settled state matters. Cancelling BOTH the deadline
    /// task and the presentation-gap task here (not just the deadline) is
    /// what keeps a superseded episode's stale gap wait from doing anything
    /// once it eventually fires: see the interleaving walk-through on
    /// `landDeferredDeviceDiff(token:afterChargerPost:)`.
    ///
    /// Not `private`: a sequencer test calls this directly to park a diff
    /// without going through `scheduleDeviceDiff`'s own settle sleep and a
    /// live device read, so it can drive the actual landing plumbing (this
    /// function plus `reconcileChargers`'s `defer`) rather than only the
    /// pure rules that decide it.
    ///
    /// Accepted trade-off: a charger event that is UNRELATED to the parked
    /// device diff (arrives, and its own settle task overlaps the window)
    /// can delay that device notification by up to the full deadline window
    /// (`deferredDeviceDiffDeadlineWindow`, 5s in production), because
    /// `isChargerSettlePending` can't distinguish "the same physical episode"
    /// from "an unrelated charger event that happens to overlap". That delay
    /// is bounded by the deadline below and never drops the notification, so
    /// it's accepted for the sake of getting the ordering right on the
    /// common case (the same episode) this fix targets.
    func deferDeviceDiff(_ devices: [USBDevice]) {
        let episodeID = openDeviceEpisodeIfNeeded()
        // This round is handing off to the park machinery now, not still
        // settling (P1-b fix): free the gate so a fresh raw publish arriving
        // while this diff is parked opens a genuinely NEW episode instead of
        // reusing this one's id. `parkedDeviceEpisodeID` is this diff's own
        // identity from here on.
        settlingDeviceEpisodeID = nil
        // Close whatever was PREVIOUSLY parked (P1-b fix): this overwrites
        // the single park slot below exactly like `deferredDeviceDiffDevices`
        // always did, so the episode identity has to be discarded the same
        // way, not silently handed to this new diff.
        closeParkedEpisode()
        parkedDeviceEpisodeID = episodeID
        deferredDeviceDiffToken += 1
        let token = deferredDeviceDiffToken
        deferredDeviceDiffDevices = devices
        // Sampled here, at park time (this function runs synchronously
        // right after `scheduleDeviceDiff` reads `currentDevices()`), not
        // when the diff eventually lands. See `deferredDeviceDiffTBSwitchIDs`'s
        // doc comment for why landing-time sampling is wrong.
        deferredDeviceDiffTBSwitchIDs = currentDownstreamTBSwitchIDs()

        deferredDeviceDiffPresentationGapTask?.cancel()
        deferredDeviceDiffPresentationGapGeneration += 1
        isPresentationGapPending = false
        scheduleAbsoluteDeadline(token: token)
    }

    /// Schedules the ABSOLUTE, NON-RESETTING deadline for the CURRENTLY
    /// parked diff (`token`). Called ONCE, at park time, by both parking
    /// entry points (`deferDeviceDiff` and `parkAndDelayDevicePost`).
    /// Nothing after this point re-schedules it: not a gap re-schedule (an
    /// unrelated or repeated charger reconcile scheduling a fresh
    /// presentation gap via `scheduleGapLanding`), only an actual landing
    /// (which cancels it, see `landDeferredDeviceDiffNow`) or a NEWER parked
    /// diff superseding this one (which cancels this deadline here, via the
    /// `?.cancel()` below, before scheduling its own). See
    /// `deferredDeviceDiffDeadlineWindow`'s doc comment for the starvation
    /// bug this design fixes and the reasoning behind the duration.
    private func scheduleAbsoluteDeadline(token: Int) {
        deferredDeviceDiffDeadlineTask?.cancel()
        deferredDeviceDiffDeadlineTask = Task { @MainActor [weak self] in
            guard let clock = self?.clock else { return }
            try? await clock.sleep(for: self?.deferredDeviceDiffDeadlineWindow ?? Self.defaultDeadlineWindow)
            guard !Task.isCancelled, let self else { return }
            self.landDeferredDeviceDiffNow(token: token)
        }
    }

    /// Entry point for the reconcile-completion landing path (called from
    /// `reconcileChargers`'s `defer`). Decides gap vs immediate via
    /// `deferredDiffLanding`, then either lands right away or schedules the
    /// gap. A no-op when nothing is deferred, so `reconcileChargers` can call
    /// this unconditionally on every exit without checking whether a diff was
    /// actually waiting.
    ///
    /// Interleavings this has to survive, all of them exercised by walking
    /// through what each landing path does to `deferredDeviceDiffToken` /
    /// `deferredDeviceDiffDevices`:
    ///
    /// 1. **Gap completes normally.** `landDeferredDeviceDiffNow` runs after
    ///    the sleep, token still matches (nothing superseded it), lands, and
    ///    cancels the (now finished) deadline task. One landing.
    /// 2. **The absolute deadline fires while a gap is ALSO pending** (the
    ///    deadline's `deferredDeviceDiffPresentationGapWindow` +
    ///    `chargerSettleWindow` window elapsed before the currently-pending
    ///    gap's own, shorter window did -- possible when a charger reconcile
    ///    took a while to arrive after park time, or when the gap has been
    ///    re-scheduled enough times by repeated reconciles that its own
    ///    countdown, restarted from the LATEST reconcile, is still running
    ///    past the deadline's absolute cutoff). The deadline task calls
    ///    `landDeferredDeviceDiffNow` directly with its own captured token,
    ///    which still matches (nothing has landed yet): it lands, increments
    ///    the token, and cancels the still-pending gap task. When the gap
    ///    task's sleep later completes, its `Task.isCancelled` check is true
    ///    and it never reaches `landDeferredDeviceDiffNow` at all; even if it
    ///    somehow did, `shouldLandDeferredDiff` would see the now-stale token
    ///    and back out. One landing either way. This is the mechanism that
    ///    bounds the WORST case: an earlier design cancelled this deadline
    ///    the moment a gap took over, which meant sustained charger flapping
    ///    (real; see `chargerSettleWindow`'s own doc comment) could re-extend
    ///    the gap indefinitely and starve the device banner. `scheduleGapLanding`
    ///    now never touches the deadline task at all, in either direction:
    ///    not to cancel it, not to re-schedule it. See
    ///    `deferredDeviceDiffDeadlineWindow`'s doc comment for the full
    ///    starvation-fix reasoning.
    /// 3. **A new device diff is deferred during the gap** (a fresh device
    ///    settle episode starts before the gap finishes). `deferDeviceDiff`
    ///    increments the token and cancels both the old deadline task AND
    ///    this old gap task (via `scheduleAbsoluteDeadline`'s own
    ///    cancel-before-schedule and this function's cancel-before-schedule
    ///    respectively). The old gap task never lands the superseded diff;
    ///    the NEW diff gets its own deadline/gap treatment from here on.
    ///    Nothing is orphaned: the new diff is exactly as pending as if it
    ///    had arrived with no gap in flight at all.
    /// 4. **A second `reconcileChargers` call lands while a gap from the
    ///    first is still pending** (two charger settles close together,
    ///    unusual but not impossible). Since nothing was deferred a second
    ///    time in between, `deferredDeviceDiffDevices` still holds the SAME
    ///    devices and the token is unchanged, so this call schedules a
    ///    SECOND gap task. Two more Codex findings live here (see property 5
    ///    below and `deferredDeviceDiffPresentationGapGeneration`'s doc
    ///    comment): the first gap task IS now explicitly cancelled before the
    ///    second is scheduled, and each gap task carries its own generation,
    ///    checked before it does ANYTHING (not just before landing). So the
    ///    first task never reaches its body at all (`Task.isCancelled`), and
    ///    even if it somehow did, the generation check would still stop it.
    ///    Only the second (newest) gap task can ever land this diff. Still
    ///    exactly one landing, and now the NEWER gap deterministically wins,
    ///    not "whichever fires first".
    /// 5. **A second `reconcileChargers` call posts NOTHING while a gap from
    ///    a FIRST (which posted real content) is still pending** (Codex
    ///    review). This call's own `afterChargerPost` is false, so on its
    ///    own `deferredDiffLanding` would say `.immediate` -- but running
    ///    that immediately would land the diff right next to THIS call's
    ///    return, defeating the gap the first call is still waiting out (the
    ///    two charger posts and the device post would again cluster).
    ///    `isPresentationGapPending` is the guard: while a gap is in flight,
    ///    `.immediate` yields to it instead of landing early. Was reasoned
    ///    belt-and-braces only at the 500ms gap (`reconcileChargers`'s 1.5s
    ///    trailing debounce meant a second reconcile that close to the first
    ///    couldn't happen live); at the current 2s gap (see
    ///    `deferredDeviceDiffPresentationGapWindow`'s doc comment) 2s exceeds
    ///    the 1.5s debounce, so this interleaving is now reachable in
    ///    production too, same reasoning as `isPresentationGapPending`'s own
    ///    doc comment. This guard earns its keep now; it was never just
    ///    theoretical hygiene.
    func landDeferredDeviceDiff(token: Int, afterChargerPost: Bool) {
        guard deferredDeviceDiffDevices != nil else { return }
        switch NotificationDecision.deferredDiffLanding(reconcilePostedChargerContent: afterChargerPost) {
        case .immediate:
            guard !isPresentationGapPending else { return }
            landDeferredDeviceDiffNow(token: token)
        case .afterPresentationGap:
            scheduleGapLanding(token: token, delay: deferredDeviceDiffPresentationGapWindow)
        }
    }

    /// Schedules a presentation-gap-guarded landing for the CURRENTLY parked
    /// diff (`deferredDeviceDiffDevices`, identified by `token`), waiting
    /// `delay` before running it. Cancels any outgoing GAP task before
    /// scheduling a new one (not just overwriting the property), and gives
    /// this one its own generation so it can tell later whether it's still
    /// the live gap; both guards are checked together after the sleep, not
    /// just the token, so a stale/superseded task can never touch
    /// `isPresentationGapPending` or land (see
    /// `deferredDeviceDiffPresentationGapGeneration`'s doc comment).
    ///
    /// Deliberately does NOT touch `deferredDeviceDiffDeadlineTask` in either
    /// direction: doesn't cancel it, doesn't re-schedule it. This function
    /// can run repeatedly for the SAME parked diff (a charger that keeps
    /// posting content re-extends the gap every time), and the deadline's
    /// entire job is to bound the total wait regardless of how many times
    /// that happens; a design that used to cancel the deadline here left the
    /// gap phase with no upper bound (see `deferredDeviceDiffDeadlineWindow`'s
    /// doc comment for the starvation bug that caused).
    ///
    /// Shared by two callers, which differ only in what `delay` they pass:
    /// `landDeferredDeviceDiff`'s `.afterPresentationGap` case (the full
    /// `deferredDeviceDiffPresentationGapWindow`, for a device diff that was
    /// deferred waiting on a charger reconcile) and
    /// `parkAndDelayDevicePost` (a REMAINDER, for a device diff that was
    /// never deferred at all but happens to be settling shortly after an
    /// unrelated charger post already went out). This is also the function
    /// that implements interleaving 4 (a second reconcile scheduling its own
    /// gap task while an earlier one is still pending): the cancel-then-
    /// generation-bump below is what lets only the newest gap task win.
    private func scheduleGapLanding(token: Int, delay: Duration) {
        deferredDeviceDiffPresentationGapTask?.cancel()
        deferredDeviceDiffPresentationGapGeneration += 1
        let gapGeneration = deferredDeviceDiffPresentationGapGeneration
        isPresentationGapPending = true
        deferredDeviceDiffPresentationGapTask = Task { @MainActor [weak self] in
            guard let clock = self?.clock else { return }
            try? await clock.sleep(for: delay)
            guard !Task.isCancelled,
                  let self,
                  gapGeneration == self.deferredDeviceDiffPresentationGapGeneration
            else { return }
            self.isPresentationGapPending = false
            self.landDeferredDeviceDiffNow(token: token)
        }
    }

    /// Wall-clock time since `lastChargerPostTime`, or `nil` if no charger
    /// post has gone out yet this app launch. Kept separate from
    /// `devicePostDelay` so the pure arithmetic in `NotificationDecision`
    /// needs no clock at all.
    private func elapsedSinceLastChargerPost() -> Duration? {
        lastChargerPostTime?.duration(to: clock.now)
    }

    /// Entry point for `scheduleDeviceDiff`'s `.runNow` disposition: a device
    /// settle that found no charger settle CURRENTLY pending. That alone
    /// doesn't mean nothing charger-related happened recently (Codex-style
    /// finding from live logs: the charger settle can fire FIRST, post, and
    /// finish reconciling entirely before the device settle's own window
    /// elapses a moment later), so this consults `devicePostDelay` before
    /// deciding. Zero delay: post now, exactly as before this fix. Non-zero:
    /// park the diff and land it after the REMAINDER, reusing the identical
    /// cancel/token/generation-guarded machinery `deferDeviceDiff` /
    /// `scheduleGapLanding` already use, so this path's exactly-once and
    /// supersession guarantees are the SAME code, not a parallel copy.
    ///
    /// Interleaving worth walking through because it's new here: a device
    /// diff already parked by THIS function (waiting out a remainder) is
    /// still parked when ANOTHER device settle fires (e.g. a second device
    /// plugged in moments later). That new settle re-enters this same
    /// function with fresh `devices`. Whichever branch it takes,
    /// `supersedeAnyParkedDiff` (delay == 0) or `parkAndDelayDevicePost`
    /// (delay > 0, via `scheduleAbsoluteDeadline`'s and `scheduleGapLanding`'s
    /// own cancel-before-schedule) invalidates the FIRST parked diff before
    /// doing anything else, so the stale, now-superseded device list can
    /// never land later under a devices-episode's-mismatched token, and
    /// "only the latest settled device state matters" holds regardless of
    /// which path a device diff arrives through. Without this, a `.runNow`
    /// diff arriving with `delay == 0` while an OLDER diff was still parked
    /// from a PREVIOUS settle would post the fresh data immediately while
    /// leaving the old parked one to land later against an already-mutated
    /// `knownDevices` baseline, producing a wrong diff for it.
    func runNowOrDelayForRecentChargerPost(_ devices: [USBDevice]) {
        let episodeID = openDeviceEpisodeIfNeeded()
        // This round is resolving (or parking) right now, not still
        // settling (P1-b fix): free the gate immediately, before either
        // branch below runs, so a fresh raw publish arriving in the middle
        // of this call's own work (there isn't one today, but this keeps
        // the invariant true by construction rather than by accident) opens
        // its own episode rather than reusing this one's id.
        settlingDeviceEpisodeID = nil
        // Sampled once, here, regardless of which branch below runs: this
        // call site IS settle time (see `deferredDeviceDiffTBSwitchIDs`'s
        // doc comment). The `delay == 0` branch's landing coincides with
        // settle time anyway, so sampling here changes nothing for it; the
        // `delay > 0` branch is the one this actually fixes, by carrying
        // the same settle-time snapshot through the park instead of
        // re-reading the closure when `parkAndDelayDevicePost`'s gap task
        // eventually lands it.
        let tbSwitchIDs = currentDownstreamTBSwitchIDs()
        let delay = NotificationDecision.devicePostDelay(
            elapsedSinceLastChargerPost: elapsedSinceLastChargerPost(),
            presentationGap: deferredDeviceDiffPresentationGapWindow
        )
        if delay > .zero {
            parkAndDelayDevicePost(devices, tbSwitchIDs: tbSwitchIDs, episodeID: episodeID, delay: delay)
        } else {
            // P1-b fix: `supersedeAnyParkedDiff()` now closes whatever WAS
            // parked (its own, possibly different, episode) before this
            // fresh diff runs under ITS OWN `episodeID`, so an event owned
            // by a superseded parked diff can never leak into this
            // unrelated one.
            supersedeAnyParkedDiff()
            diffDevices(devices, tbSwitchIDs: tbSwitchIDs, episodeID: episodeID)
        }
    }

    /// Parks `devices` as a fresh episode (its own token), starts its
    /// absolute deadline (`scheduleAbsoluteDeadline`, same as
    /// `deferDeviceDiff`: this path is just as susceptible to sustained
    /// charger flapping re-extending its gap indefinitely, since
    /// `landDeferredDeviceDiff` doesn't care HOW a diff got parked before
    /// re-scheduling its gap), then schedules the gap-guarded landing after
    /// `delay`.
    private func parkAndDelayDevicePost(_ devices: [USBDevice], tbSwitchIDs: Set<Int64>, episodeID: UInt64, delay: Duration) {
        // Close whatever was PREVIOUSLY parked (P1-b fix), same reasoning as
        // `deferDeviceDiff`'s own call: this overwrites the single park slot
        // below, so the OLD parked diff's episode identity must be
        // discarded along with its devices, not silently inherited.
        closeParkedEpisode()
        parkedDeviceEpisodeID = episodeID
        deferredDeviceDiffToken += 1
        let token = deferredDeviceDiffToken
        deferredDeviceDiffDevices = devices
        deferredDeviceDiffTBSwitchIDs = tbSwitchIDs
        scheduleAbsoluteDeadline(token: token)
        scheduleGapLanding(token: token, delay: delay)
    }

    /// Invalidates any diff currently parked, from either path (the
    /// charger-pending deadline path or the presentation-gap path): cancels
    /// both scheduled tasks, bumps both the token and the gap generation so
    /// any of their still-in-flight continuations see a stale value and back
    /// out, and clears the pending-gap flag. Called before running a device
    /// diff immediately whenever an OLDER one might still be parked; see the
    /// interleaving walk-through on `runNowOrDelayForRecentChargerPost`. Same
    /// cancel-before-superseding shape as interleaving 3 on
    /// `landDeferredDeviceDiff(token:afterChargerPost:)` (a new parked diff
    /// invalidating an outgoing one), just reached from the `.runNow` router
    /// instead of `deferDeviceDiff`.
    private func supersedeAnyParkedDiff() {
        deferredDeviceDiffToken += 1
        deferredDeviceDiffDevices = nil
        deferredDeviceDiffTBSwitchIDs = nil
        // P1-b fix (adversarial round 2, "misattribution leak"): this diff
        // is being DISCARDED, never landed, so its episode has to close here
        // too -- clearing any event still tagged to it -- exactly like every
        // other path that drops a parked diff. Before this fix, the parked
        // diff's episode stayed open (nothing here touched it), so an event
        // tagged to it could still be picked up by whatever unrelated diff
        // runs immediately after this call.
        closeParkedEpisode()
        deferredDeviceDiffDeadlineTask?.cancel()
        deferredDeviceDiffPresentationGapTask?.cancel()
        deferredDeviceDiffPresentationGapGeneration += 1
        isPresentationGapPending = false
    }

    /// The single place a deferred device diff actually runs, reached from
    /// three places: directly from `landDeferredDeviceDiff(token:afterChargerPost:)`'s
    /// `.immediate` case, after the presentation gap it schedules
    /// (interleaving 1), or after the absolute deadline
    /// (`scheduleAbsoluteDeadline`, interleaving 2). `shouldLandDeferredDiff`
    /// is the guard that keeps only the first of those to actually arrive
    /// from doing anything; see the interleaving walk-through above.
    private func landDeferredDeviceDiffNow(token: Int) {
        // `deferredDeviceDiffTBSwitchIDs` is always set alongside
        // `deferredDeviceDiffDevices` at every park site (`deferDeviceDiff`,
        // `parkAndDelayDevicePost`), so it is bound in the same guard as the
        // devices rather than falling back to a landing-time
        // `currentDownstreamTBSwitchIDs()` read: that fallback would silently
        // reopen the exact settle-time-vs-landing-time bug this snapshot
        // exists to close if the invariant ever regressed. An absent
        // snapshot here means there was never a valid parked diff to land,
        // same as an absent `deferredDeviceDiffDevices`, so it backs out the
        // same way.
        guard let devices = deferredDeviceDiffDevices,
              let tbSwitchIDs = deferredDeviceDiffTBSwitchIDs,
              let episodeID = parkedDeviceEpisodeID,
              NotificationDecision.shouldLandDeferredDiff(token: token, liveToken: deferredDeviceDiffToken)
        else { return }
        deferredDeviceDiffToken += 1
        deferredDeviceDiffDevices = nil
        deferredDeviceDiffTBSwitchIDs = nil
        // Ownership TRANSFERS into the `diffDevices` call below, untouched
        // (mirrors the settling-to-held transition in `resolveDevicePost`):
        // this diff is landing, not being discarded, so its event (if any)
        // must survive to be checked there, not cleared here.
        parkedDeviceEpisodeID = nil
        deferredDeviceDiffDeadlineTask?.cancel()
        deferredDeviceDiffPresentationGapTask?.cancel()
        deferredDeviceDiffPresentationGapGeneration += 1
        // Defensive, not load-bearing on the deadline/immediate paths (which
        // never set this true): once ANY path actually lands the diff, no
        // gap should be treated as still pending for it.
        isPresentationGapPending = false
        diffDevices(devices, tbSwitchIDs: tbSwitchIDs, episodeID: episodeID)
    }

    private func diffDevices(_ current: [USBDevice], tbSwitchIDs: Set<Int64>, episodeID: UInt64) {
        guard didPrimeBaseline else { clearEventIfOwnedBy(episodeID); return }

        let previousSnapshots = Array(knownDevices.values)
        let currentSnapshots = current.map(snapshot(for:))
        knownDevices = Dictionary(
            currentSnapshots.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Baseline discipline: refreshed unconditionally, in lockstep with
        // knownDevices above, BEFORE the notifyOnChanges gate below, so a
        // user who has notifications off during a TB plug/unplug doesn't
        // see a stale baseline manufacture a false "Thunderbolt involved" on
        // the first diff after turning notifications back on. `tbSwitchIDs`
        // is the caller's SETTLE-TIME snapshot (see
        // `deferredDeviceDiffTBSwitchIDs`'s doc comment), not re-read here:
        // re-reading `currentDownstreamTBSwitchIDs()` at landing time would
        // reopen the exact bug that snapshot exists to close.
        let previousTBSwitchIDs = knownTBSwitchIDs
        knownTBSwitchIDs = tbSwitchIDs

        // Terminal path (fix1, spec design 1): notifications are off, so
        // this settle will never reach `resolveDevicePost` at all. Clear
        // this episode's own event here, its only terminal point in that
        // case, so a stale owned event can never survive to be misread once
        // notifications come back on.
        //
        // fix2 design 6: an off-settle ALSO sweeps every pending/held
        // device job (queue and hold alike), on top of the episode clear
        // above. The baseline just advanced unconditionally, above, so it
        // correctly serves as the acknowledged/suppressed state: nothing
        // queued fires while disabled, and nothing catches up once
        // notifications come back on. See
        // `cancelPendingDeviceWorkForNotificationsOff()`'s own doc comment
        // for the asymmetry this policy accepts (a plain settings toggle,
        // with no settle observing it, leaves already-pending work alone).
        guard notifyOnChanges() else {
            clearEventIfOwnedBy(episodeID)
            cancelPendingDeviceWorkForNotificationsOff()
            return
        }

        // fix2 design 1: the map a coalesced job's fire-time reconciliation
        // reads bodies from (LATEST wins on a merge). Built here, same as
        // the old `currentByID` it replaces, recovering a device's body by
        // identity (rootID), never by name: two hubs of the same model
        // report the same product name.
        let bodyMap = deviceBodyMap(for: current)
        let derivation = Self.deriveDeviceDelta(
            previousSnapshots: previousSnapshots,
            currentSnapshots: currentSnapshots,
            previousTBSwitchIDs: previousTBSwitchIDs,
            currentTBSwitchIDs: tbSwitchIDs,
            bodyMap: bodyMap
        )

        // Diagnostic: reconstruct the same reconnect-gate check
        // `deviceNotificationContents` runs below, so the log line reflects
        // what actually decides "Reconnected" vs "Disconnected"+"Connected".
        let reconnectGateFired = derivation.removedGroups.count == 1 && derivation.addedGroups.count == 1
            && NotificationDecision.isReconnectPair(removed: derivation.removedGroups[0], added: derivation.addedGroups[0])
        log("diffDevices: addedGroups=\(derivation.addedGroups.count) removedGroups=\(derivation.removedGroups.count) addedRoots=\(derivation.addedGroups.map(\.rootName).joined(separator: ", ")) removedRoots=\(derivation.removedGroups.map(\.rootName).joined(separator: ", ")) reconnectGateFired=\(reconnectGateFired)")

        resolveDevicePost(
            removedGroups: derivation.removedGroups,
            addedGroups: derivation.addedGroups,
            thunderboltInvolved: derivation.thunderboltInvolved,
            previousLocationIDs: derivation.previousLocationIDs,
            currentLocationIDs: derivation.currentLocationIDs,
            singleDeviceBody: derivation.singleDeviceBody,
            episodeID: episodeID,
            previousSnapshots: previousSnapshots,
            currentSnapshots: currentSnapshots,
            previousTBSwitchIDs: previousTBSwitchIDs,
            currentTBSwitchIDs: tbSwitchIDs,
            bodyMap: bodyMap
        )
    }

    /// rootID (a `USBDevice.id`) to its speed/vendor body string, for
    /// `deriveDeviceDelta`'s `singleDeviceBody` lookup. Shared by every
    /// caller that needs one (`diffDevices`, and any coalesced job at fire
    /// time reads its OWN stored map instead of calling this again).
    private func deviceBodyMap(for devices: [USBDevice]) -> [UInt64: String] {
        Dictionary(
            devices.map { ($0.id, "\($0.speedLabel)\($0.vendorName.map { " · \($0)" } ?? "")") },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Ingredients + result of one endpoint-to-endpoint device diff (fix2
    /// design 3). Pure: takes only values, touches no baseline, needs no
    /// `self`. `diffDevices` (every settle) and a coalesced job's fire-time
    /// reconciliation (`fireDevicePostJob`) both call this SAME function, so
    /// the two can never drift apart. Not `private`: a sequencer test proves
    /// derivation parity against an independently hand-derived expectation.
    struct DeviceDeltaDerivation {
        let addedGroups: [USBDeviceChangeGrouper.ChangeGroup]
        let removedGroups: [USBDeviceChangeGrouper.ChangeGroup]
        let previousLocationIDs: Set<UInt32>
        let currentLocationIDs: Set<UInt32>
        let thunderboltInvolved: Bool
        let singleDeviceBody: (UInt64) -> String?
    }

    static func deriveDeviceDelta(
        previousSnapshots: [USBDeviceChangeGrouper.Snapshot],
        currentSnapshots: [USBDeviceChangeGrouper.Snapshot],
        previousTBSwitchIDs: Set<Int64>,
        currentTBSwitchIDs: Set<Int64>,
        bodyMap: [UInt64: String]
    ) -> DeviceDeltaDerivation {
        let (addedGroups, removedGroups) = USBDeviceChangeGrouper.diff(
            previous: previousSnapshots,
            current: currentSnapshots
        )
        return DeviceDeltaDerivation(
            addedGroups: addedGroups,
            removedGroups: removedGroups,
            previousLocationIDs: Set(previousSnapshots.map(\.locationID)),
            currentLocationIDs: Set(currentSnapshots.map(\.locationID)),
            thunderboltInvolved: NotificationDecision.thunderboltInvolved(
                previous: previousTBSwitchIDs,
                current: currentTBSwitchIDs
            ),
            singleDeviceBody: { rootID in bodyMap[rootID] }
        )
    }

    /// fix2 design 6: sweeps every pending or held device job the moment a
    /// settle OBSERVES notifications off, on top of the episode-event clear
    /// the caller already did. Clearing `deviceQueue` outright is safe
    /// because a sleeping drain task just wakes to an empty queue and
    /// returns (`drainDeviceQueueIfPossible`'s own `!deviceQueue.isEmpty`
    /// guard); nothing needs cancelling there. The held half is a
    /// deliberate, small behaviour change from before this fix: a batch
    /// held when notifications get switched off used to still post at its
    /// 5s cap regardless; under this policy an off-settle suppresses it too,
    /// consistent with suppressing the queue.
    ///
    /// Asymmetry, on purpose: toggling notifications off in Settings, with
    /// no device settle ever observing the off state before it flips back
    /// on, leaves any already-pending job to fire, unchanged from today.
    /// Only a settle that reads `notifyOnChanges() == false` sweeps -- this
    /// function has no independent trigger of its own.
    private func cancelPendingDeviceWorkForNotificationsOff() {
        deviceQueue.removeAll()

        guard heldDeviceBatch != nil else { return }
        heldDeviceBatch = nil
        // Belt-and-braces (adversarial fix-round finding, confirmed by
        // deliberately dropping these two lines and watching the suite stay
        // green): individually inert given `heldDeviceBatch = nil` above.
        // `flushHeldDeviceBatch`'s own `guard let batch = heldDeviceBatch`
        // already refuses to do anything once that is nil, whatever the
        // stale deadline task's captured token says and whether or not that
        // task is ever actually cancelled. Kept anyway, matching this
        // file's documented pattern elsewhere (see
        // `deferredDeviceDiffPresentationGapGeneration`'s doc comment): a
        // future refactor that loosens the `heldDeviceBatch` guard should
        // not silently start relying on these two having been dropped.
        heldDeviceBatchToken += 1
        heldDeviceBatchDeadlineTask?.cancel()
        heldDeviceBatchDeadlineTask = nil
        closeHeldEpisode()
    }

    // MARK: - Saved-cable label hold (issue #570 part B)
    //
    // A new, FINAL stage that sits strictly after every device diff has
    // resolved through the existing park/defer/deadline machinery above
    // (`diffDevices` is the single place that machinery converges on,
    // however it got there: `.runNow`, a landed deferred diff, or a landed
    // gap/deadline diff). This stage never touches `deferredDeviceDiffDevices`
    // or any of its guards; it owns an entirely separate token/generation
    // and its own fixed 5.0s timer (`cablePlausibilityHoldWindow`).
    //
    // Gate-fixes revision (Codex findings 2/3/5, adversarial A1): the
    // original design posted a held batch's content immediately on flush
    // and used a one-shot, call-local "did I just flush" flag to decide
    // whether the FOLLOWING post needed a presentation gap. That flag had
    // no memory outside the single `resolveDevicePost` call it was computed
    // in, which broke three ways: a cap-expiry flush (fired from the
    // deadline TASK, not from `resolveDevicePost`) left no trace for the
    // next unrelated settle to see, so device posts arriving right after a
    // cap expired got no gap at all (A1); a THIRD diff settling during an
    // active gap wait wasn't ordered against the one still queued, only
    // against whatever flushed most recently (Codex 2); and content was
    // composed and frozen at flush time, before the gap sleep, so a licence
    // change during that sleep couldn't un-label an already-decided post
    // (Codex 3).
    //
    // The fix replaces the one-shot flag with a proper FIFO queue
    // (`deviceQueue`) gated by a single running clock value
    // (`lastDevicePostTime`), the device-post analogue of
    // `lastChargerPostTime`. EVERY `.device` post -- the immediate no-hold
    // path, a synchronous hold-cap-avoided post, a hold flush from a NEW
    // settle superseding it, and a hold flush from the cap-expiry TASK --
    // funnels through `enqueueDevicePost(_:)`, which appends a job (the
    // batch's INGREDIENTS, not composed content) and lets
    // `drainDeviceQueueIfPossible()` release jobs one at a time, each
    // waiting out whatever remainder of `deferredDeviceDiffPresentationGapWindow`
    // is left since the last actual device post. `fireDevicePostJob(_:)` is
    // the ONE place that ever calls `NotificationDecision.deviceNotificationContents`
    // for a `.device` post, and it runs at the moment a job is actually
    // released, never earlier. The label itself is BOUND EARLIER, at job
    // creation (`capturedLabel`, consumed from `pendingCableLabelEvent` at
    // capture time so a queued job can never pick up a LATER cable's
    // event); the one thing evaluated fresh at fire time is the licence
    // nil-guard, against whatever `knownLabelledCables` says AT THAT
    // INSTANT.
    //
    // Named interleavings, walked through where each one is actually
    // implemented:
    //   - held batch vs charger post's presentation gap: NOT a real
    //     interleaving. `lastDevicePostTime` / `deviceQueue` are entirely
    //     separate from `lastChargerPostTime`; charger posts are never
    //     held, queued, or delayed by this stage (`reconcileChargers`'s own
    //     posting loop is untouched), so there is nothing here for a
    //     charger post to race against.
    //   - second device diff settling during an active hold: `resolveDevicePost`
    //     calls `flushHeldDeviceBatch` FIRST, unconditionally, before
    //     evaluating its own gate. See that function.
    //   - `landDeferredDeviceDiff` landing into an active hold: no special
    //     case needed. `landDeferredDeviceDiffNow` always ends by calling
    //     `diffDevices`, which always ends by calling `resolveDevicePost`,
    //     which always flushes first. A landed deferred diff is just
    //     another settled batch arriving from this stage's point of view.
    //   - cap expiry racing a labelled-cables update: both paths
    //     (`scheduleHeldDeviceBatchDeadline`'s timer firing,
    //     `updateLabelledCables`'s direction-matched flush) call the SAME
    //     `flushHeldDeviceBatch(token:)`, which re-checks the token before
    //     doing anything and clears `heldDeviceBatchDeadlineTask` /
    //     `heldDeviceBatch` together as its first act. Whichever reaches it
    //     first wins; the other's token has already moved on, so it's a
    //     no-op. Exactly one flush either way.
    //   - cap-expiry flush then an immediately-following diff (adversarial
    //     A1, now closed): the cap-expiry flush enqueues its job exactly
    //     like any other path, so `lastDevicePostTime` is set the moment it
    //     actually fires, regardless of which code path produced it. A
    //     brand-new `resolveDevicePost` call moments later enqueues its OWN
    //     job into the SAME queue, which reads that just-updated
    //     `lastDevicePostTime` and waits out the remainder of the spacing
    //     window exactly as if the two posts had come from the same
    //     `resolveDevicePost` call. There is no longer a code path that
    //     posts without checking `lastDevicePostTime` first.
    //   - third diff settling while a second is still queued (Codex 2, now
    //     closed): `enqueueDevicePost` always appends to `deviceQueue` and
    //     only ever starts ONE drain task at a time
    //     (`deviceQueueTask == nil` guard in `drainDeviceQueueIfPossible`),
    //     so a third job simply waits behind the second in the array. Strict
    //     FIFO by construction: nothing can jump the queue, and nothing
    //     drains two jobs on the same wait.
    //   - licence lock mid-hold: `fireDevicePostJob` re-reads
    //     `knownLabelledCables` (not any cached availability flag) at the
    //     moment it actually applies a label, so a lock that lands between
    //     hold-start and the job's actual fire drops the label even if
    //     `pendingCableLabelEvent` still holds a stale match from before the
    //     lock. A stale event surviving a lock/unlock to be misapplied to a
    //     LATER, unrelated diff is now closed by episode-scoped ownership
    //     (see the next bullet), not by a nil-feed special case.
    //   - stale-binding / diff-less-flap (fix1, episode-scoped ownership):
    //     `pendingCableLabelEvent` and `graceCableLabelEvent` are tagged
    //     with (or bounded to) a `deviceEpisodeID` the moment they are
    //     assigned (`assignCableLabelEvent(_:)`), and every consumption site
    //     -- the at-settle match in `resolveDevicePost`,
    //     `flushHeldDeviceBatch`, `tryFlushHeldDeviceBatchForPendingEvent`
    //     -- only matches when that tag equals the episode being checked.
    //     This closes two failure paths a bare capture-time bind did not: a
    //     label arriving AFTER its own batch's cap (the batch already
    //     flushed unlabelled, its episode closed) can no longer sit
    //     indefinitely and label the next unrelated same-direction settle,
    //     because `clearEventIfOwnedBy(_:)` (via `closeParkedEpisode()`/
    //     `closeHeldEpisode()`, and every direct terminal branch in
    //     `diffDevices`/`resolveDevicePost`) clears an event still tagged to
    //     the episode being closed; and a labelled-cables change with NO
    //     device episode open at all (a bare TB renegotiation flap) goes
    //     into the bounded `graceCableLabelEvent` slot instead of the owned
    //     one, claimable only by the very next episode to open within
    //     `deviceSettleWindow` of its own arrival, so it cannot label some
    //     much later, unrelated plug either. A second device episode opening
    //     while an OLDER one is still held (a completely unrelated plug
    //     settling while a prior batch waits out its cap) is not itself a
    //     race needing special handling: the two episodes carry distinct ids
    //     by construction (`deviceEpisodeIDCounter` never repeats),
    //     `assignCableLabelEvent(_:)` always prefers a currently-settling
    //     (or parked) episode over an older held one, and `resolveDevicePost`
    //     always flushes whatever is held FIRST, before evaluating the new
    //     settle, so the older batch is never starved by the newer one
    //     arriving.
    //   - P1-a, burst-heavy debounce losing the grace slot (adversarial
    //     round 2): opening used to happen only inside
    //     `runNowOrDelayForRecentChargerPost`/`deferDeviceDiff`, i.e. only
    //     once a settle round actually FIRED. `scheduleDeviceDiff`'s settle
    //     timer resets on every raw publish with no upper bound, so a burst
    //     of publishes (four, 600ms apart, is enough) can push the actual
    //     fire time several seconds past when a label event legitimately
    //     arrived just before the FIRST publish of that burst -- well past
    //     `deviceSettleWindow`, so the grace slot would have already expired
    //     by the time an episode finally opened to claim it. Fixed by moving
    //     `openDeviceEpisodeIfNeeded()` into `scheduleDeviceDiff()` itself,
    //     called synchronously on EVERY raw publish (idempotent: the first
    //     publish of a burst opens the episode and claims grace right then;
    //     every further publish in the same burst is a no-op here), so grace
    //     claiming happens at the START of a debounce burst, not its end.
    //   - P1-b, parked-diff supersede misattribution (adversarial round 2):
    //     the zero-delay `.runNow` branch of `runNowOrDelayForRecentChargerPost`
    //     (`supersedeAnyParkedDiff()` then `diffDevices(...)` directly) used
    //     to run the superseding diff under the SAME `settlingDeviceEpisodeID`
    //     the just-discarded parked diff had been retaining throughout its
    //     whole park/defer/gap/deadline lifetime, so an event tagged to the
    //     superseded diff could wrongly label the completely unrelated one
    //     that replaced it. Fixed by giving a parked diff its OWN identity,
    //     `parkedDeviceEpisodeID`, separate from `settlingDeviceEpisodeID`:
    //     parking (`deferDeviceDiff`, `parkAndDelayDevicePost`) clears the
    //     settling gate immediately (freeing it for a genuinely fresh
    //     episode to open on the very next raw publish) and moves the id
    //     into `parkedDeviceEpisodeID` instead; discarding a parked diff
    //     (`supersedeAnyParkedDiff`, or a newer park overwriting an older
    //     one) closes THAT episode (`closeParkedEpisode()`, clearing any
    //     event it owns) before anything else runs. The superseding diff
    //     then resolves under its OWN, separately-opened `episodeID`,
    //     threaded through `diffDevices`/`resolveDevicePost` as a parameter
    //     rather than read back off `settlingDeviceEpisodeID` (which may
    //     already be `nil`, or already belong to some OTHER, even newer
    //     episode, by the time those functions run).

    /// The hold-stage entry point: called at the tail of EVERY `diffDevices`
    /// run, whichever of the three landing paths reached it. Decides,
    /// pure-first, whether this settled batch needs the cable-plausibility
    /// hold at all, and either enqueues a post job straight away or parks it.
    ///
    /// Flush-never-drop (spec design 6, v2 blocker B): before doing
    /// anything else, any batch STILL held from an earlier settle is
    /// flushed (enqueued). Its content was already fully decided in SHAPE
    /// (the exact groups to post); the label MATCH, if any, is resolved
    /// right there in `flushHeldDeviceBatch` (capture-time binding,
    /// gate-fixes P2), and the final NotificationContent composition
    /// happens later, in `fireDevicePostJob`, at actual fire time. The held
    /// batch's own content is therefore NEVER discarded, only ever
    /// eventually posted labelled or unlabelled.
    private func resolveDevicePost(
        removedGroups: [USBDeviceChangeGrouper.ChangeGroup],
        addedGroups: [USBDeviceChangeGrouper.ChangeGroup],
        thunderboltInvolved: Bool,
        previousLocationIDs: Set<UInt32>,
        currentLocationIDs: Set<UInt32>,
        singleDeviceBody: @escaping (UInt64) -> String?,
        episodeID: UInt64,
        previousSnapshots: [USBDeviceChangeGrouper.Snapshot],
        currentSnapshots: [USBDeviceChangeGrouper.Snapshot],
        previousTBSwitchIDs: Set<Int64>,
        currentTBSwitchIDs: Set<Int64>,
        bodyMap: [UInt64: String]
    ) {
        flushHeldDeviceBatch(token: heldDeviceBatchToken)

        let isReconnect = removedGroups.count == 1 && addedGroups.count == 1
            && NotificationDecision.isReconnectPair(removed: removedGroups[0], added: addedGroups[0])

        // "If the feature is unavailable (nil) or no saved cables exist
        // anywhere, post immediately, exactly as today." Post-review fix:
        // "no saved cables exist anywhere" is `knownHasSavedCables == false`,
        // a fact the PROVIDER supplies (the saved-cables store's own
        // count), never inferred from `knownLabelledCables` being empty.
        // The old inference broke the feature's own flagship case: a user
        // with exactly one saved cable, currently unplugged, has
        // `knownLabelledCables == [:]` right up until that cable's
        // e-marker resolves, which is the entire reason the hold exists.
        // Reading that emptiness as "nothing saved anywhere" skipped the
        // hold and posted unlabelled on every connect of a user's only
        // saved cable. A LATER settle can still hold once the feature (or a
        // saved cable) becomes available; this is a per-settle read, not a
        // permanent switch.
        let featureCouldEverLabel = knownLabelledCables != nil && knownHasSavedCables

        // Reconnect pairs are gate-exempt from the hold (reviewer amendment
        // 3): "a power-cycling device re-enumerating at the same locationID
        // is not a cable event, the label structurally cannot resolve, and
        // a fault-recovery notification must not wait." Never held, and
        // never labelled either, for the same structural reason (see the
        // stale-doc-comment fix on `deviceNotificationContents` for the
        // full story on why this file used to claim otherwise).
        guard !isReconnect else {
            enqueueDevicePost(DevicePostJob(
                removedGroups: removedGroups, addedGroups: addedGroups, thunderboltInvolved: thunderboltInvolved,
                singleDeviceBody: singleDeviceBody, capturedLabel: nil,
                previousSnapshots: previousSnapshots, currentSnapshots: currentSnapshots,
                previousTBSwitchIDs: previousTBSwitchIDs, currentTBSwitchIDs: currentTBSwitchIDs, bodyMap: bodyMap
            ))
            // Terminal path (fix1): reconnects never hold, so this is this
            // episode's only chance to resolve. Clear its event here.
            clearEventIfOwnedBy(episodeID)
            return
        }

        let removedEligible = removedGroups.contains {
            NotificationDecision.isPortLevelChange(group: $0, previousLocationIDs: previousLocationIDs, currentLocationIDs: currentLocationIDs)
        }
        let addedEligible = addedGroups.contains {
            NotificationDecision.isPortLevelChange(group: $0, previousLocationIDs: previousLocationIDs, currentLocationIDs: currentLocationIDs)
        }

        guard featureCouldEverLabel, removedEligible || addedEligible else {
            // No group in this batch is a port-level tree change (every
            // change is inside an existing tree), or the feature could
            // never label this settle anyway: enqueue with NO label
            // eligibility at all, so `fireDevicePostJob` never even looks
            // at `pendingCableLabelEvent` for this job.
            enqueueDevicePost(DevicePostJob(
                removedGroups: removedGroups, addedGroups: addedGroups, thunderboltInvolved: thunderboltInvolved,
                singleDeviceBody: singleDeviceBody, capturedLabel: nil,
                previousSnapshots: previousSnapshots, currentSnapshots: currentSnapshots,
                previousTBSwitchIDs: previousTBSwitchIDs, currentTBSwitchIDs: currentTBSwitchIDs, bodyMap: bodyMap
            ))
            // Terminal path (fix1): a batch with no port-level group, or
            // where the feature could never label it anyway, never holds.
            clearEventIfOwnedBy(episodeID)
            return
        }

        // A usable label MIGHT already be present. CAPTURE-TIME binding
        // (gate-fixes P2, follow-up finding): the match against
        // `pendingCableLabelEvent` is decided and the event CONSUMED right
        // here, at the moment this job is created, not deferred to fire
        // time. Binding at fire time instead (the original gate-fixes fix 1
        // design) had a real bug: while THIS job sits queued behind the
        // spacing floor, a DIFFERENT cable's event could arrive and
        // overwrite the single, global `pendingCableLabelEvent` before this
        // job's turn came, so it could fire carrying a stranger's name. A
        // job now carries its OWN captured event (or none), fixed the
        // instant it's created, so a later, unrelated event can never leak
        // into it. Only the licence nil-guard (`knownLabelledCables`)
        // remains a genuine fire-time check, in `fireDevicePostJob`: a lock
        // can still legitimately erase a label between capture and fire,
        // and correctly should.
        // Owner-checked (fix1, spec design 3): only consume when the event
        // is tagged to THIS round's `episodeID`. This check is a defensive
        // invariant guard, not a reachable branch point in normal
        // operation: `episodeID` is the value this specific settle round
        // was opened/parked/landed under, so by construction it is the only
        // id `pendingCableLabelEvent` could ever carry here if it was
        // assigned to THIS round at all (`assignCableLabelEvent(_:)` always
        // tags an incoming event to whichever episode is CURRENTLY settling
        // or parked, and `resolveDevicePost` always flushes any older HELD
        // batch first, before this check ever runs -- see
        // `flushHeldDeviceBatch`'s own owner check, which is where a
        // cross-episode mismatch actually gets exercised). Kept anyway,
        // matching the belt-and-braces pattern already used elsewhere in
        // this file (see `deferredDeviceDiffPresentationGapGeneration`'s
        // doc comment): it makes "a stale event can't be misapplied here"
        // true by construction, not by relying on every caller upstream
        // continuing to get the assignment right.
        if let event = pendingCableLabelEvent, event.episodeID == episodeID,
           (event.wasAdded && addedEligible) || (!event.wasAdded && removedEligible) {
            pendingCableLabelEvent = nil
            enqueueDevicePost(DevicePostJob(
                removedGroups: removedGroups, addedGroups: addedGroups, thunderboltInvolved: thunderboltInvolved,
                singleDeviceBody: singleDeviceBody,
                capturedLabel: DevicePostJob.CapturedLabel(name: event.name, wasAdded: event.wasAdded),
                previousSnapshots: previousSnapshots, currentSnapshots: currentSnapshots,
                previousTBSwitchIDs: previousTBSwitchIDs, currentTBSwitchIDs: currentTBSwitchIDs, bodyMap: bodyMap
            ))
            // Terminal path (fix1): matched and posted, never held.
            clearEventIfOwnedBy(episodeID)
            return
        }

        // No label yet: hold. Every subsequent `updateLabelledCables` call
        // re-evaluates via `tryFlushHeldDeviceBatchForPendingEvent`; at the
        // cap, `scheduleHeldDeviceBatchDeadline` flushes (enqueues). The
        // label is bound at the FLUSH, whichever path triggers it
        // (`flushHeldDeviceBatch` matches and consumes the event into the
        // job's `capturedLabel` right then); `fireDevicePostJob` only
        // applies that captured label, subject to the fire-time licence
        // nil-guard.
        heldDeviceBatchToken += 1
        let token = heldDeviceBatchToken
        heldDeviceBatch = HeldDeviceBatch(
            removedGroups: removedGroups,
            addedGroups: addedGroups,
            thunderboltInvolved: thunderboltInvolved,
            singleDeviceBody: singleDeviceBody,
            removedEligible: removedEligible,
            addedEligible: addedEligible,
            previousSnapshots: previousSnapshots,
            currentSnapshots: currentSnapshots,
            previousTBSwitchIDs: previousTBSwitchIDs,
            currentTBSwitchIDs: currentTBSwitchIDs,
            bodyMap: bodyMap
        )
        // Not a terminal path (fix1): holding is the SAME episode, still
        // in flight. The id moves from "settling/parked" to "held" (any
        // event still tagged to it moves with it, untouched), it does not
        // close. Uses the `episodeID` PARAMETER, not `settlingDeviceEpisodeID`:
        // that property was already cleared (or reassigned to a totally
        // different, newer episode) by the caller before this function ever
        // ran -- see `settlingDeviceEpisodeID`'s doc comment.
        heldDeviceBatchEpisodeID = episodeID
        scheduleHeldDeviceBatchDeadline(token: token)
    }

    /// Schedules the fixed, non-resetting 5.0s deadline for the batch just
    /// held under `token`. Mirrors `scheduleAbsoluteDeadline`'s shape
    /// (own timer, own token check on fire) but is otherwise fully
    /// independent: this stage's timer is never re-scheduled by anything
    /// (there is no gap-extension concept here, unlike the presentation gap
    /// above the park/defer machinery), so "5.0s from hold-start" is always
    /// the true worst case, never re-extended by further activity.
    private func scheduleHeldDeviceBatchDeadline(token: Int) {
        heldDeviceBatchDeadlineTask?.cancel()
        heldDeviceBatchDeadlineTask = Task { @MainActor [weak self] in
            guard let clock = self?.clock else { return }
            try? await clock.sleep(for: Self.cablePlausibilityHoldWindow)
            guard !Task.isCancelled, let self else { return }
            self.flushHeldDeviceBatch(token: token)
        }
    }

    /// Flushes (enqueues) the currently held batch, if `token` still
    /// matches the live one (mirrors `shouldLandDeferredDiff`'s guard
    /// shape). A no-op when nothing is held or `token` is stale (already
    /// flushed by another path -- see the cap-vs-update interleaving in
    /// this section's own doc comment).
    ///
    /// CAPTURE-TIME binding (gate-fixes P2, follow-up finding): this IS the
    /// capture moment for a held batch, whichever of the three paths called
    /// it (a new diff superseding it, `tryFlushHeldDeviceBatchForPendingEvent`
    /// matching an event, or the cap deadline firing). `pendingCableLabelEvent`
    /// is checked and CONSUMED right here, once, and the result is baked
    /// into the `DevicePostJob` handed to `enqueueDevicePost`. Composing
    /// content itself still happens later, in `fireDevicePostJob` at fire
    /// time (only the licence nil-guard remains a fire-time check there):
    /// what changed is that the label ITSELF -- which event, whose name --
    /// is now fixed the instant this job is created, so it can never be
    /// swapped out for a different cable's event that happens to arrive
    /// while this job sits queued behind the spacing floor.
    private func flushHeldDeviceBatch(token: Int) {
        guard let batch = heldDeviceBatch, token == heldDeviceBatchToken else { return }
        heldDeviceBatch = nil
        heldDeviceBatchToken += 1
        heldDeviceBatchDeadlineTask?.cancel()
        heldDeviceBatchDeadlineTask = nil

        // Owner-checked (fix1, spec design 3): only consume when the event
        // is tagged to THIS held episode, mirroring the settling-side check
        // in `resolveDevicePost`.
        var capturedLabel: DevicePostJob.CapturedLabel?
        if let episodeID = heldDeviceBatchEpisodeID,
           let event = pendingCableLabelEvent, event.episodeID == episodeID {
            if event.wasAdded, batch.addedEligible {
                capturedLabel = DevicePostJob.CapturedLabel(name: event.name, wasAdded: true)
                pendingCableLabelEvent = nil
            } else if !event.wasAdded, batch.removedEligible {
                capturedLabel = DevicePostJob.CapturedLabel(name: event.name, wasAdded: false)
                pendingCableLabelEvent = nil
            }
        }

        // Terminal path (fix1): this held batch is done, whichever of the
        // three callers flushed it. Close its episode, clearing any event
        // still tagged to it (the unmatched case above).
        closeHeldEpisode()

        enqueueDevicePost(DevicePostJob(
            removedGroups: batch.removedGroups,
            addedGroups: batch.addedGroups,
            thunderboltInvolved: batch.thunderboltInvolved,
            singleDeviceBody: batch.singleDeviceBody,
            capturedLabel: capturedLabel,
            previousSnapshots: batch.previousSnapshots,
            currentSnapshots: batch.currentSnapshots,
            previousTBSwitchIDs: batch.previousTBSwitchIDs,
            currentTBSwitchIDs: batch.currentTBSwitchIDs,
            bodyMap: batch.bodyMap
        ))
    }

    /// If a batch is currently held AND `pendingCableLabelEvent`'s
    /// direction matches the side that batch is eligible on, flush
    /// (enqueue) it right now. Called from `updateLabelledCables(_:)` every
    /// time it computes a fresh event; a no-op when nothing is held or the
    /// direction doesn't match (the event just sits in
    /// `pendingCableLabelEvent`, still available to a LATER settle or a
    /// later, matching push).
    private func tryFlushHeldDeviceBatchForPendingEvent() {
        guard let batch = heldDeviceBatch,
              let episodeID = heldDeviceBatchEpisodeID,
              let event = pendingCableLabelEvent, event.episodeID == episodeID else { return }
        let matches = (event.wasAdded && batch.addedEligible) || (!event.wasAdded && batch.removedEligible)
        guard matches else { return }
        flushHeldDeviceBatch(token: heldDeviceBatchToken)
    }

    // MARK: - Device-post spacing floor (gate-fixes fix 1)

    /// Ingredients for one `.device`-category post, held by the queue.
    /// `NotificationContent` itself is still composed only at FIRE TIME
    /// (see `fireDevicePostJob`): gate-fixes finding 3 requires that, since
    /// which GROUPS to name and whether Thunderbolt was involved can't
    /// change, but the label decision must reflect whatever is true the
    /// INSTANT it actually posts. The label VALUE, however, is now fixed at
    /// CAPTURE time (gate-fixes P2, follow-up finding): see `capturedLabel`.
    private struct DevicePostJob {
        let removedGroups: [USBDeviceChangeGrouper.ChangeGroup]
        let addedGroups: [USBDeviceChangeGrouper.ChangeGroup]
        let thunderboltInvolved: Bool
        let singleDeviceBody: (UInt64) -> String?
        /// The cable label ALREADY matched and consumed against
        /// `pendingCableLabelEvent` at CAPTURE time (when this job was
        /// created: `resolveDevicePost`'s "usable label already present"
        /// branch, or `flushHeldDeviceBatch`), never re-evaluated later.
        /// `nil` = no label for this job, either because it was never
        /// eligible at all (reconnects, in-tree-only, feature-unavailable
        /// batches -- structurally not cable-mediated, doesn't change
        /// between capture and fire) or because no matching event existed
        /// at the moment of capture (that's a genuinely different case
        /// from "never eligible", but both read as `nil` here: a job with
        /// no captured label just never gets one, full stop -- a LATER
        /// event, for a DIFFERENT cable, belongs to whichever diff is
        /// eligible for it when it arrives, never to this one).
        ///
        /// Binding at capture time, not fire time, is the fix: fire-time
        /// binding (matching a live global `pendingCableLabelEvent` at the
        /// moment this job finally posts) meant a DIFFERENT cable's event,
        /// arriving while this job sat queued behind the spacing floor,
        /// could overwrite the one global slot and get wrongly attributed
        /// to this job when it finally fired -- the exact "wrong label"
        /// failure class this feature must never produce. Capturing (and
        /// consuming) the match once, at creation, makes that impossible:
        /// a job's label is a value it owns, not a live read of shared
        /// state.
        ///
        /// `var`, not `let` (fix2): a coalescing merge (`mergeIntoTail`)
        /// unconditionally drops this, tail's and the incoming job's alike
        /// -- see design 5 on `coalesced`'s own doc comment.
        var capturedLabel: CapturedLabel?

        // fix2 (device-post queue reconciliation, spec design 1): the exact
        // ingredients `USBDeviceChangeGrouper.diff` and
        // `NotificationDecision.thunderboltInvolved` were computed from.
        // `removedGroups`/`addedGroups`/`thunderboltInvolved` above stay
        // exactly as they always were and are what a NON-coalesced job
        // fires from, unchanged; these are read only by a job that becomes
        // `coalesced`, whose fire-time reconciliation re-derives its delta
        // from them instead of trusting groups precomputed against a
        // baseline that a LATER merged settle has since moved past.
        let previousSnapshots: [USBDeviceChangeGrouper.Snapshot]
        /// `var`: a merge overwrites this with the incoming job's current
        /// side (design 2, "takes the new job's current side... LATEST
        /// wins"). `previousSnapshots` above never changes on a merge: the
        /// tail keeps its OWN baseline throughout.
        var currentSnapshots: [USBDeviceChangeGrouper.Snapshot]
        let previousTBSwitchIDs: Set<Int64>
        var currentTBSwitchIDs: Set<Int64>
        /// rootID to body string. `var`: a merge overwrites this with the
        /// incoming job's map (test 13, "latest body wins").
        var bodyMap: [UInt64: String]

        /// True once this job has absorbed a later settle's data through a
        /// queue merge (design 2: "front AND tail exist... merge the new
        /// job into the tail"). `fireDevicePostJob` checks this FIRST: a
        /// coalesced job ignores `removedGroups`/`addedGroups` above
        /// entirely (design 3) and re-derives its delta from
        /// `previousSnapshots`/`currentSnapshots` at the moment it actually
        /// fires, through `DeviceDiffSequencer.deriveDeviceDelta`, the SAME
        /// pure function `diffDevices` itself calls on every settle -- so
        /// the normal path and the coalesced path can never compute the
        /// delta two different ways.
        var coalesced = false
        /// (rootLocationID, rootName) pairs recorded as REMOVED by any job
        /// folded into this one across the coalesced span (design 4): the
        /// candidate pool for reconnect synthesis when the endpoint-derived
        /// delta comes out empty. Mirrors the identity evidence
        /// `NotificationDecision.isReconnectPair` already requires (same
        /// physical port, same name), just accumulated across more than one
        /// settle instead of read off a single removed/added pair.
        var removedFlapSignatures: Set<FlapSignature> = []
        /// EVERY root identity (removed OR added) observed at each location
        /// anywhere in the coalesced span, tail's own included at first
        /// merge. This is the taint veto's evidence: if a location's
        /// signatures here include more than one distinct `rootName`, a
        /// DIFFERENT device occupied that port partway through the span, so
        /// a "removed" signature there is not safe to read as the same
        /// device returning. See `synthesizedReconnectGroups(for:)`.
        var allObservedSignatures: Set<FlapSignature> = []

        struct CapturedLabel {
            let name: String
            let wasAdded: Bool
        }

        /// A root's physical-port identity, for flap-signature bookkeeping.
        /// Same two fields `NotificationDecision.isReconnectPair` compares
        /// (`rootLocationID`/`rootName`), named for what they mean here.
        struct FlapSignature: Hashable {
            let locationID: UInt32
            let rootName: String
        }
    }

    /// Bounded queue of not-yet-posted `.device` jobs: at most one in-flight
    /// FRONT (index 0, sleeping out the spacing floor or about to fire)
    /// plus one pending reconciliation TAIL (index 1). Never pruned:
    /// flush-never-drop holds, so a job once enqueued always eventually
    /// fires (posting real content, or, for a coalesced job whose delta
    /// resolves to nothing, firing nothing but still being consumed off the
    /// queue). fix2 (device-post queue reconciliation): a strict,
    /// uncoalescing FIFO here could grow unbounded under sustained device
    /// flapping (~1 job enqueued per settle window against ~1 released per
    /// presentation gap), replaying stale notifications long after the
    /// churn ended. `enqueueDevicePost` is what enforces the <= 2 bound
    /// structurally, by merging into the tail instead of appending a third.
    /// See `mergeIntoTail(_:)`.
    private var deviceQueue: [DevicePostJob] = []
    /// Test-observable queue depth, mirroring `isChargerSettlePending`'s own
    /// reasoning for not staying `private`: a sequencer test asserts the
    /// structural <= 2 bound directly, not just inferred from post counts
    /// and timing.
    var deviceQueueDepthForTesting: Int { deviceQueue.count }
    /// Non-nil exactly while a drain task is scheduled (sleeping out the
    /// spacing floor for the job at the front of `deviceQueue`, or about to
    /// fire it). Doubles as the "only one drain task at a time" guard: a
    /// job enqueued while this is non-nil just waits in the array, and
    /// `drainDeviceQueueIfPossible` picks it up once the current task
    /// finishes. This IS the FIFO/serialisation guarantee (gate-fixes
    /// Codex finding 2): nothing can ever start a second, competing drain.
    private var deviceQueueTask: Task<Void, Never>?
    /// Clock-based, exactly like `lastChargerPostTime`: when the last
    /// `.device` post actually went out through `postNotification`, or
    /// `nil` before the first one this app launch. Read by
    /// `drainDeviceQueueIfPossible` to compute the remaining wait before the
    /// NEXT job may fire, and by `postNotification` itself to decide
    /// `previousPostWasRecent` for the delivery directive (gate-fixes fix
    /// 2). Set inside `postNotification`, not here: that's the single place
    /// a `.device` post actually happens, mirroring exactly where
    /// `lastChargerPostTime` is set for the charger side.
    var lastDevicePostTime: ClockType.Instant?

    /// Appends `job` to the queue (or merges it into the tail, once a front
    /// and a tail already exist) and (re)starts the drain if nothing is
    /// currently running. The single entry point every path in this file
    /// that wants to post `.device` content goes through -- there is no
    /// other way for a `.device` notification to reach `postNotification`
    /// any more.
    private func enqueueDevicePost(_ job: DevicePostJob) {
        if deviceQueue.count >= 2 {
            mergeIntoTail(job)
        } else {
            deviceQueue.append(job)
        }
        drainDeviceQueueIfPossible()
    }

    /// fix2 design 2: the queue invariant. A front and a tail both already
    /// exist (`deviceQueue.count >= 2`), so `job` does not get its own
    /// slot: it is folded into the existing tail instead, which absorbs
    /// every further settle until the front finally releases and the tail
    /// becomes the new front.
    ///
    /// The tail keeps its OWN previous side (its baseline, from whenever it
    /// was first created) and takes `job`'s current side, TB-switch set,
    /// and body map -- latest wins, design 1/2. Flap signatures union
    /// (design 4): on the FIRST merge for this tail, its own precomputed
    /// removed/added groups are folded in too (nothing has been recorded
    /// for it before now), and `job`'s groups are folded in on every merge.
    /// Any captured label, on either side, is unconditionally dropped
    /// (design 5): see `DevicePostJob.capturedLabel`'s doc comment for why
    /// a coalesced post is never labelled.
    private func mergeIntoTail(_ job: DevicePostJob) {
        guard var tail = deviceQueue.popLast() else {
            // Defensive: `count >= 2` at the call site guarantees a tail
            // exists. If it somehow doesn't, this job still needs a slot.
            deviceQueue.append(job)
            return
        }
        let firstMergeForThisTail = !tail.coalesced
        tail.coalesced = true

        // Taint evidence, from the SNAPSHOTS, not the groups (Codex P2 fix).
        // `USBDeviceChangeGrouper` folds a changed device beneath a
        // simultaneously changed ancestor: a device that arrives nested
        // under a brand-new parent shows up only in that parent's
        // `memberNames`, never as its own `ChangeGroup` root, so group-based
        // folding alone never learns that device's (location, name) identity
        // at all. Concretely: endpoint has A at location X; an intermediate
        // settle adds a new ancestor H with B nested beneath it, also at X;
        // a later settle returns to A. Groups record A and H, never B, so
        // the taint check below would miss B entirely and let a false
        // "Reconnected: A" through. Snapshot arrays carry every device,
        // nested ones included, which is exactly what the group-based fold
        // loses -- so fold the INTERMEDIATE endpoint about to be
        // overwritten (`tail.currentSnapshots`, still the pre-merge value
        // here) and the incoming job's own previous side, BEFORE overwriting
        // `tail.currentSnapshots` below. `removedFlapSignatures` stays
        // group-based on purpose: removal evidence (what actually LEFT) is
        // exactly what a `ChangeGroup`'s `removed` side already encodes, and
        // the synthesis candidate must still come from an actual departure,
        // not merely "something was here".
        for snapshot in tail.currentSnapshots {
            tail.allObservedSignatures.insert(DevicePostJob.FlapSignature(locationID: snapshot.locationID, rootName: snapshot.name))
        }
        for snapshot in job.previousSnapshots {
            tail.allObservedSignatures.insert(DevicePostJob.FlapSignature(locationID: snapshot.locationID, rootName: snapshot.name))
        }

        tail.currentSnapshots = job.currentSnapshots
        tail.currentTBSwitchIDs = job.currentTBSwitchIDs
        tail.bodyMap = job.bodyMap

        for group in tail.removedGroups + job.removedGroups {
            tail.removedFlapSignatures.insert(DevicePostJob.FlapSignature(locationID: group.rootLocationID, rootName: group.rootName))
        }
        for group in tail.removedGroups + tail.addedGroups + job.removedGroups + job.addedGroups {
            tail.allObservedSignatures.insert(DevicePostJob.FlapSignature(locationID: group.rootLocationID, rootName: group.rootName))
        }

        tail.capturedLabel = nil

        if firstMergeForThisTail {
            log("enqueueDevicePost: device-post queue at its bound (front + tail); coalescing further settles into the tail")
        }
        deviceQueue.append(tail)
    }

    /// Releases the front of `deviceQueue`, respecting the spacing floor
    /// against `lastDevicePostTime`. Two cases:
    ///  - No wait needed (queue was empty long enough, or this is the very
    ///    first `.device` post this launch): fires SYNCHRONOUSLY, inline,
    ///    right here, no `Task` involved. This matters for existing
    ///    behaviour and existing tests: several call sites post a device
    ///    diff and assert on `posted` immediately afterward, with no
    ///    `await` at all, and that has to keep working for the common
    ///    "nothing else has posted recently" case.
    ///  - A wait is needed: schedules exactly one `Task` (guarded by
    ///    `deviceQueueTask == nil`) that sleeps out the remainder, fires the
    ///    front job, then recurses to pick up whatever is next.
    ///
    /// Reuses `NotificationDecision.devicePostDelay`'s pure arithmetic (the
    /// SAME "remainder of the window, or zero" rule `runNowOrDelayForRecentChargerPost`
    /// already uses against `lastChargerPostTime`) rather than duplicating
    /// it: the parameter name reads charger-specific, but the arithmetic
    /// itself is generic (elapsed vs. a window), and this is exactly that
    /// same computation against a different clock reading.
    private func drainDeviceQueueIfPossible() {
        guard deviceQueueTask == nil, !deviceQueue.isEmpty else { return }

        let delay = NotificationDecision.devicePostDelay(
            elapsedSinceLastChargerPost: lastDevicePostTime?.duration(to: clock.now),
            presentationGap: deferredDeviceDiffPresentationGapWindow
        )

        guard delay > .zero else {
            let job = deviceQueue.removeFirst()
            fireDevicePostJob(job)
            drainDeviceQueueIfPossible()
            return
        }

        deviceQueueTask = Task { @MainActor [weak self] in
            guard let clock = self?.clock else { return }
            try? await clock.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.deviceQueueTask = nil
            self.drainDeviceQueueIfPossible()
        }
    }

    /// The ONE place `NotificationDecision.deviceNotificationContents` is
    /// ever called for a `.device` post (gate-fixes fix 1): composition at
    /// FIRE time, not enqueue time. Applies the job's OWN `capturedLabel`
    /// (gate-fixes P2, follow-up finding): the LABEL VALUE was already
    /// decided and consumed at capture time, so this never re-reads the
    /// global `pendingCableLabelEvent` at all -- doing so would reopen the
    /// exact bug capture-time binding closes (a different cable's event,
    /// arriving while this job sat queued, stealing this job's slot).
    ///
    /// Licence nil-guard: the ONE fire-time check that remains, deliberately
    /// (spec design 7). `knownLabelledCables` is read fresh, never cached
    /// from capture time; if it currently reads `nil` (locked), the
    /// captured label is dropped regardless of what it says. This is
    /// correct to keep at fire time (unlike the label match itself): a lock
    /// landing between capture and fire genuinely should erase a label that
    /// was valid when captured, because Notification Centre must never show
    /// Pro-only content once the licence is gone, however briefly.
    ///
    /// Multiple `NotificationContent` entries in one job (a merged
    /// removed+added pair, or similar) post in a plain, UNSPACED loop here,
    /// exactly as before this revision: the spacing floor governs the gap
    /// BETWEEN jobs (settled diffs), never between the several notifications
    /// one job's own composition can produce, which is what lets the
    /// existing removed-before-added stacking-order trick keep working
    /// (the LATER post of the pair is the one macOS actually shows).
    private func fireDevicePostJob(_ job: DevicePostJob) {
        guard job.coalesced else {
            var addedLabel: String?
            var removedLabel: String?
            if let captured = job.capturedLabel, knownLabelledCables != nil {
                if captured.wasAdded {
                    addedLabel = captured.name
                } else {
                    removedLabel = captured.name
                }
            }

            let contents = NotificationDecision.deviceNotificationContents(
                removedGroups: job.removedGroups,
                addedGroups: job.addedGroups,
                thunderboltInvolved: job.thunderboltInvolved,
                addedCableLabel: addedLabel,
                removedCableLabel: removedLabel,
                singleDeviceBody: job.singleDeviceBody
            )
            for content in contents {
                postNotification(category: .device, title: content.title, subtitle: content.subtitle, body: content.body)
            }
            return
        }

        // fix2 design 3: a coalesced job ignores its stored (stale, from
        // whichever settle first created the tail) `removedGroups`/
        // `addedGroups` and reconciles at fire time instead: re-derive the
        // delta from the endpoint snapshots, through the SAME pure function
        // `diffDevices` calls on every ordinary settle, so the two paths
        // can never drift. It must NOT re-enter `resolveDevicePost`'s
        // hold/eligibility logic: a coalesced job is past all of that
        // gating already; this only composes and posts.
        let derivation = Self.deriveDeviceDelta(
            previousSnapshots: job.previousSnapshots,
            currentSnapshots: job.currentSnapshots,
            previousTBSwitchIDs: job.previousTBSwitchIDs,
            currentTBSwitchIDs: job.currentTBSwitchIDs,
            bodyMap: job.bodyMap
        )

        var removedGroups = derivation.removedGroups
        var addedGroups = derivation.addedGroups

        if removedGroups.isEmpty, addedGroups.isEmpty {
            guard let synthesized = synthesizedReconnectGroups(for: job) else {
                // fix2 design 3: nothing to post (absent -> A -> absent, or
                // an empty delta that doesn't clear design 4's synthesis
                // bar). Deliberately does NOT call `postNotification`, so
                // `lastDevicePostTime` is left untouched: the next real job
                // must space against the last ACTUAL post, not against a
                // job that fired nothing.
                log("fireDevicePostJob: coalesced job's endpoint delta is empty and no reconnect qualifies; firing nothing")
                return
            }
            removedGroups = [synthesized.removed]
            addedGroups = [synthesized.added]
        }

        // fix2 design 5: coalesced posts are unlabelled, full stop. A name
        // must never transfer onto a synthesized aggregate: `capturedLabel`
        // carries no root/episode provenance that would let it prove the
        // transition was untouched, and equality of the final groups
        // doesn't prove that either. Already dropped at every merge
        // (`mergeIntoTail`); passing `nil` here too keeps that rule visible
        // at the one place composition actually happens, rather than
        // relying solely on the merge-time drop.
        let contents = NotificationDecision.deviceNotificationContents(
            removedGroups: removedGroups,
            addedGroups: addedGroups,
            thunderboltInvolved: derivation.thunderboltInvolved,
            addedCableLabel: nil,
            removedCableLabel: nil,
            singleDeviceBody: derivation.singleDeviceBody
        )
        for content in contents {
            postNotification(category: .device, title: content.title, subtitle: content.subtitle, body: content.body)
        }
    }

    /// fix2 design 4: a coalesced job whose endpoint-derived delta is empty
    /// may still represent a real drop-and-return the endpoint diff cannot
    /// see (the device's registry id changed across the flap, so the same
    /// physical device reads as two different ids at the two endpoints).
    /// Synthesizes a reconnect pair ONLY on an exact, untainted identity
    /// match; returns `nil` (and logs) on anything less certain, per
    /// Codex's conservative rule: several qualifying signatures never
    /// invent an aggregate presentation or pick an arbitrary root.
    ///
    /// Qualifying (per signature): the SAME (location, name) pair must
    /// appear in BOTH endpoint snapshots (so the device genuinely existed
    /// at that port both before and after the coalesced span) AND be
    /// recorded as removed by some job folded into this one (so something
    /// actually left that port in between -- otherwise there was no flap to
    /// describe at all, just an unrelated pair of endpoints that happen to
    /// match). Untainted: no DIFFERENT `rootName` was ever observed at that
    /// same location anywhere in the span (`allObservedSignatures`) -- the
    /// veto that kills the A -> B -> A false positive, where A's own
    /// removal is real evidence but B's occupancy in between means the
    /// return is not safely "the same device", it is a coincidence of the
    /// endpoint reads matching.
    private func synthesizedReconnectGroups(
        for job: DevicePostJob
    ) -> (removed: USBDeviceChangeGrouper.ChangeGroup, added: USBDeviceChangeGrouper.ChangeGroup)? {
        // The `currentSnapshots` conjunct (belt-and-braces, adversarial
        // fix-round finding): this function only ever runs when the caller
        // has already confirmed the endpoint-derived delta is EMPTY (see
        // `fireDevicePostJob`'s `removedGroups.isEmpty, addedGroups.isEmpty`
        // gate), which the reviewer believes makes this conjunct
        // structurally unreachable-false -- an empty delta already implies
        // every `previousSnapshots` entry has a matching `currentSnapshots`
        // entry by id, so a signature present in `previousSnapshots` should
        // already be present in `currentSnapshots` too. THEORETICAL, not
        // proven (no test isolates this conjunct alone), so it stays as an
        // explicit, conservative check rather than being trimmed on the
        // strength of that reasoning.
        let qualifying = job.removedFlapSignatures.filter { signature in
            job.previousSnapshots.contains { $0.locationID == signature.locationID && $0.name == signature.rootName }
                && job.currentSnapshots.contains { $0.locationID == signature.locationID && $0.name == signature.rootName }
        }

        guard qualifying.count == 1, let signature = qualifying.first else {
            if qualifying.count > 1 {
                log("fireDevicePostJob: \(qualifying.count) reconnect-synthesis signatures qualify; staying silent rather than guessing which root")
            }
            return nil
        }

        let tainted = job.allObservedSignatures.contains {
            $0.locationID == signature.locationID && $0.rootName != signature.rootName
        }
        guard !tainted else {
            log("fireDevicePostJob: reconnect synthesis vetoed; a different device occupied location \(signature.locationID) during the coalesced span")
            return nil
        }

        guard
            let previousDevice = job.previousSnapshots.first(where: { $0.locationID == signature.locationID && $0.name == signature.rootName }),
            let currentDevice = job.currentSnapshots.first(where: { $0.locationID == signature.locationID && $0.name == signature.rootName })
        else { return nil }

        // `ChangeGroup.init` is `internal` to `WhatCableCore` (no public-API
        // change outside this module, spec design 7): build the two
        // single-device groups through `USBDeviceChangeGrouper.diff` itself
        // instead, isolating each side against an empty counterpart so
        // every device in the one-element list reads as changed, regardless
        // of whether `previousDevice.id` and `currentDevice.id` happen to
        // coincide (id equality is exactly what made this delta read as
        // empty at the endpoints in the first place).
        guard
            let removed = USBDeviceChangeGrouper.diff(previous: [previousDevice], current: []).removed.first,
            let added = USBDeviceChangeGrouper.diff(previous: [], current: [currentDevice]).added.first
        else { return nil }

        return (removed: removed, added: added)
    }

    /// Public feed entry point (spec design 2): the app-side shim calls this
    /// on EVERY publish of WhatCableDarwinBackend's PD identity stream
    /// (`pdWatcher.$identities`), after recomputing the folded provider
    /// snapshot. Exists in all builds; for a free/locked build the provider
    /// returns `nil` on every call, so this is an idle no-op there (accepted
    /// cost, spec design 2).
    ///
    /// Updates `knownLabelledCables`, `knownLabelledCablesByPort`,
    /// `knownPortsAwaitingCableIdentity` and `knownHasSavedCables`
    /// UNCONDITIONALLY, independent of any device diff (see
    /// `knownLabelledCables`'s doc comment for why). Also refreshes
    /// `knownChargerCableLabels` (issue #593) for any port that already
    /// holds a charger, so a name resolving after the connect banner still
    /// reaches the disconnect banner, and can COLLAPSE an armed
    /// `chargerCableLabelGraceWindow` early (re-entering `reconcileChargers`
    /// synchronously, from a `defer` so it lands after everything below) the
    /// moment it supplies a name the waiting charger reconcile needs. It
    /// also clears that same map outright on
    /// a nil feed, so a name captured while Pro was unlocked can't survive
    /// a licence lock into a disconnect banner posted while locked; see the
    /// inline comments below for why the refresh is gated the way it is and
    /// why the clear needs no fire-time backstop.
    ///
    /// Computes a `pendingCableLabelEvent` only when both
    /// the OLD and NEW attached maps are non-nil and differ by exactly one
    /// cable ID (`NotificationDecision.cableLabelChange`); a transition
    /// across availability (nil feed -> some, or some -> nil, i.e. a
    /// licence lock or unlock) never itself produces an event; that guard
    /// is what stops a licence change from reading as a cable connecting or
    /// disconnecting.
    ///
    /// `feed` carries `hasSavedCables` alongside the attached map
    /// (`NotificationDecision.CableLabelFeed`'s doc comment): this is the
    /// post-review fix that stops an empty attached map (the normal state
    /// right up until an unattributed cable's e-marker resolves) from being
    /// misread as "no saved cables exist anywhere".
    public func updateLabelledCables(_ feed: NotificationDecision.CableLabelFeed?) {
        // Early collapse of an armed cable-name grace (issue #593): the name
        // this publish just supplied is what the waiting charger reconcile
        // was waiting for, so run it NOW rather than sitting out the rest of
        // the window. This is what keeps the common case (an e-marker
        // resolving a couple of hundred milliseconds after the settle) at
        // roughly its real cost instead of a flat 1.5s on every charger plug.
        //
        // A `defer` at the TOP so it runs LAST, on both exit paths, without
        // the call being duplicated. Two placement constraints, and only the
        // end of the function satisfies both:
        //
        //  1. It has to run AFTER the `known...` assignments below, because
        //     the reconcile it triggers reads `knownLabelledCablesByPort` for
        //     the name and must see THIS publish, not the previous one. Those
        //     assignments are the first thing this function does, so running
        //     last satisfies this just as well as running mid-function did.
        //  2. It has to run AFTER `assignCableLabelEvent(_:)` at the bottom.
        //     `reconcileChargers()` can land a parked device diff on its way
        //     out, and `resolveDevicePost` binds that batch's label from
        //     `pendingCableLabelEvent` as it stands right then. Running the
        //     collapse first meant the landing saw the PREVIOUS publish's
        //     event rather than this one's.
        //
        //     Narrow, and worth being precise about rather than overclaiming.
        //     Most of the time this is inert: an unlabelled port-level batch
        //     HOLDS rather than posting, and `assignCableLabelEvent`'s own
        //     `heldDeviceBatchEpisodeID` branch (which calls
        //     `tryFlushHeldDeviceBatchForPendingEvent()`) then picks the event
        //     up moments later, so the label arrives either way. The case
        //     that genuinely differs is TWO cable-label events arriving while
        //     ONE diff is parked: with the collapse first, the landing
        //     consumes the older event and the newer one is never applied to
        //     it, contradicting this file's own "latest event wins for an
        //     episode" policy (`assignCableLabelEvent` overwrites
        //     unconditionally). `ChargerCableLabelGraceTests`'s
        //     `testTheCollapseRunsAfterTheCableLabelEventIsAssigned` is that
        //     case, and it is the only one that discriminates the two
        //     placements. It also needs the collapse's own reconcile to post
        //     nothing, so it lands the diff synchronously (`.immediate`)
        //     rather than through the presentation gap, which happens when
        //     the charger set vanished between the two grace passes; via the
        //     gap the landing runs in a later task, after the assignment, and
        //     the placement stops mattering.
        //
        //     So: a defensive ordering fix with one demonstrated
        //     discriminating case, not a bug anyone reported. It also removes
        //     a dependency on that unstated hold-then-reassign invariant,
        //     which spans two mechanisms and is not written down anywhere it
        //     would be noticed.
        //
        // WHAT ends the wait, and it is the exact negation of what started
        // it. `reconcileChargers` arms on "unnamed AND unresolved", so this
        // collapses on "named OR resolved":
        //
        //  - NAMED: the saved cable's e-marker resolved and attributed. The
        //    banner gets its name, which is the outcome the grace exists for.
        //  - RESOLVED: the chip answered and produced no name, so the cable
        //    is not saved and no name is ever coming. Waiting out the rest of
        //    the cap would buy nothing. This half matters more than it looks:
        //    an e-marker takes a variable ~2-3s against a 1.5s settle, so
        //    most USB-C charger plugs DO arm the grace, and without this half
        //    every unsaved one paid the full window.
        //
        // Deliberately NOT "no longer in `portsAwaitingCableIdentity`". A
        // port is in neither set while it is not connected, so a flap would
        // read as resolution and end the grace early, posting unnamed a
        // moment before the name arrived. Presence in the resolved set is a
        // positive statement that the chip answered; absence from the
        // awaiting set is not. See `knownPortsWithResolvedCableIdentity`.
        //
        // EVERY waited-on port must be settled, not just one (H3 review
        // fix). A grace can wait on several ports at once, and the reconcile
        // it wakes posts ONE banner covering all of them. Collapsing as soon
        // as any single port settled published that banner while another
        // port's name was still on its way, and a banner already on screen
        // cannot be corrected: `contains(where:)` here lost the second port's
        // name outright. The cap still bounds the wait for the ports that
        // never settle, so `allSatisfy` cannot stall anything.
        //
        // Accepted cost of `allSatisfy`, recorded so it does not read as an
        // oversight (N2 review finding): a waited-on port that is UNPLUGGED
        // mid-grace lands in neither identity set, which is exactly what "not
        // connected" means, so it can never satisfy this and the wait runs to
        // the cap even though everything knowable is known. Deliberate. It is
        // bounded by the cap, needs a multi-port charger event to happen at
        // all, and the alternative (treating absence as settled) is the flap
        // hole `knownPortsWithResolvedCableIdentity` exists to close.
        //
        // A publish that settles no waited-on port changes nothing: the armed
        // task stays and the cap still applies. A nil feed can never collapse
        // either (both reads go through `feed`), so the licence-lock return
        // below is safe.
        defer {
            if !chargerCableLabelGracePortKeys.isEmpty,
               let feed,
               chargerCableLabelGracePortKeys.allSatisfy({ key in
                   feed.attachedLabelledByPort[key] != nil
                       || feed.portsWithResolvedCableIdentity.contains(key)
               }) {
                cancelChargerCableLabelGrace()
                reconcileChargers()
            }
        }

        let previous = knownLabelledCables
        knownLabelledCables = feed?.attachedLabelled
        knownLabelledCablesByPort = feed?.attachedLabelledByPort
        knownPortsAwaitingCableIdentity = feed?.portsAwaitingCableIdentity ?? []
        knownPortsWithResolvedCableIdentity = feed?.portsWithResolvedCableIdentity ?? []
        knownHasSavedCables = feed?.hasSavedCables ?? false

        // Issue #593: refresh the charger path's own name map for ports
        // that already hold a charger, so a name resolving AFTER the
        // connect banner already posted (the e-marker read finishing later
        // than the charger settle) still reaches that charger's eventual
        // disconnect banner.
        //
        // Iterating `knownChargerLabels` rather than the feed's name map is
        // what keeps the load-bearing gate ("a port with no charger on it
        // must never gain an entry here, or a cable plugged into a bare data
        // port today would show a stale name the first time that same port
        // later becomes a charger") while also letting this pass CLEAR a
        // name the feed has positively withdrawn (H4 / F3 review fix). The
        // three-way decision lives in `refreshCapturedCableName`.
        if let byPort = feed?.attachedLabelledByPort {
            for portKey in knownChargerLabels.keys {
                refreshCapturedCableName(
                    forChargerPort: portKey,
                    namesByPort: byPort,
                    resolvedPorts: feed?.portsWithResolvedCableIdentity ?? []
                )
            }
        }

        // A transition across availability (nil feed -> some, or some ->
        // nil, i.e. a licence lock or unlock) never itself produces an
        // event: that guard is what stops a licence change from reading as
        // a cable connecting or disconnecting.
        //
        // P2 fix (adversarial round 2): a nil feed still clears BOTH
        // `pendingCableLabelEvent` and `graceCableLabelEvent` outright,
        // regardless of which episode (if any) owns the former. Episode-
        // close clearing alone is not enough: a lock immediately followed by
        // an unlock, both landing before the OWNING episode ever reaches a
        // terminal path, leaves the pre-lock event sitting there, still
        // correctly owned, ready to be legitimately consumed by that
        // episode once it resolves -- even though the licence was locked in
        // between. `fireDevicePostJob`'s fire-time `knownLabelledCables`
        // nil-guard only protects the WINDOW while still locked; once
        // unlocked again, capture-time binding (this event) can go on to
        // label a post that never should have inherited a pre-lock
        // identity. Clearing outright on every nil feed, on top of episode-
        // close clearing, closes that gap. `graceCableLabelEvent` is
        // cleared here too, for the same reason: it is just as reachable by
        // a quick lock/unlock as the owned slot is.
        //
        // `knownChargerCableLabels` gets the same treatment (issue #593
        // review fix), for the same underlying reason as the two events
        // above: a name captured while Pro was unlocked must not survive a
        // licence lock and reach a banner posted while locked. The
        // reachable path is a charger attached and named, then Pro
        // deactivated (feed goes nil), then the charger unplugged:
        // `reconcileChargers` builds the disconnect line from this map, not
        // the live feed (the live feed has already lost the attribution by
        // disconnect time regardless -- that's the whole reason this map
        // exists), so an unlocked-only name sitting here would leak into a
        // locked build's own notification.
        //
        // Unlike `pendingCableLabelEvent`, this map has no fire-time guard
        // to fall back on, and doesn't need one: there is no queued job
        // reading it later, only `reconcileChargers` reading it
        // synchronously, in the very call that would post the leaked name.
        // Clearing here is therefore the WHOLE fix, not a belt-and-braces
        // layer on top of one. A charger attached before the lock and still
        // attached after it simply reads as unlabelled from this point on,
        // exactly like a charger that was never attributed in the first
        // place; it refills itself normally on the next non-nil feed, same
        // as `knownLabelledCables` and `knownLabelledCablesByPort` above.
        guard let previous, let current = feed?.attachedLabelled else {
            if feed == nil {
                pendingCableLabelEvent = nil
                graceCableLabelEvent = nil
                knownChargerCableLabels = [:]
            }
            return
        }
        guard let change = NotificationDecision.cableLabelChange(previous: previous, current: current) else { return }
        assignCableLabelEvent(change)
    }

    private func snapshot(for device: USBDevice) -> USBDeviceChangeGrouper.Snapshot {
        USBDeviceChangeGrouper.Snapshot(
            id: device.id,
            locationID: device.locationID,
            name: device.productName ?? String(localized: "USB device", bundle: _notificationsLocalizedBundle)
        )
    }

    /// Trailing-edge debounce, mirroring `scheduleDeviceDiff`: keep resetting
    /// the timer while the charger set is still changing, then reconcile
    /// once it settles. This absorbs the flap so a single connect produces a
    /// single notification. Not `private`: mirrors `scheduleDeviceDiff`'s own
    /// non-private access, for the same call-site-exercising reason.
    ///
    /// `current` is unused: it always was. The original signature took the
    /// freshly-published charger list as a parameter purely because it's
    /// what the `WatcherHub.$sources` publisher hands the sink, but the
    /// actual reconcile (`reconcileChargers`, below) re-reads the charger
    /// set fresh via `currentChargerSources` at settle time instead, exactly
    /// as before this move. Kept for signature parity with the original call
    /// site the app-side shim still drives.
    public func diffSources(_ current: [PowerSource]) {
        guard didPrimeBaseline else { return }
        // A raw charger publish is where a new charger event starts, so this
        // is where the one-grace-per-event budget resets (issue #593). Any
        // grace still armed from the previous event is cancelled outright
        // rather than left to fire: the settle task armed just below will
        // reconcile anyway, so letting the old grace also call
        // `reconcileChargers` would only add a second, earlier reconcile of
        // a charger set that is still flapping, which is exactly what the
        // debounce exists to avoid.
        cancelChargerCableLabelGrace()
        chargerCableLabelGraceUsed = false
        // Trailing-edge debounce: keep resetting the timer while the set is
        // still changing, then reconcile once it settles. This absorbs the
        // flap so a single connect produces a single notification.
        chargerSettleTask?.cancel()
        isChargerSettlePending = true
        chargerSettleTask = Task { @MainActor [weak self] in
            guard let clock = self?.clock else { return }
            try? await clock.sleep(for: self?.chargerSettleWindow ?? Self.defaultChargerSettleWindow)
            guard !Task.isCancelled, let self else { return }
            self.isChargerSettlePending = false
            self.reconcileChargers()
        }
    }

    /// Reconcile the current charger ports against the last-notified set, after
    /// the published list has settled. Notify once per charger (port), not once
    /// per power-source entry: a single charger advertises several entries on
    /// the same port (USB-PD, Brick ID, TypeC). See issue #227 follow-up.
    ///
    /// Can run TWICE for one charger event (issue #593). The first pass
    /// returns early, having mutated nothing and posted nothing, if an added
    /// port has no saved cable name yet and one could still arrive; the
    /// second, triggered either by an early collapse in
    /// `updateLabelledCables(_:)` or by `chargerCableLabelGraceWindow`
    /// expiring, proceeds and posts whether or not a name turned up. The
    /// grace is spent once per charger event, reset in `diffSources(_:)`.
    func reconcileChargers() {
        // Lands any device diff waiting on this reconcile (stack-order fix),
        // whichever exit path is taken below, and AFTER every charger post
        // below has already gone out, so the device post that follows always
        // lands on top. `chargerPostedContent` starts false and is flipped
        // just before the posting loop runs; the closure reads whatever
        // value it holds at the moment this function actually returns, not
        // the value at the point `defer` was written, which is how it sees
        // "did THIS call post anything" even though the decision is made
        // deep inside this function. A no-op when nothing is deferred, and
        // immediate (no presentation gap) when nothing was posted: see
        // `landDeferredDeviceDiff(token:afterChargerPost:)`.
        //
        // Gated on `passCompleted` (issue #593): the cable-name grace return
        // below exits this function WITHOUT having reconciled anything, and
        // landing a parked device diff there would put the device banner
        // ahead of the charger banner this pass is still waiting to post,
        // inverting the ordering the whole park machinery exists to enforce.
        // The grace return is the ONLY exit that leaves this false; every
        // other return (including the `notifyOnChanges()` one) has finished
        // its charger work and must land the diff exactly as before.
        var chargerPostedContent = false
        var passCompleted = false
        defer {
            if passCompleted {
                landDeferredDeviceDiff(token: deferredDeviceDiffToken, afterChargerPost: chargerPostedContent)
            }
        }

        let current = currentChargerSources()
        // Track chargers by `portKey` (see `chargerLabels(for:)`), so a
        // physical port keeps one stable identity here even when its source
        // nodes' UUID walks disagree or flicker between passes.
        let currentLabels = chargerLabels(for: current)
        let addedPortKeys = Set(currentLabels.keys).subtracting(knownChargerLabels.keys)
        let removedPortKeys = knownChargerLabels.keys.filter { !currentLabels.keys.contains($0) }

        // Issue #593: a USB-C cable's e-marker can resolve a second or two
        // after the port reports connected, which is LATER than the 1.5s
        // charger settle, so an added port can legitimately have no saved
        // name yet at this moment and gain one shortly after. Wait one
        // bounded window for it rather than posting an unnamed banner that
        // can never be corrected.
        //
        // Everything below this point mutates (`knownChargerLabels`,
        // `knownChargerCableLabels`, `lastChargerPostTime`), so the decision
        // has to be made HERE, before any of it: the second pass re-derives
        // `addedPortKeys` from `knownChargerLabels`, and a first pass that
        // had already absorbed the current set into it would hand the second
        // pass an empty added set and post nothing at all. That is a silent
        // total failure, strictly worse than the missing name this fixes.
        //
        // Only the ADDED side ever waits. A removal's name comes from
        // `knownChargerCableLabels`, captured back at connect time, so it is
        // either already there or never coming; waiting could not produce it.
        //
        // `knownHasSavedCables` is what keeps this off every user who has
        // saved no cables at all: for them there is provably no name coming,
        // so the banner posts at the settle window exactly as before.
        //
        // `knownPortsAwaitingCableIdentity` is what keeps it off the OTHER
        // common case, and it is the one that matters for anyone who does
        // have saved cables: a port whose chip has already answered will
        // never gain a name it doesn't have now, so an absent name there
        // means "this cable simply isn't saved", not "the read is still
        // outstanding". Waiting only on ports still awaiting identity is
        // what stops a routine plug of an unsaved cable paying the full
        // window for nothing. See that property's doc comment, including
        // the silent-chip case this still cannot fix.
        if !chargerCableLabelGraceUsed,
           let namesByPort = knownLabelledCablesByPort,
           knownHasSavedCables {
            let unnamedAddedPortKeys = addedPortKeys.filter { key in
                namesByPort[key] == nil && knownPortsAwaitingCableIdentity.contains(key)
            }
            if !unnamedAddedPortKeys.isEmpty {
                armChargerCableLabelGrace(waitingOn: unnamedAddedPortKeys)
                return
            }
        }
        // Past the only early return that skips the reconcile, so the parked
        // device diff must land on this pass's way out however it exits.
        passCompleted = true
        // Whatever grace was armed has served its purpose: this pass is
        // reconciling now. Dropping the task here stops a still-pending one
        // waking later and running a third, pointless reconcile (it would
        // find no added ports and post nothing, but it would still churn the
        // parked-diff landing machinery).
        cancelChargerCableLabelGrace()

        let previousLabels = knownChargerLabels
        knownChargerLabels = currentLabels

        log("reconcileChargers: added=\(addedPortKeys.count) removed=\(removedPortKeys.count)")

        // Cable-name bookkeeping (issue #593), unconditional and BEFORE the
        // `notifyOnChanges()` guard below, same as `knownChargerLabels`
        // just above: a disconnect must still be able to name its cable
        // even if notifications were off for the entire time the charger
        // was attached, so this can't wait behind that guard.
        //
        // `removedLines` reads `knownChargerCableLabels` BEFORE the
        // seed/refresh/drop pass that follows touches it -- a removed
        // port's name lives only in that map by the time it disconnects
        // (the live feed has already lost it), so building this first is
        // what makes the disconnect banner able to name it at all.
        let currentCableNames = knownLabelledCablesByPort ?? [:]
        let removedLines = NotificationDecision.sortedChargerLines(
            for: removedPortKeys, labels: previousLabels, cableNames: knownChargerCableLabels
        )
        // Seeds a newly added port's name and refreshes one that already
        // held a charger (both are just "this port currently has a
        // charger", so one loop covers both).
        for portKey in currentLabels.keys {
            refreshCapturedCableName(
                forChargerPort: portKey,
                namesByPort: currentCableNames,
                resolvedPorts: knownPortsWithResolvedCableIdentity
            )
        }
        // Drop LAST, after `removedLines` already captured whatever name
        // these ports had: a port whose charger went and later comes back
        // with no cable attributed must not inherit the old name.
        for portKey in removedPortKeys {
            knownChargerCableLabels.removeValue(forKey: portKey)
        }

        guard notifyOnChanges() else { return }

        // Every added port key already has a label in currentLabels (it was
        // built from the same set); this fallback only guards a mismatch
        // between the two that should never happen. The same "no number to
        // give you" wording `chargerLabels` uses, rather than a made-up claim.
        var addedLabelsByPortKey = currentLabels
        for portKey in addedPortKeys where addedLabelsByPortKey[portKey] == nil {
            addedLabelsByPortKey[portKey] = String(localized: "Wattage not reported", bundle: _notificationsLocalizedBundle)
        }
        // A plain lookup: both sides are keyed by `portKey` now, and the feed
        // publishes every name under a port's `portKey` as well as its join
        // key, so there is nothing left to alias.
        var addedCableNames: [String: String] = [:]
        for portKey in addedPortKeys {
            if let name = currentCableNames[portKey] { addedCableNames[portKey] = name }
        }
        let addedLines = NotificationDecision.sortedChargerLines(
            for: addedPortKeys, labels: addedLabelsByPortKey, cableNames: addedCableNames
        )
        let contents = NotificationDecision.chargerNotificationContents(added: addedLines, removed: removedLines)
        chargerPostedContent = !contents.isEmpty
        for content in contents {
            postNotification(category: .charger, title: content.title, subtitle: content.subtitle, body: content.body)
        }
    }

    /// Updates `knownChargerCableLabels` for ONE port that currently holds a
    /// charger. Three outcomes, and telling the middle one from the last is
    /// the whole point (H4 / F3 review fix):
    ///
    ///  - the feed names it: capture the name.
    ///  - the feed says the port is RESOLVED and does not name it: the chip
    ///    answered and no name applies, so clear any name captured earlier.
    ///    This is what stops a deleted saved cable, or a cable swapped for an
    ///    unsaved one inside the charger debounce, from still naming the
    ///    eventual disconnect banner.
    ///  - neither: a momentary feed gap (the port is in NEITHER identity set,
    ///    so it is not connected right now, or there is no feed at all). Hold
    ///    whatever was captured before rather than dropping a good name over
    ///    a flap.
    ///
    /// Before this fix the map was write-only while a charger stayed
    /// attached, so the second case fell into the third and the stale name
    /// survived. The identity partition is what makes the two separable at
    /// all; see `knownPortsWithResolvedCableIdentity`.
    ///
    /// No "is the feed available" parameter, deliberately. An earlier draft
    /// had one, guarding the clear against a nil feed; removing it left the
    /// whole suite green, because it could never change an outcome:
    /// `knownPortsWithResolvedCableIdentity` is emptied on a nil feed (see
    /// its own doc comment), so the membership test below is already false in
    /// exactly the case that guard claimed to cover. A guard that cannot fail
    /// is worse than no guard, because it advertises protection it does not
    /// provide, so the availability contract stays where it is enforced: on
    /// the property. That contract had no test of its own when this reasoning
    /// was first written down (N3 review finding, and the same pattern the
    /// guard above was deleted for); it is pinned now by
    /// `ChargerCapturedCableNameTests.testANilFeedEmptiesBothIdentitySets`.
    private func refreshCapturedCableName(
        forChargerPort portKey: String,
        namesByPort: [String: String],
        resolvedPorts: Set<String>
    ) {
        if let name = namesByPort[portKey] {
            knownChargerCableLabels[portKey] = name
            return
        }
        if resolvedPorts.contains(portKey) {
            knownChargerCableLabels.removeValue(forKey: portKey)
        }
    }

    /// Arms the one-shot cable-name grace for `portKeys` (issue #593), the
    /// added ports that gained a charger with no saved name yet, and marks
    /// the budget spent so the reconcile this eventually triggers proceeds
    /// and posts whether or not a name turned up.
    ///
    /// Two things can end the wait, and both call `reconcileChargers()`
    /// again: this task's own expiry (the cap), and an early collapse from
    /// `updateLabelledCables(_:)` once a feed publish has resolved EVERY port
    /// in `portKeys` (the common case, and the reason a plug whose cable IS
    /// saved doesn't sit out the whole window).
    ///
    /// Cancel-then-bump-generation before scheduling, mirroring
    /// `scheduleGapLanding`: a superseded task must be unable to touch shared
    /// state, by construction rather than by relying on `.cancel()` having
    /// been observed.
    private func armChargerCableLabelGrace(waitingOn portKeys: Set<String>) {
        chargerCableLabelGraceTask?.cancel()
        chargerCableLabelGraceGeneration += 1
        let generation = chargerCableLabelGraceGeneration
        chargerCableLabelGraceUsed = true
        chargerCableLabelGracePortKeys = portKeys
        log("reconcileChargers: waiting \(Self.chargerCableLabelGraceWindow) for cable names on \(portKeys.count) port(s)")
        chargerCableLabelGraceTask = Task { @MainActor [weak self] in
            guard let clock = self?.clock else { return }
            try? await clock.sleep(for: Self.chargerCableLabelGraceWindow)
            guard !Task.isCancelled,
                  let self,
                  generation == self.chargerCableLabelGraceGeneration
            else { return }
            self.chargerCableLabelGracePortKeys = []
            self.chargerCableLabelGraceTask = nil
            // `chargerCableLabelGraceUsed` stays true: this reconcile is the
            // second pass, and it must post rather than wait again.
            self.reconcileChargers()
        }
    }

    /// Drops any armed cable-name grace without reconciling. Deliberately
    /// does NOT touch `chargerCableLabelGraceUsed`: that budget belongs to
    /// the charger EVENT and is reset only in `diffSources(_:)`, where a new
    /// event starts. Bumping the generation is what stops an already-sleeping
    /// task from doing anything when it wakes, even if the `.cancel()` above
    /// isn't observed.
    private func cancelChargerCableLabelGrace() {
        chargerCableLabelGraceTask?.cancel()
        chargerCableLabelGraceTask = nil
        chargerCableLabelGraceGeneration += 1
        chargerCableLabelGracePortKeys = []
    }

    /// The current wattage label per charger port, used both to prime the
    /// baseline and to recall what a charger was delivering once it
    /// disconnects (its `PowerSource` is already gone by then).
    ///
    /// A winning PD contract is the measurement, so it labels first and is
    /// the only case allowed to say "negotiated". Without one, this defers to
    /// `ChargerWattageSource.resolve`, the same resolution the port summary
    /// uses, so a third-party MagSafe brick that only ever publishes a junk
    /// Brick ID source still reports the system adapter's wattage (issue #592
    /// on the #154 divert). When nothing resolves to a number the label says
    /// so in words: a body-less banner cannot say WHICH port changed when
    /// several are involved, and every port keeps a dictionary entry either
    /// way so add/remove diffing is unaffected.
    private func chargerLabels(for sources: [PowerSource]) -> [String: String] {
        let ports = currentPorts()
        let activePortCount = ports.filter { $0.connectionActive == true }.count
        let chargerSourceCount = ChargerWattageSource.chargerSourceCount(ports: ports, sources: sources)
        let adapter = currentAdapter()
        let unreported = String(localized: "Wattage not reported", bundle: _notificationsLocalizedBundle)
        // Grouped by `portKey` (type/number), NOT `canonicalJoinKey`. Sibling
        // source nodes on one physical port ("USB-PD" + "Brick ID", the shape
        // 95% of corpus charging ports have) each walk the registry for their
        // own HPM UUID. If one walk succeeds while the other fails, their
        // canonical keys differ and one physical port becomes two dictionary
        // entries: two banner lines for one cable, a name that lands on
        // whichever of them the race picked, and a UUID walk that flips
        // between passes reading as a disconnect plus a reconnect. `portKey`
        // is identical for siblings by construction. Mirrors
        // `ChargingInputResolver`, which groups the same way for the same
        // reason (`ChargingInputResolverTests.mixedUUIDSiblingsAreOneInput`).
        //
        // Nothing downstream needs the UUID here: `NotificationCableLabelProvider`
        // publishes every name and identity-set membership under BOTH a port's
        // join key and its `portKey`, so a plain `portKey` lookup always hits.
        return Dictionary(grouping: sources, by: \.portKey).mapValues { portSources -> String in
            let preferred = PowerSource.preferredChargingSource(in: portSources) ?? portSources.first
            if let winning = preferred?.winning {
                return String(localized: "\(winning.wattsLabel) negotiated", bundle: _notificationsLocalizedBundle)
            }
            let resolved = ChargerWattageSource.resolve(
                portSources: portSources,
                activePortCount: activePortCount,
                chargerSourceCount: chargerSourceCount,
                adapter: adapter
            )
            // A Brick ID node's wattage is a placeholder, so suppress it when
            // the adapter divert declined and resolve fell back to it.
            if ChargerWattageSource.isUnquantifiedBrickID(portSources: portSources, resolved: resolved) {
                return unreported
            }
            switch resolved {
            case .systemAdapterFallback(let watts):
                // macOS's own reading of the adapter, so it is a measurement:
                // same wording `PortSummary` uses for this case.
                return String(localized: "System reports charger at \(watts)W", bundle: _notificationsLocalizedBundle)
            case .portNegotiated(let watts):
                // The source's own advertised maximum, not a settled contract,
                // so this must never read as negotiated.
                return String(localized: "Charger advertises up to \(watts)W", bundle: _notificationsLocalizedBundle)
            case .unknown:
                return unreported
            }
        }
    }

    /// The single place ANY notification actually leaves this module,
    /// charger or device. Owns two related pieces of bookkeeping, both
    /// read BEFORE being overwritten so they describe "the previous post
    /// in this category", never this one:
    ///  - `lastChargerPostTime` / `lastDevicePostTime`: when the previous
    ///    same-category post went out, so `devicePostDelay` /
    ///    `drainDeviceQueueIfPossible` can space the NEXT one out.
    ///  - `previousPostWasRecent` (gate-fixes fix 2): whether that previous
    ///    post is recent enough it might still be PENDING rather than
    ///    delivered, threaded into the ledger so the delivery directive
    ///    knows whether to also clear a pending request. With the device-
    ///    post spacing floor (fix 1) guaranteeing `.device` posts are
    ///    normally >= one window apart, this is normally `false` for
    ///    device; the case it stays `true` for is two posts from the SAME
    ///    job firing back-to-back inside `fireDevicePostJob`'s loop (there,
    ///    `lastDevicePostTime` was JUST set by the first of the pair,
    ///    moments before this call), which is exactly the case that still
    ///    needs both lists populated.
    private func postNotification(category: NotificationCategory, title: String, subtitle: String = "", body: String) {
        let elapsedSincePreviousPost: Duration? = {
            switch category {
            case .charger: return lastChargerPostTime?.duration(to: clock.now)
            case .device: return lastDevicePostTime?.duration(to: clock.now)
            }
        }()
        let previousPostWasRecent = elapsedSincePreviousPost.map { $0 < deferredDeviceDiffPresentationGapWindow } ?? false

        // Both-orders fix: see `lastChargerPostTime`'s doc comment.
        switch category {
        case .charger: lastChargerPostTime = clock.now
        case .device: lastDevicePostTime = clock.now
        }

        let directive = deliveryLedger.nextDirective(for: category, previousPostWasRecent: previousPostWasRecent)
        post(category, NotificationContent(title: title, subtitle: subtitle, body: body), directive)
    }
}
