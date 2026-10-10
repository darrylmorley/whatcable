import Testing
import Foundation
@testable import WhatCableCore

@Suite("Connection diagnostic (mid-session counter deltas)")
struct ConnectionDiagnosticTests {

    // MARK: SessionDelta arithmetic

    @Test("Delta is the rise from baseline to current")
    func deltaRise() {
        let baseline = ConnectionCounters(plugEvents: 10, overcurrents: 0)
        let current = ConnectionCounters(plugEvents: 13, overcurrents: 1)
        let delta = SessionDelta(baseline: baseline, current: current)
        #expect(delta.plugEvents == 3)
        #expect(delta.overcurrents == 1)
        #expect(!delta.isClean)
    }

    @Test("No change is a clean delta")
    func deltaClean() {
        let counters = ConnectionCounters(plugEvents: 7, overcurrents: 2)
        let delta = SessionDelta(baseline: counters, current: counters)
        #expect(delta.isClean)
        #expect(delta.plugEvents == 0)
    }

    @Test("A controller reset (count goes backwards) clamps to zero")
    func deltaClampsNegative() {
        let baseline = ConnectionCounters(plugEvents: 50, overcurrents: 3)
        let current = ConnectionCounters(plugEvents: 1, overcurrents: 0)
        let delta = SessionDelta(baseline: baseline, current: current)
        #expect(delta.isClean)
    }

    @Test("Missing counters at baseline contribute zero, never a phantom fault")
    func deltaMissingCounters() {
        let baseline = ConnectionCounters(plugEvents: nil, overcurrents: nil)
        let current = ConnectionCounters(plugEvents: 5, overcurrents: 2)
        let delta = SessionDelta(baseline: baseline, current: current)
        #expect(delta.isClean)
    }

    @Test("A nil overcurrent baseline does not manufacture a trip (conservative by design)")
    func nilOvercurrentBaselineStaysClean() {
        // The counter was unreadable at connect and reads 1 later. We cannot
        // tell whether that 1 happened this session or is lifetime history
        // from a previous cable, so we report nothing rather than falsely
        // accuse this cable. A value present at baseline (next test) is caught.
        let baseline = ConnectionCounters(plugEvents: 0, overcurrents: nil)
        let current = ConnectionCounters(plugEvents: 0, overcurrents: 1)
        let delta = SessionDelta(baseline: baseline, current: current)
        #expect(delta.overcurrents == 0)
        #expect(ConnectionDiagnostic(delta: delta, elapsedSeconds: 60, isMagSafe: false) == nil)
    }

    @Test("An overcurrent present at baseline catches a later trip")
    func anchoredOvercurrentBaselineCatchesTrip() throws {
        let baseline = ConnectionCounters(plugEvents: 0, overcurrents: 0)
        let current = ConnectionCounters(plugEvents: 0, overcurrents: 1)
        let delta = SessionDelta(baseline: baseline, current: current)
        #expect(delta.overcurrents == 1)
        let diag = try #require(ConnectionDiagnostic(delta: delta, elapsedSeconds: 60, isMagSafe: false))
        #expect(diag.fault == .overcurrent(count: 1))
    }

    // MARK: Diagnostic tiers

    @Test("Clean session produces no banner")
    func cleanNoBanner() {
        let delta = SessionDelta(plugEvents: 0, overcurrents: 0)
        #expect(ConnectionDiagnostic(delta: delta, elapsedSeconds: 120, isMagSafe: false) == nil)
    }

    @Test("A single plug event is below the bar (normal reconnect)")
    func singleEventNoBanner() {
        let delta = SessionDelta(plugEvents: 1, overcurrents: 0)
        #expect(ConnectionDiagnostic(delta: delta, elapsedSeconds: 120, isMagSafe: false) == nil)
    }

