import Foundation
import ServiceManagement
import os.log
import WhatCableCore

/// User-facing preferences, persisted in UserDefaults and (where relevant)
/// reflected into system services like SMAppService.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private nonisolated static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "settings")

    private enum Keys {
        static let notifyOnChanges = "notifyOnChanges"
        static let hideEmptyPorts = "hideEmptyPorts"
        static let useMenuBarMode = "useMenuBarMode"
        static let showTechnicalDetails = "showTechnicalDetails"
        static let fontSize = "fontSize"
        static let preferredLanguage = "preferredLanguage"
        static let testKitLastRunVersion = "testKitLastRunVersion"
        static let autoContributeDiagnosticData = "autoContributeDiagnosticData"
        static let testKitLastAutoRunDate = "testKitLastAutoRunDate"
        static let testKitAutoConsentGiven = "testKitAutoConsentGiven"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }


    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published var notifyOnChanges: Bool {
        didSet {
            guard notifyOnChanges != oldValue else { return }
            UserDefaults.standard.set(notifyOnChanges, forKey: Keys.notifyOnChanges)
            if notifyOnChanges {
                NotificationManager.shared.requestAuthorizationIfNeeded()
            }
        }
    }

    @Published var hideEmptyPorts: Bool {
        didSet {
            guard hideEmptyPorts != oldValue else { return }
            UserDefaults.standard.set(hideEmptyPorts, forKey: Keys.hideEmptyPorts)
        }
    }

    /// When true (default), WhatCable lives in the menu bar with no Dock
    /// icon. When false, it runs as a regular Dock app with a window.
    @Published var useMenuBarMode: Bool {
        didSet {
            guard useMenuBarMode != oldValue else { return }
            UserDefaults.standard.set(useMenuBarMode, forKey: Keys.useMenuBarMode)
        }
    }

    /// Persistent preference for the advanced IOKit detail view. A momentary
    /// reveal via ⌥-click on the menu bar icon is layered on top of this in
    /// `RefreshSignal.optionHeld`.
    @Published var showTechnicalDetails: Bool {
        didSet {
            guard showTechnicalDetails != oldValue else { return }
            UserDefaults.standard.set(showTechnicalDetails, forKey: Keys.showTechnicalDetails)
        }
    }

    /// BCP 47 language code to override the system language, or empty string
    /// for system default. Written to `AppleLanguages` so Foundation's bundle
    /// lookup picks it up on the next launch.
    @Published var preferredLanguage: String {
        didSet {
            guard preferredLanguage != oldValue else { return }
            UserDefaults.standard.set(preferredLanguage, forKey: Keys.preferredLanguage)
            setCoreLocale(preferredLanguage)
            setAppLocale(preferredLanguage)
        }
    }

    /// Font size multiplier for the main content. 1.0 is the default;
    /// the slider lets users pick 0.8 to 1.4.
    static let fontSizeRange: ClosedRange<Double> = 0.8...1.4

    @Published var fontSize: Double {
        didSet {
            let clamped = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
            if clamped != fontSize { fontSize = clamped; return }
            guard fontSize != oldValue else { return }
            UserDefaults.standard.set(fontSize, forKey: Keys.fontSize)
        }
    }


    @Published var autoContributeDiagnosticData: Bool {
        didSet {
            guard autoContributeDiagnosticData != oldValue else { return }
            UserDefaults.standard.set(autoContributeDiagnosticData, forKey: Keys.autoContributeDiagnosticData)
            TestKitRunner.shared.refreshAutoSendSchedule()
        }
    }

    var testKitLastRunVersion: String? {
        get { UserDefaults.standard.string(forKey: Keys.testKitLastRunVersion) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.testKitLastRunVersion) }
    }

    /// Timestamp of the last automatic diagnostic contribution.
    /// Used to catch up on a missed run after the app was closed and to space
    /// recurring runs apart.
    var testKitLastAutoRunDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.testKitLastAutoRunDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.testKitLastAutoRunDate) }
    }

    /// True once the user has accepted the consent sheet for automatic
    /// contribution at least once. The sheet is a one-time gate: after the
    /// first Proceed, toggling "Automatically Send Diagnostic Data" off and
    /// back on enables it directly without re-showing the consent.
    var testKitAutoConsentGiven: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.testKitAutoConsentGiven) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.testKitAutoConsentGiven) }
    }

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    /// True when the user has never explicitly chosen a display mode.
    /// Fresh installs see the welcome screen. Existing users who never
    /// toggled the setting in Settings also see it once on upgrade
    /// (pre-selecting their current mode), because the init assignment
    /// doesn't fire didSet and the key stays absent until toggled.
    var needsOnboarding: Bool {
        !hasCompletedOnboarding && UserDefaults.standard.object(forKey: Keys.useMenuBarMode) == nil
    }

    private init() {
        // Launch at Login is owned by the system; read its current state.
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        // Notifications default off — opt in to avoid noise.
        self.notifyOnChanges = UserDefaults.standard.bool(forKey: Keys.notifyOnChanges)
        self.hideEmptyPorts = UserDefaults.standard.bool(forKey: Keys.hideEmptyPorts)
        // Recurring contribution is opt-in.
        self.autoContributeDiagnosticData = UserDefaults.standard.bool(forKey: Keys.autoContributeDiagnosticData)
        // Menu bar mode is the default; UserDefaults returns false for unset
        // bool keys, so explicitly check presence.
        if UserDefaults.standard.object(forKey: Keys.useMenuBarMode) == nil {
            self.useMenuBarMode = true
        } else {
            self.useMenuBarMode = UserDefaults.standard.bool(forKey: Keys.useMenuBarMode)
        }
        self.showTechnicalDetails = UserDefaults.standard.bool(forKey: Keys.showTechnicalDetails)
        let savedLanguage = UserDefaults.standard.string(forKey: Keys.preferredLanguage) ?? ""
        self.preferredLanguage = savedLanguage
        setCoreLocale(savedLanguage)
        setAppLocale(savedLanguage)
        let stored = UserDefaults.standard.double(forKey: Keys.fontSize)
        let raw = stored > 0 ? stored : 1.0
        self.fontSize = min(max(raw, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.log.error("Failed to update launch at login: \(error.localizedDescription, privacy: .public)")
            // Roll the published value back so the UI matches reality.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let actual = SMAppService.mainApp.status == .enabled
                if self.launchAtLogin != actual {
                    self.launchAtLogin = actual
                }
            }
        }
    }
}

