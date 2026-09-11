import Testing
@testable import WhatCableCore

/// Tests for the user-facing label helpers and topology walker.
/// These cover the rendering convention chosen for Phase 3:
///   - per-lane Gb/s x lane count, matching Apple's `system_profiler`
///   - hedge wording for unknown speed codes
///   - daisy-chain detection by `parentSwitchUID`
@Suite("Thunderbolt Labels")
struct ThunderboltLabelsTests {

    // MARK: - linkLabel

    @Test("Label for TB3 dual lane")
    func labelForTb3DualLane() {
        let port = makeLanePort(speed: .tb3, widthRaw: 0x2)
        #expect(ThunderboltLabels.linkLabel(for: port) == "Up to 10 Gb/s × 2")
    }

    @Test("Label for TB3 single lane")
    func labelForTb3SingleLane() {
        let port = makeLanePort(speed: .tb3, widthRaw: 0x1)
        #expect(ThunderboltLabels.linkLabel(for: port) == "Up to 10 Gb/s × 1")
    }

    @Test("Label for USB4 dual lane")
    func labelForUsb4DualLane() {
        let port = makeLanePort(speed: .usb4Tb4, widthRaw: 0x2)
        #expect(ThunderboltLabels.linkLabel(for: port) == "Up to 20 Gb/s × 2")
    }

    /// TB5 was confirmed against a real M5 Pro + UGreen JHL9580 dock
    /// sample on issue #52, so the renderer now emits the same per-lane
    /// label format as TB3 and TB4 / USB4.
    @Test("Label for TB5 dual lane")
    func labelForTb5DualLane() {
        let port = makeLanePort(speed: .tb5, widthRaw: 0x2)
        #expect(ThunderboltLabels.linkLabel(for: port) == "Up to 40 Gb/s × 2")
    }

    /// TB5 asymmetric 3 TX / 1 RX is the 120 Gb/s out / 40 Gb/s in
    /// configuration reported by `system_profiler` on the M5 Pro + UGreen
    /// dock sample, labelled from the Mac side's own point of view.
    @Test("Label for TB5 asymmetric")
    func labelForTb5Asymmetric() {
        let port = makeLanePort(speed: .tb5, widthRaw: 0x4)
        #expect(ThunderboltLabels.linkLabel(for: port) == "Up to 120 Gb/s out, 40 Gb/s in")
    }

    /// The dock side of the same link: 1 TX / 3 RX, so the totals flip.
    @Test("Label for TB5 asymmetric RX")
    func labelForTb5AsymmetricRx() {
        let port = makeLanePort(speed: .tb5, widthRaw: 0x8)
        #expect(ThunderboltLabels.linkLabel(for: port) == "Up to 40 Gb/s out, 120 Gb/s in")
    }

    @Test("Label for unknown generation is hedged")
    func labelForUnknownGenerationIsHedged() {
        let port = makeLanePort(speed: .unknown(rawSpeedCode: 0x1), widthRaw: 0x2)
        #expect(ThunderboltLabels.linkLabel(for: port) == "Unknown generation (raw speed code 0x1)")
    }

    @Test("Label nil for idle port")
    func labelNilForIdlePort() {
        let port = makeLanePort(speed: nil, widthRaw: 0)
        #expect(ThunderboltLabels.linkLabel(for: port) == nil)
    }

    @Test("Label for asymmetric link")
    func labelForAsymmetricLink() {
        // 3 TX / 1 RX on TB4. Two corpus samples confirm asymmetric mode
        // on real hardware (m4max_macos26.5.2_f, m5max_macos26.5.1); this
        // covers the TB4 generation with the same math.
        let port = makeLanePort(speed: .usb4Tb4, widthRaw: 0x4)
        #expect(ThunderboltLabels.linkLabel(for: port) == "Up to 60 Gb/s out, 20 Gb/s in")
    }

