import XCTest
@testable import WhatCableNotifications
import WhatCableCore

/// Issue #593, F2 review finding: the port join.
///
/// The charger side keys ports by `PowerSource.canonicalJoinKey`; the
/// cable-name feed keys them by `AppleHPMInterface.canonicalJoinKey`. Each
/// prefers its own HPM controller UUID and falls back to `portKey` when ITS
/// OWN registry walk returned nil. So the two strings can disagree about one
/// physical port whenever exactly one side resolved a UUID, and a plain
/// dictionary lookup then misses: no name on the banner, and no grace armed
/// either, which is a silent no-op rather than a visible failure.
///
/// The repo already treats that disagreement as real rather than theoretical:
/// `PowerSource.canonicallyMatches(port:)` exists to absorb it, and
/// `ChargingInputResolver` groups by `portKey` for the same reason, citing a
/// registry teardown race reproduced in `ChargingInputResolverTests`. The join
/// now has the same tolerance, by publishing each port's name and identity
/// under both keys and looking up under both.
@MainActor
final class ChargerCableNameJoinTests: XCTestCase {

    /// A normalised HPM controller UUID: 32 lowercase hex characters, the
    /// shape `canonicalJoinKey` produces.
    private let portUUID = "0123456789abcdef0123456789abcdef"
    /// The same physical port's plain key, `parentPortType/parentPortNumber`.
    private let portKey = "2/1"

    private final class PostedLog {
        var entries: [(NotificationCategory, NotificationContent)] = []
    }
    private final class SourcesBox { var sources: [PowerSource] = [] }

    private func flush(_ clock: ManualClock) async { await clock.settle() }

    private func makeSequencer(
        clock: ManualClock, posted: PostedLog, box: SourcesBox
    ) -> DeviceDiffSequencer<ManualClock> {
        DeviceDiffSequencer(
            clock: clock,
            currentDevices: { [] },
            currentChargerSources: { box.sources },
            currentPorts: { [] },
            currentAdapter: { nil },
            notifyOnChanges: { true },
            post: { category, content, _ in posted.entries.append((category, content)) },
            launchToken: "test-launch"
        )
    }

    private func source(uuid: String?) -> PowerSource {
        PowerSource(
            id: 1, name: "USB-PD",
            parentPortType: 2, parentPortNumber: 1,
            options: [],
            winning: PowerOption(voltageMV: 20000, maxCurrentMA: 3000, maxPowerMW: 60000),
            hpmControllerUUID: uuid
        )
    }

    /// A feed as the provider now builds it: the port's name and its identity
    /// state published under BOTH of that port's keys.
    private func feed(keys: [String], name: String?) -> NotificationDecision.CableLabelFeed {
        var byPort: [String: String] = [:]
        if let name { for key in keys { byPort[key] = name } }
        return NotificationDecision.CableLabelFeed(
            hasSavedCables: true,
            attachedLabelled: name.map { ["cable-1": $0] } ?? [:],
            attachedLabelledByPort: byPort,
            portsAwaitingCableIdentity: [],
            portsWithResolvedCableIdentity: Set(keys)
        )
    }

    /// The mirror image: the PORT failed its UUID walk (so the feed keys it
    /// by `portKey` alone) while the charger source resolved one (so the
    /// charger key is the UUID). This is the half the sequencer's second
    /// lookup fixes.
    ///
    /// Red-proof: drop the fallback from `joinAliases(of:fallbacks:)` in
    /// `DeviceDiffSequencer` (return `[key]` always). Goes red with `("")`
    /// instead of `("Desk cable")`.
    func testAChargerWithAUUIDStillGetsACableNameKeyedByPortKeyAlone() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // The port published no UUID, so both its keys collapse to `portKey`.
        sequencer.updateLabelledCables(feed(keys: [portKey], name: "Desk cable"))
        box.sources = [source(uuid: portUUID)]
        sequencer.reconcileChargers()
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(
            posted.entries.first?.1.subtitle, "Desk cable",
            "the saved name must reach the banner even when only the CHARGER side resolved a UUID"
        )
    }

    /// The grace arms on the same join, so a mismatch used to suppress the
    /// wait as well as the name: the banner posted unnamed at the settle
    /// window and the later name could never reach it. Here the port is
    /// awaiting identity under `portKey` while the charger keys by its UUID;
    /// the grace must still arm, and the name that arrives during it must
    /// still land.
    ///
    /// Red-proof: drop the fallback from `joinAliases(of:fallbacks:)` in
    /// `DeviceDiffSequencer` (return `[key]` always). Goes red at the first
    /// assertion
    /// ("XCTAssertEqual failed: ("1") is not equal to ("0")"): with the join
    /// broken the grace never arms and the banner posts immediately, unnamed.
    func testTheGraceArmsAcrossAMixedUUIDJoin() async {
        let clock = ManualClock()
        let posted = PostedLog()
        let box = SourcesBox()
        let sequencer = makeSequencer(clock: clock, posted: posted, box: box)
        sequencer.didPrimeBaseline = true
        sequencer.knownChargerLabels = [:]

        // The port published no UUID, so it is awaiting under `portKey`
        // alone; the charger source DID resolve one, so its key is the UUID.
        // Only the sequencer's own fallback can bridge that.
        sequencer.updateLabelledCables(NotificationDecision.CableLabelFeed(
            hasSavedCables: true,
            attachedLabelled: [:],
            attachedLabelledByPort: [:],
            portsAwaitingCableIdentity: [portKey],
            portsWithResolvedCableIdentity: []
        ))
        box.sources = [source(uuid: portUUID)]
        sequencer.reconcileChargers()
        await flush(clock)
        XCTAssertEqual(posted.entries.count, 0, "the grace must arm across the mixed join, not post immediately")

        // The e-marker resolves and attributes, still keyed by `portKey`.
        sequencer.updateLabelledCables(feed(keys: [portKey], name: "Desk cable"))
        await flush(clock)

        XCTAssertEqual(posted.entries.count, 1)
        XCTAssertEqual(posted.entries.first?.1.subtitle, "Desk cable")
        await clock.advance(by: .seconds(10))
    }
}
