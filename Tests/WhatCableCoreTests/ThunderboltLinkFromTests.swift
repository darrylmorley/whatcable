import XCTest
@testable import WhatCableCore

/// Covers `ThunderboltSwitch.from(...)` and `ThunderboltPort.from(...)` —
/// the pure factories the watcher uses to turn raw IOKit property
/// dictionaries into model values. Fixture dictionaries are transcribed
/// from real `whatcable --tb-debug` paste-backs on issue #52, so the keys
/// and shapes match what live machines actually report.
///
/// Two real topologies anchor the tests:
/// - Steve's M3 Air + Samsung C34J79x via TB3 (one downstream switch)
/// - Joe's M2 Pro + ASUS PA32QCV (USB4) + CalDigit TS3 Plus daisy-chain
///   (downstream + sub-downstream)
final class ThunderboltLinkFromTests: XCTestCase {

    // MARK: - LinkGeneration enum

    func testLinkGenerationKnownCodes() {
        XCTAssertEqual(LinkGeneration.from(rawSpeedCode: 0x8), .tb3)
        XCTAssertEqual(LinkGeneration.from(rawSpeedCode: 0x4), .usb4Tb4)
        XCTAssertEqual(LinkGeneration.from(rawSpeedCode: 0x2), .tb5)
    }

    func testLinkGenerationIdleReturnsNil() {
        XCTAssertNil(LinkGeneration.from(rawSpeedCode: 0))
    }

    func testLinkGenerationUnknownCode() {
        // Forward-compat: a future generation should not crash the parser.
        XCTAssertEqual(LinkGeneration.from(rawSpeedCode: 0x1), .unknown(rawSpeedCode: 0x1))
    }

    func testLinkGenerationPerLaneGbps() {
        XCTAssertEqual(LinkGeneration.tb3.perLaneGbps, 10)
        XCTAssertEqual(LinkGeneration.usb4Tb4.perLaneGbps, 20)
        XCTAssertEqual(LinkGeneration.tb5.perLaneGbps, 40)
        XCTAssertNil(LinkGeneration.unknown(rawSpeedCode: 0x1).perLaneGbps)
    }

    // MARK: - LinkWidth bitmask

    func testLinkWidthSingle() {
        let w = LinkWidth(rawValue: 0x1)
        XCTAssertTrue(w.single)
        XCTAssertFalse(w.dual)
        XCTAssertEqual(w.txLanes, 1)
        XCTAssertEqual(w.rxLanes, 1)
        XCTAssertTrue(w.isActive)
    }

    func testLinkWidthDual() {
        let w = LinkWidth(rawValue: 0x2)
        XCTAssertFalse(w.single)
        XCTAssertTrue(w.dual)
        XCTAssertEqual(w.txLanes, 2)
        XCTAssertEqual(w.rxLanes, 2)
    }

    func testLinkWidthAsymmetricTx() {
        // 3 TX / 1 RX. TB5 only; we have no real sample yet but the
        // model has to handle it without breaking.
        let w = LinkWidth(rawValue: 0x4)
        XCTAssertTrue(w.asymmetricTx)
        XCTAssertEqual(w.txLanes, 3)
        XCTAssertEqual(w.rxLanes, 1)
    }

    func testLinkWidthAsymmetricRx() {
        let w = LinkWidth(rawValue: 0x8)
        XCTAssertTrue(w.asymmetricRx)
        XCTAssertEqual(w.txLanes, 1)
        XCTAssertEqual(w.rxLanes, 3)
    }

    func testLinkWidthIdle() {
        let w = LinkWidth(rawValue: 0)
        XCTAssertFalse(w.isActive)
        XCTAssertEqual(w.txLanes, 0)
    }

    // MARK: - TargetLinkWidth (different encoding from current width)

    func testTargetLinkWidthSingle() {
        XCTAssertEqual(TargetLinkWidth.from(rawValue: 0x1), .single)
    }

    /// `Target Link Width = 3` is the named DUAL register value, NOT
    /// asymmetric. This was a footgun the planning doc nearly baked in.
    func testTargetLinkWidthThreeMeansDual() {
        XCTAssertEqual(TargetLinkWidth.from(rawValue: 0x3), .dual)
    }

