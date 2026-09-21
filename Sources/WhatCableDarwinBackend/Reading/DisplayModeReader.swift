import AppKit
import CoreGraphics
import Foundation
import WhatCableCore

/// Reads the live display mode for each attached display from CoreGraphics and
/// matches it to its DisplayPort node by EDID identity, so the display
/// diagnostic can report the true on-screen resolution (issue #249) and confirm
/// a display is at full quality even when it reaches its top mode via
/// compression (issue #246).
///
/// CoreGraphics is the right source here: it exposes the current mode through a
/// public, stable API and gives the live refresh directly, where the IOKit
/// framebuffer nodes carry no port join key and no readable mode handle on
/// Apple Silicon. See `planning/display-current-mode-coregraphics.md`.
///
/// The only platform-specific step is reading from CoreGraphics. The match
/// logic is a pure function (`match(ports:displays:)`) so it can be unit-tested
/// without hardware.
public enum DisplayModeReader {

    /// One online display as CoreGraphics sees it: its identity (for matching to
    /// a DisplayPort node) and its live mode.
    public struct ResolvedDisplay: Equatable {
        /// `CGDisplayVendorNumber`: the packed 16-bit EDID manufacturer id
        /// (same encoding as the EDID's 3-letter PNP code), or nil if absent.
        public let vendorNumber: UInt32?
        /// `CGDisplayModelNumber`: equals the EDID product id on real hardware.
        public let modelNumber: UInt32?
        /// `CGDisplaySerialNumber`: often 0 on Apple Silicon, so used only as a
        /// tiebreaker, never as a primary match key.
        public let serialNumber: UInt32?
        /// `CGDisplayIsBuiltin`: the internal laptop panel. Excluded from
        /// matching, since a DisplayPort transport node is always an external
        /// USB-C / DP connection.
        public let isBuiltin: Bool
        /// The current on-screen mode.
        public let mode: DisplayCurrentMode
        /// The display's native top mode (highest resolution, at its best
        /// refresh) from `CGDisplayCopyAllDisplayModes`. The authoritative top
        /// mode, EDID-free. nil when the mode list is unavailable, so we never
        /// fabricate a top mode the OS didn't give us.
        public let maxMode: DisplayCurrentMode?

        public init(vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?, isBuiltin: Bool = false, mode: DisplayCurrentMode, maxMode: DisplayCurrentMode?) {
            self.vendorNumber = vendorNumber
            self.modelNumber = modelNumber
            self.serialNumber = serialNumber
            self.isBuiltin = isBuiltin
            self.mode = mode
            self.maxMode = maxMode
        }
    }

    /// Public entry point: enrich each DisplayPort node with its live mode where
    /// an unambiguous match exists. Reads CoreGraphics, then defers to the pure
    /// matcher. Returns the ports unchanged on any read failure. `@MainActor`
    /// because the bpc read goes through `NSScreen.screens` underneath.
    @MainActor
    public static func enrich(_ ports: [IOPortTransportStateDisplayPort]) -> [IOPortTransportStateDisplayPort] {
        let displays = readOnlineDisplays()
        guard !displays.isEmpty else { return ports }
        return match(ports: ports, displays: displays)
    }

    /// Pure match: attach a `currentMode` to a node only when **exactly one**
    /// online display matches its EDID identity. Fail-closed by design, an
    /// ambiguous or missing match leaves `currentMode` nil so the diagnostic
    /// falls back to its existing verdict and never cross-wires a mode onto the
    /// wrong port.
    ///
    /// Match key: product id (`CGDisplayModelNumber` == EDID product id) plus
    /// vendor (`CGDisplayVendorNumber` decoded to the same 3-letter PNP code the
    /// EDID carries). Serial breaks a tie between two otherwise-identical
    /// displays. A node with no usable identity, or that matches zero or
    /// several displays, is returned untouched.
    public static func match(
        ports: [IOPortTransportStateDisplayPort],
        displays: [ResolvedDisplay]
    ) -> [IOPortTransportStateDisplayPort] {
        ports.map { port in
            guard port.currentMode == nil, let monitor = port.monitor else { return port }

            // A DisplayPort transport node is always an external connection, so
            // the internal panel is never a candidate.
            let candidates = displays.filter { display in
                !display.isBuiltin && identityMatches(monitor: monitor, display: display)
            }

            // Exactly one candidate: attach. Otherwise fail closed.
            guard candidates.count == 1 else {
                guard candidates.count > 1, let monitorSerial = monitor.serialNumber else { return port }
                // Tiebreak two identical displays by serial, if the node has one.
                let bySerial = candidates.filter { $0.serialNumber == UInt32(truncatingIfNeeded: monitorSerial) }
                guard bySerial.count == 1 else { return port }
                return attach(bySerial[0], to: port)
            }
            return attach(candidates[0], to: port)
        }
    }

