import SwiftUI
import WhatCableCore
import WhatCableDarwinBackend

/// Identity key for the generation-scoped settling card. Given to `.id(...)`
/// by `ContentView.mainContent`'s `ForEach`, so a genuine new connection
/// generation on the same port destroys and recreates the whole
/// `SettlingPortCardHost` (spec: "State identity across a generation change
/// belongs to the (portID, generation)-keyed subview: the old machine is
/// discarded whole").
struct SettlingCardIdentity: Hashable {
    let portID: UInt64
    let generation: Int?
}

/// Hosts one settling-card presentation machine
/// (`SettlingCardPhase`/`SettlingCardReducer`, Task 2), scoped to one
/// `(portID, sessionGeneration)` by this view's own identity (see
/// `SettlingCardIdentity`, applied by the caller via `.id(...)`).
///
/// Owns: the starting phase (computed via `SettlingCardReplacement
/// .startingPhase`/`SettlingCardTrigger` at construction, exactly like a
/// fresh mount — NEVER hardcoded to `.loading`), the generation-scoped
/// deadline task, the `sessionEnded` feed from the parent's authoritative
/// visibility verdict, and the fade/retain choreography. Mirrors
/// `PortCard`'s full parameter list so it can forward everything unchanged
/// once the machine reaches `.settled`.
struct SettlingPortCardHost: View {
    // Same fields `PortCard` takes, forwarded verbatim when the content
    // plan says `.liveBody`.
    let port: AppleHPMInterface
    let devices: [USBDevice]
    var tunnelledDevices: [USBDevice] = []
    var structuralTunnelledDevices: [USBDevice] = []
    let powerSources: [PowerSource]
    let identities: [USBPDSOP]
    let thunderboltSwitches: [IOThunderboltSwitch]
    let usb3Transports: [USB3Transport]
    var trmTransports: [TRMTransport] = []
    let isLive: Bool
    let showAdvanced: Bool
    let cioCapability: CIOCableCapability?
    /// Apple's own name for what is attached, from the port's UVDM node.
    let accessoryIdentity: AppleAccessoryIdentity?
    let displayPorts: [IOPortTransportStateDisplayPort]
    let chargerWattageSource: ChargerWattageSource
    let batteryFullyCharged: Bool?
    let batteryIsCharging: Bool?
    let adapter: AdapterInfo?
    var anotherPortActivelyCharging: Bool = false
    var connectionDiagnostic: ConnectionDiagnostic? = nil
    var federatedIdentities: [FederatedIdentity] = []
    var connectionAttachInstant: TimeInterval?
    var connectionSessionGeneration: Int?

    // Settling-card-specific inputs (Task 3). Unrelated to the two fields
    // above: `connectionAttachInstant`/`connectionSessionGeneration` still
    // feed `PortCard`'s own "Reading cable details..." per-line wording
    // (PR #578), independent of this spinner-first machine.
    /// The RETAINED attach instant
    /// (`AppleHPMInterfaceWatcher.connectionRetainedAttachInstant(for:)`),
    /// which survives a transient inactive interval unlike
    /// `connectionAttachInstant`. Feeds the trigger and the deadline
    /// arithmetic only.
    let retainedAttachInstant: TimeInterval?
    /// The authoritative visibility verdict for THIS port, already resolved
    /// by the caller via `SettlingCardVisibilityResolver` (never the raw
    /// optional lookup, and never defaulted to "transient/fading" on a nil
    /// lookup — see that type's doc comment).
    let settlingVisibility: SettlingCardVisibility

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The session generation this machine is scoped to, for the reducer's
    /// `deadlineReached(generation:)` check. Falls back to 0 when unknown;
    /// safe because an unknown generation implies an unknown
    /// `retainedAttachInstant` too (both come from the same
    /// `PortConnectionSessionTracker` record), which already forces the
    /// trigger to `.settled` and keeps the deadline task from ever arming.
    private var generation: Int { connectionSessionGeneration ?? 0 }

