import AppKit
import SwiftUI
import WhatCableAppKit
import WhatCableCore
import WhatCableDarwinBackend

/// Hosts a Pro screen in its own standalone window when the user taps
/// "detach" in the popover. In-place rendering stays the default; this is
/// an opt-in, user-triggered escape hatch so a diagnostics screen can
/// stay open while cables are plugged and unplugged. It reuses the exact
/// same view `PluginRegistry` builds for in-place rendering, so detached
/// and in-place content are identical. This is NOT the old auto-spawning
/// behaviour: a window only appears when the user asks for it.
@MainActor
final class DetachedProWindowManager: NSObject, NSWindowDelegate {
    static let shared = DetachedProWindowManager()
    private override init() { super.init() }

    private var windows: [String: NSWindow] = [:]

    /// Open the route's Pro screen in a standalone window, or focus the
    /// existing one if it's already detached.
    func open(route: ProScreenRoute) {
        let key = Self.key(for: route)
        if let existing = windows[key] {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        guard let screen = PluginRegistry.shared.proScreen(id: route.id, portCard: route.portCard) else {
            return
        }
        let window = Self.makeWindow(for: screen, title: Self.title(for: route))
        window.identifier = NSUserInterfaceItemIdentifier(key)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        // Remember position and size per screen kind (issue #522). Cable
        // Diagnostics shares one name across ports: while one is open a second
        // can't claim it and opens at the centred default.
        WindowFrameMemory.apply(to: window, autosaveName: Self.autosaveName(for: route))
        windows[key] = window
        // Tell the hub this surface is on screen so its shared watchers poll at
        // the active 1 Hz cadence (not the 30 s idle one) for as long as this
        // detached window is open. The Pro screens now read the hub's shared
        // watchers, so without this a popped-out screen would update only every
        // 30 seconds when the popover is closed. Per-window token, so each
        // detached window reports independently. Occlusion changes and close
        // refine/clear it below.
        WatcherHub.shared.setSurfaceVisible(true, surface: key)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Build the window for a detached Pro screen without showing it. Split
    /// out of `open(route:)` so the sizing tests drive the same host and
    /// window setup the app does.
    static func makeWindow(for screen: AnyView, title: String) -> NSWindow {
        // Inject the same fontScale environment the popover uses so the
        // Settings slider affects detached Pro screens too. The wrapper
        // observes `FontScaleStore`, so moving the slider with a window
        // open updates it live.
        //
        // The floor is 520 x 420 scaled by the Settings font slider (read
        // when the window opens), or the screen's own minimum where that is
        // larger (`minimumFloor`), so large text keeps room and a screen that
        // declares no minimum (Pro Overview) can't shrink to nothing. The
        // frame lets the screen fill the window and pins it to the top.
        // Without it, a screen with no max height (Negotiation, Display) pins
        // the window's max size to its fitting height, so it can't be made
        // taller, and a shorter screen is centred in the window (issue #600).
        let scale = AppSettings.shared.fontSize
        let host = NSHostingController(rootView: ScaledHost {
            screen
                .minimumFloor(width: 520 * scale, height: 420 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        })
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // The initial size scales with the Settings font slider so the window
        // opens at a sensible width for the current text scale. There is no
        // NSWindow minSize: the hosting controller floors the window at the
        // SwiftUI minimum above, and a minSize here (a frame size, title bar
        // included) set the floor 32pt below the screen's own.
        window.setContentSize(NSSize(width: 620 * scale, height: 680 * scale))
        return window
    }

    /// If a window for this route is already detached, focus it and
    /// return true so the caller can skip rendering it in-place too.
    func focusIfOpen(route: ProScreenRoute) -> Bool {
        guard let existing = windows[Self.key(for: route)] else { return false }
        NSApp.activate()
        existing.makeKeyAndOrderFront(nil)
        return true
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard let w = notification.object as? NSWindow,
                  let id = w.identifier?.rawValue else { return }
            WindowFrameMemory.release(w)
            windows[id] = nil
            // Drop this surface's visibility token. The hub goes idle only once
            // every surface (popover/window and all detached windows) is gone.
            WatcherHub.shared.setSurfaceVisible(false, surface: id)
        }
    }

    /// Follow each detached window's real on-screen visibility, mirroring how
    /// the main window reports occlusion. Miniaturising or fully covering a
    /// detached window lets the hub fall back to idle if nothing else is shown;
    /// revealing it brings the active cadence back.
    nonisolated func windowDidChangeOcclusionState(_ notification: Notification) {
        Task { @MainActor in
            guard let w = notification.object as? NSWindow,
                  let id = w.identifier?.rawValue,
                  windows[id] != nil else { return }
            WatcherHub.shared.setSurfaceVisible(w.occlusionState.contains(.visible), surface: id)
        }
    }

    /// Cable Diagnostics is per-port, so its key includes the port to
    /// allow one detached window per port. The other screens are global.
    private static func key(for route: ProScreenRoute) -> String {
        var k = "uk.whatcable.detached.\(route.id)"
        if let portKey = route.portCard?.portKey {
            k += ".\(portKey)"
        }
        return k
    }

    /// One autosave name per screen kind, not per port.
    static func autosaveName(for route: ProScreenRoute) -> String {
        "uk.whatcable.detached.\(route.id).frame"
    }

    private static func title(for route: ProScreenRoute) -> String {
        switch route.id {
        case "pro.power-monitor":
            return String(localized: "Power Monitor", bundle: _coreLocalizedBundle)
        case "pro.negotiation":
            return String(localized: "Negotiation Diagnostics", bundle: _coreLocalizedBundle)
        case "pro.cable-diagnostics":
            let num = route.portCard?.portNumber ?? 0
            if let type = route.portCard?.portTypeDescription {
                return String(localized: "\(type) Port \(num) Diagnostics", bundle: _coreLocalizedBundle)
            }
            return String(localized: "Cable Diagnostics", bundle: _coreLocalizedBundle)
        case "pro.overview":
            return String(localized: "WhatCable Pro", bundle: _coreLocalizedBundle)
        default:
            return "WhatCable"
        }
    }
}
