import Testing
import WhatCableCore
@testable import WhatCable

/// Tests for the settling-card SwiftUI integration layer (spec:
/// "settling-card", Task 3): the pieces that stay pure and testable without
/// a SwiftUI harness. `SettlingCardContentPlan` (which content a phase
/// constructs), `SettlingCardVisibilityResolver` (the nil-lookup mirror of
/// `ContentView.mainContent`'s fallback), `SettlingCardOpacity` (the single
/// opacity function closing the round-1 flash race), `SettlingCardDeadlineArming`
/// / `SettlingCardFadeWatchdog` (the round-2 task-arming predicates), and
/// `SettlingPortCardHost.snapshotLabel` (the formula behind the frozen
/// placeholder label).
///
/// What can't be expressed here (per the spec's own test list): the actual
/// `ForEach` removal vs. parent-retained rendering split, `.task(id:)`'s
/// real cancellation behaviour on identity change, and animation feel.
/// Those are manual M5 checks.
///
/// House rule: every test here was watched failing first, against a
/// deliberate one-line mutation of the rule it guards, then restored.
@Suite("Settling card SwiftUI integration (Task 3)")
struct SettlingCardIntegrationTests {

    // MARK: - Content plan

    /// `.loading` and `.retained` are the two phases the spec requires never
    /// construct live-input content; this pins both to their content-free
    /// plan cases regardless of `hasRevealed`.
    ///
    /// Mutation watched failing: changed the `.retained` arm to `return
    /// hasRevealed ? .liveBody : .retained`. Went red on
    /// `retainedNeverPlansLiveBodyRegardlessOfHasRevealed` below (a
    /// `.retained` card that HAD revealed before disconnecting would then
    /// plan `.liveBody`, exactly the "old live card revealed" bug the spec's
    /// caution warns about); restored.
    @Test("Loading always plans the content-free placeholder")
    func loadingAlwaysPlansPlaceholder() {
        #expect(SettlingCardContentPlan.plan(phase: .loading, hasRevealed: false) == .placeholder)
        #expect(SettlingCardContentPlan.plan(phase: .loading, hasRevealed: true) == .placeholder)
    }

    @Test("Retained never plans the live body, regardless of hasRevealed")
    func retainedNeverPlansLiveBodyRegardlessOfHasRevealed() {
        #expect(SettlingCardContentPlan.plan(phase: .retained, hasRevealed: false) == .retained)
        #expect(SettlingCardContentPlan.plan(phase: .retained, hasRevealed: true) == .retained)
    }

    /// `.settled` is the one phase the spec says DOES construct the live
    /// body.
    @Test("Settled plans the live body")
    func settledPlansLiveBody() {
        #expect(SettlingCardContentPlan.plan(phase: .settled, hasRevealed: true) == .liveBody)
    }

    /// `.fading` keeps showing whatever was already up (spec: the exit
    /// motion plays over the CURRENT content, not a fresh one) rather than
    /// switching content early.
    ///
    /// Mutation watched failing: changed the `.fading` arm to always
    /// `return .placeholder`. Went red on
    /// `fadingKeepsShowingTheLiveBodyWhenAlreadyRevealed` below (a card that
    /// disconnects AFTER reveal would flash back to the spinner while
    /// fading, instead of fading its own live body out); restored.
    @Test("Fading before any reveal keeps showing the placeholder")
    func fadingBeforeRevealKeepsShowingPlaceholder() {
        #expect(SettlingCardContentPlan.plan(phase: .fading, hasRevealed: false) == .placeholder)
    }

    @Test("Fading after a reveal keeps showing the live body")
    func fadingKeepsShowingTheLiveBodyWhenAlreadyRevealed() {
        #expect(SettlingCardContentPlan.plan(phase: .fading, hasRevealed: true) == .liveBody)
    }

    // MARK: - Visibility resolution

