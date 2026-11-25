import Foundation
import Testing
@testable import WhatCableDarwinBackend
import WhatCableCore

/// Walk-side tests for the PCIe-tunnelled dock-controller continuation (plan
/// `pcie-tunnelled-usb-attribution`, the LG UltraFine 5K case):
///
/// 1. The pure `walkContinuation` seam, which IS the live collector's
///    stop/continue rule (the collector calls it directly, so these tests
///    catch a collector that stops too early: the gap the review rounds
///    named in the synthetic-chain tests, which feed the chain in by hand).
/// 2. `classifyAncestry` over a dock-controller chain WITH the bridge chain
///    recorded (the new walk's output shape).
/// 3. The m2max_macos26.6.1 corpus pin: the reporter's own probe 38 (an OLD
///    capture, stopped at the terminator) replays to tunnelled/port=nil with
///    a PCIe carrier and nil depth/root. A regression guard only: it cannot
///    validate the new walk (the capture has no bridge chain), the synthetic
///    tests above do that.
struct PCIeTunnelWalkTests {

    private func ancestor(
        className: String = "IOPP",
        serviceName: String?,
        usbIOPortPath: String? = nil,
        entryID: UInt64? = nil,
        terminatorRegistryPath: String? = nil
    ) -> USBWatcher.USBAncestor {
        USBWatcher.USBAncestor(
            className: className,
            locationID: nil,
            usbIOPortPath: usbIOPortPath,
            usbPortType: nil,
            conformsToUSBHostDevice: false,
            serviceName: serviceName,
            entryID: entryID,
            terminatorRegistryPath: terminatorRegistryPath
        )
    }

    // MARK: - The continuation seam (plan test 1)

    @Test("walkContinuation: both tunnel kinds continue to the PCIe root; native and embedded stop")
    func continuationRule() {
        // Native USB tunnel: continues (unchanged behaviour).
        #expect(USBWatcher.walkContinuation(after: "AppleUSBXHCITR") == .continueToPCIeRoot)
        // Dock-supplied PCIe xHCI controllers: continue (the fix).
        #expect(USBWatcher.walkContinuation(after: "AppleUSBXHCIFL1100") == .continueToPCIeRoot)
        #expect(USBWatcher.walkContinuation(after: "AppleASMediaUSBXHCI") == .continueToPCIeRoot)
        #expect(USBWatcher.walkContinuation(after: "AppleUSBXHCIAR") == .continueToPCIeRoot)
        // Native Apple Silicon controllers: stop.
        #expect(USBWatcher.walkContinuation(after: "AppleT8112USBXHCI") == .stop)
        #expect(USBWatcher.walkContinuation(after: "AppleT6000USBXHCI") == .stop)
        // Apple-embedded board controllers (desktop built-in wiring,
        // discussion #417): stop, and never PCIe-carried.
        #expect(USBWatcher.walkContinuation(after: "AppleEmbeddedUSBXHCIFL1100") == .stop)
        #expect(USBWatcher.walkContinuation(after: "AppleEmbeddedUSBXHCIASMedia3142") == .stop)
        // Non-controller classes: stop (never consulted in practice; the
        // collector only asks for isWalkTerminator classes).
        #expect(USBWatcher.walkContinuation(after: "AppleUSB20Hub") == .stop)
    }

    // MARK: - Dock-controller chain classification (plan test 2)

    @Test("classifyAncestry: FL1100 chain WITH bridge chain yields PCIe carrier + depth + root")
    func dockControllerChainWithBridge() {
        // The new walk's output shape for an LG UltraFine-class monitor:
        // device -> hub port -> FL1100 controller, then the continuation's
        // pci-bridge chain up to the strict apciecN root.
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleUSB30HubPort", serviceName: nil),
            ancestor(className: "AppleUSBXHCIFL1100", serviceName: "AppleUSBXHCIFL1100"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pcic1-bridge"),
            ancestor(className: "AppleT6000PCIeC", serviceName: "AppleT6000PCIeC"),
            ancestor(serviceName: "apciec1"),
        ]
        let c = USBWatcher.classifyAncestry(ancestors, model: nil)
        #expect(c.tunnelled == true)
        #expect(c.carrier == .pcieTunnel)
        #expect(c.tunnelBridgeDepth == 2)
        #expect(c.tunnelRootName == "apciec1")
        #expect(c.portName == nil)
        #expect(c.reachedNativeController == false)
        #expect(c.reachedEmbeddedController == false)
    }

    // MARK: - Stage B v2 capture timing (plan test 14a)

