import Foundation

/// Pure helpers that turn `IOThunderboltSwitch` / `IOThunderboltPort` model
/// values into user-facing labels. Convention: per-lane Gb/s × lane count,
/// matching Apple's `system_profiler SPThunderboltDataType` output so the
/// labels line up with what users see in About This Mac → System Information.
///
/// TB5 was confirmed against a real M5 Pro + UGreen JHL9580 dock sample on
/// issue #52, so the renderer now emits a confirmed TB5 label for raw speed
/// code `0x2`. See planning/thunderbolt-fabric.md for the reasoning.
public enum ThunderboltLabels {
    /// Which end of a link "out" and "in" are written from. `.farEnd` swaps
    /// the two directions. It only matters on an asymmetric width: a
    /// symmetric label reads the same from both ends.
    public enum LinkViewpoint {
        case thisPort
        case farEnd
    }

    /// Compact human label for an active TB link.
    /// Returns nil if the port has no active link.
    /// Examples:
    /// - `"Up to 20 Gb/s × 2"` (USB4 / TB4 dual-lane)
    /// - `"Up to 10 Gb/s × 1"` (TB3 single-lane)
    /// - `"Up to 40 Gb/s × 2"` (TB5 / USB4 v2 dual-lane)
    /// - `"Up to 120 Gb/s out, 40 Gb/s in"` (TB5 asymmetric, 3 TX / 1 RX side)
    /// - `"Up to 40 Gb/s out, 120 Gb/s in"` (TB5 asymmetric, 1 TX / 3 RX side)
    public static func linkLabel(
        for port: IOThunderboltPort,
        from viewpoint: LinkViewpoint = .thisPort
    ) -> String? {
        guard port.hasTrainedLanes,
              let gen = port.currentSpeed,
              let width = port.currentWidth else {
            return nil
        }

        switch gen {
        case .tb3, .usb4Tb4, .tb5:
            guard let perLane = gen.perLaneGbps else { return nil }
            if width.asymmetricTx || width.asymmetricRx {
                // Directional totals, from this port's own point of view.
                // No single symmetric total exists on an asymmetric link, so
                // each direction gets its own honest figure rather than a
                // lane-count aside. `perLane * lanes` (Int) rather than
                // `port.txGbps`/`rxGbps` (Double), so the label never shows
                // a trailing ".0".
                var tx = perLane * width.txLanes
                var rx = perLane * width.rxLanes
                if viewpoint == .farEnd { swap(&tx, &rx) }
                return String(localized: "Up to \(tx) Gb/s out, \(rx) Gb/s in", bundle: _coreLocalizedBundle)
            }
            let lanes = describeLanes(width)
            return String(localized: "Up to \(perLane) Gb/s \(lanes)", bundle: _coreLocalizedBundle)
        case .unknown(let raw):
            let hex = String(raw, radix: 16)
            return String(localized: "Unknown generation (raw speed code 0x\(hex))", bundle: _coreLocalizedBundle)
        }
    }

    /// The Mac's-side label for a lane on `sw`. A downstream switch's
    /// upstream lane faces the Mac, so out of the Mac is into that lane and
    /// the label is read from the far end. A host root lane, or a downstream
    /// switch's own downstream lane, already points away from the Mac. Every
    /// rendered row uses this so they all agree with the port line; JSON
    /// stays per-port on purpose.
    public static func linkLabel(for port: IOThunderboltPort, on sw: IOThunderboltSwitch) -> String? {
        let facesMac = !sw.isHostRoot && port.portNumber == sw.upstreamPortNumber
        return linkLabel(for: port, from: facesMac ? .farEnd : .thisPort)
    }

    /// Lane-count suffix for a symmetric link, `× N`. `linkLabel` handles
    /// asymmetric widths separately (one rate per direction), so this only
    /// ever sees a symmetric width.
    private static func describeLanes(_ width: LinkWidth) -> String {
        let lanes = max(width.txLanes, 1)
        return "× \(lanes)"
    }

