import Foundation
import Testing
@testable import WhatCableCore

/// The PDO slot array.
///
/// macOS lays `PortControllerPortPDO` out as a fixed 13-slot array, 7 SPR
/// slots then 6 EPR slots, and `PortControllerNPDOs` counts only the SPR
/// offers. The array is therefore positional, not a list, and one of the
/// slots in the corpus holds a filler word that is not a real offer.
@Suite("PDContract PDO slots")
struct PDContractSlotTests {

    /// `0x808c8c8c`, the only filler word in the corpus. It sits in slot 13,
    /// array index 12, on four folders (m5max_macos26.5.2_f, m5pro_macos26.5.2_k,
    /// m5pro_macos27.0_d, m5pro_macos27.0_g). Its type bits say Variable, and
    /// it decodes to a minimum voltage of 40150 mV above a maximum of 400 mV,
    /// which is not a supply any source could offer.
    private static let fillerWord: UInt32 = 0x808c8c8c

    /// `m5max_macos26.5.2_f` entry 3, slot for slot as the probe prints it:
    /// four SPR Fixed offers in slots 1 to 4, the EPR Fixed offer the live
    /// contract selects in slot 8, and the filler word in slot 13.
    /// `PortControllerNPDOs` reads 4 on this machine, which is why trimming
    /// to it lost both slot 8 and slot 13.
    private static let m5maxSlots: [UInt32] = [
        0x0881_9128,   // slot 1:   5 V, 2.96 A
        0x0002_d12a,   // slot 2:   9 V, 2.98 A
        0x0004_b12b,   // slot 3:  15 V, 2.99 A
        0x0006_41f3,   // slot 4:  20 V, 4.99 A
        0, 0, 0,
        0x0008_c1f3,   // slot 8:  28 V, 4.99 A (EPR)
        0, 0, 0, 0,
        fillerWord,    // slot 13
    ]

    private static func m5maxContract() -> PDContract {
        PDContract(
            activeRdo: 0x81c7_59d6,
            pdoSlots: m5maxSlots.map { $0 == 0 ? nil : PDO.decode(rawValue: $0) },
            pdoCount: 4,
            eprPdoCount: 1,
            maxPower: 139_720,
            capMismatch: false,
            srcTypes: 0
        )
    }

    /// `0xc00c30f5`: `m4_macos26.6_i` entry 1, slot 6, and newly visible (it
    /// sits past that entry's NPDOs of 5). Same defect as the filler word in a
    /// different PDO class: an SPR PPS supply whose minimum voltage of 4800 mV
    /// sits above its maximum of 600 mV.
    private static let inverseRangePPS: UInt32 = 0xc00c_30f5

    /// `0xc1a42000`: `m1max_macos26.3.1_b` entry 3, slot 6. A real PPS offer
    /// with a real voltage range, advertising a maximum current of 0 A. 127
    /// corpus entries carry a newly visible PPS word shaped like this,
    /// `m1pro_macos26.5_y`'s `0xc0dc2000` among them.
    private static let zeroCurrentPPS: UInt32 = 0xc1a4_2000

