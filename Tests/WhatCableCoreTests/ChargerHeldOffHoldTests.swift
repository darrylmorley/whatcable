import Foundation
import Testing
@testable import WhatCableCore

/// Public issue 672: the held-off charger state must not flash during the few
/// seconds around a plug or an unplug. Clock-injected; nothing here sleeps.
@Suite("Charger held off: the wait before it shows")
struct ChargerHeldOffHoldTests {
    typealias H = ChargerHeldOffHold

    @Test("The candidate needs supply AND on battery; unknown supply stays unknown")
    func candidate() {
        #expect(H.candidate(chargerSupplyPresent: true, onBattery: true) == true)
        #expect(H.candidate(chargerSupplyPresent: true, onBattery: false) == false)
        #expect(H.candidate(chargerSupplyPresent: false, onBattery: true) == false)
        #expect(H.candidate(chargerSupplyPresent: nil, onBattery: true) == nil)
    }

    @Test("A new run publishes false until it has held for holdSeconds")
    func waitsOnTheWayIn() {
        let first = H.step(candidate: true, now: 100, since: nil)
        #expect(first.published == false)
        #expect(first.since == 100)
        // One poll tick later: still waiting.
        let tick = H.step(candidate: true, now: 101, since: first.since)
        #expect(tick.published == false)
        // Just under the hold: still waiting.
        #expect(H.step(candidate: true, now: 100 + H.holdSeconds - 0.01, since: 100).published == false)
        // Exactly the hold: shown.
        let shown = H.step(candidate: true, now: 100 + H.holdSeconds, since: 100)
        #expect(shown.published == true)
        #expect(shown.since == 100)
    }

    @Test("A plug-in blip shorter than the hold never shows")
    func plugInBlipNeverShows() {
        // At plug-in the SMC reports supply before macOS stops reading "on
        // battery": candidate true for 3 s, then the Mac starts charging.
        var since: TimeInterval?
        var shown: [Bool?] = []
        for (t, c) in [(0.0, true), (1.0, true), (2.0, true), (3.0, false), (4.0, false), (10.0, false)] {
            let r = H.step(candidate: c, now: t, since: since)
            since = r.since
            shown.append(r.published)
        }
        #expect(!shown.contains(true), "\(shown)")
    }

    @Test("False or unknown ends the run at once and restarts the wait")
    func leavingIsImmediate() {
        let gone = H.step(candidate: false, now: 200, since: 100)
        #expect(gone.published == false && gone.since == nil)
        let unknown = H.step(candidate: nil, now: 200, since: 100)
        #expect(unknown.published == nil && unknown.since == nil)
        // Back to true: the wait starts over.
        #expect(H.step(candidate: true, now: 201, since: nil).published == false)
    }

    // MARK: - Read cost: the extra reads only when "on battery" is possible

    /// Counts the two costly reads the lazy candidate may make.
    private final class Reads { var battery = 0; var adapter = 0 }

    private func lazy(_ supply: Bool?, _ state: BatteryChargeState?, record: Bool? = false,
                      adapter: Bool = false, _ reads: Reads) -> Bool? {
        H.candidate(chargerSupplyPresent: supply, chargeState: state,
                    batteryIsCharging: { reads.battery += 1; return record },
                    adapterPresent: { reads.adapter += 1; return adapter })
    }

    @Test("A Mac on AC that is charging makes no extra reads")
    func chargingOnACIsFree() {
        let reads = Reads()
        #expect(lazy(true, .charging, reads) == false)
        #expect(reads.battery == 0 && reads.adapter == 0, "battery \(reads.battery), adapter \(reads.adapter)")
    }

    @Test("No charger supply makes no extra reads")
    func noSupplyIsFree() {
        for supply in [false, nil] as [Bool?] {
            for state in [nil, .charging, .notPluggedIn, .full] as [BatteryChargeState?] {
                let reads = Reads()
                #expect(lazy(supply, state, reads) == supply)
                #expect(reads.battery == 0 && reads.adapter == 0)
            }
        }
    }

    @Test("A held Mac (SMC: not plugged in) reads only the adapter details, not the battery record")
    func heldReadsOnlyTheAdapter() {
        let reads = Reads()
        #expect(lazy(true, .notPluggedIn, adapter: false, reads) == true)
        #expect(reads.battery == 0 && reads.adapter == 1)
    }

    @Test("The lazy candidate agrees with resolvedFlags + onBattery for every input")
    func lazyMatchesTheFullRule() {
        for supply in [true, false, nil] as [Bool?] {
            for state in [nil] + BatteryChargeState.allCases.map(Optional.some) {
                for record in [true, false, nil] as [Bool?] {
                    for adapter in [true, false] {
                        let full = BatteryChargeState.resolvedFlags(state: state, isCharging: record, fullyCharged: nil)
                        let onBattery = SystemPowerState.onBattery(
                            batteryIsCharging: full.isCharging,
                            adapter: adapter ? AdapterInfo(watts: 96, isCharging: nil, source: "AC") : nil)
                        let expected = H.candidate(chargerSupplyPresent: supply, onBattery: onBattery)
                        #expect(lazy(supply, state, record: record, adapter: adapter, Reads()) == expected,
                                "supply \(String(describing: supply)) state \(String(describing: state)) record \(String(describing: record)) adapter \(adapter)")
                    }
                }
            }
        }
    }
}
