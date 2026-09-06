import Foundation

/// Builds the "Connected devices" rows for one port.
///
/// When the port has a Thunderbolt device downstream (a dock or display),
/// every USB device on the port is physically behind it: the port's one
/// connector is occupied by that device's cable. The tree therefore roots
/// at the Thunderbolt device, labelled with the live link speed, so the
/// section reads as the physical story (one 40 Gbps pipe with the USB hubs
/// inside it) instead of two bare USB hub roots that make a TB5 dock look
/// like a 480 Mbps + 10 Gbps device.
///
/// Monitors reach the Mac through the same Thunderbolt link (a DisplayPort
/// tunnel), so each connected monitor gets a row directly under the root,
/// before the USB branch.
///
/// Pure logic, no IOKit. Shared by the menu bar app and the CLI text output
/// so both render identical rows. JSON output is deliberately unchanged: it
/// already carries the Thunderbolt fabric and the USB device tree as
/// separate structured sections, and reshaping it would break consumers for
/// no information gain.
public enum ConnectedDeviceTree {
    /// One rendered row: a complete display label plus its indent depth.
    /// The renderers add only their own bullet/arrow prefix and indentation.
    ///
    /// `device` carries the node a device row was built from, so a renderer
    /// that can show more than a label (the app's expandable row) has the
    /// model to hand. It is `nil` on rows that describe something other than a
    /// USB device: the Thunderbolt root, a display, a bus header. Text
    /// renderers ignore it and draw `label` exactly as before.
    public struct Row: Equatable {
        public let label: String
        public let depth: Int
        public let device: USBDeviceNode?

        public init(label: String, depth: Int, device: USBDeviceNode? = nil) {
            self.label = label
            self.depth = depth
            self.device = device
        }

