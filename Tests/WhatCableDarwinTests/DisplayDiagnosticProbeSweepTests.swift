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
// DSC and the top mode's availability are read from macOS's display node
// (probe 26) since issue #664. The tests in this file that load probe 33 alone
// run the no-statement path, so their verdict is `.unknownMode` unless
// CoreGraphics data (absent from a probe) puts the live mode at the top;
// `.compressionActive`, `.fine` and the shortfall verdicts appear only in the
// `-- #664` tests below, which pair probe 26 (Task 10).
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
    //   Verdict: `.unknownMode` on probe 33 alone (issue #664); the
    //   statement-driven verdict for this machine is in the `#664` counts.
    //   sinkType MUST be nil here: the SoC drives HDMI directly, so there
    //   is no USB-C-to-HDMI adapter to blame (issue #352).

    @Test("m4max_macos26.5.1_b: Dell U4320Q on native HDMI port at HBR3 4-lane -- probe 33 alone, no adapter blame")
    func m4maxDellU4320Q() throws {
        guard let dp = Self.firstActiveDP(folder: "m4max_macos26.5.1_b") else { return }
        guard let edid = Self.edidDataFromText(folder: "m4max_macos26.5.1_b") else { return }

        let diag = try #require(DisplayDiagnostic(dp: dp, edid: EDIDInfo(edid)))
        // Dell U4320Q 4K: preferred 3840x2160@60 with max_pclk 600MHz.
        #expect(diag.bottleneck == .unknownMode, "probe 33 alone: no statement, so the top mode's availability cannot be read")
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
    // diagnostic has a genuine top mode again. Since issue #664 the ceiling
    // reads unknown because the statement is absent, not
    // `.compressionPlausible`: probe 33 alone carries no display-node
    // statement, so whether the top mode is offered on this link cannot be
    // read, and the figure is a receipt that decides nothing.
    // `corpusEDIDWithoutStatementIsUnknown` in DisplayDiagnosticTests covers
    // the same EDID WITH a CoreGraphics max mode and reaches the same verdict.

    @Test("m2pro_macos26.6: AORUS FO32U2P's DisplayID top mode parses; probe 33 alone reads unknown")
    func m2proDellFO32U2P() throws {
        guard let dp = Self.firstActiveDP(folder: "m2pro_macos26.6") else { return }
        guard let edid = Self.edidDataFromText(folder: "m2pro_macos26.6") else { return }

        let diag = try #require(DisplayDiagnostic(dp: dp, edid: EDIDInfo(edid)))
        #expect(diag.bottleneck == .unknownMode,
            "FO32U2P's DisplayID top mode (3840x2160@240) now parses; probe 33 alone has no statement to read its availability from, got \(diag.bottleneck)")
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
    //   Verdict: `.unknownMode` on probe 33 alone (issue #664); the
    //   statement-driven verdict for this machine is in the `#664` counts.

    @Test("m1_macos26.5_m: Dell U3425WE ultrawide at HBR3 4-lane -- probe 33 alone")
    func m1DellU3425WE() throws {
        guard let dp = Self.firstActiveDP(folder: "m1_macos26.5_m") else { return }
        guard let edid = Self.edidDataFromText(folder: "m1_macos26.5_m") else { return }

        let diag = try #require(DisplayDiagnostic(dp: dp, edid: EDIDInfo(edid)))
        #expect(diag.bottleneck == .unknownMode, "probe 33 alone: no statement, so the top mode's availability cannot be read")
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
    //   Verdict: `.unknownMode` on probe 33 alone (issue #664); the
    //   statement-driven verdict for this machine is in the `#664` counts.
    //   branchDevice label normalises to "DisplayPort 1.2".

    @Test("m1_macos26.5_p: Lenovo P24h-20 via Dp1.2 dock at HBR2 2-lane -- probe 33 alone, branchDevice normalised")
    func m1LenovoP24h20() throws {
        guard let dp = Self.firstActiveDP(folder: "m1_macos26.5_p") else { return }
        guard let edid = Self.edidDataFromText(folder: "m1_macos26.5_p") else { return }

        let diag = try #require(DisplayDiagnostic(dp: dp, edid: EDIDInfo(edid)))
        #expect(diag.bottleneck == .unknownMode, "probe 33 alone: no statement, so the top mode's availability cannot be read")
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
    //   Verdict: `.unknownMode` on probe 33 alone (issue #664); the
    //   statement-driven verdict for this machine is in the `#664` counts.
    //   Cable exonerated: tunneled=true.
    //   Note: the Studio Display's EDID describes 3840x2160 even though the panel is 5K;
    //   the EDID under-reports the native mode. Without a CoreGraphics live mode
    //   (not in probe data), the diagnostic works with what the EDID says.

    @Test("m2max_macos26.5.1: Apple Studio Display tunneled 4-lane HBR2 -- probe 33 alone, cable exonerated")
    func m2maxStudioDisplay() throws {
        guard let dp = Self.firstActiveDP(folder: "m2max_macos26.5.1", blockOffset: 1) else { return }
        guard let edid = Self.edidDataFromText(folder: "m2max_macos26.5.1", blockOffset: 1) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.bottleneck == .unknownMode, "probe 33 alone: no statement, so the top mode's availability cannot be read")
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
    // Gbps at 24 bpp, a receipt). The link is a tunnelled HBR2 4/4; probe 33
    // carries no display-node statement, so whether the top mode is offered
    // cannot be read and the verdict is `.unknownMode` (issue #664), with the
    // cable exonerated by the tunnel. The statement-driven verdict for this
    // machine is in the `#664` counts.

    @Test("m3max_macos26.5_f: Studio Display's DisplayID top mode parses; probe 33 alone reads unknown, cable still exonerated")
    func m3maxStudioDisplay() throws {
        guard let dp = Self.firstActiveDP(folder: "m3max_macos26.5_f", blockOffset: 0) else { return }
        guard let edid = Self.edidDataFromText(folder: "m3max_macos26.5_f", blockOffset: 0) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.bottleneck == .unknownMode,
            "probe 33 alone: no statement, so the top mode's availability cannot be read, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
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
    // directly from the DisplayID block. Since issue #664 the ceiling reads
    // unknown because the statement is absent, not `.compressionPlausible`:
    // probe 33 alone carries no display-node statement, so whether the top
    // mode is offered on this link cannot be read.

    @Test("m3max_macos26.5_f: Dell S2725QC's DisplayID top mode parses; probe 33 alone reads unknown")
    func m3maxDellS2725QC() throws {
        guard let dp = Self.firstActiveDP(folder: "m3max_macos26.5_f", blockOffset: 1) else { return }
        guard let edid = Self.edidDataFromText(folder: "m3max_macos26.5_f", blockOffset: 1) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.bottleneck == .unknownMode,
            "S2725QC's DisplayID top mode (3840x2160@120) now parses; probe 33 alone has no statement to read its availability from, got \(diag.bottleneck)")
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
    //   Receipt: needed=12.80 Gbps, delivered=2x5.4x0.8=8.64 Gbps (a figure
    //   no verdict branches on since issue #664)
    //
    // The cable is exonerated on the tunnel evidence. Probe 33 alone carries
    // no display-node statement, so whether the top mode is offered on this
    // link cannot be read and the verdict is `.unknownMode` (issue #664); the
    // statement-driven verdict for this machine is in the `#664` counts.
    //
    // It is also the corpus's copy of issue #596's reporter: two identical
    // panels behind a hub, which is exactly the shape that leaves the live app
    // with no CoreGraphics top mode (`DisplayModeReader.match` fails closed
    // when two displays share an EDID identity).
    //
    // (It replaces an m2pro_macos26.5_c test that asked for a second active
    // block in a folder with only one, so `firstActiveDP` returned nil and the
    // body never ran. Issue #596 task 3.)

    @Test("m2max_macos15.7.1: second Dell U2790B on 2 of 4 tunneled lanes -- probe 33 alone reads unknown, cable exonerated via tunnel")
    func m2maxDellU2790BSecondPanel() throws {
        guard let dp = Self.firstActiveDP(folder: "m2max_macos15.7.1", blockOffset: 1) else { return }
        guard let edid = Self.edidDataFromText(folder: "m2max_macos15.7.1", blockOffset: 1) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.facts.lanes == 2, "fixture guard: this is the 2-lane panel, not its 4-lane twin")
        #expect(diag.facts.maxLanes == 4)
        #expect(diag.bottleneck == .unknownMode,
            "probe 33 alone: no statement, so the top mode's availability cannot be read, got \(diag.bottleneck)")
        #expect(diag.isWarning == false)
        // The tunnel proves the cable isn't the bottleneck.
        #expect(diag.cableAssessment == .unlikelyTheCable,
            "Tunneled link must exonerate cable even when the verdict is unknown")
        #expect(diag.detail.contains("could not be matched"))
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
    //   Verdict: `.unknownMode` on probe 33 alone (issue #664); the
    //   statement-driven verdict for this machine is in the `#664` counts.
    //   Note: this is 2 of 2 lanes at HBR3. maxLanes=2 (M1's single-port
    //   alt-mode exposes 2 lanes).

    @Test("m1_macos26.5_o: MSI MP273 FHD at HBR3 2-lane -- probe 33 alone (all lanes in use)")
    func m1MSI_MP273() throws {
        guard let dp = Self.firstActiveDP(folder: "m1_macos26.5_o") else { return }
        guard let edid = Self.edidDataFromText(folder: "m1_macos26.5_o") else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.bottleneck == .unknownMode, "probe 33 alone: no statement, so the top mode's availability cannot be read")
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
    //   Verdict: `.unknownMode` on probe 33 alone (issue #664); the
    //   statement-driven verdict for this machine is in the `#664` counts.
    //   sinkType MUST be nil here: same reasoning as the m4max case above.

    @Test("m2ultra_macos26.5: Dell P2219H on native HDMI port at HBR3 4-lane -- probe 33 alone, no adapter blame")
    func m2ultraDellP2219H() throws {
        guard let dp = Self.firstActiveDP(folder: "m2ultra_macos26.5", blockOffset: 0) else { return }
        guard let edid = Self.edidDataFromText(folder: "m2ultra_macos26.5", blockOffset: 0) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.bottleneck == .unknownMode, "probe 33 alone: no statement, so the top mode's availability cannot be read")
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
    //   Verdict: `.unknownMode` on probe 33 alone (issue #664); the
    //   statement-driven verdict for this machine is in the `#664` counts.
    //   (This is the second display on the same M2 Ultra machine.)

    @Test("m2ultra_macos26.5: Samsung U28H75x 4K at HBR2 4-lane -- probe 33 alone (second display)")
    func m2ultraSamsungU28H75x() throws {
        guard let dp = Self.firstActiveDP(folder: "m2ultra_macos26.5", blockOffset: 1) else { return }
        guard let edid = Self.edidDataFromText(folder: "m2ultra_macos26.5", blockOffset: 1) else { return }

        guard let edidInfo = EDIDInfo(edid) else { return }
        let diag = try #require(DisplayDiagnostic(dp: dp, edid: edidInfo))
        #expect(diag.bottleneck == .unknownMode, "probe 33 alone: no statement, so the top mode's availability cannot be read")
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

    // MARK: - Corpus-level: no warning on any probe-33-only machine

    @Test("Sweep: none of the probe-33-only fixture machines emits a warning")
    func probe33OnlyMachinesDoNotWarn() {
        // Probe 33 alone carries no display-node statement, so these machines
        // read `.unknownMode` (issue #664), and unknown never warns. They must
        // not produce isWarning=true.
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
                "\(folder) offset=\(offset): expected no warning (probe 33 alone reads unknown), got bottleneck=\(diag.bottleneck)")
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
            #expect(diag.bottleneck == .unknownMode, "\(folder): probe 33 alone")
            #expect(diag.isWarning == false)
            let needed = try #require(diag.facts.neededGbps, "\(folder): needed is nil")
            #expect(abs(needed - neededGbps) < 0.001, "\(folder): needed \(needed) Gbps, expected \(neededGbps)")
            #expect(diag.facts.topModeSource == topSource,
                "\(folder): top labelled \(String(describing: diag.facts.topModeSource))")
            #expect(diag.facts.maxRefreshHz == topRefresh)
            #expect(diag.facts.declaredModeCount == edid.modes.count)
            #expect(diag.facts.declared420OnlyModes == count420,
                "\(folder): \(diag.facts.declared420OnlyModes) 4:2:0-only entries")
            #expect(diag.detail.contains("Its EDID also lists \(named420) in 4:2:0 only, a mode macOS does not send over the DisplayPort link."), "\(folder): \(diag.detail)")
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
    ///
    /// Since issue #664 the figure is a receipt and no verdict branches on
    /// it; the equality still holds on every block.
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
        let bitsPerPixel = Double(DisplayDiagnostic.topModeBitsPerPixel)

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

    // MARK: - Issue #664: the verdict reads macOS's statement (probe 26 paired to probe 33)

    /// The one paired display of a folder, or the n-th active block's, run
    /// through the production reader and match, then the diagnostic. nil when
    /// either probe is absent, the node did not match, or the block has no EDID.
    private static func statementDiagnostic(folder: String, block: Int = 0) -> (DisplayDiagnostic, CorpusDisplayProbes.Pairing)? {
        guard let pairing = CorpusDisplayProbes.pairings(folder: folder).first(where: { $0.entry.block == block }),
              let diag = DisplayDiagnostic(dp: pairing.matched, edid: pairing.entry.edid)
        else { return nil }
        return (diag, pairing)
    }

    /// Whether the corpus folder is on disk: the only condition under which an
    /// anchor test may return without asserting. A folder that is present but
    /// does not pair is a failure, never a skip (a green run on no data is
    /// the trap CLAUDE.md names).
    private static func folderOnDisk(_ folder: String) -> Bool {
        FileManager.default.fileExists(atPath: CorpusDisplayProbes.probeRoot.appendingPathComponent(folder).path)
    }

    /// EDID bytes 8-9 equal to 0x0610, read straight off the port's blob so
    /// this sweep does not lean on `MonitorInfo.isAppleDisplay`.
    private static func isAppleEDID(_ port: IOPortTransportStateDisplayPort) -> Bool {
        guard let edid = port.monitor?.edid, edid.count >= 10 else { return false }
        return edid[edid.startIndex + 8] == 0x06 && edid[edid.startIndex + 9] == 0x10
    }

    /// Lanes x per-lane Gbps x 0.8 (8b/10b; every corpus link is RBR to HBR3), written
    /// out here rather than through `DisplayDiagnostic.perLaneGbps` so the sweep does not
    /// lean on the code it checks.
    private static func rawLinkGbps(_ port: IOPortTransportStateDisplayPort) -> Double? {
        guard let description = port.link.linkRateDescription,
              let match = description.range(of: #"^\d+(\.\d+)?"#, options: .regularExpression),
              let perLane = Double(description[match]), port.link.laneCount > 0 else { return nil }
        return Double(port.link.laneCount) * perLane * 0.8
    }

    @Test("#664 anchor m3_macos26.6.2: 27C1U-L behind a DP 1.2 HDMI converter reads uncompressed, fine; the unsafe list names all six modes, resolved to the four non-virtual ones")
    func anchor27C1UL() throws {
        guard Self.folderOnDisk("m3_macos26.6.2") else { return }
        let (diag, pairing) = try #require(Self.statementDiagnostic(folder: "m3_macos26.6.2"), "m3_macos26.6.2 is on disk but did not pair through the production reader and match")
        #expect(pairing.record.node.currentTimingID == 45, "fixture guard: timing 45 is driven")
        let statement = try #require(diag.facts.drivenTiming)
        #expect(statement.colourModesComplete && statement.dscListComplete && statement.unsafeListComplete)
        #expect(statement.dscCapableIDs.isEmpty && statement.dscRequiredIDs.isEmpty, "no mode is DSC-capable, the list is empty")
        #expect(statement.unsafeIDs == [89, 90, 91, 92], "the six-member list, resolved to the four non-virtual modes")
        #expect(statement.validPixelEncodings == 0x1b4d)
        #expect(diag.facts.dscReading == .uncompressed)
        #expect(diag.facts.isAppleDisplay == false)
        #expect(diag.facts.sinkType == "HDMI")
        #expect(diag.facts.branchDevice == "DisplayPort 1.2")
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.isWarning == false)
        #expect(diag.detail.contains("states it is running uncompressed"), Comment(rawValue: diag.detail))
        #expect(!diag.summary.lowercased().contains("may be using compression"))
        let need = try #require(diag.facts.liveNeededGbps)
        #expect(abs(need - 12.6684) < 0.001, "527.85 MHz x 24 (dump A4)")
        let usable = try #require(diag.facts.usableGbpsRange)
        #expect(abs(usable.upperBound - 12.96) < 1e-9 && abs(usable.lowerBound - 12.65625) < 1e-9)
        #expect(diag.facts.statementContradiction == false, "12.668 fits without FEC; the six modes were published, so FEC is off on this DP 1.2 branch (dump A4, INFERRED)")
        #expect(diag.facts.topModeMatch == .exact, "the driven 527.85 MHz DTD is the EDID's top")
        #expect(diag.facts.topModeAvailability == .offeredUncompressed)
        #expect(diag.facts.statementOffersTopMode == true)
        #expect(diag.cableAssessment == .unlikelyTheCable, "2 of 2 lanes on an unknown cable, but macOS lists the top mode on this link (ruling 37)")
        #expect(diag.statementReceipts().contains("macOS rates 4 of 4 colour modes on this timing as above the HDMI adapter's TMDS rate limit."), "\(diag.statementReceipts())")
        #expect(diag.statementReceipts().contains("Top mode on this link: available, uncompressed"))
    }

    @Test("#664 anchor m4pro_macos26.6.1_b: DELL U3225QE at 4K120 over 4 lanes HBR2 tunneled reads DSC on, compressionActive")
    func anchorU3225QE() throws {
        guard Self.folderOnDisk("m4pro_macos26.6.1_b") else { return }
        let (diag, pairing) = try #require(Self.statementDiagnostic(folder: "m4pro_macos26.6.1_b", block: 1), "m4pro_macos26.6.1_b is on disk but did not pair through the production reader and match")
        #expect(pairing.record.node.currentTimingID == 76, "fixture guard: timing 76 (4400x2250 at 120 Hz, 1188 MHz) is driven")
        // Both `ColorModes` and `DSCRequiredColorElementIDs` print `[20] (sampled)` here and
        // the same first dozen IDs (corpus-parser-traps entry 13). The production reader has
        // no notion of sampling, so the replay reads twelve modes and a twelve-member list
        // that names every one of them: the INFERRED set equality of dump A4, read as the
        // live node would present it. That is why this anchor is asserted while the counts
        // below exclude sampled lists.
        let dict = try #require(CorpusDisplayProbes.drivenTimingDictionary(pairing.record))
        #expect(CorpusDisplayProbes.listSampled(dict, "DSCRequiredColorElementIDs") == true)
        #expect(CorpusDisplayProbes.listCount(dict, "DSCRequiredColorElementIDs") == 20)
        let statement = try #require(diag.facts.drivenTiming)
        #expect(statement.colourModes.count == 12)
        #expect(statement.dscRequiredIDs.count == 10, "twelve listed less the two virtual entries")
        #expect(statement.dscRequiredIDs == statement.dscCapableIDs)
        #expect(statement.dscRequiredIDs == statement.nonVirtualIDs)
        #expect(statement.unsafeIDs.isEmpty, "a DP transport is never unsafe")
        #expect(diag.facts.dscReading == .dscOn)
        #expect(diag.facts.isAppleDisplay == false)
        #expect(diag.bottleneck == .compressionActive, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.isWarning == false)
        #expect(diag.summary == "Display running compressed (DSC) to fit through the link")
        #expect(diag.detail.contains("states that this link needs compression (DSC)"), Comment(rawValue: diag.detail))
        #expect(diag.cableAssessment == .unlikelyTheCable)
        #expect(diag.facts.liveNeededGbps == nil, "8 and 10 bit on one timing and no NSScreen depth in a probe: no cross-check figure")
        #expect(diag.facts.currentMode?.pixelClockHz == 1_188_000_000)
        #expect(diag.facts.topModeMatch == .exact, "the EDID's 4K120 at 1188 MHz (CTA VIC 118, the top by clock) is the driven timing; replica-checked 2026-09-20")
        #expect(diag.facts.topModeAvailability == .offeredWithDSC)
    }

    @Test("#664 anchor m5_macos26.6.1_e: Studio Display on 4 lanes HBR3 at 0.867 of the link reads DSC on with no link blame")
    func anchorStudioDisplay() throws {
        guard Self.folderOnDisk("m5_macos26.6.1_e") else { return }
        let (diag, pairing) = try #require(Self.statementDiagnostic(folder: "m5_macos26.6.1_e", block: 1), "m5_macos26.6.1_e is on disk but did not pair through the production reader and match")
        #expect(pairing.record.node.currentTimingID == 43, "fixture guard: timing 43 (5120x2880 at 60 Hz, 936 MHz)")
        #expect(Self.isAppleEDID(pairing.entry.port))
        let statement = try #require(diag.facts.drivenTiming)
        #expect(statement.dscRequiredIDs == [46, 48])
        #expect(statement.dscCapableIDs == [46, 48])
        #expect(diag.facts.dscReading == .dscOn)
        #expect(diag.facts.isAppleDisplay == true)
        #expect(diag.bottleneck == .compressionActive, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.summary == "Display running compressed (DSC)")
        #expect(diag.detail.contains("Apple displays run compressed whenever the link supports it"), Comment(rawValue: diag.detail))
        #expect(!diag.detail.contains("needs compression"), "no link blame")
        #expect(diag.facts.lanes == 4 && diag.facts.rateDescription == "8.1 Gbps (HBR3)")
        #expect(diag.facts.liveNeededGbps == nil, "8 and 10 bit RGB and no NSScreen depth in a probe")
        #expect(diag.facts.topModeMatch == .sameRefresh, "the EDID's 964.8 MHz tiled composite against the node's 936 MHz 5K timing: same picture and refresh, another blanking")
        #expect(diag.facts.topModeAvailability == .offeredWithDSC)
    }

    @Test("#664 anchor m1max_macos15.5: the one Apple node whose lists are not all full is driven on its 5K timing, whose list is full: DSC on with the Apple wording, by the general rule")
    func anchorStudioDisplayOnMacOS155() throws {
        // Spec Design 3 (final wording): the list decides on every display, Apple's included; the Apple
        // clause changes attribution only. This node is the corpus's one Apple exception to "DSC listed on
        // every timing" (P3 dsc-apple, 45 of 46): its 4K60 timing 37 lists DSC-capable modes with an empty
        // list. It is driven on timing 43 (5120x2880 at 60 Hz, 5200x3000 totals, 936 MHz) over 4 lanes HBR2
        // tunneled, whose list is [1, 46, 48] over the DSC-capable set [1, 46, 48] (1 virtual), so the
        // general rule reads DSC on and the Apple clause removes the link blame. Replayed here so
        // acceptance 4's count is exercised on the real exception, not only on Task 6's synthetic shape.
        guard Self.folderOnDisk("m1max_macos15.5") else { return }
        let (diag, pairing) = try #require(Self.statementDiagnostic(folder: "m1max_macos15.5", block: 0), "m1max_macos15.5 is on disk but did not pair through the production reader and match")
        #expect(pairing.record.node.currentTimingID == 43, "fixture guard: timing 43 is driven")
        #expect(Self.isAppleEDID(pairing.entry.port))
        let statement = try #require(diag.facts.drivenTiming)
        #expect(statement.dscRequiredIDs == [46, 48], "the virtual mode 1 is listed by the node and resolved out")
        #expect(statement.dscCapableIDs == [46, 48])
        #expect(statement.unsafeIDs.isEmpty && statement.validPixelEncodings == 0x1b4d)
        #expect(statement.colourModesComplete && statement.dscListComplete && statement.unsafeListComplete)
        // The exception itself, as carried: the non-driven 4K60 timing lists DSC-capable modes and an empty list.
        let timing37 = try #require(statement.allTimings.first { $0.id == 37 })
        #expect(timing37.width == 3840 && timing37.height == 2160)
        #expect(timing37.lists.dscRequiredIDs.isEmpty && !timing37.lists.dscCapableIDs.isEmpty, "the not-all-full shape lives on a timing that is not driven")
        #expect(timing37.lists.dscReading(for: nil) == .uncompressed, "read by the general rule, as it would be if it were driven")
        #expect(diag.facts.dscReading == .dscOn)
        #expect(diag.facts.isAppleDisplay == true)
        #expect(diag.bottleneck == .compressionActive, "got \(diag.bottleneck): \(diag.detail)")
        #expect(diag.summary == "Display running compressed (DSC)")
        #expect(diag.detail.contains("Apple displays run compressed whenever the link supports it"), Comment(rawValue: diag.detail))
        #expect(!diag.detail.contains("needs compression"), "no link blame")
        #expect(diag.facts.lanes == 4 && diag.facts.rateDescription == "5.4 Gbps (HBR2)" && diag.facts.currentMode?.pixelClockHz == 936_000_000)
        #expect(diag.facts.topModeMatch == .sameRefresh, "the 964.8 MHz tiled composite against the 936 MHz 5K timing, as on every Studio Display")
        #expect(diag.facts.topModeAvailability == .offeredWithDSC)
    }

    @Test("#664 anchor m2pro_macos26.6.1: DELL S2721QS behind a cHDMIb converter, three 4:2:0 downstream modes on the driven timing, uncompressed, fine")
    func anchorS2721QSDownstream420() throws {
        // m1_macos26.5_o is the References' downstream-format anchor, and it cannot
        // replay: its probe 26 is the flat rendering (booleans print `<type 21>`, so
        // `external` is unreadable), cut at 64 KB with timing 72 outside the capture.
        // It anchors DisplayTimingReaderTests as a transcribed colour-mode fixture;
        // this node is the same fact in a tree rendering with complete lists.
        if Self.folderOnDisk("m1_macos26.5_o") {
            #expect(CorpusDisplayProbes.externalNodes(folder: "m1_macos26.5_o")?.isEmpty == true,
                "SKIP m1_macos26.5_o: flat rendering, not readable by the tree parser (if this ever pairs, promote it to a full anchor)")
        }
        guard Self.folderOnDisk("m2pro_macos26.6.1") else { return }
        let (diag, pairing) = try #require(Self.statementDiagnostic(folder: "m2pro_macos26.6.1", block: 1), "m2pro_macos26.6.1 is on disk but did not pair through the production reader and match")
        #expect(pairing.record.node.currentTimingID == 57, "fixture guard: timing 57 (4400x2250 at 60 Hz, 594 MHz)")
        let statement = try #require(diag.facts.drivenTiming)
        #expect(statement.downstream420 == .someModes, "3 of 6 non-virtual modes convert: K37, not K8 (ruling 44)")
        #expect(statement.colourModes.filter { $0.downstreamFormat != nil }.map(\.id).sorted() == [5, 85, 87])
        #expect(statement.colourModes.filter { $0.downstreamFormat != nil }.allSatisfy { $0.downstreamFormat == DisplayDownstreamFormat(encoding: .ycbcr420, depth: 8) })
        #expect(statement.unsafeIDs == [76, 77, 78, 79], "the modes the converter emits as 4:2:0 are not rated unsafe (P4 unsafe-downstream)")
        #expect(statement.dscRequiredIDs.isEmpty)
        #expect(diag.facts.dscReading == .uncompressed)
        #expect(diag.facts.sinkType == "HDMI")
        #expect(diag.bottleneck == .fine, "got \(diag.bottleneck): \(diag.detail)")
        #expect(!diag.detail.contains("in 4:2:0 only"), "no 4:2:0 note at all on this panel: its EDID declares no 4:2:0-only entry (the retired \"a mode macOS does not use\" sentence could not appear either way)")
        // Ruling 44 on this panel: its 4K60 sits in the Video Data Block with a 4:2:0 capability-map
        // bit, not in a Y420VDB, so the EDID declares no 4:2:0-only entry and no 4:2:0 note is shown
        // at all; the "some" sentence (K37) is pinned by DisplayDiagnosticTests on the 27C1U-L EDID.
        #expect(diag.facts.declared420OnlyModes == 0)
        #expect(!diag.detail.contains("4:2:0"), Comment(rawValue: diag.detail))
        let need = try #require(diag.facts.liveNeededGbps)
        #expect(abs(need - 14.256) < 0.001, "594 MHz x 24: every non-virtual mode is 8-bit RGB or 4:4:4")
        #expect(diag.facts.statementContradiction == false, "14.256 fits 16.875 to 17.28")
        #expect(diag.facts.topModeMatch == .exact, "the EDID's 594 MHz 4K60 (its base DTD, tied on clock with VIC 97) is the driven timing; replica-checked 2026-09-20")
        #expect(diag.facts.topModeAvailability == .offeredUncompressed)
    }

    @Test("#664 counts: over the eligible population, uncompressed for every empty-list driven timing, DSC on for every Apple display with a DSC-capable mode, and for every non-Apple timing the firmware rule marks")
    func statementCountsAcrossTheCorpus() throws {
        guard let corpus = CorpusDisplayProbes.accountCorpus() else {
            return // corpus absent: scripts/ci.sh's presence check owns that failure
        }
        var paired = 0, tested = 0
        var sampledSkipped: [String] = []
        var incomplete: [String] = []
        var emptyList = 0, emptyListNotUncompressed: [String] = []
        var appleDSC = 0, appleViolations: [String] = []
        var appleNoDSC: [String] = []
        var ruleMarked = 0, ruleMarkedListWrong: [String] = []
        var ruleMarkedAllListed = 0, ruleMarkedMixed: [String] = []
        var ruleMarkedVerdictWrong: [String] = []
        var noLink = 0
        var idsOutsideDSC: [String] = [], idsOutsideUnsafe: [String] = [], supportsDSCOutOfRange: [String] = []

        for pairing in corpus.attached {
            let folder = pairing.folder
            paired += 1
            let tag = "\(folder) block \(pairing.entry.block) \(pairing.record.node.edidKey)"
            guard let dict = CorpusDisplayProbes.drivenTimingDictionary(pairing.record),
                  let timing = DisplayTimingReader.parseTiming(dict) else { incomplete.append("\(tag): driven dictionary missing or unparseable after attach"); continue }
            if CorpusDisplayProbes.listSampled(dict, "DSCRequiredColorElementIDs") || CorpusDisplayProbes.listSampled(dict, "ColorModes") {
                sampledSkipped.append(tag)
                continue
            }
            guard timing.colourModesComplete, let rawList = timing.dscRequiredList else { incomplete.append(tag); continue }
            guard let diag = DisplayDiagnostic(dp: pairing.matched, edid: pairing.entry.edid) else { incomplete.append("\(tag): no diagnostic (EDID unparsed after attach)"); continue }
            tested += 1
            let listed = Set(rawList)
            let capableAll = Set(timing.colourModes.filter(\.isDSCCapable).map(\.id))
            let nonVirtual = Set(timing.colourModes.filter { !$0.isVirtual }.map(\.id))
            // PR #665 gate, Codex 2: the shapes the fail-closed rule now catches, censused on
            // the unsampled tested timings so the rule is shown to fire on none of them.
            let allIDs = Set(timing.colourModes.map(\.id))
            if !listed.isSubset(of: allIDs) { idsOutsideDSC.append("\(tag): DSC list \(listed.subtracting(allIDs).sorted()) not among the colour modes") }
            if !CorpusDisplayProbes.listSampled(dict, "UnsafeColorElementIDs"), let unsafe = timing.unsafeList, !Set(unsafe).isSubset(of: allIDs) {
                idsOutsideUnsafe.append("\(tag): unsafe list \(Set(unsafe).subtracting(allIDs).sorted()) not among the colour modes")
            }
            for entry in ((dict["ColorModes"] as? [Any]) ?? []).compactMap({ $0 as? [String: Any] }) {
                if let raw = (entry["SupportsDSC"] as? NSNumber)?.intValue, !(0...3).contains(raw) {
                    supportsDSCOutOfRange.append("\(tag): mode \((entry["ID"] as? NSNumber)?.intValue ?? -1) SupportsDSC \(raw)")
                }
            }

            if listed.isEmpty {
                emptyList += 1
                if diag.facts.dscReading != .uncompressed {
                    emptyListNotUncompressed.append("\(tag): reading \(String(describing: diag.facts.dscReading)), verdict \(diag.bottleneck)")
                }
            }

            if Self.isAppleEDID(pairing.entry.port) {
                if capableAll.isEmpty {
                    appleNoDSC.append("\(tag): no DSC-capable mode, list \(listed.sorted()), verdict \(diag.bottleneck)")
                } else {
                    appleDSC += 1
                    if diag.facts.dscReading != .dscOn || diag.bottleneck != .compressionActive
                        || diag.facts.isAppleDisplay != true || !diag.detail.contains("Apple displays run compressed") {
                        appleViolations.append("\(tag): reading \(String(describing: diag.facts.dscReading)), verdict \(diag.bottleneck), apple \(diag.facts.isAppleDisplay): \(diag.detail)")
                    }
                }
                continue
            }

            // The firmware rule (dump A2), FEC on: a DSC-capable mode is required when its
            // pixel clock x Apple bpp exceeds lanes x rate x 0.8 x 0.9765625.
            guard let rawLink = Self.rawLinkGbps(pairing.matched), let clock = timing.pixelClockHz else { noLink += 1; continue }
            let usable = rawLink * 0.9765625
            let marks = timing.colourModes.filter { colour in
                guard colour.isDSCCapable, let bpp = colour.encoding.bitsPerPixel(depth: colour.depth) else { return false }
                return Double(clock) * bpp / 1_000_000_000 > usable
            }.map(\.id)
            guard !marks.isEmpty else { continue }
            ruleMarked += 1
            if listed.isEmpty || listed != capableAll {
                ruleMarkedListWrong.append("\(tag): rule marks \(marks.sorted()), list \(listed.sorted()), capable \(capableAll.sorted())")
                continue
            }
            if listed.intersection(nonVirtual) == nonVirtual {
                ruleMarkedAllListed += 1
                if diag.bottleneck != .compressionActive || diag.facts.dscReading != .dscOn {
                    ruleMarkedVerdictWrong.append("\(tag): every non-virtual mode listed, got \(diag.bottleneck) / \(String(describing: diag.facts.dscReading))")
                }
            } else {
                ruleMarkedMixed.append("\(tag): \(diag.bottleneck) / \(String(describing: diag.facts.dscReading))")
                if diag.bottleneck != .unknownMode || diag.facts.dscReading != .unresolved {
                    ruleMarkedVerdictWrong.append("\(tag): DSC-capable and non-capable modes together, got \(diag.bottleneck) / \(String(describing: diag.facts.dscReading))")
                }
            }
        }

        print("DisplayDiagnosticProbeSweep/#664 \(corpus.summary)")
        for failure in corpus.failures { print("  FAILURE \(failure)") }
        print("DisplayDiagnosticProbeSweep/#664: \(paired) paired driven timings; SKIP sampled \(sampledSkipped.count), incomplete \(incomplete.count), no link \(noLink); empty list \(emptyList) (\(emptyListNotUncompressed.count) not uncompressed); Apple with DSC-capable modes \(appleDSC) (\(appleViolations.count) violations), Apple without \(appleNoDSC.count); non-Apple rule-marked \(ruleMarked): list wrong \(ruleMarkedListWrong.count), every non-virtual mode listed \(ruleMarkedAllListed), mixed \(ruleMarkedMixed.count), verdict wrong \(ruleMarkedVerdictWrong.count)")
        for line in appleNoDSC { print("  APPLE NO DSC \(line)") }
        for line in ruleMarkedMixed { print("  MIXED \(line)") }
        for line in emptyListNotUncompressed + appleViolations + ruleMarkedListWrong + ruleMarkedVerdictWrong { print("  VIOLATION \(line)") }
        print("DisplayDiagnosticProbeSweep/#664 fail-closed shapes (PR #665 gate, Codex 2) over the \(tested) tested driven timings: DSC list IDs outside the colour modes \(idsOutsideDSC.count), unsafe list IDs outside \(idsOutsideUnsafe.count), SupportsDSC outside 0...3 \(supportsDSCOutOfRange.count)")
        for line in idsOutsideDSC + idsOutsideUnsafe + supportsDSCOutOfRange { print("  FAIL-CLOSED SHAPE \(line)") }

        // Ruling 45: the population first, then the universal assertions over it with the replica's
        // exact figures (2026-09-21, a replica of the production match over the corpus): 231 eligible,
        // 231 attached, 0 failures; sampled driven lists 57, incomplete 0; empty list 137 (9 Apple);
        // Apple with a DSC-capable mode 29, without 9; non-Apple rule-marked 8 (5 every non-virtual
        // mode listed, 3 mixed); 1 non-Apple tested timing with no readable link. A figure that
        // differs is investigated (the print names every skip, violation and failure) and the
        // expected value moves only with the reason written beside it; it never moves to make a
        // run green. Every corpus ingestion that adds an eligible node re-derives this line.
        // Pair references (research/displays/display-node-keys.md, 2026-09-18, 1408 folders):
        // P3 H1 driven rows, "not member and above link" 0 in every cell; P3 dsc-apple 45 of 46
        // Apple-display nodes with every list equal to its DSC-capable set; P3 firmware rule
        // with FEC on driven timings: 185 members predicted, 0 non-members predicted. The
        // Apple nodes without a DSC-capable mode (Thunderbolt Display 0x9227 and LED Cinema
        // Display 0x9226, keys 06102792- and 06102692-) read uncompressed by the general rule
        // and are named above (ruling 22, the spec as corrected). The mixed timings (RGB and
        // 4:4:4 capable beside 4:2:2 not) read unknown, as the node does not name the live
        // mode (ruling 23).
        // Measured by this sweep on 2026-09-21 over 1415 folders (the print lines above, verbatim):
        //   DisplayDiagnosticProbeSweep/#664 population: 1415 folders, 260 captured driven timings, 231 eligible (15 with no active block carrying the key, 14 with several, 0 unkeyable nodes), attached 231, failures 0, known exceptions 0
        //   DisplayDiagnosticProbeSweep/#664: 231 paired driven timings; SKIP sampled 57, incomplete 0, no link 1; empty list 137 (0 not uncompressed); Apple with DSC-capable modes 29 (0 violations), Apple without 9; non-Apple rule-marked 8: list wrong 0, every non-virtual mode listed 5, mixed 3, verdict wrong 0
        #expect(corpus.eligible == 231, "eligible population \(corpus.eligible), replica 231: \(corpus.summary)")
        #expect(corpus.unnamedFailures.isEmpty, "eligible nodes production match did not attach and knownExceptions does not name:\n\(corpus.unnamedFailures.map(\.description).joined(separator: "\n"))")
        #expect(corpus.attached.count == corpus.eligible - CorpusDisplayProbes.knownExceptions.count, "attached \(corpus.attached.count) is not eligible \(corpus.eligible) minus the known exceptions")
        #expect(paired == corpus.attached.count)
        #expect(sampledSkipped.count == 57, "sampled driven lists \(sampledSkipped.count); the replica measured 57")
        #expect(incomplete.isEmpty, "\(incomplete.count) attached nodes with an incomplete driven timing; the corpus has none (ruling 20):\n\(incomplete.joined(separator: "\n"))")
        #expect(emptyList == 137 && emptyListNotUncompressed.isEmpty, "empty-list driven timings \(emptyList) (replica 137), \(emptyListNotUncompressed.count) not read as uncompressed")
        #expect(appleDSC == 29 && appleViolations.isEmpty, "Apple displays with a DSC-capable mode \(appleDSC) (replica 29), \(appleViolations.count) not read as DSC on with no link blame")
        #expect(appleNoDSC.count == 9 && appleNoDSC.allSatisfy { $0.contains("06102792-") || $0.contains("06102692-") }, "Apple displays without a DSC-capable mode \(appleNoDSC.count) (replica 9, every one a Thunderbolt or Cinema Display): \(appleNoDSC)")
        #expect(ruleMarked == 8 && ruleMarkedListWrong.isEmpty, "rule-marked timings \(ruleMarked) (replica 8), \(ruleMarkedListWrong.count) whose list is not the DSC-capable set")
        #expect(ruleMarkedAllListed == 5 && ruleMarkedMixed.count == 3 && ruleMarkedVerdictWrong.isEmpty, "rule-marked: every mode listed \(ruleMarkedAllListed) (replica 5), mixed \(ruleMarkedMixed.count) (replica 3), wrong verdicts \(ruleMarkedVerdictWrong.count)")
        #expect(noLink == 1, "non-Apple tested timings with no readable link \(noLink); the replica measured 1")
        #expect(paired == sampledSkipped.count + incomplete.count + tested, "every attached node is a sampled skip, named incomplete, or tested: \(paired) against \(sampledSkipped.count) + \(incomplete.count) + \(tested)")
        // PR #665 gate, Codex 2: the shapes the fail-closed rule catches (an ID no colour mode
        // carries in either list, a SupportsDSC outside the two-bit field) occur on none of the
        // tested driven timings, so the rule moves no corpus verdict. Measured 2026-09-21: 0, 0, 0.
        #expect(idsOutsideDSC.isEmpty && idsOutsideUnsafe.isEmpty && supportsDSCOutOfRange.isEmpty,
                "fail-closed shapes on tested driven timings: DSC \(idsOutsideDSC.count), unsafe \(idsOutsideUnsafe.count), SupportsDSC \(supportsDSCOutOfRange.count)")
    }

    /// PR #665 gate rerun, Claude note 4, ruled: the Mac's own HDMI port is itself the DP-to-HDMI
    /// stage (dump A1), so the unsafe list is meaningful there and the receipt names the port (K39;
    /// K40 when the list could not be read). The reviewer measured 38 paired nodes on a native HDMI
    /// port, 23 with unsafe members on the driven timing, and K15 printed on 0 of them. K39 and K40
    /// together must account for those 23: a sampled driven table whose unsafe list names unprinted
    /// IDs reads unreadable (round 1, Codex 2) and prints K40, a capture artefact.
    @Test("#664 native HDMI ports print the port's TMDS receipt: K39 and K40 together cover every native-HDMI node with unsafe members")
    func nativeHDMIPortsPrintThePortTMDSReceipt() throws {
        guard let corpus = CorpusDisplayProbes.accountCorpus() else {
            return // corpus absent: scripts/ci.sh's presence check owns that failure
        }
        var nativeHDMI = 0, withMembers = 0, k39: [String] = [], k40: [String] = [], adapterWording: [String] = [], missing: [String] = []
        for pairing in corpus.attached {
            guard pairing.matched.parentPortTypeDescription?.uppercased() == "HDMI" else { continue }
            nativeHDMI += 1
            guard let diag = DisplayDiagnostic(dp: pairing.matched, edid: pairing.entry.edid), let statement = diag.facts.drivenTiming else { continue }
            let tag = "\(pairing.folder) block \(pairing.entry.block) \(pairing.record.node.edidKey): \(pairing.entry.edid.monitorName ?? "?")"
            let receipts = diag.statementReceipts()
            if receipts.contains(where: { $0.contains("adapter's TMDS rate limit") }) { adapterWording.append(tag) }
            let hasMembers = !statement.unsafeIDsRaw.isEmpty
            if hasMembers { withMembers += 1 }
            if receipts.contains(where: { $0.hasPrefix("macOS rates") && $0.contains("HDMI port's TMDS rate limit") }) {
                k39.append("\(tag): unsafe \(statement.unsafeIDs.sorted()) of \(statement.nonVirtualIDs.sorted())")
            } else if receipts.contains(where: { $0.contains("HDMI port's TMDS rate limit could not be read") }) {
                k40.append("\(tag): unsafe list as printed \(statement.unsafeIDsRaw)")
            } else if hasMembers {
                missing.append(tag)
            }
        }
        print("DisplayDiagnosticProbeSweep/#664 native HDMI: \(nativeHDMI) attached nodes on the Mac's own HDMI port, \(withMembers) with unsafe members on the driven timing; K39 printed on \(k39.count), K40 on \(k40.count), adapter wording on \(adapterWording.count), members without a receipt \(missing.count)")
        for line in k39 { print("  K39 \(line)") }
        for line in k40 { print("  K40 \(line)") }
        for line in adapterWording + missing { print("  NATIVE HDMI RECEIPT MISSING \(line)") }
        // The reviewer's census at 99423fd9 (rerun report, note 4): 38 native-HDMI nodes, 23 with
        // members, K15 on 0. Measured by this sweep on 2026-09-21: 38, 23; K39 + K40 == 23.
        #expect(nativeHDMI == 38, "native-HDMI attached nodes \(nativeHDMI); the reviewer measured 38")
        #expect(withMembers == 23, "native-HDMI nodes with unsafe members \(withMembers); the reviewer measured 23")
        #expect(k39.count + k40.count == withMembers, "K39 \(k39.count) + K40 \(k40.count) against \(withMembers) nodes with members")
        #expect(adapterWording.isEmpty && missing.isEmpty, "adapter wording on a native port: \(adapterWording.count); members with no receipt: \(missing.count)")
    }

    /// PR #665 gate, Claude F1: on a live Mac the CoreGraphics mode reaches `match` first, carrying
    /// NSScreen's backing-store depth (8 or 10), and the reader used to keep that depth on the
    /// driven mode whenever the timing listed several depths, so `candidateModes` narrowed the DSC
    /// reading by a value the node never published. The probes carry no NSScreen data, so the
    /// sweeps above never saw it. This sweep replays every attached node three times through the
    /// production match, with no CoreGraphics mode, with one at 8 bits and with one at 10, and
    /// asserts the verdict and the reading are the same each time. Before the fix it named 12
    /// nodes (5 unknownMode to compressionActive at 10, 6 the other way, 1 between two unknown
    /// readings), the reviewer's measurement; after it, 0.
    @Test("#664 NSScreen's depth decides nothing: every attached node reads the same verdict with a CoreGraphics mode at 8 bits, at 10, and with none")
    func nsScreenDepthDecidesNothing() throws {
        guard let corpus = CorpusDisplayProbes.accountCorpus() else {
            return // corpus absent: scripts/ci.sh's presence check owns that failure
        }
        var compared = 0
        var differing: [String] = []
        var multiDepth: [String] = []
        for pairing in corpus.attached {
            let folder = pairing.folder
            let ports = CorpusDisplayProbes.activePorts(folder: folder)
            let nodes = (CorpusDisplayProbes.externalNodes(folder: folder) ?? []).map(\.node)
            guard let index = ports.firstIndex(where: { $0.block == pairing.entry.block }),
                  let plain = DisplayDiagnostic(dp: pairing.matched, edid: pairing.entry.edid) else { continue }
            let tag = "\(folder) block \(pairing.entry.block) \(pairing.record.node.edidKey)"
            compared += 1
            if let depths = pairing.matched.drivenTiming.map({ Set($0.colourModes.filter { !$0.isVirtual }.map(\.depth)) }), depths.count > 1 {
                multiDepth.append(tag)
            }
            for depth in [8, 10] {
                // The CoreGraphics mode as DisplayModeReader would attach it before the timing read:
                // the picture and refresh CoreGraphics reports, NSScreen's depth, no clock.
                let withDepth = ports.map { entry -> IOPortTransportStateDisplayPort in
                    let cg = DisplayCurrentMode(width: entry.port.currentMode?.width ?? 1, height: entry.port.currentMode?.height ?? 1,
                                                refreshHz: entry.port.currentMode?.refreshHz ?? 1, bitsPerComponent: depth)
                    return entry.port.with(currentMode: cg, maxMode: entry.port.maxMode)
                }
                let rematched = DisplayTimingReader.match(ports: withDepth, nodes: nodes)[index]
                guard let diag = DisplayDiagnostic(dp: rematched, edid: pairing.entry.edid) else {
                    differing.append("\(tag): no diagnostic at NSScreen \(depth)")
                    continue
                }
                if diag.bottleneck != plain.bottleneck || diag.facts.dscReading != plain.facts.dscReading {
                    differing.append("\(tag): NSScreen \(depth) reads \(diag.bottleneck) / \(String(describing: diag.facts.dscReading)), depth-free \(plain.bottleneck) / \(String(describing: plain.facts.dscReading)); driven \(pairing.matched.currentMode?.label ?? "?"), monitor \(pairing.entry.edid.monitorName ?? "?")")
                }
            }
        }
        print("DisplayDiagnosticProbeSweep/#664 NSScreen depth: \(compared) attached nodes replayed at 8 and 10 bits; \(multiDepth.count) driven timings list several depths; verdict or reading differs from the depth-free run on \(differing.count)")
        for line in differing { print("  NSSCREEN DEPENDENT \(line)") }
        #expect(compared == corpus.attached.count, "every attached node was replayed: \(compared) of \(corpus.attached.count)")
        #expect(compared >= 200, "only \(compared) nodes replayed; the corpus pairs 231")
        #expect(differing.isEmpty, "\(differing.count) nodes whose verdict depends on NSScreen's depth:\n\(differing.joined(separator: "\n"))")
    }

    @Test("#664 count four: every eligible node driven below its top mode reads the outcome the node's own top-mode timing gives")
    func belowTopReadsTheTopModeTiming() throws {
        guard let corpus = CorpusDisplayProbes.accountCorpus() else {
            return // corpus absent: scripts/ci.sh's presence check owns that failure
        }
        var attachedSeen = 0, noDiagnostic: [String] = []
        var belowTop = 0
        var skippedSampledDriven: [String] = [], skippedReading: [String] = []
        var offered: [String] = [], notOffered: [String] = [], notListed: [String] = []
        var mismatches: [String] = []

        for pairing in corpus.attached {
            let folder = pairing.folder
            attachedSeen += 1
            guard let diag = DisplayDiagnostic(dp: pairing.matched, edid: pairing.entry.edid),
                  let top = diag.topMode, let current = diag.facts.currentMode else {
                noDiagnostic.append("\(folder) block \(pairing.entry.block) \(pairing.record.node.edidKey)"); continue
            }
            let drivenAtTop = current.width == top.width && current.height == top.height && abs(current.refreshHz - top.refreshHz) <= 0.5
            guard !drivenAtTop else { continue }
            belowTop += 1
            let tag = "\(folder) block \(pairing.entry.block) \(pairing.record.node.edidKey): driven \(current.label), top \(top.width)x\(top.height) @ \(Int(top.refreshHz.rounded())) Hz, sink \(diag.facts.sinkType ?? "DP"), match \(String(describing: diag.facts.topModeMatch)), availability \(String(describing: diag.facts.topModeAvailability)), verdict \(diag.bottleneck)"
            // Path (b) needs the driven reading; a sampled driven list (corpus-parser-traps 13) or an
            // unresolved reading takes another path and is named, not counted.
            if let dict = CorpusDisplayProbes.drivenTimingDictionary(pairing.record),
               CorpusDisplayProbes.listSampled(dict, "DSCRequiredColorElementIDs") || CorpusDisplayProbes.listSampled(dict, "ColorModes") {
                skippedSampledDriven.append(tag); continue
            }
            guard diag.facts.dscReading == .uncompressed else { skippedReading.append(tag); continue }
            guard let availability = diag.facts.topModeAvailability else { mismatches.append("\(tag): no availability with a statement present"); continue }
            switch availability {
            case .offeredUncompressed, .offeredWithDSC, .offeredUnresolved:
                offered.append(tag)
                if diag.bottleneck != .belowMonitorMax || diag.cableAssessment != .unlikelyTheCable
                    || diag.summary != "Monitor can do more than it is set to" || !diag.detail.contains("as available on this link") {
                    mismatches.append("\(tag): offered, expected belowMonitorMax with the cable cleared and K18 to K20: \(diag.summary) / \(diag.detail)")
                }
            case .notOffered:
                notOffered.append(tag)
                let expected: DisplayDiagnostic.Bottleneck = diag.facts.sinkType == nil ? .belowMonitorMax : .adapterLimit
                if diag.bottleneck != expected || !diag.detail.contains("does not offer") {
                    mismatches.append("\(tag): not offered, expected \(expected) with K21 to K25: \(diag.summary) / \(diag.detail)")
                }
            case .notListed:
                notListed.append(tag)
                if diag.bottleneck != .unknownMode || !diag.detail.contains("has no entry matching its top mode") {
                    mismatches.append("\(tag): not listed, expected unknownMode with K26: \(diag.summary) / \(diag.detail)")
                }
            }
        }

        print("DisplayDiagnosticProbeSweep/#664 top mode \(corpus.summary)")
        for failure in corpus.failures { print("  FAILURE \(failure)") }
        print("DisplayDiagnosticProbeSweep/#664 top mode: \(belowTop) of \(attachedSeen) attached nodes driven below the top (\(noDiagnostic.count) with no diagnostic); SKIP sampled driven lists \(skippedSampledDriven.count), reading not uncompressed \(skippedReading.count); offered \(offered.count), not offered \(notOffered.count), not listed \(notListed.count); mismatches \(mismatches.count)")
        for line in offered { print("  OFFERED \(line)") }
        for line in notOffered { print("  NOT OFFERED \(line)") }
        for line in notListed { print("  NOT LISTED \(line)") }
        for line in skippedSampledDriven + skippedReading { print("  SKIP \(line)") }
        for line in mismatches { print("  MISMATCH \(line)") }

        // Ruling 45: the population first, then exact figures from the replica (2026-09-21, the
        // "refined" rule of ruling 41): 12 below the top, 3 skipped for sampled driven lists
        // (m1_macos27.0_k, m1max_macos26.5.2_r 09D15E7F, m3max_macos26.5.2_c: named skips, not
        // verdicts), 0 skipped for a reading that is not uncompressed, 9 classified: offered 3
        // (m1_macos26.5.2_af and _k behind HDMI, m4pro_macos26.5.2_g on DP), not offered 6
        // (m3_macos26.5.2_q, m4max_macos26.5.2_k 10ACF3D0, m5_macos26.5.1_n, m5_macos26.5.2_g behind
        // HDMI; m1_macos26.1, m4_macos26.5.2_au on DP), not listed 0. Before ruling 41 the same count
        // read 22 classified with 14 not listed (ruling 38). A figure that differs is investigated
        // against these names before any number moves.
        // PR #665 gate fix round 4, item 2 (measured at 2404c8f4): the Odyssey G85SB on
        // `m1pro_macos26.5.2_x` block 1 joins the below-top set (13) as a fourth sampled skip: its
        // DisplayID 2560x1440 @ 175 Hz top is listed nowhere in the capture and now stays the top
        // (match notListed, availability notListed, verdict unknownMode). Its colour reading is
        // unresolved, so the (d) sentence prints ("does not name the colour format in use"), not
        // K26, and the verdict was unknownMode before the round too (top 3440x1440 @ 120, exact,
        // offeredUnresolved); what moved is the top, the match and the facts. Its driven ColorModes
        // table is sampled (the DSC list is not), so it is named as a skip here and never a
        // classified verdict. Sampling caveat: the capture caps arrays at 12 entries, so "listed
        // nowhere" may be the truncation; a live read is never sampled.
        // Measured by this sweep on 2026-09-21 over 1415 folders (the print lines above, verbatim):
        //   DisplayDiagnosticProbeSweep/#664 top mode population: 1415 folders, 260 captured driven timings, 231 eligible (15 with no active block carrying the key, 14 with several, 0 unkeyable nodes), attached 231, failures 0, known exceptions 0
        //   DisplayDiagnosticProbeSweep/#664 top mode: 12 of 231 attached nodes driven below the top (0 with no diagnostic); SKIP sampled driven lists 3, reading not uncompressed 0; offered 3, not offered 6, not listed 0; mismatches 0
        #expect(corpus.eligible == 231, "eligible population \(corpus.eligible), replica 231: \(corpus.summary)")
        #expect(corpus.unnamedFailures.isEmpty, "eligible nodes production match did not attach and knownExceptions does not name:\n\(corpus.unnamedFailures.map(\.description).joined(separator: "\n"))")
        #expect(corpus.attached.count == corpus.eligible - CorpusDisplayProbes.knownExceptions.count)
        #expect(noDiagnostic.isEmpty, "attached nodes with no diagnostic or no top mode:\n\(noDiagnostic.joined(separator: "\n"))")
        let classified = offered.count + notOffered.count + notListed.count
        #expect(belowTop == 13, "below the top \(belowTop); the replica measured 12, plus the G85SB since fix round 4 (13)")
        #expect(skippedSampledDriven.count == 4 && skippedReading.isEmpty, "skips: sampled \(skippedSampledDriven.count) (replica 3, plus the G85SB since fix round 4: 4), reading \(skippedReading.count) (replica 0)")
        #expect(skippedSampledDriven.contains { $0.hasPrefix("m1pro_macos26.5.2_x block 1") && $0.contains("notListed") }, "the G85SB is the fourth sampled skip, not listed:\n\(skippedSampledDriven.joined(separator: "\n"))")
        #expect(classified == 9 && offered.count == 3 && notOffered.count == 6, "classified \(classified) (replica 9): offered \(offered.count) (3), not offered \(notOffered.count) (6)")
        #expect(notListed.isEmpty, "\(notListed.count) classified below-top nodes whose resolved top the node never lists; since fix round 4 the rule can leave one, and the corpus's one (the G85SB) is a sampled skip, not a classified verdict:\n\(notListed.joined(separator: "\n"))")
        #expect(mismatches.isEmpty, "\(mismatches.count) below-top nodes whose verdict does not follow the top-mode timing:\n\(mismatches.joined(separator: "\n"))")
        #expect(classified + skippedSampledDriven.count + skippedReading.count == belowTop, "every below-top node is classified or named as skipped")
    }
}
