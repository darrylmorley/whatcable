import Foundation
import Testing
@testable import WhatCableCore

/// Tests for WidgetSnapshot.init(from: CableSnapshot).
///
/// All tests run against pure model objects with no IOKit dependency.
/// The Darwin backend is not imported here; only WhatCableCore types are used.
@Suite("WidgetSnapshot from CableSnapshot")
struct WidgetSnapshotFromCableSnapshotTests {

    // MARK: - Fixtures

    /// Minimal HPM port fixture. Mirrors the pattern in PortSummaryTests.
    private func makePort(
        id: UInt64 = 1,
        connected: Bool = true,
        active: [String] = [],
        supported: [String] = [],
        portNumber: Int = 1,
        portTypeDescription: String = "USB-C",
        portDescription: String? = "Port-USB-C@1",
        rawProperties: [String: String] = ["PortType": "2"]
    ) -> AppleHPMInterface {
        AppleHPMInterface(
            id: id,
            serviceName: "Port-USB-C@\(portNumber)",
            className: "AppleHPMInterfaceType10",
            portDescription: portDescription,
            portTypeDescription: portTypeDescription,
            portNumber: portNumber,
            connectionActive: connected,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: supported,
            transportsActive: active,
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: rawProperties
        )
    }

    private func makeUSBPDSource(portNumber: Int = 1, maxW: Int = 96) -> PowerSource {
        let winning = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: maxW * 50,
            maxPowerMW: maxW * 1000
        )
        return PowerSource(
            id: 1,
            name: "USB-PD",
            parentPortType: 2,
            parentPortNumber: portNumber,
            options: [winning],
            winning: winning
        )
    }

    private func emptyCableSnapshot(ports: [AppleHPMInterface]) -> CableSnapshot {
        CableSnapshot(
            ports: ports,
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil
        )
    }

    // MARK: - Port count and basic structure

    @Test("Port count matches input")
    func portCountMatches() {
        let ports = [makePort(id: 1), makePort(id: 2, portNumber: 2)]
        let cable = emptyCableSnapshot(ports: ports)
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports.count == 2)
    }

    @Test("Empty port list produces empty widget")
    func emptyPortList() {
        let cable = emptyCableSnapshot(ports: [])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports.isEmpty)
    }

    @Test("timestamp is recent (within 5s of now)")
    func timestampIsRecent() {
        let cable = emptyCableSnapshot(ports: [makePort()])
        let before = Date()
        let widget = WidgetSnapshot(from: cable)
        let after = Date()
        #expect(widget.timestamp >= before)
        #expect(widget.timestamp <= after)
    }

    // MARK: - Port identity fields

    @Test("Port id is preserved from HPM interface")
    func portIdPreserved() {
        let port = makePort(id: 42)
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].id == 42)
    }

    @Test("portName uses portDescription when present")
    func portNameFromDescription() {
        let port = makePort(portDescription: "Left USB-C")
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].portName == "Left USB-C")
    }

    @Test("portName falls back to serviceName when portDescription is nil")
    func portNameFallsBackToServiceName() {
        let port = makePort(portDescription: nil)
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].portName == "Port-USB-C@1")
    }

    // MARK: - Status mapping

    @Test("Disconnected port maps to .empty status")
    func disconnectedPortIsEmpty() {
        let port = makePort(connected: false)
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].status == .empty)
    }

    @Test("Port with USB-PD charging source maps to .charging status")
    func chargingPortStatus() {
        let port = makePort(connected: true)
        let source = makeUSBPDSource(portNumber: 1, maxW: 96)
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [source],
            identities: [],
            usbDevices: [],
            adapter: nil
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].status == .charging)
    }

    // MARK: - Derived fields

    @Test("recentPower is always empty (no Pro contributor in CableSnapshot)")
    func recentPowerAlwaysEmpty() {
        let port = makePort(connected: true)
        let source = makeUSBPDSource()
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [source],
            identities: [],
            usbDevices: [],
            adapter: nil
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].recentPower.isEmpty)
    }

    @Test("portKey matches PowerSource portKey string for USB-C port")
    func portKeyMatchesExpected() {
        let port = makePort(portNumber: 1, rawProperties: ["PortType": "2"])
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        // portKey = "<PortType>/<portNumber>" = "2/1"
        #expect(widget.ports[0].portKey == "2/1")
    }

    @Test("chargerWatts resolved from USB-PD source")
    func chargerWattsFromPDSource() {
        let port = makePort(portNumber: 1, rawProperties: ["PortType": "2"])
        let source = makeUSBPDSource(portNumber: 1, maxW: 67)
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [source],
            identities: [],
            usbDevices: [],
            adapter: nil
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].chargerWatts == 67)
    }

    @Test("chargerWatts is nil when no charging source")
    func chargerWattsNilWhenNoSource() {
        let port = makePort(connected: false)
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].chargerWatts == nil)
    }

    @Test("deviceCount is zero when no USB devices present")
    func deviceCountZeroWhenNoDevices() {
        let port = makePort()
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].deviceCount == 0)
    }

    // MARK: - Display fields (nil when no displayPorts in snapshot)

    @Test("displayMode is nil when no display ports in snapshot")
    func displayModeNilWithoutDisplay() {
        let port = makePort()
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].displayMode == nil)
    }

    @Test("monitorName is nil when no display ports in snapshot")
    func monitorNameNilWithoutDisplay() {
        let port = makePort()
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].monitorName == nil)
    }

    @Test("displayCount is 0 when no display ports in snapshot")
    func displayCountZeroWithoutDisplay() {
        let port = makePort()
        let cable = emptyCableSnapshot(ports: [port])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports[0].displayCount == 0)
    }

    // MARK: - PowerState

    @Test("powerState is nil when no battery info in snapshot")
    func powerStateNilWhenNoBattery() {
        let port = makePort()
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil,
            batteryFullyCharged: nil,
            batteryIsCharging: nil
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.powerState == nil)
    }

    @Test("powerState.isDesktopMac reflects snapshot flag")
    func powerStateDesktopFlag() {
        let port = makePort()
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil,
            isDesktopMac: true,
            batteryFullyCharged: false,
            batteryIsCharging: false
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.powerState?.isDesktopMac == true)
    }

    @Test("powerState.isCharging reflects batteryIsCharging")
    func powerStateIsCharging() {
        let port = makePort()
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil,
            batteryFullyCharged: false,
            batteryIsCharging: true
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.powerState?.isCharging == true)
    }

    @Test("powerState.adapterWatts comes from adapter field")
    func powerStateAdapterWatts() {
        let port = makePort()
        let adapter = AdapterInfo(watts: 140, isCharging: true, source: "AC")
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: adapter,
            batteryFullyCharged: false,
            batteryIsCharging: true
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.powerState?.adapterWatts == 140)
    }

    @Test("powerState.systemPowerInWatts is always nil (Pro plugin only)")
    func powerStateSystemPowerNil() {
        let port = makePort()
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil,
            batteryFullyCharged: false,
            batteryIsCharging: false
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.powerState?.systemPowerInWatts == nil)
    }

    @Test("powerState.perPortWatts is always nil (Pro plugin only)")
    func powerStatePerPortWattsNil() {
        let port = makePort()
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil,
            batteryFullyCharged: false,
            batteryIsCharging: false
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.powerState?.perPortWatts == nil)
    }

    // MARK: - Multiple ports

    @Test("Two ports produce two entries with distinct ids")
    func twoPortsDistinctIds() {
        let p1 = makePort(id: 10, portNumber: 1)
        let p2 = makePort(id: 20, portNumber: 2)
        let cable = emptyCableSnapshot(ports: [p1, p2])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports.count == 2)
        let ids = Set(widget.ports.map(\.id))
        #expect(ids == Set([10, 20]))
    }

    @Test("Charging source on port 1 does not affect port 2 chargerWatts")
    func chargerWattsIsolatedByPort() {
        let p1 = makePort(id: 1, portNumber: 1, rawProperties: ["PortType": "2"])
        let p2 = makePort(id: 2, portNumber: 2, rawProperties: ["PortType": "2"])
        // Source attached to port 1 only (parentPortType=2, parentPortNumber=1)
        let source = makeUSBPDSource(portNumber: 1, maxW: 96)
        let cable = CableSnapshot(
            ports: [p1, p2],
            powerSources: [source],
            identities: [],
            usbDevices: [],
            adapter: nil
        )
        let widget = WidgetSnapshot(from: cable)
        let port1 = widget.ports.first { $0.id == 1 }
        let port2 = widget.ports.first { $0.id == 2 }
        #expect(port1?.chargerWatts == 96)
        #expect(port2?.chargerWatts == nil)
    }

    @Test("Widget headline agrees with its own chargerWatts pill")
    func widgetHeadlineAgreesWithItsChargerWatts() {
        // The widget resolved its wattage AFTER building the PortSummary and
        // never passed it in, so the summary was blind to the system-adapter
        // fallback that the widget's own pill is drawn from. A dock delivering
        // power leaves no per-port PowerSource node, so this shape (sole active
        // port, CC only, no source, 96W adapter) resolved to
        // .systemAdapterFallback for the pill while the summary fell through to
        // the no-charger wording. The widget then read "96W" and "no charger
        // detected" side by side. Found by review of the e-marker branch.
        let port = makePort(active: ["CC"], supported: ["CC", "USB2", "USB3", "CIO"])
        let cable = CableSnapshot(
            ports: [port],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: AdapterInfo(watts: 96, isCharging: true, source: "AC")
        )
        let widget = WidgetSnapshot(from: cable)
        let entry = widget.ports.first
        #expect(entry?.chargerWatts == 96, "the pill's own value")
        #expect(
            entry?.status == .charging,
            "a port the widget shows 96W on must not read as a non-charging state, got: \(String(describing: entry?.status))"
        )
        #expect(
            entry?.subtitle.contains("charger detected") == false,
            "must not deny a charger the widget is simultaneously showing, got: \(String(describing: entry?.subtitle))"
        )
    }

    // MARK: - Apple accessory name

    @Test("The port's UVDM accessory name reaches the widget entry")
    func accessoryNameReachesTheEntry() {
        let port = makePort(active: ["USB2"], supported: ["CC", "USB2"])
        let identity = AppleAccessoryIdentity(
            id: 700, portKey: "2/1",
            manufacturer: "Apple Inc.", vendor: "Apple Inc.",
            product: "iPhone", userString: nil, model: nil,
            serialNumber: nil, hardwareVersion: nil,
            vendorID: 0x05AC, productID: 0x12A8
        )
        let cable = CableSnapshot(
            ports: [port], powerSources: [], identities: [], usbDevices: [],
            adapter: nil, accessoryIdentities: [identity]
        )
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports.first?.accessoryName == "iPhone")
        // The widget's row shows it instead of the link-speed line.
        #expect(widget.ports.first?.rowDetail == "iPhone")
    }

    @Test("A port with no UVDM node carries no accessory name")
    func noAccessoryNameWithoutANode() {
        let cable = emptyCableSnapshot(ports: [makePort()])
        let widget = WidgetSnapshot(from: cable)
        #expect(widget.ports.first?.accessoryName == nil)
    }
}
