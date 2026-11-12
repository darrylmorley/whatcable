import AppKit

/// Remembers a window's position and size across launches (public issue #522),
/// using AppKit's frame autosave under one name per window kind.
///
/// A saved frame is only used while its title bar can still be reached on a
/// connected screen. One saved on a display that has since been unplugged (or
/// that now sits almost entirely off-screen) falls back to the window's
/// default frame, which callers set up (size + centre) before calling `apply`.
@MainActor
enum WindowFrameMemory {

    /// Height of the strip at the top of the frame treated as the title bar.
    static let titleBarHeight: CGFloat = 28
    /// How much of the title bar must sit on one screen for the window to
    /// count as reachable: enough to grab and drag it back.
    static let minimumReachableWidth: CGFloat = 80
    static let minimumReachableHeight: CGFloat = 20

    /// True when `frame` is a usable place to put a window on the screens
    /// whose visible frames are `visibleFrames` (screen coordinates, so a
    /// display left of or below the main one has negative x or y).
    nonisolated static func isUsable(_ frame: NSRect, on visibleFrames: [NSRect]) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let titleBar = NSRect(
            x: frame.minX,
            y: frame.maxY - titleBarHeight,
            width: frame.width,
            height: titleBarHeight
        )
        let needWidth = min(minimumReachableWidth, frame.width)
        return visibleFrames.contains { screen in
            let overlap = titleBar.intersection(screen)
            return !overlap.isNull
                && overlap.width >= needWidth
                && overlap.height >= minimumReachableHeight
        }
    }

    /// The window frame inside an AppKit saved-frame string (the value of the
    /// `NSWindow Frame <name>` default): its first four numbers are the
    /// window's x, y, width and height; the rest describe the screen it was
    /// saved on. Nil when the string doesn't start with four numbers.
    nonisolated static func savedWindowFrame(from descriptor: String) -> NSRect? {
        let numbers = descriptor.split(whereSeparator: \.isWhitespace).prefix(4).compactMap { Double($0) }
        guard numbers.count == 4 else { return nil }
        return NSRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    /// Restore the frame saved under `name` if it is usable on `visibleFrames`,
    /// otherwise keep the window's current (default) frame, then start
    /// autosaving moves and resizes under `name`.
    ///
    /// Returns false when `name` could not be claimed because another open
    /// window already holds it (AppKit allows one window per autosave name):
    /// that window keeps its default frame and is not remembered.
    @discardableResult
    static func apply(
        to window: NSWindow,
        autosaveName name: String,
        visibleFrames: [NSRect] = NSScreen.screens.map(\.visibleFrame)
    ) -> Bool {
        // `setFrameAutosaveName` restores any frame saved under the name, and
        // AppKit shifts one from a missing display onto a remaining screen at
        // its old size and offset rather than the centred default. So decide
        // on the frame as saved, and drop it first when it is unusable.
        if let descriptor = UserDefaults.standard.string(forKey: "NSWindow Frame \(name)"),
           let saved = savedWindowFrame(from: descriptor),
           !isUsable(saved, on: visibleFrames) {
            NSWindow.removeFrame(usingName: name)
        }
        return window.setFrameAutosaveName(name)
    }

    /// Give the autosave name back when the window goes away, so the next
    /// window of the same kind can claim it within this launch (switching
    /// between menu bar and window mode, or reopening a Pro window).
    static func release(_ window: NSWindow) {
        if !window.frameAutosaveName.isEmpty {
            window.saveFrame(usingName: window.frameAutosaveName)
            window.setFrameAutosaveName("")
        }
    }
}
