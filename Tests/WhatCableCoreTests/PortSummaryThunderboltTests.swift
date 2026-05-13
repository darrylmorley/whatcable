import XCTest
@testable import WhatCableCore

/// Phase 3 integration: PortSummary should pull TB fabric data through and
/// emit specific link-state bullets when a port has a matching switch graph.
/// Anchored against Joe's M2 Pro + ASUS PA32QCV (USB4) + CalDigit TS3 Plus
/// daisy-chain from issue #52.
final class PortSummaryThunderboltTests: XCTestCase {

    // MARK: - Fixtures

    private func tbPort(socket: String) -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-USB-C@\(socket)",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@\(socket)",
            portTypeDescription: "USB-C",
            portNumber: Int(socket),
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            transportsActive: ["CIO"],
            transportsProvisioned: ["CC"],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: [:]
        )
    }

    private func lanePort(
        portNumber: Int,
        socketID: String?,
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

    private func sw(
        uid: Int64,
        depth: Int,
        parent: Int64?,
        upstreamPort: Int = 0,
        vendor: String,
        model: String,
        ports: [ThunderboltPort]
    ) -> ThunderboltSwitch {
        ThunderboltSwitch(
            id: uid,
            className: "IOThunderboltSwitchType5",
            vendorID: 1452,
            vendorName: vendor,
            modelName: model,
            routerID: 0,
            depth: depth,
            routeString: 0,
            upstreamPortNumber: upstreamPort,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: ports,
            parentSwitchUID: parent
        )
    }

    // MARK: - Single-hop (host + one device)

    func testHostUsb4LinkProducesSpecificBullet() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let device = sw(
            uid: 200, depth: 1, parent: 100, upstreamPort: 1,
            vendor: "ASUS-Display", model: "PA32QCV",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )

        let summary = PortSummary(
            port: port,
            thunderboltSwitches: [host, device]
        )

        XCTAssertTrue(
            summary.bullets.contains("Linked at up to 20 Gb/s × 2"),
            "expected USB4 link label, got: \(summary.bullets)"
        )
        XCTAssertTrue(
            summary.bullets.contains("Connected to ASUS-Display PA32QCV"),
            "expected single-hop device label, got: \(summary.bullets)"
        )
    }

    func testTb3LinkProducesTb3Bullet() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x2)]
        )

        let summary = PortSummary(port: port, thunderboltSwitches: [host])
        XCTAssertTrue(summary.bullets.contains("Linked at up to 10 Gb/s × 2"))
    }

    // MARK: - Daisy-chain step-down (the headline UX)

    func testDaisyChainStepDownIsSurfaced() {
        // Joe's topology: USB4 to ASUS, TS3 Plus daisy-chained off the
        // ASUS at TB3 single-lane.
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let asus = sw(
            uid: 200, depth: 1, parent: 100, upstreamPort: 1,
            vendor: "ASUS-Display", model: "PA32QCV",
            ports: [
                lanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2),
                lanePort(portNumber: 4, socketID: nil, speed: .tb3, widthRaw: 0x1)
            ]
        )
        let ts3 = sw(
            uid: 300, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "CalDigit, Inc.", model: "TS3 Plus",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .tb3, widthRaw: 0x1)]
        )

        let summary = PortSummary(
            port: port,
            thunderboltSwitches: [host, asus, ts3]
        )

        XCTAssertTrue(
            summary.bullets.contains("Linked at up to 20 Gb/s × 2"),
            "host link bullet missing; got: \(summary.bullets)"
        )
        XCTAssertTrue(
            summary.bullets.contains("Connected via 2 hops: ASUS-Display PA32QCV → CalDigit, Inc. TS3 Plus"),
            "daisy-chain device list missing; got: \(summary.bullets)"
        )
        XCTAssertTrue(
            summary.bullets.contains { $0.contains("Last leg drops from up to 20 Gb/s × 2 to up to 10 Gb/s × 1") },
            "step-down bullet missing; got: \(summary.bullets)"
        )
    }

    // MARK: - Single-hop must NOT trigger step-down

    /// Regression: in Steve's TB3 sample, the host port reports
    /// `Current Link Width = 2` while the Samsung's upstream port reports
    /// `Current Link Width = 1` for the same physical cable. That's just
    /// the controller-side view aggregating lanes the device-side view
    /// doesn't; it's not a real step-down. Step-down only fires for
    /// daisy-chains with two or more downstream switches.
    func testSingleHopDoesNotEmitStepDown() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x2)]
        )
        // Samsung-style single device: upstream port reports the same
        // link from the device side with a different width value.
        let samsung = sw(
            uid: 200, depth: 1, parent: 100, upstreamPort: 1,
            vendor: "SAMSUNG ELECTRONICS CO.,LTD", model: "C34J79x",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .tb3, widthRaw: 0x1)]
        )

        let summary = PortSummary(port: port, thunderboltSwitches: [host, samsung])
        XCTAssertFalse(
            summary.bullets.contains { $0.contains("Last leg drops") },
            "single-hop must not emit step-down warning; got: \(summary.bullets)"
        )
        // Sanity: the single-hop bullets we DO want should still be there.
        XCTAssertTrue(
            summary.bullets.contains("Connected to SAMSUNG ELECTRONICS CO.,LTD C34J79x"),
            "device label still required"
        )
    }

    // MARK: - Fallback when no matching switch is found

    func testFallsBackToGenericLabelWhenNoMatchingSwitch() {
        let port = tbPort(socket: "1")
        // Switch list is empty: PortSummary should fall back to the
        // pre-Phase-3 generic line so we don't regress on machines without
        // the watcher data.
        let summary = PortSummary(port: port, thunderboltSwitches: [])
        XCTAssertTrue(
            summary.bullets.contains("Thunderbolt / USB4 link active"),
            "expected fallback bullet when no switch data; got: \(summary.bullets)"
        )
    }

    // MARK: - TB5 confirmed (issue #52: M5 Pro + UGreen JHL9580 dock)

    func testTb5LinkRendersWithPerLaneLabel() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .tb5, widthRaw: 0x2)]
        )
        let summary = PortSummary(port: port, thunderboltSwitches: [host])
        XCTAssertTrue(
            summary.bullets.contains { $0.contains("40 Gb/s") },
            "TB5 should report per-lane 40 Gb/s; got: \(summary.bullets)"
        )
        XCTAssertFalse(
            summary.bullets.contains { $0.contains("Unknown generation") },
            "TB5 should no longer be hedged; got: \(summary.bullets)"
        )
    }
}
