import SwiftUI
import AppKit
import Combine
import WhatCableCore

@main
struct WhatCableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Headless — UI is owned by AppDelegate (status item + popover, or
        // a regular window, depending on AppSettings.useMenuBarMode).
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About \(AppInfo.name)") {
                        delegate.showAboutPanel()
                    }
                }
                #if !WHATCABLE_MAS
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") {
                        UpdateChecker.shared.check(silent: false)
                    }
                }
                #endif
                CommandGroup(replacing: .help) {
                    Button("WhatCable on GitHub") {
                        NSWorkspace.shared.open(AppInfo.helpURL)
                    }
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") {
                        delegate.showSettingsPanel(nil)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    static let refreshSignal = RefreshSignal()

    // Menu bar mode
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var isPinned = false

    // Window mode
    private var window: NSWindow?

    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Override the process name so the About panel and menus use the
        // app name even though the SwiftPM executable name might differ.
        ProcessInfo.processInfo.setValue(AppInfo.name, forKey: "processName")

        NotificationManager.shared.start()
        #if !WHATCABLE_MAS
        UpdateChecker.shared.start()
        #endif

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
        menu.addItem(.init(title: "Refresh", action: #selector(menuRefresh), keyEquivalent: "r"))
        let pinItem = NSMenuItem(title: "Keep window open", action: #selector(menuTogglePin), keyEquivalent: "p")
        pinItem.state = isPinned ? .on : .off
        menu.addItem(pinItem)
        menu.addItem(.separator())
        menu.addItem(.init(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ","))
        #if !WHATCABLE_MAS
        menu.addItem(.init(title: "Check for Updates…", action: #selector(menuCheckUpdates), keyEquivalent: ""))
        #endif
        menu.addItem(.separator())
        menu.addItem(.init(title: "About \(AppInfo.name)", action: #selector(showAboutPanel), keyEquivalent: ""))
        menu.addItem(.init(title: "WhatCable on GitHub", action: #selector(menuHelp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: "Quit \(AppInfo.name)", action: #selector(menuQuit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuTogglePin() {
        isPinned.toggle()
        popover?.behavior = isPinned ? .applicationDefined : .transient
    }

    @objc private func menuRefresh() {
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
            string: "\(AppInfo.tagline)\n\nBuilt by \(AppInfo.credit).",
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

    #if !WHATCABLE_MAS
    @objc private func menuCheckUpdates() {
        UpdateChecker.shared.check(silent: false)
    }
    #endif

    @objc private func menuHelp() {
        NSWorkspace.shared.open(AppInfo.helpURL)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
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
