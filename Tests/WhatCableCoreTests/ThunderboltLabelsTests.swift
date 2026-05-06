import XCTest
@testable import WhatCableCore

/// Tests for the user-facing label helpers and topology walker.
/// These cover the rendering convention chosen for Phase 3:
///   - per-lane Gb/s × lane count, matching Apple's `system_profiler`
///   - hedge wording for unknown / TB5 (TB5 stays hedged until verified)
///   - daisy-chain detection by `parentSwitchUID`
final class ThunderboltLabelsTests: XCTestCase {

    // MARK: - linkLabel

    func testLabelForTb3DualLane() {
        let port = makeLanePort(speed: .tb3, widthRaw: 0x2)
        XCTAssertEqual(ThunderboltLabels.linkLabel(for: port), "Up to 10 Gb/s × 2")
    }

    func testLabelForTb3SingleLane() {
        let port = makeLanePort(speed: .tb3, widthRaw: 0x1)
        XCTAssertEqual(ThunderboltLabels.linkLabel(for: port), "Up to 10 Gb/s × 1")
    }

    func testLabelForUsb4DualLane() {
        let port = makeLanePort(speed: .usb4Tb4, widthRaw: 0x2)
        XCTAssertEqual(ThunderboltLabels.linkLabel(for: port), "Up to 20 Gb/s × 2")
    }

    /// TB5 stays hedged until verified against real hardware. Even though
    /// the model decodes raw 0x2 to .tb5, the renderer must not promise
    /// "TB5" or "40 Gb/s" yet.
    func testLabelForTb5IsHedged() {
        let port = makeLanePort(speed: .tb5, widthRaw: 0x2)
        let label = ThunderboltLabels.linkLabel(for: port)
        XCTAssertEqual(label, "Unknown generation (raw speed code 0x2, inferred TB5)")
    }

    func testLabelForUnknownGenerationIsHedged() {
        let port = makeLanePort(speed: .unknown(rawSpeedCode: 0x1), widthRaw: 0x2)
        XCTAssertEqual(ThunderboltLabels.linkLabel(for: port), "Unknown generation (raw speed code 0x1)")
    }

    func testLabelNilForIdlePort() {
        let port = makeLanePort(speed: nil, widthRaw: 0)
        XCTAssertNil(ThunderboltLabels.linkLabel(for: port))
    }

    func testLabelForAsymmetricLink() {
        // 3 TX / 1 RX. We have no real TB5 sample, but the model must
        // produce a sensible label if one ever lands.
        let port = makeLanePort(speed: .usb4Tb4, widthRaw: 0x4)
        XCTAssertEqual(ThunderboltLabels.linkLabel(for: port), "Up to 20 Gb/s (3 TX / 1 RX)")
    }

    // MARK: - deviceName

    func testDeviceNameAsus() {
        let sw = makeSwitch(uid: 1, vendor: "ASUS-Display", model: "PA32QCV")
        XCTAssertEqual(ThunderboltLabels.deviceName(for: sw), "ASUS-Display PA32QCV")
    }

    func testDeviceNameMissingFieldsFallsBack() {
        let sw = makeSwitch(uid: 1, vendor: "", model: "")
        XCTAssertEqual(ThunderboltLabels.deviceName(for: sw), "Unknown device")
    }

    // MARK: - Topology socket-ID parsing

