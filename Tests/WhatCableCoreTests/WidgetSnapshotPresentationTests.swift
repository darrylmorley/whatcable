import Foundation
import Testing
// A plain import, NOT `@testable`, and that is the point of this file as much
// as any assertion in it.
//
// `@testable` ignores access control, so these tests would happily compile
// against an `internal` `rowDetail` while the widget, a real separate module,
// could not see it at all. That is exactly the bug this suite was written
// after: the property moved into WhatCableCore without `public`, the widget
// stopped compiling, and `swift test` stayed green.
//
// Importing normally means the test target sees the same API surface the
// widget does, so `swift test` alone now fails if `public` is ever dropped.
// The widget-build job in scripts/ci.sh is the belt; this is the braces, and
// it costs nothing.
import WhatCableCore

/// The desktop widget's row detail line.
///
/// This suite exists because the line silently disappeared. The #181 widget
/// redesign (2026-05-28, shipped in v0.14.0) rewrote the row views and did not
/// carry `topBullet` across, so every non-display row showed a generic
/// sentence instead of the port's actual state, for ten weeks. Nothing failed,
/// because the widget target is built by xcodebuild rather than SwiftPM, so no
/// test could reach the render path at all.
///
/// The properties now live in WhatCableCore for that reason. These tests are
/// the guard that was missing.
@Suite("Widget row presentation")
struct WidgetSnapshotPresentationTests {

    private func port(
        topBullet: String? = nil,
        subtitle: String = "",
        displayMode: String? = nil,
        monitorName: String? = nil,
        displayCount: Int = 0,
        accessoryName: String? = nil
    ) -> WidgetSnapshot.PortEntry {
        WidgetSnapshot.PortEntry(
            id: 1,
            portName: "Port-USB-C@1",
            status: .dataDevice,
            headline: "USB device",
            subtitle: subtitle,
            topBullet: topBullet,
            iconName: "cable.connector",
            deviceCount: 0,
            recentPower: [],
            portKey: nil,
            chargerWatts: nil,
            linkSpeed: nil,
            displayMode: displayMode,
            monitorName: monitorName,
            displayCount: displayCount,
            accessoryName: accessoryName
        )
    }

    /// The regression itself. A port with a real measured line must show that
    /// line, not the generic sentence every port in the same state shares.
    @Test("The row shows the port's own top line, not the generic subtitle")
    func rowDetailPrefersTopBullet() {
        let p = port(
            topBullet: "Linked at up to 40 Gb/s x 2",
            subtitle: "SuperSpeed data link is active."
        )
        #expect(p.rowDetail == "Linked at up to 40 Gb/s x 2")
    }

    /// A display keeps priority. "Studio Display · 5K 60Hz" is more use on a
    /// widget than the link speed, and that ordering predates the regression.
    @Test("A display still outranks the top line")
    func displayDetailStillWins() {
        let p = port(
            topBullet: "Linked at up to 40 Gb/s x 2",
            subtitle: "Carrying both data and DisplayPort video.",
            displayMode: "5K 60Hz",
            monitorName: "Studio Display",
            displayCount: 1
        )
        #expect(p.rowDetail == "Studio Display · 5K 60Hz")
    }

    /// The subtitle is the last resort, not the second choice.
    @Test("With no top line, the subtitle is still used")
    func fallsBackToSubtitle() {
        let p = port(subtitle: "SuperSpeed data link is active.")
        #expect(p.rowDetail == "SuperSpeed data link is active.")
    }

    /// An empty string is not a detail line. Older snapshots on disk can carry
    /// one, and the App Group cache survives an app update, so a widget can
    /// decode a stale entry written by a previous version.
    @Test("An empty top line is skipped, not rendered blank")
    func emptyTopBulletIsSkipped() {
        let p = port(topBullet: "", subtitle: "SuperSpeed data link is active.")
        #expect(p.rowDetail == "SuperSpeed data link is active.")
    }

    @Test("Nothing to say means no detail line at all")
    func nilWhenNothingToShow() {
        #expect(port().rowDetail == nil)
    }

    /// Multi-monitor suffix, from issue #271. Unchanged by this fix; pinned
    /// here because it now lives in a testable place for the first time.
    @Test("A dock driving two displays appends the overflow hint")
    func multipleDisplaysAppendCount() {
        let p = port(displayMode: "4K 60Hz", monitorName: "Dell U2720Q", displayCount: 2)
        #expect(p.rowDetail == "Dell U2720Q · 4K 60Hz +1")
    }

    /// The accessory's own name beats the link-speed line. An iPhone on USB 2
    /// showed "USB 2.0 only (480 Mbps), no high-speed data", which says nothing
    /// about what is attached.
    @Test("The row shows the accessory's own name ahead of the top line")
    func rowDetailPrefersAccessoryName() {
        let p = port(
            topBullet: "USB 2.0 only (480 Mbps), no high-speed data",
            subtitle: "USB 2.0 data link is active.",
            accessoryName: "iPhone"
        )
        #expect(p.rowDetail == "iPhone")
    }

    /// A display keeps priority over the accessory name too: the mode is the
    /// thing a display row is for, and the monitor name is already in it.
    @Test("A display still outranks the accessory name")
    func displayDetailOutranksAccessoryName() {
        let p = port(
            subtitle: "Carrying both data and DisplayPort video.",
            displayMode: "5K 60Hz",
            monitorName: "Studio Display",
            displayCount: 1,
            accessoryName: "Studio Display"
        )
        #expect(p.rowDetail == "Studio Display · 5K 60Hz")
    }
}
