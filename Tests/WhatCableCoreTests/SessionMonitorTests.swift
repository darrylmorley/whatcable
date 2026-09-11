import Testing
@testable import WhatCableCore

@Suite("Session monitor (behavioural red bedrock)")
struct SessionMonitorTests {

    private let fp = "2/1#cableA"

    // Build and replay a sequence of observations on one fingerprint.
    private func replay(
        _ deliveries: [SessionMonitor.DataDelivery],
        resistance: [CableResistanceEstimate.Tier?] = [],
        fingerprint: String? = nil
    ) -> SessionMonitor {
        var monitor = SessionMonitor()
        let fingerprint = fingerprint ?? fp
        let count = max(deliveries.count, resistance.count)
        for i in 0..<count {
            let delivery = i < deliveries.count ? deliveries[i] : .notApplicable
            let tier = i < resistance.count ? resistance[i] : nil
            monitor.record(.init(fingerprint: fingerprint, dataDelivery: delivery, resistanceTier: tier))
        }
        return monitor
    }

    // MARK: Performing

    @Test("A fresh monitor performs")
    func freshPerforms() {
        let m = SessionMonitor()
        #expect(m.verdict == .performing)
        #expect(m.observationCount == 0)
    }

    @Test("Steady confirmed delivery performs")
    func steadyConfirmed() {
        let m = replay([.confirmed, .confirmed, .confirmed, .confirmed])
        #expect(m.verdict == .performing)
        #expect(m.observationCount == 4)
    }

    @Test("Host and device limits are never the cable's fault")
    func someoneElsesLimit() {
        // A whole session of notApplicable (host/device cap, no claim) is
        // never red and never even a caution.
        let m = replay([.notApplicable, .notApplicable, .notApplicable, .notApplicable])
        #expect(m.verdict == .performing)
    }

    // MARK: Must NOT convict (the asymmetry)

    @Test("One transient below-claim poll is a caution, not red")
    func singleTransientIsCaution() {
        let m = replay([.confirmed, .belowClaim, .confirmed, .confirmed])
        #expect(m.verdict == .caution)
        #expect(!m.dataNotDelivering)
    }

    @Test("Two consecutive below-claim polls (one short episode) is still caution")
    func shortEpisodeIsCaution() {
        // Below the sustained threshold (3) and only one episode, so a reseat
        // that takes two polls to settle does not convict.
        let m = replay([.belowClaim, .belowClaim, .confirmed])
        #expect(m.verdict == .caution)
        #expect(!m.dataNotDelivering)
    }

    @Test("One stable high-resistance reading is a caution, not red")
    func singleHighResistanceIsCaution() {
        let m = replay([], resistance: [.good, .high, .good])
        #expect(m.verdict == .caution)
        #expect(!m.resistanceOutOfSpec)
    }

    // MARK: Red (corroborated non-delivery)

    @Test("A sustained degradation episode goes red")
    func sustainedDegradationIsRed() {
        // Three consecutive below-claim polls with no recovery: sustained.
        let m = replay([.confirmed, .belowClaim, .belowClaim, .belowClaim])
        #expect(m.verdict == .notPerforming)
        #expect(m.dataNotDelivering)
    }

    @Test("Two separate degradation episodes (flap) go red")
    func repeatedEpisodesAreRed() {
        // drop, recover, drop again: the classic marginal-cable flap.
        let m = replay([.belowClaim, .confirmed, .belowClaim])
        #expect(m.verdict == .notPerforming)
        #expect(m.dataNotDelivering)
    }

    @Test("A notApplicable gap does not split one episode into two")
    func gapDoesNotSplitEpisode() {
        // belowClaim, then a device-limit gap, then belowClaim again, with no
        // confirmed recovery between. That is one ongoing episode of length 2,
        // not two episodes, so it stays a caution.
        let m = replay([.belowClaim, .notApplicable, .belowClaim])
        #expect(m.verdict == .caution)
        #expect(!m.dataNotDelivering)
    }

    @Test("Out-of-spec resistance sustained under load goes red")
    func sustainedHighResistanceIsRed() {
        let m = replay([], resistance: [.high, .high])
        #expect(m.verdict == .notPerforming)
        #expect(m.resistanceOutOfSpec)
    }

    @Test("A good reading between high readings resets the resistance streak")
    func resistanceStreakResets() {
        // high, good, high: never two highs in a row, so not convicted.
        let m = replay([], resistance: [.high, .good, .high])
        #expect(m.verdict == .caution)
        #expect(!m.resistanceOutOfSpec)
    }

    @Test("Marginal resistance never contributes to red")
    func marginalResistanceIsFine() {
        let m = replay([], resistance: [.marginal, .marginal, .marginal])
        #expect(m.verdict == .performing)
    }

    // MARK: Overcurrent

