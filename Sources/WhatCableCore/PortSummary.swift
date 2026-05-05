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
        isConnectedOverride: Bool? = nil
    ) {
        let connected = isConnectedOverride ?? (port.connectionActive == true)
        let active = port.transportsActive
        let supported = port.transportsSupported
        let hasUSB3 = active.contains("USB3") || port.superSpeedActive == true
        let hasUSB2 = active.contains("USB2")
        let hasTB = active.contains("CIO") // Thunderbolt = Converged I/O
        let hasDP = active.contains("DisplayPort")
        let hasEmarker = port.activeCable == true
        let portLabel = port.portDescription ?? port.serviceName

        if !connected {
            self.status = .empty
            self.headline = "Nothing connected"
            self.subtitle = "Plug a cable into \(portLabel) to see what it can do."
            self.bullets = []
            return
        }

        var bullets: [String] = []

        // Speed
        if hasTB {
            bullets.append("Thunderbolt / USB4 link active")
        } else if hasUSB3 {
            bullets.append("SuperSpeed USB (5 Gbps or faster)")
        } else if hasUSB2 {
            bullets.append("USB 2.0 only (480 Mbps) — no high-speed data")
        }

        if hasDP {
            bullets.append("Carrying DisplayPort video")
        }

        // E-marker
        if hasEmarker {
            bullets.append("Cable has an e-marker chip (advertises its capabilities)")
        } else if !active.isEmpty {
            bullets.append("Cable does not advertise an e-marker (basic cable)")
        }

        if port.opticalCable == true {
            bullets.append("Optical cable")
        }

        // Power summary from PD or MagSafe power sources.
        let chargingSource = PowerSource.preferredChargingSource(in: sources)
        if let chargingSource {
            let maxW = Int((Double(chargingSource.maxPowerMW) / 1000).rounded())
            let hasOptions = !chargingSource.options.isEmpty
            if hasOptions && maxW > 0 {
                bullets.append("Charger advertises up to \(maxW)W")
            }
            if let win = chargingSource.winning {
                bullets.append("Currently negotiated: \(win.voltsLabel) @ \(win.ampsLabel) (\(win.wattsLabel))")
            }
        }

        // Cable e-marker (SOP'): the cable's own capabilities
        let cableEmarker = identities.first(where: {
            $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
        })
        if let cable = cableEmarker, let cv = cable.cableVDO {
            bullets.append("Cable speed: \(cv.speed.label)")
            bullets.append("Cable rated for \(cv.current.label) at up to \(cv.maxVolts)V (~\(cv.maxWatts)W)")
            if cv.cableType == .active {
                bullets.append("Active cable (contains signal-conditioning electronics)")
            }
        }

        // Partner identity (SOP): what's connected
        if let partner = identities.first(where: { $0.endpoint == .sop }),
           let header = partner.idHeader {
            let kind = header.ufpProductType != .undefined ? header.ufpProductType.label : header.dfpProductType.label
            bullets.append("Connected device: \(kind) — \(VendorDB.label(for: partner.vendorID))")
        }

        // Cable e-marker vendor (SOP'): who made the cable
        if let cable = cableEmarker, cable.vendorID != 0 {
            bullets.append("Cable made by \(VendorDB.label(for: cable.vendorID))")
        }

        // Headline + status
        // Only show a wattage suffix if we have a real number (>0 and we have
        // options, not just the winning PDO).
        let chargerW: Int? = {
            guard let chargingSource, !chargingSource.options.isEmpty else { return nil }
            let w = Int((Double(chargingSource.maxPowerMW) / 1000).rounded())
            return w > 0 ? w : nil
        }()
        let chargerSuffix = chargerW.map { " · \($0)W charger" } ?? ""

        if hasTB {
            self.status = .thunderboltCable
            self.headline = "Thunderbolt / USB4" + chargerSuffix
            self.subtitle = subtitleForCapabilities(usb3: true, dp: hasDP, emarker: hasEmarker)
        } else if hasUSB3 && hasDP {
            self.status = .displayCable
            self.headline = "USB-C with video" + chargerSuffix
            self.subtitle = "Carrying both data and DisplayPort video."
        } else if hasDP {
            self.status = .displayCable
            self.headline = "Display connected" + chargerSuffix
            self.subtitle = "DisplayPort video over USB-C alt mode."
        } else if hasUSB3 {
            self.status = .dataDevice
            self.headline = "USB device" + chargerSuffix
            self.subtitle = "SuperSpeed data link is active."
        } else if hasUSB2 && !hasUSB3 {
            self.status = .dataDevice
            self.headline = "Slow USB device or charge-only cable" + chargerSuffix
            self.subtitle = "Only USB 2.0 is active. If you expected high speed, the cable may not support it."
        } else if chargingSource != nil {
            self.status = .charging
            self.headline = "Charging" + chargerSuffix
            self.subtitle = "Power is flowing. No data connection."
        } else if active.isEmpty && supported.contains("USB2") {
            self.status = .charging
            self.headline = "Charging only"
            self.subtitle = "Power is flowing but no data link is established."
        } else {
            self.status = .unknown
            self.headline = "Connected"
            self.subtitle = "Couldn't determine cable type from this port."
        }

        self.bullets = bullets
    }
}

private func subtitleForCapabilities(usb3: Bool, dp: Bool, emarker: Bool) -> String {
    var parts: [String] = []
    if usb3 { parts.append("high-speed data") }
    if dp { parts.append("video") }
    if emarker { parts.append("smart cable") }
    if parts.isEmpty { return "Connected." }
    return "Supports " + parts.joined(separator: ", ") + "."
}
