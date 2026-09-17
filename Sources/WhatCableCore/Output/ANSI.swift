import Darwin
import Foundation

/// ANSI color helpers. Disabled automatically when stdout isn't a TTY
/// (piped output, redirected to file) or when NO_COLOR is set -
/// see https://no-color.org for the convention.
public enum ANSI {
    /// Whether stdout is a real terminal. `isatty(3)` returns 0 when stdout is
    /// piped or redirected to a file, which is exactly when colour should stay
    /// off. A `static let` is evaluated lazily and exactly once per process, so
    /// this costs one syscall however much coloured text gets printed, and it
    /// needs no lock.
    private static let stdoutIsTTY = isatty(fileno(stdout)) != 0

    /// Pure decision logic, pulled out of `isEnabled` so tests can exercise
    /// every NO_COLOR / TTY combination directly. Under `swift test` stdout is
    /// redirected, so `stdoutIsTTY` is always false there; this seam is the
    /// only way the TTY branch gets covered.
    static func shouldEnable(isTTY: Bool, noColorSet: Bool) -> Bool {
        if noColorSet { return false }
        return isTTY
    }

    /// Reports whether formatter-owned ANSI sequences may be emitted.
    public static var isEnabled: Bool {
        shouldEnable(
            isTTY: stdoutIsTTY,
            noColorSet: ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        )
    }

    public static let reset = "\u{1B}[0m"
    public static let bold = "\u{1B}[1m"
    public static let dim = "\u{1B}[2m"

    public static let red = "\u{1B}[31m"
    public static let green = "\u{1B}[32m"
    public static let yellow = "\u{1B}[33m"
    public static let blue = "\u{1B}[34m"
    public static let magenta = "\u{1B}[35m"
    public static let cyan = "\u{1B}[36m"
    public static let gray = "\u{1B}[90m"

    /// Wraps text in the supplied ANSI codes when colored output is enabled.
    public static func wrap(_ codes: String, _ text: String) -> String {
        wrap(codes, text, enabled: isEnabled)
    }

    /// Pure rendering seam for tests. Production callers use `wrap(_:_:)`,
    /// which supplies the live TTY/NO_COLOR decision.
    static func wrap(_ codes: String, _ text: String, enabled: Bool) -> String {
        guard enabled else { return text }
        return codes + text + reset
    }
}
