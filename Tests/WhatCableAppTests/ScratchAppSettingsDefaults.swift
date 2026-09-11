import Foundation
@testable import WhatCable

/// Runs `body` with `AppSettings.shared.defaults` pointed at a throwaway,
/// per-call UserDefaults suite, then restores the original and discards the
/// suite. `AppSettings.shared`'s persisted keys otherwise live in
/// `UserDefaults.standard`, which every `swift test` process on this machine
/// shares (the test runner's own bundle id, not the app's, so it is the same
/// domain whichever SPM package is running), so two concurrent runs can flip
/// each other's settings mid snapshot-and-assert window. Mirrors the
/// `withScratchSuite` pattern `Tests/WhatCablePluginsTests/LicenceManagerTests.swift`
/// already uses for `LicenceManager.defaults`.
@MainActor
func withScratchAppSettingsDefaults<T>(_ body: () throws -> T) rethrows -> T {
    let name = "uk.whatcable.whatcable.tests.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    let settings = AppSettings.shared
    let original = settings.defaults
    settings.defaults = suite
    defer {
        settings.defaults = original
        suite.removePersistentDomain(forName: name)
        deleteAppSettingsTestDefaultsDomain(named: name)
    }
    return try body()
}

/// Shells out to `/usr/bin/defaults delete <name>` and waits for it to exit,
/// up to a 5 second bound: the step that makes cfprefsd actually forget the
/// domain (`removePersistentDomain` alone does not; see
/// `LicenceManagerTests.deleteDefaultsDomain`'s doc comment for the
/// measurement behind that). Best effort: an already-empty domain exits
/// non-zero, which is ignored, since the goal is met either way.
private func deleteAppSettingsTestDefaultsDomain(named name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["delete", name]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
    } catch {
        // Best effort only; removePersistentDomain above still ran.
    }
}
