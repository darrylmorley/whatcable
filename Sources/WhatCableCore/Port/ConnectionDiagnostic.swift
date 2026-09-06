import Foundation

/// A snapshot of one port's lifetime fault counters at a single instant. The
/// port controller keeps these counts for the whole life of the port, so the
/// absolute values mean nothing to a user (a port that has had cables plugged
/// into it for a year shows large numbers that are not a fault). The signal is
/// how far they climb during one continuous connection.
public struct ConnectionCounters: Equatable, Sendable {
    /// Times the port logged a plug event. A clean connection holds this
    /// steady.
    ///
    /// **What a rise does NOT tell us.** It does not say the user left the
    /// cable alone. A USB-C port stays live off the cable's own e-marker
    /// identity (`isPortLive`), which answers from the cable's termination at
    /// the Mac's connector no matter what is on the far end. So unplugging a
    /// device at the *other* end of a cable that stays in the Mac climbs this
    /// count with the connection never dropping. A user unplug and a genuine
    /// cable fault are electrically identical at the instant, and nothing in
    /// IOKit stamps "a human did this". Reported twice by beta testers
    /// (discussions #434 and #478) against wording that claimed otherwise.
    ///
    /// **Nor is it a count of drops.** Across 2510 real port readings in the
    /// probe corpus, 89.5% of ports carry a `Plug Event Count` within one of
    /// exactly twice their `ConnectionCount`, so the port logs roughly two
    /// plug events per connection. The exact per-event rule is unresolved (a
    /// one-shot corpus cannot settle it; it needs a bench capture), which is
    /// itself the reason no surface should quote this number as "dropped N
    /// times".
    public let plugEvents: Int?
    /// Times the port tripped overcurrent protection.
    public let overcurrents: Int?

    public init(plugEvents: Int?, overcurrents: Int?) {
        self.plugEvents = plugEvents
        self.overcurrents = overcurrents
    }

    public init(port: AppleHPMInterface) {
        self.init(
            plugEvents: port.plugEventCount,
            overcurrents: port.overcurrentCount
        )
    }
}

/// How far each fault counter has climbed since a connection began. A reset of
/// the underlying controller can make a counter go backwards; those negative
/// deltas are clamped to zero so a controller reset never reads as a fault.
public struct SessionDelta: Equatable, Sendable {
    public let plugEvents: Int
    public let overcurrents: Int

    /// The delta between the baseline captured when the connection began and
    /// the current reading.
    public init(baseline: ConnectionCounters, current: ConnectionCounters) {
        self.plugEvents = Self.rise(baseline.plugEvents, current.plugEvents)
        self.overcurrents = Self.rise(baseline.overcurrents, current.overcurrents)
    }

    /// Direct init for callers/tests that already hold the deltas.
    public init(plugEvents: Int, overcurrents: Int) {
        self.plugEvents = plugEvents
        self.overcurrents = overcurrents
    }

    /// The rise in a counter from baseline to now.
    ///
    /// A `nil` baseline means we never had a reading to anchor this
    /// connection to, so we report zero rather than a delta. This is
    /// deliberate and conservative: these are *lifetime* counts, so a counter
    /// that reads `nil` at connect and a value later could be carrying history
    /// from a previous cable on this port. Manufacturing a fault from an
    /// unparented count would falsely accuse an innocent cable, which is worse
    /// than missing one edge case. The live `SessionMonitor` engine anchors
    /// overcurrent the same way (first non-nil reading is the baseline, never
    /// an event). Counters also only ever climb, so a smaller "current" means
    /// the controller reset underneath us; that is clamped to zero too.
    private static func rise(_ base: Int?, _ now: Int?) -> Int {
        guard let base, let now else { return 0 }
        return max(0, now - base)
    }

    public var isClean: Bool {
        plugEvents == 0 && overcurrents == 0
    }
}

/// Turns a connection's in-session counter deltas into a plain-English fault
/// banner. The empirical sibling of `ChargingDiagnostic` / `DataLinkDiagnostic`:
/// where those judge a single snapshot ("is the cable the bottleneck right
/// now?"), this judges change over the life of one connection ("has this
/// connection misbehaved since you plugged it in?"). Same shape on purpose: a
/// failable init that returns `nil` when there is nothing to report, a `Fault`
/// enum carrying the numbers, and plain-English `summary` / `detail`.
///
/// Pure (no clock, no IOKit): the caller owns the per-port baseline and the
/// clock and passes in the resolved delta plus how long the connection has been
/// up. Living in `WhatCableCore` means any surface (the menu bar `PortCard`
/// today, a future live CLI view) generates identical copy.
///
/// Phase 1 wording is intentionally English-literal, matching how
/// `DataLinkDiagnostic` shipped: the strings move to `String(localized:)`
/// against `_coreLocalizedBundle` once the verdict wording is approved on a
/// live build.
public struct ConnectionDiagnostic: Equatable {
    public enum Fault: Equatable {
        /// The port tripped overcurrent protection during this connection.
        /// One is conclusive: a hard hardware fault, the most serious tier.
        case overcurrent(count: Int)
        /// The port logged repeated connection events during this connection.
        /// Named for what was measured, not for a cause: see
        /// `ConnectionCounters.plugEvents` for why this can't be read as
        /// "drops the user did not cause". The previous name (`repeatedDrops`)
        /// is what produced copy asserting both of those things.
        case repeatedConnectionEvents(count: Int)
    }

