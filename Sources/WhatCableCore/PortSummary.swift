import Foundation

/// Plain-English interpretation of a USBCPort's raw IOKit data.
public struct PortSummary {
    public enum Status {
        case empty
        case charging
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
        port: USBCPort,
        sources: [PowerSource] = [],
        identities: [PDIdentity] = [],
        devices: [USBDevice] = [],
        thunderboltSwitches: [ThunderboltSwitch] = [],
        isConnectedOverride: Bool? = nil,
        language: WhatCableLanguage = .default
    ) {
        func tr(_ key: String.LocalizationValue) -> String {
            LocalizedCopy.string(key, language: language)
        }

        let connected = isConnectedOverride ?? (port.connectionActive == true)
        let active = port.transportsActive
        let supported = port.transportsSupported
        let hasUSB3 = active.contains("USB3") || port.superSpeedActive == true
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
        // which means we have an SOP'/SOP'' PDIdentity for this port. The
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
            self.headline = tr("Nothing connected")
            self.subtitle = tr("Plug a cable into \(portLabel) to see what it can do.")
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
            let tbBullets = thunderboltBullets(for: port, switches: thunderboltSwitches, language: language)
            if tbBullets.isEmpty {
                bullets.append(tr("Thunderbolt / USB4 link active"))
            } else {
                bullets.append(contentsOf: tbBullets)
            }
        } else if hasUSB3 {
            bullets.append(tr("SuperSpeed USB (5 Gbps or faster)"))
        } else if hasUSB2 {
            bullets.append(tr("USB 2.0 only (480 Mbps), no high-speed data"))
        }

        if hasDP {
            bullets.append(tr("Carrying DisplayPort video"))
        }

        // Partner identity (SOP): what's connected.
        if let partner = identities.first(where: { $0.endpoint == .sop }),
           let header = partner.idHeader {
            let kind = header.ufpProductType != .undefined ? header.ufpProductType.label(language: language) : header.dfpProductType.label(language: language)
            let vendor = VendorDB.label(for: partner.vendorID)
            bullets.append(tr("Connected device: \(kind), \(vendor)"))
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
        if hasEmarker {
            bullets.append(tr("Cable has an e-marker chip (advertises its capabilities)"))
        } else if !active.isEmpty && !isMagSafe {
            if pdCapable {
                bullets.append(tr("Cable does not advertise an e-marker (basic cable)"))
            } else {
                bullets.append(tr("This port can't read cable details (USB-only port, no Power Delivery)"))
            }
        }

        // Cable e-marker (SOP'): the cable's own capabilities.
        let cableEmarker = identities.first(where: {
            $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
        })
        if let cable = cableEmarker, let cv = cable.cableVDO {
            let speedLabel = cv.speed.label(language: language)
            bullets.append(tr("Cable speed: \(speedLabel)"))
            let currentLabel = cv.current.label(language: language)
            let maxVolts = cv.maxVolts
            let maxWatts = cv.maxWatts
            bullets.append(tr("Cable rated for \(currentLabel) at up to \(maxVolts)V (~\(maxWatts)W)"))
            if cv.cableType == .active {
                if let v2 = cable.activeCableVDO2 {
                    let medium = v2.physicalConnection.label(language: language).lowercased()
                    let element = v2.activeElement.label(language: language).lowercased()
                    bullets.append(tr("Active \(medium) cable, \(element)"))
                    if v2.physicalConnection == .optical {
                        if v2.opticallyIsolated {
                            bullets.append(tr("Optical fibres are electrically isolated end-to-end"))
                        } else {
                            bullets.append(tr("Optical cable, not electrically isolated (carries copper alongside the fibres)"))
                        }
                    }
                } else {
                    bullets.append(tr("Active cable (contains signal-conditioning electronics)"))
                }
            }
        }

        // Port-level optical flag. Independent of the e-marker's claim;
        // kept on its own line for now so users can see both signals.
        if port.opticalCable == true {
            bullets.append(tr("Optical cable"))
        }

        // Cable e-marker vendor (SOP'): who made the cable.
        if let cable = cableEmarker, cable.vendorID != 0 {
            let vendor = VendorDB.label(for: cable.vendorID)
            bullets.append(tr("Cable made by \(vendor)"))
        }

        // ------------------------------------------------------------
        // C. Charging numbers
        // ------------------------------------------------------------

        // Power summary from PD or MagSafe power sources.
        let chargingSource = PowerSource.preferredChargingSource(in: sources)
        if let chargingSource {
            let maxW = Int((Double(chargingSource.maxPowerMW) / 1000).rounded())
            let hasOptions = !chargingSource.options.isEmpty
            if hasOptions && maxW > 0 {
                bullets.append(tr("Charger advertises up to \(maxW)W"))
            }
            if let win = chargingSource.winning {
                let volts = win.voltsLabel
                let amps = win.ampsLabel
                let watts = win.wattsLabel
                bullets.append(tr("Currently negotiated: \(volts) @ \(amps) (\(watts))"))
            }
        }

        // Headline + status
        // Only show a wattage suffix if we have a real number (>0 and we have
        // options, not just the winning PDO).
        let chargerW: Int? = {
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
            return tr(" · \(cableW)W cable")
        }()

        if hasTB {
            self.status = .thunderboltCable
            if let w = chargerW {
                self.headline = tr("Thunderbolt / USB4 · \(w)W charger") + cableLimitSuffix
            } else {
                self.headline = tr("Thunderbolt / USB4") + cableLimitSuffix
            }
            self.subtitle = subtitleForCapabilities(usb3: true, dp: hasDP, emarker: hasEmarker, language: language)
        } else if hasUSB3 && hasDP {
            self.status = .displayCable
            if let w = chargerW {
                self.headline = tr("USB-C with video · \(w)W charger") + cableLimitSuffix
            } else {
                self.headline = tr("USB-C with video") + cableLimitSuffix
            }
            self.subtitle = tr("Carrying both data and DisplayPort video.")
        } else if hasDP {
            self.status = .displayCable
            if let w = chargerW {
                self.headline = tr("Display connected · \(w)W charger") + cableLimitSuffix
            } else {
                self.headline = tr("Display connected") + cableLimitSuffix
            }
            self.subtitle = tr("DisplayPort video over USB-C alt mode.")
        } else if hasUSB3 {
            self.status = .dataDevice
            if let w = chargerW {
                self.headline = tr("USB device · \(w)W charger") + cableLimitSuffix
            } else {
                self.headline = tr("USB device") + cableLimitSuffix
            }
            self.subtitle = tr("SuperSpeed data link is active.")
        } else if hasUSB2 && !hasUSB3 {
            self.status = .dataDevice
            if let w = chargerW {
                self.headline = tr("Slow USB device or charge-only cable · \(w)W charger") + cableLimitSuffix
            } else {
                self.headline = tr("Slow USB device or charge-only cable") + cableLimitSuffix
            }
            self.subtitle = tr("Only USB 2.0 is active. If you expected high speed, the cable may not support it.")
        } else if chargingSource != nil {
            self.status = .charging
            if let w = chargerW {
                self.headline = tr("Charging · \(w)W charger") + cableLimitSuffix
            } else {
                self.headline = tr("Charging") + cableLimitSuffix
            }
            self.subtitle = tr("Power is flowing. No data connection.")
        } else if active.isEmpty && supported.contains("USB2") {
            self.status = .charging
            self.headline = tr("Charging only")
            self.subtitle = tr("Power is flowing but no data link is established.")
        } else {
            self.status = .unknown
            self.headline = tr("Connected")
            self.subtitle = tr("Couldn't determine cable type from this port.")
        }

        self.bullets = bullets
    }
}

