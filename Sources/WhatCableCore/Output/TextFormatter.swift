import Foundation

public enum TextFormatter {
    public static func render(
        ports: [AppleHPMInterface],
        sources: [PowerSource],
        identities: [USBPDSOP],
        showRaw: Bool,
        adapter: AdapterInfo? = nil,
        thunderboltSwitches: [IOThunderboltSwitch] = [],
        isDesktopMac: Bool = false,
        batteryFullyCharged: Bool? = nil,
        federatedIdentities: [FederatedIdentity] = [],
        usb3Transports: [USB3Transport] = [],
        cioCapabilities: [CIOCableCapability] = [],
        usbDevices: [USBDevice] = [],
        displayPorts: [IOPortTransportStateDisplayPort] = []
    ) -> String {
        if ports.isEmpty {
            return String(localized: "No USB-C / MagSafe ports were found on this Mac.", bundle: _coreLocalizedBundle) + "\n"
        }

        var out = ""
        if isDesktopMac {
            out += ANSI.wrap(ANSI.dim, "Desktop Mac: charger identity (FedDetails) is not available (no battery controller).") + "\n\n"
        }
        let activePortCount = ports.filter { $0.connectionActive == true }.count
        for (i, port) in ports.enumerated() {
            if i > 0 { out += "\n" }
            let portSources = filterSources(port, all: sources)
            let wattageSource = ChargerWattageSource.resolve(
                portSources: portSources,
                activePortCount: activePortCount,
                adapter: adapter
            )
            out += renderPort(
                port,
                sources: portSources,
                identities: filterIdentities(port, all: identities),
                showRaw: showRaw,
                adapter: adapter,
                thunderboltSwitches: thunderboltSwitches,
                federatedIdentities: federatedIdentities,
                usb3Transports: usb3Transports.filter { $0.portKey == port.portKey },
                cioCapability: cioCapabilities.first { $0.portKey == port.portKey },
                chargerWattageSource: wattageSource,
                batteryFullyCharged: batteryFullyCharged,
                usbDevices: port.matchingDevices(from: usbDevices),
                displayPort: displayPorts.first { $0.portKey == port.portKey }
            )
        }
        return out
    }

