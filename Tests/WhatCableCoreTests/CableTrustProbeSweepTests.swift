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

    /// Find the port whose cable e-marker reports a zeroed vendor ID and build
    /// its trust report, paired with that same port's SOP partner (the plug).
    /// Returns the report and the partner it was built from, so callers inspect
    /// the exact plug the report used (not a global first-match SOP — which
    /// matters on multi-port probes). Nil when the folder has no such port.
    private static func zeroedEmarkerPort(probe: String) -> (report: CableTrustReport, partner: USBPDSOP?)? {
        let ids = identities(probe: probe)
        let byPort = Dictionary(grouping: ids, by: \.parentPortNumber)
        for (_, eps) in byPort {
            guard let emarker = eps.first(where: {
                ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime) && $0.vendorID == 0
            }) else { continue }
            let partner = eps.first { $0.endpoint == .sop }
            return (report: CableTrustReport(identity: emarker, partner: partner), partner: partner)
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
    ///
    /// After the power-brick fix, a plug whose DFP field decodes as a Power
    /// Brick (DFP raw 3) must NOT soften — a charger is a device, not the
    /// cable. The Southchip/Kejinming plugs put the cable type in the DFP field
    /// non-compliantly; their raw value is private customer data not visible to
    /// this test, so the assertion encodes the spec-correct outcome for whichever
    /// raw value the plug actually emits (3 = Power Brick → no soften; 4 =
    /// active-cable lookalike → soften).
    @Test("Registered-cable plug softens the blank e-marker unless it is a power brick (real probes)", arguments: [
        "m1_macos15.6.1",   // plug VID 0x311C (Southchip), registered
        "m1_macos26.5_r",   // plug VID 0x2F16 (Shenzhen Kejinming), registered
    ])
    func registeredCablePlugSoftens(probe: String) {
        guard let result = Self.zeroedEmarkerPort(probe: probe) else {
            Issue.record("\(probe): expected a port with a zeroed e-marker")
            return
        }
        let report = result.report
        // Pin the verdict to the same-port partner the report used, not a
        // global first-match SOP (matters on multi-port probes).
        let plugIsPowerBrick = result.partner?.idHeader?.dfpProductType == .powerBrick

        if plugIsPowerBrick {
            // DFP raw 3 = Power Brick: a charger on the far end. Its VID is not
            // the cable's, so the blank e-marker stays zeroVendorID and is never
            // credited to the brick's maker.
            #expect(
                report.flags.contains { $0.code == "zeroVendorID" },
                "\(probe): a power-brick plug must not soften the blank e-marker"
            )
            #expect(
                !report.flags.contains { if case .eMarkerVIDBlankRegisteredPartner = $0 { return true }; return false },
                "\(probe): a power-brick plug's VID must not be credited to the cable"
            )
        } else {
            // DFP raw 4 (active-cable lookalike) or a UFP cable type: the plug
            // identifies the cable as a registered vendor, so the blank e-marker
            // softens to a neutral note.
            #expect(
                report.flags.contains { if case .eMarkerVIDBlankRegisteredPartner = $0 { return true }; return false },
                "\(probe): plug identifies the cable as a registered vendor, so the blank e-marker must soften to a note"
            )
            #expect(
                !report.flags.contains { $0.code == "zeroVendorID" },
                "\(probe): the blank-VID flag must not fire when the cable is registered at the plug"
            )
        }
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
        guard let report = Self.zeroedEmarkerPort(probe: probe)?.report else {
            Issue.record("\(probe): expected a port with a zeroed e-marker")
            return
        }
        #expect(
            report.flags.contains { $0.code == "zeroVendorID" },
            "\(probe): the plug is a device, not the cable, so the blank e-marker must still flag"
        )
    }
}