    /// The spec's "Implementation cautions" hole: a nil lookup (the very
    /// first frame) must resolve via the immediate liveness signal, never to
    /// `.transientFadingGrace`.
    ///
    /// Mutation watched failing: changed the `nil` arm to `return
    /// .transientFadingGrace` unconditionally. Went red on both cases below
    /// (a dead session with a young retained instant would then be allowed
    /// to spinner, which is exactly the dead-session hole the spec's Trigger
    /// section closes); restored.
    @Test("A nil lookup with the port live now resolves to .live, never .transientFadingGrace")
    func nilLookupLiveResolvesToLive() {
        #expect(SettlingCardVisibilityResolver.resolve(nil, isPortLiveNow: true) == .live)
    }

    @Test("A nil lookup with the port not live now resolves to .ended, never .transientFadingGrace")
    func nilLookupDeadResolvesToEnded() {
        #expect(SettlingCardVisibilityResolver.resolve(nil, isPortLiveNow: false) == .ended)
    }

    /// The three known-state cases mirror `PortVisibilityState` one for one
    /// and don't consult `isPortLiveNow` at all (verified by passing the
    /// OPPOSITE of what each case would otherwise suggest: if the resolver
    /// were falling through to the liveness closure instead of switching on
    /// the known state, these would flip).
    @Test("Known visibility states resolve without consulting isPortLiveNow")
    func knownStatesResolveDirectly() {
        #expect(SettlingCardVisibilityResolver.resolve(.hidden, isPortLiveNow: true) == .ended)
        #expect(SettlingCardVisibilityResolver.resolve(.live, isPortLiveNow: false) == .live)
        #expect(SettlingCardVisibilityResolver.resolve(.fading, isPortLiveNow: false) == .transientFadingGrace)
    }

    // MARK: - Mount-time visibility resolution (issue #585, task 3)

    /// The bug this exists to close: `portVisibilityStates` is a separate
    /// `@State` dictionary that lags one `.onChange` behind a generation
    /// change, so plugging into an already-visible empty port can construct
    /// a fresh `SettlingPortCardHost` while the dictionary still holds the
    /// OLD `.hidden` entry from when the port was empty. `.resolve` (the
    /// plain lookup) would fold that straight to `.ended`, and the fresh
    /// machine's trigger would then start `.settled` instead of `.loading`,
    /// skipping the spinner-then-reveal choreography (PR #579).
    /// `.resolveAtMount` is the fix: a stale `.hidden` entry is overridden
    /// by a live-now signal, exactly like a `nil` lookup.
    ///
    /// Mutation watched failing: called `.resolve` directly instead of
    /// `.resolveAtMount` (i.e. the pre-fix behaviour). Went red here (this
    /// case resolved `.ended` instead of `.live`), the very stuck-spinner
    /// symptom the fix closes; restored.
    @Test("A stale .hidden entry with the port live now resolves to .live, not .ended")
    func staleHiddenWithLiveNowResolvesToLive() {
        #expect(SettlingCardVisibilityResolver.resolveAtMount(.hidden, isPortLiveNow: true) == .live)
    }

    /// The negative case: `.hidden` with the live signal ALSO false stays
    /// `.ended`, exactly as `.resolve` already does. This is the
    /// dead-session race `.resolve`'s plain `nil` branch closes, and
    /// `.resolveAtMount` must not reopen it.
    @Test("A .hidden entry with the port not live now still resolves to .ended")
    func hiddenWithoutLiveNowResolvesToEnded() {
        #expect(SettlingCardVisibilityResolver.resolveAtMount(.hidden, isPortLiveNow: false) == .ended)
    }

    /// `.fading` carries the #536 charger-grace policy and must never be
    /// second-guessed by a same-frame live signal, unlike `.hidden`.
    @Test("A .fading entry with the port live now still resolves to .transientFadingGrace")
    func fadingWithLiveNowStaysTransientFadingGrace() {
        #expect(SettlingCardVisibilityResolver.resolveAtMount(.fading, isPortLiveNow: true) == .transientFadingGrace)
    }

    /// `.live` is unaffected: mirrors `.resolve`'s own known-state arm.
    @Test("A .live entry resolves to .live regardless of the live-now signal")
    func liveEntryStaysLive() {
        #expect(SettlingCardVisibilityResolver.resolveAtMount(.live, isPortLiveNow: false) == .live)
    }

