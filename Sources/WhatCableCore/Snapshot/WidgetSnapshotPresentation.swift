import Foundation

// Presentation helpers for the desktop widget's port rows.
//
// These live in WhatCableCore, not in the widget target, deliberately. The
// widget is built by xcodebuild and is not a target in Package.swift, so
// nothing under Tests/ can import it: any logic that lives there is untestable
// by `swift test`. That is not hypothetical. `rowDetail` silently stopped
// showing `topBullet` in the #181 widget redesign and shipped that way from
// v0.14.0, because no test could see the render path. Anything expressible as
// a plain function over a PortEntry belongs here.
extension WidgetSnapshot.PortEntry {
    /// Muted detail line: monitor + mode for a display, else the accessory's
    /// own name, else the port's own top line, else the subtitle.
    ///
    /// `topBullet` is the specific fact about this port (what the Mac
    /// measured: "Linked at up to 40 Gb/s x 2"). The subtitle is generic
    /// wording shared by every port in the same state ("SuperSpeed data link
    /// is active."), so it is the last resort, not the second choice.
    ///
    /// It was dropped here by mistake: the #181 widget redesign rewrote these
    /// row views and did not carry `topBullet` across, so from v0.14.0 every
    /// non-display row showed the generic sentence instead of the real
    /// figure. The value was still computed, written to the shared container
    /// and decoded here the whole time; only the render was missing, which is
    /// why nothing failed. Pinned by `rowDetailPrefersTopBullet` below.
    /// `public` because the widget target imports WhatCableCore and calls this
    /// across a module boundary. It was `internal` when it lived inside the
    /// widget, and moving it here without widening access broke the widget
    /// build while `swift build` and `swift test` both stayed green: the
    /// widget is not an SPM target, and the tests use `@testable import`,
    /// which ignores access control. Two reviewers caught it by compiling the
    /// widget scheme, which is the only thing that can.
    ///
    /// `displayDetail` below deliberately stays internal: only this property
    /// calls it, so publishing it would widen the library's API for nothing.
    public var rowDetail: String? {
        if let detail = displayDetail { return detail }
        // Apple's own name for the accessory outranks the measured line: on an
        // iPhone over USB 2 the top line is "USB 2.0 only (480 Mbps)", which
        // says nothing about what is attached. A display keeps priority above,
        // because its mode is the point of that row and its name is in it.
        if let accessoryName, !accessoryName.isEmpty { return accessoryName }
        if let topBullet, !topBullet.isEmpty { return topBullet }
        return subtitle.isEmpty ? nil : subtitle
    }

    /// One-line display detail: "Studio Display · 5K 60Hz", or just the mode
    /// when the monitor name is unknown. Nil when no display. When a dock drives
    /// more than one monitor through this port, a "+N" hint is appended for the
    /// others, since the card has room for one line only (issue #271).
    var displayDetail: String? {
        let base: String?
        if let mode = displayMode {
            if let name = monitorName, !name.isEmpty {
                base = "\(name) · \(mode)"
            } else {
                base = mode
            }
        } else {
            base = monitorName
        }
        guard let base, !base.isEmpty else { return nil }
        return displayCount > 1 ? "\(base) +\(displayCount - 1)" : base
    }

}
