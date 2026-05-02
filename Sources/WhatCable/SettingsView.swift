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
                .font(.title2)
            Text("Settings").font(.headline)
            Spacer()
            Button("Done", action: dismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

struct SettingsForm: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Display") {
                Toggle("Show technical details", isOn: $settings.showTechnicalDetails)
                Toggle("Hide empty ports", isOn: $settings.hideEmptyPorts)
            }
            section("Behavior") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show in menu bar", isOn: $settings.useMenuBarMode)
                Text(settings.useMenuBarMode
                     ? "Lives in the menu bar with no Dock icon."
                     : "Runs as a regular Dock app with a window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            section("Notifications") {
                Toggle("Notify on cable changes", isOn: $settings.notifyOnChanges)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }
}
