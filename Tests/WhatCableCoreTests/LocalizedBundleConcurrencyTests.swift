import Foundation
import Testing
@testable import WhatCableCore

/// Stress test for the race fix: many concurrent reads of the localized
/// bundle while other tasks flip the locale. Run under ThreadSanitizer to prove
/// there is no data race on the shared global.
///
/// Gated behind an env var because it deliberately mutates the process-wide
/// locale at speed; leaving it in the normal (parallel) suite would let it
/// perturb other tests' localized reads. Run it on its own:
///
///   WHATCABLE_TSAN_STRESS=1 swift test --sanitize=thread \
///     --filter LocalizedBundleConcurrencyTests
///
/// On the pre-fix code (stored `var` global) TSan reports a data race here; on
/// the lock-guarded version it is clean.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["WHATCABLE_TSAN_STRESS"] != nil))
struct LocalizedBundleConcurrencyTests {
    @Test("Concurrent reads during a locale switch do not race")
    func concurrentReadWrite() async {
        defer { setCoreLocale("") }   // restore the default bundle afterwards
        await withTaskGroup(of: Void.self) { group in
            // Writers: flip the locale back and forth.
            for _ in 0..<4 {
                group.addTask {
                    for i in 0..<5000 {
                        setCoreLocale(i.isMultiple(of: 2) ? "fr" : "")
                    }
                }
            }
            // Readers: touch the bundle the same way a localized string would.
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<5000 {
                        _ = _coreLocalizedBundle.bundlePath
                    }
                }
            }
        }
    }
}
