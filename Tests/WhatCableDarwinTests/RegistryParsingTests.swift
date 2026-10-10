import Foundation
import Testing
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

@Suite("Registry parsing")
struct RegistryParsingTests {
    @Test("AppleHPMInterfaceWatcher scans M4 Mini front port class")
    func appleHPMInterfaceWatcherScansM4MiniFrontPortClass() {
        #expect(AppleHPMInterfaceWatcher.candidateClasses.contains("IOPort"))
    }

    @Test("AppleHPMInterfaceWatcher extracts busIndex across controller name shapes")
    func appleHPMInterfaceWatcherExtractsBusIndexAcrossControllerNameShapes() {
        #expect(AppleHPMInterfaceWatcher.busIndex(fromRegistryName: "hpm4@3") == 4)
        #expect(AppleHPMInterfaceWatcher.busIndex(fromRegistryName: "atc1") == 1)
        #expect(AppleHPMInterfaceWatcher.busIndex(fromRegistryName: "usb-drd2@2280000") == 2)
        #expect(AppleHPMInterfaceWatcher.busIndex(fromRegistryName: "hpm@3") == nil)
        #expect(AppleHPMInterfaceWatcher.busIndex(fromRegistryName: "AppleT6000USBXHCI") == nil)
    }

    @Test("AppleHPMInterfaceWatcher extracts location fallback as hex")
    func appleHPMInterfaceWatcherExtractsLocationFallbackAsHex() {
        #expect(AppleHPMInterfaceWatcher.busIndex(fromLocation: "1") == 1)
        #expect(AppleHPMInterfaceWatcher.busIndex(fromLocation: "0A") == 10)
        #expect(AppleHPMInterfaceWatcher.busIndex(fromLocation: "") == nil)
        #expect(AppleHPMInterfaceWatcher.busIndex(fromLocation: "Port-USB-C") == nil)
    }

    @Test("USBWatcher parses usbIOPort string and Data")
    func usbWatcherParsesUsbIOPortStringAndData() {
        let path = "AppleARMIO/Port-USB-C@1"
        #expect(USBWatcher.usbIOPortPath(from: path) == path)

        let data = Data("AppleARMIO/Port-USB-C@2\u{0}".utf8)
        #expect(USBWatcher.usbIOPortPath(from: data) == "AppleARMIO/Port-USB-C@2")
    }

