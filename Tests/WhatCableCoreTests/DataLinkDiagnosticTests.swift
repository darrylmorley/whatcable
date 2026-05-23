import Testing
@testable import WhatCableCore

@Suite("Data Link Diagnostic")
struct DataLinkDiagnosticTests {

    // MARK: - Fixtures

    /// Active USB-C port. Same shape as the ChargingDiagnostic fixture
    /// (the proven-compiling AppleHPMInterface init param list).
    /// `transportsActive` defaults to `["USB3"]` because most tests in
    /// this suite exercise a USB3 link via `usb3Transports`. Tests that
    /// hand-roll TB or USB2-only scenarios override it.
    private func makePort(
        active: Bool = true,
        transportsActive: [String] = ["USB3"],
        superSpeedActive: Bool? = nil
    ) -> AppleHPMInterface {
        AppleHPMInterface(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: active,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: superSpeedActive,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [],
            transportsActive: transportsActive,
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
    }

    /// Cable e-marker (SOP') advertising a given CableSpeed code in the
    /// low 3 bits of VDO[3]. Codes: 0 = USB 2.0 (0.48), 1 = USB 3.2 Gen 1
    /// (5), 2 = Gen 2 (10), 3 = USB4 Gen 3 (40), 4 = Gen 4 (80). Mirrors
    /// the ChargingDiagnostic test's cableIdentity construction.
    private func cableEmarker(speedCode: UInt32) -> USBPDSOP {
        let validLatency: UInt32 = 1 << 13          // ~1m, avoids decode warning
        let cableVDO = speedCode | (1 << 5) | validLatency   // 3A current bits
        let idHeader: UInt32 = 0x1800_0000          // passive cable, UFP type 3
        return USBPDSOP(
            id: 2, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 0
        )
    }

    /// USB device with a given "Device Speed" enum value.
    /// 3 = 5 Gbps, 4 = 10 Gbps, 5 = 20 Gbps.
    private func device(speedRaw: UInt8) -> USBDevice {
        USBDevice(
            id: 10, locationID: 0x0100_0000,
            vendorID: 0x1234, productID: 0x5678,
            vendorName: nil, productName: "Test SSD", serialNumber: nil,
            usbVersion: nil, speedRaw: speedRaw,
            busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
    }

    private func cio(cableSpeed: Int) -> CIOCableCapability {
        CIOCableCapability(
            id: 3, portKey: "2/1",
            cableGeneration: nil, cableSpeed: cableSpeed, generation: nil,
            asymmetricModeSupported: nil, legacyAdapter: nil, linkTrainingMode: nil
        )
    }

    private func usb3(signaling: Int) -> USB3Transport {
        USB3Transport(
            id: 4, portKey: "2/1",
            signaling: signaling, signalingDescription: nil, dataRole: nil
        )
    }

    // MARK: - Applicability

    @Test("Returns nil on an inactive port")
    func returnsNilOnInactivePort() {
        let diag = DataLinkDiagnostic(
            port: makePort(active: false),
            identities: [cableEmarker(speedCode: 3)],
            devices: [device(speedRaw: 5)],
            usb3Transports: [usb3(signaling: 2)],
            cio: nil
        )
        #expect(diag == nil)
    }

    @Test("Returns nil when no active link speed is known")
    func returnsNilWithoutActiveSpeed() {
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],
            devices: [device(speedRaw: 5)],
            usb3Transports: [],            // no USB3 signaling
            cio: nil,
            tbActiveGbps: nil              // no TB link
        )
        #expect(diag == nil)
    }

    // MARK: - Bottleneck attribution

