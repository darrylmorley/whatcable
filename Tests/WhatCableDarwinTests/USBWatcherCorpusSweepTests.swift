import Foundation
import Testing
@testable import WhatCableDarwinBackend
import WhatCableCore

// MARK: - USBWatcherCorpusSweepTests
//
// Corpus-replay coverage for `USBWatcher`'s hub-nesting / tunnel classification
// (Watchers/USBWatcher.swift).
//
// SEAM NOTE (read this before extending): the classification walk is the pure
// `nonisolated static` function `USBWatcher.classifyAncestry(_:)`, which takes
// the ancestor chain as plain `USBAncestor` values. The live half
// (`collectAncestors`, private, live `io_service_t`) only gathers those values
// from IOKit and never decides anything, so replaying probe 38's recorded
// ancestor chains through `classifyAncestry` runs the REAL production walk,
// not a mirror of it. (An earlier revision of this file kept a test-local copy
// of the loop because the walk was in-line in `controllerInfo`; the seam
// extraction removed that caveat.) Still unreachable without IOKit:
// `makeDevice(from:)` (property extraction from a live service) and
// `collectAncestors` itself.
//
// `Tests/WhatCableDarwinTests/RegistryParsingTests.swift` unit-tests the
// smaller pure helpers (`usbIOPortPath`, `portName(fromUSBIOPortPath:)`,
// `busIndex`, `isThunderboltDockController`, `classifyBehindInternalHub`)
// against hand-crafted fixtures. This file is complementary: it replays the
// exact ancestor chains IOKit reported on real machines (probe 38,
// `usb_device_tree`, 64 folders with device blocks as of 2026-07) through
// `classifyAncestry`, plus named-machine ground-truth pins on git-tracked
// fixture captures.
//
// Probe 36 (`xhci_port_map`) is used more lightly: it gives a ground-truth
// XHCI-port-locationID -> usb-c-port-number map, used to sanity-check
// `busIndex(fromLocationID:)` against real device/port locationID pairs.
@Suite("USBWatcher corpus sweep - hub nesting and tunnel classification")
struct USBWatcherCorpusSweepTests {

    // MARK: - Probe root (duplicated across sweep files by house convention)

    private static let probeRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableDarwinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    private static func allProbeFolders() -> [String] {
        (try? FileManager.default
            .contentsOfDirectory(atPath: probeRoot.path)
            .filter { entry in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(
                    atPath: probeRoot.appendingPathComponent(entry).path,
                    isDirectory: &isDir
                )
                return isDir.boolValue
            }
            .sorted()
        ) ?? []
    }

    private static func loadProbeText(folder: String, fileName: String) -> String? {
        let url = probeRoot.appendingPathComponent(folder).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = root["output"] as? String
        else { return nil }
        return text
    }

    // MARK: - Probe-38 parsing
    //
    // Probe 38's own header says: "Mirrors USBWatcher.controllerInfo: each
    // device, then its IOService-plane ancestors up to the host controller,
    // with class / USBPortType / UsbIOPort." Format (verified against the
    // corpus directly, 2026-07):
    //
    //   --- Device[N] ---
    //     USB Product Name = "..."
    //     locationID = 0xHEX
    //     ...
    //     Ancestors (device -> controller):
    //       [0] class=ClassName locationID=0xHEX
    //       [1] class=ClassName locationID=0xHEX USBPortType=N
    //       [2] class=ClassName locationID=0xHEX UsbIOPort=IOService:/.../Port-USB-C@N
    //       (reached host controller: ClassName)

    struct Ancestor {
        let className: String
        let locationID: UInt32?
        let usbPortType: Int?
        let usbIOPort: String?
        /// The `usbHostDevice=1` marker (probe 38 prints it when the node
        /// conforms to IOUSBHostDevice; added 2026-07). Absent on captures
        /// from before the marker existed.
        let usbHostDevice: Bool
        /// The `name=` token: the IOService name, printed by the tunnel
        /// continuation rows the extended probe emits above the controller
        /// marker (pci-bridge chain + apciecN root). Absent on older
        /// captures and on pre-controller rows, exactly as the live
        /// collector's serviceName read can be.
        let serviceName: String?

        init(
            className: String, locationID: UInt32?, usbPortType: Int?,
            usbIOPort: String?, usbHostDevice: Bool, serviceName: String? = nil
        ) {
            self.className = className
            self.locationID = locationID
            self.usbPortType = usbPortType
            self.usbIOPort = usbIOPort
            self.usbHostDevice = usbHostDevice
            self.serviceName = serviceName
        }
    }

    struct DeviceBlock {
        let locationID: UInt32
        let ancestors: [Ancestor]
        /// The device's own `bDeviceClass = N` line (9 = hub). Feeds the
        /// embedded-branch plumbing rule.
        let deviceClass: UInt8?
        /// The device's own `USBPortType = N` line (new captures), or nil.
        /// Older captures lack it; `ownPortTypes(in:)` then derives hub
        /// values from other chains' ancestor rows.
        let ownUSBPortType: Int?
        /// The class name from the probe's own "(reached host controller: X)"
        /// line, or nil when the capture's walk never found one. This is the
        /// probe's independent (C-side) stop decision, cross-checked against
        /// the Swift classification in the sweep.
        let probeStopClass: String?
    }

