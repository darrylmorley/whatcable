import Foundation
import Testing
@testable import WhatCableCore

/// Empirical guard for DAR-140 / issue #250, run against the committed
/// `01_walk_pd_tree.json` probe fixtures rather than synthetic identities.
/// The unit tests in `CableTrustReportTests` prove the softening *logic*
/// given a correctly-shaped partner; this proves the real-world ID-header
/// bytes from the corpus decode the way the fix expects, through the same
/// `PDVDO.decodeIDHeader` + `CableTrustReport` path the app uses.
///
/// Two outcomes matter, and a false "counterfeit" accusation is the one
/// this app can't ship:
/// - Folders where the plug identifies the cable as a registered vendor
///   (#250 shape) must produce the neutral note, not `zeroVendorID`.
/// - Folders where the zeroed e-marker sits next to a registered *device*
///   plug (a dock / SSD / phone) must still produce `zeroVendorID`: the
///   device's identity says nothing about the cable.
@Suite("Cable Trust — probe sweep (DAR-140)")
struct CableTrustProbeSweepTests {

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    /// Parse a probe's PD-tree walk into `USBPDSOP` values, one per
    /// SOP / SOP' / SOP'' block, decoding the real VDO bytes.
    private static func identities(probe: String) -> [USBPDSOP] {
        let url = probeRoot.appendingPathComponent(probe).appendingPathComponent("01_walk_pd_tree.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["output"] as? String
        else { return [] }

        var result: [USBPDSOP] = []
        // Each endpoint block starts at a "=== ...CCUSBPDSOP...[n] ===" header.
        let blocks = text.components(separatedBy: "=== ").dropFirst()
        for block in blocks {
            guard block.contains("CCUSBPDSOP") else { continue }

            let endpoint: USBPDSOP.Endpoint
            if let name = firstMatch(#"Name:\s+(\S+)"#, in: block) {
                switch name {
                case "SOP": endpoint = .sop
                case "SOP'": endpoint = .sopPrime
                case "SOP''": endpoint = .sopDoublePrime
                default: endpoint = .unknown
                }
            } else {
                continue
            }

            // Port number from "Description = "Port-USB-C@N/CC/...""
            let portNumber = firstMatch(#"Description = "Port-USB-C@(\d+)/CC"#, in: block)
                .flatMap { Int($0) } ?? 0

            // Vendor ID and VDO[0..] live inside the Metadata block.
            let vendorID = firstMatch(#"Vendor ID = \d+ \(0x([0-9a-fA-F]+)\)"#, in: block)
                .flatMap { Int($0, radix: 16) } ?? 0

            let vdos = allMatches(#"\[\d+\] <data 4 bytes: ([0-9a-fA-F ]+)>"#, in: block)
                .map { bytes -> UInt32 in
                    // Little-endian: "01 2b e0 05" -> 0x05e02b01
                    let parts = bytes.split(separator: " ").compactMap { UInt32($0, radix: 16) }
                    return parts.reversed().reduce(UInt32(0)) { ($0 << 8) | $1 }
                }

            result.append(USBPDSOP(
                id: UInt64(result.count),
                endpoint: endpoint,
                parentPortType: 0,
                parentPortNumber: portNumber,
                vendorID: vendorID,
                productID: 0,
                bcdDevice: 0,
                vdos: vdos,
                specRevision: 3
            ))
        }
        return result
    }

    /// Build the trust report for the port whose cable e-marker reports a
    /// zeroed vendor ID, pairing it with that same port's SOP partner.
    /// Returns nil when the folder has no such port.
    private static func reportForZeroedEmarkerPort(probe: String) -> CableTrustReport? {
        let ids = identities(probe: probe)
        let byPort = Dictionary(grouping: ids, by: \.parentPortNumber)
        for (_, eps) in byPort {
            guard let emarker = eps.first(where: {
                ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime) && $0.vendorID == 0
            }) else { continue }
            let partner = eps.first { $0.endpoint == .sop }
            return CableTrustReport(identity: emarker, partner: partner)
        }
        return nil
    }

    // MARK: - Regex helpers

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard
            let re = try? NSRegularExpression(pattern: pattern),
            let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            m.numberOfRanges > 1,
            let r = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    // MARK: - Tests

    /// The #250 shape: plug identifies the cable as a registered vendor while
    /// the e-marker reads blank. These two folders carry that shape (the plug
    /// declares the cable type in the DFP field, ufp=undefined).
    @Test("Registered-cable plug softens the blank e-marker (real probes)", arguments: [
        "m1_macos15.6.1",   // plug VID 0x311C (Southchip), registered
        "m1_macos26.5_r",   // plug VID 0x2F16 (Shenzhen Kejinming), registered
    ])
    func registeredCablePlugSoftens(probe: String) {
        guard let report = Self.reportForZeroedEmarkerPort(probe: probe) else {
            Issue.record("\(probe): expected a port with a zeroed e-marker")
            return
        }
        #expect(
            report.flags.contains { if case .eMarkerVIDBlankRegisteredPartner = $0 { return true }; return false },
            "\(probe): plug identifies the cable as a registered vendor, so the blank e-marker must soften to a note"
        )
        #expect(
            !report.flags.contains(.zeroVendorID),
            "\(probe): the counterfeit flag must not fire when the cable is registered at the plug"
        )
    }

    /// The 20-case guard: a zeroed e-marker next to a registered *device*
    /// plug must still flag. The device's registration is irrelevant to the
    /// cable, so softening here would be a new false negative.
    @Test("Registered device plug does NOT soften the blank e-marker (real probes)", arguments: [
        "m1ultra_macos26.5",   // plug 0x174C ASMedia, peripheral
        "m4pro_macos26.5_c",   // plug 0x04E8 Samsung, peripheral
        "m4pro_macos26.5_d",   // plug 0x0BDA Realtek, peripheral
    ])
    func registeredDevicePlugDoesNotSoften(probe: String) {
        guard let report = Self.reportForZeroedEmarkerPort(probe: probe) else {
            Issue.record("\(probe): expected a port with a zeroed e-marker")
            return
        }
        #expect(
            report.flags.contains(.zeroVendorID),
            "\(probe): the plug is a device, not the cable, so the blank e-marker must still flag"
        )
    }
}
