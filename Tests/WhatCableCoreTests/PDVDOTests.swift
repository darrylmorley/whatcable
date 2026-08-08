import Foundation
import Testing
@testable import WhatCableCore

@Suite("PD VDO Decoding")
struct PDVDOTests {

    // MARK: - ID Header

    @Test("Decode passive cable ID header")
    func decodePassiveCableIDHeader() {
        // ufpProductType = 3 (passive cable) -> bits 29..27 = 011
        // vendorID = 0x1234
        // 3 << 27 = 0x1800_0000
        let vdo: UInt32 = 0x1800_0000 | 0x1234
        let header = PDVDO.decodeIDHeader(vdo)
        #expect(header.ufpProductType == .passiveCable)
        #expect(header.vendorID == 0x1234)
        #expect(!header.modalOperation)
        #expect(!header.usbCommHost)
    }

    @Test("Decode active cable ID header")
    func decodeActiveCableIDHeader() {
        // ufpProductType = 4 (active cable) -> bits 29..27 = 100
        // 4 << 27 = 0x2000_0000
        let vdo: UInt32 = 0x2000_0000 | 0x05AC // Apple vendor
        let header = PDVDO.decodeIDHeader(vdo)
        #expect(header.ufpProductType == .activeCable)
        #expect(header.vendorID == 0x05AC)
    }

    @Test("Decode USB comm bits")
    func decodeUSBCommBits() {
        // bits 31 + 30 set; vendor 0
        let vdo: UInt32 = 0xC000_0000
        let header = PDVDO.decodeIDHeader(vdo)
        #expect(header.usbCommHost)
        #expect(header.usbCommDevice)
    }

    // MARK: DFP product type (DAR-24 regression guard)
    // These tests verify that the DFP field (bits 25..23) is decoded with
    // DFP semantics, not UFP semantics. Per Table 6.34 of the USB PD R3.2
    // spec, the same raw value means different things in the two fields:
    // UFP 010 = Peripheral, DFP 010 = Host. UFP 011 = Passive Cable,
    // DFP 011 = Power Brick.

    @Test("DFP Host (010) labels as Host, not USB Peripheral")
    func dfpHostLabelsAsHost() {
        // DFP product type field = 010 (Host). Bits 25..23.
        // 2 << 23 = 0x0100_0000
        let vdo: UInt32 = 0x0100_0000
        let header = PDVDO.decodeIDHeader(vdo)
        // UFP field should be unset (000 = Not UFP)
        #expect(header.ufpProductType == .undefined)
        // DFP field should decode to .host (010), not .pdusbPeripheral
        #expect(header.dfpProductType == .host)
        #expect(header.dfpProductType.label == "Host")
    }

    @Test("DFP Power Brick (011) is not a cable")
    func dfpPowerBrickIsNotCable() {
        // DFP product type field = 011 (Power Brick). Bits 25..23.
        // 3 << 23 = 0x0180_0000
        let vdo: UInt32 = 0x0180_0000
        let header = PDVDO.decodeIDHeader(vdo)
        // UFP field is unset, so ufpProductType = .undefined
        #expect(header.ufpProductType == .undefined)
        // DFP field = .powerBrick, not .passiveCable
        #expect(header.dfpProductType == .powerBrick)
        // A power brick is NOT a cable. isCable must be false.
        #expect(!header.isCable)
        #expect(header.dfpProductType.label == "Power Brick")
    }