    @Test("Four or more plug events is an amber connection-events caution")
    func repeatedEventsCaution() throws {
        let delta = SessionDelta(plugEvents: 4, overcurrents: 0)
        let diag = try #require(ConnectionDiagnostic(delta: delta, elapsedSeconds: 180, isMagSafe: false))
        #expect(diag.severity == .caution)
        #expect(diag.fault == .repeatedConnectionEvents(count: 4))
        // The count belongs in the detail, not the headline. A port logs
        // roughly two plug events per connection, so a headline count would be
        // read as a number of interruptions we cannot stand behind.
        #expect(diag.detail.contains("4 connection events"))
        // Computed outside `#expect`: the macro rewrites its argument into an
        // expression tree, and a `contains(where:)` closure inside that gets
        // treated as possibly-throwing, which won't compile here.
        let headlineHasDigits = diag.summary.rangeOfCharacter(from: .decimalDigits) != nil
        #expect(!headlineHasDigits,
            "the headline carries a raw event count again: \(diag.summary)")
    }

    // MARK: The bar
    //
    // The corpus says a port logs roughly two plug events per connection, so
    // the old bar of 2 sat at exactly one ordinary unplug-and-replug. Both
    // testers who reported the banner (discussions #434, #478) tripped it that
    // way. These pin the new bar from both sides.

    @Test("One unplug-and-replug (2 events) stays silent")
    func oneReconnectStaysSilent() {
        let delta = SessionDelta(plugEvents: 2, overcurrents: 0)
        #expect(ConnectionDiagnostic(delta: delta, elapsedSeconds: 120, isMagSafe: false) == nil,
            "2 plug events is one ordinary reconnect on a port that logs two events per connection; it must not accuse anything")
    }

    @Test("Three events is still below the bar; four is the first that fires")
    func thresholdBoundaryIsExact() {
        // Walk the boundary by hand rather than trusting one sample: 3 is the
        // last silent value, 4 is the first that speaks.
        #expect(ConnectionDiagnostic(delta: SessionDelta(plugEvents: 3, overcurrents: 0), elapsedSeconds: 120, isMagSafe: false) == nil)
        #expect(ConnectionDiagnostic(delta: SessionDelta(plugEvents: 4, overcurrents: 0), elapsedSeconds: 120, isMagSafe: false) != nil)
        #expect(ConnectionDiagnostic.eventThreshold == 4)
    }

    // MARK: Wording

    @Test("The banner never claims the user did or did not touch the cable")
    func wordingAssertsNoCause() throws {
        // The reported defect: the copy asserted a cause it cannot know. A
        // user unplug and a genuine cable fault are electrically identical, so
        // neither direction may be stated as fact.
        let delta = SessionDelta(plugEvents: 5, overcurrents: 0)
        let diag = try #require(ConnectionDiagnostic(delta: delta, elapsedSeconds: 180, isMagSafe: false))
        let copy = diag.summary + " " + diag.detail
        #expect(!copy.localizedCaseInsensitiveContains("without you touching"),
            "the retracted claim is back: \(copy)")
        #expect(!copy.localizedCaseInsensitiveContains("you unplugged"),
            "the opposite claim is equally unprovable: \(copy)")
        #expect(!copy.localizedCaseInsensitiveContains("dropped"),
            "the count is plug events, roughly two per connection, not drops: \(copy)")
    }

    @Test("The banner says what was measured and keeps its advice conditional")
    func wordingStatesTheMeasurement() throws {
        let delta = SessionDelta(plugEvents: 6, overcurrents: 0)
        let diag = try #require(ConnectionDiagnostic(delta: delta, elapsedSeconds: 180, isMagSafe: false))
        #expect(diag.detail.contains("6 connection events"))
        #expect(diag.detail.localizedCaseInsensitiveContains("if it keeps happening"))
    }

    // MARK: MagSafe (found alongside issue #460)

    @Test("MagSafe never shows the connection-events banner")
    func magSafeSuppressesEventsTier() {
        // A magnetic connector is designed to detach, and the tier's advice
        // ("a different port or cable") is impossible on a captive cable with
        // no second MagSafe socket. All 520 MagSafe ports in the probe corpus
        // carry a non-zero plug-event count, 167 of them at 4 or above, so
        // this tier would fire there in normal use.
        let delta = SessionDelta(plugEvents: 6, overcurrents: 0)
        #expect(ConnectionDiagnostic(delta: delta, elapsedSeconds: 180, isMagSafe: true) == nil)
        #expect(ConnectionDiagnostic(delta: delta, elapsedSeconds: 180, isMagSafe: false) != nil,
            "the same delta must still fire on USB-C, or the suppression is hiding the whole tier")
    }

    @Test("MagSafe still reports a real overcurrent trip")
    func magSafeKeepsOvercurrent() throws {
        // Suppression is scoped to the events tier only. A protection trip is
        // a real hardware fault on any port, and its wording names neither a
        // cable swap nor another port.
        let delta = SessionDelta(plugEvents: 0, overcurrents: 1)
        let diag = try #require(ConnectionDiagnostic(delta: delta, elapsedSeconds: 60, isMagSafe: true))
        #expect(diag.fault == .overcurrent(count: 1))
        #expect(diag.severity == .warning)
    }

    @Test("One overcurrent trip is an orange warning")
    func overcurrentWarning() throws {
        let delta = SessionDelta(plugEvents: 0, overcurrents: 1)
        let diag = try #require(ConnectionDiagnostic(delta: delta, elapsedSeconds: 30, isMagSafe: false))
        #expect(diag.severity == .warning)
        #expect(diag.fault == .overcurrent(count: 1))
    }

    @Test("Overcurrent outranks the connection-events tier when both fire")
    func overcurrentOutranksConnectionEvents() throws {
        let delta = SessionDelta(plugEvents: 5, overcurrents: 1)
        let diag = try #require(ConnectionDiagnostic(delta: delta, elapsedSeconds: 60, isMagSafe: false))
        #expect(diag.fault == .overcurrent(count: 1))
        #expect(diag.severity == .warning)
    }

    // MARK: Elapsed window phrasing

    @Test("Under a minute and a half reads as the last minute")
    func windowSingleMinute() {
        #expect(ConnectionDiagnostic.window(45) == "in the last minute")
        #expect(ConnectionDiagnostic.window(80) == "in the last minute")
    }

    @Test("Multi-minute sessions read the rounded minute count")
    func windowMultipleMinutes() {
        #expect(ConnectionDiagnostic.window(180) == "in the last 3 minutes")
        #expect(ConnectionDiagnostic.window(600) == "in the last 10 minutes")
    }

    @Test("A zero elapsed never reads as zero minutes")
    func windowFloorsAtOne() {
        #expect(ConnectionDiagnostic.window(0) == "in the last minute")
    }

    @Test("Rounding edges floor to one minute, never zero")
    func windowRoundingEdges() {
        // 30s rounds to 0 minutes (round-half-to-even), so the max(1,...)
        // floor is load-bearing, not redundant. 90s rounds to 2 (the boundary
        // into the plural branch). Both are exercised here so neither silently
        // regresses.
        #expect(ConnectionDiagnostic.window(30) == "in the last minute")
        #expect(ConnectionDiagnostic.window(90) == "in the last 2 minutes")
    }

    @Test("The connection-events detail names the elapsed window")
    func eventsDetailMentionsWindow() throws {
        // 2 events used to be enough here; it is below the bar now, so this
        // needs a delta that actually produces a banner or it would assert on
        // an unwrapped nil rather than on the wording.
        let delta = SessionDelta(plugEvents: 4, overcurrents: 0)
        let diag = try #require(ConnectionDiagnostic(delta: delta, elapsedSeconds: 300, isMagSafe: false))
        #expect(diag.detail.contains("5 minutes"))
    }
}