    /// `nil` (no verdict yet) is unaffected: mirrors `.resolve`'s `nil` arm
    /// exactly, both directions.
    @Test("A nil entry resolves exactly like .resolve's nil arm, both directions")
    func nilEntryMatchesPlainResolve() {
        #expect(SettlingCardVisibilityResolver.resolveAtMount(nil, isPortLiveNow: true) == .live)
        #expect(SettlingCardVisibilityResolver.resolveAtMount(nil, isPortLiveNow: false) == .ended)
    }

    // MARK: - Opacity race (per-task-review finding, round 1, critical)

    /// The invariant the reviewer named directly, scoped to where it
    /// actually applies: at NO reachable combination of (parent visibility
    /// state, child phase) that can STILL BE SHOWING LIVE CONTENT
    /// (`SettlingCardContentPlan.plan(...) == .liveBody`, i.e. `.settled`,
    /// or `.fading` with `hasRevealed`) does the effective presented
    /// opacity exceed the `.fading` dimmed value once the session has
    /// ended. `.retained` is deliberately EXCLUDED: its content plan is
    /// never `.liveBody` (spec: "Parent-owned retention and removal", "keep
    /// the parent's current behaviour for that visibility state" once
    /// genuinely retained), so full opacity there is the intended steady
    /// state, not a flash of old data. `.loading` is excluded for the same
    /// reason: its content plan is `.placeholder`, never live cable data.
    ///
    /// "Once the session has ended" is read structurally, not by which side
    /// updated first: either `visibility != .live` (the parent's
    /// authoritative signal already says the session isn't confirmed live)
    /// or `phase == .fading` (this machine's own exit is running) is enough
    /// to trigger the cap, so the bound holds regardless of whether
    /// `settlingVisibility` changing or this view's `onChange`-driven
    /// `phase` mutation commits first in any given render.
    ///
    /// Exhaustive over every `(SettlingCardVisibility, SettlingCardPhase)`
    /// pair (3 x 4 = 12 combinations) before filtering to the live-content
    /// subset, not a handful of hand-picked cases, per the house rule that a
    /// corpus/space-wide claim needs a corpus/space-wide check.
    ///
    /// Mutation watched failing: reverted `SettlingCardOpacity
    /// .effectiveOpacity` to the PRE-FIX shape that reproduces the race,
    /// i.e. the two independent computations the parent and child used to
    /// each own: `phase == .fading ? SettlingCardOpacity.hidden :
    /// (visibility == .transientFadingGrace ? SettlingCardOpacity.dimmed :
    /// SettlingCardOpacity.full)`. This maps `visibility: .ended, phase:
    /// .settled` (the exact frame described in the finding: session just
    /// ended, this machine's `onChange` hasn't moved `phase` off `.settled`
    /// yet) to `.full`, exceeding `.dimmed` while `.settled`'s content plan
    /// is still `.liveBody`. Went red; restored.
    @Test("Effective opacity of live content never exceeds the dimmed value once the session has ended")
    func opacityNeverExceedsDimmedOnceSessionEnded() {
        let allPhases: [SettlingCardPhase] = [.loading, .settled, .fading, .retained]
        let allVisibilities: [SettlingCardVisibility] = [.live, .transientFadingGrace, .ended]
        for phase in allPhases {
            for hasRevealed in [false, true] {
                for visibility in allVisibilities {
                    let contentPlan = SettlingCardContentPlan.plan(phase: phase, hasRevealed: hasRevealed)
                    guard contentPlan == .liveBody else { continue }
                    let sessionEndedOrFading = (visibility != .live) || (phase == .fading)
                    guard sessionEndedOrFading else { continue }
                    let opacity = SettlingCardOpacity.effectiveOpacity(visibility: visibility, phase: phase)
                    #expect(
                        opacity <= SettlingCardOpacity.dimmed,
                        "visibility=\(visibility) phase=\(phase) hasRevealed=\(hasRevealed) produced opacity \(opacity) while showing live content, exceeding the dimmed cap"
                    )
                }
            }
        }
    }

    /// The narrower, "hand-walked" version of the same invariant: the exact
    /// frame the finding described, isolated as its own test so a future
    /// reader doesn't have to reconstruct it from the loop above. Session
    /// just ended (`visibility: .ended`); this machine's `onChange` hasn't
    /// run yet, so `phase` still reads `.settled` (its terminal pre-fade
    /// value) with a `.liveBody` content plan live behind it.
    @Test("The exact race frame: visibility just ended, phase not yet caught up, stays dimmed")
    func theExactRaceFrameStaysDimmed() {
        let opacity = SettlingCardOpacity.effectiveOpacity(visibility: .ended, phase: .settled)
        #expect(opacity == SettlingCardOpacity.dimmed)
        // The content plan at this exact (phase, hasRevealed) pair is still
        // live: confirms this is a real risk, not a vacuous combination the
        // opacity function happens to never actually see paired with live
        // content.
        #expect(SettlingCardContentPlan.plan(phase: .settled, hasRevealed: true) == .liveBody)
    }

    /// Orchestrator review finding, issue #585: `.retained` must match the
    /// SAME dimming rule `.loading`/`.settled` already use
    /// (`visibility == .live ? full : dimmed`), not its own "full unless
    /// transientFadingGrace" mapping. The owner's requirement is that the
    /// retained disconnected card is visually IDENTICAL to a launch-time
    /// disconnected card (phase `.settled`, visibility `.ended`, opacity
    /// `dimmed`). Content already matches after task 1's fix; this closes
    /// the remaining opacity gap, where `.retained` + `.ended` rendered at
    /// `full` instead of `dimmed`, brighter than the launch-time card
    /// showing the exact same content.
    ///
    /// Mutation watched failing: this test was run against the PRE-FIX
    /// `.retained` arm (`visibility == .transientFadingGrace ? dimmed :
    /// full`), which maps `.ended` to `full`. Went red (expected `dimmed`,
    /// got `full`); restored by matching `.retained` to the `.loading`/
    /// `.settled` rule.
    @Test("Retained with ended visibility resolves to dimmed, matching a launch-time disconnected card")
    func retainedWithEndedVisibilityIsDimmed() {
        let retainedOpacity = SettlingCardOpacity.effectiveOpacity(visibility: .ended, phase: .retained)
        let launchTimeOpacity = SettlingCardOpacity.effectiveOpacity(visibility: .ended, phase: .settled)
        #expect(retainedOpacity == SettlingCardOpacity.dimmed)
        #expect(retainedOpacity == launchTimeOpacity, "retained must render identically to a launch-time disconnected card")
    }

    /// `.retained` + `.transientFadingGrace` still resolves to `dimmed`
    /// (unchanged behaviour, now reached via the shared rule instead of a
    /// `.retained`-only special case).
    @Test("Retained with transient-fading-grace visibility stays dimmed")
    func retainedWithTransientFadingGraceStaysDimmed() {
        #expect(SettlingCardOpacity.effectiveOpacity(visibility: .transientFadingGrace, phase: .retained) == SettlingCardOpacity.dimmed)
    }

    /// `.retained` + `.live` still resolves to `full` (momentary: real
    /// visibility recovery flips `phase` away from `.retained` via
    /// `SettlingCardPhaseEntryRecovery` before this frame would ever be
    /// seen for long, but the mapping itself is unchanged for that case).
    @Test("Retained with live visibility stays full")
    func retainedWithLiveVisibilityStaysFull() {
        #expect(SettlingCardOpacity.effectiveOpacity(visibility: .live, phase: .retained) == SettlingCardOpacity.full)
    }

    // MARK: - Deadline task arming (Codex gate, round 2, finding 1)

    /// The exact case the finding named: `.loading` with visibility already
    /// `.ended` must not be armed, so the deadline `.task(id:)` id computed
    /// from this predicate changes (relaunching a no-op task) the instant
    /// visibility flips to ended, rather than leaving a currently-sleeping
    /// task running unbothered until it wakes on its own.
    ///
    /// Mutation watched failing: dropped the `visibility != .ended` half of
    /// the predicate (`phase == .loading` alone). Went red here; restored.
    @Test("Loading with ended visibility is not armed")
    func loadingWithEndedVisibilityIsNotArmed() {
        #expect(SettlingCardDeadlineArming.isArmed(phase: .loading, visibility: .ended) == false)
    }

    @Test("Loading with live or transient-fading visibility is armed")
    func loadingWithNonEndedVisibilityIsArmed() {
        #expect(SettlingCardDeadlineArming.isArmed(phase: .loading, visibility: .live))
        #expect(SettlingCardDeadlineArming.isArmed(phase: .loading, visibility: .transientFadingGrace))
    }

    /// Every non-`.loading` phase is never armed, regardless of visibility:
    /// the deadline only ever has anything to do while the card is actually
    /// showing the placeholder.
    @Test("Only .loading can be armed, regardless of visibility")
    func onlyLoadingCanBeArmed() {
        let nonLoadingPhases: [SettlingCardPhase] = [.settled, .fading, .retained]
        let allVisibilities: [SettlingCardVisibility] = [.live, .transientFadingGrace, .ended]
        for phase in nonLoadingPhases {
            for visibility in allVisibilities {
                #expect(
                    SettlingCardDeadlineArming.isArmed(phase: phase, visibility: visibility) == false,
                    "phase=\(phase) visibility=\(visibility) must not be armed"
                )
            }
        }
    }

    // MARK: - Fade watchdog (adversarial gate addendum, round 2, finding 4)

    /// The watchdog fires only while genuinely `.fading`. Once the normal
    /// completion path (or the watchdog itself) has already moved phase to
    /// `.retained`, a later wake must be a no-op: this is the "first
    /// delivery wins" half of the contract, expressed at the predicate
    /// level. The reducer-level half (a duplicate `fadeCompleted` while
    /// already `.retained` is a no-op regardless) is pinned by Task 2's
    /// `SettlingCardPhaseTests.retainedIsStickyAgainstEveryReducerEvent`,
    /// which already drives BOTH `fadeCompleted(parentRetainsCard: true)`
    /// and `false` at `.retained` and confirms neither moves it.
    ///
    /// Mutation watched failing: changed the predicate to `phase != .loading`
    /// (a plausible-looking but wrong stand-in). Went red on
    /// `watchdogDoesNotFireOutsideFading` below (`.settled` and `.retained`
    /// both satisfy `!= .loading`, so the watchdog would wrongly consider
    /// itself armed there too); restored.
    @Test("Watchdog fires only while .fading")
    func watchdogFiresOnlyWhileFading() {
        #expect(SettlingCardFadeWatchdog.shouldFire(phase: .fading))
    }

    @Test("Watchdog does not fire outside .fading")
    func watchdogDoesNotFireOutsideFading() {
        #expect(SettlingCardFadeWatchdog.shouldFire(phase: .loading) == false)
        #expect(SettlingCardFadeWatchdog.shouldFire(phase: .settled) == false)
        #expect(SettlingCardFadeWatchdog.shouldFire(phase: .retained) == false)
    }

    // MARK: - Visible-port membership (Codex gate, round 2, finding 3)

    /// The exact case the finding named: with "Hide empty ports" OFF, a
    /// port's visibility state can never change `ForEach` membership, so
    /// every state must resolve to visible.
    ///
    /// Mutation watched failing: dropped the `guard hideEmptyPorts else {
    /// return true }` short-circuit, letting `.hidden` fall through to
    /// `false` unconditionally. Went red here (specifically the `.hidden`
    /// case); restored.
    @Test("With hideEmptyPorts off, every state is visible")
    func hideEmptyPortsOffAlwaysVisible() {
        let allStates: [PortVisibilityState?] = [.live, .fading, .hidden, nil]
        for state in allStates {
            #expect(
                SettlingCardVisibleMembership.isVisible(state: state, hideEmptyPorts: false),
                "state=\(String(describing: state)) must be visible with hideEmptyPorts off"
            )
        }
    }

    /// With the setting ON, this mirrors `ContentView.mainContent`'s filter
    /// exactly for the three known states: `.hidden` is the only one that
    /// drops out.
    @Test("With hideEmptyPorts on, only .hidden is not visible")
    func hideEmptyPortsOnHidesOnlyHidden() {
        #expect(SettlingCardVisibleMembership.isVisible(state: .live, hideEmptyPorts: true))
        #expect(SettlingCardVisibleMembership.isVisible(state: .fading, hideEmptyPorts: true))
        #expect(SettlingCardVisibleMembership.isVisible(state: .hidden, hideEmptyPorts: true) == false)
        #expect(SettlingCardVisibleMembership.isVisible(state: nil, hideEmptyPorts: true))
    }

    // MARK: - Visible-port membership: old/new SET comparison (Codex gate, round 3, "issue 2")

    /// The exact case the finding named: a port with NO old entry at all
    /// (its first appearance) must register as a membership change. The
    /// round-2 per-key walk missed this because it only ever iterated
    /// CURRENT ports and read a missing old entry as "already visible"
    /// (via `isVisible`'s own `nil` fallback), so old-visible == new-visible
    /// and nothing fired.
    ///
    /// Mutation watched failing: reverted `membershipChanged` to the round-2
    /// per-key shape (`ports.contains { isVisible(old[key]) != isVisible(new[key]) }`,
    /// scoped to `new`'s keys only, standing in for "current ports only").
    /// Went red here; restored.
    @Test("First appearance registers as a membership change")
    func firstAppearanceIsMembershipChange() {
        let old: [String: PortVisibilityState] = [:]
        let new: [String: PortVisibilityState] = ["Port-USB-C@1": .live]
        #expect(SettlingCardVisibleMembership.membershipChanged(old: old, new: new, hideEmptyPorts: true))
        #expect(SettlingCardVisibleMembership.membershipChanged(old: old, new: new, hideEmptyPorts: false))
    }

    /// The mirror case: a port present in `old` but entirely absent from
    /// `new` (it vanished from the registry, not just gone `.hidden`) must
    /// also register as a change. A walk scoped to CURRENT ports can never
    /// even reach this port to compare it.
    @Test("Disappearance registers as a membership change")
    func disappearanceIsMembershipChange() {
        let old: [String: PortVisibilityState] = ["Port-USB-C@1": .live]
        let new: [String: PortVisibilityState] = [:]
        #expect(SettlingCardVisibleMembership.membershipChanged(old: old, new: new, hideEmptyPorts: true))
        #expect(SettlingCardVisibleMembership.membershipChanged(old: old, new: new, hideEmptyPorts: false))
    }

    /// The common case this whole gate exists to keep unanimated: the same
    /// port, present in both snapshots, only its RAW state churning
    /// (`.live` <-> `.fading`, the #536 opacity-only case) while both map to
    /// "visible" under `hideEmptyPorts`. Same visible sets, no change.
    @Test("Same visible sets, different raw states, is unchanged")
    func sameVisibleSetsIsUnchanged() {
        let old: [String: PortVisibilityState] = ["Port-USB-C@1": .live]
        let new: [String: PortVisibilityState] = ["Port-USB-C@1": .fading]
        #expect(SettlingCardVisibleMembership.membershipChanged(old: old, new: new, hideEmptyPorts: true) == false)
    }

    /// With `hideEmptyPorts` off, visible sets follow port PRESENCE only:
    /// a state churning between `.live`/`.fading`/`.hidden` for a port that
    /// stays present is never a change (every state maps to visible=true),
    /// but the port disappearing from the registry entirely still is
    /// (`membershipChanged` correctly still fires, per
    /// `disappearanceIsMembershipChange` above; this test isolates the
    /// "state alone never matters" half).
    @Test("With hideEmptyPorts off, sets follow port presence only, not raw state")
    func hideEmptyPortsOffSetsFollowPresenceOnly() {
        let old: [String: PortVisibilityState] = ["Port-USB-C@1": .live]
        let new: [String: PortVisibilityState] = ["Port-USB-C@1": .hidden]
        #expect(SettlingCardVisibleMembership.membershipChanged(old: old, new: new, hideEmptyPorts: false) == false)
    }

    // MARK: - Phase-entry recovery (round 4, replaces the round-3 fade-completion-chained design)

    /// The ordering Codex named directly, now modelled through the round-4
    /// mechanism: visibility returns to `.live` WHILE the machine is still
    /// `.fading` (the edge-triggered `sessionResumed` this produces is a
    /// correct no-op there, "no mid-fade reversal"), and THEN the fade
    /// completes with no further visibility change. `SettlingPortCardHost`'s
    /// `.onChange(of: phase)` fires the instant `phase` actually becomes
    /// `.retained`, checked here by driving the reducer to `.retained`
    /// exactly as the view's `fadeCompleted` send would, then applying the
    /// SAME predicate the observer calls at that entry.
    ///
    /// Mutation watched failing: changed `shouldRecover(onEntryTo:
    /// visibility:)` to `phase == .retained` alone, dropping the visibility
    /// check. Went red on `fadeCompletionWithoutLiveVisibilityStaysRetained`
    /// below (a genuinely dead session, visibility `.ended`, would have
    /// wrongly recovered to `.settled` the moment its fade completed);
    /// restored.
    @Test("Ordering: live arrives during .fading, fade completes, ends settled not retained")
    func liveDuringFadingThenFadeCompletesEndsSettled() {
        let generation = 12
        var phase = SettlingCardPhase.loading
        phase = SettlingCardReducer.reduce(
            phase: phase, event: .deadlineReached(generation: generation), generation: generation
        )
        #expect(phase == .settled)

        phase = SettlingCardReducer.reduce(phase: phase, event: .sessionEnded, generation: generation)
        #expect(phase == .fading)

        // Visibility returns to live while still fading. The edge-triggered
        // path (SettlingPortCardHost's onChange(of: settlingVisibility))
        // would fire sessionResumed here; the reducer correctly refuses it
        // mid-fade.
        phase = SettlingCardReducer.reduce(phase: phase, event: .sessionResumed, generation: generation)
        #expect(phase == .fading, "sessionResumed must not reverse an in-flight fade")

        // The fade completes with visibility STILL live (no further change
        // to produce a later onChange(of: settlingVisibility) edge). This is
        // exactly the phase transition SettlingPortCardHost's
        // .onChange(of: phase) observes.
        phase = SettlingCardReducer.reduce(
            phase: phase, event: .fadeCompleted(parentRetainsCard: true), generation: generation
        )
        #expect(phase == .retained)

        // The observer's predicate, evaluated on entry to .retained against
        // the current (still-live) visibility.
        #expect(SettlingCardPhaseEntryRecovery.shouldRecover(onEntryTo: phase, visibility: .live))
        phase = SettlingCardReducer.reduce(phase: phase, event: .sessionResumed, generation: generation)
        #expect(phase == .settled, "must recover to the full card on entry, not stick at .retained")
    }

    /// The negative case: if visibility is NOT live at the moment `.retained`
    /// is entered, the predicate is correctly false and the machine stays at
    /// `.retained` exactly as before this fix.
    @Test("Entry to .retained with visibility ended does not recover")
    func fadeCompletionWithoutLiveVisibilityStaysRetained() {
        #expect(SettlingCardPhaseEntryRecovery.shouldRecover(onEntryTo: .retained, visibility: .ended) == false)
    }

    /// Entry to `.retained` with the transient-fading-grace visibility (a
    /// churn dip, not a confirmed live signal) also does not recover: only a
    /// confirmed `.live` visibility does.
    @Test("Entry to .retained with transient-fading-grace visibility does not recover")
    func fadeCompletionWithTransientVisibilityStaysRetained() {
        #expect(
            SettlingCardPhaseEntryRecovery.shouldRecover(onEntryTo: .retained, visibility: .transientFadingGrace)
                == false
        )
    }

    /// Entry to phases OTHER than `.retained` never recovers, regardless of
    /// visibility: the predicate is only meaningful at the one phase the
    /// observer cares about. Exhaustive over the non-`.retained` phases and
    /// every visibility, per the house rule that a space-wide claim needs a
    /// space-wide check.
    @Test("Entry to any phase other than .retained never recovers, regardless of visibility")
    func entryToNonRetainedPhaseNeverRecovers() {
        let nonRetainedPhases: [SettlingCardPhase] = [.loading, .settled, .fading]
        let allVisibilities: [SettlingCardVisibility] = [.live, .transientFadingGrace, .ended]
        for phase in nonRetainedPhases {
            for visibility in allVisibilities {
                #expect(
                    SettlingCardPhaseEntryRecovery.shouldRecover(onEntryTo: phase, visibility: visibility) == false,
                    "phase=\(phase) visibility=\(visibility) must not recover"
                )
            }
        }
    }

    // MARK: - Placeholder label snapshot formula

    /// The formula behind the frozen placeholder label: raw port name,
    /// `portDescription` when present, `serviceName` as the fallback. Never
    /// `summary.headline` (there is no `summary` in scope here at all,
    /// which is the point: this formula reads only `AppleHPMInterface`).
    ///
    /// Mutation watched failing: swapped the formula to `port.serviceName ??
    /// port.portDescription`-shaped logic (fell back to `portDescription`
    /// instead of preferring it). Went red on
    /// `snapshotLabelPrefersPortDescription` below; restored.
    @Test("Snapshot label prefers portDescription")
    func snapshotLabelPrefersPortDescription() {
        let port = makePort(serviceName: "Port-USB-C@1", portDescription: "Port-USB-C@1 (left)")
        #expect(SettlingPortCardHost.snapshotLabel(for: port) == "Port-USB-C@1 (left)")
    }

    @Test("Snapshot label falls back to serviceName when portDescription is nil")
    func snapshotLabelFallsBackToServiceName() {
        let port = makePort(serviceName: "Port-USB-C@2", portDescription: nil)
        #expect(SettlingPortCardHost.snapshotLabel(for: port) == "Port-USB-C@2")
    }

    /// Pins the round-2 fix directly (per-branch-review finding, Codex
    /// gate, finding 2): `snapshottedPortLabel` must be `@State`-backed, not
    /// a plain stored `let`. A plain `let` is baked fresh into the View
    /// struct on every re-render regardless of `.id(...)`-preserved
    /// identity; only `@State`'s external storage box actually survives a
    /// same-identity reconstruction, which is what "snapshotted at machine
    /// creation" requires. `@State private var x: T` desugars to a stored
    /// property `_x: State<T>` alongside the computed accessor `x`, so
    /// `Mirror` can see the underlying wrapper type on the View VALUE
    /// itself, without needing a live SwiftUI render harness this codebase
    /// doesn't have.
    ///
    /// Mutation watched failing: reverted `snapshottedPortLabel` to `private
    /// let` (round-1 shape) in a scratch copy and re-ran; `Mirror` no longer
    /// found a `_snapshottedPortLabel` child of type `State<String>` (a
    /// plain `let` reflects as `snapshottedPortLabel: String` with no
    /// leading underscore and no `State<...>` wrapper), so the assertion
    /// failed. Restored.
    @Test("snapshottedPortLabel is @State-backed, not a plain stored let")
    func snapshottedPortLabelIsStateBacked() {
        let port = makePort(serviceName: "Port-USB-C@3", portDescription: "Port-USB-C@3 (right)")
        let host = SettlingPortCardHost(
            port: port,
            devices: [],
            powerSources: [],
            identities: [],
            thunderboltSwitches: [],
            usb3Transports: [],
            isLive: false,
            showAdvanced: false,
            cioCapability: nil,
            accessoryIdentity: nil,
            displayPorts: [],
            chargerWattageSource: .unknown,
            batteryFullyCharged: nil,
            batteryIsCharging: nil,
            adapter: nil,
            connectionAttachInstant: nil,
            connectionSessionGeneration: nil,
            retainedAttachInstant: nil,
            settlingVisibility: .ended
        )
        let backing = Mirror(reflecting: host).children.first { $0.label == "_snapshottedPortLabel" }
        #expect(backing != nil, "expected a State-backed storage property _snapshottedPortLabel")
        let backingTypeName = backing.map { String(describing: type(of: $0.value)) } ?? ""
        #expect(backingTypeName.hasPrefix("State<"), "expected State<...>, got \(backingTypeName)")
    }

    // MARK: - Fixtures

    private func makePort(serviceName: String, portDescription: String?) -> AppleHPMInterface {
        AppleHPMInterface(
            id: 1,
            serviceName: serviceName,
            className: "AppleHPMInterfaceType10",
            portDescription: portDescription,
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [],
            transportsActive: [],
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: [:]
        )
    }
}
