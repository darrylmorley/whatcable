import Foundation
import Testing
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

/// Tests the pure match logic of `DisplayModeReader`. The CoreGraphics read
/// itself needs hardware, but the matching, identity reconciliation, and
/// fail-closed rules are all unit-testable with injected data.
struct DisplayModeReaderTests {

    private func dpNode(productId: Int?, vendor: String?, serial: Int? = nil, hpmControllerUUID: String? = nil) -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(active: true, laneCount: 4, maxLaneCount: 4, linkRate: 4, tunneled: false, hpdState: 1),
            monitor: MonitorInfo(
                manufacturerName: vendor, productName: nil, productId: productId,
                serialNumber: serial, yearOfManufacture: nil, edid: nil
            ),
            hpmControllerUUID: hpmControllerUUID
        )
    }

    private func resolved(vendor: UInt32?, model: UInt32?, serial: UInt32? = nil, isBuiltin: Bool = false, w: Int = 3840, h: Int = 2160, hz: Double = 240, maxHz: Double? = nil) -> DisplayModeReader.ResolvedDisplay {
        let mode = DisplayCurrentMode(width: w, height: h, refreshHz: hz)
        let maxMode = DisplayCurrentMode(width: w, height: h, refreshHz: maxHz ?? hz)
        return DisplayModeReader.ResolvedDisplay(
            vendorNumber: vendor, modelNumber: model, serialNumber: serial,
            isBuiltin: isBuiltin, mode: mode, maxMode: maxMode
        )
    }

    @Test("Packed EDID vendor 0x1C54 decodes to GBT (Gigabyte)")
    func pnpDecode() {
        #expect(DisplayModeReader.pnpCode(fromPackedVendor: 0x1C54) == "GBT")
        // Apple is 0x0610 -> "APP".
        #expect(DisplayModeReader.pnpCode(fromPackedVendor: 0x0610) == "APP")
        // Junk (a field out of A-Z range) returns nil, never a false letter.
        #expect(DisplayModeReader.pnpCode(fromPackedVendor: 0xFFFF) == nil)
    }

    @Test("A clean single match attaches the live mode and the max mode")
    func cleanMatch() {
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [resolved(vendor: 0x1C54, model: 12821, hz: 120, maxHz: 240)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode == DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 120))
        #expect(out[0].maxMode == DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 240))
    }

    @Test("The HPM controller UUID survives enrichment (issue #664: the join key was dropped by with(currentMode:maxMode:))")
    func hpmControllerUUIDSurvivesMatch() {
        let uuid = "12345678-90AB-CDEF-1234-567890ABCDEF"
        let ports = [dpNode(productId: 12821, vendor: "GBT", hpmControllerUUID: uuid)]
        let displays = [resolved(vendor: 0x1C54, model: 12821, hz: 120, maxHz: 240)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode != nil, "fixture guard: the match attached")
        #expect(out[0].hpmControllerUUID == uuid)
        #expect(out[0].canonicalJoinKey == "1234567890abcdef1234567890abcdef", "the canonical key is still the UUID, not the portKey fallback")
    }

    @Test("The built-in panel is never matched to a DisplayPort node")
    func builtinExcluded() {
        // Even with an identity that would otherwise match, a built-in display
        // is excluded: a DP transport node is always an external connection.
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [resolved(vendor: 0x1C54, model: 12821, isBuiltin: true)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode == nil)
        #expect(out[0].maxMode == nil)
    }

    @Test("A nil max mode (mode list unavailable) still attaches the live mode, maxMode stays nil")
    func nilMaxModeStillAttachesLive() {
        // When CoreGraphics can't supply the mode list, the verdict must fall
        // back to the EDID reference, never to the live mode compared to itself.
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [
            DisplayModeReader.ResolvedDisplay(
                vendorNumber: 0x1C54, modelNumber: 12821, serialNumber: nil,
                mode: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60),
                maxMode: nil
            )
        ]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode?.refreshHz == 60)
        #expect(out[0].maxMode == nil)
    }

    @Test("A max mode with a 0 Hz refresh is dropped, the live mode still attaches")
    func zeroRefreshMaxModeDropped() {
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [resolved(vendor: 0x1C54, model: 12821, hz: 60, maxHz: 0)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode?.refreshHz == 60)
        #expect(out[0].maxMode == nil)
    }

    @Test("Wrong product id does not match, leaves currentMode nil")
    func noMatchOnProductId() {
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [resolved(vendor: 0x1C54, model: 9999)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode == nil)
    }

    @Test("Two identical displays with no serial are ambiguous: no attach (fail closed)")
    func ambiguousNoAttach() {
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [resolved(vendor: 0x1C54, model: 12821), resolved(vendor: 0x1C54, model: 12821)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode == nil)
    }

    @Test("Two identical displays disambiguate by serial when the node has one")
    func ambiguousSerialTiebreak() {
        let ports = [dpNode(productId: 12821, vendor: "GBT", serial: 42)]
        let displays = [
            resolved(vendor: 0x1C54, model: 12821, serial: 7, hz: 60),
            resolved(vendor: 0x1C54, model: 12821, serial: 42, hz: 240),
        ]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode?.refreshHz == 240)
    }

    @Test("A 0 Hz live mode is not trustworthy: no attach")
    func zeroRefreshNoAttach() {
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [resolved(vendor: 0x1C54, model: 12821, hz: 0)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode == nil)
    }

    @Test("A mismatched vendor with the same product id does not match")
    func vendorMustAgree() {
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [resolved(vendor: 0x0610, model: 12821)] // APP, not GBT
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode == nil)
    }

    @Test("Both sides carry a vendor but CG's number is junk: fail closed, no attach")
    func undecodableVendorFailsClosed() {
        // Product id agrees, but 0xFFFF doesn't decode to a PNP code. With both
        // sides claiming a vendor, an undecodable one must not fall back to a
        // product-id-only match.
        let ports = [dpNode(productId: 12821, vendor: "GBT")]
        let displays = [resolved(vendor: 0xFFFF, model: 12821)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode == nil)
    }

    @Test("Product id alone matches when one side lacks a vendor")
    func vendorAbsentFallsBackToProductId() {
        let ports = [dpNode(productId: 12821, vendor: nil)]
        let displays = [resolved(vendor: 0x1C54, model: 12821)]
        let out = DisplayModeReader.match(ports: ports, displays: displays)
        #expect(out[0].currentMode?.width == 3840)
    }

    // MARK: - displayPortBitsPerComponent clamp

    @Test("Bpc clamp accepts only the two depths DP Alt Mode actually carries")
    func bpcClampAcceptsOnlyKnownDPDepths() {
        // 8 (24bpp standard) and 10 (30bpp HDR / 10-bit) are the two depths a
        // DisplayPort Alt Mode link actually carries; they pass through.
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 8) == 8)
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 10) == 10)
    }

    @Test("Bpc clamp rejects backing-store framebuffer depths (false-positive guard)")
    func bpcClampRejectsBackingStoreDepths() {
        // 16 (NSWindowDepthSixtyfourBitRGB) and 32 (NSWindowDepthOnehundred-
        // twentyeightBitRGB) describe AppKit's backing store, not the link
        // encoding. Letting them through would make .compressionActive false-
        // positive on any 4K60 display the moment macOS reported a 64-bit
        // framebuffer (review pass #2 caught this on the original loose range).
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 16) == nil)
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 32) == nil)
    }

    @Test("Bpc clamp rejects middle values not observed via NSScreen.depth")
    func bpcClampRejectsMiddleValuesNotObservedHere() {
        // The clamp uses `== 8 || == 10`, not a range. 9 and 11 aren't defined
        // DP wire depths at all. 12 IS a valid VESA DP wire depth (MSA color
        // depth 0b011 in DP 1.4), but the input to this clamp is
        // `NSScreen.depth.bitsPerSample`, which hasn't been observed to report
        // 12 on macOS, so we can't confirm 12 from this source maps cleanly to
        // a 36bpp wire mode. Falling back to the 24bpp default is the safe
        // direction (under-counts bandwidth -> miss DSC rather than false-
        // positive). Extend the clamp when a real macOS observation lands.
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 9) == nil)
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 11) == nil)
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 12) == nil)
    }

    @Test("Bpc clamp rejects zero, negative, and absurd values")
    func bpcClampRejectsJunkValues() {
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 0) == nil)
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: -1) == nil)
        #expect(DisplayModeReader.displayPortBitsPerComponent(from: 1000) == nil)
    }
}
