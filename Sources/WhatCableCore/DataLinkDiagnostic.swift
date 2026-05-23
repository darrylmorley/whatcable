import Foundation

/// Compares what the Mac port, the cable, and the connected device can each
/// do for data, against the speed the link actually negotiated, and names
/// the weakest link. This is the data-speed sibling of `ChargingDiagnostic`
/// (which does the same job for power). Same shape on purpose: a failable
/// init that returns `nil` when there is nothing to judge, a `Bottleneck`
/// enum carrying the numbers, and plain-English `summary` / `detail`.
///
/// Phase 1 wording is deliberately NOT localised yet. The strings are under
/// review; once the verdict wording is approved they move to
/// `String(localized:)` against `_coreLocalizedBundle` in the UI phase,
/// matching `ChargingDiagnostic`.
public struct DataLinkDiagnostic {
    public enum Bottleneck: Hashable {
        /// Link is running at the fastest the parties support. Not a fault.
        case fine(activeGbps: Double)
        /// The cable is the binding constraint; host and device could go faster.
        case cableLimit(cableGbps: Double, capableGbps: Double)
        /// This Mac port is the slowest link.
        case hostLimit(hostGbps: Double, capableGbps: Double)
        /// The connected device itself is the cap (e.g. a USB 2.0 device).
        /// Normal, not actionable: not a cable fault.
        case deviceLimit(deviceGbps: Double)
        /// Everyone supports more than the active speed but no single
        /// culprit can be pinned. The honest answer to the case the old
        /// draft wrongly reported as "full speed".
        case degraded(activeGbps: Double, expectedGbps: Double)
        /// No e-marker and no controller data, so we cannot say whether the
        /// cable is the limit. Stated plainly rather than guessed.
        case unknownCable(activeGbps: Double)
    }

    public let bottleneck: Bottleneck
    public let summary: String
    public let detail: String

    /// True for the cases worth flagging in the inline one-line verdict.
    /// `deviceLimit` and `unknownCable` are informational, not faults, so
    /// they do not warn (a USB 2.0 keyboard or an e-marker-less cable is
    /// normal). This is a deliberate deviation from `ChargingDiagnostic`,
    /// where only `.fine` is non-warning.
    public var isWarning: Bool {
        switch bottleneck {
        case .fine, .deviceLimit, .unknownCable: return false
        case .cableLimit, .hostLimit, .degraded: return true
        }
    }

    /// True when the cable's own e-marker disagrees with the Thunderbolt
    /// controller's view of the cable (issue #111: active TB4 cables that
    /// report "passive" / a low speed in their e-marker while the
    /// controller correctly negotiates the full rate). When true the
    /// controller's higher figure is used and `detail` says so.
    public let cableSignalConflict: Bool

    /// The resolved per-party figures behind the verdict, in Gbps. The
    /// inline one-line verdict uses `summary`; the Pro breakdown renders
    /// these so the user can see the receipts (cable claims X, device does
    /// Y, link negotiated Z). All optional except `activeGbps`, which is
    /// always known (the diagnostic returns nil without it).
    public struct Facts: Hashable {
        /// What this Mac port can do, if the caller resolved it.
        public let hostGbps: Double?
        /// Cable speed as claimed by its own USB-PD e-marker.
        public let cableEmarkerGbps: Double?
        /// Cable speed as the Thunderbolt controller sees it (CIO).
        public let cableControllerGbps: Double?
        /// The cable figure actually used: the higher of the two when both
        /// exist (the controller wins on a conflict).
        public let cableGbps: Double?
        /// The fastest connected device's speed.
        public let deviceGbps: Double?
        /// The speed the link actually negotiated.
        public let activeGbps: Double
    }

    public let facts: Facts
}

