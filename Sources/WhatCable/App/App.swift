import SwiftUI
import AppKit
import Combine
import os.log
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    static let refreshSignal = RefreshSignal.shared

    // Menu bar mode
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // Window mode
    private var window: NSWindow?

    // Onboarding
    private var welcomeWindow: NSWindow?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.notice("launch: version=\(AppInfo.version, privacy: .public) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)")
        registerWidgetExtension()
        NSWindow.allowsAutomaticWindowTabbing = false

        ProcessInfo.processInfo.setValue(AppInfo.name, forKey: "processName")

        // Apply the USB-probing preference BEFORE the watchers start. Their
        // first act is to enumerate the devices already plugged in, which fires
        // the Billboard probe; on a machine that must not be probed (issue #429)
        // that one launch-time burst is enough to restart the loop. Touching
        // AppSettings.shared also runs its init, which seeds the same gate.
        USBWatcher.probeBillboardDescriptors = !AppSettings.shared.skipDeepUSBProbing
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
            if let button = statusItem?.button, let popover, !popover.isShown {
                showPopover(from: button)
            }
        } else if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            setUpWindowMode()
        }
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
        let host = NSHostingController(
            rootView: ScaledHost {
                WelcomeView(
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
        AppSettings.shared.hasCompletedOnboarding = true
        AppSettings.shared.useMenuBarMode = useMenuBar
        applyDisplayMode(menuBar: useMenuBar)
        log.notice("launch: onboarding complete, menuBar=\(useMenuBar)")
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

    /// The fixed canvas size every menu-bar glyph is composited into, so the
    /// button image is the same width no matter which symbol is chosen. Computed
    /// once as the largest rendered glyph across all offered icons (so none is
    /// clipped). A constant image width means swapping the icon never changes the
    /// button width, so the popover never has to close and reopen to re-centre
    /// its arrow. A plain SymbolConfiguration does NOT achieve this: it pins the
    /// point size, but glyphs still have different intrinsic widths (e.g.
    /// `cable.connector.horizontal` is wider than `bolt.fill`), which shifted the
    /// anchor and forced the reseat blink (issue #313).
    private static let menuBarIconCanvasSize: NSSize = {
        let config = NSImage.SymbolConfiguration(pointSize: menuBarIconPointSize, weight: .regular)
        var size = NSSize(width: menuBarIconPointSize, height: menuBarIconPointSize)
        for name in AppSettings.menuBarIconChoices {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { continue }
            size.width = max(size.width, image.size.width)
            size.height = max(size.height, image.size.height)
        }
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }()

    /// Composite an SF Symbol, centred, into the fixed canvas so every glyph
    /// occupies the same width. Returns a template image so the menu bar tints it.
    ///
    /// Uses the drawing-handler initialiser rather than lockFocus so the glyph
    /// rasterises at each display's backing scale (crisp on Retina) instead of a
    /// single baked-in scale.
    private static func centeredMenuBarIcon(_ symbol: NSImage) -> NSImage {
        let size = menuBarIconCanvasSize
        let symbolSize = symbol.size
        let canvas = NSImage(size: size, flipped: false) { _ in
            let origin = NSPoint(
                x: ((size.width - symbolSize.width) / 2).rounded(),
                y: ((size.height - symbolSize.height) / 2).rounded()
            )
            symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        canvas.isTemplate = true
        return canvas
    }

    /// The centred, constant-width glyph for a symbol name, or nil if the symbol
    /// is unavailable on this macOS.
    private static func glyphImage(_ symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: menuBarIconPointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: AppInfo.name)?
            .withSymbolConfiguration(config) else { return nil }
        return centeredMenuBarIcon(symbol)
    }

    /// Set the status-item button to the plain glyph (no readout). Falls back to
    /// a short text label if the SF Symbol is unavailable (keeps the menu bar
    /// usable). The glyph is a fixed-width canvas so the button width is identical
    /// for every icon, keeping the popover anchor stable across an icon swap.
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
        // Do not close/reopen a shown popover to re-centre its arrow after this
        // layout change. `performClose` is asynchronous, so a subsequent show
        // can observe the popover as still open and close it a second time.
        // Power updates and cable hotplug can run this path several times in a
        // burst, making the race especially easy to hit. A briefly off-centre
        // arrow is preferable to dismissing an active user session.
    }

    /// The figure-space-padded "NNW" title for the menu bar watts label. The
    /// padding keeps the width constant across 9 -> 10: U+2007 (FIGURE SPACE) is
    /// exactly one digit wide in a monospaced-digit font, so a padded single
    /// digit lines up with a double digit and the anchor doesn't drift as the
    /// value ticks.
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
        let glyphSize = menuBarIconCanvasSize
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
        if let popover, popover.isShown { popover.performClose(nil) }
        popover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        lastMenuBarContent = nil
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
            popover.performClose(nil)
        } else {
            showPopover(from: button)
        }
    }

    /// Open the popover without toggle semantics. Programmatic callers use this
    /// after checking visibility so an asynchronous AppKit state transition can
    /// never turn an intended show into a close.
    private func showPopover(from button: NSStatusBarButton) {
        guard let popover, !popover.isShown else { return }
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
                showPopover(from: button)
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
        Task { @MainActor in
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

