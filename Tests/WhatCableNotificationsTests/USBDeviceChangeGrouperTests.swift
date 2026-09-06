import Testing
@testable import WhatCableNotifications

/// Fixture topology is the real device tree from issue #551 (a DIGITUS
/// 8-port dock, `whatcable --json --raw` capture): two VIA Labs branches off
/// the dock, a USB2.0 branch (with an Apple Keyboard Hub nested inside it)
/// and a USB3.0 branch (with a nested USB3.0 hub carrying a Realtek LAN
/// adapter, plus a Generic Mass Storage device). locationIDs are the real
/// values from that capture; entryIDs are synthetic since the report didn't
/// include them.
@Suite("USBDeviceChangeGrouper")
struct USBDeviceChangeGrouperTests {
    private typealias Snapshot = USBDeviceChangeGrouper.Snapshot

    // MARK: - Fixture topology (issue #551)

    private static let usb2Hub = Snapshot(id: 1, locationID: 0x01100000, name: "USB2.0 Hub")
    private static let keyboardHub = Snapshot(id: 2, locationID: 0x01120000, name: "Keyboard Hub")
    private static let appleKeyboard = Snapshot(id: 3, locationID: 0x01122000, name: "Apple Keyboard")
    private static let pdDevice = Snapshot(id: 4, locationID: 0x01140000, name: "USB-C PD3.0 Device")

    private static let usb3Hub = Snapshot(id: 5, locationID: 0x01200000, name: "USB3.0 Hub")
    private static let nestedUsb3Hub = Snapshot(id: 6, locationID: 0x01210000, name: "USB3.0 Hub Inner")
    private static let realtekLAN = Snapshot(id: 7, locationID: 0x01212000, name: "USB 10_100_1000 LAN")
    private static let massStorage = Snapshot(id: 8, locationID: 0x01230000, name: "Mass Storage Device")

    private static var fullTree: [Snapshot] {
        [usb2Hub, keyboardHub, appleKeyboard, pdDevice, usb3Hub, nestedUsb3Hub, realtekLAN, massStorage]
    }

    // MARK: - 1. Keyboard-Hub unplug

    @Test("Unplugging the Keyboard Hub groups it with its child under one root")
    func keyboardHubUnplugGroupsWithChild() throws {
        let previous = Self.fullTree
        let current = Self.fullTree.filter { $0.id != Self.keyboardHub.id && $0.id != Self.appleKeyboard.id }

        let (added, removed) = USBDeviceChangeGrouper.diff(previous: previous, current: current)

        #expect(added.isEmpty)
        #expect(removed.count == 1)
        let group = try #require(removed.first)
        #expect(group.rootName == "Keyboard Hub")
        #expect(group.memberNames == ["Apple Keyboard"])
    }

    // MARK: - 2. Whole-dock unplug

    @Test("Unplugging the whole dock groups by each top-level hub's full subtree")
    func wholeDockUnplugGroupsByTopLevelHub() throws {
        let previous = Self.fullTree
        let current: [Snapshot] = []

        let (added, removed) = USBDeviceChangeGrouper.diff(previous: previous, current: current)

        #expect(added.isEmpty)
        #expect(removed.count == 2)

        let usb2Group = try #require(removed.first { $0.rootName == "USB2.0 Hub" })
        #expect(Set(usb2Group.memberNames) == ["Keyboard Hub", "Apple Keyboard", "USB-C PD3.0 Device"])

        let usb3Group = try #require(removed.first { $0.rootName == "USB3.0 Hub" })
        #expect(Set(usb3Group.memberNames) == ["USB3.0 Hub Inner", "USB 10_100_1000 LAN", "Mass Storage Device"])

        // No device from the previous tree is missing or double-counted.
        let totalAccountedFor = removed.reduce(0) { $0 + 1 + $1.memberNames.count }
        #expect(totalAccountedFor == previous.count)
    }

    // MARK: - 3. Single leaf add and remove

    @Test("Adding a single leaf device produces a single-member group")
    func singleLeafAdd() throws {
        let previous: [Snapshot] = [Self.usb3Hub]
        let current: [Snapshot] = [Self.usb3Hub, Self.massStorage]

        let (added, removed) = USBDeviceChangeGrouper.diff(previous: previous, current: current)

        #expect(removed.isEmpty)
        #expect(added.count == 1)
        let group = try #require(added.first)
        #expect(group.rootName == "Mass Storage Device")
        #expect(group.memberNames.isEmpty)
    }

    @Test("Removing a single leaf device produces a single-member group")
    func singleLeafRemove() throws {
        let previous: [Snapshot] = [Self.usb3Hub, Self.massStorage]
        let current: [Snapshot] = [Self.usb3Hub]

        let (added, removed) = USBDeviceChangeGrouper.diff(previous: previous, current: current)

        #expect(added.isEmpty)
        #expect(removed.count == 1)
        let group = try #require(removed.first)
        #expect(group.rootName == "Mass Storage Device")
        #expect(group.memberNames.isEmpty)
    }