    /// Seen from the far end of the link, out and in swap. A symmetric
    /// label reads the same from either end.
    @Test("Label from the far end flips the two directions")
    func labelFromFarEndFlipsDirections() {
        let rxSide = makeLanePort(speed: .tb5, widthRaw: 0x8)
        #expect(ThunderboltLabels.linkLabel(for: rxSide, from: .farEnd) == "Up to 120 Gb/s out, 40 Gb/s in")
        let txSide = makeLanePort(speed: .tb5, widthRaw: 0x4)
        #expect(ThunderboltLabels.linkLabel(for: txSide, from: .farEnd) == "Up to 40 Gb/s out, 120 Gb/s in")
        let symmetric = makeLanePort(speed: .tb5, widthRaw: 0x2)
        #expect(ThunderboltLabels.linkLabel(for: symmetric, from: .farEnd) == "Up to 40 Gb/s × 2")
    }

    /// The dock's upstream lane faces the Mac, so its 1 TX / 3 RX reads as
    /// the Mac's 120 out, 40 in. Any other lane keeps its own point of view.
    @Test("Mac-side label on a dock's upstream lane")
    func macSideLabelOnDockUpstreamLane() {
        let upstream = makeLanePort(portNumber: 1, speed: .tb5, widthRaw: 0x8)
        let dock = makeSwitch(uid: 200, depth: 1, parent: 100, upstreamPortNumber: 1, ports: [upstream])
        #expect(ThunderboltLabels.linkLabel(for: upstream, on: dock) == "Up to 120 Gb/s out, 40 Gb/s in")

        let downstream = makeLanePort(portNumber: 3, speed: .tb5, widthRaw: 0x8)
        #expect(ThunderboltLabels.linkLabel(for: downstream, on: dock) == "Up to 40 Gb/s out, 120 Gb/s in")

        let hostLane = makeLanePort(portNumber: 1, socketID: "1", speed: .tb5, widthRaw: 0x4)
        let root = makeSwitch(uid: 100, depth: 0, ports: [hostLane])
        #expect(ThunderboltLabels.linkLabel(for: hostLane, on: root) == "Up to 120 Gb/s out, 40 Gb/s in")
    }

    // MARK: - deviceName

    @Test("Device name ASUS")
    func deviceNameAsus() {
        let sw = makeSwitch(uid: 1, vendor: "ASUS-Display", model: "PA32QCV")
        #expect(ThunderboltLabels.deviceName(for: sw) == "ASUS-Display PA32QCV")
    }

    @Test("Device name missing fields falls back")
    func deviceNameMissingFieldsFallsBack() {
        let sw = makeSwitch(uid: 1, vendor: "", model: "")
        #expect(ThunderboltLabels.deviceName(for: sw) == "Unknown device")
    }

    @Test("Device name does not double a brand the model already carries")
    func deviceNameDoesNotDoubleBrand() {
        // DROM reported vendor "Ugreen" and model "Ugreen Storage Device"
        // (issue #392). The old code produced "Ugreen Ugreen Storage Device".
        let sw = makeSwitch(uid: 1, vendor: "Ugreen", model: "Ugreen Storage Device")
        #expect(ThunderboltLabels.deviceName(for: sw) == "Ugreen Storage Device")
    }

    @Test("Device name collapses when vendor equals model")
    func deviceNameCollapsesWhenVendorEqualsModel() {
        let sw = makeSwitch(uid: 1, vendor: "Ugreen", model: "Ugreen")
        #expect(ThunderboltLabels.deviceName(for: sw) == "Ugreen")
    }

    @Test("Device name dedup is case-insensitive")
    func deviceNameDedupCaseInsensitive() {
        let sw = makeSwitch(uid: 1, vendor: "UGREEN", model: "ugreen storage device")
        #expect(ThunderboltLabels.deviceName(for: sw) == "ugreen storage device")
    }

    @Test("Device name keeps vendor when model only shares a prefix word")
    func deviceNameKeepsVendorOnPartialWordPrefix() {
        // "Cal" must not collapse "Calibre X": the match is whole-word only.
        let sw = makeSwitch(uid: 1, vendor: "Cal", model: "Calibre X")
        #expect(ThunderboltLabels.deviceName(for: sw) == "Cal Calibre X")
    }

    // MARK: - Topology socket-ID parsing