    /// Human-readable name for a downstream switch ("ASUS PA32QCV",
    /// "CalDigit, Inc. TS3 Plus"). Falls back to "Unknown device" if the
    /// DROM didn't decode (rare but possible).
    public static func deviceName(for sw: IOThunderboltSwitch) -> String {
        let vendor = sw.vendorName.trimmingCharacters(in: .whitespaces)
        let model = sw.modelName.trimmingCharacters(in: .whitespaces)
        switch (vendor.isEmpty, model.isEmpty) {
        case (false, false):
            // Some DROMs repeat the brand in the model string, e.g.
            // vendor "Ugreen" + model "Ugreen Storage Device". Concatenating
            // then reads "Ugreen Ugreen Storage Device" (issue #392). If the
            // model already starts with the vendor name, it is the full
            // name on its own. Match the whole word (equal, or vendor + space)
            // so a vendor that happens to prefix an unrelated model word
            // ("Cal" vs "Calibre X") is not collapsed.
            let vLower = vendor.lowercased()
            let mLower = model.lowercased()
            if mLower == vLower || mLower.hasPrefix(vLower + " ") {
                return model
            }
            return "\(vendor) \(model)"
        case (false, true): return vendor
        case (true, false): return model
        case (true, true): return String(localized: "Unknown device", bundle: _coreLocalizedBundle)
        }
    }
}

/// Topology helpers: walk the switch graph to find the chain rooted at a
/// host port. Pure logic; no IOKit. Used by `PortSummary` and the GUI.
public enum ThunderboltTopology {
    /// Find the host root switch whose lane port has `Socket ID == "N"`,
    /// where N is parsed from a USB-C port's serviceName suffix
    /// (e.g. `Port-USB-C@1` → `1`).
    public static func hostRoot(
        forSocketID socketID: String,
        in switches: [IOThunderboltSwitch]
    ) -> IOThunderboltSwitch? {
        switches.first { sw in
            sw.isHostRoot && sw.ports.contains {
                $0.adapterType.isLane && $0.socketID == socketID
            }
        }
    }

    /// Parse the trailing `@N` suffix from a port serviceName, or nil if
    /// it doesn't have one. `Port-USB-C@1` → `"1"`. Pure parser, kept
    /// public for parser-level unit tests; **production callers must use
    /// `socketID(for:)` instead** so the data-capability gate runs.
    public static func socketID(fromServiceName name: String) -> String? {
        guard let at = name.lastIndex(of: "@") else { return nil }
        let suffix = name[name.index(after: at)...]
        return suffix.isEmpty ? nil : String(suffix)
    }

    /// The TB host-root socket ID for this port, or `nil` when this port
    /// can't host a data link. Power-only ports (MagSafe) share an `@N`
    /// suffix with the first USB-C port on the same HPM controller
    /// (issue #195), so attempting a topology lookup on them leaks the
    /// neighbouring USB-C port's lane state. Gating on `carriesData`
    /// keeps every TB-graph consumer honest at the entry point.
    public static func socketID(for port: AppleHPMInterface) -> String? {
        guard port.carriesData else { return nil }
        return socketID(fromServiceName: port.serviceName)
    }

    /// Convert a host-root switch's `acioN` Thunderbolt HAL root name (e.g.
    /// `"acio2"`) to the sibling `apciecN` PCIe tunnel root name a tunnelled
    /// USB device reports as its own `tunnelRootName` (e.g. `"apciec2"`):
    /// same index, different prefix. `nil` when `acioName` isn't a strict
    /// `"acio" + digits` name.
    ///
    /// This is the apciec<->acio port-scoping join
    /// (`research/usb-chain-attribution-identifiers.md`): Apple Silicon
    /// exposes each Thunderbolt port as two sibling registry roots sharing
    /// one index N. `ChainDeviceAttribution` uses this to validate that a
    /// tunnelled device's `tunnelRootName` actually belongs to the port
    /// being resolved, not a different port's root that slipped in.
    public static func apciecRootName(fromAcioRootName acioName: String) -> String? {
        let prefix = "acio"
        guard acioName.hasPrefix(prefix) else { return nil }
        let digits = acioName.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return "apciec\(digits)"
    }

