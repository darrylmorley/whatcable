import XCTest
@testable import WhatCableCore

/// Tests the USB device-to-port matching logic used in the UI.
/// Since the actual matching logic is currently in `ContentView.swift`
/// (an internal view function), these tests simulate that logic.
final class USBDeviceMatchingTests: XCTestCase {

    // MARK: - Simulation of matching logic

    private func matchingDevices(for port: USBCPort, allDevices: [USBDevice]) -> [USBDevice] {
        guard port.connectionActive == true else { return [] }
        
        // 1. Try matches by name (highest confidence).
        let byName = allDevices.filter { d in
            guard let dPort = d.controllerPortName else { return false }
            return dPort == port.serviceName || 
                   dPort.hasPrefix(port.serviceName) || 
                   port.serviceName.hasPrefix(dPort)
        }
        if !byName.isEmpty {
            return byName
        }
        
        // 2. Fall back to busIndex for devices that don't have a port name,
        // provided the port itself is active for USB and has a bus index.
        let portCarriesUSB = port.usbActive == true || 
                            port.superSpeedActive == true ||
                            port.transportsActive.contains { ["USB2", "USB3", "USB4", "CIO"].contains($0) }
                            
        guard portCarriesUSB, let portBus = port.busIndex else { return [] }
        
        return allDevices.filter { d in
            d.controllerPortName == nil && d.busIndex == portBus
        }
    }

    // MARK: - Helpers

    private func makePort(name: String, bus: Int? = nil, active: Bool = true, transports: [String] = ["USB2"]) -> USBCPort {
        USBCPort(
            id: UInt64(abs(name.hashValue)),
            serviceName: name,
            className: "AppleHPMInterfaceType10",
            portDescription: name,
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: active,
            activeCable: false,
            opticalCable: false,
            usbActive: true,
            superSpeedActive: false,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [],
            transportsActive: transports,
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            busIndex: bus,
            rawProperties: [:]
        )
    }

    private func makeDevice(id: UInt64, name: String, portName: String? = nil, bus: Int? = nil) -> USBDevice {
        USBDevice(
            id: id,
            locationID: 0,
            vendorID: 0,
            productID: 0,
            vendorName: "Vendor",
            productName: name,
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: nil,
            busPowerMA: nil,
            currentMA: nil,
            busIndex: bus,
            controllerPortName: portName,
            rawProperties: [:]
        )
    }

    // MARK: - Tests

    func testMatchesByExactPortName() {
        let port = makePort(name: "Port-USB-C@1")
        let dev = makeDevice(id: 1, name: "Disk", portName: "Port-USB-C@1")
        
        let matches = matchingDevices(for: port, allDevices: [dev])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.productName, "Disk")
    }

    func testMatchesByPortNameVariation_Prefix() {
        let port = makePort(name: "Port-USB-C@1")
        let dev = makeDevice(id: 1, name: "Disk", portName: "Port-USB-C") // Device says base name
        
        let matches = matchingDevices(for: port, allDevices: [dev])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.productName, "Disk")
    }

    func testMatchesByPortNameVariation_Suffix() {
        let port = makePort(name: "Port-USB-C")
        let dev = makeDevice(id: 1, name: "Disk", portName: "Port-USB-C@1") // Device says decorated name
        
        let matches = matchingDevices(for: port, allDevices: [dev])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.productName, "Disk")
    }

    func testFallsBackToBusIndexWhenNoPortNameAvailable() {
        // This simulates M1/M2 behavior where UsbIOPort might be missing.
        let port = makePort(name: "Port-USB-C@1", bus: 0)
        let dev = makeDevice(id: 1, name: "Disk", portName: nil, bus: 0)
        
        let matches = matchingDevices(for: port, allDevices: [dev])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.productName, "Disk")
    }

    func testMixedMatching_PortNameTakesPrecedence() {
        // If a device HAS a port name, it should only match that port.
        // It should NOT match via bus index if it would collide with another port.
        let port1 = makePort(name: "Port-USB-C@1", bus: 0)
        let port2 = makePort(name: "Port-USB-C@2", bus: 1)
        
        let dev1 = makeDevice(id: 1, name: "Disk1", portName: "Port-USB-C@1", bus: 0)
        let dev2 = makeDevice(id: 2, name: "Disk2", portName: nil, bus: 1)
        
        let allDevices = [dev1, dev2]
        
        let matches1 = matchingDevices(for: port1, allDevices: allDevices)
        XCTAssertEqual(matches1.count, 1)
        XCTAssertEqual(matches1.first?.productName, "Disk1")
        
        let matches2 = matchingDevices(for: port2, allDevices: allDevices)
        XCTAssertEqual(matches2.count, 1)
        XCTAssertEqual(matches2.first?.productName, "Disk2")
    }

    func testDoesNotMatchDevicesOnOtherBuses() {
        let port = makePort(name: "Port-USB-C@1", bus: 0)
        let dev = makeDevice(id: 1, name: "OtherDisk", portName: nil, bus: 1)
        
        let matches = matchingDevices(for: port, allDevices: [dev])
        XCTAssertTrue(matches.isEmpty)
    }

    func testMatchesMultipleDevicesOnSameBus() {
        let port = makePort(name: "Port-USB-C@1", bus: 0)
        let dev1 = makeDevice(id: 1, name: "Hub", portName: nil, bus: 0)
        let dev2 = makeDevice(id: 2, name: "Disk", portName: nil, bus: 0)
        
        let matches = matchingDevices(for: port, allDevices: [dev1, dev2])
        XCTAssertEqual(matches.count, 2)
    }

    func testRecognizesUSB4AndCIOAsUSBTransports() {
        let portTB = makePort(name: "Port-USB-C@1", bus: 0, transports: ["CIO"])
        let portUSB4 = makePort(name: "Port-USB-C@2", bus: 1, transports: ["USB4"])
        let dev1 = makeDevice(id: 1, name: "TB Device", portName: nil, bus: 0)
        let dev2 = makeDevice(id: 2, name: "USB4 Device", portName: nil, bus: 1)
        
        XCTAssertEqual(matchingDevices(for: portTB, allDevices: [dev1]).count, 1)
        XCTAssertEqual(matchingDevices(for: portUSB4, allDevices: [dev2]).count, 1)
    }
}
