import Foundation
import os.log

private let _portSummaryLog = Logger(subsystem: "uk.whatcable.whatcable", category: "port-summary")

/// Plain-English interpretation of a AppleHPMInterface's raw IOKit data.
public struct PortSummary {
    public enum Status {
        case empty
        case charging
        case batteryFull
        case dataDevice
        case thunderboltCable
        case displayCable
        case unknown
    }

    /// macOS reads the cable e-marker 5.0-5.6s after attach on a fixed
    /// schedule (research/emarker-read-timing.md, measured 2026-08-28).
    /// Until this much time has passed, "no SOP' node" means "not read
    /// yet", not "no e-marker".
    public static let emarkerReadWindow: TimeInterval = 6.0

    public let status: Status
    public let headline: String
    public let subtitle: String
    /// Every line, attributed to the source it came from. At most one group
    /// per `kind`, and empty groups are dropped. See `BulletGroup`.
    ///
    /// This is the authoritative representation. `bullets` is derived from it,
    /// so no caller can hand the two representations different content.
    public let groups: [BulletGroup]
    /// Structured negotiated link speed for badges / JSON. Nil when there's no
    /// active data link to badge (empty port, charge-only, display-only).
    public let linkSpeed: LinkSpeed?

    /// Flat text, for the JSON `bullets` key and the widget's one-line detail.
    ///
    /// A group's subtitle comes first, then its lines. The subtitle carries
    /// the read state ("not read on this connection"), which used to be an
    /// ordinary bullet, so including it here keeps flat consumers seeing
    /// everything they saw before the lines were attributed. The order across
    /// groups did change, but it was never a documented contract; the content
    /// is what scripts actually match on.
    public var bullets: [String] {
        groups.flatMap { group -> [String] in
            guard let subtitle = group.subtitle, !subtitle.isEmpty else { return group.lines }
            return [subtitle] + group.lines
        }
    }

    /// The single line of detail the desktop widget shows under the headline.
    ///
    /// Prefer a measurement, else whatever we have.
    ///
    /// This used to be equivalent to `bullets.first`, because the measured
    /// group sorted first and carries no subtitle. It is NOT equivalent any
    /// more: the e-marker group now leads the card, so `bullets.first` is
    /// usually a claim the cable made about itself. Naming the measured group
    /// explicitly is what keeps the widget leading with what is actually
    /// happening, and it is why card order can be changed for presentation
    /// without dragging the widget along with it.
    ///
    /// When nothing was measured, this is a read state rather than a fact
    /// about the cable, e.g. "Present, but not read on this connection". That
    /// is intended: it is the only useful thing to say on such a port, and it
    /// is what the widget showed before the lines were attributed, when the
    /// read state was an ordinary bullet that happened to sort first.
    public var topLine: String? {
        group(.measured)?.lines.first ?? bullets.first
    }

    public init(status: Status, headline: String, subtitle: String, groups: [BulletGroup] = [], linkSpeed: LinkSpeed? = nil) {
        self.status = status
        self.headline = headline
        self.subtitle = subtitle
        self.groups = groups
        self.linkSpeed = linkSpeed
    }
}