    /// The port label, SNAPSHOTTED at machine creation (spec: "Placeholder
    /// invariance": "the port label SNAPSHOTTED AT MACHINE CREATION (raw
    /// port name, not summary.headline)"). `@State`, per-branch-review
    /// finding (round 2, Codex gate, finding 2): a plain `let` is NOT
    /// actually frozen here. `.id(SettlingCardIdentity(...))` at the
    /// `ContentView` call site preserves `@State` STORAGE across a
    /// reconstruction with the same identity, but a plain stored property
    /// is baked fresh into the View struct on every re-render regardless of
    /// identity, so any watcher publication while `.loading` (a value in
    /// `port` changing, which flows down as a NEW `SettlingPortCardHost`
    /// value even though SwiftUI treats it as "the same" view for `@State`
    /// purposes) would have recomputed this from the CURRENT `port`, not
    /// the one at machine creation. `@State` is what actually freezes it.
    @State private var snapshottedPortLabel: String

    @State private var phase: SettlingCardPhase
    /// Whether this session's machine has ever reached `.settled`, i.e.
    /// whether `.fading` should keep showing the live body or the
    /// placeholder (see `SettlingCardContentPlan`'s doc comment). Set once;
    /// never reset within one machine's lifetime, since `.settled` is
    /// terminal per session and only a new generation (a whole new
    /// `SettlingPortCardHost` instance, per `SettlingCardIdentity`) starts
    /// fresh.
    @State private var hasRevealed: Bool

    init(
        port: AppleHPMInterface,
        devices: [USBDevice],
        tunnelledDevices: [USBDevice] = [],
        structuralTunnelledDevices: [USBDevice] = [],
        powerSources: [PowerSource],
        identities: [USBPDSOP],
        thunderboltSwitches: [IOThunderboltSwitch],
        usb3Transports: [USB3Transport],
        trmTransports: [TRMTransport] = [],
        isLive: Bool,
        showAdvanced: Bool,
        cioCapability: CIOCableCapability?,
        accessoryIdentity: AppleAccessoryIdentity?,
        displayPorts: [IOPortTransportStateDisplayPort],
        chargerWattageSource: ChargerWattageSource,
        batteryFullyCharged: Bool?,
        batteryIsCharging: Bool?,
        adapter: AdapterInfo?,
        anotherPortActivelyCharging: Bool = false,
        connectionDiagnostic: ConnectionDiagnostic? = nil,
        federatedIdentities: [FederatedIdentity] = [],
        connectionAttachInstant: TimeInterval?,
        connectionSessionGeneration: Int?,
        retainedAttachInstant: TimeInterval?,
        settlingVisibility: SettlingCardVisibility
    ) {
        self.port = port
        self.devices = devices
        self.tunnelledDevices = tunnelledDevices
        self.structuralTunnelledDevices = structuralTunnelledDevices
        self.powerSources = powerSources
        self.identities = identities
        self.thunderboltSwitches = thunderboltSwitches
        self.usb3Transports = usb3Transports
        self.trmTransports = trmTransports
        self.isLive = isLive
        self.showAdvanced = showAdvanced
        self.cioCapability = cioCapability
        self.accessoryIdentity = accessoryIdentity
        self.displayPorts = displayPorts
        self.chargerWattageSource = chargerWattageSource
        self.batteryFullyCharged = batteryFullyCharged
        self.batteryIsCharging = batteryIsCharging
        self.adapter = adapter
        self.anotherPortActivelyCharging = anotherPortActivelyCharging
        self.connectionDiagnostic = connectionDiagnostic
        self.federatedIdentities = federatedIdentities
        self.connectionAttachInstant = connectionAttachInstant
        self.connectionSessionGeneration = connectionSessionGeneration
        self.retainedAttachInstant = retainedAttachInstant
        self.settlingVisibility = settlingVisibility

        // `State(initialValue:)`, exactly like `_phase`/`_hasRevealed` below:
        // this is the ONE place the label is ever computed. A later
        // re-render of a view SwiftUI considers "the same" (same `.id(...)`)
        // reuses the existing `@State` storage and does NOT re-run this
        // initializer, which is what actually freezes the label (see the
        // property's doc comment).
        _snapshottedPortLabel = State(initialValue: Self.snapshotLabel(for: port))

        // The starting phase, computed exactly as a fresh mount would
        // (`SettlingCardReplacement.startingPhase` is a thin pass-through to
        // `SettlingCardTrigger.evaluate`). This is the ONE call site for
        // that decision: a genuine new generation gets here through this
        // same `init`, via `.id(SettlingCardIdentity(...))` at the call
        // site tearing down the old instance and creating a new one, never
        // through a transition applied to the old machine.
        let startPhase = SettlingCardReplacement.startingPhase(for: SettlingCardTriggerInput(
            retainedAttachInstant: retainedAttachInstant,
            now: Self.monotonicNow(),
            window: PortSummary.emarkerReadWindow,
            isMagSafe: port.portTypeDescription?.hasPrefix("MagSafe") == true,
            visibility: settlingVisibility
        ))
        _phase = State(initialValue: startPhase)
        _hasRevealed = State(initialValue: startPhase == .settled)
    }