    /// The switch UIDs of the USB-carrying tunnels THIS host root's fabric
    /// confirms: the input `ChainDeviceAttribution.resolve`'s structural
    /// tunnel join wants as `usbTunnelSwitchUIDs`, and the ONE shared place
    /// that derivation lives (both `TunnelledDeviceGrouping` and
    /// `ConnectedDeviceTree` call this rather than each filtering
    /// `tunnels(...)` themselves, which had drifted into two different, both
    /// too-loose, derivations).
    ///
    /// `TunnelPath.kind == .usb` alone is NOT enough (review finding): kind is
    /// classified from ANY classifiable adapter in the path's UUID group
    /// (deliberately, so a real cross-cable tunnel is still recognised when
    /// the host root's own adapter is a bare lane; see `TunnelPath.swift`'s
    /// file header), while `terminalSwitchUID` is independently "the deepest
    /// switch carrying this UUID". Those two facts can point at different
    /// adapters: a `.usb` classified path whose DEEPEST member happens to be
    /// a lane-only pass-through would report a `terminalSwitchUID` that never
    /// itself carries a USB adapter, and DROM depth is exactly the value the
    /// structural join divides `tunnelBridgeDepth` by two to match, so a
    /// wrong terminal switch here is a wrong depth match downstream.
    ///
    /// Three requirements, matching the project's own tunnel-attribution
    /// research (`research/thunderbolt-fabric.md`, "Cross-cable = kind known
    /// + terminal depth > 0 + path UUID spans >= 2 distinct switches"):
    ///
    /// 1. `distinctSwitchCount >= 2`: a UUID recurring on only ONE switch's
    ///    own ports is that device's internal routing, never a tunnel
    ///    (documented corpus counterexample in `TunnelPath.swift`'s header).
    /// 2. The terminal switch is DOWNSTREAM (its `depth > 0`, i.e. not the
    ///    host root itself): a tunnel terminates at a device, never at the
    ///    Mac's own controller.
    /// 3. The terminal switch's OWN adapter carrying this UUID is actually a
    ///    USB adapter type (`.usb3Down`/`.usb3Up`/`.usbGenTDown`/
    ///    `.usbGenTUp`), read straight from `terminalAdapterType`, not
    ///    re-derived from `kind`. This is the fix for the lane-only-terminal
    ///    case above: `kind` can say `.usb` from a shallower member while the
    ///    terminal itself is something else entirely.
    public static func usbTunnelTerminalSwitchUIDs(
        from hostRoot: IOThunderboltSwitch,
        in switches: [IOThunderboltSwitch]
    ) -> Set<Int64> {
        var depthByID: [Int64: Int] = [:]
        for sw in switches { depthByID[sw.id] = sw.depth }
        let usbAdapterTypes: Set<AdapterType> = [.usb3Down, .usb3Up, .usbGenTDown, .usbGenTUp]

        return Set(
            tunnels(from: hostRoot, in: switches).compactMap { tunnel -> Int64? in
                guard tunnel.distinctSwitchCount >= 2,
                      let terminalType = tunnel.terminalAdapterType,
                      usbAdapterTypes.contains(terminalType),
                      let uid = tunnel.terminalSwitchUID,
                      let depth = depthByID[uid], depth > 0
                else { return nil }
                return uid
            }
        )
    }

    /// Return the chain of downstream switches reachable from a host root,
    /// in depth order (root → device). Walks the `parentSwitchUID` graph.
    /// Returns just the root if there's nothing downstream.
    public static func chain(
        from root: IOThunderboltSwitch,
        in switches: [IOThunderboltSwitch]
    ) -> [IOThunderboltSwitch] {
        var byParent: [Int64: [IOThunderboltSwitch]] = [:]
        for sw in switches {
            guard let parentUID = sw.parentSwitchUID else { continue }
            byParent[parentUID, default: []].append(sw)
        }

        var chain: [IOThunderboltSwitch] = [root]
        var current = root
        var seen: Set<Int64> = [root.id]
        // Follow first-child only. Daisy-chains are linear in the common
        // case; if the user has a true tree (dock with two TB devices),
        // the chain follows the first downstream branch and the GUI tree
        // can render the full topology separately.
        while let children = byParent[current.id], let next = children.first {
            guard !seen.contains(next.id) else { break }
            seen.insert(next.id)
            chain.append(next)
            current = next
        }
        return chain
    }

