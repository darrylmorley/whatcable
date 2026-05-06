import Foundation
import WhatCableCore
import WhatCableDarwinBackend

@main
struct WhatCableCLI {
    static func main() async {
        // Hand-rolled flag parsing. We only have a handful of flags; pulling
        // in swift-argument-parser would be heavier than the rest of the CLI.
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("-h") || args.contains("--help") {
            print(helpText)
            return
        }
        if args.contains("--version") {
            print(AppInfo.version)
            return
        }

        if args.contains("--tb-debug") {
            print(ThunderboltProbe.dump(), terminator: "")
            return
        }

        let showRaw = args.contains("--raw")
        let asJSON = args.contains("--json")
        let watch = args.contains("--watch")
        let report = args.contains("--report")

        // Reject unknown flags so typos don't silently produce default output.
        let knownFlags: Set<String> = ["--raw", "--json", "--watch", "--report", "--tb-debug", "-h", "--help", "--version"]
        for arg in args where arg.hasPrefix("-") && !knownFlags.contains(arg) {
            FileHandle.standardError.write(Data("whatcable: unknown option \(arg)\n".utf8))
            FileHandle.standardError.write(Data(helpText.utf8))
            exit(2)
        }

        let provider = makeDefaultSnapshotProvider()

        if watch {
            await runWatch(provider: provider, asJSON: asJSON, showRaw: showRaw)
            return
        }

        do {
            let snapshot = try await provider.snapshot()

            if report {
                printCableReports(identities: snapshot.identities)
                return
            }

            try printSnapshot(snapshot, asJSON: asJSON, showRaw: showRaw)
        } catch {
            FileHandle.standardError.write(Data("whatcable: \(error)\n".utf8))
            exit(1)
        }
    }

    static let helpText = """
    whatcable \(AppInfo.version) — \(AppInfo.tagline)

    Usage: whatcable [options]

    Options:
      --watch        Continuously monitor for changes (Ctrl+C to exit)
      --json         Output as JSON instead of human-readable text
      --raw          Include raw IOKit properties for each port
      --report       Print a cable report (markdown + GitHub URL) and exit
      --tb-debug     Dump the IOThunderboltSwitch tree (for contributors helping
                     us design the Thunderbolt fabric feature). See issue tracker.
      --version      Print version and exit
      -h, --help     Show this help and exit

    """
}

private func printSnapshot(_ snapshot: CableSnapshot, asJSON: Bool, showRaw: Bool) throws {
    if asJSON {
        let json = try JSONFormatter.render(
            ports: snapshot.ports,
            sources: snapshot.powerSources,
            identities: snapshot.identities,
            showRaw: showRaw,
            adapter: snapshot.adapter
        )
        print(json)
    } else {
        let output = TextFormatter.render(
            ports: snapshot.ports,
            sources: snapshot.powerSources,
            identities: snapshot.identities,
            showRaw: showRaw,
            adapter: snapshot.adapter
        )
        print(output, terminator: "")
    }
}

private func runWatch(provider: any CableSnapshotProvider, asJSON: Bool, showRaw: Bool) async {
    let watchTask = Task {
        await consumeWatchStream(provider: provider, asJSON: asJSON, showRaw: showRaw)
    }

    // Default SIGINT / SIGTERM kill the process abruptly. Take them over so
    // the watch task can cancel cleanly, the provider's onTermination tears
    // down its internal task, and stdout flushes before exit.
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    intSrc.setEventHandler { watchTask.cancel() }
    intSrc.resume()

    let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termSrc.setEventHandler { watchTask.cancel() }
    termSrc.resume()

    await watchTask.value

    intSrc.cancel()
    termSrc.cancel()
    fflush(stdout)
}

private func consumeWatchStream(provider: any CableSnapshotProvider, asJSON: Bool, showRaw: Bool) async {
    var lastOutput = ""
    do {
        for try await snapshot in provider.watch() {
            if Task.isCancelled { return }

            let output: String
            if asJSON {
                do {
                    output = try JSONFormatter.render(
                        ports: snapshot.ports,
                        sources: snapshot.powerSources,
                        identities: snapshot.identities,
                        showRaw: showRaw,
                        adapter: snapshot.adapter
                    )
                } catch {
                    FileHandle.standardError.write(Data("whatcable: json encoding failed: \(error)\n".utf8))
                    continue
                }
            } else {
                output = TextFormatter.render(
                    ports: snapshot.ports,
                    sources: snapshot.powerSources,
                    identities: snapshot.identities,
                    showRaw: showRaw,
                    adapter: snapshot.adapter
                )
            }

            guard output != lastOutput else { continue }
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
            fflush(stdout)
        }
    } catch is CancellationError {
        return
    } catch {
        FileHandle.standardError.write(Data("whatcable: \(error)\n".utf8))
        exit(1)
    }
}

private func timestampHeader() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return "whatcable --watch · \(formatter.string(from: Date()))\n\n"
}

private func printCableReports(identities: [PDIdentity]) {
    let cables = identities.filter {
        $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
    }
    if cables.isEmpty {
        print("No cable e-markers detected. Plug in an e-marked USB-C cable and try again.")
        print("(Most cables under 60W don't carry an e-marker, so there's nothing to report on those.)")
        return
    }
    for (i, identity) in cables.enumerated() {
        if cables.count > 1 {
            print("=== Cable \(i + 1) of \(cables.count) ===")
            print("")
        }
        guard let payload = CableReport.payload(
            for: identity,
            includeSystemInfo: true
        ) else { continue }
        print(payload.markdown)
        print("")
        print("Open in GitHub to file a report:")
        print(payload.githubURL.absoluteString)
        print("")
    }
}