    @Test("Power-brick ID header is not a cable for trust softening")
    func powerBrickIDHeaderNotACableForTrustSoftening() {
        // A registered charger (Anker 0x291A, DFP raw 3 = Power Brick per
        // Table 6.34) answering at SOP as the port partner. The strict
        // `isCable` field is false; the lenient `identifiesAsCable` heuristic
        // still returns true because raw DFP 3 happens to match the UFP
        // passive-cable value. That overlap is exactly why
        // `CableTrustReport.partnerIsRegisteredCable` adds an explicit
        // `dfpProductType != .powerBrick` guard on top of `identifiesAsCable`
        // rather than relying on it.
        //
        // Characterization guard (not red→green): the chosen fix catches the
        // brick at the trust layer, so `identifiesAsCable` is intentionally
        // left true here and the red→green proof lives in CableTrustReportTests.
        let sop = USBPDSOP(
            id: 1, endpoint: .sop, parentPortType: 0, parentPortNumber: 0,
            vendorID: 0x291A, productID: 0, bcdDevice: 0,
            vdos: [(3 << 23) | UInt32(0x291A)],   // DFP raw 3 = Power Brick, Anker VID
            specRevision: 3
        )
        #expect(sop.idHeader?.dfpProductType == .powerBrick)
        #expect(sop.idHeader?.isCable == false)
        // Raw-bit heuristic still matches; the trust report refuses to soften
        // on top of this, it does not narrow the heuristic itself.
        #expect(sop.idHeader?.dfpRawValueLooksLikeCable == true)
        #expect(sop.identifiesAsCable == true)
    }

    @Test("UFP passive cable (011) is still a cable (SOP' regression guard)")
    func ufpPassiveCableStillIsCable() {
        // UFP product type = 011 (Passive Cable). Bits 29..27.
        // 3 << 27 = 0x1800_0000
        let vdo: UInt32 = 0x1800_0000
        let header = PDVDO.decodeIDHeader(vdo)
        #expect(header.ufpProductType == .passiveCable)
        // isCable must remain true for real cables
        #expect(header.isCable)
    }

    @Test("UFP active cable (100) is still a cable (SOP' regression guard)")
    func ufpActiveCableStillIsCable() {
        // UFP product type = 100 (Active Cable). Bits 29..27.
        // 4 << 27 = 0x2000_0000
        let vdo: UInt32 = 0x2000_0000
        let header = PDVDO.decodeIDHeader(vdo)
        #expect(header.ufpProductType == .activeCable)
        #expect(header.isCable)
    }

