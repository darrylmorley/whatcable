import SwiftUI
import AppKit
import Combine
import WhatCableCore
import WhatCableAppKit
import WhatCablePlugins

@main
struct WhatCableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        bootstrapPlugins(registry: .shared)
        let hooks = PluginRegistry.shared.launchHooks
        if !hooks.isEmpty {
            Task {
                for hook in hooks { await hook() }
            }
        }
    }

    var body: some Scene {
        // Headless - UI is owned by AppDelegate (status item + popover, or
        // a regular window, depending on AppSettings.useMenuBarMode).
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button(String(localized: "About \(AppInfo.name)", bundle: .module)) {
                        delegate.showAboutPanel()
                    }
                }
                CommandGroup(after: .appInfo) {
                    Button(String(localized: "Check for Updates…", bundle: .module)) {
                        UpdateChecker.shared.check(silent: false)
                    }
                }
                CommandGroup(after: .windowSize) {
                    let items = PluginRegistry.shared.menuItems[.afterWindowSize] ?? []
                    ForEach(items) { item in
                        Button(item.title) { item.action() }
                    }
                }
                CommandGroup(replacing: .help) {
                    Button(String(localized: "WhatCable on GitHub", bundle: .module)) {
                        NSWorkspace.shared.open(AppInfo.helpURL)
                    }
                }
                CommandGroup(replacing: .appSettings) {
                    Button(String(localized: "Settings…", bundle: .module)) {
                        delegate.showSettingsPanel(nil)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    let settingsItems = PluginRegistry.shared.menuItems[.appSettingsArea] ?? []
                    ForEach(settingsItems) { item in
                        Button(item.title) { item.action() }
                    }
                }
                CommandGroup(after: .toolbar) {
                    Button("Refresh") {
                        delegate.menuRefresh()
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    static let refreshSignal = RefreshSignal()
    private(set) static var shared: AppDelegate!
#if WHATCABLE_PRO
    private static let licenceIdentifier = NSUserInterfaceItemIdentifier("uk.whatcable.licence")
#endif

    // Menu bar mode
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var isPinned = false

    // Window mode
    private var window: NSWindow?
    private var settingsWindow: NSWindow?

    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSWindow.allowsAutomaticWindowTabbing = false

        // Override the process name so the About panel and menus use the
        // app name even though the SwiftPM executable name might differ.
        ProcessInfo.processInfo.setValue(AppInfo.name, forKey: "processName")

        NotificationManager.shared.start()
        WidgetDataWriter.shared.start()
        UpdateChecker.shared.start()

        applyDisplayMode(menuBar: AppSettings.shared.useMenuBarMode)

        // Live-switch when the user flips the toggle in Settings.
        AppSettings.shared.$useMenuBarMode
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] menuBar in
                self?.applyDisplayMode(menuBar: menuBar)
            }
            .store(in: &cancellables)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // In window mode, closing the window quits the app. In menu bar mode
        // there's no window to close, so this is harmless either way.
        !AppSettings.shared.useMenuBarMode
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
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func setUpMenuBarMode() {
        if popover == nil {
            let p = NSPopover()
            p.behavior = isPinned ? .applicationDefined : .transient
            p.animates = true
            p.contentSize = NSSize(width: 760, height: 540)
            p.contentViewController = NSHostingController(
                rootView: ContentView().environmentObject(Self.refreshSignal)
            )
            p.delegate = self
            popover = p
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = NSImage(systemSymbolName: "cable.connector", accessibilityDescription: AppInfo.name)
                button.target = self
                button.action = #selector(handleClick(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItem = item
        }
    }

    private func tearDownMenuBarMode() {
        if let popover, popover.isShown { popover.performClose(nil) }
        popover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func setUpWindowMode() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(
            rootView: ContentView().environmentObject(Self.refreshSignal)
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
    }

    private func tearDownWindowMode() {
        window?.delegate = nil
        window?.close()
        window = nil
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
            Self.refreshSignal.bump()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(.init(title: String(localized: "Refresh", bundle: .module), action: #selector(menuRefresh), keyEquivalent: "r"))
        let pinItem = NSMenuItem(title: String(localized: "Keep window open", bundle: .module), action: #selector(menuTogglePin), keyEquivalent: "p")
        pinItem.state = isPinned ? .on : .off
        menu.addItem(pinItem)
        menu.addItem(.separator())
        menu.addItem(.init(title: String(localized: "Settings…", bundle: .module), action: #selector(menuSettings), keyEquivalent: ","))
        for builder in PluginRegistry.shared.nsMenuItemBuilders[.statusItemMenu] ?? [] {
            menu.addItem(builder())
        }
        menu.addItem(.init(title: String(localized: "Check for Updates…", bundle: .module), action: #selector(menuCheckUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: String(localized: "About \(AppInfo.name)", bundle: .module), action: #selector(showAboutPanel), keyEquivalent: ""))
        menu.addItem(.init(title: String(localized: "WhatCable on GitHub", bundle: .module), action: #selector(menuHelp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: String(localized: "Quit \(AppInfo.name)", bundle: .module), action: #selector(menuQuit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil && item.target == nil { item.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuTogglePin() {
        isPinned.toggle()
        popover?.behavior = isPinned ? .applicationDefined : .transient
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
        NSApp.activate(ignoringOtherApps: true)
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
        NSApp.activate(ignoringOtherApps: true)
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

    @objc func menuCheckUpdates() {
#if WHATCABLE_PRO
    func showProRequiredAlert() {
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "WhatCable Pro required"
        alert.informativeText = "Power Monitor requires WhatCable Pro."
        alert.window.level = .floating
        alert.runModal()

        NSApp.setActivationPolicy(originalPolicy)
    }
#endif

        UpdateChecker.shared.check(silent: false)
    }

    @objc func menuHelp() {
        NSWorkspace.shared.open(AppInfo.helpURL)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win === settingsWindow {
            settingsWindow = nil
        }
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            Self.refreshSignal.optionHeld = false
            Self.refreshSignal.showSettings = false
        }
    }
}

final class RefreshSignal: ObservableObject {
    @Published var tick: Int = 0
    /// Ephemeral momentary-reveal flag for the advanced IOKit detail view.
    /// Set true while a ⌥-click on the menu bar icon is opening the popover,
    /// cleared when the popover closes. The persistent preference lives on
    /// `AppSettings.showTechnicalDetails`; the effective state is the OR
    /// of the two.
    @Published var optionHeld: Bool = false
    @Published var showSettings: Bool = false

    func bump() { tick &+= 1 }
}
