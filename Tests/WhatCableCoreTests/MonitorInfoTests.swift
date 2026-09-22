import Foundation
import Testing
@testable import WhatCableCore

@Suite("MonitorInfo")
struct MonitorInfoTests {

    private func monitor(edid: Data?, manufacturer: String?) -> MonitorInfo {
        MonitorInfo(manufacturerName: manufacturer, productName: nil, productId: nil, yearOfManufacture: nil, edid: edid)
    }

    /// 128 zero bytes with bytes 8-9 set: the manufacturer id field, big-endian.
    private func edid(manufacturerBytes: (UInt8, UInt8)) -> Data {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[8] = manufacturerBytes.0
        bytes[9] = manufacturerBytes.1
        return Data(bytes)
    }

    @Test("EDID bytes 8-9 equal to 0x0610 make an Apple display, whatever the name says")
    func edidBytesDecide() {
        #expect(monitor(edid: edid(manufacturerBytes: (0x06, 0x10)), manufacturer: nil).isAppleDisplay == true)
        #expect(monitor(edid: edid(manufacturerBytes: (0x06, 0x10)), manufacturer: "DEL").isAppleDisplay == true)
        #expect(monitor(edid: edid(manufacturerBytes: (0x10, 0xAC)), manufacturer: "APP").isAppleDisplay == false, "the EDID outranks a contradicting name")
        #expect(monitor(edid: edid(manufacturerBytes: (0x10, 0x06)), manufacturer: nil).isAppleDisplay == false, "byte order matters: 0x1006 is not Apple")
    }

    @Test("Without an EDID that reaches byte 9, the PNP name APP is the fallback")
    func nameIsTheFallback() {
        #expect(monitor(edid: nil, manufacturer: "APP").isAppleDisplay == true)
        #expect(monitor(edid: nil, manufacturer: "DEL").isAppleDisplay == false)
        #expect(monitor(edid: nil, manufacturer: nil).isAppleDisplay == false)
        #expect(monitor(edid: Data(repeating: 0, count: 9), manufacturer: "APP").isAppleDisplay == true, "nine bytes cannot hold byte 9")
    }

    @Test("The corpus Studio Display EDID header reads as Apple")
    func corpusStudioDisplayHeader() {
        // m5_macos26.6.1_e: 00ffffffffffff00 0610 46ae ...
        let header = Data([0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x06, 0x10, 0x46, 0xae, 0x00, 0x00, 0x00, 0x00])
        #expect(monitor(edid: header, manufacturer: nil).isAppleDisplay == true)
    }
}
