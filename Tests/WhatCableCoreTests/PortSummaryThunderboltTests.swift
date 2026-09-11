import Testing
@testable import WhatCableCore

/// Phase 3 integration: PortSummary should pull TB fabric data through and
/// emit specific link-state bullets when a port has a matching switch graph.
/// Anchored against Joe's M2 Pro + ASUS PA32QCV (USB4) + CalDigit TS3 Plus
/// daisy-chain from issue #52.
@Suite("Port Summary Thunderbolt")
struct PortSummaryThunderboltTests {

    // MARK: - Fixtures

    private func tbPort(socket: String) -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-USB-C@\(socket)",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@\(socket)",
            portTypeDescription: "USB-C",
            portNumber: Int(socket),
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            transportsActive: ["CIO"],
            transportsProvisioned: ["CC"],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: [:]
        )
    }

    private func lanePort(
        portNumber: Int,
        socketID: String?,
        speed: LinkGeneration?,
        widthRaw: UInt8
    ) -> IOThunderboltPort {
        IOThunderboltPort(
            portNumber: portNumber,
            socketID: socketID,
            adapterType: .lane,
            currentSpeed: speed,
            currentWidth: LinkWidth(rawValue: widthRaw),
            targetWidth: nil,
            rawTargetSpeed: nil,
            linkBandwidthRaw: nil
        )
    }

    private func sw(
        uid: Int64,
        depth: Int,
        parent: Int64?,
        routeString: Int64 = 0,
        upstreamPort: Int = 0,
        vendor: String,
        model: String,
        ports: [IOThunderboltPort]
    ) -> IOThunderboltSwitch {
        IOThunderboltSwitch(
            id: uid,
            className: "IOIOThunderboltSwitchType5",
            vendorID: 1452,
            vendorName: vendor,
            modelName: model,
            routerID: 0,
            depth: depth,
            routeString: routeString,
            upstreamPortNumber: upstreamPort,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: ports,
            parentSwitchUID: parent
        )
    }

    // MARK: - Single-hop (host + one device)

    @Test("Host USB4 link produces specific bullet")
    func hostUsb4LinkProducesSpecificBullet() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let device = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "ASUS-Display", model: "PA32QCV",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )

        let summary = PortSummary(
            port: port,
            thunderboltSwitches: [host, device]
        )

        #expect(
            summary.bullets.contains("Linked at up to 20 Gb/s × 2"),
            "expected USB4 link label, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains("Connected to ASUS-Display PA32QCV"),
            "expected single-hop device label, got: \(summary.bullets)"
        )
        // USB4 / TB4 host link = 40 Gbps published headline → green tb40 badge.
        #expect(summary.linkSpeed?.tier == .tb40)
        #expect(summary.linkSpeed?.badge == "40G")
    }

    @Test("TB3 link produces TB3 bullet")
    func tb3LinkProducesTb3Bullet() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x2)]
        )
        // The device is what makes the host lane a link: a host root reports
        // trained lanes on an empty socket too.
        let device = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "CalDigit, Inc.", model: "TS3 Plus",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .tb3, widthRaw: 0x2)]
        )

        let summary = PortSummary(port: port, thunderboltSwitches: [host, device])
        #expect(summary.bullets.contains("Linked at up to 10 Gb/s × 2"))
        // Speed code 0x8 is 10 Gb/s per lane, so two lanes carry 20 Gbps,
        // corpus-confirmed against Link Bandwidth. The badge follows the
        // active rate and so agrees with the bullet above; a real 40 Gbps
        // TB3 link trains at code 0x4 and is covered by the USB4/TB4 test.
        // There is no Thunderbolt tier below 40 Gbps, so the resolver
        // reuses the 20G tier (see LinkSpeed resolution in PortSummary).
        #expect(summary.linkSpeed?.tier == .usb20g)
        #expect(summary.linkSpeed?.badge == "20G")
    }

    // MARK: - TB1/TB2-era device generation cap (issue #515)

    @Test("TB1 device badge caps below the shared 40 Gbps tier, matching the diagnostic panel")
    func tb1DeviceBadgeCapsBelowSharedTier() {
        // Before this fix, the badge resolver read the host link's raw
        // `Current Link Speed` code directly and always mapped code 0x8 to
        // the 40 Gbps tier, independent of `DataLinkDiagnostic`'s cap. A
        // LaCie Rugged THB (TB1, Device ID 0x1549) would badge "40G" on
        // the port card while the Pro data-speed panel correctly said
        // 10 Gbps: the two disagreed. The badge now shares
        // `DataLinkDiagnostic.activeTBGbps`, so it must read the same
        // capped figure.
        let port = tbPort(socket: "1")
        let host = IOThunderboltSwitch(
            id: 100,
            className: "IOIOThunderboltSwitchType5",
            vendorID: 1452,
            vendorName: "Apple Inc.",
            modelName: "Mac",
            routerID: 0,
            depth: 0,
            routeString: 0,
            upstreamPortNumber: 0,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x1)],
            parentSwitchUID: nil
        )
        let device = IOThunderboltSwitch(
            id: 200,
            className: "IOThunderboltSwitchType2",
            vendorID: 0x8086,
            vendorName: "Intel",
            modelName: "LaCie Rugged THB",
            routerID: 1,
            depth: 1,
            routeString: 1,
            upstreamPortNumber: 3,
            maxPortNumber: 4,
            supportedSpeed: SupportedSpeedMask(rawValue: 0x8),
            ports: [],
            parentSwitchUID: host.id,
            thunderboltVersion: 1,
            deviceID: 0x1549
        )
        let summary = PortSummary(port: port, thunderboltSwitches: [host, device])
        #expect(summary.linkSpeed?.tier != .tb40,
            "A TB1 device must not badge into the shared 40 Gbps tier. Got tier: \(String(describing: summary.linkSpeed?.tier))")
        #expect(summary.linkSpeed?.tier == .usb10g,
            "No dedicated sub-40 Gbps Thunderbolt tier exists; the badge reuses the existing 10G tier. Got: \(String(describing: summary.linkSpeed?.tier))")
        #expect(summary.linkSpeed?.badge == "10G")
    }

    // MARK: - Daisy-chain step-down (the headline UX)

    @Test("Daisy chain step-down is surfaced")
    func daisyChainStepDownIsSurfaced() {
        // Joe's topology: USB4 to ASUS, TS3 Plus daisy-chained off the
        // ASUS at TB3 single-lane.
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let asus = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "ASUS-Display", model: "PA32QCV",
            ports: [
                lanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2),
                lanePort(portNumber: 4, socketID: nil, speed: .tb3, widthRaw: 0x1)
            ]
        )
        let ts3 = sw(
            uid: 300, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "CalDigit, Inc.", model: "TS3 Plus",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .tb3, widthRaw: 0x1)]
        )

        let summary = PortSummary(
            port: port,
            thunderboltSwitches: [host, asus, ts3]
        )

        #expect(
            summary.bullets.contains("Linked at up to 20 Gb/s × 2"),
            "host link bullet missing; got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains("Connected via 2 hops: ASUS-Display PA32QCV → CalDigit, Inc. TS3 Plus"),
            "daisy-chain device list missing; got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Last leg drops from up to 20 Gb/s × 2 to up to 10 Gb/s × 1") },
            "step-down bullet missing; got: \(summary.bullets)"
        )
    }

    // MARK: - DAR-27: step-down label must compare total throughput, not label strings

    /// 20 Gb/s x 1 vs 20 Gb/s x 2 are different label strings but the same
    /// per-lane speed. The last leg here is wider (more lanes) than the host,
    /// so total throughput is higher: this must NOT be reported as a drop.
    @Test("Equal per-lane speed different lane count does not emit step-down")
    func equalPerLaneSpeedDifferentLaneCountNoStepDown() {
        // Host link: USB4, single-lane (20 Gb/s x 1, 20 Gbps total)
        // Last leg:  USB4, dual-lane  (20 Gb/s x 2, 40 Gbps total)
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x1)] // single-lane
        )
        let first = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "Dock Co.", model: "Middle Dock",
            ports: [
                lanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x1),
                lanePort(portNumber: 4, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2) // downstream: dual-lane
            ]
        )
        let leaf = sw(
            uid: 300, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "Leaf Co.", model: "USB4 SSD",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )

        let summary = PortSummary(
            port: port,
            thunderboltSwitches: [host, first, leaf]
        )

        #expect(
            summary.bullets.contains { $0.contains("Last leg drops") } == false,
            "equal per-lane speed, wider last leg must not emit step-down; got: \(summary.bullets)"
        )
    }

    /// The last leg is genuinely slower: TB3 single-lane (10 Gbps) vs USB4
    /// dual-lane host (40 Gbps). This IS a real drop and must be reported.
    @Test("Genuinely slower last leg emits step-down")
    func genuinelySlowerLastLegEmitsStepDown() {
        // Host: USB4 dual-lane (20 x 2 = 40 Gbps total)
        // Last leg: TB3 single-lane (10 x 1 = 10 Gbps total)
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let middle = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "Dock Co.", model: "USB4 Dock",
            ports: [
                lanePort(portNumber: 1, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2),
                lanePort(portNumber: 4, socketID: nil, speed: .tb3, widthRaw: 0x1) // downstream: TB3 single
            ]
        )
        let leaf = sw(
            uid: 300, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "Old Co.", model: "TB3 Drive",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .tb3, widthRaw: 0x1)]
        )

        let summary = PortSummary(
            port: port,
            thunderboltSwitches: [host, middle, leaf]
        )

        #expect(
            summary.bullets.contains { $0.contains("Last leg drops from up to 20 Gb/s × 2 to up to 10 Gb/s × 1") },
            "genuinely slower last leg must emit step-down; got: \(summary.bullets)"
        )
    }

    /// Last leg is faster than the host link (e.g. host TB3, last leg TB5).
    /// "Faster last leg" is a weird configuration but must never produce a drop.
    @Test("Faster last leg does not emit step-down")
    func fasterLastLegDoesNotEmitStepDown() {
        // Host: TB3 single-lane (10 x 1 = 10 Gbps)
        // Last leg: TB5 dual-lane (40 x 2 = 80 Gbps)
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x1)]
        )
        let middle = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "Dock Co.", model: "Dock",
            ports: [
                lanePort(portNumber: 1, socketID: nil, speed: .tb3, widthRaw: 0x1),
                lanePort(portNumber: 4, socketID: nil, speed: .tb5, widthRaw: 0x2)
            ]
        )
        let leaf = sw(
            uid: 300, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "Fast Co.", model: "TB5 SSD",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .tb5, widthRaw: 0x2)]
        )

        let summary = PortSummary(
            port: port,
            thunderboltSwitches: [host, middle, leaf]
        )

        #expect(
            summary.bullets.contains { $0.contains("Last leg drops") } == false,
            "faster last leg must not emit step-down; got: \(summary.bullets)"
        )
    }

    // MARK: - Single-hop must NOT trigger step-down

    /// Regression: in Steve's TB3 sample, the host port reports
    /// `Current Link Width = 2` while the Samsung's upstream port reports
    /// `Current Link Width = 1` for the same physical cable. That's just
    /// the controller-side view aggregating lanes the device-side view
    /// doesn't; it's not a real step-down. Step-down only fires for
    /// daisy-chains with two or more downstream switches.
    @Test("Single hop does not emit step-down")
    func singleHopDoesNotEmitStepDown() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .tb3, widthRaw: 0x2)]
        )
        // Samsung-style single device: upstream port reports the same
        // link from the device side with a different width value.
        let samsung = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "SAMSUNG ELECTRONICS CO.,LTD", model: "C34J79x",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .tb3, widthRaw: 0x1)]
        )

        let summary = PortSummary(port: port, thunderboltSwitches: [host, samsung])
        #expect(
            summary.bullets.contains { $0.contains("Last leg drops") } == false,
            "single-hop must not emit step-down warning; got: \(summary.bullets)"
        )
        // Sanity: the single-hop bullets we DO want should still be there.
        #expect(
            summary.bullets.contains("Connected to SAMSUNG ELECTRONICS CO.,LTD C34J79x"),
            "device label still required"
        )
    }

    // MARK: - Branching tree (issue #280)

    /// tacks's topology (#280): a CalDigit TB4 Pro Dock with TWO Thunderbolt
    /// devices hanging off it: a LaCie dock (which itself feeds a Studio
    /// Display) and an OWC Express 1M2. The old first-child-only chain showed
    /// just the LaCie branch and silently dropped the OWC. Build it once here.
    private func branchingSwitches() -> [IOThunderboltSwitch] {
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let caldigit = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "CalDigit, Inc.", model: "Thunderbolt 4 Pro Dock",
            ports: [lanePort(portNumber: 2, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let lacie = sw(
            uid: 300, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "LaCie", model: "1big Dock v2",
            ports: [lanePort(portNumber: 2, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let studio = sw(
            uid: 400, depth: 3, parent: 300, upstreamPort: 1,
            vendor: "Apple Inc.", model: "Studio Display",
            ports: [lanePort(portNumber: 2, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )
        // Second branch off the CalDigit dock. Higher uid than the LaCie so it
        // sorts last; the bug was that it never appeared at all.
        let owc = sw(
            uid: 500, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "OWC", model: "Express 1M2",
            ports: [lanePort(portNumber: 2, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )
        return [host, caldigit, lacie, studio, owc]
    }

    @Test("Branching chain names every Thunderbolt device, not just one branch")
    func branchingChainNamesEveryDevice() {
        let summary = PortSummary(
            port: tbPort(socket: "1"),
            thunderboltSwitches: branchingSwitches()
        )

        // The flat named list must contain all four devices, including the
        // OWC that the linear chain used to drop.
        #expect(
            summary.bullets.contains(
                "Connected to 4 Thunderbolt devices: CalDigit, Inc. Thunderbolt 4 Pro Dock, LaCie 1big Dock v2, Apple Inc. Studio Display, OWC Express 1M2"
            ),
            "branching device list missing or wrong; got: \(summary.bullets)"
        )
        // It must NOT fall back to the misleading single-path phrasing.
        #expect(
            summary.bullets.contains { $0.hasPrefix("Connected via") } == false,
            "branching tree must not use the single-path 'Connected via N hops' bullet; got: \(summary.bullets)"
        )
    }

    @Test("Tree walk returns all branches; chain returns only the first")
    func treeWalkReturnsAllBranches() {
        let switches = branchingSwitches()
        let root = ThunderboltTopology.hostRoot(forSocketID: "1", in: switches)
        #expect(root != nil)
        guard let root else { return }

        // chain follows first-child only: host + CalDigit + LaCie + Studio.
        let chain = ThunderboltTopology.chain(from: root, in: switches)
        #expect(chain.count == 4)
        #expect(chain.contains { $0.id == 500 } == false, "chain should drop the OWC branch")

        // tree follows every branch: CalDigit (d0) -> LaCie (d1) -> Studio (d2),
        // plus OWC (d1). Flattened depth-first by uid order.
        let flat = ThunderboltTopology.flatten(ThunderboltTopology.tree(from: root, in: switches))
        #expect(flat.count == 4, "tree should reach all four downstream devices")
        #expect(flat.map(\.sw.id) == [200, 300, 400, 500], "unexpected DFS order: \(flat.map(\.sw.id))")
        #expect(flat.map(\.depth) == [0, 1, 2, 1], "unexpected depths: \(flat.map(\.depth))")
    }

    @Test("Branching tree does not emit a spurious step-down bullet")
    func branchingTreeDoesNotEmitStepDown() {
        // A dock with two leaf devices: a slower TB3 branch (lower uid, so the
        // first-child chain follows it) and a faster USB4 branch. The old code
        // compared the host link to the first-child path's last leg and would
        // wrongly fire "Last leg drops..." next to the flat device list. With
        // a real tree, "last leg" is arbitrary, so step-down must be skipped.
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let dock = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "CalDigit, Inc.", model: "TS4",
            ports: [lanePort(portNumber: 2, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let slowLeaf = sw(
            uid: 300, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "Old", model: "TB3 Disk",
            ports: [lanePort(portNumber: 2, socketID: nil, speed: .tb3, widthRaw: 0x1)]
        )
        let fastLeaf = sw(
            uid: 400, depth: 2, parent: 200, upstreamPort: 1,
            vendor: "New", model: "USB4 Disk",
            ports: [lanePort(portNumber: 2, socketID: nil, speed: .usb4Tb4, widthRaw: 0x2)]
        )

        let summary = PortSummary(
            port: tbPort(socket: "1"),
            thunderboltSwitches: [host, dock, slowLeaf, fastLeaf]
        )

        #expect(
            summary.bullets.contains { $0.hasPrefix("Connected to 3 Thunderbolt devices:") },
            "expected flat device list; got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Last leg drops") } == false,
            "branching tree must not emit a step-down bullet; got: \(summary.bullets)"
        )
    }

    // MARK: - Fallback when no matching switch is found

    @Test("Falls back to generic label when no matching switch")
    func fallsBackToGenericLabelWhenNoMatchingSwitch() {
        let port = tbPort(socket: "1")
        // Switch list is empty: PortSummary should fall back to the
        // pre-Phase-3 generic line so we don't regress on machines without
        // the watcher data.
        let summary = PortSummary(port: port, thunderboltSwitches: [])
        #expect(
            summary.bullets.contains("Thunderbolt / USB4 link active"),
            "expected fallback bullet when no switch data; got: \(summary.bullets)"
        )
        // Without a matched switch graph we can't read the rate, so leave the
        // badge off rather than guess.
        #expect(summary.linkSpeed == nil)
    }

    // MARK: - TB5 confirmed (issue #52: M5 Pro + UGreen JHL9580 dock)

    @Test("TB5 link renders with per-lane label")
    func tb5LinkRendersWithPerLaneLabel() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .tb5, widthRaw: 0x2)]
        )
        // See the TB3 test: the attached device is what makes it a link.
        let dock = sw(
            uid: 200, depth: 1, parent: 100, routeString: 1, upstreamPort: 1,
            vendor: "UGreen", model: "JHL9580",
            ports: [lanePort(portNumber: 1, socketID: nil, speed: .tb5, widthRaw: 0x2)]
        )
        let summary = PortSummary(port: port, thunderboltSwitches: [host, dock])
        #expect(
            summary.bullets.contains { $0.contains("40 Gb/s") },
            "TB5 should report per-lane 40 Gb/s; got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Unknown generation") } == false,
            "TB5 should no longer be hedged; got: \(summary.bullets)"
        )
        // TB5 published headline = 80 Gbps → green tb80 badge.
        #expect(summary.linkSpeed?.tier == .tb80)
        #expect(summary.linkSpeed?.badge == "80G")
    }

    // MARK: - Passive e-marker + active TB link (issue #111)

    /// TB4 cables from CalDigit/Cable Matters report as passive in USB-PD
    /// because their active components condition the Thunderbolt signal path,
    /// not the USB path. When the TB link is live and the e-marker says
    /// passive, PortSummary should add a clarifying note.
    private func passiveCableIdentity() -> USBPDSOP {
        // ID Header VDO[0]: ufpProductType = 3 (passiveCable), VID = 0x2B1D
        let idHeader: UInt32 = (3 << 27) | 0x2B1D
        // Cable VDO[3]: USB 3.2 Gen 2 (speed=2), 5A current (bits 5..6 = 2),
        // latency = 1 (bits 13..16)
        let cableVDO: UInt32 = 0b010 | (2 << 5) | (1 << 13)
        return USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 3
        )
    }

    // Bug C. This used to assert an explanation the app printed on EVERY
    // passive cable sitting on a live Thunderbolt link: "the active
    // electronics handle Thunderbolt, not USB". A short passive TB5 cable
    // has no active electronics, so the sentence was simply false about it.
    // The e-marker group now states what the e-marker said and nothing more.
    @Test("Passive e-marker with active TB link states passive, no invented explanation")
    func passiveEmarkerWithActiveTBLinkShowsClarification() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let cable = passiveCableIdentity()

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [host]
        )

        #expect(
            summary.group(.emarker)?.lines.contains { $0.contains("Passive (no signal-conditioning electronics)") } == true,
            "expected a plain passive line in the e-marker group; got: \(summary.groups)"
        )
        #expect(
            summary.bullets.contains { $0.contains("active electronics handle Thunderbolt") } == false,
            "must not tell a passive cable it contains active electronics; got: \(summary.bullets)"
        )
    }

    @Test("Passive e-marker without TB link does not show clarification")
    func passiveEmarkerWithoutTBLinkDoesNotShowClarification() {
        let port = USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: true,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3"],
            transportsActive: ["USB3"],
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: [:]
        )
        let cable = passiveCableIdentity()

        let summary = PortSummary(port: port, identities: [cable])

        #expect(
            summary.bullets.contains { $0.contains("E-marker reports passive") } == false,
            "passive cable on non-TB port should not show TB clarification; got: \(summary.bullets)"
        )
    }

    // MARK: - CIO cable capability (issue #111)

    /// When CIO data is present with a known speed code, PortSummary should
    /// replace the generic passive/TB fallback with a "Controller confirms"
    /// bullet plus an explanation of why the e-marker says passive.
    @Test("CIO confirms TB cable replaces passive bullet")
    func cioConfirmsTBCableReplacesPassiveBullet() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let cable = passiveCableIdentity()
        let cio = CIOCableCapability(
            id: 1, portKey: "1",
            cableGeneration: 2, negotiatedLinkSpeed: 3, generation: 3,
            asymmetricModeSupported: false, legacyAdapter: false,
            linkTrainingMode: nil
        )

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [host],
            cioCapability: cio
        )

        // The controller's reading is a measurement, so it belongs with the
        // Mac's other measurements, not among the e-marker's claims.
        #expect(
            summary.group(.measured)?.lines.contains { $0.contains("Controller confirms Thunderbolt cable") && $0.contains("40 Gbps") } == true,
            "expected the CIO confirmation in the measured group; got: \(summary.groups)"
        )
        #expect(
            summary.group(.emarker)?.lines.contains { $0.contains("Passive (no signal-conditioning electronics)") } == true,
            "expected a plain passive line in the e-marker group; got: \(summary.groups)"
        )
        #expect(
            summary.bullets.contains { $0.contains("active electronics handle Thunderbolt") } == false,
            "the false active-electronics explanation must be gone; got: \(summary.bullets)"
        )
    }

    /// When CIO data is present but the speed code is unrecognised, fall back
    /// to the existing passive/TB clarification (don't leak raw codes).
    @Test("CIO with unknown speed code falls back to passive bullet")
    func cioWithUnknownSpeedCodeFallsBackToPassiveBullet() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let cable = passiveCableIdentity()
        // Speed code 99 is not in our confirmed mapping.
        let cio = CIOCableCapability(
            id: 1, portKey: "1",
            cableGeneration: nil, negotiatedLinkSpeed: 99, generation: nil,
            asymmetricModeSupported: nil, legacyAdapter: nil,
            linkTrainingMode: nil
        )

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [host],
            cioCapability: cio
        )

        #expect(
            summary.group(.emarker)?.lines.contains { $0.contains("Passive (no signal-conditioning electronics)") } == true,
            "the e-marker's own claim still stands with an unreadable CIO code; got: \(summary.groups)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Controller confirms") } == false,
            "should not show CIO confirmation for unknown speed code; got: \(summary.bullets)"
        )
    }

    /// When CIO data exists but has no cableSpeed at all, fall back.
    @Test("CIO with nil speed falls back to passive bullet")
    func cioWithNilSpeedFallsBackToPassiveBullet() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let cable = passiveCableIdentity()
        let cio = CIOCableCapability(
            id: 1, portKey: "1",
            cableGeneration: nil, negotiatedLinkSpeed: nil, generation: nil,
            asymmetricModeSupported: nil, legacyAdapter: nil,
            linkTrainingMode: nil
        )

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [host],
            cioCapability: cio
        )

        #expect(
            summary.group(.emarker)?.lines.contains { $0.contains("Passive (no signal-conditioning electronics)") } == true,
            "the e-marker's own claim still stands with no CIO speed; got: \(summary.groups)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Controller confirms") } == false,
            "nothing to confirm without a CIO speed; got: \(summary.bullets)"
        )
    }

    /// Same shape as `passiveCableIdentity()` but claiming USB4 Gen 4
    /// (80 Gbps) instead of USB 3.2 Gen 2 (10 Gbps): the #393 e-marker
    /// claim tier.
    private func passiveCableIdentityClaiming80() -> USBPDSOP {
        let idHeader: UInt32 = (3 << 27) | 0x2B1D
        // Cable VDO[3]: USB4 Gen 4 (speed=4), 5A current, latency = 1.
        let cableVDO: UInt32 = 0b100 | (2 << 5) | (1 << 13)
        return USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 3
        )
    }

    /// Same shape as `passiveCableIdentity()` but claiming USB4 Gen 3
    /// (40 Gbps): a Thunderbolt 4 class passive cable.
    private func passiveCableIdentityClaiming40() -> USBPDSOP {
        let idHeader: UInt32 = (3 << 27) | 0x2B1D
        // Cable VDO[3]: USB4 Gen 3 (speed=3), 5A current, latency = 1.
        let cableVDO: UInt32 = 0b011 | (2 << 5) | (1 << 13)
        return USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 3
        )
    }

    /// CIO-semantics change: the CIO `CableSpeed` code is the controller's
    /// claim about the cable and peer pair, not the trained lane. On 13 of 70
    /// corpus ports with `CableSpeed=4` the endpoint cannot run 80 Gbps at
    /// all, so the old bullet told a 40 Gbps dock's owner the controller had
    /// confirmed 80. The bullet may confirm only what the lane carried.
    @Test("CIO above the trained lane prints the lane rate, not the CIO claim")
    func cioAboveLanePrintsLinkActiveAtLaneRate() {
        let port = tbPort(socket: "1")
        // Host root lane trained at Gen 3 x2: 20 Gbps per lane, two lanes,
        // 40 Gbps (the same shape the confirm fixture above uses).
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let cable = passiveCableIdentityClaiming40()
        let cio = CIOCableCapability(
            id: 1, portKey: "1",
            cableGeneration: 3, negotiatedLinkSpeed: 4, generation: 4,
            asymmetricModeSupported: true, legacyAdapter: false,
            linkTrainingMode: nil
        )

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [host],
            cioCapability: cio
        )

        #expect(
            summary.group(.measured)?.lines.contains { $0.contains("Thunderbolt link active at 40 Gbps") } == true,
            "expected the lane rate in the measured group; got: \(summary.groups)"
        )
        #expect(
            summary.bullets.contains { $0.contains("80 Gbps capable") } == false,
            "nobody has seen this cable carry 80 Gbps; got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Controller confirms") } == false,
            "the controller's claim sits above the lane, so nothing is confirmed; got: \(summary.bullets)"
        )
    }

    /// Without a trained lane figure the CIO code alone proves nothing
    /// about what the cable carried, so no controller bullet at all.
    @Test("No trained lane figure: no controller bullet")
    func noLaneFigureNoControllerBullet() {
        let port = tbPort(socket: "1")
        let cable = passiveCableIdentity()
        let cio = CIOCableCapability(
            id: 1, portKey: "1",
            cableGeneration: 2, negotiatedLinkSpeed: 3, generation: 3,
            asymmetricModeSupported: false, legacyAdapter: false,
            linkTrainingMode: nil
        )

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [],
            cioCapability: cio
        )

        #expect(
            summary.group(.measured)?.lines.contains { $0.contains("Controller confirms") } != true,
            "no lane figure, so the CIO code confirms nothing; got: \(summary.groups)"
        )
        #expect(
            summary.group(.measured)?.lines.contains { $0.contains("Thunderbolt link active") } != true,
            "no lane figure, so there is no link rate to print; got: \(summary.groups)"
        )
        #expect(
            summary.group(.emarker)?.lines.contains { $0.contains("Passive (no signal-conditioning electronics)") } == true,
            "the e-marker's own passive claim still stands; got: \(summary.groups)"
        )
    }

    /// E-marker one tier above what the controller and lane agree on: the
    /// link line names the lane rate and the cable's ceiling stays on the
    /// e-marker group's "Cable speed" line. Same direction as the #393
    /// fixture below, asserted against the lane figure explicitly.
    @Test("E-marker above the confirmed tier prints the link line at the lane rate")
    func emarkerAboveConfirmedTierPrintsLinkLine() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let cable = passiveCableIdentityClaiming80()
        let cio = CIOCableCapability(
            id: 1, portKey: "1",
            cableGeneration: 2, negotiatedLinkSpeed: 3, generation: 3,
            asymmetricModeSupported: false, legacyAdapter: false,
            linkTrainingMode: nil
        )

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [host],
            cioCapability: cio
        )

        #expect(
            summary.group(.measured)?.lines.contains { $0 == "Thunderbolt link active at 40 Gbps" } == true,
            "expected the lane rate on the link line; got: \(summary.groups)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Controller confirms") } == false,
            "a Gen 4 e-marker is not confirmed by a 40 Gbps lane; got: \(summary.bullets)"
        )
    }

    /// Issue #393: an e-marker claiming a higher tier than CIO measured
    /// must not be described as a confirmed cable capacity.
    @Test("E-marker claims a higher tier than CIO measured: link line, not a cable confirm (issue #393)")
    func emarkerClaimsHigherTierThanCIOShowsLinkLine() {
        // The exact #393 shape: e-marker claims USB4 Gen 4 (80 Gbps), but
        // the controller only measured CableSpeed=3 (40 Gbps, because
        // both endpoints capped there). Calling this a "Controller
        // confirms ... (40 Gbps capable)" bullet would understate a
        // genuine 80 Gbps cable. The bullet must describe the LINK
        // (40 Gbps), not the cable.
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        let cable = passiveCableIdentityClaiming80()
        let cio = CIOCableCapability(
            id: 1, portKey: "1",
            cableGeneration: 2, negotiatedLinkSpeed: 3, generation: 3,
            asymmetricModeSupported: true, legacyAdapter: false,
            linkTrainingMode: 2
        )

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [host],
            cioCapability: cio
        )

        #expect(
            summary.group(.measured)?.lines.contains { $0.contains("Thunderbolt link active at 40 Gbps") } == true,
            "expected the link-rate line in the measured group, not a cable-capacity confirm; got: \(summary.groups)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Controller confirms Thunderbolt cable") } == false,
            "must not describe a 40 Gbps floor as if it were the cable's confirmed capacity; got: \(summary.bullets)"
        )
        #expect(
            summary.group(.emarker)?.lines.contains { $0.contains("Passive (no signal-conditioning electronics)") } == true,
            "the e-marker's own passive claim still stands; got: \(summary.groups)"
        )
    }

    @Test("Active cable with TB link does not show passive note")
    func activeCableWithTBLinkDoesNotShowPassiveNote() {
        let port = tbPort(socket: "1")
        let host = sw(
            uid: 100, depth: 0, parent: nil,
            vendor: "Apple Inc.", model: "iOS",
            ports: [lanePort(portNumber: 1, socketID: "1", speed: .usb4Tb4, widthRaw: 0x2)]
        )
        // ID Header VDO[0]: ufpProductType = 4 (activeCable)
        let idHeader: UInt32 = (4 << 27) | 0x05AC
        let cableVDO: UInt32 = 0b011 | (2 << 5) | (1 << 13)
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 3
        )

        let summary = PortSummary(
            port: port,
            identities: [cable],
            thunderboltSwitches: [host]
        )

        #expect(
            summary.bullets.contains { $0.contains("E-marker reports passive") } == false,
            "active cable should not show passive note; got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains { $0.contains("Active cable") },
            "active cable should show active label; got: \(summary.bullets)"
        )
    }
}