    @Test("An overcurrent trip during the session goes straight to red")
    func overcurrentTripIsRed() {
        var m = SessionMonitor()
        // Baseline count of 4 (lifetime, from before this cable): not an event.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, overcurrentCount: 4))
        #expect(m.verdict == .performing)
        #expect(!m.overcurrentTripped)
        // Count climbs while still connected: a real event on this cable.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, overcurrentCount: 5))
        #expect(m.verdict == .notPerforming)
        #expect(m.overcurrentTripped)
    }

    @Test("A pre-existing overcurrent count is not blamed on the new cable")
    func overcurrentBaselineNotBlamed() {
        // A high lifetime count that never moves is the baseline, not a trip.
        let m = replay([.confirmed, .confirmed, .confirmed])
        var n = m
        for _ in 0..<3 {
            n.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, overcurrentCount: 99))
        }
        #expect(!n.overcurrentTripped)
        #expect(n.verdict == .performing)
    }

    @Test("Overcurrent baseline resets when the cable is swapped")
    func overcurrentResetsOnSwap() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: "p#A", dataDelivery: .confirmed, resistanceTier: nil, overcurrentCount: 4))
        m.record(.init(fingerprint: "p#A", dataDelivery: .confirmed, resistanceTier: nil, overcurrentCount: 6))
        #expect(m.verdict == .notPerforming)
        // New cable: its baseline is the current lifetime count (6), so it
        // starts clean even though the lifetime total is non-zero.
        m.record(.init(fingerprint: "p#B", dataDelivery: .confirmed, resistanceTier: nil, overcurrentCount: 6))
        #expect(!m.overcurrentTripped)
        #expect(m.verdict == .performing)
    }

    // MARK: Hard resets

    @Test("Three resets with no attaches is a caution")
    func hardResetsWithNoAttachesIsCaution() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 2, attachCount: 0))
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 5, attachCount: 0))
        #expect(m.verdict == .caution)
        #expect(m.hardResetsExceedAttaches)
        #expect(m.hardResetEventCount == 3)
    }

    @Test("A single reset with no attaches stays performing (below the minimum delta)")
    func singleHardResetIsBelowMinimum() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: 0))
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 1, attachCount: 0))
        #expect(m.verdict == .performing)
        #expect(!m.hardResetsExceedAttaches)
    }

    @Test("Resets matched by re-seats (attaches) stay performing")
    func resetsExplainedByAttachesArePerforming() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: 0))
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 10, attachCount: 12))
        #expect(m.verdict == .performing)
        #expect(!m.hardResetsExceedAttaches)
    }

    @Test("A delta of exactly two resets fires the caution (boundary)")
    func exactlyTwoResetsFires() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: 0))
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 2, attachCount: 0))
        #expect(m.verdict == .caution)
        #expect(m.hardResetsExceedAttaches)
    }

    @Test("The hard-reset caution never escalates to red on its own")
    func hardResetCautionNeverEscalatesAlone() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: 0))
        for count in stride(from: 1, through: 40, by: 1) {
            m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: count, attachCount: 0))
        }
        #expect(m.hardResetsExceedAttaches)
        #expect(m.verdict == .caution)
    }

    @Test("A high but static lifetime count is the baseline, not an event")
    func staticHighCountIsBaseline() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 500, attachCount: 300))
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 500, attachCount: 300))
        #expect(!m.hardResetsExceedAttaches)
        #expect(m.verdict == .performing)
    }

    @Test("Baselines reset when the cable is swapped")
    func hardResetBaselineResetsOnSwap() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: "p#A", dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: 0))
        m.record(.init(fingerprint: "p#A", dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 3, attachCount: 0))
        #expect(m.verdict == .caution)
        // New cable: fresh baseline even though the lifetime counter is non-zero.
        m.record(.init(fingerprint: "p#B", dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 3, attachCount: 0))
        #expect(!m.hardResetsExceedAttaches)
        #expect(m.verdict == .performing)
    }

    @Test("A backward jump in both counters re-anchors the baseline together")
    func backwardJumpReanchorsBaseline() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 10, attachCount: 100))
        // Sleep/wake or a controller reset: both counters drop to zero.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: 0))
        // 15 resets and 15 re-seats since the new anchor: exactly matched.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 15, attachCount: 15))
        #expect(!m.hardResetsExceedAttaches)
        #expect(m.verdict == .performing)
    }

    @Test("A backward jump does not hide a genuine reset climb with no re-seats")
    func backwardJumpStillCatchesUnmatchedResets() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 500, attachCount: 300))
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: 0))
        // Resets climb from the new anchor with no re-seats: still worth flagging.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 60, attachCount: 0))
        #expect(m.hardResetsExceedAttaches)
        #expect(m.verdict == .caution)
    }

    @Test("An attach count that never arrives never lets the caution fire")
    func attachCountNeverArrivesNeverFires() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: nil))
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 3, attachCount: nil))
        #expect(!m.hardResetsExceedAttaches)
        #expect(m.verdict == .performing)
    }

    @Test("A late-arriving attach count anchors the baseline at its own poll, not before")
    func lateAttachBaselineAnchorsAtItsOwnPoll() {
        var m = SessionMonitor()
        // Hard resets arrive alone first: nothing to anchor against yet.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 5, attachCount: nil))
        // First poll carrying both: this is the anchor, (8, 20).
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 8, attachCount: 20))
        // Three resets and three re-seats since the anchor: matched.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 11, attachCount: 23))
        #expect(!m.hardResetsExceedAttaches)
        #expect(m.verdict == .performing)
    }

    @Test("A one-sided observation sets no baseline; the first joint observation does")
    func oneSidedObservationSetsNoBaseline() {
        var m = SessionMonitor()
        // Hard-reset count alone: not enough to anchor a joint baseline. If
        // this wrongly baselined hard resets on its own (at 5), the later
        // delta would come out too large against the anchor below.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 5, attachCount: nil))
        // First observation carrying both: this is the anchor, (9, 9).
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 9, attachCount: 9))
        // Two resets and two re-seats since the anchor: matched, stays performing.
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 11, attachCount: 11))
        #expect(m.hardResetEventCount == 2)
        #expect(!m.hardResetsExceedAttaches)
        #expect(m.verdict == .performing)
    }

    @Test("The hard-reset caution does not mask a red data degradation")
    func hardResetCautionDoesNotMaskRed() {
        var m = SessionMonitor()
        m.record(.init(fingerprint: fp, dataDelivery: .confirmed, resistanceTier: nil, hardResetCount: 0, attachCount: 0))
        m.record(.init(fingerprint: fp, dataDelivery: .belowClaim, resistanceTier: nil, hardResetCount: 5, attachCount: 0))
        m.record(.init(fingerprint: fp, dataDelivery: .belowClaim, resistanceTier: nil, hardResetCount: 8, attachCount: 0))
        m.record(.init(fingerprint: fp, dataDelivery: .belowClaim, resistanceTier: nil, hardResetCount: 12, attachCount: 0))
        #expect(m.hardResetsExceedAttaches)
        #expect(m.dataNotDelivering)
        #expect(m.verdict == .notPerforming)
    }

    // MARK: Session identity

    @Test("Swapping cables resets the accumulated evidence")
    func fingerprintChangeResets() {
        var m = SessionMonitor()
        // Cable A racks up a sustained failure.
        for _ in 0..<3 {
            m.record(.init(fingerprint: "2/1#A", dataDelivery: .belowClaim, resistanceTier: nil))
        }
        #expect(m.verdict == .notPerforming)
        // Cable B is plugged in: clean slate, one confirmed poll.
        m.record(.init(fingerprint: "2/1#B", dataDelivery: .confirmed, resistanceTier: nil))
        #expect(m.verdict == .performing)
        #expect(m.observationCount == 1)
    }

    // `resistanceAttributedPortKey` and its tests were removed in the 2026-08 charging-path rework:
    // attribution now happens in `ChargingInputResolver`, covered by
    // `ChargingInputResolverTests`.

    // MARK: Bottleneck mapping

    @Test("Bottleneck mapping matches the trust model")
    func bottleneckMapping() {
        typealias D = SessionMonitor.DataDelivery
        #expect(D.from(.cableLimit(cableGbps: 10, capableGbps: 40), hasCableSpeedClaim: true) == .confirmed)
        #expect(D.from(.fine(activeGbps: 40), hasCableSpeedClaim: true) == .confirmed)
        // .fine with no cable claim has no claim to confirm.
        #expect(D.from(.fine(activeGbps: 40), hasCableSpeedClaim: false) == .notApplicable)
        // The one under-delivery signal.
        #expect(D.from(.degraded(activeGbps: 10, expectedGbps: 40), hasCableSpeedClaim: true) == .belowClaim)
        // Someone else's cap, or unjudgeable, or a contradiction pointer.
        #expect(D.from(.hostLimit(hostGbps: 10, capableGbps: 40), hasCableSpeedClaim: true) == .notApplicable)
        #expect(D.from(.deviceLimit(deviceGbps: 0.48), hasCableSpeedClaim: true) == .notApplicable)
        #expect(D.from(.unknownCable(activeGbps: 10), hasCableSpeedClaim: false) == .notApplicable)
        #expect(D.from(.cableContradictsActive(cableGbps: 10, activeGbps: 40), hasCableSpeedClaim: true) == .notApplicable)
        #expect(D.from(nil, hasCableSpeedClaim: false) == .notApplicable)
    }
}
