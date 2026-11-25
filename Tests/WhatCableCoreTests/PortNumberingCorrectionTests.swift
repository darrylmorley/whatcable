import Foundation
import Testing
@testable import WhatCableCore

// Public issue #627: macOS swaps Port-USB-C@6 and Port-USB-A@2 on
// the M5 Max Mac Studio (Mac17,14). T1 pins the table; T2 pins that a
// corrected card and its corrected transport share one port key.
//
// The property values below are copied from the IOPort node and its
// IOPortTransportStateUSB3 child in format-1 run
// 397cf7be-d888-4b06-b64d-d5adac29f7ba (the socket macOS calls
// Port-USB-A@2). No serials or identifiers are involved.

private let studio = "Mac17,14"

/// T1: the table itself.
@Suite("PortNumberingCorrection table (issue #627)")
struct PortNumberingCorrectionTests {

    @Test("Mac17,14 swaps USB-C@6 and USB-A@2 both ways, by code and by name")
    func swapsBothWays() {
        let c6 = PortNumberingCorrection.corrected(type: 2, number: 6, model: studio)
        #expect(c6.type == 3 && c6.number == 2)
        let a2 = PortNumberingCorrection.corrected(type: 3, number: 2, model: studio)
        #expect(a2.type == 2 && a2.number == 6)
        #expect(PortNumberingCorrection.corrected(portNodeName: "Port-USB-C@6", model: studio) == "Port-USB-A@2")
        #expect(PortNumberingCorrection.corrected(portNodeName: "Port-USB-A@2", model: studio) == "Port-USB-C@6")
    }

    @Test("Mac17,14 leaves C@5, A@1 and the Thunderbolt ports alone")
    func otherSocketsUnchanged() {
        for (type, number) in [(2, 1), (2, 2), (2, 3), (2, 4), (2, 5), (3, 1), (17, 1), (3, 6)] {
            let out = PortNumberingCorrection.corrected(type: type, number: number, model: studio)
            #expect(out.type == type && out.number == number, "\(type)/\(number)")
        }
        for name in ["Port-USB-C@1", "Port-USB-C@4", "Port-USB-C@5", "Port-USB-A@1",
                     "Port-MagSafe 3@1", "Port-USB-C@6x", "Port-USB-A", "Port-HDMI@2", ""] {
            #expect(PortNumberingCorrection.corrected(portNodeName: name, model: studio) == name, "\(name)")
        }
    }

    @Test("No other model is corrected", arguments: ["Mac16,9", "Mac16,10", "Mac16,11", "Mac17,13", "unknown", "", "mac17,14", "Mac17,14 "] as [String?] + [nil])
    func otherModelsUnchanged(model: String?) {
        let c6 = PortNumberingCorrection.corrected(type: 2, number: 6, model: model)
        #expect(c6.type == 2 && c6.number == 6)
        let a2 = PortNumberingCorrection.corrected(type: 3, number: 2, model: model)
        #expect(a2.type == 3 && a2.number == 2)
        #expect(PortNumberingCorrection.corrected(portNodeName: "Port-USB-A@2", model: model) == "Port-USB-A@2")
        #expect(PortNumberingCorrection.corrected(portNodeName: "Port-USB-C@6", model: model) == "Port-USB-C@6")
        let port = Fixture.ioPortA2
        for key in port.keys {
            let out = PortNumberingCorrection.correctingRead({ port[$0] }, model: model) { read in read(key) }
            #expect(Fixture.same(out, port[key]), "\(key)")
        }
        let transport = Fixture.usb3UnderA2
        for key in transport.keys {
            let out = PortNumberingCorrection.correctingRead({ transport[$0] }, model: model) { read in read(key) }
            #expect(Fixture.same(out, transport[key]), "\(key)")
        }
    }

    @Test("correctingRead rewrites the port node's naming keys on Mac17,14")
    func correctingReadPortNode() {
        let port = Fixture.ioPortA2
        PortNumberingCorrection.correctingRead({ port[$0] }, model: studio) { read in
            #expect((read("PortType") as? NSNumber)?.intValue == 2)
            #expect((read("PortNumber") as? NSNumber)?.intValue == 6)
            #expect(read("PortTypeDescription") as? String == "USB-C")
            #expect(read("PortDescription") as? String == "Port-USB-C@6")
            #expect(read("Description") as? String == "Port-USB-C@6")
        }
        let c6 = Fixture.ioPortC6
        PortNumberingCorrection.correctingRead({ c6[$0] }, model: studio) { read in
            #expect((read("PortType") as? NSNumber)?.intValue == 3)
            #expect((read("PortNumber") as? NSNumber)?.intValue == 2)
            #expect(read("PortTypeDescription") as? String == "USB-A")
            #expect(read("PortDescription") as? String == "Port-USB-A@2")
            #expect(read("Description") as? String == "Port-USB-A@2")
        }
    }

