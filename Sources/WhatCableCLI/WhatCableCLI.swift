import Foundation
import WhatCableCore
import WhatCableDarwinBackend

@main
struct WhatCableCLI {
    @MainActor
    static func main() {
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

        let showRaw = args.contains("--raw")
        let asJSON = args.contains("--json")
        let watch = args.contains("--watch")
        let report = args.contains("--report")

        // Reject unknown flags so typos don't silently produce default output.
        let knownFlags: Set<String> = ["--raw", "--json", "--watch", "--report", "-h", "--help", "--version"]
        for arg in args where arg.hasPrefix("-") && !knownFlags.contains(arg) {
            FileHandle.standardError.write(Data("whatcable: unknown option \(arg)\n".utf8))
            FileHandle.standardError.write(Data(helpText.utf8))
            exit(2)
        }

        if watch {
            let runner = WatchRunner(asJSON: asJSON, showRaw: showRaw)
            runner.start()
            dispatchMain()
        }

        let portWatcher = USBCPortWatcher()
        let powerWatcher = PowerSourceWatcher()
        let pdWatcher = PDIdentityWatcher()

        portWatcher.refresh()
        powerWatcher.refresh()
        pdWatcher.refresh()

        if report {
            printCableReports(identities: pdWatcher.identities)
            return
        }

        let adapter = SystemPower.currentAdapter()

        if asJSON {
            do {
                let json = try JSONFormatter.render(
                    ports: portWatcher.ports,
                    sources: powerWatcher.sources,
                    identities: pdWatcher.identities,
                    showRaw: showRaw,
                    adapter: adapter
                )
                print(json)
            } catch {
                FileHandle.standardError.write(Data("whatcable: json encoding failed: \(error)\n".utf8))
                exit(1)
            }
        } else {
            let output = TextFormatter.render(
                ports: portWatcher.ports,
                sources: powerWatcher.sources,
                identities: pdWatcher.identities,
                showRaw: showRaw,
                adapter: adapter
            )
            print(output, terminator: "")
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
      --version      Print version and exit
      -h, --help     Show this help and exit

    """
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