    /// Parse one ancestor line, e.g.:
    ///   "[3] class=AppleUSB30HubPort locationID=0x22120000 USBPortType=0"
    ///   "[2] class=IOUSBHostDevice locationID=0x3200000 USBPortType=5 usbHostDevice=1"
    ///   "[0] class=AppleUSB30XHCIARMPort locationID=0x100000 UsbIOPort=IOService:/.../Port-USB-C@1"
    private static func parseAncestorLine(_ line: String) -> Ancestor? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), let closeBracket = trimmed.firstIndex(of: "]") else { return nil }
        let rest = trimmed[trimmed.index(after: closeBracket)...].trimmingCharacters(in: .whitespaces)
        let tokens = rest.split(separator: " ")

        var className: String?
        var locationID: UInt32?
        var usbPortType: Int?
        var usbIOPort: String?
        var usbHostDevice = false
        var serviceName: String?

        for token in tokens {
            guard let eq = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<eq])
            let value = String(token[token.index(after: eq)...])
            switch key {
            case "class":
                className = value
            case "locationID":
                var hex = value
                if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex = String(hex.dropFirst(2)) }
                locationID = UInt32(hex, radix: 16)
            case "USBPortType":
                usbPortType = Int(value)
            case "UsbIOPort":
                usbIOPort = value
            case "usbHostDevice":
                usbHostDevice = value == "1"
            case "name":
                serviceName = value
            default:
                break
            }
        }
        guard let className else { return nil }
        return Ancestor(
            className: className, locationID: locationID, usbPortType: usbPortType,
            usbIOPort: usbIOPort, usbHostDevice: usbHostDevice, serviceName: serviceName
        )
    }

    private static func parseDeviceBlocks(_ text: String) -> [DeviceBlock] {
        text.components(separatedBy: "--- Device[").dropFirst().compactMap { block in
            var deviceLocationID: UInt32?
            var ancestors: [Ancestor] = []
            var probeStopClass: String?
            var ownUSBPortType: Int?
            var deviceClass: UInt8?
            var inAncestors = false
            for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("locationID =") || trimmed.hasPrefix("locationID=") {
                    if let eq = trimmed.firstIndex(of: "=") {
                        var hex = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex = String(hex.dropFirst(2)) }
                        deviceLocationID = UInt32(hex, radix: 16)
                    }
                    continue
                }
                if !inAncestors, trimmed.hasPrefix("USBPortType =") {
                    if let eq = trimmed.firstIndex(of: "=") {
                        ownUSBPortType = Int(trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces))
                    }
                    continue
                }
                if !inAncestors, trimmed.hasPrefix("bDeviceClass =") {
                    if let eq = trimmed.firstIndex(of: "=") {
                        deviceClass = UInt8(trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces))
                    }
                    continue
                }
                if trimmed.hasPrefix("Ancestors") { inAncestors = true; continue }
                if trimmed.hasPrefix("(reached host controller") {
                    inAncestors = false
                    if let colon = trimmed.range(of: ": "), let close = trimmed.lastIndex(of: ")") {
                        probeStopClass = String(trimmed[colon.upperBound..<close])
                    }
                    continue
                }
                if inAncestors, trimmed.hasPrefix("[") {
                    if let ancestor = parseAncestorLine(trimmed) { ancestors.append(ancestor) }
                }
            }
            guard let loc = deviceLocationID else { return nil }
            return DeviceBlock(
                locationID: loc, ancestors: ancestors, deviceClass: deviceClass,
                ownUSBPortType: ownUSBPortType, probeStopClass: probeStopClass
            )
        }
    }

    /// Own-`USBPortType` per locationID, derived from ancestor rows: an
    /// `IOUSBHostDevice` ancestor at locationID X carrying `USBPortType=N`
    /// IS device X's node, so N is X's own value. Pre-marker captures have
    /// no per-device `USBPortType =` line; this map recovers it for hubs
    /// (the only devices whose own value matters to the classifier).
    private static func ownPortTypes(in blocks: [DeviceBlock]) -> [UInt32: Int] {
        var map: [UInt32: Int] = [:]
        for block in blocks {
            for a in block.ancestors {
                if a.className == "IOUSBHostDevice" || a.usbHostDevice,
                   let loc = a.locationID, let pt = a.usbPortType {
                    map[loc] = pt
                }
            }
        }
        return map
    }

    // MARK: - Replay through the production classifier
    //
    // Probe 38's ancestor list IS the walk `collectAncestors` performs live
    // (the probe mirrors it hop for hop, including the conformance gate on
    // USBPortType). Rebuilding `USBAncestor` values from the capture and
    // calling `USBWatcher.classifyAncestry` therefore runs the real
    // production classification, not a test-local copy of it.
    struct WalkResult {
        let portName: String?
        let tunnelled: Bool
        let reachedNativeController: Bool
        let reachedEmbeddedController: Bool
        let bus: Int
        let behindInternalHub: Bool
    }

    private static func productionAncestors(_ ancestors: [Ancestor]) -> [USBWatcher.USBAncestor] {
        ancestors.map { a in
            // Conformance gate: the live collector only reads USBPortType on
            // nodes conforming to IOUSBHostDevice. New captures record that
            // gate as `usbHostDevice=1`; older captures don't, but there the
            // exact class name is a verified equivalent (766/766 USBPortType=
            // occurrences across the 2026-07 corpus sit on a line whose class
            // IS "IOUSBHostDevice", re-derived with an independent Python
            // parser before this number was written down).
            let conforms = a.usbHostDevice || a.className == "IOUSBHostDevice"
            return USBWatcher.USBAncestor(
                className: a.className,
                locationID: a.locationID,
                usbIOPortPath: a.usbIOPort,
                usbPortType: conforms ? a.usbPortType : nil,
                conformsToUSBHostDevice: conforms,
                // Old captures stop at the terminator with no `name=` token,
                // so this replays nil there (`tunnelBridgeAncestry` then
                // honestly reports no bridge depth). Captures from the
                // extended probe carry the continuation rows' names, so the
                // bridge chain replays for real.
                serviceName: a.serviceName
            )
        }
    }

    private static func replayWalk(
        deviceLocationID: UInt32,
        ancestors: [Ancestor],
        ownUSBPortType: Int? = nil,
        deviceClass: UInt8? = nil
    ) -> WalkResult {
        let c = USBWatcher.classifyAncestry(
            productionAncestors(ancestors),
            ownUSBPortType: ownUSBPortType,
            deviceClass: deviceClass
        )
        return WalkResult(
            portName: c.portName,
            tunnelled: c.tunnelled,
            reachedNativeController: c.reachedNativeController,
            reachedEmbeddedController: c.reachedEmbeddedController,
            bus: c.busIndex ?? USBWatcher.busIndex(fromLocationID: deviceLocationID),
            behindInternalHub: c.behindInternalHub
        )
    }

    // MARK: - Corpus sweep: probe 38

    @Test("Probe-38 sweep: hub-nesting classification never crashes and its structural implications hold")
    func probe38SweepStructuralInvariants() {
        var filesOnDisk = 0
        var foldersScanned = 0
        var devicesTotal = 0
        var tunnelledCount = 0
        var nativeCount = 0
        var behindInternalHubCount = 0
        var namedPortCount = 0
        var dockControllerCount = 0

        for folder in Self.allProbeFolders() {
            let fileURL = Self.probeRoot.appendingPathComponent(folder)
                .appendingPathComponent("38_usb_device_tree.json")
            if FileManager.default.fileExists(atPath: fileURL.path) { filesOnDisk += 1 }
            guard let text = Self.loadProbeText(folder: folder, fileName: "38_usb_device_tree.json") else { continue }
            let blocks = Self.parseDeviceBlocks(text)
            guard !blocks.isEmpty else { continue }
            foldersScanned += 1
            let ownPT = Self.ownPortTypes(in: blocks)

            for block in blocks {
                devicesTotal += 1
                let result = Self.replayWalk(
                    deviceLocationID: block.locationID,
                    ancestors: block.ancestors,
                    ownUSBPortType: block.ownUSBPortType ?? ownPT[block.locationID],
                    deviceClass: block.deviceClass
                )

                if result.tunnelled { tunnelledCount += 1 }
                if result.reachedNativeController { nativeCount += 1 }
                if result.behindInternalHub { behindInternalHubCount += 1 }
                if result.portName != nil { namedPortCount += 1 }
                if block.ancestors.contains(where: { USBWatcher.isThunderboltDockController($0.className) }) {
                    dockControllerCount += 1
                }

                // Cross-check against the probe's own stop decision: the C
                // probe implements the same stop boundary (tunnel / native /
                // dock; its dock rule also covers the embedded controllers
                // Swift now categorises separately) independently and records
                // which class ended its walk. When it recorded one, the Swift
                // classification must have terminated too; when it didn't,
                // none of the outcomes may fire. This is a genuine
                // two-implementation check: C in the probe, Swift in
                // classifyAncestry.
                let swiftStopped = result.tunnelled || result.reachedNativeController
                    || result.reachedEmbeddedController
                #expect(swiftStopped == (block.probeStopClass != nil),
                    "\(folder): device at 0x\(String(block.locationID, radix: 16)): probe stop \(block.probeStopClass ?? "none") disagrees with Swift classification (tunnelled=\(result.tunnelled), native=\(result.reachedNativeController))")

                // Invariant 1: tunnelled devices are never classified behind the
                // internal hub (classifyBehindInternalHub requires !tunnelled).
                #expect(!(result.tunnelled && result.behindInternalHub),
                    "\(folder): device at 0x\(String(block.locationID, radix: 16)) is both tunnelled and behind-internal-hub")

                // Invariant 2: on non-embedded walks, a device with a
                // resolved port name is never classified behind the internal
                // hub (classifyBehindInternalHub requires portName == nil).
                // Embedded walks are the exception by design: the shared
                // board node (Port-USB-A@1) stays on the record as raw
                // registry truth, and the built-in classification comes from
                // the controller, not the name.
                #expect(!(result.portName != nil && result.behindInternalHub && !result.reachedEmbeddedController),
                    "\(folder): device at 0x\(String(block.locationID, radix: 16)) has portName \(result.portName ?? "?") but is behind-internal-hub via the native path")

                // Invariant 3: behind-internal-hub requires having reached
                // either a native controller (the #348 no-port-node path) or
                // an Apple-embedded board controller (the #417 path).
                #expect(!(!result.reachedNativeController && !result.reachedEmbeddedController && result.behindInternalHub),
                    "\(folder): device at 0x\(String(block.locationID, radix: 16)) reached no native or embedded controller but is behind-internal-hub")

                // Invariant 4: bus index is always a plausible byte value
                // (busIndex(fromLocationID:) masks to 0xFF by construction, so
                // this also guards against a future signature change breaking
                // that guarantee silently).
                #expect((0...255).contains(result.bus),
                    "\(folder): bus index \(result.bus) out of byte range")

                // Invariant 5: portName, when present, always starts with "Port-"
                // (usbIOPortPath/portName's own contract; re-asserted here against
                // real corpus paths rather than hand-written ones).
                if let name = result.portName {
                    #expect(name.hasPrefix("Port-"), "\(folder): portName \(name) missing Port- prefix")
                }
            }
        }

        print("[USBWatcherSweep] probe38: \(foldersScanned) folders, \(devicesTotal) devices, "
            + "\(nativeCount) native, \(tunnelledCount) tunnelled (\(dockControllerCount) via dock controller), "
            + "\(namedPortCount) named, \(behindInternalHubCount) behind-internal-hub")

        // Coverage floor: actual 64 folders, 656 devices as of 2026-07-14
        // (grew from 30/322 with the 2026-07-13 test-kit batch; both numbers
        // re-derived with an independent Python parser over the raw corpus
        // before being written here). Floor set to ~85% of actual (54 folders,
        // 557 devices), not an arbitrary small number, so a regression that
        // silently dropped most blocks would fail this test.
        //
        // Two-tier reality: only 6 probe-38 files are git-tracked (the
        // Probe38TreeWalkTests fixture plus the 5 named-machine fixtures
        // below); the rest are on-disk-only. Gate the floor on the number of
        // probe-38 FILES physically present (20: comfortably above the 6-file
        // fresh-clone case, comfortably below the full corpus), NOT on how
        // many folders parsed: gating on the parsed count would let a parser
        // or loader regression shrink the corpus below the gate and skip the
        // floor silently (raised in the 2026-07 code review). With the file
        // count as the gate, a full corpus that stops parsing fails loudly.
        if filesOnDisk >= 20 {
            #expect(foldersScanned >= 54,
                "Expected at least 54 folders with probe-38 device blocks; got \(foldersScanned)")
            #expect(devicesTotal >= 557,
                "Expected at least 557 probe-38 device blocks across the corpus; got \(devicesTotal)")
            // The corpus has real Thunderbolt-dock topologies (CalDigit TS3+,
            // confirmed in research/thunderbolt-fabric.md); the dock-controller branch must fire at
            // least once or `isThunderboltDockController` regressed silently.
            #expect(dockControllerCount >= 1,
                "Expected at least one device reached via a Thunderbolt dock controller")
            // At least one device must resolve a named physical port, or the
            // UsbIOPort extraction regressed silently.
            #expect(namedPortCount >= 1,
                "Expected at least one device to resolve a named Port- ancestor")
        }
    }

    // MARK: - Fixture: the #375/#348 desktop front-port scenario
    //
    // In the real corpus (probe 38, 64 folders as of 2026-07-14) the devices
    // that classify behind-internal-hub are exactly the AppleEmbedded*
    // chains (Mac Studio front/USB-A, M1 mini USB-A; the #417 fix, see the
    // named-machine tests below). No corpus device reaches the gate via the
    // native-controller path: every USBPortType==2 case on a native chain
    // resolves a named board port first (M4 mini on Tahoe: Port-USB-C@6).
    // The one true "no port node at all" front-port case (issue #348: a front
    // USB-C port wired to the internal hub with no board port node, the shape
    // the original #348 reporter's Sequoia mini had) is documented in
    // project_desktop_front_ports_behind_hub but isn't present in this probe's
    // on-disk corpus. `RegistryParsingTests.swift` already covers this exact
    // scenario as an isolated fixture; it is restated here, driven through the
    // SAME `replayWalk` harness the corpus sweep above uses, so the harness
    // itself is proven correct against a known-true case rather than only
    // being exercised by ambiguous real data.
    @Test("Fixture: no-UsbIOPort ancestor reaching a USBPortType==2 hub classifies behind-internal-hub")
    func fixtureDesktopFrontPortWithNoPortNode() {
        let ancestors: [Ancestor] = [
            Ancestor(className: "IOUSBHostDevice", locationID: 0x0100_0000, usbPortType: 2, usbIOPort: nil, usbHostDevice: true),
            Ancestor(className: "AppleT8103USBXHCI", locationID: 0x0100_0000, usbPortType: nil, usbIOPort: nil, usbHostDevice: false),
        ]
        let result = Self.replayWalk(deviceLocationID: 0x0102_0000, ancestors: ancestors)
        #expect(result.portName == nil)
        #expect(result.reachedNativeController)
        #expect(!result.tunnelled)
        #expect(result.behindInternalHub, "expected the no-port-node + internal-hub + native-controller case to classify true")
        #expect(result.bus == 1)
    }

    @Test("Fixture: same shape but external hub (USBPortType==0) does not classify behind-internal-hub")
    func fixtureExternalHubWithNoPortNode() {
        let ancestors: [Ancestor] = [
            Ancestor(className: "IOUSBHostDevice", locationID: 0x0100_0000, usbPortType: 0, usbIOPort: nil, usbHostDevice: true),
            Ancestor(className: "AppleT8103USBXHCI", locationID: 0x0100_0000, usbPortType: nil, usbIOPort: nil, usbHostDevice: false),
        ]
        let result = Self.replayWalk(deviceLocationID: 0x0102_0000, ancestors: ancestors)
        #expect(!result.behindInternalHub, "external hub (USBPortType != 2) must not classify as behind-internal-hub")
    }

    // MARK: - Fixture: the #430 dock-on-a-front-port scenario
    //
    // Modelled from @jimmyorz's real M4 mini `ioreg -rl -c IOUSBHostDevice`
    // dump (issue #430). The one signal that decides the classification is
    // whether a USBPortType==2 hub (the Mac's internal front-panel hub) appears
    // ANYWHERE in the chain, not just as the nearest hub.
    //
    // Three chains, chosen so each pins a distinct decision:
    //
    //   A. Front port, external hub in the way (the #430 fix). Chain is
    //        device -> external hub (0) -> Mac internal hub (2) -> controller.
    //      The device's NEAREST hub is external (0), but the chain still passes
    //      THROUGH the internal hub (2), so it MUST classify behind-internal-hub
    //      (it shows nested under its hub in "Built-in USB ports"). This is the
    //      one shape where the old nearest-hub rule and the new whole-chain rule
    //      DIVERGE: the old rule read 0 from the nearest hub and stopped, giving
    //      false. Reverting the fix flips this #expect, so this is the real,
    //      non-vacuous regression guard for the change.
    //
    //      This chain is a dock's downstream device (#430's flash drive), but it
    //      is deliberately ALSO the shape of a plain third-party hub with a
    //      keyboard on a front port: by design #430 groups anything reachable
    //      via a front port under "Built-in USB ports", nested under whatever
    //      hub it hangs off. There is no reliable dock-vs-hub signal to treat
    //      the two differently, and nesting under the hub reads correctly either
    //      way.
    //
    //   B. Rear/direct port, external hub, NO internal hub in the chain (#373's
    //      actual reported case, same machine). Chain is
    //        device -> external hub (0) -> controller.
    //      Must stay OUT of "Built-in USB ports". Both the old and new rules
    //      agree here (no USBPortType==2 ancestor), so this does NOT discriminate
    //      old vs new; it exists to pin that #373's reported topology is
    //      unaffected. Asserted with the same prerequisite checks as A so it
    //      can't pass vacuously (e.g. by silently failing to reach the
    //      controller or by resolving a port name).
    //
    //   C. Front port again, but a stray USBPortType==2 node sits ABOVE the
    //      terminating controller. Pins the break semantics: the walk stops at
    //      the controller, so an ancestor beyond it must NOT set the flag. Here
    //      there is no internal hub BEFORE the controller, so it must classify
    //      false; if the loop ever read past the terminator it would wrongly be
    //      true.
    @Test("Fixture #430: internal hub anywhere in the chain -> behind-internal-hub; rear external hub and post-controller nodes stay out")
    func fixtureDockOnFrontPortClassifiesBehindInternalHub() {
        // A. USB DISK 3.0@02213000 -> dock USB3.1 Hub@02210000 (0)
        //    -> internal USB3 Gen2 Hub@02200000 (2) -> AppleT8132USBXHCI.
        let frontPortViaExternalHub: [Ancestor] = [
            Ancestor(className: "IOUSBHostDevice", locationID: 0x0221_0000, usbPortType: 0, usbIOPort: nil, usbHostDevice: true),
            Ancestor(className: "IOUSBHostDevice", locationID: 0x0220_0000, usbPortType: 2, usbIOPort: nil, usbHostDevice: true),
            Ancestor(className: "AppleT8132USBXHCI", locationID: 0x0220_0000, usbPortType: nil, usbIOPort: nil, usbHostDevice: false),
        ]
        let front = Self.replayWalk(deviceLocationID: 0x0221_3000, ancestors: frontPortViaExternalHub)
        #expect(front.portName == nil)
        #expect(front.reachedNativeController)
        #expect(!front.tunnelled)
        #expect(front.behindInternalHub,
            "nearest hub is external (0) but the chain passes through the internal hub (2), so it must classify behind-internal-hub (#430)")

        // B. Rear/direct external hub, no internal hub anywhere: #373's reported
        // case. Same prerequisite checks as A so the negative can't pass
        // vacuously.
        let rearExternalHub: [Ancestor] = [
            Ancestor(className: "IOUSBHostDevice", locationID: 0x0110_0000, usbPortType: 0, usbIOPort: nil, usbHostDevice: true),
            Ancestor(className: "AppleT8132USBXHCI", locationID: 0x0110_0000, usbPortType: nil, usbIOPort: nil, usbHostDevice: false),
        ]
        let rear = Self.replayWalk(deviceLocationID: 0x0111_0000, ancestors: rearExternalHub)
        #expect(rear.portName == nil)
        #expect(rear.reachedNativeController)
        #expect(!rear.tunnelled)
        #expect(!rear.behindInternalHub,
            "no internal hub in the chain, so #373's reported rear/direct external-hub case stays out of Built-in USB ports")

        // C. Break semantics: a USBPortType==2 node ABOVE the controller must be
        // ignored. No internal hub before the controller here, so it stays out.
        let internalHubPastController: [Ancestor] = [
            Ancestor(className: "IOUSBHostDevice", locationID: 0x0130_0000, usbPortType: 0, usbIOPort: nil, usbHostDevice: true),
            Ancestor(className: "AppleT8132USBXHCI", locationID: 0x0130_0000, usbPortType: nil, usbIOPort: nil, usbHostDevice: false),
            Ancestor(className: "IOUSBHostDevice", locationID: 0x0130_0000, usbPortType: 2, usbIOPort: nil, usbHostDevice: true),
        ]
        let past = Self.replayWalk(deviceLocationID: 0x0131_0000, ancestors: internalHubPastController)
        #expect(!past.behindInternalHub,
            "an internal-hub node past the terminating controller must not set the flag (walk stops at the controller)")
    }

    // MARK: - Fixture: the usbHostDevice=1 marker (no corpus capture carries it yet)
    //
    // The marker started being recorded by probe 38 in this change, so no
    // corpus capture exercises the marker branch of the parser or the
    // subclass-conformance case it exists for (a future IOUSBHostDevice
    // SUBCLASS carrying USBPortType). Cover both with synthetic probe text
    // until real marked captures arrive.
    @Test("Marker fixture: usbHostDevice=1 lets a subclass's USBPortType through; unmarked subclass stays gated")
    func fixtureUsbHostDeviceMarkerGatesConformance() {
        let text = """
        --- Device[0] ---
          locationID = 0x1020000
          Ancestors (device -> controller):
            [0] class=AppleUSBHostBillboardDevice locationID=0x1000000 USBPortType=2 usbHostDevice=1
            [1] class=AppleT8103USBXHCI locationID=0x1000000
            (reached host controller: AppleT8103USBXHCI)

        --- Device[1] ---
          locationID = 0x2020000
          Ancestors (device -> controller):
            [0] class=AppleUSBHostBillboardDevice locationID=0x2000000 USBPortType=2
            [1] class=AppleT8103USBXHCI locationID=0x2000000
            (reached host controller: AppleT8103USBXHCI)
        """
        let blocks = Self.parseDeviceBlocks(text)
        #expect(blocks.count == 2)

        // Device 0: the marker says the subclass conforms, so its
        // USBPortType==2 is honoured and the device classifies
        // behind-internal-hub (native controller, no port node).
        let marked = Self.replayWalk(deviceLocationID: blocks[0].locationID, ancestors: blocks[0].ancestors)
        #expect(marked.behindInternalHub,
            "marked subclass ancestor must pass its USBPortType through to the classifier")

        // Device 1: same chain without the marker. The parser cannot assume a
        // non-exact class conforms (pre-marker rule), so the USBPortType is
        // dropped and the classification fails the internal-hub gate.
        let unmarked = Self.replayWalk(deviceLocationID: blocks[1].locationID, ancestors: blocks[1].ancestors)
        #expect(!unmarked.behindInternalHub,
            "unmarked subclass ancestor must not be assumed to conform")
    }

    // MARK: - Named-machine ground truth (git-tracked fixture captures)
    //
    // These pins run the production classifier over real captures from
    // machines whose topology is known, so a behaviour change on any of these
    // hardware classes fails loudly instead of drifting. The five fixture
    // files are git-tracked (gitignore negations), so these tests run on a
    // fresh clone; they FAIL (not skip) if a fixture goes missing, because a
    // missing fixture silently deletes the coverage.
    //
    // Folder names are positional ingest labels; each fixture's identity is
    // pinned here by its `submitted_at` from corpus.jsonl so it stays
    // re-checkable if folders are ever renamed (see the corpus rules in
    // the whatcable-process-probe skill).

    private static func requireBlocks(_ folder: String) throws -> [DeviceBlock] {
        let text = try #require(
            Self.loadProbeText(folder: folder, fileName: "38_usb_device_tree.json"),
            "git-tracked fixture \(folder)/38_usb_device_tree.json is missing"
        )
        let blocks = Self.parseDeviceBlocks(text)
        try #require(!blocks.isEmpty, "fixture \(folder) parsed to zero device blocks")
        return blocks
    }

    /// Chains that end at an Apple-embedded third-party controller
    /// (`AppleEmbedded*`): the Mac's own extra built-in plain-USB wiring
    /// (Mac Studio front ports, Mac mini USB-A block).
    private static func embeddedChains(_ blocks: [DeviceBlock]) -> [DeviceBlock] {
        blocks.filter { $0.probeStopClass?.hasPrefix("AppleEmbedded") == true }
    }

    /// Expected-plumbing derivation from the RAW capture traits (own
    /// USBPortType 2, or a hub-class device with no IOUSBHostDevice ancestor
    /// row), computed from parsed probe text without calling production
    /// code. Mirrors the production rule by design; the mutation checks
    /// prove the pairing is non-vacuous (disable the production rule and
    /// these tests go red).
    private static func expectedPlumbing(_ block: DeviceBlock, own: Int?) -> Bool {
        let hasHubAncestorRow = block.ancestors.contains {
            $0.usbHostDevice || $0.className == "IOUSBHostDevice"
        }
        return own == USBWatcher.internalHubPortType
            || (block.deviceClass == 9 && !hasHubAncestorRow)
    }

    // ISSUE #417 FIX (Mac Studio, M2 Max, submitted 2026-07-04; and M4 Max,
    // submitted 2026-06-26): the Studio's front USB-C ports and back USB-A
    // ports hang off an Apple-embedded ASMedia controller
    // (`AppleEmbeddedUSBXHCIASMedia3142`). These devices used to classify as
    // Thunderbolt-dock tunnelled, so the app grouped a Studio's own front
    // ports under "reached through a Thunderbolt dock or display", which is
    // what the discussion #417 reporter saw. They now classify
    // behind-internal-hub and render in the "Built-in USB ports" section.
    // The shared board port node (`Port-USB-A@1`, the "connected to the back
    // USBA port" detail in the report) is KEPT on the record as raw registry
    // truth (owner rule: identifiers are never dropped); display attribution
    // routes by the behindInternalHub flag, and the port-card matcher cannot
    // match a Port-USB-A name, so keeping it cannot double-render.
    @Test("Mac Studio (#417 fix): embedded-controller devices classify as built-in, not tunnelled; the Mac's own hub silicon is excluded")
    func macStudioEmbeddedControllerFix() throws {
        for folder in ["m2max_macos26.5.2", "m4max_macos26.5.1_f"] {
            let blocks = try Self.requireBlocks(folder)
            let ownPT = Self.ownPortTypes(in: blocks)
            let embedded = Self.embeddedChains(blocks)
            #expect(!embedded.isEmpty, "\(folder): expected embedded-controller chains in this Studio fixture")

            var plumbing = 0
            var userDevices = 0
            var namedBuiltIn = 0
            for block in embedded {
                let own = block.ownUSBPortType ?? ownPT[block.locationID]
                let result = Self.replayWalk(
                    deviceLocationID: block.locationID,
                    ancestors: block.ancestors,
                    ownUSBPortType: own,
                    deviceClass: block.deviceClass
                )
                #expect(result.reachedEmbeddedController)
                #expect(!result.tunnelled,
                    "\(folder): 0x\(String(block.locationID, radix: 16)) classified tunnelled; the #417 fix regressed")
                if Self.expectedPlumbing(block, own: own) {
                    // The Mac's own hub silicon: must NOT render as a
                    // connected device in the Built-in USB ports card
                    // (PR 408 review rounds one and two).
                    plumbing += 1
                    #expect(!result.behindInternalHub,
                        "\(folder): internal hub 0x\(String(block.locationID, radix: 16)) would render as a built-in device")
                } else {
                    userDevices += 1
                    #expect(result.behindInternalHub,
                        "\(folder): 0x\(String(block.locationID, radix: 16)) must land in the Built-in USB ports section")
                    // Same-device coexistence (PR 408 round-two Codex): the
                    // kept board node and the routing flag must both hold on
                    // one record, not on different devices.
                    if result.portName == "Port-USB-A@1" { namedBuiltIn += 1 }
                }
            }
            // Both Studio fixtures carry both cases, so neither branch can
            // pass vacuously: m2max has 1 own==2 hub derivable from chains
            // (0x8300000), m4max has 2 (0x8100000, 0x8300000), and both
            // have user devices behind them. Replay-data limit, documented:
            // m2max's 0x8100000 hub has no captured children, so its own
            // USBPortType is unknowable from that capture and it replays as
            // a user device; live, makeDevice reads the property directly,
            // and post-fix captures print a per-device "USBPortType =" line.
            #expect(plumbing >= 1, "\(folder): expected the internal hub boundary case in this fixture")
            #expect(userDevices >= 1, "\(folder): expected user devices behind the embedded controller")

            // The shared board node must survive on the same record that
            // carries the built-in flag (owner rule: never drop
            // identifiers; PR 408 round-two Codex on coexistence). Both
            // Studio fixtures have user devices that resolve it.
            #expect(namedBuiltIn >= 1,
                "\(folder): expected at least one BUILT-IN device to keep Port-USB-A@1 on its own record")
        }
    }

    // Same wiring class, older silicon (M1 Mac mini, submitted 2026-07-11):
    // its back USB-A block sits behind an embedded Fresco Logic controller
    // (`AppleEmbeddedUSBXHCIFL1100`), no board port node at all. The FL1100
    // exposes two root-hub personas directly on the controller (hub class,
    // no descriptor strings, and crucially NO USBPortType=2 marking, which
    // is why the round-two review caught the Studios-only exclusion missing
    // them). User devices, including an iPhone attached DIRECTLY to the
    // controller with no hub in between, must stay built-in.
    @Test("M1 Mac mini (#417 fix): user devices are built-in; the FL1100 root personas are excluded")
    func m1MiniEmbeddedFL1100Fix() throws {
        let blocks = try Self.requireBlocks("m1_macos15.7.7_c")
        let ownPT = Self.ownPortTypes(in: blocks)
        let embedded = Self.embeddedChains(blocks)
        #expect(!embedded.isEmpty, "expected embedded FL1100 chains in the M1 mini fixture")
        var personas = 0
        var userDevices = 0
        for block in embedded {
            let own = block.ownUSBPortType ?? ownPT[block.locationID]
            let result = Self.replayWalk(
                deviceLocationID: block.locationID,
                ancestors: block.ancestors,
                ownUSBPortType: own,
                deviceClass: block.deviceClass
            )
            #expect(result.reachedEmbeddedController)
            #expect(!result.tunnelled, "M1 mini USB-A devices classified tunnelled; the #417 fix regressed")
            #expect(result.portName == nil)
            if Self.expectedPlumbing(block, own: own) {
                personas += 1
                #expect(!result.behindInternalHub,
                    "FL1100 persona 0x\(String(block.locationID, radix: 16)) would render as a permanent Unknown device")
            } else {
                userDevices += 1
                #expect(result.behindInternalHub,
                    "0x\(String(block.locationID, radix: 16)) must land in the Built-in USB ports section")
            }
        }
        // The fixture carries both cases (2 personas, 3 user devices
        // including the directly-attached iPhone), so neither branch can
        // pass vacuously.
        #expect(personas >= 2, "expected the two FL1100 root personas in the fixture")
        #expect(userDevices >= 3, "expected the three user devices in the fixture")
    }

    // Real Thunderbolt docks (M4 Pro Mac mini on Sequoia, submitted
    // 2026-07-10), the case the dock rule exists FOR: chains ending at a
    // non-embedded third-party controller (`AppleUSBXHCIAR`,
    // `AppleUSBXHCIFL1100`) are genuinely tunnelled, and none of them carry
    // a UsbIOPort under IOService:/AppleARMPE (the Mac's own board), which
    // is the structural difference from the embedded case above. Verified
    // corpus-wide before pinning: 42/42 non-embedded dock chains lack an
    // ARMPE port node, 0 counterexamples.
    @Test("Real-dock pin: non-embedded dock-controller devices classify tunnelled, never board-wired")
    func realDockControllerPin() throws {
        for folder in ["m4pro_macos15.7.7_d", "m3pro_macos26.5.1_h"] {
            let dockChains = (try Self.requireBlocks(folder)).filter { block in
                guard let stop = block.probeStopClass else { return false }
                return USBWatcher.isThunderboltDockController(stop) && !stop.hasPrefix("AppleEmbedded")
            }
            #expect(!dockChains.isEmpty, "\(folder): expected real-dock chains in this fixture")
            for block in dockChains {
                let result = Self.replayWalk(deviceLocationID: block.locationID, ancestors: block.ancestors)
                #expect(result.tunnelled, "\(folder): dock-controller chain must classify tunnelled")
                #expect(!block.ancestors.contains { $0.usbIOPort?.hasPrefix("IOService:/AppleARMPE") == true },
                    "\(folder): a dock chain carried a Mac-board UsbIOPort; the embedded/dock split just broke")
            }
        }
    }

    // M4 Mac mini on macOS 27.0 (submitted 2026-07-13): Tahoe publishes a
    // UsbIOPort board node for the mini's internal front-panel hub, so
    // front-port devices resolve a named port (Port-USB-C@6) instead of the
    // no-port-node shape issue #348 was built around. Pinned because it is
    // the only corpus evidence of this macOS-version behaviour difference.
    @Test("M4 mini on macOS 27: internal-hub devices resolve the Tahoe board port node")
    func m4MiniTahoeNamedFrontPortPin() throws {
        let blocks = try Self.requireBlocks("m4_macos27.0_e")
        let internalHubChains = blocks.filter { block in
            block.ancestors.first(where: { $0.usbPortType != nil })?.usbPortType == USBWatcher.internalHubPortType
        }
        #expect(!internalHubChains.isEmpty, "expected internal-hub chains in the m4_macos27.0_e fixture")
        for block in internalHubChains {
            let result = Self.replayWalk(deviceLocationID: block.locationID, ancestors: block.ancestors)
            #expect(result.portName == "Port-USB-C@6",
                "expected Tahoe's board port node; got \(result.portName ?? "nil")")
            #expect(!result.behindInternalHub,
                "a named port means the #348 no-port-node classification must not fire")
        }
    }

    /// Device Speed for a given device locationID, read straight from the probe
    /// text. `DeviceBlock` does not carry it, so this small local parser keeps
    /// the fixture-driven speed honest (no hardcoded value in the assertion).
    private static func deviceSpeedRaw(locationID: UInt32, in text: String) -> UInt8? {
        for block in text.components(separatedBy: "--- Device[").dropFirst() {
            var loc: UInt32?
            var speed: UInt8?
            for rawLine in block.split(separator: "\n") {
                let t = rawLine.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("locationID"), let eq = t.firstIndex(of: "=") {
                    var hex = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    if hex.hasPrefix("0x") { hex = String(hex.dropFirst(2)) }
                    loc = UInt32(hex, radix: 16)
                } else if t.hasPrefix("Device Speed"), let eq = t.firstIndex(of: "=") {
                    speed = UInt8(t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces))
                }
            }
            if loc == locationID { return speed }
        }
        return nil
    }

    private static func makeBuiltInPort(serviceName: String, busIndex: Int?) -> AppleHPMInterface {
        // A built-in USB-only front port as it reaches the app: IOPort-class,
        // USB-C, connected, USB2/USB3 transports, no PD. Mirrors the reporter's
        // Port-USB-C@5/@6 in issue #456.
        AppleHPMInterface(
            id: UInt64(bitPattern: Int64(serviceName.hashValue)),
            serviceName: serviceName,
            className: "IOPort",
            portDescription: serviceName,
            portTypeDescription: "USB-C",
            portNumber: nil,
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: true,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["USB2", "USB3"],
            transportsActive: ["USB2", "USB3"],
            transportsProvisioned: ["USB2", "USB3"],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            busIndex: busIndex,
            rawProperties: [:]
        )
    }

    // End-to-end replay for issue #456 on an EMBEDDED-controller desktop (the
    // reporter's class of machine, a Mac Studio). The whole chain runs against
    // real bytes: classifyAncestry produces the behind-internal-hub flag AND the
    // resolved port name, then Core's matchingDevices attributes the device and
    // TunnelledDeviceGrouping removes it from the Built-in USB ports list.
    //
    // This fixture is embedded-path on purpose. The native path
    // (m4MiniTahoeNamedFrontPortPin above) already clears behindInternalHub once
    // a name resolves, so a native fixture would pass with or without the fix.
    // Here the device is classified behindInternalHub == true WITH a name, which
    // is exactly the state the fix has to handle, so this test fails without it.
    @Test("Issue #456: embedded-controller front port attributes its device and does not double-render")
    func embeddedFrontPortAttributionPin() throws {
        let text = try #require(
            Self.loadProbeText(folder: "m1max_macos27.0_c", fileName: "38_usb_device_tree.json"),
            "git-tracked fixture m1max_macos27.0_c/38_usb_device_tree.json is missing"
        )
        let blocks = Self.parseDeviceBlocks(text)
        try #require(!blocks.isEmpty)
        let ownPT = Self.ownPortTypes(in: blocks)

        // Find the block whose real classification lands on Port-USB-C@5 via the
        // embedded controller AND is flagged behind the internal hub. In this
        // fixture that is the AnkerWork C310 Webcam.
        let webcam = try #require(
            blocks.first { block in
                let r = Self.replayWalk(
                    deviceLocationID: block.locationID,
                    ancestors: block.ancestors,
                    ownUSBPortType: ownPT[block.locationID],
                    deviceClass: block.deviceClass
                )
                return r.portName == "Port-USB-C@5"
                    && r.reachedEmbeddedController
                    && r.behindInternalHub
            },
            "expected an embedded-path device named Port-USB-C@5 in the fixture"
        )

        let walk = Self.replayWalk(
            deviceLocationID: webcam.locationID,
            ancestors: webcam.ancestors,
            ownUSBPortType: ownPT[webcam.locationID],
            deviceClass: webcam.deviceClass
        )
        // Precondition the fix must overcome: the flag is set on this path.
        #expect(walk.behindInternalHub)

        let speedRaw = Self.deviceSpeedRaw(locationID: webcam.locationID, in: text)
        #expect(speedRaw == 3, "AnkerWork webcam is a 5 Gbps device in this fixture")

        let device = USBDevice(
            id: 1,
            locationID: webcam.locationID,
            vendorID: 0,
            productID: 0,
            vendorName: nil,
            productName: "AnkerWork C310 Webcam",
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: speedRaw,
            busPowerMA: nil,
            currentMA: nil,
            busIndex: walk.bus,
            controllerPortName: walk.portName,
            isBehindInternalHub: walk.behindInternalHub,
            rawProperties: [:]
        )
        let port = Self.makeBuiltInPort(serviceName: "Port-USB-C@5", busIndex: walk.bus)

        // 1. The port card now attributes the device (fails without the fix,
        //    because the device is flagged behindInternalHub).
        #expect(port.matchingDevices(from: [device]) == [device])
        #expect(device.usb3SpeedLabel == "USB 3.2 Gen 1 (5 Gbps)")

        // 2. Double-render guard: once a real port claims the device, it must
        //    leave the Built-in USB ports list. Cross-check that it WOULD be
        //    there with no claiming port, so the subtraction is doing work.
        let claimed = TunnelledDeviceGrouping.group(
            devices: [device], ports: [port], thunderboltSwitches: [], isDesktopMac: true
        )
        #expect(!claimed.internalHubDevices.contains(device),
            "a device attributed to a port card must not also render under Built-in USB ports")

        let unclaimed = TunnelledDeviceGrouping.group(
            devices: [device], ports: [], thunderboltSwitches: [], isDesktopMac: true
        )
        #expect(unclaimed.internalHubDevices.contains(device),
            "with no claiming port the device is a genuine Built-in USB ports member")
    }

    // Cross-source invariant: an AppleEmbedded* stop only ever occurs on a
    // desktop Mac. The form factor comes from corpus.jsonl (probe 32, an
    // independent source from probe 38), so this cannot be satisfied by the
    // classifier agreeing with itself. Verified 4/4 folders as of 2026-07-14.
    @Test("Embedded controllers only appear on desktop Macs (corpus.jsonl cross-source)")
    func embeddedControllerImpliesDesktop() throws {
        let jsonlURL = Self.probeRoot.appendingPathComponent("corpus.jsonl")
        let jsonl = try #require(try? String(contentsOf: jsonlURL, encoding: .utf8),
            "corpus.jsonl is git-tracked and must be present")
        var formFactors: [String: String] = [:]
        for line in jsonl.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let folder = obj["folder"] as? String,
                  let ff = obj["form_factor"] as? String else { continue }
            formFactors[folder] = ff
        }

        var embeddedFolders = 0
        for folder in Self.allProbeFolders() {
            guard let text = Self.loadProbeText(folder: folder, fileName: "38_usb_device_tree.json") else { continue }
            let embedded = Self.embeddedChains(Self.parseDeviceBlocks(text))
            guard !embedded.isEmpty else { continue }
            embeddedFolders += 1
            #expect(formFactors[folder] == "desktop",
                "\(folder): AppleEmbedded* controller on a \(formFactors[folder] ?? "unknown") machine; the embedded-implies-desktop assumption just broke")
        }
        // The git-tracked fixtures alone include 3 embedded-carrying folders,
        // so this test can never pass vacuously, clone or full corpus.
        #expect(embeddedFolders >= 3,
            "expected at least 3 folders with embedded-controller chains; got \(embeddedFolders)")
    }

    // MARK: - Probe-36 cross-check: busIndex on real XHCI port / device pairs
    //
    // Probe 36 ("USB host-controller port -> physical USB-C port map") gives a
    // ground-truth locationID for each XHCI port plus a `usb-c-port-number`.
    // Its own header says "match locationID to a port above" for connected
    // devices, so any device locationID equal to a listed XHCI port locationID
    // is, by the probe's own ground truth, on that port. `busIndex(fromLocationID:)`
    // is a pure upper-byte mask, so matched pairs sharing a locationID must
    // always share a busIndex -- this exercises the real function across every
    // real locationID value on 156 machines rather than only the small
    // hand-picked values in RegistryParsingTests.

    private struct XHCIPortEntry { let locationID: UInt32; let portNumber: Int }

    private static func parseXHCIPortEntries(_ text: String) -> [XHCIPortEntry] {
        var results: [XHCIPortEntry] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("usb-c-port-number="), trimmed.contains("locationID=") else { continue }
            guard let portRange = trimmed.range(of: "usb-c-port-number="),
                  let locRange = trimmed.range(of: "locationID=") else { continue }
            let afterPort = trimmed[portRange.upperBound...]
            let portDigits = afterPort.prefix { $0.isNumber }
            guard let portNumber = Int(portDigits) else { continue }
            let afterLoc = trimmed[locRange.upperBound...]
            let locDigits = afterLoc.prefix { $0.isNumber }
            guard let locationID = UInt32(locDigits) else { continue }
            results.append(XHCIPortEntry(locationID: locationID, portNumber: portNumber))
        }
        return results
    }

    private static func parseConnectedDeviceLocationIDs(_ text: String) -> [UInt32] {
        guard let marker = text.range(of: "IOUSBHostDevice (connected devices") else { return [] }
        var ids: [UInt32] = []
        for line in text[marker.upperBound...].split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("locationID=") else { continue }
            let afterEq = trimmed.dropFirst("locationID=".count)
            let digits = afterEq.prefix { $0.isNumber }
            if let loc = UInt32(digits) { ids.append(loc) }
        }
        return ids
    }

    @Test("Probe-36 sweep: busIndex(fromLocationID:) is consistent between a connected device and its matched XHCI port")
    func probe36BusIndexCrossCheck() {
        var foldersScanned = 0
        var matchedPairs = 0

        for folder in Self.allProbeFolders() {
            guard let text = Self.loadProbeText(folder: folder, fileName: "36_xhci_port_map.json") else { continue }
            let ports = Self.parseXHCIPortEntries(text)
            let devices = Self.parseConnectedDeviceLocationIDs(text)
            guard !ports.isEmpty else { continue }
            foldersScanned += 1

            let portsByLocation = Dictionary(ports.map { ($0.locationID, $0) }, uniquingKeysWith: { first, _ in first })
            for deviceLoc in devices {
                guard let port = portsByLocation[deviceLoc] else { continue }
                matchedPairs += 1
                #expect(
                    USBWatcher.busIndex(fromLocationID: deviceLoc) == USBWatcher.busIndex(fromLocationID: port.locationID),
                    "\(folder): device at \(deviceLoc) matched port \(port.portNumber) but busIndex diverged"
                )
                #expect(port.portNumber >= 1, "\(folder): usb-c-port-number \(port.portNumber) should be >= 1")
            }
        }

        print("[USBWatcherSweep] probe36: \(foldersScanned) folders, \(matchedPairs) matched device/port pairs")

        // Coverage floor: actual 157 folders as of 2026-07. Floor ~85% (135).
        // Matched pairs depend on a device being connected at capture time, so
        // no floor is set on that count (it is legitimately often zero).
        //
        // Two-tier reality: probe 36 has ZERO git-tracked files (all 157 are
        // on-disk-only), so `foldersScanned` is 0 on a fresh clone and this
        // already skips via the threshold below rather than failing. The
        // explicit 50 threshold (rather than a bare `> 0`) is defensive
        // consistency with the other probes in this pass, in case a future
        // fixture selection ever tracks a handful of probe-36 files.
        if foldersScanned >= 50 {
            #expect(foldersScanned >= 135,
                "Expected at least 135 folders with probe-36 XHCI port entries; got \(foldersScanned)")
        }
    }
}