    /// Same monotonic clock as `AppleHPMInterfaceWatcher`'s
    /// `PortConnectionSessionTracker` and `PortCard`'s own
    /// `monotonicNow()`: `DispatchTime`'s `uptimeNanoseconds`, unaffected by
    /// wall-clock jumps.
    private static func monotonicNow() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    /// The formula behind `snapshottedPortLabel`: raw port name, `PortCard`'s
    /// own `port.portDescription ?? port.serviceName` (see its header row),
    /// never `summary.headline`. Exposed as an `internal` static function
    /// (rather than inlined into `init`) so it has a pure, SwiftUI-free unit
    /// test: the FREEZE itself is Swift's own `let` semantics (assigned once
    /// in `init`, never reassigned), which needs no test; this formula's
    /// correctness does.
    static func snapshotLabel(for port: AppleHPMInterface) -> String {
        port.portDescription ?? port.serviceName
    }

    private var contentPlan: SettlingCardContentPlan {
        SettlingCardContentPlan.plan(phase: phase, hasRevealed: hasRevealed)
    }

    /// Identity for the deadline `.task(id:)` below (per-branch-review
    /// finding, round 2, Codex gate, finding 1). Changing ANY of these three
    /// fields cancels a currently-sleeping deadline task and relaunches a
    /// fresh one (which immediately no-ops if the new state isn't armed, see
    /// `SettlingCardDeadlineArming`): `generation` is redundant with the
    /// outer `.id(SettlingCardIdentity(...))` (a generation change tears
    /// down this whole view already) but included per the review finding's
    /// exact wording, defence in depth; `phase` and `visibilityEnded` are
    /// what actually close the race, since a `sessionEnded` arriving
    /// mid-sleep now cancels the old task as part of the SAME view update
    /// that processes it, instead of leaving the old task to wake
    /// unbothered and race the `onChange` handler for who gets to `send`
    /// first.
    private struct DeadlineTaskID: Equatable {
        let generation: Int
        let phase: SettlingCardPhase
        let visibilityEnded: Bool
    }

    private var deadlineTaskID: DeadlineTaskID {
        DeadlineTaskID(generation: generation, phase: phase, visibilityEnded: settlingVisibility == .ended)
    }

    /// Applies a `SettlingCardEvent` to the reducer and, if it actually
    /// moves the phase, wraps the mutation in an explicit, narrowly scoped
    /// animation transaction (spec: "Explicit, narrowly scoped animation
    /// transactions ... no global animation on watcher-driven values" — this
    /// is that scoping: only the specific mutation this call makes
    /// animates, never a blanket `.animation(_, value: phase)` that would
    /// also fire on unrelated re-renders). `completion` runs once the
    /// animation finishes (macOS 14's `withAnimation(_:completionCriteria
    /// :body:completion:)`), used to chain `fadeCompleted` after the exit
    /// animation plays out.
    private func send(_ event: SettlingCardEvent, completion: (() -> Void)? = nil) {
        let next = SettlingCardReducer.reduce(phase: phase, event: event, generation: generation)
        guard next != phase else { return }
        withAnimation(CardMotion.animation(reduceMotion: reduceMotion), completionCriteria: .logicallyComplete) {
            phase = next
            if next == .settled { hasRevealed = true }
        } completion: {
            completion?()
        }
    }

