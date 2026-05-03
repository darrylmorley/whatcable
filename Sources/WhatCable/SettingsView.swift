import SwiftUI

/// Settings panel shown in place of the main popover content. Pushes a
/// "Done" header and groups toggles by purpose. All preferences live on
/// `AppSettings` and are persisted to UserDefaults.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            SettingsForm()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 280)
    }
}

struct SettingsForm: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Display") {
                toggle("Show technical details", isOn: $settings.showTechnicalDetails)
                toggle("Hide empty ports", isOn: $settings.hideEmptyPorts)
            }
            section("Behavior") {
                toggle("Launch at login", isOn: $settings.launchAtLogin)
                toggle("Show in menu bar", isOn: $settings.useMenuBarMode)
                Text(settings.useMenuBarMode
                     ? "Lives in the menu bar with no Dock icon."
                     : "Runs as a regular Dock app with a window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            section("Notifications") {
                toggle("Notify on cable changes", isOn: $settings.notifyOnChanges)
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .frame(width: 150, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
            Spacer()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2).bold()
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }
}
