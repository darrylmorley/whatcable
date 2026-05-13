#if WHATCABLE_PRO
import Foundation
import WhatCableProFeatures

@MainActor
func runPowerMonitor(asJSON: Bool) async {
    guard LicenceManager.shared.isUnlocked else {
        print("whatcable --monitor requires WhatCable Pro. Visit whatcable.uk to purchase.")
        exit(1)
    }

    let watcher = PowerTelemetryWatcher()
    let monitorTask = Task { @MainActor in
        watcher.start()
        defer { watcher.stop() }

        let encoder = JSONEncoder()
        for await snapshot in watcher.snapshots {
            if Task.isCancelled { return }

            if asJSON {
                do {
                    let data = try encoder.encode(snapshot)
                    if let line = String(data: data, encoding: .utf8) {
                        print(line)
                    }
                } catch {
                    FileHandle.standardError.write(Data("whatcable: json encoding failed: \(error)\n".utf8))
                }
            } else {
                print("\u{1B}[2J\u{1B}[H", terminator: "")
                print(renderPowerMonitor(snapshot))
            }
            fflush(stdout)
        }
    }

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    intSrc.setEventHandler { monitorTask.cancel() }
    intSrc.resume()

    let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termSrc.setEventHandler { monitorTask.cancel() }
    termSrc.resume()

    await monitorTask.value

    intSrc.cancel()
    termSrc.cancel()
    signal(SIGINT, SIG_DFL)
    signal(SIGTERM, SIG_DFL)
    if !asJSON {
        print("\u{1B}[0m", terminator: "")
    }
    fflush(stdout)
}

private func renderPowerMonitor(_ snapshot: PowerMonitorSnapshot) -> String {
    var lines = ["WhatCable Pro -- Power Monitor  (Ctrl-C to stop)", ""]
    var activeLines: [String] = []
    for sample in snapshot.portSamples where isActive(sample) {
        activeLines.append(renderPortLine(portIndex: sample.portIndex, sample: sample, estimate: snapshot.resistanceEstimate))
    }
    if activeLines.isEmpty {
        lines.append("No active ports")
    } else {
        lines.append(contentsOf: activeLines)
    }

    lines.append("")
    lines.append(renderSystemLine(snapshot.systemSample))
    lines.append("")
    lines.append("Last updated: \(timeFormatter.string(from: snapshot.timestamp))")
    return lines.joined(separator: "\n")
}

private func renderPortLine(portIndex: Int, sample: PortPowerSample, estimate: CableResistanceEstimate?) -> String {
    let voltage = sample.adapterVoltage > 0 ? sample.adapterVoltage : sample.configuredVoltage
    let prefix = String(
        format: "Port %-2d %@  %@  %@",
        portIndex,
        formatVoltage(voltage),
        formatCurrent(sample.current),
        formatPower(sample.watts)
    )
    return "\(prefix)   Cable: \(formatResistance(estimate))"
}

private func renderSystemLine(_ sample: PowerSample) -> String {
    String(
        format: "System  %@ in  %@  %@ total",
        formatVoltage(sample.systemVoltageIn),
        formatCurrent(sample.systemCurrentIn),
        formatPower(sample.systemPowerIn)
    )
}

private func isActive(_ sample: PortPowerSample) -> Bool {
    sample.current > 0 || sample.watts > 0 || sample.configuredVoltage > 0 || sample.adapterVoltage > 0
}

private func formatResistance(_ estimate: CableResistanceEstimate?) -> String {
    guard let estimate else { return "estimating... (0 samples)" }
    let samples = estimate.sampleCount
    let milliohms = Int(estimate.milliohms.rounded())

    switch estimate.status {
    case .insufficient:
        return "estimating... (\(samples) samples)"
    case .converging:
        return "~\(milliohms) mOhm (\(samples) samples)"
    case .stable:
        if estimate.milliohms < 100 {
            return "~\(milliohms) mOhm (\(samples) samples) [GOOD]"
        } else if estimate.milliohms <= 300 {
            return "~\(milliohms) mOhm (\(samples) samples) [MARGINAL]"
        } else {
            return "~\(milliohms) mOhm (\(samples) samples) [HIGH]"
        }
    case .unreliable:
        return "~\(milliohms) mOhm (poor signal)"
    }
}

private func formatVoltage(_ millivolts: Int) -> String {
    String(format: "%5.2fV", Double(millivolts) / 1000)
}

private func formatCurrent(_ milliamps: Int) -> String {
    String(format: "%5dmA", milliamps)
}

private func formatPower(_ value: Int) -> String {
    String(format: "%5.1fW", Double(value) / 1000)
}

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()
#endif
