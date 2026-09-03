import XCTest
import AppKit
import SwiftUI
import WhatCableAppKit
@testable import WhatCable

/// The welcome window takes its size from `WelcomeView`'s fitting size, because
/// `NSHostingController`'s default sizing options pin the window's
/// `contentMinSize` and `contentMaxSize` to it. That makes the fitting size the
/// thing to guard: while `WelcomeView` had a hardcoded `height: 480`, the
/// fitting size was 480 at every font scale and in every language, so anything
/// the content needed beyond that was cut off by the window edge (the app icon
/// at the top, "Get Started" at the bottom).
final class WelcomeWindowSizingTests: XCTestCase {

    @MainActor
    private func fittingHeight(scale: Double) -> CGFloat {
        FontScaleStore.shared.fontScale = scale
        let host = NSHostingController(
            rootView: ScaledHost {
                WelcomeView(useMenuBarInitially: true, onComplete: { _ in })
            }
        )
        return host.view.fittingSize.height
    }

    @MainActor
    func testContentHeightGrowsWithFontScale() {
        _ = NSApplication.shared
        defer { FontScaleStore.shared.fontScale = 1.0 }

        let smallest = fittingHeight(scale: 0.8)
        let largest = fittingHeight(scale: 1.4)

        // Never shorter than the original window, so the small end of the
        // slider keeps the screen's proportions.
        XCTAssertGreaterThanOrEqual(
            smallest, 480,
            "welcome content should never ask for less than the original 480pt"
        )

        // The top of the slider makes every scaled font bigger, so the content
        // must ask for meaningfully more room. A hardcoded frame height reports
        // the same number at both ends, which is exactly the bug.
        XCTAssertGreaterThan(
            largest,
            smallest + 40,
            "welcome content height must track the font-size slider, got \(smallest) at 0.8 and \(largest) at 1.4"
        )
    }

    /// Every step of the slider must make the content taller.
    ///
    /// This is deliberately a strict increase, not "never goes backwards". A
    /// non-decreasing check passes on the very bug being guarded: with the old
    /// hardcoded `height: 480` every scale reports 480, and a constant series
    /// is trivially non-decreasing, so the test would certify the bug as fine.
    ///
    /// Strict is safe here. Measured across all 19 shipped locales x all 7
    /// slider steps, all 19 give 7 distinct, strictly increasing heights. Note
    /// that the test itself only ever runs the process-default locale (en) and
    /// never calls `setAppLocale`, so that 19-locale agreement is a safety
    /// margin rather than something this test exercises.
    ///
    /// What strictness is actually exposed to is the `minHeight: 480` floor in
    /// `WelcomeView`, not the size of the steps: two adjacent scales that both
    /// land on the floor would each report 480 and tie. Only one cell of the
    /// 133 is genuinely clamped today (ko at 0.8, natural height 472, reported
    /// 480), every other locale sits at 482 there, and the next lowest cell is
    /// ko at 0.9 on 490, so there is roughly 10pt of room. The risk is
    /// one-directional: it can only appear if the copy gets SHORTER. So if you
    /// have just trimmed a string and are looking at a failure reading
    /// "480.0 then 480.0", that is two scales meeting this floor, not a
    /// regression of the window-sizing fix. A tie fails loudly and
    /// deterministically, it does not flake.
    @MainActor
    func testContentHeightStrictlyIncreasesWithFontScale() {
        _ = NSApplication.shared
        defer { FontScaleStore.shared.fontScale = 1.0 }

        var previous: CGFloat = 0
        var previousScale: Double = 0
        for scale in [0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4] {
            let height = fittingHeight(scale: scale)
            XCTAssertGreaterThan(
                height, previous,
                "content height must grow from scale \(previousScale) to \(scale), got \(previous) then \(height)"
            )
            previous = height
            previousScale = scale
        }
    }
}