    @Test("Socket ID extracted from at-suffix")
    func socketIDExtractedFromAtSuffix() {
        #expect(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C@1") == "1")
        #expect(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C@3") == "3")
    }

    @Test("Socket ID nil when no at-suffix")
    func socketIDNilWhenNoAtSuffix() {
        #expect(ThunderboltTopology.socketID(fromServiceName: "Port-USB-C") == nil)
    }

    // MARK: - Topology chain walking

    @Test("Chain single hop")
    func chainSingleHop() {
        let host = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [
            makeLanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)
        ])
        let device = makeSwitch(uid: 200, depth: 1, parent: 100, vendor: "ASUS-Display", model: "PA32QCV")
        let chain = ThunderboltTopology.chain(from: host, in: [host, device])
        #expect(chain.count == 2)
        #expect(chain.first?.id == 100)
        #expect(chain.last?.id == 200)
    }

    @Test("Chain daisy two hops")
    func chainDaisyTwoHops() {
        let host = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [])
        let asus = makeSwitch(uid: 200, depth: 1, parent: 100, vendor: "ASUS-Display", model: "PA32QCV")
        let ts3 = makeSwitch(uid: 300, depth: 2, parent: 200, vendor: "CalDigit, Inc.", model: "TS3 Plus")
        let chain = ThunderboltTopology.chain(from: host, in: [host, asus, ts3])
        #expect(chain.map(\.id) == [100, 200, 300])
    }

    // MARK: - Topology tree walking

    @Test("Tree walk terminates on a forged parentSwitchUID cycle")
    func treeTerminatesOnForgedCycle() {
        // `chain(from:in:)` already carries a `seen` set. `tree(from:in:)`
        // didn't, so a parentSwitchUID graph describing a cycle (real
        // IOKit switch UIDs don't cycle, but a hand-built or corrupted
        // fixture can) would recurse forever, one call frame per lap.
        //
        // Graph: A's parent is the host root, B's parent is A, and a
        // second record sharing A's id claims its parent is B -- closing
        // B -> A -> B. If this regresses, the symptom is this test never
        // finishing.
        let host = makeSwitch(uid: 100)
        let a = makeSwitch(uid: 200, depth: 1, parent: 100)
        let b = makeSwitch(uid: 300, depth: 2, parent: 200)
        let aAgain = makeSwitch(uid: 200, depth: 3, parent: 300)   // same id as `a`, parent B
        let switches = [host, a, b, aAgain]

        let nodes = ThunderboltTopology.tree(from: host, in: switches)
        let flat = ThunderboltTopology.flatten(nodes)
        // Visits A once, then B; the duplicate A (id already seen) is
        // dropped instead of recursed into again.
        #expect(flat.map(\.sw.id) == [200, 300])
    }

    // MARK: - hostRoot lookup by Socket ID

    @Test("Host root matches by socket ID")
    func hostRootMatchesBySocketID() {
        let portA = makeLanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)
        let portB = makeLanePort(portNumber: 2, socketID: "2", speed: nil, widthRaw: 0)
        let root1 = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [portA])
        let root2 = makeSwitch(uid: 200, depth: 0, parent: nil, ports: [portB])
        let device = makeSwitch(uid: 999, depth: 1, parent: 100)
        let switches = [root1, root2, device]

        #expect(ThunderboltTopology.hostRoot(forSocketID: "1", in: switches)?.id == 100)
        #expect(ThunderboltTopology.hostRoot(forSocketID: "2", in: switches)?.id == 200)
        #expect(ThunderboltTopology.hostRoot(forSocketID: "3", in: switches) == nil)
    }

    // MARK: - activeDownstreamLanePort

    @Test("Active downstream lane port on host root")
    func activeDownstreamLanePortOnHostRoot() {
        let port1 = makeLanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)
        let root = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [port1])
        // A host root lane counts as downstream only with a child hanging
        // off it: the trained-lane read alone is true on an empty socket.
        let dock = makeSwitch(uid: 200, depth: 1, parent: 100, routeString: 1)
        #expect(
            ThunderboltTopology.activeDownstreamLanePort(root, in: [root, dock])?.portNumber == 1
        )
    }

    /// On a downstream switch, the upstream lane port (matching
    /// `upstreamPortNumber`) faces the host. The downstream port is the
    /// one that goes toward the next-hop device.
    @Test("Active downstream lane port skips upstream on deep switch")
    func activeDownstreamLanePortSkipsUpstreamOnDeepSwitch() {
        let upPort = makeLanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)
        let downPort = makeLanePort(portNumber: 4, socketID: nil, speed: .tb3, widthRaw: 0x1)
        let dock = makeSwitch(
            uid: 200, depth: 1, parent: 100,
            upstreamPortNumber: 1,
            ports: [upPort, downPort]
        )
        // Port 4 counts as downstream only because a switch hangs off it.
        // Its route byte for a depth-2 child is byte 1, so 4 << 8 | 1.
        let leaf = makeSwitch(uid: 300, depth: 2, parent: 200, routeString: 0x0401)
        #expect(
            ThunderboltTopology.activeDownstreamLanePort(dock, in: [dock, leaf])?.portNumber == 4
        )
    }

    // MARK: - isLinked

    /// Speed code 0x8 with width 1 is what an EMPTY socket reads on Type3 to
    /// Type5 silicon, corpus-wide. The raw register read cannot tell that
    /// from a live link; the absent child switch can.
    @Test("Idle host root lane is trained but not linked")
    func idleHostRootLaneIsTrainedButNotLinked() {
        let lane = makeLanePort(portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x1)
        let root = makeSwitch(
            uid: 100, depth: 0, parent: nil,
            className: "IOThunderboltSwitchType5",
            ports: [lane]
        )
        #expect(lane.hasTrainedLanes)
        #expect(ThunderboltTopology.isLinked(port: lane, on: root, in: [root]) == false)
    }

    /// A host root exposes one physical socket as a pair of lane adapters and
    /// only one of the pair carries the route byte, so the sibling named by
    /// `Dual-Link Port` has to count as linked too.
    @Test("Host root lane and its dual-link sibling are linked when a child hangs off it")
    func hostRootLaneAndDualLinkSiblingAreLinked() {
        let lane = makeLanePort(
            portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x1, dualLinkPort: 2
        )
        let sibling = makeLanePort(
            portNumber: 2, socketID: "1", speed: .tb3, widthRaw: 0x1, dualLinkPort: 1
        )
        let root = makeSwitch(
            uid: 100, depth: 0, parent: nil,
            className: "IOThunderboltSwitchType5",
            ports: [lane, sibling]
        )
        let dock = makeSwitch(uid: 200, depth: 1, parent: 100, routeString: 1)

        #expect(ThunderboltTopology.isLinked(port: lane, on: root, in: [root, dock]))
        #expect(ThunderboltTopology.isLinked(port: sibling, on: root, in: [root, dock]))
        // Same root, no child: both lanes of the pair read as idle.
        #expect(ThunderboltTopology.isLinked(port: lane, on: root, in: [root]) == false)
        #expect(ThunderboltTopology.isLinked(port: sibling, on: root, in: [root]) == false)
    }

    /// A dock's own upstream lane is linked because the dock is in the fabric
    /// at all, and needs no child of its own. Its spare sockets are not: they
    /// sit at the same trained-but-empty signature a Mac's empty socket does.
    @Test("Downstream switch: upstream lane is linked, a spare socket is not")
    func downstreamSwitchUpstreamLaneIsLinkedSpareSocketIsNot() {
        let upstream = makeLanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)
        let spare = makeLanePort(portNumber: 5, socketID: nil, speed: .tb3, widthRaw: 0x1)
        let dock = makeSwitch(
            uid: 200, depth: 1, parent: 100, routeString: 1,
            upstreamPortNumber: 1,
            ports: [upstream, spare]
        )
        #expect(ThunderboltTopology.isLinked(port: upstream, on: dock, in: [dock]))
        #expect(spare.hasTrainedLanes)
        #expect(ThunderboltTopology.isLinked(port: spare, on: dock, in: [dock]) == false)
    }

    /// The parent's downstream port for a child at depth d is route byte
    /// d-1, not byte 0: byte 0 is the first hop from the host root.
    @Test("A dock lane with a depth-2 child hanging off it is linked")
    func dockLaneWithChildIsLinked() {
        let upstream = makeLanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)
        let toLeaf = makeLanePort(portNumber: 5, socketID: nil, speed: .tb3, widthRaw: 0x1)
        let dock = makeSwitch(
            uid: 200, depth: 1, parent: 100, routeString: 1,
            upstreamPortNumber: 1,
            ports: [upstream, toLeaf]
        )
        let leaf = makeSwitch(uid: 300, depth: 2, parent: 200, routeString: 0x0501)
        #expect(ThunderboltTopology.isLinked(port: toLeaf, on: dock, in: [dock, leaf]))
        // Byte 0 of that route is 1, the FIRST hop from the host root. Reading
        // it as the dock's own port would have linked lane 1 by accident and
        // left lane 5 unlinked.
        #expect(ThunderboltTopology.childSwitch(below: dock, onPortNumber: 5, in: [dock, leaf]) != nil)
        #expect(ThunderboltTopology.childSwitch(below: dock, onPortNumber: 1, in: [dock, leaf]) == nil)
    }

    /// A hop table row means a tunnel is routed across this lane, and a
    /// tunnel needs something at the far end, so it is a partner signal in
    /// its own right when macOS published no switch record.
    @Test("Host root lane carrying a hop table is linked with no child switch")
    func hostRootLaneWithHopTableIsLinked() {
        let lane = makeLanePort(
            portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x1,
            hopTable: [
                HopTableEntry(
                    counter: 0, hopID: 8, dstHopID: 8, dstPort: 5,
                    pathUUID: "8A3F1C20-0000-0000-0000-000000000001"
                )
            ]
        )
        let root = makeSwitch(
            uid: 100, depth: 0, parent: nil,
            className: "IOThunderboltSwitchType5",
            ports: [lane]
        )
        #expect(ThunderboltTopology.isLinked(port: lane, on: root, in: [root]))
    }

    /// Only one lane of a dual-link pair carries the hop table, so a socket
    /// whose only evidence is a tunnel has to light both lanes or one half of
    /// a live socket publishes `linkActive: false` with no label while its
    /// sibling says true.
    ///
    /// This is `research/customer-probes/m2_macos26.4.1` socket 1 verbatim:
    /// port 1 carries one hop-table row and Link Bandwidth 400 (40 Gb/s),
    /// port 2 names port 1 as its dual-link sibling and carries neither. That
    /// machine publishes no depth-1 switch at all and its USB-C port `@1`
    /// carries CIO in TransportsActive, so the socket is demonstrably live.
    /// 7 lanes across 6 corpus folders sit in this shape.
    @Test("A hop table on one lane links its dual-link sibling too")
    func hopTableLinksDualLinkSibling() {
        let carrying = makeLanePort(
            portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2, dualLinkPort: 2,
            hopTable: [
                HopTableEntry(
                    counter: 0, hopID: 8, dstHopID: 8, dstPort: 5,
                    pathUUID: "8A3F1C20-0000-0000-0000-000000000001"
                )
            ]
        )
        let sibling = makeLanePort(
            portNumber: 2, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2, dualLinkPort: 1
        )
        let root = makeSwitch(
            uid: 100, depth: 0, parent: nil,
            className: "IOThunderboltSwitchType5",
            ports: [carrying, sibling]
        )
        #expect(ThunderboltTopology.isLinked(port: carrying, on: root, in: [root]))
        #expect(ThunderboltTopology.isLinked(port: sibling, on: root, in: [root]),
            "The sibling lane of a hop-table-evidenced socket is the same physical socket and must read as linked")
    }

    /// `Dual-Link Port` is a number the firmware publishes, not a promise
    /// that the port it names is in the snapshot. Lighting a lane from the
    /// number alone is the same false live link this gate exists to remove,
    /// so the sibling has to be there and has to be a lane adapter.
    @Test("A dual-link sibling missing from the snapshot links nothing")
    func absentDualLinkSiblingLinksNothing() {
        // A dock's spare socket. It names port 1, the dock's own upstream
        // port, as its sibling, but no port 1 is published on this switch.
        let spare = makeLanePort(
            portNumber: 5, socketID: nil, speed: .tb3, widthRaw: 0x1, dualLinkPort: 1
        )
        let dock = makeSwitch(
            uid: 200, depth: 1, parent: 100, routeString: 1,
            upstreamPortNumber: 1,
            ports: [spare]
        )
        #expect(spare.hasTrainedLanes)
        #expect(ThunderboltTopology.isLinked(port: spare, on: dock, in: [dock]) == false,
            "An empty socket must not be lit by an integer naming a port that is not there")

        // A non-lane adapter numbered 1 is not a sibling either: a socket is
        // a pair of lane adapters.
        let dpAdapter = IOThunderboltPort(
            portNumber: 1,
            socketID: nil,
            adapterType: .dpIn,
            currentSpeed: nil,
            currentWidth: nil,
            targetWidth: nil,
            rawTargetSpeed: nil,
            linkBandwidthRaw: nil
        )
        let dockWithAdapter = makeSwitch(
            uid: 200, depth: 1, parent: 100, routeString: 1,
            upstreamPortNumber: 1,
            ports: [spare, dpAdapter]
        )
        #expect(ThunderboltTopology.isLinked(port: spare, on: dockWithAdapter, in: [dockWithAdapter]) == false)
    }

    /// `parentSwitchUID` names the switch one hop up, and the route byte is
    /// read at the child's own depth. A stale or forged parent pointing a
    /// depth-2 switch straight at a host root has its byte read at the wrong
    /// depth, which lights whichever unrelated port happens to carry that
    /// number.
    @Test("A depth-2 switch does not attach to a root two hops above it")
    func depthTwoChildDoesNotAttachToRoot() {
        let laneFive = makeLanePort(portNumber: 5, socketID: "2", speed: .tb3, widthRaw: 0x1)
        let root = makeSwitch(
            uid: 100, depth: 0, parent: nil,
            className: "IOThunderboltSwitchType5",
            ports: [laneFive]
        )
        // Depth 2, so its byte is byte 1 = 0x05, which names the root's lane
        // 5 by coincidence. The leaf is two hops away and hangs off a dock,
        // not off the root.
        let leaf = makeSwitch(uid: 300, depth: 2, parent: 100, routeString: 0x0501)
        #expect(ThunderboltTopology.childSwitch(below: root, onPortNumber: 5, in: [root, leaf]) == nil,
            "A depth-2 switch is not a child of a depth-0 root")
        #expect(ThunderboltTopology.isLinked(port: laneFive, on: root, in: [root, leaf]) == false)
    }

    /// A route string holds one byte per hop and is 8 bytes wide, so a depth
    /// past 8 has no byte to read. Swift's shift operator quietly yields 0
    /// rather than trapping, and 0 then matches a port literally numbered 0.
    @Test("A depth past the route string's 8 bytes is rejected, not shifted")
    func depthBeyondRouteStringIsRejected() {
        let laneZero = makeLanePort(portNumber: 0, socketID: nil, speed: .tb3, widthRaw: 0x1)
        let parent = makeSwitch(
            uid: 200, depth: 8, parent: 100, routeString: 0x0102030405060708,
            upstreamPortNumber: 1, ports: [laneZero]
        )
        let child = makeSwitch(uid: 300, depth: 9, parent: 200, routeString: 0x0102030405060708)
        #expect(ThunderboltTopology.childSwitch(below: parent, onPortNumber: 0, in: [parent, child]) == nil,
            "A hop past the end of the route string names no port")
        #expect(ThunderboltTopology.isLinked(port: laneZero, on: parent, in: [parent, child]) == false)
    }

    // MARK: - Lane pick and port order

    /// `trainedDownstreamLanePort` and `activeDownstreamLanePort` both take
    /// `candidates.first`, so which lane of a pair answers is decided by the
    /// order the ports arrive in. That order is
    /// `IOThunderboltSwitchWatcher.portsInPortNumberOrder`, in another
    /// target, and this test is the consequence that depends on it.
    ///
    /// The shape is `research/customer-probes/m4max_macos26.5.2_f` socket 2:
    /// lane 1 trains symmetric dual at Gen 4 (80 Gb/s) with Link Bandwidth
    /// 800, lane 2 reads asymmetric TX (3 TX lanes, 120 Gb/s) with Link
    /// Bandwidth 0. Link Bandwidth corroborates lane 1, so 80 is the rate the
    /// link carried and 120 is not.
    @Test("The lane pick follows port number order, which is what keeps the rate at 80")
    func lanePickFollowsPortNumberOrder() {
        let laneOne = makeLanePort(portNumber: 1, socketID: "2", speed: .tb5, widthRaw: 0x2)
        let laneTwo = makeLanePort(portNumber: 2, socketID: "2", speed: .tb5, widthRaw: 0x4)
        #expect(laneOne.activeGbps == 80)
        #expect(laneTwo.activeGbps == 120)

        let ascending = makeSwitch(
            uid: 100, depth: 0, parent: nil,
            className: "IOThunderboltSwitchType7",
            ports: [laneOne, laneTwo]
        )
        #expect(ThunderboltTopology.trainedDownstreamLanePort(ascending)?.activeGbps == 80)

        // The same two ports in registry order, which is what the probe dump
        // actually prints on 21 corpus machines. Characterisation, not a
        // wanted behaviour: without the watcher's sort the app publishes
        // 120 Gb/s on an 80 Gb/s link.
        let registryOrder = makeSwitch(
            uid: 100, depth: 0, parent: nil,
            className: "IOThunderboltSwitchType7",
            ports: [laneTwo, laneOne]
        )
        #expect(ThunderboltTopology.trainedDownstreamLanePort(registryOrder)?.activeGbps == 120)
    }

    @Test("A lane with no trained width is never linked")
    func untrainedLaneIsNeverLinked() {
        let idle = makeLanePort(portNumber: 1, socketID: "1", speed: nil, widthRaw: 0x0)
        let root = makeSwitch(uid: 100, depth: 0, parent: nil, ports: [idle])
        let dock = makeSwitch(uid: 200, depth: 1, parent: 100, routeString: 1, ports: [idle])
        #expect(idle.hasTrainedLanes == false)
        #expect(ThunderboltTopology.isLinked(port: idle, on: root, in: [root, dock]) == false)
        #expect(ThunderboltTopology.isLinked(port: idle, on: dock, in: [root, dock]) == false)
    }
}