    /// True when a CoreGraphics display is the same physical panel as a
    /// DisplayPort node's EDID identity. Requires a positive product-id match
    /// and, when both sides report a vendor, a vendor match too.
    static func identityMatches(monitor: MonitorInfo, display: ResolvedDisplay) -> Bool {
        guard let productId = monitor.productId,
              let modelNumber = display.modelNumber,
              Int(modelNumber) == productId else { return false }

        // Vendor confirmation when both sides carry it. EDID stores the
        // manufacturer as a 3-letter PNP code; CoreGraphics returns the same
        // value packed as a number, so decode CG's number and compare strings.
        // Fail closed: if both sides report a vendor but CG's number won't
        // decode (junk), don't fall back to a product-id-only match.
        if let name = monitor.manufacturerName, let vendorNumber = display.vendorNumber {
            guard let decoded = pnpCode(fromPackedVendor: vendorNumber) else { return false }
            return decoded == name
        }
        // One side lacks a vendor: product id alone is the match.
        return true
    }

    /// Attach a matched display's modes to a node, but only when the current
    /// refresh is usable. CoreGraphics has returned 0 Hz for some modes; with no
    /// trustworthy refresh there is no current-mode data to carry, so leave the
    /// node as-is. The max mode is carried only when it too has a usable refresh.
    private static func attach(_ display: ResolvedDisplay, to port: IOPortTransportStateDisplayPort) -> IOPortTransportStateDisplayPort {
        guard display.mode.refreshHz > 0 else { return port }
        let maxMode = (display.maxMode?.refreshHz ?? 0) > 0 ? display.maxMode : nil
        return port.with(currentMode: display.mode, maxMode: maxMode)
    }

    /// Decode `CGDisplayVendorNumber` (a packed EDID manufacturer id) into its
    /// 3-letter PNP code, e.g. 0x1C54 -> "GBT". Each letter is 5 bits, A=1, in
    /// the low 15 bits of the 16-bit value. Returns nil if any field is out of
    /// the A-Z range, so a junk vendor number never produces a false match.
    static func pnpCode(fromPackedVendor packed: UInt32) -> String? {
        let value = UInt16(truncatingIfNeeded: packed)
        let letters = [
            (value >> 10) & 0x1F,
            (value >> 5) & 0x1F,
            value & 0x1F,
        ]
        var out = ""
        for code in letters {
            guard (1...26).contains(code) else { return nil }
            out.append(Character(UnicodeScalar(UInt8(code) + 0x40))) // 1 -> 'A'
        }
        return out
    }

    /// Read every online display from CoreGraphics. The one platform-specific
    /// step; everything downstream is pure. `@MainActor` because the bpc read
    /// goes through `NSScreen.screens`, which is main-thread-only.
    @MainActor
    private static func readOnlineDisplays() -> [ResolvedDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        return ids.compactMap { id -> ResolvedDisplay? in
            guard let cgMode = CGDisplayCopyDisplayMode(id) else { return nil }
            let bpc = bitsPerComponent(of: id)
            let mode = mode(from: cgMode, bitsPerComponent: bpc)
            return ResolvedDisplay(
                vendorNumber: CGDisplayVendorNumber(id),
                modelNumber: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                mode: mode,
                maxMode: nativeTopMode(of: id)
            )
        }
    }

    /// Convert a CoreGraphics mode to our model in physical pixels, NOT points:
    /// a Retina 5K display is 5120 x 2880 here but only 2560 x 1440 via the
    /// point-based getters. Using the point variants would re-create issue #249.
    /// `bitsPerComponent` is plumbed in from a separate per-display read because
    /// `CGDisplayMode` doesn't expose it directly on modern macOS.
    private static func mode(from cgMode: CGDisplayMode, bitsPerComponent: Int? = nil) -> DisplayCurrentMode {
        DisplayCurrentMode(
            width: cgMode.pixelWidth,
            height: cgMode.pixelHeight,
            refreshHz: cgMode.refreshRate,
            bitsPerComponent: bitsPerComponent
        )
    }

