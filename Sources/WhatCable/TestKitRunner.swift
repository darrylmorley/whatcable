import CryptoKit
import Foundation
import os.log
import WhatCableCore

@MainActor
final class TestKitRunner: ObservableObject {
    static let shared = TestKitRunner()

    private nonisolated static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "test-kit")
    private static let apiURL = "https://whatcable-test-kit.darrylmorley-uk.workers.dev"

    enum State: Equatable {
        case idle
        case running(probe: String, current: Int, total: Int)
        case done(passed: Int, failed: Int)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    static let probeNames: [String] = [
        "01_walk_pd_tree",
        "03_hpm_deep_dive",
        "04_raw_registry_dump",
        "16_transient_props",
        "17_deep_property_dump",
        "19_pdo_decode_and_usb3_watch",
        "21_tb_cfplugin_retimer",
        "25_usb_bos_descriptor",
        "26_displayport_altmode",
        "27_iopower_management",
        "29_usb4_router_interfaces",
        "31_typec_phy_properties",
        "32_smart_battery_full_keys",
        "33_displayport_capability",
    ]

    private init() {}

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func run() {
        guard !isRunning else { return }

        Task {
            await runAllProbes()
        }
    }

    static let autoSendInterval: TimeInterval = 48 * 60 * 60 // 48hrs

    private var autoSendTimer: Timer?
    private var autoSendCatchUpTimer: Timer?


    func refreshAutoSendSchedule(delayInitialRun: Bool = false) {
        autoSendTimer?.invalidate()
        autoSendTimer = nil
        autoSendCatchUpTimer?.invalidate()
        autoSendCatchUpTimer = nil

        guard AppSettings.shared.autoContributeDiagnosticData else { return }

        autoSendTimer = Timer.scheduledTimer(withTimeInterval: Self.autoSendInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runAutomatic() }
        }

        let last = AppSettings.shared.testKitLastAutoRunDate
        let isDue = last.map { Date().timeIntervalSince($0) >= Self.autoSendInterval } ?? true
        guard isDue else { return }

        if delayInitialRun {
            autoSendCatchUpTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.runAutomatic() }
            }
        } else {
            runAutomatic()
        }
    }


    private func runAutomatic() {
        guard AppSettings.shared.autoContributeDiagnosticData else { return }
        guard !isRunning else { return }
        AppSettings.shared.testKitLastAutoRunDate = Date()
        run()
    }

    private func runAllProbes() async {
        let machineID = await Task.detached { Self.machineID() }.value
        let ver = ProcessInfo.processInfo.operatingSystemVersion
        let macosVersion = ver.patchVersion > 0
            ? "\(ver.majorVersion).\(ver.minorVersion).\(ver.patchVersion)"
            : "\(ver.majorVersion).\(ver.minorVersion)"
        let chip = Self.chipName()
        let timestamp = ISO8601DateFormatter().string(from: Date())

        guard let probesDir = Self.probesDirectory() else {
            state = .error("Probe binaries not found in app bundle")
            Self.log.error("Probe binaries directory not found")
            return
        }

        let total = Self.probeNames.count
        var passed = 0
        var failed = 0

        for (index, probeName) in Self.probeNames.enumerated() {
            state = .running(probe: probeName, current: index + 1, total: total)

            let binaryURL = probesDir.appendingPathComponent(probeName)
            guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
                Self.log.warning("Probe binary not found: \(probeName)")
                continue
            }

            let output = await runProbe(at: binaryURL)
            guard let output, !output.isEmpty else {
                Self.log.info("Probe \(probeName) produced no output, skipping")
                continue
            }

            let ok = await submitProbeResult(
                machineID: machineID,
                probeName: probeName,
                output: output,
                macosVersion: macosVersion,
                chip: chip,
                timestamp: timestamp
            )

            if ok {
                passed += 1
            } else {
                failed += 1
            }
        }

        await submitComplete(
            machineID: machineID,
            macosVersion: macosVersion,
            chip: chip,
            passed: passed,
            failed: failed,
            total: total
        )

        state = .done(passed: passed, failed: failed)
        Self.log.info("Test kit complete: \(passed) passed, \(failed) failed")

        AppSettings.shared.testKitLastRunVersion = AppInfo.version
    }

    private func runProbe(at binaryURL: URL) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = binaryURL
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    Self.log.error("Failed to launch probe: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + 30)
                timer.setEventHandler {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                timer.resume()

                process.waitUntilExit()
                timer.cancel()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                continuation.resume(returning: output)
            }
        }
    }

    private func submitProbeResult(
        machineID: String,
        probeName: String,
        output: String,
        macosVersion: String,
        chip: String,
        timestamp: String
    ) async -> Bool {
        let payload: [String: Any] = [
            "machine_id": machineID,
            "probe_name": probeName,
            "output": output,
            "macos_version": macosVersion,
            "chip": chip,
            "timestamp": timestamp,
        ]

        return await postJSON(to: "\(Self.apiURL)/submit", payload: payload)
    }

    private func submitComplete(
        machineID: String,
        macosVersion: String,
        chip: String,
        passed: Int,
        failed: Int,
        total: Int
    ) async {
        let payload: [String: Any] = [
            "machine_id": machineID,
            "macos_version": macosVersion,
            "chip": chip,
            "passed": passed,
            "failed": failed,
            "total": total,
        ]

        _ = await postJSON(to: "\(Self.apiURL)/complete", payload: payload)
    }

    private func postJSON(to urlString: String, payload: [String: Any]) async -> Bool {
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200
        } catch {
            Self.log.error("POST to \(urlString) failed: \(error.localizedDescription)")
            return false
        }
    }

    static func probesDirectory() -> URL? {
        let fm = FileManager.default

        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("probes"),
           fm.fileExists(atPath: bundlePath.path) {
            return bundlePath
        }

        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        let contentsDir = execURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fallback = contentsDir.appendingPathComponent("Resources/probes")
        if fm.fileExists(atPath: fallback.path) {
            return fallback
        }

        return nil
    }

    nonisolated static func machineID() -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-d2", "-c", "IOPlatformExpertDevice"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        var uuid = "unknown"
        for line in output.components(separatedBy: "\n") {
            if line.contains("IOPlatformUUID") {
                let parts = line.components(separatedBy: "\"")
                if parts.count >= 4 {
                    uuid = parts[3]
                }
                break
            }
        }

        let digest = SHA256.hash(data: Data(uuid.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func chipName() -> String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var result = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &result, &size, nil, 0)
        return String(cString: result)
    }
}
