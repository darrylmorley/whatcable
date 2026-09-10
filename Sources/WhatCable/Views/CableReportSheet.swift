import SwiftUI
import AppKit
import WhatCableCore
import WhatCableAppKit
import WhatCableDarwinBackend

/// Confirmation sheet shown before sending the user to GitHub to file a
/// cable report. Lets them preview the exact payload that will be embedded
/// in the issue body, and toggle whether their Mac model and macOS version
/// are included.
struct CableReportSheet: View {
    let cableIdentity: USBPDSOP
    let cioCapability: CIOCableCapability?
    /// The port this cable is plugged into, so the report can carry the port
    /// controller's own reading of the cable. See `CableClassification`.
    let port: AppleHPMInterface?
    let dismiss: () -> Void
    @Environment(\.fontScale) private var fontScale

    @State private var includeSystemInfo: Bool = false

    /// Internal rather than private: the app test target reads it to pin the
    /// port wiring, which a SwiftUI body cannot be asserted on.
    var payload: CableReport.Payload? {
        // Only fetch the Mac model when the toggle is on, matching the old
        // behavior where the sysctl call inside SystemInfo.current() only
        // ran if includeSystemInfo was true.
        let macModel = includeSystemInfo ? DarwinSystemInfo.fetchMacModel() : "unknown"
        return CableReport.payload(
            for: cableIdentity,
            includeSystemInfo: includeSystemInfo,
            macModel: macModel,
            cioCapability: cioCapability,
            port: port
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.bubble")
                    .scaledFont(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Report this cable", bundle: _appLocalizedBundle)).scaledFont(.title3, weight: .bold)
                    Text(String(localized: "Opens a pre-filled GitHub issue in your browser. Nothing is sent until you submit there.", bundle: _appLocalizedBundle))
                        .scaledFont(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(localized: "Preview of what will be included:", bundle: _appLocalizedBundle))
                .scaledFont(.caption).foregroundStyle(.secondary)

            if let payload {
                ScrollView {
                    Text(payload.markdown)
                        .scaledFont(.caption, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 240)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            Toggle(isOn: $includeSystemInfo) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Include Mac model and macOS version", bundle: _appLocalizedBundle))
                    Text(String(localized: "Helps the maintainer reproduce charger / cable behavior tied to specific hardware.", bundle: _appLocalizedBundle))
                        .scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Divider()

            HStack {
                Link(String(localized: "What gets shared?", bundle: _appLocalizedBundle), destination: URL(string: "https://github.com/darrylmorley/whatcable#privacy")!)
                    .scaledFont(.caption)
                Spacer()
                Button(String(localized: "Cancel", bundle: _appLocalizedBundle), action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Open in GitHub", bundle: _appLocalizedBundle)) {
                    if let url = payload?.githubURL {
                        NSWorkspace.shared.open(url)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(payload == nil)
            }
        }
        .padding(20)
        .frame(width: 560 * fontScale)
    }
}

