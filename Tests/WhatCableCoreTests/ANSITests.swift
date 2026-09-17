import Testing
@testable import WhatCableCore

/// Tests the pure `shouldEnable` decision logic only, not `isEnabled`
/// directly. `isEnabled` reads `stdoutIsTTY`, which captures the real
/// process's actual stdout state once at first access - under `swift test`
/// that is always false, since stdout is redirected. `shouldEnable` takes
/// both inputs as plain parameters, so it exercises the exact same logic
/// without depending on the real environment.
@Suite("ANSI color decision")
struct ANSITests {
    @Test("Colour is on when stdout is a TTY and NO_COLOR is not set")
    func colorOnWhenTTYAndNoColorUnset() {
        #expect(ANSI.shouldEnable(isTTY: true, noColorSet: false))
    }

    @Test("Colour is off when stdout is not a TTY")
    func colorOffWhenNotTTY() {
        #expect(ANSI.shouldEnable(isTTY: false, noColorSet: false) == false)
    }

    @Test("Colour is off when NO_COLOR is set, even on a TTY")
    func colorOffWhenNoColorSet() {
        #expect(ANSI.shouldEnable(isTTY: true, noColorSet: true) == false)
    }

    @Test("Colour is off when neither a TTY nor NO_COLOR set is true")
    func colorOffWhenNeitherTrue() {
        #expect(ANSI.shouldEnable(isTTY: false, noColorSet: true) == false)
    }

    @Test("Encoded hardware fields remain safe with and without formatter ANSI")
    func encodedFieldsRemainSafeAcrossTTYModes() {
        let unsafe = "Dock\u{1B}]0;forged\u{7}\n显示器"
        let encoded = TerminalFieldEncoder.encode(unsafe)
        let expected = #"Dock\u{1B}]0;forged\u{7}\u{A}显示器"#

        #expect(ANSI.wrap(ANSI.red, encoded, enabled: false) == expected)
        #expect(
            ANSI.wrap(ANSI.red, encoded, enabled: true)
                == ANSI.red + expected + ANSI.reset
        )
    }
}
