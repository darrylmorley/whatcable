import XCTest
@testable import WhatCableCore

final class PDVDOTests: XCTestCase {

    // MARK: - ID Header

    func testDecodePassiveCableIDHeader() {
        // ufpProductType = 3 (passive cable) -> bits 29..27 = 011
        // vendorID = 0x1234
        // 3 << 27 = 0x1800_0000
        let vdo: UInt32 = 0x1800_0000 | 0x1234
        let header = PDVDO.decodeIDHeader(vdo)
        XCTAssertEqual(header.ufpProductType, .passiveCable)
        XCTAssertEqual(header.vendorID, 0x1234)
        XCTAssertFalse(header.modalOperation)
        XCTAssertFalse(header.usbCommHost)
    }

    func testDecodeActiveCableIDHeader() {
        // ufpProductType = 4 (active cable) -> bits 29..27 = 100
        // 4 << 27 = 0x2000_0000
        let vdo: UInt32 = 0x2000_0000 | 0x05AC // Apple vendor
        let header = PDVDO.decodeIDHeader(vdo)
        XCTAssertEqual(header.ufpProductType, .activeCable)
        XCTAssertEqual(header.vendorID, 0x05AC)
    }

    func testDecodeUSBCommBits() {
        // bits 31 + 30 set; vendor 0
        let vdo: UInt32 = 0xC000_0000
        let header = PDVDO.decodeIDHeader(vdo)
        XCTAssertTrue(header.usbCommHost)
        XCTAssertTrue(header.usbCommDevice)
    }

    // MARK: - Cable VDO
    //
    // Layout (low bits): speed [2:0], _, vbus-through [4], current [6:5], _, maxV [10:9]

    /// Valid cable-latency bits to OR into fixtures that don't care
    /// about latency. 0001 = ~10 ns (~1 m), the most common real-world
    /// value. Real cable reports we've collected use 0001 or 1000.
    private static let validLatency: UInt32 = 1 << 13

    /// Valid Cable Termination bits for active cables (bits 12..11).
    /// `10` = one end active. Active cable fixtures need this OR'd in,
    /// otherwise the new H7 termination check fires.
    private static let validActiveTermination: UInt32 = 0b10 << 11

    func testThunderboltCable_5A_40Gbps() {
        // speed=3 (USB4 Gen3), current=2 (5A) -> 2<<5=0x40, vbus-through bit 4=1
        let vdo: UInt32 = 0b011 | (1 << 4) | (2 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.speed, .usb4Gen3)
        XCTAssertEqual(cable.current, .fiveAmp)
        XCTAssertTrue(cable.vbusThroughCable)
        XCTAssertEqual(cable.maxVoltageEncoded, 0)
        XCTAssertEqual(cable.maxVolts, 20)
        XCTAssertEqual(cable.maxWatts, 100) // 20V * 5A
        XCTAssertEqual(cable.cableType, .passive)
        XCTAssertTrue(cable.decodeWarnings.isEmpty)
    }

    func testCheap_USB2_3A() {
        // speed=0 (USB 2.0), current=1 (3A) -> 1<<5=0x20
        let vdo: UInt32 = 0b000 | (1 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.speed, .usb20)
        XCTAssertEqual(cable.current, .threeAmp)
        XCTAssertEqual(cable.maxWatts, 60) // 20V * 3A
        XCTAssertTrue(cable.decodeWarnings.isEmpty)
    }

