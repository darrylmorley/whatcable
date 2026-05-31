import SwiftUI
import WhatCableAppKit

struct TestKitSettingsSection: View {
    @EnvironmentObject private var refreshSignal: RefreshSignal
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var runner = TestKitRunner.shared
    @State private var showingConsent = false
    @State private var pendingAutoEnable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "COMMUNITY", bundle: _appLocalizedBundle))
                .scaledFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: { pendingAutoEnable = false; showingConsent = true }) {
                        Label(String(localized: "Contribute Diagnostic Data", bundle: _appLocalizedBundle), systemImage: "waveform.path.ecg")
                    }
                    .disabled(runner.isRunning)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    statusLabel
                }

                Toggle(isOn: autoSendBinding) {
                    Text(String(localized: "Automatically Send Diagnostic Data", bundle: _appLocalizedBundle))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(autoSendHelp)
            }
            .scaledFont(.body)
            .controlSize(.small)
        }
        .sheet(isPresented: $showingConsent) {
            TestKitConsentView {
                showingConsent = false
                if pendingAutoEnable {
                    pendingAutoEnable = false
                    // Remember the consent so re-toggling never re-prompts.
                    settings.testKitAutoConsentGiven = true
                    settings.autoContributeDiagnosticData = true
                } else {
                    runner.run()
                }
            } onCancel: {
                showingConsent = false
                pendingAutoEnable = false
            }
        }
        .onReceive(refreshSignal.$showTestKitConsent) { show in
            if show {
                pendingAutoEnable = false
                showingConsent = true
                refreshSignal.showTestKitConsent = false
            }
        }
    }

    private var autoSendHelp: String {
        String(localized: "Automatically contributes diagnostic data every 48 hours.", bundle: _appLocalizedBundle)
    }

    // Saving user preferences
    private var autoSendBinding: Binding<Bool> {
        Binding(
            get: { settings.autoContributeDiagnosticData },
            set: { isOn in
                if isOn {
                    if settings.testKitAutoConsentGiven {
                        settings.autoContributeDiagnosticData = true
                    } else {
                        pendingAutoEnable = true
                        showingConsent = true
                    }
                } else {
                    settings.autoContributeDiagnosticData = false
                }
            }
        )
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch runner.state {
        case .idle:
            if let lastVersion = settings.testKitLastRunVersion {
                Text(String(localized: "Last run: v\(lastVersion)", bundle: _appLocalizedBundle))
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
        case .done(let passed, let failed):
            let label = failed > 0
                ? String(localized: "\(passed) passed, \(failed) failed", bundle: _appLocalizedBundle)
                : String(localized: "\(passed) probes submitted", bundle: _appLocalizedBundle)
            Text(label)
                .scaledFont(.caption)
                .foregroundStyle(failed > 0 ? .orange : .green)
        case .error(let message):
            Text(message)
                .scaledFont(.caption)
                .foregroundStyle(.red)
        }
    }
}

struct TestKitConsentView: View {
    var onProceed: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(String(localized: "Contribute Diagnostic Data", bundle: _appLocalizedBundle), systemImage: "waveform.path.ecg")
                .scaledFont(.headline, weight: .bold)

            VStack(alignment: .leading, spacing: 12) {
                infoRow(
                    icon: "cpu",
                    title: String(localized: "What happens", bundle: _appLocalizedBundle),
                    detail: String(localized: "WhatCable runs 14 IOKit probes that read raw USB-C and Thunderbolt data from your Mac's port controller registers. The results are sent to a secure server to help improve cable and port detection.", bundle: _appLocalizedBundle)
                )

                infoRow(
                    icon: "list.clipboard",
                    title: String(localized: "What is collected", bundle: _appLocalizedBundle),
                    detail: String(localized: "Raw IOKit registry properties for each USB-C port, the model and capabilities of any connected display (its EDID, with the serial number removed), your macOS version, and chip type. This is the same data visible in System Information.", bundle: _appLocalizedBundle)
                )

                infoRow(
                    icon: "lock.shield",
                    title: String(localized: "Privacy", bundle: _appLocalizedBundle),
                    detail: String(localized: "Your machine's hardware UUID is hashed with SHA-256 before sending. No names, accounts, serial numbers, or personal data are collected or stored.", bundle: _appLocalizedBundle)
                )
            }

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: _appLocalizedBundle), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Proceed", bundle: _appLocalizedBundle), action: onProceed)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .scaledFont(.body)
        .padding(20)
        .frame(width: 420)
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
