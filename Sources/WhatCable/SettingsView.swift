import SwiftUI

/// Settings panel shown in place of the main popover content. Pushes a
/// "Done" header and groups toggles by purpose. All preferences live on
/// `AppSettings` and are persisted to UserDefaults.
struct SettingsView: View {
    let dismiss: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Display") {
                        Toggle("Show technical details", isOn: $settings.showTechnicalDetails)
                        Toggle("Hide empty ports", isOn: $settings.hideEmptyPorts)
                    }
                    section("Behavior") {
                        Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    }
                    section("Notifications") {
                        Toggle("Notify on cable changes", isOn: $settings.notifyOnChanges)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
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
