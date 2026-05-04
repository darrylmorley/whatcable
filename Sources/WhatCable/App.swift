import SwiftUI
import AppKit
import WhatCableCore

@main
struct WhatCableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
                .environmentObject(AppDelegate.refreshSignal)
                .frame(minWidth: 760, minHeight: 540)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateChecker.shared.check(silent: false)
                }
            }
            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    AppDelegate.refreshSignal.bump()
                }
                .keyboardShortcut("r")
            }
            CommandGroup(replacing: .help) {
                Button("\(AppInfo.name) on GitHub") {
                    NSWorkspace.shared.open(AppInfo.helpURL)
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let refreshSignal = RefreshSignal()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Override the process name so the About panel and menus use the
        // app name even though the SwiftPM executable name might differ.
        ProcessInfo.processInfo.setValue(AppInfo.name, forKey: "processName")

        NotificationManager.shared.start()
        UpdateChecker.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

final class RefreshSignal: ObservableObject {
    @Published var tick: Int = 0
    func bump() { tick &+= 1 }
}
