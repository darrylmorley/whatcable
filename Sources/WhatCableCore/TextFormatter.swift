import Foundation

public enum TextFormatter {
    public static func render(
        ports: [USBCPort],
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo? = nil
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
                adapter: adapter
            )
        }
        return out
    }

    private static func renderPort(
        _ port: USBCPort,
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo?
    ) -> String {
        let summary = PortSummary(port: port, sources: sources, identities: identities)
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

        if showRaw {
            out += "\n" + ANSI.wrap(ANSI.bold, "Raw IOKit properties:") + "\n"
            for key in port.rawProperties.keys.sorted() {
                let value = port.rawProperties[key] ?? ""
                out += "  " + ANSI.wrap(ANSI.gray, key) + " = \(value)\n"
            }
        }

        return out
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
