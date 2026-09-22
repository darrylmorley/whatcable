import Foundation
import Testing
@testable import WhatCableCore

/// Golden-output regression net for the formatter per-port assembly migration.
///
/// Four fixture snapshots are rendered through both public formatters and
/// compared byte for byte against checked-in expected output. The point is
/// brittleness: while the three private per-port assembly copies are
/// migrated onto `CableSnapshotContext`, ANY difference in rendered output
/// is a regression until someone deliberately decides otherwise.
///
/// Regenerating: `WC_REGENERATE_GOLDEN=1 swift test --filter FormatterGoldenOutput`
/// rewrites every golden file and the run reports the rewrite as a failure,
/// so a regeneration can never be mistaken for a pass. Re-read the diff
/// before committing regenerated files.
///
/// The app version is normalised out of the compared text: it is "dev"
/// under `swift test` but a real version inside the app bundle, and it says
/// nothing about per-port assembly.
struct FormatterGoldenOutputTests {

    private static let goldenDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("golden")

    private static var isRegenerating: Bool {
        ProcessInfo.processInfo.environment["WC_REGENERATE_GOLDEN"] == "1"
    }

    /// Normalises only the JSON `"version"` field's delimited value, never a
    /// bare substring match. `AppInfo.version` is `"dev"` under `swift test`,
    /// and a naive `text.replacingOccurrences(of: AppInfo.version, ...)`
    /// rewrites every occurrence of "dev" anywhere in the output, including
    /// inside the word "device" in hardware-controlled strings: the checked-in
    /// goldens used to contain the JSON key `"device"` written as
    /// `"<version>ice"`. The .txt output carries no version string at all
    /// (measured: zero `<version>` occurrences in any checked-in .txt golden
    /// before this fix), so it is left untouched entirely rather than run
    /// through a substitution that can only ever corrupt it.
    private func normalise(_ text: String, fileName: String) -> String {
        guard fileName.hasSuffix(".json") else { return text }
        // Anchored to the top-level line (2-space indent, JSONEncoder's
        // .sortedKeys + .prettyPrinted format), not just the first match
        // anywhere in the file. An unanchored match takes whichever
        // "version" : "..." comes first; top-level keys are emitted sorted,
        // so "ports" precedes "version", and a port's rawProperties is a
        // hardware-controlled dictionary rendered as a nested object. A
        // machine (or a future fixture) with an IOKit property literally
        // named "version" would have that hardware string rewritten while
        // the real version field kept the build's actual version: the same
        // class of bug this function's naive-substring predecessor had,
        // narrower.
        guard let range = text.range(of: #"(?m)^  "version" : ".*?""#, options: .regularExpression) else {
            return text
        }
        return text.replacingCharacters(in: range, with: "  \"version\" : \"<version>\"")
    }