extension PortSummary {
    /// - Parameter isConnectedOverride: Pass `true`/`false` to bypass the
    ///   `port.connectionActive` flag. The menu-bar UI sets this from a live
    ///   union of the device/power/PD watchers because some Apple-silicon
    ///   controllers (notably AppleHPMInterfaceType11 / MagSafe) hold
    ///   ConnectionActive=true for several seconds after unplug, which left
    ///   the UI showing a phantom "Connected" card. Pass `nil` (the default)
    ///   to fall back to `port.connectionActive` for callers that don't
    ///   track the live signals (CLI / JSON snapshots).
    public init(
        port: AppleHPMInterface,
        sources: [PowerSource] = [],
        identities: [USBPDSOP] = [],
        devices: [USBDevice] = [],
        thunderboltSwitches: [IOThunderboltSwitch] = [],
        federatedIdentities: [FederatedIdentity] = [],
        usb3Transports: [USB3Transport] = [],
        trmTransports: [TRMTransport] = [],
        cioCapability: CIOCableCapability? = nil,
        // Apple's own name for what is attached, read from the port's UVDM
        // node. Nil for any non-Apple accessory, which never publishes one.
        accessoryIdentity: AppleAccessoryIdentity? = nil,
        isConnectedOverride: Bool? = nil,
        chargerWattageSource: ChargerWattageSource = .unknown,
        batteryFullyCharged: Bool? = nil,
        batteryIsCharging: Bool? = nil,
        adapter: AdapterInfo? = nil,
        // Nonnegative elapsed MONOTONIC seconds since CC attach. nil means
        // unknown: one-shot surfaces (CLI, widget extension), or the first
        // observation of a connection that was already active when the
        // observer started (app relaunch mid-connection). Exactly
        // `emarkerReadWindow` is post-window (`age < window` is the reading
        // test). Unknown age must never produce the reading state; it always
        // renders post-window wording.
        connectionAge: TimeInterval? = nil
    ) {
        let connected = isConnectedOverride ?? (port.connectionActive == true)
        let active = port.transportsActive
        let supported = port.transportsSupported
        // USB3 is "live" only when `TransportsActive` says so. The HPM
        // port controller can keep `IOAccessoryUSBSuperSpeedActive=1` and
        // a lingering `IOPortTransportStateUSB3` service even when the
        // negotiated link is only USB 2.0 (e.g. a Micro-USB cable that
        // physically can't carry SuperSpeed). See issue #187.
        let hasUSB3 = active.contains("USB3")
        // issue #181: the HPM port controller briefly publishes
        // USB3 in TransportsActive during cable orientation / SuperSpeed
        // handshake even for a charger-only cable with no SuperSpeed peer;
        // PD negotiation then withdraws it. Printing a speed line for that
        // instant reads as WhatCable losing information it briefly had.
        // `hasCorroboratedUSB3` requires either an enumerated SuperSpeed
        // device or a TRM restriction on the selected transport (the same
        // predicate `.blockedBySecurity` keys on) before any USB3 speed
        // string is emitted. See USB3SpeedCorroboration and
        // planning/dar-50-usb3-speed-corroboration.md.
        let selectedUSB3Transport = USB3SpeedCorroboration.selectedTransport(for: port, in: usb3Transports)
        let hasCorroboratedUSB3 = hasUSB3
            && USB3SpeedCorroboration.isCorroborated(selected: selectedUSB3Transport, devices: devices)
        let hasUSB2 = active.contains("USB2")
        let hasTB = active.contains("CIO") // Thunderbolt = Converged I/O
        let hasDP = active.contains("DisplayPort")
        // Configuration Channel: required for USB-PD. Without CC the OS cannot
        // run Discover Identity, so we can't infer anything about the cable's
        // e-marker. M4 Mac Mini front USB-C ports are an example: they hang
        // off a plain xHCI controller (no PD), so reporting "basic cable" on
        // them wrongly blames the cable. See issue #50.
        let pdCapable = supported.contains("CC")
        // Data withheld by macOS accessory security.
        //
        // Two rules, both learned the hard way.
        //
        // 1. The gate is "the transport is in TransportsActive AND its
        //    restricted flag is set", never the flag alone. macOS leaves a
        //    withheld transport listed in TransportsActive and marks the node
        //    Active=Yes while refusing authorisation, which is why the headline
        //    used to claim a live link. But an accessory with no data to offer
        //    ALSO carries transportRestricted=true, with a valid signalling
        //    rate, and is not blocked: it never asked. Measured on hardware
        //    2026-07-30, a denied phone and an iPad keyboard were identical on
        //    every other field. DataLinkDiagnostic gates on the same thing,
        //    which is why it already got this right. Keep the two in step.
        //
        // 2. EVERY active data transport must be withheld, not just one. A
        //    port can run USB2 and USB3 at once with only one of them held
        //    back (m5pro_macos27.0 port 1 in the corpus: USB2 withheld, USB3
        //    running). That port really does carry data, so calling it blocked
        //    would swap one false claim for another.
        //
        // Tunnelled transports are excluded throughout: portKey is
        // parentPortType/parentPortNumber, so a dock's tunnelled node shares
        // this port's key and would otherwise report the dock's plumbing as a
        // property of the physical port.
        //
        // DELIBERATE GAP: the `hasTB` branch below does NOT consume this
        // verdict, so a Thunderbolt port whose CIO transport is withheld keeps
        // its ordinary "Thunderbolt / USB4" wording. That is scoped out, not
        // overlooked. No CIO transport is restricted anywhere in the corpus
        // (0 of 739 machines) and none has been seen on hardware, so there is
        // nothing to write wording against, and inventing a message for a
        // state nobody has observed is how the last round of guesses got
        // walked back. CIO stays in the set below because it is the correct
        // denominator: if the TB branch ever does consume the verdict, an
        // active healthy CIO link must count as data flowing. Pinned by
        // `thunderboltPortIgnoresTheWithheldVerdict` so a future change here
        // is a conscious one.
        let activeDataTransports = active.filter { $0 == "USB2" || $0 == "USB3" || $0 == "CIO" }
        let dataWithheld = !activeDataTransports.isEmpty && activeDataTransports.allSatisfy { type in
            if type == "USB3" {
                // Read USB3 restriction from the SAME selected transport the
                // speed label, corroboration, and DataLinkDiagnostic verdict
                // all read (USB3SpeedCorroboration.selectedTransport), not a
                // `contains` scan over every canonically-matching entry. A
                // `contains` scan can disagree with the selector: an
                // exact-UUID transport that is unrestricted, alongside a
                // weaker same-portKey record that IS restricted, would have
                // this arm call the port blocked while the selector (and the
                // speed label built from it) call the link fine.
                // Disagreement between the headline and the diagnostic
                // underneath is the entire bug this branch exists to fix.
                return selectedUSB3Transport?.transportRestricted == true
            }
            // USB2 (and CIO) have no transport model of their own; TRM carries
            // their restricted flag.
            return trmTransports.contains {
                $0.canonicallyMatches(port: port)
                    && $0.transportType == type
                    && $0.tunnelled != true
                    && $0.transportRestricted == true
            }
        }

        // E-marker presence is "did the cable respond to Discover Identity?",
        // which means we have an SOP'/SOP'' USBPDSOP for this port. The
        // port's `ActiveCable` IOKit flag means "this cable contains active
        // signal-conditioning electronics", which is unrelated: passive
        // cables (including high-end USB4 / 240W EPR cables) carry e-markers
        // too.
        let hasEmarker = identities.contains {
            $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
        }
        let portLabel = port.portDescription ?? port.serviceName

        if !connected {
            self.status = .empty
            self.headline = String(localized: "Nothing connected", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "Plug a cable into \(portLabel) to see what it can do.", bundle: _coreLocalizedBundle)
            self.groups = []
            self.linkSpeed = nil
            return
        }

        // Lines are attributed to the source they came from, because the four
        // sources have four different reliabilities and describe different
        // physical objects. A claim by the cable or the charger must never be
        // rendered as a fact. See planning/port-card-source-attribution.md.
        //
        //   measured  - the Mac's own controllers: link state, negotiated
        //               contract, what's plugged in
        //   emarker   - what the cable says about itself
        //   charger   - what the charger says about itself
        //   database  - what our bundled vendor / cable / certification data
        //               makes of the identifiers above
        var measured: [String] = []
        var emarkerLines: [String] = []
        var chargerLines: [String] = []
        var databaseLines: [String] = []
        // "We couldn't read it" is the state of the e-marker group, not a
        // value inside it, so it lives here rather than as a bullet.
        var emarkerSubtitle: String?

        // ------------------------------------------------------------
        // measured: live link / what's plugged in
        // ------------------------------------------------------------

        if hasTB {
            // If we have a matching Thunderbolt switch graph for this port,
            // emit specific link-state bullets (negotiated speed, lane
            // count, daisy-chain info). Otherwise fall back to the generic
            // "active" line so older paths still work.
            let tbBullets = thunderboltBullets(for: port, switches: thunderboltSwitches)
            if tbBullets.isEmpty {
                measured.append(String(localized: "Thunderbolt / USB4 link active", bundle: _coreLocalizedBundle))
            } else {
                measured.append(contentsOf: tbBullets)
            }
        } else if hasCorroboratedUSB3 {
            // Speed selection order:
            //   1. Root device (directly attached, `isRootDevice`). Its
            //      `Device Speed` reflects the upstream link end-to-end and
            //      can't be inflated by a hub in the middle.
            //   2. HPM transport's `SuperSpeedSignaling`, when present
            //      (non-nil after the signaling==0 fix). Authoritative for
            //      the port-side link generation.
            //   3. Port-matched-by-name fallback: highest-speed device that
            //      maps to this port via `controllerPortName`. Covers Apple
            //      Silicon front USB-C ports whose internal virtual root
            //      inflates locationID nibbles, hiding the actual root
            //      device from step 1. Only fires when both 1 and 2 are
            //      empty so a known-Gen-1 HPM reading still beats a
            //      seemingly-Gen-2 downstream device (see Codex review).
            let rootDeviceLabel = USBDevice.rootSuperSpeed(in: devices)?.usb3SpeedLabel
            let transportLabel = selectedUSB3Transport?.speedLabel
            let portMatchedLabel = USBDevice.portMatchedSuperSpeed(in: devices)?.usb3SpeedLabel

            if let deviceLabel = rootDeviceLabel, let hpmLabel = transportLabel,
               deviceLabel != hpmLabel {
                let portName = port.serviceName
                _portSummaryLog.warning("USB3 speed mismatch on \(portName): device=\(deviceLabel) HPM=\(hpmLabel)")
            }

            // Second-tier disagreement: no root device qualified, but the
            // controller-port-name-matched device disagrees with the HPM
            // transport. Transport wins (see selection order), but log so
            // we have visibility if Apple's virtual-root behaviour changes
            // or a deeply-hubbed device sneaks past the controllerPortName
            // filter.
            if rootDeviceLabel == nil,
               let portLabel = portMatchedLabel, let hpmLabel = transportLabel,
               portLabel != hpmLabel {
                let portName = port.serviceName
                _portSummaryLog.warning("USB3 speed mismatch on \(portName): portMatched=\(portLabel) HPM=\(hpmLabel)")
            }

            if let label = rootDeviceLabel ?? transportLabel ?? portMatchedLabel {
                measured.append(label)
            } else {
                measured.append(String(localized: "SuperSpeed USB (5 Gbps or faster)", bundle: _coreLocalizedBundle))
            }
        } else if hasUSB2 {
            measured.append(String(localized: "USB 2.0 only (480 Mbps), no high-speed data", bundle: _coreLocalizedBundle))
        }

        if hasDP {
            // `hasDP` and `dpLaneConfig` are gated on the same signal
            // (DisplayPort in transportsActive), so the config is always
            // present here; no plain-video fallback is reachable.
            if let dpConfig = port.dpLaneConfig {
                measured.append(String(localized: "Carrying DisplayPort video (\(dpConfig.label))", bundle: _coreLocalizedBundle))
            }
        }

        // A controller can retain a winning PDO while the system rejects
        // external power. In that state the source still describes the port's
        // last negotiation, but it must not drive charging copy or wattage.
        // See SystemPowerState.onBattery for the full rationale (including why
        // battery-full is deliberately not part of the test).
        let systemPowerUnavailable = SystemPowerState.onBattery(
            batteryIsCharging: batteryIsCharging, adapter: adapter)

        // Hoist the charging source lookup early. The identity-block
        // wording below and the e-marker guard further down both need
        // to know whether something is sourcing power on this port.
        let chargingSource = systemPowerUnavailable
            ? nil
            : PowerSource.preferredChargingSource(in: sources)

        // Apple's own name for the accessory, from the port's UVDM node.
        // Nil for every non-Apple accessory, and for an Apple one whose node
        // publishes nothing displayable.
        let accessoryName = accessoryIdentity?.displayName

        // Which line the name belongs on is decided by what the accessory IS,
        // not by whether power happens to be flowing. Power flow is the wrong
        // axis twice over: a charger on a full battery has no live source at
        // all (issue #278), and a Studio Display holds one while being the
        // connected device.
        //
        // The node says which it is, exactly. Measured across all 1380
        // probe-17 corpus folders: 33 nodes carry Manufacturer "0x05AC" (the
        // raw hex vendor id, not a name), those 33 are exactly the nodes
        // carrying a NON-EMPTY User String (35 carry the key at all; two of
        // those hold an empty string), and every one of those 33 values ends
        // in "USB-C Power Adapter". Everything else that carries a name
        // (Studio Display, iPhone, iPad, Macintosh, Display, Vision Pro
        // Battery, DevBand) carries "Apple Inc." or a blank Manufacturer. So
        // the hex value is the power-adapter population, with no substring
        // match on a user-facing name that arrives in the host's own language.
        let accessoryIsPowerAdapter = accessoryIdentity?.manufacturer == "0x05AC"
        /// A brick: belongs on the charger line, never the connected-device one.
        let accessoryChargerName = accessoryIsPowerAdapter ? accessoryName : nil
        /// Everything else: belongs on the connected-device line, power or no power.
        let accessoryDeviceName = accessoryIsPowerAdapter ? nil : accessoryName

        // Whether we'll emit a richer charger line later (in the charger
        // details block): either "Charger: <Manufacturer> <Name>" from
        // AdapterDetails, or "Charger: <name>" from the port's UVDM node. We
        // use this to avoid double-prefixing with the PD and FedDetails
        // fallbacks below when the signals identify the same charger.
        let adapterIdentityWillFire = chargingSource != nil
            && (adapter?.manufacturer?.isEmpty == false || accessoryChargerName != nil)

        // Partner identity (SOP): what's connected.
        if let partner = identities.first(where: { $0.endpoint == .sop }),
           let header = partner.idHeader {
            let vendor = VendorDB.label(for: partner.vendorID)
            if header.isCable && chargingSource != nil {
                // A device sourcing power on this port cannot be a passive or
                // active cable. Chargers routinely fill the PD ID-header
                // product-type field with junk (USB-PD has no "charger" product
                // type), so a charger can answer Discover Identity claiming to
                // be a "passive cable". Don't echo that back as the connected
                // device; treat it as the charger, mirroring the
                // federated-identity branch below. See issue #268.
                if !adapterIdentityWillFire {
                    // Keep the PD revision inside the single %@ argument so the
                    // info isn't dropped and no new localised key is needed.
                    let label = partner.pdRevisionLabel.map { "\(vendor) (\($0))" } ?? vendor
                    databaseLines.append(String(localized: "Charger identified as \(label)", bundle: _coreLocalizedBundle))
                }
                // If adapterIdentityWillFire, a richer "Charger: <mfr> <name>"
                // line is coming later; skip to avoid a double charger line
                // (mirrors the federated branch's guard).
            } else if let accessoryDeviceName {
                // A power adapter never reaches here: it has no device name, so
                // it falls through to the PD-derived wording below and is named
                // on the charger line instead.
                //
                // A peer Mac publishes Product "Macintosh", so a Mac-to-Mac
                // Thunderbolt link renders "Connected device: Macintosh
                // (Apple)" here. Host-to-host wording is owned elsewhere and
                // will add its own check ahead of this one, so this stays the
                // LAST alternative tried before the PD-derived wording below.
                // The PD revision goes inside the single %@ argument so no new
                // localised key is needed, exactly as the charger line does.
                let label = partner.pdRevisionLabel.map { "\(accessoryDeviceName) (Apple) (\($0))" }
                    ?? "\(accessoryDeviceName) (Apple)"
                measured.append(String(localized: "Connected device: \(label)", bundle: _coreLocalizedBundle))
            } else {
                let kind = header.ufpProductType != .undefined ? header.ufpProductType.label : header.dfpProductType.label
                if let pdRev = partner.pdRevisionLabel {
                    measured.append(String(localized: "Connected device: \(kind), \(vendor) (\(pdRev))", bundle: _coreLocalizedBundle))
                } else {
                    measured.append(String(localized: "Connected device: \(kind), \(vendor)", bundle: _coreLocalizedBundle))
                }
            }
        } else if let portNum = port.portNumber,
                  let fed = federatedIdentities.first(where: { $0.portIndex == portNum }),
                  fed.hasDevice,
                  let vendorName = VendorDB.name(for: fed.vendorID) {
            // Safe fallback: only emit a bullet when VendorDB knows the
            // VID. Unknown VIDs would expose either a silicon-vendor
            // name or just a hex code, both of which mislead users when
            // labelled as the "connected device" or "charger".
            let vendor = "\(vendorName) (0x\(String(format: "%04X", fed.vendorID)))"
            if chargingSource != nil && !adapterIdentityWillFire && accessoryDeviceName == nil {
                // A charging source is on this port and we don't have
                // a richer Manufacturer/Name pair from AdapterDetails;
                // label this as the charger. A named non-adapter accessory
                // takes the connected-device arm below instead: a display
                // sourcing power is still the connected device.
                databaseLines.append(String(localized: "Charger identified as \(vendor)", bundle: _coreLocalizedBundle))
            } else if let accessoryDeviceName {
                // Apple's own name for the thing, whether or not it is also
                // sourcing power. The same ordering note as the branch above
                // applies: this check stays last, ahead of nothing but the
                // generic wording. The "(Apple)" suffix goes inside the single
                // %@ argument, so this reuses the existing key.
                let label = "\(accessoryDeviceName) (Apple)"
                measured.append(String(localized: "Connected device: \(label)", bundle: _coreLocalizedBundle))
            } else if chargingSource == nil {
                // No charging source: the connected thing is a
                // peripheral, dock, drive, etc.
                measured.append(String(localized: "Connected device: \(vendor)", bundle: _coreLocalizedBundle))
            }
            // If chargingSource != nil && adapterIdentityWillFire,
            // the AdapterDetails "Charger:" line is coming later with
            // a richer label; skip this one to avoid double-prefix.
        }

        // ------------------------------------------------------------
        // emarker: what the cable says about itself
        // ------------------------------------------------------------

        // E-marker presence. The whole cable-details bullet only makes
        // sense on USB-C, where the user can swap cables and might wonder
        // why details are missing. On MagSafe the cable is part of the
        // brick (and MagSafe absolutely does negotiate Power Delivery,
        // just over its own pins, not the CC line we test for
        // `pdCapable`), so don't emit any "no e-marker" wording there.
        let isMagSafe = port.portTypeDescription?.hasPrefix("MagSafe") == true

        // Show the "no e-marker" explanation when there's evidence
        // something is connected (active transport, charger, SOP partner,
        // or USB device), not just when transports are active. Without
        // this, the .unknown state (empty active) never shows the bullet.
        let hasPartner = chargingSource != nil
            || identities.contains(where: { $0.endpoint == .sop })
            || !devices.isEmpty
        let hasPayload = !active.isEmpty || hasPartner

        let negotiatedAbove3A = chargingSource?.winning?.maxCurrentMA ?? 0 > 3000

        // Cable e-marker (SOP'). `hasEmarker` only means the endpoint
        // responded; its identity VDOs can still be empty when the link never
        // woke the e-marker (a connection at 3A or below, with no Thunderbolt,
        // never triggers Discover Identity). Treat "endpoint present but no
        // VDOs" as "not read on this connection", not as a blank cable.
        // Prefer a populated cable identity: with both SOP' and SOP'' present,
        // one can carry the VDOs while the other is empty, so a plain
        // first(where:) could pick the empty one and wrongly read "not read".
        let cableEmarker = identities.first(where: {
            ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime) && !$0.vdos.isEmpty
        }) ?? identities.first(where: {
            $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
        })
        let emarkerRead = cableEmarker.map { !$0.vdos.isEmpty } ?? false

