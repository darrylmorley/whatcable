import XCTest
@testable import WhatCableCore

/// Exercises the bundle-walking logic that AppInfo.version uses when
/// Bundle.main can't resolve the .app directly. The two failure modes that
/// shipped to users in v0.5.1 → v0.5.3 were:
///   - CLI in Contents/Helpers/ not finding the parent .app
///   - CLI invoked via Homebrew symlink walking up from /opt/homebrew/bin
/// Both are bundle-path-resolution bugs that fixture tests catch cheaply.
///
/// AppInfo.version is a `let` initialised from Bundle.main, so we can't drive
/// it directly from a test. These tests instead exercise the same algorithm
/// (walk up from a path, find an Info.plist, read CFBundleShortVersionString)
/// against a synthesised bundle on disk. If the algorithm changes in
/// AppInfo.swift, this needs to track it.
final class AppInfoVersionTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WhatCableTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    /// Mirrors the fallback algorithm in AppInfo.version. If you change the
    /// real one, change this one. Both should walk up from a binary path,
    /// resolving symlinks first, looking for a sibling Info.plist with
    /// CFBundleShortVersionString.
    private func resolveVersion(executablePath: String, maxLevels: Int = 4) -> String {
        var dir = URL(fileURLWithPath: executablePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0..<maxLevels {
            let plist = dir.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: plist),
               let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let v = parsed["CFBundleShortVersionString"] as? String {
                return v
            }
            dir = dir.deletingLastPathComponent()
        }
        return "dev"
    }

    private func buildSyntheticBundle(version: String) throws -> URL {
        let app = tempDir.appendingPathComponent("WhatCable.app")
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let helpers = contents.appendingPathComponent("Helpers")
        for d in [macOS, helpers] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        let plist: [String: Any] = ["CFBundleShortVersionString": version]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        // Empty placeholder binaries (we never execute them, just walk paths).
        let mainExe = macOS.appendingPathComponent("WhatCable")
        let cliExe = helpers.appendingPathComponent("whatcable")
        try Data().write(to: mainExe)
        try Data().write(to: cliExe)
        return app
    }

    func testFindsVersionFromContentsMacOS() throws {
        let app = try buildSyntheticBundle(version: "1.2.3")
        let exe = app.appendingPathComponent("Contents/MacOS/WhatCable").path
        XCTAssertEqual(resolveVersion(executablePath: exe), "1.2.3")
    }

    func testFindsVersionFromContentsHelpers() throws {
        // The case that broke v0.5.1: CLI in Helpers/ should still find the
        // bundle by walking one extra level.
        let app = try buildSyntheticBundle(version: "1.2.3")
        let exe = app.appendingPathComponent("Contents/Helpers/whatcable").path
        XCTAssertEqual(resolveVersion(executablePath: exe), "1.2.3")
    }

    func testResolvesSymlinkBeforeWalking() throws {
        // The case that broke v0.5.2: invoking via a symlink outside the
        // bundle should still find the version. Without symlink resolution,
        // walking up from /tmp/.../bin/whatcable would never reach the .app.
        let app = try buildSyntheticBundle(version: "1.2.3")
        let realExe = app.appendingPathComponent("Contents/Helpers/whatcable")

        let binDir = tempDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let link = binDir.appendingPathComponent("whatcable")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realExe)

        XCTAssertEqual(resolveVersion(executablePath: link.path), "1.2.3")
    }

    func testFallsBackToDevWhenNoBundle() throws {
        let exe = tempDir.appendingPathComponent("standalone-binary").path
        try Data().write(to: URL(fileURLWithPath: exe))
        XCTAssertEqual(resolveVersion(executablePath: exe), "dev")
    }

    func testFallsBackToDevWhenInfoPlistHasNoVersion() throws {
        // A bundle structure with an Info.plist that doesn't carry the
        // version key should still fall back rather than crash.
        let app = tempDir.appendingPathComponent("WhatCable.app")
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [String: Any](), format: .xml, options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        let exe = macOS.appendingPathComponent("WhatCable")
        try Data().write(to: exe)

        XCTAssertEqual(resolveVersion(executablePath: exe.path), "dev")
    }
}
