import Foundation

/// Groups a desktop Mac's built-in plain-USB devices by the physical port
/// they are plugged into, so the "Built-in USB ports" section can say which
/// connector each device is on ("Built-in USB-A port 1") and render one tree
/// per port instead of one big mixed tree (issue #490).
///
/// The port identity comes from `USBDevice.controllerPortName`, the
/// `Port-USB-A@N` / `Port-USB-C@N` board node macOS 26+ publishes on the
/// device's ancestor chain (`UsbIOPort`). Corpus-verified: 21 desktop
/// machines publish distinct `Port-USB-A@N` per physical port, and devices
/// behind a user's external hub still resolve to the right port node (32
/// hub-nested chains, up to two hubs deep). On macOS 15 the node is absent
/// (0/16 machines), so every device lands in the unattributed fallback group
/// and the section renders exactly as before.
///
/// Pure logic, no IOKit. Shared by the menu bar app and the CLI text output
/// so the two group identically.
public enum BuiltInPortGrouping {
    public struct Group: Equatable {
        /// The raw port node name (e.g. "Port-USB-A@1"), or `nil` for the
        /// fallback group of devices with no recognisable port node.
        public let portNodeName: String?
        /// Connector type parsed from the node name ("USB-A", "USB-C").
        /// `nil` for the fallback group.
        public let connector: String?
        /// Port number parsed from the `@N` suffix. `nil` for the fallback.
        public let portNumber: Int?
        /// The devices on this port, in input order. Hubs are kept so the
        /// tree renderer can nest their children (same rule as
        /// `TunnelledDeviceGrouping`).
        public let devices: [USBDevice]

        public init(portNodeName: String?, connector: String?, portNumber: Int?, devices: [USBDevice]) {
            self.portNodeName = portNodeName
            self.connector = connector
            self.portNumber = portNumber
            self.devices = devices
        }
    }

    /// Parses "Port-USB-A@1" into ("USB-A", 1). `nil` when the name doesn't
    /// have the `Port-<connector>@<number>` shape.
    static func parse(portNodeName: String) -> (connector: String, portNumber: Int)? {
        guard portNodeName.hasPrefix("Port-") else { return nil }
        let trimmed = portNodeName.dropFirst("Port-".count)
        let parts = trimmed.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, let number = Int(parts[1]), !parts[0].isEmpty else { return nil }
        return (String(parts[0]), number)
    }

    /// Splits the built-in section's devices into one group per physical
    /// port, sorted by connector then port number, with an unattributed
    /// fallback group last for devices whose port node is missing (macOS 15)
    /// or unparsable. Returns a single fallback group when nothing is
    /// attributable, so callers can render the pre-#490 combined list
    /// unchanged in that case.
    public static func groups(from devices: [USBDevice]) -> [Group] {
        // Parse each name once, keyed by node name, so the group build below
        // needs no second parse and no force-unwraps (review findings on the
        // first cut of this function: the `!`s were correct only by
        // call-order, and parse ran twice per group).
        var parsedByName: [String: (connector: String, portNumber: Int)] = [:]
        var devicesByName: [String: [USBDevice]] = [:]
        var namedOrder: [String] = []
        var unattributed: [USBDevice] = []
        for device in devices {
            if let name = device.controllerPortName, let parsed = parse(portNodeName: name) {
                if devicesByName[name] == nil {
                    namedOrder.append(name)
                    parsedByName[name] = parsed
                }
                devicesByName[name, default: []].append(device)
            } else {
                unattributed.append(device)
            }
        }
        var result: [Group] = namedOrder.compactMap { name in
            guard let parsed = parsedByName[name], let devices = devicesByName[name] else { return nil }
            return Group(
                portNodeName: name,
                connector: parsed.connector,
                portNumber: parsed.portNumber,
                devices: devices
            )
        }
        // Named groups only at this point; the nil-coalescing keeps the sort
        // total even if a nil-field group ever ends up here.
        result.sort {
            ($0.connector ?? "", $0.portNumber ?? 0) < ($1.connector ?? "", $1.portNumber ?? 0)
        }
        if !unattributed.isEmpty || result.isEmpty {
            result.append(Group(portNodeName: nil, connector: nil, portNumber: nil, devices: unattributed))
        }
        return result
    }

    /// True when every device in the section sits on a named USB-A port, in
    /// which case the section title itself can say "Built-in USB-A ports"
    /// (issue #490's headline ask). False as soon as any device is on a
    /// USB-C node or unattributed, where the generic title stays.
    public static func allOnUSBA(_ groups: [Group]) -> Bool {
        !groups.isEmpty && groups.allSatisfy { $0.connector == "USB-A" }
    }
}
