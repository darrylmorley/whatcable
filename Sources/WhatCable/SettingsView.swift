import SwiftUI
import WhatCableCore

/// Settings panel shown in place of the main popover content. Pushes a
/// "Done" header and groups toggles by purpose. All preferences live on
/// `AppSettings` and are persisted to UserDefaults.
struct SettingsView: View {
    var dismiss: (() -> Void)? = nil

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            if let dismiss {
                header(dismiss: dismiss)
                Divider()
            }
            ScrollView {
                SettingsForm()
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func header(dismiss: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "gearshape")
                .scaledFont(.title2)
            Text(appString("Settings")).scaledFont(.headline, weight: .bold)
            Spacer()
            Button(appString("Done"), action: dismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

struct SettingsForm: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(appString("Behavior")) {
                Toggle(appString("Launch at login"), isOn: $settings.launchAtLogin)
                Toggle(appString("Show in menu bar"), isOn: $settings.useMenuBarMode)
                Text(settings.useMenuBarMode
                     ? appString("Lives in the menu bar with no Dock icon.")
                     : appString("Runs as a regular Dock app with a window."))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
            section(appString("Display")) {
                Picker(appString("Language"), selection: $settings.language) {
                    ForEach(WhatCableLanguage.allCases) { language in
                        Text(languageName(language)).tag(language)
                    }
                }
                .pickerStyle(.menu)
                Toggle(appString("Show technical details"), isOn: $settings.showTechnicalDetails)
                Toggle(appString("Hide empty ports"), isOn: $settings.hideEmptyPorts)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(appString("Font size"))
                        Spacer()
                        Text(verbatim: "\(Int((settings.fontSize * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.fontSize, in: AppSettings.fontSizeRange, step: 0.1)
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            section(appString("Notifications")) {
                Toggle(appString("Notify on cable changes"), isOn: $settings.notifyOnChanges)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .scaledFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .scaledFont(.body)
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private func languageName(_ language: WhatCableLanguage) -> String {
        switch language {
        case .english:
            return appString("English")
        case .simplifiedChinese:
            return appString("Simplified Chinese")
        }
    }
}
