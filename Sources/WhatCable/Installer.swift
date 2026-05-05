import Foundation
import AppKit
import os.log

/// Downloads a new release zip from GitHub, validates its code signature
/// matches the currently running app, and swaps the bundles via a small
/// shell script that waits for this process to exit before doing the move.
@MainActor
final class Installer: ObservableObject {
    static let shared = Installer()
    private nonisolated static let log = Logger(subsystem: "com.bitmoor.whatcable", category: "installer")

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
                try stripQuarantine(at: extractedApp)
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
        try run("/usr/bin/unzip", ["-q", zip.path, "-d", dir.path])

        // Find the first .app at the top of `dir`.
        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError("No .app found inside the downloaded zip")
        }
        return app
    }

    private func stripQuarantine(at url: URL) throws {
        // Best-effort — failure to strip isn't fatal, Gatekeeper will just
        // prompt the user instead of launching silently.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", url.path])
    }

    private func verifySignatureMatches(new: URL, current: URL) throws {
        let newTeam = try teamIdentifier(of: new)
        let currentTeam = try teamIdentifier(of: current)
        if newTeam != currentTeam {
            throw InstallError("Signature mismatch: refusing to install (current \(currentTeam), new \(newTeam))")
        }
        // Also verify the new bundle's signature is structurally valid.
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", new.path])
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

        # Wait up to 30s for the running app to exit
        for _ in $(seq 1 60); do
            if ! kill -0 "$PID" 2>/dev/null; then break; fi
            sleep 0.5
        done

        rm -rf "$OLD"
        mv "$NEW" "$OLD"
        open "$OLD"

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
