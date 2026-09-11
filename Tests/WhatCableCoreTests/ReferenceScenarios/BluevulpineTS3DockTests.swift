import Testing
@testable import WhatCableCore

/// Reference-scenario tests anchored on the bluevulpine TS3 Plus + Samsung
/// monitor dump at
/// [research/dumps/cio/135-bluevulpine-cio-tb3-dock.md](../../../research/dumps/cio/135-bluevulpine-cio-tb3-dock.md).
///
/// Two scenarios share the same host (TB4-class MacBook Pro,
/// `AppleHPMInterfaceType10` era) and the same downstream device
/// (CalDigit TS3 Plus, `Device ID = 5587` Alpine Ridge JHL6540), with two
/// different cables attached on different days:
///
/// - Scenario 1, 2026-05-15: Lintes TB4 cable. E-marker reports
///   "USB4 Gen 3 (40 Gbps), passive". Same tier as the CIO controller,
///   no conflict.
/// - Scenario 2, 2026-05-20: original Sumitomo TB3 cable. E-marker
///   reports "USB 3.2 Gen 2 (10 Gbps), passive". CIO controller still
///   says 40 Gbps. The classic issue #111 shape: the cable is genuinely
///   TB-capable and its e-marker speed field describes USB data only.
///   The controller's figure is the cable figure and the verdict is
///   `.fine(40)`. It is not a disagreement (CIO-semantics change): a USB-only speed
///   field under a Thunderbolt link is normal (67 corpus ports), so
///   `cableSignalConflict = false` and no note is printed.
///
/// Both scenarios' CIO blocks are identical (see the comparison table
/// at lines 16-25 of the source dump). The CIO codes are
/// `CableSpeed = 3`, `CableGeneration = 1`, `Generation = 2`.
///
/// Notes on what is loaded from the dump versus what is synthesised:
/// - **From the dump:** the cable e-marker speed tier (per the prose
///   on lines 36-40 of the source), the CIO field values (per the
///   ioreg block at lines 50-108 of the source), the downstream device
///   identity (CalDigit TS3 Plus, JHL6540, TB3 silicon).
/// - **Synthesised:** the port shape (a standard TB4-class USB-C port
///   with the usual `transportsSupported` and `transportsActive`),
///   the host max (40 Gbps from `AppleHPMInterfaceType10` era), the
///   active link rate (40 Gbps, consistent with `CableSpeed = 3` and
///   the link actually coming up at TB4). These are not contentious
///   given the host class and the CIO confirmation; if the bluevulpine
///   submission ever includes a full port-controller dump we can wire
///   it in instead.
@Suite("Reference scenario: bluevulpine TS3 Plus + Samsung monitor")
struct BluevulpineTS3DockTests {

    // MARK: - Shared fixtures

