import Foundation
import Testing
import WhatCableCore

/// Schema tests for the `whatcable --json` output. The JSON shape is a public
/// contract for downstream consumers (Ubersicht / SwiftBar widgets, scripts,
/// pipelines into jq), so a refactor that silently drops or renames a field
/// would break callers without anyone noticing until a bug report.
///
/// We assert against parsed JSON rather than the underlying DTO types so the
/// DTO types can stay private to the formatter.
@Suite("JSON Formatter")
struct JSONFormatterTests {

    // MARK: - Fixtures

    private func makePort(connected: Bool = true) -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: connected,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: true,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3"],
            transportsActive: ["USB3"],
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: ["PortType": "2"]
        )
    }

    private func usbPD(maxW: Int, winningW: Int) -> PowerSource {
        let winning = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: winningW * 50,
            maxPowerMW: winningW * 1000
        )
        let max = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: maxW * 50,
            maxPowerMW: maxW * 1000
        )
        return PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [max], winning: winning
        )
    }

    private func parse(_ s: String) -> [String: Any] {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Issue.record("output was not a JSON object")
            return [:]
        }
        return obj
    }

    // MARK: - Top-level shape

    @Test("Top level has version and ports")
    func topLevelHasVersionAndPorts() throws {
        let json = try JSONFormatter.render(ports: [], sources: [], identities: [], showRaw: false)
        let obj = parse(json)
        #expect(obj["version"] as? String != nil)
        #expect(obj["ports"] as? [[String: Any]] != nil)
    }

    @Test("Empty ports list is an array")
    func emptyPortsListIsAnArray() throws {
        let json = try JSONFormatter.render(ports: [], sources: [], identities: [], showRaw: false)
        let obj = parse(json)
        #expect((obj["ports"] as? [Any])?.count == 0)
    }

    // MARK: - Port shape

    @Test("Port DTO fields")
    func portDTOFields() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let ports = obj["ports"] as? [[String: Any]] ?? []
        let first = try #require(ports.first)

        // These are the always-present keys. cable / device / charging /
        // rawProperties are optional and only appear when relevant data is
        // available; their presence is exercised in dedicated tests below.
        let expected: Set<String> = [
            "name", "type", "className", "connectionActive", "pdCapable", "status",
            "headline", "subtitle", "bullets", "transports", "powerSources"
        ]
        let actual = Set(first.keys)
        #expect(
            expected.isSubset(of: actual),
            "missing keys: \(expected.subtracting(actual))"
        )

        #expect(first["name"] as? String == "Port-USB-C@1")
        #expect(first["type"] as? String == "USB-C")
        #expect(first["className"] as? String == "AppleHPMInterfaceType10")
        #expect(first["connectionActive"] as? Bool == true)
    }

    @Test("Transports DTO fields")
    func transportsDTOFields() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let transports = try #require(port["transports"] as? [String: Any])
        #expect(transports["supported"] as? [String] == ["CC", "USB2", "USB3"])
        #expect(transports["active"] as? [String] == ["USB3"])
        #expect(transports["provisioned"] as? [String] != nil)
    }

    @Test("USB3 speed appears in transports DTO")
    func usb3SpeedAppearsInTransportsDTO() throws {
        let port = makePort()
        let transport = USB3Transport(
            id: 200, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: false,
            usb3Transports: [transport]
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let transports = try #require(portObj["transports"] as? [String: Any])
        #expect(transports["usb3Speed"] as? String == "USB 3.2 Gen 2 (10 Gbps)")
    }

    @Test("USB3 speed nil for USB2-only link with stale signals (issue #187)")
    func usb3SpeedNilForUSB2OnlyLinkWithStaleSignals() throws {
        // The HPM controller can leave `IOAccessoryUSBSuperSpeedActive=1`,
        // keep a Gen 2 `IOPortTransportStateUSB3` service registered, and
        // even keep a matched `USBDevice` reporting SuperSpeed when the
        // negotiated link is only USB 2.0. `TransportsActive` is the sole
        // authority: when USB3 isn't in it, `usb3Speed` must be nil.
        let port = USBCPort(
            id: 1, serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C",
            portNumber: 1, connectionActive: true,
            activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: true,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            transportsActive: ["CC", "USB2"],
            transportsProvisioned: ["CC", "USB3", "USB2"],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "2"]
        )
        let transport = USB3Transport(
            id: 187, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let staleDevice = USBDevice(
            id: 300, locationID: 0x0100_0000,
            vendorID: 0x04E8, productID: 0x4001,
            vendorName: nil, productName: "Stale SuperSpeed",
            serialNumber: nil, usbVersion: "3.2",
            speedRaw: 4, busPowerMA: 900, currentMA: 896,
            controllerPortName: "Port-USB-C@1",
            rawProperties: [:]
        )
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: false,
            usb3Transports: [transport],
            usbDevices: [staleDevice]
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let transports = try #require(portObj["transports"] as? [String: Any])
        #expect(transports["usb3Speed"] as? String == nil,
            "USB2-only link must not emit usb3Speed, got: \(String(describing: transports["usb3Speed"]))")
        #expect(transports["active"] as? [String] == ["CC", "USB2"])
    }

    @Test("USB3 speed nil without transport data")
    func usb3SpeedNilWithoutTransportData() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let transports = try #require(portObj["transports"] as? [String: Any])
        // usb3Speed should be absent (null) when no transport data is provided.
        #expect(transports["usb3Speed"] as? String == nil)
    }

    // MARK: - Power sources

    @Test("Power source DTO includes negotiated and options")
    func powerSourceDTOIncludesNegotiatedAndOptions() throws {
        let port = makePort()
        let json = try JSONFormatter.render(
            ports: [port], sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let powerSources = try #require(portObj["powerSources"] as? [[String: Any]])
        let pd = try #require(powerSources.first)

        #expect(pd["name"] as? String == "USB-PD")
        #expect(pd["maxPowerW"] as? Int == 96)

        let negotiated = try #require(pd["negotiated"] as? [String: Any])
        #expect(negotiated["voltageV"] as? Double == 20.0)
        #expect(negotiated["powerW"] as? Double == 60.0)

        let options = try #require(pd["options"] as? [[String: Any]])
        #expect(options.count == 1)
    }

    // MARK: - Charging

    @Test("Charging DTO fields")
    func chargingDTOFields() throws {
        let port = makePort()
        let json = try JSONFormatter.render(
            ports: [port], sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let charging = try #require(portObj["charging"] as? [String: Any])
        #expect(charging["summary"] as? String != nil)
        #expect(charging["detail"] as? String != nil)
        #expect(charging["bottleneck"] as? String != nil)
        #expect(charging["isWarning"] as? Bool != nil)
        // Bottleneck is a stable enum string, not the Swift case description.
        let bottleneck = charging["bottleneck"] as? String ?? ""
        #expect(
            ["noCharger", "chargerLimit", "cableLimit", "macLimit", "fine"].contains(bottleneck),
            "unexpected bottleneck value: \(bottleneck)"
        )
    }

    // MARK: - Trust flags

    private func cableIdentity(vendorID: Int, cableVDO: UInt32) -> USBPDSOP {
        USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 1,
            vendorID: vendorID,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(vendorID),
                0,
                0,
                cableVDO
            ],
            specRevision: 3
        )
    }

    /// Valid cable-latency bits (0001 = ~10 ns / ~1 m).
    private static let validLatency: UInt32 = 1 << 13

    @Test("Trust flags omitted for clean cable")
    func trustFlagsOmittedForCleanCable() throws {
        let port = makePort()
        // VID 0x05AC (Apple), USB4 Gen3, 5A, valid latency: no flags expected.
        let id = cableIdentity(vendorID: 0x05AC, cableVDO: (0b10 << 5) | 0b011 | Self.validLatency)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [id], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try #require(portObj["cable"] as? [String: Any])
        #expect(cable["trustFlags"] == nil)
    }

    @Test("Trust flags populated for zero VID and reserved bits")
    func trustFlagsPopulatedForZeroVidAndReservedBits() throws {
        let port = makePort()
        // VID=0, speed=6 (reserved), current=3 (reserved), valid latency: three flags.
        let vdo = UInt32(0b110) | UInt32(3 << 5) | Self.validLatency
        let id = cableIdentity(vendorID: 0, cableVDO: vdo)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [id], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try #require(portObj["cable"] as? [String: Any])
        let flags = try #require(cable["trustFlags"] as? [[String: Any]])
        #expect(flags.count == 3)

        let codes = flags.compactMap { $0["code"] as? String }
        #expect(codes == ["zeroVendorID", "reservedSpeedEncoding", "reservedCurrentEncoding"])

        // Each flag carries title + detail.
        for flag in flags {
            #expect(flag["title"] as? String != nil)
            #expect(flag["detail"] as? String != nil)
        }
    }

    @Test("Trust flags emits H3 for unregistered VID")
    func trustFlagsEmitsH3ForUnregisteredVID() throws {
        let port = makePort()
        // 0xDEAD isn't in the curated map or the bundled USB-IF list.
        let id = cableIdentity(vendorID: 0xDEAD, cableVDO: (0b10 << 5) | 0b011 | Self.validLatency)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [id], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try #require(portObj["cable"] as? [String: Any])
        let flags = try #require(cable["trustFlags"] as? [[String: Any]])
        #expect(flags.count == 1)
        #expect(flags.first?["code"] as? String == "vidNotInUSBIFList")
        // Detail should reference the VID in hex so users can grep / search.
        let detail = flags.first?["detail"] as? String ?? ""
        #expect(detail.contains("0xDEAD"), "detail should include hex VID, got: \(detail)")
    }

    // MARK: - Active Cable VDO 2 surfacing

    private func activeCableIdentity(vdo4: UInt32, vendorID: Int = 0x05AC) -> USBPDSOP {
        // Active cable: ufpProductType bits 29..27 = 100 = 4.
        // Cable VDO with valid active termination + USB4 Gen3 + 5A + valid latency.
        let cableVDO: UInt32 = UInt32(0b011) | UInt32(2 << 5) | Self.validLatency | UInt32(0b10 << 11)
        return USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 1,
            vendorID: vendorID,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [
                (4 << 27) | UInt32(vendorID),
                0,
                0,
                cableVDO,
                vdo4
            ],
            specRevision: 3
        )
    }

    @Test("Active block omitted for passive cable")
    func activeBlockOmittedForPassiveCable() throws {
        let port = makePort()
        let passive = cableIdentity(vendorID: 0x05AC, cableVDO: (0b10 << 5) | 0b011 | Self.validLatency)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [passive], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try #require(portObj["cable"] as? [String: Any])
        #expect(cable["active"] == nil, "Passive cables should not surface an active VDO2 block")
    }

    @Test("Active block present for active cable")
    func activeBlockPresentForActiveCable() throws {
        let port = makePort()
        // VDO2: optical (bit 10) + retimer (bit 9) + isolated (bit 2).
        // USB4 / USB 3.2 / USB 2.0 supported = leave bits 8, 5, 4 at 0
        // (the spec-defined "supported" value is 0, not 1).
        var vdo4: UInt32 = 0
        vdo4 |= UInt32(1) << 10
        vdo4 |= UInt32(1) << 9
        vdo4 |= UInt32(1) << 2
        let id = activeCableIdentity(vdo4: vdo4)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [id], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try #require(portObj["cable"] as? [String: Any])
        let active = try #require(cable["active"] as? [String: Any])
        #expect(active["physicalConnection"] as? String == "Optical")
        #expect(active["activeElement"] as? String == "Re-timer")
        #expect(active["opticallyIsolated"] as? Bool == true)
        #expect(active["usb4Supported"] as? Bool == true)
    }

    // MARK: - Raw properties gating

    @Test("Raw properties omitted by default")
    func rawPropertiesOmittedByDefault() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        // showRaw=false should leave rawProperties absent / null.
        #expect(json.contains("\"rawProperties\" : {") == false,
                "rawProperties should not appear as a populated object")
    }

    @Test("Raw properties included when requested")
    func rawPropertiesIncludedWhenRequested() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: true
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let raw = try #require(port["rawProperties"] as? [String: String])
        #expect(raw["PortType"] == "2")
    }

    // MARK: - pdCapable

    @Test("PD capable true when CC present")
    func pdCapableTrueWhenCCPresent() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        #expect(port["pdCapable"] as? Bool == true)
    }

    @Test("PD capable false when CC absent")
    func pdCapableFalseWhenCCAbsent() throws {
        // Mimic an M4 Mac Mini front USB-C port: USB-only, no Configuration
        // Channel, so no PD and no SOP' query possible.
        let port = USBCPort(
            id: 5, serviceName: "Port-USB-C@5", className: "IOPort",
            portDescription: "Port-USB-C@5", portTypeDescription: "USB-C",
            portNumber: 5, connectionActive: true, activeCable: nil,
            opticalCable: nil, usbActive: true, superSpeedActive: true,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["USB2", "USB3"],
            transportsActive: ["USB3"],
            transportsProvisioned: ["USB2", "USB3"],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:],
            powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: [:]
        )
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let portJSON = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        #expect(portJSON["pdCapable"] as? Bool == false)
        // And the port-level bullet should not claim a missing e-marker.
        let bullets = portJSON["bullets"] as? [String] ?? []
        #expect(bullets.contains(where: { $0.contains("No e-marker reported") }) == false,
                "no-PD port should not claim a missing e-marker, got: \(bullets)")
        #expect(bullets.contains(where: { $0.contains("can't read cable details") }),
                "expected 'port can't read cable details' bullet, got: \(bullets)")
    }

    // MARK: - JSON validity

    @Test("Renders valid JSON for disconnected port")
    func rendersValidJSONForDisconnectedPort() throws {
        let json = try JSONFormatter.render(
            ports: [makePort(connected: false)], sources: [], identities: [], showRaw: false
        )
        // Must parse successfully and have a port with connectionActive=false.
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        #expect(port["connectionActive"] as? Bool == false)
        #expect(port["status"] as? String == "empty")
        #expect(port["headline"] as? String == "Nothing connected")
    }

    // MARK: - Thunderbolt fabric

    /// The `thunderboltSwitches` key must always be present at the top
    /// level, even when the host has no Thunderbolt controller. The
    /// docstring on `CableSnapshot.thunderboltSwitches` advertises this
    /// to downstream consumers.
    @Test("IOThunderboltSwitches key present even when empty")
    func ioThunderboltSwitchesKeyPresentEvenWhenEmpty() throws {
        let json = try JSONFormatter.render(
            ports: [makePort(connected: false)], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        #expect(obj["thunderboltSwitches"] != nil, "top-level key must always exist")
        #expect((obj["thunderboltSwitches"] as? [Any])?.count == 0)
    }

    @Test("IOThunderboltSwitches encoded at top level")
    func ioThunderboltSwitchesEncodedAtTopLevel() throws {
        let host = IOThunderboltSwitch(
            id: 408750268121704800,
            className: "IOIOThunderboltSwitchType5",
            vendorID: 1452,
            vendorName: "Apple Inc.",
            modelName: "iOS",
            routerID: 0,
            depth: 0,
            routeString: 0,
            upstreamPortNumber: 7,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [
                IOThunderboltPort(
                    portNumber: 1,
                    socketID: "1",
                    adapterType: .lane,
                    currentSpeed: .usb4Tb4,
                    currentWidth: LinkWidth(rawValue: 0x2),
                    targetWidth: .dual,
                    rawTargetSpeed: 12,
                    linkBandwidthRaw: 400
                )
            ],
            parentSwitchUID: nil
        )

        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            thunderboltSwitches: [host]
        )
        let obj = parse(json)
        let switches = obj["thunderboltSwitches"] as? [[String: Any]] ?? []
        #expect(switches.count == 1)

        let sw = switches[0]
        #expect(sw["uid"] as? Int64 == 408750268121704800)
        #expect(sw["depth"] as? Int == 0)
        #expect(sw["modelName"] as? String == "iOS")

        let ports = sw["ports"] as? [[String: Any]] ?? []
        let port = ports.first ?? [:]
        #expect(port["adapterType"] as? String == "lane")
        #expect(port["linkActive"] as? Bool == true)
        #expect(port["linkLabel"] as? String == "Up to 20 Gb/s × 2")
        #expect(port["generation"] as? String == "usb4Tb4")
        #expect(port["perLaneGbps"] as? Int == 20)
        #expect(port["txLanes"] as? Int == 2)
    }

    /// TB5 was confirmed against a real M5 Pro + UGreen JHL9580 dock
    /// sample on issue #52, so JSON consumers now get `generation == "tb5"`
    /// alongside the per-lane label and the raw speed code.
    @Test("TB5 JSON generation label is confirmed")
    func tb5JsonGenerationLabelIsConfirmed() throws {
        let host = IOThunderboltSwitch(
            id: 1, className: "IOIOThunderboltSwitchType9",
            vendorID: 1452, vendorName: "Apple Inc.", modelName: "iOS",
            routerID: 0, depth: 0, routeString: 0,
            upstreamPortNumber: 7, maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 14),
            ports: [
                IOThunderboltPort(
                    portNumber: 1, socketID: "1", adapterType: .lane,
                    currentSpeed: .tb5,
                    currentWidth: LinkWidth(rawValue: 0x2),
                    targetWidth: .dual,
                    rawTargetSpeed: nil, linkBandwidthRaw: 800
                )
            ],
            parentSwitchUID: nil
        )
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            thunderboltSwitches: [host]
        )
        let obj = parse(json)
        let port = ((obj["thunderboltSwitches"] as? [[String: Any]])?.first?["ports"] as? [[String: Any]])?.first ?? [:]
        let gen = port["generation"] as? String ?? ""
        #expect(gen == "tb5", "TB5 should be reported as confirmed")
        #expect(port["linkLabel"] as? String == "Up to 40 Gb/s × 2")
        #expect(port["perLaneGbps"] as? Int == 40)
        // Raw speed code is still exposed for diagnostics consumers.
        #expect(port["rawSpeedCode"] as? Int == 0x2)
    }

    // MARK: - TRM transport state

    @Test("TRM appears on port with restricted transport")
    func trmAppearsOnPortWithRestrictedTransport() throws {
        let port = makePort()
        let trm = TRMTransport(
            id: 300,
            portKey: "2/1",
            transportType: "USB2",
            state: 2,
            stateDescription: "Limited",
            transportRestricted: true,
            transportSupervised: true,
            identificationRestricted: false,
            deviceLocked: false,
            relaxedPeriod: true,
            gracePeriodReason: 4,
            gracePeriodReasonDescription: "Device Unlocked",
            profile: 2,
            profileDescription: "Ask for New Accessories",
            cacheMiss: false
        )
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: false,
            trmTransports: [trm]
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let trmArr = try #require(portObj["trm"] as? [[String: Any]])
        #expect(trmArr.count == 1)

        let entry = trmArr[0]
        #expect(entry["transportType"] as? String == "USB2")
        #expect(entry["state"] as? Int == 2)
        #expect(entry["stateDescription"] as? String == "Limited")
        #expect(entry["transportRestricted"] as? Bool == true)
        #expect(entry["transportSupervised"] as? Bool == true)
        #expect(entry["identificationRestricted"] as? Bool == false)
        #expect(entry["deviceLocked"] as? Bool == false)
        #expect(entry["relaxedPeriod"] as? Bool == true)
        #expect(entry["gracePeriodReason"] as? Int == 4)
        #expect(entry["gracePeriodReasonDescription"] as? String == "Device Unlocked")
        #expect(entry["profile"] as? Int == 2)
        #expect(entry["profileDescription"] as? String == "Ask for New Accessories")
        #expect(entry["cacheMiss"] as? Bool == false)
    }

    @Test("TRM nil when no transport data")
    func trmNilWhenNoTransportData() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        #expect(portObj["trm"] as? [[String: Any]] == nil)
    }

    @Test("TRM multiple transports on same port")
    func trmMultipleTransportsOnSamePort() throws {
        let port = makePort()
        let usb2 = TRMTransport(
            id: 300, portKey: "2/1", transportType: "USB2",
            state: 2, stateDescription: "Limited",
            transportRestricted: true, transportSupervised: true,
            identificationRestricted: nil, deviceLocked: nil,
            relaxedPeriod: nil, gracePeriodReason: nil,
            gracePeriodReasonDescription: nil, profile: nil,
            profileDescription: nil, cacheMiss: nil
        )
        let dp = TRMTransport(
            id: 301, portKey: "2/1", transportType: "DisplayPort",
            state: nil, stateDescription: nil,
            transportRestricted: nil, transportSupervised: false,
            identificationRestricted: nil, deviceLocked: nil,
            relaxedPeriod: nil, gracePeriodReason: nil,
            gracePeriodReasonDescription: nil, profile: nil,
            profileDescription: nil, cacheMiss: nil
        )
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: false,
            trmTransports: [usb2, dp]
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let trmArr = try #require(portObj["trm"] as? [[String: Any]])
        #expect(trmArr.count == 2)

        let types = trmArr.compactMap { $0["transportType"] as? String }
        #expect(types.contains("USB2"))
        #expect(types.contains("DisplayPort"))
    }

    @Test("TRM filtered by port key")
    func trmFilteredByPortKey() throws {
        let port = makePort()  // portKey = "2/1"
        let matchingTRM = TRMTransport(
            id: 300, portKey: "2/1", transportType: "USB2",
            state: 2, stateDescription: "Limited",
            transportRestricted: true, transportSupervised: true,
            identificationRestricted: nil, deviceLocked: nil,
            relaxedPeriod: nil, gracePeriodReason: nil,
            gracePeriodReasonDescription: nil, profile: nil,
            profileDescription: nil, cacheMiss: nil
        )
        let otherPortTRM = TRMTransport(
            id: 301, portKey: "2/4", transportType: "USB2",
            state: 0, stateDescription: "Full",
            transportRestricted: false, transportSupervised: true,
            identificationRestricted: nil, deviceLocked: nil,
            relaxedPeriod: nil, gracePeriodReason: nil,
            gracePeriodReasonDescription: nil, profile: nil,
            profileDescription: nil, cacheMiss: nil
        )
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: false,
            trmTransports: [matchingTRM, otherPortTRM]
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let trmArr = try #require(portObj["trm"] as? [[String: Any]])
        // Only the matching portKey should be included
        #expect(trmArr.count == 1)
        #expect(trmArr[0]["state"] as? Int == 2)
    }

    // MARK: - Adapter DTO

    @Test("Adapter DTO appears with full details")
    func adapterDTOAppearsWithFullDetails() throws {
        let adapter = AdapterInfo(
            watts: 100,
            isCharging: nil,
            source: "AC",
            voltageMV: 20000,
            currentMA: 4990,
            adapterDescription: "pd charger",
            powerTier: 2,
            isWireless: false,
            hvcMenu: [
                AdapterHVCEntry(voltageMV: 5000, currentMA: 2960),
                AdapterHVCEntry(voltageMV: 9000, currentMA: 2980),
                AdapterHVCEntry(voltageMV: 15000, currentMA: 2990),
                AdapterHVCEntry(voltageMV: 20000, currentMA: 4990),
            ]
        )
        let json = try JSONFormatter.render(
            ports: [], sources: [], identities: [], showRaw: false,
            adapter: adapter
        )
        let obj = parse(json)
        let dto = try #require(obj["adapter"] as? [String: Any])
        #expect(dto["watts"] as? Int == 100)
        #expect(dto["source"] as? String == "AC")
        #expect(dto["voltageMV"] as? Int == 20000)
        #expect(dto["currentMA"] as? Int == 4990)
        #expect(dto["description"] as? String == "pd charger")
        #expect(dto["powerTier"] as? Int == 2)
        #expect(dto["isWireless"] as? Bool == false)

        let hvc = try #require(dto["hvcMenu"] as? [[String: Any]])
        #expect(hvc.count == 4)
        #expect(hvc[0]["voltageMV"] as? Int == 5000)
        #expect(hvc[0]["currentMA"] as? Int == 2960)
        #expect(hvc[3]["voltageMV"] as? Int == 20000)
        #expect(hvc[3]["currentMA"] as? Int == 4990)
    }

    @Test("Adapter DTO nil when no adapter")
    func adapterDTONilWhenNoAdapter() throws {
        let json = try JSONFormatter.render(
            ports: [], sources: [], identities: [], showRaw: false,
            adapter: nil
        )
        let obj = parse(json)
        // adapter key should be absent or null
        #expect(obj["adapter"] as? [String: Any] == nil)
    }

    @Test("Adapter DTO minimal fields")
    func adapterDTOMinimalFields() throws {
        let adapter = AdapterInfo(watts: 30, isCharging: nil, source: "AC")
        let json = try JSONFormatter.render(
            ports: [], sources: [], identities: [], showRaw: false,
            adapter: adapter
        )
        let obj = parse(json)
        let dto = try #require(obj["adapter"] as? [String: Any])
        #expect(dto["watts"] as? Int == 30)
        #expect(dto["source"] as? String == "AC")
        // New fields should be null/absent when not provided
        #expect(dto["voltageMV"] as? Int == nil)
        #expect(dto["hvcMenu"] as? [[String: Any]] == nil)
    }

    @Test("Adapter DTO HVC menu omitted when empty")
    func adapterDTOHVCMenuOmittedWhenEmpty() throws {
        let adapter = AdapterInfo(watts: 30, isCharging: nil, source: "AC", hvcMenu: [])
        let json = try JSONFormatter.render(
            ports: [], sources: [], identities: [], showRaw: false,
            adapter: adapter
        )
        let obj = parse(json)
        let dto = try #require(obj["adapter"] as? [String: Any])
        // Empty HVC menu should be null, not an empty array
        #expect(dto["hvcMenu"] as? [[String: Any]] == nil)
    }

    @Test("Port DTO carries IOThunderboltSwitch UID reference")
    func portDtoCarriesIOThunderboltSwitchUidReference() throws {
        let host = IOThunderboltSwitch(
            id: 12345,
            className: "IOIOThunderboltSwitchType5",
            vendorID: 1452, vendorName: "Apple Inc.", modelName: "iOS",
            routerID: 0, depth: 0, routeString: 0,
            upstreamPortNumber: 7, maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [
                IOThunderboltPort(
                    portNumber: 1, socketID: "1", adapterType: .lane,
                    currentSpeed: .usb4Tb4,
                    currentWidth: LinkWidth(rawValue: 0x2),
                    targetWidth: .dual,
                    rawTargetSpeed: 12, linkBandwidthRaw: 400
                )
            ],
            parentSwitchUID: nil
        )

        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            thunderboltSwitches: [host]
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        // Port-USB-C@1 should resolve via Socket ID "1" -> host switch UID.
        #expect(port["thunderboltSwitchUID"] as? Int64 == 12345)
    }

    /// Companion to the test above: a MagSafe port that shares the same
    /// `@1` socket suffix as the first USB-C port (universal on M-class
    /// MacBooks) must NOT inherit the colliding TB switch UID. The
    /// `socketID(for:)` gate refuses the lookup on any port that doesn't
    /// carry data. Without this, the MagSafe JSON would mis-report a
    /// Thunderbolt switch attachment it never had (issue #195).
    @Test("MagSafe port has null thunderboltSwitchUID despite colliding suffix")
    func magSafePortHasNullThunderboltSwitchUid() throws {
        let host = IOThunderboltSwitch(
            id: 408750268121704800,
            className: "IOIOThunderboltSwitchType5",
            vendorID: 1452, vendorName: "Apple Inc.", modelName: "iOS",
            routerID: 0, depth: 0, routeString: 0,
            upstreamPortNumber: 7, maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [
                IOThunderboltPort(
                    portNumber: 1, socketID: "1", adapterType: .lane,
                    currentSpeed: .usb4Tb4,
                    currentWidth: LinkWidth(rawValue: 0x2),
                    targetWidth: .dual,
                    rawTargetSpeed: 12, linkBandwidthRaw: 400
                )
            ],
            parentSwitchUID: nil
        )

        let magSafe = USBCPort(
            id: 2,
            serviceName: "Port-MagSafe 3@1",
            className: "AppleTCControllerType11",
            portDescription: "Port-MagSafe 3@1",
            portTypeDescription: "MagSafe 3",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [],
            transportsActive: ["CC"],
            transportsProvisioned: ["CC"],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:],
            powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: [:]
        )

        let json = try JSONFormatter.render(
            ports: [magSafe], sources: [], identities: [], showRaw: false,
            thunderboltSwitches: [host]
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        // The `thunderboltSwitchUID` field is encoded with
        // `encodeIfPresent`, so a nil value is omitted from the JSON
        // entirely. Either absent or explicitly null is fine; what
        // matters is that the colliding USB-C@1 switch UID does NOT
        // appear.
        let switchUID = port["thunderboltSwitchUID"]
        #expect(switchUID == nil || switchUID is NSNull,
            "MagSafe should not inherit USB-C@1's TB switch UID via the @N suffix collision; got: \(String(describing: switchUID))")
        // Defence-in-depth: no data-link verdict should appear on this
        // port either, since `carriesData` is false. Same encoding
        // rule, so the key is either absent or null.
        let dataLink = port["dataLink"]
        #expect(dataLink == nil || dataLink is NSNull,
            "MagSafe should not produce a data-link verdict, got: \(String(describing: dataLink))")
    }

    /// When the cable's e-marker reports a speed meaningfully below the
    /// active link rate and there is no controller (CIO) reading to
    /// break the tie, the new `.cableContradictsActive` bottleneck must
    /// flow through to the JSON output. Replaces the old silent
    /// cable-floor promotion that produced a confidently-wrong
    /// "Running at full data speed" verdict (issue #195 amplifier).
    @Test("dataLink.bottleneck encodes cableContradictsActive")
    func dataLinkBottleneckEncodesCableContradictsActive() throws {
        // 40 Gbps TB lane on the host root; the USB-C port advertises
        // "CIO" in transportsActive so the activeTBGbps gate is open.
        let host = IOThunderboltSwitch(
            id: 1, className: "IOIOThunderboltSwitchType5",
            vendorID: 1452, vendorName: "Apple Inc.", modelName: "iOS",
            routerID: 0, depth: 0, routeString: 0,
            upstreamPortNumber: 7, maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [
                IOThunderboltPort(
                    portNumber: 1, socketID: "1", adapterType: .lane,
                    currentSpeed: .usb4Tb4,
                    currentWidth: LinkWidth(rawValue: 0x2),
                    targetWidth: nil, rawTargetSpeed: nil,
                    linkBandwidthRaw: nil
                )
            ],
            parentSwitchUID: nil
        )

        let usbC = USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            transportsActive: ["CC", "CIO"],
            transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:],
            powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: [:]
        )

        // E-marker reporting USB 2.0 (speedCode 0 = 0.48 Gbps); no CIO
        // capability passed, so there is no tie-break.
        let validLatency: UInt32 = 1 << 13
        let cableVDO: UInt32 = 0 | (1 << 5) | validLatency
        let idHeader: UInt32 = 0x1800_0000
        let cableEmarker = USBPDSOP(
            id: 9, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 0
        )

        let json = try JSONFormatter.render(
            ports: [usbC], sources: [], identities: [cableEmarker],
            showRaw: false, thunderboltSwitches: [host]
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let dataLink = port["dataLink"] as? [String: Any] ?? [:]
        #expect(dataLink["bottleneck"] as? String == "cableContradictsActive",
            "expected cableContradictsActive bottleneck, got: \(String(describing: dataLink["bottleneck"]))")
        #expect(dataLink["isWarning"] as? Bool == true,
            "cableContradictsActive should warn; got isWarning: \(String(describing: dataLink["isWarning"]))")
    }

    @Test("Display verdict appears as a port `display` object")
    func displayDTOAppears() throws {
        // makePort is portKey "2/1"; the DP node's parent must match so the
        // formatter correlates them. A 2-lane HBR2 link with the G34w-10 EDID
        // falls short of its 100Hz ceiling -> belowMonitorMax.
        let dp = IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: true, laneCount: 2, maxLaneCount: 4, linkRate: 3,
                linkRateDescription: "5.4 Gbps (HBR2)", tunneled: false, hpdState: 1
            ),
            monitor: MonitorInfo(
                manufacturerName: nil, productName: nil, productId: nil,
                yearOfManufacture: nil, edid: Data(EDIDInfoTests.g34wBaseBlock)
            ),
            parentPortType: 2,
            parentPortNumber: 1
        )
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [],
            showRaw: false, displayPorts: [dp]
        )
        let port = (parse(json)["ports"] as? [[String: Any]])?.first ?? [:]
        let display = port["display"] as? [String: Any] ?? [:]
        #expect(display["bottleneck"] as? String == "belowMonitorMax",
            "got: \(String(describing: display["bottleneck"]))")
        #expect(display["monitorName"] as? String == "LEN G34w-10")
        #expect(display["lanes"] as? Int == 2)
        #expect(display["maxLanes"] as? Int == 4)
    }
}
