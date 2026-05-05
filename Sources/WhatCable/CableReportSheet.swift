#if os(macOS)
import SwiftUI
import AppKit
import WhatCableCore

/// Confirmation sheet shown before sending the user to GitHub to file a
/// cable report. Lets them preview the exact payload that will be embedded
/// in the issue body, and toggle whether their Mac model and macOS version
/// are included.
struct CableReportSheet: View {
    let cableIdentity: PDIdentity
    let dismiss: () -> Void

    @State private var includeSystemInfo: Bool = false

    private var payload: CableReport.Payload? {
        CableReport.payload(for: cableIdentity, includeSystemInfo: includeSystemInfo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report this cable").font(.title3).bold()
                    Text("Opens a pre-filled GitHub issue in your browser. Nothing is sent until you submit there.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Preview of what will be included:")
                .font(.caption).foregroundStyle(.secondary)

            if let payload {
                ScrollView {
                    Text(payload.markdown)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 240)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            Toggle(isOn: $includeSystemInfo) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include Mac model and macOS version")
                    Text("Helps the maintainer reproduce charger / cable behavior tied to specific hardware.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Divider()

            HStack {
                Link("What gets shared?", destination: URL(string: "https://github.com/darrylmorley/whatcable#privacy")!)
                    .font(.caption)
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Open in GitHub") {
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
        .frame(width: 560)
    }
}

#endif
