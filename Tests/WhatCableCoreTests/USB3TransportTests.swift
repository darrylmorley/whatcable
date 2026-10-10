import Testing
@testable import WhatCableCore

/// Unit tests for the USB3Transport model and its speedLabel computed property.
@Suite("USB3 Transport")
struct USB3TransportTests {

    // MARK: - speedLabel

    @Test("Gen 1 speed label")
    func gen1SpeedLabel() {
        let t = USB3Transport(id: 1, portKey: "2/1", signaling: 1, signalingDescription: "Gen 1", dataRole: "host")
        #expect(t.speedLabel == "USB 3.2 Gen 1 (5 Gbps)")
    }

    @Test("Gen 2 speed label")
    func gen2SpeedLabel() {
        let t = USB3Transport(id: 2, portKey: "2/1", signaling: 2, signalingDescription: "Gen 2", dataRole: "host")
        #expect(t.speedLabel == "USB 3.2 Gen 2 (10 Gbps)")
    }

    @Test("Unknown signaling falls back to generic label")
    func unknownSignalingFallsBackToGenericLabel() {
        let t = USB3Transport(id: 3, portKey: "2/1", signaling: 5, signalingDescription: nil, dataRole: nil)
        #expect(t.speedLabel == "USB 3.2 Gen 5")
    }

    @Test("Nil signaling returns nil")
    func nilSignalingReturnsNil() {
        let t = USB3Transport(id: 4, portKey: "2/1", signaling: nil, signalingDescription: nil, dataRole: nil)
        #expect(t.speedLabel == nil)
    }

    @Test("Zero signaling returns nil (IOKit None sentinel)")
    func zeroSignalingReturnsNil() {
        // SuperSpeedSignaling == 0 with description "None" appears on
        // CIO-tunneled USB3 and idle USB-C ports across all probed Apple
        // Silicon machines. It must not produce "USB 3.2 Gen 0" in the UI
        // (whatcable issue #190 follow-up). Falls through to the generic
        // "SuperSpeed USB (5 Gbps or faster)" text downstream.
        let t = USB3Transport(id: 5, portKey: "2/1", signaling: 0, signalingDescription: "None", dataRole: "host")
        #expect(t.speedLabel == nil)
    }

    // MARK: - Equatable / Hashable

    @Test("Equal transports are equal")
    func equalTransportsAreEqual() {
        let a = USB3Transport(id: 10, portKey: "2/1", signaling: 1, signalingDescription: "Gen 1", dataRole: "host")
        let b = USB3Transport(id: 10, portKey: "2/1", signaling: 1, signalingDescription: "Gen 1", dataRole: "host")
        #expect(a == b)
    }

    @Test("Different IDs are not equal")
    func differentIDsAreNotEqual() {
        let a = USB3Transport(id: 10, portKey: "2/1", signaling: 1, signalingDescription: "Gen 1", dataRole: "host")
        let b = USB3Transport(id: 11, portKey: "2/1", signaling: 1, signalingDescription: "Gen 1", dataRole: "host")
        #expect(a != b)
    }

    @Test("Hashable usable in Set")
    func hashableUsableInSet() {
        let a = USB3Transport(id: 10, portKey: "2/1", signaling: 1, signalingDescription: "Gen 1", dataRole: "host")
        let b = USB3Transport(id: 11, portKey: "2/2", signaling: 2, signalingDescription: "Gen 2", dataRole: "device")
        let set: Set<USB3Transport> = [a, b, a]
        #expect(set.count == 2)
    }

    // MARK: - Identifiable

    @Test("Identifiable ID")
    func identifiableID() {
        let t = USB3Transport(id: 42, portKey: "2/3", signaling: 1, signalingDescription: nil, dataRole: nil)
        #expect(t.id == 42)
    }

    // MARK: - canonicallyMatches

    /// When both the transport and the port carry matching UUIDs, the match
    /// must use UUID comparison, not portKey. This is the collision-proof
    /// path on M3+ where MagSafe@1 and USB-C@1 share portNumber 1.
    @Test("canonicallyMatches uses UUID when both sides have matching UUID")
    func canonicallyMatchesUUIDOnBothSides() {
        let uuid = "7C30AF2D-CC71-7D20-5287-C77DB8476817"
        let transport = USB3Transport(id: 1, portKey: "2/1", signaling: 1,
                                      signalingDescription: "Gen 1", dataRole: "host",
                                      hpmControllerUUID: uuid)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: uuid)
        #expect(transport.canonicallyMatches(port: port))
    }

    /// When the transport has no UUID (M1/M2 hardware) but the portKey matches,
    /// the match must still succeed via the portKey fallback. UUID absence on
    /// the source side must not silently drop the transport from the join.
    @Test("canonicallyMatches falls back to portKey when transport has no UUID (M1/M2)")
    func canonicallyMatchesFallsBackToPortKey() {
        // Transport has no UUID; port does. The portKey "2/1" matches on both sides.
        let transport = USB3Transport(id: 2, portKey: "2/1", signaling: 2,
                                      signalingDescription: "Gen 2", dataRole: "host",
                                      hpmControllerUUID: nil)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: "7C30AF2D-CC71-7D20-5287-C77DB8476817")
        #expect(transport.canonicallyMatches(port: port))
    }

    /// Issue #195 collision guard: two ports share portNumber 1 but carry
    /// different UUIDs (MagSafe@1 and USB-C@1). A USB3 transport for the
    /// USB-C port must NOT match the MagSafe port, even though the portKeys
    /// would agree if UUID comparison were skipped.
    @Test("canonicallyMatches rejects UUID mismatch even when portKey collides (issue #195 guard)")
    func canonicallyMatchesRejectsUUIDMismatch() {
        let usbcUUID    = "6230AF2D-0000-0000-0000-112233445566"
        let magSafeUUID = "7C30AF2D-0000-0000-0000-AABBCCDDEEFF"

        // USB3 transport belongs to the USB-C port.
        let transport = USB3Transport(id: 3, portKey: "2/1", signaling: 1,
                                      signalingDescription: "Gen 1", dataRole: "host",
                                      hpmControllerUUID: usbcUUID)
        // But we try to match it against the MagSafe port (different UUID, same portNumber).
        let magSafePort = makePort(portNumber: 1, portType: "MagSafe 3", uuid: magSafeUUID)

        // Must NOT match: UUIDs differ, so it is a different physical port.
        #expect(!transport.canonicallyMatches(port: magSafePort))
    }

    // MARK: - canonicalJoinKey

    @Test("canonicalJoinKey returns normalised UUID when UUID is present")
    func canonicalJoinKeyNormalisedUUID() {
        let t = USB3Transport(id: 1, portKey: "2/4", signaling: 1, signalingDescription: nil, dataRole: nil,
                              hpmControllerUUID: "AAAA1111-BBBB-2222-CCCC-333344445555")
        #expect(t.canonicalJoinKey == "aaaa1111bbbb2222cccc333344445555")
    }

    @Test("canonicalJoinKey falls back to portKey when UUID is nil")
    func canonicalJoinKeyFallsBackToPortKey() {
        let t = USB3Transport(id: 2, portKey: "2/4", signaling: 1, signalingDescription: nil, dataRole: nil,
                              hpmControllerUUID: nil)
        #expect(t.canonicalJoinKey == "2/4")
    }

    // MARK: - Helpers

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
}
