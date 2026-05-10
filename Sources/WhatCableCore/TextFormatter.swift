import Foundation

public enum TextFormatter {
    public static func render(
        ports: [USBCPort],
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo? = nil,
        thunderboltSwitches: [ThunderboltSwitch] = [],
        language: WhatCableLanguage = .default
    ) -> String {
        func tr(_ key: String.LocalizationValue) -> String {
            LocalizedCopy.string(key, language: language)
        }

        if ports.isEmpty {
            return tr("No USB-C / MagSafe ports were found on this Mac.") + "\n"
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
                thunderboltSwitches: thunderboltSwitches,
                language: language
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
        thunderboltSwitches: [ThunderboltSwitch],
        language: WhatCableLanguage
    ) -> String {
        func tr(_ key: String.LocalizationValue) -> String {
            LocalizedCopy.string(key, language: language)
        }

        let summary = PortSummary(
            port: port,
            sources: sources,
            identities: identities,
            thunderboltSwitches: thunderboltSwitches,
            language: language
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

        if let diag = ChargingDiagnostic(port: port, sources: sources, identities: identities, adapter: adapter, language: language) {
            let diagColor = diag.isWarning ? ANSI.yellow : ANSI.green
            out += "\n" + ANSI.wrap(ANSI.bold, tr("Charging: ")) + ANSI.wrap(diagColor, diag.summary) + "\n"
            out += "  " + ANSI.wrap(ANSI.dim, diag.detail) + "\n"
        }

        // Cable trust signals: hedged flags raised against the e-marker.
        // Match the popover's behaviour: only render when at least one flag
        // fires, and use the same titles + details so wording stays
        // consistent across surfaces.
        if let cable = identities.first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }) {
            let trust = CableTrustReport(identity: cable)
            if !trust.isEmpty {
                out += "\n" + ANSI.wrap(ANSI.bold + ANSI.yellow, tr("Cable trust signals:")) + "\n"
                for flag in trust.flags {
                    out += "  " + ANSI.wrap(ANSI.yellow, "⚠") + " " + ANSI.wrap(ANSI.bold, flag.title(language: language)) + "\n"
                    out += "    " + ANSI.wrap(ANSI.dim, flag.detail(language: language)) + "\n"
                }
            }
        }

        if showRaw {
            if let cable = identities.first(where: {
                $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
            }), let v2 = cable.activeCableVDO2 {
                out += "\n" + ANSI.wrap(ANSI.bold, tr("Active cable (VDO 2):")) + "\n"
                out += rawRow(tr("Physical connection"), v2.physicalConnection.label(language: language))
                out += rawRow(tr("Active element"), v2.activeElement.label(language: language))
                out += rawRow(tr("Optically isolated"), yesNo(v2.opticallyIsolated, language: language))
                out += rawRow(tr("USB lanes"), v2.twoLanesSupported ? tr("Two") : tr("One"))
                out += rawRow(tr("USB Gen"), v2.usbGen2OrHigher ? tr("Gen 2 or higher") : tr("Gen 1"))
                out += rawRow(tr("USB4 supported"), yesNo(v2.usb4Supported, language: language))
                out += rawRow(tr("USB 3.2 supported"), yesNo(v2.usb32Supported, language: language))
                out += rawRow(tr("USB 2.0 supported"), yesNo(v2.usb2Supported, language: language))
                out += rawRow(tr("USB 2.0 hub hops"), String(v2.usb2HubHopsConsumed))
                out += rawRow(tr("USB4 asymmetric"), yesNo(v2.usb4AsymmetricMode, language: language))
                out += rawRow(tr("U3 to U0 transition"), v2.u3ToU0TransitionThroughU3S ? tr("Through U3S") : tr("Direct"))
                out += rawRow(tr("Idle power (U3/CLd)"), v2.u3CLdPower.label(language: language))
                out += rawRow(tr("Max operating temp"), tempLabel(v2.maxOperatingTempC))
                out += rawRow(tr("Shutdown temp"), tempLabel(v2.shutdownTempC))
            }

            out += "\n" + ANSI.wrap(ANSI.bold, tr("Raw IOKit properties:")) + "\n"
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

    private static func yesNo(_ v: Bool, language: WhatCableLanguage = .default) -> String {
        v ? LocalizedCopy.string("Yes", language: language) : LocalizedCopy.string("No", language: language)
    }

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