    @Test("Cable is the bottleneck")
    func cableIsBottleneck() {
        // Mac port 20, device 20, but a USB 3.2 Gen 1 (5 Gbps) cable.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 1)],   // 5 Gbps
            devices: [device(speedRaw: 5)],              // 20 Gbps
            usb3Transports: [usb3(signaling: 1)],        // active 5 Gbps
            cio: nil,
            hostMaxGbps: 20
        )
        guard case .cableLimit(let cable, let capable) = diag?.bottleneck else {
            Issue.record("expected .cableLimit, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(cable == 5)
        #expect(capable == 20)
        #expect(diag!.isWarning)
    }

    @Test("Host port is the bottleneck")
    func hostIsBottleneck() {
        // Fast 40 Gbps cable, 20 Gbps device, but the Mac port only does 5.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],   // 40 Gbps
            devices: [device(speedRaw: 5)],              // 20 Gbps
            usb3Transports: [usb3(signaling: 1)],        // active 5 Gbps
            cio: nil,
            hostMaxGbps: 5
        )
        guard case .hostLimit(let host, let capable) = diag?.bottleneck else {
            Issue.record("expected .hostLimit, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(host == 5)
        #expect(capable == 20)
        #expect(diag!.isWarning)
    }

    @Test("Device is the cap, not a fault")
    func deviceIsCapNotFault() {
        // 40 Gbps cable, 40 Gbps port, but a 10 Gbps device.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],   // 40 Gbps
            devices: [device(speedRaw: 4)],              // 10 Gbps
            usb3Transports: [usb3(signaling: 2)],        // active 10 Gbps
            cio: nil,
            hostMaxGbps: 40
        )
        guard case .deviceLimit(let d) = diag?.bottleneck else {
            Issue.record("expected .deviceLimit, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(d == 10)
        #expect(diag!.isWarning == false)   // a slow device is normal, not a warning
    }

    @Test("Degraded link: everyone supports more but it came up slow")
    func degradedLink() {
        // 40 Gbps cable, 40 Gbps port, 20 Gbps device, but the TB link
        // negotiated only 5 Gbps. This is the case the old draft wrongly
        // reported as "full speed".
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],   // 40 Gbps
            devices: [device(speedRaw: 5)],              // 20 Gbps
            usb3Transports: [],
            cio: nil,
            tbActiveGbps: 5,                             // degraded link
            hostMaxGbps: 40
        )
        guard case .degraded(let active, let expected) = diag?.bottleneck else {
            Issue.record("expected .degraded, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(active == 5)
        #expect(expected == 20)
        #expect(diag!.isWarning)
    }

    @Test("No cable signal: honest 'can't tell'")
    func unknownCableWhenNoSignal() {
        // No e-marker, no controller data. Port 40, device 20, link 5.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [],
            devices: [device(speedRaw: 5)],              // 20 Gbps
            usb3Transports: [usb3(signaling: 1)],        // active 5 Gbps
            cio: nil,
            hostMaxGbps: 40
        )
        guard case .unknownCable(let active) = diag?.bottleneck else {
            Issue.record("expected .unknownCable, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(active == 5)
        #expect(diag!.isWarning == false)
        #expect(diag!.cableSignalConflict == false)
    }

    @Test("Everything matched: fine")
    func everythingFine() {
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],   // 40 Gbps
            devices: [],
            usb3Transports: [],
            cio: nil,
            tbActiveGbps: 40,                            // active 40 Gbps
            hostMaxGbps: 40
        )
        guard case .fine(let active) = diag?.bottleneck else {
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(active == 40)
        #expect(diag!.isWarning == false)
    }

    @Test("Controller overrides a lying e-marker (issue #111)")
    func controllerWinsOverEmarker() {
        // E-marker claims USB 2.0 (passive under-report), but the TB
        // controller reports CableSpeed 3 (40 Gbps). We must NOT blame the
        // cable: report fine at 40 and flag the conflict.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 0)],   // e-marker says 0.48
            devices: [],
            usb3Transports: [],
            cio: cio(cableSpeed: 3),                     // controller says 40
            tbActiveGbps: 40,
            hostMaxGbps: 40
        )
        guard case .fine(let active) = diag?.bottleneck else {
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(active == 40)
        #expect(diag!.cableSignalConflict == true)
        #expect(diag!.detail.contains("disagree"))
    }

    @Test("Controller overrides a lying e-marker that over-reports (issue #190)")
    func controllerWinsOverOverReportingEmarker() {
        // Inverse of #111: suspect cable e-marker claims USB4 Gen 4 (80
        // Gbps), but the TB controller reports CableSpeed 3 (40 Gbps).
        // We must take the controller's figure (40), not the higher
        // e-marker claim. Without this fix, max(e, c) believed the cable.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 4)],   // e-marker says 80
            devices: [],
            usb3Transports: [],
            cio: cio(cableSpeed: 3),                     // controller says 40
            tbActiveGbps: 40,
            hostMaxGbps: 80                              // M4 Max-class host
        )
        guard let facts = diag?.facts else {
            Issue.record("expected a diagnostic, got nil")
            return
        }
        #expect(facts.cableEmarkerGbps == 80)
        #expect(facts.cableControllerGbps == 40)
        #expect(facts.cableGbps == 40,
            "Controller (40) should win over the over-reporting e-marker (80). Got: \(String(describing: facts.cableGbps))")
        #expect(diag!.cableSignalConflict == true)
    }

    @Test("No capability known at all: unknownCable, not a guess")
    func noCapabilityKnown() {
        // Active 10 Gbps link, but no e-marker, no controller data, host
        // unresolved, no device. Nothing to compare against.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [],
            devices: [],
            usb3Transports: [usb3(signaling: 2)],        // active 10 Gbps
            cio: nil,
            hostMaxGbps: nil
        )
        guard case .unknownCable(let active) = diag?.bottleneck else {
            Issue.record("expected .unknownCable, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(active == 10)
        #expect(diag!.isWarning == false)
    }

    @Test("Facts expose the resolved per-party numbers")
    func factsExposeResolvedNumbers() {
        // E-marker says 0.48 (USB 2.0), controller says 40 (TB4 class),
        // host 40, device 10 (speedRaw 4), link active at 40 (TB).
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 0)],   // 0.48
            devices: [device(speedRaw: 4)],              // 10
            usb3Transports: [],
            cio: cio(cableSpeed: 3),                     // 40
            tbActiveGbps: 40,
            hostMaxGbps: 40
        )
        guard let facts = diag?.facts else {
            Issue.record("expected a diagnostic with facts, got nil")
            return
        }
        #expect(facts.cableEmarkerGbps == 0.48)
        #expect(facts.cableControllerGbps == 40)
        #expect(facts.cableGbps == 40)        // controller wins
        #expect(facts.deviceGbps == 10)
        #expect(facts.hostGbps == 40)
        #expect(facts.activeGbps == 40)
        #expect(diag!.cableSignalConflict == true)
    }

    // MARK: - TransportsActive gating

    @Test("USB2-only link ignores lingering USB3 transport (issue #187)")
    func usb2OnlyLinkIgnoresLingeringUSB3Transport() {
        // A USB-C to Micro-USB cable negotiates only USB 2.0, but the
        // HPM port controller can leave a `IOPortTransportStateUSB3`
        // service registered (carrying Gen 2 signaling) and assert
        // `IOAccessoryUSBSuperSpeedActive=1`. Neither should produce a
        // 10 Gbps verdict: `TransportsActive` is the authority.
        let diag = DataLinkDiagnostic(
            port: makePort(transportsActive: ["CC", "USB2"], superSpeedActive: true),
            identities: [],
            devices: [],
            usb3Transports: [usb3(signaling: 2)],
            cio: nil,
            hostMaxGbps: nil
        )
        #expect(diag == nil,
            "USB2-only link must not produce a USB3 data-link verdict, got: \(String(describing: diag?.bottleneck))")
    }

    // MARK: - Mac port speed inference

    /// Build a host root TB switch with the given `supportedSpeed` mask and
    /// one active lane port matching `socketID`. Minimal fixture: just
    /// enough for `hostMaxGbpsFromSwitches` to walk to it.
    private func hostSwitch(socketID: String, supportedRaw: UInt8, activeSpeed: LinkGeneration) -> IOThunderboltSwitch {
        let lane = IOThunderboltPort(
            portNumber: 1,
            socketID: socketID,
            adapterType: .lane,
            currentSpeed: activeSpeed,
            currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil,
            rawTargetSpeed: nil,
            linkBandwidthRaw: nil
        )
        return IOThunderboltSwitch(
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
            supportedSpeed: SupportedSpeedMask(rawValue: supportedRaw),
            ports: [lane],
            parentSwitchUID: nil
        )
    }

    @Test("hostMaxGbps inferred from host root supportedSpeed (TB4-class controller)")
    func hostMaxGbpsInferredTB4() {
        // Mac with a Type5 controller: supports TB3 + TB4. Max = 40 Gbps.
        let host = hostSwitch(socketID: "1", supportedRaw: 0xC, activeSpeed: .usb4Tb4)
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [],
            devices: [],
            usb3Transports: [usb3(signaling: 2)],
            cio: nil,
            thunderboltSwitches: [host]
            // hostMaxGbps deliberately omitted; should be inferred from `host`.
        )
        #expect(diag?.facts.hostGbps == 40,
            "Expected 40 Gbps host max from Type5 supportedSpeed mask, got: \(String(describing: diag?.facts.hostGbps))")
    }

    @Test("hostMaxGbps inferred from host root supportedSpeed (TB5-class controller)")
    func hostMaxGbpsInferredTB5() {
        // Mac with a Type7 controller: supports TB3 + TB4 + TB5. Max = 80.
        let host = hostSwitch(socketID: "1", supportedRaw: 0xE, activeSpeed: .tb5)
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [],
            devices: [],
            usb3Transports: [usb3(signaling: 2)],
            cio: nil,
            thunderboltSwitches: [host]
        )
        #expect(diag?.facts.hostGbps == 80,
            "Expected 80 Gbps host max from Type7 supportedSpeed mask, got: \(String(describing: diag?.facts.hostGbps))")
    }

    @Test("Per-port supportedSpeed beats the switch aggregate (asymmetric controller)")
    func perPortSupportedSpeedBeatsAggregate() {
        // Build an asymmetric host root: port socket "1" supports only
        // TB4 (per-port mask 0xC), while the switch-level aggregate is
        // 0xE (TB3 + TB4 + TB5) -- the shape the OR-the-lane-ports
        // fallback would produce on a switch with another TB5-capable
        // lane elsewhere. Using `root.supportedSpeed.maxTotalGbps`
        // would falsely report 80 Gbps for the socket-1 user. The
        // matched port's own mask must win.
        let socket1Port = IOThunderboltPort(
            portNumber: 1, socketID: "1", adapterType: .lane,
            currentSpeed: .usb4Tb4, currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xC)   // TB3 + TB4 only
        )
        let socket9Port = IOThunderboltPort(
            portNumber: 9, socketID: "9", adapterType: .lane,
            currentSpeed: .tb5, currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE)   // TB3 + TB4 + TB5
        )
        let asymmetricRoot = IOThunderboltSwitch(
            id: 100,
            className: "IOThunderboltSwitchType7",
            vendorID: 1452,
            vendorName: "Apple Inc.",
            modelName: "Mac",
            routerID: 0,
            depth: 0,
            routeString: 0,
            upstreamPortNumber: 0,
            maxPortNumber: 8,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE),  // misleading aggregate
            ports: [socket1Port, socket9Port],
            parentSwitchUID: nil
        )
        let diag = DataLinkDiagnostic(
            port: makePort(),                                   // serviceName Port-USB-C@1 → socket "1"
            identities: [],
            devices: [],
            usb3Transports: [usb3(signaling: 2)],
            cio: nil,
            thunderboltSwitches: [asymmetricRoot]
        )
        #expect(diag?.facts.hostGbps == 40,
            "Expected 40 Gbps from port-1's own mask, not 80 Gbps from the switch aggregate. Got: \(String(describing: diag?.facts.hostGbps))")
    }

    @Test("Zero supportedSpeed mask returns nil (no host blame)")
    func zeroMaskReturnsNil() {
        // A switch with no supported-speed bits at all (mask 0) must
        // produce nil hostGbps so the diagnostic never blames the host.
        let host = hostSwitch(socketID: "1", supportedRaw: 0, activeSpeed: .usb4Tb4)
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [],
            devices: [],
            usb3Transports: [usb3(signaling: 2)],
            cio: nil,
            thunderboltSwitches: [host]
        )
        #expect(diag?.facts.hostGbps == nil)
    }

    // MARK: - Thunderbolt partner switch as device cap (issue #190)

    /// Build a depth-1 partner switch attached to `parent` via `parent`'s
    /// lane port `parentLanePortNumber`. `supportedRaw` is the partner's
    /// own supported-speed mask, which is what the diagnostic uses as the
    /// connected device's capability.
    ///
    /// Mirrors what real IOKit topology looks like (verified against the
    /// Samsung C34J79x fixture in `ThunderboltLinkFromTests`):
    ///   * `parentSwitchUID` points at the parent's UID.
    ///   * `routeString` low byte is the parent's downstream port number
    ///     leading to this child (not the child's own port number).
    ///   * `upstreamPortNumber` is the child's OWN port number for its
    ///     upstream link. Real partners often have this value at 3 even
    ///     when the parent connects through port 1.
    private func partnerSwitch(
        parent: IOThunderboltSwitch,
        parentLanePortNumber: Int,
        supportedRaw: UInt8,
        partnerOwnUpstreamPortNumber: Int = 3
    ) -> IOThunderboltSwitch {
        let upstream = IOThunderboltPort(
            portNumber: partnerOwnUpstreamPortNumber, socketID: nil, adapterType: .lane,
            currentSpeed: .usb4Tb4, currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil,
            supportedSpeed: SupportedSpeedMask(rawValue: supportedRaw)
        )
        return IOThunderboltSwitch(
            id: parent.id + Int64(parentLanePortNumber),
            className: "IOThunderboltSwitchType5",
            vendorID: 9999,
            vendorName: "Partner",
            modelName: "Partner Device",
            routerID: 1,
            depth: 1,
            routeString: Int64(parentLanePortNumber),
            upstreamPortNumber: partnerOwnUpstreamPortNumber,
            maxPortNumber: 4,
            supportedSpeed: SupportedSpeedMask(rawValue: supportedRaw),
            ports: [upstream],
            parentSwitchUID: parent.id
        )
    }

    @Test("TB partner switch supplies the device cap (issue #190, Port 4)")
    func tbPartnerSwitchSuppliesDeviceCap() {
        // LaCie d2 TB3 scenario: TB3 partner (40 Gbps), no USB device, TB5
        // host (80 Gbps), 40 Gbps cable, link active at 40. Without the
        // partner-switch lookup the diagnostic had no device cap and
        // blamed the cable. With it: device = 40 from partner, cable = 40,
        // host = 80 → device limit, no cable blame.
        let host = hostSwitch(socketID: "1", supportedRaw: 0xE, activeSpeed: .usb4Tb4)
        let partner = partnerSwitch(parent: host, parentLanePortNumber: 1, supportedRaw: 0x8)   // TB3 only
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],   // 40 Gbps cable
            devices: [],                                  // TB-only device, no USB enum
            usb3Transports: [],
            cio: cio(cableSpeed: 3),                     // controller confirms 40
            thunderboltSwitches: [host, partner],
            tbActiveGbps: 40
        )
        guard let facts = diag?.facts else {
            Issue.record("expected a diagnostic, got nil")
            return
        }
        #expect(facts.deviceGbps == 40,
            "Expected 40 Gbps device cap from partner TB switch (TB3 mask). Got: \(String(describing: facts.deviceGbps))")
        if case .cableLimit = diag?.bottleneck {
            Issue.record("Expected device-side outcome, not cable blame: \(String(describing: diag?.bottleneck))")
        }
    }

    @Test("TB partner overrides a slow USB sub-device (issue #190, Ports 2/3)")
    func tbPartnerOverridesUSBSubDevice() {
        // WERO TBT4 hub scenario: TB4 partner (40 Gbps), but a 10 Gbps USB
        // hub IC inside the dock enumerates as a USB device. Active link is
        // 40 Gbps. Without the partner-switch lookup the diagnostic took
        // the USB device's 10 Gbps as the device cap and announced
        // "Device runs at 10 Gbps." With it: device = 40 from partner,
        // matching the 40 Gbps link → fine, no "10 Gbps" verdict.
        let host = hostSwitch(socketID: "1", supportedRaw: 0xE, activeSpeed: .usb4Tb4)
        let partner = partnerSwitch(parent: host, parentLanePortNumber: 1, supportedRaw: 0xC)   // TB3 + TB4
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],   // 40 Gbps cable
            devices: [device(speedRaw: 4)],              // 10 Gbps internal USB hub
            usb3Transports: [],
            cio: cio(cableSpeed: 3),                     // 40 Gbps
            thunderboltSwitches: [host, partner],
            tbActiveGbps: 40
        )
        guard let facts = diag?.facts else {
            Issue.record("expected a diagnostic, got nil")
            return
        }
        #expect(facts.deviceGbps == 40,
            "TB partner (40) must win over the internal USB hub IC (10). Got: \(String(describing: facts.deviceGbps))")
        // The link runs at the TB4 partner's cap (40 Gbps) against a TB5
        // host. That makes the device the (non-actionable) limit, which is
        // not a fault. The crucial thing is the *number*: 40, not 10.
        guard case .deviceLimit(let d) = diag?.bottleneck else {
            Issue.record("expected .deviceLimit at the partner's TB4 cap, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(d == 40, "Reported device limit should match the partner switch's mask, not the internal USB IC")
        #expect(diag!.isWarning == false, "A TB4 partner on a TB5 host is informational, not a warning")
    }

    @Test("Falls back to USB device speed when no TB partner switch present")
    func fallsBackToUSBDeviceWithoutPartner() {
        // Plain USB-C SSD: no TB partner, just a USB device at 10 Gbps.
        // The USB device cap should still drive the verdict.
        let host = hostSwitch(socketID: "1", supportedRaw: 0xE, activeSpeed: .usb4Tb4)
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],   // 40 Gbps cable
            devices: [device(speedRaw: 4)],              // 10 Gbps USB device
            usb3Transports: [usb3(signaling: 2)],        // active 10 Gbps
            cio: nil,
            thunderboltSwitches: [host]                  // host only, no partner
        )
        #expect(diag?.facts.deviceGbps == 10)
        guard case .deviceLimit(let d) = diag?.bottleneck else {
            Issue.record("expected .deviceLimit when only USB device present, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(d == 10)
    }

    @Test("Partner switch on a sibling lane port is not used for this port")
    func partnerSwitchOnOtherLaneIgnored() {
        // Controller hosts two user-visible USB-C ports on the same root.
        // Port-USB-C@1 has no partner. The sibling lane (socket "9") has
        // a TB5 partner. The diagnostic for socket "1" must not borrow
        // the sibling's partner; deviceGbps should fall back to USB.
        let socket1Lane = IOThunderboltPort(
            portNumber: 1, socketID: "1", adapterType: .lane,
            currentSpeed: .usb4Tb4, currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE)
        )
        let socket9Lane = IOThunderboltPort(
            portNumber: 9, socketID: "9", adapterType: .lane,
            currentSpeed: .usb4Tb4, currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE)
        )
        let root = IOThunderboltSwitch(
            id: 100,
            className: "IOThunderboltSwitchType7",
            vendorID: 1452,
            vendorName: "Apple Inc.",
            modelName: "Mac",
            routerID: 0,
            depth: 0,
            routeString: 0,
            upstreamPortNumber: 0,
            maxPortNumber: 16,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE),
            ports: [socket1Lane, socket9Lane],
            parentSwitchUID: nil
        )
        // Partner attached to the *sibling* lane (port 9), not port 1.
        let siblingPartner = partnerSwitch(parent: root, parentLanePortNumber: 9, supportedRaw: 0xE)
        let diag = DataLinkDiagnostic(
            port: makePort(),                             // Port-USB-C@1 → socket "1"
            identities: [],
            devices: [device(speedRaw: 4)],              // 10 Gbps USB device on this port
            usb3Transports: [usb3(signaling: 2)],
            cio: nil,
            thunderboltSwitches: [root, siblingPartner]
        )
        #expect(diag?.facts.deviceGbps == 10,
            "Sibling lane's TB partner must not be used as this port's device cap. Got: \(String(describing: diag?.facts.deviceGbps))")
    }

    // MARK: - Culprit priority on tied floors (issue #190, Port 1)

    @Test("Cable + device tied at the floor: blame device, not cable")
    func cableAndDeviceTiedAtFloorBlamesDevice() {
        // WERO TBT3 SSD scenario: TB3 device (40 Gbps), TB3 cable (40 Gbps
        // via controller), TB5 host (80 Gbps), active 40 Gbps. Both cable
        // and device are at the floor; replacing the cable would not
        // unlock more speed because the device caps there too. The verdict
        // must be device-side, not "cable is limiting."
        let host = hostSwitch(socketID: "1", supportedRaw: 0xE, activeSpeed: .usb4Tb4)
        let partner = partnerSwitch(parent: host, parentLanePortNumber: 1, supportedRaw: 0x8)   // TB3
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],   // 40 Gbps cable
            devices: [],
            usb3Transports: [],
            cio: cio(cableSpeed: 3),                     // 40 Gbps
            thunderboltSwitches: [host, partner],
            tbActiveGbps: 40
        )
        if case .cableLimit = diag?.bottleneck {
            Issue.record("Cable tied with device at 40 must not be blamed as the cable limit: got \(String(describing: diag?.bottleneck))")
        }
        guard case .deviceLimit(let d) = diag?.bottleneck else {
            Issue.record("expected .deviceLimit when cable + device tie at the floor, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(d == 40)
    }

    @Test("Partner switch matching uses routeString, not its own upstreamPortNumber")
    func partnerMatchingUsesRouteStringNotUpstreamPortNumber() {
        // Critical regression guard. Real partner switches report their
        // OWN upstream port number (3 on the Samsung C34J79x), which is
        // different from the parent host port they connect through (1).
        // Earlier drafts of this fix incorrectly matched against the
        // child's upstreamPortNumber and would not find the real partner.
        let host = hostSwitch(socketID: "1", supportedRaw: 0xE, activeSpeed: .usb4Tb4)
        let partner = partnerSwitch(
            parent: host,
            parentLanePortNumber: 1,                 // parent's downstream port is 1
            supportedRaw: 0x8,                        // TB3-class partner
            partnerOwnUpstreamPortNumber: 3          // partner's own upstream is 3 (Samsung pattern)
        )
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],
            devices: [],
            usb3Transports: [],
            cio: cio(cableSpeed: 3),
            thunderboltSwitches: [host, partner],
            tbActiveGbps: 40
        )
        #expect(diag?.facts.deviceGbps == 40,
            "Partner must be found by routeString (low byte == parent port number), not by upstreamPortNumber. Got: \(String(describing: diag?.facts.deviceGbps))")
    }

    @Test("Partner with empty supportedSpeed mask uses active TB rate")
    func partnerWithEmptyMaskUsesActiveRate() {
        // Defence-in-depth: a partner switch can be present but expose an
        // empty `supportedSpeed` mask (unrecognised bits, firmware that
        // doesn't populate the field). Falling back to USB devices would
        // re-introduce the "Device runs at 10 Gbps" bug whenever the dock
        // has a USB hub IC. Instead, the active negotiated TB rate is the
        // floor: the partner is at least that fast (it just negotiated).
        let host = hostSwitch(socketID: "1", supportedRaw: 0xE, activeSpeed: .usb4Tb4)
        let partner = partnerSwitch(
            parent: host,
            parentLanePortNumber: 1,
            supportedRaw: 0                          // empty mask
        )
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 3)],
            devices: [device(speedRaw: 4)],          // 10 Gbps USB IC behind the dock
            usb3Transports: [],
            cio: cio(cableSpeed: 3),
            thunderboltSwitches: [host, partner],
            tbActiveGbps: 40
        )
        #expect(diag?.facts.deviceGbps == 40,
            "Empty partner mask should fall back to the active TB rate (40), not the USB IC (10). Got: \(String(describing: diag?.facts.deviceGbps))")
    }

    // MARK: - Cable sanity floor (issue #190 hardening)

    @Test("Resolved cable speed is floored at the active negotiated rate")
    func cableSpeedFlooredAtActiveRate() {
        // Adversarial scenario: e-marker correctly reports 80 Gbps, link
        // is actually running at 80, but the controller's cableSpeed
        // reading is stale at 3 (40). With unconditional "CIO wins" the
        // cable cap would resolve to 40 even though the link is empirically
        // running at 80 -- physically impossible. The floor promotes the
        // resolved value to the active rate.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 4)],   // e-marker says 80
            devices: [],
            usb3Transports: [],
            cio: cio(cableSpeed: 3),                     // controller says 40 (suspect)
            tbActiveGbps: 80,                            // link is empirically 80
            hostMaxGbps: 80
        )
        #expect(diag?.facts.cableGbps == 80,
            "A cable carrying an 80 Gbps link must resolve to at least 80, regardless of what the controller's stale reading claims. Got: \(String(describing: diag?.facts.cableGbps))")
    }

    @Test("Cable is unique floor: still blame cable")
    func cableUniqueFloorStillBlamesCable() {
        // 5 Gbps cable, 20 Gbps device, 20 Gbps host, active 5 Gbps.
        // Cable is the only thing at the floor; the priority swap must
        // not stop it from being identified as the actionable culprit.
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [cableEmarker(speedCode: 1)],   // 5 Gbps
            devices: [device(speedRaw: 5)],              // 20 Gbps
            usb3Transports: [usb3(signaling: 1)],        // active 5 Gbps
            cio: nil,
            hostMaxGbps: 20
        )
        guard case .cableLimit = diag?.bottleneck else {
            Issue.record("expected .cableLimit when cable is the unique floor, got \(String(describing: diag?.bottleneck))")
            return
        }
    }

    @Test("Explicit hostMaxGbps wins over the inference")
    func explicitHostMaxGbpsWins() {
        // Caller passes 5 Gbps explicitly even though the switch graph
        // would infer 40. The explicit value should be honoured (test seam).
        let host = hostSwitch(socketID: "1", supportedRaw: 0xC, activeSpeed: .usb4Tb4)
        let diag = DataLinkDiagnostic(
            port: makePort(),
            identities: [],
            devices: [],
            usb3Transports: [usb3(signaling: 2)],
            cio: nil,
            thunderboltSwitches: [host],
            hostMaxGbps: 5
        )
        #expect(diag?.facts.hostGbps == 5)
    }
}