    /// The host port for both scenarios. TB4-class USB-C with USB3 and
    /// CIO both active (the cable is genuinely doing Thunderbolt; the
    /// CIO block in the source confirms `TransportType = 4` (CIO) is
    /// active on Port-USB-C@1).
    private static func ts3HostPort() -> AppleHPMInterface {
        AppleHPMInterface(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: true,
            superSpeedActive: true,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            transportsActive: ["CC", "USB3", "CIO"],
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

    /// Shared CIO block. Identical across both bluevulpine scenarios
    /// per the comparison table at source lines 16-25.
    /// Field origins (all from the dump):
    /// - `CableSpeed = 3` (40 Gbps TB4-class) at source line 91
    /// - `CableGeneration = 1` at source line 66
    /// - `Generation = 2` at source line 104
    /// - `LinkTrainingMode = 1` at source line 55
    /// - `AsymmetricModeSupported = Yes` at source line 69
    /// - `LegacyAdapter = No` at source line 103
    private static func ts3CIO() -> CIOCableCapability {
        CIOCableCapability(
            id: 100,
            portKey: "2/1",
            cableGeneration: 1,
            negotiatedLinkSpeed: 3,
            generation: 2,
            asymmetricModeSupported: true,
            legacyAdapter: false,
            linkTrainingMode: 1
        )
    }

    /// USB-PD cable e-marker (SOP') with the given speed code in the
    /// low 3 bits of VDO[3]. Mirrors the `cableEmarker` helper in
    /// DataLinkDiagnosticTests so the encoded shape matches what the
    /// production VDO decoder expects (1 m valid latency, 3 A current,
    /// passive cable in the ID header).
    /// Speed codes: 0 = USB 2.0 (0.48 Gbps), 1 = USB 3.2 Gen 1 (5),
    /// 2 = USB 3.2 Gen 2 (10), 3 = USB4 Gen 3 (40), 4 = Gen 4 (80).
    private static func cableEmarker(speedCode: UInt32) -> USBPDSOP {
        let validLatency: UInt32 = 1 << 13
        let cableVDO = speedCode | (1 << 5) | validLatency
        let idHeader: UInt32 = 0x1800_0000
        return USBPDSOP(
            id: 2, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 0
        )
    }

    // MARK: - Scenario 1: Lintes TB4 cable (2026-05-15)

    @Test("Scenario 1: Lintes TB4 cable, no conflict, full 40 Gbps")
    func scenario1_LintesTB4Cable_NoConflict() {
        // Lintes TB4 cable e-marker reports "USB4 Gen 3 (40 Gbps), passive"
        // per the prose at source line 12. Speed code 3 in USB-PD VDO
        // encoding. CIO also reports CableSpeed = 3. Same tier, no
        // disagreement.
        let diag = DataLinkDiagnostic(
            port: Self.ts3HostPort(),
            identities: [Self.cableEmarker(speedCode: 3)],
            devices: [],
            usb3Transports: [],
            cio: Self.ts3CIO(),
            tbActiveGbps: 40,           // CableSpeed=3 confirms 40 Gbps link
            hostMaxGbps: 40             // AppleHPMInterfaceType10 = TB4-class
        )

        guard case .fine(let active) = diag?.bottleneck else {
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(active == 40)
        #expect(diag!.cableSignalConflict == false,
            "Lintes TB4 cable (40 Gbps e-marker) matches CIO (40 Gbps). No conflict expected.")
        #expect(diag!.facts.cableEmarkerGbps == 40)
        #expect(diag!.facts.cableControllerGbps == 40)
        #expect(diag!.facts.cableGbps == 40)
    }

    // MARK: - Scenario 2: Sumitomo TB3 cable (2026-05-20)

    @Test("Scenario 2: Sumitomo passive TB3 cable, controller's figure stands without a note (issue #111)")
    func scenario2_SumitomoPassiveCable_ControllerWins() {
        // The textbook #111 case. Sumitomo cable e-marker self-reports
        // "USB 3.2 Gen 2 (10 Gbps), passive" per the prose at source
        // lines 36-37. Speed code 2 in USB-PD VDO encoding. CIO
        // controller still reports CableSpeed = 3 (40 Gbps) per source
        // line 91. The controller's figure is the cable figure. The
        // e-marker's field is USB-only, so this is not a disagreement
        // and no note is printed (CIO-semantics change; before it the flag was set).
        let diag = DataLinkDiagnostic(
            port: Self.ts3HostPort(),
            identities: [Self.cableEmarker(speedCode: 2)],
            devices: [],
            usb3Transports: [],
            cio: Self.ts3CIO(),
            tbActiveGbps: 40,
            hostMaxGbps: 40
        )

        guard case .fine(let active) = diag?.bottleneck else {
            Issue.record("expected .fine (CIO wins over passive e-marker), got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(active == 40)
        #expect(diag!.cableSignalConflict == false,
            "A USB-only e-marker speed field (10 Gbps) under CIO 40 is not a disagreement.")
        #expect(diag!.facts.cableEmarkerGbps == 10)
        #expect(diag!.facts.cableControllerGbps == 40)
        #expect(diag!.facts.cableGbps == 40,
            "Controller (40) is the cable figure over the USB-only e-marker field (10). Got: \(String(describing: diag!.facts.cableGbps))")
        // No note: the user is not told the two readings disagree,
        // because they do not describe the same thing.
        #expect(!diag!.detail.contains("disagree"),
            "Detail must not print a disagreement note: \(diag!.detail)")
    }

    // MARK: - Cross-scenario cross-field consistency

    @Test("Both scenarios produce non-contradictory verdicts (bigskookum-class)")
    func bothScenariosNonContradictory() {
        // bigskookum-class guard at the reference level: a `.fine`
        // verdict that claims "full data speed" must never coexist
        // with a cable-speed figure that is materially lower than the
        // active rate in the same diagnostic's facts. The conflict-
        // resolution path is supposed to surface the higher cable
        // figure on a cross-tier disagreement (issue #111). If a
        // future change to conflict resolution ever swapped to the
        // lower e-marker reading without flipping the bottleneck case,
        // this test catches it.
        for (label, speedCode) in [("Lintes TB4", UInt32(3)), ("Sumitomo TB3", UInt32(2))] {
            let diag = DataLinkDiagnostic(
                port: Self.ts3HostPort(),
                identities: [Self.cableEmarker(speedCode: speedCode)],
                devices: [],
                usb3Transports: [],
                cio: Self.ts3CIO(),
                tbActiveGbps: 40,
                hostMaxGbps: 40
            )
            guard let facts = diag?.facts else {
                Issue.record("\(label): expected a diagnostic")
                continue
            }
            if case .fine(let active) = diag!.bottleneck, let cable = facts.cableGbps {
                #expect(cable >= active,
                    "\(label): .fine(\(active)) with cable=\(cable) Gbps below the active rate is a contradiction (bigskookum class). Either the verdict should not be .fine, or the resolved cable figure should reflect the controller's confirmation.")
            }
        }
    }
}
