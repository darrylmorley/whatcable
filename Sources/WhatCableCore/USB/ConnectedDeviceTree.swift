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

        /// Equality is on what the row draws: its label and depth. `device` is
        /// the model the label was derived from, carried for renderers that can
        /// show more than text, so two rows that render identically compare
        /// equal whether or not the node came along.
        public static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.label == rhs.label && lhs.depth == rhs.depth
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
    public static func rows(
        devices: [USBDevice],
        port: AppleHPMInterface,
        thunderboltSwitches: [IOThunderboltSwitch],
        displayPorts: [IOPortTransportStateDisplayPort]
    ) -> [Row] {
        let deviceRows = deviceRowsGroupedByBus(devices)

        guard let hostRoot = thunderboltHostRoot(port: port, switches: thunderboltSwitches),
              let root = thunderboltRootRow(hostRoot: hostRoot, switches: thunderboltSwitches)
        else {
            // No Thunderbolt device downstream: the plain USB tree, unchanged.
            // Directly-attached monitors (USB-C DisplayPort Alt Mode, no TB
            // tunnel) keep their existing display banner; without a root to
            // hang them under, a bare display row here would just repeat it.
            return deviceRows
        }

        // "Display: <name> · video output N" suffix (Phase B of the TB link
        // tree root project): only when the port has exactly one connected
        // display AND exactly one cross-cable video tunnel with a known
        // terminal adapter port. Every other shape (0, or 2+, of either)
        // renders the plain "Display: <name>" label as before.
        //
        // Honest framing of what this suffix actually proves: there is NO
        // shared join key between IOPortTransportStateDisplayPort (joined
        // to a port by HPM `parentPortNumber`) and TunnelPath (the TB
        // adapter number space). The pairing here is by uniqueness only:
        // exactly one display and exactly one video tunnel on this port.
        // That rules out mislabelling WHICH monitor a suffix names (there's
        // only one candidate), but it does not independently confirm the
        // sole video tunnel is the thing feeding the sole display; that
        // remains a (very likely, but unverified) assumption.
        let videoTunnels = ActiveTunnelPresentation.crossCableTunnels(
            ThunderboltTopology.tunnels(from: hostRoot, in: thunderboltSwitches),
            switches: thunderboltSwitches
        ).filter { $0.kind == .video && $0.terminalAdapterPortNumber != nil }
        let soleVideoOutputAdapter: Int? = (displayPorts.count == 1 && videoTunnels.count == 1)
            ? videoTunnels[0].terminalAdapterPortNumber
            : nil

        var rows = [root]
        for dp in displayPorts {
            if let adapterNumber = soleVideoOutputAdapter, let name = displayName(for: dp) {
                rows.append(Row(
                    label: String(localized: "Display: \(name) \u{00B7} video output \(adapterNumber)", bundle: _coreLocalizedBundle),
                    depth: 1
                ))
            } else {
                rows.append(Row(label: displayLabel(for: dp), depth: 1))
            }
        }
        // Shift the device rows one level to sit under the Thunderbolt root,
        // carrying `device` across. Dropping it here would make the expandable
        // detail work everywhere except behind a dock, which is where the
        // device tree is longest and the detail is most wanted.
        rows.append(contentsOf: deviceRows.map {
            Row(label: $0.label, depth: $0.depth + 1, device: $0.device)
        })
        return rows
    }

    /// Device rows, grouped under a header per USB controller when the port
    /// has more than one. Falls back to the plain tree otherwise, so the
    /// single-bus case and every directly-attached port render as before.
    private static func deviceRowsGroupedByBus(_ devices: [USBDevice]) -> [Row] {
        guard let groups = USBDeviceNode.groupedByBus(from: devices) else {
            return USBDeviceNode.flatten(USBDeviceNode.buildTree(from: devices)).map {
                Row(label: deviceLabel(for: $0), depth: $0.depth, device: $0)
            }
        }
        return groups.flatMap { group in
            [Row(label: USBDeviceNode.busLabel(group.bus), depth: 0)]
                + USBDeviceNode.flatten(group.roots).map {
                    Row(label: deviceLabel(for: $0), depth: $0.depth + 1, device: $0)
                }
        }
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

    /// The root row: the first-hop Thunderbolt device (the dock or display
    /// the cable plugs into) plus the live link it arrived on. `nil` when
    /// `hostRoot` has no Thunderbolt device downstream.
    private static func thunderboltRootRow(
        hostRoot: IOThunderboltSwitch,
        switches: [IOThunderboltSwitch]
    ) -> Row? {
        guard let firstHop = ThunderboltTopology.tree(from: hostRoot, in: switches).first
        else { return nil }

        let name = ThunderboltLabels.deviceName(for: firstHop.sw)
        guard let link = linkDescription(for: firstHop.sw) else {
            return Row(label: name, depth: 0)
        }
        return Row(label: "\(name) - \(link)", depth: 0)
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
