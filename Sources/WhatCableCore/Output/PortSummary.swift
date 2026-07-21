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

    public let status: Status
    public let headline: String
    public let subtitle: String
    public let bullets: [String]
    /// Structured negotiated link speed for badges / JSON. Nil when there's no
    /// active data link to badge (empty port, charge-only, display-only).
    public let linkSpeed: LinkSpeed?

    public init(status: Status, headline: String, subtitle: String, bullets: [String], linkSpeed: LinkSpeed? = nil) {
        self.status = status
        self.headline = headline
        self.subtitle = subtitle
        self.bullets = bullets
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
        cioCapability: CIOCableCapability? = nil,
        isConnectedOverride: Bool? = nil,
        chargerWattageSource: ChargerWattageSource = .unknown,
        batteryFullyCharged: Bool? = nil,
        batteryIsCharging: Bool? = nil,
        adapter: AdapterInfo? = nil
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
        let hasUSB2 = active.contains("USB2")
        let hasTB = active.contains("CIO") // Thunderbolt = Converged I/O
        let hasDP = active.contains("DisplayPort")
        // Configuration Channel: required for USB-PD. Without CC the OS cannot
        // run Discover Identity, so we can't infer anything about the cable's
        // e-marker. M4 Mac Mini front USB-C ports are an example: they hang
        // off a plain xHCI controller (no PD), so reporting "basic cable" on
        // them wrongly blames the cable. See issue #50.
        let pdCapable = supported.contains("CC")
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
            self.bullets = []
            self.linkSpeed = nil
            return
        }

        var bullets: [String] = []

        // Bullets are grouped by the question the user is mentally asking,
        // so related facts sit next to each other:
        //
        //   A. What's happening on this port and what's plugged in?
        //      - link speed / Thunderbolt link
        //      - DisplayPort note
        //      - connected device
        //   B. What does the cable advertise?
        //      - e-marker presence
        //      - cable speed and power rating
        //      - active-cable details (medium, element, isolation)
        //      - port-level optical flag
        //      - cable maker
        //   C. What does the power negotiation look like?
        //      - charger max
        //      - currently negotiated PDO

        // ------------------------------------------------------------
        // A. Live link / what's plugged in
        // ------------------------------------------------------------

        if hasTB {
            // If we have a matching Thunderbolt switch graph for this port,
            // emit specific link-state bullets (negotiated speed, lane
            // count, daisy-chain info). Otherwise fall back to the generic
            // "active" line so older paths still work.
            let tbBullets = thunderboltBullets(for: port, switches: thunderboltSwitches)
            if tbBullets.isEmpty {
                bullets.append(String(localized: "Thunderbolt / USB4 link active", bundle: _coreLocalizedBundle))
            } else {
                bullets.append(contentsOf: tbBullets)
            }
        } else if hasUSB3 {
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
            let transportLabel = usb3Transports
                .first { $0.canonicallyMatches(port: port) }?
                .speedLabel
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
                bullets.append(label)
            } else {
                bullets.append(String(localized: "SuperSpeed USB (5 Gbps or faster)", bundle: _coreLocalizedBundle))
            }
        } else if hasUSB2 {
            bullets.append(String(localized: "USB 2.0 only (480 Mbps), no high-speed data", bundle: _coreLocalizedBundle))
        }

        if hasDP {
            // `hasDP` and `dpLaneConfig` are gated on the same signal
            // (DisplayPort in transportsActive), so the config is always
            // present here; no plain-video fallback is reachable.
            if let dpConfig = port.dpLaneConfig {
                bullets.append(String(localized: "Carrying DisplayPort video (\(dpConfig.label))", bundle: _coreLocalizedBundle))
            }
        }

        // A controller can retain a winning PDO while the system rejects
        // external power. In that state the source still describes the port's
        // last negotiation, but it must not drive charging copy or wattage.
        let systemPowerUnavailable = batteryIsCharging == false
            && batteryFullyCharged != true
            && adapter == nil

        // Hoist the charging source lookup early. The identity-block
        // wording below and the e-marker guard further down both need
        // to know whether something is sourcing power on this port.
        let chargingSource = systemPowerUnavailable
            ? nil
            : PowerSource.preferredChargingSource(in: sources)

        // Whether we'll emit a richer "Charger: <Manufacturer> <Name>"
        // line later (in the charger details block). We use this to
        // avoid double-prefixing with the FedDetails fallback below
        // when both signals identify the same charger.
        let adapterIdentityWillFire = chargingSource != nil
            && (adapter?.manufacturer?.isEmpty == false)

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
                    bullets.append(String(localized: "Charger identified as \(label)", bundle: _coreLocalizedBundle))
                }
                // If adapterIdentityWillFire, a richer "Charger: <mfr> <name>"
                // line is coming later; skip to avoid a double charger line
                // (mirrors the federated branch's guard).
            } else {
                let kind = header.ufpProductType != .undefined ? header.ufpProductType.label : header.dfpProductType.label
                if let pdRev = partner.pdRevisionLabel {
                    bullets.append(String(localized: "Connected device: \(kind), \(vendor) (\(pdRev))", bundle: _coreLocalizedBundle))
                } else {
                    bullets.append(String(localized: "Connected device: \(kind), \(vendor)", bundle: _coreLocalizedBundle))
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
            if chargingSource != nil && !adapterIdentityWillFire {
                // A charging source is on this port and we don't have
                // a richer Manufacturer/Name pair from AdapterDetails;
                // label this as the charger.
                bullets.append(String(localized: "Charger identified as \(vendor)", bundle: _coreLocalizedBundle))
            } else if chargingSource == nil {
                // No charging source: the connected thing is a
                // peripheral, dock, drive, etc. Keep the generic
                // wording.
                bullets.append(String(localized: "Connected device: \(vendor)", bundle: _coreLocalizedBundle))
            }
            // If chargingSource != nil && adapterIdentityWillFire,
            // the AdapterDetails "Charger:" line is coming later with
            // a richer label; skip this one to avoid double-prefix.
        }

        // ------------------------------------------------------------
        // B. The cable
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

        if hasEmarker {
            if emarkerRead {
                bullets.append(String(localized: "Cable has an e-marker chip (advertises its capabilities)", bundle: _coreLocalizedBundle))
            } else {
                bullets.append(String(localized: "Cable has an e-marker chip, not read on this connection (needs above 3A or Thunderbolt, or try reconnecting the cable)", bundle: _coreLocalizedBundle))
            }
        } else if hasPayload && !isMagSafe {
            if !pdCapable {
                bullets.append(String(localized: "This port can't read cable details (USB-only port, no Power Delivery)", bundle: _coreLocalizedBundle))
            } else if negotiatedAbove3A || hasTB {
                bullets.append(String(localized: "No e-marker detected. This cable doesn't advertise its capabilities.", bundle: _coreLocalizedBundle))
            } else {
                bullets.append(String(localized: "No e-marker detected. The cable may have one, but macOS only reads it above 3A or with Thunderbolt.", bundle: _coreLocalizedBundle))
            }
        }

        if let cable = cableEmarker, let cv = cable.cableVDO {
            let speedLabel = cv.speed.label
            bullets.append(String(localized: "Cable speed: \(speedLabel)", bundle: _coreLocalizedBundle))
            let currentLabel = cv.current.label
            let maxVolts = cv.maxVolts
            let maxWatts = cv.maxWatts
            if maxVolts > 48 {
                // The cable's voltage rating (50V) sits above USB-PD's 48V
                // delivery ceiling, so rating × current overstates the power.
                // Show the rating and the deliverable figure as separate facts
                // with the reason, so the two numbers don't read as a broken
                // multiply (50 × 5 = 250, but the cable can only carry 240W).
                bullets.append(String(localized: "Cable rated to \(maxVolts)V / \(currentLabel), delivers up to \(maxWatts)W (USB-PD caps at 48V)", bundle: _coreLocalizedBundle))
            } else {
                bullets.append(String(localized: "Cable rated for \(currentLabel) at up to \(maxVolts)V (~\(maxWatts)W)", bundle: _coreLocalizedBundle))
            }
            if cv.cableType == .active {
                if let v2 = cable.activeCableVDO2 {
                    let medium = v2.physicalConnection.label.lowercased()
                    let element = v2.activeElement.label.lowercased()
                    bullets.append(String(localized: "Active \(medium) cable, \(element)", bundle: _coreLocalizedBundle))
                    if v2.physicalConnection == .optical {
                        if v2.opticallyIsolated {
                            bullets.append(String(localized: "Optical fibres are electrically isolated end-to-end", bundle: _coreLocalizedBundle))
                        } else {
                            bullets.append(String(localized: "Optical cable, not electrically isolated (carries copper alongside the fibres)", bundle: _coreLocalizedBundle))
                        }
                    }
                } else {
                    bullets.append(String(localized: "Active cable (contains signal-conditioning electronics)", bundle: _coreLocalizedBundle))
                }
            } else if cv.cableType == .passive && cable.hasActiveLayoutContradiction {
                // The cable's ID Header says passive, but VDO[3] has the
                // "SOP'' Controller Present" bit set, a field that only exists
                // in the active-cable layout. That structural contradiction
                // suggests this is really an active cable with a mis-programmed
                // e-marker (confirmed real case: CalDigit 2M Thunderbolt 4).
                // Surface the note with hedged wording; VDO[3] is kept decoded
                // under the passive layout to avoid raising false trust flags.
                bullets.append(String(localized: "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)", bundle: _coreLocalizedBundle))
                if let v2 = cable.activeCableVDO2 {
                    let medium = v2.physicalConnection.label.lowercased()
                    let element = v2.activeElement.label.lowercased()
                    // Reuses the same key as the normal active-cable VDO2 line
                    // so no new localisation key is needed for the medium/element.
                    bullets.append(String(localized: "Active \(medium) cable, \(element)", bundle: _coreLocalizedBundle))
                }
            } else if cv.cableType == .passive && hasTB {
                if let cio = cioCapability,
                   let speed = cio.negotiatedLinkSpeed,
                   let label = CIOCableCapability.speedLabel(for: speed),
                   let cioGbps = DataLinkDiagnostic.cioCableGbps(speed) {
                    // The controller's figure is the NEGOTIATED link rate,
                    // a floor on cable capability, never a cap (issue
                    // #393). Only call it a genuine confirmation when the
                    // controller measured at least what the e-marker
                    // claims; when the e-marker claims a higher tier than
                    // the controller measured, describing the *cable* as
                    // "N Gbps capable" would understate it, so describe
                    // the *link* instead and leave the cable's capability
                    // to the "Cable speed" bullet above.
                    if !DataLinkDiagnostic.meaningfullySlower(cioGbps, than: cv.speed.maxGbps) {
                        bullets.append(String(localized: "Controller confirms Thunderbolt cable (\(label))", bundle: _coreLocalizedBundle))
                    } else {
                        bullets.append(String(localized: "Thunderbolt link active at \(DataLinkDiagnostic.label(cioGbps))", bundle: _coreLocalizedBundle))
                    }
                    bullets.append(String(localized: "E-marker reports passive. This is normal for Thunderbolt cables where the active electronics handle Thunderbolt, not USB.", bundle: _coreLocalizedBundle))
                } else {
                    // No CIO data (or unrecognised speed code): keep the
                    // existing educational fallback.
                    bullets.append(String(localized: "E-marker reports passive (no USB signal conditioning). Thunderbolt is negotiated separately by the controller.", bundle: _coreLocalizedBundle))
                }
            }
        }

        // Port-level optical flag. Independent of the e-marker's claim;
        // kept on its own line for now so users can see both signals.
        if port.opticalCable == true {
            bullets.append(String(localized: "Optical cable", bundle: _coreLocalizedBundle))
        }

        // Cable e-marker vendor (SOP'): who made the cable.
        //
        // The VID gives the silicon vendor (honest, even when an unrelated
        // retail brand is on the sleeve). A curated retail brand/model is
        // only shown on a full VID+PID match: curatedCables ignores the Cable
        // VDO (a capability spec shared across brands) and returns nothing
        // unless both VID and PID are present. So a zeroed-identity cable
        // shows no maker and no brand, just its capabilities. See #239.
        if let cable = cableEmarker, cable.vendorID != 0 {
            let vendor = VendorDB.label(for: cable.vendorID)
            bullets.append(String(localized: "Cable made by \(vendor)", bundle: _coreLocalizedBundle))

            if let match = CableDB.curatedCables(vid: cable.vendorID, pid: cable.productID).first {
                bullets.append(String(localized: "Cable identified as \(match.brand)", bundle: _coreLocalizedBundle))
            }
        }

        // ------------------------------------------------------------
        // C. Charging numbers
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
                    bullets.append(String(localized: "Charger: \(manufacturer) \(name)", bundle: _coreLocalizedBundle))
                } else {
                    bullets.append(String(localized: "Charger: \(manufacturer)", bundle: _coreLocalizedBundle))
                }
            }

            switch chargerWattageSource {
            case .portNegotiated(let w) where w > 0:
                bullets.append(String(localized: "Charger advertises up to \(w)W", bundle: _coreLocalizedBundle))
            case .systemAdapterFallback(let w):
                bullets.append(String(localized: "System reports charger at \(w)W", bundle: _coreLocalizedBundle))
            default:
                let maxW = Int((Double(chargingSource.maxPowerMW) / 1000).rounded())
                let hasOptions = !chargingSource.options.isEmpty
                if hasOptions && maxW > 0 {
                    bullets.append(String(localized: "Charger advertises up to \(maxW)W", bundle: _coreLocalizedBundle))
                }
            }
            if let win = chargingSource.winning {
                let volts = win.voltsLabel
                let amps = win.ampsLabel
                let watts = win.wattsLabel
                bullets.append(String(localized: "Currently negotiated: \(volts) @ \(amps) (\(watts))", bundle: _coreLocalizedBundle))
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
                    bullets.append(String(localized: "Charger: \(manufacturer) \(name)", bundle: _coreLocalizedBundle))
                } else {
                    bullets.append(String(localized: "Charger: \(manufacturer)", bundle: _coreLocalizedBundle))
                }
            }
            bullets.append(String(localized: "System reports charger at \(w)W", bundle: _coreLocalizedBundle))
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
        } else if hasUSB3 && hasDP {
            self.status = .displayCable
            if let w = chargerW {
                self.headline = String(localized: "USB-C with video · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "USB-C with video", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = String(localized: "Carrying both data and DisplayPort video.", bundle: _coreLocalizedBundle)
        } else if hasDP {
            self.status = .displayCable
            if let w = chargerW {
                self.headline = String(localized: "Display connected · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "Display connected", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = String(localized: "DisplayPort video over USB-C Alt Mode.", bundle: _coreLocalizedBundle)
        } else if hasUSB3 {
            self.status = .dataDevice
            if let w = chargerW {
                self.headline = String(localized: "USB device · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "USB device", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = String(localized: "SuperSpeed data link is active.", bundle: _coreLocalizedBundle)
        } else if hasUSB2 && !hasUSB3 {
            self.status = .dataDevice
            if let w = chargerW {
                self.headline = String(localized: "Slow USB device or charge-only cable · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "Slow USB device or charge-only cable", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = String(localized: "Only USB 2.0 is active. If you expected high speed, the cable may not support it.", bundle: _coreLocalizedBundle)
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
        } else if active.isEmpty && supported.contains("USB2"), batteryFullyCharged == true {
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
        } else {
            self.status = .unknown
            self.headline = String(localized: "Connected", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "Try a higher-wattage charger to identify the cable.", bundle: _coreLocalizedBundle)
        }

        self.bullets = bullets
        self.linkSpeed = resolveLinkSpeed(
            hasTB: hasTB,
            hasUSB3: hasUSB3,
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
    if let hostPort = ThunderboltTopology.activeDownstreamLanePort(root),
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
       let hostPort = ThunderboltTopology.activeDownstreamLanePort(root),
       let last = downstream.last,
       let lastLeg = ThunderboltTopology.activeDownstreamLanePort(last)
            ?? last.ports.first(where: { $0.adapterType.isLane && $0.hasActiveLink }),
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
        // Use the host link's published full-link rate (40 or 80). When we
        // can't match the switch graph for this port, leave the badge off
        // rather than guess a rate.
        guard let total = thunderboltTotalGbps(for: port, switches: switches) else {
            return nil
        }
        if total >= 80 {
            return LinkSpeed(tier: .tb80, badge: "80G")
        }
        return LinkSpeed(tier: .tb40, badge: "40G")
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

/// Published full-link Gb/s for the Thunderbolt host link on this port, or nil
/// if we can't find the matching switch graph. Mirrors `thunderboltBullets`'s
/// host-port lookup so the badge tracks the "Linked at ..." bullet.
private func thunderboltTotalGbps(
    for port: AppleHPMInterface,
    switches: [IOThunderboltSwitch]
) -> Double? {
    guard !switches.isEmpty,
          let socketID = ThunderboltTopology.socketID(for: port),
          let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches),
          let hostPort = ThunderboltTopology.activeDownstreamLanePort(root) else {
        return nil
    }
    return hostPort.currentSpeed?.totalGbps
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
    if let signaling = transports.first(where: { $0.canonicallyMatches(port: port) })?.signaling,
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
