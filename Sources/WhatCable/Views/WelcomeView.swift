import SwiftUI
import WhatCableAppKit

struct WelcomeView: View {
    @State private var useMenuBar: Bool
    var onSelectionChanged: ((Bool) -> Void)?
    var onComplete: (Bool) -> Void

    /// `useMenuBarInitially` seeds the selection from the stored preference
    /// rather than hardcoding menu bar. Issue #571 made the welcome screen
    /// reachable for users who already have a display mode (a CLI launch writes
    /// one, and legacy users who never onboarded have one), and opening on the
    /// wrong card would overwrite their choice the moment they clicked through.
    init(
        useMenuBarInitially: Bool,
        onSelectionChanged: ((Bool) -> Void)? = nil,
        onComplete: @escaping (Bool) -> Void
    ) {
        _useMenuBar = State(initialValue: useMenuBarInitially)
        self.onSelectionChanged = onSelectionChanged
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text(String(localized: "Welcome to WhatCable", bundle: _appLocalizedBundle))
                .scaledFont(.title, weight: .bold)

            Text(String(localized: "See what your USB-C cables, chargers, and devices can actually do.", bundle: _appLocalizedBundle))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "How would you like to use WhatCable?", bundle: _appLocalizedBundle))
                    .scaledFont(.headline)

                modeOption(
                    icon: "menubar.rectangle",
                    title: String(localized: "Menu bar", bundle: _appLocalizedBundle),
                    description: String(localized: "Sits in the menu bar at the top of your screen. Click the cable icon any time to check a connection.", bundle: _appLocalizedBundle),
                    badge: String(localized: "Recommended", bundle: _appLocalizedBundle),
                    isSelected: useMenuBar
                ) { useMenuBar = true; onSelectionChanged?(true) }

                modeOption(
                    icon: "macwindow",
                    title: String(localized: "Dock app", bundle: _appLocalizedBundle),
                    description: String(localized: "Opens as a regular window with a Dock icon, like most apps.", bundle: _appLocalizedBundle),
                    badge: nil,
                    isSelected: !useMenuBar
                ) { useMenuBar = false; onSelectionChanged?(false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(localized: "You can change this any time in Settings.", bundle: _appLocalizedBundle))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)

            Button(String(localized: "Get Started", bundle: _appLocalizedBundle)) {
                onComplete(useMenuBar)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(32)
        .frame(width: 420, height: 480)
    }

    @ViewBuilder
    private func modeOption(
        icon: String,
        title: String,
        description: String,
        badge: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .scaledFont(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                        Text(title).fontWeight(.medium)
                        if let badge {
                            Text(badge)
                                .scaledFont(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    Text(description)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