    @Test("A PPS supply with its minimum voltage above its maximum is not plausible either")
    func inverseRangePPSIsNotPlausible() {
        let pdo = PDO.decode(rawValue: Self.inverseRangePPS)
        #expect(pdo == .pps(minVoltage: 4_800, maxVoltage: 600, maxCurrent: 5_850))
        #expect(pdo.isPlausible == false, "\(pdo) has a minimum voltage above its maximum")
        #expect(PowerSourceSynthesis.option(for: pdo) == nil,
            "an inverse-range PPS word produced \(String(describing: PowerSourceSynthesis.option(for: pdo)))")
    }

    @Test("A PPS supply advertising 0 A keeps its row but yields no option")
    func zeroCurrentPPSIsShownButNotOffered() {
        let pdo = PDO.decode(rawValue: Self.zeroCurrentPPS)
        #expect(pdo == .pps(minVoltage: 3_200, maxVoltage: 21_000, maxCurrent: 0))
        // The source advertised it, so it stays in the list and on the card:
        // this repo reports what the hardware said, it does not edit it.
        #expect(pdo.isPlausible, "a 0 A PPS supply is still what the source advertised")
        // But there is nothing to draw from it, so it is not a power option.
        #expect(PowerSourceSynthesis.option(for: pdo) == nil,
            "a 0 A PPS supply produced \(String(describing: PowerSourceSynthesis.option(for: pdo)))")
    }

    /// `0xf`: `m5pro_macos27.0_d` entry 1, slot 13, the same filler slot that
    /// holds `0x808c8c8c` on other entries. Its type bits say Fixed and its
    /// voltage field reads 0, so there is no supply here to describe. Its
    /// sibling is `0x7` on `m5pro_macos27.0_g`. Six such words exist in the
    /// corpus, two of them newly visible.
    private static let zeroVoltageFixed: UInt32 = 0x0000_000f

    @Test("A word carrying no usable voltage is dropped; a word whose information is merely partial is kept")
    func zeroVoltageIsDroppedButZeroCurrentIsKept() {
        // No usable voltage: nothing to report, so it is not an offer.
        let noVoltage = PDO.decode(rawValue: Self.zeroVoltageFixed)
        #expect(noVoltage == .fixed(voltage: 0, maxCurrent: 150))
        #expect(noVoltage.isPlausible == false, "\(noVoltage) carries no usable voltage")

        // Partial information: a real voltage range with a current field of
        // zero. The source advertised it, so it keeps its row. This is the
        // line between the two: drop a word that carries no information, keep
        // a word whose information is merely incomplete.
        let noCurrent = PDO.decode(rawValue: Self.zeroCurrentPPS)
        #expect(noCurrent.isPlausible, "a 0 A PPS supply still names a real 3.2 V to 21 V range")
    }

    @Test("selectedPDO refuses an implausible slot, so the RDO decode falls back rather than reading filler")
    func selectedPDORefusesAnImplausibleSlot() {
        // A guard, not a live bug: zero corpus RDOs name a filler slot today.
        // Without it an RDO naming one would still steer the RDO decode's
        // branch choice off a word that `pdoList` and `displayedSlots` both
        // refuse to show.
        let contract = PDContract(
            activeRdo: 0xd000_0000,   // object position 13
            pdoSlots: (1...12).map { _ in nil } + [PDO.decode(rawValue: Self.fillerWord)],
            pdoCount: 0,
            eprPdoCount: 0,
            maxPower: 0,
            capMismatch: false,
            srcTypes: 0
        )
        #expect(PDContract.objectPosition(of: contract.activeRdo) == 13)
        #expect(contract.pdoSlots[12] != nil, "the fixture must actually occupy the slot")
        #expect(contract.selectedPDO(for: contract.activeRdo) == nil,
            "selectedPDO returned \(String(describing: contract.selectedPDO(for: contract.activeRdo))) from a slot neither pdoList nor displayedSlots will show")
    }

    @Test("The filler word is not a plausible supply")
    func fillerWordIsNotPlausible() {
        let pdo = PDO.decode(rawValue: Self.fillerWord)
        #expect(pdo == .variable(minVoltage: 40_150, maxVoltage: 400, maxCurrent: 1_400))
        #expect(pdo.isPlausible == false, "\(pdo) has a minimum voltage above its maximum")
    }

    @Test("The filler word produces no power option")
    func fillerWordProducesNoOption() {
        let pdo = PDO.decode(rawValue: Self.fillerWord)
        let option = PowerSourceSynthesis.option(for: pdo)
        #expect(option == nil,
            "the filler word decoded to \(pdo) and produced \(String(describing: option)); it must produce no option at all")
    }

    @Test("The filler word appears in neither pdoList nor displayedSlots")
    func fillerWordIsNotOffered() {
        let contract = Self.m5maxContract()
        let filler = PDO.decode(rawValue: Self.fillerWord)
        #expect(contract.pdoList.contains(filler) == false,
            "pdoList still offers the filler word: \(contract.pdoList)")
        #expect(contract.displayedSlots.contains { $0.pdo == filler } == false,
            "displayedSlots still shows the filler word")
    }

    @Test("displayedSlots numbers rows by slot, skipping empty and implausible slots")
    func displayedSlotsUsesSlotPositions() {
        let contract = Self.m5maxContract()
        #expect(contract.displayedSlots.map(\.position) == [1, 2, 3, 4, 8],
            "got positions \(contract.displayedSlots.map(\.position))")
        #expect(contract.displayedSlots.map(\.pdo) == contract.pdoList)
        #expect(contract.pdoCount == 4)
        #expect(contract.eprPdoCount == 1)
    }

    @Test("selectedPDO resolves object position 8 to the EPR Fixed offer")
    func selectedPDOResolvesEPRPosition() {
        let contract = Self.m5maxContract()
        #expect(PDContract.objectPosition(of: contract.activeRdo) == 8)
        #expect(contract.selectedPDO(for: contract.activeRdo) == .fixed(voltage: 28_000, maxCurrent: 4_990))
    }

    @Test("selectedPDO returns nil for no contract, an empty slot, and a position past the array")
    func selectedPDORefusesToGuess() {
        let contract = Self.m5maxContract()
        // Object position 0: no active contract.
        #expect(contract.selectedPDO(for: 0x0000_0000) == nil)
        // Position 5, an empty slot on this machine.
        #expect(contract.selectedPDO(for: 0x5000_0000) == nil)
        // Position 13 against a four-slot contract.
        let short = PDContract(
            activeRdo: 0xd000_0000,
            pdoSlots: Array(Self.m5maxSlots.prefix(4)).map { PDO.decode(rawValue: $0) },
            pdoCount: 4,
            eprPdoCount: 0,
            maxPower: 0,
            capMismatch: false,
            srcTypes: 0
        )
        #expect(short.selectedPDO(for: short.activeRdo) == nil)
    }
}