        // One classification for the whole card, read once here: the
        // e-marker's self-report together with the port controller's own
        // ActiveCable measurement. `port` is the port this identity belongs
        // to: every caller filters `identities` with
        // `USBPDSOP.canonicallyMatches(port:)` before handing them over.
        let cableClassification = cableEmarker.flatMap {
            CableClassification.resolve(identity: $0, port: port)
        }

        // Read state is the state of the e-marker group, so it becomes the
        // group's subtitle rather than a bullet sitting among the cable's own
        // claims. This is what kills the old contradiction where the card
        // advised "needs above 3A or Thunderbolt" while negotiating 5 A over a
        // live Thunderbolt link: the advice is now conditioned on the very
        // signals that made it wrong.
        let readConditionsMet = negotiatedAbove3A || hasTB
        if hasEmarker {
            // Issue #573 part 2: MagSafe never has this suppressed, because
            // MagSafe never has anything TO read. Its cable identity (added
            // by `USBPDSOPWatcher`'s StateCC path) carries a real VID/PID
            // but always an empty `vdos`, which is exactly what
            // `emarkerRead` above reads as "not read on this connection".
            // That wording is honest for USB-C (a real e-marker chip that
            // genuinely didn't answer) but false for MagSafe (the chip
            // answered; there was never a VDO array for it to answer with).
            // No new UI, no new strings: just don't show this one.
            if !emarkerRead && !isMagSafe {
                emarkerSubtitle = readConditionsMet
                    ? String(localized: "Present, but not read on this connection. Try reconnecting; some chargers and docks block the read.", bundle: _coreLocalizedBundle)
                    : String(localized: "Present, but not read on this connection. macOS usually reads it above 3A or over Thunderbolt.", bundle: _coreLocalizedBundle)
            }
        } else if hasPayload && !isMagSafe {
            if !pdCapable {
                emarkerSubtitle = String(localized: "This port can't read cable details: USB-only, no Power Delivery.", bundle: _coreLocalizedBundle)
            } else if let connectionAge, connectionAge < Self.emarkerReadWindow {
                // Still inside the read window: macOS hasn't necessarily run
                // Discover Identity yet, so "no e-marker" would be a claim we
                // can't back. Unknown age (nil) skips this branch entirely
                // and falls through to the post-window wording below.
                emarkerSubtitle = String(localized: "Reading cable details…", bundle: _coreLocalizedBundle)
            } else if negotiatedAbove3A {
                // A >3A contract is strong evidence the charger read the
                // e-marker (USB-PD requires it above 3A; cables rate only
                // 3A or 5A), phrased as an observation since a non-compliant
                // charger could skip the read. Owner-approved 2026-08-28.
                let amps = chargingSource?.winning?.ampsLabel ?? ""
                emarkerSubtitle = String(localized: "The \(amps) contract shows the charger treated this as an e-marked, 5A-capable cable, so charging isn't limited by the cable. This Mac couldn't get its own read here. Connect the cable to another device to see its details.", bundle: _coreLocalizedBundle)
            } else if readConditionsMet {
                emarkerSubtitle = String(localized: "No e-marker response. Cable details aren't available on this connection. Try another device to read it.", bundle: _coreLocalizedBundle)
            } else {
                emarkerSubtitle = String(localized: "No e-marker read. The cable may have one; macOS usually reads it above 3A or over Thunderbolt.", bundle: _coreLocalizedBundle)
            }
        }

