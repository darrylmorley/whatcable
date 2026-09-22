import Foundation

/// A port's visual visibility for "Hide empty ports": whether its card
/// should show in full, fade out, or drop from the list entirely.
///
/// This exists only to smooth over macOS re-attributing a single power
/// source between two ports (MagSafe and a USB-C port) every 1-2 seconds
/// (#536). Without it, "Hide empty ports" pops a charger-only port's card
/// in and out on every flip. It is purely a display decision: it never
/// changes what the app reports as connected in JSON, CLI text, the widget,
/// or notifications.
public enum PortVisibilityState: Equatable, Sendable {
    /// A non-power signal (device, PD identity, structurally-scoped
    /// tunnelled device) is present now, or a power source is attributed to
    /// this port right now.
    case live
    /// Nothing is present right now, but the port was a charger-only "live"
    /// port within the last `PortVisibilityTracker.graceWindow` seconds.
    /// Stays in the list, rendered at reduced opacity.
    case fading
    /// Nothing is present, and either nothing was ever live, a real
    /// device/PD connection just went away (no grace for that), or the
    /// grace window has elapsed.
    case hidden
}

/// Tracks, per port, whether its most recent loss of signal should hide it
/// immediately or fade it out over a short grace window.
///
/// Pure: no IOKit, which is why this is directly unit-testable. The caller
/// supplies `now` on every evaluation so tests can advance time without a
/// real clock.
///
/// Rule, deliberately simple (#536):
/// - A real unplug of a data/device connection (the port's last live
///   evaluation had a non-power signal) hides the port immediately: no fade.
/// - A charger-only port (the port's last live evaluation had power but no
///   non-power signal) whose power signal disappears fades for
///   `graceWindow` seconds, then hides.
/// - Any signal returning during the fade restores `.live` immediately.
public final class PortVisibilityTracker {
    /// How long a charger-only port stays visible (faded) after its power
    /// signal disappears, before dropping out of "Hide empty ports". Chosen
    /// to comfortably span the observed 1-2 second attribution flips.
    public static let graceWindow: TimeInterval = 3

    private struct Entry {
        var lastLiveTime: TimeInterval
        /// Whether a non-power signal was present the last time this port
        /// was evaluated as live. Decides whether a later loss of signal
        /// hides immediately (`true`) or fades (`false`).
        var hadNonPowerSignal: Bool
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// Evaluate one port's visibility for this pass.
    ///
    /// - Parameters:
    ///   - portKey: a stable per-port identity (e.g. `serviceName`).
    ///   - nonPowerLive: PD identity, matching devices, or another
    ///     non-power signal present right now.
    ///   - powerLive: a power source is attributed to this port right now.
    ///   - now: monotonic seconds, caller-supplied so tests control time.
    public func evaluate(portKey: String, nonPowerLive: Bool, powerLive: Bool, now: TimeInterval) -> PortVisibilityState {
        if nonPowerLive || powerLive {
            entries[portKey] = Entry(lastLiveTime: now, hadNonPowerSignal: nonPowerLive)
            return .live
        }

        guard let entry = entries[portKey] else { return .hidden }

        if entry.hadNonPowerSignal {
            // A real device/PD connection just vanished. Hide immediately,
            // and drop the entry so a later charger-only flap on this same
            // port key starts from a clean slate.
            entries.removeValue(forKey: portKey)
            return .hidden
        }

        // Strictly less than: at exactly `graceWindow` elapsed the fade is
        // over, not still fading. Review finding.
        if now - entry.lastLiveTime < Self.graceWindow {
            return .fading
        }

        entries.removeValue(forKey: portKey)
        return .hidden
    }

    /// Drops history for any port key not in `activeKeys`.
    ///
    /// Callers evaluate one pass at a time and normally never stop passing a
    /// key (a physical port controller service is persistent; it just loses
    /// its live signals). But if a port key genuinely drops out of the
    /// evaluation set entirely (its service node disappears from the
    /// registry) and later reappears with the same key, an un-pruned entry
    /// would let it resurface as `.fading` off a stale `lastLiveTime`
    /// instead of starting clean as `.hidden`. Call this once per pass with
    /// the full set of keys just evaluated. #536.
    public func reconcile(keeping activeKeys: Set<String>) {
        for key in entries.keys where !activeKeys.contains(key) {
            entries.removeValue(forKey: key)
        }
    }
}