    func testEPRCable_50V_5A() {
        // speed=4 (USB4 Gen4 / 80 Gbps), current=2 (5A), maxV=3 (50V)
        let vdo: UInt32 = 0b100 | (2 << 5) | (3 << 9) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.speed, .usb4Gen4)
        XCTAssertEqual(cable.current, .fiveAmp)
        XCTAssertEqual(cable.maxVoltageEncoded, 3)
        XCTAssertEqual(cable.maxVolts, 50)
        XCTAssertEqual(cable.maxWatts, 250) // 50V * 5A — EPR cable
        XCTAssertTrue(cable.decodeWarnings.isEmpty)
    }

    func testActiveCableType() {
        let vdo: UInt32 = Self.validLatency | Self.validActiveTermination
        let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
        XCTAssertEqual(cable.cableType, .active)
        XCTAssertTrue(cable.decodeWarnings.isEmpty)
    }

    func testReservedSpeedEncodingFallsBackAndWarns() {
        for speedBits in 5...7 {
            let vdo = UInt32(speedBits) | UInt32(1 << 5) | Self.validLatency
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            XCTAssertEqual(cable.speed, .usb20)
            XCTAssertEqual(cable.current, .threeAmp)
            XCTAssertEqual(cable.decodeWarnings, [.reservedSpeedEncoding(speedBits)])
        }
    }

    func testReservedCurrentEncodingFallsBackAndWarns() {
        let vdo: UInt32 = 0b001 | UInt32(3 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.speed, .usb32Gen1)
        XCTAssertEqual(cable.current, .usbDefault)
        XCTAssertEqual(cable.decodeWarnings, [.reservedCurrentEncoding(3)])
    }

    func testReservedSpeedAndCurrentEncodingsBothWarn() {
        let vdo: UInt32 = 0b101 | UInt32(3 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.speed, .usb20)
        XCTAssertEqual(cable.current, .usbDefault)
        XCTAssertEqual(
            cable.decodeWarnings,
            [.reservedSpeedEncoding(5), .reservedCurrentEncoding(3)]
        )
    }

    // MARK: - Cable Latency

    func testValidPassiveCableLatencyDoesNotWarn() {
        for latencyBits in 1...8 {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(latencyBits) << 13)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            XCTAssertTrue(
                cable.decodeWarnings.isEmpty,
                "Latency \(latencyBits) should be valid for passive cables"
            )
            XCTAssertEqual(cable.cableLatencyEncoded, latencyBits)
        }
    }

    func testInvalidPassiveCableLatencyWarns() {
        // 0000 invalid
        let zero = UInt32(0b011) | UInt32(2 << 5)
        let zeroCable = PDVDO.decodeCableVDO(zero, isActive: false)
        XCTAssertEqual(zeroCable.decodeWarnings, [.reservedCableLatencyEncoding(0)])

        // 1001..1111 invalid for passive
        for latencyBits in 9...15 {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(latencyBits) << 13)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            XCTAssertEqual(
                cable.decodeWarnings,
                [.reservedCableLatencyEncoding(latencyBits)],
                "Latency \(latencyBits) should be invalid for passive"
            )
        }
    }

    func testActiveCableLatencyAccepts1001And1010() {
        // Active cables carry optical-length latencies 1001 (~1000 ns)
        // and 1010 (~2000 ns) that passive cables would treat as invalid.
        for latencyBits in [9, 10] {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(latencyBits) << 13) | Self.validActiveTermination
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            XCTAssertTrue(
                cable.decodeWarnings.isEmpty,
                "Latency \(latencyBits) should be valid for active cables"
            )
        }
    }

    func testActiveCableLatency_1011AndUpInvalid() {
        for latencyBits in 11...15 {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(latencyBits) << 13) | Self.validActiveTermination
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            XCTAssertEqual(
                cable.decodeWarnings,
                [.reservedCableLatencyEncoding(latencyBits)],
                "Latency \(latencyBits) should be invalid even for active cables"
            )
        }
    }

    func testLatencyNanosecondsLookup() {
        // Passive: 0001..1000 -> 10..80 ns
        for (bits, ns) in [(1, 10), (4, 40), (8, 80)] {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(bits) << 13)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            XCTAssertEqual(cable.latencyNanoseconds, ns)
        }
        // Active 1001 -> 1000 ns, 1010 -> 2000 ns
        for (bits, ns) in [(9, 1000), (10, 2000)] {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(bits) << 13)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            XCTAssertEqual(cable.latencyNanoseconds, ns)
        }
        // Invalid passive 1001 -> nil
        let invalidPassive = UInt32(0b011) | UInt32(2 << 5) | (UInt32(9) << 13)
        let cable = PDVDO.decodeCableVDO(invalidPassive, isActive: false)
        XCTAssertNil(cable.latencyNanoseconds)
    }

    // MARK: - VDO Version (H6)

    func testPassiveVDOVersionZeroIsValid() {
        // 000 = v1.0, the only valid passive value.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertEqual(cable.vdoVersionEncoded, 0)
        XCTAssertTrue(cable.decodeWarnings.isEmpty)
    }

    func testPassiveVDOVersionNonZeroFlags() {
        // Anything other than 000 is invalid for passive cables.
        for version in 1...7 {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(version) << 21)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            XCTAssertEqual(
                cable.decodeWarnings,
                [.invalidVDOVersion(version)],
                "VDO version \(version) should be invalid for passive"
            )
        }
    }

    func testActiveVDOVersionAcceptsDeprecatedAndV13() {
        // 000 (deprecated v1.0), 010 (deprecated v1.2), 011 (v1.3) all valid.
        for version in [0, 0b010, 0b011] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
                | Self.validActiveTermination | (UInt32(version) << 21)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            XCTAssertTrue(
                cable.decodeWarnings.isEmpty,
                "VDO version \(version) should be valid for active"
            )
        }
    }

    func testActiveVDOVersionInvalidValuesFlag() {
        // 001 and 100..111 are invalid for active cables.
        for version in [0b001, 0b100, 0b101, 0b110, 0b111] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
                | Self.validActiveTermination | (UInt32(version) << 21)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            XCTAssertEqual(
                cable.decodeWarnings,
                [.invalidVDOVersion(version)],
                "VDO version \(version) should be invalid for active"
            )
        }
    }

    // MARK: - Cable Termination (H7)

    func testPassiveCableTerminationValid() {
        // 00 (VCONN not required) and 01 (VCONN required) both valid.
        for term in [0, 0b01] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(term) << 11)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            XCTAssertEqual(cable.cableTerminationEncoded, term)
            XCTAssertTrue(
                cable.decodeWarnings.isEmpty,
                "Termination \(term) should be valid for passive"
            )
        }
    }

    func testPassiveCableTerminationInvalid() {
        // 10 and 11 are invalid for passive cables.
        for term in [0b10, 0b11] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(term) << 11)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            XCTAssertEqual(
                cable.decodeWarnings,
                [.invalidCableTermination(term)],
                "Termination \(term) should be invalid for passive"
            )
        }
    }

    func testActiveCableTerminationValid() {
        // 10 (one end active) and 11 (both ends active) valid.
        for term in [0b10, 0b11] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(term) << 11)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            XCTAssertTrue(
                cable.decodeWarnings.isEmpty,
                "Termination \(term) should be valid for active"
            )
        }
    }

    func testActiveCableTerminationInvalid() {
        // 00 and 01 invalid for active cables.
        for term in [0, 0b01] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(term) << 11)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            XCTAssertEqual(
                cable.decodeWarnings,
                [.invalidCableTermination(term)],
                "Termination \(term) should be invalid for active"
            )
        }
    }

    // MARK: - EPR / VBUS contradiction (H9a)

    func testPassiveEPRWith20VFlags() {
        // EPR Capable bit 17 set, max VBUS encoding 00 (20V).
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | UInt32(1 << 17)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertTrue(cable.eprCapable)
        XCTAssertEqual(cable.maxVoltageEncoded, 0)
        XCTAssertEqual(cable.decodeWarnings, [.eprClaimedWithLowMaxVoltage])
    }

    func testPassiveEPRWith50VDoesNotFlag() {
        // EPR + 50V max is consistent.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
            | UInt32(1 << 17) | UInt32(0b11 << 9)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertTrue(cable.eprCapable)
        XCTAssertEqual(cable.maxVoltageEncoded, 0b11)
        XCTAssertTrue(cable.decodeWarnings.isEmpty)
    }

    func testPassiveNoEPRWith20VDoesNotFlag() {
        // Plain 20V cable that doesn't claim EPR is fine.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        XCTAssertFalse(cable.eprCapable)
        XCTAssertTrue(cable.decodeWarnings.isEmpty)
    }

    func testActiveEPRWith20VDoesNotFlag() {
        // H9a is passive-only; active cable EPR semantics need VDO2 decoder.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
            | Self.validActiveTermination | UInt32(1 << 17)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
        XCTAssertTrue(cable.eprCapable)
        XCTAssertTrue(cable.decodeWarnings.isEmpty)
    }

    // MARK: - Active Cable VDO 2

    func testDecodeActiveCableVDO2_AllFields() {
        // Build a VDO2 exercising every field. Note that USB4 / USB 3.2 /
        // USB 2.0 "Supported" bits are inverted in the spec: 0 = supported,
        // 1 = not supported. Test fixture sets them to 0 to mean "all
        // protocols supported" and asserts our decoder reports `true`.
        //   31..24: maxOperatingTemp = 100°C
        //   23..16: shutdownTemp     = 120°C
        //   14..12: u3CLdPower       = 011 (0.5-1 mW)
        //   11    : u3 transition through U3S = 1
        //   10    : physicalConnection = 1 (optical)
        //   9     : activeElement   = 1 (re-timer)
        //   8     : USB4 bit = 0     (supported)
        //   7..6  : hubHopsConsumed = 10 = 2
        //   5     : USB 2.0 bit = 0  (supported)
        //   4     : USB 3.2 bit = 0  (supported)
        //   3     : twoLanesSupported = 1
        //   2     : opticallyIsolated = 1
        //   1     : usb4AsymmetricMode = 1
        //   0     : usbGen2+ = 1
        var vdo: UInt32 = 0
        vdo |= UInt32(100) << 24
        vdo |= UInt32(120) << 16
        vdo |= UInt32(0b011) << 12
        vdo |= UInt32(1) << 11
        vdo |= UInt32(1) << 10
        vdo |= UInt32(1) << 9
        // bit 8 left as 0 (USB4 supported)
        vdo |= UInt32(0b10) << 6
        // bits 5 and 4 left as 0 (USB 2.0 + USB 3.2 supported)
        vdo |= UInt32(1) << 3
        vdo |= UInt32(1) << 2
        vdo |= UInt32(1) << 1
        vdo |= UInt32(1)
        let v2 = PDVDO.decodeActiveCableVDO2(vdo)
        XCTAssertEqual(v2.maxOperatingTempC, 100)
        XCTAssertEqual(v2.shutdownTempC, 120)
        XCTAssertEqual(v2.u3CLdPower, .halfTo1mW)
        XCTAssertTrue(v2.u3ToU0TransitionThroughU3S)
        XCTAssertEqual(v2.physicalConnection, .optical)
        XCTAssertEqual(v2.activeElement, .retimer)
        XCTAssertTrue(v2.usb4Supported)
        XCTAssertEqual(v2.usb2HubHopsConsumed, 2)
        XCTAssertTrue(v2.usb2Supported)
        XCTAssertTrue(v2.usb32Supported)
        XCTAssertTrue(v2.twoLanesSupported)
        XCTAssertTrue(v2.opticallyIsolated)
        XCTAssertTrue(v2.usb4AsymmetricMode)
        XCTAssertTrue(v2.usbGen2OrHigher)
    }

    func testDecodeActiveCableVDO2_AllZero() {
        // All-zeros VDO. Counter-intuitive but spec-correct: the protocol
        // "supported" bits read 0 = supported, so an all-zero VDO claims
        // USB4, USB 3.2, and USB 2.0 are all supported.
        let v2 = PDVDO.decodeActiveCableVDO2(0)
        XCTAssertEqual(v2.maxOperatingTempC, 0)
        XCTAssertEqual(v2.shutdownTempC, 0)
        XCTAssertEqual(v2.u3CLdPower, .greaterThan10mW)
        XCTAssertFalse(v2.u3ToU0TransitionThroughU3S)
        XCTAssertEqual(v2.physicalConnection, .copper)
        XCTAssertEqual(v2.activeElement, .redriver)
        XCTAssertTrue(v2.usb4Supported)
        XCTAssertTrue(v2.usb32Supported)
        XCTAssertTrue(v2.usb2Supported)
        XCTAssertEqual(v2.usb2HubHopsConsumed, 0)
        XCTAssertFalse(v2.opticallyIsolated)
    }

    func testDecodeActiveCableVDO2_ProtocolBitsAreInverted() {
        // Setting bits 8, 5, 4 all to 1 means "not supported."
        var vdo: UInt32 = 0
        vdo |= UInt32(1) << 8
        vdo |= UInt32(1) << 5
        vdo |= UInt32(1) << 4
        let v2 = PDVDO.decodeActiveCableVDO2(vdo)
        XCTAssertFalse(v2.usb4Supported, "bit 8 = 1 means USB4 NOT supported")
        XCTAssertFalse(v2.usb2Supported, "bit 5 = 1 means USB 2.0 NOT supported")
        XCTAssertFalse(v2.usb32Supported, "bit 4 = 1 means USB 3.2 NOT supported")
    }

    func testDecodeActiveCableVDO2_ReservedPower() {
        // 111 in bits 14..12 maps to .reserved.
        let vdo: UInt32 = UInt32(0b111) << 12
        let v2 = PDVDO.decodeActiveCableVDO2(vdo)
        XCTAssertEqual(v2.u3CLdPower, .reserved)
    }

    func testActiveCableVDO2AccessorRequiresActiveCable() {
        // Passive cable (ufpProductType=3) shouldn't expose VDO2 even if
        // vdos[4] is present.
        let passive = PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 1,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC),    // passive product type
                0,
                0,
                UInt32(0b011) | UInt32(2 << 5) | (1 << 13), // valid passive cable VDO
                0xDEADBEEF                    // would-be VDO2
            ],
            specRevision: 3
        )
        XCTAssertNil(passive.activeCableVDO2)
    }

    func testActiveCableVDO2AccessorWorksOnActiveCable() {
        // Active cable (ufpProductType=4) with five VDOs.
        let vdo3: UInt32 = UInt32(0b011) | UInt32(2 << 5) | (1 << 13) | (UInt32(0b10) << 11) // valid active termination
        let vdo4: UInt32 = (1 << 10) | (1 << 9) | (1 << 2) // optical, re-timer, isolated
        let active = PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 1,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [
                (4 << 27) | UInt32(0x05AC),
                0,
                0,
                vdo3,
                vdo4
            ],
            specRevision: 3
        )
        let v2 = active.activeCableVDO2
        XCTAssertNotNil(v2)
        XCTAssertEqual(v2?.physicalConnection, .optical)
        XCTAssertEqual(v2?.activeElement, .retimer)
        XCTAssertEqual(v2?.opticallyIsolated, true)
    }

    func testActiveCableVDO2AccessorReturnsNilWhenVDO4Missing() {
        // Active cable but only 4 VDOs (no VDO2 present).
        let active = PDIdentity(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 1,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [
                (4 << 27) | UInt32(0x05AC),
                0,
                0,
                UInt32(0b011) | UInt32(2 << 5) | (1 << 13) | (UInt32(0b10) << 11)
            ],
            specRevision: 3
        )
        XCTAssertNil(active.activeCableVDO2)
    }

    // MARK: - Cert Stat VDO

    func testCertStatPresentWhenNonZero() {
        let stat = PDVDO.decodeCertStat(0x12345)
        XCTAssertEqual(stat.xid, 0x12345)
        XCTAssertTrue(stat.isPresent)
    }

    func testCertStatMissingWhenZero() {
        let stat = PDVDO.decodeCertStat(0)
        XCTAssertEqual(stat.xid, 0)
        XCTAssertFalse(stat.isPresent)
    }

    // MARK: - VDO from Data

    func testVDOFromData_LittleEndian() {
        // 0xDEADBEEF stored little-endian = EF BE AD DE
        let data = Data([0xEF, 0xBE, 0xAD, 0xDE])
        XCTAssertEqual(PDVDO.vdoFromData(data), 0xDEADBEEF)
    }

    func testVDOFromData_TooShort() {
        XCTAssertNil(PDVDO.vdoFromData(Data([0x01, 0x02])))
    }
}
