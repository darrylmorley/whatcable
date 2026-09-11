import Foundation
import Testing
import WhatCableCore

@Suite("Text Formatter")
struct TextFormatterTests {

    // MARK: - Fixtures

    private func makePort(
        connected: Bool = true,
        rawProperties: [String: String] = ["PortType": "2"]
    ) -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: connected,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: true,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["USB2", "USB3"],
            transportsActive: connected ? ["USB3"] : [],
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: rawProperties
        )
    }

    private func tunnelledDevice(name: String, vendor: String? = "Apple") -> USBDevice {
        USBDevice(
            id: 42, locationID: 0x2011_0000,
            vendorID: 0x05AC, productID: 0x0202,
            vendorName: vendor, productName: name,
            serialNumber: nil, usbVersion: nil, speedRaw: 1,
            busPowerMA: nil, currentMA: nil,
            isThunderboltTunnelled: true,
            rawProperties: [:]
        )
    }

    // MARK: - Smoke

    @Test("Tunnelled devices render in an 'Other USB devices' section (issue #274)")
    func tunnelledDevicesRenderFlatSection() {
        // No Thunderbolt switches, so the device can't be attributed to a port
        // and falls into the flat section.
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            usbDevices: [tunnelledDevice(name: "USB Optical Mouse")]
        )
        #expect(output.contains("Other USB devices"))
        #expect(output.contains("USB Optical Mouse"))
    }

    @Test("Render produces non-empty output")
    func renderProducesNonEmptyOutput() {
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        #expect(!output.isEmpty)
    }

    @Test("Render empty ports produces non-empty output")
    func renderEmptyPortsProducesNonEmptyOutput() {
        let output = TextFormatter.render(
            ports: [], sources: [], identities: [], showRaw: false
        )
        #expect(!output.isEmpty)
        #expect(output.contains("No USB-C"))
    }

    // MARK: - Issue #573 part 2: MagSafe cable identity in CLI text

    private func magSafePort() -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-MagSafe 3@1",
            className: "AppleHPMInterfaceType11",
            portDescription: "Port-MagSafe 3@1",
            portTypeDescription: "MagSafe 3",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: ["CC"], transportsProvisioned: ["CC"],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: ["PortType": "17"]
        )
    }

    /// End-to-end CLI-text pin, alongside the `PortSummary`-level one: the
    /// unread-e-marker wording must never reach the actual `whatcable`
    /// (plain-text) output for a MagSafe port either, not just the summary
    /// struct that feeds it.
    @Test("CLI text never shows the unread-e-marker wording for a MagSafe cable identity")
    func cliTextNeverShowsUnreadEmarkerForMagSafe() {
        let magSafeCable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 17, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x7800, bcdDevice: 0,
            vdos: [], specRevision: 0
        )
        let output = TextFormatter.render(
            ports: [magSafePort()], sources: [], identities: [magSafeCable], showRaw: false
        )
        #expect(!output.contains("not read on this connection"))
    }

    // MARK: - Headline passthrough

    @Test("Headline from PortSummary appears verbatim")
    func headlineFromPortSummaryAppearsVerbatim() {
        let port = makePort(connected: false)
        let summary = PortSummary(port: port)
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: false
        )
        #expect(
            output.contains(summary.headline),
            "expected headline \"\(summary.headline)\" in render output"
        )
    }

    // MARK: - ANSI escapes absent when not a TTY

    @Test("No ANSI escapes in non-TTY output")
    func noANSIEscapesInNonTTYOutput() {
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false
        )
        #expect(
            output.contains("\u{1B}[") == false,
            "ANSI escape sequences should not appear when stdout is not a TTY"
        )
    }

    // MARK: - Terminal-safe external fields

    @Test("Hardware-controlled device names cannot inject terminal controls or lines")
    func hardwareDeviceNamesAreTerminalSafe() {
        let maliciousName = "显示器 🚀\u{1B}]0;forged title\u{7}\nforged row"
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            usbDevices: [tunnelledDevice(name: maliciousName)]
        )

        #expect(!output.contains("\u{1B}]0;forged title"))
        #expect(!output.contains("\u{7}"))
        #expect(output.contains(#"显示器 🚀\u{1B}]0;forged title\u{7}\u{A}forged row"#))
    }

    @Test("Hardware-controlled vendor names cannot inject terminal controls or lines")
    func hardwareVendorNamesAreTerminalSafe() {
        // The tree row folds the device-reported vendor in after the product
        // name (USBDevice.displayName), so the vendor string reaches the
        // terminal by the same path the product name does and needs the same
        // encoding. Product name is benign here so only the vendor is on trial.
        let maliciousVendor = "Acme\u{1B}]0;forged title\u{7}\nforged row"
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            usbDevices: [tunnelledDevice(name: "USB Optical Mouse", vendor: maliciousVendor)]
        )

        #expect(!output.contains("\u{1B}]0;forged title"))
        #expect(!output.contains("\u{7}"))
        #expect(output.contains(#"USB Optical Mouse (Acme\u{1B}]0;forged title\u{7}\u{A}forged row)"#))
    }

    @Test("--raw terminal output encodes control characters in IOKit keys and values")
    func rawIOKitFieldsAreTerminalSafe() {
        let port = makePort(rawProperties: [
            "Unsafe\u{1B}]key\u{7}": "value\u{9B}31m\rforged",
        ])
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: true
        )

        #expect(!output.contains("\u{1B}]key"))
        #expect(!output.contains("\u{7}"))
        #expect(!output.contains("\u{9B}"))
        #expect(output.contains(#"Unsafe\u{1B}]key\u{7} = value\u{9B}31m\u{D}forged"#))
    }

    // MARK: - Thunderbolt fabric tree (issue #280)

    private func tbFabricPort() -> USBCPort {
        USBCPort(
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
            rawProperties: ["PortType": "2"]
        )
    }

    private func fabricLanePort(
        _ portNumber: Int, socketID: String?,
        speed: LinkGeneration = .usb4Tb4, widthRaw: UInt8 = 0x2
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

    private func fabricSwitch(
        uid: Int64, depth: Int, parent: Int64?, vendor: String, model: String,
        lane: Int, socketID: String?,
        speed: LinkGeneration = .usb4Tb4, widthRaw: UInt8 = 0x2
    ) -> IOThunderboltSwitch {
        IOThunderboltSwitch(
            id: uid,
            className: "IOThunderboltSwitchType5",
            vendorID: 1452,
            vendorName: vendor,
            modelName: model,
            routerID: 0,
            depth: depth,
            routeString: 0,
            upstreamPortNumber: 1,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 12),
            ports: [fabricLanePort(lane, socketID: socketID, speed: speed, widthRaw: widthRaw)],
            parentSwitchUID: parent
        )
    }

    /// The CLI text output must render the whole Thunderbolt fabric tree,
    /// including the second branch (OWC) that the old linear chain dropped.
    @Test("CLI renders the full Thunderbolt fabric tree with every branch")
    func cliRendersFullThunderboltFabricTree() {
        let switches = [
            fabricSwitch(uid: 100, depth: 0, parent: nil, vendor: "Apple Inc.", model: "iOS", lane: 1, socketID: "1"),
            fabricSwitch(uid: 200, depth: 1, parent: 100, vendor: "CalDigit, Inc.", model: "Thunderbolt 4 Pro Dock", lane: 2, socketID: nil),
            fabricSwitch(uid: 300, depth: 2, parent: 200, vendor: "LaCie", model: "1big Dock v2", lane: 2, socketID: nil),
            fabricSwitch(uid: 400, depth: 3, parent: 300, vendor: "Apple Inc.", model: "Studio Display", lane: 2, socketID: nil),
            fabricSwitch(uid: 500, depth: 2, parent: 200, vendor: "OWC", model: "Express 1M2", lane: 2, socketID: nil),
        ]
        let output = TextFormatter.render(
            ports: [tbFabricPort()], sources: [], identities: [],
            showRaw: false, thunderboltSwitches: switches
        )

        #expect(output.contains("Thunderbolt fabric:"), "fabric header missing; got:\n\(output)")
        // Every device must be named, including the previously-dropped OWC.
        for name in ["CalDigit, Inc. Thunderbolt 4 Pro Dock", "LaCie 1big Dock v2", "Apple Inc. Studio Display", "OWC Express 1M2"] {
            #expect(output.contains(name), "missing \(name) in fabric tree; got:\n\(output)")
        }
        // The two branches indent to different depths under the dock: the
        // Studio Display (depth 3) sits deeper than the OWC (depth 2).
        #expect(output.contains("      ↳ Apple Inc. Studio Display"), "Studio Display indent wrong; got:\n\(output)")
        #expect(output.contains("    ↳ OWC Express 1M2"), "OWC indent wrong; got:\n\(output)")
    }

    /// The dock arrives on its upstream lane (port 1) at 1 TX / 3 RX. The
    /// fabric row is written from the Mac's side, the same way the port
    /// line is, so it reads 120 out, 40 in and never the dock's own flip.
    @Test("CLI fabric row labels an asymmetric dock link from the Mac's side")
    func cliFabricRowReadsAsymmetricLinkFromMacSide() {
        let switches = [
            fabricSwitch(
                uid: 100, depth: 0, parent: nil, vendor: "Apple Inc.", model: "iOS",
                lane: 1, socketID: "1", speed: .tb5, widthRaw: 0x4
            ),
            fabricSwitch(
                uid: 200, depth: 1, parent: 100, vendor: "Ugreen", model: "TBT5 Dock",
                lane: 1, socketID: nil, speed: .tb5, widthRaw: 0x8
            ),
        ]
        let output = TextFormatter.render(
            ports: [tbFabricPort()], sources: [], identities: [],
            showRaw: false, thunderboltSwitches: switches
        )
        // The fabric row, not the "Connected to" summary bullet above it.
        let dockRow = output.split(separator: "\n").first { $0.contains("Ugreen TBT5 Dock -") }.map(String.init)
        #expect(dockRow?.contains("Up to 120 Gb/s out, 40 Gb/s in") == true, "dock row must read from the Mac's side; got:\n\(output)")
        #expect(dockRow?.contains("40 Gb/s out") == false, "dock row must not flip to the dock's side; got:\n\(output)")
    }

    @Test("CLI encodes terminal controls in Thunderbolt device names")
    func cliEncodesThunderboltDeviceNames() {
        let switches = [
            fabricSwitch(
                uid: 100, depth: 0, parent: nil,
                vendor: "Apple Inc.", model: "Host", lane: 1, socketID: "1"
            ),
            fabricSwitch(
                uid: 200, depth: 1, parent: 100,
                vendor: "Dock\u{1B}]0;forged\u{7}", model: "Model\nrow",
                lane: 2, socketID: nil
            ),
        ]
        let output = TextFormatter.render(
            ports: [tbFabricPort()], sources: [], identities: [],
            showRaw: false, thunderboltSwitches: switches
        )

        #expect(!output.contains("\u{1B}]0;forged"))
        #expect(output.contains(#"Dock\u{1B}]0;forged\u{7} Model\u{A}row"#))
    }

    // MARK: - Cable trust signals

    /// Build an SOP' identity for trust-signal tests. `cableVDO` is VDO[3].
    /// Default uses USB4 Gen3 / 5A / ~1m latency, which produces no flags.
    private func cableIdentity(
        portNumber: Int = 1,
        vendorID: Int = 0x05AC,
        cableVDO: UInt32 = (0b10 << 5) | 0b011 | (1 << 13)
    ) -> USBPDSOP {
        USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: portNumber,
            vendorID: vendorID,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(vendorID), 0, 0, cableVDO],
            specRevision: 3
        )
    }

    @Test("No trust signals heading when cable is clean")
    func noTrustSignalsHeadingWhenCableIsClean() {
        let port = makePort()
        let cable = cableIdentity(portNumber: port.portNumber ?? 1)
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [cable], showRaw: false
        )
        #expect(
            output.contains("Cable trust signals") == false,
            "Clean cable should not surface a trust-signals section"
        )
    }

    @Test("Blank-VID note renders calmly when the VDO is well-formed")
    func blankVIDNoteRendersCalmly() {
        let port = makePort()
        // Default VDO is clean, so a blank VID is corroborated: it should
        // render as a calm "Cable note", not a warning-level "trust signals"
        // block, but still carry its title and detail.
        let cable = cableIdentity(portNumber: port.portNumber ?? 1, vendorID: 0)
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [cable], showRaw: false
        )
        #expect(output.contains("Cable note"))
        #expect(output.contains("Cable trust signals") == false)
        #expect(output.contains(TrustFlag.zeroVendorID(corroborated: true).title))
        #expect(output.contains(TrustFlag.zeroVendorID(corroborated: true).detail))
    }

    @Test("Multiple trust flags all render")
    func multipleTrustFlagsAllRender() {
        let port = makePort()
        // Unregistered VID + reserved speed = two flags.
        let vdo = UInt32(0b111) | UInt32(2 << 5) | UInt32(1 << 13)
        let cable = cableIdentity(
            portNumber: port.portNumber ?? 1,
            vendorID: 0xDEAD,
            cableVDO: vdo
        )
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [cable], showRaw: false
        )
        #expect(output.contains(TrustFlag.vidNotInUSBIFList(0xDEAD).title))
        #expect(output.contains(TrustFlag.reservedSpeedEncoding(7).title))
    }

    // MARK: - E-marker selection is order independent

    /// A bare SOP' (endpoint present, no VDOs at all): the "not read on this
    /// connection" shape, not a genuinely blank e-marker.
    private func bareCableIdentity(portNumber: Int) -> USBPDSOP {
        USBPDSOP(
            id: 2, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: portNumber,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [], specRevision: 3
        )
    }

    /// A populated SOP'', genuinely the other endpoint from `bareCableIdentity`'s
    /// SOP' (the actual shape the ticket describes: a bare SOP' shadowing a
    /// populated SOP''). Passive cable header by default so a shortfall
    /// scenario can reach `DisplayDiagnostic`'s cable-exoneration branch.
    private func populatedDoublePrimeIdentity(
        portNumber: Int,
        vendorID: Int = 0x05AC,
        cableVDO: UInt32 = (0b10 << 5) | 0b011 | (1 << 13)
    ) -> USBPDSOP {
        USBPDSOP(
            id: 3, endpoint: .sopDoublePrime,
            parentPortType: 2, parentPortNumber: portNumber,
            vendorID: vendorID, productID: 0x1234, bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(vendorID), 0, 0, cableVDO],
            specRevision: 3
        )
    }

    /// Renders one port with a bare SOP' and a populated SOP'' twice, with
    /// the two identities swapped in `identities`, and asserts the two
    /// outputs are byte-identical. This is the property the whole ticket
    /// exists to guarantee: which identity carries the real cable data must
    /// not depend on array order. Zero VID (rather than a clean cable) is
    /// deliberate: it raises `TrustFlag.zeroVendorID`, which only the
    /// populated identity can produce (the bare one has no VDOs to evaluate
    /// at all, per `CableTrustReport`'s "unread e-marker" gate), so the two
    /// renders have real content to differ on if selection is order-dependent.
    @Test("Cable e-marker selection is order independent: bare SOP' before or after a populated SOP'' renders identically")
    func cableSelectionIsOrderIndependent() {
        let port = makePort()
        let bare = bareCableIdentity(portNumber: port.portNumber ?? 1)
        let populated = populatedDoublePrimeIdentity(portNumber: port.portNumber ?? 1, vendorID: 0)

        let bareFirst = TextFormatter.render(
            ports: [port], sources: [], identities: [bare, populated], showRaw: false
        )
        let populatedFirst = TextFormatter.render(
            ports: [port], sources: [], identities: [populated, bare], showRaw: false
        )

        #expect(bareFirst == populatedFirst)
        // Confirm there is something real to compare: the populated
        // identity's trust note must actually appear in both renders, not
        // just happen to match because neither rendered it.
        #expect(bareFirst.contains(TrustFlag.zeroVendorID(corroborated: true).title))
        #expect(populatedFirst.contains(TrustFlag.zeroVendorID(corroborated: true).title))
    }

    /// Same order-independence property, but through the display verdict:
    /// a readable EDID (the real G34w-10 base block from `EDIDInfoTests`) on
    /// a link that falls short of the monitor's ceiling with every host lane
    /// in use on a passive cable. This is `DisplayDiagnostic`'s
    /// `cableUnlikely` branch, which the golden net cannot reach (every
    /// golden fixture's display port has `monitor: nil`).
    @Test("Cable e-marker selection is order independent: display verdict with a readable EDID and a link shortfall")
    func displayVerdictSelectionIsOrderIndependent() {
        let port = makePort()
        let bare = bareCableIdentity(portNumber: port.portNumber ?? 1)
        let populated = populatedDoublePrimeIdentity(portNumber: port.portNumber ?? 1)
        // 4 of 4 lanes in use, but at RBR (1.62 Gbps/lane): falls short of
        // the G34w-10's 100 Hz / 600 MHz ceiling. All host lanes in use on a
        // cable positively identified as passive is the one signal that
        // exonerates it (DisplayDiagnostic.swift's cableKnownPassive).
        let displayPort = IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: true, laneCount: 4, maxLaneCount: 4, linkRate: 3,
                linkRateDescription: "1.62 Gbps (RBR)", tunneled: false, hpdState: 1
            ),
            monitor: MonitorInfo(
                manufacturerName: nil, productName: nil, productId: nil,
                yearOfManufacture: nil, edid: Data(EDIDInfoTests.g34wBaseBlock)
            ),
            parentPortType: 2, parentPortNumber: port.portNumber ?? 1
        )

        let bareFirst = TextFormatter.render(
            ports: [port], sources: [], identities: [bare, populated], showRaw: false,
            displayPorts: [displayPort]
        )
        let populatedFirst = TextFormatter.render(
            ports: [port], sources: [], identities: [populated, bare], showRaw: false,
            displayPorts: [displayPort]
        )

        #expect(bareFirst == populatedFirst)
        // Confirm the cableUnlikely branch was actually reached, not just
        // "no display block at all".
        #expect(bareFirst.lowercased().contains("unlikely to be the cable"))
    }

    /// Same order-independence property, but through the showRaw active-cable
    /// VDO2 block, which only an active cable's e-marker carries and which
    /// the golden net cannot reach (every golden test renders `showRaw: false`).
    @Test("Cable e-marker selection is order independent: showRaw active-cable VDO2 block")
    func showRawVDO2SelectionIsOrderIndependent() {
        let port = makePort()
        let bare = bareCableIdentity(portNumber: port.portNumber ?? 1)
        // Active cable header (product type 4) with a populated VDO2 at
        // index 4, mirroring activeCableVDO2SectionAppearsInRawMode.
        var vdo4: UInt32 = 0
        vdo4 |= UInt32(1) << 10  // optical
        let vdo3: UInt32 = UInt32(0b011) | UInt32(2 << 5) | UInt32(1 << 13) | UInt32(0b10 << 11)
        let populated = USBPDSOP(
            id: 3, endpoint: .sopDoublePrime,
            parentPortType: 2, parentPortNumber: port.portNumber ?? 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(4 << 27) | UInt32(0x05AC), 0, 0, vdo3, vdo4],
            specRevision: 3
        )

        let bareFirst = TextFormatter.render(
            ports: [port], sources: [], identities: [bare, populated], showRaw: true
        )
        let populatedFirst = TextFormatter.render(
            ports: [port], sources: [], identities: [populated, bare], showRaw: true
        )

        #expect(bareFirst == populatedFirst)
        #expect(bareFirst.contains("Active cable (VDO 2)"))
    }

    // MARK: - Active Cable VDO 2 raw view

    @Test("Active cable VDO2 section appears in raw mode")
    func activeCableVDO2SectionAppearsInRawMode() {
        let port = makePort()
        // VDO2 with optical + retimer + isolated + USB4 supported (bit 8 = 0).
        var vdo4: UInt32 = 0
        vdo4 |= UInt32(1) << 10  // optical
        vdo4 |= UInt32(1) << 9   // retimer
        vdo4 |= UInt32(1) << 2   // isolated
        // bits 8 / 5 / 4 left at 0 = USB4 / USB 3.2 / USB 2.0 supported.
        let vdo3: UInt32 = UInt32(0b011) | UInt32(2 << 5) | UInt32(1 << 13) | UInt32(0b10 << 11)
        let active = USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: port.portNumber ?? 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(4 << 27) | UInt32(0x05AC), 0, 0, vdo3, vdo4],
            specRevision: 3
        )
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [active], showRaw: true
        )
        #expect(output.contains("Active cable (VDO 2)"))
        #expect(output.contains("Physical connection") && output.contains("Optical"))
        #expect(output.contains("Active element") && output.contains("Re-timer"))
        #expect(output.contains("USB4 supported") && output.contains("Yes"))
    }

    @Test("Active cable VDO2 section absent without raw flag")
    func activeCableVDO2SectionAbsentWithoutRawFlag() {
        let port = makePort()
        let vdo3: UInt32 = UInt32(0b011) | UInt32(2 << 5) | UInt32(1 << 13) | UInt32(0b10 << 11)
        let active = USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2,
            parentPortNumber: port.portNumber ?? 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(4 << 27) | UInt32(0x05AC), 0, 0, vdo3, 0],
            specRevision: 3
        )
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [active], showRaw: false
        )
        #expect(
            output.contains("Active cable (VDO 2)") == false,
            "VDO 2 deep view should only render with --raw"
        )
    }

    @Test("Trust signals suppressed for non-cable endpoint")
    func trustSignalsSuppressedForNonCableEndpoint() {
        // SOP (port partner) shouldn't be evaluated as a cable, so even
        // a zero VID on a port-partner identity shouldn't trip the section.
        let port = makePort()
        let partner = USBPDSOP(
            id: 1,
            endpoint: .sop,
            parentPortType: 2,
            parentPortNumber: port.portNumber ?? 1,
            vendorID: 0,
            productID: 0,
            bcdDevice: 0,
            vdos: [0, 0, 0, 0],
            specRevision: 3
        )
        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [partner], showRaw: false
        )
        #expect(output.contains("Cable trust signals") == false)
    }

    // MARK: - Private key redaction (DAR-148)

    /// --raw text output must not print ConnectionUUID but must print
    /// legitimate keys like PortType.
    @Test("--raw text output omits ConnectionUUID and retains PortType")
    func rawTextOmitsConnectionUUID() {
        let port = USBCPort(
            id: 1, serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3"],
            transportsActive: ["USB3"], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: [
                "ConnectionUUID": "DDDD6666-EEEE-7777-FFFF-888899990000",
                "PortType": "2",
                "VendorID": "0x05AC",
            ]
        )

        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: true
        )

        #expect(!output.contains("ConnectionUUID"), "ConnectionUUID must not appear in text output")
        #expect(!output.contains("DDDD6666"), "ConnectionUUID value must not appear in text output")
        #expect(output.contains("PortType"), "PortType must appear in text output")
        #expect(output.contains("VendorID"), "VendorID must appear in text output")
    }

    /// DAR-29 privacy regression: the HPM controller UUID must never appear in
    /// text output, even when a future readAll path captures a raw "UUID" key.
    @Test("--raw text output omits UUID key and value (DAR-29 privacy guard)")
    func rawTextOmitsHPMControllerUUID() {
        let port = USBCPort(
            id: 1, serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3"],
            transportsActive: ["USB3"], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            // Simulate a future readAll that accidentally captured UUID.
            rawProperties: [
                "UUID": "7C30AF2D-FEED-BEEF-CAFE-112233445566",
                "PortType": "2",
            ]
        )

        let output = TextFormatter.render(
            ports: [port], sources: [], identities: [], showRaw: true
        )

        #expect(!output.contains("UUID"), "UUID key must not appear in text output")
        #expect(!output.contains("7C30AF2D"), "UUID value must not appear in text output")
        #expect(output.contains("PortType"), "PortType must appear in text output")
    }

    // MARK: - Built-in display port (issue #352)

    private func hdmiDisplayDP() -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(
                active: true, laneCount: 4, maxLaneCount: 4, linkRate: 4,
                linkRateDescription: "8.1 Gbps (HBR3)", tunneled: false, hpdState: 1
            ),
            monitor: nil,
            parentPortType: 6,
            parentPortTypeDescription: "HDMI",
            parentPortNumber: 1
        )
    }

    @Test("Native HDMI port renders its own section after the USB-C group")
    func builtInHDMIPortRendersSection() {
        let hdmiPort = BuiltInDisplayPort(
            portType: "HDMI",
            portNumber: 1,
            displays: [hdmiDisplayDP()]
        )
        let output = TextFormatter.render(
            ports: [makePort()],
            sources: [], identities: [], showRaw: false,
            builtInDisplayPorts: [hdmiPort]
        )
        #expect(output.contains("Port-HDMI@1"))
        #expect(output.contains("Built-in HDMI port 1"))
        // The slim card has no PD bullets / charging / transport sections;
        // the only diagnostic block is the display verdict.
        #expect(!output.contains("Charging:"))
    }

    @Test("Native HDMI section omitted when no built-in display ports")
    func builtInHDMINotEmittedWhenEmpty() {
        let output = TextFormatter.render(
            ports: [makePort()],
            sources: [], identities: [], showRaw: false,
            builtInDisplayPorts: []
        )
        #expect(!output.contains("Port-HDMI@"))
    }

    // MARK: - Built-in USB ports gate (issue #348)

    private func frontPortDevice(name: String) -> USBDevice {
        USBDevice(
            id: 84, locationID: 0x0020_0000,
            vendorID: 0x04E8, productID: 0x61FD,
            vendorName: "Samsung", productName: name,
            serialNumber: nil, usbVersion: nil, speedRaw: 4,
            busPowerMA: nil, currentMA: nil,
            isBehindInternalHub: true,
            rawProperties: [:]
        )
    }

    @Test("Built-in USB ports section renders on a desktop Mac")
    func builtInUSBSectionRendersOnDesktop() {
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            isDesktopMac: true,
            usbDevices: [frontPortDevice(name: "PSSD T9")]
        )
        #expect(output.contains("Built-in USB ports"))
        #expect(output.contains("PSSD T9"))
    }

    @Test("Built-in section with named USB-A ports: USB-A title, per-port headers, nested devices (issue #490)")
    func builtInUSBSectionNamesUSBAPorts() {
        func namedDevice(id: UInt64, name: String, portNode: String) -> USBDevice {
            USBDevice(
                id: id, locationID: UInt32(truncatingIfNeeded: id),
                vendorID: 0x04E8, productID: 0x61FD,
                vendorName: "Samsung", productName: name,
                serialNumber: nil, usbVersion: nil, speedRaw: 4,
                busPowerMA: nil, currentMA: nil,
                controllerPortName: portNode,
                isBehindInternalHub: true,
                rawProperties: [:]
            )
        }
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            isDesktopMac: true,
            usbDevices: [
                namedDevice(id: 84, name: "PSSD T9", portNode: "Port-USB-A@1"),
                namedDevice(id: 85, name: "Backup Plus", portNode: "Port-USB-A@2"),
            ]
        )
        // All devices on USB-A nodes: the title itself says USB-A.
        #expect(output.contains("Built-in USB-A ports"))
        // One header per physical port, each device under its own port.
        #expect(output.contains("Built-in USB-A port 1"))
        #expect(output.contains("Built-in USB-A port 2"))
        #expect(output.contains("PSSD T9"))
        #expect(output.contains("Backup Plus"))
        // Devices nest one indent level deeper than their port header.
        #expect(output.contains("    \u{2022}") || output.contains("    \u{1B}"),
            "device bullets should be indented under the port header")
    }

    @Test("Built-in section with a USB-C front-port device keeps the generic title")
    func builtInUSBSectionMixedKeepsGenericTitle() {
        let namedC = USBDevice(
            id: 86, locationID: 0x0030_0000,
            vendorID: 0x04E8, productID: 0x61FD,
            vendorName: "Samsung", productName: "Front SSD",
            serialNumber: nil, usbVersion: nil, speedRaw: 4,
            busPowerMA: nil, currentMA: nil,
            controllerPortName: "Port-USB-C@6",
            isBehindInternalHub: true,
            rawProperties: [:]
        )
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            isDesktopMac: true,
            usbDevices: [namedC]
        )
        #expect(output.contains("Built-in USB ports"))
        #expect(!output.contains("Built-in USB-A ports"))
        #expect(output.contains("Built-in USB-C port 6"))
    }

    @Test("Built-in USB ports section is suppressed on a laptop (desktop-only gate)")
    func builtInUSBSectionSuppressedOnLaptop() {
        // Same front-port-flagged device, but isDesktopMac is false: the gate
        // keeps the section off laptops regardless of the structural flag.
        let output = TextFormatter.render(
            ports: [makePort()], sources: [], identities: [], showRaw: false,
            isDesktopMac: false,
            usbDevices: [frontPortDevice(name: "PSSD T9")]
        )
        #expect(!output.contains("Built-in USB ports"))
        #expect(!output.contains("PSSD T9"))
    }
}
