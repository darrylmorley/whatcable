import XCTest
import Combine
import WhatCableCore
@testable import WhatCableDarwinBackend

/// Issue #571. The safety property is "no control transfer reaches a device
/// before the app has loaded". That is only checkable if the call is
/// observable, so the reader is injectable and counted. Asserting the gate Bool
/// alone would stay green even if a new call site read descriptors directly.
@MainActor
final class USBWatcherProbeSeamTests: XCTestCase {
    private func withRestoredStatics(_ body: () throws -> Void) rethrows {
        let reader = USBWatcher.billboardReader
        let gate = USBWatcher.probeBillboardDescriptors
        let count = USBWatcher.billboardReadCount
        defer {
            USBWatcher.billboardReader = reader
            USBWatcher.probeBillboardDescriptors = gate
            USBWatcher.billboardReadCount = count
        }
        try body()
    }

    func testGateOffIssuesNoRead() throws {
        try withRestoredStatics {
            var calls = 0
            USBWatcher.billboardReader = { _ in calls += 1; return nil }
            USBWatcher.probeBillboardDescriptors = false
            USBWatcher.billboardReadCount = 0

            let watcher = USBWatcher()
            watcher.start()
            defer { watcher.stop() }

            XCTAssertEqual(calls, 0, "Gate off must issue no Billboard read at all")
            XCTAssertEqual(USBWatcher.billboardReadCount, 0)
        }
    }

    /// The non-vacuity half. Without it, `testGateOffIssuesNoRead` would pass on
    /// a machine with no USB devices by proving zero twice. Skips rather than
    /// fails on a bare host, so the suite never depends on what is plugged in.
    func testGateOnIssuesAtLeastOneReadWhenDevicesArePresent() throws {
        try withRestoredStatics {
            var calls = 0
            USBWatcher.billboardReader = { _ in calls += 1; return nil }
            USBWatcher.probeBillboardDescriptors = true
            USBWatcher.billboardReadCount = 0

            let watcher = USBWatcher()
            watcher.start()
            defer { watcher.stop() }

            try XCTSkipIf(watcher.devices.isEmpty,
                          "No USB devices enumerated on this host, so there is nothing for the gate-on case to observe")
            XCTAssertGreaterThan(calls, 0, "Gate on with devices present must issue at least one read")
            XCTAssertEqual(USBWatcher.billboardReadCount, calls)
        }
    }

    /// Re-enumeration after the gate opens must actually re-read devices, and
    /// must NOT publish an empty list on the way (which observers would see as
    /// a mass disconnect). Replaces an earlier stop()/start() that did both.
    func testReenumerateRereadsWithoutEmptyingTheList() throws {
        try withRestoredStatics {
            USBWatcher.probeBillboardDescriptors = false
            let watcher = USBWatcher()
            watcher.start()
            defer { watcher.stop() }
            try XCTSkipIf(watcher.devices.isEmpty, "No USB devices enumerated on this host")
            let before = watcher.devices.count

            // Watch every published value, so an empty intermediate would be seen.
            var published: [Int] = []
            let sub = watcher.$devices.sink { published.append($0.count) }
            defer { sub.cancel() }

            var calls = 0
            USBWatcher.billboardReader = { _ in calls += 1; return nil }
            USBWatcher.probeBillboardDescriptors = true
            watcher.reenumerate()

            XCTAssertEqual(watcher.devices.count, before, "Re-enumeration should find the same devices")
            XCTAssertGreaterThan(calls, 0, "The re-read must go through the now-open gate")
            XCTAssertFalse(published.dropFirst().contains(0),
                           "Re-enumeration must not publish an empty device list: observers read that as a mass disconnect")
        }
    }
}
