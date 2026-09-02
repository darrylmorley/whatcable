import XCTest
import WhatCableNotifications

/// `reconcileChargers` posted one `UNUserNotificationCenter.add` PER changed
/// port; once charger events shared a single "charger-event" identifier
/// (issue #567), each later post replaced the one before it, so 2+ charger
/// changes in one settle window silently lost all but the last. Mirrors
/// `NotificationManagerAddedContentTests`: `chargerNotificationContents` is
/// the pure merge decision, testable without `UNUserNotificationCenter`.
final class NotificationManagerChargerContentTests: XCTestCase {
    private func line(_ wattage: String, name: String? = nil) -> NotificationDecision.ChargerLine {
        NotificationDecision.ChargerLine(wattage: wattage, cableName: name)
    }

    func testTwoAddedChargersMergeIntoOneContentWithBothLines() {
        let contents = NotificationDecision.chargerNotificationContents(
            added: [line("30W negotiated"), line("65W negotiated")],
            removed: []
        )

        XCTAssertEqual(contents, [
            NotificationContent(
                title: "Charger connected",
                body: "30W negotiated\n65W negotiated"
            )
        ])
    }

    func testOneAddedChargerIsUnchanged() {
        let contents = NotificationDecision.chargerNotificationContents(
            added: [line("30W negotiated")],
            removed: []
        )

        XCTAssertEqual(contents, [
            NotificationContent(title: "Charger connected", body: "30W negotiated")
        ])
    }

    func testMixedAddAndRemoveProducesRemovedContentThenAddedContent() {
        let contents = NotificationDecision.chargerNotificationContents(
            added: [line("65W negotiated")],
            removed: [line("30W negotiated")]
        )

        XCTAssertEqual(contents, [
            NotificationContent(title: "Charger disconnected", body: "30W negotiated"),
            NotificationContent(title: "Charger connected", body: "65W negotiated")
        ])
    }

    func testNoChangesProducesNoContent() {
        let contents = NotificationDecision.chargerNotificationContents(added: [], removed: [])
        XCTAssertEqual(contents, [])
    }

    /// `addedPortKeys` is a `Set` and `removedLabels` used to inherit
    /// Dictionary iteration order, neither of which is stable between runs.
    /// `sortedChargerLines` is what `reconcileChargers` now calls to turn a
    /// batch of changed port keys into lines, sorted on the stable port key
    /// rather than left to iteration order, so the merged notification's
    /// line order is deterministic.
    func testChargerLabelsAreSortedByPortKeyNotIterationOrder() {
        let labels = [
            "portZ": "65W negotiated",
            "portA": "30W negotiated",
            "portM": "45W negotiated"
        ]
        // Fed in deliberately unsorted order (Set doesn't preserve insertion
        // order, so this exercises the same shape reconcileChargers would
        // otherwise be exposed to).
        let unsortedKeys: Set<String> = ["portZ", "portA", "portM"]

        let sorted = NotificationDecision.sortedChargerLines(for: unsortedKeys, labels: labels, cableNames: [:])

        XCTAssertEqual(sorted.map(\.wattage), ["30W negotiated", "45W negotiated", "65W negotiated"])
        XCTAssertTrue(sorted.allSatisfy { $0.cableName == nil })
    }

    // MARK: - Issue #593: saved-cable name composition

    /// Exactly one changed line, and it has a name: the name goes in the
    /// subtitle (macOS renders that on its own line under the title,
    /// mirroring how a device notification carries a saved name), and the
    /// body stays the bare wattage untouched.
    func testSingleNamedAddedLineNamesTheSubtitle() {
        let contents = NotificationDecision.chargerNotificationContents(
            added: [line("30W negotiated", name: "Kitchen MagSafe")],
            removed: []
        )

        XCTAssertEqual(contents, [
            NotificationContent(title: "Charger connected", subtitle: "Kitchen MagSafe", body: "30W negotiated")
        ])
    }

    /// More than one line: a subtitle can't say which port the name
    /// belongs to, so it stays empty and the named line instead carries its
    /// own "<wattage> (<name>)" suffix in the body. The unnamed line is
    /// untouched.
    func testTwoAddedLinesOneNamedGetsNoSubtitleAndASuffixOnlyOnTheNamedLine() {
        let contents = NotificationDecision.chargerNotificationContents(
            added: [line("30W negotiated", name: "Kitchen MagSafe"), line("65W negotiated")],
            removed: []
        )

        XCTAssertEqual(contents, [
            NotificationContent(
                title: "Charger connected",
                body: "30W negotiated (Kitchen MagSafe)\n65W negotiated"
            )
        ])
    }
}
