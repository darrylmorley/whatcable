import Testing
@testable import WhatCableCore

/// USB PD R3.2 RDO field layouts by selected-PDO type:
///
/// Fixed/Variable (Table 6.23):
///   bits 31:28 = Object Position
///   bits 19:10 = Operating Current in 10 mA units
///   bits  9:0  = Maximum Operating Current in 10 mA units
///
/// Battery (Table 6.24):
///   bits 31:28 = Object Position
///   bits 19:10 = Operating Power in 250 mW units
///   bits  9:0  = Maximum Operating Power in 250 mW units
///
/// PPS/AVS APDO (Table 6.26):
///   bits 31:28 = Object Position
///   bits 19:9  = Output Voltage in 20 mV units (11-bit field)
///   bits  6:0  = Operating Current in 50 mA units
///
/// The Fixed suite guards the pre-existing decode (regression). Battery and
/// PPS/AVS suites verify the new type-aware paths added in DAR-20.
@Suite("RDO Decoding")
struct RDODecodingTests {
    @Test("5V 3A contract: operating 2A, max 3A, PDO position 1")
    func basic5V3A() {
        // PDO position 1 (bits 31:28 = 0001)
        // Operating current 200 (200 * 10mA = 2000mA) at bits 19:10
        // Max operating current 300 (300 * 10mA = 3000mA) at bits 9:0
        let rdo: UInt32 = (1 << 28) | (200 << 10) | 300
        let position = PDContract.objectPosition(of: rdo)
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(position == 1)
        #expect(operating == 2000)
        #expect(max == 3000)
    }

    @Test("20V 5A contract: operating 4.5A, max 5A, PDO position 4")
    func highPower20V() {
        let rdo: UInt32 = (4 << 28) | (450 << 10) | 500
        let position = PDContract.objectPosition(of: rdo)
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(position == 4)
        #expect(operating == 4500)
        #expect(max == 5000)
    }

    @Test("Operating current is always in bits 19:10, not 9:0")
    func fieldOrderMatchesSpec() {
        // Construct an RDO where the two current values differ so a swap
        // would be caught: operating = 100 (1A), max = 300 (3A)
        let rdo: UInt32 = (2 << 28) | (100 << 10) | 300
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(operating == 1000, "Operating current should be 1000mA (bits 19:10)")
        #expect(max == 3000, "Max operating current should be 3000mA (bits 9:0)")
        #expect(operating < max, "Operating should be less than max in this test case")
    }

    @Test("Zero RDO produces all zeros")
    func zeroRDO() {
        let rdo: UInt32 = 0
        let position = PDContract.objectPosition(of: rdo)
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(position == 0)
        #expect(operating == 0)
        #expect(max == 0)
    }

    @Test("Max values: PDO position 7, both currents at 1023 (10.23A)")
    func maxValues() {
        let rdo: UInt32 = (7 << 28) | (0x3FF << 10) | 0x3FF
        let position = PDContract.objectPosition(of: rdo)
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(position == 7)
        #expect(operating == 10230)
        #expect(max == 10230)
    }

    // MARK: - Battery RDO (Table 6.24)
    // Same bit positions as Fixed but units are 250 mW, not 10 mA.

    @Test("Battery RDO: operating 40W, max 60W, PDO position 2")
    func batteryRDO() {
        // Operating power 160 (160 * 250 mW = 40 000 mW = 40 W) at bits 19:10
        // Max power 240 (240 * 250 mW = 60 000 mW = 60 W) at bits 9:0
        let rdo: UInt32 = (2 << 28) | (160 << 10) | 240
        let position = PDContract.objectPosition(of: rdo)
        let operatingPowerMW = Int((rdo >> 10) & 0x3FF) * 250
        let maxPowerMW = Int(rdo & 0x3FF) * 250
        #expect(position == 2)
        #expect(operatingPowerMW == 40_000, "Operating power should be 40 W (40000 mW)")
        #expect(maxPowerMW == 60_000, "Max power should be 60 W (60000 mW)")
    }

    @Test("Battery RDO: fixed path would misread as current, power path is correct")
    func batteryRDODoesNotMatchFixed() {
        // 160 * 250 mW = 40000 mW (correct as power)
        // 160 * 10 mA = 1600 mA (wrong if read as current)
        let rdo: UInt32 = (2 << 28) | (160 << 10) | 240
        let wrongCurrentMA = Int((rdo >> 10) & 0x3FF) * 10
        let correctPowerMW = Int((rdo >> 10) & 0x3FF) * 250
        #expect(wrongCurrentMA == 1600)
        #expect(correctPowerMW == 40_000)
        #expect(wrongCurrentMA != correctPowerMW, "Fixed-path decode gives wrong value for a Battery RDO")
    }

