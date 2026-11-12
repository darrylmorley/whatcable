import AppKit
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
            SettingsForm()
        }
        // The 640 cap is for the popover. In a resizable window it left
        // Settings shorter than the window, and centred, so its Done header
        // floated mid-window (issue #600).
        .frame(
            minWidth: 400,
            minHeight: 320,
            maxHeight: settings.useMenuBarMode ? 640 : .infinity,
            alignment: settings.useMenuBarMode ? .center : .top
        )
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
        Form {
            Section {
                Toggle(String(localized: "Launch at login", bundle: _appLocalizedBundle), isOn: $settings.launchAtLogin)
                Toggle(String(localized: "Show in menu bar", bundle: _appLocalizedBundle), isOn: $settings.useMenuBarMode)
            } header: {
                sectionHeader("Behavior")
            } footer: {
                Text(settings.useMenuBarMode
                     ? String(localized: "Lives in the menu bar with no Dock icon.", bundle: _appLocalizedBundle)
                     : String(localized: "Runs as a regular Dock app with a window.", bundle: _appLocalizedBundle))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Show technical details", bundle: _appLocalizedBundle), isOn: $settings.showTechnicalDetails)
                Toggle(String(localized: "Hide empty ports", bundle: _appLocalizedBundle), isOn: $settings.hideEmptyPorts)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(String(localized: "Skip deep USB probing", bundle: _appLocalizedBundle), isOn: $settings.skipDeepUSBProbing)
                    Text(String(localized: "Stops WhatCable reading capability info from USB devices. Turn on if a KVM switch or hub misbehaves (relay clicking, or keyboard and mouse dropping) when WhatCable runs.", bundle: _appLocalizedBundle))
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Font size", bundle: _appLocalizedBundle))
                            .scaledFont(.body)
                        Spacer()
                        Text(verbatim: "\(Int((settings.fontSize * 100).rounded()))%")
                            .scaledFont(.body, monospacedDigit: true)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller")
                            .scaledFont(.body)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.fontSize, in: AppSettings.fontSizeRange, step: 0.1)
                        Image(systemName: "textformat.size.larger")
                            .scaledFont(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Opacity", bundle: _appLocalizedBundle))
                            .scaledFont(.body)
                        Spacer()
                        Text(verbatim: "\(Int((settings.uiOpacity * 100).rounded()))%")
                            .scaledFont(.body, monospacedDigit: true)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dotted")
                            .scaledFont(.body)
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.uiOpacity, in: AppSettings.opacityRange, step: 0.05)
                        Image(systemName: "circle.fill")
                            .scaledFont(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.useMenuBarMode {
                    Toggle(String(localized: "Solid window background", bundle: _appLocalizedBundle), isOn: $settings.solidMenuBarBackground)
                }

                LabeledContent {
                    MenuBarIconPicker(selection: $settings.menuBarIcon)
                } label: {
                    Text(String(localized: "Menu bar icon", bundle: _appLocalizedBundle))
                }

                Toggle(String(localized: "Show charging watts in the menu bar", bundle: _appLocalizedBundle), isOn: $settings.showChargingWatts)

                if settings.showChargingWatts {
                    Picker(selection: $settings.menuBarWattsStyle) {
                        Text(String(localized: "Number", bundle: _appLocalizedBundle)).tag(MenuBarWattsStyle.number)
                        Text(String(localized: "Bar", bundle: _appLocalizedBundle)).tag(MenuBarWattsStyle.bar)
                    } label: {
                        Text(String(localized: "Watts display", bundle: _appLocalizedBundle))
                    }
                    .pickerStyle(.segmented)
                }

                Picker(selection: $settings.preferredLanguage) {
                    Text(String(localized: "System Default", bundle: _appLocalizedBundle)).tag("")
                    Divider()
                    ForEach(AppLanguages.available) { language in
                        Text(verbatim: language.name).tag(language.id)
                    }
                } label: {
                    Text(String(localized: "Language", bundle: _appLocalizedBundle))
                }
                .pickerStyle(.menu)
            } header: {
                sectionHeader("Appearance")
            }

            Section {
                Toggle(String(localized: "Notify on cable changes", bundle: _appLocalizedBundle), isOn: $settings.notifyOnChanges)
                Toggle(String(localized: "Notify on app updates", bundle: _appLocalizedBundle), isOn: $settings.notifyOnUpdates)
            } header: {
                sectionHeader("Notifications")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(String(localized: "Include beta versions", bundle: _appLocalizedBundle), isOn: $settings.receiveBetaUpdates)
                    Text(String(localized: "Pre-release builds, shipped a few days before a stable release. Expect rough edges.", bundle: _appLocalizedBundle))
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Turning this off stops future betas. It does not move you back off a beta you are already running. The next stable release will.", bundle: _appLocalizedBundle))
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                    if UpdateChecker.isHomebrewInstall {
                        Text(String(localized: "You installed WhatCable with Homebrew. Running brew upgrade may replace a beta with the current stable release.", bundle: _appLocalizedBundle))
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                sectionHeader("Updates")
            }

            Section {
                TestKitSettingsSection()
            } header: {
                sectionHeader("COMMUNITY")
            }

            Section {
                let builders = PluginRegistry.shared.settingsProSectionBuilders
                if builders.isEmpty {
                    Link(String(localized: "Upgrade to WhatCable Pro", bundle: _appLocalizedBundle),
                         destination: URL(string: "https://www.whatcable.uk/pro")!)
                } else {
                    ForEach(builders.indices, id: \.self) { i in
                        builders[i]()
                    }
                }
            } header: {
                sectionHeader("Pro")
            }
        }
        .formStyle(.grouped)
        .scaledFont(.body)
        .toggleStyle(.switch)
    }

    /// A section header in the small uppercase grey style, scaled with the
    /// font-size preference. `title` is an English key looked up in the app
    /// bundle, then uppercased (a no-op for non-Latin scripts).
    private func sectionHeader(_ title: String) -> some View {
        Text(String(localized: String.LocalizationValue(title), bundle: _appLocalizedBundle).uppercased())
            .scaledFont(.caption, weight: .semibold)
            .foregroundStyle(.secondary)
    }
}

