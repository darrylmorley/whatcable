import SwiftUI
import WhatCableAppKit

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
            Text(String(localized: "Settings", bundle: _appLocalizedBundle)).scaledFont(.headline, weight: .bold)
            Spacer()
            Button(String(localized: "Done", bundle: _appLocalizedBundle), action: dismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

struct SettingsForm: View {
    @ObservedObject private var settings = AppSettings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(String(localized: "Behavior", bundle: _appLocalizedBundle)) {
                Toggle(String(localized: "Launch at login", bundle: _appLocalizedBundle), isOn: $settings.launchAtLogin)
                Toggle(String(localized: "Show in menu bar", bundle: _appLocalizedBundle), isOn: $settings.useMenuBarMode)
                Text(settings.useMenuBarMode
                     ? String(localized: "Lives in the menu bar with no Dock icon.", bundle: _appLocalizedBundle)
                     : String(localized: "Runs as a regular Dock app with a window.", bundle: _appLocalizedBundle))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
            section(String(localized: "Display", bundle: _appLocalizedBundle)) {
                Toggle(String(localized: "Show technical details", bundle: _appLocalizedBundle), isOn: $settings.showTechnicalDetails)
                Toggle(String(localized: "Hide empty ports", bundle: _appLocalizedBundle), isOn: $settings.hideEmptyPorts)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(localized: "Font size", bundle: _appLocalizedBundle))
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
                Picker(String(localized: "Language", bundle: _appLocalizedBundle), selection: $settings.preferredLanguage) {
                    Text(String(localized: "System Default", bundle: _appLocalizedBundle)).tag("")
                    Divider()
                    Text(verbatim: "Deutsch").tag("de")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Español").tag("es")
                    Text(verbatim: "Français").tag("fr")
                    Text(verbatim: "Italiano").tag("it")
                    Text(verbatim: "Norsk Bokmål").tag("nb")
                    Text(verbatim: "Polski").tag("pl")
                    Text(verbatim: "हिन्दी").tag("hi")
                    Text(verbatim: "日本語").tag("ja")
                    Text(verbatim: "中文 (简体)").tag("zh-Hans")
                    Text(verbatim: "中文 (繁體)").tag("zh-Hant")
                    Text(verbatim: "Հայերեն").tag("hy")
                }
                .pickerStyle(.menu)
                .padding(.top, 4)
            }
            section(String(localized: "Notifications", bundle: _appLocalizedBundle)) {
                Toggle(String(localized: "Notify on cable changes", bundle: _appLocalizedBundle), isOn: $settings.notifyOnChanges)
            }
            TestKitSettingsSection()
            section(String(localized: "Pro", bundle: _appLocalizedBundle)) {
                let builders = PluginRegistry.shared.settingsProSectionBuilders
                if builders.isEmpty {
                    Link(String(localized: "Upgrade to WhatCable Pro", bundle: _appLocalizedBundle),
                         destination: URL(string: "https://www.whatcable.uk/pro")!)
                } else {
                    ForEach(builders.indices, id: \.self) { i in
                        builders[i]()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .scaledFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .scaledFont(.body)
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }
}