    private static func renderPort(
        _ port: AppleHPMInterface,
        sources: [PowerSource],
        identities: [USBPDSOP],
        showRaw: Bool,
        adapter: AdapterInfo?,
        thunderboltSwitches: [IOThunderboltSwitch],
        federatedIdentities: [FederatedIdentity] = [],
        usb3Transports: [USB3Transport] = [],
        cioCapability: CIOCableCapability? = nil,
        chargerWattageSource: ChargerWattageSource = .unknown,
        batteryFullyCharged: Bool? = nil,
        usbDevices: [USBDevice] = [],
        displayPort: IOPortTransportStateDisplayPort? = nil
    ) -> String {
        let summary = PortSummary(
            port: port,
            sources: sources,
            identities: identities,
            devices: usbDevices,
            thunderboltSwitches: thunderboltSwitches,
            federatedIdentities: federatedIdentities,
            usb3Transports: usb3Transports,
            cioCapability: cioCapability,
            chargerWattageSource: chargerWattageSource,
            batteryFullyCharged: batteryFullyCharged,
            adapter: adapter
        )
        let label = port.portDescription ?? port.serviceName
        let typeSuffix = port.portTypeDescription.map { " (\($0))" } ?? ""

        let header = "=== \(label)\(typeSuffix) ==="
        var out = ANSI.wrap(ANSI.bold + ANSI.cyan, header) + "\n"

        let headlineColor = color(for: summary.status)
        out += ANSI.wrap(ANSI.bold + headlineColor, summary.headline) + "\n"
        if !summary.subtitle.isEmpty {
            out += ANSI.wrap(ANSI.dim, summary.subtitle) + "\n"
        }

        if !summary.bullets.isEmpty {
            out += "\n"
            for bullet in summary.bullets {
                out += "  " + ANSI.wrap(ANSI.gray, "•") + " \(bullet)\n"
            }
        }

        if let diag = ChargingDiagnostic(port: port, sources: sources, identities: identities, adapter: adapter, wattageSource: chargerWattageSource, batteryFullyCharged: batteryFullyCharged) {
            let diagColor = diag.isWarning ? ANSI.yellow : ANSI.green
            out += "\n" + ANSI.wrap(ANSI.bold, String(localized: "Charging: ", bundle: _coreLocalizedBundle)) + ANSI.wrap(diagColor, diag.summary) + "\n"
            out += "  " + ANSI.wrap(ANSI.dim, diag.detail) + "\n"
        }

        if let dataDiag = DataLinkDiagnostic(
            port: port,
            identities: identities,
            devices: usbDevices,
            usb3Transports: usb3Transports,
            cio: cioCapability,
            thunderboltSwitches: thunderboltSwitches
        ) {
            let dataColor = dataDiag.isWarning ? ANSI.yellow : ANSI.green
            out += "\n" + ANSI.wrap(ANSI.bold, "Data: ") + ANSI.wrap(dataColor, dataDiag.summary) + "\n"
            out += "  " + ANSI.wrap(ANSI.dim, dataDiag.detail) + "\n"
        }

        // Display verdict. The cable e-marker is passed only so the verdict
        // can exonerate (not convict) the cable on an active-cable check.
        let displayCable = identities.first { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }
        if let displayPort, let displayDiag = DisplayDiagnostic(dp: displayPort, cable: displayCable) {
            let displayColor = displayDiag.isWarning ? ANSI.yellow : ANSI.green
            out += "\n" + ANSI.wrap(ANSI.bold, "Display: ") + ANSI.wrap(displayColor, displayDiag.summary) + "\n"
            out += "  " + ANSI.wrap(ANSI.dim, displayDiag.detail) + "\n"
        }

        // Name only, no diagnosis (a Billboard device is often benign). The
        // Alt-Mode inference is reserved for the Pro Display screen.
        if port.hasBillboardDevice(among: usbDevices) {
            out += "  " + ANSI.wrap(ANSI.gray, "\u{2022}") + " " + String(localized: "Billboard device present", bundle: _coreLocalizedBundle) + "\n"
        }

        if !usbDevices.isEmpty {
            let tree = USBDeviceNode.flatten(USBDeviceNode.buildTree(from: usbDevices))
            out += "\n" + ANSI.wrap(ANSI.bold, String(localized: "Connected devices:", bundle: _coreLocalizedBundle)) + "\n"
            for node in tree {
                let indent = String(repeating: "  ", count: node.depth + 1)
                let name = node.device.productName ?? String(localized: "Unknown", bundle: _coreLocalizedBundle)
                let prefix = node.depth > 0 ? "\u{21B3}" : ANSI.wrap(ANSI.gray, "\u{2022}")
                out += "\(indent)\(prefix) \(name) - \(node.device.speedLabel)\n"
            }
        }

        // Cable trust signals: hedged flags raised against the e-marker.
        // Match the popover's behaviour: only render when at least one flag
        // fires, and use the same titles + details so wording stays
        // consistent across surfaces.
        if let cable = identities.first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }) {
            let partner = identities.first(where: { $0.endpoint == .sop })
            let trust = CableTrustReport(identity: cable, partner: partner)
            if !trust.isEmpty {
                // A block with any real warning reads as a warning (yellow
                // header). A notes-only block reads calm (gray header), so a
                // softened false-positive doesn't look like an alarm.
                let hasWarning = trust.flags.contains { $0.severity == .warning }
                let header = hasWarning
                    ? ANSI.wrap(ANSI.bold + ANSI.yellow, String(localized: "Cable trust signals:", bundle: _coreLocalizedBundle))
                    : ANSI.wrap(ANSI.bold + ANSI.gray, String(localized: "Cable note:", bundle: _coreLocalizedBundle))
                out += "\n" + header + "\n"
                for flag in trust.flags {
                    // Neutral notes read calmly (gray dot); warnings keep the
                    // yellow alarm marker.
                    let marker = flag.severity == .warning
                        ? ANSI.wrap(ANSI.yellow, "⚠")
                        : ANSI.wrap(ANSI.gray, "•")
                    out += "  " + marker + " " + ANSI.wrap(ANSI.bold, flag.title) + "\n"
                    out += "    " + ANSI.wrap(ANSI.dim, flag.detail) + "\n"
                }
            }
        }

        if showRaw {
            if let cable = identities.first(where: {
                $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
            }), let v2 = cable.activeCableVDO2 {
                out += "\n" + ANSI.wrap(ANSI.bold, String(localized: "Active cable (VDO 2):", bundle: _coreLocalizedBundle)) + "\n"
                out += rawRow("Physical connection", v2.physicalConnection.label)
                out += rawRow("Active element", v2.activeElement.label)
                out += rawRow("Optically isolated", yesNo(v2.opticallyIsolated))
                out += rawRow("USB lanes", v2.twoLanesSupported ? "Two" : "One")
                out += rawRow("USB Gen", v2.usbGen2OrHigher ? "Gen 2 or higher" : "Gen 1")
                out += rawRow("USB4 supported", yesNo(v2.usb4Supported))
                out += rawRow("USB 3.2 supported", yesNo(v2.usb32Supported))
                out += rawRow("USB 2.0 supported", yesNo(v2.usb2Supported))
                out += rawRow("USB 2.0 hub hops", String(v2.usb2HubHopsConsumed))
                out += rawRow("USB4 asymmetric", yesNo(v2.usb4AsymmetricMode))
                out += rawRow("U3 to U0 transition", v2.u3ToU0TransitionThroughU3S ? "Through U3S" : "Direct")
                out += rawRow("Idle power (U3/CLd)", v2.u3CLdPower.label)
                out += rawRow("Max operating temp", tempLabel(v2.maxOperatingTempC))
                out += rawRow("Shutdown temp", tempLabel(v2.shutdownTempC))
            }

            out += "\n" + ANSI.wrap(ANSI.bold, String(localized: "Raw IOKit properties:", bundle: _coreLocalizedBundle)) + "\n"
            for key in port.rawProperties.keys.sorted() {
                let value = port.rawProperties[key] ?? ""
                out += "  " + ANSI.wrap(ANSI.gray, key) + " = \(value)\n"
            }
        }

        return out
    }

    private static func rawRow(_ key: String, _ value: String) -> String {
        "  " + ANSI.wrap(ANSI.gray, key) + " = \(value)\n"
    }

    private static func yesNo(_ v: Bool) -> String { v ? "Yes" : "No" }

    /// 0 in the temperature fields means "not specified" per the spec.
    private static func tempLabel(_ v: Int) -> String {
        v == 0 ? "—" : "\(v)°C"
    }

    private static func color(for status: PortSummary.Status) -> String {
        switch status {
        case .empty: return ANSI.gray
        case .charging: return ANSI.yellow
        case .batteryFull: return ANSI.green
        case .dataDevice: return ANSI.blue
        case .thunderboltCable: return ANSI.magenta
        case .displayCable: return ANSI.cyan
        case .unknown: return ANSI.yellow
        }
    }

    private static func filterSources(_ port: AppleHPMInterface, all: [PowerSource]) -> [PowerSource] {
        guard let key = port.portKey else { return [] }
        return all.filter { $0.portKey == key }
    }

    private static func filterIdentities(_ port: AppleHPMInterface, all: [USBPDSOP]) -> [USBPDSOP] {
        guard let key = port.portKey else { return [] }
        return all.filter { $0.portKey == key }
    }
}
