import SwiftUI

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
            Text(String(localized: "Settings", bundle: .module)).scaledFont(.headline, weight: .bold)
            Spacer()
            Button(String(localized: "Done", bundle: .module), action: dismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

struct SettingsForm: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(String(localized: "Behavior", bundle: .module)) {
                Toggle(String(localized: "Launch at login", bundle: .module), isOn: $settings.launchAtLogin)
                Toggle(String(localized: "Show in menu bar", bundle: .module), isOn: $settings.useMenuBarMode)
                Text(settings.useMenuBarMode
                     ? String(localized: "Lives in the menu bar with no Dock icon.", bundle: .module)
                     : String(localized: "Runs as a regular Dock app with a window.", bundle: .module))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
            section(String(localized: "Display", bundle: .module)) {
                Toggle(String(localized: "Show technical details", bundle: .module), isOn: $settings.showTechnicalDetails)
                Toggle(String(localized: "Hide empty ports", bundle: .module), isOn: $settings.hideEmptyPorts)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(localized: "Font size", bundle: .module))
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
            section(String(localized: "Notifications", bundle: .module)) {
                Toggle(String(localized: "Notify on cable changes", bundle: .module), isOn: $settings.notifyOnChanges)
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