        /// Equality covers everything the row carries, `device` included, as a
        /// full value comparison.
        ///
        /// It deliberately used to compare label and depth only, on the
        /// reasoning that those are what a row draws. That was a trap: a row
        /// with the wrong device attached, or none at all, compared equal to a
        /// correct one, so an assertion of the form
        /// `#expect(rows == [Row(label:depth:device:)])` silently passed on
        /// broken device routing. Nothing in the app compares rows, so this
        /// only ever cost test strength, but that is the whole point of the
        /// type.
        ///
        /// Comparing the node by value rather than by its IOKit entry ID
        /// matters because the expandable row renders fields the ID does not
        /// pin down: two snapshots sharing an entry ID can still differ in
        /// vendor, serial, USB version or hub depth, and those are exactly
        /// what the detail panel shows.
        public static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.label == rhs.label
                && lhs.depth == rhs.depth
                && lhs.device == rhs.device
        }
    }

    /// Build the rows for one port's "Connected devices" section.
    ///
    /// - Parameters:
    ///   - devices: USB devices attributed to this port.
    ///   - port: the port, used to resolve its Thunderbolt host root. The
    ///     `ThunderboltTopology.socketID(for:)` gate keeps power-only ports
    ///     (MagSafe) from borrowing a neighbouring port's fabric.
    ///   - thunderboltSwitches: the live switch list from the TB watcher.
    ///   - displayPorts: connected monitors on this port, one entry each.
    /// - Returns: rows ready to render, or an empty array when there is
    ///   nothing to show (no devices and no Thunderbolt device downstream).
    /// Whether to render every device or only the ones a user has a decision
    /// to make about.
    public enum HubDisplay: Sendable {
        /// Every device, hubs included. The CLI's shape, and what the app shows
        /// once the user asks to see everything.
        case all
        /// Hubs collapsed. Only non-hub devices are listed, each annotated with
        /// how many hubs sit between it and the port. A hub with no non-hub
        /// descendants is still shown, because dropping it would make a device
        /// disappear with nothing to explain the gap.
        case endpointsOnly
    }

    /// - Parameters:
    ///   - devices: USB devices already attributed to this port by the
    ///     ordinary (non-tunnel) join, as before.
    ///   - tunnelledDevices: tunnelled USB devices STRUCTURALLY scoped to
    ///     this specific port (`TunnelledDeviceGrouping
    ///     .structurallyScopedTunnelledDevices(for:in:thunderboltSwitches:)`),
    ///     merged into the SAME forest as `devices` so a tunnelled device
    ///     nests under its chain device in this port's tree instead of
    ///     rendering in a separate flat section. Empty by default so every
    ///     existing caller is unaffected until it opts in. A device with no
    ///     structural root data at all never appears here (the scoping
    ///     helper can't place it); it keeps flowing through
    ///     `TunnelledDeviceGrouping.group`'s single-active-port fallback,
    ///     unchanged.
    public static func rows(
        devices: [USBDevice],
        tunnelledDevices: [USBDevice] = [],
        port: AppleHPMInterface,
        thunderboltSwitches: [IOThunderboltSwitch],
        displayPorts: [IOPortTransportStateDisplayPort],
        hubs: HubDisplay = .all
    ) -> [Row] {
        // Merged once, at the top: every path below (the no-Thunderbolt
        // fallback included, though `tunnelledDevices` should be empty there
        // by construction) reads `allDevices`, never the bare `devices`
        // parameter, so a tunnelled device can never be silently dropped by
        // a path that forgot about it.
        // Defence in depth (plan pcie-tunnelled-usb-attribution): the wiring
        // rule is that callers pass native matches in `devices` and
        // structurally scoped devices in `tunnelledDevices`, never the union
        // in both; dedup by id here so a miswired caller renders a device
        // once instead of twice.
        let allDevices: [USBDevice]
        if tunnelledDevices.isEmpty {
            allDevices = devices
        } else {
            var seen = Set<UInt64>()
            allDevices = (devices + tunnelledDevices).filter { seen.insert($0.id).inserted }
        }

        guard let hostRoot = thunderboltHostRoot(port: port, switches: thunderboltSwitches)
        else {
            // No Thunderbolt device downstream: the plain USB tree, unchanged.
            // Directly-attached monitors (USB-C DisplayPort Alt Mode, no TB
            // tunnel) keep their existing display banner; without a root to
            // hang them under, a bare display row here would just repeat it.
            return deviceRowsGroupedByBus(allDevices, hubs: hubs)
        }

        let chain = ThunderboltTopology.tree(from: hostRoot, in: thunderboltSwitches)
        let chainNodes = ThunderboltTopology.flatten(chain)
        guard !chainNodes.isEmpty else { return deviceRowsGroupedByBus(allDevices, hubs: hubs) }

        let displays = displayRows(
            displayPorts: displayPorts,
            hostRoot: hostRoot,
            switches: thunderboltSwitches
        )
        let forest = USBDeviceNode.buildTree(from: allDevices)
        // The structural tunnel join's two safety inputs:
        // which switches this port's OWN fabric confirms carry a USB tunnel
        // (the shared, strict derivation: cross-cable, downstream terminal,
        // and the terminal's OWN adapter is a USB type, not just `kind`), and
        // this port's own apciecN root name, so a device whose tunnelRootName
        // names a different port fails closed rather than being trusted just
        // because it ended up in this call's `devices`.
        let usbTunnelSwitchUIDs = ThunderboltTopology.usbTunnelTerminalSwitchUIDs(from: hostRoot, in: thunderboltSwitches)
        let expectedTunnelRootName = hostRoot.acioRootName.flatMap(ThunderboltTopology.apciecRootName(fromAcioRootName:))
        let attribution = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: usbTunnelSwitchUIDs,
            expectedTunnelRootName: expectedTunnelRootName
        )

        // The gate. One chain device and nothing attributed means there is
        // nothing for the chain layout to say that the existing one doesn't, so
        // the port renders exactly as it did before: bus headers, all-hub
        // fallback and row order untouched. Everything that follows this guard
        // is reached only by a daisy chain or a port with an anchored device.
        //
        // `chain.count == 1` requires a single FIRST HOP, not a single chain
        // device. One physical connector carries one cable, and on Apple Silicon
        // each host root serves exactly one socket, so two first hops should be
        // impossible; the layout still refuses them rather than trusting that.
        // With two, both would be emitted at depth 0 and everything hung at
        // depth 1 would read as belonging to whichever came last. The old layout
        // shows the first hop only, which is what it does today.
        guard chain.count == 1, chainNodes.count > 1 || !attribution.isEmpty else {
            var rows = [chainRow(for: chainNodes[0])]
            rows.append(contentsOf: displays)
            // Shift the device rows one level to sit under the Thunderbolt root,
            // carrying `device` across. Dropping it here would make the
            // expandable detail work everywhere except behind a dock, which is
            // where the device tree is longest and the detail is most wanted.
            rows.append(contentsOf: deviceRowsGroupedByBus(allDevices, hubs: hubs).map {
                Row(label: $0.label, depth: $0.depth + 1, device: $0.device)
            })
            return rows
        }

        // The chain layout: the fabric chain is the skeleton, at its own depths,
        // and each chain device carries the USB devices attributed to it.
        //
        // Bus headers are deliberately dropped here. `groupedByBus` answers
        // "which devices share a controller"; the chain grouping answers "what
        // is plugged into what", which is the question this section exists to
        // answer, and stacking both puts back the indentation the grouping is
        // there to remove. The bus is still in `--json` and in the Pro
        // diagnostics screen.
        var nodeByID: [UInt64: USBDeviceNode] = [:]
        for node in USBDeviceNode.flatten(forest) { nodeByID[node.device.id] = node }
        let hubsAbove = hubDepths(forest)
        // Stage B v2 (step 9): the USB-tree parent of every node, needed so
        // `groupRows` can tell a `portLevelBoundaries` node whose immediate
        // parent IS attributed (a boundary mid-tree, under an owned subtree)
        // from one whose parent is already unowned (naturally reachable via
        // the ordinary leftover walk, no extra entry needed).
        var parentOf: [UInt64: UInt64] = [:]
        for node in USBDeviceNode.flatten(forest) {
            for child in node.children { parentOf[child.device.id] = node.device.id }
        }

        var rows: [Row] = []
        for (index, node) in chainNodes.enumerated() {
            rows.append(chainRow(for: node))
            // Displays stay at depth 1 under the first hop, where they render
            // today, and are deliberately NOT attributed to a deeper chain
            // device: `IOPortTransportStateDisplayPort` is joined to a port by
            // HPM port number and shares no key with the fabric, so there is
            // nothing to attribute them with.
            if index == 0 { rows.append(contentsOf: displays) }
            rows.append(contentsOf: groupRows(
                owner: node.sw.id,
                depth: node.depth + 1,
                forest: forest,
                nodeByID: nodeByID,
                parentOf: parentOf,
                hubsAbove: hubsAbove,
                attribution: attribution,
                hubs: hubs,
                annotateHops: false
            ))
        }
        // Whatever could not be placed goes last, at depth 1 under the first
        // hop: exactly where it renders today. The hop count stays on these
        // rows because nothing else on them says how far away the device is.
        // This is also the port-level group Stage B v2's `portLevelBoundaries`
        // devices render from (see `groupRows`'s nil-owner branch).
        rows.append(contentsOf: groupRows(
            owner: nil,
            depth: 1,
            forest: forest,
            nodeByID: nodeByID,
            parentOf: parentOf,
            hubsAbove: hubsAbove,
            attribution: attribution,
            hubs: hubs,
            annotateHops: true
        ))
        return rows
    }

    /// Rows for one chain device's group of USB devices, or for the leftovers
    /// when `owner` is nil.
    ///
    /// Both hub modes read the same `regionOwner`, so a device cannot appear
    /// inside the dock when collapsed and somewhere else when expanded. They
    /// differ only in what they draw: collapsed lists the non-hub devices flat,
    /// expanded nests whole subtrees.
    private static func groupRows(
        owner: Int64?,
        depth: Int,
        forest: [USBDeviceNode],
        nodeByID: [UInt64: USBDeviceNode],
        parentOf: [UInt64: UInt64],
        hubsAbove: [UInt64: Int],
        attribution: ChainDeviceAttribution,
        hubs: HubDisplay,
        annotateHops: Bool
    ) -> [Row] {
        switch hubs {
        case .endpointsOnly:
            // `regionOwner` is already keyed by every node regardless of
            // depth (not just forest roots), so a `portLevelBoundaries`
            // node (whose `regionOwner` is always nil, see
            // `ChainDeviceAttribution.resolve`'s `descend`) is already
            // picked up correctly here when `owner == nil`, and correctly
            // excluded from every OTHER owner's group. No boundary-specific
            // handling needed in this mode.
            return USBDeviceNode.flatten(forest)
                .filter {
                    !$0.device.isHub
                        && !attribution.absorbed.contains($0.device.id)
                        && attribution.regionOwner[$0.device.id] == owner
                }
                .map {
                    endpointRow(
                        for: $0,
                        depth: depth,
                        hubsAbove: annotateHops ? (hubsAbove[$0.device.id] ?? 0) : 0
                    )
                }
        case .all:
            let entries: [USBDeviceNode]
            if let owner {
                entries = attribution.regionRoots
                    .filter { $0.value == owner }
                    .keys
                    .compactMap { nodeByID[$0] }
                    .sorted { $0.device.locationID < $1.device.locationID }
            } else {
                // A node inherits its parent's owner, so an unattributed node
                // can only sit under unattributed ancestors: the leftover
                // regions are exactly the unowned forest roots. Stage B v2
                // (step 9) adds one more source of leftover entries: a
                // `portLevelBoundaries` node whose immediate USB-tree parent
                // IS attributed (owned by some chain device). Such a node is
                // a boundary mid-tree, not a forest root, so the plain
                // forest-roots scan would never surface it, and
                // `nestedRows` below deliberately refuses to render it
                // nested inside that owner's group (see there) -- without
                // this explicit entry it would render nowhere at all.
                // Sorted alongside the forest-root leftovers so ordering is
                // deterministic.
                let forestRootLeftovers = forest.filter { attribution.regionOwner[$0.device.id] == nil }
                let orphanedBoundaries = attribution.portLevelBoundaries
                    .compactMap { id -> USBDeviceNode? in
                        guard let node = nodeByID[id] else { return nil }
                        let parentIsAttributed = parentOf[id].flatMap { attribution.regionOwner[$0] } != nil
                        return parentIsAttributed ? node : nil
                    }
                // Preserve the original (unsorted, forest-declared) order
                // when there are no orphaned boundaries to merge in, so
                // existing ordering expectations are untouched; only sort
                // when boundaries need to be interleaved in.
                entries = orphanedBoundaries.isEmpty
                    ? forestRootLeftovers
                    : (forestRootLeftovers + orphanedBoundaries)
                        .sorted { $0.device.locationID < $1.device.locationID }
            }
            return entries.flatMap {
                nestedRows($0, depth: depth, group: owner, attribution: attribution)
            }
        }
    }

    /// One subtree, nested, stopping at any node that belongs to a different
    /// chain device (that node renders under its own chain row instead).
    private static func nestedRows(
        _ node: USBDeviceNode,
        depth: Int,
        group: Int64?,
        attribution: ChainDeviceAttribution
    ) -> [Row] {
        if let mark = attribution.regionRoots[node.device.id], mark != group { return [] }
        // Stage B v2 boundary (step 9): a `portLevelBoundaries` node never
        // renders nested inside an attributed group's subtree (`group !=
        // nil`); it has its own explicit entry in the port-level (leftover)
        // group instead (see `groupRows`'s `orphanedBoundaries`), which
        // calls back into this function with `group == nil`, where this
        // check does not fire and the node (and its subtree) render
        // normally.
        if group != nil, attribution.portLevelBoundaries.contains(node.device.id) { return [] }
        // An absorbed device IS the chain row above it, so its own row would be
        // a duplicate. Its children move up to take its place.
        if attribution.absorbed.contains(node.device.id) {
            return node.children.flatMap {
                nestedRows($0, depth: depth, group: group, attribution: attribution)
            }
        }
        return [Row(label: deviceLabel(for: node), depth: depth, device: node)]
            + node.children.flatMap {
                nestedRows($0, depth: depth + 1, group: group, attribution: attribution)
            }
    }

    /// Hub ancestors above each device, keyed by IOKit entry id.
    private static func hubDepths(_ forest: [USBDeviceNode]) -> [UInt64: Int] {
        var result: [UInt64: Int] = [:]
        func walk(_ node: USBDeviceNode, _ above: Int) {
            result[node.device.id] = above
            let next = node.device.isHub ? above + 1 : above
            for child in node.children { walk(child, next) }
        }
        for root in forest { walk(root, 0) }
        return result
    }

    /// The display rows for a port: one per connected monitor, at depth 1.
    ///
    /// "Display: <name> · video output N" suffix (Phase B of the TB link
    /// tree root project): only when the port has exactly one connected
    /// display AND exactly one cross-cable video tunnel with a known
    /// terminal adapter port. Every other shape (0, or 2+, of either)
    /// renders the plain "Display: <name>" label as before.
    ///
    /// Honest framing of what this suffix actually proves: there is NO
    /// shared join key between IOPortTransportStateDisplayPort (joined
    /// to a port by HPM `parentPortNumber`) and TunnelPath (the TB
    /// adapter number space). The pairing here is by uniqueness only:
    /// exactly one display and exactly one video tunnel on this port.
    /// That rules out mislabelling WHICH monitor a suffix names (there's
    /// only one candidate), but it does not independently confirm the
    /// sole video tunnel is the thing feeding the sole display; that
    /// remains a (very likely, but unverified) assumption.
    private static func displayRows(
        displayPorts: [IOPortTransportStateDisplayPort],
        hostRoot: IOThunderboltSwitch,
        switches: [IOThunderboltSwitch]
    ) -> [Row] {
        let videoTunnels = ActiveTunnelPresentation.crossCableTunnels(
            ThunderboltTopology.tunnels(from: hostRoot, in: switches),
            switches: switches
        ).filter { $0.kind == .video && $0.terminalAdapterPortNumber != nil }
        let soleVideoOutputAdapter: Int? = (displayPorts.count == 1 && videoTunnels.count == 1)
            ? videoTunnels[0].terminalAdapterPortNumber
            : nil

        return displayPorts.map { dp in
            if let adapterNumber = soleVideoOutputAdapter, let name = displayName(for: dp) {
                return Row(
                    label: String(localized: "Display: \(name) \u{00B7} video output \(adapterNumber)", bundle: _coreLocalizedBundle),
                    depth: 1
                )
            }
            return Row(label: displayLabel(for: dp), depth: 1)
        }
    }

    /// Device rows, grouped under a header per USB controller when the port
    /// has more than one. Falls back to the plain tree otherwise, so the
    /// single-bus case and every directly-attached port render as before.
    private static func deviceRowsGroupedByBus(_ devices: [USBDevice], hubs: HubDisplay = .all) -> [Row] {
        guard let groups = USBDeviceNode.groupedByBus(from: devices) else {
            let roots = USBDeviceNode.buildTree(from: devices)
            return rowsFor(roots, depthOffset: 0, hubs: hubs)
        }
        return groups.flatMap { group in
            [Row(label: USBDeviceNode.busLabel(group.bus), depth: 0)]
                + rowsFor(group.roots, depthOffset: 1, hubs: hubs)
        }
    }

    /// Flatten a device forest into rows, honouring the hub display mode.
    private static func rowsFor(_ roots: [USBDeviceNode], depthOffset: Int, hubs: HubDisplay) -> [Row] {
        switch hubs {
        case .all:
            return USBDeviceNode.flatten(roots).map {
                Row(label: deviceLabel(for: $0), depth: $0.depth + depthOffset, device: $0)
            }
        case .endpointsOnly:
            let collapsed = roots.flatMap { endpointRows($0, hubsAbove: 0, depth: depthOffset) }
            // Every device is a hub (a bare dock with nothing plugged in), so
            // collapsing leaves nothing to show. Fall back to the full tree
            // rather than render an empty "Connected devices" section.
            guard collapsed.isEmpty else { return collapsed }
            return USBDeviceNode.flatten(roots).map {
                Row(label: deviceLabel(for: $0), depth: $0.depth + depthOffset, device: $0)
            }
        }
    }

    /// Rows for one subtree with the hubs collapsed away.
    ///
    /// Every non-hub device becomes one row at a FLAT depth, annotated with the
    /// number of hubs between it and the port. The nesting is what made the
    /// full tree hard to read (five levels, mostly hubs), and once the hubs are
    /// gone the remaining devices are siblings in every sense the user cares
    /// about: they are all "things plugged into this port, through some hubs".
    ///
    /// A hub whose subtree contains no non-hub device is emitted itself, so a
    /// dock that is nothing but hubs still shows something rather than an empty
    /// section.
    private static func endpointRows(_ node: USBDeviceNode, hubsAbove: Int, depth: Int) -> [Row] {
        if node.device.isHub {
            // A hub with nothing behind it is still just plumbing, so it is
            // dropped like the rest. An earlier version showed it, reasoning
            // that a device should never silently vanish; on a real dock that
            // leaked two lone hubs into a list captioned "Show 9 hubs", which
            // read as a bug. Nothing is lost: they are counted in the toggle
            // and one click brings them back. The empty-result case is handled
            // by the caller, which falls back to the full tree.
            return node.children.flatMap {
                endpointRows($0, hubsAbove: hubsAbove + 1, depth: depth)
            }
        }
        return [endpointRow(for: node, depth: depth, hubsAbove: hubsAbove)]
            + node.children.flatMap { endpointRows($0, hubsAbove: hubsAbove, depth: depth) }
    }

    /// One collapsed device row: the device, plus how many hubs sit between it
    /// and the port when that is worth saying.
    ///
    /// The hop count is its own key, separate from the device label, so it can
    /// carry a proper plural rule in Localizable.stringsdict. An earlier version
    /// interpolated the label into the localized string, which made the key
    /// unusable for pluralisation and produced "via 1 hubs" until a hand-rolled
    /// two-way switch papered over it. That switch would still have read wrong
    /// in languages with more than two plural categories (Polish, Russian,
    /// Arabic), which is what stringsdict exists for.
    ///
    /// `hubsAbove: 0` means no suffix, which is also how the chain layout asks
    /// for a bare label on a row that already says which device it is inside.
    private static func endpointRow(for node: USBDeviceNode, depth: Int, hubsAbove: Int) -> Row {
        let base = deviceLabel(for: node)
        guard hubsAbove > 0 else { return Row(label: base, depth: depth, device: node) }
        let suffix = String(localized: "via \(hubsAbove) hubs", bundle: _coreLocalizedBundle)
        return Row(label: "\(base) \u{00B7} \(suffix)", depth: depth, device: node)
    }

    /// One device row's label. Names go through `USBDevice.displayName` so
    /// this tree, the CLI and the dashboard can never disagree about how a
    /// device is named; it also carries the localized "Unknown" fallback.
    private static func deviceLabel(for node: USBDeviceNode) -> String {
        "\(node.device.displayName) - \(node.device.speedLabel)"
    }

    /// The host root switch for this port, if it maps to one. Shared by
    /// `thunderboltRootRow` (the root row) and `rows` (tunnel lookups for the
    /// display-suffix rule) so both use the exact same socket join.
    ///
    /// The socket join relies on an invariant verified against every fabric
    /// dump we hold (M2 Pro, M3 MBA, M3 Ultra with 6 ports, M5, M5 Pro; see
    /// `research/dumps/tb-fabric/` and `--tb-debug` live): on Apple Silicon
    /// each host-root switch serves exactly ONE socket (one controller per
    /// physical port), so `hostRoot(forSocketID:)` can never hand this port a
    /// sibling port's downstream device. This is the same join the shipped
    /// fabric tree, `DataLinkDiagnostic`, and `TunnelledDeviceGrouping`
    /// already stand on; if a future Mac ever shares a root across sockets,
    /// the fix belongs in `ThunderboltTopology` for all consumers at once.
    private static func thunderboltHostRoot(
        port: AppleHPMInterface,
        switches: [IOThunderboltSwitch]
    ) -> IOThunderboltSwitch? {
        guard let socketID = ThunderboltTopology.socketID(for: port) else { return nil }
        return ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches)
    }

    /// One chain device's row: the dock or display itself plus the live link it
    /// arrived on, at its own depth in the fabric. Depth 0 is the first hop, the
    /// thing this port's cable is plugged into.
    ///
    /// Chain rows carry no `device`, so a renderer treats them like the display
    /// and bus-header rows: plain text, no expandable detail.
    private static func chainRow(for node: IOThunderboltSwitchNode) -> Row {
        let name = ThunderboltLabels.deviceName(for: node.sw)
        guard let link = linkDescription(for: node.sw) else {
            return Row(label: name, depth: node.depth)
        }
        return Row(label: "\(name) - \(link)", depth: node.depth)
    }

    /// "Thunderbolt link active at 40 Gbps" for symmetric links (the common
    /// case). Reuses the exact localised key `PortSummary`'s bullet uses, so
    /// the tree and the bullet can never disagree in any language. Asymmetric
    /// TB5 links (3 TX / 1 RX) have no single honest total, so they fall back
    /// to `ThunderboltLabels.linkLabel`'s per-lane form
    /// ("Up to 40 Gb/s (3 TX / 1 RX)"). `nil` when no lane is active.
    ///
    /// The lane is the switch's UPSTREAM lane (the leg toward the Mac) when
    /// it is active: the root row describes how the dock reaches this port,
    /// and on a daisy-chained dock the first active lane could otherwise be
    /// the downstream leg to the next device, which can run a different
    /// generation. Falls back to `connectionLanePort` (first active lane)
    /// when the upstream lane is not the active one.
    private static func linkDescription(for sw: IOThunderboltSwitch) -> String? {
        let upstream = sw.ports.first {
            $0.adapterType.isLane && $0.hasActiveLink && $0.portNumber == sw.upstreamPortNumber
        }
        guard let lane = upstream ?? ThunderboltTopology.connectionLanePort(sw) else { return nil }
        guard let gen = lane.currentSpeed,
              let width = lane.currentWidth,
              let perLane = gen.perLaneGbps,
              !(width.asymmetricTx || width.asymmetricRx)
        else { return ThunderboltLabels.linkLabel(for: lane) }
        let total = Double(perLane * max(width.txLanes, 1))
        return String(localized: "Thunderbolt link active at \(DataLinkDiagnostic.label(total))", bundle: _coreLocalizedBundle)
    }

    /// The monitor's display name, from its EDID (the same source the
    /// display banner uses), falling back to the transport's product name.
    /// `nil` when neither source gives a usable (non-blank) name.
    private static func displayName(for dp: IOPortTransportStateDisplayPort) -> String? {
        let name = dp.monitor?.edid.flatMap { EDIDInfo($0)?.monitorName }
            ?? dp.monitor?.productName
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return name
    }

    /// "Display: LEN G34w-10", or the bare "Display" label when no name is
    /// resolvable.
    private static func displayLabel(for dp: IOPortTransportStateDisplayPort) -> String {
        guard let name = displayName(for: dp) else {
            return String(localized: "Display", bundle: _coreLocalizedBundle)
        }
        return String(localized: "Display: \(name)", bundle: _coreLocalizedBundle)
    }
}
