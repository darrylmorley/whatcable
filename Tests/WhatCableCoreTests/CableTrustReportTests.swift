import Testing
@testable import WhatCableCore

@Suite("Cable Trust Report")
struct CableTrustReportTests {

    /// Valid cable-latency bits (0001 = ~10 ns, ~1 m). The decoder
    /// flags 0000 as a reserved value, so test fixtures that aren't
    /// specifically about latency need a real value.
    private static let validLatency: UInt32 = 1 << 13

    /// Build a synthetic SOP' identity. `cableVDO` is the raw VDO[3].
    private func cableIdentity(
        vendorID: Int = 0x05AC,
        endpoint: USBPDSOP.Endpoint = .sopPrime,
        cableVDO: UInt32 = (0b10 << 5) | 0b011 | (1 << 13) // USB4 Gen 3, 5A, ~1m
    ) -> USBPDSOP {
        USBPDSOP(
            id: 1,
            endpoint: endpoint,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: vendorID,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(vendorID),
                0,
                0,
                cableVDO
            ],
            specRevision: 3
        )
    }

    @Test("Clean cable produces no flags")
    func cleanCableProducesNoFlags() {
        let report = CableTrustReport(identity: cableIdentity())
        #expect(report.isEmpty)
        #expect(report.flags == [])
    }

    @Test("Non-cable endpoint produces no flags")
    func nonCableEndpointProducesNoFlags() {
        // SOP (port partner) shouldn't be evaluated as a cable.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0, endpoint: .sop))
        #expect(report.isEmpty)
    }

    @Test("Zero vendor ID flags")
    func zeroVendorIDFlags() {
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0))
        #expect(report.flags == [.zeroVendorID])
    }

    @Test("Reserved speed encoding flags")
    func reservedSpeedEncodingFlags() {
        // speed=5 (reserved), current=1 (3A), valid latency
        let vdo = UInt32(0b101) | UInt32(1 << 5) | Self.validLatency
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        #expect(report.flags == [.reservedSpeedEncoding(5)])
    }

    @Test("Reserved current encoding flags")
    func reservedCurrentEncodingFlags() {
        // speed=1 (USB 3.2 Gen1), current=3 (reserved), valid latency
        let vdo = UInt32(0b001) | UInt32(3 << 5) | Self.validLatency
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        #expect(report.flags == [.reservedCurrentEncoding(3)])
    }

    @Test("All three flags together")
    func allThreeFlagsTogether() {
        // VID=0, speed=6 (reserved), current=3 (reserved), valid latency
        let vdo = UInt32(0b110) | UInt32(3 << 5) | Self.validLatency
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0, cableVDO: vdo))
        #expect(report.flags == [
            .zeroVendorID,
            .reservedSpeedEncoding(6),
            .reservedCurrentEncoding(3)
        ])
    }

    // MARK: - Cable Latency

    @Test("Reserved cable latency flags")
    func reservedCableLatencyFlags() {
        // 0000 invalid for both cable types
        let zeroLatency = UInt32(0b011) | UInt32(2 << 5) // no latency bits
        let report = CableTrustReport(identity: cableIdentity(cableVDO: zeroLatency))
        #expect(report.flags == [.reservedCableLatencyEncoding(0)])
    }

    @Test("Active cable optical latency range is valid")
    func activeCableLatencyOpticalRangeIsValid() {
        // Build an active-cable identity. ufpProductType bits 29..27 = 100 = 4 (active).
        // Latency 1010 = ~2000 ns optical. Should not flag.
        let activeIdentity = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [
                UInt32(4 << 27) | UInt32(0x05AC), // active cable ID header
                0,
                0,
                UInt32(0b011) | UInt32(2 << 5) | (UInt32(0b1010) << 13) | UInt32(0b10 << 11) // ~2000 ns, valid active termination
            ],
            specRevision: 3
        )
        let report = CableTrustReport(identity: activeIdentity)
        #expect(
            report.isEmpty,
            "Active cable with optical latency 1010 should not flag"
        )
    }

    // MARK: - VID 0xFFFF sentinel (neutral metadata, not a flag)

    @Test("VID 0xFFFF does not fire any flag")
    func vid_FFFF_DoesNotFireAnyFlag() {
        // 0xFFFF is the spec-defined "vendor opted out of USB-IF
        // registration" sentinel. It's allowed by the spec, so we treat
        // it as neutral metadata (surfaced via the vendor-name path)
        // rather than a warning-style trust flag.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0xFFFF))
        #expect(
            report.isEmpty,
            "0xFFFF must not surface as any TrustFlag (would render as a warning)"
        )
    }

    @Test("VID 0xFFFF renders descriptive vendor name")
    func vid_FFFF_RendersDescriptiveVendorName() {
        // The neutral surface for 0xFFFF: vendorName describes it.
        #expect(
            VendorDB.name(for: 0xFFFF) == "No vendor ID assigned (USB-PD spec sentinel)"
        )
        #expect(VendorDB.isRegistered(0xFFFF) == false)
    }

    // MARK: - H3: VID not in USB-IF list

    @Test("Registered vendor does not fire H3")
    func registeredVendorDoesNotFireH3() {
        // 0x05AC (Apple) is in both the curated map and the bundled list.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0x05AC))
        #expect(report.isEmpty)
    }

    @Test("Cable e-marker chip vendors do not fire H3")
    func cableEmarkerChipVendorsDoNotFireH3() {
        // The six chip vendors observed in real cable reports
        // (#44, #45, #48, #49, #60, #62). All registered with USB-IF
        // per the bundled March 2026 list, so H3 must not fire.
        for vid in [0x20C2, 0x315C, 0x2095, 0x2E99, 0x201C, 0x2B1D] {
            let report = CableTrustReport(identity: cableIdentity(vendorID: vid))
            #expect(
                report.isEmpty,
                "H3 should not fire on registered VID \(String(format: "0x%04X", vid))"
            )
        }
    }

    @Test("Unregistered VID fires H3")
    func unregisteredVIDFiresH3() {
        // 0xDEAD is not a USB-IF assignment in any source we carry.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0xDEAD))
        #expect(report.flags == [.vidNotInUSBIFList(0xDEAD)])
    }

    @Test("Zero vendor ID does not double fire")
    func zeroVendorIDDoesNotDoubleFire() {
        // VID 0 fires zeroVendorID (stronger signal); we don't also
        // want H3 firing as a noisier "0x0000 not registered" message.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0))
        #expect(report.flags == [.zeroVendorID])
        #expect(report.flags.contains { flag in
            if case .vidNotInUSBIFList = flag { return true }
            return false
        } == false)
    }

    @Test("H3 combines with reserved encodings")
    func h3CombinesWithReservedEncodings() {
        // Unregistered VID + reserved speed bits = both flags.
        let vdo = UInt32(0b111) | UInt32(2 << 5) | Self.validLatency
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0xDEAD, cableVDO: vdo))
        #expect(report.flags == [
            .vidNotInUSBIFList(0xDEAD),
            .reservedSpeedEncoding(7)
        ])
    }

    // MARK: - H6 / H7 / H9a propagate from decoder to trust report

    @Test("Invalid VDO version surfaces as trust flag")
    func invalidVDOVersionSurfacesAsTrustFlag() {
        // Passive cable with VDO version 001 (any non-zero) is invalid.
        let vdo = UInt32(0b011) | UInt32(2 << 5) | Self.validLatency | (UInt32(1) << 21)
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        #expect(report.flags == [.invalidVDOVersion(1)])
    }

    @Test("Invalid cable termination surfaces as trust flag")
    func invalidCableTerminationSurfacesAsTrustFlag() {
        // Passive cable with termination 11 (invalid for passive).
        let vdo = UInt32(0b011) | UInt32(2 << 5) | Self.validLatency | UInt32(0b11 << 11)
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        #expect(report.flags == [.invalidCableTermination(0b11)])
    }

    @Test("EPR claimed with low max voltage surfaces as trust flag")
    func eprClaimedWithLowMaxVoltageSurfacesAsTrustFlag() {
        // Passive cable, EPR Capable set, max VBUS 20V.
        let vdo = UInt32(0b011) | UInt32(2 << 5) | Self.validLatency | UInt32(1 << 17)
        let report = CableTrustReport(identity: cableIdentity(cableVDO: vdo))
        #expect(report.flags == [.eprClaimedWithLowMaxVoltage])
    }

    // MARK: - JSON contract

    @Test("Flag codes are stable")
    func flagCodesAreStable() {
        // Codes are part of the JSON contract; pin them.
        #expect(TrustFlag.zeroVendorID.code == "zeroVendorID")
        #expect(TrustFlag.reservedSpeedEncoding(5).code == "reservedSpeedEncoding")
        #expect(TrustFlag.reservedCurrentEncoding(3).code == "reservedCurrentEncoding")
        #expect(TrustFlag.reservedCableLatencyEncoding(0).code == "reservedCableLatencyEncoding")
        #expect(TrustFlag.vidNotInUSBIFList(0xDEAD).code == "vidNotInUSBIFList")
        #expect(TrustFlag.invalidVDOVersion(1).code == "invalidVDOVersion")
        #expect(TrustFlag.invalidCableTermination(0b11).code == "invalidCableTermination")
        #expect(TrustFlag.eprClaimedWithLowMaxVoltage.code == "eprClaimedWithLowMaxVoltage")
    }

    @Test("H3 detail includes VID in hex")
    func h3DetailIncludesVIDInHex() {
        let detail = TrustFlag.vidNotInUSBIFList(0xABCD).detail
        #expect(detail.contains("0xABCD"))
    }

    // MARK: - DAR-140: blank e-marker softened by a registered cable plug

    /// Build a synthetic SOP partner identity. `productType` is the ID
    /// Header's UFP product type (3 = passive cable, 2 = peripheral). When
    /// `inDFP` is true the cable type is placed in the DFP field instead,
    /// mirroring the corpus shape where `ufp=undefined, dfp=passiveCable`.
    private func partnerIdentity(
        vendorID: Int,
        productType: Int,
        inDFP: Bool = false
    ) -> USBPDSOP {
        let header: UInt32 = inDFP
            ? (UInt32(productType) << 23) | UInt32(vendorID)   // DFP field
            : (UInt32(productType) << 27) | UInt32(vendorID)   // UFP field
        return USBPDSOP(
            id: 2,
            endpoint: .sop,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: vendorID,
            productID: 0,
            bcdDevice: 0,
            vdos: [header],
            specRevision: 3
        )
    }

    @Test("Blank e-marker is softened when the plug is a registered cable")
    func blankEmarkerSoftenedByRegisteredCablePlug() {
        // #250: e-marker VID 0, but the plug identifies the cable as a
        // registered vendor. Should be a neutral note, not a counterfeit flag.
        let partner = partnerIdentity(vendorID: 0x05AC, productType: 3) // passive cable
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0), partner: partner)
        #expect(report.flags == [.eMarkerVIDBlankRegisteredPartner(0x05AC)])
        #expect(report.flags.first?.severity == .note)
    }

    @Test("DFP-only cable plug still softens the blank e-marker")
    func blankEmarkerSoftenedWhenPlugCableTypeInDFP() {
        // Corpus reality: the plug's cable type often lives in the DFP field
        // (ufp=undefined). The fix must mirror PortSummary's UFP-or-DFP logic.
        let partner = partnerIdentity(vendorID: 0x05AC, productType: 3, inDFP: true)
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0), partner: partner)
        #expect(report.flags == [.eMarkerVIDBlankRegisteredPartner(0x05AC)])
    }

    @Test("A registered device plug does NOT soften the blank e-marker")
    func blankEmarkerNotSoftenedByDevicePlug() {
        // The 20 corpus cases: the plug is a peripheral/dock with a registered
        // VID that belongs to the device, not the cable. The counterfeit flag
        // must still fire.
        let partner = partnerIdentity(vendorID: 0x05AC, productType: 2) // peripheral
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0), partner: partner)
        #expect(report.flags == [.zeroVendorID])
    }

    @Test("An unregistered cable plug does NOT soften the blank e-marker")
    func blankEmarkerNotSoftenedByUnregisteredCablePlug() {
        // Registered-only rule: a non-zero but unregistered plug VID is weaker
        // proof, so we keep the counterfeit flag rather than going silent.
        let partner = partnerIdentity(vendorID: 0xDEAD, productType: 3) // passive cable
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0), partner: partner)
        #expect(report.flags == [.zeroVendorID])
    }

    @Test("With no plug, a blank e-marker still fires the counterfeit flag")
    func blankEmarkerStillFiresWithoutPartner() {
        // Default behaviour is preserved when there's no SOP partner.
        let report = CableTrustReport(identity: cableIdentity(vendorID: 0))
        #expect(report.flags == [.zeroVendorID])
    }

    @Test("Softened note names the plug's vendor")
    func softenedNoteNamesVendor() {
        let detail = TrustFlag.eMarkerVIDBlankRegisteredPartner(0x05AC).detail
        #expect(detail.contains("0x05AC"))
        #expect(TrustFlag.eMarkerVIDBlankRegisteredPartner(0x05AC).code == "eMarkerVIDBlankRegisteredPartner")
        #expect(TrustFlag.eMarkerVIDBlankRegisteredPartner(0x05AC).severity == .note)
    }
}
