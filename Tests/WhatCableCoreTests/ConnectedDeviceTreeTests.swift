import Foundation
import Testing
@testable import WhatCableCore

/// Unit tests for `ConnectedDeviceTree.rows`
/// (`Sources/WhatCableCore/USB/ConnectedDeviceTree.swift`): the shared
/// "Connected devices" row builder that roots the USB tree under the
/// downstream Thunderbolt device (with its live link speed) when one is
/// present, and renders the plain USB tree unchanged when not.
///
/// The corpus-replay sweep for the no-Thunderbolt path lives at the bottom
/// of this file; the dock-present path uses hand-built switch fixtures
/// because no test-kit probe captures `IOThunderboltSwitch` dumps.
@Suite("ConnectedDeviceTree rows")
struct ConnectedDeviceTreeTests {

    // MARK: - Fixtures

    /// Active USB-C data port at socket `@4`. Same proven-compiling
    /// `AppleHPMInterface` init shape as the DataLinkDiagnostic fixture.
    private func makePort(
        serviceName: String = "Port-USB-C@4",
        transportsSupported: [String] = ["CC", "USB2", "USB3", "CIO", "DisplayPort"]
    ) -> AppleHPMInterface {
        AppleHPMInterface(
            id: 1,
            serviceName: serviceName,
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: "USB-C",
            portNumber: 4,
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: transportsSupported,
            transportsActive: ["CC", "USB3", "CIO"],
            transportsProvisioned: [],
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
        speed: LinkGeneration?,
        widthRaw: UInt8,
        socketID: String? = nil,
        portNumber: Int = 1,
        hopTable: [HopTableEntry] = []
    ) -> IOThunderboltPort {
        let speedRaw: UInt8
        switch speed {
        case .tb3: speedRaw = 0x8
        case .usb4Tb4: speedRaw = 0x4
        case .tb5: speedRaw = 0x2
        default: speedRaw = 0x0
        }
        return IOThunderboltPort(
            portNumber: portNumber,
            socketID: socketID,
            adapterType: .lane,
            currentSpeed: LinkGeneration.from(rawSpeedCode: speedRaw),
            currentWidth: LinkWidth(rawValue: widthRaw),
            targetWidth: nil,
            rawTargetSpeed: nil,
            linkBandwidthRaw: nil,
            hopTable: hopTable
        )
    }

    /// A DisplayPort tunnel adapter (not a lane), used to build cross-cable
    /// video tunnels: pair with `lanePort`'s `hopTable` on the host root
    /// carrying the same `pathUUID`.
    private func dpPort(portNumber: Int, hopTable: [HopTableEntry]) -> IOThunderboltPort {
        IOThunderboltPort(
            portNumber: portNumber,
            socketID: nil,
            adapterType: .dpIn,
            currentSpeed: nil,
            currentWidth: nil,
            targetWidth: nil,
            rawTargetSpeed: nil,
            linkBandwidthRaw: nil,
            hopTable: hopTable
        )
    }

    private func hopEntry(pathUUID: String, counter: Int = 0) -> HopTableEntry {
        HopTableEntry(counter: counter, hopID: 8, dstHopID: 8, dstPort: 1, pathUUID: pathUUID)
    }

    /// Host root whose lane port carries `Socket ID == socketID`, matching
    /// the `@N` suffix on the port's serviceName. `laneHopTable` lets a test
    /// put a tunnel's path UUID directly on the root's own lane, the shape a
    /// real cross-cable tunnel takes (see `ActiveTunnelPresentationTests`).
    private func hostRoot(socketID: String = "4", laneHopTable: [HopTableEntry] = []) -> IOThunderboltSwitch {
        IOThunderboltSwitch(
            id: 100,
            className: "IOThunderboltSwitchType5",
            vendorID: 1452,
            vendorName: "Apple Inc.",
            modelName: "Mac",
            routerID: 0,
            depth: 0,
            routeString: 0,
            upstreamPortNumber: 0,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xC),
            ports: [lanePort(speed: .usb4Tb4, widthRaw: 0x2, socketID: socketID, hopTable: laneHopTable)],
            parentSwitchUID: nil
        )
    }

