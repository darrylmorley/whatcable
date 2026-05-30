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

    public init(status: Status, headline: String, subtitle: String, bullets: [String]) {
        self.status = status
        self.headline = headline
        self.subtitle = subtitle
        self.bullets = bullets
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
                .first { $0.portKey == port.portKey }?
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

        // Hoist the charging source lookup early. The identity-block
        // wording below and the e-marker guard further down both need
        // to know whether something is sourcing power on this port.
        let chargingSource = PowerSource.preferredChargingSource(in: sources)

        // Whether we'll emit a richer "Charger: <Manufacturer> <Name>"
        // line later (in the charger details block). We use this to
        // avoid double-prefixing with the FedDetails fallback below
        // when both signals identify the same charger.
        let adapterIdentityWillFire = chargingSource != nil
            && (adapter?.manufacturer?.isEmpty == false)

        // Partner identity (SOP): what's connected.
        if let partner = identities.first(where: { $0.endpoint == .sop }),
           let header = partner.idHeader {
            let kind = header.ufpProductType != .undefined ? header.ufpProductType.label : header.dfpProductType.label
            let vendor = VendorDB.label(for: partner.vendorID)
            if let pdRev = partner.pdRevisionLabel {
                bullets.append(String(localized: "Connected device: \(kind), \(vendor) (\(pdRev))", bundle: _coreLocalizedBundle))
            } else {
                bullets.append(String(localized: "Connected device: \(kind), \(vendor)", bundle: _coreLocalizedBundle))
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

        if hasEmarker {
            bullets.append(String(localized: "Cable has an e-marker chip (advertises its capabilities)", bundle: _coreLocalizedBundle))
        } else if hasPayload && !isMagSafe {
            if !pdCapable {
                bullets.append(String(localized: "This port can't read cable details (USB-only port, no Power Delivery)", bundle: _coreLocalizedBundle))
            } else if negotiatedAbove3A || hasTB {
                bullets.append(String(localized: "No e-marker detected. This cable doesn't advertise its capabilities.", bundle: _coreLocalizedBundle))
            } else {
                bullets.append(String(localized: "No e-marker detected. The cable may have one, but macOS only reads it above 3A or with Thunderbolt.", bundle: _coreLocalizedBundle))
            }
        }

        // Cable e-marker (SOP'): the cable's own capabilities.
        let cableEmarker = identities.first(where: {
            $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
        })
        if let cable = cableEmarker, let cv = cable.cableVDO {
            let speedLabel = cv.speed.label
            bullets.append(String(localized: "Cable speed: \(speedLabel)", bundle: _coreLocalizedBundle))
            let currentLabel = cv.current.label
            let maxVolts = cv.maxVolts
            let maxWatts = cv.maxWatts
            bullets.append(String(localized: "Cable rated for \(currentLabel) at up to \(maxVolts)V (~\(maxWatts)W)", bundle: _coreLocalizedBundle))
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
            } else if cv.cableType == .passive && hasTB {
                if let cio = cioCapability,
                   let speed = cio.cableSpeed,
                   let label = CIOCableCapability.speedLabel(for: speed) {
                    // CIO controller confirms the cable's TB capability.
                    // Show the confirmed speed and a short explanation of
                    // why the e-marker says "passive".
                    bullets.append(String(localized: "Controller confirms Thunderbolt cable (\(label))", bundle: _coreLocalizedBundle))
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
        if let cable = cableEmarker, cable.vendorID != 0 {
            let vendor = VendorDB.label(for: cable.vendorID)
            bullets.append(String(localized: "Cable made by \(vendor)", bundle: _coreLocalizedBundle))

            let vdo = cable.vdos.count > 3 ? cable.vdos[3] : 0
            let matches = CableDB.curatedCables(vid: cable.vendorID, pid: cable.productID, cableVDO: vdo)
            if matches.count > 1 {
                let brands = Self.joinedBrands(matches)
                bullets.append(String(localized: "Fingerprint shared across \(brands)", bundle: _coreLocalizedBundle))
            }
        } else if let cable = cableEmarker {
            let vdo = cable.vdos.count > 3 ? cable.vdos[3] : 0
            let matches = CableDB.curatedCables(vid: cable.vendorID, pid: cable.productID, cableVDO: vdo)
            if matches.count == 1 {
                bullets.append(String(localized: "Cable identified as \(matches[0].brand)", bundle: _coreLocalizedBundle))
            } else if matches.count > 1 {
                let brands = Self.joinedBrands(matches)
                bullets.append(String(localized: "Fingerprint shared across \(brands)", bundle: _coreLocalizedBundle))
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
        }

        // Headline wattage: prefer the resolved source, fall back to
        // the per-port PD options for callers that don't pass a source.
        let chargerW: Int? = {
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
        } else if chargingSource != nil {
            self.status = .charging
            if let w = chargerW {
                self.headline = String(localized: "Charging · \(w)W charger", bundle: _coreLocalizedBundle) + cableLimitSuffix
            } else {
                self.headline = String(localized: "Charging", bundle: _coreLocalizedBundle) + cableLimitSuffix
            }
            self.subtitle = String(localized: "Power is flowing. No data connection.", bundle: _coreLocalizedBundle)
        } else if active.isEmpty && supported.contains("USB2"), batteryFullyCharged == true {
            self.status = .batteryFull
            self.headline = String(localized: "Plugged in · battery full", bundle: _coreLocalizedBundle)
            // Battery-full state is shown by the charging banner instead,
            // so the subtitle here would just repeat it. Left empty; the
            // render sites skip an empty subtitle.
            self.subtitle = ""
        } else if active.isEmpty && supported.contains("USB2") {
            self.status = .charging
            self.headline = String(localized: "Charging only", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "Power is flowing but no data link is established.", bundle: _coreLocalizedBundle)
        } else {
            self.status = .unknown
            self.headline = String(localized: "Connected", bundle: _coreLocalizedBundle)
            self.subtitle = String(localized: "Try a higher-wattage charger to identify the cable.", bundle: _coreLocalizedBundle)
        }

        self.bullets = bullets
    }

    private static func joinedBrands(_ cables: [CuratedCable]) -> String {
        var seen = Set<String>()
        let names = cables.map(\.brand).filter { seen.insert($0).inserted }
        if names.count <= 2 {
            return names.joined(separator: " or ")
        }
        return names.dropLast().joined(separator: ", ") + ", or " + names.last!
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
    // downstream switch.
    let downstream = chain.dropFirst()
    if !downstream.isEmpty {
        let names = downstream.map { ThunderboltLabels.deviceName(for: $0) }
        let hops = downstream.count
        let path = names.joined(separator: " → ")
        if hops == 1 {
            bullets.append(String(localized: "Connected to \(path)", bundle: _coreLocalizedBundle))
        } else {
            bullets.append(String(localized: "Connected via \(hops) hops: \(path)", bundle: _coreLocalizedBundle))
        }
    }

    // Step-down detection: only meaningful on real daisy-chains
    // (two or more downstream switches). On a single-hop link, the
    // host's downstream port and the device's upstream port describe
    // the SAME physical cable from opposite ends; the two readings can
    // disagree on lane count (the controller-side view aggregates lanes
    // that the device-side view doesn't), and that disagreement is not
    // a real step-down. With two or more hops, comparing the first link
    // (host -> device 1) to the last link (device N-1 -> device N)
    // genuinely contrasts two distinct cables.
    if downstream.count >= 2,
       let hostPort = ThunderboltTopology.activeDownstreamLanePort(root),
       let last = downstream.last,
       let lastLeg = ThunderboltTopology.activeDownstreamLanePort(last)
            ?? last.ports.first(where: { $0.adapterType.isLane && $0.hasActiveLink }),
       let stepLabel = stepDownLabel(host: hostPort, lastLeg: lastLeg) {
        bullets.append(stepLabel)
    }

    return bullets
}

/// If the last-leg link is slower than the host link (per-lane Gbps drop
/// or lane count drop), describe the change. Returns nil for symmetric
/// chains where every leg matches.
private func stepDownLabel(host: IOThunderboltPort, lastLeg: IOThunderboltPort) -> String? {
    guard let hostLabel = ThunderboltLabels.linkLabel(for: host),
          let lastLabel = ThunderboltLabels.linkLabel(for: lastLeg) else {
        return nil
    }
    if hostLabel == lastLabel { return nil }
    let h = hostLabel.replacingOccurrences(of: "Up to", with: "up to")
    let l = lastLabel.replacingOccurrences(of: "Up to", with: "up to")
    return String(localized: "Last leg drops from \(h) to \(l)", bundle: _coreLocalizedBundle)
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
