import Foundation

/// Watches one connected cable over time and decides whether it is actually
/// *delivering* what it claims. This is the bedrock for the trust model's
/// red tier (see `research/cable-trust-model.md`): a single bad reading is
/// never enough to convict a cable, so the verdict is built from corroborated
/// evidence accumulated across a connection, not from one snapshot.
///
/// The model is deliberately a value type fed one observation at a time. The
/// platform watcher owns a `var monitor = SessionMonitor()` and calls
/// `monitor.record(_:)` each poll; the verdict is then read off `verdict`.
/// Keeping it pure (no `Date`, no IOKit, no I/O) is what lets the replay
/// tests drive a whole session as a plain array of observations and assert
/// exactly when it does, and does not, go red.
///
/// **Asymmetry (load-bearing).** Measurement can *confirm* delivery cheaply
/// but must only *convict* on corroborated evidence:
/// - one transient bad poll (a reseat, a current spike) never reaches red,
/// - a host or device limit is never the cable's fault and never reaches red,
/// - red needs either a degradation that *repeats* (dropped, recovered,
///   dropped again) or one that is *sustained* well past a debounce window,
///   or resistance that stays out of the spec budget under load.
public struct SessionMonitor: Equatable, Sendable {

    /// What a single poll says about whether the cable delivered its claim on
    /// the data link. Derived from `DataLinkDiagnostic.Bottleneck` via
    /// `DataDelivery.from(_:hasCableSpeedClaim:)` so the rules live in one
    /// tested place, the same way `CableTrust.behaviour(...)` does it.
    public enum DataDelivery: Equatable, Sendable {
        /// The link carried the cable's full claimed speed (or ran right up
        /// to the cable's own rating). Evidence the cable performs.
        case confirmed
        /// The link came up below what the cable claims, on a path where the
        /// host and device could both go faster. The cable (or its
        /// connection) is the honest suspect. One of these alone is a
        /// caution, not a conviction.
        case belowClaim
        /// Nothing demanding to judge: the cap is the host or the device, the
        /// cable made no claim, or the readings merely disagree. Neither
        /// confirms nor degrades.
        case notApplicable
    }

    /// One poll's worth of evidence. `fingerprint` identifies the connection
    /// (port + cable). When it changes, a different cable is plugged in and
    /// the session resets, so two cables' evidence can never be merged.
    public struct Observation: Equatable, Sendable {
        public let fingerprint: String
        public let dataDelivery: DataDelivery
        /// The resistance tier, but only when the estimate is `stable`; pass
        /// `nil` otherwise (a converging or unreliable estimate is no
        /// evidence). See `CableResistanceEstimate.tier(ratedFiveA:)`.
        public let resistanceTier: CableResistanceEstimate.Tier?
        /// The port controller's lifetime overcurrent trip count
        /// (`AppleHPMInterface.overcurrentCount`), or `nil` when unknown. The
        /// monitor watches the *in-session delta*: the count when the cable
        /// was plugged in is the baseline, and any rise while it stays plugged
        /// is a real overcurrent event on this connection.
        public let overcurrentCount: Int?
        /// The port controller's lifetime hard-reset count
        /// (`PortHealthCounters.hardResetCount`), or `nil` when unknown.
        /// Read as an in-session delta, exactly like `overcurrentCount`: the
        /// count at plug-in is the baseline and only a rise while the cable
        /// stays connected is evidence about this connection.
        public let hardResetCount: Int?
        /// The port controller's lifetime attach count
        /// (`PortHealthCounters.attachCount`), or `nil` when unknown. The
        /// companion to `hardResetCount`: a rise here means someone
        /// re-seated the connector, which explains a reset rather than
        /// indicting the cable.
        public let attachCount: Int?