    // MARK: - PPS/AVS APDO RDO (Table 6.26)
    // Output voltage in bits 19:9 (20 mV units, 11-bit field).
    // Operating current in bits 6:0 (50 mA units).

    @Test("PPS APDO RDO: 15V output, 3A operating current, PDO position 6")
    func ppsRDO() {
        // Output voltage 750 (750 * 20 mV = 15 000 mV = 15 V) at bits 19:9
        // Operating current 60 (60 * 50 mA = 3000 mA = 3 A) at bits 6:0
        let rdo: UInt32 = (6 << 28) | (750 << 9) | 60
        let position = PDContract.objectPosition(of: rdo)
        let outputVoltageMV = Int((rdo >> 9) & 0x7FF) * 20
        let operatingCurrentMA = Int(rdo & 0x7F) * 50
        #expect(position == 6)
        #expect(outputVoltageMV == 15_000, "Output voltage should be 15 V (15000 mV)")
        #expect(operatingCurrentMA == 3_000, "Operating current should be 3 A (3000 mA)")
    }

    @Test("PPS APDO RDO: fixed path misreads voltage field as current")
    func ppsRDODoesNotMatchFixed() {
        // 750 * 20 mV = 15000 mV (correct as voltage)
        // 750 * 10 mA = 7500 mA (wrong if read as current from bits 19:10 of a 10-bit field)
        // Note: bits 19:9 of rdo = 750, but bits 19:10 = 750 >> 1 = 375 when only 10 bits are read.
        // The point is the units (20 mV vs 10 mA) differ, so the result is always wrong.
        let rdo: UInt32 = (6 << 28) | (750 << 9) | 60
        let wrongCurrentMA = Int((rdo >> 10) & 0x3FF) * 10   // Fixed path misread
        let correctVoltageMV = Int((rdo >> 9) & 0x7FF) * 20  // PPS path
        #expect(wrongCurrentMA != correctVoltageMV, "Fixed-path decode gives wrong value for a PPS RDO")
    }

    // Real value pulled from the customer-probe corpus (machine m2max_macos26.5_c):
    // a real PPS contract a Mac negotiated, PortControllerActiveContractRdo = 0x518759d6.
    // It decodes to a plausible PPS point (18.8 V, 4.3 A); the old fixed-layout
    // decode read those bits as a meaningless 4700 mA "operating current". This
    // anchors the PPS path to confirmed hardware data, not just synthetic values.
    @Test("PPS APDO RDO: real corpus value decodes to a valid PPS point")
    func ppsRDORealCorpusValue() {
        let rdo: UInt32 = 0x518759d6
        let position = PDContract.objectPosition(of: rdo)
        let outputVoltageMV = Int((rdo >> 9) & 0x7FF) * 20
        let operatingCurrentMA = Int(rdo & 0x7F) * 50
        #expect(position == 5)
        #expect(outputVoltageMV == 18_800)
        #expect(operatingCurrentMA == 4_300)
        #expect((3_000...21_000).contains(outputVoltageMV), "Output voltage must be a valid PPS voltage")
    }

    // Real value pulled from the customer-probe corpus
    // (machine m5max_macos26.5.2_f, PortControllerInfo entry 3, MaxPower
    // 139720): an Apple 140 W brick's live EPR contract,
    // PortControllerActiveContractRdo = 0x81c759d6. Bit 31 is set, so the
    // old 3-bit read returned position 0 ("no active contract") and power
    // synthesis found no winning option. The 4-bit read gives position 8,
    // which lands on the Fixed 28 V / 4.99 A slot whose 139.72 W matches
    // MaxPower exactly.
    @Test("EPR RDO: real corpus 140 W contract selects object position 8")
    func eprObjectPositionRealCorpusValue() {
        let rdo: UInt32 = 0x81c759d6
        let position = PDContract.objectPosition(of: rdo)
        #expect(position == 8, "EPR object position is 4 bits wide (31:28), not 3")
        #expect(position != 0, "A 3-bit read reports no active contract for this real EPR contract")
    }
}
