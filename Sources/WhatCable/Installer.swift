// In-process installer for the OSS self-update path. Compiled out of
// the Mac App Store build (`WHATCABLE_MAS`) since the App Store handles
// install/upgrade itself and `AvailableUpdate` (declared in
// `UpdateChecker.swift`) is also gated out.
#if !WHATCABLE_MAS
import Foundation
import AppKit
import os.log

/// Downloads a new release zip from GitHub, validates its code signature
/// matches the currently running app, and swaps the bundles via a small
/// shell script that waits for this process to exit before doing the move.
@MainActor
final class Installer: ObservableObject {
    static let shared = Installer()
    private nonisolated static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "installer")
    private static let expectedBundleID = "uk.whatcable.whatcable"

    enum State: Equatable {
        case idle
        case downloading
        case verifying
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private init() {}

    func install(_ update: AvailableUpdate) {
        guard case .idle = state else { return }
        guard let downloadURL = update.downloadURL else {
            state = .failed("No download asset for this release")
            return
        }
        state = .downloading

        Task {
            var workDir: URL?
            do {
                workDir = try makeWorkDir()
                let zipURL = try await download(from: downloadURL, into: workDir!)

                state = .verifying
                let extractedApp = try unzipAndLocate(zip: zipURL, in: workDir!)
                try verifySignatureMatches(new: extractedApp, current: Bundle.main.bundleURL)

                state = .installing
                try launchSwapScript(newApp: extractedApp, currentApp: Bundle.main.bundleURL)

                // Give the script a moment to start before we quit.
                try await Task.sleep(nanoseconds: 250_000_000)
                NSApp.terminate(nil)
            } catch {
                if let workDir {
                    try? FileManager.default.removeItem(at: workDir)
                }
                Self.log.error("Install failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Steps

    private func makeWorkDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whatcable-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func download(from url: URL, into dir: URL) async throws -> URL {
        let (tmpURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError("Download failed with HTTP \(http.statusCode)")
        }
        let dest = dir.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }

    private func unzipAndLocate(zip: URL, in dir: URL) throws -> URL {
        try validateZipEntries(zip)
        try run("/usr/bin/unzip", ["-q", zip.path, "-d", dir.path])

        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let apps = contents.filter { $0.pathExtension == "app" }
        guard apps.count == 1, apps[0].lastPathComponent == "WhatCable.app" else {
            throw InstallError("Expected exactly one WhatCable.app in the downloaded zip")
        }
        return apps[0]
    }

    // Check zip entries for path traversal or absolute paths before extracting.
    private func validateZipEntries(_ zip: URL) throws {
        let output = try captureOutput("/usr/bin/unzip", ["-Z1", zip.path])
        for entry in output.split(separator: "\n") {
            let path = String(entry)
            if path.hasPrefix("/") || path.contains("../") || path.contains("/..") {
                throw InstallError("Zip contains unsafe path: \(path)")
            }
        }
    }

    private func verifySignatureMatches(new: URL, current: URL) throws {
        // Check team identifier matches.
        let newTeam = try teamIdentifier(of: new)
        let currentTeam = try teamIdentifier(of: current)
        if newTeam != currentTeam {
            throw InstallError("Signature mismatch: refusing to install (current \(currentTeam), new \(newTeam))")
        }
        // Check bundle ID is exactly what we expect.
        let bundleID = Bundle(url: new)?.bundleIdentifier ?? ""
        if bundleID != Self.expectedBundleID {
            throw InstallError("Unexpected bundle identifier: \(bundleID)")
        }
        // Verify signature structure is valid.
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", new.path])
        // Verify Gatekeeper / notarization acceptance.
        try run("/usr/sbin/spctl", ["--assess", "--type", "execute", new.path])
        // Strip quarantine only after all checks pass.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", new.path])
    }

    private func teamIdentifier(of app: URL) throws -> String {
        let output = try captureOutput("/usr/bin/codesign", ["-dvv", app.path])
        for line in output.split(separator: "\n") {
            if line.hasPrefix("TeamIdentifier=") {
                return String(line.dropFirst("TeamIdentifier=".count))
            }
        }
        throw InstallError("Could not read TeamIdentifier from \(app.lastPathComponent)")
    }

    private func launchSwapScript(newApp: URL, currentApp: URL) throws {
        let script = """
        #!/bin/bash
        set -e
        PID=\(ProcessInfo.processInfo.processIdentifier)
        NEW=\(shellQuote(newApp.path))
        OLD=\(shellQuote(currentApp.path))
        BACKUP="${OLD}.backup"

        # Wait up to 30s for the running app to exit
        for _ in $(seq 1 60); do
            if ! kill -0 "$PID" 2>/dev/null; then break; fi
            sleep 0.5
        done

        # Move old bundle to backup instead of deleting it.
        # If the swap fails, the user can rename .backup back.
        rm -rf "$BACKUP"
        mv "$OLD" "$BACKUP"

        if mv "$NEW" "$OLD"; then
            open "$OLD"
            sleep 2
            rm -rf "$BACKUP"
        else
            # Swap failed; remove any partial destination before restoring.
            rm -rf "$OLD"
            mv "$BACKUP" "$OLD"
            open "$OLD"
        fi

        # Clean up this script and the temp directory.
        rm -rf "$(dirname "$0")"
        rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whatcable-swap-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path]
        // Detach stdio so the child survives our exit cleanly.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        try task.run()
    }

    // MARK: - Process helpers

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let result = try captureOutput(launchPath, arguments)
        return result
    }

    private func captureOutput(_ launchPath: String, _ arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            throw InstallError("\(launchPath) failed (\(task.terminationStatus)): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct InstallError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { self.errorDescription = message }
}

#endif // !WHATCABLE_MAS

