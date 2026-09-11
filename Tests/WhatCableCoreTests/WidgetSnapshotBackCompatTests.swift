import XCTest
@testable import WhatCableCore

final class WidgetSnapshotBackCompatTests: XCTestCase {
    func testDecodesPrePowerStateSnapshot() throws {
        let json = """
        {
            "ports": [
                {
                    "id": 1,
                    "portName": "USB-C Port 1",
                    "status": "charging",
                    "headline": "Charging - 96W charger",
                    "subtitle": "Power is flowing.",
                    "topBullet": "Charger advertises up to 96W",
                    "iconName": "bolt.fill",
                    "deviceCount": 0,
                    "recentPower": [12.5, 13.0]
                },
                {
                    "id": 2,
                    "portName": "USB-C Port 2",
                    "status": "empty",
                    "headline": "Nothing connected",
                    "subtitle": "Plug a cable in.",
                    "iconName": "powerplug"
                }
            ],
            "timestamp": 738835200.0
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(snapshot.ports.count, 2)
        XCTAssertNil(snapshot.powerState)

        let port1 = snapshot.ports[0]
        XCTAssertEqual(port1.id, 1)
        XCTAssertEqual(port1.portName, "USB-C Port 1")
        XCTAssertEqual(port1.status, .charging)
        XCTAssertEqual(port1.headline, "Charging - 96W charger")
        XCTAssertEqual(port1.deviceCount, 0)
        XCTAssertEqual(port1.recentPower, [12.5, 13.0])
        XCTAssertNil(port1.portKey)
        XCTAssertNil(port1.chargerWatts)
        // Fields added after this JSON was written must default to nil.
        XCTAssertNil(port1.linkSpeed)
        XCTAssertNil(port1.displayMode)
        XCTAssertNil(port1.monitorName)
        XCTAssertEqual(port1.displayCount, 0)
        XCTAssertNil(port1.accessoryName)

        let port2 = snapshot.ports[1]
        XCTAssertEqual(port2.id, 2)
        XCTAssertEqual(port2.status, .empty)
        XCTAssertEqual(port2.deviceCount, 0)
        XCTAssertEqual(port2.recentPower, [])
        XCTAssertNil(port2.portKey)
        XCTAssertNil(port2.chargerWatts)
    }

    func testDecodesSnapshotWithLinkSpeedAndDisplay() throws {
        let json = """
        {
            "ports": [
                {
                    "id": 1,
                    "portName": "USB-C Port 1",
                    "status": "displayCable",
                    "headline": "Display connected",
                    "subtitle": "DisplayPort video over USB-C Alt Mode.",
                    "iconName": "display",
                    "linkSpeed": { "tier": "tb40", "badge": "40G" },
                    "displayMode": "5K 60Hz",
                    "monitorName": "Studio Display"
                }
            ],
            "timestamp": 738835200.0
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: json)
        let port = try XCTUnwrap(snapshot.ports.first)
        XCTAssertEqual(port.linkSpeed?.tier, .tb40)
        XCTAssertEqual(port.linkSpeed?.badge, "40G")
        XCTAssertEqual(port.displayMode, "5K 60Hz")
        XCTAssertEqual(port.monitorName, "Studio Display")
    }

    func testDecodesSnapshotWithPowerState() throws {
        let json = """
        {
            "ports": [
                {
                    "id": 1,
                    "portName": "USB-C Port 1",
                    "status": "charging",
                    "headline": "Charging",
                    "subtitle": "Power is flowing.",
                    "iconName": "bolt.fill",
                    "portKey": "2/1",
                    "chargerWatts": 96
                }
            ],
            "timestamp": 738835200.0,
            "powerState": {
                "batteryPercent": 78,
                "isCharging": true,
                "fullyCharged": false,
                "isDesktopMac": false,
                "adapterWatts": 96,
                "adapterDescription": "pd charger"
            }
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(snapshot.ports.count, 1)
        XCTAssertEqual(snapshot.ports[0].portKey, "2/1")
        XCTAssertEqual(snapshot.ports[0].chargerWatts, 96)

        let power = try XCTUnwrap(snapshot.powerState)
        XCTAssertEqual(power.batteryPercent, 78)
        XCTAssertTrue(power.isCharging)
        XCTAssertFalse(power.fullyCharged)
        XCTAssertFalse(power.isDesktopMac)
        XCTAssertEqual(power.adapterWatts, 96)
        XCTAssertEqual(power.adapterDescription, "pd charger")
        XCTAssertNil(power.systemPowerInWatts)
        XCTAssertNil(power.perPortWatts)
        XCTAssertEqual(power.recentSystemPower, [])
    }
}