    func testTargetLinkWidthUnknown() {
        XCTAssertEqual(TargetLinkWidth.from(rawValue: 0x7), .unknown(rawValue: 0x7))
    }

    // MARK: - SupportedSpeedMask

    /// Apple TB4-class controllers report 12 (0x4 | 0x8) on every host root
    /// we've seen so far.
    func testSupportedSpeedMaskTb4Class() {
        let m = SupportedSpeedMask(rawValue: 12)
        XCTAssertTrue(m.supportsTb3)
        XCTAssertTrue(m.supportsUsb4Tb4)
        XCTAssertFalse(m.supportsTb5)
    }

    /// A future TB5 controller should report 14 (0x2 | 0x4 | 0x8). Verified
    /// by inference only; no real sample yet.
    func testSupportedSpeedMaskTb5Class() {
        let m = SupportedSpeedMask(rawValue: 14)
        XCTAssertTrue(m.supportsTb5)
        XCTAssertTrue(m.supportsUsb4Tb4)
        XCTAssertTrue(m.supportsTb3)
    }

    // MARK: - AdapterType decoding

    func testAdapterTypeDecoding() {
        XCTAssertEqual(AdapterType.from(rawValue: 0), .inactive)
        XCTAssertEqual(AdapterType.from(rawValue: 1), .lane)
        XCTAssertEqual(AdapterType.from(rawValue: 2), .nhi)
        XCTAssertEqual(AdapterType.from(rawValue: 0x0e0101), .dpIn)
        XCTAssertEqual(AdapterType.from(rawValue: 0x0e0102), .dpOut)
        XCTAssertEqual(AdapterType.from(rawValue: 0x100101), .pcieDown)
        XCTAssertEqual(AdapterType.from(rawValue: 0x100102), .pcieUp)
        XCTAssertEqual(AdapterType.from(rawValue: 0x200101), .usb3Down)
        XCTAssertEqual(AdapterType.from(rawValue: 0x200102), .usb3Up)
        XCTAssertEqual(AdapterType.from(rawValue: 0xdeadbe), .other(0xdeadbe))
    }

    func testAdapterTypeDecimalValuesFromIokit() {
        // The IOKit dumps print these as decimals; sanity-check the
        // hex-to-decimal conversions.
        XCTAssertEqual(AdapterType.from(rawValue: 917761), .dpIn)
        XCTAssertEqual(AdapterType.from(rawValue: 917762), .dpOut)
        XCTAssertEqual(AdapterType.from(rawValue: 1048833), .pcieDown)
        XCTAssertEqual(AdapterType.from(rawValue: 1048834), .pcieUp)
        XCTAssertEqual(AdapterType.from(rawValue: 2097409), .usb3Down)
        XCTAssertEqual(AdapterType.from(rawValue: 2097410), .usb3Up)
    }

    // MARK: - Steve's Samsung C34J79x downstream switch (TB3)

    /// Switch #3 from issue #52 comment 1: Samsung C34J79x at Depth=1.
    private var samsungSwitch: [String: Any] {
        [
            "UID": NSNumber(value: Int64(105094508797638400)),
            "Vendor ID": NSNumber(value: 32902),
            "Device Vendor ID": NSNumber(value: 373),
            "Device Vendor Name": "SAMSUNG ELECTRONICS CO.,LTD",
            "Device Model Name": "C34J79x",
            "Router ID": NSNumber(value: 0),
            "Depth": NSNumber(value: 1),
            "Route String": NSNumber(value: 1),
            "Upstream Port Number": NSNumber(value: 3),
            "Max Port Number": NSNumber(value: 13),
            "Supported Link Speed": NSNumber(value: 12)
        ]
    }

    /// Active TB3 link from the same dump: host port @1 (Lane 1) with
    /// `Current Link Speed = 8`, `Width = 2`, `Link Bandwidth = 200`.
    private var hostTb3Port: [String: Any] {
        [
            "Adapter Type": NSNumber(value: 1),
            "Port Number": NSNumber(value: 1),
            "Socket ID": "1",
            "Current Link Speed": NSNumber(value: 8),
            "Current Link Width": NSNumber(value: 2),
            "Target Link Speed": NSNumber(value: 12),
            "Target Link Width": NSNumber(value: 3),
            "Supported Link Speed": NSNumber(value: 12),
            "Supported Link Width": NSNumber(value: 2),
            "Link Bandwidth": NSNumber(value: 200)
        ]
    }

