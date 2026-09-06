import Testing
@testable import WhatCableCore

/// Tests for the Cable VDO discrimination added to
/// `CableDB.curatedCables(vid:pid:cableVDO:)` (`Sources/WhatCableCore/Database/CableDB.swift`).
///
/// One (VID, PID) pair can now curate more than one row for two different
/// reasons, and this suite pins both against the real bundled `whatcable.db`:
///  - the same OEM cable sold under different retail brands, where every row
///    shares the identical (vid, pid, cable_vdo) fingerprint (#505: ACON
///    0x0522/0x0A33 as both Anker Prime and UGREEN), and
///  - one PID covering several capability tiers, told apart only by Cable VDO
///    (#239: Chant Sincere 0x0C62/0xC8F1's 3A/5A variants, Sumitomo
///    0x20C2/0x0714's 40/80 Gbps variants).
@Suite("CableDB: Cable VDO variant lookup")
struct CableDBVariantLookupTests {

    @Test("Same fingerprint, two brands: both resolve")
    func sameFingerprintTwoBrandsBothResolve() {
        // ACON 0x0522/0x0A33 at Cable VDO 0x110A2644 is sold as both Anker
        // Prime and UGREEN (#505). A lookup with the exact matching VDO must
        // return both curated rows, not silently pick one.
        let matches = CableDB.curatedCables(vid: 0x0522, pid: 0x0A33, cableVDO: 0x110A2644)
        #expect(matches.count == 2, "expected 2 curated rows, got \(matches.map(\.brand))")
        #expect(matches.contains { $0.brand.localizedCaseInsensitiveContains("Anker") })
        #expect(matches.contains { $0.brand.localizedCaseInsensitiveContains("UGREEN") })
    }

    @Test("Chant Sincere 3A variant resolves only the Lenovo 3A row")
    func chantSincere3AVariantResolvesOnlyThatRow() {
        // 0x0C62/0xC8F1 at Cable VDO 0x00082022 is the 3A Lenovo ThinkVision
        // variant (#402). The 5A row must not leak in.
        let matches = CableDB.curatedCables(vid: 0x0C62, pid: 0xC8F1, cableVDO: 0x0008_2022)
        #expect(matches.count == 1, "expected exactly 1 row, got \(matches.map(\.brand))")
        #expect(matches.first?.brand.contains("3 A") == true, "expected the 3A row, got \(matches.map(\.brand))")
    }

    @Test("Chant Sincere 5A variant resolves only the 5A row")
    func chantSincere5AVariantResolvesOnlyThatRow() {
        // 0x0C62/0xC8F1 at Cable VDO 0x00082042 is the 5A Lenovo/Dell variant
        // (Test-kit corpus). The 3A row must not leak in.
        let matches = CableDB.curatedCables(vid: 0x0C62, pid: 0xC8F1, cableVDO: 0x0008_2042)
        #expect(matches.count == 1, "expected exactly 1 row, got \(matches.map(\.brand))")
        #expect(matches.first?.brand.contains("5 A") == true, "expected the 5A row, got \(matches.map(\.brand))")
    }

    @Test("Chant Sincere unknown Cable VDO resolves nothing")
    func chantSincereUnknownVDOResolvesNothing() {
        // Neither curated 0x0C62/0xC8F1 row was entered with cable_vdo == 0
        // (both 0x00082022 and 0x00082042 are non-zero), so there is no
        // unversioned-fallback row to fall back to. A VDO that matches
        // neither variant exactly must resolve nothing rather than guess
        // which tier the cable actually is.
        let matches = CableDB.curatedCables(vid: 0x0C62, pid: 0xC8F1, cableVDO: 0x0008_2099)
        #expect(matches.isEmpty, "expected no match for an unrecognised variant, got \(matches.map(\.brand))")
    }

    @Test("Sumitomo 40 Gbps and 80 Gbps variants of PID 0x0714 select different rows")
    func sumitomo0714VariantsSelectDifferentRows() {
        let fortyGbps = CableDB.curatedCables(vid: 0x20C2, pid: 0x0714, cableVDO: 0x460A_2643)
        let eightyGbps = CableDB.curatedCables(vid: 0x20C2, pid: 0x0714, cableVDO: 0x460A_2644)

        #expect(fortyGbps.count == 1, "expected exactly 1 row, got \(fortyGbps.map(\.brand))")
        #expect(fortyGbps.first?.speed.contains("40 Gbps") == true, "expected the 40 Gbps row, got \(fortyGbps.map(\.speed))")

        #expect(eightyGbps.count == 1, "expected exactly 1 row, got \(eightyGbps.map(\.brand))")
        #expect(eightyGbps.first?.speed.contains("80 Gbps") == true, "expected the 80 Gbps row, got \(eightyGbps.map(\.speed))")

        #expect(fortyGbps.first?.brand != eightyGbps.first?.brand || fortyGbps.first?.speed != eightyGbps.first?.speed,
            "the two variants should be distinguishable from each other")
    }

    @Test("CalDigit's merged Thunderbolt 5 cable row resolves to exactly one brand")
    func caldigitMergedRowResolvesToOneBrand() {
        // This PR merged 5 re-report rows (issues #89, #90, #211, #243,
        // #254) for the same product (VID 0x01B6, PID 0x4003, Cable VDO
        // 0x110A2644) into a single curated row. A lookup must resolve
        // exactly one brand, not a duplicate per merged issue.
        let matches = CableDB.curatedCables(vid: 0x01B6, pid: 0x4003, cableVDO: 0x110A_2644)
        #expect(matches.count == 1, "expected exactly 1 row after the merge, got \(matches.map(\.brand))")
        #expect(matches.first?.brand.contains("CalDigit") == true)
    }

    @Test("Zero VID or zero PID still returns nothing, regardless of Cable VDO")
    func zeroIdentityStillReturnsNothing() {
        #expect(CableDB.curatedCables(vid: 0, pid: 0x4003, cableVDO: 0x110A_2644).isEmpty)
        #expect(CableDB.curatedCables(vid: 0x01B6, pid: 0, cableVDO: 0x110A_2644).isEmpty)
        #expect(CableDB.curatedCables(vid: 0, pid: 0, cableVDO: 0).isEmpty)
    }

    @Test("fingerprintCount counts distinct (VID, PID, Cable VDO) fingerprints, not just VID+PID pairs")
    func fingerprintCountCountsFingerprintsNotPairs() {
        // Chant Sincere (0x0C62, 0xC8F1) and Sumitomo (0x20C2, 0x0714) each
        // curate two rows with DIFFERENT Cable VDO under the same VID+PID
        // pair (see the 3A/5A and 40/80 Gbps tests above). Each such pair is
        // one (VID, PID) group (what `pairCount` counts) but two
        // fingerprints, so on the real bundled data fingerprintCount must be
        // strictly greater than pairCount. A naive "group count"
        // implementation (what fingerprintCount used to return) would make
        // this comparison fail.
        #expect(CableDB.fingerprintCount > CableDB.pairCount,
            "fingerprintCount (\(CableDB.fingerprintCount)) should exceed pairCount (\(CableDB.pairCount)); the Chant Sincere and Sumitomo variant pairs guarantee this on real data")
    }
}
