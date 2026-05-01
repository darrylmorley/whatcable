import SwiftUI
import AppKit

@main
struct WhatCableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Headless — UI is owned by AppDelegate's NSStatusItem + NSPopover.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    static let refreshSignal = RefreshSignal()
    private var isPinned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Override the process name so the About panel and menu bar use the
        // app name even though the SwiftPM executable name might differ.
        ProcessInfo.processInfo.setValue(AppInfo.name, forKey: "processName")

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 760, height: 540)
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(Self.refreshSignal)
        )
        popover.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cable.connector", accessibilityDescription: AppInfo.name)
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            Self.refreshSignal.bump()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(.init(title: "Refresh", action: #selector(menuRefresh), keyEquivalent: "r"))
        let pinItem = NSMenuItem(title: "Keep window open", action: #selector(menuTogglePin), keyEquivalent: "p")
        pinItem.state = isPinned ? .on : .off
        menu.addItem(pinItem)
        menu.addItem(.separator())
        menu.addItem(.init(title: "About \(AppInfo.name)", action: #selector(menuAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(.init(title: "Quit \(AppInfo.name)", action: #selector(menuQuit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuTogglePin() {
        isPinned.toggle()
        popover.behavior = isPinned ? .applicationDefined : .transient
    }

    @objc private func menuRefresh() {
        Self.refreshSignal.bump()
    }

    @objc private func menuAbout() {
        Self.showAboutPanel()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    static func showAboutPanel() {
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
}

final class RefreshSignal: ObservableObject {
    @Published var tick: Int = 0
    func bump() { tick &+= 1 }
}