    /// The one call site for `fadeCompleted(parentRetainsCard: true)`, used
    /// by both entry paths into `.retained` (the normal `onChange`-driven
    /// path and the round-2 watchdog task). Round 4: no longer chains a
    /// recovery check onto this send's animation completion (see
    /// `.onChange(of: phase)` below and `SettlingCardPhaseEntryRecovery`'s
    /// doc comment for why that check moved there). This function now does
    /// exactly what its name says: sends `fadeCompleted`, nothing else.
    private func sendFadeCompleted() {
        send(.fadeCompleted(parentRetainsCard: true))
    }

    var body: some View {
        Group {
            switch contentPlan {
            case .placeholder:
                SettlingCardPlaceholder(portLabel: snapshottedPortLabel)
            case .liveBody:
                PortCard(
                    port: port,
                    devices: devices,
                    tunnelledDevices: tunnelledDevices,
                    structuralTunnelledDevices: structuralTunnelledDevices,
                    powerSources: powerSources,
                    identities: identities,
                    thunderboltSwitches: thunderboltSwitches,
                    usb3Transports: usb3Transports,
                    trmTransports: trmTransports,
                    isLive: isLive,
                    showAdvanced: showAdvanced,
                    cioCapability: cioCapability,
                    accessoryIdentity: accessoryIdentity,
                    displayPorts: displayPorts,
                    chargerWattageSource: chargerWattageSource,
                    batteryFullyCharged: batteryFullyCharged,
                    batteryIsCharging: batteryIsCharging,
                    adapter: adapter,
                    anotherPortActivelyCharging: anotherPortActivelyCharging,
                    connectionDiagnostic: connectionDiagnostic,
                    federatedIdentities: federatedIdentities,
                    connectionAttachInstant: connectionAttachInstant,
                    connectionSessionGeneration: connectionSessionGeneration
                )
            case .retained:
                // The real disconnected card (owner ruling, issue #585, task
                // 1): every session-derived input is suppressed so this is
                // structurally the SAME card a launch-time empty port
                // renders (`PortCard`'s own `summary` falls back to
                // "Nothing connected" once `devices`/`powerSources`/
                // `identities` are all empty and `isLive` is false, exactly
                // like `ContentView.nothingConnectedState`), not a
                // hand-maintained lookalike that can drift from it. Fixes
                // the bug where `.retained` (a PERMANENT steady state for a
                // visible empty port, see the doc comment above) rendered a
                // minimal placeholder forever instead: no Diagnostics
                // button, no technical-details toggle, nothing the real
                // disconnected card offers.
                PortCard(
                    port: port,
                    devices: [],
                    tunnelledDevices: [],
                    structuralTunnelledDevices: [],
                    powerSources: [],
                    identities: [],
                    thunderboltSwitches: [],
                    usb3Transports: [],
                    trmTransports: [],
                    isLive: false,
                    showAdvanced: showAdvanced,
                    cioCapability: nil,
                    accessoryIdentity: nil,
                    displayPorts: [],
                    chargerWattageSource: .unknown,
                    batteryFullyCharged: nil,
                    batteryIsCharging: nil,
                    adapter: nil,
                    anotherPortActivelyCharging: false,
                    connectionDiagnostic: nil,
                    federatedIdentities: [],
                    connectionAttachInstant: nil,
                    connectionSessionGeneration: nil
                )
            }
        }
        .transition(CardMotion.reveal(reduceMotion: reduceMotion))
        // ONE opacity value, from ONE function (`SettlingCardOpacity
        // .effectiveOpacity`), combining what used to be two independent
        // things: the parent's `.fading`-vs-not dimming (formerly a
        // separate `.opacity(...)` modifier on this row at the `ContentView`
        // call site) and this card's own internal exit fade. Per-task-review
        // finding (round 1, critical): two independent transactions matched
        // only by a shared duration could skew relative to each other and
        // momentarily show old live content BRIGHTER than the `.fading`
        // dimmed value. Reading both `settlingVisibility` and `phase` here,
        // in one place, in the same render, removes the skew entirely: see
        // `SettlingCardOpacity`'s doc comment for why the result is
        // structurally capped rather than merely "usually in time".
        //
        // Also serves the card's own internal exit choreography: `.fading`
        // maps to fully hidden so nothing lingers, even dimmed, while
        // `.retained` content swaps in underneath; without SOME observable
        // change here the `withAnimation` in `send` would have nothing to
        // animate and its completion would fire immediately instead of
        // after a real fade (`.fading` doesn't change the content plan by
        // itself, see `SettlingCardContentPlan`'s doc comment).
        .opacity(SettlingCardOpacity.effectiveOpacity(visibility: settlingVisibility, phase: phase))
        // Narrowly scoped to this ONE row and this ONE value (per-task-review
        // finding, round 1, important): `settlingVisibility` changes as a
        // plain prop from the parent, not through this view's own `@State`,
        // so without a local animation trigger a churn-driven dimming
        // change (#536) wouldn't animate at all. Explicit `withAnimation`
        // calls in `send` still own the phase-driven transitions (the
        // loading -> body reveal, the exit fade); this only supplies a
        // transaction for the visibility-driven half of the same opacity
        // value, and it can never couple to another port's row, unlike the
        // single shared `portVisibilityStates` dictionary write this used
        // to depend on at the `ContentView` call site.
        .animation(CardMotion.animation(reduceMotion: reduceMotion), value: settlingVisibility)
        // Keyed by `deadlineTaskID` (per-branch-review finding, round 2,
        // Codex gate, finding 1), not a bare `.task { }`. A bare task is
        // only ever cancelled by the WHOLE view tearing down (a real
        // generation change); it is never cancelled by a same-generation
        // `sessionEnded`, so a deadline that happens to fire in the narrow
        // window before `onChange(of: settlingVisibility)` below has run
        // could still see `phase == .loading` and settle, briefly
        // constructing `PortCard` a moment before the fade takes over.
        // Keying on `(generation, phase, visibilityEnded)` makes the SAME
        // view update that flips `settlingVisibility` to `.ended` also
        // cancel any currently-sleeping deadline task, closing that window
        // instead of relying solely on the post-sleep guard to catch it
        // after the fact.
        .task(id: deadlineTaskID) {
            guard SettlingCardDeadlineArming.isArmed(phase: phase, visibility: settlingVisibility),
                  let instant = retainedAttachInstant else { return }
            let remaining = SettlingCardDeadline.remaining(
                retainedAttachInstant: instant,
                window: PortSummary.emarkerReadWindow,
                now: Self.monotonicNow()
            )
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Explicit re-check per spec ("checks BOTH phase and generation
            // before settling ... the task must still guard"), belt and
            // braces alongside the reducer's own generation check inside
            // `send`/`SettlingCardReducer.reduce` AND the `deadlineTaskID`
            // keying above. `.id(SettlingCardIdentity(...))` at the call
            // site already cancels this task outright on a real generation
            // change; this guard is what's left once that and the id-keyed
            // cancellation have both already run.
            guard SettlingCardDeadlineArming.isArmed(phase: phase, visibility: settlingVisibility) else { return }
            send(.deadlineReached(generation: generation))
        }
        // Fading watchdog (adversarial-gate addendum, round 2, finding 4).
        // The normal `.fading -> .retained` path is `withAnimation`'s
        // completion handler in `send`, which depends on Core Animation
        // actually delivering that completion for a view that can be
        // off-screen (the popover's `NSHostingController` is created once
        // and never torn down on close/reopen, per `App.swift`). If that
        // completion is ever dropped, the machine would stick at `.fading`
        // forever with no other event able to move it, and
        // `SettlingCardOpacity` holds it fully invisible the whole time.
        // Keyed on `phase` alone: arms fresh whenever phase BECOMES
        // `.fading`, and is cancelled the instant phase changes away from
        // it for any reason (the normal completion firing, a future event
        // this machine doesn't currently model, or the whole view tearing
        // down).
        .task(id: phase) {
            guard SettlingCardFadeWatchdog.shouldFire(phase: phase) else { return }
            try? await Task.sleep(nanoseconds: UInt64(CardMotion.fadeWatchdogInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // First-delivery-wins: if the normal completion path already
            // ran, `phase` is already `.retained`, this guard fails, and
            // the watchdog no-ops. A duplicate `fadeCompleted` delivery is
            // separately a no-op at the reducer level regardless (Task 2's
            // `retainedIsStickyAgainstEveryReducerEvent`), so this is
            // belt, and the reducer's totality is braces. Calling
            // `sendFadeCompleted()` here mutates `phase` to `.retained`
            // exactly like the normal completion path does, so this path
            // ALSO gets the round-4 phase-entry recovery check below (it
            // fires on `phase` actually becoming `.retained`, regardless of
            // which of the two paths got it there).
            guard SettlingCardFadeWatchdog.shouldFire(phase: phase) else { return }
            sendFadeCompleted()
        }
        .onChange(of: settlingVisibility) { _, newValue in
            switch newValue {
            case .ended:
                send(.sessionEnded) {
                    sendFadeCompleted()
                }
            case .live:
                // Same-generation recovery (owner ruling 2026-08-28, spec:
                // "Parent-owned retention and removal"). `send` itself is a
                // no-op unless `phase` is genuinely `.retained` right now
                // (the reducer's `.sessionResumed` arm is a no-op
                // everywhere else, including mid-`.fading`: "no mid-fade
                // reversal"), so firing this unconditionally on every
                // live-visibility change is safe; it only ever has an
                // effect at the one moment it's meant to. This is the EDGE
                // half of recovery: it catches visibility returning to
                // `.live` at any point OTHER than mid-fade, including while
                // already `.retained`. `.onChange(of: phase)` below is the
                // other half, for when visibility already returned to
                // `.live` mid-fade and there is no LATER visibility edge
                // left for this handler to catch once the fade completes.
                send(.sessionResumed)
            case .transientFadingGrace:
                break
            }
        }
        // Phase-entry recovery (round 4, owner ruling 2026-08-28's
        // "Same-generation recovery", replacing the round-3 design rejected
        // in review; see `SettlingCardPhaseEntryRecovery`'s doc comment for
        // the full history and reasoning). Fires whenever `phase` actually
        // BECOMES `.retained`, regardless of which path got it there (the
        // normal `withAnimation` completion or the fade watchdog), and
        // reads `settlingVisibility` as a plain prop here deliberately, not
        // a mirror: SwiftUI re-registers this closure fresh on every `body`
        // evaluation, so at the instant it fires it closes over the CURRENT
        // committed prop value, not a value captured at some earlier
        // render. This is what makes it safe against both round-3 failure
        // modes at once: it does not depend on an animation completion
        // firing at all (so a dropped `NSHostingController` completion,
        // Core Animation's failure mode for an off-screen popover view,
        // can't strand it), and it never reads stale state (so a session
        // that ended after this fired can't wrongly resurrect: the very
        // next `settlingVisibility` change to `.ended` would itself fire
        // `sessionEnded` through the other `onChange` above, same as any
        // other retained card).
        //
        // This can't be exercised as a unit test: it depends on SwiftUI's
        // own `.onChange(of:)` delivery timing, which is a render-loop
        // guarantee, not something this file's pure-function tests can
        // harness. `SettlingCardPhaseEntryRecovery.shouldRecover(onEntryTo:
        // visibility:)` carries the tested predicate; this call site is the
        // one place it's wired to an actual event.
        .onChange(of: phase) { _, newPhase in
            if SettlingCardPhaseEntryRecovery.shouldRecover(onEntryTo: newPhase, visibility: settlingVisibility) {
                send(.sessionResumed)
            }
        }
    }
}

/// The `.loading` placeholder. Spec: "Placeholder invariance": renders
/// ONLY the snapshotted port label, a fixed neutral icon, and a
/// `ProgressView` with "Reading cable details…" as its accessible label.
/// No summary content, diagnostics, plugin controls, power lines, device
/// rows, or e-marker content.
private struct SettlingCardPlaceholder: View {
    let portLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cable.connector.horizontal")
                .scaledFont(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(portLabel)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Reading cable details…", bundle: _coreLocalizedBundle))
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Reading cable details…", bundle: _coreLocalizedBundle))
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
