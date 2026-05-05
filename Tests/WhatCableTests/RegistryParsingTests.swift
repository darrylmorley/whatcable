import XCTest
@testable import WhatCableCore

final class RegistryParsingTests: XCTestCase {
    func testUSBCPortWatcherScansM4MiniFrontPortClass() {
        XCTAssertTrue(USBCPortWatcher.candidateClasses.contains("IOPort"))
    }

    func testUSBCPortWatcherExtractsBusIndexAcrossControllerNameShapes() {
        XCTAssertEqual(USBCPortWatcher.busIndex(fromRegistryName: "hpm4@3"), 4)
        XCTAssertEqual(USBCPortWatcher.busIndex(fromRegistryName: "atc1"), 1)
        XCTAssertEqual(USBCPortWatcher.busIndex(fromRegistryName: "usb-drd2@2280000"), 2)
        XCTAssertNil(USBCPortWatcher.busIndex(fromRegistryName: "hpm@3"))
        XCTAssertNil(USBCPortWatcher.busIndex(fromRegistryName: "AppleT6000USBXHCI"))
    }

    func testUSBCPortWatcherExtractsLocationFallbackAsHex() {
        XCTAssertEqual(USBCPortWatcher.busIndex(fromLocation: "1"), 1)
        XCTAssertEqual(USBCPortWatcher.busIndex(fromLocation: "0A"), 10)
        XCTAssertNil(USBCPortWatcher.busIndex(fromLocation: ""))
        XCTAssertNil(USBCPortWatcher.busIndex(fromLocation: "Port-USB-C"))
    }

    func testUSBWatcherParsesUsbIOPortStringAndData() {
        let path = "AppleARMIO/Port-USB-C@1"
        XCTAssertEqual(USBWatcher.usbIOPortPath(from: path), path)

        let data = Data("AppleARMIO/Port-USB-C@2\u{0}".utf8)
        XCTAssertEqual(USBWatcher.usbIOPortPath(from: data), "AppleARMIO/Port-USB-C@2")
    }

    func testUSBWatcherExtractsPortNameAndBusIndex() {
        XCTAssertEqual(
            USBWatcher.portName(fromUSBIOPortPath: "AppleARMIO/Port-USB-C@1"),
            "Port-USB-C@1"
        )
        XCTAssertNil(USBWatcher.portName(fromUSBIOPortPath: "AppleARMIO/AppleUSBHostPort@1"))
        XCTAssertEqual(USBWatcher.busIndex(fromLocationID: 0x0300_0000), 3)
    }

    func testPowerSourceWatcherHandlesBuiltInParentFieldsAndPriorityFallback() {
        let builtIn: [String: Any] = [
            "ParentBuiltInPortType": NSNumber(value: 0x11),
            "ParentBuiltInPortNumber": NSNumber(value: 2),
            "ParentPortType": NSNumber(value: 2),
            "ParentPortNumber": NSNumber(value: 1)
        ]
        let builtInParent = PowerSourceWatcher.parentPortIdentity(from: builtIn)
        XCTAssertEqual(builtInParent.type, 0x11)
        XCTAssertEqual(builtInParent.number, 2)

        let priority: [String: Any] = [
            "ParentPortType": NSNumber(value: 0x11),
            "Priority": NSNumber(value: 0x0201)
        ]
        let priorityParent = PowerSourceWatcher.parentPortIdentity(from: priority)
        XCTAssertEqual(priorityParent.type, 0x11)
        XCTAssertEqual(priorityParent.number, 1)
    }

    func testPDIdentityWatcherHandlesMagSafeCCAndSOP1Metadata() {
        let dict: [String: Any] = [
            "TransportTypeDescription": "CC",
            "ParentBuiltInPortType": NSNumber(value: 0x11),
            "ParentBuiltInPortNumber": NSNumber(value: 1),
            "Metadata": [
                "Vendor ID (SOP1)": NSNumber(value: 0x05AC),
                "Product ID (SOP1)": NSNumber(value: 0x1234),
                "bcdDevice": NSNumber(value: 0x0100)
            ]
        ]
        let metadata = PDIdentityWatcher.metadataDictionary(from: dict)
        let parent = PDIdentityWatcher.parentPortIdentity(from: dict)

        XCTAssertEqual(PDIdentityWatcher.endpoint(from: dict), .sopPrime)
        XCTAssertEqual(parent.type, 0x11)
        XCTAssertEqual(parent.number, 1)
        XCTAssertEqual(PDIdentityWatcher.vendorID(from: dict, metadata: metadata), 0x05AC)
        XCTAssertEqual(PDIdentityWatcher.productID(from: dict, metadata: metadata), 0x1234)
        XCTAssertEqual(PDIdentityWatcher.bcdDevice(from: metadata), 0x0100)
    }
}
