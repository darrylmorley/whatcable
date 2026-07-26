import Foundation
import Testing
@testable import WhatCableCore

@Suite("USB device detail display helpers")
struct USBDeviceDetailTests {

    private func device(
        vendorID: UInt16 = 0,
        productID: UInt16 = 0,
        vendorName: String? = nil,
        serialNumber: String? = nil,
        usbVersion: String? = nil
    ) -> USBDevice {
        USBDevice(
            id: 1, locationID: 0x0100_0000, vendorID: vendorID, productID: productID,
            vendorName: vendorName, productName: "Widget", serialNumber: serialNumber,
            usbVersion: usbVersion, speedRaw: nil, busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
    }

    // MARK: - vendorDisplay

    @Test("vendorDisplay prefers the device-reported vendor name and appends VID:PID")
    func vendorDisplayUsesReportedName() {
        let d = device(vendorID: 0x05AC, productID: 0x12A8, vendorName: "Apple Inc.")
        #expect(d.vendorDisplay == "Apple Inc. (0x05AC:0x12A8)")
    }

    @Test("vendorDisplay falls back to the VID database when the device reports no name")
    func vendorDisplayFallsBackToDB() {
        // 0x05AC is Apple in the bundled USB-IF list.
        let d = device(vendorID: 0x05AC, productID: 0x12A8, vendorName: nil)
        #expect(d.vendorDisplay == "Apple (0x05AC:0x12A8)")
    }

    @Test("vendorDisplay shows bare hex when no name is available anywhere")
    func vendorDisplayBareHex() {
        // Sanity-check the precondition: this VID must be unknown to the DB for
        // the test to mean anything. 0xF00D is absent from the bundled list.
        #expect(VendorDB.name(for: 0xF00D) == nil)
        let d = device(vendorID: 0xF00D, productID: 0x0002, vendorName: nil)
        #expect(d.vendorDisplay == "0xF00D:0x0002")
    }

    @Test("vendorDisplay keeps community usb.ids names that are not USB-IF registrations")
    func vendorDisplayKeepsCommunityNames() throws {
        // VendorDB.isRegistered is narrower than name(for:) by design: it
        // excludes community usb.ids entries. Gating the fallback on it would
        // drop good vendor names and show bare hex instead.
        let vid = 0x01B6
        try #require(VendorDB.name(for: vid) != nil, "precondition: VID resolves to a name")
        try #require(!VendorDB.isRegistered(vid), "precondition: VID is not a USB-IF registration")

        let d = device(vendorID: UInt16(vid), productID: 0x0002, vendorName: nil)
        #expect(d.vendorDisplay.hasSuffix("(0x01B6:0x0002)"))
        #expect(d.vendorDisplay != "0x01B6:0x0002", "the community name should be shown")
    }

    @Test("vendorDisplay never renders the VID 0 sentinel as a vendor name")
    func vendorDisplayVIDZeroStaysBareHex() {
        // VendorDB.name(for: 0) returns the cable view's explanatory sentence,
        // which would read here as a vendor literally called "No vendor
        // reported".
        let d = device(vendorID: 0, productID: 0x1234, vendorName: nil)
        #expect(d.vendorDisplay == "0x0000:0x1234")
    }

    @Test("vendorDisplay never renders the 0xFFFF sentinel as a vendor name")
    func vendorDisplayVIDFFFFStaysBareHex() {
        let d = device(vendorID: 0xFFFF, productID: 0x1234, vendorName: nil)
        #expect(d.vendorDisplay == "0xFFFF:0x1234")
    }
}