    @Test("correctingRead rewrites a transport node's parent keys on Mac17,14")
    func correctingReadTransport() {
        let t = Fixture.usb3UnderA2
        PortNumberingCorrection.correctingRead({ t[$0] }, model: studio) { read in
            #expect((read("ParentPortType") as? NSNumber)?.intValue == 2)
            #expect((read("ParentPortNumber") as? NSNumber)?.intValue == 6)
            #expect((read("ParentBuiltInPortType") as? NSNumber)?.intValue == 2)
            #expect((read("ParentBuiltInPortNumber") as? NSNumber)?.intValue == 6)
            #expect(read("ParentPortTypeDescription") as? String == "USB-C")
            #expect(read("ParentBuiltInPortTypeDescription") as? String == "USB-C")
            #expect(read("TransportDescription") as? String == "Port-USB-C@6/USB3")
        }
    }

    @Test("Keys that do not name a port pass through correctingRead untouched")
    func unrelatedKeysPassThrough() {
        var merged = Fixture.ioPortA2
        for (key, value) in Fixture.usb3UnderA2 { merged[key] = value }
        let named: Set<String> = [
            "PortType", "PortNumber", "PortTypeDescription", "PortDescription", "Description",
            "ParentPortType", "ParentPortNumber", "ParentPortTypeDescription",
            "ParentBuiltInPortType", "ParentBuiltInPortNumber", "ParentBuiltInPortTypeDescription",
            "TransportDescription",
        ]
        for key in merged.keys where !named.contains(key) {
            let out = PortNumberingCorrection.correctingRead({ merged[$0] }, model: studio) { read in read(key) }
            #expect(Fixture.same(out, merged[key]), "\(key)")
        }
        let absent = PortNumberingCorrection.correctingRead({ merged[$0] }, model: studio) { read in read("NoSuchKey") }
        #expect(absent == nil)
    }
}

/// T2: identity. The card is built the way production builds it: the
/// per-key read is corrected, `readAll` is macOS's uncorrected dictionary.
@Suite("Corrected port identity joins its transport (issue #627)")
struct PortNumberingCorrectionIdentityTests {

    static func correctedCard(readAll: Bool = true) -> AppleHPMInterface? {
        let raw = Fixture.ioPortA2
        let name = PortNumberingCorrection.corrected(portNodeName: "Port-USB-A@2", model: studio)
        return PortNumberingCorrection.correctingRead({ raw[$0] }, model: studio) { read in
            AppleHPMInterface.from(
                entryID: 0x1000005e5,
                serviceName: name,
                className: "IOPort",
                read: read,
                readAll: readAll ? { raw } : nil,
                registryPortName: "Port-USB-A@2"
            )
        }
    }

    static func correctedTransportKey() -> String {
        let t = Fixture.usb3UnderA2
        return PortNumberingCorrection.correctingRead({ t[$0] }, model: studio) { read in
            let type = (read("ParentBuiltInPortType") as? NSNumber)?.intValue ?? -1
            let number = (read("ParentBuiltInPortNumber") as? NSNumber)?.intValue ?? -1
            return "\(type)/\(number)"
        }
    }

    @Test("The corrected card is keyed 2/6, the same as its corrected transport")
    func cardKeyMatchesTransport() throws {
        let card = try #require(Self.correctedCard())
        // rawProperties stays macOS's own: PortType 3.
        #expect(card.rawProperties["PortType"] == "3")
        #expect(card.rawProperties["PortDescription"] == "Port-USB-A@2")
        #expect(card.serviceName == "Port-USB-C@6")
        #expect(card.registryPortName == "Port-USB-A@2")
        #expect(card.portKey == "2/6")
        #expect(Self.correctedTransportKey() == "2/6")

        let transport = USB3Transport(
            id: 0x1000006e2, portKey: Self.correctedTransportKey(),
            signaling: 0, signalingDescription: "None", dataRole: nil, active: true
        )
        #expect(USB3SpeedCorroboration.selectedTransport(for: card, in: [transport])?.id == 0x1000006e2)
    }

    @Test("PortPowerPrecedence keys the corrected card 2/6 too")
    func powerPrecedenceKey() throws {
        let card = try #require(Self.correctedCard())
        let resolutions = PortPowerPrecedence.resolve(
            ports: [card], samples: [], powerSources: [],
            chargerAttached: false, onBattery: false, batteryInstalled: false
        )
        #expect(resolutions.map(\.identity.key) == ["2/6"])
    }