/// A row of selectable glyph buttons for choosing the menu bar icon. Shows
/// the actual SF Symbols so the choice is visual, and hides any symbol that
/// isn't available on this macOS.
struct MenuBarIconPicker: View {
    @Binding var selection: String
    @Environment(\.fontScale) private var fontScale

    private var availableIcons: [String] {
        AppSettings.menuBarIconChoices.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
    }

    /// Friendly, localised name for an SF Symbol, used for the tooltip and
    /// VoiceOver. Falls back to the raw symbol name for any future addition.
    private func label(for symbolName: String) -> String {
        switch symbolName {
        case "cable.connector":
            return String(localized: "Cable", bundle: _appLocalizedBundle)
        case "cable.connector.horizontal":
            return String(localized: "Cable, horizontal", bundle: _appLocalizedBundle)
        case "bolt.fill":
            return String(localized: "Bolt", bundle: _appLocalizedBundle)
        case "powerplug.fill":
            return String(localized: "Power plug", bundle: _appLocalizedBundle)
        case "powercord.fill":
            return String(localized: "Power cord", bundle: _appLocalizedBundle)
        default:
            return symbolName
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(availableIcons, id: \.self) { name in
                Button {
                    selection = name
                } label: {
                    Image(systemName: name)
                        .scaledFont(.body)
                        .frame(width: 28 * fontScale, height: 24 * fontScale)
                        // Without this the button only responds where the glyph
                        // actually paints: `.plain` hit-tests the rendered
                        // content, and the box below is drawn as decoration, so
                        // the empty space inside it was dead. Makes the whole
                        // swatch the target, which is what it looks like.
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == name ? Color.accentColor.opacity(0.25) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selection == name ? Color.accentColor : Color.secondary.opacity(0.3),
                                        lineWidth: selection == name ? 1.5 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help(label(for: name))
                .accessibilityLabel(label(for: name))
                .accessibilityAddTraits(selection == name ? [.isSelected] : [])
            }
        }
    }
}