    @Test("USBWatcher extracts port name and bus index")
    func usbWatcherExtractsPortNameAndBusIndex() {
        #expect(
            USBWatcher.portName(fromUSBIOPortPath: "AppleARMIO/Port-USB-C@1") ==
            "Port-USB-C@1"
        )
        #expect(USBWatcher.portName(fromUSBIOPortPath: "AppleARMIO/AppleUSBHostPort@1") == nil)
        #expect(USBWatcher.busIndex(fromLocationID: 0x0300_0000) == 3)
    }

    @Test("Front-port gate: native + not-tunnelled + no-port-name + internal hub qualifies (issues #348, #373)")
    func behindInternalHubStructuralGate() {
        // The one true case: a device that reached a native controller, is not
        // tunnelled, matched no Port-USB-C@N node, and hangs off the Mac's own
        // internal hub. This is a desktop front-panel device.
        #expect(
            USBWatcher.classifyBehindInternalHub(
                reachedNativeController: true, tunnelled: false, portName: nil, underInternalHub: true
            ) == true
        )

        // Issue #373: a device behind an EXTERNAL hub. It can also reach the
        // native controller with no port name, so the first three conditions
        // pass, but its hub is external (USBPortType != internal), so it must
        // NOT be grouped as built-in.
        #expect(
            USBWatcher.classifyBehindInternalHub(
                reachedNativeController: true, tunnelled: false, portName: nil, underInternalHub: false
            ) == false
        )

        // Back-port device: has a UsbIOPort ancestor, so portName is set.
        #expect(
            USBWatcher.classifyBehindInternalHub(
                reachedNativeController: true, tunnelled: false, portName: "Port-USB-C@2", underInternalHub: true
            ) == false
        )

        // Thunderbolt-tunnelled device: reached AppleUSBXHCITR, never a native
        // controller. Both the tunnelled flag and the missing native controller
        // independently disqualify it, so the two device sets can't overlap.
        #expect(
            USBWatcher.classifyBehindInternalHub(
                reachedNativeController: false, tunnelled: true, portName: nil, underInternalHub: false
            ) == false
        )
        // Defensive: even if a future walk somehow set both, tunnelled wins.
        #expect(
            USBWatcher.classifyBehindInternalHub(
                reachedNativeController: true, tunnelled: true, portName: nil, underInternalHub: true
            ) == false
        )

        // Walk never reached any controller (e.g. the 20-hop bound was hit):
        // fail safe, do not classify as front-port.
        #expect(
            USBWatcher.classifyBehindInternalHub(
                reachedNativeController: false, tunnelled: false, portName: nil, underInternalHub: true
            ) == false
        )

        // The internal-hub port type constant matches Apple's
        // kIOUSBHostPortTypeInternal (validated against the corpus).
        #expect(USBWatcher.internalHubPortType == 2)
    }

    @Test("Thunderbolt 3 dock controllers are recognised, native/tunnel/Intel are not")
    func thunderboltDockControllerClassification() {
        // Third-party USB host controllers a TB3 dock supplies over its PCIe
        // tunnel. Every distinct class name observed in the customer-probe
        // corpus must be recognised so its devices surface (TS3+ support case).
        for dock in [
            "AppleUSBXHCIFL1100",
            "AppleASMediaUSBXHCI",
            "AppleASMedia1042USBXHCI",
            "AppleUSBXHCIAR",
        ] {
            #expect(USBWatcher.isThunderboltDockController(dock) == true, "\(dock) should be a dock controller")
        }

        // Apple-embedded board controllers: the Mac's own built-in plain-USB
        // wiring (Mac Studio front ports + back USB-A, M1 mini USB-A block).
        // These carried the dock classification until discussion #417 showed
        // that grouped a Studio's front ports under "reached through a
        // Thunderbolt dock"; they are their own category now.
        for embedded in [
            "AppleEmbeddedUSBXHCIASMedia3142",
            "AppleEmbeddedUSBXHCIFL1100",
        ] {
            #expect(USBWatcher.isThunderboltDockController(embedded) == false,
                "\(embedded) is the Mac's own wiring, not a dock (discussion #417)")
            #expect(USBWatcher.isEmbeddedBuiltInController(embedded) == true,
                "\(embedded) should classify as an embedded built-in controller")
        }
        // The dock variants of the same silicon stay docks and never read as
        // embedded: the prefix is the whole distinction.
        #expect(USBWatcher.isEmbeddedBuiltInController("AppleASMediaUSBXHCI") == false)
        #expect(USBWatcher.isEmbeddedBuiltInController("AppleUSBXHCIFL1100") == false)

        // Native Apple Silicon controllers: excluded by the AppleT prefix. The
        // M5 Pro/Max name ends in "AUSS", not "USBXHCI", so the suffix-based
        // native check misses it, but the AppleT prefix still keeps it out of
        // the dock branch (no false positive on built-in ports).
        for native in [
            "AppleT8103USBXHCI", "AppleT6000USBXHCI", "AppleT8112USBXHCI",
            "AppleT8122USBXHCI", "AppleT8132USBXHCI", "AppleT8142USBXHCI",
            "AppleT8140USBXHCI", "AppleT6050USBXHCIAUSS",
        ] {
            #expect(USBWatcher.isThunderboltDockController(native) == false, "\(native) is native, not a dock")
        }

        // The native USB tunnel (Studio Display / USB4 dock) is handled by its
        // own branch above this one, never as a dock controller.
        #expect(USBWatcher.isThunderboltDockController("AppleUSBXHCITR") == false)

        // Intel built-in controllers: unsupported, and excluded explicitly so a
        // theoretical enumeration can't be mistaken for a dock.
        #expect(USBWatcher.isThunderboltDockController("AppleIntelCNLUSBXHCI") == false)
        #expect(USBWatcher.isThunderboltDockController("AppleIntelICLUSBXHCI") == false)

        // Non-controller class names never match.
        #expect(USBWatcher.isThunderboltDockController("IOUSBHostDevice") == false)
        #expect(USBWatcher.isThunderboltDockController("AppleARMIODevice") == false)
    }

    @Test("PowerSourceWatcher handles built-in parent fields and priority fallback")
    func powerSourceWatcherHandlesBuiltInParentFieldsAndPriorityFallback() {
        let builtIn: [String: Any] = [
            "ParentBuiltInPortType": NSNumber(value: 0x11),
            "ParentBuiltInPortNumber": NSNumber(value: 2),
            "ParentPortType": NSNumber(value: 2),
            "ParentPortNumber": NSNumber(value: 1)
        ]
        let builtInParent = PowerSourceWatcher.parentPortIdentity(read: { builtIn[$0] })
        #expect(builtInParent.type == 0x11)
        #expect(builtInParent.number == 2)

        let priority: [String: Any] = [
            "ParentPortType": NSNumber(value: 0x11),
            "Priority": NSNumber(value: 0x0201)
        ]
        let priorityParent = PowerSourceWatcher.parentPortIdentity(read: { priority[$0] })
        #expect(priorityParent.type == 0x11)
        #expect(priorityParent.number == 1)
    }

    @Test("Charger-in watts policy: SMC rail wins, then gauge, then adapter, 0 on battery")
    func chargerInputWattsSelectionPolicy() {
        // On battery: always 0, regardless of any other reading.
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: false, smcWatts: 60, systemPowerInMilliwatts: 60_000, adapterWatts: 70) == 0)

        // Live SMC rail wins and rounds to the nearest watt (60.4 -> 60, 60.6 -> 61).
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: true, smcWatts: 60.4, systemPowerInMilliwatts: 30_000, adapterWatts: 70) == 60)
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: true, smcWatts: 60.6, systemPowerInMilliwatts: 30_000, adapterWatts: 70) == 61)

        // SMC absent or zero -> gauge (milliwatts) rounded to nearest watt.
        // 29_500 mW -> 30 W (29_500 + 500 = 30_000, /1000 = 30).
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: true, smcWatts: nil, systemPowerInMilliwatts: 29_500, adapterWatts: 70) == 30)
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: true, smcWatts: 0, systemPowerInMilliwatts: 29_499, adapterWatts: 70) == 29)

        // SMC and gauge both unusable -> rated adapter wattage.
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: true, smcWatts: nil, systemPowerInMilliwatts: nil, adapterWatts: 70) == 70)
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: true, smcWatts: 0, systemPowerInMilliwatts: 0, adapterWatts: 96) == 96)

        // Externally connected but nothing readable (charging paused, no adapter
        // wattage) -> 0. This is the case the menu bar hides on.
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: true, smcWatts: nil, systemPowerInMilliwatts: nil, adapterWatts: nil) == 0)
        #expect(PowerSourceWatcher.selectChargerInputWatts(
            externalConnected: true, smcWatts: 0, systemPowerInMilliwatts: 0, adapterWatts: 0) == 0)
    }

    @Test("USBPDSOP watcher handles MagSafe CC and SOP1 metadata")
    func usbPDSOPWatcherHandlesMagSafeCCAndSOP1Metadata() {
        let dict: [String: Any] = [
            "TransportTypeDescription": "CC",
            "ParentBuiltInPortType": NSNumber(value: 0x11),
            "ParentBuiltInPortNumber": NSNumber(value: 1),
            "Metadata": [
                "Vendor ID (SOP1)": NSNumber(value: 0x05AC),
                "Product ID (SOP1)": NSNumber(value: 0x1234),
                "bcdDevice": NSNumber(value: 0x0100)
            ]
        ]
        let metadata = USBPDSOPWatcher.metadataDictionary(read: { dict[$0] })
        let parent = USBPDSOPWatcher.parentPortIdentity(read: { dict[$0] })

        #expect(USBPDSOPWatcher.endpoint(read: { dict[$0] }) == .sopPrime)
        #expect(parent.type == 0x11)
        #expect(parent.number == 1)
        #expect(USBPDSOPWatcher.vendorID(read: { dict[$0] }, metadata: metadata) == 0x05AC)
        #expect(USBPDSOPWatcher.productID(read: { dict[$0] }, metadata: metadata) == 0x1234)
        #expect(USBPDSOPWatcher.bcdDevice(from: metadata) == 0x0100)
    }

    @Test("USBPDSOPWatcher handles built-in parent fields and priority fallback")
    func usbPDSOPWatcherHandlesBuiltInParentFieldsAndPriorityFallback() {
        // When both key variants are present with different values, the
        // BuiltIn variant must win so PD identity and power data resolve to
        // the same portKey (matches PowerSourceWatcher's order).
        let builtIn: [String: Any] = [
            "ParentBuiltInPortType": NSNumber(value: 0x11),
            "ParentBuiltInPortNumber": NSNumber(value: 2),
            "ParentPortType": NSNumber(value: 2),
            "ParentPortNumber": NSNumber(value: 1)
        ]
        let builtInParent = USBPDSOPWatcher.parentPortIdentity(read: { builtIn[$0] })
        #expect(builtInParent.type == 0x11)
        #expect(builtInParent.number == 2)

        let priority: [String: Any] = [
            "ParentPortType": NSNumber(value: 0x11),
            "Priority": NSNumber(value: 0x0201)
        ]
        let priorityParent = USBPDSOPWatcher.parentPortIdentity(read: { priority[$0] })
        #expect(priorityParent.type == 0x11)
        #expect(priorityParent.number == 1)
    }

    // MARK: - HPMPortUUIDMap.from(ports:)

    /// `from(ports:)` must build the same UUID -> portKey map that `current()`
    /// builds from IOKit, just from already-captured ports instead of a second
    /// IOKit sweep. The test covers the normal case (UUID present) and confirms
    /// the normalisation (dashes stripped, lowercase) used to match SMC DxUI.
    @Test("HPMPortUUIDMap.from(ports:) builds map from captured port UUIDs")
    func hpmPortUUIDMapFromPorts() {
        // Two ports with distinct UUIDs (the M3+ dashed form the watcher reads).
        let uuid1 = "7C30AF2D-CC71-7D20-5287-C77DB8476817"
        let uuid2 = "6230AF2D-EE59-552E-E28A-652CCC0E7B11"

        let port1 = AppleHPMInterface(
            id: 1, serviceName: "Port-USB-C@1", className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C",
            portNumber: 1, connectionActive: false,
            activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "CIO"],
            transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            hpmControllerUUID: uuid1,
            rawProperties: ["PortType": "2"]
        )
        let port2 = AppleHPMInterface(
            id: 2, serviceName: "Port-MagSafe 3@1", className: "AppleHPMInterfaceType11",
            portDescription: "Port-MagSafe 3@1", portTypeDescription: "MagSafe 3",
            portNumber: 1, connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: [], transportsActive: ["CC"], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            hpmControllerUUID: uuid2,
            rawProperties: [:]
        )

        let map = HPMPortUUIDMap.from(ports: [port1, port2])

        // UUIDs are normalised (dashes stripped, lowercase) as keys.
        let normalised1 = HPMPortUUIDMap.normalise(uuid1)
        let normalised2 = HPMPortUUIDMap.normalise(uuid2)
        #expect(map[normalised1] == "2/1",  "USB-C@1 must map to portKey 2/1")
        #expect(map[normalised2] == "17/1", "MagSafe@1 must map to portKey 17/1")
        #expect(map.count == 2)
    }

    /// Ports with no UUID (M1/M2 fallback or defensive nil) are skipped.
    /// The map must be empty rather than guessing positional mappings.
    @Test("HPMPortUUIDMap.from(ports:) is empty when no UUIDs present")
    func hpmPortUUIDMapFromPortsEmptyWithoutUUIDs() {
        let port = AppleHPMInterface(
            id: 1, serviceName: "Port-USB-C@1", className: "AppleTCControllerType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C",
            portNumber: 1, connectionActive: false,
            activeCable: nil, opticalCable: nil, usbActive: nil,
            superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3"],
            transportsActive: [], transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil,
            hpmControllerUUID: nil,    // M1/M2: no UUID
            rawProperties: ["PortType": "2"]
        )

        let map = HPMPortUUIDMap.from(ports: [port])
        #expect(map.isEmpty, "No positional guessing: empty map when UUIDs absent")
    }

    // MARK: - PCIe bridge depth for tunnelled devices

    /// Builds a bare `USBAncestor` for the bridge-walk tests: only
    /// `className` and `serviceName` matter to `tunnelBridgeAncestry`, so
    /// every other field is a harmless default.
    private func ancestor(className: String = "IOPP", serviceName: String?) -> USBWatcher.USBAncestor {
        USBWatcher.USBAncestor(
            className: className,
            locationID: nil,
            usbIOPortPath: nil,
            usbPortType: nil,
            conformsToUSBHostDevice: false,
            serviceName: serviceName
        )
    }

    /// The ground-truth shape (`research/customer-probes/m3pro_macos27.0_l`,
    /// issue #493's own reporter): the LaCie 1big sits 4 `pci-bridge` hops
    /// from `apciec2`. Path (child to parent, matching `collectAncestors`'
    /// order): AppleUSBXHCITR, IOPP, pci-bridge@2, IOPP, pci-bridge@0, IOPP,
    /// pci-bridge@1, IOPP, pci-bridge@0, IOPP, pcic2-bridge@0 (NOT counted:
    /// different name), AppleT8122PCIeC, apciec2.
    @Test("tunnelBridgeAncestry counts pci-bridge hops to the apciecN root (LaCie 1big shape)")
    func tunnelBridgeAncestryCountsLaCieShape() {
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleUSBXHCITR", serviceName: "AppleUSBXHCITR"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            // A DIFFERENT name ("pcic2-bridge", not "pci-bridge") sits once
            // per apciec root and is deliberately NOT counted: it's a fixed
            // structural element, not a variable measure of chain depth.
            ancestor(serviceName: "pcic2-bridge"),
            ancestor(serviceName: "AppleT8122PCIeC"),
            ancestor(serviceName: "apciec2"),
        ]
        let result = USBWatcher.tunnelBridgeAncestry(ancestors, from: 0)
        #expect(result?.bridgeDepth == 4)
        #expect(result?.rootName == "apciec2")
    }

    /// The Studio Display shape from the SAME machine, chained one level
    /// deeper (TB DROM `Depth` 3 vs the LaCie's 2): 6 `pci-bridge` hops, not
    /// 4. This is the second ground-truth data point that pins the
    /// "count doubles per depth level" relationship the Core-side join
    /// (`ChainDeviceAttribution`) depends on.
    @Test("tunnelBridgeAncestry counts pci-bridge hops to the apciecN root (Studio Display shape, one level deeper)")
    func tunnelBridgeAncestryCountsStudioDisplayShape() {
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleUSBXHCITR", serviceName: "AppleUSBXHCITR"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pcic2-bridge"),
            ancestor(serviceName: "AppleT8122PCIeC"),
            ancestor(serviceName: "apciec2"),
        ]
        let result = USBWatcher.tunnelBridgeAncestry(ancestors, from: 0)
        #expect(result?.bridgeDepth == 6)
        #expect(result?.rootName == "apciec2")
    }

    @Test("tunnelBridgeAncestry returns nil when the apciecN root is never reached")
    func tunnelBridgeAncestryNilWithoutRoot() {
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleUSBXHCITR", serviceName: "AppleUSBXHCITR"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            // Walk ends here: no apciecN root, e.g. replaying probe data that
            // stopped collecting at the old terminator.
        ]
        #expect(USBWatcher.tunnelBridgeAncestry(ancestors, from: 0) == nil)
    }

    @Test("classifyAncestry surfaces tunnelBridgeDepth and tunnelRootName for a tunnelled device")
    func classifyAncestrySurfacesTunnelBridgeDepth() {
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleUSBXHCITR", serviceName: "AppleUSBXHCITR"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "IOPP"),
            ancestor(serviceName: "pci-bridge"),
            ancestor(serviceName: "apciec0"),
        ]
        let classification = USBWatcher.classifyAncestry(ancestors)
        #expect(classification.tunnelled == true)
        #expect(classification.tunnelBridgeDepth == 2)
        #expect(classification.tunnelRootName == "apciec0")
        #expect(classification.carrier == .usbTunnel)
    }

    @Test("classifyAncestry leaves tunnelBridgeDepth nil for a non-tunnelled device")
    func classifyAncestryNilBridgeDepthWhenNotTunnelled() {
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleT8112USBXHCI", serviceName: "AppleT8112USBXHCI"),
        ]
        let classification = USBWatcher.classifyAncestry(ancestors)
        #expect(classification.tunnelled == false)
        #expect(classification.tunnelBridgeDepth == nil)
        #expect(classification.tunnelRootName == nil)
    }

    @Test("classifyAncestry: dock-controller tunnel with NO bridge chain (old capture / walk never reached apciecN) keeps nil depth+root but a PCIe carrier")
    func classifyAncestryNilBridgeDepthForDockController() {
        // The TB3-dock-own-controller branch (isThunderboltDockController)
        // with nothing recorded above the controller: a replay of an old
        // capture that stopped at the terminator, or a live walk that never
        // reached a strict apciecN within its bound. The failure invariant
        // (plan pcie-tunnelled-usb-attribution): still tunnelled, carrier
        // still .pcieTunnel (the terminator proves that much), depth and
        // root honestly nil, so the device stays fallback-eligible and is
        // never structurally claimed.
        let ancestors: [USBWatcher.USBAncestor] = [
            ancestor(className: "AppleUSBXHCIFL1100", serviceName: "AppleUSBXHCIFL1100"),
        ]
        let classification = USBWatcher.classifyAncestry(ancestors)
        #expect(classification.tunnelled == true)
        #expect(classification.tunnelBridgeDepth == nil)
        #expect(classification.tunnelRootName == nil)
        #expect(classification.carrier == .pcieTunnel)
    }
}
