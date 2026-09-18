import Foundation
import Testing
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

// MARK: - DisplayDiagnosticProbeSweepTests (DAR-138)
//
// Corpus-backed tests for DisplayDiagnostic. Each test loads a real probe-33
// file from `research/customer-probes/`, parses it into a
// `IOPortTransportStateDisplayPort` using the same `makeUpdate` path the live
// app uses, then runs `DisplayDiagnostic` and asserts verdict-level
// expectations grounded in the machine's `inspection.md`.
//
// Why WhatCableDarwinTests (not WhatCableCoreTests): the parse step needs
// `DisplayPortTransportWatcher.makeUpdate`, which lives in
// `WhatCableDarwinBackend`. `DisplayDiagnostic` itself is in
// `WhatCableCore` and is accessible from here via the dependency chain.
//
// DSC coverage limit: monitor DSC capability is not in these probes (issue
// #246). Where the verdict is `.compressionPlausible`, the test confirms that
// verdict; it cannot confirm the display is actually compressing. The
// `.fine`-via-DSC upgrade path (CoreGraphics live-mode confirmation) is not
// exercised here because probe 33 carries no CoreGraphics data.
//
// All helpers in this file are file-private; there is no shared
// Support/ProbeCorpus.swift dependency.

@Suite("DisplayDiagnostic -- customer probe sweep (DAR-138)")
struct DisplayDiagnosticProbeSweepTests {

    // MARK: - Corpus root

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    // MARK: - Probe 33 loader

    private static func loadProbe33(folder: String) -> String? {
        let url = probeRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("33_displayport_capability.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Probe 33 block parser
    //
    // Parses `=== DisplayPort node [N] ===` blocks from probe 33.
    // Properties use `KEY = VALUE` equals format at 2-space indent.
    // Metadata sub-fields appear as flat `Metadata.KEY = VALUE` lines;
    // they are folded into a nested dict under "Metadata" so the watcher's
    // `read("Metadata") as? [String: Any]` lookup works normally.
    // (File-private copy of the parser from DisplayPortTransportWatcherSweepTests.)

    private static func parseDPNode33Blocks(text: String) -> [[String: Any]] {
        guard let regex = try? NSRegularExpression(
            pattern: "=== DisplayPort node \\[\\d+\\] ===")
        else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var blocks: [[String: Any]] = []
        for (i, match) in matches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = i + 1 < matches.count
                ? matches[i + 1].range.lowerBound
                : nsText.length
            let body = nsText.substring(with: NSRange(location: bodyStart,
                                                      length: bodyEnd - bodyStart))
            blocks.append(parseEqualsProps(body: body))
        }
        return blocks
    }

    private static func parseEqualsProps(body: String) -> [String: Any] {
        var props: [String: Any] = [:]
        var metadata: [String: Any] = [:]

        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard s.hasPrefix("  "), !s.hasPrefix("   ") else { continue }
            let stripped = String(s.dropFirst(2))

            if stripped.hasPrefix("Metadata.") {
                let rest = String(stripped.dropFirst("Metadata.".count))
                if let (key, val) = parseEqualsLine(rest) {
                    metadata[key] = val
                }
                continue
            }
            if stripped.hasPrefix("---") { continue }
            if let (key, val) = parseEqualsLine(stripped) {
                props[key] = val
            }
        }
        if !metadata.isEmpty { props["Metadata"] = metadata }
        return props
    }

    private static func parseEqualsLine(_ stripped: String) -> (String, Any)? {
        guard let eqRange = stripped.range(of: " = ") else { return nil }
        let key = String(stripped[..<eqRange.lowerBound])
        let valStr = String(stripped[eqRange.upperBound...])
        if valStr == "(absent)" || valStr == "(redacted)" { return nil }
        if valStr.hasPrefix("<") { return nil }
        if valStr.hasPrefix("{") { return nil }
        if valStr == "true" { return (key, NSNumber(value: true)) }
        if valStr == "false" { return (key, NSNumber(value: false)) }
        if valStr.hasPrefix("\""), valStr.hasSuffix("\""), valStr.count >= 2 {
            return (key, String(valStr.dropFirst().dropLast()))
        }
        if let n = matchInt(valStr) { return (key, NSNumber(value: n)) }
        return nil
    }

    private static func matchInt(_ s: String) -> Int? {
        if let spaceIdx = s.firstIndex(of: " ") {
            if let v = Int(s[..<spaceIdx]) { return v }
        }
        return Int(s)
    }

    // MARK: - Model builder

    /// Parse a single props dict (one probe-33 block) into a
    /// `DisplayPortTransportWatcher.DisplayPortUpdate` using the same static
    /// parse function the live watcher uses.
    private static func makeUpdate(props: [String: Any],
                                   id: UInt64) -> DisplayPortTransportWatcher.DisplayPortUpdate? {
        let read: (String) -> Any? = { props[$0] }
        return DisplayPortTransportWatcher.makeUpdate(
            entryID: id,
            read: read,
            portIndex: 0,
            portType: "USB-C",
            hpmControllerUUID: nil
        )
    }

    /// Pull the first active block from a probe-33 text and build a model.
    /// Returns nil when the file is absent (fresh clone) or has no active block.
    private static func firstActiveDP(folder: String,
                                      blockOffset: Int = 0) -> IOPortTransportStateDisplayPort? {
        guard let text = loadProbe33(folder: folder) else { return nil }
        let blocks = parseDPNode33Blocks(text: text)
        var activeCount = 0
        for (i, props) in blocks.enumerated() {
            guard (props["Active"] as? NSNumber)?.boolValue == true else { continue }
            if activeCount < blockOffset {
                activeCount += 1
                continue
            }
            return makeUpdate(props: props, id: UInt64(i))?.status
        }
        return nil
    }

    // MARK: - Helper: EDID hex extraction
    //
    // Probe 33 stores EDID as `Metadata.EDID = <N bytes serial-redacted> HEX...`
    // We strip the `<...>` prefix and decode the hex to pass real EDID bytes to
    // `DisplayDiagnostic(dp:)`. This exercises the production EDID-parse path.
    //
    // Note: the "serial-redacted" prefix marks that the serial-number bytes
    // within the EDID were zeroed before storage, for privacy. The monitor name,
    // timings, and range-limits are intact.