        if let cable = cableEmarker, let cv = cable.cableVDO {
            let speedLabel = cv.speed.label
            emarkerLines.append(String(localized: "Cable speed: \(speedLabel)", bundle: _coreLocalizedBundle))
            let currentLabel = cv.current.label
            let maxVolts = cv.maxVolts
            let maxWatts = cv.maxWatts
            if maxVolts > 48 {
                // The cable's voltage rating (50V) sits above USB-PD's 48V
                // delivery ceiling, so rating × current overstates the power.
                // Show the rating and the deliverable figure as separate facts
                // with the reason, so the two numbers don't read as a broken
                // multiply (50 × 5 = 250, but the cable can only carry 240W).
                emarkerLines.append(String(localized: "Cable rated to \(maxVolts)V / \(currentLabel), delivers up to \(maxWatts)W (USB-PD caps at 48V)", bundle: _coreLocalizedBundle))
            } else {
                emarkerLines.append(String(localized: "Cable rated for \(currentLabel) at up to \(maxVolts)V (~\(maxWatts)W)", bundle: _coreLocalizedBundle))
            }
            // Only a captive plug earns a line: a Type-C plug on a USB-C
            // cable is not information, and the two deprecated types cannot
            // reach a USB-C port.
            if cv.plugType == .captive {
                emarkerLines.append(cv.plugType.label)
            }
            // The active / passive verdict is the classifier's, not the
            // e-marker's alone: a mis-programmed e-marker no longer decides
            // it by itself (issue #111). Which reading settled it picks the
            // wording.
            if let resolution = cableClassification, resolution.type == .active {
                switch resolution.source {
                case .emarker:
                    if let v2 = cable.activeCableVDO2 {
                        let medium = v2.physicalConnection.label.lowercased()
                        let element = v2.activeElement.label.lowercased()
                        emarkerLines.append(String(localized: "Active \(medium) cable, \(element)", bundle: _coreLocalizedBundle))
                        if v2.physicalConnection == .optical {
                            if v2.opticallyIsolated {
                                emarkerLines.append(String(localized: "Optical fibres are electrically isolated end-to-end", bundle: _coreLocalizedBundle))
                            } else {
                                emarkerLines.append(String(localized: "Optical cable, not electrically isolated (carries copper alongside the fibres)", bundle: _coreLocalizedBundle))
                            }
                        }
                    } else {
                        emarkerLines.append(String(localized: "Active cable (contains signal-conditioning electronics)", bundle: _coreLocalizedBundle))
                    }
                case .portController:
                    // The port controller measured an active cable while the
                    // e-marker declared itself passive. A measurement beats a
                    // structural inference, so this wording wins over the
                    // contradiction wording below on the four corpus ports
                    // that set both.
                    emarkerLines.append(String(localized: "E-marker reports passive, but the port controller detects an active cable", bundle: _coreLocalizedBundle))
                    if let v2 = cable.activeCableVDO2(classifiedAs: resolution) {
                        let medium = v2.physicalConnection.label.lowercased()
                        let element = v2.activeElement.label.lowercased()
                        // Reuses the same key as the normal active-cable VDO2 line
                        // so no new localisation key is needed for the medium/element.
                        emarkerLines.append(String(localized: "Active \(medium) cable, \(element)", bundle: _coreLocalizedBundle))
                    }
                case .layoutContradiction:
                    // The cable's ID Header says passive, but VDO[3] has the
                    // "SOP'' Controller Present" bit set, a field that only exists
                    // in the active-cable layout. That structural contradiction
                    // suggests this is really an active cable with a mis-programmed
                    // e-marker (confirmed real case: CalDigit 2M Thunderbolt 4).
                    // Surface the note with hedged wording; VDO[3] is kept decoded
                    // under the passive layout to avoid raising false trust flags.
                    //
                    // Still reached when the controller flag is false: m1_macos26.2
                    // port 1 in the corpus carries the contradiction with
                    // ActiveCable false.
                    emarkerLines.append(String(localized: "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)", bundle: _coreLocalizedBundle))
                    if let v2 = cable.activeCableVDO2 {
                        let medium = v2.physicalConnection.label.lowercased()
                        let element = v2.activeElement.label.lowercased()
                        // Reuses the same key as the normal active-cable VDO2 line
                        // so no new localisation key is needed for the medium/element.
                        emarkerLines.append(String(localized: "Active \(medium) cable, \(element)", bundle: _coreLocalizedBundle))
                    }
                }
            } else if cableClassification?.type == .passive {
                // Plain statement of what the e-marker says, nothing more.
                //
                // This used to carry an explanation ("normal for Thunderbolt
                // cables where the active electronics handle Thunderbolt, not
                // USB") on every passive cable sitting on a live Thunderbolt
                // link. That sentence was written for the #111 case, where a
                // 2 m cable declaring itself passive is suspicious because 2 m
                // passive at 40 Gbps is not physically possible. Applied
                // universally it was simply false: a short passive TB5 cable
                // has no active electronics at all. The mis-programmed-e-marker
                // cases are covered by the two branches above.
                emarkerLines.append(String(localized: "Passive (no signal-conditioning electronics)", bundle: _coreLocalizedBundle))
            }

            // The controller's reading of the cable, placed with the Mac's
            // other measurements rather than among the e-marker's claims.
            //
            // The CIO figure is the controller's claim about the cable and
            // peer pair: a floor on cable capability that can sit above the
            // lane the link trained (31 of 378 replayed corpus ports). The bullet
            // confirms the lower of that claim and the lane; the cable's own
            // ceiling stays on the e-marker group's "Cable speed" line.
            //
            // Still gated on a passive e-marker and a live Thunderbolt link,
            // which is where it has always fired. Widening it to active cables
            // is a separate change with its own user-visible effect.
            if cv.cableType == .passive, hasTB,
               let cio = cioCapability,
               let speed = cio.negotiatedLinkSpeed,
               let label = CIOCableCapability.speedLabel(for: speed),
               let cioGbps = DataLinkDiagnostic.cioCableGbps(speed),
               // With no trained lane figure the CIO code alone proves
               // nothing about what the cable carried, so no controller
               // bullet is printed rather than its claim as a rate.
               let laneGbps = DataLinkDiagnostic.activeTBGbps(port: port, switches: thunderboltSwitches) {
                let confirmed = min(cioGbps, laneGbps)
                // `label` names the CIO tier, so it is only safe once the lane
                // has carried that tier; otherwise it would sit above the lane.
                let laneCorroboratesClaim = !DataLinkDiagnostic.meaningfullySlower(laneGbps, than: cioGbps)
                if laneCorroboratesClaim,
                   !DataLinkDiagnostic.meaningfullySlower(confirmed, than: cv.speed.maxGbps) {
                    measured.append(String(localized: "Controller confirms Thunderbolt cable (\(label))", bundle: _coreLocalizedBundle))
                } else {
                    measured.append(String(localized: "Thunderbolt link active at \(DataLinkDiagnostic.label(laneGbps))", bundle: _coreLocalizedBundle))
                }
            }
        }

        // Port-level optical flag. This is the port controller's own reading,
        // not the cable's claim, so it sits with the measurements. Under the
        // old flat list it was indistinguishable from the e-marker's optical
        // lines above.
        if port.opticalCable == true {
            measured.append(String(localized: "Optical cable", bundle: _coreLocalizedBundle))
        }

