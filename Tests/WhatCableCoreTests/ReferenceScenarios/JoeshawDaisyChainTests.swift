import Testing
@testable import WhatCableCore

/// Reference-scenario test anchored on the joeshaw daisy-chain dump at
/// [research/dumps/cio/135-joeshaw-cio-daisy-chain.md](../../../research/dumps/cio/135-joeshaw-cio-daisy-chain.md).
///
/// **Topology** (from the source dump):
/// M2 Pro MacBook Pro → ASUS PA32QCV 6K monitor (USB4, JHL8440, depth 1)
/// → CalDigit TS3 Plus (TB3, JHL6540, depth 2). The CIO block attaches
/// to the depth-1 ASUS hop (`Device Vendor Name = "ASUS-Display"`,
/// `Device Model Name = "PA32QCV"` at source lines 38 and 50), not the
/// terminal TS3 Plus. CIO reports the first hop, not the chain tail.
///
/// **Cable**: original Sumitomo TB3 cable, VID `0x20C2`. WhatCable's own
/// JSON output (embedded in the source dump at line 189) confirms:
/// `"Cable speed: USB 3.2 Gen 2 (10 Gbps)"`. That is USB-PD VDO speed
/// code 2.
///
/// **Bug class**: same issue #111 pattern as
/// [BluevulpineTS3DockTests.swift](BluevulpineTS3DockTests.swift)
/// (USB-only e-marker speed field, CIO confirms TB, no note since
/// the CIO-semantics change), but on a different real Mac
/// (M2 Pro, not the unspecified TB4-class machine) and with the added
/// daisy-chain complication. The CIO `Generation = 3` here (source
/// line 65) versus `Generation = 2` on bluevulpine: empirical evidence
/// the CIO `Generation` field is host-chip-dependent. The verdict is
/// not sensitive to that field, so this test is robust to that
/// observation.
///
/// **Synthesised vs from-dump**:
/// - **From the dump**: cable identity (Sumitomo, 10 Gbps e-marker per
///   WhatCable JSON line 189), CIO codes (lines 27, 52, 65), downstream
///   device (ASUS PA32QCV).
/// - **Synthesised**: port shape (standard M2 Pro USB-C), host max
///   (40 Gbps, since M2 Pro is TB4-class with `AsymmetricModeSupported = No`
///   per source line 30), active link rate (40 Gbps, consistent with
///   the WhatCable JSON's "Linked at up to 20 Gb/s × 2" bullet at
///   source line 185 = 40 Gbps full-duplex TB).
@Suite("Reference scenario: joeshaw M2 Pro + ASUS PA32QCV + CalDigit TS3 Plus")
struct JoeshawDaisyChainTests {

    private static func hostPort() -> AppleHPMInterface {
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

    /// CIO block from the ASUS PA32QCV depth-1 hop.
    /// Field origins (all from the source dump):
    /// - `CableSpeed = 3` (40 Gbps TB4-class) at line 52
    /// - `CableGeneration = 2` at line 27
    /// - `Generation = 3` at line 65 (M2 Pro host-tagged; not asserted)
    /// - `LinkTrainingMode = 2` at line 17
    /// - `AsymmetricModeSupported = No` at line 30
    /// - `LegacyAdapter = No` at line 64
    private static func asusCIO() -> CIOCableCapability {
        CIOCableCapability(
            id: 200,
            portKey: "2/1",
            cableGeneration: 2,
            negotiatedLinkSpeed: 3,
            generation: 3,
            asymmetricModeSupported: false,
            legacyAdapter: false,
            linkTrainingMode: 2
        )
    }

    private static func cableEmarker(speedCode: UInt32) -> USBPDSOP {
        let validLatency: UInt32 = 1 << 13
        let cableVDO = speedCode | (1 << 5) | validLatency
        let idHeader: UInt32 = 0x1800_0000
        return USBPDSOP(
            id: 2, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x20C2, productID: 0, bcdDevice: 0,
            vdos: [idHeader, 0, 0, cableVDO],
            specRevision: 0
        )
    }

    @Test("Sumitomo passive cable on M2 Pro daisy chain: controller's figure stands without a note")
    func sumitomoPassiveCable_ControllerWins() {
        // Sumitomo TB3 cable e-marker self-reports as 10 Gbps passive
        // (USB-PD VDO speed code 2). CIO controller at the depth-1 ASUS
        // hop reports CableSpeed = 3 (40 Gbps TB-capable). The
        // controller's figure is the cable figure; the USB-only field
        // is not a disagreement, so no note (CIO-semantics change; the flag used to
        // be set here). The link is genuinely at 40 Gbps
        // because the M2 Pro and the ASUS PA32QCV both negotiate TB4
        // (the WhatCable JSON in the dump confirms "Linked at up to
        // 20 Gb/s × 2").
        let diag = DataLinkDiagnostic(
            port: Self.hostPort(),
            identities: [Self.cableEmarker(speedCode: 2)],
            devices: [],
            usb3Transports: [],
            cio: Self.asusCIO(),
            tbActiveGbps: 40,
            hostMaxGbps: 40
        )

        guard case .fine(let active) = diag?.bottleneck else {
            Issue.record("expected .fine, got \(String(describing: diag?.bottleneck))")
            return
        }
        #expect(active == 40)
        #expect(diag!.cableSignalConflict == false,
            "A USB-only 10 Gbps e-marker field under CIO 40 is not a disagreement.")
        #expect(diag!.facts.cableEmarkerGbps == 10)
        #expect(diag!.facts.cableControllerGbps == 40)
        #expect(diag!.facts.cableGbps == 40,
            "Controller (40) is the cable figure over the USB-only e-marker field (10).")
        #expect(!diag!.detail.contains("disagree"),
            "Detail must not print a disagreement note: \(diag!.detail)")
    }
}