        public init(
            fingerprint: String,
            dataDelivery: DataDelivery,
            resistanceTier: CableResistanceEstimate.Tier?,
            overcurrentCount: Int? = nil,
            hardResetCount: Int? = nil,
            attachCount: Int? = nil
        ) {
            self.fingerprint = fingerprint
            self.dataDelivery = dataDelivery
            self.resistanceTier = resistanceTier
            self.overcurrentCount = overcurrentCount
            self.hardResetCount = hardResetCount
            self.attachCount = attachCount
        }
    }

    /// The running assessment of the current connection.
    public enum Verdict: String, Equatable, Sendable {
        /// No corroborated problem. Either confirmed delivery or simply
        /// nothing demanding has stressed the cable yet.
        case performing
        /// One degradation or one out-of-spec reading has been seen, but not
        /// enough to convict. A soft heads-up, never the cable's fault yet.
        case caution
        /// Corroborated non-delivery: repeated or sustained data degradation,
        /// or resistance out of the spec budget under load. This is the
        /// behavioural red tier. Wording stays observational ("isn't
        /// performing as expected"), never "fake".
        case notPerforming
    }

    // MARK: Debounce thresholds
    //
    // These are conservative on purpose (erring toward never convicting a
    // good cable) and will be tuned once the engine has watched real
    // hardware. At a ~2s poll, a streak of 3 is roughly 6 seconds.

    /// A single degradation episode this long (consecutive `belowClaim`
    /// polls with no recovery) counts as sustained, not transient.
    static let sustainedDegradationPolls = 3
    /// This many separate degradation episodes (each ended by a recovery)
    /// counts as repeating, the classic marginal-cable flap.
    static let repeatedEpisodeCount = 2
    /// Consecutive stable out-of-spec resistance readings before resistance
    /// counts as a real fault rather than one transient under a current spike.
    static let sustainedHighResistancePolls = 2
    /// The in-session hard-reset delta has to reach this before the ratio
    /// rule can fire. One reset is ordinary renegotiation; two or more with
    /// no re-seat to explain them is the shape worth flagging.
    static let minimumHardResetDelta = 2

    // MARK: Accumulated state (reset on a fingerprint change)

    private var fingerprint: String?
    /// Distinct data-degradation episodes seen so far. An episode opens on
    /// the first `belowClaim` and closes only on a `confirmed` recovery, so a
    /// gap of `notApplicable` polls does not split one episode in two.
    private var dataEpisodeCount = 0
    private var inDataEpisode = false
    private var currentEpisodePolls = 0
    private var longestEpisodePolls = 0
    /// Consecutive stable out-of-spec resistance readings.
    private var highResistanceStreak = 0
    private var longestHighResistanceStreak = 0
    /// The overcurrent trip count when this connection's first count was
    /// seen. The delta against the latest count is the events on this cable.
    private var overcurrentBaseline: Int?
    private var overcurrentEvents = 0
    /// Baselines for the lifetime hard-reset and attach counters, taken
    /// together from the first observation that carries both. The rule
    /// compares two deltas, so they only mean something anchored at the same
    /// instant: an observation carrying one counter without the other sets
    /// no baseline at all.
    private var hardResetBaseline: Int?
    private var attachBaseline: Int?
    private var hardResetEvents = 0
    private var attachEvents = 0
    /// Total observations recorded this session (lets the UI show "watched
    /// for N polls" without the engine needing a clock).
    public private(set) var observationCount = 0

    public init() {}

    /// Fold one poll into the session. Returns the resulting verdict for
    /// convenience; it is also available on `verdict`.
    @discardableResult
    public mutating func record(_ observation: Observation) -> Verdict {
        // A different cable on the line is a different session. Reset before
        // recording so the new cable starts from a clean slate.
        if observation.fingerprint != fingerprint {
            reset(to: observation.fingerprint)
        }

        observationCount += 1
        recordDataDelivery(observation.dataDelivery)
        recordResistance(observation.resistanceTier)
        recordOvercurrent(observation.overcurrentCount)
        recordHardResets(count: observation.hardResetCount, attaches: observation.attachCount)
        return verdict
    }