    /// Read the live bits-per-channel macOS is driving for this display, so the
    /// display diagnostic can tell DSC apart from a 10bpc HDR mode that just
    /// needs more bandwidth. We use `NSScreen.depth.bitsPerSample`, the typed
    /// Swift overlay around the (Swift-obsolete) `NSBitsPerSampleFromDepth` C
    /// function, which gives us a principled answer without poking at raw
    /// `NSWindowDepth` constants. The clamp logic is delegated to
    /// `displayPortBitsPerComponent(from:)` so the integer range check is
    /// reachable from tests without going through `NSScreen`.
    @MainActor
    private static func bitsPerComponent(of id: CGDirectDisplayID) -> Int? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id
        }) else { return nil }
        return displayPortBitsPerComponent(from: screen.depth.bitsPerSample)
    }

    /// Clamp a raw `NSScreen.depth.bitsPerSample` value to the two depths we've
    /// observed it report on real macOS: 8bpc (24bpp standard) and 10bpc (30bpp
    /// HDR / 10-bit). Everything else returns nil so the diagnostic falls back
    /// to its 24bpp default.
    ///
    /// The 16bpc / 32bpc values (from `NSWindowDepthSixtyfourBitRGB` /
    /// `NSWindowDepthOnehundredtwentyeightBitRGB`) describe AppKit's backing
    /// store, not the link encoding, so they must not flow through as wire bpc.
    ///
    /// 12bpc is a defined VESA DP wire depth (MSA color depth `0b011` in DP
    /// 1.4) but macOS hasn't been observed to report 12 via `NSScreen.depth`,
    /// so we can't confirm that path maps cleanly to a 36bpp wire mode. Rejected
    /// here for now; extend when a real macOS observation lands. 9 and 11 are
    /// not defined wire depths anywhere. Using `==` rather than a range makes
    /// all of this explicit rather than letting unknown middle values pass.
    static func displayPortBitsPerComponent(from bps: Int) -> Int? {
        (bps == 8 || bps == 10) ? bps : nil
    }

    /// The display's native top mode from `CGDisplayCopyAllDisplayModes`: the
    /// highest-resolution mode (by pixel area), and at that resolution the
    /// highest refresh. This is the EDID-free native mode: macOS reports the
    /// real one here even for 5K/6K displays whose EDID can't describe it.
    ///
    /// Resolution first, not throughput: a lower-resolution, higher-refresh mode
    /// can win on pixels-per-second (e.g. 4K120 beats 5K60), which would mislabel
    /// a 5K panel's native size. nil when the mode list is unavailable, so we
    /// never fabricate a top mode.
    private static func nativeTopMode(of id: CGDirectDisplayID) -> DisplayCurrentMode? {
        guard let cfModes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] else { return nil }
        return cfModes
            .map { mode(from: $0) }
            .max { ($0.width * $0.height, $0.refreshHz) < ($1.width * $1.height, $1.refreshHz) }
    }
}

extension IOPortTransportStateDisplayPort {
    /// Copy this node with the matched modes attached. Kept in the backend
    /// because only the two readers (CoreGraphics here, the display node in
    /// `DisplayTimingReader`) set them. `drivenTiming` is set only by
    /// `DisplayTimingReader.match`; a nil argument keeps whatever the port
    /// already carries. `hpmControllerUUID` is carried across so the port
    /// keeps its canonical join key through enrichment (issue #664, Finding
    /// "The join key is dropped").
    func with(currentMode: DisplayCurrentMode, maxMode: DisplayCurrentMode?, drivenTiming: DisplayTimingStatement? = nil) -> IOPortTransportStateDisplayPort {
        IOPortTransportStateDisplayPort(
            link: link, monitor: monitor, dfpType: dfpType,
            branchDeviceId: branchDeviceId, branchDeviceOUI: branchDeviceOUI,
            sinkCount: sinkCount, role: role, roleDescription: roleDescription,
            driverStatus: driverStatus, driverStatusDescription: driverStatusDescription,
            transportType: transportType, transportTypeDescription: transportTypeDescription,
            transportDescription: transportDescription,
            authorizationRequired: authorizationRequired, authorizationStatus: authorizationStatus,
            authorizationStatusDescription: authorizationStatusDescription,
            authenticationRequired: authenticationRequired, authenticationStatus: authenticationStatus,
            authenticationStatusDescription: authenticationStatusDescription,
            hashStatus: hashStatus, hashStatusDescription: hashStatusDescription,
            trmTransportSupervised: trmTransportSupervised,
            parentPortType: parentPortType, parentPortTypeDescription: parentPortTypeDescription,
            parentPortNumber: parentPortNumber, parentPortBuiltIn: parentPortBuiltIn,
            parentBuiltInPortType: parentBuiltInPortType,
            parentBuiltInPortTypeDescription: parentBuiltInPortTypeDescription,
            parentBuiltInPortNumber: parentBuiltInPortNumber,
            edidChanged: edidChanged, nominalSignalingFrequenciesHz: nominalSignalingFrequenciesHz,
            index: index, currentMode: currentMode, maxMode: maxMode,
            drivenTiming: drivenTiming ?? self.drivenTiming,
            hpmControllerUUID: hpmControllerUUID
        )
    }
}
