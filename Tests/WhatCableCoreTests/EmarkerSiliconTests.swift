import Foundation
import Testing
@testable import WhatCableCore

@Suite("E-marker Silicon Vendors")
struct EmarkerSiliconTests {

    @Test("All five silicon vendor IDs resolve to their short name")
    func siliconVendorsResolve() {
        #expect(EmarkerSilicon.shortName(for: 0x315C) == "CPS")
        #expect(EmarkerSilicon.shortName(for: 0x2109) == "VIA")
        #expect(EmarkerSilicon.shortName(for: 0x2E87) == "Injoinic")
        #expect(EmarkerSilicon.shortName(for: 0x2E99) == "Hynetek")
        #expect(EmarkerSilicon.shortName(for: 0x04B4) == "Cypress")
    }

    @Test("A cable brand's own vendor ID resolves to nil")
    func cableBrandResolvesToNil() {
        #expect(EmarkerSilicon.shortName(for: 0x05AC) == nil)  // Apple
        #expect(EmarkerSilicon.shortName(for: 0x2B1D) == nil)  // e-marker VID from a cable maker
    }
}
