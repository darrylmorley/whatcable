import XCTest
@testable import WhatCableCore

final class PDVDOTests: XCTestCase {

    // MARK: - ID Header

    func testDecodePassiveCableIDHeader() {
        // ufpProductType = 3 (passive cable) -> bits 29..27 = 011
        // vendorID = 0x1234
        // 3 << 27 = 0x1800_0000
        let vdo: UInt32 = 0x1800_0000 | 0x1234
        let header = PDVDO.decodeIDHeader(vdo)
        XCTAssertEqual(header.ufpProductType, .passiveCable)
        XCTAssertEqual(header.vendorID, 0x1234)
        XCTAssertFalse(header.modalOperation)
        XCTAssertFalse(header.usbCommHost)
    }

    func testDecodeActiveCableIDHeader() {
        // ufpProductType = 4 (active cable) -> bits 29..27 = 100
        // 4 << 27 = 0x2000_0000
        let vdo: UInt32 = 0x2000_0000 | 0x05AC // Apple vendor
        let header = PDVDO.decodeIDHeader(vdo)
        XCTAssertEqual(header.ufpProductType, .activeCable)
        XCTAssertEqual(header.vendorID, 0x05AC)
    }

    func testDecodeUSBCommBits() {
        // bits 31 + 30 set; vendor 0
        let vdo: UInt32 = 0xC000_0000
        let header = PDVDO.decodeIDHeader(vdo)
        XCTAssertTrue(header.usbCommHost)
        XCTAssertTrue(header.usbCommDevice)
    }

    // MARK: - Cable VDO
    //
    // Layout (low bits): speed [2:0], _, vbus-through [4], current [6:5], _, maxV [10:9]

    func testThunderboltCable_5A_40Gbps() {
        // speed=3 (USB4 Gen3), current=2 (5A) -> 2<<5=0x40, vbus-through bit 4=1
        let vdo: UInt32 = 0b011 | (1 << 4) | (2 << 5)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.speed, .usb4Gen3)
        XCTAssertEqual(cable.current, .fiveAmp)
        XCTAssertTrue(cable.vbusThroughCable)
        XCTAssertEqual(cable.maxVoltageEncoded, 0)
        XCTAssertEqual(cable.maxVolts, 20)
        XCTAssertEqual(cable.maxWatts, 100) // 20V * 5A
        XCTAssertEqual(cable.cableType, .passive)
    }

    func testCheap_USB2_3A() {
        // speed=0 (USB 2.0), current=1 (3A) -> 1<<5=0x20
        let vdo: UInt32 = 0b000 | (1 << 5)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.speed, .usb20)
        XCTAssertEqual(cable.current, .threeAmp)
        XCTAssertEqual(cable.maxWatts, 60) // 20V * 3A
    }

    func testEPRCable_50V_5A() {
        // speed=4 (USB4 Gen4 / 80 Gbps), current=2 (5A), maxV=3 (50V)
        let vdo: UInt32 = 0b100 | (2 << 5) | (3 << 9)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.speed, .usb4Gen4)
        XCTAssertEqual(cable.current, .fiveAmp)
        XCTAssertEqual(cable.maxVoltageEncoded, 3)
        XCTAssertEqual(cable.maxVolts, 50)
        XCTAssertEqual(cable.maxWatts, 250) // 50V * 5A — EPR cable
    }

    func testActiveCableType() {
        let vdo: UInt32 = 0
        let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
        XCTAssertEqual(cable.cableType, .active)
    }

    // MARK: - VDO from Data

    func testVDOFromData_LittleEndian() {
        // 0xDEADBEEF stored little-endian = EF BE AD DE
        let data = Data([0xEF, 0xBE, 0xAD, 0xDE])
        XCTAssertEqual(PDVDO.vdoFromData(data), 0xDEADBEEF)
    }

    func testVDOFromData_TooShort() {
        XCTAssertNil(PDVDO.vdoFromData(Data([0x01, 0x02])))
    }
}
