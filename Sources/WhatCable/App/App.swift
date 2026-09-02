import SwiftUI
import AppKit
import Combine
import os.log
import UserNotifications
import WhatCableCore
import WhatCableDarwinBackend
import WhatCableAppKit
import WhatCablePlugins

// Launch diagnostics use `.notice`, not `.info`, on purpose. `log stream`
// and `log show` hide info/debug unless you pass `--level info`, so the
// simple command we hand non-technical users (issue #221) would show
// nothing. `.notice` is the lowest level a plain `log` command displays.
private let log = Logger(subsystem: "uk.whatcable.whatcable", category: "lifecycle")

@main
struct WhatCableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        bootstrapPlugins(registry: .shared)
    }

    var body: some Scene {
        // Headless - UI is owned by AppDelegate (status item + popover, or
        // a regular window, depending on AppSettings.useMenuBarMode).
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button(String(localized: "About \(AppInfo.name)", bundle: _appLocalizedBundle)) {
                        delegate.showAboutPanel()
                    }
                }
                CommandGroup(after: .appInfo) {
                    Button(String(localized: "Check for Updates…", bundle: _appLocalizedBundle)) {
                        UpdateChecker.shared.check(silent: false)
                    }
                }
                CommandGroup(after: .windowSize) {
                    let items = PluginRegistry.shared.menuItems[.afterWindowSize] ?? []
                    ForEach(items) { item in
                        Button(item.title) { item.action() }
                    }
                }
                CommandGroup(after: .toolbar) {
                    Button(String(localized: "Refresh", bundle: _appLocalizedBundle)) {
                        delegate.menuRefresh()
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
                CommandGroup(replacing: .help) {
                    Button(String(localized: "WhatCable on GitHub", bundle: _appLocalizedBundle)) {
                        NSWorkspace.shared.open(AppInfo.helpURL)
                    }
                }
                CommandGroup(replacing: .appSettings) {
                    Button(String(localized: "Settings…", bundle: _appLocalizedBundle)) {
                        delegate.showSettingsPanel(nil)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    let settingsItems = PluginRegistry.shared.menuItems[.appSettingsArea] ?? []
                    ForEach(settingsItems) { item in
                        Button(item.title) { item.action() }
                    }
                }
                #if DEBUG
                // Internal, debug-only route to the diagnostic reasoning surface.
                // Not compiled into release builds.
                CommandGroup(after: .help) {
                    Button("Diagnostic Reasoning (Debug)…") {
                        delegate.showDiagnosticDebugWindow()
                    }
                }
                #endif
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    static let refreshSignal = RefreshSignal.shared

    /// Diagnostic-only logging for the notification-click investigation.
    /// `.info` level, `.public` privacy on identifiers/titles/booleans
    /// (device names, not personal data), so `log stream --level info` can
    /// reconstruct the full click-to-popover sequence without reasoning.
    private nonisolated static let notificationClickLog = Logger(subsystem: "uk.whatcable.whatcable", category: "notification-clicks")

    // Menu bar mode
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // Window mode
    private var window: NSWindow?

    // Onboarding
    private var welcomeWindow: NSWindow?
    /// Mode applied if the welcome window is dismissed without clicking a card.
    /// Seeded from the stored preference in `showWelcomeWindow`, not defaulted:
    /// `WelcomeView` only reports a selection when a card is clicked, so a user
    /// who launched with `whatcable --desktop` and closed the window would
    /// otherwise have their Dock app silently converted to a menu bar app
    /// (issue #571 made this reachable by showing the welcome screen to legacy
    /// users who have a mode key but never onboarded).
    private var onboardingMenuBarChoice = true

    private var cancellables: Set<AnyCancellable> = []

    /// What's currently painted on the status item, so we skip the layout pass
    /// when nothing meaningful changed. Covers the glyph, the numeric readout, and
    /// the power bar's quantised fill step.
    private enum MenuBarContent: Equatable {
        case glyphOnly(symbol: String)
        case number(symbol: String, watts: Int)
        case bar(symbol: String, fillStep: Int)
    }
    private var lastMenuBarContent: MenuBarContent?

    /// The button width the popover was last anchored for, so the reanchor
    /// deferred block can tell a real width change from the ~1 Hz churn of
    /// `updateMenuBarPresentation` being called every time the watts readout
    /// ticks. Set whenever the popover is (re)anchored: on open, and inside
    /// `reanchorPopoverAfterWidthChange` when it applies an update.
    private var lastAnchoredButtonWidth: CGFloat?

    /// The queued reanchor block, held so a user-initiated close can cancel a
    /// stale one before it runs. Without this, a queued reanchor from just
    /// before the click can fire after `performClose`, undoing the user's
    /// close (the v1.5.0-beta.2 popover-won't-close bug).
    private var pendingReanchor: DispatchWorkItem?

    /// Observes the status item's own window moving, so the open popover can be
    /// re-pointed when a NEIGHBOURING menu bar item appears or disappears (issue
    /// #543). `reanchorPopoverAfterWidthChange` only fires when OUR button
    /// changes width; it has nothing to say about another app's icon sliding
    /// ours sideways while its own size stays the same. AppKit's claim that a
    /// popover "automatically moves when the location of the positioning view
    /// changes" doesn't hold for status items (see the doc comment above
    /// `reanchorPopoverAfterWidthChange`), so this needs the same explicit fix.
    /// Ported from the equivalent observer in the sibling app WhatPort, which
    /// shipped this fix first.
    private var statusItemMoveObserver: NSObjectProtocol?

    /// Notification-click activation race (see `NotificationClickPresentation`):
    /// held so a second notification click while one is already pending can
    /// tear down the previous observer/timeout before starting a new one,
    /// rather than stacking two observers on the same notification.
    private var pendingNotificationActivationObserver: NSObjectProtocol?
    private var pendingNotificationActivationTimeout: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard, resolved before anything else in this
        // method starts. A different copy of WhatCable on disk (e.g.
        // Homebrew and a manual /Applications copy) shares the same bundle
        // ID, so macOS happily launches a second process rather than
        // reopening the running one. Two live copies both watch the ports,
        // post duplicate notifications, and steal each other's focus
        // (observed live, issue #455). No subsystem below may start before
        // this resolves, which is why the whole rest of what used to be
        // this method is now `continueNormalLaunch()`: the only two places
        // allowed to call it are the plain "no other copy" branch here and
        // the failed-handover branch of the completion handler below.
        let other = Self.anotherInstance()
        let decision = LaunchInstanceDecision.decide(
            otherExists: other != nil,
            myLaunch: NSRunningApplication.current.launchDate,
            otherLaunch: other?.launchDate,
            myPID: ProcessInfo.processInfo.processIdentifier,
            otherPID: other?.processIdentifier ?? 0
        )
        guard decision == .deferToRunningInstance, let other else {
            log.notice("launch: no established other instance, continuing launch")
            continueNormalLaunch()
            return
        }

        // NSRunningApplication.activate() does NOT deliver the reopen Apple
        // Event: it just raises the other process's windows, it does not
        // ask it to reopen, so the other copy's
        // `applicationShouldHandleReopen` never fires and its popover
        // stays shut. Opening the already-running app via LaunchServices
        // is what actually sends `kAEReopenApplication`, exactly as if the
        // user had double-clicked it in Finder while it was already
        // running. `bundleURL` can be nil in principle (a process that's
        // already exiting, or an unusual launch context); if so there is
        // nothing to hand off to, so this copy continues rather than
        // deferring to a target it can't reach.
        guard let bundleURL = other.bundleURL else {
            log.notice("launch: other instance has no bundle URL, continuing launch instead of deferring")
            continueNormalLaunch()
            return
        }

        log.notice("launch: another instance is already running, attempting handover")
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    // The other copy may have died between the lookup above
                    // and this call, or the open genuinely failed. Better
                    // one late-starting copy than zero, so this process
                    // takes over rather than terminating into nothing.
                    log.notice("launch: handover failed (\(error.localizedDescription, privacy: .public)), continuing launch instead")
                    self.continueNormalLaunch()
                } else {
                    log.notice("launch: handover succeeded, terminating")
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// The rest of what used to be all of `applicationDidFinishLaunching`,
    /// pulled out so the single-instance guard above can call it from
    /// either the synchronous "no other copy" path or the asynchronous
    /// failed-handover path in `openApplication`'s completion handler.
    /// Nothing here may run before the guard has resolved.
    private func continueNormalLaunch() {
        // Assigned first thing, per Apple's docs, so a click that arrives
        // while the app is relaunching (the app was quit, a notification
        // sat in Notification Centre, the user clicks it) still routes
        // (issue #567).
        UNUserNotificationCenter.current().delegate = self

        log.notice("launch: version=\(AppInfo.version, privacy: .public) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)")
        registerWidgetExtension()
        NSWindow.allowsAutomaticWindowTabbing = false

        ProcessInfo.processInfo.setValue(AppInfo.name, forKey: "processName")

        // Apply the USB-probing gate BEFORE the watchers start. Their first
        // act is to enumerate the devices already plugged in, which fires the
        // Billboard probe; on a machine that must not be probed (issue #429)
        // that one launch-time burst is enough to restart the loop. Touching
        // AppSettings.shared also runs its init, which seeds the same gate.
        //
        // The gate is two conditions now, not just the compatibility switch:
        // a first run keeps the bus quiet until the welcome screen has been
        // through, because this line runs before any UI exists and a user
        // whose hardware the probe breaks would otherwise never get a window
        // to fix it from (issue #571).
        AppSettings.shared.applyUSBProbeGate()
        WatcherHub.shared.start()
        NotificationManager.shared.start()
        WidgetDataWriter.shared.start()
        UpdateChecker.shared.start()
        log.notice("launch: subsystems started")

        // Run launch hooks here, after all singletons have been started.
        // Hooks registered by plugins may call into NotificationManager,
        // WidgetDataWriter, UpdateChecker, or WatcherHub; running them in
        // App.init() (before applicationDidFinishLaunching) meant those
        // singletons were still in their private init and not yet started.
        let launchHooks = PluginRegistry.shared.launchHooks
        if !launchHooks.isEmpty {
            Task { @MainActor in
                for hook in launchHooks { await hook() }
            }
        }

        if AppSettings.shared.needsOnboarding {
            showWelcomeWindow()
        } else {
            applyDisplayMode(menuBar: AppSettings.shared.useMenuBarMode)
            log.notice("launch: display mode applied, menuBar=\(AppSettings.shared.useMenuBarMode)")
        }

        // No-op on Apple Silicon, i.e. on every supported Mac. Deferred a
        // runloop turn so the modal doesn't run inside
        // applicationDidFinishLaunching, and so whatever it sits in front of
        // (status item or window) already exists.
        DispatchQueue.main.async {
            UnsupportedArchitectureNotice.showIfNeeded()
        }

        // Live-switch when the user flips the toggle in Settings.
        AppSettings.shared.$useMenuBarMode
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] menuBar in
                self?.applyDisplayMode(menuBar: menuBar)
            }
            .store(in: &cancellables)

        // Live-swap the menu bar glyph when the user picks a new one.
        AppSettings.shared.$menuBarIcon
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarPresentation()
            }
            .store(in: &cancellables)

        // Repaint whenever the watcher publishes new power values. The watcher
        // recomputes on WatcherHub's existing poll cadence (1 Hz visible, 30 s
        // idle) and only publishes on change, so there's no separate per-second
        // timer and no IOKit read in the app target. Rated watts feeds the bar.
        WatcherHub.shared.powerWatcher.$chargerInputWatts
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarPresentation()
            }
            .store(in: &cancellables)

        WatcherHub.shared.powerWatcher.$chargerRatedWatts
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarPresentation()
            }
            .store(in: &cancellables)

        AppSettings.shared.$showChargingWatts
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.lastMenuBarContent = nil  // force a repaint on toggle
                // Turn the watcher's charger-in read on/off with the toggle.
                self.syncChargerWattsReading()
                self.updateMenuBarPresentation()
            }
            .store(in: &cancellables)

        // Repaint when the user switches between the number and the bar.
        AppSettings.shared.$menuBarWattsStyle
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.lastMenuBarContent = nil  // force a repaint on style change
                self.updateMenuBarPresentation()
            }
            .store(in: &cancellables)

        // Pin toggle: the menu item and the in-app button both write
        // RefreshSignal.keepOpen; this applies it to the live popover.
        Self.refreshSignal.$keepOpen
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keepOpen in
                self?.popover?.behavior = keepOpen ? .applicationDefined : .transient
            }
            .store(in: &cancellables)

        // A plugin (header button or status-menu item) sets a Pro-screen
        // route; bring the surface forward so the user sees it. The route
        // itself is rendered by ContentView. Nil (Back) needs no action.
        Self.refreshSignal.$activeProScreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                guard route != nil else { return }
                self?.presentMainSurface()
            }
            .store(in: &cancellables)

        // Idle the watcher poll while the Settings screen is up. Settings shows
        // no live data, but it renders inside ContentView, which observes every
        // watcher; left at the active cadence, each poll tick re-renders the
        // view under the icon picker and intermittently eats a click (issue
        // surfaced in testing). Menu-bar mode only: window mode drives its own
        // visibility via occlusion.
        Self.refreshSignal.$showSettings
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showSettings in
                guard let self, let popover = self.popover else { return }
                WatcherHub.shared.setUIVisible(popover.isShown && !showSettings)
            }
            .store(in: &cancellables)
    }

    /// Bring WhatCable to the foreground when the user explicitly opened a
    /// window (launch in window mode, onboarding, Settings, About, or a
    /// navigation request from outside the popover).
    ///
    /// The no-arg `NSApp.activate()` added in macOS 14 is *cooperative*: it
    /// will not pull the app in front of whatever the user was already using,
    /// so in window mode the window opened behind every time (issue #419).
    /// The `ignoringOtherApps: true` form is the forceful version: it honours
    /// an explicit user request to come forward. Confined to this one helper
    /// so the reasoning lives in a single place rather than scattered.
    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Bring the single content surface forward (popover in menu-bar
    /// mode, window in desktop mode) without changing any navigation
    /// state. Used when navigation is triggered from outside the popover.
    private func presentMainSurface() {
        activateApp()
        if AppSettings.shared.useMenuBarMode {
            Self.notificationClickLog.info("presentMainSurface: mode=menuBar popoverExists=\(self.popover != nil, privacy: .public) popoverIsShown=\(self.popover?.isShown ?? false, privacy: .public)")
            if let button = statusItem?.button, let popover, !popover.isShown {
                togglePopover(from: button)
            }
        } else if let window {
            Self.notificationClickLog.info("presentMainSurface: mode=window")
            window.makeKeyAndOrderFront(nil)
        } else {
            Self.notificationClickLog.info("presentMainSurface: mode=window")
            setUpWindowMode()
        }
    }

    /// The other running copy of WhatCable, if any, keyed on the shared
    /// bundle ID and excluding this process by PID. Static so the
    /// single-instance guard in `applicationDidFinishLaunching` can call it
    /// before `self` exists as a fully set-up delegate.
    private static func anotherInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Reopen hook: macOS calls this when the Dock icon is clicked, or the
    /// app is launched again from Finder/Spotlight, while WhatCable is
    /// already running as THIS process (issue #455). Bring the existing
    /// popover (or window) forward instead of doing nothing. Returning
    /// false tells AppKit we handled it ourselves, so it doesn't also try
    /// to open a new untitled window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log.notice("launch: reopen handled, presenting main surface")
        presentMainSurface()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        TestKitRunner.shared.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // In window mode, closing the window quits the app. In menu bar mode
        // there's no window to close, so this is harmless either way.
        !AppSettings.shared.useMenuBarMode
    }

    // MARK: - Onboarding

    private func showWelcomeWindow() {
        NSApp.setActivationPolicy(.regular)
        // Seed the dismissal fallback from the same value the view opens on, so
        // closing the window without clicking a card cannot change the mode.
        onboardingMenuBarChoice = AppSettings.shared.useMenuBarMode
        let host = NSHostingController(
            rootView: ScaledHost {
                WelcomeView(
                    useMenuBarInitially: AppSettings.shared.useMenuBarMode,
                    onSelectionChanged: { [weak self] useMenuBar in
                        self?.onboardingMenuBarChoice = useMenuBar
                    },
                    onComplete: { [weak self] useMenuBar in
                        self?.completeOnboarding(useMenuBar: useMenuBar)
                    }
                )
            }
        )
        let w = NSWindow(contentViewController: host)
        w.title = AppInfo.name
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        let scale = AppSettings.shared.fontSize
        w.setContentSize(NSSize(width: 420 * scale, height: 480 * scale))
        w.center()
        welcomeWindow = w
        w.makeKeyAndOrderFront(nil)
        activateApp()
        log.notice("launch: showing onboarding window")
    }

    private func completeOnboarding(useMenuBar: Bool) {
        guard let w = welcomeWindow else { return }
        welcomeWindow = nil
        // Mode first, completion marker last. Each is a separate UserDefaults
        // write, so if the process dies between them an interrupted prefix must
        // not leave onboarding marked complete with the mode unset: that would
        // skip the welcome screen next launch AND open the probe gate. (The
        // mode's didSet no-ops on an unchanged value, so on the common path
        // where the user accepts the recommended menu bar card nothing is
        // written at all. That is fine, absent reads as menu bar; the ordering
        // matters for the case where it does write.)
        AppSettings.shared.useMenuBarMode = useMenuBar
        // Setting this re-applies the USB probe gate through its own setter, so
        // there is no separate call to forget here (issue #571).
        AppSettings.shared.hasCompletedOnboarding = true
        applyDisplayMode(menuBar: useMenuBar)
        // Launch deliberately enumerated with probing off, so the devices we
        // already hold carry no alt-mode data. Re-read them now the gate is
        // open. This does not disturb the notification registration; see
        // USBWatcher.reenumerate() for why stop()/start() is the wrong tool.
        //
        // AFTER applyDisplayMode and deferred a runloop turn, both deliberate.
        // The read is a synchronous control transfer on the main thread with no
        // timeout, and on the hardware this whole change exists for it is the
        // thing that hangs. Doing it before the status item or window exists
        // would repeat the original bug one click later: a frozen machine with
        // no UI. This way there is a visible app first, and a hang is
        // attributable to the click that caused it.
        if USBWatcher.probeBillboardDescriptors {
            DispatchQueue.main.async {
                WatcherHub.shared.deviceWatcher.reenumerate()
            }
        }
        log.notice("launch: onboarding complete, menuBar=\(useMenuBar), usbProbe=\(USBWatcher.probeBillboardDescriptors)")
        DispatchQueue.main.async { w.close() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === welcomeWindow {
            completeOnboarding(useMenuBar: onboardingMenuBarChoice)
            return false
        }
        return true
    }

    /// Track window-mode visibility for the poll cadence. macOS sets
    /// `.visible` when any part of the window is on screen and clears it when
    /// the window is miniaturised or fully covered, so this follows real
    /// visibility, not just key focus. Only the main content window matters;
    /// the transient welcome window is ignored.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let changed = notification.object as? NSWindow, changed === window else { return }
        WatcherHub.shared.setUIVisible(changed.occlusionState.contains(.visible))
    }

    // MARK: - Display mode

    private func applyDisplayMode(menuBar: Bool) {
        if menuBar {
            tearDownWindowMode()
            setUpMenuBarMode()
            NSApp.setActivationPolicy(.accessory)
        } else {
            tearDownMenuBarMode()
            NSApp.setActivationPolicy(.regular)
            setUpWindowMode()
            activateApp()
        }
    }

    private func setUpMenuBarMode() {
        if popover == nil {
            let p = NSPopover()
            p.behavior = Self.refreshSignal.keepOpen ? .applicationDefined : .transient
            p.animates = true
            let host = NSHostingController(
                rootView: ScaledHost {
                    ContentView().environmentObject(Self.refreshSignal)
                }
            )
            host.sizingOptions = [.preferredContentSize]
            p.contentViewController = host
            p.delegate = self
            popover = p
            log.notice("menuBar: popover created")
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                applyGlyph(to: button, symbolName: AppSettings.shared.menuBarIcon)
                button.target = self
                button.action = #selector(handleClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                log.notice("menuBar: statusItem button configured, hasImage=\(button.image != nil), frame=\(button.frame.debugDescription, privacy: .public)")
            } else {
                log.error("menuBar: statusItem.button is nil, removing broken item")
                NSStatusBar.system.removeStatusItem(item)
                return
            }
            statusItem = item
            log.notice("menuBar: statusItem created, isVisible=\(item.isVisible)")
            observeStatusItemMoves()
        }
        // Turn on the watcher's charger-in read if the toggle is already on, then
        // paint the initial state from whatever it has published.
        syncChargerWattsReading()
        updateMenuBarPresentation()
    }

    /// Tell the shared power watcher whether to compute the live charger-in
    /// wattage. Only needed while the readout is enabled AND we're in menu-bar
    /// mode (the only place the label shows); off the rest of the time so no
    /// SMC / battery read runs. The watcher computes on WatcherHub's existing
    /// poll cadence, so there is no separate per-second timer here.
    private func syncChargerWattsReading() {
        WatcherHub.shared.powerWatcher.readsChargerInputWatts =
            AppSettings.shared.showChargingWatts && statusItem != nil
    }

    /// Point size every menu-bar glyph is rendered at.
    private static let menuBarIconPointSize: CGFloat = 16

    /// The box every menu-bar glyph is drawn into. One size for all of them, so
    /// swapping icons never changes the button width and so never moves the
    /// popover: the status item is right-aligned in the menu bar, so a width
    /// change slides its left edge, and the popover correctly follows the icon.
    ///
    /// The size is chosen, not measured off the widest icon. Sizing the box to
    /// the widest glyph is what made the item 42pt wide when a typical menu bar
    /// extra is 22-26pt (issue #411): the default `cable.connector` is only 10pt
    /// wide and was being padded out to 24pt to match `powerplug.fill`. Glyphs
    /// wider or taller than this box are scaled down to fit instead, keeping
    /// their aspect ratio, so every icon gets the same 18x18 footprint without
    /// inheriting the widest one's. Note that is a constant footprint, not a
    /// constant painted glyph: a symbol already smaller than the box keeps its
    /// natural size and simply sits centred in it.
    private static let menuBarIconBoxSize = NSSize(width: 18, height: 18)

    /// The uniform-size glyph for a symbol name, or nil if the symbol is
    /// unavailable on this macOS. Returns a template image so the menu bar tints it.
    ///
    /// Aspect-fit into `menuBarIconBoxSize` and centred, so every icon occupies
    /// exactly the same space. A plain SymbolConfiguration does NOT achieve this:
    /// it pins the point size, but glyphs still have different intrinsic widths
    /// (`cable.connector.horizontal` is 24pt against `cable.connector`'s 10pt),
    /// which shifts the button and moves the popover with it (issue #313).
    ///
    /// Uses the drawing-handler initialiser rather than lockFocus so the glyph
    /// rasterises at each display's backing scale (crisp on Retina) instead of a
    /// single baked-in scale.
    private static func glyphImage(_ symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: menuBarIconPointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: AppInfo.name)?
            .withSymbolConfiguration(config) else { return nil }

        let box = menuBarIconBoxSize
        let natural = symbol.size
        // Only ever scale down: a glyph already inside the box keeps its own size
        // rather than being blown up to fill it.
        let scale = min(1, min(box.width / natural.width, box.height / natural.height))
        let drawn = NSSize(width: natural.width * scale, height: natural.height * scale)

        let canvas = NSImage(size: box, flipped: false) { _ in
            let origin = NSPoint(
                x: ((box.width - drawn.width) / 2).rounded(),
                y: ((box.height - drawn.height) / 2).rounded()
            )
            symbol.draw(
                in: NSRect(origin: origin, size: drawn),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
            return true
        }
        canvas.isTemplate = true
        return canvas
    }

    /// Set the status-item button to the plain glyph (no readout). Falls back to
    /// a short text label if the SF Symbol is unavailable (keeps the menu bar
    /// usable).
    private func applyGlyph(to button: NSStatusBarButton, symbolName: String) {
        if let image = Self.glyphImage(symbolName) {
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            log.warning("menuBar: SF Symbol \(symbolName, privacy: .public) returned nil, using text fallback")
            button.image = nil
            button.imagePosition = .noImage
            button.title = "WC"
        }
    }

    /// Re-anchor an open popover after the status-item button changed width, so
    /// its arrow stays centred on the button.
    ///
    /// AppKit's header says popovers "are automatically moved when the location
    /// or size of the positioning view changes", but that does not hold for an
    /// `NSStatusBarButton`: issue #313 is a reproduction, with a screenshot, of
    /// the arrow going misaligned on an icon swap and only correcting on the
    /// next reopen. So the re-anchor has to be explicit.
    ///
    /// This used to call `show` again on the assumption that the header's "if
    /// the popover is already being shown, this method will update to be
    /// associated with the new view and positioningRect passed" made it a safe
    /// re-anchor rather than a reopen. It isn't safe: `updateMenuBarPresentation`
    /// runs on every `MenuBarContent` change, and that includes the raw watts
    /// value ticking ~1 Hz while charging with the readout on, so `show` was
    /// being re-invoked roughly once a second on an already-open popover. A
    /// user's click-to-close could race a queued re-show and pop the popover
    /// back open, or land inside the "click that opened it" ignore window and
    /// have the transient dismiss swallowed. That's the v1.5.0-beta.2
    /// popover-won't-close bug. Assigning `popover.positioningRect` instead
    /// only mutates a property AppKit already tracks continuously; it can't
    /// re-enter or fight a concurrent `performClose`. An earlier attempt at
    /// this approach was rejected because the arrow was left off-centre after
    /// an icon swap, but that test read the button's bounds synchronously in
    /// the same runloop turn, before the status bar had reflowed the item to
    /// its new width. Reading a fresh `bounds` inside the deferred block below
    /// avoids that stale read, and `positioningRect` moves the arrow correctly.
    ///
    /// Animation is suppressed for the re-anchor so this reads as the arrow
    /// staying put, not the panel re-presenting itself.
    ///
    /// The previous implementation called `performClose` and reopened, which is
    /// why it needed a `keepOpen` guard: that close dismissed popovers the user
    /// had pinned (issue #346). Nothing closes here, so no guard is needed and
    /// pinned popovers get their arrow re-centred too.
    ///
    /// The "did the width actually change?" check now lives inside the deferred
    /// block, checked against a fresh read, not before scheduling. It used to be
    /// deliberately absent because a pre-scheduling check reads the button's
    /// width before the status bar has reflowed a `variableLength` item (which
    /// happens on its own schedule, not synchronously), so it could read stale
    /// and skip a re-anchor that was actually needed. That objection doesn't
    /// apply once the check runs after the same deferred turn that waits for the
    /// reflow to settle, and skipping the no-op case here is what stops the
    /// ~1 Hz watts tick from touching `positioningRect` when nothing moved.
    private func reanchorPopoverAfterWidthChange() {
        // Deferred a runloop turn on purpose. An NSStatusItem with
        // `variableLength` reflows to fit its contents on the status bar's own
        // schedule, not synchronously inside the layout call above, so
        // re-anchoring immediately reads the button at its OLD width. The item
        // then grows and leaves the arrow off-centre, which is what turning the
        // watts readout on did: the label adds ~29pt, and the arrow stayed put
        // while the item widened underneath it. By the next turn the status bar
        // has settled and `bounds` is the real rect.
        // The button is deliberately re-read here rather than captured. Between
        // scheduling and the next turn the menu bar can be torn down and rebuilt
        // (`tearDownMenuBarMode` then `setUpMenuBarMode`, e.g. a display-mode
        // switch), which leaves the captured button belonging to a status item
        // that has been removed. Repositioning relative to a view that is no
        // longer in a window raises NSInvalidArgumentException, so the stale
        // button has to be dropped, not merely null-checked.
        //
        // Held in `pendingReanchor` so a user-initiated close (togglePopover's
        // close branch) or a popover teardown can cancel a queued-but-not-yet-run
        // block. Without that, a reanchor queued a moment before the user's
        // click could still fire after the close and touch a popover the user
        // just dismissed.
        pendingReanchor?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  let button = self.statusItem?.button,
                  button.window != nil,
                  let popover = self.popover,
                  popover.isShown
            else { return }
            let currentWidth = button.bounds.width
            guard Self.shouldReanchor(lastWidth: self.lastAnchoredButtonWidth, currentWidth: currentWidth) else { return }
            let animated = popover.animates
            popover.animates = false
            popover.positioningRect = button.bounds
            popover.animates = animated
            self.lastAnchoredButtonWidth = currentWidth
        }
        pendingReanchor = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    /// Whether the button has genuinely changed width since the popover was
    /// last anchored, versus a no-op call caused by `updateMenuBarPresentation`
    /// re-running for an unrelated content change (e.g. the watts value
    /// ticking). `nil` means never anchored, so treat it as changed. The 0.5pt
    /// epsilon absorbs floating-point noise from layout, not real movement.
    nonisolated static func shouldReanchor(lastWidth: CGFloat?, currentWidth: CGFloat) -> Bool {
        guard let lastWidth else { return true }
        return abs(currentWidth - lastWidth) > 0.5
    }

    /// Watch for `didMoveNotification`, so a neighbouring menu bar item
    /// appearing or disappearing (which slides our item, and its window,
    /// sideways without changing its width) re-points the open popover too
    /// (issue #543). Idempotent: removes any previous observer first, so
    /// calling this again (e.g. a future re-setup) can't stack two.
    ///
    /// Registered unscoped (`object: nil`) rather than pinned to a captured
    /// `item.button?.window`, and filtered by identity inside the handler
    /// instead. The object-pinned version was the first cut here and review
    /// flagged it: the button's window at status-item creation is a one-time
    /// snapshot of an undocumented value, never guaranteed non-nil by AppKit.
    /// If it were nil at registration the fix would silently disarm, and if
    /// AppKit ever rehosts the status item in a different window later, a
    /// pinned observer would be left watching the old one and never fire
    /// again. Filtering by identity per notification instead follows
    /// whatever window is current at the moment of the move, so a window
    /// replacement is handled automatically, for the cost of one pointer
    /// compare per menu-bar-wide move.
    ///
    /// This does NOT go through `pendingReanchor`'s deferred-block machinery.
    /// That deferral exists in `reanchorPopoverAfterWidthChange` because a
    /// `variableLength` status item reflows to its new width on the status
    /// bar's own schedule, so the width has to be read a runloop turn later to
    /// avoid a stale read. `didMoveNotification` is different: it fires AFTER
    /// the window has already moved, so `button.bounds` read inside the handler
    /// is already current, there is nothing left to wait for. And unlike the
    /// deferred width path, writing `positioningRect` here can't race a
    /// concurrent `performClose`: it's a synchronous property assignment on the
    /// main thread, made directly inside a main-queue notification callback, not
    /// a block queued to run later that a close could have to cancel out from
    /// under.
    private func observeStatusItemMoves() {
        stopObservingStatusItemMoves()
        statusItemMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // queue: .main above guarantees this block runs on the main
            // thread no matter which thread posted the notification, which is
            // what makes assumeIsolated safe here.
            MainActor.assumeIsolated {
                guard let self, notification.object as? NSWindow === self.statusItem?.button?.window else { return }
                self.reanchorPopoverAfterStatusItemMove()
            }
        }
    }

    private func stopObservingStatusItemMoves() {
        guard let statusItemMoveObserver else { return }
        NotificationCenter.default.removeObserver(statusItemMoveObserver)
        self.statusItemMoveObserver = nil
    }

    /// Re-point the open popover's arrow after the status item's window itself
    /// moved (see `observeStatusItemMoves`). Mirrors the animation-suppression
    /// trick in `reanchorPopoverAfterWidthChange`: without it the arrow visibly
    /// slides to its new spot instead of just being there.
    private func reanchorPopoverAfterStatusItemMove() {
        guard let popover, popover.isShown,
              let button = statusItem?.button, button.window != nil
        else { return }
        let animated = popover.animates
        popover.animates = false
        popover.positioningRect = button.bounds
        popover.animates = animated
    }

    /// Single entry point that paints the status item for the current state: the
    /// plain glyph, the glyph plus the numeric "NNW" readout, or the glyph plus a
    /// power bar. One renderer so the icon swap, the watts update, and the style
    /// change can't fight over the button. Dedupes on `lastMenuBarContent` so an
    /// unchanged state does no layout work.
    ///
    /// The IOKit read lives in the watcher and only runs while the readout is on,
    /// so users with the feature off (the default) pay no read cost.
    private func updateMenuBarPresentation() {
        guard let button = statusItem?.button else { return }
        guard AppSettings.shared.useMenuBarMode else { return }

        let symbol = AppSettings.shared.menuBarIcon
        let watts = WatcherHub.shared.powerWatcher.chargerInputWatts
        let showReadout = AppSettings.shared.showChargingWatts && watts > 0

        let content: MenuBarContent
        if showReadout {
            switch AppSettings.shared.menuBarWattsStyle {
            case .number:
                content = .number(symbol: symbol, watts: watts)
            case .bar:
                let step = Self.powerBarFillStep(
                    watts: watts,
                    rated: WatcherHub.shared.powerWatcher.chargerRatedWatts
                )
                content = .bar(symbol: symbol, fillStep: step)
            }
        } else {
            content = .glyphOnly(symbol: symbol)
        }

        guard content != lastMenuBarContent else { return }
        lastMenuBarContent = content

        switch content {
        case .glyphOnly(let symbol):
            applyGlyph(to: button, symbolName: symbol)
        case .number(let symbol, let watts):
            applyGlyph(to: button, symbolName: symbol)
            button.attributedTitle = Self.wattsAttributedTitle(watts)
            button.imagePosition = .imageLeft
        case .bar(let symbol, let fillStep):
            button.image = Self.menuBarBarImage(symbolName: symbol, fillStep: fillStep)
            button.imagePosition = .imageOnly
            button.title = ""
        }
        button.needsLayout = true
        button.needsDisplay = true
        button.layoutSubtreeIfNeeded()
        reanchorPopoverAfterWidthChange()
    }

    /// The figure-space-padded "NNW" title for the menu bar watts label. The
    /// padding keeps the width constant across 9 -> 10: U+2007 (FIGURE SPACE) is
    /// exactly one digit wide in a monospaced-digit font, so a padded single
    /// digit lines up with a double digit (issue #346).
    ///
    /// This padding is kept deliberately, even though the popover is now
    /// re-anchored on a width change rather than closed and reopened. The
    /// re-anchor keeps the arrow centred, but it cannot stop the item itself
    /// changing width, and a live wattage ticking across 9 -> 10 would then
    /// shuffle the whole popover sideways every few seconds while the user is
    /// reading it. Costing 8pt of menu bar, only while charging below 10W, is
    /// the cheaper side of that trade. The icon padding was a different case
    /// and was removed: see `glyphImage`.
    private static func wattsAttributedTitle(_ watts: Int) -> NSAttributedString {
        let digits = String(watts)
        let padded = digits.count < 2
            ? String(repeating: "\u{2007}", count: 2 - digits.count) + digits
            : digits
        return NSAttributedString(
            string: "\(padded)W",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            ]
        )
    }

    // MARK: - Power bar

    /// Number of discrete fill steps in the power bar. Quantising the fill keeps
    /// the bar still instead of twitching every second (issue #366).
    nonisolated private static let powerBarSteps = 10
    private static let powerBarWidth: CGFloat = 22
    private static let powerBarHeight: CGFloat = 6
    private static let powerBarGap: CGFloat = 4
    /// Scale used when the adapter doesn't report a rating, so the bar still
    /// shows something sensible. Covers the common laptop charger range.
    nonisolated private static let powerBarFallbackRatedWatts = 100.0

    /// Quantised fill level (0...`powerBarSteps`) for live watts against the
    /// charger's rated wattage. Falls back to a fixed scale when the rating is
    /// unknown. Any positive draw returns at least step 1 so the bar always shows
    /// a visible nub while charging, never an empty track. Pure and testable.
    nonisolated static func powerBarFillStep(watts: Int, rated: Int) -> Int {
        guard watts > 0 else { return 0 }
        let denom = rated > 0 ? Double(rated) : powerBarFallbackRatedWatts
        let fraction = min(1.0, Double(watts) / denom)
        return max(1, Int((fraction * Double(powerBarSteps)).rounded()))
    }

    /// Glyph plus a fill bar, composited into one fixed-width template image so
    /// the menu bar tints it and the button width stays constant as the fill
    /// changes. The track is drawn faint and the fill solid (template images keep
    /// alpha, so both tint to the menu bar colour at their drawn opacity).
    private static func menuBarBarImage(symbolName: String, fillStep: Int) -> NSImage {
        let glyph = glyphImage(symbolName)
        // Every glyph is drawn into the same box, so the composite is a constant
        // width whether or not the symbol resolved.
        let glyphSize = menuBarIconBoxSize
        let totalWidth = glyphSize.width + powerBarGap + powerBarWidth
        let height = max(glyphSize.height, powerBarHeight)
        let fraction = Double(fillStep) / Double(powerBarSteps)
        let radius = powerBarHeight / 2

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            if let glyph {
                let gy = ((height - glyphSize.height) / 2).rounded()
                glyph.draw(at: NSPoint(x: 0, y: gy), from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            let barX = glyphSize.width + powerBarGap
            let barY = ((height - powerBarHeight) / 2).rounded()
            let track = NSRect(x: barX, y: barY, width: powerBarWidth, height: powerBarHeight)
            NSColor.black.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
            if fraction > 0 {
                // Floor the fill at one bar-height so a low but non-zero level is
                // still a visible nub, not an invisible sliver.
                let fillWidth = max(powerBarHeight, powerBarWidth * CGFloat(fraction))
                let fill = NSRect(x: barX, y: barY, width: fillWidth, height: powerBarHeight)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func tearDownMenuBarMode() {
        // Leaving menu-bar mode: stop the watcher reading charger-in watts.
        WatcherHub.shared.powerWatcher.readsChargerInputWatts = false
        // Drop any queued reanchor before the status item goes away, so it
        // can't fire against a button/popover that no longer exists.
        pendingReanchor?.cancel()
        pendingReanchor = nil
        stopObservingStatusItemMoves()
        if let popover, popover.isShown { popover.performClose(nil) }
        popover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        lastMenuBarContent = nil
        lastAnchoredButtonWidth = nil
    }

    private func setUpWindowMode() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            WatcherHub.shared.setUIVisible(true)
            return
        }
        let host = NSHostingController(
            rootView: ScaledHost {
                ContentView().environmentObject(Self.refreshSignal)
            }
        )
        let w = NSWindow(contentViewController: host)
        w.title = AppInfo.name
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 760, height: 540))
        w.center()
        w.delegate = self
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        // Window is on screen: poll at the live cadence. Occlusion changes
        // (miniaturise, fully covered) flip this back via the delegate below.
        WatcherHub.shared.setUIVisible(true)
    }

    private func tearDownWindowMode() {
        window?.delegate = nil
        window?.close()
        window = nil
        // No surface left in window mode: drop to the idle poll cadence.
        WatcherHub.shared.setUIVisible(false)
    }

    // MARK: - Status item handling (menu bar mode)

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu(from: sender)
        } else {
            // ⌥-click momentarily reveals the technical-details view,
            // matching the macOS convention used by Wi-Fi / Volume /
            // Bluetooth menus. The flag is cleared when the popover closes
            // (see popoverDidClose), so the persistent preference in
            // AppSettings is what survives across opens.
            Self.refreshSignal.optionHeld = event.modifierFlags.contains(.option)
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            // User close always wins: drop any reanchor that was queued a
            // moment ago (e.g. from a watts tick just before the click) so it
            // can't fire after this close and reopen or reposition a popover
            // the user just dismissed.
            pendingReanchor?.cancel()
            pendingReanchor = nil
            popover.performClose(nil)
        } else {
            // Cap the popover to the display the status item lives on, so a tall
            // panel (e.g. "show technical details" on a small or heavily scaled
            // screen) can't grow past the screen and push its own header, and the
            // settings gear with it, up behind the menu bar out of reach (issue
            // #454). The status-bar button's window sits on the menu-bar screen,
            // so its visibleFrame is the real room a downward-growing popover has:
            // it already excludes the menu bar and the Dock. Small allowance for
            // the popover's own arrow so the whole thing fits. Never taller than
            // the historic 760 cap, so larger screens are unaffected.
            if let visibleHeight = (button.window?.screen ?? NSScreen.main)?.visibleFrame.height {
                Self.refreshSignal.maxPopoverHeight = min(760, visibleHeight - 12)
            } else {
                Self.refreshSignal.maxPopoverHeight = 760
            }
            Self.refreshSignal.bump()
            // Refresh the offered update version on open, throttled so it
            // doesn't hit GitHub on every panel open (issue #372).
            UpdateChecker.shared.checkIfStale()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            // No pendingReanchor cancel here, and that asymmetry with the
            // close branch is deliberate: a reanchor queued before this open
            // compares against the width recorded on this line, so it no-ops
            // rather than misfires (reviewer-traced).
            lastAnchoredButtonWidth = button.bounds.width
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(.init(title: String(localized: "Refresh", bundle: _appLocalizedBundle), action: #selector(menuRefresh), keyEquivalent: "r"))
        let pinItem = NSMenuItem(title: String(localized: "Keep window open", bundle: _appLocalizedBundle), action: #selector(menuTogglePin), keyEquivalent: "p")
        pinItem.state = Self.refreshSignal.keepOpen ? .on : .off
        menu.addItem(pinItem)
        menu.addItem(.separator())
        menu.addItem(.init(title: String(localized: "Settings…", bundle: _appLocalizedBundle), action: #selector(menuSettings), keyEquivalent: ","))
        for builder in PluginRegistry.shared.nsMenuItemBuilders[.statusItemMenu] ?? [] {
            menu.addItem(builder())
        }
        menu.addItem(.init(title: String(localized: "Check for Updates…", bundle: _appLocalizedBundle), action: #selector(menuCheckUpdates), keyEquivalent: ""))
        let testKitItem = NSMenuItem(
            title: String(localized: "Contribute Diagnostic Data…", bundle: _appLocalizedBundle),
            action: #selector(menuRunTestKit),
            keyEquivalent: ""
        )
        if TestKitRunner.shared.isRunning {
            testKitItem.isEnabled = false
        }
        menu.addItem(testKitItem)
        menu.addItem(.separator())
        menu.addItem(.init(title: String(localized: "About \(AppInfo.name)", bundle: _appLocalizedBundle), action: #selector(showAboutPanel), keyEquivalent: ""))
        menu.addItem(.init(title: String(localized: "WhatCable on GitHub", bundle: _appLocalizedBundle), action: #selector(menuHelp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: String(localized: "Quit \(AppInfo.name)", bundle: _appLocalizedBundle), action: #selector(menuQuit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil && item.target == nil { item.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuTogglePin() {
        // The $keepOpen sink applies this to the live popover.
        Self.refreshSignal.keepOpen.toggle()
    }

    @objc func menuRefresh() {
        Self.refreshSignal.bump()
    }

    @objc private func menuSettings() {
        showSettings()
    }

    @objc func showSettingsPanel(_ sender: Any?) {
        showSettings()
    }


    private func showSettings() {
        activateApp()
        Self.refreshSignal.showSettings = true
        if AppSettings.shared.useMenuBarMode {
            if let button = statusItem?.button, let popover, !popover.isShown {
                togglePopover(from: button)
            }
        } else {
            if let window {
                window.makeKeyAndOrderFront(nil)
            } else {
                setUpWindowMode()
            }
        }
    }

    @objc func showAboutPanel() {
        activateApp()
        let credits = NSAttributedString(
            string: "\(AppInfo.tagline)\n\n\(AppInfo.credit)",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 11)
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .version: "",
            .credits: credits,
            .init(rawValue: "Copyright"): AppInfo.copyright
        ])
    }


    @objc private func menuRunTestKit() {
        showSettings()
        Self.refreshSignal.showTestKitConsent = true
    }

    @objc private func menuCheckUpdates() {
        UpdateChecker.shared.check(silent: false)
    }

    @objc private func menuHelp() {
        NSWorkspace.shared.open(AppInfo.helpURL)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Widget extension registration

    /// Tell PluginKit about our widget extension on every launch.
    ///
    /// Launch Services can accumulate stale extension entries across app
    /// upgrades (especially Homebrew cask upgrades). When pkd sees multiple
    /// entries for the same bundle ID, its dedup logic can reject all of
    /// them, leaving "Final plugin count: 0" and no widget in the gallery.
    /// Explicitly adding the appex bypasses the stale-entry collision.
    private func registerWidgetExtension() {
        guard let appexURL = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("WhatCableWidget.appex") else { return }
        // Capture the path as a plain String before leaving the main actor.
        // pluginkit talks to the pkd daemon over XPC, which can be slow at
        // login or right after an upgrade. Running it synchronously here would
        // stall the launch. Task.detached (not Task) is required: a plain Task
        // started inside a @MainActor context still runs on the main thread,
        // which would not help. Detached runs on a background thread entirely
        // outside the main actor.
        let appexPath = appexURL.path
        Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            task.arguments = ["-a", appexPath]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    log.notice("launch: registered widget extension via pluginkit")
                } else {
                    log.warning("launch: pluginkit -a exited with status \(task.terminationStatus)")
                }
            } catch {
                log.warning("launch: pluginkit -a failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidShow(_ notification: Notification) {
        // Popover is on screen: poll at the live cadence so readings tick, unless
        // it opened straight into Settings (no live data, so stay idle).
        Task { @MainActor in
            WatcherHub.shared.setUIVisible(!Self.refreshSignal.showSettings)
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Self.notificationClickLog.info("popoverDidClose")
        Task { @MainActor in
            // Belt-and-braces alongside togglePopover's own cancel: any close,
            // however it happened, drops a queued reanchor so it can't fire
            // against a popover that just went away. Guarded on the popover
            // still being closed: this Task lands a turn late, and if the user
            // reopened in that gap the queued reanchor now belongs to the NEW
            // presentation, so cancelling it here would leave a fresh popover
            // with a stale arrow until the next content change (review
            // finding on the first cut of this fix).
            if self.popover?.isShown != true {
                self.pendingReanchor?.cancel()
                self.pendingReanchor = nil
            }
            // Drop to the idle cadence only if a menu-bar popover still exists.
            // This callback also fires when the popover is torn down to switch
            // into window mode: that close arrives late (after setUpWindowMode
            // has already marked the window visible), so treating it as
            // "nothing visible" would wrongly park window mode at the idle
            // cadence. By then tearDownMenuBarMode has set `popover` to nil, so
            // this guard skips it; a normal user-dismissed close leaves the
            // popover non-nil and correctly drops to idle.
            if self.popover != nil { WatcherHub.shared.setUIVisible(false) }
            Self.refreshSignal.optionHeld = false
            Self.refreshSignal.showSettings = false
            Self.refreshSignal.showTestKitConsent = false
        }
    }

    // MARK: - Notification clicks (issue #567)

    /// Show the banner (and keep it in Notification Centre's list) even
    /// when macOS considers WhatCable frontmost, e.g. the popover is
    /// already open when a new device notification arrives.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Self.notificationClickLog.info("willPresent: identifier=\(notification.request.identifier, privacy: .public)")
        completionHandler([.banner, .list])
    }

    /// Thin shell around `NotificationRouting.action(for:)`: the actual
    /// identifier -> action decision is a pure function, tested on its own.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Only a real click opens the popover. There are no action buttons
        // today, but macOS also routes a plain dismiss through this same
        // delegate method with its own actionIdentifier, and that must not
        // be treated as a click.
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        Task { @MainActor in
            Self.notificationClickLog.info("didReceive: identifier=\(identifier, privacy: .public) actionIdentifier=\(actionIdentifier, privacy: .public) isActive=\(NSApp.isActive, privacy: .public)")
        }
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }
        let action = NotificationRouting.action(for: identifier)
        Task { @MainActor in
            self.routeNotificationClick(action)
        }
        completionHandler()
    }

    /// Brings the popover forward for a notification click, always clearing
    /// any Settings/Pro-screen overlay first so the main content is what's
    /// actually on screen (clicking "Charger connected" while Settings is
    /// open should land on the main content, not leave Settings showing).
    ///
    /// Whether that happens right away or after a real activation handover
    /// is `NotificationClickPresentation`'s call: see its doc comment for
    /// why a notification click needs this and a status-item click doesn't.
    private func routeNotificationClick(_ action: NotificationClickAction) {
        Self.refreshSignal.showSettings = false
        Self.refreshSignal.activeProScreen = nil

        let presentation = NotificationClickPresentation.decide(isAppActive: NSApp.isActive)
        Self.notificationClickLog.info("routeNotificationClick: presentation=\(String(describing: presentation), privacy: .public)")
        switch presentation {
        case .presentNow:
            presentMainSurface()
        case .activateThenPresentOnActivation:
            presentMainSurfaceAfterActivation()
        }
    }

    /// Activates the app, then defers `presentMainSurface()` until
    /// `didBecomeActiveNotification` actually fires, instead of presenting
    /// in the same tick as `activateApp()`. The popover is `.transient` and
    /// closes itself the instant it thinks focus has moved away; presenting
    /// while the activation handover from the notification-banner click is
    /// still in flight means the tail of that handover reads as a
    /// click-away, and the popover flashes open and immediately closes
    /// again. Waiting for confirmation that activation actually landed
    /// means there's nothing left in flight to misread as a click-away.
    ///
    /// A short safety timeout presents anyway and tears the observer down
    /// if `didBecomeActiveNotification` never arrives, so a missed
    /// notification can never strand the click doing nothing.
    ///
    /// A second notification click while one of these is already pending
    /// tears down the previous observer/timeout first (see
    /// `clearPendingNotificationActivation`), so rapid double-clicking never
    /// stacks two observers waiting on the same notification, which would
    /// otherwise present twice or leave one of them dangling.
    private func presentMainSurfaceAfterActivation() {
        clearPendingNotificationActivation()

        // Both closures below call back into this actor-isolated type from a
        // context the compiler can't itself prove is MainActor: the
        // `addObserver` closure because `queue: .main` is a runtime
        // guarantee, not a type-level one, and the `DispatchWorkItem`
        // likewise because it's dispatched onto `DispatchQueue.main`.
        // `MainActor.assumeIsolated` documents that guarantee and, crucially,
        // keeps the call synchronous rather than hopping through `Task`.
        // A `Task { @MainActor in ... }` hop introduces a suspension point:
        // the closure returns immediately and the actual work runs on a
        // later turn of the run loop, which reopens exactly the race this
        // fix exists to close. A stale task queued by an old timeout, or by
        // an old observer fire, could then run its
        // `finishPendingNotificationActivation()` AFTER a second click has
        // already registered a new observer, clearing its pending state out
        // from under it. With `assumeIsolated`, the observer firing, the
        // timeout firing, and a second click's own
        // `clearPendingNotificationActivation()` all run synchronously on
        // the main thread, so they serialise: whichever runs first
        // completes in full (clearing state and presenting, or clearing
        // state to make way for a new pending activation) before the next
        // one starts. There is no window for a stale completion to land
        // after a newer one has taken over.
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.notificationClickLog.info("activation observer fired")
                self?.finishPendingNotificationActivation()
            }
        }
        pendingNotificationActivationObserver = observer
        Self.notificationClickLog.info("presentMainSurfaceAfterActivation: observer registered")

        let timeout = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                Self.notificationClickLog.info("activation timeout fired")
                self?.finishPendingNotificationActivation()
            }
        }
        pendingNotificationActivationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: timeout)

        activateApp()
    }

    /// Common landing point for both the observer firing and the safety
    /// timeout firing: tear down whichever of the two didn't win, then
    /// present. Whichever path calls this first cancels the other, so only
    /// one `presentMainSurface()` call ever happens per pending activation.
    private func finishPendingNotificationActivation() {
        Self.notificationClickLog.info("finishPendingNotificationActivation")
        clearPendingNotificationActivation()
        presentMainSurface()
    }

    /// Removes any pending observer and cancels any pending timeout,
    /// leaving neither able to fire again. Safe to call when nothing is
    /// pending.
    private func clearPendingNotificationActivation() {
        if let observer = pendingNotificationActivationObserver {
            NotificationCenter.default.removeObserver(observer)
            pendingNotificationActivationObserver = nil
        }
        pendingNotificationActivationTimeout?.cancel()
        pendingNotificationActivationTimeout = nil
    }
}

#if DEBUG
extension AppDelegate {
    private static var diagnosticDebugWindow: NSWindow?

    /// Opens the internal diagnostic-reasoning surface. Debug builds only.
    @MainActor func showDiagnosticDebugWindow() {
        if let existing = AppDelegate.diagnosticDebugWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: DiagnosticDebugView()))
        window.title = "Diagnostic Reasoning (Debug)"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        AppDelegate.diagnosticDebugWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