    @Test("DFP Hub (001) labels as USB Hub")
    func dfpHubLabelsAsHub() {
        // DFP product type = 001 (Hub). Bits 25..23.
        // 1 << 23 = 0x0080_0000
        let vdo: UInt32 = 0x0080_0000
        let header = PDVDO.decodeIDHeader(vdo)
        #expect(header.dfpProductType == .pdusbHub)
        #expect(header.dfpProductType.label == "USB Hub")
        // A hub advertising only the DFP field is not a cable.
        #expect(!header.isCable)
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

    @Test("Cable speed report labels are stable and non-localized")
    func cableSpeedReportLabels() {
        let expected: [(PDVDO.CableSpeed, String)] = [
            (.usb20, "USB 2.0 (480 Mbps)"),
            (.usb32Gen1, "USB 3.2 Gen 1 (5 Gbps)"),
            (.usb32Gen2, "USB 3.2 Gen 2 (10 Gbps)"),
            (.usb4Gen3, "USB4 Gen 3 (40 Gbps, Thunderbolt 4 class)"),
            (.usb4Gen4, "USB4 Gen 4 (80 Gbps, Thunderbolt 5 class)"),
        ]

        for (speed, reportLabel) in expected {
            #expect(speed.reportLabel == reportLabel)
        }
    }

    @Test("Thunderbolt cable 5A 40Gbps")
    func thunderboltCable_5A_40Gbps() {
        // speed=3 (USB4 Gen3), current=2 (5A) -> 2<<5=0x40
        // Bit 4 is set in the raw VDO, but for a passive cable Table 6.42
        // defines bits 4..3 as Reserved. The decoder must ignore bit 4 and
        // report vbusThroughCable = false.
        let vdo: UInt32 = 0b011 | (1 << 4) | (2 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.speed == .usb4Gen3)
        #expect(cable.current == .fiveAmp)
        #expect(!cable.vbusThroughCable) // reserved bit for passive; must always be false
        #expect(cable.maxVoltageEncoded == 0)
        #expect(cable.maxVolts == 20)
        #expect(cable.maxWatts == 100) // 20V * 5A
        #expect(cable.cableType == .passive)
        #expect(cable.decodeWarnings.isEmpty)
    }

    // MARK: - VBUS Through Cable (DAR-26)
    // Bit 4 is "VBUS Through Cable" only in Active Cable VDO1 (Table 6.43).
    // For passive cables (Table 6.42) bits 4..3 are Reserved and have no meaning.

    @Test("Passive cable with bit 4 set reports vbusThroughCable = false (DAR-26)")
    func passiveCable_Bit4Set_VBUSThroughIsFalse() {
        // VDO with bit 4 = 1, otherwise a plain passive cable.
        // Per Table 6.42 the bit is Reserved for passive cables, so the
        // decoder must return false regardless of what the raw bit contains.
        let vdo: UInt32 = (1 << 4) | (1 << 5) | Self.validLatency  // 3A, bit4=1
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(!cable.vbusThroughCable, "bit 4 is Reserved for passive cables and must not be interpreted as VBUS Through")
    }

    @Test("Active cable with bit 4 set reports vbusThroughCable = true (DAR-26)")
    func activeCable_Bit4Set_VBUSThroughIsTrue() {
        // VDO with bit 4 = 1 for an active cable.
        // Per Table 6.43 bit 4 is "VBUS Through Cable" for active cables.
        let vdo: UInt32 = (1 << 4) | (1 << 5) | Self.validLatency | Self.validActiveTermination
        let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
        #expect(cable.vbusThroughCable, "bit 4 is VBUS Through Cable for active cables and must be true when set")
    }

    @Test("Cheap USB2 3A cable")
    func cheap_USB2_3A() {
        // speed=0 (USB 2.0), current=1 (3A) -> 1<<5=0x20
        let vdo: UInt32 = 0b000 | (1 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.speed == .usb20)
        #expect(cable.current == .threeAmp)
        #expect(cable.maxWatts == 60) // 20V * 3A
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("EPR cable 50V 5A reports the 240W deliverable, not a 250W multiply")
    func eprCable_50V_5A() {
        // speed=4 (USB4 Gen4 / 80 Gbps), current=2 (5A), maxV=3 (50V)
        let vdo: UInt32 = 0b100 | (2 << 5) | (3 << 9) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.speed == .usb4Gen4)
        #expect(cable.current == .fiveAmp)
        #expect(cable.maxVoltageEncoded == 3)
        // The rating field still reads 50V (that's a true property of the cable).
        #expect(cable.maxVolts == 50)
        // But power is clamped to USB-PD's 48V ceiling: 48 * 5 = 240, not 250.
        // 50V is insulation headroom the spec never delivers against.
        #expect(cable.maxWatts == 240)
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("Deprecated encodings 1 and 2 both resolve to 20V, not 30V or 40V")
    func deprecatedMaxVBUSEncodings_ResolveAs20V() {
        // Per spec Table 6.42, encodings 01 and 10 are DEPRECATED and mean 20V.
        // The old code wrongly mapped them to 30V and 40V; this test pins the
        // corrected behaviour.
        //
        // Encoding 1 (was wrongly 30V, now 20V). 5A cable: 20 * 5 = 100W.
        let cable1 = PDVDO.decodeCableVDO(0b100 | (2 << 5) | (1 << 9) | Self.validLatency, isActive: false)
        #expect(cable1.maxVoltageEncoded == 1)
        #expect(cable1.maxVolts == 20)
        #expect(cable1.maxWatts == 100)
        // Encoding 2 (was wrongly 40V, now 20V). 5A cable: 20 * 5 = 100W.
        let cable2 = PDVDO.decodeCableVDO(0b100 | (2 << 5) | (2 << 9) | Self.validLatency, isActive: false)
        #expect(cable2.maxVoltageEncoded == 2)
        #expect(cable2.maxVolts == 20)
        #expect(cable2.maxWatts == 100)
        // Encoding 3 is the only non-20V value: 50V. 5A: clamped to 48V = 240W.
        let cable3 = PDVDO.decodeCableVDO(0b100 | (2 << 5) | (3 << 9) | Self.validLatency, isActive: false)
        #expect(cable3.maxVoltageEncoded == 3)
        #expect(cable3.maxVolts == 50)
        #expect(cable3.maxWatts == 240)
    }

    @Test("Active cable type detection")
    func activeCableType() {
        let vdo: UInt32 = Self.validLatency | Self.validActiveTermination
        let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
        #expect(cable.cableType == .active)
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("Reserved speed encoding falls back and warns")
    func reservedSpeedEncodingFallsBackAndWarns() {
        for speedBits in 5...7 {
            let vdo = UInt32(speedBits) | UInt32(1 << 5) | Self.validLatency
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            #expect(cable.speed == .usb20)
            #expect(cable.current == .threeAmp)
            #expect(cable.decodeWarnings == [.reservedSpeedEncoding(speedBits)])
            #expect(cable.reportSpeedLabel == "Reserved cable speed encoding (\(speedBits))")
        }
    }

    @Test("Reserved current encoding falls back and warns")
    func reservedCurrentEncodingFallsBackAndWarns() {
        let vdo: UInt32 = 0b001 | UInt32(3 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.speed == .usb32Gen1)
        #expect(cable.current == .usbDefault)
        #expect(cable.decodeWarnings == [.reservedCurrentEncoding(3)])
    }

    @Test("Reserved speed and current encodings both warn")
    func reservedSpeedAndCurrentEncodingsBothWarn() {
        let vdo: UInt32 = 0b101 | UInt32(3 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.speed == .usb20)
        #expect(cable.current == .usbDefault)
        #expect(
            cable.decodeWarnings ==
            [.reservedSpeedEncoding(5), .reservedCurrentEncoding(3)]
        )
    }

    // MARK: - Cable Latency

    @Test("Valid passive cable latency does not warn")
    func validPassiveCableLatencyDoesNotWarn() {
        for latencyBits in 1...8 {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(latencyBits) << 13)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            #expect(
                cable.decodeWarnings.isEmpty,
                "Latency \(latencyBits) should be valid for passive cables"
            )
            #expect(cable.cableLatencyEncoded == latencyBits)
        }
    }

