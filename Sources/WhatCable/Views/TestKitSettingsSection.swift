import SwiftUI
import WhatCableAppKit
import WhatCableCore

struct TestKitSettingsSection: View {
    @EnvironmentObject private var refreshSignal: RefreshSignal
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var runner = TestKitRunner.shared
    @State private var showingConsent = false

    var body: some View {
        // Rows only. The section header is supplied by the enclosing Form
        // section in SettingsView so it matches the other settings groups.
        HStack(spacing: 8) {
            Button(action: { showingConsent = true }) {
                Label(String(localized: "Contribute Diagnostic Data", bundle: _coreLocalizedBundle), systemImage: "waveform.path.ecg")
            }
            .disabled(runner.isRunning)
            .buttonStyle(.bordered)
            .controlSize(.small)

            statusLabel

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showingConsent) {
            // Wrapped so the sheet's own window picks up the opacity slider too
            // (sheets are separate child windows, not covered by the parent's
            // ScaledHost).
            ScaledHost {
                TestKitConsentView {
                    showingConsent = false
                    runner.run()
                } onCancel: {
                    showingConsent = false
                }
            }
        }
        .onReceive(refreshSignal.$showTestKitConsent) { show in
            if show {
                showingConsent = true
                refreshSignal.showTestKitConsent = false
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch runner.state {
        case .idle:
            if let lastVersion = settings.testKitLastRunVersion {
                Text(String(localized: "Last run: v\(lastVersion)", bundle: _coreLocalizedBundle))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        case .running(let probe, let current, let total):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(verbatim: "\(current)/\(total): \(probe)")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done(let passed, let failed, let noOutput, let noOutputProbes):
            // Matches the CLI's completion line style ("N submitted, N failed,
            // N no output"). See testKitDoneLabel(...) below for the wording
            // and the localisation note (this label has no translation
            // entries in any Localizable.strings yet; that predates this
            // change).
            let label = Self.testKitDoneLabel(passed: passed, failed: failed, noOutput: noOutput)

            if noOutputProbes.isEmpty {
                Text(label)
                    .scaledFont(.caption)
                    .foregroundStyle(failed > 0 ? .orange : .green)
            } else {
                // Subtle: same caption styling, just an extra hover tooltip
                // naming which probes produced nothing, no separate line.
                Text(label)
                    .scaledFont(.caption)
                    .foregroundStyle(.orange)
                    .help(String(localized: "No output: \(noOutputProbes.joined(separator: ", "))", bundle: _coreLocalizedBundle))
            }
        case .error(let message):
            Text(message)
                .scaledFont(.caption)
                .foregroundStyle(.red)
        }
    }

    /// Whole-phrase label per passed/failed/noOutput combination, matching
    /// the CLI's completion line style. Each combination is its own full
    /// localizable string (not fragments concatenated with a hardcoded
    /// separator) so a translator gets natural phrasing rather than joined
    /// clauses. Plain function, not a `@ViewBuilder` body: an if/else chain
    /// that only produces a `String` (no `View` in any branch) doesn't
    /// compile inside a `@ViewBuilder` context, since the builder tries to
    /// treat every branch as view content.
    ///
    /// NOTE: as with the prior "passed, failed" / "probes submitted" strings
    /// this replaces, none of these phrases have translation entries in any
    /// Localizable.strings yet (verified: zero hits for "passed"/"submitted"/
    /// "no output" across all 13 en.lproj and other .lproj folders), so today
    /// every locale falls back to the English text via `String(localized:)`'s
    /// default-value behaviour. That's a pre-existing gap this change doesn't
    /// introduce or fix; the new label is kept consistent with what the old
    /// one already did.
    private static func testKitDoneLabel(passed: Int, failed: Int, noOutput: Int) -> String {
        if failed > 0 && noOutput > 0 {
            return String(localized: "\(passed) submitted, \(failed) failed, \(noOutput) no output", bundle: _coreLocalizedBundle)
        } else if failed > 0 {
            return String(localized: "\(passed) submitted, \(failed) failed", bundle: _coreLocalizedBundle)
        } else if noOutput > 0 {
            return String(localized: "\(passed) submitted, \(noOutput) no output", bundle: _coreLocalizedBundle)
        } else {
            return String(localized: "\(passed) probes submitted", bundle: _coreLocalizedBundle)
        }
    }
}

struct TestKitConsentView: View {
    var onProceed: () -> Void
    var onCancel: () -> Void
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "Contribute Diagnostic Data", bundle: _coreLocalizedBundle), systemImage: "waveform.path.ecg")
                .scaledFont(.headline, weight: .bold)

            VStack(alignment: .leading, spacing: 12) {
                infoRow(
                    icon: "cpu",
                    title: String(localized: "What happens", bundle: _coreLocalizedBundle),
                    detail: String(localized: "WhatCable runs \(TestKitRunner.probeNames.count) IOKit probes that read hardware data your Mac already publishes. The results are sent to a secure server to help improve cable and port detection.", bundle: _coreLocalizedBundle)
                )

                infoRow(
                    icon: "cable.connector",
                    title: String(localized: "Before you start", bundle: _coreLocalizedBundle),
                    detail: String(localized: "Plug in the cables and devices you want included, then leave everything connected until it finishes. Plugging or unplugging during the run can leave gaps in the results.", bundle: _coreLocalizedBundle)
                )

                infoRow(
                    icon: "list.clipboard",
                    title: String(localized: "What is collected", bundle: _coreLocalizedBundle),
                    detail: String(localized: "Raw IOKit registry properties, a list of the driver classes present on your Mac, plus your macOS version, chip type and Mac model identifier (for example, Mac14,3). This is data macOS already exposes on your Mac.", bundle: _coreLocalizedBundle)
                )

                infoRow(
                    icon: "lock.shield",
                    title: String(localized: "Privacy", bundle: _coreLocalizedBundle),
                    detail: String(localized: "Your machine's hardware UUID is hashed with SHA-256 before sending. No names, accounts, your Mac's serial number, or personal data are collected or stored.", bundle: _coreLocalizedBundle)
                )
            }

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: _coreLocalizedBundle), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Proceed", bundle: _coreLocalizedBundle), action: onProceed)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .scaledFont(.body)
        .padding(20)
        .frame(width: 420 * fontScale)
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(.body, weight: .semibold)
                Text(detail)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