    /// Pull EDID hex directly from the raw probe text (bypasses parseEqualsLine's
    /// `<...>` skip rule, which correctly rejects opaque binary but misses the
    /// serial-redacted EDID format that is hex after the prefix).
    private static func edidDataFromText(folder: String,
                                         blockOffset: Int = 0) -> Data? {
        guard let text = loadProbe33(folder: folder) else { return nil }
        let blocks = text.components(separatedBy: "=== DisplayPort node")
        var activeCount = 0
        for block in blocks.dropFirst() {
            guard block.contains("Active = true") else { continue }
            if activeCount < blockOffset {
                activeCount += 1
                continue
            }
            // Match: `  Metadata.EDID = <N bytes serial-redacted> HEX`
            if let range = block.range(of: "Metadata.EDID = "),
               let lineEnd = block[range.upperBound...].firstIndex(of: "\n") {
                let rest = String(block[range.upperBound..<lineEnd])
                // Strip `<N bytes serial-redacted> ` prefix
                if let anglEnd = rest.range(of: "> ") {
                    let hexStr = String(rest[anglEnd.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    return hexFromString(hexStr)
                }
            }
            break
        }
        return nil
    }

    private static func hexFromString(_ s: String) -> Data? {
        let hex = s.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let byte = UInt8(hex[i..<j], radix: 16) else { return nil }
            data.append(byte)
            i = j
        }
        return data.isEmpty ? nil : data
    }

    // MARK: - Helper: 4:2:0-only entries

    /// A CTA VIC from the YCbCr 4:2:0 Video Data Block: a mode the panel
    /// supports at 4:2:0 only.
    private static func isYCbCr420Only(_ mode: EDIDMode) -> Bool {
        if case .ctaVIC(_, _, _, true) = mode.source { return true }
        return false
    }

    /// The highest declared entry the panel supports in full colour, by the
    /// chain `EDIDInfo.topMode` uses (pixel clock, then area, then refresh,
    /// then list order), written out here so the sweep does not lean on the
    /// code it checks.
    private static func fullColourTop(of edid: EDIDInfo) -> EDIDMode? {
        var best: EDIDMode? = nil
        for candidate in edid.modes where !isYCbCr420Only(candidate) {
            guard candidate.width > 0, candidate.height > 0, candidate.hTotal > 0, candidate.vTotal > 0 else { continue }
            guard let current = best else { best = candidate; continue }
            if candidate.pixelClockHz != current.pixelClockHz {
                if candidate.pixelClockHz > current.pixelClockHz { best = candidate }
                continue
            }
            let candidateArea = candidate.width * candidate.height
            let currentArea = current.width * current.height
            if candidateArea != currentArea {
                if candidateArea > currentArea { best = candidate }
                continue
            }
            if candidate.refreshHz > current.refreshHz { best = candidate }
        }
        return best
    }

    // MARK: - Individual machine tests

    // MARK: m4max_macos26.5.1_b -- Dell U4320Q on the M4 Max MBP's native HDMI port, HBR3 4/4 lanes
    //
    // Ground truth (probe 33):
    //   Monitor: DELL U4320Q (4K 43", 3840x2160 preferred)
    //   Link: 4 of 4 lanes, 8.1 Gbps (HBR3), tunneled=false
    //   ParentPortType=6, ParentPortTypeDescription="HDMI", ParentPortNumber=1
    //     (the SoC's native HDMI port, not a CalDigit TS4 dock as an earlier
    //     comment guessed; issue #352)
    //   BranchDeviceID: "pHDMIg" (the Mac's internal HDMI bridge)
    //   DFPType: absent at top level; Metadata.DFP Type Description = "HDMI"
    //   EDID: preferred 3840x2160@60Hz, max_pclk=600 MHz
    //   Bandwidth: needed=14.4 Gbps, delivered=4*8.1*0.8=25.92 Gbps --> .fine
    //   sinkType MUST be nil here: the SoC drives HDMI directly, so there
    //   is no USB-C-to-HDMI adapter to blame (issue #352).

    @Test("m4max_macos26.5.1_b: Dell U4320Q on native HDMI port at HBR3 4-lane -- verdict fine, no adapter blame")
    func m4maxDellU4320Q() throws {
        guard let dp = Self.firstActiveDP(folder: "m4max_macos26.5.1_b") else { return }
        guard let edid = Self.edidDataFromText(folder: "m4max_macos26.5.1_b") else { return }

        let diag = try #require(DisplayDiagnostic(dp: dp, edid: EDIDInfo(edid)))
        // Dell U4320Q 4K: preferred 3840x2160@60 with max_pclk 600MHz.
        // 4x8.1x0.8=25.92 Gbps > 14.4 Gbps needed --> .fine.
        #expect(diag.bottleneck == .fine, "Dell U4320Q at HBR3 4-lane should be fine, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        // Sanity: the link numbers round-tripped correctly.
        #expect(diag.facts.lanes == 4)
        #expect(diag.facts.maxLanes == 4)
        #expect(diag.facts.rateDescription == "8.1 Gbps (HBR3)")
        // Issue #352: this is the M4 Max MBP's *native* HDMI port (probe has
        // ParentPortType=6, ParentPortTypeDescription="HDMI", ParentPortNumber=1),
        // not a CalDigit TS4 path as the earlier comment guessed. There's no
        // adapter on the chain; the SoC drives HDMI directly. So sinkType must
        // stay nil here so the verdict can't blame an adapter and so the DSC
        // carve-out is reachable for marginal-link cases.
        #expect(diag.facts.sinkType == nil)
        // branchDevice label: "pHDMIg" doesn't start with "Dp", so it passes through as-is.
        #expect(diag.facts.branchDevice == "pHDMIg")
    }

    // MARK: m2pro_macos26.6 -- AORUS FO32U2P 4K240, HBR3 4/4 lanes, direct DP
    //
    // Ground truth:
    //   Monitor: AORUS FO32U2P (4K 240Hz gaming monitor)
    //   Link: 4 of 4 lanes, 8.1 Gbps (HBR3), tunneled=false
    //   DFPType: absent, BranchDeviceID: absent
    //   EDID: preferred 3840x2160@60, 0xFD envelope 2340 MHz / 240 Hz. The
    //     panel's 240 Hz modes live in a DisplayID 1.2 extension block (Type I
    //     timings), now parsed: highest detailed timing is 3840x2160@240 at
    //     2291.12 MHz, needing about 55.0 Gbps uncompressed.
    //   Bandwidth: needed=55.0 Gbps, delivered=25.92 Gbps (4 lanes, HBR3) --
    //     every lane at the high rate, short of the uncompressed top mode
    //
    // Issue #596 changed this expectation once already, and the reason is
    // worth keeping. The verdict used to be .compressionPlausible because the
    // 0xFD range-limits envelope stood in for the top mode, and for this
    // panel the envelope happened to be right. It is not a mode, though: the
    // same substitution told an AOC U24P10R it could run a 75 Hz it has no
    // mode for, and claimed 60 Gbps for an ASUS PG27AQDP whose real top
    // timing needs 6. So the diagnostic reads modes only.
    //
    // Before DisplayID timings were parsed, the FO32U2P's 240 Hz modes were
    // invisible to the EDID parser, so from the EDID alone this panel looked
    // like a 4K60 and the verdict was .unknownMode (the envelope, at 4.39x
    // the only mode then readable, was too far off to trust). Now the real
    // 3840x2160@240 timing is read directly from the DisplayID block, so the
    // diagnostic has a genuine top mode again and reaches the DisplayPort
    // ceiling branch: every lane at HBR3, no CoreGraphics live mode to
    // confirm it, so `.compressionPlausible`, the same non-accusatory verdict
    // issue #246 introduced. `corpusEDIDCompressionPlausible` in
    // DisplayDiagnosticTests covers the same EDID WITH a CoreGraphics max
    // mode and reaches the same verdict.

    @Test("m2pro_macos26.6: AORUS FO32U2P's DisplayID top mode reaches the DisplayPort ceiling")
    func m2proDellFO32U2P() throws {
        guard let dp = Self.firstActiveDP(folder: "m2pro_macos26.6") else { return }
        guard let edid = Self.edidDataFromText(folder: "m2pro_macos26.6") else { return }

        let diag = try #require(DisplayDiagnostic(dp: dp, edid: EDIDInfo(edid)))
        #expect(diag.bottleneck == .compressionPlausible,
            "FO32U2P's DisplayID top mode (3840x2160@240) now parses; every lane is at HBR3 with no live mode to confirm it, got \(diag.bottleneck)")
        #expect(diag.isWarning == false,
            "this path must never warn: we have no evidence the link is short of anything")
        #expect(diag.facts.maxMode == nil, "guard: probe 33 carries no CoreGraphics data")
        #expect(diag.facts.lanes == 4)
        #expect(diag.facts.rateDescription == "8.1 Gbps (HBR3)")
        // m2pro_macos26.6 probe 33 has no DFP Type Description at all (direct native DP).
        #expect(diag.facts.sinkType == nil, "No DFP adapter in the chain")
        // Monitor name must parse from the real EDID.
        #expect(diag.facts.monitorName == "AORUS FO32U2P")
        // A real mode is being compared now, not the envelope: needed bandwidth
        // for 3840x2160@240 sits well above the 25.92 Gbps this link delivers.
        let needed = try #require(diag.facts.neededGbps)
        #expect(needed > 25.92)
        #expect(diag.facts.maxRefreshHz == 240)
    }

    // MARK: m1_macos26.5_m -- Dell U3425WE ultrawide, HBR3 4/4 lanes, direct DP
    //
    // Ground truth:
    //   Monitor: DELL U3425WE (3440x1440 WQHD ultrawide, up to 120Hz)
    //   Link: 4 of 4 lanes, 8.1 Gbps (HBR3), tunneled=false
    //   EDID: preferred 3440x1440@60, max_pclk=670 MHz
    //   Bandwidth: needed=16.08 Gbps, delivered=25.92 Gbps --> .fine
    //   Cable exoneration: link is already fine (no shortfall to attribute).

    @Test("m1_macos26.5_m: Dell U3425WE ultrawide at HBR3 4-lane -- verdict fine")
    func m1DellU3425WE() throws {
        guard let dp = Self.firstActiveDP(folder: "m1_macos26.5_m") else { return }
        guard let edid = Self.edidDataFromText(folder: "m1_macos26.5_m") else { return }

        let diag = try #require(DisplayDiagnostic(dp: dp, edid: EDIDInfo(edid)))
        // 4x8.1x0.8=25.92 delivered > 16.08 needed at 120Hz max --> .fine.
        #expect(diag.bottleneck == .fine, "U3425WE at HBR3 4-lane should be fine, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        #expect(diag.facts.lanes == 4)
        // Monitor name from EDID.
        #expect(diag.facts.monitorName == "DELL U3425WE")
    }

    // MARK: m1_macos26.5_p -- Lenovo P24h-20, HBR2 2/2 lanes, BranchDeviceID=Dp1.2 (dock)
    //
    // Ground truth:
    //   Monitor: LEN P24h-20 (2560x1440 IPS, max 75Hz)
    //   Link: 2 of 2 lanes, 5.4 Gbps (HBR2), tunneled=false
    //   BranchDeviceID: "Dp1.2" (Lenovo dock reporting DisplayPort 1.2)
    //   DFPType: absent (so NO adapterLimit -- "Dp1.2" is a DP hub, not HDMI/DVI/VGA)
    //   EDID: preferred 2560x1440@60, max_pclk=300 MHz (75Hz)
    //   Bandwidth: needed=7.2 Gbps, delivered=2x5.4x0.8=8.64 Gbps --> .fine
    //   The link is NOT at the DP ceiling (2 lanes < HBR3 threshold, but it delivers
    //   enough for 75Hz). branchDevice label normalises to "DisplayPort 1.2".

    @Test("m1_macos26.5_p: Lenovo P24h-20 via Dp1.2 dock at HBR2 2-lane -- verdict fine, branchDevice normalised")
    func m1LenovoP24h20() throws {
        guard let dp = Self.firstActiveDP(folder: "m1_macos26.5_p") else { return }
        guard let edid = Self.edidDataFromText(folder: "m1_macos26.5_p") else { return }

        let diag = try #require(DisplayDiagnostic(dp: dp, edid: EDIDInfo(edid)))
        // 2x5.4x0.8=8.64 Gbps > 7.2 Gbps needed --> .fine.
        #expect(diag.bottleneck == .fine, "P24h-20 at HBR2 2-lane delivers enough for 75Hz, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        // "Dp1.2" normalises to "DisplayPort 1.2" via branchDeviceLabel.
        #expect(diag.facts.branchDevice == "DisplayPort 1.2",
            "BranchDeviceID 'Dp1.2' must normalise to 'DisplayPort 1.2', got \(diag.facts.branchDevice ?? "nil")")
        // Lenovo P24h-20: DFP Type Description = "DP" (not HDMI/DVI/VGA), so sinkType is nil.
        #expect(diag.facts.sinkType == nil)
        #expect(diag.facts.lanes == 2)
        #expect(diag.facts.maxLanes == 2)
        #expect(diag.facts.monitorName == "LEN P24h-20")
    }

    // MARK: m2max_macos26.5.1 -- Apple Studio Display, HBR2 4/4 lanes, tunneled
    //
    // Ground truth:
    //   Monitor: Apple Studio Display (5K -- but EDID reports 3840x2160@60 preferred,
    //   no range-limits descriptor, max_pclk from DTD scan gives ~533 MHz)
    //   Link: 4 of 4 lanes, 5.4 Gbps (HBR2), tunneled=true
    //   Bandwidth: needed ~12.7 Gbps (from preferred DTD pclk 533 MHz), delivered=17.28 Gbps --> .fine
    //   Cable exonerated: tunneled=true.
    //   Note: the Studio Display's EDID describes 3840x2160 even though the panel is 5K;
    //   the EDID under-reports the native mode. Without a CoreGraphics live mode
    //   (not in probe data), the diagnostic works with what the EDID says.

    @Test("m2max_macos26.5.1: Apple Studio Display tunneled 4-lane HBR2 -- verdict fine, cable exonerated")
    func m2maxStudioDisplay() throws {
        guard let dp = Self.firstActiveDP(folder: "m2max_macos26.5.1", blockOffset: 1) else { return }
        guard let edid = Self.edidDataFromText(folder: "m2max_macos26.5.1", blockOffset: 1) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        // 4x5.4x0.8=17.28 Gbps delivered > ~12.7 Gbps needed for the EDID-described mode.
        #expect(diag.bottleneck == .fine, "Studio Display tunneled should be fine, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        #expect(diag.cableAssessment == .unlikelyTheCable,
            "Tunneled link must exonerate the cable")
        #expect(diag.facts.lanes == 4)
        #expect(dp.link.tunneled == true)
        // Monitor name from the EDID.
        #expect(diag.facts.monitorName == "StudioDisplay")
    }

    // MARK: m3max_macos26.5_f block 1 -- Apple Studio Display (second machine, tunneled HBR2 4/4)
    //
    // The EDID declares the panel's real 5120x2880@60 twice: as a DisplayID
    // Type I timing in block 3 (936 MHz) and, through the tiled topology in
    // block 2 (2 x 1 tiles of 2560x2880) applied to the CTA DTD 4 tile mode
    // in block 1 (482.4 MHz), as a composite at 2 x 482.4 = 964.8 MHz. The
    // composite has the higher clock, so it is the declared top (about 23.16
    // Gbps at 24 bpp). The link is a tunnelled HBR2 4/4 (17.28 Gbps
    // delivered); probe 33 carries no CoreGraphics data, so the DSC-active
    // check cannot run; so on replay the verdict is the link-limited one, with
    // the cable exonerated by the tunnel. The old .fine was right only because
    // the parser under-read the panel as 4K60. The live app usually has
    // CoreGraphics data, which reaches the DSC path instead.

    @Test("m3max_macos26.5_f: Studio Display's DisplayID top mode exceeds the tunnelled link, cable still exonerated")
    func m3maxStudioDisplay() throws {
        guard let dp = Self.firstActiveDP(folder: "m3max_macos26.5_f", blockOffset: 0) else { return }
        guard let edid = Self.edidDataFromText(folder: "m3max_macos26.5_f", blockOffset: 0) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.bottleneck == .belowMonitorMax,
            "Studio Display's real 5120x2880@60 mode now parses and exceeds the tunnelled link, got \(diag.bottleneck)")
        #expect(diag.isWarning == true)
        #expect(diag.cableAssessment == .unlikelyTheCable, "Tunneled must exonerate cable")
        #expect(diag.facts.monitorName == "StudioDisplay")
        #expect(diag.facts.maxRefreshHz == 60)
        #expect(diag.facts.topModeWidth == 5120)
        #expect(diag.facts.topModeSource == "tiled composite of 2 tiles",
            "got \(String(describing: diag.facts.topModeSource))")
        let needed = try #require(diag.facts.neededGbps)
        #expect(needed > 17.28)
        #expect(abs(needed - 964_800_000.0 * 24 / 1e9) < 1e-9, "expected the composite's 964.8 MHz x 24bpp, got \(needed)")
    }

    // MARK: m3max_macos26.5_f block 2 -- Dell S2725QC, HBR3 4/4 lanes, direct DP
    //
    // Ground truth (second active block on the same machine):
    //   Monitor: DELL S2725QC (4K 27", up to 120Hz)
    //   Link: 4 of 4 lanes, 8.1 Gbps (HBR3), tunneled=false
    //   EDID: preferred 3840x2160@60, 0xFD envelope 1190 MHz / 120 Hz. The
    //     panel's 120 Hz mode lives in a DisplayID 1.2 extension block (Type I
    //     timings), now parsed: highest detailed timing is 3840x2160@120 at
    //     1188.0 MHz, needing about 28.5 Gbps uncompressed.
    //   Bandwidth: needed=28.5 Gbps, delivered=25.92 Gbps (4 lanes, HBR3) --
    //     every lane at the high rate, short of the uncompressed top mode
    //
    // Same shape as the FO32U2P case above, same reason: before DisplayID
    // timings were parsed, this panel's 120 Hz mode was invisible to the EDID
    // parser, so corpus replay saw only an understated 4K60 and the verdict
    // was .unknownMode (the 1190 MHz envelope, at 2.23x that one mode, was
    // too far off to trust). Now the real 3840x2160@120 timing is read
    // directly from the DisplayID block, reaching the DisplayPort ceiling
    // branch: every lane at HBR3, no CoreGraphics live mode to confirm it, so
    // `.compressionPlausible`. The live app path usually has the
    // CoreGraphics top mode and never reaches this branch.

    @Test("m3max_macos26.5_f: Dell S2725QC's DisplayID top mode reaches the DisplayPort ceiling")
    func m3maxDellS2725QC() throws {
        guard let dp = Self.firstActiveDP(folder: "m3max_macos26.5_f", blockOffset: 1) else { return }
        guard let edid = Self.edidDataFromText(folder: "m3max_macos26.5_f", blockOffset: 1) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.bottleneck == .compressionPlausible,
            "S2725QC's DisplayID top mode (3840x2160@120) now parses; every lane is at HBR3 with no live mode to confirm it, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        #expect(diag.facts.maxMode == nil, "guard: probe 33 carries no CoreGraphics data")
        #expect(diag.facts.lanes == 4)
        #expect(diag.facts.rateDescription == "8.1 Gbps (HBR3)")
        #expect(diag.facts.monitorName == "DELL S2725QC")
        #expect(diag.facts.maxRefreshHz == 120)
    }

    // MARK: m2max_macos15.7.1 -- two identical Dell U2790B panels on one tunnel
    //
    // Ground truth (probe 33, blocks 1 and 2, both active):
    //   Monitors: two DELL U2790B (4K 27" 60Hz), same model on the same dock
    //   Block 1: 4 of 4 lanes, 5.4 Gbps (HBR2), tunneled=true --> carries 4K60
    //   Block 2 (the one under test): 2 of 4 lanes, same rate, tunneled=true
    //   EDID (both): top declared timing 3840x2160@60 at 533.25 MHz; the 0xFD
    //     envelope (600 MHz / 80 Hz) is a range, not a mode, and is never read
    //   Bandwidth: needed=12.80 Gbps, delivered=2x5.4x0.8=8.64 Gbps
    //   NOT at ceiling (2 of 4 lanes, and HBR2 per-lane < 8.0)
    //
    // This is the key "tunneled but still belowMonitorMax" case: the cable is
    // exonerated on the tunnel evidence, but the link itself is genuinely
    // carrying less than the monitor's own declared mode.
    //
    // It is also the corpus's copy of issue #596's reporter: two identical
    // panels behind a hub, which is exactly the shape that leaves the live app
    // with no CoreGraphics top mode (`DisplayModeReader.match` fails closed
    // when two displays share an EDID identity). The declared list alone
    // drives the verdict, so the shortfall stands.
    //
    // (It replaces an m2pro_macos26.5_c test that asked for a second active
    // block in a folder with only one, so `firstActiveDP` returned nil and the
    // body never ran. Issue #596 task 3.)

    @Test("m2max_macos15.7.1: second Dell U2790B on 2 of 4 tunneled lanes -- belowMonitorMax, cable exonerated via tunnel")
    func m2maxDellU2790BSecondPanel() throws {
        guard let dp = Self.firstActiveDP(folder: "m2max_macos15.7.1", blockOffset: 1) else { return }
        guard let edid = Self.edidDataFromText(folder: "m2max_macos15.7.1", blockOffset: 1) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.facts.lanes == 2, "fixture guard: this is the 2-lane panel, not its 4-lane twin")
        #expect(diag.facts.maxLanes == 4)
        #expect(diag.bottleneck == .belowMonitorMax,
            "U2790B on half its lanes should be belowMonitorMax, got \(diag.bottleneck)")
        #expect(diag.isWarning == true)
        // The tunnel proves the cable isn't the bottleneck.
        #expect(diag.cableAssessment == .unlikelyTheCable,
            "Tunneled link must exonerate cable even when verdict is belowMonitorMax")
        #expect(diag.detail.lowercased().contains("tunnel"),
            "Detail must mention tunnel for the cable-exoneration wording")
        #expect(diag.detail.lowercased().contains("unlikely to be the cable"),
            "Detail must say cable is unlikely the cause when tunneled")
        #expect(diag.facts.monitorName == "U2790B")
        #expect(diag.facts.maxRefreshHz == 60)
        #expect(!diag.detail.contains("80"), "the 80Hz scan ceiling must never reach the user as a mode")
    }

    // MARK: m1_macos26.5_o -- MSI MP273 FHD, HBR3 2/2 lanes, direct DP
    //
    // Ground truth:
    //   Monitor: MSI MP273 (1920x1080 FHD, max 75Hz)
    //   Link: 2 of 2 lanes, 8.1 Gbps (HBR3), tunneled=false
    //   EDID: preferred 1920x1080@60, max_pclk=180 MHz (75Hz)
    //   Bandwidth: needed=4.32 Gbps, delivered=2x8.1x0.8=12.96 Gbps --> .fine
    //   Note: this is 2 of 2 lanes at HBR3. maxLanes=2 (M1's single-port
    //   alt-mode exposes 2 lanes). The link delivers enough; verdict is .fine.
    //   (No ceiling guard fires: lanes==maxLanes and perLane>=8.0, but needed<delivered,
    //   so the .fine check triggers before the ceiling check.)

    @Test("m1_macos26.5_o: MSI MP273 FHD at HBR3 2-lane -- verdict fine (all lanes in use)")
    func m1MSI_MP273() throws {
        guard let dp = Self.firstActiveDP(folder: "m1_macos26.5_o") else { return }
        guard let edid = Self.edidDataFromText(folder: "m1_macos26.5_o") else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        // 2x8.1x0.8=12.96 Gbps > 4.32 Gbps needed --> .fine.
        #expect(diag.bottleneck == .fine, "MSI MP273 at HBR3 2-lane should be fine, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        #expect(diag.facts.lanes == 2)
        #expect(diag.facts.maxLanes == 2)
        #expect(diag.facts.monitorName == "MSI MP273")
    }

    // MARK: m2ultra_macos26.5 block 0 -- Dell P2219H FHD on the M2 Ultra Mac Studio's native HDMI port
    //
    // Ground truth (probe 33):
    //   Monitor: DELL P2219H (1920x1080 FHD, max 76Hz)
    //   Link: 4 of 4 lanes, 8.1 Gbps (HBR3), tunneled=false
    //   ParentPortType=6, ParentPortTypeDescription="HDMI", ParentPortNumber=2
    //     (the Mac Studio's native HDMI socket, issue #352)
    //   BranchDeviceID: "pHDMIg"; DFPType absent at top level
    //   EDID: preferred 1920x1080@60, max_pclk=170 MHz (76Hz)
    //   Bandwidth: needed=4.08 Gbps, delivered=25.92 Gbps --> .fine
    //   sinkType MUST be nil here: same reasoning as the m4max case above.

    @Test("m2ultra_macos26.5: Dell P2219H on native HDMI port at HBR3 4-lane -- verdict fine, no adapter blame")
    func m2ultraDellP2219H() throws {
        guard let dp = Self.firstActiveDP(folder: "m2ultra_macos26.5", blockOffset: 0) else { return }
        guard let edid = Self.edidDataFromText(folder: "m2ultra_macos26.5", blockOffset: 0) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        // 4x8.1x0.8=25.92 Gbps > 4.08 Gbps needed --> .fine
        #expect(diag.bottleneck == .fine, "Dell P2219H at HBR3 should be fine, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        // Issue #352: M2 Ultra Mac Studio's native HDMI port (probe has
        // ParentPortType=6, ParentPortTypeDescription="HDMI", ParentPortNumber=2).
        // sinkType stays nil on the native HDMI path so the diagnostic can't
        // wrongly blame a USB-C-to-HDMI adapter that isn't there.
        #expect(diag.facts.sinkType == nil)
        #expect(diag.facts.branchDevice == "pHDMIg")
        #expect(diag.facts.monitorName == "DELL P2219H")
    }

    // MARK: m2ultra_macos26.5 block 1 -- Samsung U28H75x 4K, HBR2 4/4 lanes, direct DP
    //
    // Ground truth:
    //   Monitor: Samsung U28H75x (3840x2160 4K 28", max 75Hz)
    //   Link: 4 of 4 lanes, 5.4 Gbps (HBR2), tunneled=false
    //   EDID: preferred 3840x2160@60, max_pclk=600 MHz
    //   Bandwidth: needed=14.4 Gbps, delivered=4x5.4x0.8=17.28 Gbps --> .fine
    //   (This is the second display on the same M2 Ultra machine.)

    @Test("m2ultra_macos26.5: Samsung U28H75x 4K at HBR2 4-lane -- verdict fine (second display)")
    func m2ultraSamsungU28H75x() throws {
        guard let dp = Self.firstActiveDP(folder: "m2ultra_macos26.5", blockOffset: 1) else { return }
        guard let edid = Self.edidDataFromText(folder: "m2ultra_macos26.5", blockOffset: 1) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        // 4x5.4x0.8=17.28 Gbps > 14.4 Gbps needed --> .fine.
        #expect(diag.bottleneck == .fine, "Samsung U28H75x 4K at HBR2 should be fine, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        #expect(diag.facts.lanes == 4)
        #expect(diag.facts.monitorName == "U28H75x")
    }

    // MARK: - Sweep: no active block silently returns nil

    @Test("Sweep: inactive DP blocks must not produce a diagnostic (active=false guard)")
    func inactiveBlocksProduceNoDiagnostic() {
        // Confirm that the `guard dp.link.active else { return nil }` in
        // DisplayDiagnostic.init fires correctly on real corpus data.
        // We sample all inactive blocks from our fixture machines and confirm nil.
        let machines = [
            "m4max_macos26.5.1_b", "m2pro_macos26.6", "m1_macos26.5_m",
            "m1_macos26.5_p", "m2max_macos26.5.1", "m3max_macos26.5_f",
            "m2pro_macos26.5_c", "m1_macos26.5_o", "m2ultra_macos26.5",
        ]
        var inactiveChecked = 0
        for folder in machines {
            guard let text = Self.loadProbe33(folder: folder) else { continue }
            let blocks = Self.parseDPNode33Blocks(text: text)
            for (i, props) in blocks.enumerated() {
                guard (props["Active"] as? NSNumber)?.boolValue == false else { continue }
                guard let update = Self.makeUpdate(props: props, id: UInt64(i)) else { continue }
                let dp = update.status
                // An inactive block must produce nil from DisplayDiagnostic.
                let diag = DisplayDiagnostic(dp: dp, edid: nil)
                #expect(diag == nil,
                    "Inactive DP block in \(folder) must yield nil diagnostic, but got non-nil")
                inactiveChecked += 1
            }
        }
        // Guard: at least some inactive blocks were checked (confirms the test ran).
        // Most machines have 1-3 inactive ports. If the files are absent (fresh clone),
        // inactiveChecked stays 0 and we skip the guard.
        if inactiveChecked > 0 {
            #expect(inactiveChecked >= 3,
                "Expected to check at least 3 inactive blocks across fixture machines; got \(inactiveChecked)")
        }
    }

    // MARK: - Sweep: BuiltInDisplayPort grouping over the real corpus (issue #352)

    /// Walk every probe-33 folder, parse each block through the same
    /// `makeUpdate` path the live watcher uses, and feed the resulting
    /// statuses to `BuiltInDisplayPort.group`. Any folder whose probe text
    /// contains `ParentPortTypeDescription = "HDMI"` for an active block
    /// MUST yield at least one `BuiltInDisplayPort` after grouping. Any
    /// folder with only USB-C / tunnelled parents MUST yield zero.
    ///
    /// This catches a class of bug where the grouping function gates on a
    /// field that isn't actually emitted by IOKit. The earlier draft used
    /// `parentPortBuiltIn` as a guard; 0 of 79 corpus HDMI blocks emit
    /// that field, so the feature would have shipped dead despite all
    /// synthesized unit tests passing.
    @Test("Sweep: BuiltInDisplayPort.group surfaces every native HDMI port in the corpus")
    func sweepBuiltInDisplayPortGrouping() throws {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: Self.probeRoot.path) else {
            return // fresh clone, corpus not synced; skip
        }
        var foldersWithProbe33 = 0
        var foldersWithHDMI = 0
        var foldersGroupedAsHDMI = 0
        var foldersOnlyUSBC = 0
        var foldersGroupedAsUSBC = 0
        for folder in folders {
            guard let text = Self.loadProbe33(folder: folder) else { continue }
            foldersWithProbe33 += 1
            let blocks = Self.parseDPNode33Blocks(text: text)
            // Build the live model the same way the watcher does.
            let statuses = blocks.enumerated().compactMap { i, props in
                Self.makeUpdate(props: props, id: UInt64(i))?.status
            }
            let groups = BuiltInDisplayPort.group(from: statuses)

            // Did the raw probe text claim any active HDMI parent?
            let hasActiveHDMI = blocks.contains { props in
                guard (props["Active"] as? NSNumber)?.boolValue == true else { return false }
                guard let type = props["ParentPortTypeDescription"] as? String else { return false }
                guard let tunneled = (props["Tunneled"] as? NSNumber)?.boolValue, !tunneled else { return false }
                return type.uppercased() == "HDMI"
            }
            let hasAnyUSBCOnly = blocks.allSatisfy { props in
                guard (props["Active"] as? NSNumber)?.boolValue == true else { return true }
                let type = (props["ParentPortTypeDescription"] as? String)?.uppercased()
                return type == "USB-C" || type == nil
            } && !hasActiveHDMI

            if hasActiveHDMI {
                foldersWithHDMI += 1
                if !groups.isEmpty {
                    foldersGroupedAsHDMI += 1
                } else {
                    Issue.record("\(folder) has an active HDMI parent in the probe but BuiltInDisplayPort.group returned empty")
                }
            } else if hasAnyUSBCOnly {
                foldersOnlyUSBC += 1
                if groups.isEmpty {
                    foldersGroupedAsUSBC += 1
                } else {
                    Issue.record("\(folder) has only USB-C / tunnelled active parents but BuiltInDisplayPort.group returned \(groups.count) entries")
                }
            }
        }
        // Guard against a silent skip (no corpus on disk in this checkout).
        if foldersWithHDMI > 0 {
            #expect(foldersGroupedAsHDMI == foldersWithHDMI,
                "Expected every folder with an HDMI parent (\(foldersWithHDMI)) to surface in grouping, got \(foldersGroupedAsHDMI)")
        }
        if foldersOnlyUSBC > 0 {
            #expect(foldersGroupedAsUSBC == foldersOnlyUSBC,
                "Expected every USB-C-only folder (\(foldersOnlyUSBC)) to yield no HDMI groups, got \(foldersOnlyUSBC - foldersGroupedAsUSBC) leaks")
        }
        // Floor: at minimum N HDMI-bearing folders must be in the sweep so
        // a future corpus that lost most of them (selective re-fetch, partial
        // sync) doesn't silently degrade this into a near-vacuous check.
        // Actual 23 such folders as of 2026-07 (up from 14). Native-HDMI is a
        // narrow, curated signal (only ~5-6% of the 410-folder corpus), so
        // unlike the broader per-probe floors elsewhere in this file the
        // usual ~85-90%-of-actual policy would leave almost no slack for
        // routine dedup/curation churn; 15 (~65% of actual, 3x the old stale
        // floor of 5) still catches a real regression without that risk.
        //
        // Two-tier reality: only 9 probe-33 files are git-tracked (the named
        // fixtures the other two tests in this file use directly), out of
        // ~240 with probe 33 on disk. Gate on a raw-corpus-presence threshold
        // (50) well above that 9-file fresh-clone case, so a fresh clone
        // SKIPS this floor instead of failing it, while the correctness
        // checks above (`foldersGroupedAsHDMI == foldersWithHDMI`,
        // `foldersGroupedAsUSBC == foldersOnlyUSBC`) keep running against
        // whatever data is present, tracked-only or full corpus alike.
        if foldersWithProbe33 >= 50 {
            #expect(foldersWithHDMI >= 15,
                "Only \(foldersWithHDMI) folder(s) with active HDMI parents found across the corpus; sweep is near-vacuous, restore HDMI fixtures")
        }
    }

    // MARK: - Sweep: every active block with a parseable EDID produces a non-nil diagnostic

    @Test("Sweep: every active block with readable EDID from fixtures produces a diagnostic")
    func allActiveBlocksWithEdidProduceDiagnostic() {
        let machines = [
            "m4max_macos26.5.1_b", "m2pro_macos26.6", "m1_macos26.5_m",
            "m1_macos26.5_p", "m2max_macos26.5.1", "m3max_macos26.5_f",
            "m2pro_macos26.5_c", "m1_macos26.5_o", "m2ultra_macos26.5",
        ]
        var checked = 0
        var withDiag = 0

        for folder in machines {
            guard let text = Self.loadProbe33(folder: folder) else { continue }
            let rawBlocks = text.components(separatedBy: "=== DisplayPort node")
            let parsedBlocks = Self.parseDPNode33Blocks(text: text)

            for (i, props) in parsedBlocks.enumerated() {
                guard (props["Active"] as? NSNumber)?.boolValue == true else { continue }
                guard let update = Self.makeUpdate(props: props, id: UInt64(i)) else { continue }
                let dp = update.status

                // Try to extract EDID from the raw text for this block.
                var edidInfo: EDIDInfo? = nil
                if i + 1 < rawBlocks.count {
                    let rawBlock = rawBlocks[i + 1]
                    if rawBlock.contains("Metadata.EDID = "),
                       let rangeStart = rawBlock.range(of: "Metadata.EDID = "),
                       let lineEnd = rawBlock[rangeStart.upperBound...].firstIndex(of: "\n") {
                        let rest = String(rawBlock[rangeStart.upperBound..<lineEnd])
                        if let anglEnd = rest.range(of: "> ") {
                            let hexStr = String(rest[anglEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
                            if let data = Self.hexFromString(hexStr) {
                                edidInfo = EDIDInfo(data)
                            }
                        }
                    }
                }

                checked += 1
                let diag = DisplayDiagnostic(dp: dp, edid: edidInfo)
                #expect(diag != nil,
                    "Active DP block \(i) in \(folder) must produce a DisplayDiagnostic")
                if diag != nil { withDiag += 1 }
            }
        }

        // Guard: at least 9 active blocks checked (1 per fixture machine minimum).
        if checked > 0 {
            #expect(checked >= 9,
                "Expected at least 9 active DP blocks across fixture machines; got \(checked)")
            #expect(withDiag == checked,
                "Every active block must produce a diagnostic; got \(withDiag)/\(checked)")
        }
    }

    // MARK: - Corpus-level: no .belowMonitorMax warning on any "fine" machine

    @Test("Sweep: none of the fine-verdict fixture machines emits a warning")
    func fineVerdictMachinesDoNotWarn() {
        // These machines are confirmed .fine at their active link state.
        // They must not produce isWarning=true.
        let fineMachines: [(String, Int)] = [
            ("m4max_macos26.5.1_b", 0),  // Dell U4320Q
            ("m1_macos26.5_m", 0),        // Dell U3425WE
            ("m1_macos26.5_p", 0),        // Lenovo P24h-20
            ("m1_macos26.5_o", 0),        // MSI MP273
            ("m2ultra_macos26.5", 1),      // Samsung U28H75x
            ("m2ultra_macos26.5", 0),      // Dell P2219H
        ]

        for (folder, offset) in fineMachines {
            guard let dp = Self.firstActiveDP(folder: folder, blockOffset: offset) else { continue }
            guard let text = Self.loadProbe33(folder: folder) else { continue }

            // Extract EDID for the correct active block.
            var edidData: Data? = nil
            let rawBlocks = text.components(separatedBy: "=== DisplayPort node")
            var activeCount = 0
            for rawBlock in rawBlocks.dropFirst() {
                guard rawBlock.contains("Active = true") else { continue }
                if activeCount < offset {
                    activeCount += 1
                    continue
                }
                if rawBlock.contains("Metadata.EDID = "),
                   let rangeStart = rawBlock.range(of: "Metadata.EDID = "),
                   let lineEnd = rawBlock[rangeStart.upperBound...].firstIndex(of: "\n") {
                    let rest = String(rawBlock[rangeStart.upperBound..<lineEnd])
                    if let anglEnd = rest.range(of: "> ") {
                        let hexStr = String(rest[anglEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
                        edidData = Self.hexFromString(hexStr)
                    }
                }
                break
            }

            guard let data = edidData, let edidInfo = EDIDInfo(data) else { continue }
            guard let diag = DisplayDiagnostic(dp: dp, edid: edidInfo) else { continue }

            #expect(diag.isWarning == false,
                "\(folder) offset=\(offset): expected no warning (fine verdict), got bottleneck=\(diag.bottleneck)")
        }
    }

    // MARK: - Sweep: the five panels whose EDID top is a 4:2:0-only VIC

    /// Five corpus EDIDs put a YCbCr 4:2:0-only CTA VIC at the top of their
    /// declared list on pixel clock (594 MHz). Each is judged against its
    /// highest full-colour entry: the 27C1U-L's own 4K60 DTD, and the 297
    /// MHz 4K30 VIC on the other three. The 4:2:0 entries stay in
    /// `declaredModeCount` and are counted in `declared420OnlyModes`. Before
    /// the change this fails with `.adapterLimit` on three of the five and
    /// needed 14.256 Gbps on all five.
    @Test("Sweep: the five 4:2:0-top panels are judged against their full-colour top")
    func ycbcr420TopPanelsAreJudgedAgainstTheirFullColourTop() throws {
        // folder, active-block offset, monitor name, needed Gbps, top source,
        // top refresh, 4:2:0-only entry count, the named 4:2:0 mode
        // (digits grouped by locale, as `String(localized:)` renders an Int)
        let panels: [(String, Int, String, Double, String, Int, Int, String)] = [
            ("m1max_macos26.5.2_k", 0, "HDMI",       7.128,  "CTA VIC 100 (block 1)",       30, 4, "\(4096.formatted()) × \(2160.formatted()) at 60Hz"),
            ("m1max_macos26.5.2_b", 0, "SyncMaster", 7.128,  "CTA VIC 100 (block 1)",       30, 4, "\(4096.formatted()) × \(2160.formatted()) at 60Hz"),
            ("m4_macos26.5.1_m",    1, "UGREEN",     7.128,  "CTA VIC 95 (block 1)",        30, 2, "\(3840.formatted()) × \(2160.formatted()) at 60Hz"),
            ("m3_macos26.6.2",      0, "27C1U-L",    12.668, "detailed timing 1 (block 0)", 60, 1, "\(3840.formatted()) × \(2160.formatted()) at 60Hz"),
            ("m3_macos26.5_j",      0, "27C1U-L",    12.668, "detailed timing 1 (block 0)", 60, 1, "\(3840.formatted()) × \(2160.formatted()) at 60Hz"),
        ]
        var checked = 0
        for (folder, offset, name, neededGbps, topSource, topRefresh, count420, named420) in panels {
            guard let dp = Self.firstActiveDP(folder: folder, blockOffset: offset),
                  let data = Self.edidDataFromText(folder: folder, blockOffset: offset),
                  let edid = EDIDInfo(data) else { continue }
            checked += 1
            let edidTop = try #require(edid.topMode)
            #expect(edidTop.sourceDescription.contains("4:2:0"),
                "\(folder): fixture guard, the EDID's own top is the 4:2:0 VIC, got \(edidTop.sourceDescription)")
            let diag = try #require(DisplayDiagnostic(dp: dp, edid: edid))
            #expect(diag.facts.monitorName == name)
            #expect(diag.bottleneck == .fine, "\(folder): got \(diag.bottleneck): \(diag.detail)")
            #expect(diag.isWarning == false)
            let needed = try #require(diag.facts.neededGbps, "\(folder): needed is nil")
            #expect(abs(needed - neededGbps) < 0.001, "\(folder): needed \(needed) Gbps, expected \(neededGbps)")
            #expect(diag.facts.topModeSource == topSource,
                "\(folder): top labelled \(String(describing: diag.facts.topModeSource))")
            #expect(diag.facts.maxRefreshHz == topRefresh)
            #expect(diag.facts.declaredModeCount == edid.modes.count)
            #expect(diag.facts.declared420OnlyModes == count420,
                "\(folder): \(diag.facts.declared420OnlyModes) 4:2:0-only entries")
            #expect(diag.detail.contains("Its EDID also lists \(named420) in 4:2:0 only"), "\(folder): \(diag.detail)")
        }
        #expect(checked == 5, "only \(checked) of the five panels could be loaded from the corpus")
    }

    // MARK: - Sweep: needed bandwidth is the declared top mode's clock, nothing else

    /// Walk every probe-33 folder in the corpus -- not the named fixture
    /// machines above, the whole thing -- and assert the property the
    /// diagnostic now guarantees: for every active DisplayPort block whose
    /// EDID parses, the needed bandwidth is exactly the highest FULL-COLOUR
    /// declared entry's pixel clock times bits per pixel, and the top mode
    /// is labelled from that entry. A 4:2:0-only entry (a CTA VIC from the
    /// Y420VDB) is a declared fact that never becomes the comparison mode:
    /// it stays in `declaredModeCount`, is counted in
    /// `declared420OnlyModes`, and the resolved top is never one. Probe 33
    /// carries no CoreGraphics data, so
    /// `resolveTopMode`'s no-max-mode rule applies on every block. A block
    /// with no readable link rate is `.unknownMode` but still carries the
    /// figure, so it is checked too.
    ///
    /// Before this, `needed` could come from the 0xFD range-limits envelope
    /// (a range of accepted signals, not a mode: up to 10x the real top in
    /// this corpus), from a max mode scaled by a blanking ratio, or from a
    /// 1.08 constant, and 15 blocks dropped the figure altogether behind an
    /// envelope-ratio guard. None of those paths exists now, so every block
    /// counts and the equality is exact. Watched red by making the
    /// no-max-mode rule return `preferredMode` instead of `topMode`: every
    /// panel whose declared top is not its preferred mode fails.
    @Test("Sweep: needed bandwidth equals the declared top mode's pixel clock times bits per pixel, across the corpus")
    func neededBandwidthEqualsTheDeclaredTopModesPixelClock() throws {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: Self.probeRoot.path) else {
            return // fresh clone, corpus not synced; skip
        }

        var foldersWithProbe33 = 0
        var evaluated = 0
        var noLinkRate = 0
        var ycbcr420Tops = 0
        let bitsPerPixel = Double(DisplayDiagnostic.assumedBitsPerPixel)

        for folder in folders {
            guard let text = Self.loadProbe33(folder: folder) else { continue }
            foldersWithProbe33 += 1
            let blocks = Self.parseDPNode33Blocks(text: text)
            let rawBlocks = text.components(separatedBy: "=== DisplayPort node")

            for (i, props) in blocks.enumerated() {
                guard (props["Active"] as? NSNumber)?.boolValue == true else { continue }
                guard let update = Self.makeUpdate(props: props, id: UInt64(i)) else { continue }
                let dp = update.status

                guard i + 1 < rawBlocks.count else { continue }
                let rawBlock = rawBlocks[i + 1]
                guard rawBlock.contains("Metadata.EDID = "),
                      let rangeStart = rawBlock.range(of: "Metadata.EDID = "),
                      let lineEnd = rawBlock[rangeStart.upperBound...].firstIndex(of: "\n")
                else { continue }
                let rest = String(rawBlock[rangeStart.upperBound..<lineEnd])
                guard let anglEnd = rest.range(of: "> ") else { continue }
                let hexStr = String(rest[anglEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard let data = Self.hexFromString(hexStr), let edidInfo = EDIDInfo(data) else { continue }
                let edidTop = try #require(edidInfo.topMode, "\(folder) block \(i): a parsed EDID always has a top mode")
                if Self.isYCbCr420Only(edidTop) { ycbcr420Tops += 1 }
                let top = try #require(Self.fullColourTop(of: edidInfo), "\(folder) block \(i): a parsed EDID always has a full-colour top")
                guard let diag = DisplayDiagnostic(dp: dp, edid: edidInfo) else { continue }
                if diag.facts.deliveredGbps == nil { noLinkRate += 1 }

                evaluated += 1
                let expected = Double(top.pixelClockHz) * bitsPerPixel / 1_000_000_000
                let needed = try #require(diag.facts.neededGbps,
                    "\(folder) block \(i): neededGbps is nil on \(diag.bottleneck); with no CoreGraphics data the top mode is always declared")
                #expect(abs(needed - expected) < 1e-9,
                    "\(folder) block \(i): needed \(needed) Gbps is not the declared top's \(expected) Gbps (\(top.sourceDescription))")
                #expect(diag.facts.topModeSource == top.sourceDescription,
                    "\(folder) block \(i): top mode labelled \(String(describing: diag.facts.topModeSource)), declared top is \(top.sourceDescription)")
                #expect(diag.facts.declaredModeCount == edidInfo.modes.count)
                #expect(diag.facts.declared420OnlyModes == edidInfo.modes.filter(Self.isYCbCr420Only).count)
                let resolved = try #require(diag.topMode, "\(folder) block \(i): a declared top always resolves")
                if case .declared(.ctaVIC(_, _, _, true)) = resolved.source {
                    Issue.record("\(folder) block \(i): the verdict was computed against a 4:2:0-only entry")
                }
            }
        }

        // Coverage floor: a corpus directory that exists but yields no
        // probe-33 folders, or one that lost most of its probe-33 files, must
        // not pass silently. Unconditional on purpose: the only SKIP path is
        // the absent directory handled by the early return above, which
        // scripts/ci.sh's corpus-presence check owns. 608 blocks evaluated at
        // the time of writing (593 + the 15 the old envelope guard dropped).
        #expect(evaluated >= 550,
            "Only \(evaluated) blocks evaluated across \(foldersWithProbe33) folders with probe 33; expected at least 550 -- sweep may be near-vacuous")
        #expect(ycbcr420Tops >= 5, "expected the corpus's five 4:2:0-top EDIDs, saw \(ycbcr420Tops)")
        print("neededBandwidthEqualsTheDeclaredTopModesPixelClock: evaluated \(evaluated) blocks (\(noLinkRate) of them with no readable link rate, \(ycbcr420Tops) whose EDID top is 4:2:0-only) across \(foldersWithProbe33) folders")
    }
}