    @Test("A memberwise fixture with no reportedTypeCode still keys from rawProperties")
    func fallbackToRawPortType() {
        let port = AppleHPMInterface(
            id: 1, serviceName: "Port-MagSafe 3@1", className: "AppleHPMInterfaceType11",
            portDescription: "Port-MagSafe 3@1", portTypeDescription: "USB-C", portNumber: 1,
            connectionActive: true, activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil, overcurrentCount: nil,
            pinConfiguration: [:], powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "17"]
        )
        #expect(port.reportedTypeCode == nil)
        #expect(port.registryPortName == nil)
        #expect(port.portKey == "17/1")
    }

    @Test("--json carries registryPortName on the corrected port only")
    func jsonField() throws {
        let card = try #require(Self.correctedCard())
        let plain = try #require(Fixture.plainCard())
        let out = try JSONFormatter.render(ports: [card, plain], sources: [], identities: [], showRaw: true)
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        let ports = try #require(obj["ports"] as? [[String: Any]])
        let corrected = try #require(ports.first { $0["name"] as? String == "Port-USB-C@6" })
        #expect(corrected["registryPortName"] as? String == "Port-USB-A@2")
        #expect((corrected["rawProperties"] as? [String: String])?["PortDescription"] == "Port-USB-A@2")
        let other = try #require(ports.first { $0["name"] as? String == "Port-USB-C@5" })
        #expect(other.keys.contains("registryPortName") == false)
    }

    @Test("--raw prints one note on the corrected port only")
    func rawNote() throws {
        let card = try #require(Self.correctedCard())
        let plain = try #require(Fixture.plainCard())
        let note = "macOS names this port Port-USB-A@2; corrected for this Mac model"
        let corrected = TextFormatter.render(ports: [card], sources: [], identities: [], showRaw: true)
        #expect(corrected.components(separatedBy: note).count == 2, "\(corrected)")
        let other = TextFormatter.render(ports: [plain], sources: [], identities: [], showRaw: true)
        #expect(!other.contains("macOS names this port"))
        let notRaw = TextFormatter.render(ports: [card], sources: [], identities: [], showRaw: false)
        #expect(!notRaw.contains("macOS names this port"))
    }
}

/// Property dictionaries as macOS published them in run 397cf7be.
enum Fixture {
    static let ioPortA2: [String: Any] = [
        "BuiltIn": true,
        "ConnectionActive": true,
        "ConnectionCount": NSNumber(value: 1),
        "Description": "Port-USB-A@2",
        "PortDescription": "Port-USB-A@2",
        "PortNumber": NSNumber(value: 2),
        "PortType": NSNumber(value: 3),
        "PortTypeDescription": "USB-A",
        "TransportsActive": ["USB3"],
        "TransportsProvisioned": ["USB2", "USB3"],
        "TransportsSupported": ["USB2", "USB3"],
        "UserAuthorizationStatusDescription": "Not Required",
    ]

    static let ioPortC6: [String: Any] = [
        "BuiltIn": true,
        "ConnectionActive": true,
        "Description": "Port-USB-C@6",
        "PortDescription": "Port-USB-C@6",
        "PortNumber": NSNumber(value: 6),
        "PortType": NSNumber(value: 2),
        "PortTypeDescription": "USB-C",
        "TransportsActive": ["USB3"],
        "TransportsSupported": ["USB2", "USB3"],
    ]

    static let usb3UnderA2: [String: Any] = [
        "Active": true,
        "ParentBuiltInPortNumber": NSNumber(value: 2),
        "ParentBuiltInPortType": NSNumber(value: 3),
        "ParentBuiltInPortTypeDescription": "USB-A",
        "ParentPortBuiltIn": true,
        "ParentPortNumber": NSNumber(value: 2),
        "ParentPortType": NSNumber(value: 3),
        "ParentPortTypeDescription": "USB-A",
        "PortDataRole": NSNumber(value: 2),
        "PortDataRoleDescription": "Host",
        "SuperSpeedSignaling": NSNumber(value: 0),
        "SuperSpeedSignalingDescription": "None",
        "TransportDescription": "Port-USB-A@2/USB3",
        "TransportType": NSNumber(value: 3),
        "TransportTypeDescription": "USB3",
    ]

    /// An uncorrected front USB-C card (Port-USB-C@5), built with no model.
    static func plainCard() -> AppleHPMInterface? {
        let raw: [String: Any] = [
            "ConnectionActive": true, "PortDescription": "Port-USB-C@5",
            "PortNumber": NSNumber(value: 5), "PortType": NSNumber(value: 2),
            "PortTypeDescription": "USB-C", "TransportsSupported": ["USB2", "USB3"],
        ]
        return AppleHPMInterface.from(
            entryID: 5, serviceName: "Port-USB-C@5", className: "IOPort",
            read: { raw[$0] }, readAll: { raw }
        )
    }

    /// Value equality for the property types these fixtures use.
    static func same(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l as NSObject, r as NSObject): return l.isEqual(r)
        default: return false
        }
    }
}
