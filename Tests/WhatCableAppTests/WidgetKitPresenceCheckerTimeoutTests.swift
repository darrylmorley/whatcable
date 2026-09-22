import Testing
@testable import WhatCable

/// Tests for `withTimeout`, the race helper `WidgetKitPresenceChecker` uses
/// so a hung `WidgetCenter.getCurrentConfigurations` call can never take
/// `WidgetDataWriter`'s heartbeat loop down with it.
///
/// `WidgetDataWriter.performHeartbeatTick()` awaits `refreshPresence()`,
/// which awaits `presenceChecker.hasInstalledWidgets()`, every ~60s for the
/// app's whole life. If `WidgetCenter` ever failed to invoke its completion
/// handler at all, an unbounded `withCheckedContinuation` there would hang
/// that await forever: no more staleness refreshes, no more presence
/// checks, permanently, not just a slow tick.
///
/// These tests drive `withTimeout` directly with a controllable operation
/// rather than depending on WidgetKit's own timing (which cannot be made to
/// hang on demand from a test), and each carries a `.timeLimit` trait so a
/// regression that removes the race fails fast instead of hanging the suite.
@Suite("withTimeout")
struct WidgetKitPresenceCheckerTimeoutTests {

    @Test("Falls back when the operation never completes", .timeLimit(.minutes(1)))
    func fallsBackWhenOperationNeverCompletes() async {
        let result = await withTimeout(.milliseconds(50), fallback: true) {
            // Simulates WidgetCenter's completion handler never firing: a
            // checked continuation that is never resumed by this side.
            await withCheckedContinuation { (_: CheckedContinuation<Bool, Never>) in
                // Deliberately left unresumed.
            }
        }
        #expect(result == true)
    }

    @Test("Falls back when the operation is merely slow, not fast enough for the timeout", .timeLimit(.minutes(1)))
    func fallsBackWhenOperationIsTooSlow() async {
        let result = await withTimeout(.milliseconds(50), fallback: true) {
            try? await Task.sleep(for: .seconds(30))
            return false
        }
        #expect(result == true)
    }

    @Test("Returns the operation's own result when it finishes before the timeout")
    func returnsOperationResultWhenFast() async {
        let result = await withTimeout(.seconds(5), fallback: false) {
            true
        }
        #expect(result == true)
    }

    @Test("The fallback value is returned verbatim, not hardcoded to true", .timeLimit(.minutes(1)))
    func fallbackValueIsUsedVerbatim() async {
        let result = await withTimeout(.milliseconds(20), fallback: 42) {
            // Simulates an operation that never completes, ensuring the
            // timeout always fires regardless of how long the test stalls.
            await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in
                // Deliberately left unresumed.
            }
        }
        #expect(result == 42)
    }
}