    /// Compares `rendered` against the golden file, or writes it when
    /// regenerating. Returns nothing: it records the Issue itself so the
    /// caller reads as a plain list of surfaces.
    private func compare(_ rendered: String, fileName: String) throws {
        let url = Self.goldenDirectory.appendingPathComponent(fileName)
        let actual = normalise(rendered, fileName: fileName)
        if Self.isRegenerating {
            try FileManager.default.createDirectory(
                at: Self.goldenDirectory, withIntermediateDirectories: true)
            try actual.write(to: url, atomically: true, encoding: .utf8)
            Issue.record("Regenerated golden file \(fileName). Review the diff, then re-run without WC_REGENERATE_GOLDEN.")
            return
        }
        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record("Missing golden file \(fileName). Run WC_REGENERATE_GOLDEN=1 swift test --filter FormatterGoldenOutput to create it.")
            return
        }
        #expect(actual == expected, "\(fileName): rendered output differs from the golden file")
    }

    @Test("Golden: every fixture renders identically through JSONFormatter")
    func jsonGoldenOutputUnchanged() throws {
        for fixture in Self.fixtures {
            let snapshot = fixture.snapshot
            let rendered = try JSONFormatter.render(
                ports: snapshot.ports,
                sources: snapshot.powerSources,
                identities: snapshot.identities,
                showRaw: fixture.showRaw,
                adapter: snapshot.adapter,
                thunderboltSwitches: snapshot.thunderboltSwitches,
                isDesktopMac: snapshot.isDesktopMac,
                batteryFullyCharged: snapshot.batteryFullyCharged,
                batteryIsCharging: snapshot.batteryIsCharging,
                federatedIdentities: snapshot.federatedIdentities,
                usb3Transports: snapshot.usb3Transports,
                trmTransports: snapshot.trmTransports,
                cioCapabilities: snapshot.cioCapabilities,
                usbDevices: snapshot.usbDevices,
                displayPorts: snapshot.displayPorts
            )
            try compare(rendered, fileName: "\(fixture.name).json")
        }
    }

    @Test("Golden: every fixture renders identically through TextFormatter")
    func textGoldenOutputUnchanged() throws {
        for fixture in Self.fixtures {
            let snapshot = fixture.snapshot
            let rendered = TextFormatter.render(
                ports: snapshot.ports,
                sources: snapshot.powerSources,
                identities: snapshot.identities,
                showRaw: fixture.showRaw,
                adapter: snapshot.adapter,
                thunderboltSwitches: snapshot.thunderboltSwitches,
                isDesktopMac: snapshot.isDesktopMac,
                batteryFullyCharged: snapshot.batteryFullyCharged,
                batteryIsCharging: snapshot.batteryIsCharging,
                federatedIdentities: snapshot.federatedIdentities,
                usb3Transports: snapshot.usb3Transports,
                trmTransports: snapshot.trmTransports,
                cioCapabilities: snapshot.cioCapabilities,
                usbDevices: snapshot.usbDevices,
                displayPorts: snapshot.displayPorts
            )
            try compare(rendered, fileName: "\(fixture.name).txt")
        }
    }

    /// A guard against a vacuous pass: an empty fixture list, a fixture with
    /// no ports, or an empty golden file would make the two tests above
    /// succeed having compared nothing. Actually opens each golden file
    /// (skipped only while regenerating, when the files may not exist yet)
    /// rather than just asserting on the fixture inputs, so this test's own
    /// doc comment stays true of what it checks.
    @Test("Golden: the fixture set is non-empty and every golden file has content")
    func fixtureSetIsNotVacuous() throws {
        #expect(Self.fixtures.count == 6)
        for fixture in Self.fixtures {
            #expect(!fixture.snapshot.ports.isEmpty, "\(fixture.name): fixture has no ports")
            guard !Self.isRegenerating else { continue }
            for ext in ["json", "txt"] {
                let fileName = "\(fixture.name).\(ext)"
                let url = Self.goldenDirectory.appendingPathComponent(fileName)
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    Issue.record("Missing golden file \(fileName). Run WC_REGENERATE_GOLDEN=1 swift test --filter FormatterGoldenOutput to create it.")
                    continue
                }
                #expect(!contents.isEmpty, "\(fileName): golden file is empty")
            }
        }
    }

    // MARK: - Fixtures

    struct Fixture {
        let name: String
        let snapshot: CableSnapshot
        /// Rendered with `showRaw: true` when set. Only one fixture needs
        /// this: it is what makes the showRaw-gated blocks (raw IOKit
        /// properties, the active-cable VDO2 view) part of the byte-for-byte
        /// comparison instead of dead code as far as this net is concerned.
        var showRaw: Bool = false
    }

    /// Five shapes, each chosen because it exercises a different part of
    /// the per-port assembly the three copies duplicate.
    static let fixtures: [Fixture] = [
        Fixture(name: "single-port-charging", snapshot: singlePortCharging()),
        Fixture(name: "two-port-standby-charger", snapshot: twoPortStandbyCharger()),
        Fixture(name: "bare-emarker-shadowing", snapshot: bareEmarkerShadowing()),
        Fixture(name: "magsafe-and-usbc", snapshot: magSafeAndUSBC()),
        Fixture(name: "thunderbolt-dock-with-devices", snapshot: thunderboltDockWithDevices(), showRaw: true),
        Fixture(name: "display-driven-timing", snapshot: displayDrivenTiming())
    ]

    /// One active USB-C port, a 140W adapter, a populated cable e-marker
    /// and a device identity. Exercises charger-wattage resolution and the
    /// ordinary cable / device split.
    private static func singlePortCharging() -> CableSnapshot {
        CableSnapshot(
            ports: [makePort(portNumber: 1, portType: "USB-C", connectionActive: true)],
            powerSources: [makeSource(portType: 2, portNumber: 1, winningMW: 100_000)],
            identities: [
                makeIdentity(portType: 2, portNumber: 1, endpoint: .sopPrime,
                             vdos: [0x1C60_05AC, 0, 0x720A_0100, 0x110A_2644]),
                makeIdentity(portType: 2, portNumber: 1, endpoint: .sop)
            ],
            usbDevices: [],
            adapter: AdapterInfo(watts: 140, isCharging: true, source: "AC"),
            usb3Transports: [makeUSB3(portKey: "2/1", signaling: 2)],
            trmTransports: [makeTRM(portKey: "2/1", transportType: "USB3")],
            cioCapabilities: [makeCIO(id: 1, portKey: "2/1", negotiatedLinkSpeed: 3)],
            displayPorts: [makeDisplayPort(parentPortType: 2, parentPortNumber: 1)],
            batteryFullyCharged: false,
            batteryIsCharging: true
        )
    }

    /// Two USB-C ports, only one holding a live contract. This is issue
    /// #264: the other port must read as a standby charger, which depends
    /// entirely on the machine-wide chargingPortKeys set.
    private static func twoPortStandbyCharger() -> CableSnapshot {
        CableSnapshot(
            ports: [
                makePort(portNumber: 1, portType: "USB-C", connectionActive: true),
                makePort(portNumber: 2, portType: "USB-C", connectionActive: true)
            ],
            powerSources: [
                makeSource(portType: 2, portNumber: 1, winningMW: 100_000),
                makeSource(portType: 2, portNumber: 2)
            ],
            identities: [
                makeIdentity(portType: 2, portNumber: 1, endpoint: .sopPrime,
                             vdos: [0x1C60_05AC, 0, 0x720A_0100, 0x110A_2644]),
                makeIdentity(portType: 2, portNumber: 2, endpoint: .sopPrime,
                             vdos: [0x1C60_05AC, 0, 0x720A_0100, 0x110A_2644])
            ],
            usbDevices: [],
            adapter: AdapterInfo(watts: 96, isCharging: true, source: "AC"),
            batteryFullyCharged: false,
            batteryIsCharging: true
        )
    }

    /// One port whose identity array puts a BARE SOP' (no VDOs) ahead of a
    /// POPULATED SOP''. This is the fixture that pins the e-marker
    /// selection difference this migration settles: JSONFormatter prefers the
    /// populated one today, TextFormatter and DashboardCommand take the
    /// first. Its golden files are expected to change in Task 5, and only
    /// there.
    private static func bareEmarkerShadowing() -> CableSnapshot {
        CableSnapshot(
            ports: [makePort(portNumber: 1, portType: "USB-C", connectionActive: true)],
            powerSources: [makeSource(portType: 2, portNumber: 1, winningMW: 60_000)],
            identities: [
                makeIdentity(portType: 2, portNumber: 1, endpoint: .sopPrime, vdos: []),
                makeIdentity(portType: 2, portNumber: 1, endpoint: .sopDoublePrime,
                             vdos: [0x1C60_05AC, 0, 0x720A_0100, 0x110A_2644]),
                makeIdentity(portType: 2, portNumber: 1, endpoint: .sop)
            ],
            usbDevices: [],
            adapter: AdapterInfo(watts: 67, isCharging: true, source: "AC"),
            displayPorts: [makeDisplayPort(parentPortType: 2, parentPortNumber: 1)],
            batteryFullyCharged: false,
            batteryIsCharging: true
        )
    }

    /// A MagSafe port alongside a USB-C port, both idle. Exercises the
    /// non-USB-C branch and the no-adapter / no-source path.
    private static func magSafeAndUSBC() -> CableSnapshot {
        CableSnapshot(
            ports: [
                makePort(portNumber: 1, portType: "USB-C", connectionActive: false),
                makePort(portNumber: 2, portType: "MagSafe 3", connectionActive: false)
            ],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil,
            batteryFullyCharged: nil,
            batteryIsCharging: nil
        )
    }

    /// A Thunderbolt dock on port @4: a native USB device attached
    /// directly, a tunnelled device structurally scoped to the same port by
    /// its apciecN root name, and a second tunnelled device no port claims
    /// at all, so both the per-port device tree and the flat fallback
    /// section render. Port @1 is a second, unrelated idle port. Port @5 is
    /// a third, identity-less data port: see its own comment below.
    ///
    /// This is the fixture the golden net was missing entirely: every other
    /// fixture passes usbDevices: [] and none passes thunderboltSwitches,
    /// so neither JSONFormatter's structurallyScopedIDs subtraction loop
    /// nor TextFormatter's switch from a structurallyScopedByPort map to
    /// per-context arrays was ever exercised. Rendered with showRaw: true
    /// so the raw-only blocks are covered too: the port @4 e-marker below
    /// is an active cable carrying VDO2 data, so this is also the only
    /// fixture whose golden reaches the active-cable VDO2 raw view, not
    /// just the raw IOKit properties block.
    private static func thunderboltDockWithDevices() -> CableSnapshot {
        let hostRoot = makeHostRootSwitch(id: 100, socketID: "4", acioRootName: "acio4")
        // Active cable (product type 4) with a populated VDO2 at index 4:
        // header, then two zero VDOs, the cable VDO, then VDO2 (optical +
        // retimer + isolated + non-zero temperature fields, so both the
        // "<v>degC" and the zero/em-dash branches of tempLabel are covered,
        // not just the zero one), mirroring TextFormatterTests's own
        // activeCableVDO2SectionAppearsInRawMode fixture.
        var vdo4: UInt32 = 0
        vdo4 |= UInt32(1) << 10  // optical
        vdo4 |= UInt32(1) << 9   // retimer
        vdo4 |= UInt32(1) << 2   // isolated
        vdo4 |= UInt32(85) << 24  // max operating temp, degrees C
        vdo4 |= UInt32(100) << 16 // shutdown temp, degrees C
        let vdo3: UInt32 = UInt32(0b011) | UInt32(2 << 5) | UInt32(1 << 13) | UInt32(0b10 << 11)
        let activeCableEmarker = makeIdentity(
            portType: 2, portNumber: 4, endpoint: .sopDoublePrime,
            vdos: [(4 << 27) | 0x05AC, 0, 0, vdo3, vdo4]
        )
        return CableSnapshot(
            ports: [
                makePort(portNumber: 1, portType: "USB-C", connectionActive: false),
                makeDataPort(serviceName: "Port-USB-C@4", portNumber: 4),
                // Identity-less: no identities target port @5, so its
                // e-marker bullet group renders in its EMPTY state (a
                // "state" string, no bullet lines). That shape existed
                // implicitly on @4 before this fixture's active-cable
                // identity was added; without a second data port, no golden
                // anywhere pins BulletGroup.state or the text renderer's
                // un-bulleted state line, even though a live port whose
                // cable returns no e-marker is a common configuration, not
                // an edge case. No Thunderbolt socket is associated with
                // @5, so it claims nothing structurally and does not affect
                // the device-attribution pinning above.
                makeDataPort(serviceName: "Port-USB-C@5", portNumber: 5)
            ],
            powerSources: [],
            identities: [activeCableEmarker],
            usbDevices: [
                makeNativeDevice(id: 10, controllerPortName: "Port-USB-C@4"),
                makeTunnelledDevice(id: 11, tunnelRootName: "apciec4",
                                    productName: "Dock Hub", locationID: 0x0310_0000),
                makeTunnelledDevice(id: 12, tunnelRootName: "apciec9",
                                    productName: "Orphan Hub", locationID: 0x0410_0000)
            ],
            adapter: nil,
            thunderboltSwitches: [hostRoot],
            batteryFullyCharged: nil,
            batteryIsCharging: nil
        )
    }

    // MARK: - Fixture builders
    //
    // Copied deliberately from CableSnapshotContextTests so this file
    // stands alone: a golden net that shares its inputs with the code
    // under test would move when that test file moves.

    private static func makePort(portNumber: Int, portType: String,
                                 connectionActive: Bool?) -> AppleHPMInterface {
        AppleHPMInterface(
            id: UInt64(portNumber),
            serviceName: "Port-\(portType)@\(portNumber)",
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: portType,
            portNumber: portNumber,
            connectionActive: connectionActive, activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [], transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            hpmControllerUUID: nil,
            rawProperties: ["PortType": portType == "USB-C" ? "2" : "17"]
        )
    }

    private static func makeSource(portType: Int, portNumber: Int,
                                   winningMW: Int? = nil) -> PowerSource {
        PowerSource(
            id: UInt64(portNumber), name: "USB-PD",
            parentPortType: portType, parentPortNumber: portNumber,
            options: [PowerOption(voltageMV: 20000, maxCurrentMA: 5000,
                                  maxPowerMW: winningMW ?? 100_000)],
            winning: winningMW.map {
                PowerOption(voltageMV: 20000, maxCurrentMA: 5000, maxPowerMW: $0)
            },
            hpmControllerUUID: nil)
    }

    private static func makeIdentity(portType: Int, portNumber: Int,
                                     endpoint: USBPDSOP.Endpoint,
                                     vdos: [UInt32] = []) -> USBPDSOP {
        USBPDSOP(id: UInt64(portNumber * 100 + endpoint.hashValue % 50 + vdos.count),
                 endpoint: endpoint,
                 parentPortType: portType, parentPortNumber: portNumber,
                 vendorID: 0x05AC, productID: 0x1, bcdDevice: 0, vdos: vdos,
                 specRevision: 3, hpmControllerUUID: nil)
    }

    private static func makeUSB3(portKey: String, signaling: Int) -> USB3Transport {
        USB3Transport(id: 1, portKey: portKey, signaling: signaling,
                      signalingDescription: nil, dataRole: nil,
                      hpmControllerUUID: nil)
    }

    private static func makeTRM(portKey: String, transportType: String) -> TRMTransport {
        TRMTransport(
            id: 1, portKey: portKey, transportType: transportType,
            state: nil, stateDescription: nil, transportRestricted: nil,
            transportSupervised: nil, identificationRestricted: nil,
            deviceLocked: nil, relaxedPeriod: nil, gracePeriodReason: nil,
            gracePeriodReasonDescription: nil, profile: nil,
            profileDescription: nil, cacheMiss: nil, tunnelled: nil,
            hpmControllerUUID: nil)
    }

    private static func makeCIO(id: UInt64, portKey: String,
                                negotiatedLinkSpeed: Int) -> CIOCableCapability {
        CIOCableCapability(
            id: id, portKey: portKey, cableGeneration: nil,
            negotiatedLinkSpeed: negotiatedLinkSpeed, generation: nil,
            asymmetricModeSupported: nil, legacyAdapter: nil,
            linkTrainingMode: nil, hpmControllerUUID: nil)
    }

    private static func makeDisplayPort(parentPortType: Int,
                                        parentPortNumber: Int) -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: DisplayPortLink(active: true, laneCount: 4, maxLaneCount: 4,
                                  linkRate: 20, tunneled: false, hpdState: 1),
            monitor: nil,
            parentPortType: parentPortType,
            parentPortNumber: parentPortNumber,
            hpmControllerUUID: nil
        )
    }

    /// The corpus's 27C1U-L (m3_macos26.6.2) on a USB-C port through a
    /// DisplayPort 1.2 HDMI converter, 2 lanes at HBR3, with macOS's statement
    /// about the driven timing attached: DSC list empty, all four link-side
    /// modes rated unsafe. Exercises the statement receipts, the cross-check
    /// and the `drivenTiming` JSON block end to end from the real EDID bytes.
    private static func displayDrivenTiming() -> CableSnapshot {
        CableSnapshot(
            ports: [makePort(portNumber: 1, portType: "USB-C", connectionActive: true)],
            powerSources: [],
            identities: [],
            usbDevices: [],
            adapter: nil,
            displayPorts: [makeDrivenDisplayPort(parentPortType: 2, parentPortNumber: 1)],
            batteryFullyCharged: nil,
            batteryIsCharging: nil
        )
    }

    /// `Metadata.EDID` of m3_macos26.6.2 block 0, 256 bytes.
    private static let edid27C1UL: [UInt8] = EDIDInfoTests.hexBytes(
        "00ffffffffffff0025e3ffff0000000022210103803c22782e7885ad4f3bb3260e50542d6b80d1c0b30095008180714f81c08140a9c031ce0046f0705a8008204a0055502100001a000000fd00284b28843c000a202020202020000000fc0032374331552d4c002020202020000000ff003030303030303030303030303101ae"
        + "020332f24c0102030405111213141f019023097f07830100006a030c001000384220000067d85dc401788003e20f00e20e61565e00a0a0a029503020350055502100001a023a801871382d403020350055502100001a0000000000000000000000000000000000000000000000000000000000000000000000000000000000ca")

    private static func makeDrivenDisplayPort(parentPortType: Int, parentPortNumber: Int) -> IOPortTransportStateDisplayPort {
        func colour(_ id: Int, _ encoding: DisplayPixelEncoding, _ depth: Int, virtual: Bool = false) -> DisplayColourMode {
            DisplayColourMode(id: id, encoding: encoding, depth: depth, supportsDSC: 0, isVirtual: virtual, downstreamFormat: nil)
        }
        let lists = DisplayTimingLists(
            colourModes: [colour(90, .rgb444, 8), colour(89, .rgb444, 8), colour(91, .ycbcr444, 8), colour(92, .ycbcr444, 8),
                          colour(10, .ycbcr422, 12, virtual: true), colour(11, .ycbcr422DPTunneling, 12, virtual: true)],
            dscRequiredList: [], unsafeList: [90, 89, 91, 92, 10, 11], validPixelEncodings: 0x1b4d, colourModesComplete: true, dscListComplete: true, unsafeListComplete: true)
        let statement = DisplayTimingStatement(
            driven: lists,
            allTimings: [DisplayNodeTiming(id: 45, width: 3840, height: 2160, refreshHz: 60.0, pixelClockHz: 527_850_000, lists: lists)])
        return IOPortTransportStateDisplayPort(
            link: DisplayPortLink(active: true, laneCount: 2, maxLaneCount: 2, linkRate: 4,
                                  linkRateDescription: "8.1 Gbps (HBR3)", tunneled: false, hpdState: 1),
            monitor: MonitorInfo(manufacturerName: "IOC", productName: "27C1U-L", productId: 65535, serialNumber: 0,
                                 yearOfManufacture: 2023, edid: Data(edid27C1UL)),
            dfpType: "HDMI", branchDeviceId: "Dp1.2",
            parentPortType: parentPortType, parentPortNumber: parentPortNumber,
            currentMode: DisplayCurrentMode(width: 3840, height: 2160, refreshHz: 60, bitsPerComponent: 8, pixelClockHz: 527_850_000),
            drivenTiming: statement,
            hpmControllerUUID: nil
        )
    }

    /// A port that carries data, so the Thunderbolt socket lookup runs.
    /// Shaped like the fixture in CableSnapshotContextTests.
    private static func makeDataPort(serviceName: String, portNumber: Int) -> AppleHPMInterface {
        AppleHPMInterface(
            id: UInt64(portNumber),
            serviceName: serviceName,
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: "USB-C",
            portNumber: portNumber,
            connectionActive: true, activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            transportsActive: ["CC", "USB3", "CIO"],
            transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: ["PortType": "2"]
        )
    }

    private static func makeHostRootSwitch(id: Int64, socketID: String,
                                           acioRootName: String) -> IOThunderboltSwitch {
        let lane = IOThunderboltPort(
            portNumber: 1, socketID: socketID, adapterType: .lane,
            currentSpeed: .usb4Tb4, currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil, rawTargetSpeed: nil, linkBandwidthRaw: nil,
            hopTable: [])
        return IOThunderboltSwitch(
            id: id, className: "IOThunderboltSwitchType5", vendorID: 0x5AC,
            vendorName: "Apple Inc.", modelName: "Mac", routerID: 0, depth: 0,
            routeString: 0, upstreamPortNumber: 7, maxPortNumber: 7,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [lane],
            parentSwitchUID: nil, acioRootName: acioRootName)
    }

    private static func makeNativeDevice(id: UInt64, controllerPortName: String) -> USBDevice {
        USBDevice(
            id: id, locationID: 0x0100_0000, vendorID: 0x05AC, productID: 0x1234,
            vendorName: "Apple", productName: "Magic Keyboard", serialNumber: nil,
            usbVersion: nil, speedRaw: 2, busPowerMA: nil, currentMA: nil,
            controllerPortName: controllerPortName,
            deviceClass: 0x00, rawProperties: [:])
    }

    /// `productName` and `locationID` are parameters, not hardcoded, so two
    /// tunnelled devices in the same fixture render as distinguishable text
    /// and JSON. A golden net that gives them identical rendered fields
    /// pins the COUNT of devices per section, not WHICH device is in which
    /// section: a misrouting regression (structural join claiming the
    /// wrong device) would leave the golden byte-identical even though the
    /// count invariant it does check still holds.
    private static func makeTunnelledDevice(id: UInt64, tunnelRootName: String,
                                             productName: String, locationID: UInt32) -> USBDevice {
        USBDevice(
            id: id, locationID: locationID, vendorID: 0x05AC, productID: 0x1234,
            vendorName: nil, productName: productName, serialNumber: nil,
            usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
            isThunderboltTunnelled: true, tunnelBridgeDepth: 2,
            tunnelRootName: tunnelRootName, tunnelCarrier: .usbTunnel,
            deviceClass: 0x09, rawProperties: [:])
    }
}
