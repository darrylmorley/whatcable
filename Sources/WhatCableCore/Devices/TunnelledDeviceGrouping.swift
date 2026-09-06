import Foundation

/// Decides how to present USB devices that match no physical USB-C port and
/// would otherwise be silently dropped. Two cases:
///
/// 1. Devices reached over a Thunderbolt tunnel (issue #274), behind a TB dock
///    or display. The helper nests them under the host port when exactly one
///    Thunderbolt device is connected, else renders flat.
/// 2. Devices behind an internal Apple USB hub (issue #348), the front USB-C
///    and USB-A ports on Mac mini / Studio / Pro. These never nest under a
///    port: front ports have no port-controller silicon to attribute to.
///
/// Safety rule for the TB-tunnelled nesting: only attribute to a port when
/// **exactly one** Thunderbolt device is connected. With one connection there
/// is no ambiguity about what the tunnelled devices are behind, so the
/// attribution is certain without the per-port tunnel join (the
/// `apciec`/`acio` correlation that is not yet confirmed on multi-port
/// hardware). With two or more Thunderbolt devices the helper returns no
/// host port and the caller renders a flat "Other USB devices" section
/// instead of guessing.
///
/// Pure logic, no IOKit. Shared by the menu bar app, the CLI text output, and
/// the JSON output so all three group identically.
public enum TunnelledDeviceGrouping {
    public struct Result: Equatable {
        /// The Thunderbolt-tunnelled devices, in input order. Empty when there
        /// are none, in which case the caller shows no extra section.
        public let devices: [USBDevice]
        /// The `serviceName` of the one connected Thunderbolt port these devices
        /// nest under (e.g. "Port-USB-C@2"), or `nil` to render them flat. Only
        /// set when exactly one Thunderbolt device is connected.
        public let hostPortServiceName: String?
        /// Devices on a desktop Mac's plain-USB front ports (issue #348).
        /// Not attributed to a port (front ports have no port-controller silicon
        /// to attribute to), but may include a hub the user plugged into a front
        /// port, kept so its children nest under it in the rendered tree. This is
        /// the single place the desktop-only policy is applied: it is empty unless
        /// `group` was called
        /// with `isDesktopMac: true`, so every consumer of this array is
        /// laptop-safe without its own check. Also empty when there is no
        /// front-port activity.
        public let internalHubDevices: [USBDevice]

        public init(
            devices: [USBDevice],
            hostPortServiceName: String?,
            internalHubDevices: [USBDevice] = []
        ) {
            self.devices = devices
            self.hostPortServiceName = hostPortServiceName
            self.internalHubDevices = internalHubDevices
        }
    }