    /// Downstream device switch (a dock) whose lane carries the given link.
    private func dockSwitch(
        id: Int64 = 200,
        parent: Int64 = 100,
        vendor: String = "Ugreen Group Limited",
        model: String = "TBT5 Docking Station 10-in-1",
        speed: LinkGeneration? = .usb4Tb4,
        widthRaw: UInt8 = 0x2,
        ports: [IOThunderboltPort]? = nil
    ) -> IOThunderboltSwitch {
        IOThunderboltSwitch(
            id: id,
            className: "IOThunderboltSwitchType7",
            vendorID: 0x2B89,
            vendorName: vendor,
            modelName: model,
            routerID: 1,
            depth: 1,
            routeString: 1,
            upstreamPortNumber: 1,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE),
            ports: ports ?? [lanePort(speed: speed, widthRaw: widthRaw)],
            parentSwitchUID: parent
        )
    }

    private func device(
        id: UInt64,
        locationID: UInt32,
        name: String?,
        speedRaw: UInt8
    ) -> USBDevice {
        USBDevice(
            id: id,
            locationID: locationID,
            vendorID: 0x1234,
            productID: 0x5678,
            vendorName: nil,
            productName: name,
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: speedRaw,
            busPowerMA: nil,
            currentMA: nil,
            rawProperties: [:]
        )
    }

    /// A hub at the bus root plus one child behind it: depths 0 and 1.
    private var hubAndChild: [USBDevice] {
        [
            device(id: 1, locationID: 0x0110_0000, name: "USB3 HUB", speedRaw: 4),
            device(id: 2, locationID: 0x0111_0000, name: "USB 10_100_1000 LAN", speedRaw: 3),
        ]
    }

    private func displayPort(productName: String?) -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: true, laneCount: 2, maxLaneCount: 4,
                linkRate: 0, tunneled: true, hpdState: 1
            ),
            monitor: MonitorInfo(
                manufacturerName: nil,
                productName: productName,
                productId: nil,
                yearOfManufacture: nil,
                edid: nil
            )
        )
    }

    // MARK: - No Thunderbolt device: plain tree, unchanged

    @Test("No TB switches: rows are the plain USB tree with original depths")
    func noThunderboltPlainTree() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: hubAndChild,
            port: makePort(),
            thunderboltSwitches: [],
            displayPorts: []
        )
        try #require(rows.count == 2)
        #expect(rows[0] == ConnectedDeviceTree.Row(label: "USB3 HUB - Super Speed+ (10 Gbps)", depth: 0))
        #expect(rows[1] == ConnectedDeviceTree.Row(label: "USB 10_100_1000 LAN - Super Speed (5 Gbps)", depth: 1))
    }

    @Test("No TB switches and a monitor: no display row (the banner covers it)")
    func noThunderboltNoDisplayRow() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: hubAndChild,
            port: makePort(),
            thunderboltSwitches: [],
            displayPorts: [displayPort(productName: "LEN G34w-10")]
        )
        try #require(rows.count == 2, "A monitor without a TB root must not add a row")
        #expect(!rows.contains { $0.label.contains("G34w") })
    }

    @Test("Nothing connected: empty rows")
    func emptyInputEmptyRows() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [],
            displayPorts: []
        )
        #expect(rows.isEmpty)
    }

    // MARK: - Thunderbolt device downstream: rooted tree

    @Test("Dock present: root row names the dock with the 40 Gbps link, USB depths shift by one")
    func dockRootRow() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: hubAndChild,
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch()],
            displayPorts: []
        )
        try #require(rows.count == 3)
        #expect(rows[0] == ConnectedDeviceTree.Row(
            label: "Ugreen Group Limited TBT5 Docking Station 10-in-1 - Thunderbolt link active at 40 Gbps",
            depth: 0
        ))
        #expect(rows[1].depth == 1 && rows[1].label.hasPrefix("USB3 HUB"))
        #expect(rows[2].depth == 2 && rows[2].label.hasPrefix("USB 10_100_1000 LAN"))
    }

    @Test("TB5 dual-lane link labels 80 Gbps")
    func tb5LinkLabels80() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch(speed: .tb5, widthRaw: 0x2)],
            displayPorts: []
        )
        try #require(rows.count == 1)
        #expect(rows[0].label.hasSuffix("Thunderbolt link active at 80 Gbps"))
    }

    @Test("Asymmetric TB5 link falls back to the per-lane label, never a false total")
    func asymmetricFallsBack() throws {
        // 3 TX / 1 RX (raw 0x4): no single honest total exists.
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch(speed: .tb5, widthRaw: 0x4)],
            displayPorts: []
        )
        try #require(rows.count == 1)
        #expect(rows[0].label.contains("TX"), "Asymmetric link must show the per-lane form: \(rows[0].label)")
        #expect(!rows[0].label.contains("Thunderbolt link active at"))
    }

    @Test("Idle lane: root row is the bare device name, no link suffix")
    func idleLaneNameOnly() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch(speed: nil, widthRaw: 0x0)],
            displayPorts: []
        )
        try #require(rows.count == 1)
        #expect(rows[0] == ConnectedDeviceTree.Row(label: "Ugreen Group Limited TBT5 Docking Station 10-in-1", depth: 0))
    }

    @Test("Dock with no USB devices: root row alone")
    func dockAloneStillRoots() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch()],
            displayPorts: []
        )
        try #require(rows.count == 1)
        #expect(rows[0].depth == 0)
    }

    @Test("Daisy chain: the root row is the first hop, not the deeper device")
    func daisyChainFirstHop() throws {
        let deeper = dockSwitch(id: 300, parent: 200, vendor: "Samsung", model: "X5")
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch(), deeper],
            displayPorts: []
        )
        try #require(rows.count == 1)
        #expect(rows[0].label.contains("TBT5 Docking Station"))
        #expect(!rows.contains { $0.label.contains("X5") })
    }

    @Test("Daisy-chained dock with a slower downstream lane: the root row shows the upstream (Mac-facing) leg")
    func upstreamLaneWinsOverDownstream() throws {
        // Downstream lane listed FIRST (port 3, TB3 dual = 20 Gbps) so a
        // naive first-active-lane pick would label 20; the upstream lane
        // (port 1 == upstreamPortNumber, TB4 dual = 40 Gbps) must win.
        let mixedDock = dockSwitch(ports: [
            lanePort(speed: .tb3, widthRaw: 0x2, portNumber: 3),
            lanePort(speed: .usb4Tb4, widthRaw: 0x2, portNumber: 1),
        ])
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [hostRoot(), mixedDock],
            displayPorts: []
        )
        try #require(rows.count == 1)
        #expect(rows[0].label.hasSuffix("Thunderbolt link active at 40 Gbps"),
            "Root row must describe the Mac-facing leg, got: \(rows[0].label)")
    }

    @Test("Different socket: another port's dock never roots this port's tree")
    func otherSocketNoRoot() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: hubAndChild,
            port: makePort(serviceName: "Port-USB-C@1"),
            thunderboltSwitches: [hostRoot(socketID: "4"), dockSwitch()],
            displayPorts: []
        )
        try #require(rows.count == 2)
        #expect(rows[0].depth == 0 && rows[0].label.hasPrefix("USB3 HUB"))
    }

    @Test("Power-only port (MagSafe shape): no root row even with a fabric present")
    func magSafeNoRoot() throws {
        // transportsSupported without data transports fails the carriesData
        // gate inside ThunderboltTopology.socketID(for:), issue #195.
        let rows = ConnectedDeviceTree.rows(
            devices: hubAndChild,
            port: makePort(serviceName: "Port-USB-C@4", transportsSupported: ["CC"]),
            thunderboltSwitches: [hostRoot(), dockSwitch()],
            displayPorts: []
        )
        try #require(rows.count == 2)
        #expect(rows[0].depth == 0 && rows[0].label.hasPrefix("USB3 HUB"))
    }

    // MARK: - Display rows

    @Test("Monitor under the dock: display row at depth 1, before the USB branch")
    func displayRowUnderRoot() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: hubAndChild,
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch()],
            displayPorts: [displayPort(productName: "LEN G34w-10")]
        )
        try #require(rows.count == 4)
        #expect(rows[1] == ConnectedDeviceTree.Row(label: "Display: LEN G34w-10", depth: 1))
        #expect(rows[2].label.hasPrefix("USB3 HUB"), "USB branch must follow the display row")
    }

    @Test("Two monitors: one row each")
    func twoMonitorsTwoRows() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch()],
            displayPorts: [displayPort(productName: "LEN G34w-10"), displayPort(productName: "DELL U2723QE")]
        )
        try #require(rows.count == 3)
        #expect(rows[1].label == "Display: LEN G34w-10")
        #expect(rows[2].label == "Display: DELL U2723QE")
    }

    @Test("Monitor with no readable name: bare Display label")
    func namelessDisplayRow() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch()],
            displayPorts: [displayPort(productName: nil)]
        )
        try #require(rows.count == 2)
        #expect(rows[1] == ConnectedDeviceTree.Row(label: "Display", depth: 1))
    }

    // MARK: - "video output N" display suffix (TB link tree root, Phase B)

    private static let videoUUID = "AAAAAAAA-0000-0000-0000-000000000001"
    private static let videoUUID2 = "BBBBBBBB-0000-0000-0000-000000000002"

    @Test("Single display + single cross-cable video tunnel: display row gets the 'video output N' suffix")
    func singleDisplaySingleVideoTunnelSuffix() throws {
        let root = hostRoot(laneHopTable: [hopEntry(pathUUID: Self.videoUUID)])
        let dock = dockSwitch(ports: [
            lanePort(speed: .usb4Tb4, widthRaw: 0x2),
            dpPort(portNumber: 5, hopTable: [hopEntry(pathUUID: Self.videoUUID)]),
        ])
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [root, dock],
            displayPorts: [displayPort(productName: "LEN G34w-10")]
        )
        try #require(rows.count == 2)
        #expect(rows[1] == ConnectedDeviceTree.Row(
            label: "Display: LEN G34w-10 \u{00B7} video output 5",
            depth: 1
        ))
    }

    @Test("Two displays: no suffix, even with exactly one cross-cable video tunnel")
    func twoDisplaysNoSuffix() throws {
        let root = hostRoot(laneHopTable: [hopEntry(pathUUID: Self.videoUUID)])
        let dock = dockSwitch(ports: [
            lanePort(speed: .usb4Tb4, widthRaw: 0x2),
            dpPort(portNumber: 5, hopTable: [hopEntry(pathUUID: Self.videoUUID)]),
        ])
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [root, dock],
            displayPorts: [displayPort(productName: "LEN G34w-10"), displayPort(productName: "DELL U2723QE")]
        )
        try #require(rows.count == 3)
        #expect(rows[1].label == "Display: LEN G34w-10", "No suffix: which tunnel feeds which monitor is ambiguous")
        #expect(rows[2].label == "Display: DELL U2723QE")
    }

    @Test("Two cross-cable video tunnels: no suffix, even with exactly one display")
    func twoVideoTunnelsNoSuffix() throws {
        let root = hostRoot(laneHopTable: [
            hopEntry(pathUUID: Self.videoUUID),
            hopEntry(pathUUID: Self.videoUUID2),
        ])
        let dock = dockSwitch(ports: [
            lanePort(speed: .usb4Tb4, widthRaw: 0x2),
            dpPort(portNumber: 5, hopTable: [hopEntry(pathUUID: Self.videoUUID)]),
            dpPort(portNumber: 6, hopTable: [hopEntry(pathUUID: Self.videoUUID2)]),
        ])
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [root, dock],
            displayPorts: [displayPort(productName: "LEN G34w-10")]
        )
        try #require(rows.count == 2)
        #expect(rows[1].label == "Display: LEN G34w-10", "Ambiguous: two candidate tunnels for one display")
    }

    @Test("Tunnel terminating at the host root itself (depth 0): not cross-cable, no suffix")
    func hostInternalTunnelNoSuffix() throws {
        // The video UUID is carried only by a protocol adapter ON the host
        // root: segmentCount 1, terminal = the root itself (depth 0). Not
        // cross-cable per the locked design rule, so ActiveTunnelPresentation's
        // crossCableTunnels filter (shared with this suffix) drops it. A
        // separate, unrelated dock is present purely so a root row exists to
        // hang the display row under.
        let root = IOThunderboltSwitch(
            id: 100,
            className: "IOThunderboltSwitchType5",
            vendorID: 1452,
            vendorName: "Apple Inc.",
            modelName: "Mac",
            routerID: 0,
            depth: 0,
            routeString: 0,
            upstreamPortNumber: 0,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xC),
            ports: [
                lanePort(speed: .usb4Tb4, widthRaw: 0x2, socketID: "4"),
                dpPort(portNumber: 9, hopTable: [hopEntry(pathUUID: Self.videoUUID)]),
            ],
            parentSwitchUID: nil
        )
        let dock = dockSwitch()
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [root, dock],
            displayPorts: [displayPort(productName: "LEN G34w-10")]
        )
        try #require(rows.count == 2)
        #expect(rows[1].label == "Display: LEN G34w-10", "Host-internal tunnel must not produce a suffix")
    }

    @Test("Dock-internal-only video-kind UUID (distinctSwitchCount 1): no 'video output N' suffix, even with one display and one candidate tunnel")
    func dockInternalOnlyVideoTunnelNoSuffix() throws {
        // Only the dock's own DP adapter carries this UUID; the host
        // root's lane never sees it (`hostRoot()` defaults to an empty
        // `laneHopTable`). Mirrors the real ASUS-internal PCIe UUID
        // 93B7660C in research/dumps/tb-fabric/052-joeshaw-..., with a DP
        // adapter instead of PCIe so it exercises the video-suffix path
        // this suite covers.
        let root = hostRoot()
        let dock = dockSwitch(ports: [
            lanePort(speed: .usb4Tb4, widthRaw: 0x2),
            dpPort(portNumber: 5, hopTable: [hopEntry(pathUUID: Self.videoUUID)]),
        ])
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [root, dock],
            displayPorts: [displayPort(productName: "LEN G34w-10")]
        )
        try #require(rows.count == 2)
        #expect(rows[1].label == "Display: LEN G34w-10", "Dock-internal-only tunnel must not produce a suffix")
    }

    @Test("No displays: a cross-cable video tunnel present doesn't change the no-display case")
    func noDisplayCaseUnchangedWithVideoTunnel() throws {
        let root = hostRoot(laneHopTable: [hopEntry(pathUUID: Self.videoUUID)])
        let dock = dockSwitch(ports: [
            lanePort(speed: .usb4Tb4, widthRaw: 0x2),
            dpPort(portNumber: 5, hopTable: [hopEntry(pathUUID: Self.videoUUID)]),
        ])
        let rows = ConnectedDeviceTree.rows(
            devices: [],
            port: makePort(),
            thunderboltSwitches: [root, dock],
            displayPorts: []
        )
        try #require(rows.count == 1, "Root row alone: no display rows to suffix")
        #expect(rows[0].depth == 0)
    }

    // MARK: - Grouping by USB controller

    /// Same shape as `device`, plus the controller bus the device enumerates
    /// on. A dock exposes several controllers, and that is what the grouping
    /// keys off.
    private func busDevice(
        id: UInt64,
        locationID: UInt32,
        name: String?,
        speedRaw: UInt8,
        busIndex: Int
    ) -> USBDevice {
        USBDevice(
            id: id,
            locationID: locationID,
            vendorID: 0x1234,
            productID: 0x5678,
            vendorName: nil,
            productName: name,
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: speedRaw,
            busPowerMA: nil,
            currentMA: nil,
            busIndex: busIndex,
            rawProperties: [:]
        )
    }

    @Test("Two USB controllers: devices group under a bus header each")
    func twoBusesGroup() throws {
        let devices = [
            busDevice(id: 1, locationID: 0x2020_0000, name: "Audio", speedRaw: 1, busIndex: 0x20),
            busDevice(id: 2, locationID: 0x2070_0000, name: "Extreme Pro", speedRaw: 4, busIndex: 0x20),
            busDevice(id: 3, locationID: 0x2120_0000, name: "Shure MV7", speedRaw: 1, busIndex: 0x21),
        ]
        let rows = ConnectedDeviceTree.rows(
            devices: devices, port: makePort(),
            thunderboltSwitches: [], displayPorts: []
        )
        let labels = rows.map { $0.label }
        #expect(labels.contains("USB bus 0x20"))
        #expect(labels.contains("USB bus 0x21"))

        // Headers sit at depth 0 with their devices indented one level under.
        let header20 = try #require(rows.firstIndex { $0.label == "USB bus 0x20" })
        #expect(rows[header20].depth == 0)
        #expect(rows[header20 + 1].depth == 1)
        #expect(rows[header20 + 1].label.hasPrefix("Audio"))

        // Every device still appears exactly once.
        #expect(labels.filter { $0.hasPrefix("Shure MV7") }.count == 1)
        #expect(rows.count == 5)
    }

    @Test("A device with no readable bus suppresses grouping entirely")
    func unknownBusSuppressesGrouping() {
        // Partial grouping would imply the ungrouped device sits on a bus we
        // could not read, so the whole set falls back to the plain tree.
        let devices = [
            busDevice(id: 1, locationID: 0x2020_0000, name: "Audio", speedRaw: 1, busIndex: 0x20),
            device(id: 2, locationID: 0x2120_0000, name: "Shure MV7", speedRaw: 1),
        ]
        let rows = ConnectedDeviceTree.rows(
            devices: devices, port: makePort(),
            thunderboltSwitches: [], displayPorts: []
        )
        #expect(!rows.contains { $0.label.hasPrefix("USB bus") })
        #expect(rows.count == 2)
    }

    @Test("A hub child with no readable bus suppresses grouping")
    func unknownBusOnHubChildSuppressesGrouping() {
        // The child hangs off the hub by locationID, so it is a descendant
        // rather than a root. Checking roots alone would let it render under
        // its parent's header, claiming a controller nothing established.
        let devices = [
            busDevice(id: 1, locationID: 0x2010_0000, name: "USB3 HUB", speedRaw: 4, busIndex: 0x20),
            device(id: 2, locationID: 0x2011_0000, name: "LAN", speedRaw: 3),
            busDevice(id: 3, locationID: 0x2120_0000, name: "Shure MV7", speedRaw: 1, busIndex: 0x21),
        ]
        let rows = ConnectedDeviceTree.rows(
            devices: devices, port: makePort(),
            thunderboltSwitches: [], displayPorts: []
        )
        #expect(!rows.contains { $0.label.hasPrefix("USB bus") })
        #expect(rows.count == 3)
    }

    @Test("Device rows carry their node so the app can expand them")
    func deviceRowsCarryTheirNode() throws {
        let rows = ConnectedDeviceTree.rows(
            devices: hubAndChild, port: makePort(),
            thunderboltSwitches: [], displayPorts: []
        )
        try #require(rows.count == 2)
        #expect(rows.allSatisfy { $0.device != nil })
        #expect(rows[0].device?.device.productName == "USB3 HUB")
    }

    @Test("Devices under a Thunderbolt root keep their node")
    func devicesUnderDockKeepTheirNode() throws {
        // The dock path re-maps rows to shift depth. Dropping the node there
        // would leave the expander working everywhere except behind a dock.
        let rows = ConnectedDeviceTree.rows(
            devices: hubAndChild, port: makePort(),
            thunderboltSwitches: [hostRoot(), dockSwitch()], displayPorts: []
        )
        let root = try #require(rows.first)
        #expect(root.device == nil, "the Thunderbolt root row is not a USB device")

        let deviceRows = rows.dropFirst()
        try #require(deviceRows.count == 2)
        #expect(deviceRows.allSatisfy { $0.device != nil })
        #expect(deviceRows.allSatisfy { $0.depth >= 1 }, "shifted under the root")
    }

    @Test("Bus header rows carry no node")
    func busHeaderRowsCarryNoNode() throws {
        let devices = [
            busDevice(id: 1, locationID: 0x2020_0000, name: "Audio", speedRaw: 1, busIndex: 0x20),
            busDevice(id: 2, locationID: 0x2120_0000, name: "Shure MV7", speedRaw: 1, busIndex: 0x21),
        ]
        let rows = ConnectedDeviceTree.rows(
            devices: devices, port: makePort(),
            thunderboltSwitches: [], displayPorts: []
        )
        let header = try #require(rows.first { $0.label.hasPrefix("USB bus") })
        #expect(header.device == nil)
    }

    @Test("One USB controller: no bus header, rows unchanged")
    func oneBusIsNotGrouped() {
        let devices = [
            busDevice(id: 1, locationID: 0x2020_0000, name: "Audio", speedRaw: 1, busIndex: 0x20),
            busDevice(id: 2, locationID: 0x2070_0000, name: "Extreme Pro", speedRaw: 4, busIndex: 0x20),
        ]
        let rows = ConnectedDeviceTree.rows(
            devices: devices, port: makePort(),
            thunderboltSwitches: [], displayPorts: []
        )
        // A lone header would add indentation and no information.
        #expect(!rows.contains { $0.label.hasPrefix("USB bus") })
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.depth == 0 })
    }
}

