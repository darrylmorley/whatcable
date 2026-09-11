import XCTest
import Combine
import IOKit
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
        let arrivals = USBWatcher.billboardNubArrivals
        let lastNubDevice = USBWatcher.lastBillboardNubDeviceID
        defer {
            USBWatcher.billboardReader = reader
            USBWatcher.probeBillboardDescriptors = gate
            USBWatcher.billboardReadCount = count
            USBWatcher.billboardNubArrivals = arrivals
            USBWatcher.lastBillboardNubDeviceID = lastNubDevice
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

    // MARK: - Registry-first Billboard read

    /// The `UsbBillboard*` keys the Mac mini's own Billboard nub carries live
    /// (IOKit class `AppleUSBHostBillboardDevice`, two levels below the dock
    /// device), alongside the ordinary NSNumber keys a registry entry has.
    private func billboardNubDict() -> [String: Any] {
        [
            "idVendor": NSNumber(value: 0x05ac),
            "idProduct": NSNumber(value: 0x1a00),
            "UsbBillboardSupportedModes": ["SVID 0xff00 VDO 0x2687e000", "Thunderbolt", "DisplayPort"],
            "UsbBillboardCurrentMode": "SVID 0xff00 VDO 0x2687e000",
            "UsbBillboardPreferredMode": "SVID 0xff00 VDO 0x2687e000",
            "UsbBillboardVersion": "1.22",
        ]
    }

    /// A Billboard nub's alt modes come from macOS's registry keys, not from
    /// a BOS control transfer (which IOKit refuses on the nub anyway). A
    /// property read is not bus traffic, so it must work with the probe gate
    /// off and must not count as a read.
    func testBillboardNubIsReadFromRegistryWithoutAControlTransfer() throws {
        try withRestoredStatics {
            var calls = 0
            USBWatcher.billboardReader = { _ in calls += 1; return nil }
            USBWatcher.probeBillboardDescriptors = false
            USBWatcher.billboardReadCount = 0

            let capability = USBWatcher.registryBillboard(from: billboardNubDict())

            let cap = try XCTUnwrap(capability, "A nub dictionary with UsbBillboard* keys must yield a capability")
            XCTAssertEqual(cap.altModes.count, 3)
            XCTAssertEqual(cap.altModes.map(\.svid), [0xFF00, 0x8087, 0xFF01])
            XCTAssertEqual(cap.altModes[0].state, .configured)
            XCTAssertEqual(cap.altModes[1].state, .notAttempted)
            XCTAssertEqual(cap.altModes[2].state, .notAttempted)
            XCTAssertEqual(cap.preferredIndex, 0)
            XCTAssertEqual(USBWatcher.billboardReadCount, 0, "A registry read is not a control transfer")
            XCTAssertEqual(calls, 0, "The registry path must not go through the BOS reader")
        }
    }

    /// `UsbBillboardAltModeFailed` handed over as an NSNumber must still
    /// count. A live CFBoolean bridges through `as? Bool` on its own (measured),
    /// so this guards the belt-and-braces arm, not a bridging failure.
    func testAltModeFailedAsNSNumberIsHonoured() throws {
        try withRestoredStatics {
            var dict = billboardNubDict()
            dict["UsbBillboardCurrentMode"] = nil
            dict["UsbBillboardAltModeFailed"] = NSNumber(value: true)

            let cap = try XCTUnwrap(USBWatcher.registryBillboard(from: dict))
            XCTAssertTrue(cap.hasFailedAltMode)
            XCTAssertEqual(cap.altModes.count, 3)
            XCTAssertTrue(cap.altModes.allSatisfy { $0.state == .error },
                          "AltModeFailed marks every mode as failed; got \(cap.altModes.map(\.state))")
        }
    }

    /// A nub dictionary with none of the keys yields nil, so `makeDevice`
    /// falls through to the gated control transfer and the device loses
    /// nothing it had before.
    func testDictWithoutSupportedModesReturnsNil() throws {
        try withRestoredStatics {
            let dict: [String: Any] = [
                "idVendor": NSNumber(value: 0x05ac),
                "idProduct": NSNumber(value: 0x1a00),
            ]
            XCTAssertNil(USBWatcher.registryBillboard(from: dict))
        }
    }

    /// The seam tests above prove `registryBillboard` on a hand-built
    /// dictionary. This is the live-host half: it enumerates real devices
    /// through `makeDevice(from:)` and proves the child walk
    /// (`billboardNubProperties`) reaches one real `AppleUSBHostBillboardDevice`
    /// nub and fills its parent device's `billboard`, with the probe gate off.
    /// The corpus sweep in `USBWatcherCorpusSweepTests` sizes the claim across
    /// many machines; this proves the walk on the one nub this host has.
    ///
    /// The precondition is measured independently of the code under test: a
    /// direct IOKit match on the nub class. On the Mac mini this suite runs on
    /// the expected device is "TBT5 Docking Station 10-in-1" at locationID
    /// 0x00110000, with modes USB (SVID 0xFF00) configured, Thunderbolt and
    /// DisplayPort not attempted.
    func testLiveBillboardNubFillsItsParentDeviceWithTheGateOff() throws {
        try XCTSkipIf(Self.liveBillboardNubCount() == 0,
                      "No AppleUSBHostBillboardDevice nub on this host")

        try withRestoredStatics {
            var calls = 0
            USBWatcher.billboardReader = { _ in calls += 1; return nil }
            USBWatcher.probeBillboardDescriptors = false
            USBWatcher.billboardReadCount = 0

            let watcher = USBWatcher()
            watcher.start()
            defer { watcher.stop() }

            let filled = watcher.devices.filter { $0.billboard != nil }
            XCTAssertFalse(filled.isEmpty,
                           "A Billboard nub exists on this host, so its parent device must carry a registry-decoded capability")

            let device = try XCTUnwrap(filled.first)
            let cap = try XCTUnwrap(device.billboard)
            let modes = cap.altModes.map { "\($0.protocolName ?? String(format: "0x%04X", $0.svid)):\($0.state)" }
            print("Live Billboard parent: \(device.productName ?? "?") at \(String(format: "0x%08X", device.locationID)) altModes: \(modes)")

            XCTAssertGreaterThanOrEqual(cap.altModes.count, 1)
            let configuredCount = cap.altModes.filter { $0.state == .configured }.count
            XCTAssertTrue(configuredCount == 1 || cap.hasFailedAltMode,
                          "Expected exactly one configured mode or a failed alt mode; got \(modes)")

            XCTAssertEqual(USBWatcher.billboardReadCount, 0, "Gate is off: no control transfer may have been issued")
            XCTAssertEqual(calls, 0, "Gate is off: no control transfer may have been issued")
        }
    }

    /// The nub can match after its parent device has already been built (the
    /// device's matched notification does not wait for child matching), so
    /// `USBWatcher` also watches the nub class and rebuilds the one parent
    /// device when a nub arrives. That hot-plug ordering cannot be exercised
    /// here: there is no safe way to re-enumerate a device on this host. What
    /// this proves is the rest of the mechanism: `kIOFirstMatchNotification`
    /// delivers the already-present nub at registration, so the handler must
    /// have run, its parent walk must resolve to a device in the list that
    /// carries a registry-decoded capability, the replace-or-append must not
    /// duplicate that device, and none of it may issue a control transfer.
    func testBillboardNubArrivalRebuildsItsParentDevice() throws {
        try XCTSkipIf(Self.liveBillboardNubCount() == 0,
                      "No AppleUSBHostBillboardDevice nub on this host")

        try withRestoredStatics {
            var calls = 0
            USBWatcher.billboardReader = { _ in calls += 1; return nil }
            USBWatcher.probeBillboardDescriptors = false
            USBWatcher.billboardReadCount = 0
            USBWatcher.billboardNubArrivals = 0
            USBWatcher.lastBillboardNubDeviceID = nil

            let watcher = USBWatcher()
            watcher.start()
            defer { watcher.stop() }

            XCTAssertGreaterThanOrEqual(USBWatcher.billboardNubArrivals, 1,
                                        "The nub registration must deliver the already-present nub at start()")
            let resolvedID = try XCTUnwrap(USBWatcher.lastBillboardNubDeviceID,
                                           "The nub arrival must resolve to a USB device")
            let resolved = try XCTUnwrap(watcher.devices.first { $0.id == resolvedID },
                                         "The device the nub resolved to must be in the list")
            XCTAssertNotNil(resolved.billboard, "The rebuilt parent must carry the nub's registry-decoded capability")

            let ids = watcher.devices.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count,
                           "Replace-or-append must not duplicate a device; ids: \(ids)")

            XCTAssertEqual(USBWatcher.billboardReadCount, 0, "Gate is off: no control transfer may have been issued")
            XCTAssertEqual(calls, 0, "Gate is off: no control transfer may have been issued")
        }
    }

    /// How many `AppleUSBHostBillboardDevice` services IOKit matches right
    /// now. A direct class match, nothing from `USBWatcher`, so the skip
    /// decision cannot be fooled by the walk under test failing.
    private static func liveBillboardNubCount() -> Int {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleUSBHostBillboardDevice"),
            &iterator
        ) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var count = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
            count += 1
        }
        return count
    }
}