    /// Visual severity, mapped to a callout colour by the UI. Kept here (not as
    /// a UI type) so the CLI and app agree on which faults are the loud ones.
    /// `warning` is the orange "act now" tier; `caution` is the amber "worth a
    /// look" tier.
    public enum Severity: Equatable {
        case warning
        case caution
    }

    /// A plug-event count at or above this during one connection is reportable
    /// instability.
    ///
    /// Was 2, on the assumption of one plug event per reconnect. The corpus
    /// says a port logs roughly two plug events per connection (see
    /// `ConnectionCounters.plugEvents`), which put the bar at exactly one
    /// ordinary unplug-and-replug: both testers who reported this banner
    /// tripped it within minutes of trying. 4 keeps a single deliberate
    /// reconnect below the bar under either per-event rule (one or two events
    /// per cycle), so the banner needs a genuine repeat to appear.
    public static let eventThreshold = 4

    public let fault: Fault
    public let severity: Severity
    public let summary: String
    public let detail: String

    /// Returns `nil` when the session is clean. Overcurrent outranks the
    /// connection-events tier: a hardware protection trip is the more serious
    /// signal, so when both fire the overcurrent banner is the one shown.
    ///
    /// - Parameters:
    ///   - delta: the rise in each counter since the connection began.
    ///   - elapsedSeconds: how long the connection has been up, for the "in the
    ///     last X minutes" window on the connection-events banner.
    ///   - isMagSafe: whether this is a MagSafe port. Suppresses the
    ///     connection-events tier only. MagSafe is a magnetic connector
    ///     designed to detach under load, so a rising plug-event count there is
    ///     expected rather than a fault, and the advice that tier gives ("try a
    ///     different port or cable") is impossible to follow on a captive cable
    ///     with no second MagSafe socket. Overcurrent still fires: a protection
    ///     trip is a real fault on any port, and its wording names neither.
    ///
    ///     Deliberately has **no default**. A default of `false` would let a
    ///     future caller silently reinstate the bug this suppression exists to
    ///     fix, and the compiler is the only thing that reliably notices.
    public init?(delta: SessionDelta, elapsedSeconds: TimeInterval, isMagSafe: Bool) {
        if delta.overcurrents >= 1 {
            self.fault = .overcurrent(count: delta.overcurrents)
            self.severity = .warning
            self.summary = "Cable triggered overcurrent protection"
            self.detail = "The port cut power to protect itself during this connection. Disconnect the cable and inspect both the cable and the port for damage or debris before reusing them."
        } else if delta.plugEvents >= Self.eventThreshold && !isMagSafe {
            self.fault = .repeatedConnectionEvents(count: delta.plugEvents)
            self.severity = .caution
            let window = Self.window(elapsedSeconds)
            // States the measurement and lists what can produce it, without
            // claiming which. We cannot show the user caused this, and equally
            // cannot show they did not, so the copy asserts neither and the
            // advice is conditional on it recurring.
            //
            // The count stays out of the headline on purpose. A port logs
            // roughly two plug events per connection, so "interrupted N times"
            // would translate the raw count into a number of interruptions we
            // cannot stand behind: the same mistake, one layer down. The detail
            // gives the number and says plainly what it counts.
            self.summary = "Repeated connection events"
            self.detail = "The port logged \(delta.plugEvents) connection events \(window). Anything being unplugged or moved counts, and so does a damaged plug, debris in the port, or a marginal cable. If it keeps happening, try reseating the cable, or a different port or cable."
        } else {
            // Clean session, a handful of events below the bar (one ordinary
            // unplug-and-replug lands here), or a MagSafe port doing what a
            // magnetic connector does. Nothing to surface.
            return nil
        }
    }

    /// "in the last minute" / "in the last N minutes" for the elapsed window.
    /// At least one minute so a fresh session never reads "0 minutes".
    static func window(_ elapsedSeconds: TimeInterval) -> String {
        let minutes = max(1, Int((elapsedSeconds / 60).rounded()))
        if minutes == 1 {
            return "in the last minute"
        }
        return "in the last \(minutes) minutes"
    }
}
