import Foundation
import WhatCableCore

/// Continuous-monitoring mode. Holds the three IOKit watchers, polls the
/// port watcher (whose property changes don't fire match notifications),
/// and re-renders when the output actually changes.
@MainActor
final class WatchRunner {
    private let portWatcher = USBCPortWatcher()
    private let powerWatcher = PowerSourceWatcher()
    private let pdWatcher = PDIdentityWatcher()

    private let asJSON: Bool
    private let showRaw: Bool
    private var lastOutput: String = ""
    private var pollTimer: DispatchSourceTimer?
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    init(asJSON: Bool, showRaw: Bool) {
        self.asJSON = asJSON
        self.showRaw = showRaw
    }

    func start() {
        // Notification-driven for power sources and PD identities.
        // USBCPortWatcher's match notifications fire only for service
        // creation, not for property changes (cable plug/unplug), so we
        // also poll its refresh() on a timer.
        portWatcher.start()
        powerWatcher.start()
        pdWatcher.start()

        renderIfChanged()

        // dispatchMain() runs a dispatch queue, not a CFRunLoop — Timer
        // wouldn't fire. DispatchSourceTimer is the dispatch-native
        // equivalent and works under dispatchMain().
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.portWatcher.refresh()
                self.renderIfChanged()
            }
        }
        timer.resume()
        pollTimer = timer

        installSignalHandler()
    }

    private func installSignalHandler() {
        // Default SIGINT prints ^C and exits; we want a clean exit so
        // watchers stop their IOKit notification ports first.
        // Also handle SIGTERM (sent by kill, launchd, etc.) for the same reason.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSrc.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.shutdown()
                exit(0)
            }
        }
        intSrc.resume()
        sigintSource = intSrc

        let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSrc.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.shutdown()
                exit(0)
            }
        }
        termSrc.resume()
        sigtermSource = termSrc
    }

    private func shutdown() {
        pollTimer?.cancel()
        pollTimer = nil
        sigintSource?.cancel()
        sigintSource = nil
        sigtermSource?.cancel()
        sigtermSource = nil
        portWatcher.stop()
        powerWatcher.stop()
        pdWatcher.stop()
    }

    private func renderIfChanged() {
        let output: String
        if asJSON {
            do {
                output = try JSONFormatter.render(
                    ports: portWatcher.ports,
                    sources: powerWatcher.sources,
                    identities: pdWatcher.identities,
                    showRaw: showRaw
                )
            } catch {
                FileHandle.standardError.write(Data("whatcable: json encoding failed: \(error)\n".utf8))
                return
            }
        } else {
            output = TextFormatter.render(
                ports: portWatcher.ports,
                sources: powerWatcher.sources,
                identities: pdWatcher.identities,
                showRaw: showRaw
            )
        }

        guard output != lastOutput else { return }
        lastOutput = output

        if asJSON {
            // Newline-delimited JSON: one self-contained object per change.
            print(output)
        } else {
            // Clear screen + home cursor, then redraw.
            print("\u{1B}[2J\u{1B}[H", terminator: "")
            print(timestampHeader())
            print(output, terminator: "")
        }
        // dispatchMain doesn't autoflush stdout when it's a pipe.
        fflush(stdout)
    }

    private func timestampHeader() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "whatcable --watch · \(formatter.string(from: Date()))\n\n"
    }
}
