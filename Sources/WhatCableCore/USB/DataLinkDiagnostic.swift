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
        /// cable is the limit. Stated plainly rather than guessed. Also
        /// reused (issue #393) as a hedge when the only figures above the
        /// active rate are a cable claim (e-marker or controller) and the
        /// host's own ceiling, with no device known to exceed the link: a
        /// healthy link, not a fault, so we say what we can verify rather
        /// than guess a culprit.
        case unknownCable(activeGbps: Double)
        /// The cable's e-marker reports a speed meaningfully below the
        /// link's apparent active rate, and there is no controller (CIO)
        /// reading to break the tie. One of the two signals is wrong; we
        /// surface both numbers rather than silently picking a side
        /// (issue #195 follow-up: the old defence-in-depth floor would
        /// promote the cable to the active rate, which masked
        /// legitimately slow cables whenever the active reading was
        /// itself unreliable).
        case cableContradictsActive(cableGbps: Double, activeGbps: Double)
        /// macOS TRM (Trust and Restrict Management) has blocked data on this
        /// transport. The link is physically capable of `signaledGbps`, but
        /// macOS is withholding data until the user approves the accessory.
        /// Takes precedence over healthy/speed verdicts because the link is
        /// not actually passing data regardless of the signaled rate.
        case blockedBySecurity(signaledGbps: Double)
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
        case .cableLimit, .hostLimit, .degraded, .cableContradictsActive, .blockedBySecurity: return true
        }
    }

    /// True when the cable's e-marker claims a USB4 speed (Gen 3 or Gen 4
    /// speed bits) and the controller reads a tier above it with the live
    /// lane agreeing (issue #111). A USB-only speed field below the
    /// controller's figure is not a disagreement: that field describes
    /// USB data, not Thunderbolt, and an active-cable VDO is not a speed
    /// claim either. When true the controller's higher figure is used and
    /// `detail` says so.
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
        /// The Thunderbolt controller's claim about the cable and peer
        /// pair (CIO CableSpeed). A floor on cable capability, never a
        /// cap, and it can sit above the lane the port actually trained.
        public let cableControllerGbps: Double?
        /// The cable figure actually used: the e-marker's own claim, or the
        /// controller's figure when it reads a higher tier than the
        /// e-marker claims; either way never below the lane a live
        /// Thunderbolt link carried.
        public let cableGbps: Double?
        /// The fastest connected device's speed.
        public let deviceGbps: Double?
        /// Name of the device used for `deviceGbps`, for display in tiles.
        public let deviceName: String?
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

        // Defence-in-depth (issue #195): refuse the diagnostic on any
        // port that can't host a data link, even if every downstream
        // socket-ID lookup is correctly gated. A future regression that
        // re-introduces an un-gated TB topology lookup would still be
        // caught here. Belt and braces against the same class of bug.
        guard port.carriesData else { return nil }

        // Pick the port's USB 3 transport via the shared Core selector
        // (canonically matched, tunnelled entries excluded). This used to
        // be a local `filter { tunnelled != true }` plus a fallback to ANY
        // unmatched direct entry in the whole snapshot; the fallback is
        // dropped in the migration to the shared selector (selector
        // migration policy). A corpus disagreement sweep over 443
        // active-USB3 ports found zero cases where that fallback would have
        // fired and disagreed with PortSummary/JSONFormatter's selection
        // (see the commit introducing this), so dropping it is not a
        // behaviour change in practice, only in the (previously unreachable)
        // worst case.
        // Tunnelled entries are excluded: portKey is
        // parentPortType/parentPortNumber, so a dock's tunnelled
        // Port-USB-C@N/CIO/USB3@0 node shares this port's key and could be
        // selected as the port's own link, which would let a dock's plumbing
        // drive this port's verdict (including the blocked-by-security one
        // below). PortSummary applies the same exclusion via the same
        // selector; the two can never disagree, which is the bug that
        // started this.
        let usb3 = port.transportsActive.contains("USB3")
            ? USB3SpeedCorroboration.selectedTransport(for: port, in: usb3Transports)
            : nil

        // issue #181: require corroboration (an enumerated
        // SuperSpeed device, or a TRM restriction on the selected transport
        // -- the SAME predicate `.blockedBySecurity` below keys on) before
        // trusting the transport's signaled speed at all. Without this, the
        // HPM controller's brief USB3 handshake on a charger-only cable
        // (no SuperSpeed peer) produces a transient "Running at N Gbps"
        // verdict that PD negotiation is about to withdraw. Gating on
        // corroboration here, rather than nil-ing `usb3ActiveGbps`
        // unconditionally, is deliberate: a restricted transport IS
        // corroborated (by definition, via the second arm below), so this
        // gate does not touch the `.blockedBySecurity` path -- nil-ing
        // `usb3ActiveGbps` outright would make `active` nil and return
        // before `.blockedBySecurity` is ever constructed.
        let usb3Corroborated = USB3SpeedCorroboration.isCorroborated(selected: usb3, devices: devices)

        // The speed the link actually negotiated: the Thunderbolt link if
        // there is one, otherwise the USB 3 rate of the Mac-to-first-device
        // link. On a hub that uplink is the only link the cable verdict is
        // about, so we read the directly-attached (root) SuperSpeed device
        // and ignore the slower links living deeper inside the hub. Gated on
        // TransportsActive carrying USB3 (issue #187) AND corroboration
        // mirroring the port summary's own `usb3Speed` resolution.
        let usb3ActiveGbps = port.transportsActive.contains("USB3") && usb3Corroborated
            ? Self.usb3ActiveGbps(usb3: usb3, devices: devices)
            : nil
        let activeGbps = tbActiveGbps
            ?? Self.activeTBGbps(port: port, switches: thunderboltSwitches)
            ?? usb3ActiveGbps

        // Without a known active speed there is no data-speed verdict to
        // give. Returning nil keeps this off ports that are charge-only or
        // where the link state isn't readable yet.
        guard let active = activeGbps else { return nil }

        // A port cannot be slower than a link it trained, so a host figure
        // meaningfully below `active` is wrong rather than binding and is
        // dropped from the facts and the comparison, the same way a
        // direct-partner device cap is (`deviceCapDropped` below). The
        // corpus holds one such port: an asymmetric TB5 link at 120 whose
        // `supportedSpeed` mask assumes two lanes and reads 80. The mask
        // itself is the rate model's business, not this diagnostic's.
        let hostCapDropped = resolvedHostMaxGbps.map { Self.capContradictsActive($0, active: active) } ?? false
        let reportedHostGbps = hostCapDropped ? nil : resolvedHostMaxGbps

        // TRM (Trust and Restrict Management) short-circuit. When macOS has
        // blocked data on the USB3 transport, the transport's signaling rate
        // is still present (hence `active` is non-nil above) but no data
        // actually flows until the user approves the accessory. Reporting a
        // healthy "Running at X Gbps" verdict in this state is false
        // reassurance. The signaled rate goes into `signaledGbps`
        // so the verdict can say what the link *would* do once approved.
        // This check runs before the cable-speed resolution so it takes
        // precedence over all speed-based verdicts.
        if usb3?.transportRestricted == true,
           let signaledGbps = Self.usb3Gbps(usb3?.signaling) {
            self.cableSignalConflict = false
            self.facts = Facts(
                hostGbps: reportedHostGbps,
                cableEmarkerGbps: nil,
                cableControllerGbps: nil,
                cableGbps: nil,
                deviceGbps: nil,
                deviceName: nil,
                activeGbps: active
            )
            self.bottleneck = .blockedBySecurity(signaledGbps: signaledGbps)
            self.summary = String(localized: "Data blocked by macOS accessory security", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "The link is capable of \(Self.label(signaledGbps)), but macOS is blocking data until you approve the accessory. Click Allow on the connection prompt, or check System Settings > Privacy & Security > Allow accessories to connect, then replug.", bundle: _coreLocalizedBundle)
            return
        }

        // The Thunderbolt controller's claim about the cable and peer pair.
        // It is not the trained lane: the corpus shows it sitting a tier
        // above the lane the port actually runs, on peers that cannot run
        // that tier at all (31 of 378 replayed ports above the lane; 13 of
        // 70 code-4 ports on endpoints that cannot run 80), so it is a
        // FLOOR on cable capability and never a cap or a measurement (issue
        // #393: a genuine 80 Gbps CableMatters TB5 cable between two
        // 40 Gbps endpoints negotiates 40, but it is still an 80 Gbps
        // cable). Only the confirmed codes are mapped; unknown codes stay
        // nil rather than guess (mirrors CIOCableCapability.speedLabel's
        // conservatism).
        let cioGbps = Self.cioCableGbps(cio?.negotiatedLinkSpeed)
        // A CIO row is live only when the port's active transports include
        // CIO: the watcher passes every IOPortTransportStateCIO node whether
        // or not its Active flag is set, and 4 corpus ports carry an
        // Active: false row on a CC-only port. `activeTBGbps` gates on the
        // same transport list, so the floor and the contradiction gate
        // below share its notion of live. `cioGbps` and the facts keep
        // reading the row as it is.
        let liveCIO = port.transportsActive.contains("CIO") ? cio : nil

        // Cable's claimed speed from its e-marker (SOP' / SOP'').
        let cableIdentity = identities
            .first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime })
        var emarkerGbps = cableIdentity?.cableVDO?.speed.maxGbps
        // PD spec-revision ambiguity: the e-marker encoding "Gen3" means
        // 20 Gbps under PD 3.0 but 40 Gbps under PD 3.1, and the revision
        // is not readable from the e-marker fields, so the decoder
        // hardcodes 40 (see research/usb-spec-reference.md). When the
        // controller measured the link at 20, the PD 3.0 reading (a real
        // TB3-era 20 Gbps passive cable) is the one consistent with the
        // evidence; assuming 40 here would flag a healthy TB3 cable as
        // "running slower than expected". Resolve the ambiguous claim to
        // the floor's reading.
        if cableIdentity?.cableVDO?.speed == .usb4Gen3, cioGbps == 20 {
            emarkerGbps = 20
        }

        // The e-marker describes what the cable itself claims; CIO is the
        // controller's claim about the cable and peer. Resolve the two:
        //   - Same tier: agreement, no conflict, take the (equal) value.
        //   - CIO tier HIGHER than the e-marker: the controller's figure
        //     is the cable figure. It is a note only when the e-marker
        //     claimed a USB4 speed of its own (Gen 3 or Gen 4 speed bits)
        //     and the live lane agrees with the controller (issue #111:
        //     a TB4 cable whose e-marker under-reports). The e-marker's
        //     speed field describes USB data only, so a USB-only figure
        //     (USB 2.0, Gen 1, Gen 2) under a Thunderbolt link is normal,
        //     not a disagreement. An active-cable VDO is not a speed
        //     claim either: an active Thunderbolt 3 cable with a USB 2.0
        //     data path is the normal design for that generation (the LG
        //     UltraFine 5K bundled cable, issue #331). On the unfixed code
        //     the note fired on 93 of 383 replayed ports, 81 of them a
        //     passive USB 3.2 Gen 2 e-marker under a 20 or 40 Gbps
        //     controller figure; 4 survive, every one a passive e-marker
        //     claiming USB4 Gen 3 under a controller figure of 80 with
        //     the lane at 80. A CIO figure the lane does not corroborate
        //     is a claim, handled below, not a note.
        //   - CIO tier LOWER than the e-marker: NOT a conflict. Both can
        //     be true at once (the cable claims 80, but only ran at 40
        //     because that's all the peer allowed). The e-marker's claim
        //     is the cable figure here; the negotiated rate already lives
        //     in `active`. (This direction used to be treated as "the
        //     controller always wins", on the theory that a higher
        //     e-marker claim must be a lying cable (issue #190). Issue
        //     #393 proved that assumption wrong for genuine cables: CIO
        //     is a floor, not a ceiling, so a claim above it is not by
        //     itself evidence of anything. Suspicion about a specific
        //     cable is CableTrust's job, not this tiebreak's.)
        //   - Only one signal present: use it, no conflict.
        //   - Neither present: unknown, no conflict.
        let emarkerClaimsUSB4Speed = cableIdentity?.cableVDO.map {
            $0.speed == .usb4Gen3 || $0.speed == .usb4Gen4
        } ?? false
        let conflict: Bool
        var cableMaxGbps: Double?
        switch (emarkerGbps, cioGbps) {
        case let (e?, c?):
            if Self.sameTier(e, c) {
                conflict = false
                cableMaxGbps = max(e, c)
            } else if c > e {
                conflict = emarkerClaimsUSB4Speed && Self.sameTier(c, active)
                // A USB-only speed field says nothing about Thunderbolt, so
                // the controller's figure stands in for it. A USB4 Gen 3 or
                // Gen 4 claim is the cable's own Thunderbolt rating, and a
                // controller tier above it that the lane has not carried is
                // an uncorroborated claim about the cable and peer (13 of
                // 70 code-4 ports sit on endpoints that cannot run 80), so
                // the rating stays until the lane proves more.
                cableMaxGbps = (emarkerClaimsUSB4Speed && !Self.sameTier(c, active)) ? e : c
            } else {
                conflict = false
                cableMaxGbps = e
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
        // A live CIO row (CIO among the active transports) means the
        // Thunderbolt link is up and demonstrably carried `active`. A cable
        // figure below that is self-refuting in
        // the same way a direct-partner cap below it is
        // (`capContradictsActive`): the e-marker's USB-only speed field, or
        // an unmapped CIO code such as CableSpeed 0, is not evidence
        // against the link. Floor the figure at the lane rate so the USB
        // field never becomes the verdict's floor.
        if liveCIO != nil, let c = cableMaxGbps, Self.capContradictsActive(c, active: active) {
            cableMaxGbps = active
        }
        // Cable / active-rate contradiction detection. When the resolved
        // cable speed is meaningfully below the active rate, one of the
        // two signals is wrong. The earlier silent promotion (issue #195
        // follow-up) assumed the cable e-marker must be the wrong one,
        // which masked legitimate slow cables whenever the active reading
        // was itself unreliable (e.g. a topology leak before the per-port
        // gating in this commit, or any future leak we miss). The honest
        // answer is to surface the contradiction.
        //
        // The gate is the absence of a live controller row (CIO among the
        // active transports), not of a mapped controller figure. It exists
        // for the no-controller USB3 path, where the active reading itself
        // can be unreliable and the e-marker is the only other signal. With
        // a live CIO row the link is demonstrably up at `active` and the
        // floor above has already settled the figure; stating
        // `liveCIO == nil` here anyway makes the rule explicit rather than
        // a side effect of the floor.
        let cableContradiction: Bool
        if let c = cableMaxGbps, c < active, !Self.sameTier(c, active), liveCIO == nil {
            cableContradiction = true
        } else {
            cableContradiction = false
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
        //
        // On a multi-hop chain (issue #507: a TB2-to-TB3 adapter sitting
        // between the host and a TB1 drive) the direct partner is the
        // adapter, not the real device. Using the adapter's capability
        // mask blames the cable for a gap that is actually the drive's own
        // ceiling. `deepTerminalSwitch` walks past the adapter to the
        // chain's actual endpoint on a genuine daisy-chain, and stays nil
        // (falling back to the direct partner) on a single hop or on a
        // branching tree, where "the terminal device" isn't a well-defined
        // single answer.
        let partner = Self.partnerSwitch(port: port, switches: thunderboltSwitches)
        let terminal = Self.deepTerminalSwitch(port: port, switches: thunderboltSwitches)
        let fastestDevice = devices
            .filter { $0.speedRaw != nil }
            .max { (Self.deviceGbps($0.speedRaw) ?? 0) < (Self.deviceGbps($1.speedRaw) ?? 0) }
        let usbDeviceGbps = Self.deviceGbps(fastestDevice?.speedRaw)
        let rawDeviceMaxGbps: Double?
        // Where the figure came from. `active` is the FIRST HOP's rate
        // (`activeTBGbps` reads the host's own downstream lane), so only a cap
        // describing the direct partner is comparable to it at all. A terminal
        // switch further down the chain, and a USB device tunnelled behind the
        // partner, both describe a different link and are legitimately slower
        // than the one carrying them.
        let deviceCapIsDirectPartner: Bool
        if let terminal {
            rawDeviceMaxGbps = terminal.supportedSpeed.maxTotalGbps
                ?? Self.terminalLegActiveGbps(terminal)
                ?? Self.activeTBGbps(port: port, switches: thunderboltSwitches)
            deviceCapIsDirectPartner = false
        } else if let partner {
            rawDeviceMaxGbps = partner.supportedSpeed.maxTotalGbps
                ?? Self.activeTBGbps(port: port, switches: thunderboltSwitches)
            deviceCapIsDirectPartner = true
        } else {
            // A device that declares SuperSpeed in its BOS or bcdUSB but
            // enumerated at 480 Mbps is not evidence against the cable.
            // Across the customer-probe corpus (probe 25's declared-versus-
            // negotiated speed joined to probe 38's wiring path, two parsers
            // agreeing), 130 such rows on 68 machines sit with every hub
            // above them at USB 2.0 (USB 2.0 companion hubs inside docks,
            // and cameras such as a Logitech C920 behind one); rows where a
            // faster hop sits above the device are 3 in 7815, each
            // explained by a Gen 1 port or hop.
            //
            // So no cable-limit verdict is ever derived from BOS or
            // declared-speed data here. Do not add one without an
            // SS-capable hop above the device (a hub or port that itself
            // enumerated at SuperSpeed), and even then the hub is the first
            // suspect, not the cable.
            //
            // Reachability note: this arm only runs with no Thunderbolt
            // partner, and `active` is nil unless a SuperSpeed device is in
            // the native list or the transport is TRM-restricted, so the
            // fastest device here is already SuperSpeed; a 480 Mbps device
            // limit cannot be produced on this path in production.
            rawDeviceMaxGbps = usbDeviceGbps
            deviceCapIsDirectPartner = false
        }
        // TB1/TB2-era device cap (issue #515): the device figure comes from
        // the terminal switch when there is a genuine multi-hop chain,
        // otherwise the direct partner (the same switch the branches above
        // read from). Capping here covers both the supportedSpeed-mask path
        // and the terminalLegActiveGbps fallback in one place.
        let deviceCapGbps = (terminal ?? partner)?.deviceGenerationCapGbps
        let deviceMaxGbps: Double?
        if let raw = rawDeviceMaxGbps, let cap = deviceCapGbps {
            deviceMaxGbps = min(raw, cap)
        } else {
            deviceMaxGbps = rawDeviceMaxGbps
        }

        // A direct partner's cap that sits meaningfully below the rate the
        // first hop demonstrably carried is self-refuting: the switch on the
        // other end of this cable took part in that link. Such a figure is
        // dropped from the comparison AND from the reported facts, so no
        // consumer prints a capability the diagnostic decided not to trust.
        let deviceCapDropped = deviceMaxGbps.map {
            deviceCapIsDirectPartner && Self.capContradictsActive($0, active: active)
        } ?? false
        let reportedDeviceGbps = deviceCapDropped ? nil : deviceMaxGbps
        // A dropped device figure never enters `caps`, so it can't be named
        // in a cable-limit/host-limit detail either: those sentences build
        // from `fasterOthers`, which only ever lists parties actually in
        // `caps`.

        // Capture the resolved figures for the Pro breakdown. Every
        // constructed instance flows through here (the only earlier return
        // is the no-active-speed guard, which yields no instance).
        let deviceLabel: String?
        if let terminal {
            deviceLabel = terminal.modelName
        } else if let partner {
            deviceLabel = partner.modelName
        } else {
            deviceLabel = fastestDevice?.productName
        }

        self.facts = Facts(
            hostGbps: reportedHostGbps,
            cableEmarkerGbps: emarkerGbps,
            cableControllerGbps: cioGbps,
            cableGbps: cableMaxGbps,
            deviceGbps: reportedDeviceGbps,
            deviceName: deviceLabel,
            activeGbps: active
        )

        let conflictNote = conflict
            ? " " + String(localized: "The cable's e-marker and the Thunderbolt controller disagree on its speed. The controller measured a higher, confirmed rate, so that figure is used.", bundle: _coreLocalizedBundle)
            : ""

        // Cable / active-rate contradiction short-circuit. When the
        // e-marker claims a speed meaningfully below the active rate and
        // CIO is not available to break the tie, report the contradiction
        // honestly rather than picking a side. Trying a known-good cable
        // is the only reliable way for the user to resolve it.
        if cableContradiction, let cableClaim = cableMaxGbps {
            self.bottleneck = .cableContradictsActive(cableGbps: cableClaim, activeGbps: active)
            self.summary = String(localized: "Cable says \(Self.label(cableClaim)), link reads \(Self.label(active))", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "The cable's e-marker reports \(Self.label(cableClaim)), but the active link is reading \(Self.label(active)). One of those readings is wrong, and without a Thunderbolt controller cross-check we can't tell which. Trying a known-good cable will identify the culprit.", bundle: _coreLocalizedBundle)
            return
        }

        // Every capability we actually know about, tagged by party. The
        // link can never run faster than the slowest of these.
        //
        // The dropped direct-partner and host caps (`deviceCapDropped` and
        // `hostCapDropped` above) never enter the comparison, so they can
        // neither become the floor nor be blamed. The cable cap is left
        // alone here: it already has its own floor and
        // `cableContradictsActive` short-circuit above.
        var caps: [(party: String, value: Double)] = []
        if let c = cableMaxGbps         { caps.append((party: "cable",  value: c)) }
        if let h = reportedHostGbps     { caps.append((party: "host",   value: h)) }
        if let d = reportedDeviceGbps   { caps.append((party: "device", value: d)) }

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
            // Inside this branch every known cap is above `active`, so a
            // non-nil cable figure is always an unverified claim here:
            // nobody has seen the cable carry it, whether it came from the
            // e-marker or from the controller. A claim, or a fast host, or
            // both, never earn `.degraded` on their own (issue #393: a
            // known-fast host with an unknown device is a healthy link,
            // not a fault). Only a device demonstrably capable of more
            // than the link carried does, and then only with a cable
            // figure in hand: with none, the cable is the honest suspect
            // and the verdict says so rather than blaming the link.
            let deviceExceedsActive = deviceMaxGbps
                .map { Self.meaningfullySlower(active, than: $0) } ?? false
            if !deviceExceedsActive || cableMaxGbps == nil {
                self.bottleneck = .unknownCable(activeGbps: active)
                self.summary = String(localized: "Running at \(Self.label(active))", bundle: _coreLocalizedBundle)
                if let claim = cableMaxGbps {
                    if reportedHostGbps != nil {
                        // The host figure IS known here (it's just not the
                        // reason this branch fired: the device is what's
                        // unresolved). Naming "no host ... data" would be
                        // false, so this variant names only the device.
                        self.detail = String(localized: "The cable claims \(Self.label(claim)), and the link has run at least \(Self.label(active)). There's no device data to compare against, so we can't tell if anything else is limiting it.", bundle: _coreLocalizedBundle)
                    } else {
                        self.detail = String(localized: "The cable claims \(Self.label(claim)), and the link has run at least \(Self.label(active)). There's no host or device data to compare against, so we can't tell if anything else is limiting it.", bundle: _coreLocalizedBundle)
                    }
                } else {
                    self.detail = String(localized: "This cable has no e-marker and no controller data, so we can't tell whether it is the limit.", bundle: _coreLocalizedBundle)
                }
                return
            }

            // Slower than a device we can see doing more, with a cable
            // figure that says the same. Something unidentified degraded
            // it. Never claim "full speed" here (the old draft bug).
            self.bottleneck = .degraded(activeGbps: active, expectedGbps: expected)
            self.summary = String(localized: "Running slower than expected (\(Self.label(active)))", bundle: _coreLocalizedBundle)
            self.detail = String(localized: "The parts we can see all support \(Self.label(expected)) or more, but the link came up slower. Reseating the cable or trying another port may help.", bundle: _coreLocalizedBundle) + conflictNote
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

        // Which OTHER parties actually resolved faster than the floor,
        // named individually rather than assumed as a fixed pair: a party
        // absent from `fasterOthers` was never resolved, and naming it
        // anyway (the old "Mac and device" / "cable and device" wording)
        // claims a figure nobody measured. `fasterOthers` can never
        // contain `culprit` itself (it's tied at the floor, not faster
        // than it), so for "cable" this is host and/or device, and for
        // "host" it's cable and/or device.
        let fasterParties = Set(fasterOthers.map(\.party))

        switch culprit {
        case "cable":
            self.bottleneck = .cableLimit(cableGbps: expected, capableGbps: capable)
            self.summary = String(localized: "Cable is limiting data speed", bundle: _coreLocalizedBundle)
            if fasterParties == ["host"] {
                self.detail = String(localized: "The Mac can do \(Self.label(capable)), but the cable only carries \(Self.label(expected)). A faster cable would unlock full speed.", bundle: _coreLocalizedBundle) + conflictNote
            } else if fasterParties == ["device"] {
                self.detail = String(localized: "The device can do \(Self.label(capable)), but the cable only carries \(Self.label(expected)). A faster cable would unlock full speed.", bundle: _coreLocalizedBundle) + conflictNote
            } else {
                // Both host and device resolved faster: keep the original
                // two-party English text byte-identical so its existing
                // translations aren't invalidated.
                self.detail = String(localized: "The Mac and device can do \(Self.label(capable)), but the cable only carries \(Self.label(expected)). A faster cable would unlock full speed.", bundle: _coreLocalizedBundle) + conflictNote
            }
        case "host":
            self.bottleneck = .hostLimit(hostGbps: expected, capableGbps: capable)
            self.summary = String(localized: "This Mac port limits data speed", bundle: _coreLocalizedBundle)
            if fasterParties == ["cable"] {
                self.detail = String(localized: "The cable can do \(Self.label(capable)), but this port maxes out at \(Self.label(expected)).", bundle: _coreLocalizedBundle) + conflictNote
            } else if fasterParties == ["device"] {
                self.detail = String(localized: "The device can do \(Self.label(capable)), but this port maxes out at \(Self.label(expected)).", bundle: _coreLocalizedBundle) + conflictNote
            } else {
                // Both cable and device resolved faster: keep the original
                // two-party English text byte-identical.
                self.detail = String(localized: "The cable and device can do \(Self.label(capable)), but this port maxes out at \(Self.label(expected)).", bundle: _coreLocalizedBundle) + conflictNote
            }
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
    ///
    /// Reads the lane port's width-aware `activeGbps` (per-lane Gbps times
    /// trained TX lanes), not the generation's dual-lane headline: a link
    /// trained down to one lane runs at half the headline, and the corpus
    /// confirms the width-aware figure against `Link Bandwidth`.
    ///
    /// Gated on `transportsActive.contains("CIO")`: on Apple Silicon the
    /// internal root-to-downstream-switch lane is always reported as
    /// active even when no user cable is plugged in, so reading the lane
    /// state without a "this port is actually carrying TB" signal would
    /// attribute internal-link speed to the user's cable (issue #195
    /// follow-up: this is what produced the "40 Gbps" reading on a port
    /// holding a USB 2.0 cable). CIO in `transportsActive` is the
    /// authoritative "the user's cable is doing Thunderbolt" signal.
    static func activeTBGbps(
        port: AppleHPMInterface,
        switches: [IOThunderboltSwitch]
    ) -> Double? {
        guard port.transportsActive.contains("CIO"),
              !switches.isEmpty,
              let socketID = ThunderboltTopology.socketID(for: port),
              let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches),
              let hostPort = ThunderboltTopology.trainedDownstreamLanePort(root),
              let negotiated = hostPort.activeGbps else {
            return nil
        }
        // TB1/TB2-era first-hop partner (issue #515): code 0x8 reads as a
        // real Gen 2 link at 10 Gb/s per trained lane, but a TB1/TB2 device
        // negotiates less than even that.
        // Cap with the directly-connected partner's device-generation
        // ceiling, not the terminal device's: a dock's own link genuinely
        // runs at its rated speed even when a TB1 leaf hangs off it further
        // down the chain, so only the FIRST hop's own class matters here.
        if let cap = Self.partnerSwitch(port: port, switches: switches)?.deviceGenerationCapGbps {
            return min(negotiated, cap)
        }
        return negotiated
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
              let socketID = ThunderboltTopology.socketID(for: port),
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
              let socketID = ThunderboltTopology.socketID(for: port),
              let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches),
              let hostLanePort = root.ports.first(where: {
                  $0.adapterType.isLane && $0.socketID == socketID
              }) else {
            return nil
        }
        // Both lanes of the socket. One physical socket is a pair of lane
        // adapters sharing a Socket ID and only one of the pair carries the
        // route byte, so resolving the socket to its first lane and stopping
        // there would lose the partner whenever the byte names the other.
        // `ThunderboltTopology.isLinked` reads the same socket the same way,
        // through the same helper, so the two cannot disagree about whether
        // there is a partner on this lane.
        for lane in ThunderboltTopology.socketLanePorts(of: hostLanePort, on: root) {
            if let partner = ThunderboltTopology.childSwitch(
                below: root,
                onPortNumber: lane.portNumber,
                in: switches
            ) {
                return partner
            }
        }
        return nil
    }

    /// The switch at the far end of a genuine multi-hop Thunderbolt daisy
    /// chain (an adapter or hub sitting between the host and the real
    /// device), or `nil` when there's only one hop or the topology
    /// branches (issue #507).
    ///
    /// A single hop already has the right answer from `partnerSwitch`
    /// (issue #190: a direct-attach TB drive with no enumerated USB
    /// device). This only fires for two-or-more-hop linear chains, where
    /// `partnerSwitch` would return the first hop (e.g. a TB2-to-TB3
    /// adapter), not the device actually plugged in at the end of the
    /// cable run.
    ///
    /// Resolves the port-qualified direct partner first and walks/counts
    /// only within THAT partner's own subtree, never the whole root. A
    /// root can host more than one user-visible USB-C lane (asymmetric
    /// controllers, multi-port hubs); starting from the root instead of
    /// the partner would let a chain hanging off a SIBLING socket get
    /// attributed to this port, or let a sibling's own branching fabric
    /// make this port's genuinely linear chain look like it branches,
    /// silently disabling the fix on hardware that happens to have both.
    ///
    /// Mirrors the branching guard `PortSummary.thunderboltBullets` uses
    /// for its step-down bullet: on a branching tree (a dock fanning out
    /// to two Thunderbolt devices) there's no single "last" device, so we
    /// bail and let the caller fall back to the direct partner (the dock
    /// itself is the right comparator there).
    ///
    /// Walks only past a passthrough. A dock with a display behind it has
    /// the same two-hop shape as the adapter this was written for, but the
    /// dock IS what the cable is plugged into, and naming the panel at the
    /// end of the chain "the device on the cable" is wrong. The two are told
    /// apart by what the direct partner publishes: a passthrough exposes
    /// lane adapters only, while a dock, a display or a drive also exposes
    /// PCIe, DisplayPort or USB (`exposesNonLaneAdapters`).
    /// True when a switch publishes any adapter that is not a lane (physical
    /// Thunderbolt port) and not inactive.
    ///
    /// A passthrough adapter forwards the fabric and tunnels nothing itself,
    /// so it has lanes only. Anything that terminates a tunnel is a real
    /// endpoint: a dock, a display, a drive. The test is deliberately "not a
    /// lane" rather than a list of known protocol types, because an adapter
    /// type the decoder has not learned yet lands in `.other` and would
    /// otherwise read as a passthrough. TB5's USB Gen T adapter was exactly
    /// that until issue #52 named it.
    static func exposesNonLaneAdapters(_ sw: IOThunderboltSwitch) -> Bool {
        sw.ports.contains { port in
            switch port.adapterType {
            case .lane, .inactive:
                return false
            default:
                return true
            }
        }
    }

    static func deepTerminalSwitch(
        port: AppleHPMInterface,
        switches: [IOThunderboltSwitch]
    ) -> IOThunderboltSwitch? {
        guard let partner = Self.partnerSwitch(port: port, switches: switches) else {
            return nil
        }
        // A partner with no ports published is not evidence of a passthrough.
        // A dock whose adapters failed to enumerate looks identical to a bare
        // adapter here, and naming the leaf of the chain on that guess is the
        // worse error, so the walk stops rather than proceeds.
        guard !partner.ports.isEmpty else { return nil }
        // A partner that tunnels a protocol of its own is the device on the
        // cable, so the walk stops here.
        guard !Self.exposesNonLaneAdapters(partner) else { return nil }
        let chain = ThunderboltTopology.chain(from: partner, in: switches)
        let downstream = Array(chain.dropFirst())
        guard !downstream.isEmpty else { return nil }

        // If the partner's full subtree has more switches than the linear
        // chain found, this is a branching tree, not a daisy-chain: bail.
        let allDownstream = ThunderboltTopology.flatten(
            ThunderboltTopology.tree(from: partner, in: switches)
        )
        guard allDownstream.count == downstream.count else { return nil }

        return downstream.last
    }

    /// The active link rate of the leg arriving at a chain's terminal
    /// switch, used as the fallback when the terminal switch has no
    /// `supportedSpeed` mask of its own. The arriving leg is the
    /// terminal's own UPSTREAM lane (the port whose `portNumber` matches
    /// its `upstreamPortNumber`), not any downstream lane it might still
    /// expose: a downstream lane on a nominal terminal is left over from a
    /// child record that's temporarily absent (a fabric read mid-update),
    /// and reading it would report the leg toward a device that isn't
    /// there. Falls back to any active lane only when the upstream one
    /// isn't present or isn't active (a genuine leaf may only populate
    /// that one port anyway, so the fallback is usually a no-op).
    static func terminalLegActiveGbps(_ sw: IOThunderboltSwitch) -> Double? {
        let upstreamLeg = sw.ports.first {
            $0.adapterType.isLane && $0.portNumber == sw.upstreamPortNumber && $0.hasTrainedLanes
        }
        guard let leg = upstreamLeg
                ?? sw.ports.first(where: { $0.adapterType.isLane && $0.hasTrainedLanes }) else {
            return nil
        }
        return leg.activeGbps
    }

    /// USB 3 signaling generation to Gbps. 1 = Gen 1 (5), 2 = Gen 2 (10).
    static func usb3Gbps(_ signaling: Int?) -> Double? {
        switch signaling {
        case 1: return 5
        case 2: return 10
        default: return nil
        }
    }

    /// The negotiated USB 3 rate of the Mac-to-first-device link, in Gbps.
    ///
    /// On a hub, the directly-attached (root) SuperSpeed device is the
    /// Mac-to-hub uplink, the only link the cable verdict is about. Slower
    /// SuperSpeed links deeper inside the hub (a secondary 5 Gbps hub, a
    /// card reader) are the hub's internal wiring, not the cable, so they
    /// must not set the port's headline speed. We therefore prefer the root
    /// device's enumerated speed, then fall back to the controller's USB3
    /// transport signaling, then the port-name-matched device, exactly
    /// matching the source order `JSONFormatter`/`PortSummary` use for
    /// `usb3Speed`, so the headline and the bullet can never disagree
    /// (issue #245).
    ///
    /// The caller gates on `TransportsActive` carrying USB3 (issue #187: the
    /// controller can leave a stale SuperSpeed transport/device registered
    /// on a link that is really USB 2.0); this helper assumes USB3 is live.
    static func usb3ActiveGbps(usb3: USB3Transport?, devices: [USBDevice]) -> Double? {
        if let root = USBDevice.rootSuperSpeed(in: devices),
           let gbps = Self.deviceGbps(root.speedRaw) {
            return gbps
        }
        if let signaled = Self.usb3Gbps(usb3?.signaling) {
            return signaled
        }
        if let matched = USBDevice.portMatchedSuperSpeed(in: devices),
           let gbps = Self.deviceGbps(matched.speedRaw) {
            return gbps
        }
        return nil
    }

    /// CIO controller cable-speed code to Gbps. Confirmed codes:
    /// 2 = TB3 / 20, 3 = TB4 / 40, 4 = TB5 / 80.
    static func cioCableGbps(_ code: Int?) -> Double? {
        switch code {
        case 2: return 20
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

    /// True when a resolved endpoint cap contradicts the rate the link
    /// actually carried: the cap is meaningfully below `active`.
    ///
    /// An endpoint cannot be slower than a link it took part in, so such a
    /// cap is wrong rather than binding. Callers drop it instead of letting
    /// it set the floor and collect the blame. Uses `meaningfullySlower`, so
    /// a cap inside the same tier as `active` still counts as agreeing.
    static func capContradictsActive(_ cap: Double, active: Double) -> Bool {
        Self.meaningfullySlower(cap, than: active)
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