    @Test("Invalid passive cable latency warns")
    func invalidPassiveCableLatencyWarns() {
        // 0000 invalid
        let zero = UInt32(0b011) | UInt32(2 << 5)
        let zeroCable = PDVDO.decodeCableVDO(zero, isActive: false)
        #expect(zeroCable.decodeWarnings == [.reservedCableLatencyEncoding(0)])

        // 1001..1111 invalid for passive
        for latencyBits in 9...15 {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(latencyBits) << 13)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            #expect(
                cable.decodeWarnings ==
                [.reservedCableLatencyEncoding(latencyBits)],
                "Latency \(latencyBits) should be invalid for passive"
            )
        }
    }

    @Test("Active cable latency accepts 1001 and 1010")
    func activeCableLatencyAccepts1001And1010() {
        // Active cables carry optical-length latencies 1001 (~1000 ns)
        // and 1010 (~2000 ns) that passive cables would treat as invalid.
        for latencyBits in [9, 10] {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(latencyBits) << 13) | Self.validActiveTermination
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            #expect(
                cable.decodeWarnings.isEmpty,
                "Latency \(latencyBits) should be valid for active cables"
            )
        }
    }

    @Test("Active cable latency 1011 and up is invalid")
    func activeCableLatency_1011AndUpInvalid() {
        for latencyBits in 11...15 {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(latencyBits) << 13) | Self.validActiveTermination
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            #expect(
                cable.decodeWarnings ==
                [.reservedCableLatencyEncoding(latencyBits)],
                "Latency \(latencyBits) should be invalid even for active cables"
            )
        }
    }

    @Test("Latency nanoseconds lookup")
    func latencyNanosecondsLookup() {
        // Passive: 0001..1000 -> 10..80 ns
        for (bits, ns) in [(1, 10), (4, 40), (8, 80)] {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(bits) << 13)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            #expect(cable.latencyNanoseconds == ns)
        }
        // Active 1001 -> 1000 ns, 1010 -> 2000 ns
        for (bits, ns) in [(9, 1000), (10, 2000)] {
            let vdo = UInt32(0b011) | UInt32(2 << 5) | (UInt32(bits) << 13)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            #expect(cable.latencyNanoseconds == ns)
        }
        // Invalid passive 1001 -> nil
        let invalidPassive = UInt32(0b011) | UInt32(2 << 5) | (UInt32(9) << 13)
        let cable = PDVDO.decodeCableVDO(invalidPassive, isActive: false)
        #expect(cable.latencyNanoseconds == nil)
    }

    // MARK: - VDO Version (H6)

    @Test("Passive VDO version zero is valid")
    func passiveVDOVersionZeroIsValid() {
        // 000 = v1.0, the only valid passive value.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.vdoVersionEncoded == 0)
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("Passive VDO version non-zero flags")
    func passiveVDOVersionNonZeroFlags() {
        // Anything other than 000 is invalid for passive cables.
        for version in 1...7 {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(version) << 21)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            #expect(
                cable.decodeWarnings ==
                [.invalidVDOVersion(version)],
                "VDO version \(version) should be invalid for passive"
            )
        }
    }

    @Test("Active VDO version accepts deprecated and v1.3")
    func activeVDOVersionAcceptsDeprecatedAndV13() {
        // 000 (deprecated v1.0), 010 (deprecated v1.2), 011 (v1.3) all valid.
        for version in [0, 0b010, 0b011] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
                | Self.validActiveTermination | (UInt32(version) << 21)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            #expect(
                cable.decodeWarnings.isEmpty,
                "VDO version \(version) should be valid for active"
            )
        }
    }

    @Test("Active VDO version invalid values flag")
    func activeVDOVersionInvalidValuesFlag() {
        // 001 and 100..111 are invalid for active cables.
        for version in [0b001, 0b100, 0b101, 0b110, 0b111] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
                | Self.validActiveTermination | (UInt32(version) << 21)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            #expect(
                cable.decodeWarnings ==
                [.invalidVDOVersion(version)],
                "VDO version \(version) should be invalid for active"
            )
        }
    }

    // MARK: - Cable Termination (H7)

    @Test("Passive cable termination valid")
    func passiveCableTerminationValid() {
        // 00 (VCONN not required) and 01 (VCONN required) both valid.
        for term in [0, 0b01] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(term) << 11)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            #expect(cable.cableTerminationEncoded == term)
            #expect(
                cable.decodeWarnings.isEmpty,
                "Termination \(term) should be valid for passive"
            )
        }
    }

    @Test("Passive cable termination invalid")
    func passiveCableTerminationInvalid() {
        // 10 and 11 are invalid for passive cables.
        for term in [0b10, 0b11] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(term) << 11)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            #expect(
                cable.decodeWarnings ==
                [.invalidCableTermination(term)],
                "Termination \(term) should be invalid for passive"
            )
        }
    }

    @Test("Active cable termination valid")
    func activeCableTerminationValid() {
        // 10 (one end active) and 11 (both ends active) valid.
        for term in [0b10, 0b11] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(term) << 11)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            #expect(
                cable.decodeWarnings.isEmpty,
                "Termination \(term) should be valid for active"
            )
        }
    }

    @Test("Active cable termination invalid")
    func activeCableTerminationInvalid() {
        // 00 and 01 invalid for active cables.
        for term in [0, 0b01] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (UInt32(term) << 11)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
            #expect(
                cable.decodeWarnings ==
                [.invalidCableTermination(term)],
                "Termination \(term) should be invalid for active"
            )
        }
    }

    // MARK: - EPR / VBUS contradiction (H9a)

    @Test("Passive EPR with encoding 0 (20V) flags")
    func passiveEPRWith20VFlags() {
        // EPR Capable bit 17 set, max VBUS encoding 00 (20V).
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | UInt32(1 << 17)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.eprCapable)
        #expect(cable.maxVoltageEncoded == 0)
        #expect(cable.decodeWarnings == [.eprClaimedWithLowMaxVoltage])
    }

    @Test("Passive EPR with deprecated encodings 1 and 2 also flags (H9a widening)")
    func passiveEPRWithDeprecatedEncodings_Flag() {
        // Encodings 01 and 10 are deprecated (treated as 20V per spec).
        // A passive EPR-capable cable reporting either is still contradictory:
        // EPR requires 50V (encoding 11). H9a must fire for all non-50V cases.
        for enc in [1, 2] {
            let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
                | UInt32(1 << 17) | UInt32(enc << 9)
            let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
            #expect(cable.eprCapable, "encoding \(enc) should still be EPR capable")
            #expect(cable.maxVoltageEncoded == enc)
            #expect(
                cable.decodeWarnings == [.eprClaimedWithLowMaxVoltage],
                "encoding \(enc) should trigger H9a"
            )
        }
    }

    @Test("Passive EPR with 50V (encoding 3) does not flag")
    func passiveEPRWith50VDoesNotFlag() {
        // EPR + encoding 11 (50V) is the only consistent combination.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
            | UInt32(1 << 17) | UInt32(0b11 << 9)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.eprCapable)
        #expect(cable.maxVoltageEncoded == 0b11)
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("Passive no EPR with 20V does not flag")
    func passiveNoEPRWith20VDoesNotFlag() {
        // Plain 20V cable that doesn't claim EPR is fine.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.eprCapable == false)
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("Active EPR with 20V does not flag")
    func activeEPRWith20VDoesNotFlag() {
        // H9a is passive-only; active cable EPR semantics need VDO2 decoder.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
            | Self.validActiveTermination | UInt32(1 << 17)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
        #expect(cable.eprCapable)
        #expect(cable.decodeWarnings.isEmpty)
    }

    // MARK: - Active Cable VDO 2

    @Test("Decode active cable VDO2 all fields")
    func decodeActiveCableVDO2_AllFields() {
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
        #expect(v2.maxOperatingTempC == 100)
        #expect(v2.shutdownTempC == 120)
        #expect(v2.u3CLdPower == .halfTo1mW)
        #expect(v2.u3ToU0TransitionThroughU3S)
        #expect(v2.physicalConnection == .optical)
        #expect(v2.activeElement == .retimer)
        #expect(v2.usb4Supported)
        #expect(v2.usb2HubHopsConsumed == 2)
        #expect(v2.usb2Supported)
        #expect(v2.usb32Supported)
        #expect(v2.twoLanesSupported)
        #expect(v2.opticallyIsolated)
        #expect(v2.usb4AsymmetricMode)
        #expect(v2.usbGen2OrHigher)
    }

    @Test("Decode active cable VDO2 all zero")
    func decodeActiveCableVDO2_AllZero() {
        // All-zeros VDO. Counter-intuitive but spec-correct: the protocol
        // "supported" bits read 0 = supported, so an all-zero VDO claims
        // USB4, USB 3.2, and USB 2.0 are all supported.
        let v2 = PDVDO.decodeActiveCableVDO2(0)
        #expect(v2.maxOperatingTempC == 0)
        #expect(v2.shutdownTempC == 0)
        #expect(v2.u3CLdPower == .greaterThan10mW)
        #expect(!v2.u3ToU0TransitionThroughU3S)
        #expect(v2.physicalConnection == .copper)
        #expect(v2.activeElement == .redriver)
        #expect(v2.usb4Supported)
        #expect(v2.usb32Supported)
        #expect(v2.usb2Supported)
        #expect(v2.usb2HubHopsConsumed == 0)
        #expect(!v2.opticallyIsolated)
    }

    @Test("Decode active cable VDO2 protocol bits are inverted")
    func decodeActiveCableVDO2_ProtocolBitsAreInverted() {
        // Setting bits 8, 5, 4 all to 1 means "not supported."
        var vdo: UInt32 = 0
        vdo |= UInt32(1) << 8
        vdo |= UInt32(1) << 5
        vdo |= UInt32(1) << 4
        let v2 = PDVDO.decodeActiveCableVDO2(vdo)
        #expect(v2.usb4Supported == false, "bit 8 = 1 means USB4 NOT supported")
        #expect(v2.usb2Supported == false, "bit 5 = 1 means USB 2.0 NOT supported")
        #expect(v2.usb32Supported == false, "bit 4 = 1 means USB 3.2 NOT supported")
    }

    @Test("Decode active cable VDO2 reserved power")
    func decodeActiveCableVDO2_ReservedPower() {
        // 111 in bits 14..12 maps to .reserved.
        let vdo: UInt32 = UInt32(0b111) << 12
        let v2 = PDVDO.decodeActiveCableVDO2(vdo)
        #expect(v2.u3CLdPower == .reserved)
    }

    @Test("Active cable VDO2 accessor requires active cable")
    func activeCableVDO2AccessorRequiresActiveCable() {
        // Passive cable (ufpProductType=3) shouldn't expose VDO2 even if
        // vdos[4] is present.
        let passive = USBPDSOP(
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
        #expect(passive.activeCableVDO2 == nil)
    }

    @Test("Active cable VDO2 accessor works on active cable")
    func activeCableVDO2AccessorWorksOnActiveCable() {
        // Active cable (ufpProductType=4) with five VDOs.
        let vdo3: UInt32 = UInt32(0b011) | UInt32(2 << 5) | (1 << 13) | (UInt32(0b10) << 11) // valid active termination
        let vdo4: UInt32 = (1 << 10) | (1 << 9) | (1 << 2) // optical, re-timer, isolated
        let active = USBPDSOP(
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
        #expect(v2 != nil)
        #expect(v2?.physicalConnection == .optical)
        #expect(v2?.activeElement == .retimer)
        #expect(v2?.opticallyIsolated == true)
    }

    @Test("Active cable VDO2 accessor returns nil when VDO4 missing")
    func activeCableVDO2AccessorReturnsNilWhenVDO4Missing() {
        // Active cable but only 4 VDOs (no VDO2 present).
        let active = USBPDSOP(
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
        #expect(active.activeCableVDO2 == nil)
    }

    // MARK: - SOP'' Controller Present / Active Layout Contradiction (DAR-30)

    @Test("Passive cable with bit 3 clear: sopDoubleControllerPresent is false")
    func passiveCableNoBit3_sopDoubleControllerPresentFalse() {
        // Normal passive cable. Bit 3 is in the Reserved [4:3] region and
        // must be zero per Table 6.42. Confirm we read it correctly as false.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(!cable.sopDoubleControllerPresent)
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("Passive cable with bit 3 set: sopDoubleControllerPresent is true")
    func passiveCableBit3Set_sopDoubleControllerPresentTrue() {
        // Bit 3 set on a passive-layout decode. This is the CalDigit-style
        // contradiction: bit [3] is Reserved in the passive layout and should
        // be zero; it is "SOP'' Controller Present" in the active layout.
        // We read it unconditionally so callers can detect the contradiction.
        let vdo: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency | (1 << 3)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: false)
        #expect(cable.sopDoubleControllerPresent)
        // Bit 3 being set does NOT itself generate a decode warning.
        // The contradiction is surfaced via USBPDSOP.hasActiveLayoutContradiction,
        // not as a CableVDO warning, because the full context (ID Header product
        // type) is only visible at the USBPDSOP level.
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("Active cable with bit 3 set: sopDoubleControllerPresent is true, no contradiction")
    func activeCableBit3Set_sopDoubleControllerPresentTrue_noContradiction() {
        // An active cable correctly reporting active has SOP'' Controller Present
        // set too. No contradiction since the ID Header already says active.
        let vdo: UInt32 = UInt32(2 << 5) | Self.validLatency | Self.validActiveTermination | (1 << 3)
        let cable = PDVDO.decodeCableVDO(vdo, isActive: true)
        #expect(cable.sopDoubleControllerPresent)
        #expect(cable.cableType == .active)
        #expect(cable.decodeWarnings.isEmpty)
    }

    @Test("hasActiveLayoutContradiction: true for CalDigit-style passive mis-report")
    func hasActiveLayoutContradiction_CalDigitStyle() {
        // Synthetic fixture matching the CalDigit 2M TB4 cable from issue #111:
        // ID Header says passive (Product Type = 3), but VDO[3] bit 3 is set.
        // VDO3 = 0x3208485A: bit 3 = 1, termination = 0b01 (passive-valid).
        let caldigitVDO3: UInt32 = 0x3208485A
        let passiveIDHeader: UInt32 = (3 << 27) | UInt32(0x2B1D) // Product Type 3, VID Lintes
        let sop = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 2,
            vendorID: 0x2B1D,
            productID: 0x1901,
            bcdDevice: 0x97,
            vdos: [
                passiveIDHeader,
                0,                  // Cert Stat
                0x19010097,         // Product VDO
                caldigitVDO3,       // Cable VDO: passive layout, but bit 3 set
            ],
            specRevision: 3
        )
        #expect(sop.hasActiveLayoutContradiction)
    }

    @Test("hasActiveLayoutContradiction: false for normal passive cable (regression guard)")
    func hasActiveLayoutContradiction_NormalPassive_False() {
        // A genuinely passive cable with bit 3 clear must NOT be flagged.
        // This is the regression guard: 154 out of 157 passive-reporting cables
        // in the customer-probe corpus have bit 3 clear; this must remain zero.
        let normalPassiveVDO3: UInt32 = 0b011 | UInt32(2 << 5) | Self.validLatency
        let passiveIDHeader: UInt32 = (3 << 27) | UInt32(0x05AC)
        let sop = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 1,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [passiveIDHeader, 0, 0, normalPassiveVDO3],
            specRevision: 3
        )
        #expect(!sop.hasActiveLayoutContradiction)
    }

    @Test("hasActiveLayoutContradiction: false for correctly-reporting active cable")
    func hasActiveLayoutContradiction_ActiveSelfReport_False() {
        // An active cable that correctly self-reports as active is not a
        // contradiction, even though it has bit 3 set.
        let activeVDO3: UInt32 = UInt32(2 << 5) | Self.validLatency | Self.validActiveTermination | (1 << 3)
        let activeIDHeader: UInt32 = (4 << 27) | UInt32(0x05AC)
        let sop = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 1,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [activeIDHeader, 0, 0, activeVDO3],
            specRevision: 3
        )
        #expect(!sop.hasActiveLayoutContradiction)
    }

    @Test("hasActiveLayoutContradiction: false when VDO[3] absent")
    func hasActiveLayoutContradiction_NoVDO3_False() {
        // No Cable VDO present (e.g. e-marker not read) means no contradiction.
        let passiveIDHeader: UInt32 = (3 << 27) | UInt32(0x05AC)
        let sop = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: 1,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [passiveIDHeader, 0, 0],  // only 3 VDOs, no VDO[3]
            specRevision: 3
        )
        #expect(!sop.hasActiveLayoutContradiction)
    }

    // MARK: - Cert Stat VDO

    @Test("Cert stat present when non-zero")
    func certStatPresentWhenNonZero() {
        let stat = PDVDO.decodeCertStat(0x12345)
        #expect(stat.xid == 0x12345)
        #expect(stat.isPresent)
    }

    @Test("Cert stat missing when zero")
    func certStatMissingWhenZero() {
        let stat = PDVDO.decodeCertStat(0)
        #expect(stat.xid == 0)
        #expect(stat.isPresent == false)
    }

    // MARK: - VDO from Data

    @Test("VDO from data little endian")
    func vdoFromData_LittleEndian() {
        // 0xDEADBEEF stored little-endian = EF BE AD DE
        let data = Data([0xEF, 0xBE, 0xAD, 0xDE])
        #expect(PDVDO.vdoFromData(data) == 0xDEADBEEF)
    }

    @Test("VDO from data too short")
    func vdoFromData_TooShort() {
        #expect(PDVDO.vdoFromData(Data([0x01, 0x02])) == nil)
    }
}
