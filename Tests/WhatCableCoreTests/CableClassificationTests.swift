import Foundation
import Testing
@testable import WhatCableCore

@Suite("Cable Classification")
struct CableClassificationTests {

    // Real corpus fingerprint: CalDigit 2M Thunderbolt 4 cable, VID 0x2B1D,
    // PID 0x1901. The ID Header self-reports passive while VDO[3] bit 3 is
    // set, which only exists in the active layout.
    private static let caldigitContradictionVDOs: [UInt32] = [
        0x1C002B1D, 0x00000000, 0x19010097, 0x3208485A,
    ]

    // The same cable's other capture, bit 3 clear. Nothing in the e-marker
    // says active, so only the port controller can promote it.
    private static let caldigitCleanVDOs: [UInt32] = [
        0x1C002B1D, 0x00000000, 0x19010097, 0x32084842,
    ]

    // Passive-layout VDO[3] with a valid latency field and bit 3 clear.
    private static let plainPassiveVDO3: UInt32 = 0b011 | (2 << 5) | (1 << 13)

    private static func identity(vdos: [UInt32]) -> USBPDSOP {
        USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 3,
            vendorID: 0x2B1D,
            productID: 0x1901,
            bcdDevice: 0x97,
            vdos: vdos,
            specRevision: 3
        )
    }

    private static func passiveIdentity() -> USBPDSOP {
        identity(vdos: [(3 << 27) | 0x2B1D, 0, 0x19010097, plainPassiveVDO3])
    }

    private static func activeIdentity() -> USBPDSOP {
        // Active layout needs a termination of 0b10 or 0b11 to decode cleanly.
        let activeVDO3: UInt32 = 0b011 | (2 << 5) | (1 << 13) | (0b10 << 11)
        return identity(vdos: [(4 << 27) | 0x2B1D, 0, 0x19010097, activeVDO3])
    }

    private static func port(activeCable: Bool?) -> AppleHPMInterface {
        AppleHPMInterface(
            id: 3,
            serviceName: "Port-USB-C@3",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@3",
            portTypeDescription: "USB-C",
            portNumber: 3,
            connectionActive: true, activeCable: activeCable, opticalCable: false,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "2"]
        )
    }

    @Test("Passive e-marker plus port controller ActiveCable promotes to active")
    func passivePlusPortControllerPromotes() {
        let resolution = CableClassification.resolve(
            identity: Self.passiveIdentity(),
            port: Self.port(activeCable: true)
        )
        #expect(resolution?.type == .active)
        #expect(resolution?.source == .portController)
    }

    @Test("Passive e-marker with port controller saying not active stays passive")
    func passivePlusPortControllerFalseStaysPassive() {
        let resolution = CableClassification.resolve(
            identity: Self.passiveIdentity(),
            port: Self.port(activeCable: false)
        )
        #expect(resolution?.type == .passive)
        #expect(resolution?.source == .emarker)
    }

    @Test("Passive e-marker with no port stays passive")
    func passiveWithNoPortStaysPassive() {
        let resolution = CableClassification.resolve(
            identity: Self.passiveIdentity(),
            port: nil
        )
        #expect(resolution?.type == .passive)
        #expect(resolution?.source == .emarker)
    }

    @Test("Active e-marker is never demoted by a port controller saying not active")
    func activeIsNeverDemoted() {
        let resolution = CableClassification.resolve(
            identity: Self.activeIdentity(),
            port: Self.port(activeCable: false)
        )
        #expect(resolution?.type == .active)
        #expect(resolution?.source == .emarker)
    }

    @Test("Active e-marker agreeing with the port keeps the e-marker source")
    func activeAgreeingKeepsEmarkerSource() {
        let resolution = CableClassification.resolve(
            identity: Self.activeIdentity(),
            port: Self.port(activeCable: true)
        )
        #expect(resolution?.type == .active)
        #expect(resolution?.source == .emarker)
    }

    @Test("Active layout contradiction alone promotes to active")
    func layoutContradictionPromotes() {
        let identity = Self.identity(vdos: Self.caldigitContradictionVDOs)
        #expect(identity.hasActiveLayoutContradiction)
        let resolution = CableClassification.resolve(identity: identity, port: Self.port(activeCable: false))
        #expect(resolution?.type == .active)
        #expect(resolution?.source == .layoutContradiction)
    }

    @Test("Port controller wins when both promotion conditions hold")
    func portControllerWinsOverContradiction() {
        let identity = Self.identity(vdos: Self.caldigitContradictionVDOs)
        let resolution = CableClassification.resolve(identity: identity, port: Self.port(activeCable: true))
        #expect(resolution?.type == .active)
        #expect(resolution?.source == .portController)
    }

    @Test("Corpus capture with bit 3 clear is the pure port controller case")
    func cleanCaptureIsPurePortControllerCase() {
        let identity = Self.identity(vdos: Self.caldigitCleanVDOs)
        #expect(!identity.hasActiveLayoutContradiction)
        let resolution = CableClassification.resolve(identity: identity, port: Self.port(activeCable: true))
        #expect(resolution?.type == .active)
        #expect(resolution?.source == .portController)
    }

    @Test("Identity with no VDO[3] resolves to nil")
    func noCableVDOResolvesToNil() {
        let identity = Self.identity(vdos: [(3 << 27) | 0x2B1D, 0, 0x19010097])
        #expect(identity.cableVDO == nil)
        #expect(CableClassification.resolve(identity: identity, port: Self.port(activeCable: true)) == nil)
    }

    @Test("A VCONN-powered device is never promoted by the port controller")
    func vconnPoweredDeviceIsNeverPromoted() {
        // Real corpus shape: Apple VCONN-Powered Device, VID 0x05AC,
        // VDO[3] 0x11000000, ID Header product type 6, sitting on a port
        // whose controller reports ActiveCable true (m3_macos26.5.2_f port 1
        // and m4pro_macos27.0_d port 3). "Not active" is not the same as
        // "self-reported passive": promotion needs the passive product type,
        // the same gate hasActiveLayoutContradiction already applies.
        let identity = USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(6 << 27) | 0x05AC, 0, 0, 0x11000000],
            specRevision: 3
        )
        #expect(identity.idHeader?.ufpProductType == .vpd)
        let resolution = CableClassification.resolve(identity: identity, port: Self.port(activeCable: true))
        #expect(resolution?.type == .passive)
        #expect(resolution?.source == .emarker)
    }
}
