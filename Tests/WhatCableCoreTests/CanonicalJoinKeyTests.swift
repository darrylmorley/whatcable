import Foundation
import Testing
@testable import WhatCableCore

/// Tests for the `canonicallyMatches` and `canonicalJoinKey` logic on
/// `PowerSource` and `CIOCableCapability`. These types carry the same
/// UUID-keyed join logic as `USB3Transport` and `TRMTransport`, so each
/// needs the same three-scenario coverage: UUID match, portKey fallback
/// (no UUID on source), and UUID mismatch guard (issue #195).
@Suite("Canonical Join Key")
struct CanonicalJoinKeyTests {

    // MARK: - PowerSource.canonicallyMatches

    @Test("PowerSource matches by UUID when both sides have a UUID")
    func powerSourceMatchesUUID() {
        let uuid = "7C30AF2D-CC71-7D20-5287-C77DB8476817"
        let source = PowerSource(id: 1, name: "USB-PD",
                                 parentPortType: 2, parentPortNumber: 1,
                                 options: [], winning: nil,
                                 hpmControllerUUID: uuid)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: uuid)
        #expect(source.canonicallyMatches(port: port))
    }

    /// No UUID on the source (M1/M2 hardware): portKey fallback must still match.
    /// A source that can't resolve a UUID must not silently drop from the join.
    @Test("PowerSource falls back to portKey when source has no UUID (M1/M2)")
    func powerSourceFallsBackToPortKey() {
        let source = PowerSource(id: 2, name: "USB-PD",
                                 parentPortType: 2, parentPortNumber: 1,
                                 options: [], winning: nil,
                                 hpmControllerUUID: nil)
        let port = makePort(portNumber: 1, portType: "USB-C",
                            uuid: "7C30AF2D-CC71-7D20-5287-C77DB8476817")
        #expect(source.canonicallyMatches(port: port))
    }

    /// Issue #195 guard: MagSafe@1 and USB-C@1 share portNumber 1 but have
    /// distinct UUIDs. A source with the USB-C UUID must not match the MagSafe port.
    @Test("PowerSource rejects UUID mismatch even when portKey collides (issue #195 guard)")
    func powerSourceRejectsUUIDMismatch() {
        let usbcUUID    = "6230AF2D-0000-0000-0000-112233445566"
        let magSafeUUID = "7C30AF2D-0000-0000-0000-AABBCCDDEEFF"
        let source = PowerSource(id: 3, name: "USB-PD",
                                 parentPortType: 2, parentPortNumber: 1,
                                 options: [], winning: nil,
                                 hpmControllerUUID: usbcUUID)
        let magSafePort = makePort(portNumber: 1, portType: "MagSafe 3", uuid: magSafeUUID)
        #expect(!source.canonicallyMatches(port: magSafePort))
    }

    @Test("PowerSource canonicalJoinKey is normalised UUID when UUID present")
    func powerSourceCanonicalJoinKeyIsNormalisedUUID() {
        let source = PowerSource(id: 1, name: "USB-PD",
                                 parentPortType: 2, parentPortNumber: 4,
                                 options: [], winning: nil,
                                 hpmControllerUUID: "AAAA1111-BBBB-2222-CCCC-333344445555")
        #expect(source.canonicalJoinKey == "aaaa1111bbbb2222cccc333344445555")
    }

    @Test("PowerSource canonicalJoinKey falls back to portKey when UUID is nil")
    func powerSourceCanonicalJoinKeyFallsBackToPortKey() {
        let source = PowerSource(id: 2, name: "USB-PD",
                                 parentPortType: 2, parentPortNumber: 3,
                                 options: [], winning: nil,
                                 hpmControllerUUID: nil)
        #expect(source.canonicalJoinKey == "2/3")
    }

    // MARK: - CIOCableCapability.canonicallyMatches

    @Test("CIOCableCapability matches by UUID when both sides have a UUID")
    func cioMatchesUUID() {
        let uuid = "7C30AF2D-CC71-7D20-5287-C77DB8476817"
        let cio = CIOCableCapability(id: 1, portKey: "2/1",
                                     cableGeneration: 2, negotiatedLinkSpeed: 3,
                                     generation: 3, asymmetricModeSupported: nil,
                                     legacyAdapter: nil, linkTrainingMode: nil,
                                     hpmControllerUUID: uuid)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: uuid)
        #expect(cio.canonicallyMatches(port: port))
    }

    @Test("CIOCableCapability falls back to portKey when source has no UUID (M1/M2)")
    func cioFallsBackToPortKey() {
        let cio = CIOCableCapability(id: 2, portKey: "2/1",
                                     cableGeneration: nil, negotiatedLinkSpeed: nil,
                                     generation: nil, asymmetricModeSupported: nil,
                                     legacyAdapter: nil, linkTrainingMode: nil,
                                     hpmControllerUUID: nil)
        let port = makePort(portNumber: 1, portType: "USB-C",
                            uuid: "7C30AF2D-CC71-7D20-5287-C77DB8476817")
        #expect(cio.canonicallyMatches(port: port))
    }

    @Test("CIOCableCapability rejects UUID mismatch even when portKey collides (issue #195 guard)")
    func cioRejectsUUIDMismatch() {
        let cioUUID     = "6230AF2D-0000-0000-0000-112233445566"
        let magSafeUUID = "7C30AF2D-0000-0000-0000-AABBCCDDEEFF"
        let cio = CIOCableCapability(id: 3, portKey: "2/1",
                                     cableGeneration: nil, negotiatedLinkSpeed: nil,
                                     generation: nil, asymmetricModeSupported: nil,
                                     legacyAdapter: nil, linkTrainingMode: nil,
                                     hpmControllerUUID: cioUUID)
        let magSafePort = makePort(portNumber: 1, portType: "MagSafe 3", uuid: magSafeUUID)
        #expect(!cio.canonicallyMatches(port: magSafePort))
    }

    @Test("CIOCableCapability canonicalJoinKey is normalised UUID when UUID present")
    func cioCanonicalJoinKeyIsNormalisedUUID() {
        let cio = CIOCableCapability(id: 1, portKey: "2/2",
                                     cableGeneration: nil, negotiatedLinkSpeed: 3,
                                     generation: nil, asymmetricModeSupported: nil,
                                     legacyAdapter: nil, linkTrainingMode: nil,
                                     hpmControllerUUID: "AAAA1111-BBBB-2222-CCCC-333344445555")
        #expect(cio.canonicalJoinKey == "aaaa1111bbbb2222cccc333344445555")
    }

    @Test("CIOCableCapability canonicalJoinKey falls back to portKey when UUID is nil")
    func cioCanonicalJoinKeyFallsBackToPortKey() {
        let cio = CIOCableCapability(id: 2, portKey: "2/2",
                                     cableGeneration: nil, negotiatedLinkSpeed: nil,
                                     generation: nil, asymmetricModeSupported: nil,
                                     legacyAdapter: nil, linkTrainingMode: nil,
                                     hpmControllerUUID: nil)
        #expect(cio.canonicalJoinKey == "2/2")
    }

    // MARK: - USBPDSOP.canonicallyMatches

    @Test("USBPDSOP matches by UUID when both sides have a UUID")
    func usbpdSOPMatchesUUID() {
        let uuid = "7C30AF2D-CC71-7D20-5287-C77DB8476817"
        let sop = USBPDSOP(id: 1, endpoint: .sopPrime, parentPortType: 2, parentPortNumber: 1,
                           vendorID: 0x413c, productID: 0xb070, bcdDevice: 0, vdos: [], specRevision: 3,
                           hpmControllerUUID: uuid)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: uuid)
        #expect(sop.canonicallyMatches(port: port))
    }

    @Test("USBPDSOP falls back to portKey when source has no UUID (M1/M2)")
    func usbpdSOPFallsBackToPortKey() {
        let sop = USBPDSOP(id: 2, endpoint: .sopPrime, parentPortType: 2, parentPortNumber: 1,
                           vendorID: 0x413c, productID: 0xb070, bcdDevice: 0, vdos: [], specRevision: 3,
                           hpmControllerUUID: nil)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: "7C30AF2D-CC71-7D20-5287-C77DB8476817")
        #expect(sop.canonicallyMatches(port: port))
    }

    @Test("USBPDSOP rejects UUID mismatch even when portKey collides (issue #195 guard)")
    func usbpdSOPRejectsUUIDMismatch() {
        let usbcUUID    = "6230AF2D-0000-0000-0000-112233445566"
        let magSafeUUID = "7C30AF2D-0000-0000-0000-AABBCCDDEEFF"
        let sop = USBPDSOP(id: 3, endpoint: .sopPrime, parentPortType: 2, parentPortNumber: 1,
                           vendorID: 0, productID: 0, bcdDevice: 0, vdos: [], specRevision: 3,
                           hpmControllerUUID: usbcUUID)
        let magSafePort = makePort(portNumber: 1, portType: "MagSafe 3", uuid: magSafeUUID)
        #expect(!sop.canonicallyMatches(port: magSafePort))
    }

    @Test("USBPDSOP canonicalJoinKey is normalised UUID when UUID present")
    func usbpdSOPCanonicalJoinKeyIsNormalisedUUID() {
        let sop = USBPDSOP(id: 1, endpoint: .sop, parentPortType: 2, parentPortNumber: 4,
                           vendorID: 0, productID: 0, bcdDevice: 0, vdos: [], specRevision: 3,
                           hpmControllerUUID: "AAAA1111-BBBB-2222-CCCC-333344445555")
        #expect(sop.canonicalJoinKey == "aaaa1111bbbb2222cccc333344445555")
    }

    @Test("USBPDSOP canonicalJoinKey falls back to portKey when UUID is nil")
    func usbpdSOPCanonicalJoinKeyFallsBackToPortKey() {
        let sop = USBPDSOP(id: 2, endpoint: .sop, parentPortType: 2, parentPortNumber: 3,
                           vendorID: 0, productID: 0, bcdDevice: 0, vdos: [], specRevision: 3,
                           hpmControllerUUID: nil)
        #expect(sop.canonicalJoinKey == "2/3")
    }

    // MARK: - IOPortTransportStateDisplayPort.canonicallyMatches

    @Test("DisplayPort matches by UUID when both sides have a UUID")
    func displayPortMatchesUUID() {
        let uuid = "7C30AF2D-CC71-7D20-5287-C77DB8476817"
        let dp = makeDisplayPort(parentPortType: 2, parentPortNumber: 1, uuid: uuid)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: uuid)
        #expect(dp.canonicallyMatches(port: port))
    }

    @Test("DisplayPort falls back to portKey when source has no UUID (M1/M2)")
    func displayPortFallsBackToPortKey() {
        let dp = makeDisplayPort(parentPortType: 2, parentPortNumber: 1, uuid: nil)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: "7C30AF2D-CC71-7D20-5287-C77DB8476817")
        #expect(dp.canonicallyMatches(port: port))
    }

    @Test("DisplayPort rejects UUID mismatch even when portKey collides (issue #195 guard)")
    func displayPortRejectsUUIDMismatch() {
        let usbcUUID    = "6230AF2D-0000-0000-0000-112233445566"
        let magSafeUUID = "7C30AF2D-0000-0000-0000-AABBCCDDEEFF"
        let dp = makeDisplayPort(parentPortType: 2, parentPortNumber: 1, uuid: usbcUUID)
        let magSafePort = makePort(portNumber: 1, portType: "MagSafe 3", uuid: magSafeUUID)
        #expect(!dp.canonicallyMatches(port: magSafePort))
    }

    @Test("DisplayPort canonicalJoinKey is normalised UUID when UUID present")
    func displayPortCanonicalJoinKeyIsNormalisedUUID() {
        let dp = makeDisplayPort(parentPortType: 2, parentPortNumber: 4,
                                 uuid: "AAAA1111-BBBB-2222-CCCC-333344445555")
        #expect(dp.canonicalJoinKey == "aaaa1111bbbb2222cccc333344445555")
    }

    @Test("DisplayPort canonicalJoinKey falls back to portKey when UUID is nil")
    func displayPortCanonicalJoinKeyFallsBackToPortKey() {
        let dp = makeDisplayPort(parentPortType: 2, parentPortNumber: 3, uuid: nil)
        #expect(dp.canonicalJoinKey == "2/3")
    }

    @Test("DisplayPort hpmControllerUUID is absent from encoded JSON output (privacy guard)")
    func displayPortUUIDNotInEncodedOutput() throws {
        let dp = makeDisplayPort(parentPortType: 2, parentPortNumber: 1,
                                 uuid: "7C30AF2D-CC71-7D20-5287-C77DB8476817")
        let data = try JSONEncoder().encode(dp)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(!json.contains("hpmControllerUUID"),
            "hpmControllerUUID must not appear in encoded DisplayPort JSON")
        #expect(!json.contains("7C30AF2D"),
            "UUID value must not appear in encoded DisplayPort JSON")
    }

    // MARK: - Helpers

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

    private func makePort(portNumber: Int, portType: String, uuid: String?) -> AppleHPMInterface {
        AppleHPMInterface(
            id: UInt64(portNumber),
            serviceName: "Port-\(portType)@\(portNumber)",
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: portType,
            portNumber: portNumber,
            connectionActive: nil, activeCable: nil, opticalCable: nil,
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

    // MARK: - USBPDSOP.matchingPort(in:)

    /// The join the CLI's `--report` path uses to find the port a cable is
    /// plugged into. It feeds `CableClassification`, so picking the wrong
    /// port files a passive cable as active into `data/known-cables.md`.
    private func cableIdentity(portNumber: Int, uuid: String?) -> USBPDSOP {
        USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: portNumber,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0,
            vdos: [0x1C002B1D, 0x00000000, 0x19010097, 0x32084842],
            specRevision: 3,
            hpmControllerUUID: uuid
        )
    }

    @Test("matchingPort picks the identity's own port, not the first one")
    func matchingPortPicksItsOwnPort() {
        let first = makePort(portNumber: 1, portType: "USB-C", uuid: nil)
        let own = makePort(portNumber: 3, portType: "USB-C", uuid: nil)
        let identity = cableIdentity(portNumber: 3, uuid: nil)
        #expect(identity.matchingPort(in: [first, own])?.serviceName == own.serviceName)
    }

    @Test("matchingPort is UUID-keyed when both sides carry a UUID")
    func matchingPortIsUUIDKeyed() {
        // MagSafe@1 and USB-C@1 share a port number and differ only by UUID
        // (issue #195). The identity must land on its own controller.
        let uuidA = "7C30AF2D-CC71-7D20-5287-C77DB8476817"
        let uuidB = "1D9F3C88-0000-0000-0000-0000000000B2"
        let magsafe = makePort(portNumber: 1, portType: "MagSafe 3", uuid: uuidA)
        let usbc = makePort(portNumber: 1, portType: "USB-C", uuid: uuidB)
        let identity = cableIdentity(portNumber: 1, uuid: uuidB)
        #expect(identity.matchingPort(in: [magsafe, usbc])?.serviceName == usbc.serviceName)
    }

    @Test("matchingPort returns nil when the identity's port is absent")
    func matchingPortReturnsNilWhenAbsent() {
        let other = makePort(portNumber: 2, portType: "USB-C", uuid: nil)
        let identity = cableIdentity(portNumber: 4, uuid: nil)
        #expect(identity.matchingPort(in: [other]) == nil)
        #expect(identity.matchingPort(in: []) == nil)
    }
}