    /// Return the full downstream tree rooted at a host root, following
    /// *every* branch. A dock with two Thunderbolt devices yields two child
    /// subtrees. Depth 0 is the root's direct children (the first downstream
    /// devices), matching how `chain`'s `dropFirst()` is consumed. Returns an
    /// empty array when nothing is downstream.
    ///
    /// This is the branch-aware counterpart to `chain(from:in:)`, which only
    /// follows the first child. Use this for rendering the whole fabric;
    /// `chain` is still the right tool for "deepest single path" questions
    /// like step-down detection.
    public static func tree(
        from root: IOThunderboltSwitch,
        in switches: [IOThunderboltSwitch]
    ) -> [IOThunderboltSwitchNode] {
        var byParent: [Int64: [IOThunderboltSwitch]] = [:]
        for sw in switches {
            guard let parentUID = sw.parentSwitchUID else { continue }
            byParent[parentUID, default: []].append(sw)
        }

        // Cycle guard, mirroring `chain(from:in:)`'s `seen` set. Every
        // branch of the recursive walk shares this one set, so a switch
        // is visited at most once across the whole tree, however many
        // parentSwitchUID edges point at it. Without it, a malformed
        // parentSwitchUID graph with a 2+ node cycle would recurse
        // forever: `chain` has this guard already, `tree` didn't.
        var seen: Set<Int64> = [root.id]

        func build(_ sw: IOThunderboltSwitch, depth: Int) -> IOThunderboltSwitchNode {
            let kids = (byParent[sw.id] ?? [])
                .filter { !seen.contains($0.id) }
                .sorted { $0.id < $1.id }
                .map { child -> IOThunderboltSwitchNode in
                    seen.insert(child.id)
                    return build(child, depth: depth + 1)
                }
            return IOThunderboltSwitchNode(sw: sw, depth: depth, children: kids)
        }

        return (byParent[root.id] ?? [])
            .filter { !seen.contains($0.id) }
            .sorted { $0.id < $1.id }
            .map { child -> IOThunderboltSwitchNode in
                seen.insert(child.id)
                return build(child, depth: 0)
            }
    }

    /// Flatten a tree into depth-first order (parent, then its subtree),
    /// preserving each node's `depth`. Mirrors `USBDeviceNode.flatten` so the
    /// CLI and GUI render the Thunderbolt fabric the same way they render the
    /// USB device tree.
    public static func flatten(_ nodes: [IOThunderboltSwitchNode]) -> [IOThunderboltSwitchNode] {
        var result: [IOThunderboltSwitchNode] = []
        for node in nodes {
            result.append(node)
            result.append(contentsOf: flatten(node.children))
        }
        return result
    }

    /// The switch hanging off one port of `sw`, or nil when nothing is
    /// attached there.
    ///
    /// A route string encodes one byte per hop from the host root, so the
    /// parent's own downstream port for a child at depth d is byte d-1, and
    /// byte 0 only answers for a depth-1 child. Checked against the corpus
    /// folders that publish the parent link: where the parent's ports are
    /// visible the byte names one of them every time, 47 of 47, with 4 more
    /// children under a parent that published no ports at all.
    ///
    /// `upstreamPortNumber` is NOT that number: it is the child's own port
    /// for its upstream link, and the two differ on real hardware.
    public static func childSwitch(
        below sw: IOThunderboltSwitch,
        onPortNumber portNumber: Int,
        in switches: [IOThunderboltSwitch]
    ) -> IOThunderboltSwitch? {
        switches.first { child in
            // One hop, not any number of hops. `parentSwitchUID` is read from
            // the registry and can be stale or malformed, and a depth-2
            // switch pointed straight at a root would have its byte read at
            // the wrong depth, lighting whichever unrelated port carries that
            // number. 13 corpus captures are truncated, 6 of them keeping a
            // partial switch list, so malformed topology is not hypothetical.
            guard child.parentSwitchUID == sw.id,
                  child.depth >= 1,
                  child.depth == sw.depth + 1,
                  child.depth <= routeStringHopCount else { return false }
            let hopByte = (child.routeString >> (8 * Int64(child.depth - 1))) & 0xFF
            return Int(hopByte) == portNumber
        }
    }