    private mutating func reset(to fingerprint: String) {
        self.fingerprint = fingerprint
        dataEpisodeCount = 0
        inDataEpisode = false
        currentEpisodePolls = 0
        longestEpisodePolls = 0
        highResistanceStreak = 0
        longestHighResistanceStreak = 0
        overcurrentBaseline = nil
        overcurrentEvents = 0
        hardResetBaseline = nil
        attachBaseline = nil
        hardResetEvents = 0
        attachEvents = 0
        observationCount = 0
    }

    private mutating func recordDataDelivery(_ delivery: DataDelivery) {
        switch delivery {
        case .belowClaim:
            if !inDataEpisode {
                inDataEpisode = true
                dataEpisodeCount += 1
                currentEpisodePolls = 0
            }
            currentEpisodePolls += 1
            longestEpisodePolls = max(longestEpisodePolls, currentEpisodePolls)
        case .confirmed:
            // A clean recovery ends the current episode. The next degradation
            // will count as a separate (repeated) episode.
            inDataEpisode = false
            currentEpisodePolls = 0
        case .notApplicable:
            // No evidence either way. Hold the episode state: we only treat a
            // recurrence as a *separate* episode when the link actually
            // recovered to full speed in between (a `confirmed`), which is the
            // stricter, harder-to-convict reading.
            break
        }
    }

    private mutating func recordResistance(_ tier: CableResistanceEstimate.Tier?) {
        switch tier {
        case .high:
            highResistanceStreak += 1
            longestHighResistanceStreak = max(longestHighResistanceStreak, highResistanceStreak)
        case .good, .marginal:
            highResistanceStreak = 0
        case nil:
            // No stable reading this poll: not evidence, leave the streak.
            break
        }
    }

    private mutating func recordOvercurrent(_ count: Int?) {
        guard let count else { return }
        guard let baseline = overcurrentBaseline else {
            // First count seen this session: it is the baseline, not an event.
            overcurrentBaseline = count
            return
        }
        // Counters only climb; clamp against a controller reset to avoid a
        // negative delta reading as zero events when it should stay flat.
        overcurrentEvents = max(0, count - baseline)
    }

    private mutating func recordHardResets(count: Int?, attaches: Int?) {
        // The ratio compares two deltas, so it is only meaningful once both
        // counters are anchored at the same poll. An observation carrying
        // one without the other can't set that anchor: a lopsided baseline
        // would make the comparison meaningless, not conservative.
        guard let count, let attaches else { return }
        guard let resetBase = hardResetBaseline, let attachBase = attachBaseline else {
            // First observation carrying both: baseline them together here.
            hardResetBaseline = count
            attachBaseline = attaches
            return
        }
        guard count >= resetBase, attaches >= attachBase else {
            // Either counter moved backwards (sleep/wake, a controller
            // reset). Re-anchor both to this poll and zero both deltas
            // instead of clamping just the hard-reset side: clamping only
            // the numerator would suppress it while leaving the denominator
            // free to fall behind, making the caution MORE likely to fire,
            // the wrong direction for a corroborating signal.
            hardResetBaseline = count
            attachBaseline = attaches
            hardResetEvents = 0
            attachEvents = 0
            return
        }
        hardResetEvents = count - resetBase
        attachEvents = attaches - attachBase
    }

    // MARK: Verdict

    /// True when the data link has demonstrably failed to deliver the cable's
    /// claim in a corroborated way: either one sustained episode or two
    /// separate episodes.
    public var dataNotDelivering: Bool {
        longestEpisodePolls >= Self.sustainedDegradationPolls
            || dataEpisodeCount >= Self.repeatedEpisodeCount
    }

    /// True when resistance has stayed out of the spec budget under load for
    /// long enough to rule out a one-poll transient.
    public var resistanceOutOfSpec: Bool {
        longestHighResistanceStreak >= Self.sustainedHighResistancePolls
    }

