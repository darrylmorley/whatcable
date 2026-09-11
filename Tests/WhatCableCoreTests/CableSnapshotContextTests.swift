import Foundation
import Testing
@testable import WhatCableCore

/// Tests for `CableSnapshotContext`, the Core-level per-port assembly builder
/// These lock the joins the formatters currently duplicate: which
/// power sources / identities / transports belong to a port, which CIO entry
/// wins, which devices are attributed, and the cross-port charging flag.
struct CableSnapshotContextTests {

    // MARK: - Test 1: every field populated, in order

    @Test("Every PortContext field is populated and ordered like snapshot.ports")
    func everyPortContextFieldIsPopulated() throws {
        let port1 = makePort(portNumber: 1, portType: "USB-C", uuid: nil, connectionActive: true)
        let port2 = makePort(portNumber: 2, portType: "USB-C", uuid: nil, connectionActive: true)

        let source1 = makeSource(portType: 2, portNumber: 1, winningMW: 100_000)
        let source2 = makeSource(portType: 2, portNumber: 2)

        let cableIdentity = makeIdentity(
            portType: 2, portNumber: 1, endpoint: .sopPrime,
            vdos: [0x1C60_05AC, 0, 0x720A_0100, 0x110A_2644])
        let deviceIdentity = makeIdentity(portType: 2, portNumber: 1, endpoint: .sop)
        let port2Identity = makeIdentity(portType: 2, portNumber: 2, endpoint: .sopPrime)

        let usb3 = makeUSB3(portKey: "2/1", signaling: 2)
        let trm = makeTRM(portKey: "2/1", transportType: "USB3")
        let cioFirst = makeCIO(id: 1, portKey: "2/1", negotiatedLinkSpeed: 3)
        let cioSecond = makeCIO(id: 2, portKey: "2/1", negotiatedLinkSpeed: 4)
        let displayPort = makeDisplayPort(parentPortType: 2, parentPortNumber: 1, uuid: nil)

        let federated = FederatedIdentity(
            portIndex: 0, vendorID: 0x05AC, productID: 0x0001, pdSpecRevision: 3,
            powerRole: 0, dualRolePower: false, externalConnected: true)

        let snapshot = CableSnapshot(
            ports: [port1, port2],
            powerSources: [source1, source2],
            identities: [cableIdentity, deviceIdentity, port2Identity],
            usbDevices: [],
            adapter: AdapterInfo(watts: 140, isCharging: true, source: "AC"),
            thunderboltSwitches: [],
            isDesktopMac: false,
            federatedIdentities: [federated],
            usb3Transports: [usb3],
            trmTransports: [trm],
            cioCapabilities: [cioFirst, cioSecond],
            displayPorts: [displayPort],
            batteryFullyCharged: false,
            batteryIsCharging: true
        )

        let context = CableSnapshotContext(snapshot: snapshot)

        // One context per port, in snapshot order.
        #expect(context.portContexts.count == 2)
        #expect(context.portContexts.map { $0.port.id } == [port1.id, port2.id])

        let first = try #require(context.portContexts.first)
        #expect(first.portSources.count == 1)
        #expect(first.portSources.first?.parentPortNumber == 1)
        #expect(first.portIdentities.count == 2)
        #expect(first.portUSB3.count == 1)
        #expect(first.portUSB3.first?.signaling == 2)
        #expect(first.portTRM.count == 1)
        #expect(first.portTRM.first?.transportType == "USB3")
        // FIRST canonical CIO match wins, mirroring the formatters.
        #expect(first.portCIO?.negotiatedLinkSpeed == 3)
        #expect(first.portDisplayPorts.count == 1)
        #expect(first.matchedDevices.isEmpty)
        #expect(first.structurallyScopedTunnelledDevices.isEmpty)
        #expect(first.attributedDevices.isEmpty)

        // Snapshot-wide passthroughs.
        #expect(context.adapter?.watts == 140)
        #expect(context.batteryIsCharging == true)
        #expect(context.batteryFullyCharged == false)
        #expect(context.federatedIdentities.count == 1)
        #expect(context.isDesktopMac == false)
        #expect(context.thunderboltSwitches.isEmpty)

        // Port 2 sees only its own entries.
        let second = context.portContexts[1]
        #expect(second.portSources.count == 1)
        #expect(second.portSources.first?.parentPortNumber == 2)
        #expect(second.portIdentities.count == 1)
        #expect(second.portUSB3.isEmpty)
        #expect(second.portTRM.isEmpty)
        #expect(second.portCIO == nil)
        #expect(second.portDisplayPorts.isEmpty)
    }

    // MARK: - Test 2: UUID join beats portKey join

