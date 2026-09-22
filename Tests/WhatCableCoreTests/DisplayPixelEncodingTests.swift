// Tests/WhatCableCoreTests/DisplayPixelEncodingTests.swift
import Foundation
import Testing
@testable import WhatCableCore

@Suite("DisplayPixelEncoding")
struct DisplayPixelEncodingTests {

    @Test("The fifteen kernel names, by value, and nil outside the table")
    func namesFollowTheKernelTable() {
        #expect(DisplayPixelEncoding(rawValue: 0) == .rgb444)
        #expect(DisplayPixelEncoding.rgb444.name == "RGB 4:4:4")
        #expect(DisplayPixelEncoding.ycbcr420.name == "YCbCr 4:2:0")
        #expect(DisplayPixelEncoding.ycbcr422.name == "YCbCr 4:2:2")
        #expect(DisplayPixelEncoding.ycbcr444.name == "YCbCr 4:4:4")
        #expect(DisplayPixelEncoding.dolbyVisionNative.name == "DolbyVision (native)")
        #expect(DisplayPixelEncoding.dolbyVisionHDMITunneling.name == "DolbyVision (HDMI tunneling)")
        #expect(DisplayPixelEncoding.ycbcr422DPTunneling.name == "YCbCr 4:2:2 (DP tunneling)")
        #expect(DisplayPixelEncoding.ycbcr422HDMITunneling.name == "YCbCr 4:2:2 (HDMI tunneling)")
        #expect(DisplayPixelEncoding.dolbyVisionLLYCbCr422.name == "DolbyVision LL YCbCr 4:2:2")
        #expect(DisplayPixelEncoding.dolbyVisionLLYCbCr422DPTunneling.name == "DolbyVision LL YCbCr 4:2:2 (DP tunneling)")
        #expect(DisplayPixelEncoding.dolbyVisionLLYCbCr422HDMITunneling.name == "DolbyVision LL YCbCr 4:2:2 (HDMI tunneling)")
        #expect(DisplayPixelEncoding.dolbyVisionLLYCbCr444.name == "DolbyVision LL YCbCr 4:4:4")
        #expect(DisplayPixelEncoding.dolbyVisionLLRGB444.name == "DolbyVision LL RGB 4:4:4")
        #expect(DisplayPixelEncoding.grgbTunneledEvenLineBlue.name == "GRGB Tunneled as YCbCr422 (Even line blue)")
        #expect(DisplayPixelEncoding.grgbTunneledEvenLineRed.name == "GRGB Tunneled as YCbCr422 (Even line red)")
        #expect(DisplayPixelEncoding(rawValue: 15).name == nil)
        #expect(DisplayPixelEncoding(rawValue: -1).name == nil)
        #expect(DisplayPixelEncoding(rawValue: 15).rawValue == 15, "an unknown value is carried, not dropped")
    }

    @Test("Apple's bits-per-pixel table, per encoding family (DCP.bin bitsPerPixel, dump A2)")
    func bitsPerPixelFollowsAppleTable() {
        for enc in [DisplayPixelEncoding.rgb444, .ycbcr444, .dolbyVisionLLYCbCr444, .dolbyVisionLLRGB444] {
            #expect(enc.bitsPerPixel(depth: 8) == 24, "encoding \(enc.rawValue)")
            #expect(enc.bitsPerPixel(depth: 10) == 30, "encoding \(enc.rawValue)")
        }
        for enc in [DisplayPixelEncoding.ycbcr422, .grgbTunneledEvenLineBlue, .grgbTunneledEvenLineRed] {
            #expect(enc.bitsPerPixel(depth: 8) == 16, "encoding \(enc.rawValue)")
            #expect(enc.bitsPerPixel(depth: 12) == 24, "encoding \(enc.rawValue)")
        }
        #expect(DisplayPixelEncoding.ycbcr420.bitsPerPixel(depth: 8) == 12)
        #expect(DisplayPixelEncoding.ycbcr420.bitsPerPixel(depth: 10) == 15)
        for raw in 4...10 {
            #expect(DisplayPixelEncoding(rawValue: raw).bitsPerPixel(depth: 8) == 24, "encoding \(raw)")
            #expect(DisplayPixelEncoding(rawValue: raw).bitsPerPixel(depth: 12) == 24, "encoding \(raw): a flat 24 whatever the depth")
        }
        #expect(DisplayPixelEncoding(rawValue: 15).bitsPerPixel(depth: 8) == nil, "the firmware calls 15 and above invalid")
        #expect(DisplayPixelEncoding(rawValue: -1).bitsPerPixel(depth: 8) == nil)
        #expect(DisplayPixelEncoding.rgb444.bitsPerPixel(depth: 0) == nil)
    }

    @Test("Codable as its integer")
    func codableAsInteger() throws {
        let data = try JSONEncoder().encode([DisplayPixelEncoding.ycbcr444, DisplayPixelEncoding(rawValue: 14)])
        #expect(String(data: data, encoding: .utf8) == "[3,14]")
        let back = try JSONDecoder().decode([DisplayPixelEncoding].self, from: data)
        #expect(back == [.ycbcr444, .grgbTunneledEvenLineRed])
    }
}