    func testSocketIDExtractedFromAtSuffix() {
        XCTAssertEqual(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C@1"), "1")
        XCTAssertEqual(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C@3"), "3")
    }

    func testSocketIDNilWhenNoAtSuffix() {
        XCTAssertNil(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C"))
    }

    // MARK: - Topology chain walking

    func testChainSingleHop() {
        let host = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [
            makeLanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)
        ])
        let device = makeSwitch(uid: 200, depth: 1, parent: 100, vendor: "ASUS-Display", model: "PA32QCV")
        let chain = ThunderboltTopology.chain(from: host, in: [host, device])
        XCTAssertEqual(chain.count, 2)
        XCTAssertEqual(chain.first?.id, 100)
        XCTAssertEqual(chain.last?.id, 200)
    }

    func testChainDaisyTwoHops() {
        let host = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [])
        let asus = makeSwitch(uid: 200, depth: 1, parent: 100, vendor: "ASUS-Display", model: "PA32QCV")
        let ts3 = makeSwitch(uid: 300, depth: 2, parent: 200, vendor: "CalDigit, Inc.", model: "TS3 Plus")
        let chain = ThunderboltTopology.chain(from: host, in: [host, asus, ts3])
        XCTAssertEqual(chain.map(\.id), [100, 200, 300])
    }

    // MARK: - hostRoot lookup by Socket ID

    func testHostRootMatchesBySocketID() {
        let portA = makeLanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)
        let portB = makeLanePort(portNumber: 2, socketID: "2", speed: nil, widthRaw: 0)
        let root1 = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [portA])
        let root2 = makeSwitch(uid: 200, depth: 0, parent: nil, ports: [portB])
        let device = makeSwitch(uid: 999, depth: 1, parent: 100)
        let switches = [root1, root2, device]

        XCTAssertEqual(ThunderboltTopology.hostRoot(forSocketID: "1", in: switches)?.id, 100)
        XCTAssertEqual(ThunderboltTopology.hostRoot(forSocketID: "2", in: switches)?.id, 200)
        XCTAssertNil(ThunderboltTopology.hostRoot(forSocketID: "3", in: switches))
    }

    // MARK: - activeDownstreamLanePort

    func testActiveDownstreamLanePortOnHostRoot() {
        let port1 = makeLanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)
        let root = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [port1])
        XCTAssertEqual(ThunderboltTopology.activeDownstreamLanePort(root)?.portNumber, 1)
    }

    /// On a downstream switch, the upstream lane port (matching
    /// `upstreamPortNumber`) faces the host. The downstream port is the
    /// one that goes toward the next-hop device.
    func testActiveDownstreamLanePortSkipsUpstreamOnDeepSwitch() {
        let upPort = makeLanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)
        let downPort = makeLanePort(portNumber: 4, socketID: nil, speed: .tb3, widthRaw: 0x1)
        let dock = makeSwitch(
            uid: 200, depth: 1, parent: 100,
            upstreamPortNumber: 1,
            ports: [upPort, downPort]
        )
        XCTAssertEqual(ThunderboltTopology.activeDownstreamLanePort(dock)?.portNumber, 4)
    }
}

// MARK: - Test helpers

private func makeLanePort(
    portNumber: Int = 1,
    socketID: String? = nil,
    speed: LinkGeneration?,
    widthRaw: UInt8
) -> ThunderboltPort {
    ThunderboltPort(
        portNumber: portNumber,
        socketID: socketID,
        adapterType: .lane,
        currentSpeed: speed,
        currentWidth: LinkWidth(rawValue: widthRaw),
        targetWidth: nil,
        rawTargetSpeed: nil,
        linkBandwidthRaw: nil
    )
}

private func makeSwitch(
    uid: Int64,
    depth: Int = 0,
    parent: Int64? = nil,
    upstreamPortNumber: Int = 0,
    vendor: String = "Apple Inc.",
    model: String = "iOS",
    ports: [ThunderboltPort] = []
) -> ThunderboltSwitch {
    ThunderboltSwitch(
        id: uid,
        className: "IOThunderboltSwitchType7",
        vendorID: 1452,
        vendorName: vendor,
        modelName: model,
        routerID: 0,
        depth: depth,
        routeString: 0,
        upstreamPortNumber: upstreamPortNumber,
        maxPortNumber: 8,
        supportedSpeed: SupportedSpeedMask(rawValue: 12),
        ports: ports,
        parentSwitchUID: parent
    )
}