// MARK: - Test helpers

private func makeLanePort(
    portNumber: Int = 1,
    socketID: String? = nil,
    speed: LinkGeneration?,
    widthRaw: UInt8,
    dualLinkPort: Int? = nil,
    hopTable: [HopTableEntry] = []
) -> IOThunderboltPort {
    IOThunderboltPort(
        portNumber: portNumber,
        socketID: socketID,
        adapterType: .lane,
        currentSpeed: speed,
        currentWidth: LinkWidth(rawValue: widthRaw),
        targetWidth: nil,
        rawTargetSpeed: nil,
        linkBandwidthRaw: nil,
        dualLinkPort: dualLinkPort,
        hopTable: hopTable
    )
}

private func makeSwitch(
    uid: Int64,
    depth: Int = 0,
    parent: Int64? = nil,
    routeString: Int64 = 0,
    upstreamPortNumber: Int = 0,
    className: String = "IOIOThunderboltSwitchType7",
    vendor: String = "Apple Inc.",
    model: String = "iOS",
    ports: [IOThunderboltPort] = []
) -> IOThunderboltSwitch {
    IOThunderboltSwitch(
        id: uid,
        className: className,
        vendorID: 1452,
        vendorName: vendor,
        modelName: model,
        routerID: 0,
        depth: depth,
        routeString: routeString,
        upstreamPortNumber: upstreamPortNumber,
        maxPortNumber: 8,
        supportedSpeed: SupportedSpeedMask(rawValue: 12),
        ports: ports,
        parentSwitchUID: parent
    )
}
