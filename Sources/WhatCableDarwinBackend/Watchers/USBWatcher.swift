import Foundation
import IOKit
import IOKit.usb
import os
import WhatCableCore

@MainActor
public final class USBWatcher: ObservableObject {
    @Published public private(set) var devices: [USBDevice] = []

    // nonisolated so `classifyAncestry` (a nonisolated static pure function)
    // can log from off the main actor. Logger is a Sendable struct.
    nonisolated private static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "usb")

    /// Master switch for the one and only thing WhatCable puts on the USB bus:
    /// the Billboard BOS descriptor read in `makeDevice`. When false, that read
    /// is skipped and the app issues no USB control transfers at all.
    ///
    /// This backs the "Skip deep USB probing" compatibility setting (issue
    /// #429). Some KVM switches and USB hubs react to the BOS control transfer
    /// by resetting or flipping their relay. That re-enumerates the bus, which
    /// re-fires the probe, which flips it again: a self-sustaining loop (about
    /// one cycle per enumeration round-trip) that leaves the attached keyboard
    /// and mouse unusable. Turning this off breaks the loop on the next
    /// enumeration. It is read fresh on every device appearance, so flipping it
    /// at runtime takes effect immediately; all `USBWatcher` instances (menu
    /// bar, CLI snapshot, Pro diagnostics) honour the one value.
    ///
    /// Whether the Billboard/BOS descriptor read may be issued at all.
    ///
    /// Defaults FALSE so an unset gate fails closed. Fail-open is what made
    /// issue #571 possible: a watcher started before anything had decided would
    /// put traffic on the bus. Every real entry point sets this explicitly
    /// before starting a watcher (the app from `AppSettings`, the CLI from
    /// `--no-usb-probe`, the widget forces it off), so nobody loses the
    /// alt-mode data by this default; it only governs a path that forgot to
    /// decide, and such a path should be silent rather than probing.
    public static var probeBillboardDescriptors = false

    /// The Billboard/BOS read itself, injectable so tests can observe whether a
    /// control transfer was issued. Production keeps the real reader. This
    /// exists because "no probe happened" is otherwise unprovable: nothing logs
    /// the read, so its absence could only be argued from the absence of a line
    /// that never existed. Issue #571 is exactly a bug about a probe happening
    /// when it should not have.
    static var billboardReader: (io_service_t) -> BillboardCapability? = {
        BillboardDescriptorReader.read(from: $0)
    }

    /// Count of Billboard reads issued since it was last reset. Diagnostic only;
    /// nothing in production branches on it.
    static var billboardReadCount = 0

    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let addedCallback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<USBWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak watcher] in watcher?.handleAdded(iterator: iterator) }
        }

        let removedCallback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<USBWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak watcher] in watcher?.handleRemoved(iterator: iterator) }
        }

        // IOServiceAddMatchingNotification consumes one reference to the matching
        // dictionary, so call IOServiceMatching fresh for each registration.
        // Only drain the iterator when registration succeeds; the out-parameter
        // iterator is only valid on KERN_SUCCESS, and passing an uninitialised
        // value to IOIteratorNext is undefined behaviour.
        if IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            addedCallback,
            selfPtr,
            &addedIter
        ) == KERN_SUCCESS {
            handleAdded(iterator: addedIter)
        }

        if IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            IOServiceMatching("IOUSBHostDevice"),
            removedCallback,
            selfPtr,
            &removedIter
        ) == KERN_SUCCESS {
            handleRemoved(iterator: removedIter)
        }
    }

    public func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        devices.removeAll()
    }

    /// Rebuild the device list from what is attached right now, WITHOUT
    /// touching the notification registration.
    ///
    /// Needed when the probe gate opens after launch (issue #571): the devices
    /// already held were built with probing off, so they carry no alt-mode data.
    ///
    /// Deliberately not `stop()` then `start()`, which looks equivalent and is
    /// not. That path empties `devices` and republishes it, which every
    /// observer sees as a mass disconnect, and it destroys and recreates the
    /// notification port: if re-registration then failed, `notifyPort` would be
    /// left non-nil with nothing registered, so the `guard notifyPort == nil`
    /// in `start()` would suppress every future retry and USB watching would be
    /// dead for the rest of the process. This replaces the array in one
    /// assignment, so there is no empty intermediate and no teardown to fail.
    public func reenumerate() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOUSBHostDevice"),
            &iterator
        ) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        let rebuilt = wcDrainAllRetrying(iterator) { makeDevice(from: $0) }.compactMap { $0 }
        devices = rebuilt.sorted { ($0.productName ?? "") < ($1.productName ?? "") }
    }

    private func handleAdded(iterator: io_iterator_t) {
        let found = wcDrainAllRetrying(iterator) { service in makeDevice(from: service) }
        for device in found {
            guard let device, !devices.contains(where: { $0.id == device.id }) else { continue }
            devices.append(device)
        }
        devices.sort { ($0.productName ?? "") < ($1.productName ?? "") }
    }

    private func handleRemoved(iterator: io_iterator_t) {
        let removedEntryIDs = wcDrainAllRetrying(iterator) { service -> UInt64? in
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }
            return entryID
        }
        for entryID in removedEntryIDs {
            guard let entryID else { continue }
            devices.removeAll { $0.id == entryID }
        }
    }

    private func makeDevice(from service: io_service_t) -> USBDevice? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }

        // USBWatcher uses the bulk fetch intentionally: it iterates all keys
        // from the returned dictionary to populate `rawProperties` on USBDevice.
        // There is no fixed key list, so per-key reads are not feasible here.
        // USB device services are stable (not torn-down mid-read), so the
        // IOCFUnserializeBinary crash path described in issue #181 does not
        // apply. See also: AppleHPMInterfaceWatcher.makePort for the contrast.
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let vendorID = (dict["idVendor"] as? NSNumber)?.uint16Value ?? 0
        let productID = (dict["idProduct"] as? NSNumber)?.uint16Value ?? 0
        let locationID = (dict["locationID"] as? NSNumber)?.uint32Value ?? 0
        let speedRaw = (dict["Device Speed"] as? NSNumber)?.uint8Value
        let bcdUSB = (dict["bcdUSB"] as? NSNumber)?.uint16Value
        let busPower = (dict["Bus Power Available"] as? NSNumber).map { $0.intValue * 2 }
        let current = (dict["Requested Power"] as? NSNumber).map { $0.intValue * 2 }
        let deviceClass = (dict["bDeviceClass"] as? NSNumber)?.uint8Value

        // The leaf IOKit class. A Billboard device enumerates as
        // "AppleUSBHostBillboardDevice" (a subclass of IOUSBHostDevice, so the
        // matcher above still catches it). Used as a detection signal that
        // doesn't depend on the product-name string.
        // Only trust the buffer when the call succeeds; on failure IOKit does
        // not guarantee it leaves the buffer untouched, and USBDevice's
        // contract is that ioClassName is nil when unavailable.
        var classBuf = [CChar](repeating: 0, count: 128)
        let ioClassName = IOObjectGetClass(service, &classBuf) == KERN_SUCCESS
            ? String(cString: classBuf)
            : nil

        var raw: [String: String] = [:]
        for (k, v) in dict {
            raw[k] = stringify(v)
        }

        let (busIdx, portName, tunnelled, behindInternalHub, tunnelBridgeDepth, tunnelRootName, tunnelCarrier, tunnelControllerRegistryPath, tunnelAncestorEntryIDs) = controllerInfo(
            for: service,
            fallback: locationID,
            ownUSBPortType: (dict["USBPortType"] as? NSNumber)?.intValue,
            deviceClass: deviceClass
        )

        // Read the Billboard Capability Descriptor (advertised Alt Modes and
        // their per-mode state) once, here at device-appearance. One-shot
        // control transfer, no device-open.
        //
        // We probe every device deliberately, NOT just Billboard-class ones.
        // Functional docks, hubs and AV adapters advertise a Billboard
        // capability inside their ordinary BOS (seen on 103 such devices across
        // 71 machines in the customer-probe corpus), and the Pro Cable
        // Diagnostics screen surfaces those alt modes; gating to Billboard-class
        // devices would blank that table for them. The freeze in issue #370
        // came purely from a force-open fallback that no longer exists.
        //
        // The no-open read is safe on a device a kernel driver holds, but it is
        // NOT invisible: it is a real control transfer on the bus, and some KVM
        // switches and hubs react to it (issue #429). `probeBillboardDescriptors`
        // is the user's escape hatch for that; when off, we issue nothing.
        let billboard: BillboardCapability?
        if Self.probeBillboardDescriptors {
            Self.billboardReadCount += 1
            billboard = Self.billboardReader(service)
        } else {
            billboard = nil
        }

        return USBDevice(
            id: entryID,
            locationID: locationID,
            vendorID: vendorID,
            productID: productID,
            vendorName: dict["USB Vendor Name"] as? String,
            productName: dict["USB Product Name"] as? String,
            serialNumber: dict["USB Serial Number"] as? String,
            usbVersion: bcdUSB.map { formatBCD($0) },
            speedRaw: speedRaw,
            busPowerMA: busPower,
            currentMA: current,
            busIndex: busIdx,
            controllerPortName: portName,
            isThunderboltTunnelled: tunnelled,
            isBehindInternalHub: behindInternalHub,
            tunnelBridgeDepth: tunnelBridgeDepth,
            tunnelRootName: tunnelRootName,
            tunnelCarrier: tunnelCarrier,
            tunnelControllerRegistryPath: tunnelControllerRegistryPath,
            tunnelAncestorEntryIDs: tunnelAncestorEntryIDs,
            deviceClass: deviceClass,
            ioClassName: ioClassName,
            billboard: billboard,
            rawProperties: raw
        )
    }

    /// One hop of the IOService-plane parent walk above a USB device, as
    /// consumed by `classifyAncestry`. The live walk builds these in
    /// `collectAncestors`; the corpus sweep rebuilds them from probe 38
    /// captures (`38_usb_device_tree`), so the exact same classification code
    /// runs in production and against every recorded real machine.
    struct USBAncestor: Equatable, Sendable {
        /// IOKit class name (IOObjectGetClass).
        let className: String
        /// The ancestor's `locationID`, when it has one. Captured on every hop
        /// so the classification can take the bus index from whichever
        /// controller ends the walk.
        let locationID: UInt32?
        /// The ancestor's `UsbIOPort` registry path, already resolved from its
        /// String/Data raw form via `usbIOPortPath(from:)`. nil when absent.
        let usbIOPortPath: String?
        /// The ancestor's `USBPortType`. Only populated when the node conforms
        /// to `IOUSBHostDevice` (the hubs and devices), mirroring the
        /// conformance gate the live walk applies before reading the key.
        let usbPortType: Int?
        /// Whether the node conforms to `IOUSBHostDevice` at all, i.e. is a
        /// hub or device rather than port/controller plumbing. Used by the
        /// embedded-branch plumbing rule: a hub with NO conforming ancestor
        /// sits directly on the controller's root ports.
        let conformsToUSBHostDevice: Bool
        /// The ancestor's plain IOService-plane name (`IORegistryEntryGetName`),
        /// distinct from `className` (the driver class). Only meaningful above
        /// a tunnelled `AppleUSBXHCITR` controller, where the walk continues
        /// past the normal terminator to find the PCIe bridge chain up to the
        /// `apciecN` root: PCIe bridge nodes are named plain
        /// `"pci-bridge"`, and the root is named `"apciecN"` (the index baked
        /// into the name itself, no `@` suffix). nil only when the read fails.
        let serviceName: String?
        /// Registry entry ID of this ancestor node (`IORegistryEntryGetRegistryEntryID`).
        /// Captured on every hop; cheap, and needed by the Stage B instance-identity
        /// check (a Thunderbolt switch's PCIe up-adapter `pciEntryID` must be a
        /// member of the controller's ancestor entry IDs, not just a matching path
        /// string). nil only when the read fails.
        let entryID: UInt64?
        /// Full IOService-plane registry path of THIS node, captured ONLY when this
        /// ancestor is the walk terminator for a continuing tunnel (`walkContinuation`
        /// returns `.continueToPCIeRoot`). Captured at the terminator hit, before the
        /// continuation walk advances toward `apciecN`, per the capture-timing rule
        /// (`planning/pcie-tunnelled-usb-attribution.md`). nil for every other
        /// ancestor, and nil when the terminator's path read fails.
        let terminatorRegistryPath: String?

        // Explicit init (rather than relying on the synthesized memberwise
        // one) so existing test call sites built before `entryID` /
        // `terminatorRegistryPath` existed keep compiling unchanged: both
        // default to nil, matching "unknown" for older fixtures/replays.
        init(
            className: String,
            locationID: UInt32?,
            usbIOPortPath: String?,
            usbPortType: Int?,
            conformsToUSBHostDevice: Bool,
            serviceName: String?,
            entryID: UInt64? = nil,
            terminatorRegistryPath: String? = nil
        ) {
            self.className = className
            self.locationID = locationID
            self.usbIOPortPath = usbIOPortPath
            self.usbPortType = usbPortType
            self.conformsToUSBHostDevice = conformsToUSBHostDevice
            self.serviceName = serviceName
            self.entryID = entryID
            self.terminatorRegistryPath = terminatorRegistryPath
        }
    }

    /// The decisions `controllerInfo` derives from the parent walk.
    /// `reachedNativeController` is exposed alongside the four consumed values
    /// so tests and sweeps can assert on the gate itself, not just its effect.
    struct AncestryClassification: Equatable, Sendable {
        /// Upper byte of the terminating controller's `locationID`, or nil when
        /// the walk ended without reading one (caller falls back to the
        /// device's own locationID).
        let busIndex: Int?
        /// Physical port service name (e.g. "Port-USB-C@1") from the first
        /// `UsbIOPort` ancestor, or nil.
        let portName: String?
        /// The device reached the Mac over a Thunderbolt PCIe tunnel.
        let tunnelled: Bool
        /// The walk ended at a native Apple Silicon controller (`AppleT*USBXHCI`).
        let reachedNativeController: Bool
        /// The walk ended at an Apple-embedded board controller
        /// (`isEmbeddedBuiltInController`): the Mac's own extra built-in
        /// plain-USB wiring (discussion #417).
        let reachedEmbeddedController: Bool
        /// The device is on a desktop Mac's plain-USB built-in port, either
        /// via the no-port-node native path (issue #348) or behind an
        /// Apple-embedded board controller (discussion #417).
        let behindInternalHub: Bool
        /// Count of `"pci-bridge"`-named ancestors between the tunnelled
        /// `AppleUSBXHCITR` controller and its `apciecN` PCIe-C host bridge
        /// root, walked past the normal terminator. `nil` when the
        /// device is not tunnelled, or the walk never reached an `apciecN`
        /// root within the bound. Verified against ground-truth fixtures
        /// (`research/usb-chain-attribution-identifiers.md`): this count is
        /// always even on Apple Silicon and equals twice the TB DROM `Depth`
        /// of the switch that owns the tunnel (`ChainDeviceAttribution` does
        /// that division; this layer only captures the raw count).
        let tunnelBridgeDepth: Int?
        /// The `apciecN` root name (e.g. `"apciec2"`) the bridge walk ended
        /// at, or `nil` when not tunnelled or the root was not found.
        let tunnelRootName: String?
        /// Which tunnel kind carried a tunnelled device (`.usbTunnel` for
        /// `AppleUSBXHCITR`, `.pcieTunnel` for a dock-supplied PCIe xHCI).
        /// Always set when `tunnelled` is true on a live classification;
        /// `nil` otherwise. See `TunnelCarrier` in Core.
        let carrier: TunnelCarrier?
        /// Full IOService-plane registry path of the tunnel/dock controller,
        /// saved at the terminator hit. `nil` when not tunnelled, or the
        /// terminator's path read failed. See `USBAncestor.terminatorRegistryPath`.
        let tunnelControllerRegistryPath: String?
        /// Registry entry IDs from the controller up to (and including) the
        /// `apciecN` root, in walk order, starting with the controller's own
        /// entry ID. Empty when not tunnelled or no entry IDs were captured.
        let tunnelAncestorEntryIDs: [UInt64]
    }

    /// Classifies a USB device from its IOService-plane ancestor chain,
    /// collecting these pieces of information:
    ///   - `portName`: parsed from the first ancestor with a `UsbIOPort`
    ///     property. These are the `usb-drd*-port-hs/ss` nodes that sit
    ///     between the device and the `AppleT*USBXHCI` controller. Their
    ///     `UsbIOPort` value is a registry path ending in the physical port's
    ///     service name (e.g. ".../Port-USB-C@1").
    ///   - `busIndex`: upper byte of the XHCI controller's `locationID`, kept
    ///     as a fallback for older topologies that don't expose `UsbIOPort`
    ///     (and for the advanced view).
    ///   - `tunnelled`: the device reached the Mac over a Thunderbolt PCIe
    ///     tunnel. Either the chain runs through `AppleUSBXHCITR`, the native
    ///     USB tunnel (issue #274), or through a Thunderbolt 3 dock's own PCIe
    ///     USB host controller (`isThunderboltDockController`).
    ///   - `behindInternalHub`: the device is on a desktop Mac's plain-USB
    ///     front port. Detected structurally: the walk reaches a native
    ///     controller, is not tunnelled, and finds no `UsbIOPort` ancestor
    ///     (no `Port-USB-C@N` match). See the gate below the loop (issue #348).
    ///
    /// Pure: no IOKit. This is the seam that makes the walk replayable from
    /// probe 38 corpus captures (`USBWatcherCorpusSweepTests`); the live half
    /// is `collectAncestors`, which only gathers, never decides.
    /// - Parameter ownUSBPortType: the DEVICE's own `USBPortType` property
    ///   (the kind of port the device itself is plugged into), read from its
    ///   property dictionary in `makeDevice`. Used only in the embedded
    ///   branch: a value of `internalHubPortType` (2) means the device is
    ///   plugged into a port internal to the Mac's board, i.e. it IS the
    ///   Mac's own hub silicon, not something the user attached.
    /// - Parameter deviceClass: the device's own `bDeviceClass`. Used only in
    ///   the embedded branch: class 9 (hub) with no hub ancestor is the
    ///   Mac's own root fan-out silicon (see the plumbing rule below).
    nonisolated static func classifyAncestry(
        _ ancestors: [USBAncestor],
        ownUSBPortType: Int? = nil,
        deviceClass: UInt8? = nil
    ) -> AncestryClassification {
        var portName: String?
        var bus: Int?
        var tunnelled = false
        // Set when the walk lands on a *native* Apple Silicon USB host
        // controller (`AppleT*USBXHCI`), as opposed to the tunnelled
        // `AppleUSBXHCITR`. Used below to gate the internal-hub classification.
        var reachedNativeController = false
        // Set when the walk lands on an Apple-embedded third-party controller
        // (`AppleEmbedded*USBXHCI*`): built-in plain-USB wiring, see the
        // branch below.
        var reachedEmbeddedController = false
        // Set when ANY hub ancestor before the terminating controller reports
        // `internalHubPortType` (2), i.e. the walk passes through the Mac's own
        // internal front-panel hub on its way to the controller. `USBPortType`
        // reports the kind of port a hub is plugged into: the Mac's internal
        // hubs report 2, external hubs (docks, keyboard hubs) report 0.
        //
        // This is the whole-chain test, not the nearest-hub test the original
        // #373 fix used. A dock plugged into a desktop front port is an external
        // hub (its own devices' nearest hub is the dock, reporting 0), but the
        // chain still runs THROUGH the Mac's internal hub, so those devices
        // belong under "Built-in USB ports" (issue #430, @jimmyorz's M4 mini).
        // The nearest-hub test dropped them because their nearest hub was the
        // dock. The distinction that keeps #373 fixed: a device behind an
        // external hub on a REAR port never passes through the internal hub, so
        // this stays false for it. Both cases appear together in #430's dump.
        var passedInternalHub = false

        // Whether any ancestor before the terminating controller conforms to
        // IOUSBHostDevice, i.e. the device hangs off a hub rather than
        // sitting directly on the controller's root ports.
        var hasHubAncestor = false

        // Index of the terminating tunnel controller (either the native
        // `AppleUSBXHCITR` or a dock-supplied PCIe xHCI), when found. Used
        // after the loop to walk the remainder of `ancestors` (which, for both
        // tunnel cases, `collectAncestors` keeps gathering past the usual
        // terminator; see `walkContinuation`) and count the PCIe bridge chain
        // up to `apciecN`. `nil` for the native and embedded cases, which have
        // no such chain.
        var tunnelControllerIndex: Int?
        // Which tunnel kind the terminator proves; set alongside
        // `tunnelControllerIndex`.
        var carrier: TunnelCarrier?

        for (index, ancestor) in ancestors.enumerated() {
            if ancestor.conformsToUSBHostDevice { hasHubAncestor = true }
            if portName == nil, let portPath = ancestor.usbIOPortPath {
                if let name = Self.portName(fromUSBIOPortPath: portPath) {
                    portName = name
                } else {
                    // Found a `UsbIOPort` ancestor, but its path tail isn't a
                    // recognised `Port-*` node. Without a port name the device
                    // is later treated as port-less and, on a desktop, surfaced
                    // as a front-port device (issue #348). If a future Apple
                    // Silicon generation renames the port node, this is the
                    // silent failure mode; log it so it's diagnosable. The path
                    // is IOKit topology, not PII.
                    Self.log.debug("UsbIOPort path has no recognised port node: \(portPath, privacy: .public)")
                }
            }

            // Flag the internal hub anywhere in the chain, not just the nearest
            // one: a dock (external hub, value 0) plugged into a front port sits
            // between the device and the Mac's internal hub, so reading the
            // nearest hub only would miss the internal hub further up and drop
            // the dock's downstream devices (issue #430). `usbPortType` is only
            // populated for `IOUSBHostDevice` ancestors (the conformance gate in
            // `collectAncestors`), so this reads hubs, never port/controller
            // plumbing.
            if ancestor.usbPortType == Self.internalHubPortType {
                passedInternalHub = true
            }

            // The tunnelled host controller for devices behind a Thunderbolt
            // dock or display (issue #274). It plays the same role as the native
            // XHCI controller below, but reached over the TB PCIe tunnel, so we
            // flag the device and stop the walk at it. There is no `UsbIOPort`
            // on this path, so `portName` stays nil and the device matches no
            // physical port.
            if ancestor.className.hasPrefix("AppleUSBXHCITR") {
                tunnelled = true
                tunnelControllerIndex = index
                carrier = .usbTunnel
                if let loc = ancestor.locationID { bus = Self.busIndex(fromLocationID: loc) }
                break
            }
            if ancestor.className.hasPrefix("AppleT") && ancestor.className.hasSuffix("USBXHCI") {
                reachedNativeController = true
                if let loc = ancestor.locationID { bus = Self.busIndex(fromLocationID: loc) }
                break
            }
            // Apple-embedded third-party controller: the Mac's own extra
            // built-in plain-USB wiring (Mac Studio front ports and back
            // USB-A, M1 Mac mini USB-A block), soldered to the board but
            // driven by third-party silicon (`AppleEmbeddedUSBXHCIASMedia3142`,
            // `AppleEmbeddedUSBXHCIFL1100`). Before this branch existed these
            // fell through to the dock rule below and were wrongly grouped
            // under "reached through a Thunderbolt dock" (discussion #417 on
            // a Mac Studio). The `AppleEmbedded` prefix is Apple's own marker
            // for board-mounted controllers: across the whole customer-probe
            // corpus every `AppleEmbedded*` stop is a desktop Mac and no real
            // dock ever carries the prefix.
            if Self.isEmbeddedBuiltInController(ancestor.className) {
                reachedEmbeddedController = true
                // Like the dock branch below, deliberately no `locationID`
                // read: built-in devices are grouped by flag, never matched
                // by bus index, so `bus` is left to the caller's fallback.
                break
            }
            // A Thunderbolt 3 dock (e.g. CalDigit TS3+) brings its own PCIe USB
            // host controller rather than tunnelling USB natively, so its
            // downstream devices enumerate under a third-party XHCI driver class
            // (`AppleUSBXHCIFL1100`, `AppleASMediaUSBXHCI`, `AppleUSBXHCIAR`,
            // ...) instead of `AppleUSBXHCITR`. Those devices still reached the
            // Mac over the Thunderbolt PCIe tunnel and have no `UsbIOPort`
            // ancestor, so we flag them tunnelled and stop, exactly like the
            // native-tunnel case above. Confirmed on TS3+ hardware
            // (m4_macos27.0_c / m1pro_macos26.5.1_i in the customer-probe
            // corpus). We do not read `locationID` here: a tunnelled device is
            // attributed to its port by Thunderbolt topology, not bus index, so
            // `bus` is left to the caller's fallback.
            if Self.isThunderboltDockController(ancestor.className) {
                tunnelled = true
                tunnelControllerIndex = index
                carrier = .pcieTunnel
                break
            }
        }

        // Everything behind an embedded controller is a built-in plain-USB
        // port, so by default it belongs in the "Built-in USB ports" section
        // (issue #348 UX), not under a dock. Its `UsbIOPort` board node
        // (e.g. "Port-USB-A@1" / "Port-USB-C@5") is KEPT on the record exactly
        // as macOS reports it (owner rule: identifiers are never dropped; it is
        // raw registry truth and a research join key). On macOS 26+ that node
        // names the PHYSICAL port distinctly (Port-USB-C@5 vs @6, Port-USB-A@1
        // vs @2 on one controller, confirmed across the customer-probe corpus),
        // NOT a controller-wide shared node as an earlier reading here assumed.
        // So a built-in USB-only port card CAN attribute its device by an exact
        // name match (issue #456, `AppleHPMInterface.claimsInternalHubDevice`);
        // `TunnelledDeviceGrouping.group` subtracts any device a real port
        // claims so it renders exactly once (card OR Built-in USB ports, never
        // both). A device whose name resolves to no real port card (USB-A, or
        // older macOS where the name is absent) stays in the Built-in USB ports
        // section via the behindInternalHub flag, as before.
        //
        // One exclusion (raised across both PR 408 review rounds): the
        // embedded controller's own hub silicon also enumerates as USB
        // devices, and flagging THOSE would render the Mac's plumbing as
        // permanently connected devices in the card. Two hardware signals
        // identify plumbing, and BOTH are needed (verified over every
        // embedded chain in the 524-machine corpus: 16 plumbing exclusions,
        // all visibly Apple silicon; 33 user devices, all kept):
        //   - own `USBPortType == internalHubPortType` (2): Apple marks its
        //     internal hubs as plugged into board-internal ports (the
        //     Studio ASMedia fan-out hubs).
        //   - a hub-class device (bDeviceClass 9) with NO hub ancestor: it
        //     sits directly on the controller's root ports, so it IS the
        //     controller's own fan-out (the M1 mini FL1100 root-hub
        //     personas, which do NOT carry USBPortType=2). Non-hub devices
        //     directly on the controller are real user hardware (an iPhone
        //     on an M1 mini USB-A port does exactly this) and are kept.
        // Residual, documented: a USER hub plugged into a direct-wired
        // USB-A port would match the second signal and be excluded; zero
        // such cases exist in the corpus, and its children would still
        // render (unnested), so the failure mode is mild. Excluded plumbing
        // renders nowhere, exactly like the mini's internal hub on the
        // native path.
        //
        // ASSUMPTION (same class as the AppleT-prefix note on
        // isThunderboltDockController): AppleEmbedded* controllers only
        // exist on desktop Macs (every corpus occurrence is a desktop; the
        // sweep cross-checks this against probe-32 form factors). If a
        // future LAPTOP shipped one, its devices would classify
        // behind-internal-hub here and then be dropped by the desktop gate
        // in TunnelledDeviceGrouping.group, vanishing from the UI. Revisit
        // if the embedded-implies-desktop sweep ever fails.
        let isOwnInternalPlumbing = ownUSBPortType == Self.internalHubPortType
            || (deviceClass == 9 && !hasHubAncestor)
        let behindInternalHub = (reachedEmbeddedController && !isOwnInternalPlumbing)
            || Self.classifyBehindInternalHub(
            reachedNativeController: reachedNativeController,
            tunnelled: tunnelled,
            portName: portName,
            underInternalHub: passedInternalHub
        )

        // PCIe bridge depth: for both tunnel cases (native `AppleUSBXHCITR`
        // and dock-supplied PCIe xHCI), and only when `collectAncestors`
        // actually gathered the extra ancestors above the terminator (the
        // live walk does this; a caller replaying from probe data that
        // stopped at the terminator, like the older
        // `USBWatcherCorpusSweepTests` fixtures, simply gets nil here, which
        // is the correct honest answer for that input).
        let tunnelAncestry = tunnelControllerIndex.flatMap { Self.tunnelBridgeAncestry(ancestors, from: $0) }

        // Stage B v2 join inputs: the controller's saved registry path
        // (captured live at the terminator hit, see `USBAncestor.terminatorRegistryPath`)
        // and the entry-ID list from the controller up through the bridge
        // chain, used for the instance-identity membership check. Both are
        // derived the same pure way as `tunnelAncestry` above, so replays of
        // old captures that never recorded them simply get nil/empty, the
        // honest answer for that input.
        let tunnelControllerRegistryPath = tunnelControllerIndex.flatMap { ancestors[$0].terminatorRegistryPath }
        let tunnelAncestorEntryIDs: [UInt64] = tunnelControllerIndex.map { xhciIndex in
            var ids: [UInt64] = []
            if let ownID = ancestors[xhciIndex].entryID { ids.append(ownID) }
            var index = xhciIndex + 1
            while index < ancestors.count {
                if let id = ancestors[index].entryID { ids.append(id) }
                if let name = ancestors[index].serviceName,
                   RegistryRootNaming.isRootName(name, prefix: "apciec") {
                    break
                }
                index += 1
            }
            return ids
        } ?? []

        return AncestryClassification(
            busIndex: bus,
            portName: portName,
            tunnelled: tunnelled,
            reachedNativeController: reachedNativeController,
            reachedEmbeddedController: reachedEmbeddedController,
            behindInternalHub: behindInternalHub,
            tunnelBridgeDepth: tunnelAncestry?.bridgeDepth,
            tunnelRootName: tunnelAncestry?.rootName,
            carrier: carrier,
            tunnelControllerRegistryPath: tunnelControllerRegistryPath,
            tunnelAncestorEntryIDs: tunnelAncestorEntryIDs
        )
    }

    /// Counts the `"pci-bridge"`-named ancestors between the tunnelled
    /// `AppleUSBXHCITR` controller (at `xhciIndex` in `ancestors`) and the
    /// `apciecN` PCIe-C host bridge root, stopping at the first ancestor whose
    /// name starts with `"apciec"`.
    ///
    /// Verified against `research/customer-probes/m3pro_macos27.0_l`
    /// and `_m` (issue #493's own reporter, ground truth): the LaCie 1big's
    /// tunnel controller sits 4 `pci-bridge` hops from `apciec2` (TB DROM
    /// `Depth` 2), the Studio Display chained behind it sits 6 hops from the
    /// SAME `apciec2` root (TB DROM `Depth` 3). Both figures reproduced
    /// identically across the reporter's two independent captures, and the
    /// count-doubles-per-depth-level pattern held across ~40 further
    /// Apple Silicon corpus folders re-checked during the follow-up
    /// investigation (`research/usb-chain-attribution-identifiers.md`).
    /// `ChainDeviceAttribution` is what turns this raw count into a switch;
    /// this layer only captures it.
    ///
    /// Pure: no IOKit, so it is unit-testable and corpus-replayable from
    /// parsed ancestor lists.
    ///
    /// Bounded by `ancestors.count` (itself bounded by `collectAncestors`'s
    /// iteration cap), so a malformed or cyclic registry cannot hang this.
    nonisolated static func tunnelBridgeAncestry(
        _ ancestors: [USBAncestor],
        from xhciIndex: Int
    ) -> (bridgeDepth: Int, rootName: String)? {
        var count = 0
        var index = xhciIndex + 1
        while index < ancestors.count {
            let name = ancestors[index].serviceName
            // Strict "apciec" + digits (`RegistryRootNaming`), matching the
            // live collector's own stop condition above.
            if let name, RegistryRootNaming.isRootName(name, prefix: "apciec") {
                return (count, name)
            }
            if name == "pci-bridge" { count += 1 }
            index += 1
        }
        // Ran out of ancestors without finding the apciec root: the live
        // collector's extra bound was exceeded, or (replaying from data that
        // only captured up to the terminator) there is nothing past it.
        return nil
    }

    /// True when `className` is an Apple-embedded third-party USB host
    /// controller: board-mounted silicon driving a desktop Mac's extra
    /// built-in plain-USB ports (Mac Studio front ports and back USB-A, M1
    /// Mac mini USB-A block). Apple's own driver naming carries the
    /// distinction: embedded controllers get the `AppleEmbedded` prefix
    /// (`AppleEmbeddedUSBXHCIASMedia3142`, `AppleEmbeddedUSBXHCIFL1100`);
    /// the same silicon inside a dock enumerates without it
    /// (`AppleASMediaUSBXHCI`, `AppleUSBXHCIFL1100`). Verified across the
    /// customer-probe corpus: every `AppleEmbedded*` stop is a desktop Mac,
    /// and none of the 42 real-dock chains carries the prefix.
    ///
    /// Pure so it is unit-testable without IOKit.
    nonisolated static func isEmbeddedBuiltInController(_ className: String) -> Bool {
        className.hasPrefix("AppleEmbedded") && className.contains("USBXHCI")
    }

    /// True when `className` is a host controller that ends the ancestor walk
    /// (native, tunnel, embedded, or dock: the same four cases
    /// `classifyAncestry` breaks on, composed from the same predicates so the
    /// two can't drift). Used by `collectAncestors` to stop gathering at the
    /// controller, exactly where the pure classification stops reading.
    nonisolated static func isWalkTerminator(_ className: String) -> Bool {
        className.hasPrefix("AppleUSBXHCITR")
            || (className.hasPrefix("AppleT") && className.hasSuffix("USBXHCI"))
            || isEmbeddedBuiltInController(className)
            || isThunderboltDockController(className)
    }

    /// What the ancestor walk does AFTER recording a terminating host
    /// controller (`isWalkTerminator`): stop there, or keep walking up to the
    /// `apciecN` PCIe-C host bridge root to capture the PCIe bridge chain.
    ///
    /// Both tunnel kinds continue: the native USB tunnel (`AppleUSBXHCITR`)
    /// and a dock-supplied PCIe xHCI (`isThunderboltDockController`, e.g. the
    /// LG UltraFine 5K's FL1100), because both sit on a Thunderbolt tunnel
    /// whose `apciecN` root is the port-scoping join key. Native and embedded
    /// controllers stop: nothing above them is read.
    ///
    /// Pure, and used by the live collector directly, so a unit test on this
    /// function IS a test of the collector's stop/continue rule (the seam the
    /// plan's review rounds asked for; synthetic-chain classification tests
    /// alone cannot catch a collector that stops too early).
    enum WalkContinuation: Equatable, Sendable {
        case stop
        case continueToPCIeRoot
    }

    nonisolated static func walkContinuation(after className: String) -> WalkContinuation {
        if isEmbeddedBuiltInController(className) { return .stop }
        if className.hasPrefix("AppleUSBXHCITR") { return .continueToPCIeRoot }
        if isThunderboltDockController(className) { return .continueToPCIeRoot }
        return .stop
    }

    /// Live half of the ancestor walk: gathers IOService-plane parents of a
    /// USB device into `USBAncestor` records, reading only the properties
    /// `classifyAncestry` consumes, and stopping at the first host controller
    /// (`isWalkTerminator`), which is included as the final record. Gathers,
    /// never decides: all classification logic lives in the pure function so
    /// the corpus sweep can run the real thing.
    ///
    /// The 20-hop bound to the host controller mirrors the old in-line walk:
    /// the real depth from a USB device to its host controller is small (2-4
    /// hops directly attached; a few more behind chained hubs), so 20 is far
    /// beyond anything observed and just acts as a backstop against a
    /// malformed or cyclic registry.
    ///
    /// For the tunnelled cases (`walkContinuation` returns
    /// `.continueToPCIeRoot`: the native `AppleUSBXHCITR` tunnel controller
    /// AND a dock-supplied PCIe xHCI like the LG UltraFine's FL1100), the
    /// walk does NOT stop at the controller: it keeps going, up to
    /// `extraTunnelHopBound` further hops, to reach the `apciecN` PCIe-C
    /// host bridge root and capture the PCIe bridge chain in between
    /// (`tunnelBridgeAncestry`). Ground truth
    /// (`research/customer-probes/m3pro_macos27.0_l`) needed up to 15
    /// hops from `AppleUSBXHCITR` to `apciec2`; `extraTunnelHopBound` leaves
    /// headroom above that, and a dock controller is expected to sit no
    /// deeper. Native and embedded terminators still stop immediately,
    /// unchanged: nothing above them is read, live
    /// or replayed.
    private static func collectAncestors(of service: io_service_t) -> [USBAncestor] {
        let hostControllerBound = 20
        let extraTunnelHopBound = 20
        var ancestors: [USBAncestor] = []
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        var pastTunnelController = false
        var hops = 0
        while hops < hostControllerBound + extraTunnelHopBound {
            hops += 1
            var parent: io_service_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                break
            }
            IOObjectRelease(current)
            current = parent

            var classBuf = [CChar](repeating: 0, count: 128)
            let className = IOObjectGetClass(current, &classBuf) == KERN_SUCCESS
                ? String(cString: classBuf)
                : ""

            var nameBuf = [CChar](repeating: 0, count: 128)
            let serviceName = IORegistryEntryGetName(current, &nameBuf) == KERN_SUCCESS
                ? String(cString: nameBuf)
                : nil

            let locationID = (IORegistryEntryCreateCFProperty(
                current, "locationID" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? NSNumber)?.uint32Value

            var usbIOPortPath: String?
            if let raw = IORegistryEntryCreateCFProperty(
                current, "UsbIOPort" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() {
                usbIOPortPath = Self.usbIOPortPath(from: raw)
            }

            // Conformance gate: only `IOUSBHostDevice` nodes (the hubs and
            // devices) carry a meaningful `USBPortType`; reading it elsewhere
            // would let an unrelated node shadow the nearest hub's value.
            let conforms = IOObjectConformsTo(current, "IOUSBHostDevice") != 0
            var usbPortType: Int?
            if conforms {
                usbPortType = (IORegistryEntryCreateCFProperty(
                    current, "USBPortType" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? NSNumber)?.intValue
            }

            var entryID: UInt64 = 0
            let hasEntryID = IORegistryEntryGetRegistryEntryID(current, &entryID) == KERN_SUCCESS

            let continuesToPCIeRoot = Self.isWalkTerminator(className)
                && Self.walkContinuation(after: className) == .continueToPCIeRoot

            // Capture-timing rule (Stage B v2): save the controller's own
            // registry path AT the terminator hit, before the continuation
            // walk advances toward apciecN. Reading it here, not after the
            // walk finishes, is what pins it to the controller node rather
            // than whatever the walk happens to end on.
            var terminatorRegistryPath: String?
            if continuesToPCIeRoot {
                var pathBuf = [CChar](repeating: 0, count: 512)
                if IORegistryEntryGetPath(current, kIOServicePlane, &pathBuf) == KERN_SUCCESS {
                    terminatorRegistryPath = String(cString: pathBuf)
                }
            }

            ancestors.append(USBAncestor(
                className: className,
                locationID: locationID,
                usbIOPortPath: usbIOPortPath,
                usbPortType: usbPortType,
                conformsToUSBHostDevice: conforms,
                serviceName: serviceName,
                entryID: hasEntryID ? entryID : nil,
                terminatorRegistryPath: terminatorRegistryPath
            ))

            if continuesToPCIeRoot {
                // A tunnel controller (native `AppleUSBXHCITR` or a
                // dock-supplied PCIe xHCI): don't stop here, keep walking
                // (bounded above) to reach the apciecN root and capture the
                // PCIe bridge chain.
                pastTunnelController = true
                continue
            }
            if pastTunnelController {
                // Past the tunnel controller: stop once the apciecN root is
                // reached. `tunnelBridgeAncestry` reads this same name. Strict
                // "apciec" + digits match (`RegistryRootNaming`), not a loose
                // prefix: a loose check would also stop on an unrelated
                // sibling name that happens to start with the same letters,
                // corrupting the port-scoping comparison this name feeds
                // (review finding).
                if let serviceName, RegistryRootNaming.isRootName(serviceName, prefix: "apciec") { break }
                continue
            }
            // The normal terminators (native, embedded, dock): stop
            // immediately, like the old in-line walk did.
            if Self.isWalkTerminator(className) { break }
        }
        return ancestors
    }

    /// Walks the IOKit parent chain from a USB device and classifies it. See
    /// `classifyAncestry` for what is derived and how; this wrapper only pairs
    /// the live collector with the pure classifier and applies the bus-index
    /// fallback.
    private func controllerInfo(
        for service: io_service_t,
        fallback locationID: UInt32,
        ownUSBPortType: Int?,
        deviceClass: UInt8?
    ) -> (Int?, String?, Bool, Bool, Int?, String?, TunnelCarrier?, String?, [UInt64]) {
        let classification = Self.classifyAncestry(
            Self.collectAncestors(of: service),
            ownUSBPortType: ownUSBPortType,
            deviceClass: deviceClass
        )
        // Fallback: the device's own locationID upper byte mirrors its
        // controller's locationID upper byte on Apple Silicon.
        let bus = classification.busIndex ?? Self.busIndex(fromLocationID: locationID)
        return (
            bus,
            classification.portName,
            classification.tunnelled,
            classification.behindInternalHub,
            classification.tunnelBridgeDepth,
            classification.tunnelRootName,
            classification.carrier,
            classification.tunnelControllerRegistryPath,
            classification.tunnelAncestorEntryIDs
        )
    }

    /// `USBPortType` value Apple reports for a port that is internal to the Mac
    /// (`kIOUSBHostPortTypeInternal`). The Mac's own front-panel hub reports it;
    /// external hubs (including Apple's own Studio Display and keyboard hubs)
    /// report 0. Confirmed across the customer-probe corpus: this value is only
    /// ever reported by Apple internal hardware, only on desktop Macs, and every
    /// desktop's internal hub reports it.
    ///
    /// Cross-validated against Apple's own built-in marker: every hub that
    /// carries the `com.apple.developer.driverkit.builtin` entitlement reports
    /// `USBPortType == 2`, and every hub reporting 2 carries that entitlement
    /// (97/97 both ways across the corpus). So this value is exactly the set of
    /// Mac-internal hubs, no broader, no narrower. The corpus also has external
    /// hubs that are easy to mistake for internal (Microchip/Prolific/Intel
    /// generic hubs reporting `USBPortType == 5`, Studio Display hubs reporting
    /// 0); none carry the entitlement and none report 2. See
    /// `classifyBehindInternalHub`.
    nonisolated static let internalHubPortType = 2

    /// Structural front-port classification (issue #348). True when all four
    /// hold:
    ///   1. `reachedNativeController` -- the parent walk reached a native USB
    ///      host controller (`AppleT*USBXHCI`), not the Thunderbolt tunnel.
    ///   2. `!tunnelled` -- the walk did NOT go through `AppleUSBXHCITR`.
    ///   3. `portName == nil` -- no `UsbIOPort` ancestor, i.e. no `Port-USB-C@N`
    ///      match.
    ///   4. `underInternalHub` -- the chain passes through the Mac's own
    ///      internal hub (`USBPortType == internalHubPortType`) somewhere before
    ///      the controller, whether or not the device's nearest hub is external.
    /// On a desktop Mac that means a device on a plain-USB front-panel port.
    /// Back-port devices always have a `usb-drd*-port-*` (`UsbIOPort`) ancestor,
    /// so they fail (3). TB-tunnelled devices fail (1)/(2).
    ///
    /// Condition (4) is what keeps issue #373 fixed while also fixing #430. The
    /// original #348 gate assumed `portName == nil` was enough to mean "behind
    /// the Mac's internal hub", but a device behind an *external* hub also has
    /// no `Port-USB-C@N` node and reaches the native controller, so keyboards
    /// behind an external hub were wrongly grouped as built-in (#373). The
    /// caller derives this flag from `USBPortType`: only the Mac's internal hub
    /// reports `internalHubPortType`.
    ///
    /// #373 first used the NEAREST hub's `USBPortType`, which fixed the
    /// external-hub-on-a-rear-port case but then dropped a dock's downstream
    /// devices on a desktop FRONT port: the dock is external (nearest hub 0),
    /// yet the chain still runs through the internal hub (#430, @jimmyorz's M4
    /// mini). The caller now flags the internal hub ANYWHERE in the chain, so
    /// front-port dock devices qualify while rear-port external-hub devices,
    /// whose chain never touches the internal hub, still do not. Both cases are
    /// present in #430's dump.
    ///
    /// This is pure structure, not a desktop guarantee: the desktop-only product
    /// policy is applied downstream in `TunnelledDeviceGrouping.group`. Pure so
    /// it is unit-testable without IOKit.
    nonisolated static func classifyBehindInternalHub(
        reachedNativeController: Bool,
        tunnelled: Bool,
        portName: String?,
        underInternalHub: Bool
    ) -> Bool {
        reachedNativeController && !tunnelled && portName == nil && underInternalHub
    }

    /// True when `className` is the third-party USB host controller a
    /// Thunderbolt 3 dock brings over its PCIe tunnel (Fresco Logic
    /// `AppleUSBXHCIFL1100`, `AppleASMediaUSBXHCI`, `AppleUSBXHCIAR`, and the
    /// like), as opposed to a native Apple Silicon controller (`AppleT*`),
    /// the native USB tunnel (`AppleUSBXHCITR`, handled separately), an
    /// Apple-embedded board controller (`AppleEmbedded*`, the Mac's own
    /// built-in plain-USB wiring, see `isEmbeddedBuiltInController`; treating
    /// these as docks was the discussion #417 bug), or an Intel built-in
    /// controller (Intel Macs are unsupported and do not enumerate these in
    /// practice). The match is structural: any `*USBXHCI` host controller that
    /// is none of those four is a dock-supplied controller, so its devices
    /// reached the Mac over Thunderbolt. Validated against every controller
    /// class name in the customer-probe corpus with zero false positives,
    /// including the M5 Pro/Max native `AppleT6050USBXHCIAUSS` (excluded by the
    /// `AppleT` prefix).
    ///
    /// ASSUMPTION: every native Apple Silicon USB host controller class starts
    /// with `AppleT` (true across M1-M5: T8103, T6000, T8112, T8122, T8132,
    /// T8142, T6050). If a future Apple chip family used a different prefix, its
    /// native controller would clear all three exclusions and be misread as a
    /// dock, so its back-port devices would surface under "Other USB devices"
    /// instead of their port. Revisit when a new silicon generation lands.
    ///
    /// Pure so it is unit-testable without IOKit.
    nonisolated static func isThunderboltDockController(_ className: String) -> Bool {
        className.contains("USBXHCI")
            && !className.hasPrefix("AppleT")
            && !className.hasPrefix("AppleUSBXHCITR")
            && !className.hasPrefix("AppleIntel")
            && !isEmbeddedBuiltInController(className)
    }

    nonisolated static func busIndex(fromLocationID locationID: UInt32) -> Int {
        Int((locationID >> 24) & 0xFF)
    }

    nonisolated static func usbIOPortPath(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let data = value as? Data {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }

    nonisolated static func portName(fromUSBIOPortPath path: String) -> String? {
        guard let last = path.split(separator: "/").last else { return nil }
        let name = String(last)
        return name.hasPrefix("Port-") ? name : nil
    }

    private func formatBCD(_ value: UInt16) -> String {
        let major = (value >> 8) & 0xFF
        let minor = (value >> 4) & 0xF
        let sub = value & 0xF
        return sub == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(sub)"
    }

    private func stringify(_ value: Any) -> String {
        switch value {
        case let n as NSNumber: return n.stringValue
        case let s as String: return s
        case let d as Data: return d.map { String(format: "%02X", $0) }.joined(separator: " ")
        case let a as [Any]: return "[\(a.map { stringify($0) }.joined(separator: ", "))]"
        default: return String(describing: value)
        }
    }
}

