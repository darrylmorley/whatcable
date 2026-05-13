import Foundation

/// Pure helpers that turn `ThunderboltSwitch` / `ThunderboltPort` model
/// values into user-facing labels. Convention: per-lane Gb/s × lane count,
/// matching Apple's `system_profiler SPThunderboltDataType` output so the
/// labels line up with what users see in About This Mac → System Information.
///
/// TB5 was confirmed against a real M5 Pro + UGreen JHL9580 dock sample on
/// issue #52, so the renderer now emits a confirmed TB5 label for raw speed
/// code `0x2`. See planning/thunderbolt-fabric.md for the reasoning.
public enum ThunderboltLabels {
    /// Compact human label for an active TB link.
    /// Returns nil if the port has no active link.
    /// Examples:
    /// - `"Up to 20 Gb/s × 2"` (USB4 / TB4 dual-lane)
    /// - `"Up to 10 Gb/s × 1"` (TB3 single-lane)
    /// - `"Up to 40 Gb/s × 2"` (TB5 / USB4 v2 dual-lane)
    /// - `"Up to 40 Gb/s (3 TX / 1 RX)"` (TB5 asymmetric)
    public static func linkLabel(for port: ThunderboltPort) -> String? {
        guard port.hasActiveLink,
              let gen = port.currentSpeed,
              let width = port.currentWidth else {
            return nil
        }

        switch gen {
        case .tb3, .usb4Tb4, .tb5:
            guard let perLane = gen.perLaneGbps else { return nil }
            let lanes = describeLanes(width)
            return String(localized: "Up to \(perLane) Gb/s \(lanes)", bundle: .module)
        case .unknown(let raw):
            let hex = String(raw, radix: 16)
            return String(localized: "Unknown generation (raw speed code 0x\(hex))", bundle: .module)
        }
    }

    /// Lane-count suffix. Symmetric links read `× N`; asymmetric links
    /// (TB5 3+1 configurations) read `(N TX / M RX)`.
    private static func describeLanes(_ width: LinkWidth) -> String {
        if width.asymmetricTx || width.asymmetricRx {
            return "(\(width.txLanes) TX / \(width.rxLanes) RX)"
        }
        // Symmetric: just lane count.
        let lanes = max(width.txLanes, 1)
        return "× \(lanes)"
    }

    /// Human-readable name for a downstream switch ("ASUS PA32QCV",
    /// "CalDigit, Inc. TS3 Plus"). Falls back to "Unknown device" if the
    /// DROM didn't decode (rare but possible).
    public static func deviceName(for sw: ThunderboltSwitch) -> String {
        let vendor = sw.vendorName.trimmingCharacters(in: .whitespaces)
        let model = sw.modelName.trimmingCharacters(in: .whitespaces)
        switch (vendor.isEmpty, model.isEmpty) {
        case (false, false): return "\(vendor) \(model)"
        case (false, true): return vendor
        case (true, false): return model
        case (true, true): return String(localized: "Unknown device", bundle: .module)
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
        in switches: [ThunderboltSwitch]
    ) -> ThunderboltSwitch? {
        switches.first { sw in
            sw.isHostRoot && sw.ports.contains {
                $0.adapterType.isLane && $0.socketID == socketID
            }
        }
    }

    /// Parse the trailing `@N` suffix from a port serviceName, or nil if
    /// it doesn't have one. `Port-USB-C@1` → `"1"`.
    public static func socketID(fromServiceName name: String) -> String? {
        guard let at = name.lastIndex(of: "@") else { return nil }
        let suffix = name[name.index(after: at)...]
        return suffix.isEmpty ? nil : String(suffix)
    }

    /// Return the chain of downstream switches reachable from a host root,
    /// in depth order (root → device). Walks the `parentSwitchUID` graph.
    /// Returns just the root if there's nothing downstream.
    public static func chain(
        from root: ThunderboltSwitch,
        in switches: [ThunderboltSwitch]
    ) -> [ThunderboltSwitch] {
        var byParent: [Int64: [ThunderboltSwitch]] = [:]
        for sw in switches {
            guard let parentUID = sw.parentSwitchUID else { continue }
            byParent[parentUID, default: []].append(sw)
        }

        var chain: [ThunderboltSwitch] = [root]
        var current = root
        // Follow first-child only. Daisy-chains are linear in the common
        // case; if the user has a true tree (dock with two TB devices),
        // the chain follows the first downstream branch and the GUI tree
        // can render the full topology separately.
        while let children = byParent[current.id], let next = children.first {
            chain.append(next)
            current = next
        }
        return chain
    }

    /// Find the active downstream lane port on a switch (the one going
    /// toward the next-hop device, not the upstream link to the host).
    /// Useful for picking which port's link state describes the next leg.
    public static func activeDownstreamLanePort(_ sw: ThunderboltSwitch) -> ThunderboltPort? {
        // Host root: any active lane port is downstream by definition.
        // Downstream switch: skip the lane port matching upstreamPortNumber,
        // pick the first active one of the rest.
        let candidates = sw.ports.filter { $0.adapterType.isLane && $0.hasActiveLink }
        if sw.isHostRoot {
            return candidates.first
        }
        return candidates.first { $0.portNumber != sw.upstreamPortNumber }
    }
}