/// Corpus-replay sweep: with no Thunderbolt switches, `ConnectedDeviceTree`
/// must reproduce the USB tree exactly as `USBDeviceNode` builds it, for
/// every real device topology in the corpus. This pins the "plain tree,
/// unchanged" contract against real machines, not just the two-device
/// fixture above. The dock-present path can't be corpus-replayed (no
/// test-kit probe captures IOThunderboltSwitch dumps); it is covered by the
/// fixture tests.
@Suite("ConnectedDeviceTree: corpus sweep")
struct ConnectedDeviceTreeCorpusTests {

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // Probe-38 parsing: deliberate duplicate of the parser in
    // TunnelledDeviceGroupingCorpusTests (same target; Swift `private` is
    // file-scoped, and these sweeps are kept self-contained on purpose).
    private static func parseProbe38(_ text: String) -> [USBDevice] {
        text.components(separatedBy: "--- Device[").dropFirst().compactMap { block in
            func value(_ key: String) -> String? {
                for line in block.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix(key),
                          trimmed.dropFirst(key.count).first == " " || trimmed.dropFirst(key.count).first == "=",
                          let eq = trimmed.firstIndex(of: "=")
                    else { continue }
                    return trimmed[trimmed.index(after: eq)...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                return nil
            }
            func hex(_ key: String) -> UInt64? {
                guard var raw = value(key) else { return nil }
                if raw.hasPrefix("0x") || raw.hasPrefix("0X") { raw = String(raw.dropFirst(2)) }
                return UInt64(raw, radix: 16)
            }
            guard let loc = hex("locationID").map({ UInt32(truncatingIfNeeded: $0) }) else { return nil }
            return USBDevice(
                id: UInt64(loc),
                locationID: loc,
                vendorID: hex("idVendor").map { UInt16(truncatingIfNeeded: $0) } ?? 0,
                productID: hex("idProduct").map { UInt16(truncatingIfNeeded: $0) } ?? 0,
                vendorName: value("USB Vendor Name"),
                productName: value("USB Product Name"),
                serialNumber: nil,
                usbVersion: nil,
                speedRaw: value("Device Speed").flatMap { UInt8($0) },
                busPowerMA: nil,
                currentMA: nil,
                // Upper byte of the locationID is the USB controller index,
                // exactly how USBWatcher derives it live. Without this every
                // corpus device would have a nil busIndex, grouping would be
                // suppressed on every folder, and the sweep would silently
                // stop covering the grouping path.
                busIndex: Int(loc >> 24),
                deviceClass: value("bDeviceClass").flatMap { UInt8($0) },
                rawProperties: [:]
            )
        }
    }

    private static func port() -> AppleHPMInterface {
        AppleHPMInterface(
            id: 1, serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: nil, portTypeDescription: "USB-C", portNumber: 1,
            connectionActive: true, activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            transportsActive: ["CC", "USB3"], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
    }

    @Test("No-TB path reproduces USBDeviceNode's tree on every corpus topology")
    func plainTreeMatchesCorpusTopologies() throws {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: Self.probeRoot.path))?.sorted() ?? []
        var swept = 0
        var devicesSeen = 0
        var withBusIndex = 0
        var grouped = 0
        for folder in folders {
            let url = Self.probeRoot.appendingPathComponent(folder).appendingPathComponent("38_usb_device_tree.json")
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = root["output"] as? String
            else { continue }
            let devices = Self.parseProbe38(text)
            guard !devices.isEmpty else { continue }
            swept += 1
            devicesSeen += devices.count

            let rows = ConnectedDeviceTree.rows(
                devices: devices, port: Self.port(),
                thunderboltSwitches: [], displayPorts: []
            )
            if devices.contains(where: { $0.busIndex != nil }) { withBusIndex += 1 }
            let expected = Self.expectedRows(devices)
            if expected.contains(where: { $0.depth == 0 && $0.label.hasPrefix("USB bus") }) { grouped += 1 }

            // Validates that ConnectedDeviceTree reproduces the expected tree on
            // every real topology (same devices, order, depth, routing, and bus
            // grouping) against an INDEPENDENT reimplementation of both rules
            // (`expectedRows` / `referenceName` below), never against the
            // production properties themselves. Building the expectation from
            // `displayName` or `groupedByBus` would be circular: a regression
            // would change both sides and the sweep would still pass. Per the
            // project's "a check that reads the same source as the thing it
            // checks is not a check" rule.
            try #require(rows.count == expected.count, "\(folder): row count diverged from the expected tree")
            for (row, want) in zip(rows, expected) {
                #expect(row == ConnectedDeviceTree.Row(label: want.label, depth: want.depth),
                    "\(folder): row diverged from the canonical rendering: \(row.label)")
            }
        }
        // Fixture floor: at least the tracked probe-38 replay fixture must be
        // present even on a fresh clone; a full on-disk corpus sweeps far more.
        // If this fires at 0, the sweep is vacuous, not passing.
        #expect(swept >= 1, "Sweep ran on zero folders; corpus probes missing")
        #expect(devicesSeen > 0)
        // Non-vacuity floors for the bus grouping specifically. The parser
        // derives busIndex from the locationID, so every corpus device has one;
        // without these, a parser that silently stopped setting busIndex would
        // send every folder down the ungrouped path and the sweep would still
        // pass while testing nothing about grouping. Real multi-controller
        // machines exist in the corpus, so `grouped` must not be zero either.
        if swept > 1 {
            #expect(withBusIndex == swept, "every corpus folder should carry a bus index")
            #expect(grouped > 0, "no corpus machine exercised the bus grouping path")
        }
    }

    /// Independent reimplementation of the rows `ConnectedDeviceTree.rows`
    /// should produce for the no-Thunderbolt path, covering both the bus
    /// grouping rule and the naming rule. Deliberately does not call
    /// `USBDeviceNode.groupedByBus` or `USBDevice.displayName`; it re-derives
    /// both so a regression in either diverges here on real corpus data.
    ///
    /// The grouping rule restated: group the top-level devices under one header
    /// per USB controller, but only when every device in the tree has a readable
    /// bus index and the top-level devices span more than one controller. A lone
    /// header adds indentation and no information; a partial grouping would
    /// imply a device sits on a controller nothing established.
    private static func expectedRows(_ devices: [USBDevice]) -> [(label: String, depth: Int)] {
        let tree = USBDeviceNode.buildTree(from: devices)
        func label(_ node: USBDeviceNode) -> String {
            let name = referenceName(product: node.device.productName, vendor: node.device.vendorName)
            return "\(name) - \(node.device.speedLabel)"
        }

        var busOrder: [Int] = []
        for root in tree {
            guard let bus = root.device.busIndex else { continue }
            if !busOrder.contains(bus) { busOrder.append(bus) }
        }
        let everyDeviceHasABus = USBDeviceNode.flatten(tree).allSatisfy { $0.device.busIndex != nil }

        guard everyDeviceHasABus, busOrder.count > 1 else {
            return USBDeviceNode.flatten(tree).map { (label: label($0), depth: $0.depth) }
        }

        var out: [(label: String, depth: Int)] = []
        for bus in busOrder {
            let word = String(localized: "USB bus", bundle: _coreLocalizedBundle)
            out.append((label: "\(word) \(String(format: "0x%02X", bus))", depth: 0))
            for root in tree where root.device.busIndex == bus {
                for node in USBDeviceNode.flatten([root]) {
                    out.append((label: label(node), depth: node.depth + 1))
                }
            }
        }
        return out
    }

    /// Independent reimplementation of `USBDevice.displayName`'s naming rule,
    /// kept deliberately separate from production so the corpus sweep above is a
    /// real cross-check, not a tautology. Same rule (append the maker unless the
    /// product already names its brand as a whole word), written as different
    /// code. If you change the naming rule, change it in both places on purpose.
    ///
    /// "Independent" means re-derived here rather than calling the property
    /// under test. It deliberately does NOT extend to the case-folding
    /// primitive. An earlier version of this oracle used `lowercased()` while
    /// production uses `compare(options: .caseInsensitive)`, and those are two
    /// different rules rather than one rule written twice: they agree on ASCII
    /// and diverge on real Unicode (ICU folds German "STRASSE" to match
    /// "Straße", the "ﬁ" ligature to "fi", and the micro sign to Greek mu;
    /// Swift's `lowercased()` does none of those). A device reporting any of
    /// those would have failed the sweep against a naming rule that was working
    /// correctly. Same fold, different code.
    private static func referenceName(product rawProduct: String?, vendor rawVendor: String?) -> String {
        let product = (rawProduct ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !product.isEmpty else {
            return String(localized: "Unknown", bundle: _coreLocalizedBundle)
        }
        let vendor = (rawVendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vendor.isEmpty else { return product }
        let boundary: (Character) -> Bool = { !$0.isLetter && !$0.isNumber }
        guard let brand = vendor.split(whereSeparator: boundary).first, brand.count >= 2 else {
            return "\(product) (\(vendor))"
        }
        let namesBrand = product
            .split(whereSeparator: boundary)
            .first { $0.compare(brand, options: .caseInsensitive) == .orderedSame } != nil
        return namesBrand ? product : "\(product) (\(vendor))"
    }
}