    /// Hubs are deliberately kept in both result sets, not filtered out. A hub is
    /// a branch point of the device tree, so dropping it collapses everything
    /// behind it to a flat list and hides which device hangs off which hub. That
    /// flat list is exactly what users kept reporting (issues #106, #280, #375:
    /// "USB2.1 Hub -> Magic Trackpad" should read as the hub with the trackpad
    /// nested under it). `USBDeviceNode.buildTree` needs the hub present to nest
    /// its children, so keeping hubs is what lets the renderers (app, CLI, JSON)
    /// show the real hierarchy. The Mac's own internal front-panel hub is never a
    /// member of either set (it is the boundary the walk stops at, never itself
    /// flagged `isThunderboltTunnelled` or `isBehindInternalHub`), so showing hubs
    /// surfaces the hubs the user attached, never the Mac's internal plumbing.
    ///
    /// - Parameter isDesktopMac: gates the `internalHubDevices` result. The
    ///   front-panel hub ports only exist on Mac mini / Studio / Pro, so on a
    ///   laptop the internal-hub set is forced empty here regardless of the
    ///   per-device structural flag. Defaults to `false` (fail closed): a caller
    ///   that does not opt in gets no front-port devices, never a laptop false
    ///   positive. The `isBehindInternalHub` flag itself stays pure structural
    ///   truth; this is the one place the desktop product policy is applied.
    /// The tunnelled devices belonging to THIS port by structure, not by the
    /// single-active-port heuristic `group(...)` below falls back to: those
    /// whose `tunnelRootName` matches the port's own `apciecN` root, derived
    /// from its Thunderbolt host root switch's `acioRootName` (the
    /// corpus-verified apciec<->acio index pairing,
    /// `research/usb-chain-attribution-identifiers.md`). This is the
    /// port-scoping join `ChainDeviceAttribution`'s structural tunnel pass
    /// needs as its `expectedTunnelRootName`, and it is also how a device
    /// with a valid `tunnelRootName` is fed into `ConnectedDeviceTree.rows`'s
    /// `tunnelledDevices` parameter so it nests in the SAME tree as the
    /// port's other devices, instead of the flat/single-port fallback below.
    ///
    /// Returns `[]` when the port has no Thunderbolt host root, the host
    /// root's `acioRootName` was never captured (older macOS, or the acio
    /// ancestor walk's bound was exceeded), or no device's `tunnelRootName`
    /// matches it. All three fail closed to "claims nothing", leaving the
    /// device to the single-active-port fallback in `group(...)`, which is
    /// the ONLY path for a device with no structural root data at all
    /// (`tunnelRootName == nil`): this function can never structurally claim
    /// such a device, by construction (`$0.tunnelRootName == apciecName`
    /// requires a non-nil match).
    public static func structurallyScopedTunnelledDevices(
        for port: AppleHPMInterface,
        in devices: [USBDevice],
        thunderboltSwitches: [IOThunderboltSwitch]
    ) -> [USBDevice] {
        guard let socketID = ThunderboltTopology.socketID(for: port),
              let hostRoot = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches),
              let acioName = hostRoot.acioRootName,
              let apciecName = ThunderboltTopology.apciecRootName(fromAcioRootName: acioName)
        else { return [] }
        return devices.filter { $0.isThunderboltTunnelled && $0.tunnelRootName == apciecName }
    }

    /// The `usbTunnelSwitchUIDs` argument `ChainDeviceAttribution.resolve`
    /// wants for this port: the switch UIDs of the USB-carrying tunnels this
    /// port's fabric actually reports. Shared here (rather than duplicated at
    /// each call site) because both the CLI (`TextFormatter`) and the app
    /// (`ContentView`) need to compute the exact same set for the exact same
    /// port.
    public static func usbTunnelSwitchUIDs(
        for port: AppleHPMInterface,
        thunderboltSwitches: [IOThunderboltSwitch]
    ) -> Set<Int64> {
        guard let socketID = ThunderboltTopology.socketID(for: port),
              let hostRoot = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches)
        else { return [] }
        return ThunderboltTopology.usbTunnelTerminalSwitchUIDs(from: hostRoot, in: thunderboltSwitches)
    }

    /// This port's own `apciecN` root name, when derivable: the
    /// `expectedTunnelRootName` argument `ChainDeviceAttribution.resolve`
    /// wants. `nil` under the same conditions
    /// `structurallyScopedTunnelledDevices` fails closed on.
    public static func expectedTunnelRootName(
        for port: AppleHPMInterface,
        thunderboltSwitches: [IOThunderboltSwitch]
    ) -> String? {
        guard let socketID = ThunderboltTopology.socketID(for: port),
              let hostRoot = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches),
              let acioName = hostRoot.acioRootName
        else { return nil }
        return ThunderboltTopology.apciecRootName(fromAcioRootName: acioName)
    }

    /// Every USB device attributable to `port`: its direct native-bus matches
    /// (`matchingDevices`, the `UsbIOPort`/bus join) UNION the tunnelled
    /// devices structurally scoped to it by `apciecN` root name
    /// (`structurallyScopedTunnelledDevices`), deduplicated by device id with
    /// input order preserved.
    ///
    /// This is the ONE list/count/summary answer to "what devices are on this
    /// port", shared by the widget snapshot (Core), the formatters' per-port
    /// device arrays, and the Pro screens, so they cannot drift (plan
    /// `pcie-tunnelled-usb-attribution`, review round 2/3). It is NOT for
    /// `ConnectedDeviceTree.rows`, which keeps the split matched/scoped
    /// arrays; feeding it the union would render structural devices twice.
    public static func attributedDevices(
        for port: AppleHPMInterface,
        in devices: [USBDevice],
        thunderboltSwitches: [IOThunderboltSwitch]
    ) -> [USBDevice] {
        var seen = Set<UInt64>()
        var result: [USBDevice] = []
        for device in port.matchingDevices(from: devices)
            + structurallyScopedTunnelledDevices(for: port, in: devices, thunderboltSwitches: thunderboltSwitches)
        where seen.insert(device.id).inserted {
            result.append(device)
        }
        return result
    }

    public static func group(
        devices: [USBDevice],
        ports: [AppleHPMInterface],
        thunderboltSwitches: [IOThunderboltSwitch],
        isDesktopMac: Bool = false,
        // Device ids already placed by `structurallyScopedTunnelledDevices`
        // for SOME port (across every port, unioned by the caller). Excluded
        // here so a structurally-scoped device renders exactly once: nested
        // in its port's tree, never ALSO in this flat/single-port fallback.
        structurallyScoped: Set<UInt64> = []
    ) -> Result {
        // Hubs are kept (see the type doc): they are the branch points the tree
        // renderer needs to nest each device under the hub it hangs off.
        let tunnelled = devices.filter { $0.isThunderboltTunnelled && !structurallyScoped.contains($0.id) }
        // Front-port / internal-hub devices: those the parent walk flagged as
        // behind the Mac's internal hub. Desktop-only: empty on laptops (see
        // isDesktopMac). The tunnelled exclusion is defensive; isBehindInternalHub
        // already implies !tunnelled. Any hub here is one the user attached to a
        // front port (an external hub), kept so its children nest under it; the
        // Mac's own internal hub is the boundary of this set and never a member.
        // Subtract any device now claimed by a real port card via an exact
        // port-name match (issue #456): a named built-in USB-only port
        // (e.g. Port-USB-C@5 on a Mac Studio) attributes its device to the
        // card, so it must not ALSO appear here or it renders twice. Uses the
        // same `claimsInternalHubDevice` predicate `matchingDevices` uses to add
        // it, so the two sides can't drift. Only an active port claims (an
        // inactive port's `matchingDevices` returns nothing), mirroring the card
        // side exactly. USB-A built-in devices are unaffected: no USB-A port
        // card exists to claim them, so they stay here as before.
        let internalHub = isDesktopMac
            ? devices.filter { device in
                device.isBehindInternalHub
                    && !device.isThunderboltTunnelled
                    && !ports.contains { port in
                        port.connectionActive == true
                            && port.claimsInternalHubDevice(device)
                    }
            }
            : []

        guard !tunnelled.isEmpty else {
            return Result(
                devices: [],
                hostPortServiceName: nil,
                internalHubDevices: internalHub
            )
        }

        // Ports that currently have a Thunderbolt device downstream (a dock or
        // display). A single dock fanning out to two displays is still one
        // connection (one port), so this counts physical Thunderbolt links.
        let portsWithDevice = ports.filter { port in
            guard let socketID = ThunderboltTopology.socketID(for: port),
                  let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches)
            else { return false }
            return !ThunderboltTopology.tree(from: root, in: thunderboltSwitches).isEmpty
        }

        let hostPortServiceName = portsWithDevice.count == 1
            ? portsWithDevice.first?.serviceName
            : nil
        return Result(
            devices: tunnelled,
            hostPortServiceName: hostPortServiceName,
            internalHubDevices: internalHub
        )
    }
}