extension DataLinkDiagnostic {
    /// - Parameters:
    ///   - port: the physical USB-C / MagSafe port. Used only to gate on
    ///     `connectionActive` (mirrors `ChargingDiagnostic`'s stale-port
    ///     guard: a disconnected port can keep cached state around).
    ///   - identities: USB-PD Discover Identity endpoints for this port.
    ///     The cable e-marker is the SOP' / SOP'' entry; the connected
    ///     device/charger is SOP. We read the cable's claimed speed here.
    ///   - devices: USB devices on this port. The fastest one is taken as
    ///     the representative device cap (the device the link is serving).
    ///   - usb3Transports: USB 3 SuperSpeed transports; the one matching
    ///     this port (by `portKey`) gives the negotiated USB 3 rate.
    ///   - cio: the Thunderbolt controller's own cable assessment for this
    ///     port, if a TB link is active. Ground truth for TB cables and can
    ///     legitimately disagree with the e-marker (issue #111).
    ///   - thunderboltSwitches: the host's TB switch graph. The port's
    ///     active downstream lane link gives the negotiated TB rate. The
    ///     correlation reuses the same `ThunderboltTopology` helpers
    ///     `PortSummary` uses, so the messy switch-tree walk stays in one
    ///     tested place.
    ///   - tbActiveGbps: explicit override for the active TB rate. When
    ///     `nil` it is resolved from `thunderboltSwitches`. Mainly a test
    ///     seam (mirrors `ChargingDiagnostic`'s defaulted `wattageSource`).
    ///   - hostMaxGbps: what this Mac port can do, resolved by the caller.
    ///     Optional: when `nil` the diagnostic tries to infer it from the
    ///     host root Thunderbolt switch's `supportedSpeed` mask. If that
    ///     also fails (non-TB port, switches not yet populated) the host
    ///     stays unknown and the diagnostic never blames it (degrades to
    ///     `unknownCable` / `degraded` instead).
    public init?(
        port: AppleHPMInterface,
        identities: [USBPDSOP],
        devices: [USBDevice],
        usb3Transports: [USB3Transport],
        cio: CIOCableCapability?,
        thunderboltSwitches: [IOThunderboltSwitch] = [],
        tbActiveGbps: Double? = nil,
        hostMaxGbps: Double? = nil
    ) {
        // Resolve the Mac port's capability. Explicit caller value wins
        // (mainly a test seam). Otherwise infer from the host root TB
        // switch's `supportedSpeed` mask. Nil for non-TB USB-C ports.
        let resolvedHostMaxGbps = hostMaxGbps
            ?? Self.hostMaxGbpsFromSwitches(port: port, switches: thunderboltSwitches)
        // Same guard as ChargingDiagnostic: an inactive port can still
        // expose stale link state. Don't diagnose a port that isn't live.
        guard port.connectionActive == true else { return nil }

        // Pick the port's USB 3 transport (portKey is the correlation key;
        // fall back to the only entry if the caller pre-filtered). Only
        // trust the transport's speed when USB3 is in `TransportsActive`:
        // the HPM port controller can leave a stale USB3 transport service
        // around when the negotiated link is only USB 2.0 (issue #187).
        let usb3 = port.transportsActive.contains("USB3")
            ? (usb3Transports.first { $0.portKey == port.portKey } ?? usb3Transports.first)
            : nil

        // The speed the link actually negotiated: the Thunderbolt link if
        // there is one, otherwise the USB 3 signaling generation.
        let activeGbps = tbActiveGbps
            ?? Self.activeTBGbps(port: port, switches: thunderboltSwitches)
            ?? Self.usb3Gbps(usb3?.signaling)

        // Without a known active speed there is no data-speed verdict to
        // give. Returning nil keeps this off ports that are charge-only or
        // where the link state isn't readable yet.
        guard let active = activeGbps else { return nil }

        // Cable's claimed speed from its e-marker (SOP' / SOP'').
        let cableIdentity = identities
            .first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime })
        let emarkerGbps = cableIdentity?.cableVDO?.speed.maxGbps

        // Cable's speed as the Thunderbolt controller sees it. Only the
        // confirmed codes are mapped; unknown codes stay nil rather than
        // guess (mirrors CIOCableCapability.speedLabel's conservatism).
        let cioGbps = Self.cioCableGbps(cio?.cableSpeed)

        // When both signals exist and disagree across tiers, the controller
        // is authoritative either way. The original case (issue #111) was an
        // active TB4 cable e-marker that under-reported as "passive low
        // speed" while the controller correctly showed 40. Issue #190 was
        // the inverse: a suspect cable (zero VID) over-reported as 80 while
        // the controller showed 40. In both cases the controller's reading
        // is the trustworthy one, so resolve the disagreement to CIO rather
        // than taking the higher figure.
        let conflict: Bool
        let cableMaxGbps: Double?
        switch (emarkerGbps, cioGbps) {
        case let (e?, c?):
            if Self.sameTier(e, c) {
                conflict = false
                cableMaxGbps = max(e, c)
            } else {
                conflict = true
                cableMaxGbps = c
            }
        case let (e?, nil):
            conflict = false
            cableMaxGbps = e
        case let (nil, c?):
            conflict = false
            cableMaxGbps = c
        case (nil, nil):
            conflict = false
            cableMaxGbps = nil
        }
        // Sanity floor: the cable must be able to carry whatever speed the
        // link is *actually* running at; otherwise the link could not have
        // negotiated. If our resolved cable cap is meaningfully below the
        // active rate (e.g. a controller cableSpeed=3 reading on a TB5
        // cable due to a firmware quirk, with the e-marker correctly
        // saying 80 and the link running at 80), the resolved value is
        // suspect, not the active link. Promote to the active rate so the
        // verdict layer never claims "cable carries N" while the link is
        // empirically running faster.
        let cableFloored: Double?
        if let c = cableMaxGbps, c < active, !Self.sameTier(c, active) {
            cableFloored = active
        } else {
            cableFloored = cableMaxGbps
        }
        self.cableSignalConflict = conflict

        // The device cap. For a Thunderbolt partner (issue #190) the real
        // capability lives on the partner's own TB switch, not on whatever
        // USB devices happen to be enumerated behind it: a TB dock has an
        // internal USB hub IC at 5/10 Gbps that does NOT represent the
        // dock's actual speed, and a TB-only / SATA-only drive (e.g. LaCie
        // d2) enumerates no USB device at all. When a TB partner is
        // present, USB enumerations behind it are sub-components, so we
        // ignore them and use the partner's `supportedSpeed.maxTotalGbps`
        // mask. If that mask is missing or unrecognised, the active TB
        // link rate is a safe lower bound (the partner must support at
        // least the speed it actually negotiated). The USB device list is
        // consulted only when no TB partner switch is reachable.
        let partner = Self.partnerSwitch(port: port, switches: thunderboltSwitches)
        let fastestDevice = devices
            .filter { $0.speedRaw != nil }
            .max { (Self.deviceGbps($0.speedRaw) ?? 0) < (Self.deviceGbps($1.speedRaw) ?? 0) }
        let usbDeviceGbps = Self.deviceGbps(fastestDevice?.speedRaw)
        let deviceMaxGbps: Double?
        if let partner {
            deviceMaxGbps = partner.supportedSpeed.maxTotalGbps
                ?? Self.activeTBGbps(port: port, switches: thunderboltSwitches)
        } else {
            deviceMaxGbps = usbDeviceGbps
        }

        // Capture the resolved figures for the Pro breakdown. Every
        // constructed instance flows through here (the only earlier return
        // is the no-active-speed guard, which yields no instance).
        self.facts = Facts(
            hostGbps: resolvedHostMaxGbps,
            cableEmarkerGbps: emarkerGbps,
            cableControllerGbps: cioGbps,
            cableGbps: cableFloored,
            deviceGbps: deviceMaxGbps,
            activeGbps: active
        )

        let conflictNote = conflict
            ? " " + String(localized: "The cable's e-marker and the Thunderbolt controller disagree on its speed; the controller's reading is treated as authoritative.", bundle: _coreLocalizedBundle)
            : ""

        // Every capability we actually know about, tagged by party. The
        // link can never run faster than the slowest of these.
        var caps: [(party: String, value: Double)] = []
        if let c = cableFloored         { caps.append((party: "cable",  value: c)) }
        if let h = resolvedHostMaxGbps  { caps.append((party: "host",   value: h)) }
        if let d = deviceMaxGbps        { caps.append((party: "device", value: d)) }

        guard let expected = caps.map(\.value).min() else {
            // We know the active speed but have nothing to compare it to:
            // no e-marker, no controller data, host unresolved, no device.
            // Don't guess a culprit.
            self.bottleneck = .unknownCable(activeGbps: active)
            self.summary = String(localized: "Running at \(Self.label(active))", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "There's no cable e-marker or controller data, and no port or device capability to compare against, so we can't tell whether the cable is the limit.", bundle: _coreLocalizedBundle)
            return
        }

        if Self.meaningfullySlower(active, than: expected) {
            // Slower than even the slowest part we can see. Something
            // unidentified degraded it. If the cable is the unknown, it's
            // the honest suspect; otherwise it's an unattributed degrade.
            // Either way, never claim "full speed" here (the old draft bug).
            if cableFloored == nil {
                self.bottleneck = .unknownCable(activeGbps: active)
                self.summary = String(localized: "Running at \(Self.label(active))", bundle: _coreLocalizedBundle)
                self.detail = String(localized: "This cable has no e-marker and no controller data, so we can't tell whether it is the limit.", bundle: _coreLocalizedBundle)
            } else {
                self.bottleneck = .degraded(activeGbps: active, expectedGbps: expected)
                self.summary = String(localized: "Running slower than expected (\(Self.label(active)))", bundle: _coreLocalizedBundle)
                self.detail = String(localized: "The parts we can see all support \(Self.label(expected)) or more, but the link came up slower. Reseating the cable or trying another port may help.", bundle: _coreLocalizedBundle) + conflictNote
            }
            return
        }

        // The link is running about as fast as the slowest known part
        // allows. If some other known part is faster, that slowest part is
        // holding it back. If everything known is the same tier, nothing is
        // being limited and the link is fine.
        let limiters = caps.filter { Self.sameTier($0.value, expected) }
        let fasterOthers = caps.filter { Self.meaningfullySlower(expected, than: $0.value) }

        guard !fasterOthers.isEmpty else {
            self.bottleneck = .fine(activeGbps: active)
            self.summary = String(localized: "Running at full data speed (\(Self.label(active)))", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "Nothing is being held back: the parts we can see all support this speed.", bundle: _coreLocalizedBundle) + conflictNote
            return
        }

        // Name the binding part. When only one party is at the floor it is
        // the culprit. When multiple parties tie at the floor (e.g. a TB3
        // device on a TB3-rated cable, both 40 Gbps, with a TB5 host), the
        // priority decides which one we call out. Prefer the non-actionable
        // parts (device, then host) over the cable: if device or host is
        // also at the floor, replacing the cable would not unlock more
        // speed, so "Cable is limiting data speed" would be misleading.
        // The cable wins the call-out only when it is the unique floor.
        let capable = fasterOthers.map(\.value).min() ?? expected
        let priority = ["device", "host", "cable"]
        let culprit = priority.first { p in limiters.contains { $0.party == p } } ?? "device"

        switch culprit {
        case "cable":
            self.bottleneck = .cableLimit(cableGbps: expected, capableGbps: capable)
            self.summary = String(localized: "Cable is limiting data speed", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "The Mac and device can do \(Self.label(capable)), but the cable only carries \(Self.label(expected)). A faster cable would unlock full speed.", bundle: _coreLocalizedBundle) + conflictNote
        case "host":
            self.bottleneck = .hostLimit(hostGbps: expected, capableGbps: capable)
            self.summary = String(localized: "This Mac port limits data speed", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "The cable and device can do \(Self.label(capable)), but this port maxes out at \(Self.label(expected)).", bundle: _coreLocalizedBundle) + conflictNote
        default: // device
            self.bottleneck = .deviceLimit(deviceGbps: expected)
            self.summary = String(localized: "Device runs at \(Self.label(expected))", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "This is the fastest the connected device supports. It is not a cable problem.", bundle: _coreLocalizedBundle) + conflictNote
        }
    }

    // MARK: - Speed resolution helpers

    /// The active Thunderbolt link rate for a port, resolved from the host
    /// switch graph. Reuses the same `ThunderboltTopology` correlation
    /// `PortSummary` uses (socket-ID match -> host root -> active
    /// downstream lane port). Returns `nil` when the port isn't on a TB
    /// link or no link is up.
    static func activeTBGbps(
        port: AppleHPMInterface,
        switches: [IOThunderboltSwitch]
    ) -> Double? {
        guard !switches.isEmpty,
              let socketID = ThunderboltTopology.socketID(fromServiceName: port.serviceName),
              let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches),
              let hostPort = ThunderboltTopology.activeDownstreamLanePort(root),
              let gen = hostPort.currentSpeed else {
            return nil
        }
        return gen.totalGbps
    }

    /// The Mac port's maximum throughput, taken from the host root TB
    /// switch's `supportedSpeed` mask. This is what the chip can negotiate,
    /// not what is currently active. Returns `nil` for non-TB USB-C ports
    /// (no matching host root) or when the switch graph isn't loaded yet.
    ///
    /// Uses the specific lane port matching the user's socket ID when one
    /// is present, not the switch-level aggregate. On a hypothetical
    /// controller with per-port asymmetric capabilities (e.g. one port
    /// configured for TB5 and another for TB4), the switch aggregate would
    /// overstate the capability of any port that doesn't have every bit.
    /// The per-port mask avoids that. Falls back to the switch aggregate
    /// only when the matched port has no `supportedSpeed` of its own.
    static func hostMaxGbpsFromSwitches(
        port: AppleHPMInterface,
        switches: [IOThunderboltSwitch]
    ) -> Double? {
        guard !switches.isEmpty,
              let socketID = ThunderboltTopology.socketID(fromServiceName: port.serviceName),
              let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches) else {
            return nil
        }
        if let portMask = root.ports
            .first(where: { $0.adapterType.isLane && $0.socketID == socketID })?
            .supportedSpeed {
            return portMask.maxTotalGbps
        }
        return root.supportedSpeed.maxTotalGbps
    }

    /// The directly-connected Thunderbolt partner switch for this user-
    /// visible USB-C port, or `nil` when none is reachable.
    ///
    /// Per-port matching is what makes this safe on controllers that host
    /// more than one user-visible USB-C port on a single root switch
    /// (asymmetric M-class controllers, multi-port hubs, etc). The
    /// `parentSwitchUID` guard pins the partner to *this* root. The
    /// `routeString`-low-byte guard pins it to *this* lane port: each hop
    /// in a TB route is one byte; for a depth-1 partner the only hop is
    /// the parent's downstream port number. Matching against
    /// `upstreamPortNumber` would be wrong (that field is the *partner's
    /// own* port number for its upstream link, not the parent's port
    /// number; the Samsung C34J79x fixture in `ThunderboltLinkFromTests`
    /// is the canonical proof of that: parent port 1, partner upstream
    /// port 3).
    static func partnerSwitch(
        port: AppleHPMInterface,
        switches: [IOThunderboltSwitch]
    ) -> IOThunderboltSwitch? {
        guard !switches.isEmpty,
              let socketID = ThunderboltTopology.socketID(fromServiceName: port.serviceName),
              let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches),
              let hostLanePort = root.ports.first(where: {
                  $0.adapterType.isLane && $0.socketID == socketID
              }) else {
            return nil
        }
        return switches.first { sw in
            sw.parentSwitchUID == root.id
                && Int(sw.routeString & 0xFF) == hostLanePort.portNumber
        }
    }

    /// USB 3 signaling generation to Gbps. 1 = Gen 1 (5), 2 = Gen 2 (10).
    static func usb3Gbps(_ signaling: Int?) -> Double? {
        switch signaling {
        case 1: return 5
        case 2: return 10
        default: return nil
        }
    }

    /// CIO controller cable-speed code to Gbps. Only the confirmed codes
    /// are mapped (3 = TB4 / 40, 4 = TB5 / 80). TB3 is unsampled, so an
    /// unknown code returns nil rather than a guess.
    static func cioCableGbps(_ code: Int?) -> Double? {
        switch code {
        case 3: return 40
        case 4: return 80
        default: return nil
        }
    }

    /// USB device "Device Speed" enum to Gbps. Mirrors USBDevice.speedLabel.
    static func deviceGbps(_ speedRaw: UInt8?) -> Double? {
        switch speedRaw {
        case 0: return 0.0015   // Low Speed   1.5 Mbps
        case 1: return 0.012    // Full Speed  12 Mbps
        case 2: return 0.48     // High Speed  480 Mbps
        case 3: return 5        // SuperSpeed  5 Gbps
        case 4: return 10       // SuperSpeed+ 10 Gbps
        case 5: return 20       // Gen 2x2     20 Gbps
        default: return nil
        }
    }

    /// Speeds come in well-separated tiers (0.48 / 5 / 10 / 20 / 40 / 80),
    /// so a 10% band is plenty to absorb rounding without merging tiers.
    static func sameTier(_ a: Double, _ b: Double) -> Bool {
        guard a > 0, b > 0 else { return a == b }
        let ratio = a / b
        return ratio >= 0.9 && ratio <= 1.111
    }

    /// `a` is meaningfully slower than `b` (more than ~10% below it).
    static func meaningfullySlower(_ a: Double, than b: Double) -> Bool {
        a < b * 0.9
    }

    /// Human-readable speed: sub-1-Gbps as Mbps, whole numbers without ".0".
    static func label(_ gbps: Double) -> String {
        if gbps < 1 {
            return "\(Int((gbps * 1000).rounded())) Mbps"
        }
        if gbps.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(gbps)) Gbps"
        }
        return "\(gbps) Gbps"
    }
}
