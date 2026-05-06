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

    func testTrustFlagsOmittedForCleanCable() throws {
        let port = makePort()
        // VID 0x05AC (Apple), USB4 Gen3, 5A: no flags expected.
        let id = cableIdentity(vendorID: 0x05AC, cableVDO: (0b10 << 5) | 0b011)
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
        // VID=0, speed=6 (reserved), current=3 (reserved): all three flags.
        let vdo = UInt32(0b110) | UInt32(3 << 5)
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
}
