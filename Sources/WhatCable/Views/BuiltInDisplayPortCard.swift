import SwiftUI
import WhatCableCore

/// Slim port card for a native video output socket (today: the built-in HDMI
/// 2.1 port on Apple Silicon MacBook Pros, Mac mini Pro, and Mac Studio).
///
/// USB-C / MagSafe ports get the full `PortCard`: power, transports, e-marker,
/// trust signals, billboard, Thunderbolt fabric, USB device tree. A native
/// HDMI port has none of those: no port-controller silicon, no PD contract, no
/// USB tunnel, no e-marker, no Thunderbolt. So this card shows only what the
/// HDMI port actually carries: the live display verdict per attached monitor.
///
/// Visible only when at least one display is plugged in (the IOKit DisplayPort
/// transport node has no idle representation). Issue #352.
struct BuiltInDisplayPortCard: View {
    let port: BuiltInDisplayPort

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "display")
                    .scaledFont(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: port.serviceName)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(headline)
                        .scaledFont(.title3, weight: .bold)
                    Text(subtitle)
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            // One banner per attached display. A future MST split through the
            // built-in HDMI port would produce more than one entry; today this
            // is almost always a single banner.
            ForEach(Array(port.displays.enumerated()), id: \.offset) { _, displayPort in
                if let diagnostic = DisplayDiagnostic(dp: displayPort, cable: nil) {
                    DisplayBanner(diagnostic: diagnostic)
                        .padding(.leading, 48)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var headline: String {
        // `BuiltInDisplayPort.group` filters inactive DP nodes, so the
        // entity is constructed only when at least one display is attached.
        // The single-display branch handles the universally common case;
        // the count branch covers a hypothetical MST split through one
        // HDMI socket.
        if port.displays.count == 1 {
            return String(localized: "Display connected", bundle: _coreLocalizedBundle)
        }
        return String(localized: "\(port.displays.count) displays connected", bundle: _coreLocalizedBundle)
    }

    private var subtitle: String {
        String(localized: "Built-in \(port.portType) port \(port.portNumber)", bundle: _coreLocalizedBundle)
    }
}
