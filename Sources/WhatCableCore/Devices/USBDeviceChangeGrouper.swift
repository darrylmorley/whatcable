import Foundation

/// Groups a set of connected / disconnected USB devices by hub subtree, so a
/// hub (or dock) that arrives or leaves along with its children produces one
/// notification instead of one per device.
///
/// Why this exists: IOKit does not deliver a hub's own termination and its
/// children's terminations in one atomic batch. Unplugging a hub can surface
/// the child's "gone" notification and the hub's "gone" notification in
/// separate callback fires, sometimes with the hub arriving late. A flat,
/// per-device diff (`entryID` in, `entryID` out) therefore reports whatever
/// happened to have settled by the time it ran: sometimes the child alone,
/// sometimes the hub alone, sometimes both. See issue #551.
///
/// The fix has two parts. This type is the pure half: given two device
/// snapshots, fold every changed device under its nearest ALSO-changed
/// ancestor, so a hub and its changed children always resolve to a single
/// group no matter which of them IOKit reported. The other half is a
/// settle-window debounce in `NotificationManager` (mirroring the existing
/// charger settle window) that waits for the published device list to stop
/// changing before diffing, so the split-fire deliveries above land inside
/// one diff instead of two.
///
/// Pure logic, no IOKit: reuses the same parent/child rule as
/// `USBDeviceNode.buildTree` (`USBDevice.parentLocationID`), just applied to
/// a minimal snapshot instead of the full `USBDevice` model, so fixtures stay
/// small.
public enum USBDeviceChangeGrouper {
    /// Minimal view of a `USBDevice` needed to group changes: identity,
    /// topology, and a display name. Callers build this from whatever full
    /// device model they have; the grouper never sees more than this.
    public struct Snapshot: Hashable, Sendable {
        public let id: UInt64
        public let locationID: UInt32
        public let name: String

        public init(id: UInt64, locationID: UInt32, name: String) {
            self.id = id
            self.locationID = locationID
            self.name = name
        }
    }

    /// One notification's worth of change: a subtree root plus the other
    /// devices that changed alongside it. `memberNames` excludes the root.
    ///
    /// `rootID` lets a caller recover the full device model for the root
    /// (e.g. to read its speed/vendor for a single-member notification body)
    /// by identity instead of matching on `rootName`, which is not unique:
    /// two hubs of the same model report the same product name.
    ///
    /// `rootLocationID` is the root's physical port path. It persists across
    /// a re-enumeration (the same physical port produces the same locationID
    /// even when the device gets a new entryID), so it's the key a caller
    /// uses to spot a same-port drop-and-return: a removed group and an
    /// added group with the same `rootLocationID` (and the same `rootName`)
    /// are very likely the same physical device flapping, not a swap.
    public struct ChangeGroup: Equatable, Sendable {
        public let rootID: UInt64
        public let rootName: String
        public let rootLocationID: UInt32
        public let memberNames: [String]
    }

    /// Diffs two device snapshots and groups the devices that appeared or
    /// disappeared by hub subtree.
    ///
    /// Adds are grouped over `current` (the tree the new devices now sit in);
    /// removals are grouped over `previous` (the tree they used to sit in,
    /// since by definition they are no longer in `current`).
    public static func diff(
        previous: [Snapshot],
        current: [Snapshot]
    ) -> (added: [ChangeGroup], removed: [ChangeGroup]) {
        let previousIDs = Set(previous.map(\.id))
        let currentIDs = Set(current.map(\.id))

        let addedDevices = current.filter { !previousIDs.contains($0.id) }
        let removedDevices = previous.filter { !currentIDs.contains($0.id) }

        return (
            added: group(changed: addedDevices, within: current),
            removed: group(changed: removedDevices, within: previous)
        )
    }

    /// Folds `changed` devices under their nearest also-changed ancestor,
    /// walking the parent chain through `allDevices` (which may include
    /// unchanged devices, e.g. an unchanged hub sitting between two changed
    /// descendants).
    private static func group(changed: [Snapshot], within allDevices: [Snapshot]) -> [ChangeGroup] {
        guard !changed.isEmpty else { return [] }

        let changedIDs = Set(changed.map(\.id))
        // Real IOKit locationIDs are unique per controller (the bus byte in
        // the top nibbles differs across controllers), so this dedupe is a
        // theoretical safety net, not a path expected to fire on live data.
        let byLocation = Dictionary(
            allDevices.map { ($0.locationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Nearest ancestor of `device` (by locationID chain) that is also in
        // the changed set, skipping over unchanged ancestors in between.
        // `nil` if `device` has no changed ancestor (it's a group root), or
        // if it has locationID 0 (roots the tree; groups alone).
        func nearestChangedAncestor(of device: Snapshot) -> Snapshot? {
            var locationID: UInt32? = device.locationID == 0
                ? nil
                : USBDevice.parentLocationID(device.locationID)
            while let currentLocationID = locationID {
                guard let candidate = byLocation[currentLocationID] else { return nil }
                if changedIDs.contains(candidate.id) { return candidate }
                locationID = USBDevice.parentLocationID(currentLocationID)
            }
            return nil
        }

        // Topmost changed ancestor of `device`: the group root it belongs
        // under, or `device` itself if nothing above it also changed.
        func groupRoot(of device: Snapshot) -> Snapshot {
            var node = device
            while let ancestor = nearestChangedAncestor(of: node) {
                node = ancestor
            }
            return node
        }

        var membersByRootID: [UInt64: [Snapshot]] = [:]
        var rootIDsSeen = Set<UInt64>()
        var roots: [Snapshot] = []

        for device in changed.sorted(by: { $0.locationID < $1.locationID }) {
            let root = groupRoot(of: device)
            if root.id == device.id {
                if rootIDsSeen.insert(root.id).inserted {
                    roots.append(root)
                }
            } else {
                membersByRootID[root.id, default: []].append(device)
            }
        }

        return roots
            .sorted { $0.locationID < $1.locationID }
            .map { root in
                let members = (membersByRootID[root.id] ?? []).sorted { $0.locationID < $1.locationID }
                return ChangeGroup(
                    rootID: root.id,
                    rootName: root.name,
                    rootLocationID: root.locationID,
                    memberNames: members.map(\.name)
                )
            }
    }
}