    // MARK: - 4. Connect of the Keyboard Hub subtree

    @Test("Connecting the Keyboard Hub subtree groups it with its child")
    func keyboardHubConnectGroupsWithChild() throws {
        let previous = Self.fullTree.filter { $0.id != Self.keyboardHub.id && $0.id != Self.appleKeyboard.id }
        let current = Self.fullTree

        let (added, removed) = USBDeviceChangeGrouper.diff(previous: previous, current: current)

        #expect(removed.isEmpty)
        #expect(added.count == 1)
        let group = try #require(added.first)
        #expect(group.rootName == "Keyboard Hub")
        #expect(group.memberNames == ["Apple Keyboard"])
    }

    // MARK: - 5. Split-fire documentation

    /// This is exactly why `NotificationManager` needs a settle-window
    /// debounce (`deviceSettleWindow`) rather than diffing every publish in
    /// isolation: IOKit can deliver a hub's own termination and its child's
    /// termination as two separate publishes. Diffed alone, each publish
    /// looks like a clean, correctly-grouped change: first the leaf goes,
    /// then (once the hub itself catches up) the hub goes. But taken as two
    /// separate notifications, the user sees "Apple Keyboard disconnected"
    /// followed later by "Keyboard Hub disconnected", instead of the one
    /// "Keyboard Hub" notification that reflects what physically happened
    /// (one hub unplugged). The debounce exists to fold these two publishes
    /// back into a single diff before this function ever sees them.
    @Test("A hub's split-fire termination diffs as two separate single-item groups")
    func splitFireTerminationDocumentsWhyTheDebounceExists() throws {
        let previous = Self.fullTree
        // Intermediate publish: only the leaf (Apple Keyboard) has gone so far.
        let intermediate = Self.fullTree.filter { $0.id != Self.appleKeyboard.id }
        // Final publish: the hub itself has now also gone.
        let final = intermediate.filter { $0.id != Self.keyboardHub.id }

        let (_, removedAtLeafStep) = USBDeviceChangeGrouper.diff(previous: previous, current: intermediate)
        #expect(removedAtLeafStep.count == 1)
        let leafGroup = try #require(removedAtLeafStep.first)
        #expect(leafGroup.rootName == "Apple Keyboard")
        #expect(leafGroup.memberNames.isEmpty)

        let (_, removedAtHubStep) = USBDeviceChangeGrouper.diff(previous: intermediate, current: final)
        #expect(removedAtHubStep.count == 1)
        let hubGroup = try #require(removedAtHubStep.first)
        #expect(hubGroup.rootName == "Keyboard Hub")
        #expect(hubGroup.memberNames.isEmpty)
    }

    // MARK: - 6. Changed grandchild under an UNCHANGED intermediate hub

    /// `usb2Hub` -> `keyboardHub` -> `appleKeyboard` is a three-level chain.
    /// Here the root (`usb2Hub`) and the grandchild (`appleKeyboard`) both
    /// change, but the hub between them (`keyboardHub`) does not: it's
    /// present, identical, in both snapshots. The fold has to walk PAST that
    /// unchanged hub to find the grandchild's nearest changed ancestor,
    /// which is the root two levels up, not stop at the first ancestor it
    /// meets. `keyboardHub` itself must not appear anywhere in the group
    /// (it didn't change).
    @Test("Removing a root and its grandchild groups them despite an unchanged hub between them")
    func removalGroupsAcrossUnchangedIntermediateHub() throws {
        let previous = Self.fullTree
        let current = Self.fullTree.filter { $0.id != Self.usb2Hub.id && $0.id != Self.appleKeyboard.id }

        let (added, removed) = USBDeviceChangeGrouper.diff(previous: previous, current: current)

        #expect(added.isEmpty)
        #expect(removed.count == 1)
        let group = try #require(removed.first)
        #expect(group.rootName == "USB2.0 Hub")
        #expect(group.memberNames == ["Apple Keyboard"])
    }

    @Test("Adding a root and its grandchild groups them despite an unchanged hub between them")
    func addGroupsAcrossUnchangedIntermediateHub() throws {
        let previous = Self.fullTree.filter { $0.id != Self.usb2Hub.id && $0.id != Self.appleKeyboard.id }
        let current = Self.fullTree

        let (added, removed) = USBDeviceChangeGrouper.diff(previous: previous, current: current)

        #expect(removed.isEmpty)
        #expect(added.count == 1)
        let group = try #require(added.first)
        #expect(group.rootName == "USB2.0 Hub")
        #expect(group.memberNames == ["Apple Keyboard"])
    }
}