    @Test("Canonical matching prefers the controller UUID over the portKey")
    func canonicalMatchingPrefersUUIDOverPortKey() {
        let portUUID = "00000000-0000-0000-0000-00000000000A"
        let otherUUID = "00000000-0000-0000-0000-00000000000B"
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: portUUID, connectionActive: true)

        // Right UUID, wrong port number: the UUID join must still claim it.
        let uuidMatch = makeSource(portType: 2, portNumber: 99, uuid: portUUID)
        // Right port number, different UUID: must be excluded.
        let uuidMismatch = makeSource(portType: 2, portNumber: 1, uuid: otherUUID)

        let snapshot = makeSnapshot(ports: [port], powerSources: [uuidMatch, uuidMismatch])
        let context = CableSnapshotContext(snapshot: snapshot)

        #expect(context.portContexts.count == 1)
        #expect(context.portContexts[0].portSources.count == 1)
        #expect(context.portContexts[0].portSources.first?.parentPortNumber == 99)
    }

    // MARK: - Test 3: first CIO match wins

    @Test("portCIO is the first canonical CIO match, not the last")
    func firstCanonicalCIOMatchWins() {
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: nil, connectionActive: true)
        let snapshot = makeSnapshot(
            ports: [port],
            cioCapabilities: [
                makeCIO(id: 1, portKey: "2/1", negotiatedLinkSpeed: 3),
                makeCIO(id: 2, portKey: "2/1", negotiatedLinkSpeed: 4)
            ])

        let context = CableSnapshotContext(snapshot: snapshot)
        #expect(context.portContexts[0].portCIO?.negotiatedLinkSpeed == 3)
    }

    // MARK: - Test: portAccessory resolves per-port, not globally

    @Test("portAccessory resolves the accessory identity that matches its own port")
    func portAccessoryJoinsPerPort() throws {
        let port1 = makePort(portNumber: 1, portType: "USB-C", uuid: nil, connectionActive: true)
        let port2 = makePort(portNumber: 2, portType: "USB-C", uuid: nil, connectionActive: true)

        let accessory1 = makeAccessory(id: 1, portKey: "2/1", product: "iPhone")
        let accessory2 = makeAccessory(id: 2, portKey: "2/2", product: "iPad")

        let snapshot = makeSnapshot(
            ports: [port1, port2],
            accessoryIdentities: [accessory1, accessory2])
        let context = CableSnapshotContext(snapshot: snapshot)

        #expect(context.portContexts.count == 2)
        let first = try #require(context.portContexts.first)
        let second = context.portContexts[1]

        #expect(first.portAccessory?.id == accessory1.id)
        #expect(second.portAccessory?.id == accessory2.id)
    }

    // MARK: - Test 4: cross-port charging flag

    @Test("anotherPortActivelyCharging points at the OTHER port holding the contract")
    func multiChargerStandby() {
        let port1 = makePort(portNumber: 1, portType: "USB-C", uuid: nil, connectionActive: true)
        let port2 = makePort(portNumber: 2, portType: "USB-C", uuid: nil, connectionActive: true)
        // Port 1 holds a live negotiated contract; port 2 has a charger
        // connected but no winning option (the standby charger, issue #264).
        let charging = makeSource(portType: 2, portNumber: 1, winningMW: 100_000)
        let standby = makeSource(portType: 2, portNumber: 2)

        let snapshot = makeSnapshot(ports: [port1, port2], powerSources: [charging, standby])
        let context = CableSnapshotContext(snapshot: snapshot)

        #expect(context.portContexts[0].anotherPortActivelyCharging == false)
        #expect(context.portContexts[1].anotherPortActivelyCharging == true)
        // The port holding the contract resolves to a wattage-bearing case.
        // Which case is ChargerWattageSource's own concern, not this one.
        #expect(context.portContexts[0].chargerWattageSource.watts != nil)
    }

    // MARK: - Test 5: device attribution

    @Test("attributedDevices is matched-first, then structurally scoped, deduplicated")
    func structuralDeviceAttribution() throws {
        // One Thunderbolt host root on socket 4 whose acio4 root name maps to
        // the apciec4 tunnel root a tunnelled device reports.
        let port = makeDataPort(serviceName: "Port-USB-C@4", portNumber: 4)
        let hostRoot = makeHostRootSwitch(id: 100, socketID: "4", acioRootName: "acio4")

        let native = makeNativeDevice(id: 1, controllerPortName: "Port-USB-C@4")
        let tunnelled = makeTunnelledDevice(id: 2, tunnelRootName: "apciec4")

        let snapshot = makeSnapshot(
            ports: [port],
            usbDevices: [native, tunnelled],
            thunderboltSwitches: [hostRoot])
        let context = CableSnapshotContext(snapshot: snapshot)
        let portContext = try #require(context.portContexts.first)

        #expect(portContext.matchedDevices.map { $0.id } == [1])
        #expect(portContext.structurallyScopedTunnelledDevices.map { $0.id } == [2])
        // Matched first, then scoped.
        #expect(portContext.attributedDevices.map { $0.id } == [1, 2])
        // And every device appears exactly once.
        #expect(Set(portContext.attributedDevices.map { $0.id }).count
            == portContext.attributedDevices.count)
    }

    // MARK: - Test 6: vdoRoleLabel

    @Test("CableReport.vdoRoleLabel maps index 3 to the cable VDO")
    func vdoRoleLabelIsPublic() {
        #expect(CableReport.vdoRoleLabel(at: 3) == "Cable")
    }

    // MARK: - Test: one e-marker selection policy

    @Test("cableEmarker prefers a populated SOP'' over a bare SOP', and partnerIdentity is the SOP")
    func cableEmarkerPrefersPopulatedVDOs() throws {
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: nil, connectionActive: true)
        // The bare SOP' comes FIRST on purpose: a first-match policy would
        // pick it and shadow the populated SOP'' behind it.
        let bare = makeIdentity(portType: 2, portNumber: 1, endpoint: .sopPrime, vdos: [])
        let populated = makeIdentity(
            portType: 2, portNumber: 1, endpoint: .sopDoublePrime,
            vdos: [0x1C60_05AC, 0, 0x720A_0100, 0x110A_2644])
        let partner = makeIdentity(portType: 2, portNumber: 1, endpoint: .sop)

        let context = CableSnapshotContext(snapshot: makeSnapshot(
            ports: [port], identities: [bare, populated, partner]))
        let portContext = try #require(context.portContexts.first)

        #expect(portContext.cableEmarker?.id == populated.id)
        #expect(portContext.partnerIdentity?.id == partner.id)
    }

    @Test("cableEmarker falls back to the first SOP' when no identity carries VDOs")
    func cableEmarkerFallsBackToFirstWhenAllBare() throws {
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: nil, connectionActive: true)
        let first = makeIdentity(portType: 2, portNumber: 1, endpoint: .sopPrime, vdos: [])
        let second = makeIdentity(portType: 2, portNumber: 1, endpoint: .sopDoublePrime, vdos: [])

        let context = CableSnapshotContext(snapshot: makeSnapshot(
            ports: [port], identities: [first, second]))
        let portContext = try #require(context.portContexts.first)

        // `first` and `second` share an id here (makeIdentity derives id from
        // portNumber and vdos.count, and both are bare), so an id comparison
        // could not tell a correct "first in array" pick from an incorrect
        // "last in array" one. Compare endpoint instead, which does
        // distinguish them.
        #expect(portContext.cableEmarker?.endpoint == first.endpoint)
        #expect(portContext.partnerIdentity == nil)
    }

    // MARK: - Helpers

    private func makeSnapshot(
        ports: [AppleHPMInterface],
        powerSources: [PowerSource] = [],
        identities: [USBPDSOP] = [],
        usbDevices: [USBDevice] = [],
        thunderboltSwitches: [IOThunderboltSwitch] = [],
        cioCapabilities: [CIOCableCapability] = [],
        accessoryIdentities: [AppleAccessoryIdentity] = []
    ) -> CableSnapshot {
        CableSnapshot(
            ports: ports,
            powerSources: powerSources,
            identities: identities,
            usbDevices: usbDevices,
            adapter: nil,
            thunderboltSwitches: thunderboltSwitches,
            cioCapabilities: cioCapabilities,
            accessoryIdentities: accessoryIdentities
        )
    }

    private func makeSource(portType: Int, portNumber: Int, uuid: String? = nil,
                            winningMW: Int? = nil, name: String = "USB-PD") -> PowerSource {
        let options = [PowerOption(voltageMV: 20000, maxCurrentMA: 5000,
                                   maxPowerMW: winningMW ?? 100_000)]
        return PowerSource(
            id: UInt64(portNumber), name: name,
            parentPortType: portType, parentPortNumber: portNumber,
            options: options,
            winning: winningMW.map {
                PowerOption(voltageMV: 20000, maxCurrentMA: 5000, maxPowerMW: $0)
            },
            hpmControllerUUID: uuid)
    }

    private func makeIdentity(portType: Int, portNumber: Int, endpoint: USBPDSOP.Endpoint,
                              vdos: [UInt32] = [], uuid: String? = nil) -> USBPDSOP {
        USBPDSOP(id: UInt64(portNumber * 10 + vdos.count), endpoint: endpoint,
                 parentPortType: portType, parentPortNumber: portNumber,
                 vendorID: 0x05AC, productID: 0x1, bcdDevice: 0, vdos: vdos,
                 specRevision: 3, hpmControllerUUID: uuid)
    }

    private func makeUSB3(portKey: String, signaling: Int, uuid: String? = nil) -> USB3Transport {
        USB3Transport(id: 1, portKey: portKey, signaling: signaling,
                      signalingDescription: nil, dataRole: nil,
                      hpmControllerUUID: uuid)
    }

    private func makeTRM(portKey: String, transportType: String,
                         uuid: String? = nil) -> TRMTransport {
        TRMTransport(
            id: 1, portKey: portKey, transportType: transportType,
            state: nil, stateDescription: nil, transportRestricted: nil,
            transportSupervised: nil, identificationRestricted: nil,
            deviceLocked: nil, relaxedPeriod: nil, gracePeriodReason: nil,
            gracePeriodReasonDescription: nil, profile: nil,
            profileDescription: nil, cacheMiss: nil, tunnelled: nil,
            hpmControllerUUID: uuid)
    }

    private func makeCIO(id: UInt64, portKey: String, negotiatedLinkSpeed: Int,
                         uuid: String? = nil) -> CIOCableCapability {
        CIOCableCapability(
            id: id, portKey: portKey, cableGeneration: nil,
            negotiatedLinkSpeed: negotiatedLinkSpeed, generation: nil,
            asymmetricModeSupported: nil, legacyAdapter: nil,
            linkTrainingMode: nil, hpmControllerUUID: uuid)
    }

    private func makeAccessory(id: UInt64, portKey: String, product: String,
                               uuid: String? = nil) -> AppleAccessoryIdentity {
        AppleAccessoryIdentity(
            id: id, portKey: portKey, manufacturer: nil, vendor: nil,
            product: product, userString: nil, model: nil, serialNumber: nil,
            hardwareVersion: nil, vendorID: nil, productID: nil,
            hpmControllerUUID: uuid)
    }

    private func makeDisplayPort(parentPortType: Int, parentPortNumber: Int,
                                 uuid: String?) -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(active: true, laneCount: 4, maxLaneCount: 4,
                                  linkRate: 20, tunneled: false, hpdState: 1),
            monitor: nil,
            parentPortType: parentPortType,
            parentPortNumber: parentPortNumber,
            hpmControllerUUID: uuid
        )
    }

    private func makePort(portNumber: Int, portType: String, uuid: String?,
                          connectionActive: Bool? = nil) -> AppleHPMInterface {
        AppleHPMInterface(
            id: UInt64(portNumber),
            serviceName: "Port-\(portType)@\(portNumber)",
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: portType,
            portNumber: portNumber,
            connectionActive: connectionActive, activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            hpmControllerUUID: uuid,
            rawProperties: ["PortType": portType == "USB-C" ? "2" : "17"]
        )
    }

    /// A port that carries data, so the Thunderbolt socket lookup runs.
    /// Shaped like the fixture in ConnectedDeviceTreeStructuralWiringTests.
    private func makeDataPort(serviceName: String, portNumber: Int) -> AppleHPMInterface {
        AppleHPMInterface(
            id: UInt64(portNumber),
            serviceName: serviceName,
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: "USB-C",
            portNumber: portNumber,
            connectionActive: true, activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            transportsActive: ["CC", "USB3", "CIO"],
            transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "2"]
        )
    }

    private func makeHostRootSwitch(id: Int64, socketID: String,
                                    acioRootName: String) -> IOThunderboltSwitch {
        let lane = IOThunderboltPort(
            portNumber: 1, socketID: socketID, adapterType: .lane,
            currentSpeed: .usb4Tb4, currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil,
            hopTable: [])
        return IOThunderboltSwitch(
            id: id, className: "IOThunderboltSwitchType5", vendorID: 0x5AC,
            vendorName: "Apple Inc.", modelName: "Mac", routerID: 0, depth: 0,
            routeString: 0, upstreamPortNumber: 7, maxPortNumber: 7,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [lane],
            parentSwitchUID: nil, acioRootName: acioRootName)
    }

    private func makeNativeDevice(id: UInt64, controllerPortName: String) -> USBDevice {
        USBDevice(
            id: id, locationID: 0x0100_0000, vendorID: 0x05AC, productID: 0x1234,
            vendorName: "Apple", productName: "Magic Keyboard", serialNumber: nil,
            usbVersion: nil, speedRaw: 2, busPowerMA: nil, currentMA: nil,
            controllerPortName: controllerPortName,
            deviceClass: 0x00, rawProperties: [:])
    }

    private func makeTunnelledDevice(id: UInt64, tunnelRootName: String) -> USBDevice {
        USBDevice(
            id: id, locationID: 0x0310_0000, vendorID: 0x05AC, productID: 0x1234,
            vendorName: nil, productName: "USB2 Hub", serialNumber: nil,
            usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
            isThunderboltTunnelled: true, tunnelBridgeDepth: 2,
            tunnelRootName: tunnelRootName, tunnelCarrier: .usbTunnel,
            deviceClass: 0x09, rawProperties: [:])
    }
}