        // Cable e-marker vendor (SOP'): who made the cable.
        //
        // The VID gives the silicon vendor (honest, even when an unrelated
        // retail brand is on the sleeve). A curated retail brand/model is
        // only shown on a full VID+PID match; a zeroed-identity cable shows
        // no maker and no brand, just its capabilities. See #239.
        //
        // The raw Cable VDO (0 when the cable has none) discriminates
        // between capability variants and same-fingerprint rebrands sharing
        // one VID+PID (see CableDB.curatedCables). A fingerprint can now
        // resolve more than one brand (the #505 case: the identical e-marker
        // sold under several sleeve brands). Showing only the first brand
        // would mislabel every cable whose brand doesn't sort first, so a
        // 2+ match gets its own honest wording instead of picking a winner.
        //
        // The old single line "Cable made by CalDigit, Inc. (0x01B6)" blended
        // two sources: the cable declared a number, we turned it into a name.
        // It moves to the database group, worded so a stale or missing entry
        // in our list reads as a limit of our records rather than a claim
        // about the cable.
        //
        // The raw VID is deliberately NOT given its own line in the e-marker
        // group. It would be new free content, and the Pro diagnostics screen
        // already shows it (cable identity section, alongside Product ID and
        // the raw cable VDOs). The card keeps exactly the vendor information
        // it has always shown.
        if let cable = cableEmarker, cable.vendorID != 0 {
            let vendorHex = "0x" + String(format: "%04X", cable.vendorID)
            if let vendorName = VendorDB.name(for: cable.vendorID) {
                databaseLines.append(String(localized: "Made by \(vendorName) (\(vendorHex)), per our bundled vendor list", bundle: _coreLocalizedBundle))
                // The vendor name above is honest, so it stays. This says
                // what it means: an e-marker that was never reprogrammed
                // answers with its chip maker's default ID, so the name is
                // the silicon supplier rather than the cable brand.
                if let chip = EmarkerSilicon.shortName(for: cable.vendorID) {
                    databaseLines.append(String(localized: "E-marker carries its chip maker's default vendor ID (\(chip)); the cable brand is not recorded", bundle: _coreLocalizedBundle))
                }
            } else {
                databaseLines.append(String(localized: "\(vendorHex) isn't in our bundled vendor list", bundle: _coreLocalizedBundle))
            }

            let cableVDORaw = cable.vdos.count > 3 ? cable.vdos[3] : 0
            let matches = CableDB.curatedCables(vid: cable.vendorID, pid: cable.productID, cableVDO: cableVDORaw)
            var seenBrands = Set<String>()
            let distinctBrands = matches.map(\.brand).filter { seenBrands.insert($0).inserted }
            if distinctBrands.count == 1 {
                databaseLines.append(String(localized: "Cable identified as \(distinctBrands[0])", bundle: _coreLocalizedBundle))
            } else if distinctBrands.count > 1 {
                let brandList = distinctBrands.joined(separator: "; ")
                databaseLines.append(String(localized: "This e-marker is used in: \(brandList)", bundle: _coreLocalizedBundle))
            }
        }

        // USB-IF certification, looked up offline by the cable's Cert Stat
        // XID (compiled into whatcable.db, no live network). Keyed by the XID,
        // NOT the VID, so this must sit outside the `vendorID != 0` block
        // above: a zero-VID cable can still carry a real XID (and the JSON
        // output shows it either way, so the two must agree).
        //
        // Neutral provenance only: who certified it and whether it passed. The
        // certifying company is usually the manufacturer / ODM, not the retail
        // brand on the sleeve, so it is labelled "Manufacturer". Absence is
        // normal and says nothing. A VID match is a mild confirming note; a
        // mismatch is never surfaced (ODM rebrands legitimately differ). See
        // research/usb-if-registry.md.
        if let cable = cableEmarker, let xid = cable.certStatVDO?.xid {
            let xidHex = "0x" + String(xid, radix: 16, uppercase: true)
            // The raw XID gets no line of its own here. It would be new free
            // content on a card that has never shown a certified cable's ID,
            // so it lives in the Pro diagnostics cable-identity section
            // instead, next to the Vendor ID row. What the card shows is
            // unchanged: the certified line, or the neutral note below when
            // we can't resolve the ID.
            let certs = CableDB.certifications(forXID: xid)
            // Prefer the listing whose vendor matches the cable's own VID;
            // otherwise the first listing (rebrands share one XID).
            if let cert = certs.first(where: { $0.vendorID == cable.vendorID }) ?? certs.first {
                // status ("Pass" / "Obsolete") is always present in the
                // compiled data; the no-status forms are defensive only.
                let status = cert.status
                switch (cert.model.isEmpty, status.isEmpty) {
                case (false, false):
                    databaseLines.append(String(localized: "USB-IF certified. Manufacturer: \(cert.company), model \(cert.model) (\(status))", bundle: _coreLocalizedBundle))
                case (false, true):
                    databaseLines.append(String(localized: "USB-IF certified. Manufacturer: \(cert.company), model \(cert.model)", bundle: _coreLocalizedBundle))
                case (true, false):
                    databaseLines.append(String(localized: "USB-IF certified. Manufacturer: \(cert.company) (\(status))", bundle: _coreLocalizedBundle))
                case (true, true):
                    databaseLines.append(String(localized: "USB-IF certified. Manufacturer: \(cert.company)", bundle: _coreLocalizedBundle))
                }
                // Confirming note only, and only for a real (non-zero) VID
                // match. A mismatch is never shown as anything.
                if cable.vendorID != 0 && certs.contains(where: { $0.vendorID == cable.vendorID }) {
                    databaseLines.append(String(localized: "The cable's declared maker matches the USB-IF certificate", bundle: _coreLocalizedBundle))
                }
            } else if xid != 0 {
                // The cable advertised a certification ID, but USB-IF publishes
                // no listing for it. A neutral transparency note, never a
                // fault: certification is voluntary, the registry has two
                // sources that don't fully agree, and ~15% of real cables sit
                // here (Apple's own most of all). It is deliberately gated on
                // `xid != 0`: a cable that carries no ID (the 64% majority) has
                // claimed nothing to check, so it stays silent. This closes the
                // gap a beta tester raised (darrylmorley/whatcable#475): "no
                // ID" and "an ID that isn't published" used to look identical.
                //
                // Worded as a limit of our copy of the registry, not a verdict
                // on the cable. Under the old flat list it read as the latter.
                databaseLines.append(String(localized: "\(xidHex) isn't in our copy of the USB-IF registry", bundle: _coreLocalizedBundle))
            }
        }

        // ------------------------------------------------------------
        // charger: what the charger says about itself, plus the contract
        // the Mac actually measured
        // ------------------------------------------------------------

        // Power summary from PD or MagSafe power sources.
        if let chargingSource {
            // Surface the IOKit-reported charger brand and product name
            // when present. Only Apple bricks and a handful of other
            // sources populate AdapterDetails.Manufacturer / Name; on
            // third-party chargers these are typically nil and the
            // FedDetails fallback (in the identity block above) carries
            // the brand instead.
            if let manufacturer = adapter?.manufacturer, !manufacturer.isEmpty {
                if let name = adapter?.name, !name.isEmpty {
                    chargerLines.append(String(localized: "Charger: \(manufacturer) \(name)", bundle: _coreLocalizedBundle))
                } else {
                    chargerLines.append(String(localized: "Charger: \(manufacturer)", bundle: _coreLocalizedBundle))
                }
            } else if let accessoryChargerName {
                // AdapterDetails said nothing, but the port's UVDM node names
                // the brick. This is the richer line, so `adapterIdentityWillFire`
                // counts it and the PD / FedDetails "Charger identified as"
                // wording stands down: never two charger identities on one card.
                chargerLines.append(String(localized: "Charger: \(accessoryChargerName)", bundle: _coreLocalizedBundle))
            }

            switch chargerWattageSource {
            case .portNegotiated(let w) where w > 0:
                chargerLines.append(String(localized: "Charger advertises up to \(w)W", bundle: _coreLocalizedBundle))
            case .systemAdapterFallback(let w):
                // macOS's own reading of the adapter, not the charger's PDOs,
                // so this is a measurement.
                measured.append(String(localized: "System reports charger at \(w)W", bundle: _coreLocalizedBundle))
            default:
                let maxW = Int((Double(chargingSource.maxPowerMW) / 1000).rounded())
                let hasOptions = !chargingSource.options.isEmpty
                if hasOptions && maxW > 0 {
                    chargerLines.append(String(localized: "Charger advertises up to \(maxW)W", bundle: _coreLocalizedBundle))
                }
            }
            if let win = chargingSource.winning {
                let volts = win.voltsLabel
                let amps = win.ampsLabel
                let watts = win.wattsLabel
                // The contract the port controller actually settled on.
                measured.append(String(localized: "Currently negotiated: \(volts) @ \(amps) (\(watts))", bundle: _coreLocalizedBundle))
            }
        } else if !systemPowerUnavailable,
                  case .systemAdapterFallback(let w) = chargerWattageSource, w > 0 {
            // No live USB-PD source on this port (e.g. the battery is full so
            // macOS tore the contract down), but the system adapter reading
            // still resolves to a charger for this port. Surface its brand and
            // wattage so the number is visible even without a negotiated
            // contract. Mirrors the `if let chargingSource` block above; the
            // two are mutually exclusive (the Brick-ID fallback keeps a live
            // source, so it stays in that branch). See issue #278.
            if let manufacturer = adapter?.manufacturer, !manufacturer.isEmpty {
                if let name = adapter?.name, !name.isEmpty {
                    chargerLines.append(String(localized: "Charger: \(manufacturer) \(name)", bundle: _coreLocalizedBundle))
                } else {
                    chargerLines.append(String(localized: "Charger: \(manufacturer)", bundle: _coreLocalizedBundle))
                }
            } else if let accessoryChargerName {
                // AdapterDetails is silent, so the port's UVDM node is the only
                // thing that names the brick in this state. Mirrors the
                // live-source branch above.
                chargerLines.append(String(localized: "Charger: \(accessoryChargerName)", bundle: _coreLocalizedBundle))
            }
            measured.append(String(localized: "System reports charger at \(w)W", bundle: _coreLocalizedBundle))
        }