    func testSamsungSwitchParses() {
        let model = ThunderboltSwitch.from(
            properties: samsungSwitch,
            className: "IOThunderboltSwitchType3",
            ports: []
        )
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.id, 105094508797638400)
        XCTAssertEqual(model?.depth, 1)
        XCTAssertEqual(model?.routeString, 1)
        XCTAssertEqual(model?.modelName, "C34J79x")
        XCTAssertEqual(model?.vendorName, "SAMSUNG ELECTRONICS CO.,LTD")
        XCTAssertEqual(model?.upstreamPortNumber, 3)
        XCTAssertFalse(model?.isHostRoot ?? true)
    }

    func testHostTb3PortParsesAsActiveTb3Link() {
        let port = ThunderboltPort.from(properties: hostTb3Port)
        XCTAssertNotNil(port)
        XCTAssertEqual(port?.adapterType, .lane)
        XCTAssertEqual(port?.socketID, "1")
        XCTAssertEqual(port?.currentSpeed, .tb3)
        XCTAssertEqual(port?.perLaneGbps, 10)
        XCTAssertEqual(port?.currentWidth?.dual, true)
        XCTAssertEqual(port?.txLanes, 2)
        XCTAssertEqual(port?.targetWidth, .dual)
        XCTAssertEqual(port?.linkBandwidthRaw, 200)
        XCTAssertTrue(port?.hasActiveLink ?? false)
    }

    // MARK: - Joe's daisy-chain (USB4 + TB3 step-down)

    /// ASUS PA32QCV at Depth=1 via Intel JHL8440 controller.
    private var asusSwitch: [String: Any] {
        [
            // ASUS UID is negative in IOKit (Int64 sign bit set). This is
            // exactly why the model uses Int64 rather than UInt64.
            "UID": NSNumber(value: Int64(-9185256489162756864)),
            "Vendor ID": NSNumber(value: 32903),
            "Device Vendor ID": NSNumber(value: 2821),
            "Device Vendor Name": "ASUS-Display",
            "Device Model Name": "PA32QCV",
            "Router ID": NSNumber(value: 0),
            "Depth": NSNumber(value: 1),
            "Route String": NSNumber(value: 1),
            "Upstream Port Number": NSNumber(value: 1),
            "Max Port Number": NSNumber(value: 19),
            "Supported Link Speed": NSNumber(value: 12)
        ]
    }

    /// Host port @1 on Joe's M2 Pro: USB4 link to the ASUS, speed=4, width=2.
    private var hostUsb4Port: [String: Any] {
        [
            "Adapter Type": NSNumber(value: 1),
            "Port Number": NSNumber(value: 1),
            "Socket ID": "1",
            "Current Link Speed": NSNumber(value: 4),
            "Current Link Width": NSNumber(value: 2),
            "Target Link Speed": NSNumber(value: 12),
            "Target Link Width": NSNumber(value: 3),
            "Link Bandwidth": NSNumber(value: 400)
        ]
    }

    /// CalDigit TS3 Plus at Depth=2, Route String=769 (= 0x301: entered
    /// ASUS port 3, then host port 1).
    private var ts3PlusSwitch: [String: Any] {
        [
            "UID": NSNumber(value: Int64(17188550068006400)),
            "Vendor ID": NSNumber(value: 32902),
            "Device Vendor ID": NSNumber(value: 61),
            "Device Vendor Name": "CalDigit, Inc.",
            "Device Model Name": "TS3 Plus",
            "Router ID": NSNumber(value: 0),
            "Depth": NSNumber(value: 2),
            "Route String": NSNumber(value: 769),
            "Upstream Port Number": NSNumber(value: 1),
            "Max Port Number": NSNumber(value: 11),
            "Supported Link Speed": NSNumber(value: 12)
        ]
    }

    /// TS3 Plus upstream lane port: TB3 single-lane (the step-down).
    private var ts3PlusUpstreamPort: [String: Any] {
        [
            "Adapter Type": NSNumber(value: 1),
            "Port Number": NSNumber(value: 3),
            "Current Link Speed": NSNumber(value: 8),
            "Current Link Width": NSNumber(value: 1),
            "Target Link Speed": NSNumber(value: 12),
            "Target Link Width": NSNumber(value: 1),
            "Link Bandwidth": NSNumber(value: 100)
        ]
    }

    func testHostUsb4PortDetectedAsTb4Class() {
        let port = ThunderboltPort.from(properties: hostUsb4Port)
        XCTAssertEqual(port?.currentSpeed, .usb4Tb4)
        XCTAssertEqual(port?.perLaneGbps, 20)
        XCTAssertEqual(port?.txLanes, 2)
        XCTAssertEqual(port?.linkBandwidthRaw, 400)
    }

    func testDaisyChainStepDownDetected() {
        // The interesting UX bullet for this topology is "USB4 to ASUS,
        // step-down to TB3 single-lane on the next leg". This test
        // confirms the model exposes everything a renderer needs to
        // produce that label. The renderer itself is Phase 3.
        let usb4 = ThunderboltPort.from(properties: hostUsb4Port)
        let tb3 = ThunderboltPort.from(properties: ts3PlusUpstreamPort)
        XCTAssertEqual(usb4?.currentSpeed, .usb4Tb4)
        XCTAssertEqual(tb3?.currentSpeed, .tb3)
        // Per-lane Gbps drops on the second hop. Lane count also drops.
        XCTAssertGreaterThan(usb4?.perLaneGbps ?? 0, tb3?.perLaneGbps ?? 0)
        XCTAssertGreaterThan(usb4?.txLanes ?? 0, tb3?.txLanes ?? 0)
    }

    func testTs3PlusSwitchAtDepth2() {
        let model = ThunderboltSwitch.from(
            properties: ts3PlusSwitch,
            className: "IOThunderboltSwitchType3",
            ports: []
        )
        XCTAssertEqual(model?.depth, 2)
        XCTAssertEqual(model?.routeString, 769)
        XCTAssertEqual(model?.modelName, "TS3 Plus")
    }

    func testAsusSwitchHandlesNegativeUid() {
        // Regression guard: IOKit reports some UIDs as signed Int64 with
        // the sign bit set. The model must store these without truncation.
        let model = ThunderboltSwitch.from(
            properties: asusSwitch,
            className: "IOThunderboltSwitchIntelJHL8440",
            ports: []
        )
        XCTAssertEqual(model?.id, -9185256489162756864)
        XCTAssertEqual(model?.modelName, "PA32QCV")
    }

    // MARK: - Idle / non-lane ports

    func testIdleHostPortHasNoLinkState() {
        // From the M5 Pro idle probe: lane port with everything zeroed.
        let dict: [String: Any] = [
            "Adapter Type": NSNumber(value: 1),
            "Port Number": NSNumber(value: 1),
            "Socket ID": "1",
            "Current Link Speed": NSNumber(value: 0),
            "Current Link Width": NSNumber(value: 0)
        ]
        let port = ThunderboltPort.from(properties: dict)
        XCTAssertNil(port?.currentSpeed)
        XCTAssertEqual(port?.currentWidth?.isActive, false)
        XCTAssertFalse(port?.hasActiveLink ?? true)
    }

    func testProtocolAdapterPortHasNoLinkState() {
        // PCIe adapter ports report Adapter Type but not link generation.
        // The factory should not invent a generation just because the
        // dictionary happens to contain a Link Bandwidth value.
        let dict: [String: Any] = [
            "Adapter Type": NSNumber(value: 1048833),  // PCIe down
            "Port Number": NSNumber(value: 3),
            "Link Bandwidth": NSNumber(value: 60)
        ]
        let port = ThunderboltPort.from(properties: dict)
        XCTAssertEqual(port?.adapterType, .pcieDown)
        XCTAssertNil(port?.currentSpeed)
        XCTAssertNil(port?.currentWidth)
        XCTAssertFalse(port?.hasActiveLink ?? true)
    }

    // MARK: - Missing fields

    func testSwitchWithoutUidReturnsNil() {
        let model = ThunderboltSwitch.from(
            properties: ["Vendor ID": NSNumber(value: 1)],
            className: "IOThunderboltSwitchType7",
            ports: []
        )
        XCTAssertNil(model)
    }

    func testPortWithoutPortNumberReturnsNil() {
        let port = ThunderboltPort.from(properties: ["Adapter Type": NSNumber(value: 1)])
        XCTAssertNil(port)
    }
}