/// Build the TB-specific bullets for a port whose `transportsActive`
/// includes `"CIO"`. Returns an empty array if we can't find a matching
/// switch (e.g. the port doesn't have an `@N` suffix, or the Thunderbolt
/// watcher hasn't populated yet). Caller falls back to a generic bullet
/// in that case.
private func thunderboltBullets(
    for port: USBCPort,
    switches: [ThunderboltSwitch],
    language: WhatCableLanguage = .default
) -> [String] {
    func tr(_ key: String.LocalizationValue) -> String {
        LocalizedCopy.string(key, language: language)
    }

    guard !switches.isEmpty,
          let socketID = ThunderboltTopology.socketID(fromServiceName: port.serviceName),
          let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches) else {
        return []
    }

    let chain = ThunderboltTopology.chain(from: root, in: switches)
    var bullets: [String] = []

    // First-hop link state: the host root's downstream lane port describes
    // the cable's negotiated speed.
    if let hostPort = ThunderboltTopology.activeDownstreamLanePort(root),
       let label = ThunderboltLabels.linkLabel(for: hostPort, language: language) {
        // label is e.g. "Up to 20 Gb/s × 2" — replace the leading "Up"
        // with "up" for the bullet phrasing without lowercasing units.
        let linkSpeed = label.replacingOccurrences(of: "Up to", with: "up to")
        bullets.append(tr("Linked at \(linkSpeed)"))
    }

    // Connected-device line. Only meaningful when there's at least one
    // downstream switch.
    let downstream = chain.dropFirst()
    if !downstream.isEmpty {
        let names = downstream.map { ThunderboltLabels.deviceName(for: $0, language: language) }
        let hops = downstream.count
        let path = names.joined(separator: " → ")
        if hops == 1 {
            bullets.append(tr("Connected to \(path)"))
        } else {
            bullets.append(tr("Connected via \(hops) hops: \(path)"))
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
       let stepLabel = stepDownLabel(host: hostPort, lastLeg: lastLeg, language: language) {
        bullets.append(stepLabel)
    }

    return bullets
}

/// If the last-leg link is slower than the host link (per-lane Gbps drop
/// or lane count drop), describe the change. Returns nil for symmetric
/// chains where every leg matches.
private func stepDownLabel(
    host: ThunderboltPort,
    lastLeg: ThunderboltPort,
    language: WhatCableLanguage = .default
) -> String? {
    guard let hostLabel = ThunderboltLabels.linkLabel(for: host, language: language),
          let lastLabel = ThunderboltLabels.linkLabel(for: lastLeg, language: language) else {
        return nil
    }
    if hostLabel == lastLabel { return nil }
    let h = hostLabel.replacingOccurrences(of: "Up to", with: "up to")
    let l = lastLabel.replacingOccurrences(of: "Up to", with: "up to")
    return LocalizedCopy.string("Last leg drops from \(h) to \(l)", language: language)
}

private func subtitleForCapabilities(
    usb3: Bool,
    dp: Bool,
    emarker: Bool,
    language: WhatCableLanguage = .default
) -> String {
    var parts: [String] = []
    if usb3 { parts.append(LocalizedCopy.string("high-speed data", language: language)) }
    if dp { parts.append(LocalizedCopy.string("video", language: language)) }
    if emarker { parts.append(LocalizedCopy.string("smart cable", language: language)) }
    if parts.isEmpty { return LocalizedCopy.string("Connected.", language: language) }
    let capabilities = parts.joined(separator: ", ")
    return LocalizedCopy.string("Supports \(capabilities).", language: language)
}