        // Headline wattage: prefer the resolved source, fall back to
        // the per-port PD options for callers that don't pass a source.
        let chargerW: Int? = {
            if systemPowerUnavailable { return nil }
            if let w = chargerWattageSource.watts, w > 0 { return w }
            guard let chargingSource, !chargingSource.options.isEmpty else { return nil }
            let w = Int((Double(chargingSource.maxPowerMW) / 1000).rounded())
            return w > 0 ? w : nil
        }()

        // Cable limit suffix: only emitted when the cable's e-marker
        // reports a maxWatts that is strictly less than what the charger
        // advertises. The diagnostic banner already explains this in
        // detail when a cable is plugged in; the headline suffix is the
        // at-a-glance equivalent so the user can spot a cable mismatch
        // without reading further.
        let cableLimitSuffix: String = {
            guard let chargerW,
                  let cableW = cableEmarker?.cableVDO?.maxWatts,
                  cableW > 0,
                  cableW < chargerW else { return "" }
            return String(localized: " · \(cableW)W cable", bundle: _coreLocalizedBundle)
        }()

        if hasTB {
            self.status = .thunderboltCable
            if let w = chargerW {
                self.headline = String(localized: "Thunderbolt / USB4 · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "Thunderbolt / USB4", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = subtitleForCapabilities(usb3: true, dp: hasDP, emarker: hasEmarker)
        } else if hasCorroboratedUSB3 && hasDP {
            self.status = .displayCable
            if let w = chargerW {
                self.headline = String(localized: "USB-C with video · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "USB-C with video", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = dataWithheld
                ? String(localized: "Video is working. macOS is holding data back until you approve the accessory.", bundle: _coreLocalizedBundle)
                : String(localized: "Carrying both data and DisplayPort video.", bundle: _coreLocalizedBundle)
        } else if hasDP {
            self.status = .displayCable
            if let w = chargerW {
                self.headline = String(localized: "Display connected · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "Display connected", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = String(localized: "DisplayPort video over USB-C Alt Mode.", bundle: _coreLocalizedBundle)
        } else if hasCorroboratedUSB3 {
            self.status = .dataDevice
            if let w = chargerW {
                self.headline = (dataWithheld
                    ? String(localized: "USB device, data blocked · \(w)W charger", bundle: _coreLocalizedBundle)
                    : String(localized: "USB device · \(w)W charger", bundle: _coreLocalizedBundle)) + cableLimitSuffix
            } else {
                self.headline = (dataWithheld
                    ? String(localized: "USB device, data blocked", bundle: _coreLocalizedBundle)
                    : String(localized: "USB device", bundle: _coreLocalizedBundle)) + cableLimitSuffix
            }
            // The link is signalling, but nothing crosses it until the user
            // approves the accessory, so claiming an active data link here is
            // the contradiction this branch exists to avoid.
            //
            // For USB3 the Data diagnostic underneath carries the full
            // explanation and the Settings path, and this line only has to
            // stop disagreeing with it. NOT so for USB2: DataLinkDiagnostic
            // has no TRM path, so a USB2-blocked port (3 of the 4 corpus
            // machines with withheld data) gets this headline with nothing
            // beneath it explaining what to do. Still better than the old
            // "Only USB 2.0 is active", which was simply false, but it is a
            // known gap, not a complete answer.
            self.subtitle = dataWithheld
                ? String(localized: "macOS is holding data back until you approve the accessory.", bundle: _coreLocalizedBundle)
                : String(localized: "SuperSpeed data link is active.", bundle: _coreLocalizedBundle)
        } else if let vpd = cableEmarker?.vpdVDO, !vpd.chargeThroughSupported, !dataWithheld,
                  chargingSource == nil {
            // A VCONN-Powered Device answers Discover Identity at SOP' the way
            // a cable does, so before this branch Apple's USB-C EarPods fell
            // into the USB2 arm below and read as a slow charge-only cable
            // (issue #542). They are an accessory with a USB-C plug on the end
            // of them, not a cable.
            //
            // No wattage suffix, deliberately: the figure on this port is a
            // machine-wide system-adapter reading, and the accessory draws
            // nothing from it, so printing a charger figure next to a pair of
            // earphones is the confusion the issue reports.
            //
            // Gated on Charge Through Support being clear. A VPD that does
            // pass power through would make "does not charge" false, so it
            // falls through to the arm below, which is no worse than today.
            // No corpus sample sets that bit; it is covered by a unit test.
            //
            // Also gated on there being no live charging source. A VPD that
            // says it cannot pass power, on a port holding a real contract,
            // is contradicting its own e-marker, and "does not charge" would
            // then be false about a port charging the Mac. Zero corpus
            // machines reach it; the charging arms below keep it.
            self.status = .dataDevice
            self.headline = String(localized: "USB accessory (audio or adapter)", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "This accessory has its own USB-C plug. It is not a cable and does not charge.", bundle: _coreLocalizedBundle)
        } else if hasUSB2 && !hasCorroboratedUSB3 {
            self.status = .dataDevice
            if let w = chargerW {
                self.headline = (dataWithheld
                    ? String(localized: "USB device, data blocked · \(w)W charger", bundle: _coreLocalizedBundle)
                    : String(localized: "Slow USB device or charge-only cable · \(w)W charger", bundle: _coreLocalizedBundle)) + cableLimitSuffix
            } else {
                self.headline = (dataWithheld
                    ? String(localized: "USB device, data blocked", bundle: _coreLocalizedBundle)
                    : String(localized: "Slow USB device or charge-only cable", bundle: _coreLocalizedBundle)) + cableLimitSuffix
            }
            self.subtitle = dataWithheld
                ? String(localized: "macOS is holding data back until you approve the accessory.", bundle: _coreLocalizedBundle)
                : String(localized: "Only USB 2.0 is active. If you expected high speed, the cable may not support it.", bundle: _coreLocalizedBundle)
        } else if chargingSource != nil, batteryFullyCharged == true {
            self.status = .batteryFull
            self.headline = String(localized: "Plugged in · battery full", bundle: _coreLocalizedBundle)
            // Battery-full state is shown by the charging banner instead,
            // so the subtitle here would just repeat it. Left empty; the
            // render sites skip an empty subtitle.
            self.subtitle = ""
        } else if chargingSource != nil, batteryIsCharging == false {
            // Charger is connected and negotiated a contract, but macOS has
            // paused charging (charge limit or Optimized Battery Charging).
            // FullyCharged is false so the battery-full branch above didn't
            // fire. Show "Plugged in" rather than "Charging" because the
            // battery is not actually gaining charge right now.
            self.status = .charging
            if let w = chargerW {
                self.headline = String(localized: "Plugged in · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "Plugged in", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = String(localized: "Power is flowing. No data connection.", bundle: _coreLocalizedBundle)
        } else if chargingSource != nil {
            self.status = .charging
            if let w = chargerW {
                self.headline = String(localized: "Charging · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "Charging", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = String(localized: "Power is flowing. No data connection.", bundle: _coreLocalizedBundle)
        } else if let w = chargerW {
            // A charger is present on this port (the system adapter reading
            // resolved a wattage for it) but there's no live USB-PD contract
            // to read, e.g. the battery is full so macOS tore the contract
            // down, or a charge-only cable never negotiated one. Placed above
            // the generic `active.isEmpty` "Charging only" branch so a known
            // charger wattage is surfaced ("Charging · NW") instead of the
            // bare "Charging only" / "try a higher-wattage charger". See #278.
            if batteryFullyCharged == true {
                self.status = .batteryFull
                self.headline = String(localized: "Plugged in · battery full", bundle: _coreLocalizedBundle)
                // Battery-full state is shown by the charging banner instead,
                // so the subtitle here would just repeat it. Left empty; the
                // render sites skip an empty subtitle.
                self.subtitle = ""
            } else if batteryIsCharging == false {
                // Same as the live-contract on-hold branch but we only have
                // the system adapter wattage, not a per-port negotiated value.
                self.status = .charging
                self.headline = String(localized: "Plugged in · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
                self.subtitle = String(localized: "Power is flowing. No data connection.", bundle: _coreLocalizedBundle)
            } else {
                self.status = .charging
                self.headline = String(localized: "Charging · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
                self.subtitle = String(localized: "Power is flowing. No data connection.", bundle: _coreLocalizedBundle)
            }
        } else if active.isEmpty && supported.contains("USB2") && !systemPowerUnavailable, batteryFullyCharged == true {
            // "Plugged in · battery full" is a plugged-in claim, so it must not
            // fire when the system reports no power (unplugged at 100% with a
            // stale PDO): that would keep asserting "plugged in" on battery.
            // The genuine charge-hold-at-100% case has an adapter, so
            // systemPowerUnavailable is false there and this still fires.
            self.status = .batteryFull
            self.headline = String(localized: "Plugged in · battery full", bundle: _coreLocalizedBundle)
            // Battery-full state is shown by the charging banner instead,
            // so the subtitle here would just repeat it. Left empty; the
            // render sites skip an empty subtitle.
            self.subtitle = ""
        } else if active.isEmpty && supported.contains("USB2") && !systemPowerUnavailable {
            self.status = .charging
            self.headline = String(localized: "Charging only", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "Power is flowing but no data link is established.", bundle: _coreLocalizedBundle)
        } else if !systemPowerUnavailable,
                  FederatedIdentity.chargerPresent(on: port, in: federatedIdentities, portIsLive: connected) {
            // No PowerSource node and no resolvable wattage on this port, but
            // FedDetails says a charger is attached here. This is the M1 Pro/Max/
            // Ultra USB-C case (macOS publishes no per-port node there): the
            // charger isn't the active source, so it negotiated no contract we
            // can read. Without this branch the card fell to the generic
            // "Connected / try a higher-wattage charger" below, which is about
            // the cable e-marker and read as a contradiction next to the
            // "Charger on standby" banner (issue #459). Say a charger is plugged
            // in; the banner explains the standby detail.
            //
            // `!systemPowerUnavailable` is the same guard the two branches above
            // carry, and it was missing here. "Plugged in" is a plugged-in
            // claim, so it must not fire when the system reports no external
            // power. Reproduced on an M5 on 2026-08-10: `pmset` reported
            // battery power and discharging while the card showed a charging
            // bolt and "Plugged in". FedDetails is the only signal this branch
            // rests on and `FedExternalConnected` is known stale roughly 40% of
            // the time, so it needs the cross-check more than its siblings do,
            // not less.
            //
            // This cannot reinstate the #459 contradiction it was added to fix.
            // `ChargingDiagnostic`'s standby banner already requires
            // `!SystemPowerState.onBattery(...)` on the same recovery path, so
            // on battery the banner is silent too and there is nothing left to
            // contradict.
            self.status = .charging
            self.headline = String(localized: "Plugged in", bundle: _coreLocalizedBundle)
            self.subtitle = ""
        } else if emarkerRead {
            // The cable's e-marker was read in full, so the bullets above
            // already list its maker, speed and power rating. The catch-all
            // below tells the user to find a higher-wattage charger, which is
            // how you make macOS run Discover Identity when it hasn't. Here it
            // already has, so the advice is both useless and a flat
            // contradiction of the list underneath it (reported 2026-07-30: a
            // fully identified Thunderbolt 5 cable, told to find a bigger
            // charger).
            //
            // The wording is deliberately about what we can SEE, not about
            // what is happening. Two separate reasons, both from review:
            //
            //  - Reaching here does not prove no power is flowing. The charger
            //    branches above need a per-port PowerSource node, a resolved
            //    adapter wattage, or a FedDetails entry. A charger can miss all
            //    three at once: PowerSourceSynthesis fails closed when it can't
            //    attribute a reading to exactly one port (two active source-less
            //    ports, say), and FedDetails can miss in the same tick. "No
            //    power is running" would be a claim we cannot back. "No charger
            //    detected" is one we can.
            //  - It must not read as reassurance. A display or dock cable whose
            //    e-marker was read on an earlier negotiation but whose link then
            //    failed to establish lands in this same branch, and "nothing is
            //    wrong here" would be a lie there.
            //
            // Status stays .unknown for both reasons: we still cannot say why
            // the port is quiet, so the card keeps its caution icon.
            self.status = .unknown
            self.headline = String(localized: "Connected", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "No data link or charger detected on this port.", bundle: _coreLocalizedBundle)
        } else if systemPowerUnavailable {
            // On battery. The advice below is "try a HIGHER-WATTAGE charger",
            // which quietly assumes a charger is already attached; on battery
            // that reads as nonsense. The underlying point is the same though:
            // macOS only runs Discover Identity when the link negotiates above
            // 3 A, so power is what identifies the cable. Say that plainly.
            //
            // This branch is only reachable because of the guard added above.
            // Before it, an on-battery port with a stale FedDetails entry
            // claimed "Plugged in" instead, so the wrong advice was hidden
            // behind a worse bug.
            self.status = .unknown
            self.headline = String(localized: "Connected", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "Connect a charger to identify the cable.", bundle: _coreLocalizedBundle)
        } else {
            self.status = .unknown
            self.headline = String(localized: "Connected", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "Try a higher-wattage charger to identify the cable.", bundle: _coreLocalizedBundle)
        }

        // An e-marker that answered but told us nothing we can decode. Every
        // line in this group comes from a Cable VDO, a non-zero vendor ID or a
        // certification ID, so a response carrying none of those (an ID header
        // alone, say) leaves the group with no lines and no read-state
        // subtitle, and the empty-group filter below would drop it silently.
        // The old flat list said "Cable has an e-marker chip" here, so say the
        // equivalent rather than showing the user nothing.
        if hasEmarker, emarkerRead, emarkerLines.isEmpty, emarkerSubtitle == nil {
            if cableEmarker?.vpdVDO != nil {
                // A VCONN-Powered Device did answer, and with real data; it is
                // simply not cable data, so `cableVDO` is nil and the group has
                // no lines. Saying it "reported no capability data" would be a
                // new wrong message rather than a fixed one (issue #542).
                emarkerSubtitle = String(localized: "This plug is part of the accessory, not a cable, so there is no cable rating.", bundle: _coreLocalizedBundle)
            } else {
                emarkerSubtitle = String(localized: "Answered, but reported no capability data.", bundle: _coreLocalizedBundle)
            }
        }

        // The cable first. This is a cable app: what the cable says about
        // itself is the question the user opened the card to answer, and the
        // read state ("not read on this connection") belongs at the top where
        // it explains an otherwise bare card, rather than below a list of
        // measurements. Then what the Mac measured, then what our records add
        // about the cable, and the charger last: it is the one group that is
        // not about the cable at all.
        //
        // Order is presentation only. `topLine` names the measured group
        // explicitly, so the widget still leads with a measurement rather than
        // following whatever sorts first here.
        let groups = [
            BulletGroup(kind: .emarker, header: BulletGroup.Kind.emarker.header, subtitle: emarkerSubtitle, lines: emarkerLines),
            BulletGroup(kind: .measured, header: BulletGroup.Kind.measured.header, lines: measured),
            BulletGroup(kind: .database, header: BulletGroup.Kind.database.header, lines: databaseLines),
            BulletGroup(kind: .charger, header: BulletGroup.Kind.charger.header, lines: chargerLines),
        ].filter { !$0.isEmpty }

        self.groups = groups
        self.linkSpeed = resolveLinkSpeed(
            hasTB: hasTB,
            hasUSB3: hasCorroboratedUSB3,
            hasUSB2: hasUSB2,
            port: port,
            devices: devices,
            usb3Transports: usb3Transports,
            switches: thunderboltSwitches
        )
    }
}

/// Build the TB-specific bullets for a port whose `transportsActive`
/// includes `"CIO"`. Returns an empty array if we can't find a matching
/// switch (e.g. the port doesn't have an `@N` suffix, or the Thunderbolt
/// watcher hasn't populated yet). Caller falls back to a generic bullet
/// in that case.
private func thunderboltBullets(
    for port: AppleHPMInterface,
    switches: [IOThunderboltSwitch]
) -> [String] {
    guard !switches.isEmpty,
          let socketID = ThunderboltTopology.socketID(for: port),
          let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches) else {
        return []
    }

    let chain = ThunderboltTopology.chain(from: root, in: switches)
    var bullets: [String] = []

    // First-hop link state: the host root's downstream lane port describes
    // the cable's negotiated speed.
    if let hostPort = ThunderboltTopology.trainedDownstreamLanePort(root),
       let label = ThunderboltLabels.linkLabel(for: hostPort) {
        // label is e.g. "Up to 20 Gb/s × 2" — replace the leading "Up"
        // with "up" for the bullet phrasing without lowercasing units.
        let linkSpeed = label.replacingOccurrences(of: "Up to", with: "up to")
        bullets.append(String(localized: "Linked at \(linkSpeed)", bundle: _coreLocalizedBundle))
    }

    // Connected-device line. Only meaningful when there's at least one
    // downstream switch. On a linear daisy-chain we show the path
    // (A → B). On a branching tree (a dock with two Thunderbolt devices)
    // the first-child path would silently drop the other branches
    // (issue #280), so instead we name every downstream device. The
    // indented fabric tree below carries the branch structure on both the
    // CLI and the GUI.
    let downstream = chain.dropFirst()
    let allDownstream = ThunderboltTopology.flatten(
        ThunderboltTopology.tree(from: root, in: switches)
    )
    let isBranching = allDownstream.count > downstream.count
    if isBranching {
        // Branching: the linear chain is hiding devices. Name them all.
        let names = allDownstream.map { ThunderboltLabels.deviceName(for: $0.sw) }
        let count = names.count
        let list = names.joined(separator: ", ")
        bullets.append(String(localized: "Connected to \(count) Thunderbolt devices: \(list)", bundle: _coreLocalizedBundle))
    } else if !downstream.isEmpty {
        let names = downstream.map { ThunderboltLabels.deviceName(for: $0) }
        let hops = downstream.count
        let path = names.joined(separator: " → ")
        if hops == 1 {
            bullets.append(String(localized: "Connected to \(path)", bundle: _coreLocalizedBundle))
        } else {
            bullets.append(String(localized: "Connected via \(hops) hops: \(path)", bundle: _coreLocalizedBundle))
        }
    }

    // Step-down detection: only meaningful on linear daisy-chains
    // (two or more downstream switches). Skip when branching: the
    // linear chain's "last" node is arbitrary in a tree, so a
    // step-down reading would be meaningless or misleading.
    // On a single-hop link, the host's downstream port and the device's
    // upstream port describe the SAME physical cable from opposite ends;
    // the two readings can disagree on lane count (the controller-side
    // view aggregates lanes that the device-side view doesn't), and
    // that disagreement is not a real step-down. With two or more hops,
    // comparing the first link (host -> device 1) to the last link
    // (device N-1 -> device N) genuinely contrasts two distinct cables.
    if !isBranching,
       downstream.count >= 2,
       let hostPort = ThunderboltTopology.trainedDownstreamLanePort(root),
       let last = downstream.last,
       let lastLeg = ThunderboltTopology.trainedDownstreamLanePort(last)
            ?? last.ports.first(where: { $0.adapterType.isLane && $0.hasTrainedLanes }),
       let stepLabel = stepDownLabel(host: hostPort, lastLeg: lastLeg) {
        bullets.append(stepLabel)
    }

    return bullets
}

/// If the last-leg link is slower than the host link, describe the change.
/// Returns nil when the labels match, or when the last leg is equal speed or
/// faster than the host link.
///
/// "Slower" is defined as a strictly lower total throughput, where total
/// throughput = per-lane Gb/s x lane count. For asymmetric links the dominant
/// (larger) lane count is used. This definition ensures that equal per-lane
/// speed across different lane counts (e.g. 20 Gb/s x 1 vs 20 Gb/s x 2) is
/// NOT reported as a drop: the last leg may carry fewer lanes but the per-lane
/// rate is unchanged, and the chain is still running at the same generation.
///
/// Example comparisons:
///   - host 20 x 2 (40 Gbps) vs last-leg 10 x 1 (10 Gbps) → drop (10 < 40)
///   - host 20 x 1 (20 Gbps) vs last-leg 20 x 2 (40 Gbps) → nil (40 >= 20)
///   - host 20 x 1 (20 Gbps) vs last-leg 20 x 1 (20 Gbps) → nil (equal)
private func stepDownLabel(host: IOThunderboltPort, lastLeg: IOThunderboltPort) -> String? {
    guard let hostLabel = ThunderboltLabels.linkLabel(for: host),
          let lastLabel = ThunderboltLabels.linkLabel(for: lastLeg) else {
        return nil
    }
    // Fast path: identical labels are never a drop.
    if hostLabel == lastLabel { return nil }

    // Compute total throughput (Gbps) for each leg.
    // perLaneGbps is nil for unknown generations; treat those as not-comparable
    // and return nil so we never show a misleading drop label.
    guard let hostPerLane = host.currentSpeed?.perLaneGbps,
          let lastPerLane = lastLeg.currentSpeed?.perLaneGbps,
          let hostWidth = host.currentWidth,
          let lastWidth = lastLeg.currentWidth else {
        return nil
    }
    let hostLanes = max(hostWidth.txLanes, hostWidth.rxLanes, 1)
    let lastLanes = max(lastWidth.txLanes, lastWidth.rxLanes, 1)
    let hostTotal = hostPerLane * hostLanes
    let lastTotal = lastPerLane * lastLanes

    // Only emit the step-down message when the last leg is genuinely slower.
    guard lastTotal < hostTotal else { return nil }

    let h = hostLabel.replacingOccurrences(of: "Up to", with: "up to")
    let l = lastLabel.replacingOccurrences(of: "Up to", with: "up to")
    return String(localized: "Last leg drops from \(h) to \(l)", bundle: _coreLocalizedBundle)
}

/// Build the structured link-speed badge from the same signals the speed
/// bullets use, so the badge never disagrees with the prose. Returns nil when
/// there's no active data link worth badging (display-only, charge-only,
/// nothing connected). Thunderbolt / USB4 takes priority, then USB 3, then
/// USB 2.
private func resolveLinkSpeed(
    hasTB: Bool,
    hasUSB3: Bool,
    hasUSB2: Bool,
    port: AppleHPMInterface,
    devices: [USBDevice],
    usb3Transports: [USB3Transport],
    switches: [IOThunderboltSwitch]
) -> LinkSpeed? {
    if hasTB {
        // Use the host link's published full-link rate (40 or 80), capped
        // by any TB1/TB2-era device ceiling on the first-hop partner
        // (issue #515). Reuses `DataLinkDiagnostic.activeTBGbps` rather
        // than re-deriving the cap here, so this badge can never disagree
        // with the Pro data-speed breakdown. When we can't match the
        // switch graph for this port, leave the badge off rather than
        // guess a rate.
        guard let total = DataLinkDiagnostic.activeTBGbps(port: port, switches: switches) else {
            return nil
        }
        if total >= 80 {
            return LinkSpeed(tier: .tb80, badge: "80G")
        }
        if total >= 40 {
            return LinkSpeed(tier: .tb40, badge: "40G")
        }
        // TB1/TB2-era device cap (issue #515): the negotiated total can
        // now read below 40 Gbps instead of the misleading shared 40 Gbps
        // code. There is no dedicated Thunderbolt tier under 40 Gbps, so
        // this reuses the existing USB 10G/20G tiers (same badge text,
        // blue rather than green) instead of inventing a new tier case or
        // a new user-facing string.
        if total >= 20 {
            return LinkSpeed(tier: .usb20g, badge: "20G")
        }
        return LinkSpeed(tier: .usb10g, badge: "10G")
    }
    if hasUSB3 {
        switch usb3Gbps(port: port, devices: devices, transports: usb3Transports) {
        case 20: return LinkSpeed(tier: .usb20g, badge: "20G")
        case 10: return LinkSpeed(tier: .usb10g, badge: "10G")
        default: return LinkSpeed(tier: .usb5g, badge: "5G")  // SuperSpeed floor
        }
    }
    if hasUSB2 {
        return LinkSpeed(tier: .usb2, badge: "480M")
    }
    return nil
}

/// Negotiated USB 3 link in Gb/s (5, 10, or 20), using the same precedence as
/// the speed bullet: directly-attached root device first (its `speedRaw`
/// distinguishes 20 Gbps Gen 2x2), then the HPM transport's signaling
/// generation, then a port-matched device. Falls back to the 5 Gbps
/// SuperSpeed floor when nothing finer is available.
private func usb3Gbps(
    port: AppleHPMInterface,
    devices: [USBDevice],
    transports: [USB3Transport]
) -> Int {
    if let raw = USBDevice.rootSuperSpeed(in: devices)?.speedRaw {
        return gbpsFromSpeedRaw(raw)
    }
    // `signaling == 0` is IOKit's "None" sentinel, not Gen 0. The speed bullet
    // treats it as "no info" (USB3Transport.speedLabel returns nil) and falls
    // through to a port-matched device, so the badge must do the same or it
    // would read 5G where the bullet shows 10G/20G.
    if let signaling = USB3SpeedCorroboration.selectedTransport(for: port, in: transports)?.signaling,
       signaling != 0 {
        // Signaling only encodes Gen 1 (1) / Gen 2 (2); 20 Gbps is only seen
        // via a device's speedRaw above or below.
        return signaling >= 2 ? 10 : 5
    }
    if let raw = USBDevice.portMatchedSuperSpeed(in: devices)?.speedRaw {
        return gbpsFromSpeedRaw(raw)
    }
    return 5
}

/// USB device `speedRaw` to Gb/s: 3 = 5 Gbps, 4 = 10 Gbps, 5 = 20 Gbps.
private func gbpsFromSpeedRaw(_ raw: UInt8) -> Int {
    switch raw {
    case 5: return 20
    case 4: return 10
    default: return 5
    }
}

private func subtitleForCapabilities(usb3: Bool, dp: Bool, emarker: Bool) -> String {
    var parts: [String] = []
    if usb3 { parts.append(String(localized: "high-speed data", bundle: _coreLocalizedBundle)) }
    if dp { parts.append(String(localized: "video", bundle: _coreLocalizedBundle)) }
    if emarker { parts.append(String(localized: "smart cable", bundle: _coreLocalizedBundle)) }
    if parts.isEmpty { return String(localized: "Connected.", bundle: _coreLocalizedBundle) }
    let capabilities = parts.joined(separator: ", ")
    return String(localized: "Supports \(capabilities).", bundle: _coreLocalizedBundle)
}
