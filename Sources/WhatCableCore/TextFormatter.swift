import Foundation

public enum TextFormatter {
    public static func render(
        ports: [USBCPort],
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo? = nil,
        thunderboltSwitches: [ThunderboltSwitch] = []
    ) -> String {
        if ports.isEmpty {
            return "No USB-C / MagSafe ports were found on this Mac.\n"
        }

        var out = ""
        for (i, port) in ports.enumerated() {
            if i > 0 { out += "\n" }
            out += renderPort(
                port,
                sources: filterSources(port, all: sources),
                identities: filterIdentities(port, all: identities),
                showRaw: showRaw,
                adapter: adapter,
                thunderboltSwitches: thunderboltSwitches
            )
        }
        return out
    }

    private static func renderPort(
        _ port: USBCPort,
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo?,
        thunderboltSwitches: [ThunderboltSwitch]
    ) -> String {
        let summary = PortSummary(
            port: port,
            sources: sources,
            identities: identities,
            thunderboltSwitches: thunderboltSwitches
        )
        let label = port.portDescription ?? port.serviceName
        let typeSuffix = port.portTypeDescription.map { " (\($0))" } ?? ""

        let header = "=== \(label)\(typeSuffix) ==="
        var out = ANSI.wrap(ANSI.bold + ANSI.cyan, header) + "\n"

        let headlineColor = color(for: summary.status)
        out += ANSI.wrap(ANSI.bold + headlineColor, summary.headline) + "\n"
        out += ANSI.wrap(ANSI.dim, summary.subtitle) + "\n"

        if !summary.bullets.isEmpty {
            out += "\n"
            for bullet in summary.bullets {
                out += "  " + ANSI.wrap(ANSI.gray, "•") + " \(bullet)\n"
            }
        }

        if let diag = ChargingDiagnostic(port: port, sources: sources, identities: identities, adapter: adapter) {
            let diagColor = diag.isWarning ? ANSI.yellow : ANSI.green
            out += "\n" + ANSI.wrap(ANSI.bold, "Charging: ") + ANSI.wrap(diagColor, diag.summary) + "\n"
            out += "  " + ANSI.wrap(ANSI.dim, diag.detail) + "\n"
        }

        // Cable trust signals: hedged flags raised against the e-marker.
        // Match the popover's behaviour: only render when at least one flag
        // fires, and use the same titles + details so wording stays
        // consistent across surfaces.
        if let cable = identities.first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }) {
            let trust = CableTrustReport(identity: cable)
            if !trust.isEmpty {
                out += "\n" + ANSI.wrap(ANSI.bold + ANSI.yellow, "Cable trust signals:") + "\n"
                for flag in trust.flags {
                    out += "  " + ANSI.wrap(ANSI.yellow, "⚠") + " " + ANSI.wrap(ANSI.bold, flag.title) + "\n"
                    out += "    " + ANSI.wrap(ANSI.dim, flag.detail) + "\n"
                }
            }
        }

        if showRaw {
            // Active Cable VDO 2 deep view: every decoded field. Surfaced
            // here (not in the bullet list) because most users don't care
            // about idle power or thermal limits, but engineers diagnosing
            // a cable do.
            if let cable = identities.first(where: {
                $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
            }), let v2 = cable.activeCableVDO2 {
                out += "\n" + ANSI.wrap(ANSI.bold, "Active cable (VDO 2):") + "\n"
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

            out += "\n" + ANSI.wrap(ANSI.bold, "Raw IOKit properties:") + "\n"
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
        case .dataDevice: return ANSI.blue
        case .thunderboltCable: return ANSI.magenta
        case .displayCable: return ANSI.cyan
        case .unknown: return ANSI.yellow
        }
    }

    private static func filterSources(_ port: USBCPort, all: [PowerSource]) -> [PowerSource] {
        guard let key = port.portKey else { return [] }
        return all.filter { $0.portKey == key }
    }

    private static func filterIdentities(_ port: USBCPort, all: [PDIdentity]) -> [PDIdentity] {
        guard let key = port.portKey else { return [] }
        return all.filter { $0.portKey == key }
    }
}