    /// Hops a route string can address: one byte per hop across its 8 bytes.
    /// Past that there is no byte to read, and Swift's shift operator returns
    /// 0 rather than trapping, so an out-of-range depth would silently match
    /// a port numbered 0.
    private static let routeStringHopCount = MemoryLayout<Int64>.size

    /// True when this lane port is carrying a link to something that is
    /// actually there.
    ///
    /// `IOThunderboltPort.hasTrainedLanes` is the raw register read, and it
    /// reads true on an empty socket on both sides of the fabric: on a Mac's
    /// host root, and on a dock's spare port. So the lane needs evidence of a
    /// far end, and there are three kinds:
    ///
    /// 1. A hop table row, meaning a tunnel is routed across this lane, and a
    ///    tunnel needs something at the far end. Measured over the corpus
    ///    folders with no depth-1 switch and no truncated capture, 7 lane
    ///    ports across 6 folders carry one, and every one of those folders
    ///    holds a CIO-active USB-C port.
    /// 2. A switch hanging off this port.
    /// 3. On a downstream switch only, being the lane that switch is itself
    ///    attached by (`upstreamPortNumber`). The switch is in the fabric, so
    ///    its leg toward the Mac is real.
    ///
    /// All three are asked of the whole SOCKET, through `socketLanePorts`:
    /// one physical socket is a pair of lane adapters and only one of the
    /// pair carries any of that evidence, so a lane-by-lane answer reports
    /// one half of a live socket as empty. 7 lanes across 6 corpus folders
    /// were in exactly that state under the hop-table clause alone.
    ///
    /// Anything else is an empty socket. A blanket "any trained lane on a
    /// downstream switch is linked" was the earlier rule and it was wrong:
    /// 412 dock lanes in the corpus sit at the idle signature with nothing
    /// attached to them.
    public static func isLinked(
        port: IOThunderboltPort,
        on sw: IOThunderboltSwitch,
        in switches: [IOThunderboltSwitch]
    ) -> Bool {
        guard port.hasTrainedLanes else { return false }
        // Every clause asks about the SOCKET, not the lane, because only one
        // lane of the pair carries any of this evidence. Asking lane by lane
        // is what published `linkActive: false` on one half of a live 40 Gb/s
        // socket while its sibling said true.
        for lane in socketLanePorts(of: port, on: sw) {
            if !lane.hopTable.isEmpty { return true }
            if childSwitch(below: sw, onPortNumber: lane.portNumber, in: switches) != nil {
                return true
            }
            if !sw.isHostRoot, lane.portNumber == sw.upstreamPortNumber { return true }
        }
        return false
    }

    /// The lane adapters that make up one physical socket: this port, plus
    /// the dual-link sibling it names when that sibling is actually published
    /// on the switch as a lane adapter.
    ///
    /// Apple Silicon exposes one socket as a PAIR of lane adapters sharing a
    /// Socket ID, and only one of the pair carries the route byte, the hop
    /// table and the aggregate `Link Bandwidth`. So "is there something on
    /// the far end of this socket" can only be answered by looking at both.
    /// The rule lives here, once, because `isLinked` and
    /// `DataLinkDiagnostic.partnerSwitch` both ask it and must not disagree.
    ///
    /// The sibling has to be present: `Dual-Link Port` is a number the
    /// firmware publishes, not a promise that the port is in the snapshot,
    /// and propagating linkage from a port that is not there would be the
    /// same false live link this gate exists to remove. Measured over 9313
    /// corpus lane adapters, the key is present on 9303, is never zero, and
    /// never names the port itself.
    public static func socketLanePorts(
        of port: IOThunderboltPort,
        on sw: IOThunderboltSwitch
    ) -> [IOThunderboltPort] {
        guard let siblingNumber = port.dualLinkPort,
              siblingNumber != port.portNumber,
              let sibling = sw.ports.first(where: {
                  $0.portNumber == siblingNumber && $0.adapterType.isLane
              }) else {
            return [port]
        }
        return [port, sibling]
    }

