import Testing
@testable import WhatCableCore

/// Unit tests for TRMTransport model.
@Suite("TRM Transport")
struct TRMTransportTests {

    // MARK: - Basic properties

    @Test("Is restricted when state is 2")
    func isRestrictedWhenStateIs2() {
        let t = makeTRM(state: 2, transportRestricted: nil)
        #expect(t.isRestricted)
    }

    @Test("Is restricted when transportRestricted is true")
    func isRestrictedWhenTransportRestrictedTrue() {
        let t = makeTRM(state: nil, transportRestricted: true)
        #expect(t.isRestricted)
    }

    @Test("Not restricted when state is 0")
    func notRestrictedWhenStateIs0() {
        let t = makeTRM(state: 0, transportRestricted: false)
        #expect(!t.isRestricted)
    }

    @Test("Not restricted when all nil")
    func notRestrictedWhenAllNil() {
        let t = makeTRM(state: nil, transportRestricted: nil)
        #expect(!t.isRestricted)
    }

    // MARK: - Summary label

    @Test("Summary label with state description")
    func summaryLabelWithStateDescription() {
        let t = makeTRM(transportType: "USB2", stateDescription: "Limited")
        #expect(t.summaryLabel == "USB2: Limited")
    }

    @Test("Summary label falls back to Supervised")
    func summaryLabelFallsBackToSupervised() {
        let t = makeTRM(transportType: "DisplayPort", stateDescription: nil, transportSupervised: true)
        #expect(t.summaryLabel == "DisplayPort: Supervised")
    }

    @Test("Summary label falls back to Unknown")
    func summaryLabelFallsBackToUnknown() {
        let t = makeTRM(transportType: "CIO", stateDescription: nil, transportSupervised: nil)
        #expect(t.summaryLabel == "CIO: Unknown")
    }

    // MARK: - Equatable / Hashable

    @Test("Equatable")
    func equatable() {
        let a = makeTRM(id: 1, state: 2)
        let b = makeTRM(id: 1, state: 2)
        #expect(a == b)
    }

    @Test("Not equal when state differs")
    func notEqualWhenStateDiffers() {
        let a = makeTRM(id: 1, state: 0)
        let b = makeTRM(id: 1, state: 2)
        #expect(a != b)
    }

    @Test("Hashable")
    func hashable() {
        let a = makeTRM(id: 1, transportType: "USB2")
        let b = makeTRM(id: 2, transportType: "DisplayPort")
        let set: Set<TRMTransport> = [a, b, a]
        #expect(set.count == 2)
    }

    // MARK: - Full init preserves all fields

    @Test("Full init preserves all fields")
    func fullInit() {
        let t = TRMTransport(
            id: 42,
            portKey: "0/2",
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
        #expect(t.id == 42)
        #expect(t.portKey == "0/2")
        #expect(t.transportType == "USB2")
        #expect(t.state == 2)
        #expect(t.stateDescription == "Limited")
        #expect(t.transportRestricted == true)
        #expect(t.transportSupervised == true)
        #expect(t.identificationRestricted == false)
        #expect(t.deviceLocked == false)
        #expect(t.relaxedPeriod == true)
        #expect(t.gracePeriodReason == 4)
        #expect(t.gracePeriodReasonDescription == "Device Unlocked")
        #expect(t.profile == 2)
        #expect(t.profileDescription == "Ask for New Accessories")
        #expect(t.cacheMiss == false)
    }

    @Test("Minimal init")
    func minimalInit() {
        let t = TRMTransport(
            id: 1,
            portKey: "0/4",
            transportType: "DisplayPort",
            state: nil,
            stateDescription: nil,
            transportRestricted: nil,
            transportSupervised: false,
            identificationRestricted: nil,
            deviceLocked: nil,
            relaxedPeriod: nil,
            gracePeriodReason: nil,
            gracePeriodReasonDescription: nil,
            profile: nil,
            profileDescription: nil,
            cacheMiss: nil
        )
        #expect(t.state == nil)
        #expect(t.stateDescription == nil)
        #expect(!t.isRestricted)
        #expect(t.transportSupervised == false)
    }

    // MARK: - CableSnapshot backward compatibility

    @Test("CableSnapshot defaults to empty TRM")
    func cableSnapshotDefaultsToEmptyTRM() {
        let snapshot = CableSnapshot(
            ports: [], powerSources: [], identities: [],
            usbDevices: [], adapter: nil
        )
        #expect(snapshot.trmTransports.isEmpty)
    }

    // MARK: - canonicallyMatches

    /// UUID match: both transport and port carry the same UUID. Must match.
    @Test("canonicallyMatches uses UUID when both sides have matching UUID")
    func canonicallyMatchesUUIDOnBothSides() {
        let uuid = "7C30AF2D-CC71-7D20-5287-C77DB8476817"
        let t = makeTRM(portKey: "2/1", uuid: uuid)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: uuid)
        #expect(t.canonicallyMatches(port: port))
    }

    /// No UUID on transport (M1/M2): must fall back to portKey comparison.
    @Test("canonicallyMatches falls back to portKey when transport has no UUID (M1/M2)")
    func canonicallyMatchesFallsBackToPortKey() {
        let t = makeTRM(portKey: "2/1", uuid: nil)
        let port = makePort(portNumber: 1, portType: "USB-C", uuid: "7C30AF2D-CC71-7D20-5287-C77DB8476817")
        #expect(t.canonicallyMatches(port: port))
    }

    /// Issue #195 guard: same portNumber, different UUIDs. Must NOT match.
    @Test("canonicallyMatches rejects UUID mismatch even when portKey collides (issue #195 guard)")
    func canonicallyMatchesRejectsUUIDMismatch() {
        let trmUUID     = "6230AF2D-0000-0000-0000-112233445566"
        let magSafeUUID = "7C30AF2D-0000-0000-0000-AABBCCDDEEFF"
        let t = makeTRM(portKey: "2/1", uuid: trmUUID)
        let magSafePort = makePort(portNumber: 1, portType: "MagSafe 3", uuid: magSafeUUID)
        #expect(!t.canonicallyMatches(port: magSafePort))
    }

    // MARK: - canonicalJoinKey

    @Test("canonicalJoinKey returns normalised UUID when UUID is present")
    func canonicalJoinKeyNormalisedUUID() {
        let t = makeTRM(uuid: "AAAA1111-BBBB-2222-CCCC-333344445555")
        #expect(t.canonicalJoinKey == "aaaa1111bbbb2222cccc333344445555")
    }

    @Test("canonicalJoinKey falls back to portKey when UUID is nil")
    func canonicalJoinKeyFallsBackToPortKey() {
        let t = makeTRM(portKey: "2/3", uuid: nil)
        #expect(t.canonicalJoinKey == "2/3")
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

    private func makeTRM(
        id: UInt64 = 1,
        portKey: String = "0/2",
        transportType: String = "USB2",
        state: Int? = nil,
        stateDescription: String? = nil,
        transportRestricted: Bool? = nil,
        transportSupervised: Bool? = nil,
        uuid: String? = nil
    ) -> TRMTransport {
        TRMTransport(
            id: id,
            portKey: portKey,
            transportType: transportType,
            state: state,
            stateDescription: stateDescription,
            transportRestricted: transportRestricted,
            transportSupervised: transportSupervised,
            identificationRestricted: nil,
            deviceLocked: nil,
            relaxedPeriod: nil,
            gracePeriodReason: nil,
            gracePeriodReasonDescription: nil,
            profile: nil,
            profileDescription: nil,
            cacheMiss: nil,
            hpmControllerUUID: uuid
        )
    }
}