    @Test("classifyAncestry: the saved controller path names the CONTROLLER node, not a bridge or apciecN; ancestor entry IDs start at the controller")
    func stageBCaptureTiming() {
        // Same shape as `dockControllerChainWithBridge` above, but with
        // `entryID` on every hop and `terminatorRegistryPath` set ONLY on
        // the FL1100 controller ancestor (index 1), mirroring the live
        // collector's capture-timing rule: the path is saved AT the
        // terminator hit, before the continuation walk advances. If a future
        // regression moved the capture to fire after the walk (recording
        // whatever node it happened to end on), this test would see the
        // apciec1 or a bridge node's path instead of the controller's own.
        let controllerPath = "IOService:/AppleARMPE/arm-io/usb-drd0@fake/AppleUSBXHCIFL1100@0"
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleUSB30HubPort", serviceName: nil, entryID: 1),
            ancestor(
                className: "AppleUSBXHCIFL1100", serviceName: "AppleUSBXHCIFL1100",
                entryID: 100, terminatorRegistryPath: controllerPath
            ),
            ancestor(serviceName: "IOPP", entryID: 101),
            ancestor(serviceName: "pci-bridge", entryID: 102),
            ancestor(serviceName: "IOPP", entryID: 103),
            ancestor(serviceName: "pci-bridge", entryID: 104),
            ancestor(serviceName: "IOPP", entryID: 105),
            ancestor(serviceName: "pcic1-bridge", entryID: 106),
            ancestor(className: "AppleT6000PCIeC", serviceName: "AppleT6000PCIeC", entryID: 107),
            ancestor(serviceName: "apciec1", entryID: 108),
        ]
        let c = USBWatcher.classifyAncestry(ancestors, model: nil)
        #expect(c.tunnelControllerRegistryPath == controllerPath,
            "the saved path must name the controller (entryID 100), never a bridge hop or the apciec1 root")
        #expect(c.tunnelAncestorEntryIDs == [100, 101, 102, 103, 104, 105, 106, 107, 108],
            "the entry-ID list starts AT the controller (its own id first) and includes every hop up to and including the apciecN root")
    }

    @Test("classifyAncestry: XHCITR chain is unchanged and carries the USB carrier")
    func usbTunnelChainUnchanged() {
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleUSBXHCITR", serviceName: "AppleUSBXHCITR"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "apciec2"),
        ]
        let c = USBWatcher.classifyAncestry(ancestors, model: nil)
        #expect(c.tunnelled == true)
        #expect(c.carrier == .usbTunnel)
        #expect(c.tunnelBridgeDepth == 2)
        #expect(c.tunnelRootName == "apciec2")
    }

    @Test("classifyAncestry: embedded controller never continues and never gets a PCIe carrier")
    func embeddedControllerStops() {
        // Even if extra ancestors WERE somehow present past an embedded
        // controller (they never are: the collector stops), classification
        // must not read them: the terminator decides, and embedded means
        // built-in wiring, not a tunnel.
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleEmbeddedUSBXHCIFL1100", serviceName: "AppleEmbeddedUSBXHCIFL1100"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "apciec0"),
        ]
        let c = USBWatcher.classifyAncestry(ancestors, model: nil)
        #expect(c.tunnelled == false)
        #expect(c.carrier == nil)
        #expect(c.tunnelBridgeDepth == nil)
        #expect(c.tunnelRootName == nil)
        #expect(c.reachedEmbeddedController == true)
    }

    // MARK: - Corpus pin: the reporter's capture (plan test 12, regression guard only)

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    /// Parse one probe-38 ancestor line (helper duplicated from
    /// `USBWatcherCorpusSweepTests` per the house copy rule).
    private static func parseAncestorLine(_ line: String) -> USBWatcher.USBAncestor? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), let closeBracket = trimmed.firstIndex(of: "]") else { return nil }
        let rest = trimmed[trimmed.index(after: closeBracket)...].trimmingCharacters(in: .whitespaces)
        var className: String?
        var locationID: UInt32?
        var usbPortType: Int?
        var usbIOPort: String?
        var usbHostDevice = false
        var serviceName: String?
        // Stage B v2: accepted, not required. `entryID=` is a NEW token
        // (the private design note "PCIe-tunnelled USB attribution"); older captures
        // never had it and must still parse (the `default: break` below
        // already makes any unrecognised token harmless, this just also
        // extracts the one this file's tests care about).
        var entryID: UInt64?
        for token in rest.split(separator: " ") {
            guard let eq = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<eq])
            let value = String(token[token.index(after: eq)...])
            switch key {
            case "class": className = value
            case "locationID":
                var hex = value
                if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex = String(hex.dropFirst(2)) }
                locationID = UInt32(hex, radix: 16)
            case "USBPortType": usbPortType = Int(value)
            case "UsbIOPort": usbIOPort = value
            case "usbHostDevice": usbHostDevice = value == "1"
            case "name": serviceName = value
            case "entryID": entryID = UInt64(value)
            default: break
            }
        }
        guard let className else { return nil }
        let conforms = usbHostDevice || className == "IOUSBHostDevice"
        return USBWatcher.USBAncestor(
            className: className, locationID: locationID, usbIOPortPath: usbIOPort,
            usbPortType: conforms ? usbPortType : nil,
            conformsToUSBHostDevice: conforms, serviceName: serviceName,
            entryID: entryID
        )
    }

    // MARK: - New probe-38 format replay (review finding: Stage B evidence)

    @Test("Extended probe-38 format: continuation rows replay to bridge depth + root through the real parser and classifier")
    func newProbeFormatReplaysBridgeChain() {
        // The exact shape the extended probe emits for an FL1100 behind a
        // PCIe tunnel: numbered continuation rows with name= tokens ABOVE
        // the controller marker (which the block parsers treat as
        // end-of-ancestors).
        let lines = [
            "    [0] class=AppleUSB30HubPort locationID=0x20540000",
            "    [1] class=AppleUSBXHCIFL1100 locationID=0x20000000",
            "    [2] class=IOPP name=IOPP",
            "    [3] class=IOPCIDevice name=pci-bridge",
            "    [4] class=IOPP name=IOPP",
            "    [5] class=IOPCIDevice name=pci-bridge",
            "    [6] class=IOPP name=IOPP",
            "    [7] class=IOPCIDevice name=pcic1-bridge",
            "    [8] class=AppleT6000PCIeC name=AppleT6000PCIeC",
            "    [9] class=IOPlatformDevice name=apciec1",
        ]
        let ancestors = lines.compactMap { Self.parseAncestorLine($0) }
        #expect(ancestors.count == 10, "all rows incl. continuation parse as ancestors, got \(ancestors.count)")
        let c = USBWatcher.classifyAncestry(ancestors, model: nil)
        #expect(c.tunnelled == true)
        #expect(c.carrier == .pcieTunnel)
        #expect(c.tunnelBridgeDepth == 2, "two pci-bridge names between controller and root")
        #expect(c.tunnelRootName == "apciec1")
    }

    /// Parses probe 38's terminal marker line, e.g.
    /// `"    (reached host controller: AppleUSBXHCIFL1100) path=IOService:/fake/AppleUSBXHCIFL1100@0"`.
    /// This IS the testable seam the review finding asked for: a Swift-side
    /// replay parser for the marker line's `path=` token, factored out so a
    /// C-side format regression (the token dropped, moved, or corrupted)
    /// shows up as a parse/assertion failure here rather than the test
    /// silently never looking at that part of the line (review finding,
    /// MEDIUM, round 2026-08-13).
    private static func parseMarkerLine(_ line: String) -> (controllerClass: String, path: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("(reached host controller: "),
              let close = trimmed.firstIndex(of: ")")
        else { return nil }
        let controllerClass = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: "(reached host controller: ".count)..<close])
        let rest = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("path=") else { return (controllerClass, nil) }
        return (controllerClass, String(rest.dropFirst("path=".count)))
    }

    @Test("Test 14b: probe-38 golden shape - entryID= on ancestor/continuation rows and path= after the marker are accepted, not required, and don't disturb classification")
    func probe38GoldenShapeAcceptsNewTokens() throws {
        // The controller's saved registry path: named as a constant, both
        // baked into the fixture line below AND asserted against after
        // parsing, so the assertion actually exercises the marker-line
        // parser rather than restating a literal the test never reads back.
        let savedControllerPath = "IOService:/fake/AppleUSBXHCIFL1100@0"

        // OLD shape (pre-Stage-B-v2): no entryID=, no path=. Must keep
        // classifying exactly as before.
        let oldLines = [
            "    [0] class=AppleUSB30HubPort locationID=0x20540000",
            "    [1] class=AppleUSBXHCIFL1100 locationID=0x20000000",
            "    [2] class=IOPP name=IOPP",
            "    [3] class=IOPCIDevice name=pci-bridge",
            "    [4] class=IOPP name=IOPP",
            "    [5] class=IOPCIDevice name=pci-bridge",
            "    [6] class=IOPP name=IOPP",
            "    [7] class=IOPCIDevice name=pcic1-bridge",
            "    [8] class=AppleT6000PCIeC name=AppleT6000PCIeC",
            "    [9] class=IOPlatformDevice name=apciec1",
            "    (reached host controller: AppleUSBXHCIFL1100)",
        ]
        // NEW shape: entryID= appended to every ancestor/continuation row
        // (before UsbIOPort=, per the format rule), and path= appended
        // after the "(reached host controller: ...)" marker.
        let newLines = [
            "    [0] class=AppleUSB30HubPort locationID=0x20540000 entryID=1",
            "    [1] class=AppleUSBXHCIFL1100 locationID=0x20000000 entryID=100",
            "    [2] class=IOPP name=IOPP entryID=101",
            "    [3] class=IOPCIDevice name=pci-bridge entryID=102",
            "    [4] class=IOPP name=IOPP entryID=103",
            "    [5] class=IOPCIDevice name=pci-bridge entryID=104",
            "    [6] class=IOPP name=IOPP entryID=105",
            "    [7] class=IOPCIDevice name=pcic1-bridge entryID=106",
            "    [8] class=AppleT6000PCIeC name=AppleT6000PCIeC entryID=107",
            "    [9] class=IOPlatformDevice name=apciec1 entryID=108",
            "    (reached host controller: AppleUSBXHCIFL1100) path=\(savedControllerPath)",
        ]

        let oldAncestors = oldLines.compactMap { Self.parseAncestorLine($0) }
        let newAncestors = newLines.compactMap { Self.parseAncestorLine($0) }
        // The marker line itself never matches "[", so it contributes no
        // ancestor row in either shape (confirmed by the count staying 10
        // for both): the trailing " path=..." never even reaches the
        // per-row tokenizer this file replays through.
        #expect(oldAncestors.count == 10)
        #expect(newAncestors.count == 10)

        // The marker line itself, actually parsed (the review fix): the OLD
        // shape carries no path= token at all; the NEW shape's path= must
        // equal the saved controller path EXACTLY, naming the controller
        // node (class AppleUSBXHCIFL1100) and nothing else -- not
        // "pcic1-bridge", not "apciec1", both of which appear as ancestor
        // ROW names above but must never leak into the marker's path.
        let oldMarker = try #require(Self.parseMarkerLine(oldLines.last!))
        #expect(oldMarker.controllerClass == "AppleUSBXHCIFL1100")
        #expect(oldMarker.path == nil, "old shape carries no path= token")

        let newMarker = try #require(Self.parseMarkerLine(newLines.last!))
        #expect(newMarker.controllerClass == "AppleUSBXHCIFL1100")
        #expect(newMarker.path == savedControllerPath,
            "the marker's path= must equal the saved controller path, not a bridge or apciecN name")

        let oldClassification = USBWatcher.classifyAncestry(oldAncestors, model: nil)
        let newClassification = USBWatcher.classifyAncestry(newAncestors, model: nil)
        #expect(oldClassification.tunnelled == newClassification.tunnelled)
        #expect(oldClassification.carrier == newClassification.carrier)
        #expect(oldClassification.tunnelBridgeDepth == newClassification.tunnelBridgeDepth)
        #expect(oldClassification.tunnelRootName == newClassification.tunnelRootName)
        // The new tokens DO add information when present: entryID threads
        // through to tunnelAncestorEntryIDs.
        #expect(oldClassification.tunnelAncestorEntryIDs.isEmpty, "old shape has no entryID tokens, so nothing to thread")
        #expect(newClassification.tunnelAncestorEntryIDs == [100, 101, 102, 103, 104, 105, 106, 107, 108])
    }

    @Test("m2max_macos26.6.1 pin: the LG's 8 devices replay tunnelled/port=nil with PCIe carrier, nil depth+root; the 19 native devices keep their ports")
    func reporterCapturePin() throws {
        let url = Self.probeRoot
            .appendingPathComponent("m2max_macos26.6.1")
            .appendingPathComponent("38_usb_device_tree.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["output"] as? String else {
            // Raw probe 38 is gitignored for this folder; on a fresh clone or
            // unlinked worktree this pin has no input. The corpus-presence CI
            // check keeps this from silently skipping everywhere.
            return
        }
        var tunnelledCount = 0
        var nativeCount = 0
        for block in text.components(separatedBy: "--- Device[").dropFirst() {
            let ancestors = block.split(separator: "\n").compactMap { Self.parseAncestorLine(String($0)) }
            guard !ancestors.isEmpty else { continue }
            let c = USBWatcher.classifyAncestry(ancestors, model: nil)
            if c.tunnelled {
                tunnelledCount += 1
                #expect(c.carrier == .pcieTunnel, "every tunnelled device in this capture is on the LG's FL1100")
                #expect(c.portName == nil)
                // Old capture shape: the probe stopped at the terminator, so
                // depth/root replay honestly nil (the failure invariant).
                #expect(c.tunnelBridgeDepth == nil)
                #expect(c.tunnelRootName == nil)
            } else {
                nativeCount += 1
                #expect(c.portName != nil, "native devices in this capture all carry a UsbIOPort port name")
            }
        }
        // Floors, so a parser regression shows as a failure rather than a
        // clean run: the capture holds 8 FL1100 devices and 19 native ones.
        #expect(tunnelledCount == 8, "expected the LG's 8 devices, got \(tunnelledCount)")
        #expect(nativeCount == 19, "expected 19 native devices, got \(nativeCount)")
    }
}
