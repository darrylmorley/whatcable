import XCTest
import WhatCableCore

/// Schema tests for the `whatcable --json` output. The JSON shape is a public
/// contract for downstream consumers (Übersicht / SwiftBar widgets, scripts,
/// pipelines into jq), so a refactor that silently drops or renames a field
/// would break callers without anyone noticing until a bug report.
///
/// We assert against parsed JSON rather than the underlying DTO types so the
/// DTO types can stay private to the formatter.
final class JSONFormatterTests: XCTestCase {

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
            XCTFail("output was not a JSON object")
            return [:]
        }
        return obj
    }

    // MARK: - Top-level shape

    func testTopLevelHasVersionAndPorts() throws {
        let json = try JSONFormatter.render(ports: [], sources: [], identities: [], showRaw: false)
        let obj = parse(json)
        XCTAssertNotNil(obj["version"] as? String)
        XCTAssertNotNil(obj["ports"] as? [[String: Any]])
    }

    func testEmptyPortsListIsAnArray() throws {
        let json = try JSONFormatter.render(ports: [], sources: [], identities: [], showRaw: false)
        let obj = parse(json)
        XCTAssertEqual((obj["ports"] as? [Any])?.count, 0)
    }

    // MARK: - Port shape

    func testPortDTOFields() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let ports = obj["ports"] as? [[String: Any]] ?? []
        let first = try XCTUnwrap(ports.first)

        // These are the always-present keys. cable / device / charging /
        // rawProperties are optional and only appear when relevant data is
        // available; their presence is exercised in dedicated tests below.
        let expected: Set<String> = [
            "name", "type", "className", "connectionActive", "pdCapable", "status",
            "headline", "subtitle", "bullets", "transports", "powerSources"
        ]
        let actual = Set(first.keys)
        XCTAssertTrue(
            expected.isSubset(of: actual),
            "missing keys: \(expected.subtracting(actual))"
        )

        XCTAssertEqual(first["name"] as? String, "Port-USB-C@1")
        XCTAssertEqual(first["type"] as? String, "USB-C")
        XCTAssertEqual(first["className"] as? String, "AppleHPMInterfaceType10")
        XCTAssertEqual(first["connectionActive"] as? Bool, true)
    }

    func testTransportsDTOFields() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let transports = try XCTUnwrap(port["transports"] as? [String: Any])
        XCTAssertEqual(transports["supported"] as? [String], ["CC", "USB2", "USB3"])
        XCTAssertEqual(transports["active"] as? [String], ["USB3"])
        XCTAssertNotNil(transports["provisioned"] as? [String])
    }

    // MARK: - Power sources

    func testPowerSourceDTOIncludesNegotiatedAndOptions() throws {
        let port = makePort()
        let json = try JSONFormatter.render(
            ports: [port], sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let powerSources = try XCTUnwrap(portObj["powerSources"] as? [[String: Any]])
        let pd = try XCTUnwrap(powerSources.first)

        XCTAssertEqual(pd["name"] as? String, "USB-PD")
        XCTAssertEqual(pd["maxPowerW"] as? Int, 96)

        let negotiated = try XCTUnwrap(pd["negotiated"] as? [String: Any])
        XCTAssertEqual(negotiated["voltageV"] as? Double, 20.0)
        XCTAssertEqual(negotiated["powerW"] as? Double, 60.0)

        let options = try XCTUnwrap(pd["options"] as? [[String: Any]])
        XCTAssertEqual(options.count, 1)
    }

    // MARK: - Charging

    func testChargingDTOFields() throws {
        let port = makePort()
        let json = try JSONFormatter.render(
            ports: [port], sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let charging = try XCTUnwrap(portObj["charging"] as? [String: Any])
        XCTAssertNotNil(charging["summary"] as? String)
        XCTAssertNotNil(charging["detail"] as? String)
        XCTAssertNotNil(charging["bottleneck"] as? String)
        XCTAssertNotNil(charging["isWarning"] as? Bool)
        // Bottleneck is a stable enum string, not the Swift case description.
        let bottleneck = charging["bottleneck"] as? String ?? ""
        XCTAssertTrue(
            ["noCharger", "chargerLimit", "cableLimit", "macLimit", "fine"].contains(bottleneck),
            "unexpected bottleneck value: \(bottleneck)"
        )
    }

    // MARK: - Trust flags

    private func cableIdentity(vendorID: Int, cableVDO: UInt32) -> PDIdentity {
        PDIdentity(
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

    func testTrustFlagsOmittedForCleanCable() throws {
        let port = makePort()
        // VID 0x05AC (Apple), USB4 Gen3, 5A, valid latency: no flags expected.
        let id = cableIdentity(vendorID: 0x05AC, cableVDO: (0b10 << 5) | 0b011 | Self.validLatency)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [id], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try XCTUnwrap(portObj["cable"] as? [String: Any])
        XCTAssertNil(cable["trustFlags"])
    }

    func testTrustFlagsPopulatedForZeroVidAndReservedBits() throws {
        let port = makePort()
        // VID=0, speed=6 (reserved), current=3 (reserved), valid latency: three flags.
        let vdo = UInt32(0b110) | UInt32(3 << 5) | Self.validLatency
        let id = cableIdentity(vendorID: 0, cableVDO: vdo)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [id], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try XCTUnwrap(portObj["cable"] as? [String: Any])
        let flags = try XCTUnwrap(cable["trustFlags"] as? [[String: Any]])
        XCTAssertEqual(flags.count, 3)

        let codes = flags.compactMap { $0["code"] as? String }
        XCTAssertEqual(codes, ["zeroVendorID", "reservedSpeedEncoding", "reservedCurrentEncoding"])

        // Each flag carries title + detail.
        for flag in flags {
            XCTAssertNotNil(flag["title"] as? String)
            XCTAssertNotNil(flag["detail"] as? String)
        }
    }

    func testTrustFlagsEmitsH3ForUnregisteredVID() throws {
        let port = makePort()
        // 0xDEAD isn't in the curated map or the bundled USB-IF list.
        let id = cableIdentity(vendorID: 0xDEAD, cableVDO: (0b10 << 5) | 0b011 | Self.validLatency)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [id], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try XCTUnwrap(portObj["cable"] as? [String: Any])
        let flags = try XCTUnwrap(cable["trustFlags"] as? [[String: Any]])
        XCTAssertEqual(flags.count, 1)
        XCTAssertEqual(flags.first?["code"] as? String, "vidNotInUSBIFList")
        // Detail should reference the VID in hex so users can grep / search.
        let detail = flags.first?["detail"] as? String ?? ""
        XCTAssertTrue(detail.contains("0xDEAD"), "detail should include hex VID, got: \(detail)")
    }

    // MARK: - Active Cable VDO 2 surfacing

    private func activeCableIdentity(vdo4: UInt32, vendorID: Int = 0x05AC) -> PDIdentity {
        // Active cable: ufpProductType bits 29..27 = 100 = 4.
        // Cable VDO with valid active termination + USB4 Gen3 + 5A + valid latency.
        let cableVDO: UInt32 = UInt32(0b011) | UInt32(2 << 5) | Self.validLatency | UInt32(0b10 << 11)
        return PDIdentity(
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

    func testActiveBlockOmittedForPassiveCable() throws {
        let port = makePort()
        let passive = cableIdentity(vendorID: 0x05AC, cableVDO: (0b10 << 5) | 0b011 | Self.validLatency)
        let json = try JSONFormatter.render(
            ports: [port], sources: [], identities: [passive], showRaw: false
        )
        let obj = parse(json)
        let portObj = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let cable = try XCTUnwrap(portObj["cable"] as? [String: Any])
        XCTAssertNil(cable["active"], "Passive cables should not surface an active VDO2 block")
    }

    func testActiveBlockPresentForActiveCable() throws {
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
        let cable = try XCTUnwrap(portObj["cable"] as? [String: Any])
        let active = try XCTUnwrap(cable["active"] as? [String: Any])
        XCTAssertEqual(active["physicalConnection"] as? String, "Optical")
        XCTAssertEqual(active["activeElement"] as? String, "Re-timer")
        XCTAssertEqual(active["opticallyIsolated"] as? Bool, true)
        XCTAssertEqual(active["usb4Supported"] as? Bool, true)
    }

    // MARK: - Raw properties gating

    func testRawPropertiesOmittedByDefault() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        // showRaw=false should leave rawProperties absent / null.
        XCTAssertFalse(json.contains("\"rawProperties\" : {"),
                       "rawProperties should not appear as a populated object")
    }

    func testRawPropertiesIncludedWhenRequested() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: true
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        let raw = try XCTUnwrap(port["rawProperties"] as? [String: String])
        XCTAssertEqual(raw["PortType"], "2")
    }

    // MARK: - pdCapable

    func testPDCapableTrueWhenCCPresent() throws {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        XCTAssertEqual(port["pdCapable"] as? Bool, true)
    }

    func testPDCapableFalseWhenCCAbsent() throws {
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
        XCTAssertEqual(portJSON["pdCapable"] as? Bool, false)
        // And the port-level bullet should not claim "basic cable".
        let bullets = portJSON["bullets"] as? [String] ?? []
        XCTAssertFalse(bullets.contains(where: { $0.contains("does not advertise") }),
                       "no-PD port should not claim 'basic cable', got: \(bullets)")
        XCTAssertTrue(bullets.contains(where: { $0.contains("can't read cable details") }),
                      "expected 'port can't read cable details' bullet, got: \(bullets)")
    }

    // MARK: - JSON validity

    func testRendersValidJSONForDisconnectedPort() throws {
        let json = try JSONFormatter.render(
            ports: [makePort(connected: false)], sources: [], identities: [], showRaw: false
        )
        // Must parse successfully and have a port with connectionActive=false.
        let obj = parse(json)
        let port = (obj["ports"] as? [[String: Any]])?.first ?? [:]
        XCTAssertEqual(port["connectionActive"] as? Bool, false)
        XCTAssertEqual(port["status"] as? String, "empty")
        XCTAssertEqual(port["headline"] as? String, "Nothing connected")
    }

    // MARK: - Thunderbolt fabric

    /// The `thunderboltSwitches` key must always be present at the top
    /// level, even when the host has no Thunderbolt controller. The
    /// docstring on `CableSnapshot.thunderboltSwitches` advertises this
    /// to downstream consumers.
    func testThunderboltSwitchesKeyPresentEvenWhenEmpty() throws {
        let json = try JSONFormatter.render(
            ports: [makePort(connected: false)], sources: [], identities: [], showRaw: false
        )
        let obj = parse(json)
        XCTAssertNotNil(obj["thunderboltSwitches"], "top-level key must always exist")
        XCTAssertEqual((obj["thunderboltSwitches"] as? [Any])?.count, 0)
    }

    func testThunderboltSwitchesEncodedAtTopLevel() throws {
        let host = ThunderboltSwitch(
            id: 408750268121704800,
            className: "IOThunderboltSwitchType5",
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
                ThunderboltPort(
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
        XCTAssertEqual(switches.count, 1)

        let sw = switches[0]
        XCTAssertEqual(sw["uid"] as? Int64, 408750268121704800)
        XCTAssertEqual(sw["depth"] as? Int, 0)
        XCTAssertEqual(sw["modelName"] as? String, "iOS")

        let ports = sw["ports"] as? [[String: Any]] ?? []
        let port = ports.first ?? [:]
        XCTAssertEqual(port["adapterType"] as? String, "lane")
        XCTAssertEqual(port["linkActive"] as? Bool, true)
        XCTAssertEqual(port["linkLabel"] as? String, "Up to 20 Gb/s × 2")
        XCTAssertEqual(port["generation"] as? String, "usb4Tb4")
        XCTAssertEqual(port["perLaneGbps"] as? Int, 20)
        XCTAssertEqual(port["txLanes"] as? Int, 2)
    }

    /// TB5 was confirmed against a real M5 Pro + UGreen JHL9580 dock
    /// sample on issue #52, so JSON consumers now get `generation == "tb5"`
    /// alongside the per-lane label and the raw speed code.
    func testTb5JsonGenerationLabelIsConfirmed() throws {
        let host = ThunderboltSwitch(
            id: 1, className: "IOThunderboltSwitchType9",
            vendorID: 1452, vendorName: "Apple Inc.", modelName: "iOS",
            routerID: 0, depth: 0, routeString: 0,
            upstreamPortNumber: 7, maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 14),
            ports: [
                ThunderboltPort(
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
        XCTAssertEqual(gen, "tb5", "TB5 should be reported as confirmed")
        XCTAssertEqual(port["linkLabel"] as? String, "Up to 40 Gb/s × 2")
        XCTAssertEqual(port["perLaneGbps"] as? Int, 40)
        // Raw speed code is still exposed for diagnostics consumers.
        XCTAssertEqual(port["rawSpeedCode"] as? Int, 0x2)
    }

    func testPortDtoCarriesThunderboltSwitchUidReference() throws {
        let host = ThunderboltSwitch(
            id: 12345,
            className: "IOThunderboltSwitchType5",
            vendorID: 1452, vendorName: "Apple Inc.", modelName: "iOS",
            routerID: 0, depth: 0, routeString: 0,
            upstreamPortNumber: 7, maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [
                ThunderboltPort(
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
        // Port-USB-C@1 should resolve via Socket ID "1" → host switch UID.
        XCTAssertEqual(port["thunderboltSwitchUID"] as? Int64, 12345)
    }
}
