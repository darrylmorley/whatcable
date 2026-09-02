import XCTest
import WhatCableNotifications
@testable import WhatCable

/// Issue #570 part B: `NotificationManager.foldLabelledCables(from:)`, the
/// nil-vs-empty fold over every registered
/// `PluginRegistry.notificationCableLabelProviders` closure.
///
/// Post-review fix: the fold combines `CableLabelFeed`, not a bare
/// dictionary: `hasSavedCables` folds by OR, `attachedLabelled` merges
/// first-writer-wins, matching the coordinator's fix spec exactly.
@MainActor
final class NotificationManagerLabelledCableFoldTests: XCTestCase {
    private func feed(hasSavedCables: Bool, _ attachedLabelled: [String: String] = [:]) -> NotificationDecision.CableLabelFeed {
        NotificationDecision.CableLabelFeed(hasSavedCables: hasSavedCables, attachedLabelled: attachedLabelled)
    }

    /// No providers registered at all (the public-mirror build) -> nil.
    ///
    /// Red-proof: change the empty-array guard to return a feed and this
    /// goes red.
    func testNoProvidersIsNil() {
        XCTAssertNil(NotificationManager.foldLabelledCables(from: []))
    }

    /// A single provider returning nil (licence locked) -> nil, not a
    /// feed with `hasSavedCables: false`.
    ///
    /// Red-proof: drop the `anyAvailable` tracking and just return the
    /// accumulated feed unconditionally, and this goes red (would return a
    /// non-nil feed).
    func testSingleNilProviderIsNil() {
        XCTAssertNil(NotificationManager.foldLabelledCables(from: [{ nil }]))
    }

    /// A single provider returning an empty, unlocked feed passes it
    /// through, distinct from nil.
    func testSingleEmptyFeedIsNotNil() {
        let result = NotificationManager.foldLabelledCables(from: [{ self.feed(hasSavedCables: false) }])
        XCTAssertEqual(result, feed(hasSavedCables: false))
    }

    /// A single provider returning real data passes it through unchanged.
    func testSingleProviderWithDataPassesThrough() {
        let result = NotificationManager.foldLabelledCables(from: [
            { self.feed(hasSavedCables: true, ["a": "Apple TB 1m"]) },
        ])
        XCTAssertEqual(result, feed(hasSavedCables: true, ["a": "Apple TB 1m"]))
    }

    /// Multiple providers merge `attachedLabelled` (first writer wins on
    /// key collision) and fold `hasSavedCables` by OR.
    func testMultipleProvidersMergeFirstWriterWinsAndOrHasSavedCables() {
        let result = NotificationManager.foldLabelledCables(from: [
            { self.feed(hasSavedCables: false, ["a": "First"]) },
            { self.feed(hasSavedCables: true, ["a": "Second", "b": "Other"]) },
        ])
        XCTAssertEqual(result, feed(hasSavedCables: true, ["a": "First", "b": "Other"]))
    }

    /// `hasSavedCables` true from ANY provider survives even when the
    /// providers disagree on order (OR is commutative, but worth pinning
    /// both directions since this is exactly the flagship-scenario signal).
    ///
    /// Red-proof: change `||` to `&&` in the fold and this goes red.
    func testHasSavedCablesTrueSurvivesRegardlessOfOrder() {
        let trueFirst = NotificationManager.foldLabelledCables(from: [
            { self.feed(hasSavedCables: true) },
            { self.feed(hasSavedCables: false) },
        ])
        let falseFirst = NotificationManager.foldLabelledCables(from: [
            { self.feed(hasSavedCables: false) },
            { self.feed(hasSavedCables: true) },
        ])
        XCTAssertEqual(trueFirst?.hasSavedCables, true)
        XCTAssertEqual(falseFirst?.hasSavedCables, true)
    }

    /// One nil provider alongside one real one still yields the real data:
    /// "nil-wins-nothing" semantics (nil only if ALL providers are nil).
    func testOneNilAmongMultipleStillYieldsData() {
        let result = NotificationManager.foldLabelledCables(from: [
            { nil },
            { self.feed(hasSavedCables: true, ["a": "Apple TB 1m"]) },
        ])
        XCTAssertEqual(result, feed(hasSavedCables: true, ["a": "Apple TB 1m"]))
    }

    /// `portsAwaitingCableIdentity` folds by UNION, not first-writer-wins:
    /// it is a set of ports, not a keyed choice between competing values, so
    /// a port only one provider is still waiting on has to survive the
    /// fold. The charger grace then waits on it, which costs one bounded
    /// window; dropping it posts a banner that can never be corrected.
    ///
    /// Red-proof: leave `portsAwaitingCableIdentity` out of the fold's
    /// result (so it defaults to `[]`), and this goes red with `[]` instead
    /// of both ports.
    func testPortsAwaitingCableIdentityFoldsByUnion() {
        let result = NotificationManager.foldLabelledCables(from: [
            { NotificationDecision.CableLabelFeed(
                hasSavedCables: true, attachedLabelled: [:], portsAwaitingCableIdentity: ["port-a"]
            ) },
            { NotificationDecision.CableLabelFeed(
                hasSavedCables: true, attachedLabelled: [:], portsAwaitingCableIdentity: ["port-b"]
            ) },
        ])
        XCTAssertEqual(result?.portsAwaitingCableIdentity, ["port-a", "port-b"])
    }

    /// `portsWithResolvedCableIdentity` folds by UNION too: any provider
    /// that has SEEN a port answer is reason enough for the charger grace to
    /// stop waiting on it.
    ///
    /// Red-proof: leave `portsWithResolvedCableIdentity` out of the fold's
    /// result (so it defaults to `[]`), and this goes red with `[]` instead
    /// of both ports. Without it a multi-provider build would never collapse
    /// a grace on resolution, only on a name or the cap.
    func testPortsWithResolvedCableIdentityFoldsByUnion() {
        let result = NotificationManager.foldLabelledCables(from: [
            { NotificationDecision.CableLabelFeed(
                hasSavedCables: true, attachedLabelled: [:], portsWithResolvedCableIdentity: ["port-a"]
            ) },
            { NotificationDecision.CableLabelFeed(
                hasSavedCables: true, attachedLabelled: [:], portsWithResolvedCableIdentity: ["port-b"]
            ) },
        ])
        XCTAssertEqual(result?.portsWithResolvedCableIdentity, ["port-a", "port-b"])
    }
}