    /// True when the port controller logged an overcurrent trip while this
    /// cable was connected. A hard hardware fault, so even one is conclusive:
    /// no caution step, straight to red.
    public var overcurrentTripped: Bool {
        overcurrentEvents >= 1
    }

    /// Overcurrent trips seen on this connection since it was plugged in (the
    /// in-session delta the verdict already uses). Zero until one is seen.
    /// Exposed so a recorder can persist the delta without re-deriving it.
    public var overcurrentEventCount: Int {
        overcurrentEvents
    }

    /// True when this connection has logged more hard resets than attaches
    /// while it stayed plugged in. A link renegotiating repeatedly without
    /// anyone re-seating it is worth flagging, but the counters are lifetime
    /// and cannot name a cable, so this is a caution and never contributes to
    /// `.notPerforming` on its own. Before a joint baseline exists (no
    /// observation has yet carried both counters) both deltas stay zero, so
    /// this reads `false`: no attach evidence makes the comparison
    /// unevaluable, not won by default.
    public var hardResetsExceedAttaches: Bool {
        hardResetEvents >= Self.minimumHardResetDelta && hardResetEvents > attachEvents
    }

    /// Hard resets seen on this connection since it was plugged in (the
    /// in-session delta the caution uses). Exposed so a recorder can persist
    /// the delta without re-deriving it, matching `overcurrentEventCount`.
    public var hardResetEventCount: Int {
        hardResetEvents
    }

    /// The current verdict for this connection.
    public var verdict: Verdict {
        if dataNotDelivering || resistanceOutOfSpec || overcurrentTripped {
            return .notPerforming
        }
        // Some evidence of trouble, but below the conviction bar: a single
        // (still-open or recovered) degradation, one out-of-spec reading, or
        // a hard-reset ratio that looks unusual but can't be pinned on a
        // cable (the counters are lifetime, not per-cable).
        if dataEpisodeCount > 0 || longestHighResistanceStreak > 0 || hardResetsExceedAttaches {
            return .caution
        }
        return .performing
    }
}

// `resistanceAttributedPortKey(in:)` lived here until the 2026-08 charging-path rework. Attribution now
// happens where the estimate is built: `ChargingInputResolver` names the
// charging port and `PowerMonitorSnapshot.resistancePortKey` carries it, so
// no surface has to guess from per-port draw any more.

extension SessionMonitor.DataDelivery {
    /// Classify a data-link bottleneck into a delivery outcome. Extracted so
    /// the rules are testable without building a full `DataLinkDiagnostic`,
    /// and so they stay aligned with `CableTrust.behaviour(...)`.
    ///
    /// - `.cableLimit` and `.fine` (when the cable made a speed claim) are the
    ///   two ways the link confirms the cable delivered.
    /// - `.degraded` is the one under-delivery signal: the link is below what
    ///   every known part (cable included) supports, so on a capable path the
    ///   cable or its connection is the suspect.
    /// - everything else neither confirms nor degrades: `.hostLimit` /
    ///   `.deviceLimit` are someone else's cap, `.unknownCable` can't be
    ///   judged, `.cableContradictsActive` is the cable claiming *below* the
    ///   active rate (a contradiction pointer, handled by `CableTrust`, not an
    ///   under-delivery), and `.fine` with no cable claim has no claim to fail.
    ///
    /// - Parameter hasCableSpeedClaim: whether the cable advertised a usable
    ///   speed (same gate `CableTrust.behaviour` uses for the `.fine` case).
    public static func from(
        _ bottleneck: DataLinkDiagnostic.Bottleneck?,
        hasCableSpeedClaim: Bool
    ) -> Self {
        switch bottleneck {
        case .cableLimit:
            return .confirmed
        case .fine:
            return hasCableSpeedClaim ? .confirmed : .notApplicable
        case .degraded:
            return .belowClaim
        case .hostLimit, .deviceLimit, .unknownCable, .cableContradictsActive,
             .blockedBySecurity, .none:
            return .notApplicable
        }
    }
}