    /// The downstream lane port picked on the raw trained-lane read alone,
    /// with no partner evidence required. Host root: the first trained lane.
    /// Downstream switch: the first trained lane that is not the upstream
    /// one.
    ///
    /// This exists for the CIO-gated callers (`DataLinkDiagnostic.activeTBGbps`
    /// and `PortSummary`'s Thunderbolt bullets). They are only ever entered
    /// for a port whose active transports carry CIO, which is already the
    /// authoritative "this cable is doing Thunderbolt" signal, so an idle
    /// port never reaches them. Requiring a switch record on top would buy
    /// nothing there and would silence a real verdict whenever macOS did not
    /// publish one. Measured over captures that are not truncated, 7
    /// CIO-active machines have no depth-1 switch record at all. The
    /// hop-table clause in `isLinked` recovers 6 of those 7; the last,
    /// m5pro_macos26.5.1, publishes no hop table either, so there only the
    /// raw pick answers. Every caller that is NOT CIO-gated wants
    /// `activeDownstreamLanePort(_:in:)` instead.
    public static func trainedDownstreamLanePort(_ sw: IOThunderboltSwitch) -> IOThunderboltPort? {
        let candidates = sw.ports.filter { $0.adapterType.isLane && $0.hasTrainedLanes }
        if sw.isHostRoot {
            return candidates.first
        }
        return candidates.first { $0.portNumber != sw.upstreamPortNumber }
    }

    /// The lane port whose link label best represents *how this switch is
    /// connected*: its upstream lane, the leg toward the Mac, falling back to
    /// the first linked lane when that one is absent or not linked.
    ///
    /// Lanes on one switch do NOT all run at the same speed, so "the first
    /// linked one" is not interchangeable with "the arriving one". Measured:
    /// an OWC Express 4M2 arrives on port 3 at 20 Gb/s x 2 while ports 1 and
    /// 2 sit idle at 10 Gb/s x 1, and ports sort ascending, so the first-lane
    /// rule labelled the device with a lane it does not arrive on. 41 of 448
    /// downstream switches in the corpus are attached on a port above 1.
    /// `ConnectedDeviceTree.linkDescription` already preferred the upstream
    /// lane for the same reason; this is that rule in one place.
    public static func connectionLanePort(
        _ sw: IOThunderboltSwitch,
        in switches: [IOThunderboltSwitch]
    ) -> IOThunderboltPort? {
        let linkedLanes = sw.ports.filter {
            $0.adapterType.isLane && isLinked(port: $0, on: sw, in: switches)
        }
        return linkedLanes.first { $0.portNumber == sw.upstreamPortNumber } ?? linkedLanes.first
    }

    /// Find the linked downstream lane port on a switch (the one going
    /// toward the next-hop device, not the upstream link to the host).
    /// Useful for picking which port's link state describes the next leg.
    public static func activeDownstreamLanePort(
        _ sw: IOThunderboltSwitch,
        in switches: [IOThunderboltSwitch]
    ) -> IOThunderboltPort? {
        // Host root: any linked lane port is downstream by definition.
        // Downstream switch: skip the lane port matching upstreamPortNumber,
        // pick the first linked one of the rest.
        let candidates = sw.ports.filter {
            $0.adapterType.isLane && isLinked(port: $0, on: sw, in: switches)
        }
        if sw.isHostRoot {
            return candidates.first
        }
        return candidates.first { $0.portNumber != sw.upstreamPortNumber }
    }
}

// MARK: - Fabric tree

/// A node in the Thunderbolt fabric tree: one switch plus its depth from the
/// host root and its downstream children. Mirrors `USBDeviceNode` so the CLI
/// and GUI can render the fabric the same way they render the USB device tree.
/// Built from the flat switch list by `ThunderboltTopology.tree(from:in:)`,
/// which walks `parentSwitchUID`.
public struct IOThunderboltSwitchNode: Identifiable {
    public let sw: IOThunderboltSwitch
    public let depth: Int
    public let children: [IOThunderboltSwitchNode]

    public var id: Int64 { sw.id }

    public init(sw: IOThunderboltSwitch, depth: Int, children: [IOThunderboltSwitchNode]) {
        self.sw = sw
        self.depth = depth
        self.children = children
    }
}
