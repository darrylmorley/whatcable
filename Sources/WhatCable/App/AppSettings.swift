import Foundation
import ServiceManagement
import os.log
import WhatCableAppKit
import WhatCableCore
import WhatCableNotifications
import WhatCableDarwinBackend

/// How the menu bar shows charger power when `showChargingWatts` is on: the
/// numeric "NNW" readout, or a calmer fill bar that shows power as a fraction of
/// the charger's rating and barely moves (issue #366).
enum MenuBarWattsStyle: String, CaseIterable {
    case number
    case bar
}

/// User-facing preferences, persisted in UserDefaults and (where relevant)
/// reflected into system services like SMAppService.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private nonisolated static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "settings")

    private enum Keys {
        static let notifyOnChanges = "notifyOnChanges"
        static let notifyOnUpdates = "notifyOnUpdates"
        static let hideEmptyPorts = "hideEmptyPorts"
        static let useMenuBarMode = "useMenuBarMode"
        static let showTechnicalDetails = "showTechnicalDetails"
        static let fontSize = "fontSize"
        static let uiOpacity = "uiOpacity"
        static let menuBarIcon = "menuBarIcon"
        static let preferredLanguage = "preferredLanguage"
        static let testKitLastRunVersion = "testKitLastRunVersion"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let showChargingWatts = "showChargingWatts"
        static let menuBarWattsStyle = "menuBarWattsStyle"
        static let skipDeepUSBProbing = "skipDeepUSBProbing"
        static let receiveBetaUpdates = "receiveBetaUpdates"
    }


    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// How turning a notification toggle on requests OS permission. Injected
    /// (default is the real call) so a test can flip `notifyOnChanges` /
    /// `notifyOnUpdates` without touching `UNUserNotificationCenter`, which
    /// crashes when the running binary is not a signed app bundle (true of
    /// the `swift test` process, not of the shipped app).
    var requestNotificationAuthorization: () -> Void = { NotificationManager.shared.requestAuthorizationIfNeeded() }

    @Published var notifyOnChanges: Bool {
        didSet {
            guard notifyOnChanges != oldValue else { return }
            UserDefaults.standard.set(notifyOnChanges, forKey: Keys.notifyOnChanges)
            if notifyOnChanges {
                requestNotificationAuthorization()
            }
        }
    }

    /// Whether the "WhatCable X.Y available" update notification is posted.
    /// Independent of `notifyOnChanges` (issue #550): the two toggles used to
    /// be nested, so update notifications only fired when both were on. Each
    /// now stands alone. Defaults true (owner decision) so existing users who
    /// already got update notifications keep getting them regardless of their
    /// notifyOnChanges setting; turning it off silences only update alerts,
    /// leaving cable-change notifications and the in-window update notice
    /// untouched.
    @Published var notifyOnUpdates: Bool {
        didSet {
            guard notifyOnUpdates != oldValue else { return }
            UserDefaults.standard.set(notifyOnUpdates, forKey: Keys.notifyOnUpdates)
            if notifyOnUpdates {
                requestNotificationAuthorization()
            }
        }
    }

    /// Whether the in-app updater offers pre-release builds as well as
    /// stable ones. Defaults false: with it off, the updater keeps hitting
    /// `releases/latest`, which GitHub never returns a pre-release from, so
    /// an opted-out user cannot be shown a beta even by accident.
    ///
    /// Turning it on widens what is offered, it does not force a beta: the
    /// updater still picks whichever release is newest, so a stable always
    /// supersedes its own betas.
    @Published var receiveBetaUpdates: Bool {
        didSet {
            guard receiveBetaUpdates != oldValue else { return }
            UserDefaults.standard.set(receiveBetaUpdates, forKey: Keys.receiveBetaUpdates)
            // Opting out has to withdraw a beta that is already on offer, not
            // just stop the next one. Otherwise the banner still installs it.
            UpdateChecker.shared.discardPrereleaseOfferIfOptedOut()
        }
    }

    /// Whether this update must not be offered because it is a pre-release and
    /// the user is not opted into betas. One definition, used both when a
    /// check completes and when the toggle changes, so the two cannot drift.
    func suppressesPrerelease(_ update: AvailableUpdate) -> Bool {
        !receiveBetaUpdates && AppInfo.isPrerelease(update.version)
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

    /// Compatibility switch for USB probing, off by default. When off, and once
    /// the user has been through the welcome screen, WhatCable reads each USB
    /// device's capability descriptor so the Pro diagnostics can show alt modes.
    /// That read is a real USB control transfer, and a few KVM switches and hubs
    /// react badly to it (issue #429), so turning this switch on makes
    /// `USBWatcher` issue no USB traffic at all.
    ///
    /// This switch is only half the gate: on a first run nothing is read no
    /// matter how it is set, so that a machine the probe breaks still reaches a
    /// UI (issue #571). See `USBProbeGate`.
    @Published var skipDeepUSBProbing: Bool {
        didSet {
            guard skipDeepUSBProbing != oldValue else { return }
            UserDefaults.standard.set(skipDeepUSBProbing, forKey: Keys.skipDeepUSBProbing)
            applyUSBProbeGate()
        }
    }

    /// Push both gate inputs through the one decision.
    ///
    /// Called from both inputs' setters and from launch, so no caller has to
    /// remember: `skipDeepUSBProbing`'s didSet, `hasCompletedOnboarding`'s
    /// setter, and `continueNormalLaunch`. `AppSettings.init` cannot call it
    /// (self is not fully initialised there) and spells the same expression out.
    func applyUSBProbeGate() {
        USBWatcher.probeBillboardDescriptors = USBProbeGate.shouldProbe(
            hasCompletedOnboarding: hasCompletedOnboarding,
            skipDeepUSBProbing: skipDeepUSBProbing
        )
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
            setNotificationsLocale(preferredLanguage)
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
            // Mirror to the AppKit store so every SwiftUI surface (popover,
            // detached Pro windows, licence panel, welcome) tracks the slider
            // live, not just the popover.
            FontScaleStore.shared.fontScale = fontSize
        }
    }

    /// Window opacity for every surface. 1.0 is fully opaque (the default);
    /// the slider lets users pick down to 0.5. Floored at 0.5 so the content
    /// never becomes unreadable.
    static let opacityRange: ClosedRange<Double> = 0.5...1.0

    @Published var uiOpacity: Double {
        didSet {
            let clamped = min(max(uiOpacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
            if clamped != uiOpacity { uiOpacity = clamped; return }
            guard uiOpacity != oldValue else { return }
            UserDefaults.standard.set(uiOpacity, forKey: Keys.uiOpacity)
            // Mirror to the AppKit store so every surface (popover, detached
            // Pro windows, licence panel, welcome) tracks the slider live.
            OpacityStore.shared.opacity = uiOpacity
        }
    }

    /// SF Symbol name shown in the menu bar status item. The curated list
    /// keeps users to glyphs we know render; an unknown stored value (e.g.
    /// a symbol dropped in a future macOS) falls back to the default.
    static let defaultMenuBarIcon = "cable.connector"
    static let menuBarIconChoices: [String] = [
        "cable.connector",
        "cable.connector.horizontal",
        "bolt.fill",
        "powerplug.fill",
        "powercord.fill",
    ]

    /// Clamp a raw icon name to the curated list, falling back to the default
    /// so a stray value can't leave the menu bar with a blank icon. Shared by
    /// `init` and the `menuBarIcon` setter.
    static func validatedMenuBarIcon(_ raw: String) -> String {
        menuBarIconChoices.contains(raw) ? raw : defaultMenuBarIcon
    }

    /// When true, the menu bar status item shows the live charger input watts
    /// next to the icon (e.g. "50W") while the Mac is on external power.
    /// Hidden on battery, when watts read 0, and in window mode.
    @Published var showChargingWatts: Bool {
        didSet {
            guard showChargingWatts != oldValue else { return }
            UserDefaults.standard.set(showChargingWatts, forKey: Keys.showChargingWatts)
        }
    }

    /// Whether the watts readout shows a number or a fill bar. Only relevant when
    /// `showChargingWatts` is on. Defaults to the number (existing behaviour).
    @Published var menuBarWattsStyle: MenuBarWattsStyle {
        didSet {
            guard menuBarWattsStyle != oldValue else { return }
            UserDefaults.standard.set(menuBarWattsStyle.rawValue, forKey: Keys.menuBarWattsStyle)
        }
    }

    @Published var menuBarIcon: String {
        didSet {
            let validated = Self.validatedMenuBarIcon(menuBarIcon)
            if validated != menuBarIcon {
                menuBarIcon = validated
                return
            }
            guard menuBarIcon != oldValue else { return }
            UserDefaults.standard.set(menuBarIcon, forKey: Keys.menuBarIcon)
        }
    }

    var testKitLastRunVersion: String? {
        get { UserDefaults.standard.string(forKey: Keys.testKitLastRunVersion) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.testKitLastRunVersion) }
    }

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.hasCompletedOnboarding)
            // One of the two USB probe gate inputs (issue #571), so re-apply the
            // gate here rather than relying on every caller to remember.
            applyUSBProbeGate()
        }
    }

    /// True when the user has never been through the welcome screen.
    ///
    /// This used to also require the display-mode key to be absent. That had to
    /// go (issue #571): `whatcable --desktop` and `--popover` write that key, so
    /// a CLI-launched first run would never see the welcome screen, and since
    /// the USB probe gate now depends on onboarding completing, deep probing
    /// would be disabled forever on those machines. Accepted side effect: a
    /// legacy user who has a mode key but never completed onboarding sees the
    /// welcome screen once, pre-selecting their current mode.
    var needsOnboarding: Bool {
        !hasCompletedOnboarding
    }

    /// Whether a never-touched `receiveBetaUpdates` key should default to on,
    /// given the value already stored (nil if the key is absent) and the
    /// running build's version string.
    ///
    /// Discussion #555: two testers assumed a beta build would offer them
    /// betas automatically and missed a release because the toggle read off.
    /// A pre-release build IS the opt-in (manually installing one is a
    /// deliberate act), so a beta install now defaults the toggle on. An
    /// explicit choice, on or off, is never overridden: `storedValue` being
    /// non-nil short-circuits regardless of what it holds. Pure and
    /// UserDefaults-free so the five-row matrix can be tested without a
    /// suite-isolated defaults dance.
    nonisolated static func defaultsReceiveBetaUpdates(storedValue: Any?, runningVersion: String) -> Bool {
        storedValue == nil && AppInfo.isPrerelease(runningVersion)
    }

    private init() {
        // Launch at Login is owned by the system; read its current state.
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        // Notifications default off — opt in to avoid noise.
        self.notifyOnChanges = UserDefaults.standard.bool(forKey: Keys.notifyOnChanges)
        // Update notifications default on, independent of notifyOnChanges
        // (owner decision on issue #550): absent key reads as on for fresh
        // installs and upgraders alike. This is a deliberate reversal of an
        // earlier migration that inherited notifyOnChanges instead; the owner
        // decided update notifications should default on regardless of
        // whether cable-change notifications are on, even though that means
        // an upgrader who had deliberately left notifyOnChanges off starts
        // getting update notifications after upgrading. See postNotification
        // in UpdateChecker for how the resulting authorization gap (nothing
        // else requests permission before the first post) is closed.
        if UserDefaults.standard.object(forKey: Keys.notifyOnUpdates) == nil {
            self.notifyOnUpdates = true
        } else {
            self.notifyOnUpdates = UserDefaults.standard.bool(forKey: Keys.notifyOnUpdates)
        }
        // Betas are opt-in; an unset key reads false. Exception: a build
        // whose own version is a pre-release defaults the key to true, once,
        // the first time it ever launches (discussion #555, see
        // defaultsReceiveBetaUpdates above). A stored value, explicit true or
        // explicit false, is never touched.
        if AppSettings.defaultsReceiveBetaUpdates(
            storedValue: UserDefaults.standard.object(forKey: Keys.receiveBetaUpdates),
            runningVersion: AppInfo.version
        ) {
            UserDefaults.standard.set(true, forKey: Keys.receiveBetaUpdates)
        }
        self.receiveBetaUpdates = UserDefaults.standard.bool(forKey: Keys.receiveBetaUpdates)
        self.hideEmptyPorts = UserDefaults.standard.bool(forKey: Keys.hideEmptyPorts)
        // Menu bar mode is the default; UserDefaults returns false for unset
        // bool keys, so explicitly check presence.
        if UserDefaults.standard.object(forKey: Keys.useMenuBarMode) == nil {
            self.useMenuBarMode = true
        } else {
            self.useMenuBarMode = UserDefaults.standard.bool(forKey: Keys.useMenuBarMode)
        }
        self.showTechnicalDetails = UserDefaults.standard.bool(forKey: Keys.showTechnicalDetails)
        // Deep USB probing is on by default once onboarding is done; the absent
        // key reads as false (don't skip). Seed the watcher's static so the very
        // first enumeration honours both gate inputs, before the settings UI is
        // ever opened.
        let skipProbing = UserDefaults.standard.bool(forKey: Keys.skipDeepUSBProbing)
        self.skipDeepUSBProbing = skipProbing
        // Seed the watcher's static from both gate inputs: the saved preference,
        // and whether the app has ever loaded far enough to show its UI
        // (issue #571). Spelled out rather than calling applyUSBProbeGate(),
        // because self is not fully initialised here.
        USBWatcher.probeBillboardDescriptors = USBProbeGate.shouldProbe(
            hasCompletedOnboarding: UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding),
            skipDeepUSBProbing: skipProbing
        )
        let savedLanguage = UserDefaults.standard.string(forKey: Keys.preferredLanguage) ?? ""
        self.preferredLanguage = savedLanguage
        setCoreLocale(savedLanguage)
        setAppLocale(savedLanguage)
        setNotificationsLocale(savedLanguage)
        let stored = UserDefaults.standard.double(forKey: Keys.fontSize)
        let raw = stored > 0 ? stored : 1.0
        let initialScale = min(max(raw, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        self.fontSize = initialScale
        // Seed the AppKit-side store so the first popover/window open
        // already gets the right scale, before the user ever touches the
        // slider. didSet runs only on subsequent changes.
        FontScaleStore.shared.fontScale = initialScale
        let storedOpacity = UserDefaults.standard.double(forKey: Keys.uiOpacity)
        let rawOpacity = storedOpacity > 0 ? storedOpacity : 1.0
        let initialOpacity = min(max(rawOpacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        self.uiOpacity = initialOpacity
        // Seed the AppKit-side store so the first surface opens at the saved
        // opacity, before the user touches the slider.
        OpacityStore.shared.opacity = initialOpacity
        let savedIcon = UserDefaults.standard.string(forKey: Keys.menuBarIcon) ?? Self.defaultMenuBarIcon
        self.menuBarIcon = Self.validatedMenuBarIcon(savedIcon)
        self.showChargingWatts = UserDefaults.standard.bool(forKey: Keys.showChargingWatts)
        self.menuBarWattsStyle = UserDefaults.standard.string(forKey: Keys.menuBarWattsStyle)
            .flatMap(MenuBarWattsStyle.init(rawValue:)) ?? .number
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                let actual = SMAppService.mainApp.status == .enabled
                if self.launchAtLogin != actual {
                    self.launchAtLogin = actual
                }
            }
        }
    }
}

